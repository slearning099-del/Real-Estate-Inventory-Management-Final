/**
 * Inventory Approval Handler - Utility class for field mapping and stock record creation.
 * Provides helper methods for dynamic field retrieval and stock record building.
 */
public with sharing class InventoryApprovalHandler {
    /**
     * Describes all fields for the given SObject type.
     * @param objectApiName The API name of the SObject to describe.
     * @return Map of field name to Schema.SObjectField.
     */
    public static Map<String, Schema.SObjectField> describeObjectFields(String objectApiName) {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(objectApiName)) {
            return new Map<String, Schema.SObjectField>();
        }
        return globalDescribe.get(objectApiName).getDescribe().fields.getMap();
    }

    /**
     * Returns the first available field from a list of candidates that exists on the SObject.
     * @param fields Map of available fields to check against.
     * @param candidates List of field API names to check in order.
     * @return The first matching field API name, or null if none found.
     */
    public static String getFirstAvailableField(Map<String, Schema.SObjectField> fields, List<String> candidates) {
        if (fields == null || candidates == null) {
            return null;
        }
        for (String candidate : candidates) {
            if (!String.isBlank(candidate) && fields.containsKey(candidate)) {
                return candidate;
            }
        }
        return null;
    }

    /**
     * Adds a field to select list if it exists, with optional relationship field.
     * @param selectFields List to add field to.
     * @param fields Available fields to check.
     * @param fieldApiName Field to add if it exists.
     * @param relationshipField Related object field to include if fieldApiName is a reference.
     */
    public static void addFieldIfExists(List<String> selectFields, Map<String, Schema.SObjectField> fields, String fieldApiName, String relationshipField) {
        if (String.isBlank(fieldApiName) || fields == null || !fields.containsKey(fieldApiName)) {
            return;
        }
        if (!selectFields.contains(fieldApiName)) {
            selectFields.add(fieldApiName);
        }
        if (!String.isBlank(relationshipField) && fields.get(fieldApiName).getDescribe().getType() == Schema.DisplayType.Reference) {
            if (!selectFields.contains(relationshipField)) {
                selectFields.add(relationshipField);
            }
        }
    }

    /**
     * Gets string value from SObject field, handling null safely.
     * @param record The SObject record.
     * @param fieldName The field API name.
     * @return String value or null.
     */
    public static String getString(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) {
            return null;
        }
        Object value = record.get(fieldName);
        return value == null ? null : String.valueOf(value);
    }

    /**
     * Gets decimal value from SObject field, handling multiple numeric types.
     * @param record The SObject record.
     * @param fieldName The field API name.
     * @return Decimal value or null.
     */
    public static Decimal getDecimal(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) {
            return null;
        }
        Object value = record.get(fieldName);
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }
        return null;
    }

    /**
     * Gets datetime value from SObject field.
     * @param record The SObject record.
     * @param fieldName The field API name.
     * @return Datetime value or null.
     */
    public static Datetime getDateTime(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) {
            return null;
        }
        Object value = record.get(fieldName);
        return value instanceof Datetime ? (Datetime) value : null;
    }

    /**
     * Gets item name from either a direct field or relationship.
     * @param record The SObject record.
     * @param itemNameField The item name field API name.
     * @return Item name string or null.
     */
    public static String getItemName(SObject record, String itemNameField) {
        if (record == null || String.isBlank(itemNameField)) {
            return getString(record, 'Name');
        }
        if (itemNameField == 'Inventory_Item__c') {
            return getString(record, 'Inventory_Item__r.Name');
        }
        return getString(record, itemNameField);
    }

    /**
     * Gets vendor name from either a direct field or relationship.
     * @param record The SObject record.
     * @param vendorField The vendor field API name.
     * @return Vendor name string or null.
     */
    public static String getVendorName(SObject record, String vendorField) {
        if (record == null || String.isBlank(vendorField)) {
            return null;
        }
        String value = getString(record, vendorField);
        if (String.isBlank(value) && vendorField == 'Vendor__c') {
            return getString(record, 'Vendor__r.Name');
        }
        if (String.isBlank(value) && vendorField == 'Supplier__c') {
            return getString(record, 'Supplier__r.Name');
        }
        return value;
    }

    /**
     * Gets unit label from either a direct field or relationship.
     * @param record The SObject record.
     * @param unitField The unit field API name.
     * @return Unit label string or null.
     */
    public static String getUnitLabel(SObject record, String unitField) {
        if (record == null || String.isBlank(unitField)) {
            return null;
        }
        if (unitField == 'Unit_Master__c') {
            return getString(record, 'Unit_Master__r.Name');
        }
        return getString(record, unitField);
    }

    /**
     * Builds Available_Item_Stock__c records from approved line items.
     * @param approvedLineItems List of approved Purchase Order Line Items.
     * @param lineItemFields Map of line item fields for reference.
     * @param quantityField The quantity field API name.
     * @param itemNameField The item name field API name.
     * @param itemCodeField The item code field API name.
     * @param unitField The unit field API name.
     * @param vendorField The vendor field API name.
     * @param categoryField The category field API name.
     * @return List of Available_Item_Stock__c records ready to insert.
     */
    public static List<SObject> buildAvailableStockRecords(
        List<SObject> approvedLineItems,
        Map<String, Schema.SObjectField> lineItemFields,
        String quantityField,
        String itemNameField,
        String itemCodeField,
        String unitField,
        String vendorField,
        String categoryField
    ) {
        List<SObject> stockRecords = new List<SObject>();
        if (approvedLineItems == null || approvedLineItems.isEmpty()) {
            return stockRecords;
        }

        Map<String, Schema.SObjectField> stockFields = describeObjectFields('Available_Item_Stock__c');
        if (stockFields.isEmpty()) {
            return stockRecords;
        }

        String stockQuantityField = getFirstAvailableField(stockFields, new List<String>{'Available_Quantity__c','Quantity__c','Stock_Quantity__c'});
        String stockItemNameField = getFirstAvailableField(stockFields, new List<String>{'Item_Name__c','Inventory_Item__c'});
        String stockItemCodeField = getFirstAvailableField(stockFields, new List<String>{'Item_Code__c','Product_Code__c'});
        String stockUnitField = getFirstAvailableField(stockFields, new List<String>{'Unit__c','Unit_Master__c'});
        String stockVendorField = getFirstAvailableField(stockFields, new List<String>{'Vendor__c','Supplier__c'});
        String stockCategoryField = getFirstAvailableField(stockFields, new List<String>{'Category__c','Item_Category__c'});
        String stockPOField = getFirstAvailableField(stockFields, new List<String>{'Purchase_Order__c'});
        String stockPhaseField = getFirstAvailableField(stockFields, new List<String>{'Project_Phase__c'});
        String stockLineItemField = getFirstAvailableField(stockFields, new List<String>{'Purchase_Order_Line_Item__c','Source_PO_Line_Item__c','Line_Item__c'});

        Set<Id> approvedLineItemIds = new Set<Id>();
        for (SObject lineItem : approvedLineItems) {
            approvedLineItemIds.add((Id) lineItem.get('Id'));
        }

        Set<Id> existingStockIds = fetchExistingStockIds(stockLineItemField, approvedLineItemIds);
        Schema.SObjectType stockType = Schema.getGlobalDescribe().get('Available_Item_Stock__c');

        for (SObject lineItem : approvedLineItems) {
            Id lineItemId = (Id) lineItem.get('Id');
            if (!String.isBlank(stockLineItemField) && existingStockIds.contains(lineItemId)) {
                continue;
            }

            Decimal quantity = getDecimal(lineItem, quantityField);
            if (quantity == null || quantity <= 0) {
                continue;
            }

            SObject stockRecord = buildStockRecord(stockType, stockFields, lineItem, quantity, stockQuantityField, stockItemNameField, stockItemCodeField, stockUnitField, stockVendorField, stockCategoryField, stockPOField, stockPhaseField, stockLineItemField, itemNameField, itemCodeField, unitField, vendorField, categoryField, lineItemId);
            stockRecords.add(stockRecord);
        }

        return stockRecords;
    }

    private static Set<Id> fetchExistingStockIds(String stockLineItemField, Set<Id> approvedLineItemIds) {
        Set<Id> existingIds = new Set<Id>();
        if (String.isBlank(stockLineItemField)) {
            return existingIds;
        }
        
        List<String> selectFields = new List<String>{stockLineItemField};
        String soql = 'SELECT ' + String.join(selectFields, ',') + ' FROM Available_Item_Stock__c WHERE ' + stockLineItemField + ' IN :approvedLineItemIds';
        for (SObject existingStock : Database.query(soql)) {
            Id existingLineItemId = (Id) existingStock.get(stockLineItemField);
            if (existingLineItemId != null) {
                existingIds.add(existingLineItemId);
            }
        }
        return existingIds;
    }

    private static SObject buildStockRecord(
        Schema.SObjectType stockType,
        Map<String, Schema.SObjectField> stockFields,
        SObject lineItem,
        Decimal quantity,
        String stockQuantityField,
        String stockItemNameField,
        String stockItemCodeField,
        String stockUnitField,
        String stockVendorField,
        String stockCategoryField,
        String stockPOField,
        String stockPhaseField,
        String stockLineItemField,
        String itemNameField,
        String itemCodeField,
        String unitField,
        String vendorField,
        String categoryField,
        Id lineItemId
    ) {
        SObject stockRecord = stockType.newSObject();
        if (stockFields.containsKey('Name')) {
            stockRecord.put('Name', 'Stock allocated for ' + getItemName(lineItem, itemNameField));
        }
        if (!String.isBlank(stockQuantityField)) {
            stockRecord.put(stockQuantityField, quantity);
        }
        if (!String.isBlank(stockItemNameField)) {
            setItemNameField(stockRecord, stockItemNameField, lineItem, itemNameField);
        }
        if (!String.isBlank(stockItemCodeField) && stockItemCodeField != stockItemNameField) {
            stockRecord.put(stockItemCodeField, getString(lineItem, itemCodeField));
        }
        if (!String.isBlank(stockUnitField)) {
            setUnitField(stockRecord, stockUnitField, lineItem, unitField);
        }
        if (!String.isBlank(stockVendorField)) {
            stockRecord.put(stockVendorField, getString(lineItem, vendorField));
        }
        if (!String.isBlank(stockCategoryField)) {
            stockRecord.put(stockCategoryField, getString(lineItem, categoryField));
        }
        if (!String.isBlank(stockPOField)) {
            stockRecord.put(stockPOField, lineItem.get('Purchase_Order__c'));
        }
        if (!String.isBlank(stockPhaseField)) {
            stockRecord.put(stockPhaseField, lineItem.get('Project_Phase__c'));
        }
        if (!String.isBlank(stockLineItemField)) {
            stockRecord.put(stockLineItemField, lineItemId);
        }
        return stockRecord;
    }

    private static void setItemNameField(SObject stockRecord, String stockItemNameField, SObject lineItem, String itemNameField) {
        if (stockItemNameField == 'Inventory_Item__c' && itemNameField == 'Inventory_Item__c') {
            Object inventoryItemRef = lineItem.get('Inventory_Item__c');
            if (inventoryItemRef != null) {
                stockRecord.put(stockItemNameField, inventoryItemRef);
            }
        } else {
            stockRecord.put(stockItemNameField, getItemName(lineItem, itemNameField));
        }
    }

    private static void setUnitField(SObject stockRecord, String stockUnitField, SObject lineItem, String unitField) {
        if (stockUnitField == 'Unit_Master__c' && unitField == 'Unit_Master__c') {
            Object unitRef = lineItem.get('Unit_Master__c');
            if (unitRef != null) {
                stockRecord.put(stockUnitField, unitRef);
            }
        } else {
            stockRecord.put(stockUnitField, getString(lineItem, unitField));
        }
    }

    /**
     * Creates Available_Item_Stock__c records from approved line items for trigger context.
     * @param approvedLineItems List of Purchase_Order_Line_Item__c records that were approved.
     */
    public static void createAvailableStockForApprovedLineItems(List<Purchase_Order_Line_Item__c> approvedLineItems) {
        if (approvedLineItems == null || approvedLineItems.isEmpty()) {
            return;
        }
        
        Map<String, Schema.SObjectField> lineItemFields = describeObjectFields('Purchase_Order_Line_Item__c');
        if (lineItemFields.isEmpty()) {
            return;
        }

        String quantityField = getFirstAvailableField(lineItemFields, new List<String>{'Quantity__c','Requested_Quantity__c','Qty__c'});
        String itemNameField = getFirstAvailableField(lineItemFields, new List<String>{'Item_Name__c','Inventory_Item__c'});
        String itemCodeField = getFirstAvailableField(lineItemFields, new List<String>{'Item_Code__c','Product_Code__c'});
        String unitField = getFirstAvailableField(lineItemFields, new List<String>{'Unit__c','Unit_Master__c'});
        String vendorField = getFirstAvailableField(lineItemFields, new List<String>{'Vendor__c','Supplier__c'});
        String categoryField = getFirstAvailableField(lineItemFields, new List<String>{'Item_Category__c','Category__c'});

        List<SObject> approvedSObjects = new List<SObject>();
        for (Purchase_Order_Line_Item__c item : approvedLineItems) {
            approvedSObjects.add(item);
        }

        List<SObject> stockRecords = buildAvailableStockRecords(
            approvedSObjects,
            lineItemFields,
            quantityField,
            itemNameField,
            itemCodeField,
            unitField,
            vendorField,
            categoryField
        );
        if (!stockRecords.isEmpty()) {
            insert stockRecords;
        }
    }
}