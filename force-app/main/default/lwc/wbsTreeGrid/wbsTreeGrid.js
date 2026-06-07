import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getWBSTree from '@salesforce/apex/WBSTreeController.getWBSTree';
import deleteWBSItem from '@salesforce/apex/WBSTreeController.deleteWBSItem';
import runCPM from '@salesforce/apex/WBSTreeController.runCPM';

const DEP_LABELS = {
    FS: 'Finish-to-Start (FS)',
    SS: 'Start-to-Start (SS)',
    FF: 'Finish-to-Finish (FF)',
    SF: 'Start-to-Finish (SF)'
};

function fmtDate(d) {
    if (!d) return '';
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d));
    return m ? `${m[3]}-${m[2]}-${m[1]}` : String(d);
}

function fmtCurrency(v) {
    if (v == null) return '';
    return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(v);
}

export default class WbsTreeGrid extends LightningElement {
    @api recordId;

    @track treeData = [];
    @track showModal = false;
    @track editRecordId;
    @track parentId;
    @track modalTitle = 'New WBS Item';

    _wiredResult;
    _expandedIds = new Set();
    @track _expandedVersion = 0;

    isLoading = true;
    isCpmRunning = false;
    hasError = false;
    errorMessage;

    @wire(getWBSTree, { projectId: '$recordId' })
    wiredTree(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.treeData = this._transform(result.data);
            this._expandedIds = new Set();
            this._collectIds(this.treeData);
            this._expandedVersion++;
            this.hasError = false;
        } else if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error.body?.message ?? 'Failed to load WBS data.';
        }
    }

    _transform(nodes) {
        return nodes.map(n => ({
            ...n,
            pct: n.progress ?? 0,
            displayStart: n.earlyStart ?? n.startDate,
            displayEnd:   n.earlyFinish ?? n.endDate,
            depTypeFull:  n.predecessorCode && n.dependencyType ? (DEP_LABELS[n.dependencyType] ?? n.dependencyType) : null,
            children: n.children?.length ? this._transform(n.children) : []
        }));
    }

    _collectIds(nodes) {
        nodes.forEach(n => {
            this._expandedIds.add(n.id);
            if (n.children?.length) this._collectIds(n.children);
        });
    }

    get flatRows() {
        void this._expandedVersion;
        const rows = [];
        this._flatten(this.treeData, rows, 0);
        return rows;
    }

    _flatten(nodes, rows, depth) {
        nodes.forEach(n => {
            const hasChildren = n.children?.length > 0;
            const isExpanded  = this._expandedIds.has(n.id);
            const pct         = n.pct ?? 0;
            const isCritical  = n.isCritical === true;
            const isRoot      = depth === 0;

            const cls = [
                'wbs-row',
                isRoot ? 'wbs-row-root' : (hasChildren ? 'wbs-row-branch' : 'wbs-row-leaf'),
                isCritical ? 'wbs-row-critical' : ''
            ].filter(Boolean).join(' ');

            rows.push({
                id:               n.id,
                depth,
                hasChildren,
                isExpanded,
                name:             n.name,
                wbsCode:          n.wbsCode ?? '',
                durationDays:     n.durationDays ?? '',
                lagDisplay:       n.lagDays ? String(n.lagDays) : '',
                predecessorCode:  n.predecessorCode ?? '',
                depTypeFull:      n.depTypeFull ?? '',
                budgetFormatted:  fmtCurrency(n.budget),
                floatDisplay:     n.floatDays != null ? String(n.floatDays) : '',
                startFormatted:   fmtDate(n.displayStart),
                endFormatted:     fmtDate(n.displayEnd),
                isCritical,
                rowClass:         cls,
                indentStyle:      `margin-left:${depth * 1.25}rem`,
                toggleIcon:       isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                codeClass:        ['wbs-code', isRoot ? 'wbs-code-root' : '', isCritical ? 'wbs-code-critical' : ''].filter(Boolean).join(' '),
                nameClass:        ['wbs-name', isRoot ? 'wbs-name-root' : '', isCritical ? 'wbs-name-critical' : ''].filter(Boolean).join(' '),
                progressFillStyle: `width:${Math.min(pct, 100)}%`,
                progressLabel:    `${Math.round(pct)}%`
            });

            if (hasChildren && isExpanded) {
                this._flatten(n.children, rows, depth + 1);
            }
        });
    }

    get hasData()  { return !this.isLoading && !this.hasError && this.treeData.length > 0; }
    get isEmpty()  { return !this.isLoading && !this.hasError && this.treeData.length === 0; }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        if (this._expandedIds.has(id)) this._expandedIds.delete(id);
        else this._expandedIds.add(id);
        this._expandedVersion++;
    }

    async handleRunCPM() {
        this.isCpmRunning = true;
        try {
            await runCPM({ projectId: this.recordId });
            this.toast('CPM Complete', 'Critical path and progress recalculated', 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this.toast('CPM Error', e.body?.message ?? 'Recalculation failed', 'error');
        } finally {
            this.isCpmRunning = false;
        }
    }

    handleAddRoot() {
        this.editRecordId = undefined;
        this.parentId     = undefined;
        this.modalTitle   = 'New Root WBS Item';
        this.showModal    = true;
    }

    handleAddChild(event) {
        this.editRecordId = undefined;
        this.parentId     = event.currentTarget.dataset.id;
        this.modalTitle   = `Add Child under: ${event.currentTarget.dataset.label}`;
        this.showModal    = true;
    }

    handleEdit(event) {
        this.editRecordId = event.currentTarget.dataset.id;
        this.parentId     = undefined;
        this.modalTitle   = `Edit: ${event.currentTarget.dataset.label}`;
        this.showModal    = true;
    }

    async handleDelete(event) {
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.label;
        try {
            await deleteWBSItem({ itemId: id });
            this.toast('Deleted', `"${name}" removed`, 'success');
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
            if (this.parentId) fields.Parent_WBS_Item__c = this.parentId;
        }
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSaveSuccess() {
        this.showModal = false;
        this.toast('Saved', 'WBS item saved successfully', 'success');
        refreshApex(this._wiredResult);
    }

    handleSaveError(event) {
        this.toast('Save Error', event.detail?.message ?? 'Save failed', 'error');
    }

    closeModal() {
        this.showModal    = false;
        this.editRecordId = undefined;
        this.parentId     = undefined;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
