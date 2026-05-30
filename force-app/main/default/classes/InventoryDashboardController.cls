/**
 * @description Controller class for Inventory Management Dashboard
 * @author Salesforce
 * @date 2026
 */
public with sharing class InventoryDashboardController {
    
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
     * @description Get all Projects
     * @return List<ProjectWrapper> List of projects
     */
    @AuraEnabled(cacheable=true)
    public static List<ProjectWrapper> getProjects() {
        try {
            List<ProjectWrapper> projects = new List<ProjectWrapper>();
            
            // Query all projects
            for (Project__c proj : [
                SELECT Id, Name 
                FROM Project__c 
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
            
            // Query Available Stock records (all quantities in one object)
            for (Available_Stock__c stock : [
                SELECT Id, Name, Project_Phase__c, 
                       Inventory_Item__r.Name,
                       Available_Quantity__c, 
                       Used_Quantity__c, 
                       Return_Item_Quantity__c
                FROM Available_Stock__c
                WHERE Project_Phase__c IN :phaseIds
            ]) {
                String phaseId = stock.Project_Phase__c;
                String itemName = stock.Inventory_Item__r != null && String.isNotBlank(stock.Inventory_Item__r.Name) 
                    ? stock.Inventory_Item__r.Name 
                    : 'Unknown Item';
                
                Decimal availableQty = stock.Available_Quantity__c != null ? stock.Available_Quantity__c : 0;
                Decimal usedQty = stock.Used_Quantity__c != null ? stock.Used_Quantity__c : 0;
                Decimal returnedQty = stock.Return_Item_Quantity__c != null ? stock.Return_Item_Quantity__c : 0;
                
                // Update phase summary
                if (phaseSummaryMap.containsKey(phaseId)) {
                    phaseSummaryMap.get(phaseId).totalAvailable += availableQty;
                    phaseSummaryMap.get(phaseId).totalUsed += usedQty;
                    phaseSummaryMap.get(phaseId).totalReturned += returnedQty;
                    
                    dashboardData.totalAvailable += availableQty;
                    dashboardData.totalUsed += usedQty;
                    dashboardData.totalReturned += returnedQty;
                }
                
                // Update item details
                if (!phaseItemMap.get(phaseId).containsKey(itemName)) {
                    InventoryItem item = new InventoryItem();
                    item.phaseId = phaseId;
                    item.phaseName = phasesMap.get(phaseId).Name;
                    item.itemName = itemName;
                    item.availableQty = 0;
                    item.usedQty = 0;
                    item.returnedQty = 0;
                    phaseItemMap.get(phaseId).put(itemName, item);
                }
                
                // Aggregate quantities by item
                phaseItemMap.get(phaseId).get(itemName).availableQty += availableQty;
                phaseItemMap.get(phaseId).get(itemName).usedQty += usedQty;
                phaseItemMap.get(phaseId).get(itemName).returnedQty += returnedQty;
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