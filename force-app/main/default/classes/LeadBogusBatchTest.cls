@IsTest
private class LeadBogusBatchTest {
  private static String uniq() {
    return String.valueOf(Math.abs(Crypto.getRandomInteger()));
  }

  private static String requireLeadStatus(String masterLabel) {
    List<LeadStatus> matches = [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE MasterLabel = :masterLabel
      LIMIT 1
    ];
    System.assert(
      !matches.isEmpty(),
      'Missing LeadStatus in org: ' + masterLabel
    );
    return matches[0].MasterLabel;
  }

  private static String pickAnyOtherNonConvertedStatus(String excludeStatus) {
    List<LeadStatus> matches = [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE IsConverted = FALSE AND MasterLabel != :excludeStatus
      LIMIT 10
    ];
    System.assert(
      !matches.isEmpty(),
      'No other non-converted LeadStatus found.'
    );
    return matches[0].MasterLabel;
  }

  private static String getConvertedStatus() {
    // Prefer default converted status.
    List<LeadStatus> matches = [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE IsConverted = TRUE AND IsDefault = TRUE
      LIMIT 1
    ];
    if (!matches.isEmpty()) {
      return matches[0].MasterLabel;
    }

    matches = [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE IsConverted = TRUE
      LIMIT 1
    ];
    System.assert(!matches.isEmpty(), 'No converted LeadStatus found.');
    return matches[0].MasterLabel;
  }

  private static Lead insertLead(String status, Integer daysAgo) {
    String u = uniq();
    Lead l = new Lead(
      LastName = 'Lead-' + u,
      Company = 'Test Company ' + u,
      Email = 'test+' + u + '@example.com',
      Status = status
    );
    insert l;
    Test.setCreatedDate(l.Id, System.now().addDays(-daysAgo));
    return l;
  }

  @IsTest
  static void olderWorkingContacted_becomesBogus() {
    String openStatus = requireLeadStatus('Working - Contacted');
    String bogusStatus = requireLeadStatus('Closed - Converted');

    Lead l = insertLead(openStatus, 31);

    Test.startTest();
    Database.executeBatch(new LeadBogusBatch(openStatus, bogusStatus, 30), 200);
    Test.stopTest();

    Lead updated = [
      SELECT Status
      FROM Lead
      WHERE Id = :l.Id
    ];
    System.assertEquals(bogusStatus, updated.Status);
  }

  @IsTest
  static void youngerWorkingContacted_isUnchanged() {
    String openStatus = requireLeadStatus('Working - Contacted');
    String bogusStatus = requireLeadStatus('Closed - Converted');

    Lead l = insertLead(openStatus, 10);

    Test.startTest();
    Database.executeBatch(new LeadBogusBatch(openStatus, bogusStatus, 30), 200);
    Test.stopTest();

    Lead updated = [
      SELECT Status
      FROM Lead
      WHERE Id = :l.Id
    ];
    System.assertEquals(openStatus, updated.Status);
  }

  @IsTest
  static void olderNonWorkingStatus_isUnchanged() {
    String openStatus = requireLeadStatus('Working - Contacted');
    String bogusStatus = requireLeadStatus('Closed - Converted');

    String otherStatus = pickAnyOtherNonConvertedStatus(openStatus);
    Lead l = insertLead(otherStatus, 31);

    Test.startTest();
    Database.executeBatch(new LeadBogusBatch(openStatus, bogusStatus, 30), 200);
    Test.stopTest();

    Lead updated = [
      SELECT Status
      FROM Lead
      WHERE Id = :l.Id
    ];
    System.assertEquals(otherStatus, updated.Status);
  }

  @IsTest
  static void convertedLeads_areNotUpdatedToBogus() {
    String openStatus = requireLeadStatus('Working - Contacted');
    String bogusStatus = requireLeadStatus('Closed - Converted');

    Lead l = insertLead(openStatus, 31);
    String convertedStatus = getConvertedStatus();

    Test.startTest();
    Database.LeadConvert lc = new Database.LeadConvert();
    lc.setLeadId(l.Id);
    lc.setConvertedStatus(convertedStatus);
    lc.setDoNotCreateOpportunity(true);
    Database.convertLead(lc);

    Lead statusBeforeBatch = [
      SELECT Status, IsConverted
      FROM Lead
      WHERE Id = :l.Id
    ];

    Database.executeBatch(new LeadBogusBatch(openStatus, bogusStatus, 30), 200);
    Test.stopTest();

    Lead statusAfterBatch = [
      SELECT Status, IsConverted
      FROM Lead
      WHERE Id = :l.Id
    ];
    System.assertEquals(true, statusAfterBatch.IsConverted);
    System.assertEquals(statusBeforeBatch.Status, statusAfterBatch.Status);
  }

  @IsTest
  static void bulkLeads_updateInBulk() {
    String openStatus = requireLeadStatus('Working - Contacted');
    String bogusStatus = requireLeadStatus('Closed - Converted');

    Integer n = 205; // > typical batch size to force multiple execute() calls.
    List<Lead> leads = new List<Lead>();
    for (Integer i = 0; i < n; i++) {
      leads.add(
        new Lead(
          LastName = 'LeadBulk-' + i + '-' + uniq(),
          Company = 'Bulk Co ' + i,
          Email = 'bulk+' + i + '+' + uniq() + '@example.com',
          Status = openStatus
        )
      );
    }
    insert leads;

    DateTime older = System.now().addDays(-31);
    for (Lead l : leads) {
      Test.setCreatedDate(l.Id, older);
    }

    Test.startTest();
    // Use a batch size equal to total records so the test framework executes
    // the batch in a single chunk (avoids executeBatch invocation limits).
    Database.executeBatch(new LeadBogusBatch(openStatus, bogusStatus, 30), n);
    Test.stopTest();

    System.assertEquals(
      n,
      [SELECT COUNT() FROM Lead WHERE Id IN :leads AND Status = :bogusStatus]
    );
  }
}