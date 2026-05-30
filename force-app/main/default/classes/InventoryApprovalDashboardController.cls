/**
 * Inventory Approval Dashboard Controller
 * Manages inventory approvals, stock transfers, and analytics for project managers.
 */
public with sharing class InventoryApprovalDashboardController {
    private static final String LINE_ITEM_OBJECT = 'Purchase_Order_Line_Item__c';
    private static final String AVAILABLE_STOCK_OBJECT = 'Available_Item_Stock__c';
    private static final Set<String> PENDING_STATUS_VALUES = new Set<String>{'Pending','Submitted for Approval','Awaiting Approval','New','Approval Pending','Pending Approval'};
    private static final Set<String> APPROVED_STATUS_VALUES = new Set<String>{'Approved','Accepted'};
    private static final Set<String> REJECTED_STATUS_VALUES = new Set<String>{'Rejected','Declined'};

    /**
     * Retrieves inventory approval dashboard data including pending items, analytics, and summaries.
     * @param projectPhaseId The Project Phase record ID to retrieve data for.
     * @return DashboardPayload containing items, analytics, and summary information.
     */
    @AuraEnabled(cacheable=true)
    public static DashboardPayload getDashboardData(Id projectPhaseId) {
        if (projectPhaseId == null) {
            throw new AuraHandledException('Project Phase Id is required.');
        }

        Map<String, Schema.SObjectField> lineItemFields = InventoryApprovalHandler.describeObjectFields(LINE_ITEM_OBJECT);
        if (lineItemFields.isEmpty()) {
            throw new AuraHandledException('Purchase Order Line Item object is not available.');
        }

        QueryFieldConfig fieldConfig = buildQueryFieldConfig(lineItemFields);
        List<SObject> lineItems = fetchLineItemsForPhase(projectPhaseId, fieldConfig);
        
        DashboardPayload payload = new DashboardPayload();
        payload.items = buildApprovalItems(lineItems, fieldConfig);
        payload.categoryDistribution = buildCategoryAnalytics(payload.items);
        payload.statusDistribution = buildStatusAnalytics(payload.items);
        payload.quantityByItemType = buildQuantityAnalytics(payload.items);
        payload.phaseAllocation = fetchPhaseAllocation();
        
        Set<Id> lineItemIds = extractIds(payload.items);
        payload.approvalHistory = fetchApprovalHistory(lineItemIds);
        payload.summary = buildDashboardSummary(payload.items, projectPhaseId);
        payload.hasApprovalProcess = hasApprovalProcess();

        if (payload.statusDistribution.isEmpty()) {
            payload.statusDistribution.add(new AnalyticsEntry('Pending', payload.summary.pendingCount));
            payload.statusDistribution.add(new AnalyticsEntry('Approved', payload.summary.approvedCount));
            payload.statusDistribution.add(new AnalyticsEntry('Rejected', payload.summary.rejectedCount));
        }
        return payload;
    }

    /**
     * Processes approval or rejection actions on line items and creates stock records if approved.
     * @param actions List of approval actions to process.
     * @return ApprovalActionResult with success count and message.
     */
    @AuraEnabled
    public static ApprovalActionResult processApprovalActions(List<ApprovalActionRequest> actions) {
        ApprovalActionResult result = new ApprovalActionResult();
        if (actions == null || actions.isEmpty()) {
            result.message = 'No approval actions were provided.';
            return result;
        }

        Set<Id> lineItemIds = extractLineItemIds(actions);
        if (lineItemIds.isEmpty()) {
            result.message = 'No valid purchase order line items were selected.';
            return result;
        }

        Map<String, Schema.SObjectField> lineItemFields = InventoryApprovalHandler.describeObjectFields(LINE_ITEM_OBJECT);
        if (lineItemFields.isEmpty()) {
            throw new AuraHandledException('Purchase Order Line Item object is not available.');
        }

        QueryFieldConfig fieldConfig = buildQueryFieldConfig(lineItemFields);
        List<SObject> lineItems = fetchLineItemsById(lineItemIds, fieldConfig);
        
        Map<Id, ApprovalActionRequest> actionMap = new Map<Id, ApprovalActionRequest>();
        for (ApprovalActionRequest action : actions) {
            if (action != null && action.lineItemId != null) {
                actionMap.put(action.lineItemId, action);
            }
        }

        List<SObject> lineItemsToUpdate = new List<SObject>();
        List<SObject> approvedLineItems = new List<SObject>();

        for (SObject lineItem : lineItems) {
            ApprovalActionRequest action = actionMap.get((Id) lineItem.get('Id'));
            if (action == null) continue;

            String normalizedAction = action.action == null ? '' : action.action.trim();
            String nextStatus = normalizedAction.equalsIgnoreCase('Approve') ? 'Approved' : 'Rejected';
            lineItem.put(fieldConfig.statusField, nextStatus);
            
            if (!String.isBlank(action.comment) && !String.isBlank(fieldConfig.commentField)) {
                lineItem.put(fieldConfig.commentField, action.comment);
            }
            lineItemsToUpdate.add(lineItem);
            if (normalizedAction.equalsIgnoreCase('Approve')) {
                approvedLineItems.add(lineItem);
            }
        }

        if (!lineItemsToUpdate.isEmpty()) {
            update lineItemsToUpdate;
        }

        if (!approvedLineItems.isEmpty()) {
            List<SObject> stockRecords = InventoryApprovalHandler.buildAvailableStockRecords(
                approvedLineItems,
                lineItemFields,
                fieldConfig.quantityField,
                fieldConfig.itemNameField,
                fieldConfig.itemCodeField,
                fieldConfig.unitField,
                fieldConfig.vendorField,
                fieldConfig.categoryField
            );
            if (!stockRecords.isEmpty()) {
                insert stockRecords;
            }
        }

        result.successCount = lineItemsToUpdate.size();
        result.message = 'Approval action applied to ' + result.successCount + ' line item(s).';
        return result;
    }

    /**
     * Submits line items for approval through Salesforce approval process.
     * @param lineItemIds List of line item IDs to submit for approval.
     * @return ApprovalSubmissionResult with submission status and errors.
     */
    @AuraEnabled
    public static ApprovalSubmissionResult submitLineItemsForApproval(List<Id> lineItemIds) {
        ApprovalSubmissionResult result = new ApprovalSubmissionResult();
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            result.message = 'No line items were selected for approval submission.';
            return result;
        }

        List<Approval.ProcessSubmitRequest> requests = new List<Approval.ProcessSubmitRequest>();
        for (Id lineItemId : lineItemIds) {
            Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
            request.setObjectId(lineItemId);
            request.setComments('Submitted from Inventory Approval Dashboard.');
            requests.add(request);
        }

        for (Approval.ProcessSubmitRequest req : requests) {
            try {
                Approval.ProcessResult processResult = Approval.process(req);
                if (processResult.isSuccess()) {
                    result.successCount++;
                } else {
                    Database.Error[] errors = processResult.getErrors();
                    for (Database.Error error : errors) {
                        result.errors.add(error.getMessage());
                    }
                }
            } catch (Exception ex) {
                result.errors.add(ex.getMessage());
            }
        }

        if (result.successCount > 0) {
            result.message = result.successCount + ' approval request(s) submitted successfully.';
        } else if (result.errors.isEmpty()) {
            result.message = 'No approval requests were submitted.';
        }
        return result;
    }

    private static QueryFieldConfig buildQueryFieldConfig(Map<String, Schema.SObjectField> lineItemFields) {
        QueryFieldConfig config = new QueryFieldConfig();
        config.statusField = InventoryApprovalHandler.getFirstAvailableField(lineItemFields, new List<String>{'Approval_Status__c','Status__c'});
        config.quantityField = InventoryApprovalHandler.getFirstAvailableField(lineItemFields, new List<String>{'Quantity__c','Requested_Quantity__c','Qty__c'});
        config.itemNameField = InventoryApprovalHandler.getFirstAvailableField(lineItemFields, new List<String>{'Item_Name__c','Inventory_Item__c'});
        config.itemCodeField = InventoryApprovalHandler.getFirstAvailableField(lineItemFields, new List<String>{'Item_Code__c','Product_Code__c'});
        config.unitField = InventoryApprovalHandler.getFirstAvailableField(lineItemFields, new List<String>{'Unit__c','Unit_Master__c'});
        config.vendorField = InventoryApprovalHandler.getFirstAvailableField(lineItemFields, new List<String>{'Vendor__c','Supplier__c'});
        config.categoryField = InventoryApprovalHandler.getFirstAvailableField(lineItemFields, new List<String>{'Item_Category__c','Category__c'});
        config.requestDateField = InventoryApprovalHandler.getFirstAvailableField(lineItemFields, new List<String>{'Requested_Date__c','Request_Date__c','CreatedDate'});
        if (String.isBlank(config.requestDateField)) {
            config.requestDateField = 'CreatedDate';
        }
        config.commentField = InventoryApprovalHandler.getFirstAvailableField(lineItemFields, new List<String>{'Approval_Comments__c','Comments__c','Remarks__c'});
        return config;
    }

    private static List<SObject> fetchLineItemsForPhase(Id projectPhaseId, QueryFieldConfig config) {
        List<String> selectFields = buildSelectFields(config, true);
        String soql = 'SELECT ' + String.join(selectFields, ',') + ' FROM Purchase_Order_Line_Item__c WHERE Project_Phase__c = :projectPhaseId ORDER BY ' + config.requestDateField + ' DESC NULLS LAST';
        return Database.query(soql);
    }

    private static List<SObject> fetchLineItemsById(Set<Id> lineItemIds, QueryFieldConfig config) {
        List<String> selectFields = buildSelectFields(config, false);
        String soql = 'SELECT ' + String.join(selectFields, ',') + ' FROM Purchase_Order_Line_Item__c WHERE Id IN :lineItemIds';
        return Database.query(soql);
    }

    private static List<String> buildSelectFields(QueryFieldConfig config, Boolean includeDateFields) {
        Map<String, Schema.SObjectField> lineItemFields = InventoryApprovalHandler.describeObjectFields(LINE_ITEM_OBJECT);
        List<String> selectFields = new List<String>{'Id','Name'};
        InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, 'Purchase_Order__c', 'Purchase_Order__r.Name');
        InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, 'Project_Phase__c', 'Project_Phase__r.Name');
        InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, config.itemNameField, config.itemNameField == 'Inventory_Item__c' ? 'Inventory_Item__r.Name' : null);
        InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, config.itemCodeField, null);
        InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, config.quantityField, null);
        InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, config.unitField, config.unitField == 'Unit_Master__c' ? 'Unit_Master__r.Name' : null);
        InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, config.vendorField, 'Vendor__r.Name');
        InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, config.categoryField, null);
        if (includeDateFields) {
            InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, config.requestDateField, null);
        }
        InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, config.statusField, null);
        InventoryApprovalHandler.addFieldIfExists(selectFields, lineItemFields, config.commentField, null);
        return selectFields;
    }

    private static List<ApprovalItem> buildApprovalItems(List<SObject> lineItems, QueryFieldConfig config) {
        List<ApprovalItem> items = new List<ApprovalItem>();
        for (SObject lineItem : lineItems) {
            String statusValue = normalizeStatus(InventoryApprovalHandler.getString(lineItem, config.statusField));
            ApprovalItem item = buildApprovalItem(lineItem, config, statusValue);
            items.add(item);
        }
        return items;
    }

    private static List<AnalyticsEntry> buildCategoryAnalytics(List<ApprovalItem> items) {
        Map<String, Integer> categoryMap = new Map<String, Integer>();
        for (ApprovalItem item : items) {
            String categoryLabel = String.isBlank(item.category) ? 'Unassigned' : item.category;
            categoryMap.put(categoryLabel, categoryMap.containsKey(categoryLabel) ? categoryMap.get(categoryLabel) + 1 : 1);
        }
        return buildAnalytics(categoryMap);
    }

    private static List<AnalyticsEntry> buildStatusAnalytics(List<ApprovalItem> items) {
        Map<String, Integer> statusMap = new Map<String, Integer>();
        for (ApprovalItem item : items) {
            statusMap.put(item.status, statusMap.containsKey(item.status) ? statusMap.get(item.status) + 1 : 1);
        }
        return buildAnalytics(statusMap);
    }

    private static List<AnalyticsEntry> buildQuantityAnalytics(List<ApprovalItem> items) {
        Map<String, Decimal> typeQuantityMap = new Map<String, Decimal>();
        for (ApprovalItem item : items) {
            String itemTypeKey = String.isBlank(item.itemName) ? 'Unknown item' : item.itemName;
            Decimal quantityValue = item.quantity == null ? 0 : item.quantity;
            typeQuantityMap.put(itemTypeKey, typeQuantityMap.containsKey(itemTypeKey) ? typeQuantityMap.get(itemTypeKey) + quantityValue : quantityValue);
        }
        List<AnalyticsEntry> results = new List<AnalyticsEntry>();
        for (String label : typeQuantityMap.keySet()) {
            results.add(new AnalyticsEntry(label, typeQuantityMap.get(label)));
        }
        return results;
    }

    private static Set<Id> extractIds(List<ApprovalItem> items) {
        Set<Id> ids = new Set<Id>();
        for (ApprovalItem item : items) {
            ids.add(item.id);
        }
        return ids;
    }

    private static Set<Id> extractLineItemIds(List<ApprovalActionRequest> actions) {
        Set<Id> ids = new Set<Id>();
        for (ApprovalActionRequest action : actions) {
            if (action != null && action.lineItemId != null) {
                ids.add(action.lineItemId);
            }
        }
        return ids;
    }

    private static DashboardSummary buildDashboardSummary(List<ApprovalItem> items, Id projectPhaseId) {
        DashboardSummary summary = new DashboardSummary();
        summary.pendingCount = countByStatus(items, 'Pending');
        summary.approvedCount = countByStatus(items, 'Approved');
        summary.rejectedCount = countByStatus(items, 'Rejected');
        summary.highQuantityAlertCount = countHighQuantityAlerts(items);
        summary.newRequestsCount = countNewRequests(items);
        summary.totalQuantity = calculateTotalQuantity(items);
        summary.pendingBadge = summary.pendingCount > 0 ? 'Approval pending' : 'No pending approvals';
        summary.projectPhaseName = fetchProjectPhaseName(projectPhaseId);
        summary.lastRefresh = System.now();
        summary.projectPhaseId = projectPhaseId;
        return summary;
    }

    private static Integer countNewRequests(List<ApprovalItem> items) {
        Integer count = 0;
        Datetime sevenDaysAgo = System.now().addDays(-7);
        for (ApprovalItem item : items) {
            if (item.requestedDate != null && item.requestedDate >= sevenDaysAgo && isPendingStatus(item.status)) {
                count++;
            }
        }
        return count;
    }

    private static Decimal calculateTotalQuantity(List<ApprovalItem> items) {
        Decimal total = 0;
        for (ApprovalItem item : items) {
            if (item.quantity != null) {
                total += item.quantity;
            }
        }
        return total;
    }

    private static List<AnalyticsEntry> fetchPhaseAllocation() {
        List<AnalyticsEntry> allocations = new List<AnalyticsEntry>();
        Map<String, Schema.SObjectField> stockFields = InventoryApprovalHandler.describeObjectFields(AVAILABLE_STOCK_OBJECT);
        if (stockFields.isEmpty()) {
            return allocations;
        }

        String stockQtyField = InventoryApprovalHandler.getFirstAvailableField(stockFields, new List<String>{'Available_Quantity__c','Quantity__c','Stock_Quantity__c'});
        String stockPhaseField = InventoryApprovalHandler.getFirstAvailableField(stockFields, new List<String>{'Project_Phase__c'});
        if (String.isBlank(stockQtyField) || String.isBlank(stockPhaseField)) {
            return allocations;
        }

        String stockPhaseNameField = 'Project_Phase__r.Name';
        List<String> selectFields = new List<String>{stockQtyField, stockPhaseField, stockPhaseNameField};
        String soql = 'SELECT ' + String.join(selectFields, ',') + ' FROM Available_Item_Stock__c WHERE ' + stockPhaseField + ' != NULL';
        
        for (SObject stock : Database.query(soql)) {
            Id phaseId = (Id) stock.get(stockPhaseField);
            Decimal quantity = InventoryApprovalHandler.getDecimal(stock, stockQtyField);
            if (quantity == null) {
                quantity = 0;
            }
            String phaseName = InventoryApprovalHandler.getString(stock, stockPhaseNameField);
            if (String.isBlank(phaseName)) {
                phaseName = phaseId == null ? 'Unknown phase' : String.valueOf(phaseId);
            }
            
            Boolean found = false;
            for (AnalyticsEntry entry : allocations) {
                if (entry.label == phaseName) {
                    entry.value += quantity;
                    found = true;
                    break;
                }
            }
            if (!found) {
                allocations.add(new AnalyticsEntry(phaseName, quantity));
            }
        }
        return allocations;
    }

    private static List<ApprovalHistoryEntry> fetchApprovalHistory(Set<Id> lineItemIds) {
        List<ApprovalHistoryEntry> historyEntries = new List<ApprovalHistoryEntry>();
        if (lineItemIds == null || lineItemIds.isEmpty() || !Schema.getGlobalDescribe().containsKey('ProcessInstance')) {
            return historyEntries;
        }

        List<ProcessInstance> processes = [
            SELECT Id, TargetObjectId, Status, CompletedDate,
                (SELECT Id, ActorId, Actor.Name, Comments, StepStatus, CreatedDate
                 FROM StepsAndWorkitems ORDER BY CreatedDate DESC LIMIT 1)
            FROM ProcessInstance
            WHERE TargetObjectId IN :lineItemIds
            ORDER BY CreatedDate DESC
        ];

        for (ProcessInstance process : processes) {
            ApprovalHistoryEntry entry = new ApprovalHistoryEntry();
            entry.lineItemId = process.TargetObjectId;
            entry.processStatus = process.Status;
            entry.completedDate = process.CompletedDate;
            if (process.StepsAndWorkitems != null && !process.StepsAndWorkitems.isEmpty()) {
                ProcessInstanceHistory workItem = process.StepsAndWorkitems[0];
                entry.currentApprover = InventoryApprovalHandler.getString(workItem, 'Actor.Name');
                entry.currentStep = workItem.StepStatus;
                entry.comments = workItem.Comments;
                entry.lastStepDate = workItem.CreatedDate;
            }
            historyEntries.add(entry);
        }
        return historyEntries;
    }

    private static String normalizeStatus(String status) {
        if (String.isBlank(status)) {
            return 'Pending';
        }
        if (APPROVED_STATUS_VALUES.contains(status.trim())) {
            return 'Approved';
        }
        if (REJECTED_STATUS_VALUES.contains(status.trim())) {
            return 'Rejected';
        }
        return status.trim();
    }

    private static Boolean hasApprovalProcess() {
        return Schema.getGlobalDescribe().containsKey('Approval') || Schema.getGlobalDescribe().containsKey('ProcessInstance');
    }

    private static String fetchProjectPhaseName(Id phaseId) {
        if (phaseId == null) {
            return null;
        }
        try {
            Project_Phase__c phase = [SELECT Name FROM Project_Phase__c WHERE Id = :phaseId LIMIT 1];
            return phase.Name;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Integer countByStatus(List<ApprovalItem> items, String statusToken) {
        Integer count = 0;
        for (ApprovalItem item : items) {
            if (item != null && !String.isBlank(item.status) && item.status.equalsIgnoreCase(statusToken)) {
                count++;
            }
        }
        return count;
    }

    private static Integer countHighQuantityAlerts(List<ApprovalItem> items) {
        Integer alerts = 0;
        for (ApprovalItem item : items) {
            if (item != null && item.quantity != null && item.quantity >= 100 && isPendingStatus(item.status)) {
                alerts++;
            }
        }
        return alerts;
    }

    private static List<AnalyticsEntry> buildAnalytics(Map<String, Integer> sourceMap) {
        List<AnalyticsEntry> results = new List<AnalyticsEntry>();
        for (String label : sourceMap.keySet()) {
            results.add(new AnalyticsEntry(label, sourceMap.get(label)));
        }
        return results;
    }

    private static ApprovalItem buildApprovalItem(SObject lineItem, QueryFieldConfig config, String statusValue) {
        ApprovalItem item = new ApprovalItem();
        item.id = (Id) lineItem.get('Id');
        item.lineItemName = InventoryApprovalHandler.getString(lineItem, 'Name');
        item.itemName = InventoryApprovalHandler.getItemName(lineItem, config.itemNameField);
        item.itemCode = InventoryApprovalHandler.getString(lineItem, config.itemCodeField);
        item.quantity = InventoryApprovalHandler.getDecimal(lineItem, config.quantityField);
        item.unit = InventoryApprovalHandler.getUnitLabel(lineItem, config.unitField);
        item.vendor = InventoryApprovalHandler.getVendorName(lineItem, config.vendorField);
        item.purchaseOrderNumber = InventoryApprovalHandler.getString(lineItem, 'Purchase_Order__r.Name');
        item.projectPhaseName = InventoryApprovalHandler.getString(lineItem, 'Project_Phase__r.Name');
        item.requestedDate = InventoryApprovalHandler.getDateTime(lineItem, config.requestDateField);
        item.status = statusValue;
        item.category = InventoryApprovalHandler.getString(lineItem, config.categoryField);
        item.comments = InventoryApprovalHandler.getString(lineItem, config.commentField);
        item.badgeVariant = getBadgeVariant(item.status);
        item.canApprove = isPendingStatus(item.status);
        return item;
    }

    private static Boolean isPendingStatus(String status) {
        return status != null && PENDING_STATUS_VALUES.contains(status.trim());
    }

    private static String getBadgeVariant(String status) {
        if (String.isBlank(status)) {
            return 'warning';
        }
        if (APPROVED_STATUS_VALUES.contains(status.trim())) {
            return 'success';
        }
        if (REJECTED_STATUS_VALUES.contains(status.trim())) {
            return 'destructive';
        }
        return 'warning';
    }

    /**
     * Dashboard payload wrapper class.
     */
    public class DashboardPayload {
        @AuraEnabled public List<ApprovalItem> items;
        @AuraEnabled public List<AnalyticsEntry> categoryDistribution;
        @AuraEnabled public List<AnalyticsEntry> statusDistribution;
        @AuraEnabled public List<AnalyticsEntry> quantityByItemType;
        @AuraEnabled public List<AnalyticsEntry> phaseAllocation;
        @AuraEnabled public List<ApprovalHistoryEntry> approvalHistory;
        @AuraEnabled public DashboardSummary summary;
        @AuraEnabled public Boolean hasApprovalProcess;
    }

    /**
     * Dashboard summary statistics wrapper.
     */
    public class DashboardSummary {
        @AuraEnabled public Integer pendingCount;
        @AuraEnabled public Integer approvedCount;
        @AuraEnabled public Integer rejectedCount;
        @AuraEnabled public Integer highQuantityAlertCount;
        @AuraEnabled public Integer newRequestsCount;
        @AuraEnabled public Decimal totalQuantity;
        @AuraEnabled public String pendingBadge;
        @AuraEnabled public String projectPhaseName;
        @AuraEnabled public Id projectPhaseId;
        @AuraEnabled public Datetime lastRefresh;
    }

    /**
     * Approval item wrapper for dashboard display.
     */
    public class ApprovalItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String lineItemName;
        @AuraEnabled public String itemName;
        @AuraEnabled public String itemCode;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String unit;
        @AuraEnabled public String vendor;
        @AuraEnabled public String purchaseOrderNumber;
        @AuraEnabled public String projectPhaseName;
        @AuraEnabled public Datetime requestedDate;
        @AuraEnabled public String status;
        @AuraEnabled public String category;
        @AuraEnabled public String comments;
        @AuraEnabled public String badgeVariant;
        @AuraEnabled public Boolean canApprove;
    }

    /**
     * Approval action request input wrapper.
     */
    public class ApprovalActionRequest {
        @AuraEnabled public Id lineItemId;
        @AuraEnabled public String action;
        @AuraEnabled public String comment;
    }

    /**
     * Approval action result wrapper.
     */
    public class ApprovalActionResult {
        @AuraEnabled public Integer successCount = 0;
        @AuraEnabled public String message;
    }

    /**
     * Approval submission result wrapper.
     */
    public class ApprovalSubmissionResult {
        @AuraEnabled public Integer successCount = 0;
        @AuraEnabled public String message;
        @AuraEnabled public List<String> errors = new List<String>();
    }

    /**
     * Analytics entry wrapper for chart data.
     */
    public class AnalyticsEntry {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal value;

        public AnalyticsEntry() {
        }

        public AnalyticsEntry(String label, Integer value) {
            this.label = label;
            this.value = value == null ? 0 : Decimal.valueOf(value);
        }

        public AnalyticsEntry(String label, Decimal value) {
            this.label = label;
            this.value = value == null ? 0 : value;
        }
    }

    /**
     * Approval history entry wrapper.
     */
    public class ApprovalHistoryEntry {
        @AuraEnabled public Id lineItemId;
        @AuraEnabled public String processStatus;
        @AuraEnabled public String currentApprover;
        @AuraEnabled public String currentStep;
        @AuraEnabled public String comments;
        @AuraEnabled public Datetime lastStepDate;
        @AuraEnabled public Datetime completedDate;
    }

    /**
     * Query field configuration helper class.
     */
    private class QueryFieldConfig {
        public String statusField;
        public String quantityField;
        public String itemNameField;
        public String itemCodeField;
        public String unitField;
        public String vendorField;
        public String categoryField;
        public String requestDateField;
        public String commentField;
    }
}