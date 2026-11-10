@IsTest
private class RevenueHubServiceTest {
  @IsTest
  static void requestsPaymentAndDocumentForApprovedQuote() {
    RevenueHubIntegrationWorker.suppressEnqueueForTest = true;
    User requestUser = createUser('Revenue_Hub_User');
    System.runAs(requestUser) {
      Quote quoteRecord = createQuote(true, 'Approved');

      Id paymentId = RevenueHubPaymentRequestService.requestPayment(
        quoteRecord.Id
      );
      Id existingPaymentId = RevenueHubPaymentRequestService.requestPayment(
        quoteRecord.Id
      );
      Id documentRequestId = RevenueHubDocumentRequestService.requestDocument(
        quoteRecord.Id,
        ' STANDARD '
      );

      System.assertEquals(paymentId, existingPaymentId);
      Payment_Transaction__c payment = [
        SELECT Amount__c, Logical_Payment_Key__c, Idempotency_Key__c
        FROM Payment_Transaction__c
        WHERE Id = :paymentId
        WITH SYSTEM_MODE
      ];
      System.assertEquals(100, payment.Amount__c);
      System.assertEquals(
        'QUOTE-' + String.valueOf(quoteRecord.Id),
        payment.Logical_Payment_Key__c
      );
      System.assert(payment.Idempotency_Key__c.startsWith('MOCK-'));

      Document_Request__c documentRequest = [
        SELECT Template_Key__c, Status__c
        FROM Document_Request__c
        WHERE Id = :documentRequestId
        WITH SYSTEM_MODE
      ];
      System.assertEquals('STANDARD', documentRequest.Template_Key__c);
      System.assertEquals('Queued', documentRequest.Status__c);
    }
  }

  @IsTest
  static void rejectsInvalidRequestsAndUnapprovedQuotes() {
    RevenueHubIntegrationWorker.suppressEnqueueForTest = true;
    User requestUser = createUser('Revenue_Hub_User');
    System.runAs(requestUser) {
      Quote quoteRecord = createQuote(true, 'Approved');

      Boolean invalidTemplateRejected = false;
      try {
        RevenueHubDocumentRequestService.requestDocument(quoteRecord.Id, ' ');
      } catch (AuraHandledException caughtException) {
        invalidTemplateRejected = caughtException
          .getMessage()
          .contains('template key');
      }
      System.assert(invalidTemplateRejected);

      quoteRecord.Status = 'Draft';
      Database.update(quoteRecord, AccessLevel.SYSTEM_MODE);
      Boolean unapprovedQuoteRejected = false;
      try {
        RevenueHubPaymentRequestService.requestPayment(quoteRecord.Id);
      } catch (AuraHandledException caughtException) {
        unapprovedQuoteRejected = caughtException
          .getMessage()
          .contains('approved Quotes');
      }
      System.assert(unapprovedQuoteRejected);

      Quote emptyQuote = createQuote(false, 'Approved');
      Boolean emptyQuoteRejected = false;
      try {
        RevenueHubRequestPolicy.getApprovedQuote(emptyQuote.Id);
      } catch (AuraHandledException caughtException) {
        emptyQuoteRejected = caughtException
          .getMessage()
          .contains('positive total');
      }
      System.assert(emptyQuoteRejected);
    }
  }

  @IsTest
  static void doesNotReturnPaymentForConflictingLogicalKey() {
    RevenueHubIntegrationWorker.suppressEnqueueForTest = true;
    User requestUser = createUser('Revenue_Hub_User');
    System.runAs(requestUser) {
      Quote requestedQuote = createQuote(true, 'Approved');
      Quote conflictingQuote = createQuote(true, 'Approved');
      Payment_Transaction__c conflictingPayment = new Payment_Transaction__c(
        Opportunity__c = conflictingQuote.OpportunityId,
        Quote__c = conflictingQuote.Id,
        Amount__c = 100,
        Status__c = 'Queued',
        Payment_Provider__c = 'Mock',
        Logical_Payment_Key__c = 'QUOTE-' + requestedQuote.Id,
        Idempotency_Key__c = 'CONFLICT-' +
          RevenueHubRequestPolicy.generateRandomToken(),
        Requested_At__c = System.now()
      );
      Database.insert(conflictingPayment, AccessLevel.SYSTEM_MODE);

      Boolean conflictingKeyRejected = false;
      try {
        RevenueHubPaymentRequestService.requestPayment(requestedQuote.Id);
      } catch (AuraHandledException caughtException) {
        conflictingKeyRejected = caughtException
          .getMessage()
          .contains('already exists');
      }
      System.assert(conflictingKeyRejected);
    }
  }

