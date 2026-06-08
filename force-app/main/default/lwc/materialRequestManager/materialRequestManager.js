import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import currentUserId from '@salesforce/user/Id';
import getRequestsForProject from '@salesforce/apex/MaterialRequestController.getRequestsForProject';
import getWbsItemsForProject from '@salesforce/apex/MaterialRequestController.getWbsItemsForProject';
import getProducts           from '@salesforce/apex/MaterialRequestController.getProducts';
import createRequest from '@salesforce/apex/MaterialRequestController.createRequest';
import submitRequest from '@salesforce/apex/MaterialRequestController.submitRequest';
import approveRequest from '@salesforce/apex/MaterialRequestController.approveRequest';
import rejectRequest from '@salesforce/apex/MaterialRequestController.rejectRequest';
import deleteRequest from '@salesforce/apex/MaterialRequestController.deleteRequest';

function fmtDate(d) {
    if (!d) return '—';
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d));
    return m ? `${m[3]}-${m[2]}-${m[1]}` : String(d);
}

function fmtCurrency(v) {
    if (v == null) return '—';
    return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(v);
}

const STATUS_LABEL = { Draft: 'Draft', Submitted: 'Pending Approval', Approved: 'Approved', Rejected: 'Rejected' };
const STATUS_CLASS = {
    Draft:     'status-badge status-draft',
    Submitted: 'status-badge status-submitted',
    Approved:  'status-badge status-approved',
    Rejected:  'status-badge status-rejected'
};
const RFQ_STATUS_LABEL = { Draft: 'Draft', Sent: 'Sent', Quoted: 'Quoted', Awarded: 'Awarded', Closed: 'Closed' };
const RFQ_STATUS_CLASS = {
    Draft:   'status-badge status-draft',
    Sent:    'status-badge status-submitted',
    Quoted:  'status-badge status-info',
    Awarded: 'status-badge status-approved',
    Closed:  'status-badge status-closed'
};

function enrichRequest(r) {
    return {
        ...r,
        statusLabel:      STATUS_LABEL[r.status] ?? r.status,
        statusClass:      STATUS_CLASS[r.status]  ?? 'status-badge',
        quantityLabel:    r.quantity != null ? `${r.quantity} ${r.unit ?? ''}` : '—',
        requiredDateLabel: fmtDate(r.requiredDate),
        isDraft:          r.status === 'Draft',
        isSubmitted:      r.status === 'Submitted',
        isApproved:       r.status === 'Approved',
        isRejected:       r.status === 'Rejected'
    };
}

function enrichRfq(q) {
    return {
        ...q,
        statusLabel:          RFQ_STATUS_LABEL[q.status] ?? q.status,
        statusClass:          RFQ_STATUS_CLASS[q.status]  ?? 'status-badge',
        expectedDeliveryLabel: fmtDate(q.expectedDelivery),
        estimatedValueLabel:   fmtCurrency(q.estimatedValue),
        vendor:               q.vendor ?? '—'
    };
}

export default class MaterialRequestManager extends NavigationMixin(LightningElement) {
    @api recordId;

    userId = currentUserId;

    @track activeFilter = 'all';
    @track showNewModal  = false;
    @track showRejectModal = false;
    @track rejectTargetId;
    @track rejectionReason = '';
    @track isSaving    = false;
    @track isRejecting = false;

    @track newWbsItemId    = '';
    @track newProductId    = '';
    @track newQuantity     = '';
    @track newUnit         = 'nos';
    @track newRequiredDate = '';
    @track newNotes        = '';
    @track wbsOptions      = [];
    @track productOptions  = [];

    _wiredResult;
    isLoading  = true;
    hasError   = false;
    errorMessage = '';

    @wire(getRequestsForProject, { projectId: '$recordId' })
    wiredData(result) {
        this._wiredResult = result;
        this.isLoading    = false;
        if (result.data) {
            this.hasError = false;
        } else if (result.error) {
            this.hasError     = true;
            this.errorMessage = result.error.body?.message ?? 'Failed to load requests.';
        }
    }

    get _requests() {
        return (this._wiredResult?.data?.requests ?? []).map(enrichRequest);
    }

    get filteredRequests() {
        if (this.activeFilter === 'pending') return this._requests.filter(r => r.isSubmitted);
        if (this.activeFilter === 'mine')    return this._requests.filter(r => r.requestedById === this.userId);
        return this._requests;
    }

    get rfqRows() {
        return (this._wiredResult?.data?.rfqs ?? []).map(enrichRfq);
    }

    get hasRfqs()    { return this.rfqRows.length > 0; }
    get isEmpty()    { return !this.isLoading && !this.hasError && this.filteredRequests.length === 0; }
    get allCount()   { return this._requests.length; }
    get pendingCount(){ return this._requests.filter(r => r.isSubmitted).length; }
    get myCount()    { return this._requests.filter(r => r.requestedById === this.userId).length; }

