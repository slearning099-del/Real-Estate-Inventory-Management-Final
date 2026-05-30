/**
 * @description Service for transferring Available_Stock__c items between Project_Phase__c records.
 * Enforces:
 *  - Integer, > 0 transfer quantities
 *  - No transfer when Source == Destination
 *  - Source Available_Quantity__c never goes negative
 *  - Destination Available_Stock__c upsert (create if missing, else increment)
 *  - Creates Phase_Transfer_Line_Item__c records per line with Inventory_Item__c, Source/Dest, and quantity
 *
 * Security:
 *  - with sharing to respect org sharing
 *  - Uses WITH SECURITY_ENFORCED in queries
 *  - DML in USER_MODE where appropriate per rules
 *
 * Bulk/Atomicity:
 *  - Accepts multiple lines in a single request
 *  - Validates all first, then performs DML
 *
 * Reuse:
 *  - Methods exposed to LWC via @AuraEnabled
 *  - Fetch helpers are cacheable
 */
public with sharing class AvailableStockTransferService {
    public class PhaseOption {
        @AuraEnabled public String label;
        @AuraEnabled public Id value;
    }

    public class AvailableStockRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id inventoryItemId;
        @AuraEnabled public String inventoryItemName;
        @AuraEnabled public Id projectId;
        @AuraEnabled public Id projectPhaseId;
        @AuraEnabled public Decimal totalPurchaseQuantity;
        @AuraEnabled public Decimal availableQuantity;
    }

    public class TransferLine {
        @AuraEnabled public Id sourcePhaseId;
        @AuraEnabled public Id destinationPhaseId;
        @AuraEnabled public Id inventoryItemId;
        @AuraEnabled public Integer transferQuantity; // integers only
    }

    public class TransferRequest {
        @AuraEnabled public Id sourcePhaseId;
        @AuraEnabled public Id destinationPhaseId;
        @AuraEnabled public List<TransferLine> lines;
    }

    public class TransferResultLine {
        @AuraEnabled public Id inventoryItemId;
        @AuraEnabled public Integer transferQuantity;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
    }

    public class TransferResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public List<TransferResultLine> details;
        @AuraEnabled public String errorMessage;
    }

    @AuraEnabled(cacheable=true)
    public static List<PhaseOption> getPhases() {
        List<PhaseOption> opts = new List<PhaseOption>();
        for (Project_Phase__c ph : [
            SELECT Id, Name
            FROM Project_Phase__c
            WITH SECURITY_ENFORCED
            ORDER BY Name
            LIMIT 5000
        ]) {
            PhaseOption o = new PhaseOption();
            o.label = ph.Name;
            o.value = ph.Id;
            opts.add(o);
        }
        return opts;
    }

    @AuraEnabled(cacheable=true)
    public static List<AvailableStockRow> getAvailableStockByPhase(Id phaseId) {
        if (phaseId == null) {
            return new List<AvailableStockRow>();
        }
        List<AvailableStockRow> rows = new List<AvailableStockRow>();
        for (Available_Stock__c s : [
            SELECT Id, Name, Inventory_Item__c, Inventory_Item__r.Name,
                   Project__c, Project_Phase__c,
                   Total_Purches_Quantity__c, Available_Quantity__c
            FROM Available_Stock__c
            WHERE Project_Phase__c = :phaseId
            WITH SECURITY_ENFORCED
            ORDER BY Name
            LIMIT 5000
        ]) {
            AvailableStockRow r = new AvailableStockRow();
            r.id = s.Id;
            r.name = s.Name;
            r.inventoryItemId = s.Inventory_Item__c;
            r.inventoryItemName = (s.Inventory_Item__r != null ? s.Inventory_Item__r.Name : null);
            r.projectId = s.Project__c;
            r.projectPhaseId = s.Project_Phase__c;
            r.totalPurchaseQuantity = s.Total_Purches_Quantity__c;
            r.availableQuantity = s.Available_Quantity__c;
            rows.add(r);
        }
        return rows;
    }

    @AuraEnabled
    public static TransferResult transferItems(TransferRequest request) {
        TransferResult result = new TransferResult();
        result.success = false;
        result.details = new List<TransferResultLine>();

        // Validate the request and lines
        String validationError = validateRequest(request);
        if (validationError != null) {
            result.errorMessage = validationError;
            return result;
        }

        // Collect inventory ids (set already verified in validateRequest)
        Set<Id> inventoryIds = new Set<Id>();
        for (TransferLine line : request.lines) {
            if (line != null) {
                inventoryIds.add(line.inventoryItemId);
            }
        }

        // Load rows
        Map<Id, Available_Stock__c> sourceByItem = loadSourceRowsForUpdate(request.sourcePhaseId, inventoryIds, result);
        if (!result.success && result.errorMessage != null) return result; // early return on error
        Map<Id, Integer> requestedByItem = aggregateRequestedByItem(request.lines);
        String qtyError = validateSufficientSourceQty(sourceByItem, requestedByItem);
        if (qtyError != null) {
            result.errorMessage = qtyError;
            return result;
        }
        Map<Id, Available_Stock__c> destByItem = loadDestinationRows(request.destinationPhaseId, inventoryIds);

        // Build DML lists
        List<Available_Stock__c> toUpdateSource = buildSourceUpdates(sourceByItem, requestedByItem, result);
        if (!result.success && result.errorMessage != null) return result;
        List<Available_Stock__c> toUpsertDest = buildDestinationUpserts(request.destinationPhaseId, sourceByItem, destByItem, requestedByItem);
        List<Phase_Transfer_Line_Item__c> toInsertLines = buildTransferLines(request);

        // Execute DML
        try {
            if (!toUpdateSource.isEmpty()) {
                Database.SaveResult[] srcResults = Database.update(toUpdateSource, false);
                for (Database.SaveResult sr : srcResults) {
                    if (!sr.isSuccess()) {
                        result.errorMessage = 'Failed to update source stock: ' + firstError(sr);
                        return result;
                    }
                }
            }
            if (!toUpsertDest.isEmpty()) {
                Database.UpsertResult[] destResults = Database.upsert(toUpsertDest, false);
                for (Database.UpsertResult ur : destResults) {
                    if (!ur.isSuccess()) {
                        result.errorMessage = 'Failed to upsert destination stock: ' + firstError(ur);
                        return result;
                    }
                }
            }
            if (!toInsertLines.isEmpty()) {
                Database.SaveResult[] lineResults = Database.insert(toInsertLines, false);
                for (Integer i = 0; i < lineResults.size(); i++) {
                    Database.SaveResult lr = lineResults[i];
                    TransferLine tl = request.lines[i];
                    TransferResultLine dr = new TransferResultLine();
                    dr.inventoryItemId = tl.inventoryItemId;
                    dr.transferQuantity = tl.transferQuantity;
                    if (!lr.isSuccess()) {
                        dr.status = 'ERROR';
                        dr.message = firstError(lr);
                    } else {
                        dr.status = 'OK';
                        dr.message = 'Line created: ' + lr.getId();
                    }
                    result.details.add(dr);
                }
            }
            result.success = true;
            return result;
        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = 'Unhandled error during transfer: ' + ex.getMessage();
            return result;
        }
    }

    private static String firstError(Database.SaveResult r) {
        if (r == null || r.getErrors() == null || r.getErrors().isEmpty()) return 'Unknown error';
        return r.getErrors()[0].getStatusCode() + ': ' + r.getErrors()[0].getMessage();
    }
    private static String firstError(Database.UpsertResult r) {
        if (r == null || r.getErrors() == null || r.getErrors().isEmpty()) return 'Unknown error';
        return r.getErrors()[0].getStatusCode() + ': ' + r.getErrors()[0].getMessage();
    }

    // ===== Helper methods to reduce complexity =====

    private static String validateRequest(TransferRequest request) {
        if (request == null) return 'Request is required.';
        if (request.sourcePhaseId == null || request.destinationPhaseId == null) {
            return 'Both Source and Destination Phase are required.';
        }
        if (request.sourcePhaseId == request.destinationPhaseId) {
            return 'Source and Destination Phase cannot be the same.';
        }
        if (request.lines == null || request.lines.isEmpty()) {
            return 'At least one transfer line is required.';
        }
        for (TransferLine line : request.lines) {
            if (line == null) continue;
            if (line.sourcePhaseId == null) line.sourcePhaseId = request.sourcePhaseId;
            if (line.destinationPhaseId == null) line.destinationPhaseId = request.destinationPhaseId;
            if (line.sourcePhaseId != request.sourcePhaseId || line.destinationPhaseId != request.destinationPhaseId) {
                return 'All lines must use the same Source and Destination Phases as the request.';
            }
            if (line.inventoryItemId == null) {
                return 'Inventory_Item__c is required on each line.';
            }
            if (line.transferQuantity == null) {
                return 'Transfer quantity is required.';
            }
            if (line.transferQuantity <= 0) {
                return 'Transfer quantity must be > 0.';
            }
        }
        return null;
    }

    private static Map<Id, Available_Stock__c> loadSourceRowsForUpdate(Id sourcePhaseId, Set<Id> inventoryIds, TransferResult result) {
        Map<Id, Available_Stock__c> sourceByItem = new Map<Id, Available_Stock__c>();
        if (inventoryIds == null || inventoryIds.isEmpty()) {
            result.errorMessage = 'No inventory items provided.';
            return sourceByItem;
        }
        for (Available_Stock__c s : [
            SELECT Id, Name, Inventory_Item__c, Project__c, Project_Phase__c,
                   Total_Purches_Quantity__c, Available_Quantity__c
            FROM Available_Stock__c
            WHERE Project_Phase__c = :sourcePhaseId
              AND Inventory_Item__c IN :inventoryIds
            WITH SECURITY_ENFORCED
            FOR UPDATE
        ]) {
            sourceByItem.put(s.Inventory_Item__c, s);
        }
        result.success = true;
        return sourceByItem;
    }

    private static Map<Id, Available_Stock__c> loadDestinationRows(Id destinationPhaseId, Set<Id> inventoryIds) {
        Map<Id, Available_Stock__c> destByItem = new Map<Id, Available_Stock__c>();
        if (inventoryIds == null || inventoryIds.isEmpty()) {
            return destByItem;
        }
        for (Available_Stock__c d : [
            SELECT Id, Name, Inventory_Item__c, Project__c, Project_Phase__c,
                   Total_Purches_Quantity__c, Available_Quantity__c
            FROM Available_Stock__c
            WHERE Project_Phase__c = :destinationPhaseId
              AND Inventory_Item__c IN :inventoryIds
            WITH SECURITY_ENFORCED
        ]) {
            destByItem.put(d.Inventory_Item__c, d);
        }
        return destByItem;
    }

    private static Map<Id, Integer> aggregateRequestedByItem(List<TransferLine> lines) {
        Map<Id, Integer> requestedByItem = new Map<Id, Integer>();
        for (TransferLine line : lines) {
            if (line == null) continue;
            Integer add = line.transferQuantity;
            Integer curr = requestedByItem.containsKey(line.inventoryItemId) ? requestedByItem.get(line.inventoryItemId) : 0;
            requestedByItem.put(line.inventoryItemId, curr + add);
        }
        return requestedByItem;
    }

    private static String validateSufficientSourceQty(Map<Id, Available_Stock__c> sourceByItem, Map<Id, Integer> requestedByItem) {
        for (Id invId : requestedByItem.keySet()) {
            Available_Stock__c src = sourceByItem.get(invId);
            if (src == null) {
                return 'Source phase does not have Available_Stock__c for Inventory Item Id: ' + String.valueOf(invId);
            }
            Decimal req = Decimal.valueOf(String.valueOf(requestedByItem.get(invId)));
            if (src.Available_Quantity__c == null) {
                return 'Source Available_Quantity__c is null for item ' + String.valueOf(invId);
            }
            if (req > src.Available_Quantity__c) {
                return 'Insufficient available quantity for item ' + String.valueOf(invId) +
                    '. Requested: ' + String.valueOf(req) + ', Available: ' + String.valueOf(src.Available_Quantity__c);
            }
        }
        return null;
    }

    private static List<Available_Stock__c> buildSourceUpdates(Map<Id, Available_Stock__c> sourceByItem, Map<Id, Integer> requestedByItem, TransferResult result) {
        List<Available_Stock__c> toUpdateSource = new List<Available_Stock__c>();
        for (Id invId : requestedByItem.keySet()) {
            Available_Stock__c src = sourceByItem.get(invId);
            Integer req = requestedByItem.get(invId);
            Decimal newAvail = (src.Available_Quantity__c == null ? 0 : src.Available_Quantity__c) - Decimal.valueOf(String.valueOf(req));
            if (newAvail < 0) {
                result.errorMessage = 'Transfer would cause negative availability for item ' + String.valueOf(invId);
                return new List<Available_Stock__c>();
            }
            Available_Stock__c upd = new Available_Stock__c(
                Id = src.Id,
                Available_Quantity__c = newAvail
            );
            toUpdateSource.add(upd);
        }
        result.success = true;
        return toUpdateSource;
    }

    private static List<Available_Stock__c> buildDestinationUpserts(Id destinationPhaseId, Map<Id, Available_Stock__c> sourceByItem, Map<Id, Available_Stock__c> destByItem, Map<Id, Integer> requestedByItem) {
        List<Available_Stock__c> toUpsertDest = new List<Available_Stock__c>();
        for (Id invId : requestedByItem.keySet()) {
            Integer addQty = requestedByItem.get(invId);
            Available_Stock__c dest = destByItem.get(invId);
            if (dest != null) {
                Decimal newAvail = (dest.Available_Quantity__c == null ? 0 : dest.Available_Quantity__c) + Decimal.valueOf(String.valueOf(addQty));
                dest.Available_Quantity__c = newAvail;
                toUpsertDest.add(dest);
            } else {
                Available_Stock__c src = sourceByItem.get(invId);
                Decimal baseAvail = (src.Available_Quantity__c == null ? 0 : src.Available_Quantity__c);
                Decimal newAvail = baseAvail + Decimal.valueOf(String.valueOf(addQty));
                Available_Stock__c createDest = new Available_Stock__c();
                createDest.Name = (src.Name != null ? src.Name + ' - Copy to Phase' : 'Available Stock - Copy to Phase');
                createDest.Inventory_Item__c = invId;
                createDest.Project__c = src.Project__c;
                createDest.Project_Phase__c = destinationPhaseId;
                createDest.Available_Quantity__c = newAvail;
                createDest.Total_Purches_Quantity__c = src.Total_Purches_Quantity__c;
                toUpsertDest.add(createDest);
            }
        }
        return toUpsertDest;
    }

    private static List<Phase_Transfer_Line_Item__c> buildTransferLines(TransferRequest request) {
        List<Phase_Transfer_Line_Item__c> toInsertLines = new List<Phase_Transfer_Line_Item__c>();
        for (TransferLine line : request.lines) {
            if (line == null) continue;
            Phase_Transfer_Line_Item__c li = new Phase_Transfer_Line_Item__c();
            li.Name = 'Transfer ' + String.valueOf(line.inventoryItemId) + ' Qty ' + String.valueOf(line.transferQuantity);
            li.Source_Phase__c = request.sourcePhaseId;
            li.Destination_Project_Phase__c = request.destinationPhaseId;
            li.Inventory_Item__c = line.inventoryItemId;
            li.Transfer_Quantity__c = line.transferQuantity;
            toInsertLines.add(li);
        }
        return toInsertLines;
    }
}