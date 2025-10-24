import { LightningElement, track } from 'lwc';
import testConnection from '@salesforce/apex/ExternalOrgQueryController.testConnection';
import getAvailableObjects from '@salesforce/apex/ExternalOrgQueryController.getAvailableObjects';
import getObjectDependencies from '@salesforce/apex/ExternalOrgQueryController.getObjectDependencies';
import getCreateableFields from '@salesforce/apex/ExternalOrgQueryController.getCreateableFields';
import queryWithSession from '@salesforce/apex/ExternalOrgQueryController.queryWithSession';
import getAvailableObjectsCurrent from '@salesforce/apex/ExternalOrgQueryController.getAvailableObjectsCurrent';
import getObjectDependenciesCurrent from '@salesforce/apex/ExternalOrgQueryController.getObjectDependenciesCurrent';
import getCreateableFieldsCurrent from '@salesforce/apex/ExternalOrgQueryController.getCreateableFieldsCurrent';
import queryCurrent from '@salesforce/apex/ExternalOrgQueryController.queryCurrent';

export default class ExternalOrgQuery extends LightningElement {
    // UI state for external org connection and query execution
    // Source org (kept as existing fields for compatibility)
    @track username = 'ayannbhunia@gmail.com.dbtd3'; // for testing, will remove later
    @track password = 'aYANbHUNIA1234!UwlqVpYeKSapeeHia8ecxJk5'; // for testing, will remove later
    @track environment = 'Production';
    @track testMessage;
    @track sessionId;
    @track instanceUrl;

    // Destination org (new, stored separately)
    @track destUsername = '';
    @track destPassword = '';
    @track destEnvironment = 'Production';
    @track destTestMessage;
    @track destSessionId;
    @track destInstanceUrl;
    @track soql = '';
    // Removed table results; we no longer build datatable
    @track error;
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
    @track finalExportQueries = [];
    isLoading = false;
    // One-shot flags to suppress onchange after manual deselect click
    _suppressSourceChangeOnce = false;
    _suppressDestChangeOnce = false;

    planEdges = new Map();
    lastQueriedIdSets = new Map();
    // Picklist state for current-org selection
    @track sourceUseCurrent = 'no';
    @track destUseCurrent = 'no';
    // Lightweight console logger
    debug = (...args) => { try { console.log('[ExternalOrgQuery]', ...args); } catch (e) { /* no-op */ } };

    get environmentOptions() {
        // Environment options for login host selection
        return [
            { label: 'Production', value: 'Production' },
            { label: 'Sandbox', value: 'Sandbox' }
        ];
    }

    get yesNoOptions() {
        return [
            { label: 'Yes', value: 'yes' },
            { label: 'No', value: 'no' }
        ];
    }

    // Connection state + button gating
    get isSourceConnected() {
        return this.isSourceCurrentOrg || !!(this.sessionId && this.instanceUrl);
    }

    get isDestinationConnected() {
        return this.isDestinationCurrentOrg || !!(this.destSessionId && this.destInstanceUrl);
    }

    get isRunDisabled() {
        // Disable until source connected, SOQL present, and object picklist loaded
        return !this.isSourceConnected || !this.soql || !this.showObjectPicker || this.isLoading;
    }

    get canTestSource() {
        return !!this.username && !!this.password && !this.isLoading;
    }

