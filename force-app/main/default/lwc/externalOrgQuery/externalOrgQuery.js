import { LightningElement, track } from 'lwc';
import loginAndQuery from '@salesforce/apex/ExternalOrgQueryController.loginAndQuery';
import testConnection from '@salesforce/apex/ExternalOrgQueryController.testConnection';
import getAvailableObjects from '@salesforce/apex/ExternalOrgQueryController.getAvailableObjects';
import getObjectDependencies from '@salesforce/apex/ExternalOrgQueryController.getObjectDependencies';
import getCreateableFields from '@salesforce/apex/ExternalOrgQueryController.getCreateableFields';
import queryWithSession from '@salesforce/apex/ExternalOrgQueryController.queryWithSession';

export default class ExternalOrgQuery extends LightningElement {
    // UI state for external org connection and query execution
    @track username = 'ayannbhunia@gmail.com.dbtd3'; // for testing, will remove later
    @track password = 'aYANbHUNIA1234!UwlqVpYeKSapeeHia8ecxJk5'; // for testing, will remove later
    @track environment = 'Production';
    @track soql = '';
    @track columns = [];
    @track rows = [];
    @track error;
    @track testMessage;
    @track sessionId;
    @track instanceUrl;
    @track availableObjects = [];
    @track selectedObject;
    @track dependencyTree;
    @track showObjectPicker = false;
    @track maxDepth = 3;
    @track excludedObjects = [];
    @track planRoot;
    @track planReady = false;
    @track exportLimit = 50;
    @track exportOrder = [];
    @track lastQueriedIdSnapshot;
    isLoading = false;

    planEdges = new Map();
    lastQueriedIdSets = new Map();

    get environmentOptions() {
        // Environment options for login host selection
        return [
            { label: 'Production', value: 'Production' },
            { label: 'Sandbox', value: 'Sandbox' }
        ];
    }

    get hasResults() {
        return this.rows && this.rows.length > 0;
    }

    get isRunDisabled() {
        return !this.username || !this.password || !this.soql || this.isLoading;
    }
    
    get showTestButton() {
        return !!this.username && !!this.password && !this.isLoading;
    }

    get objectOptions() {
        return this.availableObjects.map(obj => ({
            label: obj,
            value: obj
        }));
    }

    @track objectFilter = '';
    get filteredObjectOptions() {
        const term = (this.objectFilter || '').toLowerCase();
        const opts = this.objectOptions;
        if (!term) return opts;
        return opts.filter(o => (o.label && o.label.toLowerCase().includes(term)) || (o.value && o.value.toLowerCase().includes(term)));
    }
    handleObjectFilterChange = (event) => { this.objectFilter = event.target.value || ''; };

    get selectedObjectEmpty() {
        return !this.selectedObject;
    }

    get excludedObjectOptions() {
        return this.availableObjects.map(obj => ({
            label: obj,
            value: obj
        }));
    }

    get standardObjects() {
        // Common standard Salesforce objects
        const standardObjects = [
            'Account', 'Contact', 'Lead', 'Opportunity', 'Case', 'Campaign', 'Product2',
            'Pricebook2', 'PricebookEntry', 'Quote', 'Contract', 'Task', 'Event',
            'User', 'Profile', 'Role', 'PermissionSet', 'Group', 'Queue', 'Territory',
            'Asset', 'Solution', 'Idea', 'Vote', 'Attachment', 'Document', 'Folder',
            'ContentDocument', 'ContentVersion', 'ContentWorkspace', 'FeedItem',
            'FeedComment', 'CollaborationGroup', 'CollaborationGroupMember',
            'WorkOrder', 'WorkOrderLineItem', 'ServiceAppointment', 'ServiceResource',
            'OperatingHours', 'ServiceTerritory', 'Location', 'MaintenancePlan',
            'MaintenanceAsset', 'ReturnOrder', 'ReturnOrderLineItem', 'Shipment',
            'ShipmentItem', 'ProductItem', 'InventoryItem', 'InventoryAdjustment',
            'InventoryAdjustmentItem', 'InventoryTransfer', 'InventoryTransferItem',
            'InventoryCount', 'InventoryCountItem', 'InventoryCountAdjustment',
            'InventoryCountAdjustmentItem', 'InventoryCountAdjustmentLine'
        ];
        
        return this.availableObjects.filter(obj => standardObjects.includes(obj));
    }

