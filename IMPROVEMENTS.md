# Current Issues & Roadmap

## Recently Addressed

1.  **Upsert Support (Smart Sync)**: Added ability to "Sync (Upsert)" records. Matched records are updated in the destination, while unmatched records are inserted. This prevents duplicates on repeat runs.
2.  **Scalability (N+1 Callouts)**: Refactored dependency discovery to use iterative BFS and the Salesforce Composite API. Describe calls are now batched (25 per callout), significantly reducing latency and avoiding callout limits for large schemas.
3.  **Polymorphic Fields**: Fixed a bug where only the first object in a polymorphic lookup (e.g., `WhoId`) was followed. The system now follows all valid referenced objects.
4.  **Schema Mismatch Warnings**: The tool now detects fields present in Source but missing in Destination during the export plan phase. A warning is displayed in the "Check & Import" wizard listing specific skipped fields, improving user trust.
5.  **External-to-External Seeding**: Removed the limitation that required the destination to be the current org. Users can now seed data between two connected external organizations using REST API for the destination writes.
6.  **Performance (Bulk Matching)**: Moved the heavy matching logic from the browser to the server. The `findMatchingRecords` Apex method now processes records in batches using optimized SOQL queries, resolving browser freeze issues with large datasets.
7.  **Architecture Refactoring (Service-Oriented)**: Decomposed the monolithic `ExternalOrgQueryController` into specialized service classes (`Auth`, `Query`, `Describe`, `DML`, `Seeding`). The controller now acts as a thin Facade, improving modularity, readability, and testability.

## Current Issues

### Security & Credentials

1.  **Hardcoded Credentials**: The file `externalOrgQuery.js` contains hardcoded testing credentials (`@track username`, `@track password`).
    - _Risk_: High. These should be removed immediately.
2.  **Password Transmission**: Credentials are sent from the client (LWC) to the server (Apex) to perform SOAP login.
    - _Risk_: Medium. While transmitted over HTTPS, this "pass-through" pattern handles raw passwords.
    - _Fix_: Move to Named Credentials (if possible for dynamic targets) or OAuth 2.0 Web Server flow.

### Architecture & Scalability

1.  **DML Limits**: While Batch Apex helps, extremely large individual records or massive fan-outs might still hit specific governor limits. Careful batch sizing (currently 1 task per batch step) mitigates this.
2.  **Stateful Batch Heap Limits**: The `DataSeedingBatch` class maintains the ID map in memory using `Database.Stateful`. For very large seeding jobs (tens of thousands of records), this could exceed the 12MB async heap limit.

### Reliability & Maintenance

1.  **Missing Unit Tests**: No Apex test classes exist. Deployment to production requires 75% code coverage.
2.  **Detailed Batch Error Reporting**: While the UI shows error counts, specific row-level errors from the Batch job are not surfaced to the user, making debugging difficult without access to backend logs.

---

## Proposed New Functionalities

### 1. Robustness & Data Integrity

- **Field Mapping**: Add a UI step to map Source fields to Destination fields if API names differ or if the user wants to transform data.
- **Data Masking**: Add a "Masking" configuration (e.g., scramble emails, phone numbers) for seeding Sandbox environments with production data safely.
- **Persistent ID Mapping**: Store the ID map in a Custom Object or File instead of memory to support massive datasets.
- **Error Log Object**: Create a `Seeding_Error_Log__c` object to store row-level failures from Batch jobs for user review.

### 2. Connectivity

- **OAuth 2.0 Integration**: Replace username/password/token login with a proper OAuth flow (Connected App) for better security.

### 3. User Experience (UX)

- **Save/Load Configurations**: Allow users to save their "Seeding Plan" (Root object, depth, exclusions, matching rules) to a Custom Metadata Type or a JSON file so complex setups can be reused.
- **Progress Resumption**: If an import fails halfway, store the state (e.g., "processed 50/100 batches") so it can be resumed without starting over.

---

## Refactoring Recommendations

1.  **Remove Secrets**: Delete the hardcoded values in `externalOrgQuery.js`.
2.  **Error Handling**: Enhance `insertRecordsCurrent` to return specific field errors rather than a generic message.