    get allTabClass()     { return `filter-tab${this.activeFilter === 'all'     ? ' active' : ''}`; }
    get pendingTabClass() { return `filter-tab${this.activeFilter === 'pending' ? ' active' : ''}`; }
    get myTabClass()      { return `filter-tab${this.activeFilter === 'mine'    ? ' active' : ''}`; }

    get unitOptions() {
        return [
            { label: 'nos',          value: 'nos' },
            { label: 'kg',           value: 'kg' },
            { label: 'ton',          value: 'ton' },
            { label: 'm (Meter)',    value: 'm' },
            { label: 'm² (Sq. m)',   value: 'm2' },
            { label: 'm³ (Cu. m)',   value: 'm3' },
            { label: 'bag',          value: 'bag' },
            { label: 'set',          value: 'set' },
            { label: 'roll',         value: 'roll' },
            { label: 'lump sum',     value: 'lump sum' }
        ];
    }

    filterAll()     { this.activeFilter = 'all'; }
    filterPending() { this.activeFilter = 'pending'; }
    filterMine()    { this.activeFilter = 'mine'; }

    async openNewRequestModal() {
        this.showNewModal = true;
        try {
            const [wbs, products] = await Promise.all([
                getWbsItemsForProject({ projectId: this.recordId }),
                getProducts()
            ]);
            this.wbsOptions     = wbs      ?? [];
            this.productOptions = products ?? [];
        } catch (e) {
            this._toast('Error', 'Could not load options: ' + (e.body?.message ?? e.message), 'error');
        }
    }

    closeNewModal() {
        this.showNewModal = false;
        this._resetForm();
    }

    _resetForm() {
        this.newWbsItemId    = '';
        this.newProductId    = '';
        this.newQuantity     = '';
        this.newUnit         = 'nos';
        this.newRequiredDate = '';
        this.newNotes        = '';
    }

    handleWbsChange(e)     { this.newWbsItemId = e.detail.value; }
    handleProductChange(e) { this.newProductId = e.detail.value; }
    handleQuantityChange(e) { this.newQuantity     = e.target.value; }
    handleUnitChange(e)     { this.newUnit         = e.detail.value; }
    handleDateChange(e)     { this.newRequiredDate = e.target.value; }
    handleNotesChange(e)    { this.newNotes        = e.target.value; }

    async saveNewRequest() {
        if (!this.newWbsItemId || !this.newProductId || !this.newQuantity) {
            this._toast('Validation', 'WBS Item, Product and Quantity are required.', 'error');
            return;
        }
        this.isSaving = true;
        try {
            await createRequest({
                wbsItemId:    this.newWbsItemId,
                productId:    this.newProductId,
                quantity:     parseFloat(this.newQuantity),
                unit:         this.newUnit,
                requiredDate: this.newRequiredDate || null,
                notes:        this.newNotes.trim() || null
            });
            this._toast('Success', 'Request created as Draft.', 'success');
            this.showNewModal = false;
            this._resetForm();
            await refreshApex(this._wiredResult);
        } catch (e) {
            this._toast('Error', e.body?.message ?? 'Could not create request.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSubmit(e) {
        const id = e.currentTarget.dataset.id;
        try {
            await submitRequest({ requestId: id });
            this._toast('Submitted', 'Request submitted for manager approval.', 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this._toast('Error', e.body?.message ?? 'Could not submit.', 'error');
        }
    }

    async handleApprove(e) {
        const id = e.currentTarget.dataset.id;
        try {
            await approveRequest({ requestId: id });
            this._toast('Approved', 'Request approved and RFQ created.', 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this._toast('Error', e.body?.message ?? 'Could not approve.', 'error');
        }
    }

    openRejectModal(e) {
        this.rejectTargetId  = e.currentTarget.dataset.id;
        this.rejectionReason = '';
        this.showRejectModal = true;
    }

    closeRejectModal() {
        this.showRejectModal = false;
        this.rejectTargetId  = null;
    }

    handleReasonChange(e) { this.rejectionReason = e.target.value; }

    async confirmReject() {
        if (!this.rejectionReason.trim()) {
            this._toast('Validation', 'Please enter a rejection reason.', 'error');
            return;
        }
        this.isRejecting = true;
        try {
            await rejectRequest({ requestId: this.rejectTargetId, reason: this.rejectionReason.trim() });
            this._toast('Rejected', 'Request has been rejected.', 'warning');
            this.showRejectModal = false;
            await refreshApex(this._wiredResult);
        } catch (e) {
            this._toast('Error', e.body?.message ?? 'Could not reject.', 'error');
        } finally {
            this.isRejecting = false;
        }
    }

    async handleDelete(e) {
        const id = e.currentTarget.dataset.id;
        try {
            await deleteRequest({ requestId: id });
            this._toast('Deleted', 'Draft request deleted.', 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this._toast('Error', e.body?.message ?? 'Could not delete.', 'error');
        }
    }

    navigateToRfq(e) {
        const rfqId = e.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: rfqId, actionName: 'view' }
        });
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
