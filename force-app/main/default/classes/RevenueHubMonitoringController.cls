public without sharing class RevenueHubMonitoringController {
  private static final Integer MAXIMUM_MONITORED_JOBS = 50;

  @AuraEnabled(cacheable=true)
  public static List<Integration_Job__c> getRecentJobs() {
    return [
      SELECT
        Id,
        Name,
        CreatedDate,
        Correlation_Id__c,
        Integration_Type__c,
        Status__c,
        Attempt_Count__c,
        Maximum_Attempts__c,
        Next_Retry_At__c,
        Error_Category__c,
        Sanitized_Error__c,
        Payment_Transaction__c,
        Document_Request__c
      FROM Integration_Job__c
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :MAXIMUM_MONITORED_JOBS
    ];
  }

  @AuraEnabled
  public static void retryJob(Id jobId) {
    if (!FeatureManagement.checkPermission('Manage_Revenue_Integration_Jobs')) {
      throw RevenueHubRequestPolicy.handledException(
        'You do not have permission to retry Revenue Hub jobs.'
      );
    }
    if (jobId == null) {
      throw RevenueHubRequestPolicy.handledException(
        'An integration job is required.'
      );
    }

    List<Integration_Job__c> jobs = [
      SELECT
        Id,
        Status__c,
        Integration_Type__c,
        Payment_Transaction__c,
        Document_Request__c,
        Attempt_Count__c,
        Maximum_Attempts__c
      FROM Integration_Job__c
      WHERE Id = :jobId
      WITH USER_MODE
      FOR UPDATE
    ];
    if (jobs.isEmpty()) {
      throw RevenueHubRequestPolicy.handledException(
        'The integration job was not found or is not accessible.'
      );
    }

    Integration_Job__c job = jobs[0];
    if (
      job.Status__c != 'Failed' ||
      job.Attempt_Count__c >= job.Maximum_Attempts__c
    ) {
      throw RevenueHubRequestPolicy.handledException(
        'Only failed jobs with attempts remaining can be retried.'
      );
    }

    if (job.Integration_Type__c == 'Payment') {
      if (
        job.Payment_Transaction__c == null ||
        job.Document_Request__c != null
      ) {
        throw RevenueHubRequestPolicy.handledException(
          'The payment job has an invalid parent.'
        );
      }
      // The visible job and custom permission authorize this internal state check.
      List<Payment_Transaction__c> payments = [
        SELECT Id, Status__c
        FROM Payment_Transaction__c
        WHERE Id = :job.Payment_Transaction__c
        WITH SYSTEM_MODE
        FOR UPDATE
      ];
      if (payments.isEmpty() || payments[0].Status__c != 'Failed') {
        throw RevenueHubRequestPolicy.handledException(
          'The payment request is not available for retry.'
        );
      }
      payments[0].Status__c = 'Queued';
      payments[0].Completed_At__c = null;
      payments[0].Failure_Reason__c = null;
      Database.update(payments[0], AccessLevel.SYSTEM_MODE);
    } else if (job.Integration_Type__c == 'Document') {
      if (
        job.Document_Request__c == null ||
        job.Payment_Transaction__c != null
      ) {
        throw RevenueHubRequestPolicy.handledException(
          'The document job has an invalid parent.'
        );
      }
      List<Document_Request__c> documentRequests = [
        SELECT Id, Status__c
        FROM Document_Request__c
        WHERE Id = :job.Document_Request__c
        WITH SYSTEM_MODE
        FOR UPDATE
      ];
      if (
        documentRequests.isEmpty() || documentRequests[0].Status__c != 'Failed'
      ) {
        throw RevenueHubRequestPolicy.handledException(
          'The document request is not available for retry.'
        );
      }
      documentRequests[0].Status__c = 'Queued';
      documentRequests[0].Completed_At__c = null;
      documentRequests[0].Failure_Reason__c = null;
      Database.update(documentRequests[0], AccessLevel.SYSTEM_MODE);
    } else {
      throw RevenueHubRequestPolicy.handledException(
        'The integration job type is not supported.'
      );
    }

    job.Status__c = 'Queued';
    job.Next_Retry_At__c = null;
    job.Error_Category__c = null;
    job.Sanitized_Error__c = null;
    Database.update(job, AccessLevel.SYSTEM_MODE);
    RevenueHubIntegrationWorker.enqueueIntegrationJob(job.Id);
  }
}
