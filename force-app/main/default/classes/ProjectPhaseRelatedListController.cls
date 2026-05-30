public with sharing class ProjectPhaseRelatedListController {


    /*@AuraEnabled(cacheable=true)
    public static List<Tower__c> getTowersWithUnits(Id phaseId) {

        return [
            SELECT Id, Name,
                (SELECT Id, Name 
                 FROM Property_Units__r)
            FROM Tower__c
            WHERE Project_Phase__c = :phaseId
        ];
    }*/
}