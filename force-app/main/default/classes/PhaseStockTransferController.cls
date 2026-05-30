public with sharing class PhaseStockTransferController {

    @AuraEnabled(cacheable=true)
    public static List<Available_Stock__c> getAvailableStock(Id phaseId) {

        if(phaseId == null){
            return new List<Available_Stock__c>();
        }

        return [
            SELECT Id, Name,
                   Available_Quantity__c,
                   Inventory_Item__c,
                   Inventory_Item__r.Name
            FROM Available_Stock__c
            WHERE Project_Phase__c = :phaseId
            AND Available_Quantity__c > 0
        ];
    }


    @AuraEnabled
    public static void transferStock(
        Id sourcePhaseId,
        Id destinationPhaseId,
        List<StockWrapper> stockList
    ) {

        if(sourcePhaseId == null || destinationPhaseId == null){
            throw new AuraHandledException('Source or Destination missing.');
        }

        if(sourcePhaseId == destinationPhaseId){
            throw new AuraHandledException('Source and Destination cannot be same.');
        }

        if(stockList == null || stockList.isEmpty()){
            throw new AuraHandledException('No stock selected.');
        }

        Set<Id> stockIds = new Set<Id>();
        Set<Id> inventoryIds = new Set<Id>();

        for(StockWrapper sw : stockList){
            stockIds.add(sw.stockId);
            inventoryIds.add(sw.inventoryItemId);
        }

        Map<Id, Available_Stock__c> sourceMap =
            new Map<Id, Available_Stock__c>(
                [SELECT Id, Available_Quantity__c, Inventory_Item__c
                 FROM Available_Stock__c
                 WHERE Id IN :stockIds]
            );

        Map<Id, Available_Stock__c> destMap = new Map<Id, Available_Stock__c>();

        for(Available_Stock__c d :
            [SELECT Id, Available_Quantity__c, Inventory_Item__c
             FROM Available_Stock__c
             WHERE Project_Phase__c = :destinationPhaseId
             AND Inventory_Item__c IN :inventoryIds]) {

            destMap.put(d.Inventory_Item__c, d);
        }

        List<Available_Stock__c> updates = new List<Available_Stock__c>();
        List<Available_Stock__c> inserts = new List<Available_Stock__c>();
        List<Phase_Transfer_Line_Item__c> transferLines = new List<Phase_Transfer_Line_Item__c>();

        for(StockWrapper sw : stockList){

            Available_Stock__c source = sourceMap.get(sw.stockId);
            if(source == null) continue;

            if(sw.transferQty == null || sw.transferQty <= 0) continue;

            if(sw.transferQty > source.Available_Quantity__c){
                throw new AuraHandledException(
                    'Transfer quantity exceeds available quantity.'
                );
            }

            // 🔹 Reduce Source Quantity
            source.Available_Quantity__c =
                source.Available_Quantity__c - sw.transferQty;

            updates.add(source);

            // 🔹 Increase Destination Quantity
            if(destMap.containsKey(sw.inventoryItemId)){

                Available_Stock__c dest = destMap.get(sw.inventoryItemId);
                dest.Available_Quantity__c =
                    dest.Available_Quantity__c + sw.transferQty;

                updates.add(dest);

            } else {

                inserts.add(new Available_Stock__c(
                    Project_Phase__c = destinationPhaseId,
                    Inventory_Item__c = sw.inventoryItemId,
                    Available_Quantity__c = sw.transferQty,
                    Name = 'Transferred'
                ));
            }

            // 🔹 Create Transfer Line Item (Auto Number will generate automatically)
            transferLines.add(new Phase_Transfer_Line_Item__c(
                Transfer_Quantity__c = sw.transferQty,
                Destination_Project_Phase__c = destinationPhaseId
            ));
        }

        if(!updates.isEmpty()) update updates;
        if(!inserts.isEmpty()) insert inserts;
        if(!transferLines.isEmpty()) insert transferLines;
    }


    public class StockWrapper {
        @AuraEnabled public Id stockId;
        @AuraEnabled public Id inventoryItemId;
        @AuraEnabled public Decimal transferQty;
    }
}