  @IsTest
  static void monitorsJobsAndRetriesFailedPaymentAndDocument() {
    RevenueHubIntegrationWorker.suppressEnqueueForTest = true;
    User adminUser = createUser('Revenue_Hub_Integration_Admin');
    System.runAs(adminUser) {
      Quote quoteRecord = createQuote(true, 'Approved');
      Payment_Transaction__c payment = new Payment_Transaction__c(
        Opportunity__c = quoteRecord.OpportunityId,
        Quote__c = quoteRecord.Id,
        Amount__c = 100,
        Status__c = 'Failed',
        Payment_Provider__c = 'Mock',
        Logical_Payment_Key__c = 'MONITOR-' + quoteRecord.Id,
        Idempotency_Key__c = 'MONITOR-' + quoteRecord.Id,
        Requested_At__c = System.now(),
        Completed_At__c = System.now(),
        Failure_Reason__c = 'A sanitized test failure.'
      );
      Database.insert(payment, AccessLevel.SYSTEM_MODE);
      Integration_Job__c paymentJob = createFailedJob(
        payment.Id,
        null,
        'Payment'
      );

      Document_Request__c documentRequest = new Document_Request__c(
        Quote__c = quoteRecord.Id,
        Status__c = 'Failed',
        Document_Provider__c = 'Mock',
        Template_Key__c = 'STANDARD',
        Requested_At__c = System.now(),
        Completed_At__c = System.now(),
        Failure_Reason__c = 'A sanitized test failure.'
      );
      Database.insert(documentRequest, AccessLevel.SYSTEM_MODE);
      Integration_Job__c documentJob = createFailedJob(
        null,
        documentRequest.Id,
        'Document'
      );

      System.assertEquals(
        2,
        RevenueHubMonitoringController.getRecentJobs().size()
      );
      RevenueHubMonitoringController.retryJob(paymentJob.Id);
      RevenueHubMonitoringController.retryJob(documentJob.Id);

      Payment_Transaction__c queuedPayment = [
        SELECT Status__c, Completed_At__c
        FROM Payment_Transaction__c
        WHERE Id = :payment.Id
        WITH SYSTEM_MODE
      ];
      Document_Request__c queuedDocument = [
        SELECT Status__c, Completed_At__c
        FROM Document_Request__c
        WHERE Id = :documentRequest.Id
        WITH SYSTEM_MODE
      ];
      System.assertEquals('Queued', queuedPayment.Status__c);
      System.assertEquals(null, queuedPayment.Completed_At__c);
      System.assertEquals('Queued', queuedDocument.Status__c);
      System.assertEquals(null, queuedDocument.Completed_At__c);
    }
  }

  @IsTest
  static void enforcesAdminPermissionAndRejectsExhaustedRetry() {
    User requestUser = createUser('Revenue_Hub_User');
    System.runAs(requestUser) {
      Boolean permissionDenied = false;
      try {
        RevenueHubMonitoringController.retryJob(null);
      } catch (AuraHandledException caughtException) {
        permissionDenied = caughtException.getMessage().contains('permission');
      }
      System.assert(permissionDenied);
    }

    User adminUser = createUser('Revenue_Hub_Integration_Admin');
    System.runAs(adminUser) {
      Quote quoteRecord = createQuote(true, 'Approved');
      Payment_Transaction__c payment = new Payment_Transaction__c(
        Opportunity__c = quoteRecord.OpportunityId,
        Quote__c = quoteRecord.Id,
        Amount__c = 100,
        Status__c = 'Failed',
        Payment_Provider__c = 'Mock',
        Logical_Payment_Key__c = 'EXHAUSTED-' + quoteRecord.Id,
        Idempotency_Key__c = 'EXHAUSTED-' + quoteRecord.Id,
        Requested_At__c = System.now(),
        Completed_At__c = System.now(),
        Failure_Reason__c = 'A sanitized test failure.'
      );
      Database.insert(payment, AccessLevel.SYSTEM_MODE);
      Integration_Job__c job = createFailedJob(payment.Id, null, 'Payment');
      List<Integration_Attempt__c> attempts = new List<Integration_Attempt__c>();
      for (Integer attemptNumber = 1; attemptNumber <= 3; attemptNumber++) {
        attempts.add(
          new Integration_Attempt__c(
            Integration_Job__c = job.Id,
            Attempt_Number__c = attemptNumber,
            Started_At__c = System.now(),
            Completed_At__c = System.now(),
            Outcome__c = 'Failed'
          )
        );
      }
      Database.insert(attempts, AccessLevel.SYSTEM_MODE);

      Boolean exhaustedRetryRejected = false;
      try {
        RevenueHubMonitoringController.retryJob(job.Id);
      } catch (AuraHandledException caughtException) {
        exhaustedRetryRejected = caughtException
          .getMessage()
          .contains('attempts remaining');
      }
      System.assert(exhaustedRetryRejected);
    }
  }

