public class AvailableStockHandler {

    public static void handleReturn(List<Available_Stock__c> newList,
                                    Map<Id, Available_Stock__c> oldMap){

        List<Return_Item_Stock__c> insertList = new List<Return_Item_Stock__c>();

        // Step 1: Collect Inventory Item Ids
        Set<Id> itemIds = new Set<Id>();
        for(Available_Stock__c stock : newList){
            if(stock.Inventory_Item__c != null){
                itemIds.add(stock.Inventory_Item__c);
            }
        }

        // Step 2: Fetch Inventory Item with Warehouse
        Map<Id, Inventory_Item__c> itemMap = new Map<Id, Inventory_Item__c>(
            [SELECT Id, Inventory_Warehouse__c
             FROM Inventory_Item__c
             WHERE Id IN :itemIds]
        );

        // Step 3: Create Return Record
        for(Available_Stock__c stock : newList){

            Available_Stock__c oldStock = oldMap.get(stock.Id);

            if(stock.Is_Return__c == true && oldStock.Is_Return__c == false){

                Return_Item_Stock__c newReturn = new Return_Item_Stock__c();
                newReturn.Name= stock.Name;
                newReturn.Project__c = stock.Project__c;
                newReturn.Project_Phase__c = stock.Project_Phase__c;
                newReturn.Inventory_Item__c = stock.Inventory_Item__c;
                newReturn.Return_Quantity__c = stock.Return_Item_Quantity__c;
                newReturn.Return_Type__c = 'Damage';

                // 🔥 Get Warehouse from Inventory Item
                if(itemMap.containsKey(stock.Inventory_Item__c)){
                    newReturn.Inventory_Warehouse__c =
                        itemMap.get(stock.Inventory_Item__c).Inventory_Warehouse__c;
                }

                insertList.add(newReturn);
            }
        }

        if(!insertList.isEmpty()){
            insert insertList;
        }
    }
}