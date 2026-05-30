/**
 * Bulkified duplicate prevention for Contact based on Email and Phone.
 */
public with sharing class ContactTriggerHandler {
  private static final String DUP_EMAIL_MSG = 'A contact with this email already exists.';
  private static final String DUP_PHONE_MSG = 'A contact with this phone number already exists.';
  private static final String DUP_BATCH_EMAIL_MSG = 'Duplicate email in the same transaction.';
  private static final String DUP_BATCH_PHONE_MSG = 'Duplicate phone number in the same transaction.';

  public static void beforeInsert(List<Contact> newContacts) {
    runValidation(newContacts);
  }

  public static void beforeUpdate(
    List<Contact> newContacts,
    Map<Id, Contact> oldMap
  ) {
    List<Contact> toValidate = new List<Contact>();
    for (Contact c : newContacts) {
      Contact oldC = oldMap.get(c.Id);
      if (emailOrPhoneChanged(c, oldC)) {
        toValidate.add(c);
      }
    }
    if (!toValidate.isEmpty()) {
      runValidation(toValidate);
    }
  }

  private static Boolean emailOrPhoneChanged(Contact newC, Contact oldC) {
    return normalizeEmail(newC.Email) != normalizeEmail(oldC.Email) ||
      normalizePhone(newC.Phone) != normalizePhone(oldC.Phone);
  }

  private static void runValidation(List<Contact> contacts) {
    Set<String> emails = new Set<String>();
    Set<String> phones = new Set<String>();

    for (Contact c : contacts) {
      String e = normalizeEmail(c.Email);
      if (!String.isBlank(e)) {
        emails.add(e);
      }
      String p = normalizePhone(c.Phone);
      if (!String.isBlank(p)) {
        phones.add(p);
      }
    }

    flagIntraBatchDuplicates(contacts);

    if (emails.isEmpty() && phones.isEmpty()) {
      return;
    }

    Map<String, Set<Id>> emailToContactIds = new Map<String, Set<Id>>();
    Map<String, Set<Id>> phoneToContactIds = new Map<String, Set<Id>>();

    for (Contact row : queryExistingContacts(contacts)) {
      String e = normalizeEmail(row.Email);
      if (!String.isBlank(e)) {
        addToMap(emailToContactIds, e, row.Id);
      }
      String p = normalizePhone(row.Phone);
      if (!String.isBlank(p)) {
        addToMap(phoneToContactIds, p, row.Id);
      }
    }

    for (Contact c : contacts) {
      if (c.getErrors().size() > 0) {
        continue;
      }

      String e = normalizeEmail(c.Email);
      if (!String.isBlank(e)) {
        Set<Id> ids = emailToContactIds.get(e);
        if (ids != null && conflictsWithAnotherContact(ids, c.Id)) {
          c.addError(DUP_EMAIL_MSG);
          continue;
        }
      }

      String p = normalizePhone(c.Phone);
      if (!String.isBlank(p)) {
        Set<Id> ids = phoneToContactIds.get(p);
        if (ids != null && conflictsWithAnotherContact(ids, c.Id)) {
          c.addError(DUP_PHONE_MSG);
        }
      }
    }
  }

  private static void flagIntraBatchDuplicates(List<Contact> contacts) {
    Map<String, List<Contact>> emailBuckets = new Map<String, List<Contact>>();
    Map<String, List<Contact>> phoneBuckets = new Map<String, List<Contact>>();

    for (Contact c : contacts) {
      String e = normalizeEmail(c.Email);
      if (!String.isBlank(e)) {
        if (!emailBuckets.containsKey(e)) {
          emailBuckets.put(e, new List<Contact>());
        }
        emailBuckets.get(e).add(c);
      }
      String p = normalizePhone(c.Phone);
      if (!String.isBlank(p)) {
        if (!phoneBuckets.containsKey(p)) {
          phoneBuckets.put(p, new List<Contact>());
        }
        phoneBuckets.get(p).add(c);
      }
    }

    for (String key : emailBuckets.keySet()) {
      List<Contact> bucket = emailBuckets.get(key);
      if (bucket.size() > 1) {
        for (Contact c : bucket) {
          c.addError(DUP_BATCH_EMAIL_MSG);
        }
      }
    }

    for (String key : phoneBuckets.keySet()) {
      List<Contact> bucket = phoneBuckets.get(key);
      if (bucket.size() > 1) {
        for (Contact c : bucket) {
          c.addError(DUP_BATCH_PHONE_MSG);
        }
      }
    }
  }

  /**
   * Loads candidate contacts using Email / Phone IN clauses built from the triggering rows.
   * Email keys are compared in normalized form after fetch. Phone compares by digits-only;
   * SOQL uses trimmed raw values plus digit-only variants so common format differences still match.
   * Cross-format gaps remain unless you add a dedicated normalized phone field and query it.
   */
  private static List<Contact> queryExistingContacts(List<Contact> contacts) {
    Set<String> emailIn = new Set<String>();
    Set<String> phoneIn = new Set<String>();

    for (Contact c : contacts) {
      if (!String.isBlank(c.Email)) {
        String trimmed = c.Email.trim();
        emailIn.add(trimmed);
        emailIn.add(trimmed.toLowerCase());
      }
      if (!String.isBlank(c.Phone)) {
        String trimmedPhone = c.Phone.trim();
        phoneIn.add(trimmedPhone);
        String digits = normalizePhone(c.Phone);
        if (!String.isBlank(digits) && digits != trimmedPhone) {
          phoneIn.add(digits);
        }
      }
    }

    Map<Id, Contact> byId = new Map<Id, Contact>();

    if (!emailIn.isEmpty()) {
      for (Contact row : [
        SELECT Id, Email, Phone
        FROM Contact
        WHERE Email IN :emailIn
      ]) {
        byId.put(row.Id, row);
      }
    }
    if (!phoneIn.isEmpty()) {
      for (Contact row : [
        SELECT Id, Email, Phone
        FROM Contact
        WHERE Phone IN :phoneIn
      ]) {
        byId.put(row.Id, row);
      }
    }

    return byId.values();
  }

  private static void addToMap(
    Map<String, Set<Id>> m,
    String key,
    Id contactId
  ) {
    if (!m.containsKey(key)) {
      m.put(key, new Set<Id>());
    }
    m.get(key).add(contactId);
  }

  /**
   * True if any Id in the set belongs to a contact other than the current record.
   */
  private static Boolean conflictsWithAnotherContact(
    Set<Id> ids,
    Id currentId
  ) {
    if (currentId == null) {
      return !ids.isEmpty();
    }
    for (Id existingId : ids) {
      if (existingId != currentId) {
        return true;
      }
    }
    return false;
  }

  private static String normalizeEmail(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    return value.trim().toLowerCase();
  }

  /**
   * Compares phone values by digits only so formatting differences do not bypass checks.
   */
  private static String normalizePhone(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    String digits = value.replaceAll('\\D', '');
    return String.isBlank(digits) ? null : digits;
  }
}