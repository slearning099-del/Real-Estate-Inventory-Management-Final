public with sharing class ProjectDashboardController {
    private static final String LINE_ITEM_OBJECT = 'Purchase_Order_Line_Item__c';
    private static final Set<String> PENDING_STATUS_VALUES = new Set<String>{'Pending','Submitted for Approval','Awaiting Approval','New','Approval Pending','Pending Approval'};
    private static final Set<String> APPROVED_STATUS_VALUES = new Set<String>{'Approved','Accepted'};
    private static final Set<String> REJECTED_STATUS_VALUES = new Set<String>{'Rejected','Declined'};

    @AuraEnabled(cacheable=true)
    public static ProjectDashboardPayload getDashboardDataByProjectId(Id projectId) {
        if (projectId == null) {
            throw new AuraHandledException('Project Id is required.');
        }

        Map<String, Schema.SObjectField> lineItemFields = describeObjectFields(LINE_ITEM_OBJECT);
        if (lineItemFields.isEmpty()) {
            throw new AuraHandledException('Purchase Order Line Item object is not available.');
        }

        String statusField = getFirstAvailableField(lineItemFields, new List<String>{'Approval_Status__c','Status__c'});
        String quantityField = getFirstAvailableField(lineItemFields, new List<String>{'Quantity__c','Requested_Quantity__c','Qty__c'});

        List<Project_Phase__c> phases = [
            SELECT Id, Name
            FROM Project_Phase__c
            WHERE Project__c = :projectId
            ORDER BY Name
        ];

        ProjectDashboardPayload payload = new ProjectDashboardPayload();
        payload.phaseSummaries = new List<ProjectPhaseSummary>();
        payload.summary = new SummaryCounts();
        payload.summary.totalPhases = phases.size();
        payload.summary.pendingCount = 0;
        payload.summary.approvedCount = 0;
        payload.summary.rejectedCount = 0;
        payload.summary.totalQuantity = 0;
        payload.summary.lastRefresh = System.now();

        if (phases.isEmpty()) {
            return payload;
        }

        Set<Id> phaseIds = new Set<Id>();
        Map<Id, String> phaseNames = new Map<Id, String>();
        for (Project_Phase__c phase : phases) {
            phaseIds.add(phase.Id);
            phaseNames.put(phase.Id, phase.Name);
        }

        List<String> selectFields = new List<String>{'Id','Project_Phase__c'};
        if (!String.isBlank(statusField)) {
            selectFields.add(statusField);
        }
        if (!String.isBlank(quantityField)) {
            selectFields.add(quantityField);
        }

        String soql = 'SELECT ' + String.join(selectFields, ',') + ' FROM ' + LINE_ITEM_OBJECT + ' WHERE Project_Phase__c IN :phaseIds';
        List<SObject> lineItems = Database.query(soql);

        Map<Id, ProjectPhaseSummary> summaryMap = new Map<Id, ProjectPhaseSummary>();
        for (Id phaseId : phaseIds) {
            ProjectPhaseSummary phaseSummary = new ProjectPhaseSummary();
            phaseSummary.phaseId = phaseId;
            phaseSummary.phaseName = phaseNames.get(phaseId);
            phaseSummary.pendingCount = 0;
            phaseSummary.approvedCount = 0;
            phaseSummary.rejectedCount = 0;
            phaseSummary.totalQuantity = 0;
            summaryMap.put(phaseId, phaseSummary);
        }

        for (SObject lineItem : lineItems) {
            Id phaseId = (Id) lineItem.get('Project_Phase__c');
            if (phaseId == null || !summaryMap.containsKey(phaseId)) {
                continue;
            }
            ProjectPhaseSummary phaseSummary = summaryMap.get(phaseId);
            String status = getString(lineItem, statusField);
            Decimal quantity = getDecimal(lineItem, quantityField);
            if (isPendingStatus(status)) {
                phaseSummary.pendingCount++;
                payload.summary.pendingCount++;
            } else if (isApprovedStatus(status)) {
                phaseSummary.approvedCount++;
                payload.summary.approvedCount++;
            } else if (isRejectedStatus(status)) {
                phaseSummary.rejectedCount++;
                payload.summary.rejectedCount++;
            }
            if (quantity != null) {
                phaseSummary.totalQuantity += quantity;
                payload.summary.totalQuantity += quantity;
            }
        }

        payload.phaseSummaries.addAll(summaryMap.values());
        return payload;
    }

    private static Boolean isPendingStatus(String status) {
        return status != null && PENDING_STATUS_VALUES.contains(status.trim());
    }

    private static Boolean isApprovedStatus(String status) {
        return status != null && APPROVED_STATUS_VALUES.contains(status.trim());
    }

    private static Boolean isRejectedStatus(String status) {
        return status != null && REJECTED_STATUS_VALUES.contains(status.trim());
    }

    private static Decimal getDecimal(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) {
            return null;
        }
        Object value = record.get(fieldName);
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        return null;
    }

    private static String getString(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) {
            return null;
        }
        Object value = record.get(fieldName);
        return value == null ? null : String.valueOf(value);
    }

    private static Map<String, Schema.SObjectField> describeObjectFields(String objectApiName) {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(objectApiName)) {
            return new Map<String, Schema.SObjectField>();
        }
        return globalDescribe.get(objectApiName).getDescribe().fields.getMap();
    }

    private static String getFirstAvailableField(Map<String, Schema.SObjectField> fields, List<String> candidates) {
        if (fields == null || candidates == null) {
            return null;
        }
        for (String candidate : candidates) {
            if (!String.isBlank(candidate) && fields.containsKey(candidate)) {
                return candidate;
            }
        }
        return null;
    }

    public class ProjectDashboardPayload {
        @AuraEnabled public List<ProjectPhaseSummary> phaseSummaries;
        @AuraEnabled public SummaryCounts summary;
    }

    public class ProjectPhaseSummary {
        @AuraEnabled public Id phaseId;
        @AuraEnabled public String phaseName;
        @AuraEnabled public Integer pendingCount;
        @AuraEnabled public Integer approvedCount;
        @AuraEnabled public Integer rejectedCount;
        @AuraEnabled public Decimal totalQuantity;
    }

    public class SummaryCounts {
        @AuraEnabled public Integer totalPhases;
        @AuraEnabled public Integer pendingCount;
        @AuraEnabled public Integer approvedCount;
        @AuraEnabled public Integer rejectedCount;
        @AuraEnabled public Decimal totalQuantity;
        @AuraEnabled public Datetime lastRefresh;
    }
}