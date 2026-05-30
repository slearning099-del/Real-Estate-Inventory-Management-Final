/**
 * @description Test class for ProjectPhaseTowerWizardController.
 *              Covers all methods including bulk creation up to 200 towers.
 */
@isTest
private class ProjectPhaseTowerWizardControllerTest {

    // ─────────────────────────────────────────────────────────────
    //  Test data setup
    // ─────────────────────────────────────────────────────────────
    @TestSetup
    static void setupTestData() {
        Project__c project = new Project__c(Name = 'Test Project');
        insert project;

        Project_Phase__c phase = new Project_Phase__c(
            Name                = 'Test Phase',
            Project__c          = project.Id,
            Phase_Status__c     = 'Planning',
            Budget__c           = 1000000,
            Phase_Start_Date__c = Date.today(),
            Phase_End_Date__c   = Date.today().addDays(90)
        );
        insert phase;
    }

    // ─────────────────────────────────────────────────────────────
    //  getProjectPhaseDetails
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void testGetProjectPhaseDetails_Success() {
        Project_Phase__c phase = [SELECT Id FROM Project_Phase__c LIMIT 1];

        Test.startTest();
        Project_Phase__c result =
            ProjectPhaseTowerWizardController.getProjectPhaseDetails(phase.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,              'Phase should be returned');
        System.assertEquals('Test Phase',    result.Name, 'Name should match');
        System.assertEquals('Test Project',  result.Project__r.Name, 'Project name should match');
        System.assertEquals('Planning',      result.Phase_Status__c, 'Status should match');
        System.assertEquals(1000000,         result.Budget__c,       'Budget should match');
    }

