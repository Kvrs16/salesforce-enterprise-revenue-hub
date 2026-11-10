public without sharing class RevenueHubIntegrationWorker implements Queueable {
  @TestVisible
  private static Boolean suppressEnqueueForTest = false;

  private Id jobId;

  public RevenueHubIntegrationWorker(Id jobId) {
    this.jobId = jobId;
  }

  public static void enqueueIntegrationJob(Id jobId) {
    if (!suppressEnqueueForTest) {
      System.enqueueJob(new RevenueHubIntegrationWorker(jobId));
    }
  }

  public void execute(QueueableContext context) {
    List<Integration_Job__c> jobs = [
      SELECT
        Id,
        Status__c,
        Integration_Type__c,
        Payment_Transaction__c,
        Document_Request__c
      FROM Integration_Job__c
      WHERE Id = :jobId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (jobs.isEmpty()) {
      return;
    }

    Integration_Job__c job = jobs[0];
    if (job.Status__c != 'Queued') {
      return;
    }

    Boolean hasPayment = job.Payment_Transaction__c != null;
    Boolean hasDocument = job.Document_Request__c != null;
    if (
      hasPayment == hasDocument ||
      (job.Integration_Type__c == 'Payment') != hasPayment
    ) {
      job.Status__c = 'Processing';
      job.Started_At__c = System.now();
      Database.update(job, AccessLevel.SYSTEM_MODE);
      System.enqueueJob(new RevenueHubIntegrationExecutionWorker(job.Id));
      return;
    }

    job.Status__c = 'Processing';
    job.Started_At__c = System.now();
    Database.update(job, AccessLevel.SYSTEM_MODE);

    if (hasPayment) {
      List<Payment_Transaction__c> payments = [
        SELECT Id, Status__c
        FROM Payment_Transaction__c
        WHERE Id = :job.Payment_Transaction__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (payments.isEmpty() || payments[0].Status__c != 'Queued') {
        job.Status__c = 'Dead Letter';
        job.Completed_At__c = System.now();
        job.Error_Category__c = 'Validation';
        job.Sanitized_Error__c = 'The payment request is missing or is not queued.';
        Database.update(job, AccessLevel.SYSTEM_MODE);
        return;
      }
      payments[0].Status__c = 'Processing';
      Database.update(payments[0], AccessLevel.SYSTEM_MODE);
    } else {
      List<Document_Request__c> documentRequests = [
        SELECT Id, Status__c
        FROM Document_Request__c
        WHERE Id = :job.Document_Request__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (
        documentRequests.isEmpty() || documentRequests[0].Status__c != 'Queued'
      ) {
        job.Status__c = 'Dead Letter';
        job.Completed_At__c = System.now();
        job.Error_Category__c = 'Validation';
        job.Sanitized_Error__c = 'The document request is missing or is not queued.';
        Database.update(job, AccessLevel.SYSTEM_MODE);
        return;
      }
      documentRequests[0].Status__c = 'Processing';
      Database.update(documentRequests[0], AccessLevel.SYSTEM_MODE);
    }

    System.enqueueJob(new RevenueHubIntegrationExecutionWorker(job.Id));
  }
}
