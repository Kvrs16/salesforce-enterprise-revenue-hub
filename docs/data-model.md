# Data Model

## Standard objects

Use `Account`, `Contact`, `Opportunity`, `Product2`, `Pricebook2`, `PricebookEntry`, `OpportunityLineItem`, `Quote`, `QuoteLineItem`, and Salesforce Files. Do not copy standard pricing or Quote totals into a parallel custom quote model.

The target org accepted Quote- and QuoteLineItem-dependent metadata and Apex tests. The org is single-currency; do not add a competing `Currency_Code__c` field.

Fields used by the application are enforced as nonblank by object validation rules rather than field-level required flags. This allows permission sets to retain read-only access to operational fields while preserving data integrity.

## Custom objects

### `Payment_Transaction__c`

One full-Quote payment request; split payments and installments are outside the baseline.

| Field                        | Type                           | Purpose                                                                   |
| ---------------------------- | ------------------------------ | ------------------------------------------------------------------------- |
| `Name`                       | Auto Number `PAY-{000000}`     | Internal transaction number                                               |
| `Opportunity__c`             | Required Lookup(Opportunity)   | Navigation and reporting                                                  |
| `Quote__c`                   | Required Lookup(Quote)         | Approved payment source                                                   |
| `Amount__c`                  | Currency(18,2)                 | Immutable server-derived snapshot of approved Quote total                 |
| `Status__c`                  | Restricted Picklist            | `Draft`, `Queued`, `Processing`, `Succeeded`, `Failed`, `Cancelled`       |
| `Payment_Provider__c`        | Restricted Picklist            | `Mock`, `Stripe` (Stripe is optional and not implemented in the baseline) |
| `Logical_Payment_Key__c`     | Text(80), Unique, External ID  | One logical full payment per Quote                                        |
| `Idempotency_Key__c`         | Text(255), Unique, External ID | Provider idempotency key reused for retries                               |
| `External_Transaction_Id__c` | Text(255), External ID         | Provider transaction identifier                                           |
| `Payment_URL__c`             | URL                            | Provider-hosted checkout link, when available                             |
| `Requested_At__c`            | Date/Time                      | Initiation time                                                           |
| `Completed_At__c`            | Date/Time                      | Authoritative terminal outcome time                                       |
| `Failure_Reason__c`          | Long Text Area                 | Sanitized user-safe failure                                               |

Both lookups use restrictive delete behavior. A validation rule enforces that the selected Quote belongs to the selected Opportunity and that the amount is positive. The service derives amount and keys server-side; users cannot set payment status or amount directly. Payment success is not inferred from a checkout redirect.

### `Document_Request__c`

| Field                                 | Type                       | Purpose                                                                       |
| ------------------------------------- | -------------------------- | ----------------------------------------------------------------------------- |
| `Name`                                | Auto Number `DOC-{000000}` | Request number                                                                |
| `Quote__c`                            | Required Lookup(Quote)     | Source for an approved document request                                       |
| `Status__c`                           | Restricted Picklist        | `Draft`, `Queued`, `Processing`, `Generated`, `Failed`, `Cancelled`           |
| `Document_Provider__c`                | Restricted Picklist        | `Mock`, `PandaDoc` (PandaDoc is optional and not implemented in the baseline) |
| `Template_Key__c`                     | Text(100)                  | Non-secret template mapping key                                               |
| `External_Document_Id__c`             | Text(255), External ID     | Provider document identifier                                                  |
| `Document_URL__c`                     | URL                        | Provider document link, when available                                        |
| `Requested_At__c` / `Completed_At__c` | Date/Time                  | Lifecycle timestamps                                                          |
| `Failure_Reason__c`                   | Long Text Area             | Sanitized failure                                                             |

The Quote lookup restricts deletion. A mock response is explicitly simulated; it does not imply a real generated file. When an actual file is produced, link a `ContentVersion` through Salesforce Files rather than storing base64 in this record.

### `Integration_Job__c`

One logical outbound operation. It references exactly one payment transaction or document request through real lookups; it does not store a Salesforce record ID in free text.

| Field                               | Type                             | Purpose                                                                                      |
| ----------------------------------- | -------------------------------- | -------------------------------------------------------------------------------------------- |
| `Name`                              | Auto Number `JOB-{000000}`       | Job number                                                                                   |
| `Correlation_Id__c`                 | Text(36), Unique, External ID    | Cross-layer trace identifier                                                                 |
| `Integration_Type__c`               | Restricted Picklist              | `Payment`, `Document`                                                                        |
| `Payment_Transaction__c`            | Lookup(Payment Transaction)      | Payment parent                                                                               |
| `Document_Request__c`               | Lookup(Document Request)         | Document parent                                                                              |
| `Status__c`                         | Restricted Picklist              | `Queued`, `Processing`, `Completed`, `Failed`, `Retry Scheduled`, `Dead Letter`, `Cancelled` |
| `Attempt_Count__c`                  | Roll-Up Summary (count attempts) | Attempt history count                                                                        |
| `Maximum_Attempts__c`               | Number(2,0), default 3           | Bounded retry ceiling                                                                        |
| `Next_Retry_At__c`                  | Date/Time                        | Scheduled dispatch eligibility                                                               |
| `Last_HTTP_Status__c`               | Number(3,0)                      | Last response status, if any                                                                 |
| `Started_At__c` / `Completed_At__c` | Date/Time                        | Job timestamps                                                                               |
| `Error_Category__c`                 | Restricted Picklist              | Sanitized operational classification                                                         |
| `Sanitized_Error__c`                | Long Text Area                   | Redacted error summary                                                                       |
| `External_Request_Id__c`            | Text(255)                        | Provider request correlation                                                                 |

A validation rule requires exactly one related payment/document and requires that it match `Integration_Type__c`. Restrict deletion to preserve audit history.

### `Integration_Attempt__c`

Master-detail child of `Integration_Job__c`; deleting a job deletes its attempts. Keep job deletion unavailable to application users.

Fields: auto-number `Name` (`ATT-{000000}`), required `Attempt_Number__c`, `Started_At__c`, `Completed_At__c`, `HTTP_Status__c`, restricted `Outcome__c` (`Succeeded`, `Failed`, `Timed Out`), and sanitized `Sanitized_Error__c`.

## State transitions

| Entity           | Allowed transitions                                                                                                                                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Payment          | Draft -> Queued -> Processing -> Succeeded or Failed; Draft/Queued -> Cancelled; Failed -> Queued only for an authorized retry                                                                                      |
| Document request | Draft -> Queued -> Processing -> Generated or Failed; Draft/Queued -> Cancelled; Failed -> Queued only for an authorized retry                                                                                      |
| Integration job  | Queued -> Processing; Processing -> Completed, Failed, Retry Scheduled, or Dead Letter; Retry Scheduled -> Queued or Dead Letter; Failed -> Queued only for an authorized retry or Dead Letter; Queued -> Cancelled |

Enforce transitions in the Apex domain policy and with metadata validation rules; do not accept arbitrary UI status updates. Refund and signature states are not implemented in the baseline.

## Ownership and sharing

Custom business and integration objects use Private organization-wide defaults. Attempt history inherits its parent job's access. Managers receive access through configured role hierarchy/sharing policy, not broad object permissions. Final sharing behavior must be tested with representative users in the target org.
