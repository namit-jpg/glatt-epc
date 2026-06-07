import { LightningElement, api, wire } from 'lwc';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import FRAPPE_GANTT from '@salesforce/resourceUrl/frappe_gantt';
import getWBSFlat from '@salesforce/apex/WBSTreeController.getWBSFlat';

export default class GanttChart extends LightningElement {
    @api recordId;

    isLoading = true;
    hasError = false;
    errorMessage;
    isEmpty = false;
    viewMode = 'Week';
    highlightCritical = false;
    criticalCount = 0;
    totalCount = 0;
    _gantt;
    _tasks = [];
    _criticalIds = new Set();
    _libLoaded = false;
    _dataLoaded = false;

    get dayVariant()   { return this.viewMode === 'Day'   ? 'brand' : 'neutral'; }
    get weekVariant()  { return this.viewMode === 'Week'  ? 'brand' : 'neutral'; }
    get monthVariant() { return this.viewMode === 'Month' ? 'brand' : 'neutral'; }
    get criticalVariant() { return this.highlightCritical ? 'destructive' : 'neutral'; }

    get showLegend() { return !this.isLoading && !this.hasError && !this.isEmpty; }

    get criticalSummary() {
        return `${this.criticalCount} of ${this.totalCount} tasks on the critical path`;
    }

    connectedCallback() {
        Promise.all([
            loadStyle(this, FRAPPE_GANTT + '/frappe-gantt.css'),
            loadScript(this, FRAPPE_GANTT + '/frappe-gantt.js')
        ])
        .then(() => {
            this._libLoaded = true;
            this.tryRender();
        })
        .catch(e => {
            this.hasError = true;
            this.isLoading = false;
            this.errorMessage = 'Failed to load Gantt library: ' + (e.message || e);
        });
    }

    @wire(getWBSFlat, { projectId: '$recordId' })
    wiredTasks({ data, error }) {
        if (data) {
            this._tasks = data;
            this._dataLoaded = true;
            this.tryRender();
        } else if (error) {
            this.hasError = true;
            this.isLoading = false;
            this.errorMessage = error.body?.message ?? 'Failed to load WBS data.';
        }
    }

    tryRender() {
        if (!this._libLoaded || !this._dataLoaded) return;
        this.isLoading = false;

        if (!this._tasks.length) {
            this.isEmpty = true;
            return;
        }

        this._criticalIds = new Set(this._tasks.filter(t => t.isCritical).map(t => t.id));
        this.criticalCount = this._criticalIds.size;
        this.totalCount = this._tasks.length;

        // Frappe Gantt modifies task objects in-place; pass copies.
        // Dependencies must reference ids present in the task list or the
        // library throws — drop any that point to filtered-out items.
        const knownIds = new Set(this._tasks.map(t => t.id));
        const tasks = this._tasks.map(t => ({
            id: t.id,
            name: t.name,
            start: t.start,
            end: t.endDate,
            progress: t.progress ?? 0,
            dependencies: knownIds.has(t.dependencies) ? t.dependencies : '',
            custom_class: t.isCritical ? 'gantt-critical' : ''
        }));

        const container = this.refs.ganttContainer;
        // Frappe Gantt needs a real SVG element inside the container.
        // Style tag injected here because LWC scoped CSS can't reach
        // innerHTML-created elements.
        container.innerHTML =
            '<style>' +
            '.gantt .bar-wrapper.gantt-critical .bar{fill:#fdb6b6;}' +
            '.gantt .bar-wrapper.gantt-critical .bar-progress{fill:#ea001e;}' +
            // Critical chain connector arrows: always red, like MS Project link lines
            '.gantt .arrow-critical{stroke:#ea001e;stroke-width:1.8;}' +
            // Highlight mode: fade everything that is not on the critical path
            '.dim-noncritical .gantt .bar-wrapper:not(.gantt-critical){opacity:0.25;}' +
            '.dim-noncritical .gantt path[data-from]:not(.arrow-critical){opacity:0.15;}' +
            '.dim-noncritical .gantt .bar-wrapper.gantt-critical .bar{fill:#f8a3a3;}' +
            '</style>' +
            '<svg></svg>';
        const svg = container.querySelector('svg');

        try {
            // eslint-disable-next-line no-undef
            this._gantt = new Gantt(svg, tasks, {
                view_mode: this.viewMode,
                date_format: 'YYYY-MM-DD'
            });
            this.markCriticalArrows();
            this.applyHighlightClass();
        } catch (e) {
            this.hasError = true;
            this.errorMessage = 'Gantt render failed: ' + (e.message || e);
        }
    }

    // An arrow is part of the critical chain when both its endpoints are critical.
    markCriticalArrows() {
        const container = this.refs.ganttContainer;
        if (!container) return;
        container.querySelectorAll('path[data-from]').forEach(p => {
            const from = p.getAttribute('data-from');
            const to = p.getAttribute('data-to');
            if (this._criticalIds.has(from) && this._criticalIds.has(to)) {
                p.classList.add('arrow-critical');
            }
        });
    }

    applyHighlightClass() {
        const container = this.refs.ganttContainer;
        if (!container) return;
        container.classList.toggle('dim-noncritical', this.highlightCritical);
    }

    handleViewMode(event) {
        this.viewMode = event.target.dataset.mode;
        if (this._gantt) {
            this._gantt.change_view_mode(this.viewMode);
            // view-mode change re-renders bars and arrows — re-mark the chain
            this.markCriticalArrows();
        }
    }

    handleToggleCritical() {
        this.highlightCritical = !this.highlightCritical;
        this.applyHighlightClass();
    }
}
