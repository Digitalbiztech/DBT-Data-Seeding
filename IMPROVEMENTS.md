# Current Issues & Roadmap

## Recently Addressed
1.  **Upsert Support (Smart Sync)**: Added ability to "Sync (Upsert)" records. Matched records are updated in the destination, while unmatched records are inserted. This prevents duplicates on repeat runs.
2.  **Scalability (N+1 Callouts)**: Refactored dependency discovery to use iterative BFS and the Salesforce Composite API. Describe calls are now batched (25 per callout), significantly reducing latency and avoiding callout limits for large schemas.
3.  **Polymorphic Fields**: Fixed a bug where only the first object in a polymorphic lookup (e.g., `WhoId`) was followed. The system now follows all valid referenced objects.
4.  **Schema Mismatch Warnings**: The tool now detects fields present in Source but missing in Destination during the export plan phase. A warning is displayed in the "Check & Import" wizard listing specific skipped fields, improving user trust.
5.  **External-to-External Seeding**: Removed the limitation that required the destination to be the current org. Users can now seed data between two connected external organizations using REST API for the destination writes.
6.  **Performance (Bulk Matching)**: Moved the heavy matching logic from the browser to the server. The `findMatchingRecords` Apex method now processes records in batches using optimized SOQL queries, resolving browser freeze issues with large datasets.

## Current Issues

### Security & Credentials
1.  **Hardcoded Credentials**: The file `externalOrgQuery.js` contains hardcoded testing credentials (`@track username`, `@track password`).
    *   *Risk*: High. These should be removed immediately.
2.  **Password Transmission**: Credentials are sent from the client (LWC) to the server (Apex) to perform SOAP login.
    *   *Risk*: Medium. While transmitted over HTTPS, this "pass-through" pattern handles raw passwords.
    *   *Fix*: Move to Named Credentials (if possible for dynamic targets) or OAuth 2.0 Web Server flow.

### Architecture & Scalability
3.  **DML Limits**: `insertRecordsCurrent` uses standard `Database.insert`.
    *   *Impact*: Large imports might hit Apex Governor Limits (CPU time, heap size) or mixed DML errors if not carefully batched.

---

## Proposed New Functionalities

### 1. Robustness & Data Integrity
*   **Upsert / Idempotency**: Allow users to select an "External ID" field for objects. Use this field to Upsert records instead of Insert, preventing duplicates on re-runs.
*   **Field Mapping**: Add a UI step to map Source fields to Destination fields if API names differ or if the user wants to transform data.
*   **Data Masking**: Add a "Masking" configuration (e.g., scramble emails, phone numbers) for seeding Sandbox environments with production data safely.

### 2. Connectivity
*   **OAuth 2.0 Integration**: Replace username/password/token login with a proper OAuth flow (Connected App) for better security.
*   **Any-to-Any Transfer**: Update the controller to support `createRecord` via REST API on a remote Destination org, enabling External-to-External seeding.

### 3. User Experience (UX)
*   **Save/Load Configurations**: Allow users to save their "Seeding Plan" (Root object, depth, exclusions, matching rules) to a Custom Metadata Type or a JSON file so complex setups can be reused.
*   **Progress Resumption**: If an import fails halfway, store the state (e.g., "processed 50/100 batches") so it can be resumed without starting over.

### 4. Performance
*   **Batch Apex Implementation**: Move the heavy lifting (Query -> Remap -> Insert) into a Batch Apex class. The LWC would just kick off the batch job and poll for status. This resolves browser timeout/memory issues.

---

## Refactoring Recommendations

1.  **Remove Secrets**: Delete the hardcoded values in `externalOrgQuery.js`.
2.  **Error Handling**: Enhance `insertRecordsCurrent` to return specific field errors rather than a generic message.
3.  **Code Separation**: Extract the "Dependency Tree" logic in `ExternalOrgQueryController` into a dedicated service class (e.g., `DependencyService.cls`) to improve readability and testability.
