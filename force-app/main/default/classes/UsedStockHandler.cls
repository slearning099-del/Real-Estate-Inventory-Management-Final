public class UsedStockHandler {
        public static void handleAfter(List<Available_Stock__c> newList,
                                   Map<Id, Available_Stock__c> oldMap) {

        List<Available_Stock__c> recordsToProcess = new List<Available_Stock__c>();

        for (Available_Stock__c newRec : newList) {

            // INSERT case
            if (oldMap == null) {
                if (newRec.Used_Quantity__c != null && newRec.Used_Quantity__c > 0) {
                    recordsToProcess.add(newRec);
                }
            }
            // UPDATE case
            else {
                Available_Stock__c oldRec = oldMap.get(newRec.Id);

                if (newRec.Used_Quantity__c != oldRec.Used_Quantity__c) {
                    recordsToProcess.add(newRec);
                }
            }
        }

        if (recordsToProcess.isEmpty()) {
            return;
        }

        // Collect Inventory + Phase combinations
        Set<Id> inventoryIds = new Set<Id>();
        Set<Id> phaseIds = new Set<Id>();

        for (Available_Stock__c rec : recordsToProcess) {
            if (rec.Inventory_Item__c != null && rec.Project_Phase__c != null) {
                inventoryIds.add(rec.Inventory_Item__c);
                phaseIds.add(rec.Project_Phase__c);
            }
        }

        if (inventoryIds.isEmpty() || phaseIds.isEmpty()) {
            return;
        }

        // Query existing Used_Item_Stock__c records
        Map<String, Used_Item_Stock__c> existingUsedMap = new Map<String, Used_Item_Stock__c>();

        for (Used_Item_Stock__c usedRec : [
            SELECT Id, Inventory_Item__c, Project_Phase__c, Used_Quantity__c
            FROM Used_Item_Stock__c
            WHERE Inventory_Item__c IN :inventoryIds
            AND Project_Phase__c IN :phaseIds
        ]) {
            String key = usedRec.Inventory_Item__c + '-' + usedRec.Project_Phase__c;
            existingUsedMap.put(key, usedRec);
        }

        List<Used_Item_Stock__c> recordsToInsert = new List<Used_Item_Stock__c>();
        List<Used_Item_Stock__c> recordsToUpdate = new List<Used_Item_Stock__c>();

        for (Available_Stock__c rec : recordsToProcess) {

            if (rec.Inventory_Item__c == null || rec.Project_Phase__c == null) {
                continue;
            }

            String key = rec.Inventory_Item__c + '-' + rec.Project_Phase__c;

            if (existingUsedMap.containsKey(key)) {

                Used_Item_Stock__c existing = existingUsedMap.get(key);
                existing.Used_Quantity__c = rec.Used_Quantity__c;
                recordsToUpdate.add(existing);

            } else {

                Used_Item_Stock__c newUsed = new Used_Item_Stock__c();
                newUsed.Name = rec.Name;
                newUsed.Inventory_Item__c = rec.Inventory_Item__c;
                newUsed.Project_Phase__c = rec.Project_Phase__c;
                newUsed.Used_Quantity__c = rec.Used_Quantity__c;

                recordsToInsert.add(newUsed);
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }

        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }
    }

}