    get customObjects() {
        return this.availableObjects.filter(obj => !this.standardObjects.includes(obj));
    }

    // Simple getter methods for template
    handleUsernameChange = (event) => { this.username = event.target.value; this.testMessage = undefined; this.error = undefined; this.resetObjectSelection(); console.log('Username updated'); };
    handlePasswordChange = (event) => { this.password = event.target.value; this.testMessage = undefined; this.error = undefined; this.resetObjectSelection(); console.log('Password updated'); };
    handleEnvironmentChange = (event) => { this.environment = event.detail.value; };
    handleSoqlChange = (event) => { this.soql = event.target.value; };
    handleObjectChange = (event) => { this.selectedObject = event.detail.value; this.dependencyTree = undefined; };
    handleDepthChange = (event) => { this.maxDepth = parseInt(event.target.value) || 3; this.dependencyTree = undefined; };
    handleExcludedObjectsChange = (event) => { this.excludedObjects = event.detail.value || []; this.dependencyTree = undefined; };
    handleSelectStandardObjects = () => { this.excludedObjects = this.standardObjects; this.dependencyTree = undefined; };
    handleSelectCustomObjects = () => { this.excludedObjects = this.customObjects; this.dependencyTree = undefined; };
    handleClearExclusions = () => { this.excludedObjects = []; this.dependencyTree = undefined; };

    get hasPlan() {
        return this.planReady && this.planRoot && Array.isArray(this.planRoot.children) && this.planRoot.children.length > 0;
    }

    get canShowPlanControls() {
        return this.hasPlan;
    }

    get hasCollectedIds() {
        return this.lastQueriedIdSets && typeof this.lastQueriedIdSets.size === 'number' && this.lastQueriedIdSets.size > 0;
    }

    get isExportDisabled() {
        return !this.hasPlan || !this.hasExportOrder || this.isLoading;
    }

    get isFinalExportDisabled() {
        return this.isExportDisabled || !this.hasCollectedIds;
    }

    handlePlanNodeToggle = (event) => {
        const { nodeId } = event.detail || {};
        if (!nodeId || !this.planRoot) {
            return;
        }
        const clonedRoot = this.clonePlanNode(this.planRoot);
        if (this.toggleNodeCollapsed(clonedRoot, nodeId)) {
            this.planRoot = clonedRoot;
        }
    };

    handlePlanNodeDrop = (event) => {
        const { sourceId, targetId } = event.detail || {};
        if (!sourceId || !targetId || sourceId === targetId || !this.planRoot) {
            return;
        }
        const fromInfo = this.findParentAndIndexById(this.planRoot, sourceId);
        const toInfo = this.findParentAndIndexById(this.planRoot, targetId);
        if (!fromInfo || !toInfo || fromInfo.parent.id !== toInfo.parent.id) {
            return; // only reorder within same parent for now
        }
        const parent = fromInfo.parent;
        const currentChildren = [...parent.children];
        const [moved] = currentChildren.splice(fromInfo.index, 1);
        currentChildren.splice(toInfo.index, 0, moved);
        parent.children = currentChildren;
        this.planRoot = this.clonePlanNode(this.planRoot);
        if (parent.id === 'plan-root') {
            this.exportOrder = currentChildren.map(node => node.objectName);
            console.log(JSON.stringify({ type: 'PLAN_REORDER', order: this.exportOrder }, null, 2));
        }
    };

    clonePlanNode(node) {
        if (!node) {
            return node;
        }
        return {
            ...node,
            children: node.children ? node.children.map(child => this.clonePlanNode(child)) : []
        };
    }

    toggleNodeCollapsed(node, nodeId) {
        if (!node) {
            return false;
        }
        if (node.id === nodeId) {
            node.isCollapsed = !node.isCollapsed;
            return true;
        }
        if (node.children && node.children.length) {
            for (const child of node.children) {
                if (this.toggleNodeCollapsed(child, nodeId)) {
                    return true;
                }
            }
        }
        return false;
    }

    buildPlanState(dependencyTree) {
        if (!dependencyTree) {
            this.planRoot = undefined;
            this.planEdges = new Map();
            this.exportOrder = [];
            this.planReady = false;
            return;
        }
        const edgesByObject = this.collectPlanEdges(dependencyTree);
        const rootObject = dependencyTree.objectName;
        const order = this.computeExportOrder(edgesByObject, rootObject);
        this.exportOrder = order;
        this.planEdges = edgesByObject;
        this.planRoot = this.buildPlanTree(rootObject, order, edgesByObject);
        this.planReady = true;
        this.lastQueriedIdSets = new Map();
        this.lastQueriedIdSnapshot = undefined;
    }

