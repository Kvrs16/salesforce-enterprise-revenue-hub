public class RevenueHubRetryPolicy {
  public static final Integer MAXIMUM_ATTEMPTS = 3;
  private static final Integer MAXIMUM_DELAY_MINUTES = 60;

  public static DateTime nextRetryAt(Integer attemptNumber) {
    if (attemptNumber == null || attemptNumber < 1) {
      throw new IllegalArgumentException(
        'Attempt number must be a positive integer.'
      );
    }
    Integer delayMinutes = 1;
    for (
      Integer completedAttempt = 1;
      completedAttempt < attemptNumber;
      completedAttempt++
    ) {
      if (delayMinutes >= MAXIMUM_DELAY_MINUTES / 2) {
        delayMinutes = MAXIMUM_DELAY_MINUTES;
        break;
      }
      delayMinutes *= 2;
    }
    return System.now().addMinutes(delayMinutes);
  }
}
