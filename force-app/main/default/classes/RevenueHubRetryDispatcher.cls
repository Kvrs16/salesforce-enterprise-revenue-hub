public without sharing class RevenueHubRetryDispatcher implements Schedulable {
  private static final Integer MAXIMUM_JOBS_PER_RUN = 1;

  public void execute(SchedulableContext context) {
    DateTime currentTime = System.now();
    List<Integration_Job__c> dueJobs = [
      SELECT
        Id,
        Integration_Type__c,
        Payment_Transaction__c,
        Document_Request__c,
        Attempt_Count__c,
        Maximum_Attempts__c
      FROM Integration_Job__c
      WHERE Status__c = 'Retry Scheduled' AND Next_Retry_At__c <= :currentTime
      WITH SYSTEM_MODE
      LIMIT :MAXIMUM_JOBS_PER_RUN
      FOR UPDATE
    ];
    if (dueJobs.isEmpty()) {
      return;
    }

    Set<Id> paymentIds = new Set<Id>();
    Set<Id> documentRequestIds = new Set<Id>();
    for (Integration_Job__c job : dueJobs) {
      if (job.Payment_Transaction__c != null) {
        paymentIds.add(job.Payment_Transaction__c);
      }
      if (job.Document_Request__c != null) {
        documentRequestIds.add(job.Document_Request__c);
      }
    }

    Map<Id, Payment_Transaction__c> paymentsById = new Map<Id, Payment_Transaction__c>();
    if (!paymentIds.isEmpty()) {
      paymentsById = new Map<Id, Payment_Transaction__c>(
        [
          SELECT Id, Status__c
          FROM Payment_Transaction__c
          WHERE Id IN :paymentIds
          WITH SYSTEM_MODE
        ]
      );
    }
    Map<Id, Document_Request__c> documentsById = new Map<Id, Document_Request__c>();
    if (!documentRequestIds.isEmpty()) {
      documentsById = new Map<Id, Document_Request__c>(
        [
          SELECT Id, Status__c
          FROM Document_Request__c
          WHERE Id IN :documentRequestIds
          WITH SYSTEM_MODE
        ]
      );
    }

    List<Integration_Job__c> jobsToUpdate = new List<Integration_Job__c>();
    List<Payment_Transaction__c> paymentsToUpdate = new List<Payment_Transaction__c>();
    List<Document_Request__c> documentsToUpdate = new List<Document_Request__c>();
    List<Id> jobsToEnqueue = new List<Id>();
    for (Integration_Job__c job : dueJobs) {
      Boolean exhaustedAttempts =
        job.Attempt_Count__c >= job.Maximum_Attempts__c;
      Payment_Transaction__c payment = paymentsById.get(
        job.Payment_Transaction__c
      );
      Document_Request__c documentRequest = documentsById.get(
        job.Document_Request__c
      );
      Boolean validParent =
        (payment != null &&
        payment.Status__c == 'Failed' &&
        documentRequest == null) ||
        (documentRequest != null &&
        documentRequest.Status__c == 'Failed' &&
        payment == null);

      if (exhaustedAttempts || !validParent) {
        job.Status__c = 'Dead Letter';
        job.Completed_At__c = currentTime;
        job.Next_Retry_At__c = null;
        job.Error_Category__c = exhaustedAttempts ? 'Provider' : 'Validation';
        job.Sanitized_Error__c = exhaustedAttempts
          ? 'The configured maximum number of attempts was reached.'
          : 'The retry request is missing a failed parent record.';
        jobsToUpdate.add(job);
        continue;
      }

      if (payment != null) {
        payment.Status__c = 'Queued';
        payment.Completed_At__c = null;
        payment.Failure_Reason__c = null;
        paymentsToUpdate.add(payment);
      } else {
        documentRequest.Status__c = 'Queued';
        documentRequest.Completed_At__c = null;
        documentRequest.Failure_Reason__c = null;
        documentsToUpdate.add(documentRequest);
      }
      job.Status__c = 'Queued';
      job.Next_Retry_At__c = null;
      job.Error_Category__c = null;
      job.Sanitized_Error__c = null;
      jobsToUpdate.add(job);
      jobsToEnqueue.add(job.Id);
    }

    if (!paymentsToUpdate.isEmpty()) {
      Database.update(paymentsToUpdate, AccessLevel.SYSTEM_MODE);
    }
    if (!documentsToUpdate.isEmpty()) {
      Database.update(documentsToUpdate, AccessLevel.SYSTEM_MODE);
    }
    if (!jobsToUpdate.isEmpty()) {
      Database.update(jobsToUpdate, AccessLevel.SYSTEM_MODE);
    }
    if (!jobsToEnqueue.isEmpty()) {
      RevenueHubIntegrationWorker.enqueueIntegrationJob(jobsToEnqueue[0]);
    }
  }
}