    @isTest
    static void testGetProjectPhaseDetails_NullId() {
        Test.startTest();
        try {
            ProjectPhaseTowerWizardController.getProjectPhaseDetails(null);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), 'Should mention required');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetProjectPhaseDetails_NotFound() {
        Id fakeId = 'a00000000000000AAA';
        Test.startTest();
        try {
            ProjectPhaseTowerWizardController.getProjectPhaseDetails(fakeId);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not found'), 'Should mention not found');
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────
    //  checkExistingTowers
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void testCheckExistingTowers_None() {
        Project_Phase__c phase = [SELECT Id FROM Project_Phase__c LIMIT 1];

        Test.startTest();
        Boolean result = ProjectPhaseTowerWizardController.checkExistingTowers(phase.Id);
        Test.stopTest();

        System.assertEquals(false, result, 'Should be false when no towers exist');
    }

    @isTest
    static void testCheckExistingTowers_Exist() {
        Project_Phase__c phase = [SELECT Id, Project__c FROM Project_Phase__c LIMIT 1];
        insert new Tower__c(
            Name             = 'Existing Tower',
            Project__c       = phase.Project__c,
            Project_Phase__c = phase.Id,
            Status__c        = 'Planning'
        );

        Test.startTest();
        Boolean result = ProjectPhaseTowerWizardController.checkExistingTowers(phase.Id);
        Test.stopTest();

        System.assertEquals(true, result, 'Should be true when towers exist');
    }

    @isTest
    static void testCheckExistingTowers_NullId() {
        Test.startTest();
        try {
            ProjectPhaseTowerWizardController.checkExistingTowers(null);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), 'Should mention required');
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────
    //  createTowers — happy paths
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void testCreateTowers_Single() {
        Project_Phase__c phase = [SELECT Id, Project__c FROM Project_Phase__c LIMIT 1];

        List<Tower__c> towers = new List<Tower__c>{
            new Tower__c(
                Name             = 'Tower A',
                Project__c       = phase.Project__c,
                Project_Phase__c = phase.Id,
                Status__c        = 'Planning'
            )
        };

        Test.startTest();
        ProjectPhaseTowerWizardController.TowerCreationResult result =
            ProjectPhaseTowerWizardController.createTowers(towers);
        Test.stopTest();

        System.assertEquals(true,  result.success,      'Should succeed');
        System.assertEquals(1,     result.successCount, 'Should create 1 tower');
        System.assertEquals(0,     result.errorCount,   'Should have 0 errors');
        System.assertEquals(1, [SELECT COUNT() FROM Tower__c], 'DB should have 1 tower');
    }

    @isTest
    static void testCreateTowers_Multiple() {
        Project_Phase__c phase = [SELECT Id, Project__c FROM Project_Phase__c LIMIT 1];

        List<Tower__c> towers = new List<Tower__c>();
        for (Integer i = 1; i <= 5; i++) {
            towers.add(new Tower__c(
                Name             = 'Tower ' + i,
                Project__c       = phase.Project__c,
                Project_Phase__c = phase.Id,
                Status__c        = 'Planning'
            ));
        }

        Test.startTest();
        ProjectPhaseTowerWizardController.TowerCreationResult result =
            ProjectPhaseTowerWizardController.createTowers(towers);
        Test.stopTest();

        System.assertEquals(true, result.success,      'Should succeed');
        System.assertEquals(5,    result.successCount, 'Should create 5 towers');
        System.assertEquals(5, [SELECT COUNT() FROM Tower__c], 'DB should have 5 towers');
    }

    @isTest
    static void testCreateTowers_DifferentStatuses() {
        Project_Phase__c phase = [SELECT Id, Project__c FROM Project_Phase__c LIMIT 1];

        List<Tower__c> towers = new List<Tower__c>{
            new Tower__c(Name='T1', Project__c=phase.Project__c, Project_Phase__c=phase.Id, Status__c='Planning'),
            new Tower__c(Name='T2', Project__c=phase.Project__c, Project_Phase__c=phase.Id, Status__c='Finishing Stage'),
            new Tower__c(Name='T3', Project__c=phase.Project__c, Project_Phase__c=phase.Id, Status__c='Ready For possession'),
            new Tower__c(Name='T4', Project__c=phase.Project__c, Project_Phase__c=phase.Id, Status__c='Handover Progress'),
            new Tower__c(Name='T5', Project__c=phase.Project__c, Project_Phase__c=phase.Id, Status__c='On Hold')
        };

        Test.startTest();
        ProjectPhaseTowerWizardController.TowerCreationResult result =
            ProjectPhaseTowerWizardController.createTowers(towers);
        Test.stopTest();

        System.assertEquals(true, result.success,      'Should succeed');
        System.assertEquals(5,    result.successCount, 'Should create 5 towers');
    }

    // ─────────────────────────────────────────────────────────────
    //  createTowers — bulk (200 towers, tests chunked DML)
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void testCreateTowers_Bulk200() {
        Project_Phase__c phase = [SELECT Id, Project__c FROM Project_Phase__c LIMIT 1];

        List<Tower__c> towers = new List<Tower__c>();
        for (Integer i = 1; i <= 200; i++) {
            towers.add(new Tower__c(
                Name             = 'Tower ' + String.valueOf(i).leftPad(3, '0'),
                Project__c       = phase.Project__c,
                Project_Phase__c = phase.Id,
                Status__c        = 'Planning'
            ));
        }

        Test.startTest();
        ProjectPhaseTowerWizardController.TowerCreationResult result =
            ProjectPhaseTowerWizardController.createTowers(towers);
        Test.stopTest();

        System.assertEquals(true,  result.success,      'Should succeed for 200 towers');
        System.assertEquals(200,   result.successCount, 'Should create 200 towers');
        System.assertEquals(0,     result.errorCount,   'Should have 0 errors');
        System.assertEquals(200, [SELECT COUNT() FROM Tower__c], 'DB should have 200 towers');
    }

    // ─────────────────────────────────────────────────────────────
    //  createTowers — error paths
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void testCreateTowers_NullList() {
        Test.startTest();
        try {
            ProjectPhaseTowerWizardController.createTowers(null);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('No towers'), 'Should mention no towers');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateTowers_EmptyList() {
        Test.startTest();
        try {
            ProjectPhaseTowerWizardController.createTowers(new List<Tower__c>());
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('No towers'), 'Should mention no towers');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateTowers_ExceedsMax() {
        Project_Phase__c phase = [SELECT Id, Project__c FROM Project_Phase__c LIMIT 1];

        List<Tower__c> towers = new List<Tower__c>();
        for (Integer i = 1; i <= 201; i++) {
            towers.add(new Tower__c(
                Name             = 'Tower ' + i,
                Project__c       = phase.Project__c,
                Project_Phase__c = phase.Id,
                Status__c        = 'Planning'
            ));
        }

        Test.startTest();
        try {
            ProjectPhaseTowerWizardController.createTowers(towers);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('200'), 'Should mention 200 limit');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateTowers_MissingName() {
        Project_Phase__c phase = [SELECT Id, Project__c FROM Project_Phase__c LIMIT 1];

        List<Tower__c> towers = new List<Tower__c>{
            new Tower__c(Project__c=phase.Project__c, Project_Phase__c=phase.Id, Status__c='Planning')
        };

        Test.startTest();
        try {
            ProjectPhaseTowerWizardController.createTowers(towers);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Name'), 'Should mention Name');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateTowers_MissingProjectPhase() {
        Project_Phase__c phase = [SELECT Id, Project__c FROM Project_Phase__c LIMIT 1];

        List<Tower__c> towers = new List<Tower__c>{
            new Tower__c(Name='T1', Project__c=phase.Project__c, Status__c='Planning')
        };

        Test.startTest();
        try {
            ProjectPhaseTowerWizardController.createTowers(towers);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Project Phase'), 'Should mention Project Phase');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateTowers_AlreadyExist() {
        Project_Phase__c phase = [SELECT Id, Project__c FROM Project_Phase__c LIMIT 1];
        insert new Tower__c(
            Name='Existing', Project__c=phase.Project__c,
            Project_Phase__c=phase.Id, Status__c='Planning'
        );

        List<Tower__c> towers = new List<Tower__c>{
            new Tower__c(Name='New', Project__c=phase.Project__c,
                         Project_Phase__c=phase.Id, Status__c='Planning')
        };

        Test.startTest();
        try {
            ProjectPhaseTowerWizardController.createTowers(towers);
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('already exist'), 'Should mention already exist');
        }
        Test.stopTest();
    }
}