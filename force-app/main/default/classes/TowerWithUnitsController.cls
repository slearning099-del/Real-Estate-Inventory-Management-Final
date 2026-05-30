public with sharing class TowerWithUnitsController {

    @AuraEnabled(cacheable=true)
    public static List<Tower__c> getTowersWithUnits(Id phaseId) {
        if (phaseId == null) {
            return new List<Tower__c>();
        }

        return [
            SELECT Id, Name,
                (SELECT Id, Name,
                        (SELECT Id, Name FROM Sub_Units__r)
                 FROM Property_Units__r)
            FROM Tower__c
            WHERE Project_Phase__c = :phaseId
            ORDER BY Name
        ];
    }

}