    collectPlanEdges(root) {
        const edgesByObject = new Map();
        const visitedEdges = new Set();
        const addEdge = (fromObj, fieldName, toObj) => {
            if (!fromObj || !fieldName || !toObj) {
                return;
            }
            if (!edgesByObject.has(fromObj)) {
                edgesByObject.set(fromObj, []);
            }
            const existing = edgesByObject.get(fromObj);
            if (!existing.some(edge => edge.fieldName === fieldName && edge.target === toObj)) {
                existing.push({ fieldName, target: toObj });
            }
        };

        const walkParents = (currentObjectName, parents, path = new Set()) => {
            if (!parents || !parents.length) {
                return;
            }
            const nextPath = new Set(path);
            if (currentObjectName) {
                nextPath.add(currentObjectName);
            }
            for (const parent of parents) {
                const edgeKey = `${currentObjectName}|${parent.fieldName}|${parent.objectName}`;
                if (!visitedEdges.has(edgeKey)) {
                    addEdge(currentObjectName, parent.fieldName, parent.objectName);
                    visitedEdges.add(edgeKey);
                }
                if (parent.objectName && !nextPath.has(parent.objectName)) {
                    walkParents(parent.objectName, parent.parents, nextPath);
                }
            }
        };

        if (root && root.objectName) {
            walkParents(root.objectName, root.parents || []);
        }

        const visitedObjects = new Set();
        const collectObjects = (node) => {
            if (!node || !node.objectName || visitedObjects.has(node.objectName)) {
                return;
            }
            visitedObjects.add(node.objectName);
            if (!edgesByObject.has(node.objectName)) {
                edgesByObject.set(node.objectName, []);
            }
            (node.parents || []).forEach(collectObjects);
        };
        collectObjects(root);

        return edgesByObject;
    }

        buildPlanTree(rootObject, order, edgesByObject) {
        const buildEdgeNode = (fromObj, edge, pathKey, depth, visited) => {
            const edgeId = `edge-${pathKey}-${fromObj}-${edge.fieldName}-${edge.target}`;
            const childObjectNode = buildObjectNode(edge.target, `${pathKey}o`, depth + 1, visited);
            if (childObjectNode) {
                childObjectNode.suppressHeader = true;
                childObjectNode.isCollapsed = false;
            }
            return {
                id: edgeId,
                type: 'edge',
                label: `${edge.fieldName} -> ${edge.target}`,
                objectName: fromObj,
                fieldName: edge.fieldName,
                targetObject: edge.target,
                isCollapsed: false,
                isLeaf: false,
                draggable: false,
                isSelected: true,
                children: childObjectNode ? [childObjectNode] : []
            };
        };

        const buildObjectNode = (objectName, pathKey = 'r', depth = 0, visited = new Set()) => {
            const nodeId = `obj-${pathKey}-${objectName}`;
            const node = {
                id: nodeId,
                type: 'object',
                label: objectName,
                objectName,
                isCollapsed: depth > 0,
                isLeaf: false,
                draggable: depth === 0,
                children: []
            };
            if (visited.has(`${pathKey}|${objectName}`)) {
                node.isLeaf = true;
                return node;
            }
            const nextVisited = new Set(visited);
            nextVisited.add(`${pathKey}|${objectName}`);
            const edges = edgesByObject.get(objectName) || [];
            edges.forEach((e, idx) => {
                node.children.push(buildEdgeNode(objectName, e, `${pathKey}e${idx}`, depth + 1, nextVisited));
            });
            node.isLeaf = node.children.length === 0;
            return node;
        };

        const root = buildObjectNode(rootObject, 'r', 0, new Set());
        root.draggable = false;
        root.label = `Export Plan for ${rootObject}`;
        root.id = 'plan-root';
        return root;
    }

    findParentAndIndexById(node, id) {
        if (!node || !id) return null;
        const stack = [node];
        while (stack.length) {
            const current = stack.pop();
            if (!current || !current.children) continue;
            for (let i = 0; i < current.children.length; i++) {
                const child = current.children[i];
                if (child && child.id === id) {
                    return { parent: current, index: i };
                }
                stack.push(child);
            }
        }
        return null;
    }

