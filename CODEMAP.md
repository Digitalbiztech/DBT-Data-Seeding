# Codebase Map: Salesforce Data Seeding Application

This document outlines the structure and responsibilities of the components in the Data Seed application.

## Directory Structure: `force-app/main/default/`

### 1. Classes (`/classes`)
Backend logic handles authentication with external Salesforce organizations, schema discovery, and data operations.

*   **`ExternalOrgQueryController.cls`**
    *   **Authentication**:
        *   `login(username, password, environment)`: Performs a SOAP login to `login.salesforce.com` or `test.salesforce.com` to obtain a Session ID and Server URL.
        *   `testConnection`: Verifies credentials and returns connection details.
    *   **Query & Discovery (Remote)**:
        *   `loginAndQuery`: Wrapper to login and immediately run a SOQL query via REST API.
        *   `queryWithSession` / `queryByUrl`: Executes SOQL queries against a remote org using a provided Session ID.
        *   `getAvailableObjects`: Fetches a list of queryable sObjects from the remote org.
        *   `getObjectDependencies`: Builds a dependency tree (parents/lookups and children) using an iterative BFS approach and the Salesforce Composite API (batching 25 describes per call) to avoid N+1 callouts. Supports polymorphic fields.
        *   `describeSObject`: Helper to get field metadata (cached per transaction).
        *   `getCreateableFields`: Retrieves fields that can be written to in the remote org.
        *   **`getRequiredFields`**: Retrieves mandatory fields (createable, !nillable, !defaulted) for an object to ensure safe inserts.
    *   **Query & Discovery (Current Org)**:
        *   `queryCurrent`: Runs SOQL against the local (hosting) org.
        *   `getAvailableObjectsCurrent`: Schema reflection for the local org.
        *   `getObjectDependenciesCurrent`: Builds dependency tree for local objects.
        *   `getCreateableFieldsCurrent`: Schema reflection for createable fields in the local org.
    *   **Batch & Import Operations**:
        *   `startDataSeedingBatch`: Initiates the `DataSeedingBatch` job to transfer data.
        *   `getBatchJobStatus`: Polls the status of the background job.
        *   `getBatchReport`: Retrieves the JSON report (saved as `ContentVersion`) from a completed batch job.
    *   **Data Manipulation (DML)**:
        *   `insertRecordsCurrent` / `updateRecordsCurrent`: Inserts/Updates records in the local org.
        *   `createRecordsRemote` / `updateRecordsRemote`: Inserts/Updates records in a remote org via REST API (Composite Collections).
    *   **Matching Logic**:
        *   `findMatchingRecords`: efficient bulk matching of records between source and destination based on selected fields.

*   **`DataSeedingBatch.cls`**
    *   **Role**: Implements `Database.Batchable` and `Database.Stateful` to process seeding tasks asynchronously.
    *   **Logic**:
        *   Iterates through a list of ordered tasks (queries).
        *   Handles pagination via `nextRecordsUrl` (chaining batch jobs if needed).
        *   Remaps Parent IDs using a stateful `idRemap` map.
        *   Captures detailed execution logs.
    *   **Inner Classes**:
        *   `LogEntry`: Captures failure/success context (Object, Source ID, Dest ID, Message, Status).
    *   **Reporting**: Saves a JSON execution report as a `ContentVersion` file upon completion.

### 2. Lightning Web Components (`/lwc`)
Frontend UI for configuring connections, visualizing data dependencies, and executing the transfer.

*   **`externalOrgQuery`** (Main Container)
    *   **Connection Management**:
        *   Source/Destination can be "Current Org" or "External Org" (User/Pass).
        *   **Reverse Orgs**: Utility to swap Source and Destination credentials/settings.
    *   **Object Selection**:
        *   Searchable dropdown for objects.
        *   **SQL Editor**:
            *   Parses SOQL input (`SELECT ... FROM ...`).
            *   **Auto-configuration**: Automatically sets Object, Limit, and Plan constraints based on the query.
            *   **Field Filtering**: Respects `SELECT` fields, ensuring only requested + required fields are exported.
            *   **Nested Queries**: Automatically includes child relationships specified in subqueries.
        *   **Quick Filters**: Buttons to easily include/exclude Standard or Custom objects.
        *   **Configs**: "Max Depth" and "Excluded Objects" to refine the dependency tree.
    *   **Plan & Export**:
        *   **Export Plan**: Visualizes the dependency tree with togglable nodes/edges.
        *   **Execution**: Calculates topological sort order, bootstraps IDs, and generates final filtered SOQL queries.
    *   **Import / Matching Wizard**:
        *   **Check & Import**: A modal wizard for pre-flight checks.
            *   Step 1: Select matching fields per object. Warns on schema mismatches.
            *   Step 2: Comparison results (Matched vs Unmatched counts).
            *   Step 3: Execution (Import Unmatched or Sync/Upsert).
            *   Step 4: Summary report.
        *   **Batch Execution**: Calls `startDataSeedingBatch` for large-scale imports and polls for status/reports.
    *   **Key State**: `planRoot`, `exportOrder`, `finalExportQueries`, `importStatus`, `wizard`, `matchResultsByObject`, `soqlConstraints`.

*   **`externalOrgQueryNode`** (Presentation/Recursive)
    *   **Responsibilities**:
        *   Renders a single node (Object or Edge) in the dependency tree.
        *   Supports recursion to display children nodes.
        *   **Interaction**: Checkboxes for selection, expand/collapse toggles, drag-and-drop reordering.
        *   **Visuals**: Distinguishes between Objects and Edges; visual cues for locked/disabled states.

### 3. Applications (`/applications`)
*   **`Data_Seed.app-meta.xml`**: Defines the "Data Seed" Lightning App, exposing the `externalOrgQuery` LWC via a standard home page tab.

### 4. Remote Site Settings (`/remoteSiteSettings`)
Network security configuration to allow the Apex controller to make callouts.
*   **`LoginSalesforce`**: Allow SOAP login to Production (`login.salesforce.com`).
*   **`TestSalesforce`**: Allow SOAP login to Sandbox (`test.salesforce.com`).
*   **`DBTD3Instance`**: Example specific instance allowlist.

## Data Flow
1.  **Connect**: User authenticates Source and Destination (supporting Local<->Remote, Remote<->Remote, Local<->Local).
2.  **Plan**: User selects a root object (e.g., `Account`). System builds a dependency tree (Account -> Parent User, Account -> Child Contacts).
    *   *New*: User can paste a SOQL query to auto-configure this plan and restrict field selection.
3.  **Refine**: User filters the tree (depth, exclusions, checkboxes).
4.  **Export (Id Collection)**: System queries Source to find all related Record IDs required by the plan (Bootstrap -> Dependents).
5.  **Finalize**: System constructs precise SOQL queries (filtered by IDs) to fetch only the necessary fields (Requested U Required).
6.  **Import (Batch)**:
    *   `DataSeedingBatch` fetches records from Source.
    *   Foreign Keys (Lookups) are remapped using the `idRemap` state.
    *   Records are inserted/created in Destination.
    *   Results are logged and saved to a file (`SeedingReport.json`).
