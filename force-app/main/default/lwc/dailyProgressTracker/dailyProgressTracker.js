import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getProgressBoard from '@salesforce/apex/DailyProgressController.getProgressBoard';
import deleteProgress from '@salesforce/apex/DailyProgressController.deleteProgress';

const STATUS_CLASS = {
    'Planned':     'status-badge status-planned',
    'In Progress': 'status-badge status-inprogress',
    'Blocked':     'status-badge status-blocked',
    'Complete':    'status-badge status-complete'
};

export default class DailyProgressTracker extends LightningElement {
    @api recordId;

    @track wbsGroups = [];
    @track showModal = false;
    @track selectedWpId;
    @track selectedWpName;
    @track modalTitle = 'Log Daily Progress';

    _wiredResult;
    isLoading = true;
    hasError = false;
    errorMessage;

    @wire(getProgressBoard, { projectId: '$recordId' })
    wiredBoard(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.wbsGroups = this._buildGroups(result.data.wpCards);
            this.hasError = false;
        } else if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error.body?.message ?? 'Failed to load progress data.';
        }
    }

    _buildGroups(cards) {
        const groupMap = new Map();
        const groupOrder = [];

        for (const card of cards) {
            if (!groupMap.has(card.wbsItemId)) {
                groupMap.set(card.wbsItemId, { wbsItemId: card.wbsItemId, wbsItemName: card.wbsItemName, cards: [] });
                groupOrder.push(card.wbsItemId);
            }
            groupMap.get(card.wbsItemId).cards.push(this._enrichCard(card));
        }

        return groupOrder.map(id => groupMap.get(id));
    }

    _enrichCard(card) {
        const pct = card.latestPercent ?? 0;
        return {
            ...card,
            progressValue: pct,
            progressStyle: `width: ${Math.min(pct, 100)}%`,
            progressLabel: card.latestPercent != null ? `${card.latestPercent}%` : 'Not started',
            statusClass: STATUS_CLASS[card.status] ?? 'status-badge',
            hasEntries: card.entries && card.entries.length > 0,
            entries: (card.entries ?? []).map(e => this._enrichEntry(e))
        };
    }

    _enrichEntry(entry) {
        let dateStr = '';
        if (entry.progressDate) {
            const d = new Date(entry.progressDate + 'T12:00:00');
            dateStr = d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
        }
        return {
            ...entry,
            progressDateFormatted: dateStr
        };
    }

    get isEmpty() {
        return !this.isLoading && !this.hasError && this.wbsGroups.length === 0;
    }

    get hasData() {
        return !this.isLoading && !this.hasError && this.wbsGroups.length > 0;
    }

    get todayDate() {
        const now = new Date();
        const y = now.getFullYear();
        const m = String(now.getMonth() + 1).padStart(2, '0');
        const d = String(now.getDate()).padStart(2, '0');
        return `${y}-${m}-${d}`;
    }

    get showWpField() {
        return !this.selectedWpId;
    }

    handleNew() {
        this.selectedWpId = null;
        this.selectedWpName = null;
        this.modalTitle = 'Log Daily Progress';
        this.showModal = true;
    }

    handleLogForWp(event) {
        this.selectedWpId = event.currentTarget.dataset.wpId;
        this.selectedWpName = event.currentTarget.dataset.wpName;
        this.modalTitle = `Log Progress: ${this.selectedWpName}`;
        this.showModal = true;
    }

    handleSubmit(event) {
        event.preventDefault();
        const fields = { ...event.detail.fields };
        fields.Project__c = this.recordId;
        if (this.selectedWpId) fields.Work_Package__c = this.selectedWpId;
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSaveSuccess() {
        this.showModal = false;
        this.toast('Saved', 'Progress entry logged', 'success');
        refreshApex(this._wiredResult);
    }

    handleSaveError(event) {
        this.toast('Save Error', event.detail?.message ?? 'Save failed', 'error');
    }

    async handleDeleteEntry(event) {
        const entryId = event.currentTarget.dataset.entryId;
        try {
            await deleteProgress({ progressId: entryId });
            this.toast('Deleted', 'Progress entry removed', 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this.toast('Error', e.body?.message ?? 'Delete failed', 'error');
        }
    }

    closeModal() {
        this.showModal = false;
        this.selectedWpId = null;
        this.selectedWpName = null;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
