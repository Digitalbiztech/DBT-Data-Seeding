# Data Seeding Algorithm & Execution Flow

```mermaid
sequenceDiagram
    participant User
    participant LWC as ExternalOrgQuery (LWC)
    participant Auth as ExternalOrgAuthService
    participant Desc as ExternalOrgDescribeService
    participant Query as ExternalOrgQueryService
    participant DML as ExternalOrgDmlService
    participant Batch as DataSeedingBatch
    participant Source as Source Org
    participant Dest as Dest Org

    Note over User, LWC: 1. Setup & Connection
    User->>LWC: Enter Credentials
    LWC->>Auth: testConnection()
    Auth->>Source: SOAP Login
    Source-->>Auth: SessionId + URL
    Auth-->>LWC: Success

    Note over User, LWC: 2. Object Selection & Plan
    User->>LWC: Select Root Object (e.g. Account)
    LWC->>Desc: getObjectDependencies(Account, Depth)
    Desc->>Source: Describe API (Recursive)
    Source-->>Desc: Schema (Fields, Relations)
    Desc-->>LWC: Dependency Tree
    LWC->>LWC: Render Plan Tree (User selects nodes)

    Note over User, LWC: 3. Export (Collect IDs)
    User->>LWC: Export (Limit X)
    LWC->>LWC: Compute Topological Order (Children -> Parents)
    loop For each Object in Order
        LWC->>Query: queryWithSession(SELECT Id, RefFields...)
        Query->>Source: SOQL
        Source-->>Query: Rows
        LWC->>LWC: Collect IDs & Parent IDs (Graph Traversal)
    end
    LWC->>LWC: Store IDs in State (lastQueriedIdSets)

    Note over User, LWC: 4. Final Export & Import
    User->>LWC: Final Export
    LWC->>LWC: Generate Tasks (SOQL per 200 IDs)
    User->>LWC: Start Import
    LWC->>Batch: startDataSeedingBatch(Tasks, PlanEdges)
    Batch->>Batch: Queue Job

    Note over Batch, Dest: 5. Batch Execution (Async)
    loop For each Task (Object Batch)
        Batch->>Query: queryWithSession/queryByUrl (Source)
        Query->>Source: Fetch Records (Page 2000)
        Source-->>Query: Records + NextUrl

        Batch->>Batch: Remap Reference Fields (using idRemap)

        loop Chunked Insert (200 records)
            Batch->>DML: createRecordsRemote(Chunk)
            DML->>Dest: POST /composite/sobjects
            Dest-->>DML: Success/Error + New IDs
            Batch->>Batch: Update idRemap (OldId -> NewId)
            Batch->>Batch: Log Results
        end

        opt Pagination
            Batch->>Batch: Update NextUrl
            Batch->>Batch: Chain (Reschedule Self)
        end
    end

    Batch->>Batch: Save Report (ContentVersion)
    LWC->>Batch: Poll Status
    Batch-->>LWC: Completed
    LWC->>LWC: Display Report
```

## detailed Code Flow

### 1. Initialization

- **LWC**: `externalOrgQuery` initializes.
- **Auth**: User provides credentials. `ExternalOrgAuthService.login` performs SOAP login to get `sessionId` and `serverUrl`.
- **Discovery**: `ExternalOrgDescribeService.getAvailableObjects` fetches SObjects.

### 2. Plan Generation

- **Selection**: User selects an object.
- **Describe**: `ExternalOrgDescribeService.getObjectDependencies` recursively builds a tree.
  - Uses `describeCache` to minimize callouts.
  - Handles `maxDepth` and `excludedObjects`.
  - Identifies `reference` fields (Lookups) and `childRelationships`.
- **UI**: Tree is rendered. User unchecks/checks nodes.
- **Topological Sort**: `computeExportOrder` in JS sorts objects so parents are processed before children.

### 3. ID Collection (Bootstrap)

- **Goal**: Find relevant records to seed starting from the root object.
- **Process**:
  1. Query Root Object (Limit X).
  2. Extract IDs and Reference IDs (Parent IDs).
  3. Recursively Query Parents based on extracted IDs.
  4. Store all collected IDs in `lastQueriedIdSets`.

### 4. Batch Preparation

- **Final Export**: LWC generates a list of "Tasks".
  - Each Task = Object Name + SOQL query for specific IDs (WHERE Id IN (...)).
  - Queries are chunked (e.g. 200 IDs per query) to keep SOQL length manageable.
- **Start**: `DataSeedingService.startDataSeedingBatch` is called.
  - Pass `taskList`: Ordered list of queries (Parents First).
  - Pass `planEdges`: Map of Reference Fields for ID remapping.

### 5. Batch Execution (`DataSeedingBatch`)

- **State**: Maintains `idRemap` (Map<Object, Map<OldId, NewId>>).
- **Execute**:
  1. **Fetch**: `ExternalOrgQueryService` executes the task's SOQL against Source.
     - Handles standard pagination (nextRecordsUrl).
  2. **Remap**: Iterates fetched records.
     - For each field in `planEdges`, checks if value exists in `idRemap`.
     - Replaces Source ID with Destination ID.
  3. **Insert**: `ExternalOrgDmlService` sends records to Destination.
     - **CRITICAL**: Must chunk into 200 records for Composite API.
  4. **Update Map**: On success, store `OldId -> NewId` in `idRemap`.
  5. **Log**: Store success/error in `logs` list.
- **Chaining**:
  - If `nextRecordsUrl` exists -> Chain same task.
  - Else -> Move to next task -> Chain.
- **Finish**: Save `logs` as JSON in `ContentVersion`.
