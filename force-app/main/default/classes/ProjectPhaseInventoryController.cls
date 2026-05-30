/**
 * @description Controller class for Project Phase Inventory Dashboard
 * @author Salesforce
 * @date 2026
 */
public with sharing class ProjectPhaseInventoryController {
    
    /**
     * @description Wrapper class for Project data
     */
    public class ProjectWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        
        public ProjectWrapper(String id, String name) {
            this.id = id;
            this.name = name;
        }
    }
    
    /**
     * @description Wrapper class for Project Phase Summary
     */
    public class PhaseSummary {
        @AuraEnabled public String phaseId;
        @AuraEnabled public String phaseName;
        @AuraEnabled public Decimal totalAvailable;
        @AuraEnabled public Decimal totalUsed;
        @AuraEnabled public Decimal totalReturned;
        
        public PhaseSummary() {
            this.totalAvailable = 0;
            this.totalUsed = 0;
            this.totalReturned = 0;
        }
    }
    
    /**
     * @description Wrapper class for Inventory Item Details
     */
    public class InventoryItem {
        @AuraEnabled public String phaseId;
        @AuraEnabled public String phaseName;
        @AuraEnabled public String itemName;
        @AuraEnabled public Decimal availableQty;
        @AuraEnabled public Decimal usedQty;
        @AuraEnabled public Decimal returnedQty;
        
        public InventoryItem() {
            this.availableQty = 0;
            this.usedQty = 0;
            this.returnedQty = 0;
        }
    }
    
    /**
     * @description Wrapper class for complete Dashboard Data
     */
    public class DashboardData {
        @AuraEnabled public List<PhaseSummary> phaseSummaries;
        @AuraEnabled public Decimal totalAvailable;
        @AuraEnabled public Decimal totalUsed;
        @AuraEnabled public Decimal totalReturned;
        @AuraEnabled public List<InventoryItem> inventoryItems;
        
        public DashboardData() {
            this.phaseSummaries = new List<PhaseSummary>();
            this.inventoryItems = new List<InventoryItem>();
            this.totalAvailable = 0;
            this.totalUsed = 0;
            this.totalReturned = 0;
        }
    }
    
    /**
     * @description Get all active Projects
     * @return List<ProjectWrapper> List of projects
     */
    @AuraEnabled(cacheable=true)
    public static List<ProjectWrapper> getProjects() {
        try {
            List<ProjectWrapper> projects = new List<ProjectWrapper>();
            
            // Query all projects - adjust the fields based on your org's Project__c object
            for (Project__c proj : [
                SELECT Id, Name 
                FROM Project__c 
                WHERE Active__c = true
                ORDER BY Name ASC 
                LIMIT 1000
            ]) {
                projects.add(new ProjectWrapper(proj.Id, proj.Name));
            }
            
            return projects;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching projects: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get Dashboard Data for selected Project
     * @param projectId Selected Project Id
     * @return DashboardData Complete dashboard data
     */
    @AuraEnabled
    public static DashboardData getDashboardData(String projectId) {
        try {
            if (String.isBlank(projectId)) {
                throw new AuraHandledException('Project ID is required');
            }
            
            DashboardData dashboardData = new DashboardData();
            Map<String, PhaseSummary> phaseSummaryMap = new Map<String, PhaseSummary>();
            Map<String, Map<String, InventoryItem>> phaseItemMap = new Map<String, Map<String, InventoryItem>>();
            
            // Get all phases for the project
            Map<Id, Project_Phase__c> phasesMap = new Map<Id, Project_Phase__c>([
                SELECT Id, Name, Project__c
                FROM Project_Phase__c
                WHERE Project__c = :projectId
                ORDER BY Name ASC
            ]);
            
            if (phasesMap.isEmpty()) {
                return dashboardData;
            }
            
            Set<Id> phaseIds = phasesMap.keySet();
            
            // Initialize phase summaries
            for (Project_Phase__c phase : phasesMap.values()) {
                PhaseSummary summary = new PhaseSummary();
                summary.phaseId = phase.Id;
                summary.phaseName = phase.Name;
                phaseSummaryMap.put(phase.Id, summary);
                phaseItemMap.put(phase.Id, new Map<String, InventoryItem>());
            }
            
            // Query Available Stock
            for (Available_Stock__c availStock : [
                SELECT Id, Name, Project_Phase__c, Item_Name__c, Quantity__c
                FROM Available_Stock__c
                WHERE Project_Phase__c IN :phaseIds AND Quantity__c != null
            ]) {
                String phaseId = availStock.Project_Phase__c;
                String itemName = String.isNotBlank(availStock.Item_Name__c) ? availStock.Item_Name__c : 'Unknown Item';
                
                // Update phase summary
                if (phaseSummaryMap.containsKey(phaseId)) {
                    phaseSummaryMap.get(phaseId).totalAvailable += availStock.Quantity__c;
                    dashboardData.totalAvailable += availStock.Quantity__c;
                }
                
                // Update item details
                if (!phaseItemMap.get(phaseId).containsKey(itemName)) {
                    InventoryItem item = new InventoryItem();
                    item.phaseId = phaseId;
                    item.phaseName = phasesMap.get(phaseId).Name;
                    item.itemName = itemName;
                    phaseItemMap.get(phaseId).put(itemName, item);
                }
                phaseItemMap.get(phaseId).get(itemName).availableQty += availStock.Quantity__c;
            }
            
            // Query Used Stock
            for (Used_Stock__c usedStock : [
                SELECT Id, Name, Project_Phase__c, Item_Name__c, Quantity__c
                FROM Used_Stock__c
                WHERE Project_Phase__c IN :phaseIds AND Quantity__c != null
            ]) {
                String phaseId = usedStock.Project_Phase__c;
                String itemName = String.isNotBlank(usedStock.Item_Name__c) ? usedStock.Item_Name__c : 'Unknown Item';
                
                // Update phase summary
                if (phaseSummaryMap.containsKey(phaseId)) {
                    phaseSummaryMap.get(phaseId).totalUsed += usedStock.Quantity__c;
                    dashboardData.totalUsed += usedStock.Quantity__c;
                }
                
                // Update item details
                if (!phaseItemMap.get(phaseId).containsKey(itemName)) {
                    InventoryItem item = new InventoryItem();
                    item.phaseId = phaseId;
                    item.phaseName = phasesMap.get(phaseId).Name;
                    item.itemName = itemName;
                    phaseItemMap.get(phaseId).put(itemName, item);
                }
                phaseItemMap.get(phaseId).get(itemName).usedQty += usedStock.Quantity__c;
            }
            
            // Query Returned Stock
            for (Return_Stock__c returnStock : [
                SELECT Id, Name, Project_Phase__c, Item_Name__c, Quantity__c
                FROM Return_Stock__c
                WHERE Project_Phase__c IN :phaseIds AND Quantity__c != null
            ]) {
                String phaseId = returnStock.Project_Phase__c;
                String itemName = String.isNotBlank(returnStock.Item_Name__c) ? returnStock.Item_Name__c : 'Unknown Item';
                
                // Update phase summary
                if (phaseSummaryMap.containsKey(phaseId)) {
                    phaseSummaryMap.get(phaseId).totalReturned += returnStock.Quantity__c;
                    dashboardData.totalReturned += returnStock.Quantity__c;
                }
                
                // Update item details
                if (!phaseItemMap.get(phaseId).containsKey(itemName)) {
                    InventoryItem item = new InventoryItem();
                    item.phaseId = phaseId;
                    item.phaseName = phasesMap.get(phaseId).Name;
                    item.itemName = itemName;
                    phaseItemMap.get(phaseId).put(itemName, item);
                }
                phaseItemMap.get(phaseId).get(itemName).returnedQty += returnStock.Quantity__c;
            }
            
            // Compile results
            dashboardData.phaseSummaries = phaseSummaryMap.values();
            
            for (Map<String, InventoryItem> itemMap : phaseItemMap.values()) {
                dashboardData.inventoryItems.addAll(itemMap.values());
            }
            
            return dashboardData;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching dashboard data: ' + e.getMessage());
        }
    }
}