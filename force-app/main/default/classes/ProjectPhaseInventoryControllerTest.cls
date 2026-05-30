/**
 * @description Test class for ProjectPhaseInventoryController
 * @author Salesforce
 * @date 2026
 */
@isTest
private class ProjectPhaseInventoryControllerTest {
    
    @testSetup
    static void setupTestData() {
        // Create test Project
        Project__c project = new Project__c(
            Name = 'Test Project',
            Active__c = true
        );
        insert project;
        
        // Create test Project Phases
        List<Project_Phase__c> phases = new List<Project_Phase__c>();
        for (Integer i = 1; i <= 3; i++) {
            phases.add(new Project_Phase__c(
                Name = 'Phase ' + i,
                Project__c = project.Id
            ));
        }
        insert phases;
        
        // Create test Available Stock records
        List<Available_Stock__c> availStocks = new List<Available_Stock__c>();
        for (Project_Phase__c phase : phases) {
            availStocks.add(new Available_Stock__c(
                Name = 'Avail Stock ' + phase.Name,
                Project_Phase__c = phase.Id,
                Item_Name__c = 'Item A',
                Quantity__c = 100
            ));
            availStocks.add(new Available_Stock__c(
                Name = 'Avail Stock ' + phase.Name + ' B',
                Project_Phase__c = phase.Id,
                Item_Name__c = 'Item B',
                Quantity__c = 50
            ));
        }
        insert availStocks;
        
        // Create test Used Stock records
        List<Used_Stock__c> usedStocks = new List<Used_Stock__c>();
        for (Project_Phase__c phase : phases) {
            usedStocks.add(new Used_Stock__c(
                Name = 'Used Stock ' + phase.Name,
                Project_Phase__c = phase.Id,
                Item_Name__c = 'Item A',
                Quantity__c = 30
            ));
        }
        insert usedStocks;
        
        // Create test Return Stock records
        List<Return_Stock__c> returnStocks = new List<Return_Stock__c>();
        for (Project_Phase__c phase : phases) {
            returnStocks.add(new Return_Stock__c(
                Name = 'Return Stock ' + phase.Name,
                Project_Phase__c = phase.Id,
                Item_Name__c = 'Item A',
                Quantity__c = 10
            ));
        }
        insert returnStocks;
    }
    
    @isTest
    static void testGetProjects() {
        Test.startTest();
        List<ProjectPhaseInventoryController.ProjectWrapper> projects = 
            ProjectPhaseInventoryController.getProjects();
        Test.stopTest();
        
        System.assertNotEquals(null, projects, 'Projects should not be null');
        System.assertEquals(1, projects.size(), 'Should return 1 project');
        System.assertEquals('Test Project', projects[0].name, 'Project name should match');
    }
    
    @isTest
    static void testGetDashboardData() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        
        Test.startTest();
        ProjectPhaseInventoryController.DashboardData data = 
            ProjectPhaseInventoryController.getDashboardData(project.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, data, 'Dashboard data should not be null');
        System.assertEquals(3, data.phaseSummaries.size(), 'Should have 3 phase summaries');
        System.assertEquals(450, data.totalAvailable, 'Total available should be 450 (3 phases * 150)');
        System.assertEquals(90, data.totalUsed, 'Total used should be 90 (3 phases * 30)');
        System.assertEquals(30, data.totalReturned, 'Total returned should be 30 (3 phases * 10)');
        System.assert(data.inventoryItems.size() > 0, 'Should have inventory items');
    }
    
    @isTest
    static void testGetDashboardDataWithNullProjectId() {
        Boolean exceptionCaught = false;
        
        Test.startTest();
        try {
            ProjectPhaseInventoryController.getDashboardData(null);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assert(e.getMessage().contains('Project ID is required'), 
                'Error message should mention Project ID');
        }
        Test.stopTest();
        
        System.assert(exceptionCaught, 'Exception should be thrown for null project ID');
    }
    
    @isTest
    static void testGetDashboardDataWithNoPhases() {
        // Create a project without phases
        Project__c emptyProject = new Project__c(
            Name = 'Empty Project',
            Active__c = true
        );
        insert emptyProject;
        
        Test.startTest();
        ProjectPhaseInventoryController.DashboardData data = 
            ProjectPhaseInventoryController.getDashboardData(emptyProject.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, data, 'Dashboard data should not be null');
        System.assertEquals(0, data.phaseSummaries.size(), 'Should have no phase summaries');
        System.assertEquals(0, data.totalAvailable, 'Total available should be 0');
        System.assertEquals(0, data.totalUsed, 'Total used should be 0');
        System.assertEquals(0, data.totalReturned, 'Total returned should be 0');
    }
    
    @isTest
    static void testPhaseSummaryCalculations() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        List<Project_Phase__c> phases = [SELECT Id, Name FROM Project_Phase__c WHERE Project__c = :project.Id];
        
        Test.startTest();
        ProjectPhaseInventoryController.DashboardData data = 
            ProjectPhaseInventoryController.getDashboardData(project.Id);
        Test.stopTest();
        
        // Verify phase summaries
        for (ProjectPhaseInventoryController.PhaseSummary summary : data.phaseSummaries) {
            System.assertEquals(150, summary.totalAvailable, 'Each phase should have 150 available (100+50)');
            System.assertEquals(30, summary.totalUsed, 'Each phase should have 30 used');
            System.assertEquals(10, summary.totalReturned, 'Each phase should have 10 returned');
        }
    }
    
    @isTest
    static void testInventoryItemAggregation() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        
        Test.startTest();
        ProjectPhaseInventoryController.DashboardData data = 
            ProjectPhaseInventoryController.getDashboardData(project.Id);
        Test.stopTest();
        
        // Verify inventory items
        System.assert(data.inventoryItems.size() > 0, 'Should have inventory items');
        
        // Check that Item A exists and has correct quantities
        Boolean itemAFound = false;
        for (ProjectPhaseInventoryController.InventoryItem item : data.inventoryItems) {
            if (item.itemName == 'Item A') {
                itemAFound = true;
                System.assertEquals(100, item.availableQty, 'Item A should have 100 available per phase');
                System.assertEquals(30, item.usedQty, 'Item A should have 30 used per phase');
                System.assertEquals(10, item.returnedQty, 'Item A should have 10 returned per phase');
            }
        }
        System.assert(itemAFound, 'Item A should be found in inventory items');
    }
}