    async handleRunQuery() {
        this.error = undefined;
        this.testMessage = undefined;
        this.isLoading = true;
        try {
            console.log('Calling Apex loginAndQuery');
            const result = await loginAndQuery({
                username: this.username,
                password: this.password,
                environment: this.environment,
                soql: this.soql
            });

            const cols = (result.columns || []).map((c) => ({ label: c, fieldName: c }));
            const data = (result.rows || []).map((row, idx) => ({ key: row.Id || idx.toString(), ...row }));

            this.columns = cols;
            this.rows = data;
            console.log('Query success. Rows:', this.rows.length);
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : (e && e.message ? e.message : 'Unknown error');
            console.error('Query error', this.error);
            this.rows = [];
            this.columns = [];
        } finally {
            this.isLoading = false;
        }
    }

    async handleTestConnection() {
        this.error = undefined;
        this.testMessage = undefined;
        this.isLoading = true;
        try {
            console.log('Calling Apex testConnection');
            const res = await testConnection({
                username: this.username,
                password: this.password,
                environment: this.environment
            });
            if (res && res.success) {
                const instance = res.instanceUrl ? ` (${res.instanceUrl})` : '';
                this.testMessage = `Connection successful${instance}`;
                
                // Store session details for future API calls
                this.sessionId = res.sessionId;
                this.instanceUrl = res.instanceUrl;
                
                // Automatically fetch available objects
                await this.fetchAvailableObjects();
                
                console.log('Connection test successful');
            } else {
                this.error = (res && res.message) ? res.message : 'Connection failed';
                console.error('Connection test failed', this.error);
            }
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : (e && e.message ? e.message : 'Unknown error');
            console.error('Connection test error', this.error);
        } finally {
            this.isLoading = false;
        }
    }

    async fetchAvailableObjects() {
        if (!this.sessionId || !this.instanceUrl) {
            console.error('SessionId or instanceUrl not available');
            return;
        }

        try {
            console.log('Fetching available objects');
            const objects = await getAvailableObjects({
                sessionId: this.sessionId,
                instanceUrl: this.instanceUrl
            });
            this.availableObjects = objects || [];
            this.showObjectPicker = true;
            console.log('Fetched objects:', this.availableObjects.length);
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : (e && e.message ? e.message : 'Failed to fetch objects');
            console.error('Error fetching objects', this.error);
        }
    }

    handleLimitChange = (event) => {
        const val = parseInt(event.target.value, 10);
        this.exportLimit = Number.isFinite(val) && val > 0 ? val : 1;
    };

    async runQueryWithSession(soql) {
        return queryWithSession({
            sessionId: this.sessionId,
            instanceUrl: this.instanceUrl,
            soql
        });
    }

    get hasExportOrder() {
        return Array.isArray(this.exportOrder) && this.exportOrder.length > 0;
    }

    async handleExport() {
        if (!this.sessionId || !this.instanceUrl) {
            this.error = 'Please test connection first';
            return;
        }
        if (!this.hasPlan || !this.hasExportOrder) {
            this.error = 'Run Check Plan to build the export plan first';
            return;
        }

        const limit = Number.isFinite(this.exportLimit) && this.exportLimit > 0 ? this.exportLimit : 1;
        const order = [...this.exportOrder];
        if (!order.length) {
            this.error = 'No objects available in export order';
            return;
        }

        this.error = undefined;
        try {
            this.isLoading = true;
            const selectedEdges = this.collectSelectedEdgesFromPlan(this.planRoot);
            const queriedMap = await this.collectIds(order, limit, selectedEdges);
            const cloned = new Map();
            for (const [objectName, idSet] of queriedMap.entries()) {
                cloned.set(objectName, new Set(idSet));
            }
            this.lastQueriedIdSets = cloned;
            this.lastQueriedIdSnapshot = this.serializeIdSets(cloned);
            console.log(JSON.stringify({ type: 'ID_COLLECTION_RESULT', queriedIdSet: this.lastQueriedIdSnapshot }, null, 2));
        } catch (e) {
            const msg = e && e.body && e.body.message ? e.body.message : (e && e.message ? e.message : 'Export failed');
            this.error = msg;
            console.error('Export error', msg);
        } finally {
            this.isLoading = false;
        }
    }

