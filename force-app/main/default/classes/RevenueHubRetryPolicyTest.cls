@IsTest
private class RevenueHubRetryPolicyTest {
  @IsTest
  static void calculatesExponentialRetryDelay() {
    DateTime beforeCalculation = System.now();

    DateTime firstRetry = RevenueHubRetryPolicy.nextRetryAt(1);
    DateTime secondRetry = RevenueHubRetryPolicy.nextRetryAt(2);
    DateTime thirdRetry = RevenueHubRetryPolicy.nextRetryAt(3);

    System.assert(
      firstRetry >= beforeCalculation.addSeconds(59),
      'The first retry should be delayed by one minute.'
    );
    System.assert(
      firstRetry <= System.now().addSeconds(61),
      'The first retry should not exceed one minute.'
    );
    System.assert(
      secondRetry >= beforeCalculation.addSeconds(119),
      'The second retry should be delayed by two minutes.'
    );
    System.assert(
      secondRetry <= System.now().addSeconds(121),
      'The second retry should not exceed two minutes.'
    );
    System.assert(
      thirdRetry >= beforeCalculation.addSeconds(239),
      'The third retry should be delayed by four minutes.'
    );
    System.assert(
      thirdRetry <= System.now().addSeconds(241),
      'The third retry should not exceed four minutes.'
    );
  }

  @IsTest
  static void capsRetryDelay() {
    DateTime beforeCalculation = System.now();
    DateTime cappedRetry = RevenueHubRetryPolicy.nextRetryAt(10);

    System.assert(
      cappedRetry >= beforeCalculation.addSeconds(3599),
      'The retry delay should reach the one-hour cap.'
    );
    System.assert(
      cappedRetry <= System.now().addSeconds(3601),
      'The retry delay must not exceed the one-hour cap.'
    );
  }

  @IsTest
  static void rejectsInvalidAttemptNumber() {
    Boolean invalidAttemptRejected = false;
    try {
      RevenueHubRetryPolicy.nextRetryAt(0);
    } catch (IllegalArgumentException caughtException) {
      invalidAttemptRejected = caughtException
        .getMessage()
        .contains('positive integer');
    }

    System.assert(
      invalidAttemptRejected,
      'Retry scheduling must reject a zero attempt number.'
    );
  }
}
