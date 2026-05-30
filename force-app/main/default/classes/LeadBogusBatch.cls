/**
 * Marks stale Leads as Bogus.
 *
 * Eligibility:
 * - Not converted
 * - Status == openStatus
 * - CreatedDate older than ageDays
 */
public with sharing class LeadBogusBatch implements Database.Batchable<SObject> {
  private final String openStatus;
  private final String bogusStatus;
  private final Integer ageDays;

  public LeadBogusBatch() {
    // These defaults match the common "stale lead" setup in this org:
    // update only "Working - Contacted" leads older than 30 days,
    // marking them as "Closed - Converted".
    this('Working - Contacted', 'Closed - Converted', 30);
  }

  @TestVisible
  public LeadBogusBatch(
    String openStatus,
    String bogusStatus,
    Integer ageDays
  ) {
    this.openStatus = openStatus;
    this.bogusStatus = bogusStatus;
    this.ageDays = ageDays;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    DateTime cutoff = System.now().addDays(-ageDays);
    return Database.getQueryLocator(
      [
        SELECT Id, Status
        FROM Lead
        WHERE
          IsConverted = FALSE
          AND Status = :openStatus
          AND CreatedDate < :cutoff
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    List<Lead> toUpdate = new List<Lead>();
    for (SObject row : scope) {
      Lead l = (Lead) row;
      l.Status = bogusStatus;
      toUpdate.add(l);
    }

    if (!toUpdate.isEmpty()) {
      update toUpdate;
    }
  }

  public void finish(Database.BatchableContext bc) {
    // Intentionally left blank.
  }
}