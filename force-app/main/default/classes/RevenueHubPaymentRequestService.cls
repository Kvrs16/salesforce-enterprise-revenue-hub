public with sharing class RevenueHubPaymentRequestService {
  @AuraEnabled
  public static Id requestPayment(Id quoteId) {
    RevenueHubRequestPolicy.requireUserActionPermission();
    Quote quoteRecord = RevenueHubRequestPolicy.getApprovedQuote(quoteId);

    List<Payment_Transaction__c> existingPayments = [
      SELECT Id
      FROM Payment_Transaction__c
      WHERE Quote__c = :quoteRecord.Id
      WITH USER_MODE
      LIMIT 1
    ];
    if (!existingPayments.isEmpty()) {
      return existingPayments[0].Id;
    }

    String logicalPaymentKey = 'QUOTE-' + String.valueOf(quoteRecord.Id);
    Payment_Transaction__c payment = new Payment_Transaction__c(
      Opportunity__c = quoteRecord.OpportunityId,
      Quote__c = quoteRecord.Id,
      Amount__c = quoteRecord.GrandTotal,
      Status__c = 'Queued',
      Payment_Provider__c = 'Mock',
      Logical_Payment_Key__c = logicalPaymentKey,
      Idempotency_Key__c = 'MOCK-' +
        RevenueHubRequestPolicy.generateRandomToken(),
      Requested_At__c = System.now()
    );
    Savepoint savepoint = Database.setSavepoint();
    try {
      Database.insert(payment, AccessLevel.SYSTEM_MODE);
    } catch (DmlException caughtException) {
      Boolean duplicatePayment = false;
      for (
        Integer errorIndex = 0;
        errorIndex < caughtException.getNumDml();
        errorIndex++
      ) {
        if (
          String.valueOf(caughtException.getDmlStatusCode(errorIndex)) ==
          'DUPLICATE_VALUE'
        ) {
          duplicatePayment = true;
          break;
        }
      }
      if (!duplicatePayment) {
        throw caughtException;
      }

      Database.rollback(savepoint);
      List<Payment_Transaction__c> concurrentPayments = [
        SELECT Id, Quote__c
        FROM Payment_Transaction__c
        WHERE Logical_Payment_Key__c = :logicalPaymentKey
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (
        !concurrentPayments.isEmpty() &&
        concurrentPayments[0].Quote__c == quoteRecord.Id
      ) {
        List<Payment_Transaction__c> visibleConcurrentPayment = [
          SELECT Id
          FROM Payment_Transaction__c
          WHERE Id = :concurrentPayments[0].Id
          WITH USER_MODE
          LIMIT 1
        ];
        if (!visibleConcurrentPayment.isEmpty()) {
          return visibleConcurrentPayment[0].Id;
        }
      }
      throw RevenueHubRequestPolicy.handledException(
        'A payment request already exists for this Quote. Contact the record owner if you cannot access it.'
      );
    }

    Integration_Job__c job = new Integration_Job__c(
      Correlation_Id__c = RevenueHubRequestPolicy.generateRandomToken(),
      Integration_Type__c = 'Payment',
      Payment_Transaction__c = payment.Id,
      Status__c = 'Queued',
      Maximum_Attempts__c = RevenueHubRetryPolicy.MAXIMUM_ATTEMPTS
    );
    Database.insert(job, AccessLevel.SYSTEM_MODE);

    RevenueHubIntegrationWorker.enqueueIntegrationJob(job.Id);
    return payment.Id;
  }
}
