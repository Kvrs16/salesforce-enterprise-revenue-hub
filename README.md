# Salesforce Enterprise Revenue & Integration Hub

An original Salesforce DX portfolio project by Vijaya Rani, designed to demonstrate secure revenue lifecycle orchestration, asynchronous integrations, and operational monitoring.

## Status

The first application slice is deployed to the connected Developer Edition org (`practice-org-1`): permission-gated payment/document services, deterministic mock gateways, asynchronous processing, bounded retry handling, an integration monitor/retry action, and a Lightning workspace. The deployment completed successfully (ID `0Afg500000GaSNxCAN`); all 21 selected Apex tests passed. The retry dispatcher is scheduled hourly and handles at most one due retry per run. Local formatting, lint, source conversion, and the 3 LWC Jest tests also pass. The baseline does not process real payments or generate provider documents.

## Planned lifecycle

```text
Account -> Opportunity -> Products -> Quote approval
        -> Document request -> Payment request -> Integration monitoring
```

The project uses standard Salesforce pricing and Quote behavior rather than implementing CPQ. Stripe and PandaDoc are optional future adapters, not part of the mock baseline.

## Technology

- Salesforce DX source format
- Apex services and Queueable processing
- Lightning Web Components
- Salesforce approval process and targeted Flow automation
- Jest, Apex tests, Salesforce Code Analyzer, and GitHub Actions (planned)

## Repository layout

- `force-app/main/default/` - Salesforce metadata and application source
- `docs/` - architecture, data model, security, and delivery notes
- `integrations/` - optional provider or webhook services when implemented
- `scripts/` - local setup and test-data helpers

## Development

Prerequisites: Salesforce CLI, Git, Node.js LTS, VS Code with Salesforce extensions, and a compatible non-production Salesforce development org.

```powershell
sf --version
sf org list
npm install
```

`npm test` runs the LWC Jest suites. Apex tests require Salesforce CLI test execution against a compatible org. The target org is single-currency and accepted the Quote-dependent metadata. No Git remote or push has been created. See [the deployment guide](./docs/deployment-guide.md) for the hourly retry schedule.

## Security

Do not commit Salesforce authentication files, credentials, API tokens, payment data, or provider secrets. Request services check the action custom permission and read approved Quotes in user mode. Mock results are simulations only; real payment success must come from an authoritative provider-side confirmation, never a browser redirect.

## Author

Vijaya Rani - [GitHub](https://github.com/Kvrs16)
