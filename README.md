# Salesforce Enterprise Revenue & Integration Hub

A Salesforce application for requesting payment and document operations from approved Quotes, processing requests asynchronously, and monitoring integration outcomes.

## Features

- Lightning workspace for selecting eligible Quotes and submitting requests.
- Apex services that validate request permissions and Quote eligibility.
- Asynchronous processing through Queueable Apex.
- Logical payment deduplication and controlled state transitions.
- Integration job monitoring, attempt history, and operator retry actions.
- Deterministic mock payment and document gateways.
- Role-specific permission sets and Apex and LWC tests.

## Application workflow

```text
Approved Quote
  -> Payment or document request
  -> Integration job
  -> Queueable processing
  -> Mock gateway
  -> Result and attempt history
```

The application uses standard Salesforce Quote and pricing objects. It is not a CPQ implementation.

## Implementation scope

The current implementation includes request services, mock gateways, asynchronous workers, retry scheduling, and a Lightning monitoring workspace.

Payment and document responses are simulated. Real Stripe and PandaDoc adapters, payment processing, provider-generated documents, and verified webhooks remain future work.

## Technology stack

Salesforce DX, Apex, Queueable Apex, Lightning Web Components, standard Salesforce approval configuration, Salesforce CLI, and LWC Jest.

Source metadata targets Salesforce API 68.0. The current data model assumes a single-currency development org with standard Quotes and Quote Line Items enabled.

## Local setup

### Prerequisites

- Salesforce CLI, Git, Node.js LTS, and npm.
- A compatible non-production Salesforce development org.
- Standard Quotes and Quote Line Items enabled in the target org.

### 1. Clone and install

```sh
git clone https://github.com/Kvrs16/salesforce-enterprise-revenue-hub.git
cd salesforce-enterprise-revenue-hub
npm ci
```

### 2. Authorize a development org

```sh
sf org login web --alias revenue-hub-dev --instance-url https://login.salesforce.com
```

### 3. Run local checks

```sh
npm run prettier:verify
npm run lint
npm run test:unit -- --runInBand
```

### 4. Validate and deploy metadata

Check the deployment and project-specific Apex tests:

```sh
sf project deploy start --dry-run --source-dir force-app --target-org revenue-hub-dev --test-level RunSpecifiedTests --tests RevenueHubServiceTest RevenueHubRetryPolicyTest RevenueHubRequestPolicyTest RevenueHubMockGatewayTest RevenueHubIntegrationWorkerTest --wait 30
```

After successful validation, deploy to the same development org:

```sh
sf project deploy start --source-dir force-app --target-org revenue-hub-dev --test-level RunSpecifiedTests --tests RevenueHubServiceTest RevenueHubRetryPolicyTest RevenueHubRequestPolicyTest RevenueHubMockGatewayTest RevenueHubIntegrationWorkerTest --wait 30
```

Assign permission sets according to the required role: `Revenue_Hub_User`, `Revenue_Hub_Manager`, or `Revenue_Hub_Integration_Admin`. The [security model](docs/security-model.md) describes their access boundaries.

Open **Revenue Hub** from the Salesforce App Launcher. Prepare an approved Quote with accessible related records before submitting requests through the workspace.

### 5. Schedule retry processing

Deploying the dispatcher class does not schedule it. Run the scheduling script once in the development org:

```sh
sf apex run --file scripts/apex/schedule-retry-dispatcher.apex --target-org revenue-hub-dev
```

The script schedules the dispatcher hourly. Each execution dispatches at most one due retry. Backoff defines the earliest eligible time; actual execution also depends on the dispatcher schedule.

## Repository structure

```text
force-app/main/default/   Apex, LWCs, objects, permission sets, and app metadata
docs/                    Architecture, data model, deployment, and testing
scripts/                 Apex setup helpers
```

## Testing

LWC tests run locally with `npm test`. Apex tests run in a compatible Salesforce org and cover services, request policies, retry behavior, mock gateways, and asynchronous processing.

The [testing guide](docs/testing-guide.md) describes the validation approach.

## Security

User-facing controllers enforce record access and object/field permissions. Privileged actions require custom permissions, and asynchronous workers operate on authorized persisted requests. Integration errors are sanitized before storage.

The mock baseline requires no external provider credentials. Future adapters should use org-managed credentials and verified provider callbacks for authoritative payment outcomes.

## Roadmap

- Implement Stripe and PandaDoc adapters.
- Add authenticated webhook handling with signature verification and replay protection.
- Improve retry throughput for larger backlogs.
- Add operational notifications and automated CI checks.

## Documentation

- [Architecture](docs/architecture.md)
- [Data model](docs/data-model.md)
- [Security model](docs/security-model.md)
- [Deployment guide](docs/deployment-guide.md)
- [Testing guide](docs/testing-guide.md)
