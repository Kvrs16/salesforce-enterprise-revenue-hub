System.schedule(
    'Revenue Hub Retry Dispatcher',
    '0 0 * * * ?',
    new RevenueHubRetryDispatcher()
);