    handlePlanEdgeToggle = (event) => {
        const { nodeId, isSelected } = event.detail || {};
        if (!nodeId) return;
        const root = this.clonePlanNode(this.planRoot);
        const info = this.findParentAndIndexById(root, nodeId);
        if (!info) return;
        const edgeNode = info.parent.children[info.index];
        edgeNode.isSelected = !!isSelected;
        // Cascade selection state down to all descendant edges below the target object
        const cascade = (node, selected) => {
            if (!node || !Array.isArray(node.children)) return;
            for (const child of node.children) {
                if (child.type === 'edge') {
                    child.isSelected = !!selected;
                    if (child.children && child.children[0]) cascade(child.children[0], selected);
                } else {
                    cascade(child, selected);
                }
            }
        };
        if (edgeNode.children && edgeNode.children[0]) {
            cascade(edgeNode.children[0], !!isSelected);
        }
        this.planRoot = root;
    };

    handlePlanObjectToggle = (event) => {
        const { nodeId, isSelected } = event.detail || {};
        if (!nodeId) return;
        const root = this.clonePlanNode(this.planRoot);
        const info = this.findParentAndIndexById(root, nodeId);
        if (!info) return;
        const objectNode = info.parent.children[info.index] || (info.parent.id === nodeId ? info.parent : null);
        if (!objectNode) return;
        const setEdges = (node, selected) => {
            if (!node || !Array.isArray(node.children)) return;
            for (const child of node.children) {
                if (child.type === 'edge') {
                    child.isSelected = !!selected;
                    if (child.children && child.children[0]) setEdges(child.children[0], selected);
                } else {
                    setEdges(child, selected);
                }
            }
        };
        setEdges(objectNode, !!isSelected);
        this.planRoot = root;
    };

    collectSelectedEdgesFromPlan(root) {
        const map = new Map();
        const add = (fromObj, fieldName, toObj) => {
            if (!map.has(fromObj)) map.set(fromObj, []);
            map.get(fromObj).push({ fieldName, target: toObj });
        };
        const walk = (node, currentObject) => {
            if (!node) return;
            if (node.type === 'object') {
                currentObject = node.objectName;
            }
            if (Array.isArray(node.children)) {
                for (const child of node.children) {
                    if (child.type === 'edge') {
                        if (child.isSelected) add(currentObject, child.fieldName, child.targetObject);
                        if (child.children && child.children[0]) {
                            walk(child.children[0], child.targetObject);
                        }
                    } else {
                        walk(child, currentObject);
                    }
                }
            }
        };
        walk(root, root && root.objectName);
        return map;
    }
    async collectIds(order, limit, edgesByObject) {
        const queried = new Map();
        const pending = new Map();

        for (const objectName of order) {
            this.ensureObjectEntry(objectName, queried, pending);
        }

        const bootstrapObjects = this.getBootstrapObjects(order, edgesByObject);
        for (const objectName of bootstrapObjects) {
            await this.queryAndProcess(objectName, { limit }, edgesByObject, queried, pending);
        }

        while (true) {
            let madeProgress = false;

            for (let idx = order.length - 1; idx >= 0; idx -= 1) {
                const objectName = order[idx];
                const pendingSet = pending.get(objectName);
                if (!pendingSet || pendingSet.size === 0) {
                    continue;
                }
                const idsToQuery = Array.from(pendingSet).filter((id) => id && !queried.get(objectName).has(id));
                if (!idsToQuery.length) {
                    pendingSet.clear();
                    continue;
                }
                await this.queryAndProcess(objectName, { ids: idsToQuery }, edgesByObject, queried, pending);
                pendingSet.clear();
                madeProgress = true;
            }

            if (!madeProgress) {
                break;
            }

            const stillPending = order.some((objectName) => {
                const set = pending.get(objectName);
                if (!set || set.size === 0) {
                    return false;
                }
                for (const id of set) {
                    if (id && !queried.get(objectName).has(id)) {
                        return true;
                    }
                }
                return false;
            });

            if (!stillPending) {
                break;
            }
        }

        return queried;
    }

    ensureObjectEntry(objectName, queried, pending) {
        if (!queried.has(objectName)) {
            queried.set(objectName, new Set());
        }
        if (!pending.has(objectName)) {
            pending.set(objectName, new Set());
        }
    }

    getBootstrapObjects(order, edgesByObject) {
        if (!order || !order.length) {
            return [];
        }
        const referencedAsTarget = new Set();
        for (const edges of edgesByObject.values()) {
            for (const edge of edges) {
                referencedAsTarget.add(edge.target);
            }
        }
        const candidates = order.filter((objectName) => !referencedAsTarget.has(objectName));
        // Only bootstrap objects that still have selected outgoing edges
        const withEdges = candidates.filter((obj) => {
            const edges = edgesByObject.get(obj) || [];
            return edges.length > 0;
        });
        if (withEdges.length) {
            return withEdges;
        }
        return [];
    }

