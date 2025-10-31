# Project Plan and Activity Log

This document captures the evolving specification and the concrete implementation for the External Org Export Planner (Apex + LWC). It is the single source of truth for what was requested, how it was built, and how it works.

## Stakeholder Requests ↔ Implementations (Detailed Mapping)

The following maps each stakeholder request to the concrete implementation delivered. This section is the authoritative tracker for scope and outcomes.

1) Dual-Org Credentials and Current-Org Mode
- Request: Manage Source and Destination orgs side by side; allow the “current org” as either side with no login. Disable irrelevant inputs in current-org mode and simplify the UX.
- Implementation:
  - Split credentials pane into Source/Destination with independent Test Connection buttons.
  - Current Org toggle on both sides (mutually exclusive). Disables username/password/environment, hides Test Connection, shows helper text, and routes calls to current‑org Apex endpoints.
  - Reverse button swaps Source/Destination selections and credentials.

2) Guarded Query Entry and SOQL Smart Parsing
- Request: Don’t allow freeform querying until the Source connection is established; auto-derive object and LIMIT from SOQL.
- Implementation:
  - Gate the SOQL textarea and Run Query button until Source is connected and objects are loaded.
  - Parser extracts FROM object, LIMIT value, handles case‑insensitive names and managed‑package namespaces (ns__MyObj__c ↔ MyObj__c). If unmatched, shows an error tied to the picklist.

3) Exclusions and Minimal Plan Fallback
- Request: Default “Exclude Standard Objects”; if dependencies are null, still allow planning/export.
- Implementation:
  - Apply default exclusions after connecting/fetching objects.
  - When dependency graph returns empty, synthesize a minimal tree with only the selected object so planning and export can proceed.

4) Unified Plan View and Interaction Model
- Request: Merge dependency view with export plan; provide expand/collapse, selection, locking, and reordering where it matters.
- Implementation:
  - Single recursive LWC component renders object nodes and edge nodes as one plan tree.
  - Edge headers show “Field → TargetObject”; suppress repeated target headers right under their edges.
  - Stable path‑based ids ensure correct expand/collapse and drag/drop even for repeated objects.
  - Selection cascades: unchecking a parent deselects and locks descendants (dim + disabled). Re‑checking unlocks.
  - Expand/collapse only rendered when children exist; global Expand All / Collapse All actions added.
  - Drag/drop constrained to siblings; top‑level reorder feeds the export order used by the engine.

5) Plan Depth and Bootstrap Behavior
- Request: Support depth 0 (root only), and proceed even when roots have no outgoing edges.
- Implementation:
  - Depth = 0 means plan tree contains just the selected object.
  - Bootstrap always queries root Ids with LIMIT N even if no dependencies exist.

6) Export Engine (ID Collection → Final Export)
- Request: Collect IDs iteratively along selected edges and then build final SOQL with only creatable fields.
- Implementation:
  - ID collection runs in export order, batching IN clauses where needed. Maintains a per‑object `queriedIdSet` for dedupe and logs `ID_COLLECTION_RESULT` summaries.
  - Final Export builds per‑object SOQL using creatable fields (via Apex helpers) and emits `FINAL_EXPORT_SOQL` entries for execution/inspection.

7) Routing and Current‑Org Support in Apex
- Request: All features should work when Source or Destination is the current org, without external sessions.
- Implementation:
  - Introduced current‑org endpoints for describes, queries, dependency discovery, creatable fields, and inserts.
  - LWC routing helpers (`routeSourceCall`, `routeDestinationCall`) choose between current‑org and external‑org paths automatically.

8) UI Layout and Clarity Pass
- Request: Reduce clutter; keep key actions obvious.
- Implementation:
  - Header shows only Expand All / Collapse All.
  - Controls for Bootstrap Limit, Export, and Final Export grouped below the tree.
  - Removed noisy console logs; kept minimal essential diagnostics.

9) Stability and Edge‑Case Fixes
- Request: Avoid recursion blow‑ups or blocked actions in edge cases; support namespace variance.
- Implementation:
  - Cycle/recursion protection during dependency traversal by tracking visited objects per path.
  - Validation accepts current‑org without requiring external session values.
  - Case‑insensitive and namespace‑flexible matching for parsed SOQL object names.

