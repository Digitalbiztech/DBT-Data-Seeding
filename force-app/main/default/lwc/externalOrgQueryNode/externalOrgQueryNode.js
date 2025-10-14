import { LightningElement, api } from 'lwc';

export default class ExternalOrgQueryNode extends LightningElement {
    @api node;
    @api fieldTypeOptions = [];

    onRadioClick = (event) => {
        // Allow "radio" to toggle off when already selected
        if (this.node && this.node.isSelected) {
            event.preventDefault();
            event.stopPropagation();
            event.target.checked = false;
            this.dispatchEvent(
                new CustomEvent('nodetoggle', {
                    detail: { nodeId: this.node.nodeId, isSelected: false },
                    bubbles: true,
                    composed: true
                })
            );
        }
    };

    onRadioChange = (event) => {
        // Normal case: selecting the node (checked=true)
        const checked = event.target.checked;
        this.dispatchEvent(
            new CustomEvent('nodetoggle', {
                detail: { nodeId: this.node.nodeId, isSelected: checked },
                bubbles: true,
                composed: true
            })
        );
    };

    onFieldTypeChange = (event) => {
        const fieldType = event.detail.value;
        this.dispatchEvent(
            new CustomEvent('fieldtypechange', {
                detail: { nodeId: this.node.nodeId, fieldType },
                bubbles: true,
                composed: true
            })
        );
    };

    // Just re-dispatch bubbling events from descendants
    bubbleToggle = (event) => {
        this.dispatchEvent(
            new CustomEvent('nodetoggle', {
                detail: event.detail,
                bubbles: true,
                composed: true
            })
        );
    };

    bubbleFieldType = (event) => {
        this.dispatchEvent(
            new CustomEvent('fieldtypechange', {
                detail: event.detail,
                bubbles: true,
                composed: true
            })
        );
    };
}