    async queryAndProcess(objectName, options, edgesByObject, queried, pending) {
        this.ensureObjectEntry(objectName, queried, pending);
        const edges = edgesByObject.get(objectName) || [];
        const fieldSet = new Set();
        for (const edge of edges) {
            if (edge.fieldName) {
                fieldSet.add(edge.fieldName);
            }
        }
        const fieldList = Array.from(fieldSet);
        const selectClause = fieldList.length ? `Id, ${fieldList.join(', ')}` : 'Id';

        if (options.ids && options.ids.length) {
            const batches = this.chunkArray(options.ids, 200);
            for (const batch of batches) {
                const cleaned = batch.filter(Boolean);
                if (!cleaned.length) {
                    continue;
                }
                const where = cleaned.map((id) => `'${id.replace(/'/g, "\\'")}'`).join(',');
                const soql = `SELECT ${selectClause} FROM ${objectName} WHERE Id IN (${where})`;
                await this.processQueryRows(objectName, soql, edges, queried, pending);
            }
        } else {
            // Bootstrap query: only run if there are selected outgoing edges
            if (fieldList.length === 0) {
                return; // no selected paths from this object; skip bootstrapping it
            }
            const soql = `SELECT ${selectClause} FROM ${objectName} LIMIT ${options.limit}`;
            await this.processQueryRows(objectName, soql, edges, queried, pending);
        }
    }

    async processQueryRows(objectName, soql, edges, queried, pending) {
        const result = await this.runQueryWithSession(soql);
        const rows = (result && result.rows) || [];
        const objectSet = queried.get(objectName);
        for (const row of rows) {
            if (!row) {
                continue;
            }
            const rowId = row.Id;
            if (rowId) {
                objectSet.add(rowId);
            }
            for (const edge of edges) {
                const rawValue = edge.fieldName ? row[edge.fieldName] : undefined;
                if (!rawValue) {
                    continue;
                }
                this.ensureObjectEntry(edge.target, queried, pending);
                const targetPending = pending.get(edge.target);
                const targetQueried = queried.get(edge.target);
                const values = Array.isArray(rawValue) ? rawValue : [rawValue];
                for (const value of values) {
                    if (!value) {
                        continue;
                    }
                    const candidate = typeof value === 'object' && value !== null ? value.Id : value;
                    if (typeof candidate === 'string' && candidate && !targetQueried.has(candidate)) {
                        targetPending.add(candidate);
                    }
                }
            }
        }
    }

    serializeIdSets(idSetMap) {
        const output = {};
        for (const [objectName, idSet] of idSetMap.entries()) {
            output[objectName] = Array.from(idSet).sort();
        }
        return output;
    }

    chunkArray(arr, size) {
        const out = [];
        for (let i = 0; i < arr.length; i += size) {
            out.push(arr.slice(i, i + size));
        }
        return out;
    }

    async handleFinalExport() {
        if (!this.sessionId || !this.instanceUrl) {
            this.error = 'Please test connection first';
            return;
        }
        if (!this.lastQueriedIdSets || this.lastQueriedIdSets.size === 0) {
            this.error = 'Run Export to collect IDs before building final queries';
            return;
        }
        const objectsWithIds = this.exportOrder.filter((objectName) => {
            const set = this.lastQueriedIdSets.get(objectName);
            return set && set.size > 0;
        });
        if (!objectsWithIds.length) {
            this.error = 'No collected IDs available for final export';
            return;
        }

        this.error = undefined;
        try {
            this.isLoading = true;
            const creatableMap = await getCreateableFields({
                sessionId: this.sessionId,
                instanceUrl: this.instanceUrl,
                objectNames: objectsWithIds
            });

            const queries = [];
            for (const objectName of objectsWithIds) {
                const ids = Array.from(this.lastQueriedIdSets.get(objectName) || []);
                if (!ids.length) {
                    continue;
                }
                const fields = (creatableMap && creatableMap[objectName]) || [];
                const uniqueFields = ['Id', ...fields.filter((field) => field && field !== 'Id')];
                const selectClause = uniqueFields.join(', ');
                for (const batch of this.chunkArray(ids, 200)) {
                    const where = batch.filter(Boolean).map((id) => `'${id.replace(/'/g, "\\'")}'`).join(',');
                    if (!where) {
                        continue;
                    }
                    const soql = `SELECT ${selectClause} FROM ${objectName} WHERE Id IN (${where})`;
                    queries.push({ objectName, count: batch.length, soql });
                }
            }

            console.log(JSON.stringify({ type: 'FINAL_EXPORT_SOQL', queries }, null, 2));
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : (e && e.message ? e.message : 'Failed to build final export queries');
            console.error('Final export error', this.error);
        } finally {
            this.isLoading = false;
        }
    }