10) Post‑Final Export Hooks (Initial)
- Request: Basic import flow and destination checks.
- Implementation:
  - When `finalExportQueries` are ready, show “Check Matching in Destination” (placeholder) and “Start Import.”
  - Start Import (current‑org): executes bottom‑to‑top, remaps lookup references via accumulated old→new Id maps, and performs DML with `allOrNone=false`.

## Recent Activity (Chronological Log)
- Added dual‑pane credentials with reverse swap and current‑org toggles (mutually exclusive).
- Gated SOQL until Source connected; added parser for object + LIMIT with namespace awareness.
- Default exclusions and minimal‑tree fallback when dependencies absent.
- Unified tree component with selection/locking, expand/collapse, and constrained drag/drop; top‑level reorder drives export order.
- Implemented export bootstrap for roots with no edges; depth=0 supported.
- Iterative ID collection with batching and `ID_COLLECTION_RESULT` logging.
- Final Export with creatable‑only fields and `FINAL_EXPORT_SOQL` emission.
- LWC routing helpers; Apex current‑org endpoints for describe/query/deps/creatable/insert.
- UI cleanup: moved actions under the tree; reduced console noise.
- Guarded recursion; improved case/namespace matching.
- Introduced post‑Final Export actions and current‑org import loop with Id remapping.

## Goals
- Connect to a Source org and a Destination org (either can be the current org) and plan an export of records based on dependency paths.
- Visualize dependencies in a tree, allow selective inclusion, and compute a safe export order.
- Collect IDs iteratively and build final SOQL with creatable fields only.

## Requests Implemented (Summary)

- Split credentials UI into two halves: Source Org and Destination Org.
- Add "Reverse" button to swap Source and Destination credentials and selection.
- Separate Test Connection for Source and Destination; Source connection drives export, Destination currently only validates.
- Add Current Org radio selection on each side (only one can be current at a time); when selected:
  - Disable Username/Password/Environment inputs and hide Test Connection.
  - Use Apex current-org endpoints (no login or external session required).
  - Add subtle help text "No login needed. Uses this org’s data." and grey out inputs.
- Gate SOQL textarea and Run Query until Source connection is available and object picklist is loaded.
- Run Query only parses SOQL (no data fetch/table) to auto-select object and limit.
- SOQL parsing upgrades:
  - Extract object name after FROM; extract LIMIT value.
  - Case-insensitive matching against picklist.
  - Namespace handling: match `ns__MyObject__c` to `MyObject__c` and vice-versa; error if no match.
- Default exclusions: “Exclude Standard Objects” automatically applied after connecting/fetching objects.
- Dependency tree build when dependencies are null: create a minimal tree with only the selected object so export can proceed.
- “Check Plan” collapses all nodes initially, then re-opens the root only (descendants stay collapsed).
- Depth supports 0 (just the selected object without dependencies).
- Export bootstrap improved: collect Ids even if the root has no outgoing edges (depth 0 or leaf cases) and still respect the limit.
- Removed previous SOQL parse console noise; kept essential debug minimal.

1) Unified Plan Tree (merged dependency + plan)
- One recursive LWC (`externalOrgQueryNode`) renders the export plan: object nodes and edge nodes.
- Edge nodes display `Field -> TargetObject`; the target object header directly under an edge is suppressed to avoid duplication.
- Each node has a unique path-based id so expand/collapse and drag/drop always target the correct instance, even when the same object appears multiple times.
- Per‑group numbering: each set of sibling edges is numbered `1..N` (stable across reordering within the same parent).

2) Selection model with locking
- Edge nodes have checkboxes; object nodes (non‑root) have a “select‑all” checkbox.
- Unchecking a parent (object or edge) cascades to all descendants (deselect + lock). Locked descendants are visibly dimmed and their checkboxes disabled; users cannot re‑enable a child while its ancestor remains unchecked.
- Re‑checking the parent unlocks the descendants.
- Id‑collection honors only the selected edges; deselected branches are excluded from export.

