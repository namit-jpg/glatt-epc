import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getDashboard from '@salesforce/apex/EPCDashboardController.getDashboard';

const WEATHER_ICON = { Sunny: 'Sun', Cloudy: 'Cloud', Rain: 'Rain', Other: '-' };

const BU_CLASS = {
    OSD:      'bu-badge bu-badge_osd',
    Steriles: 'bu-badge bu-badge_steriles',
    OEM:      'bu-badge bu-badge_oem'
};

function fmtCurrency(val) {
    if (val == null || val === 0) return '—';
    if (val >= 10_000_000) return '₹' + (val / 10_000_000).toFixed(1) + ' Cr';
    if (val >= 100_000)    return '₹' + (val / 100_000).toFixed(1) + ' L';
    if (val >= 1_000)      return '₹' + (val / 1_000).toFixed(0) + 'K';
    return '₹' + val.toFixed(0);
}

function fmtDate(d) {
    if (!d) return '—';
    const [y, m, day] = String(d).split('-');
    return `${day}/${m}/${y}`;
}

function progressStyle(pct) {
    const clamped = Math.max(0, Math.min(100, pct ?? 0));
    return `width:${clamped}%`;
}

export default class EpcDashboard extends LightningElement {
    @track _data = null;
    _wiredResult;
    isLoading    = true;
    isRefreshing = false;
    hasError     = false;
    errorMessage = '';

    @wire(getDashboard)
    wiredData(result) {
        this._wiredResult = result;
        this.isLoading    = false;
        this.isRefreshing = false;
        if (result.data) {
            this._data    = this._transform(result.data);
            this.hasError = false;
        } else if (result.error) {
            this.hasError     = true;
            this.errorMessage = result.error?.body?.message ?? 'Failed to load dashboard data.';
        }
    }

    _transform(raw) {
        return {
            ...raw,
            portfolio: raw.portfolio.map(p => ({
                ...p,
                progressLabel: (p.progress ?? 0).toFixed(1) + '%',
                progressStyle: progressStyle(p.progress),
                budgetLabel:   fmtCurrency(p.budget),
                spentLabel:    fmtCurrency(p.spent),
                spentStyle:    progressStyle(p.budget > 0 ? (p.spent / p.budget) * 100 : 0),
                endDateLabel:  fmtDate(p.endDate),
                statusClass:   'status-badge status-badge_' + (p.statusClass ?? 'plan'),
                buClass:       BU_CLASS[p.businessUnit] ?? 'bu-badge'
            })),
            buBreakdown: raw.buBreakdown.map(bu => ({
                ...bu,
                progressLabel:  (bu.avgProgress ?? 0).toFixed(1) + '%',
                progressStyle:  progressStyle(bu.avgProgress),
                budgetLabel:    fmtCurrency(bu.totalBudget),
                pluralSuffix:   bu.projectCount === 1 ? '' : 's',
                buClass:        BU_CLASS[bu.businessUnit] ?? 'bu-badge'
            })),
            criticalItems: raw.criticalItems.map(c => ({
                ...c,
                endDateLabel: fmtDate(c.endDate),
                riskClass:    'risk-badge risk-badge_' + (c.riskClass ?? 'critical')
            })),
            recentLogs: raw.recentLogs.map(l => ({
                ...l,
                dateLabel:    fmtDate(l.logDate),
                percentLabel: (l.percentComplete ?? 0).toFixed(0),
                weatherIcon:  WEATHER_ICON[l.weather] ?? '-',
                notesSnippet: l.notes ? (l.notes.length > 120 ? l.notes.substring(0, 117) + '…' : l.notes) : ''
            }))
        };
    }

    handleRefresh() {
        this.isRefreshing = true;
        refreshApex(this._wiredResult);
    }

    // ── Computed properties ───────────────────────────────────
    get hasData()          { return !this.isLoading && !this.hasError && this._data?.projectCount > 0; }
    get isEmpty()          { return !this.isLoading && !this.hasError && (!this._data || this._data.projectCount === 0); }
    get projectCount()     { return this._data?.projectCount ?? 0; }
    get criticalItemCount(){ return this._data?.criticalItemCount ?? 0; }
    get atRiskCount()      { return this._data?.atRiskCount ?? 0; }
    get totalBudgetLabel() { return fmtCurrency(this._data?.totalBudget); }
    get avgProgressLabel() { return (this._data?.avgProgress ?? 0).toFixed(1) + '%'; }
    get avgProgressBarStyle() { return progressStyle(this._data?.avgProgress); }
    get portfolio()        { return this._data?.portfolio ?? []; }
    get buBreakdown()      { return this._data?.buBreakdown ?? []; }
    get criticalItems()    { return this._data?.criticalItems ?? []; }
    get recentLogs()       { return this._data?.recentLogs ?? []; }
    get hasCriticalItems() { return this.criticalItems.length > 0; }
    get hasLogs()          { return this.recentLogs.length > 0; }
}
