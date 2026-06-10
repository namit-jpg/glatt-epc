import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getLineItems from '@salesforce/apex/RFQLineItemController.getLineItems';
import deleteLineItem from '@salesforce/apex/RFQLineItemController.deleteLineItem';

const COLUMNS = [
    { label: 'Line #', fieldName: 'name', type: 'text', initialWidth: 110 },
    { label: 'Material', fieldName: 'materialName', type: 'text', wrapText: true },
    { label: 'Product', fieldName: 'productName', type: 'text', wrapText: true },
    {
        label: 'Qty', fieldName: 'quantity', type: 'number', initialWidth: 90,
        typeAttributes: { maximumFractionDigits: 2 },
        cellAttributes: { alignment: 'right' }
    },
    { label: 'Unit', fieldName: 'unit', type: 'text', initialWidth: 80 },
    {
        label: 'Unit Price', fieldName: 'unitPrice', type: 'currency', initialWidth: 130,
        typeAttributes: { currencyCode: 'INR', minimumFractionDigits: 0, maximumFractionDigits: 2 },
        cellAttributes: { alignment: 'right' }
    },
    {
        label: 'Total Price', fieldName: 'totalPrice', type: 'currency', initialWidth: 140,
        typeAttributes: { currencyCode: 'INR', minimumFractionDigits: 0, maximumFractionDigits: 2 },
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

export default class RfqLineItems extends LightningElement {
    @api recordId;

    @track rows = [];
    @track showModal = false;
    @track editRecordId;
    @track modalTitle = 'New Line Item';

    columns = COLUMNS;
    totalValue = 0;

    _wiredResult;
    isLoading = true;
    hasError = false;
    errorMessage;

    @wire(getLineItems, { rfqId: '$recordId' })
    wiredItems(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.rows = result.data.rows;
            this.totalValue = result.data.totalValue;
            this.hasError = false;
        } else if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error.body?.message ?? 'Failed to load line items.';
        }
    }

    get hasData()  { return !this.isLoading && !this.hasError && this.rows.length > 0; }
    get isEmpty()  { return !this.isLoading && !this.hasError && this.rows.length === 0; }
    get itemCount(){ return this.rows.length; }
    get cardTitle(){ return `RFQ Line Items (${this.rows.length})`; }

    handleNew() {
        this.editRecordId = undefined;
        this.modalTitle = 'New Line Item';
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
            await deleteLineItem({ lineItemId: id });
            this.toast('Deleted', `"${label}" removed`, 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this.toast('Error', e.body?.message ?? 'Delete failed', 'error');
        }
    }

    handleSubmit(event) {
        event.preventDefault();
        const fields = { ...event.detail.fields };
        fields.RFQ__c = this.recordId; // link new line item to this RFQ
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSaveSuccess() {
        this.showModal = false;
        this.toast('Saved', 'Line item saved successfully', 'success');
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
