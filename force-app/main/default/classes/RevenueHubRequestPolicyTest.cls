@IsTest
private class RevenueHubRequestPolicyTest {
  @IsTest
  static void blocksActionsWithoutCustomPermission() {
    Boolean permissionDenied = false;
    try {
      RevenueHubRequestPolicy.requireUserActionPermission();
    } catch (AuraHandledException caughtException) {
      permissionDenied = caughtException.getMessage().contains('permission');
    }

    System.assert(
      permissionDenied,
      'A user without the custom permission must not start a Revenue Hub action.'
    );
  }

  @IsTest
  static void rejectsMissingQuoteId() {
    Boolean quoteRejected = false;
    try {
      RevenueHubRequestPolicy.getApprovedQuote(null);
    } catch (AuraHandledException caughtException) {
      quoteRejected = caughtException.getMessage()
        .contains('Quote is required');
    }

    System.assert(
      quoteRejected,
      'A missing Quote ID must be rejected before any query is run.'
    );
  }
}
