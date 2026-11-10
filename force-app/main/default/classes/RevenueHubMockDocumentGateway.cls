public class RevenueHubMockDocumentGateway implements RevenueHubDocumentGateway {
  public RevenueHubIntegrationResult createDocument(
    Document_Request__c documentRequest
  ) {
    RevenueHubIntegrationResult result = new RevenueHubIntegrationResult();
    result.outcome = 'Succeeded';
    result.externalId = 'MOCK-DOC-' + String.valueOf(documentRequest.Id);
    result.resourceUrl =
      'https://example.invalid/mock-documents/' +
      String.valueOf(documentRequest.Id);
    result.retryable = false;
    return result;
  }
}
