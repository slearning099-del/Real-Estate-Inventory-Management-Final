/**
 * @description Apex controller for the Real Estate CRM Dashboard LWC.
 *              Provides aggregated statistics for Projects, Phases, Towers,
 *              Property Units, and Sub Units using efficient aggregate SOQL.
 *
 * Objects used (existing org API names):
 *   Project__c, Project_Phase__c, Tower__c, Property_Unit__c, Sub_Unit__c
 *
 * Property_unit_Status__c picklist: Available, Hold, Reserved, Booked, Sold
 * Sub_Unit_Status__c picklist:      Available, Hold, Booked
 *
 * @author  RealEstate Dev Team
 * @version 1.0
 */
public with sharing class RealEstateDashboardController {

    // ─────────────────────────────────────────────────────────────────────────
    //  PUBLIC ENTRY POINT  –  single server call returns everything
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Returns the complete dashboard payload in one round-trip.
     *              Marked cacheable=true so the LWC wire adapter caches the
     *              result and avoids redundant server calls.
     *
     * @param projectId      Optional – filter by Project__c Id
     * @param projectPhaseId Optional – filter by Project_Phase__c Id
     * @param towerId        Optional – filter by Tower__c Id
     * @param startDate      Optional – filter Property_Unit__c by CreatedDate >=
     * @param endDate        Optional – filter Property_Unit__c by CreatedDate <=
     * @return               DashboardPayload wrapper
     */
    @AuraEnabled(cacheable=true)
    public static DashboardPayload getDashboardData(
        Id      projectId,
        Id      projectPhaseId,
        Id      towerId,
        Date    startDate,
        Date    endDate
    ) {
        try {
            DashboardPayload payload = new DashboardPayload();

            // ── Summary counts (no filters – always show org-wide totals) ──
            payload.summary = buildSummary();

            // ── KPI cards (respect all filters) ──────────────────────────
            payload.kpi = buildKpi(projectId, projectPhaseId, towerId, startDate, endDate);

            // ── Tower-wise inventory (respect project / phase filters) ────
            payload.towerInventory = buildTowerInventory(projectId, projectPhaseId, towerId);

            // ── Filter picklist options ───────────────────────────────────
            payload.projectOptions      = getProjectOptions();
            payload.projectPhaseOptions = getProjectPhaseOptions(projectId);
            payload.towerOptions        = getTowerOptions(projectId, projectPhaseId);

            return payload;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Dashboard data load failed: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Lazy-loads Project Phase options when a Project is selected.
     *              Separate cacheable call to avoid re-fetching the full payload.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPhasesByProject(Id projectId) {
        return getProjectPhaseOptions(projectId);
    }

    /**
     * @description Lazy-loads Tower options when a Project / Phase is selected.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getTowersByPhase(Id projectId, Id projectPhaseId) {
        return getTowerOptions(projectId, projectPhaseId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  PRIVATE HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /** Org-wide record counts – no filters applied */
    private static SummaryStats buildSummary() {
        SummaryStats s = new SummaryStats();

        s.totalProjects      = [SELECT COUNT() FROM Project__c      WITH SECURITY_ENFORCED];
        s.totalPhases        = [SELECT COUNT() FROM Project_Phase__c WITH SECURITY_ENFORCED];
        s.totalTowers        = [SELECT COUNT() FROM Tower__c         WITH SECURITY_ENFORCED];
        s.totalPropertyUnits = [SELECT COUNT() FROM Property_Unit__c WITH SECURITY_ENFORCED];
        s.totalSubUnits      = [SELECT COUNT() FROM Sub_Unit__c      WITH SECURITY_ENFORCED];

        return s;
    }

    /** KPI aggregates filtered by project / phase / tower / date range */
    private static KpiStats buildKpi(
        Id   projectId,
        Id   projectPhaseId,
        Id   towerId,
        Date startDate,
        Date endDate
    ) {
        KpiStats kpi = new KpiStats();

        // Build dynamic WHERE clause for Property_Unit__c
        String whereClause = buildPropertyUnitWhere(
            projectId, projectPhaseId, towerId, startDate, endDate
        );

        // Aggregate query – one SOQL for all KPI counts
        String soql =
            'SELECT Property_unit_Status__c status, COUNT(Id) cnt ' +
            'FROM Property_Unit__c ' +
            (String.isBlank(whereClause) ? '' : 'WHERE ' + whereClause + ' ') +
            'WITH SECURITY_ENFORCED ' +
            'GROUP BY Property_unit_Status__c';

        Integer total = 0;
        for (AggregateResult ar : Database.query(soql)) {
            String  status = (String)  ar.get('status');
            Integer cnt    = (Integer) ar.get('cnt');
            total += cnt;

            if (status == 'Sold') {
                kpi.totalSold += cnt;
            } else if (status == 'Available') {
                kpi.totalAvailable += cnt;
            } else if (status == 'Hold') {
                kpi.totalHold += cnt;
            } else if (status == 'Booked' || status == 'Reserved') {
                kpi.totalBooked += cnt;
            }
        }

        kpi.totalInventory = total;
        kpi.salesPercentage = total > 0
            ? ((Decimal) kpi.totalSold / total * 100).setScale(1)
            : 0;

        return kpi;
    }

    /** Per-tower inventory breakdown */
    private static List<TowerInventory> buildTowerInventory(
        Id projectId,
        Id projectPhaseId,
        Id towerId
    ) {
        // Build WHERE for Property_Unit__c (no date filter for chart)
        String whereClause = buildPropertyUnitWhere(projectId, projectPhaseId, towerId, null, null);

        String soql =
            'SELECT Tower__c towerId, Tower__r.Name towerName, ' +
            '       Property_unit_Status__c status, COUNT(Id) cnt ' +
            'FROM Property_Unit__c ' +
            (String.isBlank(whereClause) ? '' : 'WHERE ' + whereClause + ' ') +
            'WITH SECURITY_ENFORCED ' +
            'GROUP BY Tower__c, Tower__r.Name, Property_unit_Status__c ' +
            'ORDER BY Tower__r.Name';

        // Aggregate into a map keyed by Tower Id
        Map<Id, TowerInventory> towerMap = new Map<Id, TowerInventory>();

        for (AggregateResult ar : Database.query(soql)) {
            Id      tId    = (Id)      ar.get('towerId');
            String  tName  = (String)  ar.get('towerName');
            String  status = (String)  ar.get('status');
            Integer cnt    = (Integer) ar.get('cnt');

            if (tId == null) continue;

            TowerInventory ti = towerMap.get(tId);
            if (ti == null) {
                ti          = new TowerInventory();
                ti.towerId  = tId;
                ti.towerName = tName != null ? tName : 'Unknown Tower';
                towerMap.put(tId, ti);
            }

            ti.totalFlats += cnt;

            if (status == 'Sold') {
                ti.soldFlats += cnt;
            } else if (status == 'Available') {
                ti.availableFlats += cnt;
            } else if (status == 'Hold') {
                ti.holdFlats += cnt;
            } else if (status == 'Booked' || status == 'Reserved') {
                ti.bookedFlats += cnt;
            }
        }

        // Sort by tower name
        List<TowerInventory> result = new List<TowerInventory>(towerMap.values());
        result.sort();
        return result;
    }

    /** Builds a safe WHERE clause string for Property_Unit__c queries */
    private static String buildPropertyUnitWhere(
        Id   projectId,
        Id   projectPhaseId,
        Id   towerId,
        Date startDate,
        Date endDate
    ) {
        List<String> conditions = new List<String>();

        if (towerId != null) {
            conditions.add('Tower__c = \'' + String.escapeSingleQuotes(towerId) + '\'');
        } else if (projectPhaseId != null) {
            // Property_Unit__c → Tower__c → Project_Phase__c
            conditions.add(
                'Tower__r.Project_Phase__c = \'' +
                String.escapeSingleQuotes(projectPhaseId) + '\''
            );
        } else if (projectId != null) {
            conditions.add(
                'Tower__r.Project__c = \'' +
                String.escapeSingleQuotes(projectId) + '\''
            );
        }

        if (startDate != null) {
            conditions.add('CreatedDate >= ' + startDate.format() + 'T00:00:00Z');
        }
        if (endDate != null) {
            conditions.add('CreatedDate <= ' + endDate.format() + 'T23:59:59Z');
        }

        return String.join(conditions, ' AND ');
    }

    /** Project picklist options */
    private static List<PicklistOption> getProjectOptions() {
        List<PicklistOption> opts = new List<PicklistOption>();
        opts.add(new PicklistOption('', '-- All Projects --'));
        for (Project__c p : [
            SELECT Id, Name
            FROM   Project__c
            WITH   SECURITY_ENFORCED
            ORDER  BY Name
            LIMIT  200
        ]) {
            opts.add(new PicklistOption(p.Id, p.Name));
        }
        return opts;
    }

    /** Project Phase picklist options, optionally filtered by project */
    private static List<PicklistOption> getProjectPhaseOptions(Id projectId) {
        List<PicklistOption> opts = new List<PicklistOption>();
        opts.add(new PicklistOption('', '-- All Phases --'));

        String soql =
            'SELECT Id, Name FROM Project_Phase__c ' +
            (projectId != null
                ? 'WHERE Project__c = \'' + String.escapeSingleQuotes(projectId) + '\' '
                : '') +
            'WITH SECURITY_ENFORCED ORDER BY Name LIMIT 200';

        for (SObject rec : Database.query(soql)) {
            opts.add(new PicklistOption((Id) rec.get('Id'), (String) rec.get('Name')));
        }
        return opts;
    }

    /** Tower picklist options, optionally filtered by project and/or phase */
    private static List<PicklistOption> getTowerOptions(Id projectId, Id projectPhaseId) {
        List<PicklistOption> opts = new List<PicklistOption>();
        opts.add(new PicklistOption('', '-- All Towers --'));

        List<String> conditions = new List<String>();
        if (projectPhaseId != null) {
            conditions.add(
                'Project_Phase__c = \'' + String.escapeSingleQuotes(projectPhaseId) + '\''
            );
        } else if (projectId != null) {
            conditions.add(
                'Project__c = \'' + String.escapeSingleQuotes(projectId) + '\''
            );
        }

        String whereStr = conditions.isEmpty() ? '' : 'WHERE ' + String.join(conditions, ' AND ') + ' ';
        String soql =
            'SELECT Id, Name FROM Tower__c ' + whereStr +
            'WITH SECURITY_ENFORCED ORDER BY Name LIMIT 200';

        for (SObject rec : Database.query(soql)) {
            opts.add(new PicklistOption((Id) rec.get('Id'), (String) rec.get('Name')));
        }
        return opts;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  WRAPPER CLASSES
    // ─────────────────────────────────────────────────────────────────────────

    /** Root payload returned to the LWC */
    public class DashboardPayload {
        @AuraEnabled public SummaryStats          summary;
        @AuraEnabled public KpiStats              kpi;
        @AuraEnabled public List<TowerInventory>  towerInventory;
        @AuraEnabled public List<PicklistOption>  projectOptions;
        @AuraEnabled public List<PicklistOption>  projectPhaseOptions;
        @AuraEnabled public List<PicklistOption>  towerOptions;
    }

    /** Org-wide record counts */
    public class SummaryStats {
        @AuraEnabled public Integer totalProjects      = 0;
        @AuraEnabled public Integer totalPhases        = 0;
        @AuraEnabled public Integer totalTowers        = 0;
        @AuraEnabled public Integer totalPropertyUnits = 0;
        @AuraEnabled public Integer totalSubUnits      = 0;
    }

    /** KPI card values */
    public class KpiStats {
        @AuraEnabled public Integer totalInventory = 0;
        @AuraEnabled public Integer totalSold      = 0;
        @AuraEnabled public Integer totalAvailable = 0;
        @AuraEnabled public Integer totalHold      = 0;
        @AuraEnabled public Integer totalBooked    = 0;
        @AuraEnabled public Decimal salesPercentage = 0;
    }

    /** Per-tower inventory row (also used as chart data) */
    public class TowerInventory implements Comparable {
        @AuraEnabled public Id      towerId;
        @AuraEnabled public String  towerName;
        @AuraEnabled public Integer totalFlats     = 0;
        @AuraEnabled public Integer soldFlats      = 0;
        @AuraEnabled public Integer availableFlats = 0;
        @AuraEnabled public Integer holdFlats      = 0;
        @AuraEnabled public Integer bookedFlats    = 0;

        public Integer compareTo(Object other) {
            TowerInventory o = (TowerInventory) other;
            if (o == null) return -1;
            String a = this.towerName == null ? '' : this.towerName;
            String b = o.towerName   == null ? '' : o.towerName;
            return a.toLowerCase().compareTo(b.toLowerCase());
        }
    }

    /**
     * @description Fetches Property_Unit__c records for the drill-down modal.
     *              Filtered by tower + status. Returns up to 200 rows.
     *
     * @param towerId  Tower__c Id
     * @param status   Property_unit_Status__c value (e.g. 'Sold', 'Available')
     * @return         List of UnitRow wrappers
     */
    @AuraEnabled(cacheable=true)
    public static List<UnitRow> getUnitsByTowerAndStatus(Id towerId, String status) {
        if (towerId == null) {
            throw new AuraHandledException('Tower Id is required.');
        }
        try {
            List<String> conditions = new List<String>();
            conditions.add('Tower__c = :towerId');
            if (String.isNotBlank(status)) {
                conditions.add('Property_unit_Status__c = :status');
            }

            String soql =
                'SELECT Id, Name, Property_unit_Status__c, Area_SQFt__c, ' +
                '       Base_Price__c, Final_Amount__c, Unit_View_Type__c, ' +
                '       Property_Unit_Code__c ' +
                'FROM Property_Unit__c ' +
                'WHERE ' + String.join(conditions, ' AND ') + ' ' +
                'WITH SECURITY_ENFORCED ' +
                'ORDER BY Name ' +
                'LIMIT 200';

            List<UnitRow> rows = new List<UnitRow>();
            for (Property_Unit__c u : (List<Property_Unit__c>) Database.query(soql)) {
                UnitRow row      = new UnitRow();
                row.id           = u.Id;
                row.name         = u.Name;
                row.unitCode     = u.Property_Unit_Code__c;
                row.status       = u.Property_unit_Status__c;
                row.areaSqft     = u.Area_SQFt__c;
                row.basePrice    = u.Base_Price__c;
                row.finalAmount  = u.Final_Amount__c;
                row.viewType     = u.Unit_View_Type__c;
                rows.add(row);
            }
            return rows;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading units: ' + e.getMessage());
        }
    }

    /** Lightweight unit row for the drill-down modal */
    public class UnitRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  unitCode;
        @AuraEnabled public String  status;
        @AuraEnabled public Decimal areaSqft;
        @AuraEnabled public Decimal basePrice;
        @AuraEnabled public Decimal finalAmount;
        @AuraEnabled public String  viewType;
    }

    /** Generic label/value pair for filter dropdowns */
    public class PicklistOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;

        public PicklistOption(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }
}