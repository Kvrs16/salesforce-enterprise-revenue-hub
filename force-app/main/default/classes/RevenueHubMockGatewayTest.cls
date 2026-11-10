@IsTest
private class RevenueHubMockGatewayTest {
  @IsTest
  static void paymentGatewayReturnsExplicitSimulation() {
    Payment_Transaction__c payment = new Payment_Transaction__c();

    RevenueHubIntegrationResult result = new RevenueHubMockPaymentGateway()
      .createPayment(payment);

    System.assertEquals('Succeeded', result.outcome);
    System.assertEquals(false, result.retryable);
    System.assert(
      result.externalId.startsWith('MOCK-PAY-'),
      'The external ID should identify a mock result.'
    );
    System.assert(
      result.resourceUrl.startsWith('https://example.invalid/'),
      'The mock URL must not resolve to a real payment provider.'
    );
  }

  @IsTest
  static void documentGatewayReturnsExplicitSimulation() {
    Document_Request__c documentRequest = new Document_Request__c();

    RevenueHubIntegrationResult result = new RevenueHubMockDocumentGateway()
      .createDocument(documentRequest);

    System.assertEquals('Succeeded', result.outcome);
    System.assertEquals(false, result.retryable);
    System.assert(
      result.externalId.startsWith('MOCK-DOC-'),
      'The external ID should identify a mock result.'
    );
    System.assert(
      result.resourceUrl.startsWith('https://example.invalid/'),
      'The mock URL must not resolve to a real document provider.'
    );
  }
}
