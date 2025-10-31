# Copilot instructions for DBT-Data-Seeding

This repository is a Salesforce DX project (SFDX) containing Apex classes, Lightning Web Components (LWC), and metadata manifests. The goal of these notes is to give an AI coding agent the minimal, high-value context needed to make correct, safe, and useful edits.

Note: For a detailed implementation log and complete feature breakdown, refer to `PLAN.md` in the `.github` directory. This file contains the chronological development history, algorithms, data structures, and comprehensive implementation details.

Summary / Big picture
- This is a Salesforce DX project whose source lives under `force-app/main/default` and is configured by `sfdx-project.json` (sourceApiVersion 62.0).
- Major components:
  - Apex controllers: `force-app/main/default/classes/*.cls` (example: `ExternalOrgQueryController.cls`). These provide @AuraEnabled methods used by LWCs and perform HTTP callouts.
  - LWC bundles: `force-app/main/default/lwc/*` (example: `externalOrgQuery`). The LWC `externalOrgQuery.js` calls Apex via `@salesforce/apex/ExternalOrgQueryController.<method>`.
  - Remote site settings: `force-app/main/default/remoteSiteSettings/*.remoteSite` — required for callouts to external Salesforce instances.
  - Manifest(s): `manifest/Seed.xml` is a package manifest that includes Apex classes, LWC bundles, and remote site settings.

Developer workflows & commands (concrete)
- Install dependencies: run `npm install` in the repo root.
- Unit tests (LWC): `npm test` (runs `sfdx-lwc-jest`). You can run `npm run test:unit:watch` for iterative testing.
- Lint & format:
  - `npm run lint` (ESLint over `aura`/`lwc` JS files)
  - `npm run prettier` to format Apex/JS/XML/HTML and `npm run prettier:verify` to check formatting
  - Hooks: Husky + lint-staged are configured; formatting/linting run pre-commit
- Deploy flow (typical SFDX): source is in `force-app` so use standard SFDX commands, for example:
  - Deploy source to an org: `sfdx force:source:deploy -p force-app -u <ORG_ALIAS>`
  - Push to a scratch org: `sfdx force:source:push -u <SCRATCH_ORG>`
  - Authenticate an org: `sfdx auth:web:login -a <ALIAS>`
(Note: repo does not include CI scripts; prefer using SFDX CLI and `npm test` locally or in CI.)

Project-specific conventions & gotchas
- Field handling: The component automatically handles OwnerId, Group, and other system-managed fields during export/import:
  - Uses `getCreateableFields` to get creatable fields from both source and destination orgs
  - Takes intersection of creatable fields to ensure fields can be set in destination
  - System fields like OwnerId and Group are naturally excluded as they aren't creatable
  - Do not add explicit field exclusion lists; rely on createable field intersection
  - Export process: collects IDs iteratively along selected edges, then builds final SOQL with only creatable fields

Key files to inspect when changing behavior
- `force-app/main/default/classes/ExternalOrgQueryController.cls` — main Apex controller; handles login, query, describe, dependency-tree, and insert helpers.
- `force-app/main/default/lwc/externalOrgQuery/externalOrgQuery.js` — large LWC that orchestrates UI, calls Apex, builds export/import plans; good example of client-side patterns used across the repo.
- `force-app/main/default/remoteSiteSettings/*` — callout targets; ensure entries exist for any external endpoints used by Apex.
- `manifest/Seed.xml` — manifest used for packaging/deploying all classes/LWC/RemoteSiteSettings.
- `package.json` — scripts for linting/testing/formatting; prefer these scripts in CI and local flows.

Small engineering contract (short)
- Inputs: LWC UI provides credentials and SOQL strings to Apex methods.
- Outputs: Apex returns JSON-like maps/lists (see `QueryResultWrapper` and `ConnectionTestResult` in `ExternalOrgQueryController.cls`).
- Error modes: callout failures (HTTP non-2xx), invalid input (blank username/password/soql), JSON parse errors. Apex surfaces these via exceptions/AuraHandledException.

Edge cases and attention areas for PR reviewers / AI edits
- Export engine behavior:
  - Supports depth 0 (root object only) and proceeds even when roots have no outgoing edges
  - Uses two-phase export: first collects IDs along selected edges, then builds final SOQL
  - Always bootstraps root object query with LIMIT N even if no dependencies exist
  - Field selection automatically excludes system-managed fields (OwnerId, Group) by using creatable field intersection
  - Maintains per-object old→new Id maps during import for reference field remapping

If you modify or add functionality, include:
- A unit test for any LWC UI logic (use `sfdx-lwc-jest`).
- Formatting via `npm run prettier` and lint fixes so precommit hooks are satisfied.

If anything above is incomplete or inaccurate, point to the file or behavior and I will update this document.
