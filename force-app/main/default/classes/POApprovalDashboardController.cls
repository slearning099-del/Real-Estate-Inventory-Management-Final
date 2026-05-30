/**
 * POApprovalDashboardController
 *
 * Handles all backend logic for the PO Approval Dashboard LWC.
 *
 * Flow:
 *   1. User clicks "Submit for Approval" on PO record page
 *   2. Apex submits PO to approval process (status → Pending Approval)
 *   3. Apex sends a Salesforce Bell Notification to the approver
 *      with the direct PO record link
 *   4. Approver clicks the bell → PO record page opens
 *   5. Dashboard component auto-loads via @api recordId
 *   6. Approver clicks Approve/Reject inside the dashboard
 *   7. On Approve → Available_Stock__c records are created
 *
 * Bell notification uses CustomNotificationType: PO_Approval_Notification
 */
public with sharing class POApprovalDashboardController {

    private static final String WORK_ITEM_PREFIX    = '04i';
    private static final String NOTIF_TYPE_DEV_NAME = 'PO_Approval_Notification';

    // ─────────────────────────────────────────────────────────────
    // Wrapper classes
    // ─────────────────────────────────────────────────────────────

    public class PODashboardData {
        @AuraEnabled public POHeader         poHeader;
        @AuraEnabled public List<POLineItem> lineItems;
        @AuraEnabled public List<ChartEntry> categoryChart;
        @AuraEnabled public List<ChartEntry> statusChart;
        @AuraEnabled public List<ChartEntry> quantityChart;
        @AuraEnabled public ApprovalSummary  approvalSummary;
        @AuraEnabled public String           workItemId;
        @AuraEnabled public Boolean          canActOnApproval;
        @AuraEnabled public Boolean          canSubmitForApproval;
    }

    public class POHeader {
        @AuraEnabled public String  poId;
        @AuraEnabled public String  poNumber;
        @AuraEnabled public String  poCode;
        @AuraEnabled public String  vendorName;
        @AuraEnabled public String  requestedBy;
        @AuraEnabled public String  requestedDate;
        @AuraEnabled public String  poDate;
        @AuraEnabled public String  status;
        @AuraEnabled public String  projectPhase;
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Decimal totalQuantity;
        @AuraEnabled public Decimal totalCost;
    }

    public class POLineItem {
        @AuraEnabled public String  id;
        @AuraEnabled public String  lineItemCode;
        @AuraEnabled public String  itemName;
        @AuraEnabled public String  itemCode;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String  unit;
        @AuraEnabled public Decimal unitCost;
        @AuraEnabled public Decimal totalCost;
        @AuraEnabled public String  projectPhase;
        @AuraEnabled public String  statusBadge;
    }

    public class ChartEntry {
        @AuraEnabled public String  label;
        @AuraEnabled public Decimal value;
        @AuraEnabled public String  color;
        public ChartEntry(String lbl, Decimal val, String clr) {
            label = lbl; value = val; color = clr;
        }
    }

    public class ApprovalSummary {
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Decimal totalQuantity;
        @AuraEnabled public Decimal totalCost;
        @AuraEnabled public String  approvalStatus;
        @AuraEnabled public String  submittedBy;
        @AuraEnabled public String  submittedDate;
        @AuraEnabled public String  approverName;
        @AuraEnabled public List<ApprovalHistoryEntry> history;
    }

    public class ApprovalHistoryEntry {
        @AuraEnabled public String stepName;
        @AuraEnabled public String actorName;
        @AuraEnabled public String action;
        @AuraEnabled public String comments;
        @AuraEnabled public String createdDate;
    }

    public class ActionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  message;
        @AuraEnabled public String  workItemId;
    }

    public class PendingApprovalItem {
        @AuraEnabled public String  workItemId;
        @AuraEnabled public String  poId;
        @AuraEnabled public String  poNumber;
        @AuraEnabled public String  poCode;
        @AuraEnabled public String  vendorName;
        @AuraEnabled public String  submittedBy;
        @AuraEnabled public String  submittedDate;
        @AuraEnabled public Integer totalLineItems;
    }


    // ─────────────────────────────────────────────────────────────
    // SUBMIT FOR APPROVAL + BELL NOTIFICATION
    // ─────────────────────────────────────────────────────────────

    @AuraEnabled
    public static ActionResult submitForApproval(Id poRecordId, String comments) {
        ActionResult res = new ActionResult();
        try {
            Purchase_Order__c po = [
                SELECT Id, Name, Status__c, Purchase_Order_Code__c,
                       Vendor__r.Name, CreatedBy.Name
                FROM   Purchase_Order__c
                WHERE  Id = :poRecordId
                LIMIT  1
            ];

            if (po.Status__c != 'Draft') {
                res.success = false;
                res.message = 'Only Draft Purchase Orders can be submitted. Current status: ' + po.Status__c;
                return res;
            }

            // Submit to Salesforce Approval Process
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(poRecordId);
            req.setSubmitterId(UserInfo.getUserId());
            req.setProcessDefinitionNameOrId('Purchase_Order_Approval');
            if (String.isNotBlank(comments)) {
                req.setComments(comments);
            }
            Approval.ProcessResult result = Approval.process(req);

            if (result.isSuccess()) {
                // Find the work item just created to get the approver Id
                List<ProcessInstanceWorkitem> workItems = [
                    SELECT Id, ActorId, Actor.Name
                    FROM   ProcessInstanceWorkitem
                    WHERE  ProcessInstance.TargetObjectId = :poRecordId
                    AND    ProcessInstance.Status         = 'Pending'
                    ORDER BY CreatedDate DESC
                    LIMIT  1
                ];

                if (!workItems.isEmpty()) {
                    res.workItemId = workItems[0].Id;
                    // Send bell notification to the approver
                    sendBellNotification(
                        poRecordId,
                        po.Name,
                        po.Purchase_Order_Code__c,
                        po.Vendor__r != null ? po.Vendor__r.Name : '',
                        workItems[0].ActorId
                    );
                }

                res.success = true;
                res.message = 'Purchase Order "' + po.Name + '" submitted for approval. ' +
                              'The approver has been notified.';
            } else {
                res.success = false;
                res.message = (result.getErrors() != null && !result.getErrors().isEmpty())
                              ? result.getErrors()[0].getMessage() : 'Submission failed.';
            }
        } catch (Exception e) {
            res.success = false;
            res.message = e.getMessage();
        }
        return res;
    }


    // ─────────────────────────────────────────────────────────────
    // BELL NOTIFICATION (private helper)
    // Sends a Salesforce bell notification to the approver.
    // The notification body contains the PO details and the
    // direct record link so the approver can click straight
    // to the PO page where the dashboard auto-loads.
    // ─────────────────────────────────────────────────────────────

    private static void sendBellNotification(
        Id     poRecordId,
        String poNumber,
        String poCode,
        String vendorName,
        Id     approverId
    ) {
        try {
            // Look up the Custom Notification Type
            List<CustomNotificationType> notifTypes = [
                SELECT Id
                FROM   CustomNotificationType
                WHERE  DeveloperName = :NOTIF_TYPE_DEV_NAME
                LIMIT  1
            ];

            if (notifTypes.isEmpty()) {
                System.debug('[POApprovalDashboard] CustomNotificationType "' +
                             NOTIF_TYPE_DEV_NAME + '" not found. Skipping bell notification.');
                return;
            }

            String title = 'Pending Approval: ' + poNumber;
            String body  = 'Purchase Order ' + poNumber +
                           (String.isNotBlank(poCode)    ? ' (' + poCode + ')'       : '') +
                           (String.isNotBlank(vendorName) ? ' — Vendor: ' + vendorName : '') +
                           ' is awaiting your approval. Click to review the Inventory Dashboard.';

            Messaging.CustomNotification notif = new Messaging.CustomNotification();
            notif.setNotificationTypeId(notifTypes[0].Id);
            notif.setTargetId(poRecordId);   // clicking opens the PO record page
            notif.setTitle(title);
            notif.setBody(body);

            Set<String> recipientIds = new Set<String>{ approverId };
            notif.send(recipientIds);

        } catch (Exception e) {
            // Non-fatal — log and continue
            System.debug('[POApprovalDashboard] Bell notification error: ' + e.getMessage());
        }
    }


    // ─────────────────────────────────────────────────────────────
    // UNIFIED ENTRY POINT
    // Accepts either a Purchase_Order__c Id or a
    // ProcessInstanceWorkitem Id (prefix 04i).
    // ─────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static PODashboardData getDashboardDataByRecordId(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record Id is required.');
        }

        Id     poRecordId        = null;
        String resolvedWorkItemId = null;

        if (recordId.startsWith(WORK_ITEM_PREFIX)) {
            List<ProcessInstanceWorkitem> wis = [
                SELECT Id, ProcessInstance.TargetObjectId
                FROM   ProcessInstanceWorkitem
                WHERE  Id = :recordId
                LIMIT  1
            ];
            if (wis.isEmpty()) {
                List<ProcessInstanceWorkitem> fallback = [
                    SELECT Id, ProcessInstance.TargetObjectId
                    FROM   ProcessInstanceWorkitem
                    WHERE  ActorId = :UserInfo.getUserId()
                    AND    ProcessInstance.Status = 'Pending'
                    ORDER BY CreatedDate DESC
                    LIMIT  1
                ];
                if (fallback.isEmpty()) {
                    throw new AuraHandledException('No pending approval work item found.');
                }
                poRecordId         = fallback[0].ProcessInstance.TargetObjectId;
                resolvedWorkItemId = fallback[0].Id;
            } else {
                poRecordId         = wis[0].ProcessInstance.TargetObjectId;
                resolvedWorkItemId = wis[0].Id;
            }
        } else {
            poRecordId = (Id) recordId;
        }

        PODashboardData data = buildDashboard(poRecordId);

        if (resolvedWorkItemId != null) {
            data.workItemId       = resolvedWorkItemId;
            data.canActOnApproval = true;
        }
        return data;
    }

    @AuraEnabled(cacheable=false)
    public static PODashboardData getDashboardData(Id poRecordId) {
        if (poRecordId == null) {
            throw new AuraHandledException('Purchase Order Id is required.');
        }
        return buildDashboard(poRecordId);
    }


    // ─────────────────────────────────────────────────────────────
    // GET PENDING APPROVALS
    // Returns all POs currently pending the current user's approval.
    // ─────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<PendingApprovalItem> getPendingApprovals() {
        List<PendingApprovalItem> result = new List<PendingApprovalItem>();
        try {
            List<ProcessInstanceWorkitem> workItems = [
                SELECT Id,
                       ProcessInstance.TargetObjectId,
                       ProcessInstance.SubmittedBy.Name,
                       ProcessInstance.CreatedDate
                FROM   ProcessInstanceWorkitem
                WHERE  ActorId                  = :UserInfo.getUserId()
                AND    ProcessInstance.Status   = 'Pending'
                ORDER BY CreatedDate DESC
            ];

            if (workItems.isEmpty()) return result;

            Set<Id> poIds = new Set<Id>();
            for (ProcessInstanceWorkitem wi : workItems) {
                poIds.add(wi.ProcessInstance.TargetObjectId);
            }

            Map<Id, Purchase_Order__c> poMap = new Map<Id, Purchase_Order__c>([
                SELECT Id, Name, Purchase_Order_Code__c, Vendor__r.Name
                FROM   Purchase_Order__c
                WHERE  Id IN :poIds
            ]);

            Map<Id, Integer> lineItemCountMap = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Purchase_Order__c poId, COUNT(Id) cnt
                FROM   Purchase_Order_Line_Item__c
                WHERE  Purchase_Order__c IN :poIds
                GROUP BY Purchase_Order__c
            ]) {
                lineItemCountMap.put((Id) ar.get('poId'), (Integer) ar.get('cnt'));
            }

            for (ProcessInstanceWorkitem wi : workItems) {
                Id poId = wi.ProcessInstance.TargetObjectId;
                Purchase_Order__c po = poMap.get(poId);
                if (po == null) continue;

                PendingApprovalItem item = new PendingApprovalItem();
                item.workItemId    = wi.Id;
                item.poId          = poId;
                item.poNumber      = po.Name;
                item.poCode        = po.Purchase_Order_Code__c;
                item.vendorName    = po.Vendor__r != null ? po.Vendor__r.Name : '—';
                item.submittedBy   = wi.ProcessInstance.SubmittedBy != null
                                     ? wi.ProcessInstance.SubmittedBy.Name : '—';
                item.submittedDate = wi.ProcessInstance.CreatedDate != null
                                     ? wi.ProcessInstance.CreatedDate.format('MMM dd, yyyy') : '—';
                item.totalLineItems = lineItemCountMap.containsKey(poId)
                                      ? lineItemCountMap.get(poId) : 0;
                result.add(item);
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        return result;
    }


    // ─────────────────────────────────────────────────────────────
    // GET APPROVAL HISTORY
    // ─────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<ApprovalHistoryEntry> getApprovalHistory(Id poRecordId) {
        List<ApprovalHistoryEntry> history = new List<ApprovalHistoryEntry>();
        try {
            List<ProcessInstance> instances = [
                SELECT Id,
                       (SELECT Id, StepStatus, Comments, CreatedDate,
                               Actor.Name, ProcessNode.Name
                        FROM   StepsAndWorkitems
                        ORDER BY CreatedDate ASC)
                FROM   ProcessInstance
                WHERE  TargetObjectId = :poRecordId
                ORDER BY CreatedDate DESC
                LIMIT  1
            ];
            if (!instances.isEmpty()) {
                for (ProcessInstanceHistory step : instances[0].StepsAndWorkitems) {
                    ApprovalHistoryEntry entry = new ApprovalHistoryEntry();
                    entry.stepName    = step.ProcessNode != null ? step.ProcessNode.Name : 'Approval';
                    entry.actorName   = step.Actor       != null ? step.Actor.Name       : '—';
                    entry.action      = step.StepStatus;
                    entry.comments    = step.Comments;
                    entry.createdDate = step.CreatedDate != null
                                        ? step.CreatedDate.format('MMM dd, yyyy hh:mm a') : '—';
                    history.add(entry);
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        return history;
    }


    // ─────────────────────────────────────────────────────────────
    // APPROVE
    // ─────────────────────────────────────────────────────────────

    @AuraEnabled
    public static ActionResult approveOrder(Id workItemId, String comments) {
        ActionResult res = new ActionResult();
        try {
            // Capture the PO Id BEFORE processing — work item is consumed after approval
            Id poRecordId = null;
            List<ProcessInstanceWorkitem> wis = [
                SELECT ProcessInstance.TargetObjectId
                FROM   ProcessInstanceWorkitem
                WHERE  Id = :workItemId
                LIMIT  1
            ];
            if (!wis.isEmpty()) {
                poRecordId = wis[0].ProcessInstance.TargetObjectId;
            }

            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(workItemId);
            req.setAction('Approve');
            if (String.isNotBlank(comments)) req.setComments(comments);

            Approval.ProcessResult result = Approval.process(req);

            if (result.isSuccess()) {
                if (poRecordId != null) {
                    createAvailableStockRecords(poRecordId);
                }
                res.success = true;
                res.message = 'Purchase Order approved successfully. Available Stock records created.';
            } else {
                res.success = false;
                res.message = (result.getErrors() != null && !result.getErrors().isEmpty())
                              ? result.getErrors()[0].getMessage() : 'Approval failed.';
            }
        } catch (Exception e) {
            res.success = false;
            res.message = e.getMessage();
        }
        return res;
    }


    // ─────────────────────────────────────────────────────────────
    // REJECT
    // ─────────────────────────────────────────────────────────────

    @AuraEnabled
    public static ActionResult rejectOrder(Id workItemId, String comments) {
        ActionResult res = new ActionResult();
        try {
            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(workItemId);
            req.setAction('Reject');
            if (String.isNotBlank(comments)) req.setComments(comments);

            Approval.ProcessResult result = Approval.process(req);

            if (result.isSuccess()) {
                res.success = true;
                res.message = 'Purchase Order rejected.';
            } else {
                res.success = false;
                res.message = (result.getErrors() != null && !result.getErrors().isEmpty())
                              ? result.getErrors()[0].getMessage() : 'Rejection failed.';
            }
        } catch (Exception e) {
            res.success = false;
            res.message = e.getMessage();
        }
        return res;
    }


    // ─────────────────────────────────────────────────────────────
    // CORE DASHBOARD BUILDER
    // ─────────────────────────────────────────────────────────────

    private static PODashboardData buildDashboard(Id poRecordId) {
        PODashboardData data = new PODashboardData();

        Purchase_Order__c po = [
            SELECT Id, Name, Purchase_Order_Code__c, PO_Date__c,
                   Status__c, Vendor__r.Name, Project_Phase__r.Name,
                   CreatedBy.Name, CreatedDate
            FROM   Purchase_Order__c
            WHERE  Id = :poRecordId
            LIMIT  1
        ];

        POHeader hdr      = new POHeader();
        hdr.poId          = po.Id;
        hdr.poNumber      = po.Name;
        hdr.poCode        = po.Purchase_Order_Code__c;
        hdr.vendorName    = po.Vendor__r         != null ? po.Vendor__r.Name         : '—';
        hdr.requestedBy   = po.CreatedBy         != null ? po.CreatedBy.Name         : '—';
        hdr.requestedDate = po.CreatedDate       != null
                            ? po.CreatedDate.format('MMM dd, yyyy')                  : '—';
        hdr.poDate        = po.PO_Date__c        != null ? po.PO_Date__c.format()    : '—';
        hdr.status        = po.Status__c;
        hdr.projectPhase  = po.Project_Phase__r  != null ? po.Project_Phase__r.Name  : '—';
        data.poHeader     = hdr;

        // canSubmitForApproval — only when status is Draft
        data.canSubmitForApproval = (po.Status__c == 'Draft');

        // Line items
        List<Purchase_Order_Line_Item__c> rawItems = [
            SELECT Id, Name, PO_line_item_code__c,
                   Inventory_Item__r.Name,
                   Inventory_Item__r.Item_Code__c,
                   Inventory_Item__r.Unit_Master__r.Name,
                   Inventory_Item__r.Item_Unit_Cost__c,
                   Quantity__c, Total_Item_Cost__c,
                   Project_Phase__r.Name
            FROM   Purchase_Order_Line_Item__c
            WHERE  Purchase_Order__c = :poRecordId
            ORDER BY Name ASC
        ];

        List<POLineItem>     lineItems   = new List<POLineItem>();
        Decimal              totalQty    = 0;
        Decimal              totalCost   = 0;
        Map<String, Decimal> qtyByItem   = new Map<String, Decimal>();
        Map<String, Integer> countByUnit = new Map<String, Integer>();

        for (Purchase_Order_Line_Item__c li : rawItems) {
            POLineItem item   = new POLineItem();
            item.id           = li.Id;
            item.lineItemCode = li.PO_line_item_code__c;
            item.itemName     = li.Inventory_Item__r != null ? li.Inventory_Item__r.Name : li.Name;
            item.itemCode     = (li.Inventory_Item__r != null && li.Inventory_Item__r.Item_Code__c != null)
                                ? li.Inventory_Item__r.Item_Code__c : '—';
            item.quantity     = li.Quantity__c         != null ? li.Quantity__c         : 0;
            item.unit         = (li.Inventory_Item__r  != null
                                && li.Inventory_Item__r.Unit_Master__r != null)
                                ? li.Inventory_Item__r.Unit_Master__r.Name : '—';
            item.unitCost     = (li.Inventory_Item__r  != null
                                && li.Inventory_Item__r.Item_Unit_Cost__c != null)
                                ? li.Inventory_Item__r.Item_Unit_Cost__c : 0;
            item.totalCost    = li.Total_Item_Cost__c  != null ? li.Total_Item_Cost__c  : 0;
            item.projectPhase = li.Project_Phase__r    != null ? li.Project_Phase__r.Name : '—';
            item.statusBadge  = 'Pending';
            lineItems.add(item);

            totalQty  += item.quantity;
            totalCost += item.totalCost;

            String iName = item.itemName;
            qtyByItem.put(iName,
                (qtyByItem.containsKey(iName) ? qtyByItem.get(iName) : 0) + item.quantity);
            String uName = String.isBlank(item.unit) ? 'Unknown' : item.unit;
            countByUnit.put(uName,
                (countByUnit.containsKey(uName) ? countByUnit.get(uName) : 0) + 1);
        }

        data.lineItems    = lineItems;
        hdr.totalItems    = lineItems.size();
        hdr.totalQuantity = totalQty;
        hdr.totalCost     = totalCost;

        // Charts
        String[] colors = new String[]{
            '#2C7BE5','#39B54A','#F7B924','#E63757','#6C757D',
            '#00B8D9','#FF8B00','#6554C0','#36B37E','#FF5630'
        };
        Integer ci = 0;

        List<ChartEntry> catChart = new List<ChartEntry>();
        for (String lbl : countByUnit.keySet()) {
            catChart.add(new ChartEntry(lbl,
                Decimal.valueOf(countByUnit.get(lbl)),
                colors[Math.mod(ci++, colors.size())]));
        }
        data.categoryChart = catChart;

        data.statusChart = new List<ChartEntry>{
            new ChartEntry('Pending',  Decimal.valueOf(lineItems.size()), '#F7B924'),
            new ChartEntry('Approved', 0,                                 '#39B54A'),
            new ChartEntry('Rejected', 0,                                 '#E63757')
        };

        ci = 0;
        List<ChartEntry> qtyChart = new List<ChartEntry>();
        for (String lbl : qtyByItem.keySet()) {
            qtyChart.add(new ChartEntry(lbl, qtyByItem.get(lbl),
                colors[Math.mod(ci++, colors.size())]));
        }
        data.quantityChart = qtyChart;

        // Approval summary + history
        ApprovalSummary summary = new ApprovalSummary();
        summary.totalItems      = lineItems.size();
        summary.totalQuantity   = totalQty;
        summary.totalCost       = totalCost;
        summary.approvalStatus  = po.Status__c;
        summary.history         = new List<ApprovalHistoryEntry>();

        List<ProcessInstance> instances = [
            SELECT Id, Status, SubmittedBy.Name, CreatedDate,
                   (SELECT Id, StepStatus, Comments, CreatedDate,
                           Actor.Name, ProcessNode.Name
                    FROM   StepsAndWorkitems
                    ORDER BY CreatedDate ASC)
            FROM   ProcessInstance
            WHERE  TargetObjectId = :poRecordId
            ORDER BY CreatedDate DESC
            LIMIT  1
        ];

        String workItemId = null;
        if (!instances.isEmpty()) {
            ProcessInstance pi    = instances[0];
            summary.submittedBy   = pi.SubmittedBy != null
                                    ? pi.SubmittedBy.Name : '—';
            summary.submittedDate = pi.CreatedDate != null
                                    ? pi.CreatedDate.format('MMM dd, yyyy hh:mm a') : '—';

            for (ProcessInstanceHistory step : pi.StepsAndWorkitems) {
                ApprovalHistoryEntry entry = new ApprovalHistoryEntry();
                entry.stepName    = step.ProcessNode != null ? step.ProcessNode.Name : 'Approval';
                entry.actorName   = step.Actor       != null ? step.Actor.Name       : '—';
                entry.action      = step.StepStatus;
                entry.comments    = step.Comments;
                entry.createdDate = step.CreatedDate != null
                                    ? step.CreatedDate.format('MMM dd, yyyy hh:mm a') : '—';
                summary.history.add(entry);
                if (step.StepStatus == 'Pending') {
                    summary.approverName = step.Actor != null ? step.Actor.Name : '—';
                }
            }

            List<ProcessInstanceWorkitem> wis = [
                SELECT Id
                FROM   ProcessInstanceWorkitem
                WHERE  ProcessInstanceId = :pi.Id
                AND    ActorId           = :UserInfo.getUserId()
                LIMIT  1
            ];
            if (!wis.isEmpty()) workItemId = wis[0].Id;
        }

        data.approvalSummary  = summary;
        data.workItemId       = workItemId;
        data.canActOnApproval = workItemId != null;

        return data;
    }


    // ─────────────────────────────────────────────────────────────
    // CREATE AVAILABLE STOCK RECORDS ON APPROVAL
    // ─────────────────────────────────────────────────────────────

    private static void createAvailableStockRecords(Id poId) {
        List<Purchase_Order_Line_Item__c> lineItems = [
            SELECT Id, Inventory_Item__c, Quantity__c,
                   Project_Phase__c, Purchase_Order__r.Project__c
            FROM   Purchase_Order_Line_Item__c
            WHERE  Purchase_Order__c = :poId
        ];

        Set<Id> inventoryItemIds = getInventoryItemIds(lineItems);
        Set<Id> projectPhaseIds  = getProjectPhaseIds(lineItems);

        Set<Id> existingItemIds = new Set<Id>();
        for (Available_Stock__c existing : [
            SELECT Inventory_Item__c
            FROM   Available_Stock__c
            WHERE  Inventory_Item__c IN :inventoryItemIds
            AND    Project_Phase__c  IN :projectPhaseIds
        ]) {
            existingItemIds.add(existing.Inventory_Item__c);
        }

        List<Available_Stock__c> stockToInsert = new List<Available_Stock__c>();
        for (Purchase_Order_Line_Item__c li : lineItems) {
            if (li.Inventory_Item__c == null)                   continue;
            if (existingItemIds.contains(li.Inventory_Item__c)) continue;

            Available_Stock__c stock        = new Available_Stock__c();
            stock.Inventory_Item__c         = li.Inventory_Item__c;
            stock.Available_Quantity__c     = li.Quantity__c != null ? li.Quantity__c : 0;
            stock.Total_Purches_Quantity__c = li.Quantity__c != null ? li.Quantity__c : 0;
            stock.Project_Phase__c          = li.Project_Phase__c;
            stock.Project__c                = li.Purchase_Order__r.Project__c;
            stockToInsert.add(stock);
        }

        if (!stockToInsert.isEmpty()) {
            insert stockToInsert;
        }
    }

    private static Set<Id> getInventoryItemIds(List<Purchase_Order_Line_Item__c> items) {
        Set<Id> ids = new Set<Id>();
        for (Purchase_Order_Line_Item__c li : items) {
            if (li.Inventory_Item__c != null) ids.add(li.Inventory_Item__c);
        }
        return ids;
    }

    private static Set<Id> getProjectPhaseIds(List<Purchase_Order_Line_Item__c> items) {
        Set<Id> ids = new Set<Id>();
        for (Purchase_Order_Line_Item__c li : items) {
            if (li.Project_Phase__c != null) ids.add(li.Project_Phase__c);
        }
        return ids;
    }
}
