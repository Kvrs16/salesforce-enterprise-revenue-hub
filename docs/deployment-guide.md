# Deployment Guide

## Current status

The metadata was deployed successfully to the non-production Developer Edition org `practice-org-1` (deployment ID `0Afg500000GaSNxCAN`). All 21 selected Apex tests passed. The org accepted Quote-dependent metadata and test records. Local formatting, lint, offline Metadata API conversion, and all 3 LWC Jest tests passed. No Git push was made.

## Prerequisites

- Latest stable Salesforce CLI
- Git and Node.js LTS
- Salesforce Extension Pack
- A compatible non-production Salesforce development org
- Standard Quotes and Quote Line Items available in the target org

## Local checks

From the project directory, run the local checks:

```powershell
sf --version
npm run prettier:verify
npm run lint
npm run test:unit
```

For this non-source-tracked Developer Edition org, use `sf project deploy start --dry-run` rather than `sf project deploy preview` for a check-only deployment. The check-only deployment and selected Apex tests have passed.

## Org setup and deployment

The current metadata deployment is complete. Do not deploy to production. No credentials or provider secrets are needed for the mock baseline.

Automatic retry processing is not scheduled by deploying the Apex class alone. The owner-approved dispatcher is scheduled hourly in `practice-org-1`, at the top of the hour. It dispatches at most one due retry per run, so additional due retries wait for the next hourly run. To recreate it after removal, run `scripts/apex/schedule-retry-dispatcher.apex` once with `sf apex run --file scripts/apex/schedule-retry-dispatcher.apex --target-org practice-org-1`.

## Secrets

Do not commit `.sf`, `.sfdx`, local auth files, `.env` files, keys, or provider tokens. Real provider setup belongs in Named Credentials and External Credentials configured in the target org.
