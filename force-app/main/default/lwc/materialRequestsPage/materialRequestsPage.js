import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import currentUserId from '@salesforce/user/Id';
import getAllRequests       from '@salesforce/apex/MaterialRequestController.getAllRequests';
import getProjects         from '@salesforce/apex/MaterialRequestController.getProjects';
import getWbsItemsForProject from '@salesforce/apex/MaterialRequestController.getWbsItemsForProject';
import getProducts           from '@salesforce/apex/MaterialRequestController.getProducts';
import createRequest       from '@salesforce/apex/MaterialRequestController.createRequest';
import submitRequest       from '@salesforce/apex/MaterialRequestController.submitRequest';
import approveRequest      from '@salesforce/apex/MaterialRequestController.approveRequest';
import rejectRequest       from '@salesforce/apex/MaterialRequestController.rejectRequest';
import deleteRequest       from '@salesforce/apex/MaterialRequestController.deleteRequest';

function fmtDate(d) {
    if (!d) return '—';
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d));
    return m ? `${m[3]}-${m[2]}-${m[1]}` : String(d);
}

const STATUS_LABEL = {
    Draft:     'Draft',
    Submitted: 'Pending Approval',
    Approved:  'Approved',
    Rejected:  'Rejected'
};
const STATUS_CLASS = {
    Draft:     'status-pill pill-draft',
    Submitted: 'status-pill pill-pending',
    Approved:  'status-pill pill-approved',
    Rejected:  'status-pill pill-rejected'
};

function enrich(r) {
    return {
        ...r,
        statusLabel:       STATUS_LABEL[r.status] ?? r.status,
        statusClass:       STATUS_CLASS[r.status]  ?? 'status-pill',
        quantityLabel:     r.quantity != null ? `${r.quantity} ${r.unit ?? ''}`.trim() : '—',
        requiredDateLabel: fmtDate(r.requiredDate),
        isDraft:           r.status === 'Draft',
        isSubmitted:       r.status === 'Submitted',
        isApproved:        r.status === 'Approved',
        isRejected:        r.status === 'Rejected'
    };
}

export default class MaterialRequestsPage extends NavigationMixin(LightningElement) {
    userId = currentUserId;

    @track activeFilter  = 'all';
    @track showNewModal  = false;
    @track showRejectModal = false;
    @track rejectTargetId;
    @track rejectionReason = '';
    @track isSaving    = false;
    @track isRejecting = false;

    // New request form
    @track newProjectId    = '';
    @track newWbsItemId    = '';
    @track newProductId    = '';
    @track newQuantity     = '';
    @track newUnit         = 'nos';
    @track newRequiredDate = '';
    @track newNotes        = '';

    @track projectOptions = [];
    @track wbsOptions     = [];
    @track productOptions = [];
    @track wbsDisabled    = true;

    _wiredResult;
    isLoading    = true;
    hasError     = false;
    errorMessage = '';

    @wire(getAllRequests)
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
        return (this._wiredResult?.data?.requests ?? []).map(enrich);
    }

    get filteredRequests() {
        if (this.activeFilter === 'mine')    return this._requests.filter(r => r.requestedById === this.userId);
        if (this.activeFilter === 'pending') return this._requests.filter(r => r.isSubmitted);
        return this._requests;
    }

    get allCount()     { return this._requests.length; }
    get myCount()      { return this._requests.filter(r => r.requestedById === this.userId).length; }
    get pendingCount() { return this._requests.filter(r => r.isSubmitted).length; }
    get isEmpty()      { return !this.isLoading && !this.hasError && this.filteredRequests.length === 0; }

    get allPillClass()     { return `filter-pill${this.activeFilter === 'all'     ? ' active' : ''}`; }
    get myPillClass()      { return `filter-pill${this.activeFilter === 'mine'    ? ' active' : ''}`; }
    get pendingPillClass() { return `filter-pill${this.activeFilter === 'pending' ? ' active' : ''}`; }

    get wbsPlaceholder() { return this.newProjectId ? 'Select WBS item' : 'Select a project first'; }

    get unitOptions() {
        return [
            { label: 'nos',        value: 'nos' },
            { label: 'kg',         value: 'kg' },
            { label: 'ton',        value: 'ton' },
            { label: 'm (Meter)',  value: 'm' },
            { label: 'm² (Sq. m)', value: 'm2' },
            { label: 'm³ (Cu. m)', value: 'm3' },
            { label: 'bag',        value: 'bag' },
            { label: 'set',        value: 'set' },
            { label: 'roll',       value: 'roll' },
            { label: 'lump sum',   value: 'lump sum' }
        ];
    }

    filterAll()     { this.activeFilter = 'all'; }
    filterMine()    { this.activeFilter = 'mine'; }
    filterPending() { this.activeFilter = 'pending'; }

    async openNewModal() {
        this.showNewModal = true;
        try {
            const [projects, products] = await Promise.all([getProjects(), getProducts()]);
            this.projectOptions = projects ?? [];
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
        this.newProjectId    = '';
        this.newWbsItemId    = '';
        this.newProductId    = '';
        this.newQuantity     = '';
        this.newUnit         = 'nos';
        this.newRequiredDate = '';
        this.newNotes        = '';
        this.wbsOptions      = [];
        this.wbsDisabled     = true;
    }

    async handleProjectChange(e) {
        this.newProjectId  = e.detail.value;
        this.newWbsItemId  = '';
        this.wbsOptions    = [];
        this.wbsDisabled   = true;
        if (!this.newProjectId) return;
        try {
            const opts = await getWbsItemsForProject({ projectId: this.newProjectId });
            this.wbsOptions  = opts ?? [];
            this.wbsDisabled = false;
        } catch (e) {
            this._toast('Error', 'Could not load WBS items.', 'error');
        }
    }

    handleWbsChange(e)      { this.newWbsItemId    = e.detail.value; }
    handleProductChange(e)  { this.newProductId    = e.detail.value; }
    handleQuantityChange(e) { this.newQuantity     = e.target.value; }
    handleUnitChange(e)     { this.newUnit         = e.detail.value; }
    handleDateChange(e)     { this.newRequiredDate = e.target.value; }
    handleNotesChange(e)    { this.newNotes        = e.target.value; }

    async saveNewRequest() {
        await this._doCreate(false);
    }

    async saveAndSubmit() {
        await this._doCreate(true);
    }

    async _doCreate(andSubmit) {
        if (!this.newProjectId || !this.newWbsItemId || !this.newProductId || !this.newQuantity) {
            this._toast('Validation', 'Project, WBS Item, Product and Quantity are required.', 'error');
            return;
        }
        this.isSaving = true;
        try {
            const reqId = await createRequest({
                wbsItemId:    this.newWbsItemId,
                productId:    this.newProductId,
                quantity:     parseFloat(this.newQuantity),
                unit:         this.newUnit,
                requiredDate: this.newRequiredDate || null,
                notes:        this.newNotes.trim() || null
            });
            if (andSubmit) {
                await submitRequest({ requestId: reqId });
                this._toast('Submitted', 'Request submitted for manager approval.', 'success');
            } else {
                this._toast('Saved', 'Request saved as Draft.', 'success');
            }
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
            this._toast('Submitted', 'Request submitted for approval.', 'success');
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
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: e.currentTarget.dataset.id, actionName: 'view' }
        });
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