    computeExportOrder(edgesByObject, rootObject, idSetKeys = []) {
        // Build nodes, adjacency (parent -> children), and in-degree(children)
        const nodes = new Set(idSetKeys || []);
        const adj = new Map();
        const inDegree = new Map();

        const ensureNode = (n) => {
            if (!inDegree.has(n)) inDegree.set(n, 0);
        };

        for (const [fromObj, edges] of edgesByObject.entries()) {
            nodes.add(fromObj);
            ensureNode(fromObj);
            for (const e of edges) {
                nodes.add(e.target);
                ensureNode(e.target);
                // Edge: parent (target) -> child (fromObj)
                if (!adj.has(e.target)) adj.set(e.target, new Set());
                if (!adj.get(e.target).has(fromObj)) {
                    adj.get(e.target).add(fromObj);
                    inDegree.set(fromObj, (inDegree.get(fromObj) || 0) + 1);
                }
            }
        }

        // Ensure all idSetKeys exist in maps
        for (const n of nodes) ensureNode(n);

        // Kahn's algorithm with tie-breaker: prioritize root when it becomes available
        const order = [];
        const inQueue = new Set();
        const queue = [];

        const enqueue = (n, prioritize = false) => {
            if (inQueue.has(n)) return;
            if (prioritize) {
                queue.unshift(n);
            } else {
                queue.push(n);
            }
            inQueue.add(n);
        };

        for (const n of nodes) {
            if ((inDegree.get(n) || 0) === 0) enqueue(n, n === rootObject);
        }

        while (queue.length) {
            const n = queue.shift();
            order.push(n);
            const children = Array.from(adj.get(n) || []);
            for (const c of children) {
                inDegree.set(c, (inDegree.get(c) || 0) - 1);
                if ((inDegree.get(c) || 0) === 0) enqueue(c, c === rootObject);
            }
        }

        // Add any isolated nodes not reached
        for (const n of nodes) {
            if (!order.includes(n)) order.push(n);
        }

        return order;
    }

    async handleCheckPlan() {
        if (!this.selectedObject || !this.sessionId || !this.instanceUrl) {
            this.error = 'Please select an object and ensure connection is established';
            return;
        }

        this.error = undefined;
        this.isLoading = true;

        try {
            console.log('Checking dependencies for:', this.selectedObject, 'with depth:', this.maxDepth, 'excluding:', this.excludedObjects);
            const dependencies = await getObjectDependencies({
                sessionId: this.sessionId,
                instanceUrl: this.instanceUrl,
                objectName: this.selectedObject,
                maxDepth: this.maxDepth,
                excludedObjects: this.excludedObjects
            });
            this.dependencyTree = dependencies;
            this.buildPlanState(dependencies);
            console.log(JSON.stringify({ type: 'EXPORT_PLAN', root: this.selectedObject, order: this.exportOrder }, null, 2));
            
            console.log('Dependencies retrieved:', dependencies);
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : (e && e.message ? e.message : 'Failed to get dependencies');
            console.error('Error getting dependencies', this.error);
            this.dependencyTree = undefined;
            this.planRoot = undefined;
            this.planEdges = new Map();
            this.exportOrder = [];
            this.planReady = false;
        } finally {
            this.isLoading = false;
        }
    }

    resetObjectSelection() {
        this.showObjectPicker = false;
        this.availableObjects = [];
        this.selectedObject = undefined;
        this.dependencyTree = undefined;
        this.sessionId = undefined;
        this.instanceUrl = undefined;
        this.maxDepth = 3;
        this.excludedObjects = [];
        this.planRoot = undefined;
        this.planEdges = new Map();
        this.exportOrder = [];
        this.planReady = false;
        this.lastQueriedIdSets = new Map();
        this.lastQueriedIdSnapshot = undefined;
    }
}