3) Expand/Collapse UX
- Expand chevrons render only if a node has visible descendants. Leaves show a record icon.
- Global “Expand All” and “Collapse All” buttons are available in the plan header.
- After “Collapse All”, expanding an edge automatically uncollapses its immediate (suppressed) child object so grandchildren render properly.

4) Drag and Drop
- Every node is draggable, but reordering is constrained to siblings under the same parent (range‑limited).
- Reordering top‑level siblings (children of the root) updates the `exportOrder` that the export flow uses.
- Reordering deeper levels is visual only (export order is still derived from the top‑level plan).

5) Export workflow
- “Check Plan” builds the plan tree from live describes with configurable depth and excluded objects.
- “Export” collects IDs iteratively:
  - Bootstrap only objects that have selected outgoing edges and only the selected reference fields.
  - Iteratively query in the configured order (with batching for IN clauses) until no new IDs are discovered.
  - Logs a summary (`ID_COLLECTION_RESULT`) showing the `queriedIdSet` by object.
- “Final Export” builds final SOQL statements per object with creatable fields only:
  - Apex helper `getCreateableFields` added to gather fields from describe.
  - Emits `FINAL_EXPORT_SOQL` entries (object, count, SOQL) to be executed/presented per existing mechanics.

6) UI layout refinements
- In the plan header, show only “Expand All” / “Collapse All”.
- Place “Bootstrap Limit”, “Export”, and “Final Export” controls below the node tree.
- Edge vs object nodes have distinct visuals (left border/tint) and locked state has a muted style (row dimming, muted checkbox appearance).

## Key Algorithms & Data Structures

### Dependency Discovery (Apex)
- Describe the selected object, identify reference fields (lookup/md) that are creatable and not excluded.
- Build a tree of “parent” edges (`DependencyNode.parents`) with cycle protection and depth limiting.
- Cache describes per transaction to minimize callouts.

### Plan Tree Construction (LWC)
- Convert the server tree into a display tree with two node types:
  - object node: `{ id, type:'object', label, isCollapsed, draggable, children:[edge nodes] }`
  - edge node: `{ id, type:'edge', label:'Field -> Target', seq, isSelected, draggable, children:[target object node] }`
- Suppress the header of the target object directly under an edge; only the edge line shows.
- Number sibling edges `1..N` using their index under the same parent (numbers are stable when reordering within that parent).

### Id‑Collection (LWC)
- Inputs: `order` (top‑down object names), `limit` (bootstrap), and `selectedEdges` (Map<object, edges[]>).
- Data: `queried[object]` (Set) and `pending[object]` (Set).
- Bootstrap only objects with selected outgoing edges; query `Id` + selected reference fields.
- Iterate in top‑down order; for each object with new pending Ids, query in chunks and harvest further references.
- Stop when there are no pending Ids across all objects.

### Final SOQL Builder (LWC + Apex)
- Ask Apex for creatable fields per object (`getCreateableFields`).
- For each object, produce batched SOQL with only creatable fields and the collected Ids.

## Apex Endpoints
- `testConnection(username, password, environment)` — returns session info.
- `loginAndQuery(username, password, environment, soql)` — SOAP login then REST query; used by the ad‑hoc runner.
- `queryWithSession(sessionId, instanceUrl, soql)` — REST query with existing session.
- `getAvailableObjects(sessionId, instanceUrl)` — list of queryable sObjects.
- `getObjectDependencies(sessionId, instanceUrl, objectName, maxDepth, excludedObjects)` — parent dependency discovery.
- `getCreateableFields(sessionId, instanceUrl, objectNames)` — returns creatable fields per object (new).

## Components & Files

LWC
- `externalOrgQuery` (container)
  - HTML: plan header (Expand/Collapse), plan tree, bottom controls (limit + export buttons), connection and object selection UI.
  - JS: builds plan tree, selection + locking, expand/collapse, drag/drop, id‑collection, final SOQL building.
  - CSS: full‑height plan area, layout spacing.
