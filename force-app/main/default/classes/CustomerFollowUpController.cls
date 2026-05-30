public with sharing class CustomerFollowUpController {
    
    @AuraEnabled(cacheable=true)
    public static List<Contact> getContacts() {
        return [
            SELECT Id, Name
            FROM Contact
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
    public static List<Property_Unit__c> getPropertyUnits() {
        return [
            SELECT Id, Name
            FROM Property_Unit__c
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