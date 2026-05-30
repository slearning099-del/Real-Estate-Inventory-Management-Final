/**
 * @description Test class for InventoryDashboardController
 * @author Salesforce
 * @date 2026
 */
@isTest
private class InventoryDashboardControllerTest {
    
    @testSetup
    static void setupTestData() {
        // Create test Project
        Project__c project = new Project__c(
            Name = 'Test Project'
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
        List<Available_Stock__c> stocks = new List<Available_Stock__c>();
        for (Project_Phase__c phase : phases) {
            stocks.add(new Available_Stock__c(
                Name = 'Stock ' + phase.Name,
                Project_Phase__c = phase.Id,
                Available_Quantity__c = 100,
                Used_Quantity__c = 30,
                Return_Item_Quantity__c = 10
            ));
        }
        insert stocks;
    }
    
    @isTest
    static void testGetProjects() {
        Test.startTest();
        List<InventoryDashboardController.ProjectWrapper> projects = 
            InventoryDashboardController.getProjects();
        Test.stopTest();
        
        System.assertNotEquals(null, projects, 'Projects should not be null');
        System.assertEquals(1, projects.size(), 'Should return 1 project');
        System.assertEquals('Test Project', projects[0].name, 'Project name should match');
    }
    
    @isTest
    static void testGetDashboardData() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        
        Test.startTest();
        InventoryDashboardController.DashboardData data = 
            InventoryDashboardController.getDashboardData(project.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, data, 'Dashboard data should not be null');
        System.assertEquals(3, data.phaseSummaries.size(), 'Should have 3 phase summaries');
        System.assertEquals(300, data.totalAvailable, 'Total available should be 300');
        System.assertEquals(90, data.totalUsed, 'Total used should be 90');
        System.assertEquals(30, data.totalReturned, 'Total returned should be 30');
    }
    
    @isTest
    static void testGetDashboardDataWithNullProjectId() {
        Boolean exceptionCaught = false;
        
        Test.startTest();
        try {
            InventoryDashboardController.getDashboardData(null);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assert(e.getMessage().contains('Project ID is required'), 
                'Error message should mention Project ID');
        }
        Test.stopTest();
        
        System.assert(exceptionCaught, 'Exception should be thrown for null project ID');
    }
}