@IsTest
private class ContactTriggerHandlerTest {
  private static String uniq() {
    return String.valueOf(Math.abs(Crypto.getRandomInteger()));
  }

  private static void assertDmlFailed(DmlException e, String keyword) {
    System.assert(e.getNumDml() > 0, 'Expected at least one failed row.');
    Boolean found = false;
    for (Integer i = 0; i < e.getNumDml(); i++) {
      if (e.getDmlMessage(i).containsIgnoreCase(keyword)) {
        found = true;
        break;
      }
    }
    System.assert(
      found,
      'Expected message containing: ' + keyword + ' — got: ' + e.getMessage()
    );
  }

  @IsTest
  static void insert_uniqueEmailAndPhone_succeeds() {
    String u = uniq();
    Contact c = new Contact(
      LastName = 'TestUnique',
      Email = 'unique-' + u + '@example.com',
      Phone = '555000' + u.right(4)
    );

    Test.startTest();
    insert c;
    Test.stopTest();

    System.assertNotEquals(null, c.Id);
  }

  @IsTest
  static void insert_blankEmailAndPhone_succeeds() {
    Contact c = new Contact(LastName = 'NoEmailPhone');

    Test.startTest();
    insert c;
    Test.stopTest();

    System.assertNotEquals(null, c.Id);
  }

  @IsTest
  static void insert_duplicateEmailAgainstExisting_fails() {
    String u = uniq();
    String email = 'dup-email-' + u + '@example.com';
    insert new Contact(LastName = 'Seed', Email = email);

    Contact duplicate = new Contact(LastName = 'Dup', Email = email);

    Test.startTest();
    try {
      insert duplicate;
      System.assert(false, 'Expected DmlException for duplicate email.');
    } catch (DmlException e) {
      assertDmlFailed(e, 'email');
    }
    Test.stopTest();
  }

  @IsTest
  static void insert_duplicateEmailNormalizedAgainstExisting_fails() {
    String u = uniq();
    String base = 'DupNorm-' + u + '@example.com';
    insert new Contact(LastName = 'Seed', Email = base);

    Contact duplicate = new Contact(
      LastName = 'Dup',
      Email = 'DUPNORM-' + u + '@EXAMPLE.COM'
    );

    Test.startTest();
    try {
      insert duplicate;
      System.assert(
        false,
        'Expected DmlException for duplicate normalized email.'
      );
    } catch (DmlException e) {
      assertDmlFailed(e, 'email');
    }
    Test.stopTest();
  }

  @IsTest
  static void insert_duplicatePhoneAgainstExisting_fails() {
    String u = uniq();
    String phone = '(555) 100-' + u.right(4);
    insert new Contact(LastName = 'SeedPhone', Phone = phone);

    Contact duplicate = new Contact(LastName = 'DupPhone', Phone = phone);

    Test.startTest();
    try {
      insert duplicate;
      System.assert(false, 'Expected DmlException for duplicate phone.');
    } catch (DmlException e) {
      assertDmlFailed(e, 'phone');
    }
    Test.stopTest();
  }

  @IsTest
  static void insert_intraBatchDuplicateEmail_fails() {
    String u = uniq();
    String email = 'batch-email-' + u + '@example.com';
    List<Contact> rows = new List<Contact>{
      new Contact(LastName = 'A', Email = email),
      new Contact(LastName = 'B', Email = email)
    };

    Test.startTest();
    try {
      insert rows;
      System.assert(
        false,
        'Expected DmlException for intra-batch duplicate email.'
      );
    } catch (DmlException e) {
      assertDmlFailed(e, 'same transaction');
    }
    Test.stopTest();
  }

  @IsTest
  static void insert_intraBatchDuplicatePhoneDigits_fails() {
    String phone = '5551112233';
    List<Contact> rows = new List<Contact>{
      new Contact(LastName = 'P1', Phone = '(555) 111-2233'),
      new Contact(LastName = 'P2', Phone = '555-111-2233')
    };

    Test.startTest();
    try {
      insert rows;
      System.assert(
        false,
        'Expected DmlException for intra-batch duplicate phone.'
      );
    } catch (DmlException e) {
      assertDmlFailed(e, 'same transaction');
    }
    Test.stopTest();
  }

  @IsTest
  static void insert_bulk_uniqueRows_succeeds() {
    String u = uniq();
    List<Contact> rows = new List<Contact>();
    for (Integer i = 0; i < 50; i++) {
      rows.add(
        new Contact(
          LastName = 'Bulk' + i,
          Email = 'bulk-' + u + '-' + i + '@example.com',
          Phone = '555900' + String.valueOf(1000 + i)
        )
      );
    }

    Test.startTest();
    insert rows;
    Test.stopTest();

    for (Contact c : rows) {
      System.assertNotEquals(null, c.Id);
    }
  }

  @IsTest
  static void update_sameEmailAndPhone_otherFields_succeeds() {
    String u = uniq();
    Contact c = new Contact(
      LastName = 'Upd',
      Email = 'upd-' + u + '@example.com',
      Phone = '555200' + u.right(4)
    );
    insert c;

    c.LastName = 'UpdChanged';

    Test.startTest();
    update c;
    Test.stopTest();

    Contact loaded = [
      SELECT LastName, Email, Phone
      FROM Contact
      WHERE Id = :c.Id
    ];
    System.assertEquals('UpdChanged', loaded.LastName);
    System.assertEquals('upd-' + u + '@example.com', loaded.Email);
  }

  @IsTest
  static void update_changeToExistingEmail_fails() {
    String u = uniq();
    String taken = 'taken-' + u + '@example.com';
    insert new Contact(LastName = 'Holder', Email = taken);

    Contact mover = new Contact(
      LastName = 'Mover',
      Email = 'mover-' + u + '@example.com'
    );
    insert mover;

    mover.Email = taken;

    Test.startTest();
    try {
      update mover;
      System.assert(
        false,
        'Expected DmlException when colliding with existing email.'
      );
    } catch (DmlException e) {
      assertDmlFailed(e, 'email');
    }
    Test.stopTest();
  }

  @IsTest
  static void update_changeToExistingPhone_fails() {
    String u = uniq();
    String phone = '555300' + u.right(4);
    insert new Contact(LastName = 'HolderP', Phone = phone);

    Contact mover = new Contact(
      LastName = 'MoverP',
      Phone = '555400' + u.right(4)
    );
    insert mover;

    mover.Phone = phone;

    Test.startTest();
    try {
      update mover;
      System.assert(
        false,
        'Expected DmlException when colliding with existing phone.'
      );
    } catch (DmlException e) {
      assertDmlFailed(e, 'phone');
    }
    Test.stopTest();
  }

  @IsTest
  static void update_keepUniqueValues_noFalsePositive() {
    String u = uniq();
    String email = 'solo-' + u + '@example.com';
    Contact c = new Contact(
      LastName = 'Solo',
      Email = email,
      Phone = '555600' + u.right(4)
    );
    insert c;

    c.LastName = 'Solo2';

    Test.startTest();
    update c;
    Test.stopTest();

    System.assertEquals(
      'Solo2',
      [SELECT LastName FROM Contact WHERE Id = :c.Id].LastName
    );
  }
}