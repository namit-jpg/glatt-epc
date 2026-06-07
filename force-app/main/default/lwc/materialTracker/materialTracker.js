import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getMaterialBoard from '@salesforce/apex/MaterialLogController.getMaterialBoard';
import deleteMaterial from '@salesforce/apex/MaterialLogController.deleteMaterial';

const COLUMNS = [
    { label: 'WBS Item', fieldName: 'wbsItemName', type: 'text', wrapText: true },
    { label: 'Material', fieldName: 'materialName', type: 'text', wrapText: true },
    { label: 'Cost Type', fieldName: 'costType', type: 'text', initialWidth: 110 },
    {
        label: 'Qty', fieldName: 'quantity', type: 'number', initialWidth: 90,
        typeAttributes: { maximumFractionDigits: 2 },
        cellAttributes: { alignment: 'right' }
    },
    { label: 'Unit', fieldName: 'unit', type: 'text', initialWidth: 80 },
    {
        label: 'Rate', fieldName: 'rate', type: 'currency', initialWidth: 120,
        typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 2, currencyCode: 'INR' },
        cellAttributes: { alignment: 'right' }
    },
    {
        label: 'Total Cost', fieldName: 'totalCost', type: 'currency', initialWidth: 130,
        typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0, currencyCode: 'INR' },
        cellAttributes: { alignment: 'right' }
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

export default class MaterialTracker extends LightningElement {
    @api recordId;

    @track rows = [];
    @track wbsSummaries = [];
    @track showModal = false;
    @track editRecordId;
    @track modalTitle = 'New Material Entry';

    columns = COLUMNS;
    workTotal = 0;
    materialTotal = 0;
    costTotal = 0;
    grandTotal = 0;

    _wiredResult;
    isLoading = true;
    hasError = false;
    errorMessage;

    @wire(getMaterialBoard, { projectId: '$recordId' })
    wiredBoard(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.rows = result.data.rows;
            this.workTotal = result.data.workTotal;
            this.materialTotal = result.data.materialTotal;
            this.costTotal = result.data.costTotal;
            this.grandTotal = result.data.grandTotal;
            this.wbsSummaries = result.data.wbsSummaries.map(s => ({
                ...s,
                entryLabel: `${s.entryCount} ${s.entryCount === 1 ? 'entry' : 'entries'}`,
                percentLabel: s.percentOfBudget != null ? `${s.percentOfBudget}% of budget` : 'No budget set',
                cardClass: s.isOverBudget
                    ? 'slds-box slds-box_x-small wbs-card wbs-card_over'
                    : 'slds-box slds-box_x-small wbs-card',
                fillClass: s.isOverBudget ? 'budget-fill budget-fill_over' : 'budget-fill',
                fillStyle: `width: ${s.percentOfBudget != null ? Math.min(s.percentOfBudget, 100) : 0}%`
            }));
            this.hasError = false;
        } else if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error.body?.message ?? 'Failed to load material data.';
        }
    }

    get hasData()         { return !this.isLoading && !this.hasError && this.rows.length > 0; }
    get isEmpty()         { return !this.isLoading && !this.hasError && this.rows.length === 0; }
    get hasWbsSummaries() { return this.wbsSummaries.length > 0; }

    handleNew() {
        this.editRecordId = undefined;
        this.modalTitle = 'New Material Entry';
        this.showModal = true;
    }

    handleRowAction(event) {
        const { name } = event.detail.action;
        const row = event.detail.row;

        if (name === 'edit') {
            this.editRecordId = row.id;
            this.modalTitle = `Edit: ${row.materialName ?? row.name}`;
            this.showModal = true;
        } else if (name === 'delete') {
            this.handleDelete(row.id, row.materialName ?? row.name);
        }
    }

    async handleDelete(id, label) {
        try {
            await deleteMaterial({ materialId: id });
            this.toast('Deleted', `"${label}" removed`, 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this.toast('Error', e.body?.message ?? 'Delete failed', 'error');
        }
    }

    handleSubmit(event) {
        event.preventDefault();
        this.template.querySelector('lightning-record-edit-form').submit({ ...event.detail.fields });
    }

    handleSaveSuccess() {
        this.showModal = false;
        this.toast('Saved', 'Material entry saved successfully', 'success');
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
