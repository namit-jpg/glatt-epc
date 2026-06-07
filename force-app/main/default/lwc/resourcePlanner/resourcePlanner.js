import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getResourcePlan from '@salesforce/apex/ResourceAllocationController.getResourcePlan';
import deleteAllocation from '@salesforce/apex/ResourceAllocationController.deleteAllocation';

const COLUMNS = [
    { label: 'Resource', fieldName: 'resourceName', type: 'text' },
    { label: 'Role', fieldName: 'role', type: 'text' },
    {
        label: 'Allocation', fieldName: 'allocationFraction', type: 'percent', initialWidth: 110,
        typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 },
        cellAttributes: { alignment: 'right' }
    },
    { label: 'WBS Item', fieldName: 'wbsItemName', type: 'text', wrapText: true },
    {
        label: 'Start', fieldName: 'startDate', type: 'date', initialWidth: 125,
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
    },
    {
        label: 'End', fieldName: 'endDate', type: 'date', initialWidth: 125,
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit',   name: 'edit',   iconName: 'utility:edit' },
                { label: 'Delete', name: 'delete', iconName: 'utility:delete' }
            ]
        }
    }
];

export default class ResourcePlanner extends LightningElement {
    @api recordId;

    @track allocations = [];
    @track resources = [];
    @track showModal = false;
    @track editRecordId;
    @track modalTitle = 'New Allocation';

    columns = COLUMNS;
    _wiredResult;
    isLoading = true;
    hasError = false;
    errorMessage;

    @wire(getResourcePlan, { projectId: '$recordId' })
    wiredPlan(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.allocations = result.data.allocations.map(a => ({
                ...a,
                allocationFraction: a.allocationPercent != null ? a.allocationPercent / 100 : null
            }));
            this.resources = result.data.resources.map(r => ({
                ...r,
                loadLabel: `${r.currentLoad}% across all projects`,
                projectAllocationLabel: `${r.projectAllocation}% on this project`,
                cardClass: r.isOverAllocated
                    ? 'slds-box slds-box_x-small resource-card resource-card_over'
                    : 'slds-box slds-box_x-small resource-card',
                fillClass: r.isOverAllocated ? 'load-fill load-fill_over' : 'load-fill',
                fillStyle: `width: ${Math.min(r.currentLoad, 100)}%`
            }));
            this.hasError = false;
        } else if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error.body?.message ?? 'Failed to load resource plan.';
        }
    }

    get hasData()      { return !this.isLoading && !this.hasError && this.allocations.length > 0; }
    get isEmpty()      { return !this.isLoading && !this.hasError && this.allocations.length === 0; }
    get hasResources() { return this.resources.length > 0; }

    handleNew() {
        this.editRecordId = undefined;
        this.modalTitle = 'New Allocation';
        this.showModal = true;
    }

    handleRowAction(event) {
        const { name } = event.detail.action;
        const row = event.detail.row;

        if (name === 'edit') {
            this.editRecordId = row.id;
            this.modalTitle = `Edit: ${row.resourceName ?? row.name}`;
            this.showModal = true;
        } else if (name === 'delete') {
            this.handleDelete(row.id, row.resourceName ?? row.name);
        }
    }

    async handleDelete(id, label) {
        try {
            await deleteAllocation({ allocationId: id });
            this.toast('Deleted', `Allocation for "${label}" removed`, 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this.toast('Error', e.body?.message ?? 'Delete failed', 'error');
        }
    }

    handleSubmit(event) {
        event.preventDefault();
        const fields = { ...event.detail.fields };
        if (!this.editRecordId) {
            fields.Project__c = this.recordId;
        }
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSaveSuccess() {
        this.showModal = false;
        this.toast('Saved', 'Allocation saved successfully', 'success');
        refreshApex(this._wiredResult);
    }

    handleSaveError(event) {
        this.toast('Save Error', event.detail?.message ?? 'Save failed', 'error');
    }

    closeModal() {
        this.showModal = false;
        this.editRecordId = undefined;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
