@IsTest
private without sharing class RevenueHubIntegrationWorkerTest {
  @IsTest
  static void claimsQueuedPaymentAndCompletesMockProcessing() {
    Id quoteId = createQuote();
    Payment_Transaction__c payment = createPayment(quoteId, 'Mock', 'Queued');
    Integration_Job__c job = createJob(payment.Id, null, 'Payment', 'Queued');

    new RevenueHubIntegrationWorker(job.Id).execute(null);

    Payment_Transaction__c processingPayment = [
      SELECT Status__c
      FROM Payment_Transaction__c
      WHERE Id = :payment.Id
      WITH SYSTEM_MODE
    ];
    Integration_Job__c processingJob = [
      SELECT Status__c
      FROM Integration_Job__c
      WHERE Id = :job.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Processing', processingPayment.Status__c);
    System.assertEquals('Processing', processingJob.Status__c);

    new RevenueHubIntegrationExecutionWorker(job.Id).execute(null);

    Payment_Transaction__c completedPayment = [
      SELECT Status__c, External_Transaction_Id__c, Payment_URL__c
      FROM Payment_Transaction__c
      WHERE Id = :payment.Id
      WITH SYSTEM_MODE
    ];
    Integration_Job__c completedJob = [
      SELECT Status__c, Attempt_Count__c
      FROM Integration_Job__c
      WHERE Id = :job.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Succeeded', completedPayment.Status__c);
    System.assert(
      completedPayment.External_Transaction_Id__c.startsWith('MOCK-PAY-')
    );
    System.assert(
      completedPayment.Payment_URL__c.startsWith('https://example.invalid/')
    );
    System.assertEquals('Completed', completedJob.Status__c);
    System.assertEquals(1, completedJob.Attempt_Count__c);
  }

  @IsTest
  static void completesMockDocumentProcessing() {
    Id quoteId = createQuote();
    Document_Request__c documentRequest = new Document_Request__c(
      Quote__c = quoteId,
      Status__c = 'Processing',
      Document_Provider__c = 'Mock',
      Template_Key__c = 'STANDARD',
      Requested_At__c = System.now()
    );
    Database.insert(documentRequest, AccessLevel.SYSTEM_MODE);
    Integration_Job__c job = createJob(
      null,
      documentRequest.Id,
      'Document',
      'Processing'
    );

    new RevenueHubIntegrationExecutionWorker(job.Id).execute(null);

    Document_Request__c completedRequest = [
      SELECT Status__c, External_Document_Id__c, Document_URL__c
      FROM Document_Request__c
      WHERE Id = :documentRequest.Id
      WITH SYSTEM_MODE
    ];
    Integration_Job__c completedJob = [
      SELECT Status__c, Attempt_Count__c
      FROM Integration_Job__c
      WHERE Id = :job.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Generated', completedRequest.Status__c);
    System.assert(
      completedRequest.External_Document_Id__c.startsWith('MOCK-DOC-')
    );
    System.assert(
      completedRequest.Document_URL__c.startsWith('https://example.invalid/')
    );
    System.assertEquals('Completed', completedJob.Status__c);
    System.assertEquals(1, completedJob.Attempt_Count__c);
  }

  @IsTest
  static void claimsQueuedDocumentAndCompletesMockProcessing() {
    Id quoteId = createQuote();
    Document_Request__c documentRequest = new Document_Request__c(
      Quote__c = quoteId,
      Status__c = 'Queued',
      Document_Provider__c = 'Mock',
      Template_Key__c = 'STANDARD',
      Requested_At__c = System.now()
    );
    Database.insert(documentRequest, AccessLevel.SYSTEM_MODE);
    Integration_Job__c job = createJob(
      null,
      documentRequest.Id,
      'Document',
      'Queued'
    );

    new RevenueHubIntegrationWorker(job.Id).execute(null);

    Document_Request__c processingRequest = [
      SELECT Status__c
      FROM Document_Request__c
      WHERE Id = :documentRequest.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Processing', processingRequest.Status__c);

    new RevenueHubIntegrationExecutionWorker(job.Id).execute(null);

    Document_Request__c completedRequest = [
      SELECT Status__c
      FROM Document_Request__c
      WHERE Id = :documentRequest.Id
      WITH SYSTEM_MODE
    ];
    Integration_Job__c completedJob = [
      SELECT Status__c, Attempt_Count__c
      FROM Integration_Job__c
      WHERE Id = :job.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Generated', completedRequest.Status__c);
    System.assertEquals('Completed', completedJob.Status__c);
    System.assertEquals(1, completedJob.Attempt_Count__c);
  }

  @IsTest
  static void ignoresMissingAndNonQueuedJobs() {
    Id quoteId = createQuote();
    Payment_Transaction__c payment = createPayment(quoteId, 'Mock', 'Queued');
    Integration_Job__c job = createJob(
      payment.Id,
      null,
      'Payment',
      'Processing'
    );

    new RevenueHubIntegrationWorker(job.Id).execute(null);
    Integration_Job__c unchangedJob = [
      SELECT Status__c
      FROM Integration_Job__c
      WHERE Id = :job.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Processing', unchangedJob.Status__c);

    Database.delete(job, AccessLevel.SYSTEM_MODE);
    new RevenueHubIntegrationWorker(job.Id).execute(null);
  }

  @IsTest
  static void deadLettersQueuedJobWithNonQueuedPayment() {
    Id quoteId = createQuote();
    Payment_Transaction__c payment = createPayment(quoteId, 'Mock', 'Failed');
    Integration_Job__c job = createJob(payment.Id, null, 'Payment', 'Queued');

    new RevenueHubIntegrationWorker(job.Id).execute(null);

    Integration_Job__c deadLetterJob = [
      SELECT Status__c, Error_Category__c, Completed_At__c
      FROM Integration_Job__c
      WHERE Id = :job.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Dead Letter', deadLetterJob.Status__c);
    System.assertEquals('Validation', deadLetterJob.Error_Category__c);
    System.assertNotEquals(null, deadLetterJob.Completed_At__c);
  }

  @IsTest
  static void marksUnimplementedProviderAsPermanentFailure() {
    Id quoteId = createQuote();
    Payment_Transaction__c payment = createPayment(
      quoteId,
      'Stripe',
      'Processing'
    );
    Integration_Job__c job = createJob(
      payment.Id,
      null,
      'Payment',
      'Processing'
    );

    new RevenueHubIntegrationExecutionWorker(job.Id).execute(null);

    Payment_Transaction__c failedPayment = [
      SELECT Status__c, Failure_Reason__c
      FROM Payment_Transaction__c
      WHERE Id = :payment.Id
      WITH SYSTEM_MODE
    ];
    Integration_Job__c failedJob = [
      SELECT Status__c, Error_Category__c, Attempt_Count__c
      FROM Integration_Job__c
      WHERE Id = :job.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Failed', failedPayment.Status__c);
    System.assertEquals('Failed', failedJob.Status__c);
    System.assertEquals('Configuration', failedJob.Error_Category__c);
    System.assertEquals(1, failedJob.Attempt_Count__c);
    System.assert(
      failedPayment.Failure_Reason__c.contains('provider did not complete')
    );
  }

  @IsTest
  static void dispatchesOneDueRetry() {
    RevenueHubIntegrationWorker.suppressEnqueueForTest = true;
    Id quoteId = createQuote();
    Payment_Transaction__c payment = createPayment(quoteId, 'Mock', 'Failed');
    payment.Completed_At__c = System.now();
    payment.Failure_Reason__c = 'A sanitized test failure.';
    Database.update(payment, AccessLevel.SYSTEM_MODE);
    Integration_Job__c job = createJob(
      payment.Id,
      null,
      'Payment',
      'Retry Scheduled'
    );
    job.Next_Retry_At__c = System.now().addMinutes(-1);
    job.Error_Category__c = 'Network';
    Database.update(job, AccessLevel.SYSTEM_MODE);

    new RevenueHubRetryDispatcher().execute(null);

    Payment_Transaction__c completedPayment = [
      SELECT Status__c, Completed_At__c
      FROM Payment_Transaction__c
      WHERE Id = :payment.Id
      WITH SYSTEM_MODE
    ];
    Integration_Job__c completedJob = [
      SELECT Status__c, Next_Retry_At__c, Error_Category__c
      FROM Integration_Job__c
      WHERE Id = :job.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Queued', completedPayment.Status__c);
    System.assertEquals(null, completedPayment.Completed_At__c);
    System.assertEquals('Queued', completedJob.Status__c);
    System.assertEquals(null, completedJob.Next_Retry_At__c);
    System.assertEquals(null, completedJob.Error_Category__c);
  }

  @IsTest
  static void dispatchesDueDocumentRetry() {
    RevenueHubIntegrationWorker.suppressEnqueueForTest = true;
    Id quoteId = createQuote();
    Document_Request__c documentRequest = new Document_Request__c(
      Quote__c = quoteId,
      Status__c = 'Failed',
      Document_Provider__c = 'Mock',
      Template_Key__c = 'STANDARD',
      Requested_At__c = System.now(),
      Completed_At__c = System.now(),
      Failure_Reason__c = 'A sanitized test failure.'
    );
    Database.insert(documentRequest, AccessLevel.SYSTEM_MODE);
    Integration_Job__c job = createJob(
      null,
      documentRequest.Id,
      'Document',
      'Retry Scheduled'
    );
    job.Next_Retry_At__c = System.now().addMinutes(-1);
    job.Error_Category__c = 'Network';
    Database.update(job, AccessLevel.SYSTEM_MODE);

    new RevenueHubRetryDispatcher().execute(null);

    Document_Request__c queuedDocument = [
      SELECT Status__c, Completed_At__c
      FROM Document_Request__c
      WHERE Id = :documentRequest.Id
      WITH SYSTEM_MODE
    ];
    Integration_Job__c queuedJob = [
      SELECT Status__c, Next_Retry_At__c, Error_Category__c
      FROM Integration_Job__c
      WHERE Id = :job.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Queued', queuedDocument.Status__c);
    System.assertEquals(null, queuedDocument.Completed_At__c);
    System.assertEquals('Queued', queuedJob.Status__c);
    System.assertEquals(null, queuedJob.Next_Retry_At__c);
    System.assertEquals(null, queuedJob.Error_Category__c);
  }

  @IsTest
  static void leavesJobsAloneWhenNoRetriesAreDue() {
    new RevenueHubRetryDispatcher().execute(null);
    System.assertEquals(0, Limits.getQueueableJobs());
  }

  private static Id createQuote() {
    Account accountRecord = new Account(Name = 'Revenue Hub Test Account');
    Database.insert(accountRecord, AccessLevel.SYSTEM_MODE);

    Opportunity opportunity = new Opportunity(
      Name = 'Revenue Hub Test Opportunity',
      AccountId = accountRecord.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
    );
    Database.insert(opportunity, AccessLevel.SYSTEM_MODE);

    Quote quoteRecord = new Quote(
      Name = 'Revenue Hub Test Quote',
      OpportunityId = opportunity.Id,
      Status = 'Approved'
    );
    Database.insert(quoteRecord, AccessLevel.SYSTEM_MODE);
    return quoteRecord.Id;
  }

  private static Payment_Transaction__c createPayment(
    Id quoteId,
    String provider,
    String status
  ) {
    Quote quoteRecord = [
      SELECT OpportunityId
      FROM Quote
      WHERE Id = :quoteId
      WITH SYSTEM_MODE
    ];
    Payment_Transaction__c payment = new Payment_Transaction__c(
      Opportunity__c = quoteRecord.OpportunityId,
      Quote__c = quoteId,
      Amount__c = 100,
      Status__c = status,
      Payment_Provider__c = provider,
      Logical_Payment_Key__c = 'TEST-' + String.valueOf(quoteId),
      Idempotency_Key__c = 'TEST-' +
        RevenueHubRequestPolicy.generateRandomToken(),
      Requested_At__c = System.now(),
      Completed_At__c = status == 'Failed' ? System.now() : null,
      Failure_Reason__c = status == 'Failed'
        ? 'A sanitized test failure.'
        : null
    );
    Database.insert(payment, AccessLevel.SYSTEM_MODE);
    return payment;
  }

  private static Integration_Job__c createJob(
    Id paymentId,
    Id documentRequestId,
    String integrationType,
    String status
  ) {
    Integration_Job__c job = new Integration_Job__c(
      Correlation_Id__c = RevenueHubRequestPolicy.generateRandomToken(),
      Integration_Type__c = integrationType,
      Payment_Transaction__c = paymentId,
      Document_Request__c = documentRequestId,
      Status__c = status,
      Maximum_Attempts__c = RevenueHubRetryPolicy.MAXIMUM_ATTEMPTS
    );
    if (status == 'Processing') {
      job.Started_At__c = System.now();
    }
    if (status == 'Retry Scheduled') {
      job.Started_At__c = System.now();
    }
    Database.insert(job, AccessLevel.SYSTEM_MODE);
    return job;
  }
}
