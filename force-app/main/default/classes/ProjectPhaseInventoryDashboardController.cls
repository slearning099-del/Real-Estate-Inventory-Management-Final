public with sharing class ProjectPhaseInventoryDashboardController {
  private static final Integer MAX_ROWS = 200;

  @AuraEnabled(cacheable=true)
  public static DashboardData getInventoryDashboardData(
    Id projectPhaseId,
    Date startDate,
    Date endDate,
    String itemCategory,
    String stockStatus
  ) {
    if (projectPhaseId == null) {
      throw new AuraHandledException('Project Phase Id is required.');
    }

    DashboardData data = new DashboardData();
    String availableObject = resolveAvailableObjectApiName();
    String inventoryCategoryField = resolveInventoryCategoryFieldApiName();

    data.availableRows = queryAvailableRows(
      availableObject,
      projectPhaseId,
      startDate,
      endDate,
      itemCategory,
      stockStatus,
      inventoryCategoryField
    );
    data.usedRows = queryUsedRows(
      projectPhaseId,
      startDate,
      endDate,
      itemCategory,
      stockStatus,
      inventoryCategoryField
    );
    data.returnRows = queryReturnRows(
      projectPhaseId,
      startDate,
      endDate,
      itemCategory,
      stockStatus,
      inventoryCategoryField
    );

    data.totalAvailable = sumQuantity(data.availableRows);
    data.totalUsed = sumQuantity(data.usedRows);
    data.totalReturned = sumQuantity(data.returnRows);
    data.remainingStock =
      data.totalAvailable - data.totalUsed + data.totalReturned;

    Decimal denominator = data.totalAvailable + data.totalReturned;
    if (denominator > 0) {
      data.usagePercentage = (data.totalUsed / denominator) * 100;
    } else {
      data.usagePercentage = 0;
    }

    data.inventoryHealth = getInventoryHealth(data.remainingStock);
    data.itemSummaries = buildItemSummaries(
      data.availableRows,
      data.usedRows,
      data.returnRows
    );
    data.availableStockObjectApiName = availableObject;
    return data;
  }

  private static List<InventoryRow> queryAvailableRows(
    String availableObject,
    Id projectPhaseId,
    Date startDate,
    Date endDate,
    String itemCategory,
    String stockStatus,
    String inventoryCategoryField
  ) {
    if (String.isBlank(availableObject)) {
      return new List<InventoryRow>();
    }

    if (!isStatusAllowed(stockStatus, 'Available')) {
      return new List<InventoryRow>();
    }

    Datetime startDateTime = startDate == null
      ? null
      : Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
    Datetime endDateTime = endDate == null
      ? null
      : Datetime.newInstance(endDate, Time.newInstance(23, 59, 59, 999));

    String soql =
      'SELECT Id, Name, LastModifiedDate, Inventory_Item__c, ' +
      'Inventory_Item__r.Name, Inventory_Item__r.Item_Code__c, ' +
      'Inventory_Item__r.Unit_Master__r.Name, Available_Quantity__c ' +
      'FROM ' + availableObject +
      ' WHERE Project_Phase__c = :projectPhaseId';

    if (startDateTime != null) {
      soql += ' AND LastModifiedDate >= :startDateTime';
    }
    if (endDateTime != null) {
      soql += ' AND LastModifiedDate <= :endDateTime';
    }
    if (!String.isBlank(itemCategory) && !String.isBlank(inventoryCategoryField)) {
      soql += ' AND Inventory_Item__r.' + inventoryCategoryField + ' = :itemCategory';
    }
    soql += ' ORDER BY LastModifiedDate DESC LIMIT :MAX_ROWS';

    List<InventoryRow> rows = new List<InventoryRow>();
    for (SObject record : Database.query(soql)) {
      rows.add(
        new InventoryRow(
          (Id) record.get('Id'),
          (Id) record.get('Inventory_Item__c'),
          (String) record.get('Name'),
          (String) getNestedValue(record, 'Inventory_Item__r.Name'),
          (String) getNestedValue(record, 'Inventory_Item__r.Item_Code__c'),
          (Decimal) record.get('Available_Quantity__c'),
          (String) getNestedValue(record, 'Inventory_Item__r.Unit_Master__r.Name'),
          'Available',
          (Datetime) record.get('LastModifiedDate')
        )
      );
    }
    return rows;
  }

  private static List<InventoryRow> queryUsedRows(
    Id projectPhaseId,
    Date startDate,
    Date endDate,
    String itemCategory,
    String stockStatus,
    String inventoryCategoryField
  ) {
    if (!isStatusAllowed(stockStatus, 'Used')) {
      return new List<InventoryRow>();
    }

    Datetime startDateTime = startDate == null
      ? null
      : Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
    Datetime endDateTime = endDate == null
      ? null
      : Datetime.newInstance(endDate, Time.newInstance(23, 59, 59, 999));

    String soql =
      'SELECT Id, Name, LastModifiedDate, Inventory_Item__c, Used_Quantity__c, ' +
      'Inventory_Item__r.Name, Inventory_Item__r.Item_Code__c, ' +
      'Inventory_Item__r.Unit_Master__r.Name ' +
      'FROM Used_Item_Stock__c WHERE Project_Phase__c = :projectPhaseId';

    if (startDateTime != null) {
      soql += ' AND LastModifiedDate >= :startDateTime';
    }
    if (endDateTime != null) {
      soql += ' AND LastModifiedDate <= :endDateTime';
    }
    if (!String.isBlank(itemCategory) && !String.isBlank(inventoryCategoryField)) {
      soql += ' AND Inventory_Item__r.' + inventoryCategoryField + ' = :itemCategory';
    }
    soql += ' ORDER BY LastModifiedDate DESC LIMIT :MAX_ROWS';

    List<InventoryRow> rows = new List<InventoryRow>();
    for (SObject record : Database.query(soql)) {
      rows.add(
        new InventoryRow(
          (Id) record.get('Id'),
          (Id) record.get('Inventory_Item__c'),
          (String) record.get('Name'),
          (String) getNestedValue(record, 'Inventory_Item__r.Name'),
          (String) getNestedValue(record, 'Inventory_Item__r.Item_Code__c'),
          (Decimal) record.get('Used_Quantity__c'),
          (String) getNestedValue(record, 'Inventory_Item__r.Unit_Master__r.Name'),
          'Used',
          (Datetime) record.get('LastModifiedDate')
        )
      );
    }
    return rows;
  }

  private static List<InventoryRow> queryReturnRows(
    Id projectPhaseId,
    Date startDate,
    Date endDate,
    String itemCategory,
    String stockStatus,
    String inventoryCategoryField
  ) {
    if (!isStatusAllowed(stockStatus, 'Returned')) {
      return new List<InventoryRow>();
    }

    Datetime startDateTime = startDate == null
      ? null
      : Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
    Datetime endDateTime = endDate == null
      ? null
      : Datetime.newInstance(endDate, Time.newInstance(23, 59, 59, 999));

    String soql =
      'SELECT Id, Name, LastModifiedDate, Inventory_Item__c, Return_Quantity__c, Return_Type__c, ' +
      'Inventory_Item__r.Name, Inventory_Item__r.Item_Code__c, ' +
      'Inventory_Item__r.Unit_Master__r.Name ' +
      'FROM Return_Item_Stock__c WHERE Project_Phase__c = :projectPhaseId';

    if (startDateTime != null) {
      soql += ' AND LastModifiedDate >= :startDateTime';
    }
    if (endDateTime != null) {
      soql += ' AND LastModifiedDate <= :endDateTime';
    }
    if (!String.isBlank(itemCategory) && !String.isBlank(inventoryCategoryField)) {
      soql += ' AND Inventory_Item__r.' + inventoryCategoryField + ' = :itemCategory';
    }
    soql += ' ORDER BY LastModifiedDate DESC LIMIT :MAX_ROWS';

    List<InventoryRow> rows = new List<InventoryRow>();
    for (SObject record : Database.query(soql)) {
      String rowStatus = String.isBlank((String) record.get('Return_Type__c'))
        ? 'Returned'
        : (String) record.get('Return_Type__c');
      rows.add(
        new InventoryRow(
          (Id) record.get('Id'),
          (Id) record.get('Inventory_Item__c'),
          (String) record.get('Name'),
          (String) getNestedValue(record, 'Inventory_Item__r.Name'),
          (String) getNestedValue(record, 'Inventory_Item__r.Item_Code__c'),
          (Decimal) record.get('Return_Quantity__c'),
          (String) getNestedValue(record, 'Inventory_Item__r.Unit_Master__r.Name'),
          rowStatus,
          (Datetime) record.get('LastModifiedDate')
        )
      );
    }
    return rows;
  }

  private static List<ItemStockSummary> buildItemSummaries(
    List<InventoryRow> availableRows,
    List<InventoryRow> usedRows,
    List<InventoryRow> returnRows
  ) {
    Map<Id, ItemStockSummary> byItemId = new Map<Id, ItemStockSummary>();

    upsertSummariesFromRows(byItemId, availableRows, 'Available');
    upsertSummariesFromRows(byItemId, usedRows, 'Used');
    upsertSummariesFromRows(byItemId, returnRows, 'Returned');

    for (ItemStockSummary summary : byItemId.values()) {
      summary.remainingQuantity =
        summary.availableQuantity - summary.usedQuantity + summary.returnedQuantity;

      Decimal denom = summary.availableQuantity + summary.returnedQuantity;
      summary.usagePercentage = denom > 0 ? (summary.usedQuantity / denom) * 100 : 0;
      summary.inventoryHealth = getInventoryHealth(summary.remainingQuantity);
    }

    List<ItemStockSummary> results = new List<ItemStockSummary>();
    results.addAll(byItemId.values());
    results.sort();
    return results;
  }

  private static void upsertSummariesFromRows(
    Map<Id, ItemStockSummary> byItemId,
    List<InventoryRow> rows,
    String type
  ) {
    if (rows == null) {
      return;
    }

    for (InventoryRow row : rows) {
      if (row == null || row.itemId == null) {
        continue;
      }

      ItemStockSummary summary = byItemId.get(row.itemId);
      if (summary == null) {
        summary = new ItemStockSummary();
        summary.itemId = row.itemId;
        summary.itemName = row.itemName;
        summary.itemCode = row.itemCode;
        summary.unit = row.unit;
        byItemId.put(row.itemId, summary);
      } else {
        // Fill any missing descriptive fields (varies by object).
        if (String.isBlank(summary.itemName)) summary.itemName = row.itemName;
        if (String.isBlank(summary.itemCode)) summary.itemCode = row.itemCode;
        if (String.isBlank(summary.unit)) summary.unit = row.unit;
      }

      Decimal qty = row.quantity == null ? 0 : row.quantity;
      if (type == 'Available') {
        summary.availableQuantity += qty;
      } else if (type == 'Used') {
        summary.usedQuantity += qty;
      } else if (type == 'Returned') {
        summary.returnedQuantity += qty;
      }

      if (summary.lastUpdated == null || (row.lastUpdated != null && row.lastUpdated > summary.lastUpdated)) {
        summary.lastUpdated = row.lastUpdated;
      }
    }
  }

  private static Boolean isStatusAllowed(String requestedStatus, String statusValue) {
    return String.isBlank(requestedStatus) ||
      requestedStatus.equalsIgnoreCase('All') ||
      requestedStatus.equalsIgnoreCase(statusValue);
  }

  private static Decimal sumQuantity(List<InventoryRow> rows) {
    Decimal total = 0;
    for (InventoryRow row : rows) {
      if (row.quantity != null) {
        total += row.quantity;
      }
    }
    return total;
  }

  private static String getInventoryHealth(Decimal remainingStock) {
    if (remainingStock == null || remainingStock <= 0) {
      return 'Critical';
    }
    if (remainingStock < 20) {
      return 'Low';
    }
    return 'Healthy';
  }

  private static Object getNestedValue(SObject record, String relationshipPath) {
    SObject currentRecord = record;
    List<String> pathParts = relationshipPath.split('\\.');
    for (Integer i = 0; i < pathParts.size() - 1; i++) {
      if (currentRecord == null) {
        return null;
      }
      currentRecord = currentRecord.getSObject(pathParts[i]);
    }
    return currentRecord == null ? null : currentRecord.get(pathParts[pathParts.size() - 1]);
  }

  private static String resolveAvailableObjectApiName() {
    Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
    if (globalMap.containsKey('Available_Item_Stock__c')) {
      return 'Available_Item_Stock__c';
    }
    if (globalMap.containsKey('Available_Stock__c')) {
      return 'Available_Stock__c';
    }
    return null;
  }

  private static String resolveInventoryCategoryFieldApiName() {
    Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
    if (!globalMap.containsKey('Inventory_Item__c')) {
      return null;
    }
    Map<String, Schema.SObjectField> fieldsByName =
      globalMap.get('Inventory_Item__c').getDescribe().fields.getMap();
    if (fieldsByName.containsKey('Category__c')) {
      return 'Category__c';
    }
    if (fieldsByName.containsKey('Item_Category__c')) {
      return 'Item_Category__c';
    }
    if (fieldsByName.containsKey('Unit_Master__c')) {
      return 'Unit_Master__r.Name';
    }
    return null;
  }

  public class InventoryRow {
    @AuraEnabled public Id id;
    @AuraEnabled public Id itemId;
    @AuraEnabled public String stockName;
    @AuraEnabled public String itemName;
    @AuraEnabled public String itemCode;
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public String unit;
    @AuraEnabled public String status;
    @AuraEnabled public Datetime lastUpdated;

    public InventoryRow(
      Id id,
      Id itemId,
      String stockName,
      String itemName,
      String itemCode,
      Decimal quantity,
      String unit,
      String status,
      Datetime lastUpdated
    ) {
      this.id = id;
      this.itemId = itemId;
      this.stockName = stockName;
      this.itemName = itemName;
      this.itemCode = itemCode;
      this.quantity = quantity;
      this.unit = unit;
      this.status = status;
      this.lastUpdated = lastUpdated;
    }
  }

  public class ItemStockSummary implements Comparable {
    @AuraEnabled public Id itemId;
    @AuraEnabled public String itemName;
    @AuraEnabled public String itemCode;
    @AuraEnabled public String unit;
    @AuraEnabled public Decimal availableQuantity = 0;
    @AuraEnabled public Decimal usedQuantity = 0;
    @AuraEnabled public Decimal returnedQuantity = 0;
    @AuraEnabled public Decimal remainingQuantity = 0;
    @AuraEnabled public Decimal usagePercentage = 0;
    @AuraEnabled public String inventoryHealth;
    @AuraEnabled public Datetime lastUpdated;

    public Integer compareTo(Object other) {
      ItemStockSummary o = (ItemStockSummary) other;
      if (o == null) return -1;

      // Sort by most recently updated, then by name.
      Datetime a = this.lastUpdated;
      Datetime b = o.lastUpdated;
      if (a != null && b != null && a != b) {
        return a > b ? -1 : 1;
      }
      if (a != null && b == null) return -1;
      if (a == null && b != null) return 1;

      String an = this.itemName == null ? '' : this.itemName;
      String bn = o.itemName == null ? '' : o.itemName;
      return an.toLowerCase().compareTo(bn.toLowerCase());
    }
  }

  public class DashboardData {
    @AuraEnabled public List<InventoryRow> availableRows;
    @AuraEnabled public List<InventoryRow> usedRows;
    @AuraEnabled public List<InventoryRow> returnRows;
    @AuraEnabled public List<ItemStockSummary> itemSummaries;
    @AuraEnabled public Decimal totalAvailable;
    @AuraEnabled public Decimal totalUsed;
    @AuraEnabled public Decimal totalReturned;
    @AuraEnabled public Decimal remainingStock;
    @AuraEnabled public Decimal usagePercentage;
    @AuraEnabled public String inventoryHealth;
    @AuraEnabled public String availableStockObjectApiName;
  }
}