- `externalOrgQueryNode` (recursive node)
  - HTML: edge/object headers, checkboxes (edge + object), conditional header suppression, recursive child rendering.
  - JS: hasChildren logic (only when visible descendants exist), disabled/locked interactions, DnD events.
  - CSS: edge vs object visuals, locked/muted styles, numbering badge.

Apex
- `ExternalOrgQueryController.cls` — auth, query, describe, dependencies, creatable fields (with per‑transaction describe cache).

## Notable Fixes
- Resolved LWC template unary (`!`) usage and parser errors (unicode escapes, stray `\n`), replaced arrows with ASCII where needed.
- Fixed expand after Collapse All for edge nodes (auto‑uncollapse immediate child object).
- Cleaned unused code: removed `planEdges` remnants and an unused getter.

## Current Flow (End‑to‑End)
1) Test Connection → stores `sessionId`/`instanceUrl` and fetches objects.
2) Select object, set depth/exclusions → Check Plan → builds plan tree.
3) Toggle edges/objects (locks apply), reorder nodes (within siblings) as needed.
4) Expand/Collapse to inspect; numbering visible per sibling group.
5) Set Bootstrap Limit (below tree) → Export → logs `ID_COLLECTION_RESULT` with final `queriedIdSet`.
6) Final Export → logs `FINAL_EXPORT_SOQL` with creatable‑field SOQL for each object.

## Open Follow-Ups / Ideas
- Optional: remove the ad-hoc SOQL runner UI if not needed in production.
- Optional: persist plan selections/locks and export order per user in custom settings or local storage.
- Optional: downloadable CSV/JSON for final export.
- Add Jest unit tests for plan construction and id-collection logic.

## Major Features (Details)

1) Dual-Org UI + Current Org mode
- Source and Destination halves each include Username, Password, Environment, and a Test Connection button.
- A radio “Use Current Org” is shown above each half; only one side can be selected at a time.
- When selected for a side:
  - Inputs become disabled and visually greyed; helper text clarifies no login needed.
  - For Source Current Org, object list and operations use current-org Apex methods.
- “Reverse” swaps Source and Destination credentials and flips Current Org selection if set.

2) SOQL parsing (UI assist only)
- On Run Query (post-connect, post-objects), parse SOQL to:
  - Detect object name and set the Object picklist (case-insensitive + namespace tolerant).
  - Detect LIMIT and set the Bootstrap Limit.
- If object cannot be matched, an error is shown.
- No query execution or table rendering; this path only configures UI for planning.

3) Object fetching and exclusions
- After a successful Source connection (or selecting Source as Current Org), fetch available objects and show the object picker.
- Default the “Excluded Objects” selection to all Standard Objects (button still available to toggle).

4) Plan Tree (unified)
- The plan tree merges the dependency view and export plan using nodes:
  - Object node and Edge node (Field -> TargetObject). The target header under an edge is suppressed.
- Selection and locking rules:
  - Deselecting a parent cascades lock to descendants; reselecting unlocks.
  - Only selected edges/paths are used for ID collection.
- Expand/Collapse behavior:
  - Global Expand All / Collapse All.
  - After “Check Plan”, collapse everything then re-open the root (descendants collapsed by default).
- Drag/Drop:
  - Reorder siblings within the same parent; reordering root children updates `exportOrder`.

5) Export workflow updates
- Check Plan builds dependency tree with configurable depth and excluded objects.
- Export collects IDs iteratively:
  - Bootstrap selection now falls back to the root object if no objects have outgoing edges.
  - Even with no selected outgoing edges (depth 0), a bootstrap SELECT Id LIMIT N runs for the root.
  - Iterative querying follows `exportOrder`, harvesting parent references through selected edges.
- Final Export builds batched SOQL per object with creatable fields only.

## Algorithms & Data Structures (Updated)

- Dependency discovery supports both external-org (REST describe) and current-org (Schema describe) paths.
- Plan Tree nodes:
  - Object node `{ id, type:'object', label, objectName, isCollapsed, draggable, children }`
  - Edge node `{ id, type:'edge', label:'Field -> Target', fieldName, targetObject, isSelected, draggable, children:[target object suppressed header] }`
