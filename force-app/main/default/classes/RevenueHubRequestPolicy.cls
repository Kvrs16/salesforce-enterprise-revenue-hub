public inherited sharing class RevenueHubRequestPolicy {
  public static void requireUserActionPermission() {
    if (!FeatureManagement.checkPermission('Use_Revenue_Hub_Actions')) {
      throw handledException(
        'You do not have permission to request Revenue Hub actions.'
      );
    }
  }

  public static Quote getApprovedQuote(Id quoteId) {
    if (quoteId == null) {
      throw handledException('A Quote is required.');
    }

    List<Quote> quotes = [
      SELECT Id, OpportunityId, Status, GrandTotal
      FROM Quote
      WHERE Id = :quoteId
      WITH USER_MODE
      LIMIT 1
    ];
    if (quotes.isEmpty()) {
      throw handledException('The Quote was not found or is not accessible.');
    }

    Quote quoteRecord = quotes[0];
    if (quoteRecord.Status != 'Approved') {
      throw handledException('Only approved Quotes can be processed.');
    }
    if (
      quoteRecord.OpportunityId == null ||
      quoteRecord.GrandTotal == null ||
      quoteRecord.GrandTotal <= 0
    ) {
      throw handledException(
        'The approved Quote must have an Opportunity and a positive total.'
      );
    }

    return quoteRecord;
  }

  public static AuraHandledException handledException(String message) {
    AuraHandledException handledError = new AuraHandledException(message);
    handledError.setMessage(message);
    return handledError;
  }

  public static String generateRandomToken() {
    return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
  }
}
