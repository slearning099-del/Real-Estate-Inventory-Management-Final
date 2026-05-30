public with sharing class ContactLookupController {
    
    @AuraEnabled
    public static List<Contact> getContacts() {
        List<Contact> contacts = [
            SELECT Id, Name, Phone
            FROM Contact 
            ORDER BY Name
        ];
        return contacts;
    }
    
    @AuraEnabled
    public static Contact getContactById(Id contactId) {
        Contact contact = [
            SELECT Id, Name, Phone
            FROM Contact 
            WHERE Id = :contactId
            LIMIT 1
        ];
        return contact;
    }
}