import { LightningElement, track } from 'lwc';
import loginAndQuery from '@salesforce/apex/ExternalOrgQueryController.loginAndQuery';
import testConnection from '@salesforce/apex/ExternalOrgQueryController.testConnection';
import getAvailableObjects from '@salesforce/apex/ExternalOrgQueryController.getAvailableObjects';
import getObjectDependencies from '@salesforce/apex/ExternalOrgQueryController.getObjectDependencies';
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
    @track allStandardObjects = [];
    @track selectedNodes = new Set();
    @track nodeFieldTypes = new Map();
    @track recordLimit = 2;
    @track tiebreakInput = '';
    isLoading = false;

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

    get hasDependencies() {
        return this.dependencyTree && this.dependencyTree.parents && this.dependencyTree.parents.length > 0;
    }

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

    get fieldTypeOptions() {
        return [
            { label: 'Id', value: 'Id' },
            { label: 'ExternalId', value: 'ExternalId' }
        ];
    }

    get rootDepth() {
        return 1;
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
    
    handleNodeSelection = (event) => {
        const { nodeId } = event.target.dataset;
        this.updateNodeSelection(nodeId, event.target.checked);
    };

    handleNodeClick = (event) => {
        const { nodeId } = event.target.dataset;
        const node = this.findNodeInTree(this.dependencyTree, nodeId);
        if (!node) return;

        if (node.isSelected) {
            event.preventDefault();
            event.stopPropagation();
            event.target.checked = false;
            this.updateNodeSelection(nodeId, false);
        }
    };

    updateNodeSelection = (nodeId, isSelected) => {
        if (isSelected) {
            this.selectedNodes.add(nodeId);
        } else {
            this.selectedNodes.delete(nodeId);
        }
        
        const node = this.findNodeInTree(this.dependencyTree, nodeId);
        if (node) {
            node.isSelected = isSelected;
            node.cardClass = this.computeCardClass(node);
            this.handleCascadingSelection(node, isSelected);
        }
        
        this.selectedNodes = new Set(this.selectedNodes);
        this.refreshDependencyTree();
    };

    handleCascadingSelection = (node, isSelected) => {
        if (!node) return;
        
        if (isSelected) {
            this.checkAllChildren(node);
        } else {
            this.uncheckAllChildren(node);
        }
        
        node.cardClass = this.computeCardClass(node);
    };
    
    findNodeInTree = (root, targetNodeId) => {
        if (!root) return null;

        if (root.nodeId === targetNodeId) {
            return root;
        }

        if (!root.parents || root.parents.length === 0) {
            return null;
        }

        for (let parent of root.parents) {
            const found = this.findNodeInTree(parent, targetNodeId);
            if (found) {
                return found;
            }
        }

        return null;
    };
    
    checkAllChildren = (node) => {
        if (!node.parents || node.parents.length === 0) return;
        
        node.parents.forEach(child => {
            child.isSelected = true;
            child.cardClass = this.computeCardClass(child);
            this.selectedNodes.add(child.nodeId);
            this.checkAllChildren(child);
        });
    };
    
    uncheckAllChildren = (node) => {
        if (!node.parents || node.parents.length === 0) return;
        
        node.parents.forEach(child => {
            child.isSelected = false;
            child.cardClass = this.computeCardClass(child);
            if (child.nodeId) {
                this.selectedNodes.delete(child.nodeId);
            }
            this.uncheckAllChildren(child);
        });
    };
    
    handleNodeToggle = (event) => {
        const { nodeId, isSelected } = event.detail || {};
        if (!nodeId) return;
        this.updateNodeSelection(nodeId, isSelected);
    };

    handleFieldTypeChange = (event) => {
        const nodeId = (event.detail && event.detail.nodeId) || (event.target && event.target.dataset && event.target.dataset.nodeId);
        const fieldType = (event.detail && (event.detail.fieldType || event.detail.value));
        this.nodeFieldTypes.set(nodeId, fieldType);
        const node = this.findNodeInTree(this.dependencyTree, nodeId);
        if (node) {
            node.fieldType = fieldType;
        }
        
        this.nodeFieldTypes = new Map(this.nodeFieldTypes);
        this.refreshDependencyTree();
    };
    
    generateNodeId = (objectName, fieldName, depth) => {
        return `${objectName}_${fieldName}_${depth}`;
    };
    
    decorateDependencyTree = (tree) => {
        if (!tree) {
            return tree;
        }

        const decorated = { ...tree };
        const parents = tree.parents || [];

        this.selectedNodes = new Set();
        this.nodeFieldTypes = new Map();

        decorated.parents = this.decorateNodes(parents, 1, 'r');

        this.selectedNodes = new Set(this.selectedNodes);
        this.nodeFieldTypes = new Map(this.nodeFieldTypes);

        return decorated;
    };

    decorateNodes = (nodes, depth, path) => {
        if (!nodes || nodes.length === 0) {
            return [];
        }

        return nodes.map((node, index) => {
            const objectKey = node.objectName || `object_${depth}_${index}`;
            const fieldKey = node.fieldName || `field_${depth}_${index}`;
            const idSuffix = `${path}-${index}`;
            const nodeId = `${this.generateNodeId(objectKey, fieldKey, depth)}_${idSuffix}`;
            const fieldType = this.nodeFieldTypes.has(nodeId) ? this.nodeFieldTypes.get(nodeId) : 'Id';

            const decoratedNode = {
                ...node,
                nodeId,
                depth,
                isSelected: true,
                fieldType,
            };

            decoratedNode.cardClass = this.computeCardClass(decoratedNode);

            this.selectedNodes.add(nodeId);
            this.nodeFieldTypes.set(nodeId, fieldType);

            if (node.parents && node.parents.length > 0) {
                decoratedNode.parents = this.decorateNodes(node.parents, depth + 1, idSuffix);
            }

            return decoratedNode;
        });
    };

    computeCardClass = (node) => {
        const baseClass = 'dependency-node-card slds-box slds-theme_default slds-m-bottom_small';
        return node && node.isSelected === false ? `${baseClass} unchecked` : baseClass;
    };

    refreshDependencyTree = () => {
        this.dependencyTree = this.cloneTree(this.dependencyTree);
    };

    cloneTree = (node) => {
        if (!node) {
            return node;
        }

        const clonedNode = { ...node };

        if (node.parents && node.parents.length > 0) {
            clonedNode.parents = node.parents.map(child => this.cloneTree(child));
        }

        return clonedNode;
    };

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

    handleRecordLimitChange = (event) => {
        const val = parseInt(event.target.value, 10);
        this.recordLimit = Number.isFinite(val) && val > 0 ? val : 1;
    };

    async handleExportPlan() {
        if (!this.dependencyTree || !this.selectedObject) {
            this.error = 'Please select an object and check dependencies first';
            return;
        }

        try {
            this.isLoading = true;
            const rootObject = this.dependencyTree.objectName;
            const { orderGraph, nodeSet } = this.collectOrderGraphFromSelection(this.dependencyTree);
            const rawOrder = this.computeExportOrder(orderGraph, rootObject, Array.from(nodeSet));
            const finalOrder = this.applyPreferenceOrder(rawOrder, this.parseTiebreakInput(this.tiebreakInput));

            const planPayload = {
                type: 'EXPORT_PLAN',
                root: rootObject,
                order: finalOrder,
                selectedNodesOnly: true,
                preferences: this.parseTiebreakInput(this.tiebreakInput)
            };
            console.log(JSON.stringify(planPayload, null, 2));

            const steps = finalOrder.map((obj, idx) => `${idx + 1}. ${obj}`);
            console.log(JSON.stringify({ type: 'EXPORT_ORDER_HUMAN', message: `Retrieve in order: ${steps.join(' -> ')}` }));
        } catch (e) {
            const msg = e && e.message ? e.message : 'Failed to build export plan';
            this.error = msg;
            console.error('Export plan error', msg);
        } finally {
            this.isLoading = false;
        }
    }

    // Build a retrieval order strictly from selected nodes only (no queries)
    handleOrderOnly = () => {
        if (!this.dependencyTree || !this.selectedObject) {
            this.error = 'Please select an object and check dependencies first';
            return;
        }

        try {
            const rootObject = this.dependencyTree.objectName;
            const { orderGraph, nodeSet } = this.collectOrderGraphFromSelection(this.dependencyTree);
            const rawOrder = this.computeExportOrder(orderGraph, rootObject, Array.from(nodeSet));
            const finalOrder = this.applyPreferenceOrder(rawOrder, this.parseTiebreakInput(this.tiebreakInput));

            const payload = {
                type: 'ORDER_ONLY',
                root: rootObject,
                order: finalOrder,
                selectedNodesOnly: true,
                preferences: this.parseTiebreakInput(this.tiebreakInput)
            };
            console.log(JSON.stringify(payload, null, 2));

            const steps = finalOrder.map((obj, idx) => `${idx + 1}. ${obj}`);
            console.log(JSON.stringify({ type: 'EXPORT_ORDER_HUMAN', message: `Retrieve in order: ${steps.join(' -> ')}` }));
        } catch (e) {
            const msg = e && e.message ? e.message : 'Failed to build order';
            this.error = msg;
            console.error('Order only error', msg);
        }
    };

    collectEdges(root) {
        // Returns both:
        // - edgesByObject: for querying parents (selected nodes only)
        // - orderGraph: parent edges only for ordering (children excluded for minimal migrations)
        const edgesByObject = new Map();
        const orderGraph = new Map();

        const addEdge = (map, fromObj, fieldName, toObj, fieldType) => {
            if (!map.has(fromObj)) map.set(fromObj, []);
            map.get(fromObj).push({ fieldName, target: toObj, fieldType });
        };

        const walkParents = (currentObjectName, nodes) => {
            if (!nodes || !nodes.length) return;
            for (const n of nodes) {
                if (!n.isSelected) continue;
                // For query and order (parents only)
                addEdge(edgesByObject, currentObjectName, n.fieldName, n.objectName, n.fieldType || 'Id');
                addEdge(orderGraph, currentObjectName, n.fieldName, n.objectName, n.fieldType || 'Id');
                // Recurse up unless using ExternalId (treat as terminal)
                if (n.fieldType !== 'ExternalId' && n.parents && n.parents.length) {
                    walkParents(n.objectName, n.parents);
                }
            }
        };

        walkParents(root.objectName, root.parents || []);

        return { edgesByObject, orderGraph };
    }

    // Construct only the ordering graph from selected nodes
    collectOrderGraphFromSelection(root) {
        const orderGraph = new Map(); // child -> [{ target: parent }]
        const nodeSet = new Set([root.objectName]);

        const addEdge = (fromObj, toObj) => {
            if (!orderGraph.has(fromObj)) orderGraph.set(fromObj, []);
            orderGraph.get(fromObj).push({ fieldName: '', target: toObj, fieldType: 'Id' });
            nodeSet.add(fromObj);
            nodeSet.add(toObj);
        };

        const walkParents = (currentObjectName, nodes) => {
            if (!nodes || !nodes.length) return;
            for (const n of nodes) {
                if (!n.isSelected) continue;
                addEdge(currentObjectName, n.objectName);
                if (n.parents && n.parents.length) {
                    walkParents(n.objectName, n.parents);
                }
            }
        };

        walkParents(root.objectName, root.parents || []);
        return { orderGraph, nodeSet };
    }

    

    handleTiebreakChange = (event) => {
        this.tiebreakInput = event.target.value || '';
    };

    parseTiebreakInput(input) {
        if (!input) return [];
        const groups = [];
        const lines = input.split(/\r?\n|;/).map(s => s.trim()).filter(Boolean);
        for (const line of lines) {
            const objs = line.split(',').map(s => s.trim()).filter(Boolean);
            if (objs.length) groups.push(objs);
        }
        return groups;
    }

    applyPreferenceOrder(order, groups) {
        if (!groups || !groups.length) return order;
        const seen = new Set();
        const result = [];
        const lower = (s) => (s || '').toLowerCase();
        for (const group of groups) {
            const set = new Set(group.map(lower));
            for (const obj of order) {
                if (!seen.has(obj) && set.has(lower(obj))) {
                    result.push(obj);
                    seen.add(obj);
                }
            }
        }
        for (const obj of order) {
            if (!seen.has(obj)) {
                result.push(obj);
                seen.add(obj);
            }
        }
        return result;
    }

    async runQueryWithSession(soql) {
        return queryWithSession({
            sessionId: this.sessionId,
            instanceUrl: this.instanceUrl,
            soql
        });
    }

    chunkArray(arr, size) {
        const out = [];
        for (let i = 0; i < arr.length; i += size) {
            out.push(arr.slice(i, i + size));
        }
        return out;
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
            this.dependencyTree = this.decorateDependencyTree(dependencies);
            
            console.log('Dependencies retrieved:', dependencies);
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : (e && e.message ? e.message : 'Failed to get dependencies');
            console.error('Error getting dependencies', this.error);
            this.dependencyTree = undefined;
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
        this.selectedNodes = new Set();
        this.nodeFieldTypes = new Map();
    }
}