- ID Collection:
  - Inputs: `exportOrder`, bootstrap `exportLimit`, selected edges map.
  - Bootstrap root when no edges exist; always query Id (plus selected references) LIMIT N.
  - Resolve pending IDs in batches; stop when no pending remain.

## Apex Endpoints (Updated)

- External org
  - `testConnection(username, password, environment)`
  - `loginAndQuery(username, password, environment, soql)`
  - `queryWithSession(sessionId, instanceUrl, soql)`
  - `getAvailableObjects(sessionId, instanceUrl)`
  - `getObjectDependencies(sessionId, instanceUrl, objectName, maxDepth, excludedObjects)`
  - `getCreateableFields(sessionId, instanceUrl, objectNames)`
- Current org (new)
  - `getAvailableObjectsCurrent()`
  - `queryCurrent(soql)`
  - `getObjectDependenciesCurrent(objectName, maxDepth, excludedObjects)`
  - `getCreateableFieldsCurrent(objectNames)`

## Edge Cases & Behaviors
- Null dependencies → build minimal tree with selected object; allow export path.
- Depth = 0 → no parent discovery; bootstrap still queries root Ids.
- Namespace case: match `ns__MyObj__c` to `MyObj__c` and vice-versa when parsing SOQL.
- Case-insensitive object matching between parsed SOQL and picklist.
- Run Query disabled until Source connected, SOQL entered, and object picklist loaded.
- Only one side can be Current Org at a time; reversing flips selection.


## Recent Changes Summary (Requests → Implementation)

- Current org selection UX
  - Replaced radios with linked Yes/No picklists labeled "Use Current Org ?" for both Source and Destination.
  - Enforced mutual exclusivity: setting Source to Yes forces Destination to No, and vice versa.
  - Disables Username/Password/Environment on the side set to Yes and displays helper text.
  - Routing: current-org mode uses `*Current` Apex endpoints; external mode uses session-based endpoints.

- Validation and stability fixes
  - Check Plan validation accepts current-org mode without requiring external sessionId/instanceUrl.
  - Prevented plan recursion overflow by tracking visited object names per path.
  - Export/Final Export guards updated to support current-org Source without session.

- Centralized routing helpers in LWC
  - `ensureSourceConnected(message)` / `ensureDestinationConnected(message)` to gate actions.
  - `routeSourceCall(fnCurrent, fnSession)` / `routeDestinationCall(fnCurrent, fnSession)` to select Apex path.
  - Unified object list loader `fetchAvailableObjectsSource()` routes automatically.
  - Query routing consolidated in `runQueryWithSession()` using `routeSourceCall`.

- Final Export enhancements
  - Button disabled until Destination is connected (either current org or tested external session).
  - For each object (iterating bottom→top), fetch creatable fields from both Source and Destination and use intersection + Id for SELECT so queries are valid in both orgs.
  - Store generated queries in `finalExportQueries` for subsequent steps.

- Post–Final Export actions
  - Show two buttons when `finalExportQueries` exist:
    - "Check Matching in Destination" (placeholder; implementation pending).
    - "Start Import" (enabled when Destination = current org).
  - Start Import (initial implementation):
    - Iterates from bottom to top over `finalExportQueries`.
    - Runs the stored SOQL against Source, builds destination records without Id, remaps lookup references using old→new Id mappings built from earlier inserts, and inserts via Apex DML (current org).
    - Maintains per-object old→new Id maps for downstream remapping during the loop.

## Additional Apex Endpoints

- Current org
  - `insertRecordsCurrent(objectName, records)` — performs simple Database.insert (allOrNone=false) on current org; returns a list of `{ oldId, newId, success, errorMessage }` mappings.

## Next Steps

- Implement external Destination import using REST (POST /sobjects) so Start Import works with username/password Destination mode.
- Implement the logic behind "Check Matching in Destination" (counts, field presence, row-by-row deltas).
- Expose `finalExportQueries` in the UI for review/copy/download and show progress/results for imports.
- Add unit tests for routing helpers, field intersection logic, and ID remapping during import.