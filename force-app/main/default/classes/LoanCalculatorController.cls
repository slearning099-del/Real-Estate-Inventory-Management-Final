public with sharing class LoanCalculatorController {
    
    @AuraEnabled
    public static Booking__c getBookingByContactId(String contactId) {
        // Validate input
        if (String.isBlank(contactId)) {
            System.debug('Invalid contact ID provided: ' + contactId);
            return null;
        }
        
        try {
            System.debug('Attempting to query booking for contact ID: ' + contactId);
            
            // First, verify that the contact exists
            List<Contact> contacts = [
                SELECT Id 
                FROM Contact 
                WHERE Id = :contactId
                LIMIT 1
            ];
            
            if (contacts.isEmpty()) {
                System.debug('No contact found with ID: ' + contactId);
                return null;
            }
            
            // Query the latest Booking record for the given contact with all required fields
            List<Booking__c> bookings = [
                SELECT Id, Tower__c, Property_Unit__c, Sub_Unit__c, 
                       Booking_Amount__c, Net_Amount__c, Contact__c
                FROM Booking__c 
                WHERE Contact__c = :contactId 
                ORDER BY CreatedDate DESC 
                LIMIT 1
            ];
            
            if (bookings.size() > 0) {
                System.debug('Found booking record: ' + bookings[0].Id);
                System.debug('Booking data: ' + bookings[0]);
                return bookings[0];
            }
            
            System.debug('No booking found for contact: ' + contactId);
            return null;
        } catch (Exception e) {
            System.debug('Error fetching booking: ' + e.getMessage());
            System.debug('Error type: ' + e.getTypeName());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Return null to indicate failure, but log the error for debugging purposes
            return null;
        }
    }
}