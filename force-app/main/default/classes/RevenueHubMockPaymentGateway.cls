public class RevenueHubMockPaymentGateway implements RevenueHubPaymentGateway {
  public RevenueHubIntegrationResult createPayment(
    Payment_Transaction__c payment
  ) {
    RevenueHubIntegrationResult result = new RevenueHubIntegrationResult();
    result.outcome = 'Succeeded';
    result.externalId = 'MOCK-PAY-' + String.valueOf(payment.Id);
    result.resourceUrl =
      'https://example.invalid/mock-payments/' + String.valueOf(payment.Id);
    result.retryable = false;
    return result;
  }
}
