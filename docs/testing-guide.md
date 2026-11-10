# Testing Guide

## Current status

The deployed `practice-org-1` run passed all 21 Apex tests across `RevenueHubIntegrationWorkerTest`, `RevenueHubMockGatewayTest`, `RevenueHubRequestPolicyTest`, `RevenueHubRetryPolicyTest`, and `RevenueHubServiceTest`. Coverage includes request authorization and validation, server-derived payment amount and idempotency, mock payment/document processing, retry dispatch and manual retry authorization, and retry policy bounds. The LWC Jest suite passes all 3 tests for Quote eligibility and payment request submission.

Run local checks from the project root:

```powershell
npm run prettier:verify
npm run lint
npm run test:unit
```

Run the Apex suite against a connected non-production org:

```powershell
sf apex run test --target-org practice-org-1 --test-level RunSpecifiedTests `
  --tests RevenueHubIntegrationWorkerTest `
  --tests RevenueHubMockGatewayTest `
  --tests RevenueHubRequestPolicyTest `
  --tests RevenueHubRetryPolicyTest `
  --tests RevenueHubServiceTest --wait 120 --result-format human
```

The provider implementations are mocks. Tests do not make real payment or document-provider calls.

## Planned test coverage

| Area             | Planned verification                                                                                                    |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Data model       | Required relationships, quote/opportunity consistency, positive amount, and valid state transitions                     |
| Security         | Permission-set field access, private sharing, and denied unauthorized request/retry actions                             |
| Payment service  | Approved Quote eligibility, server-derived amount, duplicate logical request, and idempotency reuse                     |
| Payment provider | Deterministic success, validation/auth/network/rate-limit/server failures, timeout, malformed/empty responses           |
| Document service | Template validation, duplicate request, generated status, and provider failures                                         |
| Retry            | Retryable vs permanent failure, bounded attempts, exhaustion, dead-letter, scheduled dispatch, and manual authorization |
| Bulk behavior    | Collection-based processing without SOQL/DML in loops                                                                   |
| LWC              | Approved/unapproved Quote eligibility, request invocation, loading/error/success states, and job refresh behavior       |
| Flows            | Dead-letter notification entry criteria, fault handling, and no recursive record update                                 |

## Reporting results

Mark tests as Passed only after executing them and recording the command/result. For blocked tests, state the missing org feature or dependency. Do not use `SeeAllData=true` unless an exceptional reason is documented.
