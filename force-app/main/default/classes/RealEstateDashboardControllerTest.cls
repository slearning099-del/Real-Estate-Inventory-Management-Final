/**
 * @description Test class for RealEstateDashboardController.
 *              Covers all public methods with positive, negative, and
 *              boundary-condition scenarios.
 *
 * @author  RealEstate Dev Team
 * @version 1.0
 */
@IsTest
private class RealEstateDashboardControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    //  TEST DATA SETUP
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        // Project
        Project__c proj = new Project__c(
            Name           = 'Test Project',
            Project_Status__c = 'In Progress'
        );
        insert proj;

        // Project Phase
        Project_Phase__c phase = new Project_Phase__c(
            Name       = 'Phase 1',
            Project__c = proj.Id,
            Phase_Status__c = 'In Progress'
        );
        insert phase;

        // Towers
        List<Tower__c> towers = new List<Tower__c>();
        for (Integer i = 1; i <= 3; i++) {
            towers.add(new Tower__c(
                Name              = 'Tower ' + i,
                Project__c        = proj.Id,
                Project_Phase__c  = phase.Id,
                Status__c         = 'Planning'
            ));
        }
        insert towers;

        // Property Units – spread across towers with different statuses
        List<Property_Unit__c> units = new List<Property_Unit__c>();
        String[] statuses = new String[]{ 'Sold', 'Available', 'Hold', 'Booked', 'Reserved' };
        Integer idx = 0;
        for (Tower__c t : towers) {
            for (Integer u = 0; u < 10; u++) {
                units.add(new Property_Unit__c(
                    Name                   = t.Name + '-Unit-' + u,
                    Tower__c               = t.Id,
                    Property_unit_Status__c = statuses[Math.mod(idx++, statuses.size())]
                ));
            }
        }
        insert units;

        // Sub Units
        List<Sub_Unit__c> subUnits = new List<Sub_Unit__c>();
        for (Property_Unit__c pu : units) {
            subUnits.add(new Sub_Unit__c(
                Name             = pu.Name + '-SU',
                Property_Unit__c = pu.Id,
                Tower__c         = pu.Tower__c,
                Sub_Unit_Status__c = 'Available'
            ));
        }
        insert subUnits;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getDashboardData – no filters
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetDashboardData_noFilters() {
        Test.startTest();
        RealEstateDashboardController.DashboardPayload payload =
            RealEstateDashboardController.getDashboardData(null, null, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assertNotEquals(null, payload.summary, 'Summary should not be null');
        System.assertNotEquals(null, payload.kpi, 'KPI should not be null');
        System.assertNotEquals(null, payload.towerInventory, 'Tower inventory should not be null');

        // Summary counts
        System.assertEquals(1, payload.summary.totalProjects,      'Should have 1 project');
        System.assertEquals(1, payload.summary.totalPhases,        'Should have 1 phase');
        System.assertEquals(3, payload.summary.totalTowers,        'Should have 3 towers');
        System.assertEquals(30, payload.summary.totalPropertyUnits,'Should have 30 property units');
        System.assertEquals(30, payload.summary.totalSubUnits,     'Should have 30 sub units');

        // KPI totals
        System.assertEquals(30, payload.kpi.totalInventory, 'Total inventory should be 30');
        System.assert(payload.kpi.totalSold > 0,      'Should have sold units');
        System.assert(payload.kpi.totalAvailable > 0, 'Should have available units');
        System.assert(payload.kpi.salesPercentage >= 0, 'Sales % should be non-negative');

        // Tower inventory chart data
        System.assertEquals(3, payload.towerInventory.size(), 'Should have 3 tower rows');

        // Filter options
        System.assert(payload.projectOptions.size() >= 2,      'Should have project options');
        System.assert(payload.projectPhaseOptions.size() >= 2, 'Should have phase options');
        System.assert(payload.towerOptions.size() >= 2,        'Should have tower options');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getDashboardData – filtered by project
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetDashboardData_filteredByProject() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        RealEstateDashboardController.DashboardPayload payload =
            RealEstateDashboardController.getDashboardData(proj.Id, null, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assertEquals(30, payload.kpi.totalInventory, 'All 30 units belong to this project');
        System.assertEquals(3, payload.towerInventory.size(), 'Should have 3 towers for this project');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getDashboardData – filtered by project phase
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetDashboardData_filteredByPhase() {
        Project_Phase__c phase = [SELECT Id FROM Project_Phase__c LIMIT 1];

        Test.startTest();
        RealEstateDashboardController.DashboardPayload payload =
            RealEstateDashboardController.getDashboardData(null, phase.Id, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assertEquals(30, payload.kpi.totalInventory, 'All 30 units belong to this phase');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getDashboardData – filtered by tower
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetDashboardData_filteredByTower() {
        Tower__c tower = [SELECT Id FROM Tower__c LIMIT 1];

        Test.startTest();
        RealEstateDashboardController.DashboardPayload payload =
            RealEstateDashboardController.getDashboardData(null, null, tower.Id, null, null);
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assertEquals(10, payload.kpi.totalInventory, '10 units per tower');
        System.assertEquals(1, payload.towerInventory.size(), 'Should have 1 tower row');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getDashboardData – date range filter
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetDashboardData_dateRangeFilter() {
        Date today = Date.today();

        Test.startTest();
        RealEstateDashboardController.DashboardPayload payload =
            RealEstateDashboardController.getDashboardData(
                null, null, null,
                today.addDays(-1),
                today.addDays(1)
            );
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null');
        // All test records created today – should be within range
        System.assertEquals(30, payload.kpi.totalInventory, 'All 30 units within date range');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getDashboardData – date range excludes all records
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetDashboardData_dateRangeExcludesAll() {
        Date pastDate = Date.today().addDays(-365);

        Test.startTest();
        RealEstateDashboardController.DashboardPayload payload =
            RealEstateDashboardController.getDashboardData(
                null, null, null,
                pastDate.addDays(-10),
                pastDate.addDays(-5)
            );
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assertEquals(0, payload.kpi.totalInventory, 'No units in past date range');
        System.assertEquals(0, payload.towerInventory.size(), 'No tower rows when no units');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getPhasesByProject
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetPhasesByProject() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        List<RealEstateDashboardController.PicklistOption> opts =
            RealEstateDashboardController.getPhasesByProject(proj.Id);
        Test.stopTest();

        // Should have "All Phases" + 1 phase
        System.assertEquals(2, opts.size(), 'Should have 2 options (all + 1 phase)');
        System.assertEquals('', opts[0].value, 'First option should be blank (All)');
    }

    @IsTest
    static void testGetPhasesByProject_nullProject() {
        Test.startTest();
        List<RealEstateDashboardController.PicklistOption> opts =
            RealEstateDashboardController.getPhasesByProject(null);
        Test.stopTest();

        // Should return all phases + "All" option
        System.assert(opts.size() >= 2, 'Should return all phases when no project filter');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  getTowersByPhase
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetTowersByPhase() {
        Project_Phase__c phase = [SELECT Id, Project__c FROM Project_Phase__c LIMIT 1];

        Test.startTest();
        List<RealEstateDashboardController.PicklistOption> opts =
            RealEstateDashboardController.getTowersByPhase(phase.Project__c, phase.Id);
        Test.stopTest();

        // Should have "All Towers" + 3 towers
        System.assertEquals(4, opts.size(), 'Should have 4 options (all + 3 towers)');
    }

    @IsTest
    static void testGetTowersByPhase_nullFilters() {
        Test.startTest();
        List<RealEstateDashboardController.PicklistOption> opts =
            RealEstateDashboardController.getTowersByPhase(null, null);
        Test.stopTest();

        System.assert(opts.size() >= 4, 'Should return all towers when no filter');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  KPI sales percentage calculation
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSalesPercentageCalculation() {
        Test.startTest();
        RealEstateDashboardController.DashboardPayload payload =
            RealEstateDashboardController.getDashboardData(null, null, null, null, null);
        Test.stopTest();

        Decimal expectedPct = ((Decimal) payload.kpi.totalSold / payload.kpi.totalInventory * 100)
            .setScale(1);
        System.assertEquals(
            expectedPct,
            payload.kpi.salesPercentage,
            'Sales percentage should match manual calculation'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Tower inventory sort order
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testTowerInventorySortOrder() {
        Test.startTest();
        RealEstateDashboardController.DashboardPayload payload =
            RealEstateDashboardController.getDashboardData(null, null, null, null, null);
        Test.stopTest();

        List<RealEstateDashboardController.TowerInventory> inv = payload.towerInventory;
        for (Integer i = 0; i < inv.size() - 1; i++) {
            System.assert(
                inv[i].towerName.toLowerCase() <= inv[i + 1].towerName.toLowerCase(),
                'Tower inventory should be sorted alphabetically'
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Tower totals consistency
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testTowerTotalsConsistency() {
        Test.startTest();
        RealEstateDashboardController.DashboardPayload payload =
            RealEstateDashboardController.getDashboardData(null, null, null, null, null);
        Test.stopTest();

        for (RealEstateDashboardController.TowerInventory ti : payload.towerInventory) {
            Integer sumParts = ti.soldFlats + ti.availableFlats + ti.holdFlats + ti.bookedFlats;
            System.assertEquals(
                ti.totalFlats,
                sumParts,
                'Tower total should equal sum of status buckets for ' + ti.towerName
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Empty org scenario (no data)
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testEmptyOrgScenario() {
        // Delete all test data to simulate empty org
        delete [SELECT Id FROM Sub_Unit__c];
        delete [SELECT Id FROM Property_Unit__c];
        delete [SELECT Id FROM Tower__c];
        delete [SELECT Id FROM Project_Phase__c];
        delete [SELECT Id FROM Project__c];

        Test.startTest();
        RealEstateDashboardController.DashboardPayload payload =
            RealEstateDashboardController.getDashboardData(null, null, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null even with no data');
        System.assertEquals(0, payload.summary.totalProjects,      'No projects');
        System.assertEquals(0, payload.kpi.totalInventory,         'No inventory');
        System.assertEquals(0, payload.towerInventory.size(),      'No tower rows');
        System.assertEquals(0, payload.kpi.salesPercentage,        'Sales % should be 0');
    }
}