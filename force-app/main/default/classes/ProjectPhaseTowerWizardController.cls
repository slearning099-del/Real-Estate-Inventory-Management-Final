/**
 * @description Controller for Project Phase Tower Wizard LWC.
 *              Supports bulk creation of up to 200 Tower__c records
 *              using chunked DML to stay within governor limits.
 * @author      RealEstate Dev Team
 */
public with sharing class ProjectPhaseTowerWizardController {

    /** Maximum towers per single DML chunk (well below the 10 000 row limit) */
    private static final Integer CHUNK_SIZE = 200;

    /** Hard cap exposed to the UI */
    public static final Integer MAX_TOWERS = 200;

    // ─────────────────────────────────────────────────────────────
    //  getProjectPhaseDetails
    // ─────────────────────────────────────────────────────────────
    /**
     * @description Returns Project Phase with its parent Project details.
     *              Marked cacheable=true so the LWC wire cache is used on
     *              repeated opens without an extra server round-trip.
     */
    @AuraEnabled(cacheable=true)
    public static Project_Phase__c getProjectPhaseDetails(Id projectPhaseId) {
        if (projectPhaseId == null) {
            throw new AuraHandledException('Project Phase Id is required.');
        }
        try {
            List<Project_Phase__c> phases = [
                SELECT  Id,
                        Name,
                        Project__c,
                        Project__r.Id,
                        Project__r.Name,
                        Phase_Status__c,
                        Budget__c,
                        Phase_Start_Date__c,
                        Phase_End_Date__c,
                        Project_Phase_Code__c
                FROM    Project_Phase__c
                WHERE   Id = :projectPhaseId
                WITH    SECURITY_ENFORCED
                LIMIT   1
            ];
            if (phases.isEmpty()) {
                throw new AuraHandledException('Project Phase record not found.');
            }
            return phases[0];
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading Project Phase: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────
    //  checkExistingTowers
    // ─────────────────────────────────────────────────────────────
    /**
     * @description Returns true when at least one Tower__c already exists
     *              for the given Project Phase (one-time-use guard).
     */
    @AuraEnabled(cacheable=true)
    public static Boolean checkExistingTowers(Id projectPhaseId) {
        if (projectPhaseId == null) {
            throw new AuraHandledException('Project Phase Id is required.');
        }
        try {
            return ([
                SELECT COUNT()
                FROM   Tower__c
                WHERE  Project_Phase__c = :projectPhaseId
                WITH   SECURITY_ENFORCED
            ] > 0);
        } catch (Exception e) {
            throw new AuraHandledException('Error checking existing towers: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────
    //  createTowers  (chunked bulk insert, up to 200 records)
    // ─────────────────────────────────────────────────────────────
    /**
     * @description Bulk-inserts Tower__c records in chunks of CHUNK_SIZE.
     *              Accepts up to MAX_TOWERS (200) towers per call.
     *              Returns a TowerCreationResult with success count and
     *              any per-row error messages.
     *
     * @param  towers  Serialised list of Tower__c sObjects from the LWC.
     * @return         TowerCreationResult wrapper.
     */
    @AuraEnabled
    public static TowerCreationResult createTowers(List<Tower__c> towers) {
        // ── Input guards ──────────────────────────────────────────
        if (towers == null || towers.isEmpty()) {
            throw new AuraHandledException('No towers provided for creation.');
        }
        if (towers.size() > MAX_TOWERS) {
            throw new AuraHandledException(
                'Cannot create more than ' + MAX_TOWERS + ' towers at once.'
            );
        }

        // ── Field-level validation (no SOQL in loop) ─────────────
        List<String> validationErrors = new List<String>();
        Set<Id>      phaseIds         = new Set<Id>();

        for (Integer i = 0; i < towers.size(); i++) {
            Tower__c t = towers[i];
            if (String.isBlank(t.Name)) {
                validationErrors.add('Tower ' + (i + 1) + ': Name is required.');
            }
            if (t.Project_Phase__c == null) {
                validationErrors.add('Tower ' + (i + 1) + ': Project Phase is required.');
            } else {
                phaseIds.add(t.Project_Phase__c);
            }
            if (t.Project__c == null) {
                validationErrors.add('Tower ' + (i + 1) + ': Project is required.');
            }
        }
        if (!validationErrors.isEmpty()) {
            throw new AuraHandledException(String.join(validationErrors, '\n'));
        }

        // ── One-time-use guard ────────────────────────────────────
        Integer existingCount = [
            SELECT COUNT()
            FROM   Tower__c
            WHERE  Project_Phase__c IN :phaseIds
            WITH   SECURITY_ENFORCED
        ];
        if (existingCount > 0) {
            throw new AuraHandledException(
                'Towers already exist for this Project Phase. ' +
                'This wizard can only be used once per phase.'
            );
        }

        // ── Chunked bulk insert ───────────────────────────────────
        Integer      successCount = 0;
        List<String> dmlErrors    = new List<String>();

        for (Integer start = 0; start < towers.size(); start += CHUNK_SIZE) {
            Integer chunkEnd   = Math.min(start + CHUNK_SIZE, towers.size());
            List<Tower__c> chunk = new List<Tower__c>();
            for (Integer j = start; j < chunkEnd; j++) {
                chunk.add(towers[j]);
            }

            Database.SaveResult[] results = Database.insert(chunk, false);

            for (Integer k = 0; k < results.size(); k++) {
                if (results[k].isSuccess()) {
                    successCount++;
                } else {
                    for (Database.Error err : results[k].getErrors()) {
                        dmlErrors.add(
                            'Tower ' + (start + k + 1) + ': ' + err.getMessage()
                        );
                    }
                }
            }
        }

        // ── Return result wrapper ─────────────────────────────────
        TowerCreationResult result = new TowerCreationResult();
        result.successCount = successCount;
        result.errorCount   = dmlErrors.size();
        result.errors       = dmlErrors;
        result.success      = dmlErrors.isEmpty();
        return result;
    }

    // ─────────────────────────────────────────────────────────────
    //  Inner wrapper — returned to LWC
    // ─────────────────────────────────────────────────────────────
    public class TowerCreationResult {
        @AuraEnabled public Boolean      success;
        @AuraEnabled public Integer      successCount;
        @AuraEnabled public Integer      errorCount;
        @AuraEnabled public List<String> errors;
    }
}