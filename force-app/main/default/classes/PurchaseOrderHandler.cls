public class PurchaseOrderHandler {

    public static void movePOLineItemsToStock(
        List<Purchase_Order__c> newList,
        Map<Id, Purchase_Order__c> oldMap
    ){

        Set<Id> receivedPOIds = new Set<Id>();

        // 1️⃣ Check Status changed to Received
        for(Purchase_Order__c newPO : newList){

            Purchase_Order__c oldPO = oldMap.get(newPO.Id);

            if(newPO.Status__c == 'Received' && 
               oldPO.Status__c != 'Received'){

                receivedPOIds.add(newPO.Id);
            }
        }

        if(receivedPOIds.isEmpty()){
            return;
        }

        // 2️⃣ Get related PO Line Items
        List<Purchase_Order_Line_Item__c> poliList = [
            SELECT Id, Inventory_Item__c, Project_Phase__c, Quantity__c
            FROM Purchase_Order_Line_Item__c
            WHERE Purchase_Order__c IN :receivedPOIds
        ];

        if(poliList.isEmpty()){
            return;
        }

        // 3️⃣ Prepare Sets
        Set<Id> itemIds = new Set<Id>();
        Set<Id> phaseIds = new Set<Id>();

        for(Purchase_Order_Line_Item__c poli : poliList){
            itemIds.add(poli.Inventory_Item__c);
            phaseIds.add(poli.Project_Phase__c);
        }

        // 4️⃣ Get Existing Available Stock
        Map<String, Available_Stock__c> stockMap = new Map<String, Available_Stock__c>();

        for(Available_Stock__c stock : [
            SELECT Id, Inventory_Item__c, Project_Phase__c, Total_Purches_Quantity__c
            FROM Available_Stock__c
            WHERE Inventory_Item__c IN :itemIds
            AND Project_Phase__c IN :phaseIds
        ]){

            String key = stock.Inventory_Item__c + '-' + stock.Project_Phase__c;
            stockMap.put(key, stock);
        }

        List<Available_Stock__c> stockToInsert = new List<Available_Stock__c>();
        List<Available_Stock__c> stockToUpdate = new List<Available_Stock__c>();

        // 5️⃣ Process Each Line Item
        for(Purchase_Order_Line_Item__c poli : poliList){

            String key = poli.Inventory_Item__c + '-' + poli.Project_Phase__c;

            if(stockMap.containsKey(key)){

                // Add Quantity to existing stock
                Available_Stock__c existingStock = stockMap.get(key);
                existingStock.Total_Purches_Quantity__c += poli.Quantity__c;
                stockToUpdate.add(existingStock);

            } else {

                // Create new stock record
                Available_Stock__c newStock = new Available_Stock__c();
                newStock.Inventory_Item__c = poli.Inventory_Item__c;
                newStock.Project_Phase__c = poli.Project_Phase__c;
                newStock.Total_Purches_Quantity__c = poli.Quantity__c;
                newStock.Used_Quantity__c = 0;

                stockToInsert.add(newStock);
            }
        }

        // 6️⃣ DML Operations
        if(!stockToUpdate.isEmpty()){
            update stockToUpdate;
        }

        if(!stockToInsert.isEmpty()){
            insert stockToInsert;
        }
    }
}