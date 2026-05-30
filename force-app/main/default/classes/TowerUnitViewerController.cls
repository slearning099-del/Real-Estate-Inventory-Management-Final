public with sharing class TowerUnitViewerController {
    
    // Projects
    @AuraEnabled
    public static List<Project__c> getProjects() {
        return [
            SELECT Id, Name, Company__c, Start_Date__c, Project_Status__c
            FROM Project__c
            ORDER BY Name
        ];
    }

    // Phases filtered by Project
    @AuraEnabled
    public static List<Project_Phase__c> getPhases(Id projectId) {
        return [
            SELECT Id, Name, Project__c, Phase_Start_Date__c, Phase_End_Date__c, Phase_Status__c
            FROM Project_Phase__c
            WHERE Project__c = :projectId
            ORDER BY Name
        ];
    }

    // Towers filtered by Phase
    @AuraEnabled
    public static List<Tower__c> getTowersByPhase(Id phaseId) {
        return [
            SELECT Id, Name, Building_Floor_Count__c, Project__c, Project_Phase__c
            FROM Tower__c
            WHERE Project_Phase__c = :phaseId
            ORDER BY Name
        ];
    }

    // Legacy: all towers (kept for backward compatibility; UI will now use getTowersByPhase)
    @AuraEnabled
    public static List<Tower__c> getTowers() {
        return [
            SELECT Id, Name, Building_Floor_Count__c 
            FROM Tower__c 
            ORDER BY Name
        ];
    }
    
    // Property Units filtered by Tower
    @AuraEnabled
    public static List<Property_Unit__c> getPropertyUnits(Id towerId) {
        return [
            SELECT Id, Name, Property_Unit_Status__c, Unit_View_Type__c, Area_sqft__c, Base_Price__c, Final_Amount__c, Tower__c 
            FROM Property_Unit__c 
            WHERE Tower__c = :towerId 
            ORDER BY Name
        ];
    }
    
    // Sub Units filtered by Property Unit
    @AuraEnabled
    public static List<Sub_Unit__c> getSubUnits(Id propertyUnitId) {
        return [
            SELECT Id, Name, Sub_Unit_Price__c, Property_Unit__c 
            FROM Sub_Unit__c 
            WHERE Property_Unit__c = :propertyUnitId 
            ORDER BY Name
        ];
    }
}