  private static User createUser(String permissionSetName) {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE UserType = 'Standard'
      LIMIT 1
    ];
    User testUser = new User(
      Alias = 'revhub',
      Email = 'revenue-hub@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Revenue Hub Test',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standardProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'revenue-hub-' +
        RevenueHubRequestPolicy.generateRandomToken() +
        '@example.invalid'
    );
    Database.insert(testUser);

    PermissionSet permissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permissionSetName
      LIMIT 1
    ];
    Database.insert(
      new PermissionSetAssignment(
        AssigneeId = testUser.Id,
        PermissionSetId = permissionSet.Id
      )
    );
    return testUser;
  }

  private static Quote createQuote(Boolean addLineItem, String status) {
    Id standardPricebookId = Test.getStandardPricebookId();
    Product2 product = new Product2(
      Name = 'Revenue Hub Test Product',
      IsActive = true
    );
    Database.insert(product, AccessLevel.SYSTEM_MODE);
    PricebookEntry pricebookEntry = new PricebookEntry(
      Pricebook2Id = standardPricebookId,
      Product2Id = product.Id,
      UnitPrice = 100,
      IsActive = true
    );
    Database.insert(pricebookEntry, AccessLevel.SYSTEM_MODE);

    Account accountRecord = new Account(Name = 'Revenue Hub Test Account');
    Database.insert(accountRecord, AccessLevel.SYSTEM_MODE);
    Opportunity opportunity = new Opportunity(
      Name = 'Revenue Hub Test Opportunity',
      AccountId = accountRecord.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      Pricebook2Id = standardPricebookId
    );
    Database.insert(opportunity, AccessLevel.SYSTEM_MODE);

    Quote quoteRecord = new Quote(
      Name = 'Revenue Hub Test Quote',
      OpportunityId = opportunity.Id,
      Pricebook2Id = standardPricebookId,
      ExpirationDate = Date.today().addDays(30),
      Status = status
    );
    Database.insert(quoteRecord, AccessLevel.SYSTEM_MODE);
    if (addLineItem) {
      Database.insert(
        new QuoteLineItem(
          QuoteId = quoteRecord.Id,
          PricebookEntryId = pricebookEntry.Id,
          Quantity = 1,
          UnitPrice = 100
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
    return quoteRecord;
  }

  private static Integration_Job__c createFailedJob(
    Id paymentId,
    Id documentRequestId,
    String integrationType
  ) {
    Integration_Job__c job = new Integration_Job__c(
      Correlation_Id__c = RevenueHubRequestPolicy.generateRandomToken(),
      Integration_Type__c = integrationType,
      Payment_Transaction__c = paymentId,
      Document_Request__c = documentRequestId,
      Status__c = 'Failed',
      Maximum_Attempts__c = RevenueHubRetryPolicy.MAXIMUM_ATTEMPTS,
      Started_At__c = System.now(),
      Completed_At__c = System.now(),
      Error_Category__c = 'Provider',
      Sanitized_Error__c = 'A sanitized test failure.'
    );
    Database.insert(job, AccessLevel.SYSTEM_MODE);
    return job;
  }
}