    get canTestDestination() {
        return !!this.destUsername && !!this.destPassword && !this.isLoading;
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
    handleUsernameChange = (event) => { this.username = event.target.value; this.testMessage = undefined; this.error = undefined; this.clearSourceSession(); this.resetObjectSelection(); console.log('Username updated'); };
    handlePasswordChange = (event) => { this.password = event.target.value; this.testMessage = undefined; this.error = undefined; this.clearSourceSession(); this.resetObjectSelection(); console.log('Password updated'); };
    handleEnvironmentChange = (event) => { this.environment = event.detail.value; this.testMessage = undefined; this.error = undefined; this.clearSourceSession(); this.resetObjectSelection(); };
    handleSoqlChange = (event) => { this.soql = event.target.value; };
    handleObjectChange = (event) => { this.selectedObject = event.detail.value; this.dependencyTree = undefined; };
    
    // Destination input handlers
    handleDestUsernameChange = (event) => { this.destUsername = event.target.value; this.destTestMessage = undefined; };
    handleDestPasswordChange = (event) => { this.destPassword = event.target.value; this.destTestMessage = undefined; };
    handleDestEnvironmentChange = (event) => { this.destEnvironment = event.detail.value; this.destTestMessage = undefined; };
    handleDepthChange = (event) => {
        const raw = parseInt(event.target.value, 10);
        const safe = Number.isFinite(raw) && raw >= 0 ? raw : 0;
        this.maxDepth = safe;
        this.dependencyTree = undefined;
    };

    // New picklist handlers to centralize YES/NO and keep Source/Destination synchronized
    handleSourceCurrentPick = (event) => {
        const val = (event && event.detail && event.detail.value) || 'no';
        this.sourceUseCurrent = val;
        if (val === 'yes') {
            // Force destination to NO
            this.destUseCurrent = 'no';
            this.currentOrgFor = 'source';
            this.destTestMessage = undefined;
            // Switch to current-org for source: reset external session/UI and load objects
            this.clearSourceSession();
            this.resetObjectSelection();
            this.fetchAvailableObjectsSource();
        } else {
            // Turning off current org for source
            if (this.isSourceCurrentOrg) {
                this.currentOrgFor = this.destUseCurrent === 'yes' ? 'destination' : '';
            }
            this.clearSourceSession();
            this.resetObjectSelection();
        }
    };

    handleDestinationCurrentPick = (event) => {
        const val = (event && event.detail && event.detail.value) || 'no';
        this.destUseCurrent = val;
        if (val === 'yes') {
            // Force source to NO
            this.sourceUseCurrent = 'no';
            this.currentOrgFor = 'destination';
            // Clear destination external session as we are using current org
            this.destSessionId = undefined;
            this.destInstanceUrl = undefined;
            this.destTestMessage = undefined;
        } else {
            // Turning off current org for destination
            if (this.isDestinationCurrentOrg) {
                this.currentOrgFor = this.sourceUseCurrent === 'yes' ? 'source' : '';
            }
        }
    };

    // Helper utilities to centralize connection routing
    isSourceCurrent() { return this.isSourceCurrentOrg; }
    isDestinationCurrent() { return this.isDestinationCurrentOrg; }
    ensureSourceConnected(message = 'Please test connection first') {
        if (this.isSourceCurrentOrg) return true;
        if (this.sessionId && this.instanceUrl) return true;
        this.error = message;
        return false;
    }
    ensureDestinationConnected(message = 'Please test connection first') {
        if (this.isDestinationCurrentOrg) return true;
        if (this.destSessionId && this.destInstanceUrl) return true;
        this.error = message;
        return false;
    }
    routeSourceCall(fnCurrent, fnSession) {
        return this.isSourceCurrentOrg ? fnCurrent() : fnSession();
    }
    routeDestinationCall(fnCurrent, fnSession) {
        return this.isDestinationCurrentOrg ? fnCurrent() : fnSession();
    }
    handleExcludedObjectsChange = (event) => { this.excludedObjects = event.detail.value || []; this.dependencyTree = undefined; };
    handleSelectStandardObjects = () => { this.excludedObjects = this.standardObjects; this.dependencyTree = undefined; };
    handleSelectCustomObjects = () => { this.excludedObjects = this.customObjects; this.dependencyTree = undefined; };
    handleClearExclusions = () => { this.excludedObjects = []; this.dependencyTree = undefined; };

    // Current Org selection state
    @track currentOrgFor = '';
    get isSourceCurrentOrg() { return this.currentOrgFor === 'source'; }
    get isDestinationCurrentOrg() { return this.currentOrgFor === 'destination'; }
    get sourceSectionClass() { return this.isSourceCurrentOrg ? 'section-disabled' : ''; }
    get destinationSectionClass() { return this.isDestinationCurrentOrg ? 'section-disabled' : ''; }
    handleSelectSourceCurrent = () => {
        if (this._suppressSourceChangeOnce) {
            this._suppressSourceChangeOnce = false;
            return;
        }
        if (!this.isSourceCurrentOrg) {
            this.currentOrgFor = 'source';
            this.sourceUseCurrent = 'yes';
            this.destUseCurrent = 'no';
            this.destTestMessage = undefined;
            // Clear any external source session and fetch current org objects
            this.clearSourceSession();
            this.resetObjectSelection();
            this.fetchAvailableObjectsSource();
        }
    };
    handleSelectDestinationCurrent = () => {
        if (this._suppressDestChangeOnce) {
            this._suppressDestChangeOnce = false;
            return;
        }
        if (!this.isDestinationCurrentOrg) {
            this.currentOrgFor = 'destination';
            this.sourceUseCurrent = 'no';
            this.destUseCurrent = 'yes';
            // Clear destination external session
            this.destSessionId = undefined;
            this.destInstanceUrl = undefined;
            this.destTestMessage = undefined;
        }
    };

    // Allow unselecting the currently selected radio by clicking it again
    handleToggleSourceCurrent = (event) => {
        try { event && event.stopPropagation && event.stopPropagation(); } catch (e) { /* no-op */ }
        if (this.isSourceCurrentOrg) {
            // Suppress the immediate onchange that lightning-input may fire
            this._suppressSourceChangeOnce = true;
            // Unselect current-org for source
            this.currentOrgFor = '';
            // Reset UI that depends on source connection/object list
            this.clearSourceSession();
            this.resetObjectSelection();
        }
        // If not selected, normal onchange will handle selecting it
    };

    handleToggleDestinationCurrent = (event) => {
        try { event && event.stopPropagation && event.stopPropagation(); } catch (e) { /* no-op */ }
        if (this.isDestinationCurrentOrg) {
            // Suppress the immediate onchange that lightning-input may fire
            this._suppressDestChangeOnce = true;
            // Unselect current-org for destination
            this.currentOrgFor = '';
            // No additional cleanup needed for destination beyond UI state
        }
        // If not selected, normal onchange will handle selecting it
    };

    get hasPlan() {
        // Consider a plan valid if we built a root node, even with no edges
        return this.planReady && !!this.planRoot;
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
        const destConnected = this.isDestinationCurrentOrg || (!!this.destSessionId && !!this.destInstanceUrl);
        return this.isExportDisabled || !this.hasCollectedIds || !destConnected;
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
            this.exportOrder = currentChildren.map(node => (node.type === 'edge' && node.targetObject) ? node.targetObject : (node.objectName || node.label));
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

    handleExpandAll = () => {
        if (!this.planRoot) return;
        const clone = this.clonePlanNode(this.planRoot);
        const setCollapsed = (node, collapsed) => {
            if (!node) return;
            if (node.children && node.children.length) {
                node.isCollapsed = collapsed;
                for (const child of node.children) setCollapsed(child, collapsed);
            }
        };
        setCollapsed(clone, false);
        this.planRoot = clone;
    };

    handleCollapseAll = () => {
        if (!this.planRoot) return;
        const clone = this.clonePlanNode(this.planRoot);
        const setCollapsed = (node, collapsed) => {
            if (!node) return;
            if (node.children && node.children.length) {
                node.isCollapsed = collapsed;
                for (const child of node.children) setCollapsed(child, collapsed);
            }
        };
        setCollapsed(clone, true);
        this.planRoot = clone;
    };

    toggleNodeCollapsed(node, nodeId) {
        if (!node) {
            return false;
        }
        if (node.id === nodeId) {
            node.isCollapsed = !node.isCollapsed;
            // If expanding an edge node with a suppressed child object header,
            // also uncollapse the immediate child object so grandchildren become visible.
            if (!node.isCollapsed && node.type === 'edge' && node.children && node.children[0]) {
                node.children[0].isCollapsed = false;
            }
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
        const buildEdgeNode = (fromObj, edge, pathKey, depth, visited, seq) => {
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
                draggable: true,
                isSelected: true,
                seq,
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
                draggable: true,
                children: []
            };
            // Prevent cycles: if this object is already in the current path, stop here
            if (visited.has(objectName)) {
                node.isLeaf = true;
                return node;
            }
            const nextVisited = new Set(visited);
            nextVisited.add(objectName);
            const edges = edgesByObject.get(objectName) || [];
            edges.forEach((e, idx) => {
                const edgeNode = buildEdgeNode(objectName, e, `${pathKey}e${idx}`, depth + 1, nextVisited, idx + 1);
                node.children.push(edgeNode);
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
        // Now only parses SOQL and updates object/limit; no data fetching
        this.error = undefined;
        this.testMessage = undefined;
        this.debug('Run Query clicked', {
            isSourceConnected: this.isSourceConnected,
            showObjectPicker: this.showObjectPicker,
            isLoading: this.isLoading,
            soqlPreview: (this.soql || '').slice(0, 120)
        });
        if (!this.isSourceConnected) {
            this.error = 'Please test Source connection first';
            this.debug('Blocked: source not connected');
            return;
        }
        if (!this.showObjectPicker) {
            this.debug('Blocked: object picklist not loaded yet');
        }
        try {
            const parsed = this.parseSoql(this.soql || '');
            if (parsed && parsed.objectName) {
                const obj = parsed.objectName;
                const match = this.findAvailableObjectMatch(obj);
                if (match) {
                    this.selectedObject = match;
                    this.dependencyTree = undefined;
                    this.debug('Selected object set from SOQL (matched):', this.selectedObject);
                } else {
                    const msg = `Object \"${obj}\" not found in available objects`;
                    this.error = msg;
                    this.debug('SOQL object match error:', msg);
                }
            }
            if (parsed && Number.isFinite(parsed.limit)) {
                this.exportLimit = parsed.limit;
                // limit set from query LIMIT clause
                }
        } catch (parseErr) {
            this.error = parseErr && parseErr.message ? parseErr.message : 'Failed to parse SOQL';
        }
    }

    parseSoql(soql) {
        const text = (soql || '').trim();
        if (!text) {
            throw new Error('SOQL is empty');
        }
        const fromMatch = text.match(/\bfrom\s+([a-zA-Z0-9_]+)/i);
        if (!fromMatch || !fromMatch[1]) {
            throw new Error('Unable to detect object name after FROM');
        }
        const objectName = fromMatch[1];
        let limit;
        const limMatch = text.match(/\blimit\s+(\d+)/i);
        if (limMatch && limMatch[1]) {
            const n = parseInt(limMatch[1], 10);
            if (!Number.isFinite(n)) {
                throw new Error('Invalid LIMIT value');
            }
            limit = n;
        }
        return { objectName, limit };
    }

    stripNamespace(name) {
        const n = (name || '').trim();
        // Remove leading package namespace prefix like ns__
        return n.replace(/^[a-zA-Z0-9]+__/, '');
    }

    normalizeName(name) {
        return (name || '').toLowerCase();
    }

    findAvailableObjectMatch(objName) {
        const list = Array.isArray(this.availableObjects) ? this.availableObjects : [];
        const objLower = this.normalizeName(objName);
        // 1) direct case-insensitive match
        const direct = list.find(o => this.normalizeName(o) === objLower);
        if (direct) return direct;
        // 2) suffix exact match (case-insensitive)
        const suffix = this.normalizeName(this.stripNamespace(objName));
        const exactSuffix = list.find(o => this.normalizeName(o) === suffix);
        if (exactSuffix) return exactSuffix;
        // 3) namespaced mapping by comparing stripped names case-insensitively
        const candidates = list.filter(o => this.normalizeName(this.stripNamespace(o)) === suffix);
        if (candidates.length === 1) return candidates[0];
        // ambiguous or none => no match
        return null;
    }

    async handleTestConnection() {
        this.error = undefined;
        this.testMessage = undefined;
        this.isLoading = true;
        try {
            this.debug('Calling Apex testConnection (source)', { username: this.username, environment: this.environment });
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
                await this.fetchAvailableObjectsSource();
                
                this.debug('Connection test successful (source)');
            } else {
                this.error = (res && res.message) ? res.message : 'Connection failed';
                this.debug('Connection test failed (source)', this.error);
            }
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : (e && e.message ? e.message : 'Unknown error');
            this.debug('Connection test error (source)', this.error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleTestConnectionDestination() {
        // Destination connection test: only display result, store separately
        this.destTestMessage = undefined;
        const credsMissing = !this.destUsername || !this.destPassword;
        if (credsMissing) {
            this.destTestMessage = 'Please provide Destination Username and Password';
            return;
        }
        this.isLoading = true;
        try {
            this.debug('Calling Apex testConnection (destination)', { username: this.destUsername, environment: this.destEnvironment });
            const res = await testConnection({
                username: this.destUsername,
                password: this.destPassword,
                environment: this.destEnvironment
            });
            if (res && res.success) {
                const instance = res.instanceUrl ? ` (${res.instanceUrl})` : '';
                this.destTestMessage = `Connection successful${instance}`;
                this.destSessionId = res.sessionId;
                this.destInstanceUrl = res.instanceUrl;
            } else {
                this.destTestMessage = (res && res.message) ? `Connection failed: ${res.message}` : 'Connection failed';
            }
        } catch (e) {
            const msg = e && e.body && e.body.message ? e.body.message : (e && e.message ? e.message : 'Unknown error');
            this.destTestMessage = `Connection failed: ${msg}`;
        } finally {
            this.isLoading = false;
        }
    }

    // Unified object list fetch using current-org or session based on source mode
    async fetchAvailableObjectsSource() {
        try {
            this.debug('Fetching available objects (source, routed)');
            const objects = await this.routeSourceCall(
                () => getAvailableObjectsCurrent(),
                () => {
                    if (!this.sessionId || !this.instanceUrl) {
                        this.debug('No session available for external object fetch');
                        return [];
                    }
                    return getAvailableObjects({ sessionId: this.sessionId, instanceUrl: this.instanceUrl });
                }
            );
            this.availableObjects = objects || [];
            this.showObjectPicker = true;
            try { this.excludedObjects = this.standardObjects; } catch (e) { /* no-op */ }
            this.debug('Fetched objects count', (this.availableObjects && this.availableObjects.length) || 0);
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : (e && e.message ? e.message : 'Failed to fetch objects');
            this.debug('Error fetching objects', this.error);
        }
    }

    handleLimitChange = (event) => {
        const val = parseInt(event.target.value, 10);
        this.exportLimit = Number.isFinite(val) && val > 0 ? val : 1;
    };

    async runQueryWithSession(soql) {
        return this.routeSourceCall(
            () => queryCurrent({ soql }),
            () => queryWithSession({ sessionId: this.sessionId, instanceUrl: this.instanceUrl, soql })
        );
    }

    get hasExportOrder() {
        return Array.isArray(this.exportOrder) && this.exportOrder.length > 0;
    }

    async handleExport() {
        if (!this.ensureSourceConnected('Please test connection first')) {
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
        // Cascade selection + lock state down to all descendant edges below the target object
        const setDescendants = (node, selected) => {
            if (!node || !Array.isArray(node.children)) return;
            for (const child of node.children) {
                if (child.type === 'edge') {
                    child.isSelected = !!selected;
                    child.lockedByAncestor = !selected;
                    if (child.children && child.children[0]) {
                        child.children[0].lockedByAncestor = !selected;
                        setDescendants(child.children[0], selected);
                    }
                } else {
                    child.lockedByAncestor = !selected;
                    setDescendants(child, selected);
                }
            }
        };
        if (edgeNode.children && edgeNode.children[0]) {
            setDescendants(edgeNode.children[0], !!isSelected);
        }
        this.planRoot = root;
    };

    handlePlanObjectToggle = (event) => {
        const { nodeId, isSelected } = event.detail || {};
        if (!nodeId) return;
        const root = this.clonePlanNode(this.planRoot);
        const info = this.findParentAndIndexById(root, nodeId);
        if (!info) return;
        const objectNode = info.parent.children[info.index] || (info.parent && info.parent.id === nodeId ? info.parent : null);
        if (!objectNode) return;
        const setDescendants = (node, selected) => {
            if (!node || !Array.isArray(node.children)) return;
            for (const child of node.children) {
                if (child.type === 'edge') {
                    child.isSelected = !!selected;
                    child.lockedByAncestor = !selected;
                    if (child.children && child.children[0]) {
                        // lock/unlock the target object subtree
                        child.children[0].lockedByAncestor = !selected;
                        setDescendants(child.children[0], selected);
                    }
                } else {
                    child.lockedByAncestor = !selected;
                    setDescendants(child, selected);
                }
            }
        };
        // Lock or unlock all descendants based on object selection
        objectNode.lockedByAncestor = !isSelected;
        setDescendants(objectNode, !!isSelected);
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
        // Prefer to bootstrap objects that still have selected outgoing edges
        const withEdges = candidates.filter((obj) => {
            const edges = edgesByObject.get(obj) || [];
            return edges.length > 0;
        });
        if (withEdges.length) {
            return withEdges;
        }
        // If none have edges (e.g., depth 0 or a leaf/root-only export),
        // bootstrap the first object in the order (root prioritized in order)
        return [order[0]];
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
            // Bootstrap query: even if there are no selected outgoing edges, we still need Ids
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
        // Require source connectivity for schema discovery if not current org
        if (!this.ensureSourceConnected('Please test connection first')) {
            return;
        }
        // Destination must be connected (either as current org or tested external session)
        if (!this.ensureDestinationConnected('Please test destination connection first')) {
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

            // Get creatable fields from source and destination for intersection
            const sourceCreatableMap = await this.routeSourceCall(
                () => getCreateableFieldsCurrent({ objectNames: objectsWithIds }),
                () => getCreateableFields({ sessionId: this.sessionId, instanceUrl: this.instanceUrl, objectNames: objectsWithIds })
            );
            const destCreatableMap = await this.routeDestinationCall(
                () => getCreateableFieldsCurrent({ objectNames: objectsWithIds }),
                () => getCreateableFields({ sessionId: this.destSessionId, instanceUrl: this.destInstanceUrl, objectNames: objectsWithIds })
            );

            // Iterate bottom-to-top of export order (reverse order)
            const iterationOrder = objectsWithIds.slice().reverse();
            const queries = [];
            for (const objectName of iterationOrder) {
                const ids = Array.from(this.lastQueriedIdSets.get(objectName) || []);
                if (!ids.length) continue;

                const srcFields = (sourceCreatableMap && sourceCreatableMap[objectName]) || [];
                const dstFields = (destCreatableMap && destCreatableMap[objectName]) || [];
                const dstSet = new Set(dstFields);
                const intersect = srcFields.filter((f) => f && f !== 'Id' && dstSet.has(f));
                const uniqueFields = ['Id', ...intersect];
                const selectClause = uniqueFields.join(', ');

                for (const batch of this.chunkArray(ids, 200)) {
                    const where = batch.filter(Boolean).map((id) => `'${id.replace(/'/g, "\\'")}'`).join(',');
                    if (!where) continue;
                    const soql = `SELECT ${selectClause} FROM ${objectName} WHERE Id IN (${where})`;
                    queries.push({ objectName, count: batch.length, soql, fields: uniqueFields });
                }
            }

            this.finalExportQueries = queries;
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
        // Require an object, and if using external session, require a tested connection
        if (!this.selectedObject) {
            this.error = 'Please select an object and ensure connection is established';
            return;
        }
        if (!this.ensureSourceConnected('Please select an object and ensure connection is established')) {
            return;
        }

        this.error = undefined;
        this.isLoading = true;

        try {
            console.log('Checking dependencies for:', this.selectedObject, 'with depth:', this.maxDepth, 'excluding:', this.excludedObjects);
            const paramsCurrent = { objectName: this.selectedObject, maxDepth: this.maxDepth, excludedObjects: this.excludedObjects };
            const paramsSession = { sessionId: this.sessionId, instanceUrl: this.instanceUrl, objectName: this.selectedObject, maxDepth: this.maxDepth, excludedObjects: this.excludedObjects };
            const dependencies = await this.routeSourceCall(
                () => getObjectDependenciesCurrent(paramsCurrent),
                () => getObjectDependencies(paramsSession)
            );
            // Fallback: if no dependencies returned, build a minimal tree with only the selected object
            const dep = dependencies || { objectName: this.selectedObject, parents: [] };
            this.dependencyTree = dep;
            this.buildPlanState(dep);
            // Collapse all nodes initially after building the plan,
            // then re-open the root so only descendants are collapsed
            try {
                this.handleCollapseAll();
                if (this.planRoot) {
                    const clone = this.clonePlanNode(this.planRoot);
                    clone.isCollapsed = false;
                    this.planRoot = clone;
                }
            } catch (e) { /* no-op */ }
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

    clearSourceSession() {
        this.sessionId = undefined;
        this.instanceUrl = undefined;
        this.testMessage = undefined;
    }

    handleReverseOrgs = () => {
        // Swap credentials and environments between Source and Destination
        this.debug('Reversing orgs');
        const sU = this.username;
        const sP = this.password;
        const sE = this.environment;

        this.username = this.destUsername || '';
        this.password = this.destPassword || '';
        this.environment = this.destEnvironment || 'Production';

        this.destUsername = sU || '';
        this.destPassword = sP || '';
        this.destEnvironment = sE || 'Production';

        // Swap current-org selection if set
        if (this.currentOrgFor === 'source') {
            this.currentOrgFor = 'destination';
        } else if (this.currentOrgFor === 'destination') {
            this.currentOrgFor = 'source';
        }

        // Clear connection states and UI dependent on source
        this.clearSourceSession();
        this.destSessionId = undefined;
        this.destInstanceUrl = undefined;
        this.destTestMessage = undefined;
        this.error = undefined;
        this.resetObjectSelection();
        // If source is now current org, prefetch objects
        if (this.isSourceCurrentOrg) {
            this.fetchAvailableObjectsSource();
        }
        // Sync the picklist UI to reflect currentOrgFor
        this.sourceUseCurrent = this.isSourceCurrentOrg ? 'yes' : 'no';
        this.destUseCurrent = this.isDestinationCurrentOrg ? 'yes' : 'no';
    };
}





