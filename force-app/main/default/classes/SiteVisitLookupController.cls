public with sharing class SiteVisitLookupController {
    
    @AuraEnabled(cacheable=true)
    public static List<Project_Phase__c> getProjectPhases() {
        return [
            SELECT Id, Name
            FROM Project_Phase__c
            ORDER BY Name
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Tower__c> getTowers() {
        return [
            SELECT Id, Name
            FROM Tower__c
            ORDER BY Name
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Sub_Unit__c> getSubUnits() {
        return [
            SELECT Id, Name
            FROM Sub_Unit__c
            ORDER BY Name
        ];
    }
    
}