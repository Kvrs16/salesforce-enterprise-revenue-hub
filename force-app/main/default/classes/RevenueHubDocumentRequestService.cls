public with sharing class RevenueHubDocumentRequestService {
  private static final Integer MAXIMUM_TEMPLATE_KEY_LENGTH = 100;

  @AuraEnabled
  public static Id requestDocument(Id quoteId, String templateKey) {
    RevenueHubRequestPolicy.requireUserActionPermission();
    Quote quoteRecord = RevenueHubRequestPolicy.getApprovedQuote(quoteId);

    String normalizedTemplateKey = templateKey == null
      ? null
      : templateKey.trim();
    if (
      String.isBlank(normalizedTemplateKey) ||
      normalizedTemplateKey.length() > MAXIMUM_TEMPLATE_KEY_LENGTH
    ) {
      throw RevenueHubRequestPolicy.handledException(
        'A valid document template key is required.'
      );
    }

    Document_Request__c documentRequest = new Document_Request__c(
      Quote__c = quoteRecord.Id,
      Status__c = 'Queued',
      Document_Provider__c = 'Mock',
      Template_Key__c = normalizedTemplateKey,
      Requested_At__c = System.now()
    );
    Database.insert(documentRequest, AccessLevel.SYSTEM_MODE);

    Integration_Job__c job = new Integration_Job__c(
      Correlation_Id__c = RevenueHubRequestPolicy.generateRandomToken(),
      Integration_Type__c = 'Document',
      Document_Request__c = documentRequest.Id,
      Status__c = 'Queued',
      Maximum_Attempts__c = RevenueHubRetryPolicy.MAXIMUM_ATTEMPTS
    );
    Database.insert(job, AccessLevel.SYSTEM_MODE);

    RevenueHubIntegrationWorker.enqueueIntegrationJob(job.Id);
    return documentRequest.Id;
  }
}
