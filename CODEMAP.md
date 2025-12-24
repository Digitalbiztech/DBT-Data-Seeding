# Codebase Map: Salesforce Data Seeding Application

This document outlines the structure and responsibilities of the components in the Data Seed application.

## Directory Structure: `force-app/main/default/`

### 1. Classes (`/classes`)
Backend logic handles authentication with external Salesforce organizations, schema discovery, and data operations.

*   **`ExternalOrgQueryController.cls`**
    *   **Authentication**:
        *   `login(username, password, environment)`: Performs a SOAP login to `login.salesforce.com` or `test.salesforce.com` to obtain a Session ID and Server URL.
        *   `testConnection`: Verifies credentials and returns connection details.
    *   **Query & Discovery**:
        *   `loginAndQuery`: Wrapper to login and immediately run a SOQL query via REST API.
        *   `queryWithSession`: Executes SOQL queries against a remote org using a provided Session ID.
        *   `getAvailableObjects`: Fetches a list of queryable sObjects from the remote org.
        *   `getObjectDependencies`: Builds a dependency tree (parents/lookups and children) using an iterative BFS approach and the Salesforce Composite API (batching 25 describes per call) to avoid N+1 callouts. Supports polymorphic fields.
        *   `describeSObject`: Helper to get field metadata (cached per transaction).
    *   **Current Org Operations**:
        *   `queryCurrent`: Runs SOQL against the local (hosting) org.
        *   `insertRecordsCurrent`: Inserts records into the local org. Used during the import phase.
        *   `updateRecordsCurrent`: Updates records in the local org. Used during the "Sync (Upsert)" phase.
        *   `getAvailableObjectsCurrent` / `getCreateableFieldsCurrent`: Schema reflection for the local org.
    *   **Remote Org Operations**:
        *   `createRecordsRemote`: Inserts records into a remote org via REST API (Composite Collections).
        *   `updateRecordsRemote`: Updates records in a remote org via REST API.

### 2. Lightning Web Components (`/lwc`)
Frontend UI for configuring connections, visualizing data dependencies, and executing the transfer.

*   **`externalOrgQuery`** (Main Container)
    *   **Responsibilities**:
        *   Manages source and destination connection state (Username/Password or "Current Org").
        *   Allows users to select a root object and configure dependency depth.
        *   Orchestrates the "Plan" generation (calls `getObjectDependencies`).
        *   **Export Plan**: visualizes the tree, allows toggling nodes/edges.
        *   **Export Execution**:
            *   Calculates topological sort order for object insertion.
            *   Bootstrap queries: Collects IDs from the source based on the plan.
            *   Final Export: Generates specific SOQL queries to fetch data for import.
        *   **Matching Wizard**: Provides a multi-step UI to compare data between Source and Destination.
            *   Step 1: Select comparison fields.
            *   Step 2: Comparison results (Matched vs Unmatched).
            *   Step 3: Import report for current object.
            *   Supports "Sync (Upsert)" which inserts new records and updates existing ones based on Destination IDs.
            *   Navigation: Supports "Previous Object", "Next Object", and "Back to Select" for a refined workflow.
        *   **Import Execution**: Reads data from Source (via REST proxy) and inserts into Destination (via `insertRecordsCurrent` for local or `createRecordsRemote` for external targets).
    *   **Key State**: `planRoot`, `exportOrder`, `finalExportQueries`, `importStatus`, `wizard`.

*   **`externalOrgQueryNode`** (Presentation/Recursive)
    *   **Responsibilities**:
        *   Renders a single node (Object or Edge) in the dependency tree.
        *   Supports recursion to display children nodes.
        *   Handles UI interactions: Expanding/collapsing, checking boxes to include/exclude paths.
        *   Supports Drag-and-Drop (stubbed in UI) for reordering.

### 3. Applications (`/applications`)
*   **`Data_Seed.app-meta.xml`**: Defines the "Data Seed" Lightning App, likely exposing the `externalOrgQuery` LWC via a tab (referenced as `standard-home` or a utility bar, though the XML shows `Data_Seed_UtilityBar`).

### 4. Remote Site Settings (`/remoteSiteSettings`)
Network security configuration to allow the Apex controller to make callouts.
*   **`LoginSalesforce`**: Allow SOAP login to Production.
*   **`TestSalesforce`**: Allow SOAP login to Sandbox.
*   **`DBTD3Instance`**: Example specific instance allowlist.

## Data Flow
1.  **Connect**: User authenticates Source (External or Current) and Destination (External or Current).
2.  **Plan**: User selects a root object (e.g., `Account`). System builds a dependency tree (Account -> Parent User, Account -> Child Contacts).
3.  **Refine**: User selects which branches of the tree to include.
4.  **Export (Id Collection)**: System queries Source to find all related Record IDs required by the plan.
5.  **Finalize**: System constructs precise SOQL queries (filtered by IDs) to fetch only the necessary fields.
6.  **Import**:
    *   Records are fetched from Source.
    *   Foreign Keys (Lookups) are remapped (logic exists to map old Source IDs to new Destination IDs).
    *   Records are inserted into Destination.
