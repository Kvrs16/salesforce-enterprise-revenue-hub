# Security Model

## Trust boundaries

- Salesforce record access, object permissions, field-level security, and custom permissions are enforced server-side.
- LWC inputs are untrusted. Apex re-queries the Opportunity and Quote, verifies their relationship and approval/eligibility, and derives the amount from the Quote.
- A payment checkout redirect is not proof of payment. Only an authoritative provider-side confirmation may move a transaction to `Succeeded`.
- The baseline mock provider is a simulation, not production payment security. Real webhook processing requires an external authenticated receiver that validates signatures over the raw body, timestamp tolerance, replay protection, and duplicate event IDs.
- Provider credentials never belong in Apex, JavaScript, custom metadata, or source control. Optional real adapters use Named Credentials and External Credentials.

## Permission sets

Create three least-privilege permission sets:

| Permission set                  | Intended access                                                                                                              |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `Revenue_Hub_User`              | Read records available through sharing; `Use_Revenue_Hub_Actions` custom permission for authorized payment/document requests |
| `Revenue_Hub_Manager`           | User actions plus appropriate inherited/shared record visibility; no direct status or amount editing                         |
| `Revenue_Hub_Integration_Admin` | Read sanitized job and attempt data; `Manage_Revenue_Integration_Jobs` custom permission for the manual retry service        |

None grants System Administrator, Modify All Data, direct status edits, or access to secrets. Add Apex class access only for implemented classes.

## Apex access rules

Controllers declare sharing explicitly, use user-mode queries, and check custom permissions. Payment/document creation uses explicit system-mode DML only after the caller passes the action custom permission and a user-mode approved-Quote query; amounts and relationships are derived from that Quote. Manual retry requires the integration-admin custom permission and a user-visible job row. Async workers use explicit system-mode queries and DML only for persisted, validated job IDs and their related records; they do not accept amounts, status values, or arbitrary parent IDs from the browser.

Custom objects remain Private. The integration-admin permission set receives View All only for integration jobs and attempt history; it does not grant View All or Modify All on payment or document records. Lookups and Quote/Opportunity relationships are revalidated in Apex; relationship consistency is also protected by validation rules. Dynamic SOQL is unnecessary for the baseline.

## Threats and mitigations

| Threat                                | Mitigation                                                                                                             | Residual risk                                                                   |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Unauthorized payment or retry         | Custom permissions checked in Apex; no direct object edit access                                                       | Misassigned permission sets                                                     |
| Amount/record manipulation            | Server-side relationship and Quote total validation; immutable amount after queueing                                   | Quote price changes before request are handled by re-reading at initiation      |
| Duplicate charges                     | Unique logical payment key and persisted provider idempotency key; retry reuses both                                   | Provider-specific idempotency retention varies                                  |
| Forged/replayed webhook               | No public Salesforce webhook in baseline; optional external verifier checks signature, timestamp, and event uniqueness | External receiver and credential configuration require separate security review |
| Unauthorized document access          | Private sharing, Quote access checks, minimal provider links                                                           | Provider-hosted links may have their own exposure controls                      |
| Sensitive data leakage                | Never store card data or auth headers; sanitize logs and provider errors                                               | Provider errors still require review before persistence                         |
| SOQL injection / privilege escalation | Bind variables, user-mode access, explicit custom permissions, no client-authoritative status                          | Apex async system context remains privileged and requires code review           |
| Retry abuse                           | Bounded exponential backoff, manual retry permission, duplicate job locking                                            | Org scheduling limits and provider throttling                                   |

## Data retention

Integration records store correlation and sanitized operational data only. Define a retention/cleanup policy before production-like volumes; do not delete records automatically in the foundation phase.

## Environment notes

The inspected Developer Edition org is single-currency and does not expose Quote objects. No org settings or credentials were changed. Quote enablement and deployment require explicit, separately reviewed execution.
