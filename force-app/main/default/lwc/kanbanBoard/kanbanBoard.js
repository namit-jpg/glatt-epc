import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getWorkPackages from '@salesforce/apex/KanbanController.getWorkPackages';
import updateStatus from '@salesforce/apex/KanbanController.updateStatus';

const STATUSES = [
    { status: 'Planned',     label: 'Planned' },
    { status: 'In Progress', label: 'In Progress' },
    { status: 'Blocked',     label: 'Blocked' },
    { status: 'Complete',    label: 'Complete' }
];

function fmtDate(iso) {
    if (!iso) return '';
    const [y, m, d] = iso.split('-');
    return `${m}/${d}/${y}`;
}

export default class KanbanBoard extends LightningElement {
    @api recordId;

    @track _cards = [];
    _wiredResult;
    _dragCardId;

    isLoading = true;
    hasError = false;
    errorMessage;

    showModal = false;

    @wire(getWorkPackages, { projectId: '$recordId' })
    wiredCards(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this._cards = result.data.map(c => ({
                ...c,
                wbsLabel: (c.wbsCode ? c.wbsCode + ' – ' : '') + (c.wbsName ?? ''),
                displayStart: fmtDate(c.plannedStart),
                displayEnd:   fmtDate(c.plannedEnd),
                hasDate: !!(c.plannedStart || c.plannedEnd)
            }));
            this.hasError = false;
        } else if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error.body?.message ?? 'Failed to load work packages.';
        }
    }

    get columns() {
        return STATUSES.map(s => ({
            ...s,
            cards:   this._cards.filter(c => c.status === s.status),
            count:   this._cards.filter(c => c.status === s.status).length,
            isEmpty: this._cards.filter(c => c.status === s.status).length === 0
        }));
    }

    get hasData()  { return !this.isLoading && !this.hasError; }
    get totalCount() { return this._cards.length; }

    // ---- drag-drop ----

    handleDragStart(event) {
        this._dragCardId = event.currentTarget.dataset.id;
        event.currentTarget.classList.add('dragging');
    }

    handleDragEnd(event) {
        event.currentTarget.classList.remove('dragging');
    }

    handleDragOver(event) {
        event.preventDefault();
        event.currentTarget.classList.add('drag-over');
    }

    handleDragLeave(event) {
        event.currentTarget.classList.remove('drag-over');
    }

    async handleDrop(event) {
        event.preventDefault();
        const col = event.currentTarget;
        col.classList.remove('drag-over');

        const targetStatus = col.dataset.status;
        const cardId = this._dragCardId;
        if (!cardId || !targetStatus) return;

        const card = this._cards.find(c => c.id === cardId);
        if (!card || card.status === targetStatus) return;

        // Optimistic update so the UI moves the card immediately
        this._cards = this._cards.map(c =>
            c.id === cardId ? { ...c, status: targetStatus } : c
        );

        try {
            await updateStatus({ workPackageId: cardId, newStatus: targetStatus });
            await refreshApex(this._wiredResult);
        } catch (e) {
            // Roll back optimistic update
            this._cards = this._cards.map(c =>
                c.id === cardId ? { ...c, status: card.status } : c
            );
            this.toast('Error', e.body?.message ?? 'Status update failed', 'error');
        }
    }

    // ---- new WP modal ----

    handleNewWP() {
        this.showModal = true;
    }

    closeModal() {
        this.showModal = false;
    }

    handleSaveSuccess() {
        this.showModal = false;
        this.toast('Saved', 'Work package created', 'success');
        refreshApex(this._wiredResult);
    }

    handleSaveError(event) {
        this.toast('Error', event.detail?.message ?? 'Save failed', 'error');
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
