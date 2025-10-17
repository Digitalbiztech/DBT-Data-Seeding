import { LightningElement, api } from 'lwc';

export default class ExternalOrgQueryNode extends LightningElement {
    @api node;

    get hasChildren() {
        return this.node && Array.isArray(this.node.children) && this.node.children.length > 0;
    }

    get isEdge() {
        return this.node && this.node.type === 'edge';
    }

    get isObject() {
        return this.node && this.node.type === 'object';
    }

    get isDraggable() {
        return this.node && !!this.node.draggable;
    }

    get containerClass() {
        const classes = ['plan-node'];
        if (this.hasChildren) {
            classes.push('plan-node--parent');
        } else {
            classes.push('plan-node--leaf');
        }
        if (this.isDraggable) {
            classes.push('plan-node--draggable');
        }
        return classes.join(' ');
    }

    get toggleIcon() {
        if (!this.hasChildren) {
            return 'utility:dash';
        }
        return this.node.isCollapsed ? 'utility:chevronright' : 'utility:chevrondown';
    }

    handleToggle = (event) => {
        event.stopPropagation();
        if (!this.hasChildren) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('plannodetoggle', {
                detail: { nodeId: this.node.id },
                bubbles: true,
                composed: true
            })
        );
    };

    handleEdgeCheckboxChange = (event) => {
        const checked = !!event.target.checked;
        this.dispatchEvent(
            new CustomEvent('planedgetoggle', {
                detail: { nodeId: this.node.id, isSelected: checked },
                bubbles: true,
                composed: true
            })
        );
    };

    get objectChecked() {
        // object checkbox reflects whether all descendant edges are selected
        const allEdgesSelected = (node) => {
            if (!node || !Array.isArray(node.children) || !node.children.length) {
                return true;
            }
            for (const child of node.children) {
                if (child.type === 'edge') {
                    if (!child.isSelected) return false;
                    if (child.children && child.children[0]) {
                        if (!allEdgesSelected(child.children[0])) return false;
                    }
                } else {
                    if (!allEdgesSelected(child)) return false;
                }
            }
            return true;
        };
        return allEdgesSelected(this.node);
    }

    handleObjectCheckboxChange = (event) => {
        const checked = !!event.target.checked;
        this.dispatchEvent(
            new CustomEvent('planobjecttoggle', {
                detail: { nodeId: this.node.id, isSelected: checked },
                bubbles: true,
                composed: true
            })
        );
    };

    handleDragStart = (event) => {
        if (!this.isDraggable) {
            event.preventDefault();
            return;
        }
        event.stopPropagation();
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', this.node.id);
    };

    handleDragOver = (event) => {
        if (!this.isDraggable) {
            return;
        }
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
    };

    handleDrop = (event) => {
        if (!this.isDraggable) {
            return;
        }
        event.preventDefault();
        const sourceId = event.dataTransfer.getData('text/plain');
        if (!sourceId || sourceId === this.node.id) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('plannodedrop', {
                detail: { sourceId, targetId: this.node.id },
                bubbles: true,
                composed: true
            })
        );
    };
}
