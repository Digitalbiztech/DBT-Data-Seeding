import { LightningElement, track } from 'lwc';
import loginAndQuery from '@salesforce/apex/ExternalOrgQueryController.loginAndQuery';
import testConnection from '@salesforce/apex/ExternalOrgQueryController.testConnection';
import getAvailableObjects from '@salesforce/apex/ExternalOrgQueryController.getAvailableObjects';
import getObjectDependencies from '@salesforce/apex/ExternalOrgQueryController.getObjectDependencies';

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
    get isNodeSelected() {
        return (nodeId) => this.selectedNodes.has(nodeId);
    }

    get getNodeFieldType() {
        return (nodeId) => this.nodeFieldTypes.get(nodeId) || 'Id';
    }

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
        const nodeId = event.target.dataset.nodeId;
        const isSelected = event.target.checked;
        
        if (isSelected) {
            this.selectedNodes.add(nodeId);
        } else {
            this.selectedNodes.delete(nodeId);
        }
        
        // Handle cascading behavior
        this.handleCascadingSelection(nodeId, isSelected);
        
        // Force reactivity update
        this.selectedNodes = new Set(this.selectedNodes);
    };
    
    handleCascadingSelection = (nodeId, isSelected) => {
        // Find the node in the dependency tree
        const node = this.findNodeInTree(this.dependencyTree, nodeId);
        if (!node) return;
        
        if (isSelected) {
            // When checking a parent, check all its children
            this.checkAllChildren(node, nodeId.split('_')[2]); // depth from nodeId
        } else {
            // When unchecking a parent, uncheck all its children
            this.uncheckAllChildren(node, nodeId.split('_')[2]); // depth from nodeId
        }
    };
    
    findNodeInTree = (root, targetNodeId) => {
        if (!root || !root.parents) return null;
        
        for (let parent of root.parents) {
            const parentNodeId = this.generateNodeId(parent.objectName, parent.fieldName, 1);
            if (parentNodeId === targetNodeId) {
                return parent;
            }
            
            // Check children
            if (parent.parents && parent.parents.length > 0) {
                for (let child of parent.parents) {
                    const childNodeId = this.generateNodeId(child.objectName, child.fieldName, 2);
                    if (childNodeId === targetNodeId) {
                        return child;
                    }
                    
                    // Check grandchildren
                    if (child.parents && child.parents.length > 0) {
                        for (let grandchild of child.parents) {
                            const grandchildNodeId = this.generateNodeId(grandchild.objectName, grandchild.fieldName, 3);
                            if (grandchildNodeId === targetNodeId) {
                                return grandchild;
                            }
                        }
                    }
                }
            }
        }
        return null;
    };
    
    checkAllChildren = (node, currentDepth) => {
        if (!node.parents || node.parents.length === 0) return;
        
        const nextDepth = parseInt(currentDepth) + 1;
        node.parents.forEach(child => {
            const childNodeId = this.generateNodeId(child.objectName, child.fieldName, nextDepth);
            this.selectedNodes.add(childNodeId);
            this.checkAllChildren(child, nextDepth);
        });
    };
    
    uncheckAllChildren = (node, currentDepth) => {
        if (!node.parents || node.parents.length === 0) return;
        
        const nextDepth = parseInt(currentDepth) + 1;
        node.parents.forEach(child => {
            const childNodeId = this.generateNodeId(child.objectName, child.fieldName, nextDepth);
            this.selectedNodes.delete(childNodeId);
            this.uncheckAllChildren(child, nextDepth);
        });
    };
    
    handleFieldTypeChange = (event) => {
        const nodeId = event.target.dataset.nodeId;
        const fieldType = event.detail.value;
        this.nodeFieldTypes.set(nodeId, fieldType);
        
        // Force reactivity update
        this.nodeFieldTypes = new Map(this.nodeFieldTypes);
    };
    
    isNodeSelected = (nodeId) => {
        return this.selectedNodes.has(nodeId);
    };
    
    getNodeFieldType = (nodeId) => {
        return this.nodeFieldTypes.get(nodeId) || 'Id';
    };
    
    generateNodeId = (objectName, fieldName, depth) => {
        return `${objectName}_${fieldName}_${depth}`;
    };
    
    initializeNodeStates = (node, depth = 0) => {
        if (!node) return;
        
        // Initialize current node
        const nodeId = this.generateNodeId(node.objectName, node.fieldName, depth);
        this.selectedNodes.add(nodeId);
        this.nodeFieldTypes.set(nodeId, 'Id');
        
        // Initialize child nodes
        if (node.parents && node.parents.length > 0) {
            node.parents.forEach(parent => {
                this.initializeNodeStates(parent, depth + 1);
            });
        }
        
        // Force reactivity update
        this.selectedNodes = new Set(this.selectedNodes);
        this.nodeFieldTypes = new Map(this.nodeFieldTypes);
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
            
            // Initialize node selections and field types
            this.initializeNodeStates(dependencies);
            
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