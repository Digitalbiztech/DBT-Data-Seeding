# GEMINI.md - DBT Data Seeding Project

## Project Overview

This is a **Salesforce DX (SFDX)** project designed for **Data Seeding** between Salesforce Orgs. It allows users to export records from a "Source" org and import them into a "Destination" org while automatically maintaining referential integrity (Lookups/Master-Detail relationships).

### Key Technologies

- **Backend:** Salesforce Apex (Services, Batch Apex, REST/SOAP Callouts).
- **Frontend:** Lightning Web Components (LWC).
- **Architecture:** Service-Oriented Architecture (SOA) with a Facade pattern.
- **Tooling:** SFDX CLI, npm, Prettier, ESLint, Jest (for LWC testing), Husky (pre-commit hooks).

---

## Core Architecture & Logic

### 1. Dependency Discovery (Child -> Parent)

The system traverses the schema starting from a root object to find all required parents.

- **Class:** `ExternalOrgDescribeService.cls`
- **Logic:** Recursive describe calls (batched 25 at a time) to build a dependency tree.
- **Goal:** Identify which objects must be seeded _before_ the child records.

### 2. Data Seeding Execution (Parent -> Child)

Records are imported in topological order to satisfy foreign key constraints.

- **Class:** `DataSeedingBatch.cls`
- **Mechanism:**
  1. **Fetch:** Query records from the Source Org via `ExternalOrgQueryService`.
  2. **Remap:** Replace Source IDs with Destination IDs using an in-memory `idRemap` map.
  3. **Insert:** Push records to the Destination Org using `ExternalOrgDmlService` (Salesforce Composite API).
  4. **Log:** Track success/failure and update the ID map for downstream children.

### 3. Service-Oriented Design

The project uses specialized service classes to isolate concerns:

- `ExternalOrgAuthService`: Handles authentication (SOAP login).
- `ExternalOrgDescribeService`: Schema and dependency discovery.
- `ExternalOrgQueryService`: Remote SOQL execution.
- `ExternalOrgDmlService`: Remote record creation (Composite API).
- `DataSeedingService`: Orchestrates batch jobs and high-level seeding logic.
- `ExternalOrgQueryController`: A thin **Facade** for LWC `@AuraEnabled` methods.

---

## Development & Operations

### Building and Running

- **Deploy to Org:** `sf project deploy start`
- **Run Apex Tests:** `sf apex test run -n <ClassName> -r human` (Note: Many tests are currently being implemented/refactored).
- **LWC Tests:** `npm run test:unit`
- **Formatting:** `npm run test` (runs linting and prettier).

### Key Commands (Scripts)

Available in `package.json`:

- `npm run lint`: Lint LWC JavaScript files.
- `npm run test:unit`: Run Jest tests for LWCs.
- `npm run prettier`: Format all source files (Apex, JS, HTML, XML, etc.).

### Utility Scripts

- **Location:** `scripts/apex/`
- **Usage:** Contains various `.apex` scripts for manual testing and data initialization (e.g., `import_test_data.apex`). Run via `sf apex run --file scripts/apex/your_script.apex`.

---

## Development Conventions

- **Surgical Changes:** Adhere to the SOA pattern. Business logic belongs in Service classes, not the Controller.
- **ID Remapping:** Always consider that IDs from the Source Org are invalid in the Destination Org. Use the `idRemap` logic in `DataSeedingBatch`.
- **Bulkification:** Callouts and DML operations must be bulkified. Use the Composite API (limit 200 records per sub-request) where possible.
- **Security:**
  - **CRITICAL:** Do NOT commit hardcoded credentials. Check `externalOrgQuery.js` for `@track username/password` before any push.
  - **Remote Site Settings:** Ensure the target org URLs are registered in `force-app/main/default/remoteSiteSettings` (e.g., `LoginSalesforce`, `TestSalesforce`).
  - Avoid raw password handling; prefer OAuth or Named Credentials (roadmap item).

---

## Key Files & Directories

- `force-app/main/default/classes/`: Core Apex logic and services.
- `force-app/main/default/lwc/externalOrgQuery/`: Main UI for seeding configuration and execution.
- `CODEMAP.md`: Visual representation of the execution flow (Mermaid diagrams).
- `DEPENDENCY_LOGIC.md`: Explanation of Child->Parent vs Parent->Child logic.
- `IMPROVEMENTS.md`: Current issues, security risks, and technical roadmap.
- `sfdx-project.json`: SFDX project configuration.
