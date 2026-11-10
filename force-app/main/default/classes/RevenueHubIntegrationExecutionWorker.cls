public without sharing class RevenueHubIntegrationExecutionWorker implements Queueable, Database.AllowsCallouts {
  private static final Set<String> ERROR_CATEGORIES = new Set<String>{
    'Validation',
    'Authorization',
    'Configuration',
    'Authentication',
    'Network',
    'Rate Limit',
    'Provider',
    'Unknown'
  };

  private Id jobId;

  public RevenueHubIntegrationExecutionWorker(Id jobId) {
    this.jobId = jobId;
  }

  public void execute(QueueableContext context) {
    List<Integration_Job__c> jobs = [
      SELECT
        Id,
        Status__c,
        Integration_Type__c,
        Payment_Transaction__c,
        Document_Request__c,
        Maximum_Attempts__c
      FROM Integration_Job__c
      WHERE Id = :jobId
      WITH SYSTEM_MODE
      LIMIT 1
      FOR UPDATE
    ];
    if (jobs.isEmpty() || jobs[0].Status__c != 'Processing') {
      return;
    }

    Integration_Job__c job = jobs[0];
    Integer priorAttemptCount = [
      SELECT COUNT()
      FROM Integration_Attempt__c
      WHERE Integration_Job__c = :job.Id
      WITH SYSTEM_MODE
    ];
    Integer attemptNumber = priorAttemptCount + 1;
    DateTime attemptStartedAt = System.now();
    RevenueHubIntegrationResult result;

    if (
      job.Integration_Type__c == 'Payment' &&
      job.Payment_Transaction__c != null &&
      job.Document_Request__c == null
    ) {
      List<Payment_Transaction__c> payments = [
        SELECT Id, Payment_Provider__c, Idempotency_Key__c
        FROM Payment_Transaction__c
        WHERE Id = :job.Payment_Transaction__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!payments.isEmpty() && payments[0].Payment_Provider__c == 'Mock') {
        try {
          result = new RevenueHubMockPaymentGateway()
            .createPayment(payments[0]);
        } catch (CalloutException caughtException) {
          result = retryableFailure('Network');
        }
      } else {
        result = permanentFailure('Configuration');
      }
    } else if (
      job.Integration_Type__c == 'Document' &&
      job.Document_Request__c != null &&
      job.Payment_Transaction__c == null
    ) {
      List<Document_Request__c> documentRequests = [
        SELECT Id, Document_Provider__c, Template_Key__c
        FROM Document_Request__c
        WHERE Id = :job.Document_Request__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (
        !documentRequests.isEmpty() &&
        documentRequests[0].Document_Provider__c == 'Mock'
      ) {
        try {
          result = new RevenueHubMockDocumentGateway()
            .createDocument(documentRequests[0]);
        } catch (CalloutException caughtException) {
          result = retryableFailure('Network');
        }
      } else {
        result = permanentFailure('Configuration');
      }
    } else {
      result = permanentFailure('Validation');
    }

    if (result == null || result.outcome != 'Succeeded') {
      completeFailure(job, result, attemptNumber, attemptStartedAt);
      return;
    }

    DateTime completedAt = System.now();
    Integration_Attempt__c attempt = new Integration_Attempt__c(
      Integration_Job__c = job.Id,
      Attempt_Number__c = attemptNumber,
      Started_At__c = attemptStartedAt,
      Completed_At__c = completedAt,
      Outcome__c = 'Succeeded'
    );
    if (job.Integration_Type__c == 'Payment') {
      Payment_Transaction__c payment = [
        SELECT Id, Status__c
        FROM Payment_Transaction__c
        WHERE Id = :job.Payment_Transaction__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      payment.Status__c = 'Succeeded';
      payment.Completed_At__c = completedAt;
      payment.External_Transaction_Id__c = result.externalId;
      payment.Payment_URL__c = result.resourceUrl;
      payment.Failure_Reason__c = null;
      Database.update(payment, AccessLevel.SYSTEM_MODE);
    } else {
      Document_Request__c documentRequest = [
        SELECT Id, Status__c
        FROM Document_Request__c
        WHERE Id = :job.Document_Request__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      documentRequest.Status__c = 'Generated';
      documentRequest.Completed_At__c = completedAt;
      documentRequest.External_Document_Id__c = result.externalId;
      documentRequest.Document_URL__c = result.resourceUrl;
      documentRequest.Failure_Reason__c = null;
      Database.update(documentRequest, AccessLevel.SYSTEM_MODE);
    }

    job.Status__c = 'Completed';
    job.Completed_At__c = completedAt;
    job.Next_Retry_At__c = null;
    job.Error_Category__c = null;
    job.Sanitized_Error__c = null;
    Database.update(job, AccessLevel.SYSTEM_MODE);
    Database.insert(attempt, AccessLevel.SYSTEM_MODE);
  }

  private static void completeFailure(
    Integration_Job__c job,
    RevenueHubIntegrationResult result,
    Integer attemptNumber,
    DateTime attemptStartedAt
  ) {
    Boolean retryable = result != null && result.retryable == true;
    String category = result != null &&
      ERROR_CATEGORIES.contains(result.errorCategory)
      ? result.errorCategory
      : 'Unknown';
    String safeMessage = 'The integration provider did not complete the request. Review the attempt and correlation ID.';
    DateTime completedAt = System.now();
    Integration_Attempt__c attempt = new Integration_Attempt__c(
      Integration_Job__c = job.Id,
      Attempt_Number__c = attemptNumber,
      Started_At__c = attemptStartedAt,
      Completed_At__c = completedAt,
      Outcome__c = result != null &&
        result.outcome == 'Timed Out'
        ? 'Timed Out'
        : 'Failed',
      HTTP_Status__c = result == null ? null : result.httpStatus,
      Sanitized_Error__c = safeMessage
    );

    Boolean canRetry =
      retryable && Decimal.valueOf(attemptNumber) < job.Maximum_Attempts__c;
    if (canRetry) {
      job.Status__c = 'Retry Scheduled';
      job.Next_Retry_At__c = RevenueHubRetryPolicy.nextRetryAt(attemptNumber);
    } else {
      job.Status__c = retryable ? 'Dead Letter' : 'Failed';
      job.Completed_At__c = completedAt;
      job.Next_Retry_At__c = null;
    }
    job.Error_Category__c = category;
    job.Sanitized_Error__c = safeMessage;

    if (
      job.Integration_Type__c == 'Payment' &&
      job.Payment_Transaction__c != null
    ) {
      Payment_Transaction__c payment = [
        SELECT Id, Status__c
        FROM Payment_Transaction__c
        WHERE Id = :job.Payment_Transaction__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      payment.Status__c = 'Failed';
      payment.Completed_At__c = completedAt;
      payment.Failure_Reason__c = safeMessage;
      Database.update(payment, AccessLevel.SYSTEM_MODE);
    } else if (
      job.Integration_Type__c == 'Document' &&
      job.Document_Request__c != null
    ) {
      Document_Request__c documentRequest = [
        SELECT Id, Status__c
        FROM Document_Request__c
        WHERE Id = :job.Document_Request__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      documentRequest.Status__c = 'Failed';
      documentRequest.Completed_At__c = completedAt;
      documentRequest.Failure_Reason__c = safeMessage;
      Database.update(documentRequest, AccessLevel.SYSTEM_MODE);
    }
    Database.update(job, AccessLevel.SYSTEM_MODE);
    Database.insert(attempt, AccessLevel.SYSTEM_MODE);
  }

  private static RevenueHubIntegrationResult retryableFailure(String category) {
    RevenueHubIntegrationResult result = new RevenueHubIntegrationResult();
    result.outcome = 'Failed';
    result.errorCategory = category;
    result.retryable = true;
    return result;
  }

  private static RevenueHubIntegrationResult permanentFailure(String category) {
    RevenueHubIntegrationResult result = new RevenueHubIntegrationResult();
    result.outcome = 'Failed';
    result.errorCategory = category;
    result.retryable = false;
    return result;
  }
}
