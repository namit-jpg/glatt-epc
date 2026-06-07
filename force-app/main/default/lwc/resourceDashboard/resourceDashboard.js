import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getUtilizationMatrix from '@salesforce/apex/ResourceAllocationController.getUtilizationMatrix';

const MONTHS_AHEAD = 6;

const CELL_CLASS_BY_STATUS = {
    empty: 'heat-cell heat-cell_empty',
    ok:    'heat-cell heat-cell_ok',
    warn:  'heat-cell heat-cell_warn',
    over:  'heat-cell heat-cell_over'
};

export default class ResourceDashboard extends LightningElement {
    @track monthLabels = [];
    @track rows = [];

    resourceCount = 0;
    overAllocatedCount = 0;
    averageLoad = 0;

    _wiredResult;
    isLoading = true;
    isRefreshing = false;
    hasError = false;
    errorMessage;

    @wire(getUtilizationMatrix, { monthsAhead: MONTHS_AHEAD })
    wiredMatrix(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.monthLabels = result.data.monthLabels;
            this.resourceCount = result.data.resourceCount;
            this.overAllocatedCount = result.data.overAllocatedCount;
            this.averageLoad = result.data.averageLoad;
            this.rows = result.data.rows.map(row => ({
                ...row,
                projectCountLabel: `${row.projectCount} project${row.projectCount === 1 ? '' : 's'}`,
                cells: row.cells.map((cell, index) => ({
                    ...cell,
                    key: `${row.resourceId}-${index}`,
                    label: cell.load > 0 ? `${cell.load}%` : '—',
                    cellClass: CELL_CLASS_BY_STATUS[cell.status] ?? CELL_CLASS_BY_STATUS.empty,
                    title: `${row.resourceName} — ${result.data.monthLabels[index]}: ${cell.load}% allocated`
                }))
            }));
            this.hasError = false;
        } else if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error.body?.message ?? 'Failed to load utilization data.';
        }
    }

    get hasData()              { return !this.isLoading && !this.hasError && this.rows.length > 0; }
    get isEmpty()              { return !this.isLoading && !this.hasError && this.rows.length === 0; }
    get hasOverAllocations()   { return this.overAllocatedCount > 0; }
    get averageLoadLabel()     { return `${this.averageLoad}%`; }
    get overAllocatedClass() {
        return this.hasOverAllocations
            ? 'slds-text-heading_large slds-text-color_error'
            : 'slds-text-heading_large slds-text-color_success';
    }

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            await refreshApex(this._wiredResult);
        } finally {
            this.isRefreshing = false;
        }
    }
}
