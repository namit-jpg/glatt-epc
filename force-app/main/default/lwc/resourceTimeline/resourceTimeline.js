import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getResourceTimeline from '@salesforce/apex/ResourceAllocationController.getResourceTimeline';

const DAY = 86400000;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// Layout constants (px) — tuned to MS Project / Frappe Gantt proportions
const NAME_COL = 232;
const ROW_MIN_H = 46;
const BAR_H = 26;
const LANE_GAP = 4;
const ROW_PAD = 7;
const MIN_BAR_W = 5;

// Zoom presets: pixels-per-day + which unit each header tier renders
const ZOOM = {
    week:    { px: 22,  top: 'month',   bottom: 'day'   },
    month:   { px: 7.6, top: 'month',   bottom: 'week'  },
    quarter: { px: 3.4, top: 'quarter', bottom: 'month' }
};

// A professional, well-separated palette; one stable colour per project
const PALETTE = [
    { bar: '#0176d3', edge: '#0b5cab' },
    { bar: '#2e844a', edge: '#1a6332' },
    { bar: '#9050e9', edge: '#6b27c7' },
    { bar: '#e2683c', edge: '#b8431c' },
    { bar: '#0b827c', edge: '#066059' },
    { bar: '#b85c00', edge: '#8a4500' },
    { bar: '#cb3a8f', edge: '#9c216a' },
    { bar: '#3b6ad4', edge: '#2746a0' }
];
const NO_PROJECT_COLOR = { bar: '#9c9c9c', edge: '#6e6e6e' };

function parseUtcMs(dateStr) {
    if (!dateStr) return null;
    const p = String(dateStr).split('-');
    if (p.length !== 3) return null;
    return Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
}
const serialOf = (ms) => (ms == null ? NaN : Math.round(ms / DAY));
const dowOf = (serial) => new Date(serial * DAY).getUTCDay(); // 0=Sun..6=Sat

function dayMonthLabel(serial) {
    const d = new Date(serial * DAY);
    return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

export default class ResourceTimeline extends LightningElement {
    @track _data = null;
    _wiredResult;
    isLoading = true;
    hasError = false;
    errorMessage = '';

    selectedProjectId = 'all';
    zoom = 'month';
    _scrolledToToday = false;

    @track view = { hasData: false };
    @track kpi = {};

    @wire(getResourceTimeline)
    wired(result) {
        this._wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this._data = result.data;
            this.hasError = false;
            this._scrolledToToday = false;
            this._build();
        } else if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error?.body?.message ?? 'Failed to load timeline.';
        }
    }

    renderedCallback() {
        if (this.view.hasData && !this._scrolledToToday && this.view.todayScrollLeft != null) {
            const scroller = this.template.querySelector('.rt-scroll');
            if (scroller) {
                scroller.scrollLeft = this.view.todayScrollLeft;
                this._scrolledToToday = true;
            }
        }
    }

    // ── Project colours (stable across filters) ───────────────────
    get _projectColorMap() {
        const map = new Map();
        const sorted = [...(this._data?.projects ?? [])].sort((a, b) =>
            (a.name || '').localeCompare(b.name || ''));
        sorted.forEach((p, i) => map.set(p.id, PALETTE[i % PALETTE.length]));
        return map;
    }

    get projectOptions() {
        const opts = [{ label: 'All projects', value: 'all' }];
        [...(this._data?.projects ?? [])]
            .sort((a, b) => (a.name || '').localeCompare(b.name || ''))
            .forEach(p => opts.push({ label: p.name, value: p.id }));
        return opts;
    }

    get legend() {
        const colors = this._projectColorMap;
        return [...(this._data?.projects ?? [])]
            .sort((a, b) => (a.name || '').localeCompare(b.name || ''))
            .map(p => {
                const c = colors.get(p.id) || NO_PROJECT_COLOR;
                return { id: p.id, name: p.name, style: `background:${c.bar};` };
            });
    }

    // ── Main builder ──────────────────────────────────────────────
    _build() {
        const colors = this._projectColorMap;
        const all = this._data?.allocations ?? [];
        const allocs = (this.selectedProjectId === 'all'
            ? all
            : all.filter(a => a.projectId === this.selectedProjectId))
            .map(a => ({
                ...a,
                _s: serialOf(parseUtcMs(a.startDate)),
                _e: serialOf(parseUtcMs(a.endDate))
            }))
            .filter(a => Number.isFinite(a._s) && Number.isFinite(a._e) && a._e >= a._s);

        if (!allocs.length) {
            this.view = { hasData: false };
            this.kpi = { resources: 0, over: 0, projects: 0, range: '—' };
            return;
        }

        const cfg = ZOOM[this.zoom];
        const px = cfg.px;

        // Domain padded to whole months
        let minS = Infinity, maxS = -Infinity;
        for (const a of allocs) { if (a._s < minS) minS = a._s; if (a._e > maxS) maxS = a._e; }
        const sd = new Date(minS * DAY), ed = new Date(maxS * DAY);
        const domStartMs = Date.UTC(sd.getUTCFullYear(), sd.getUTCMonth(), 1);
        const domEndMs = Date.UTC(ed.getUTCFullYear(), ed.getUTCMonth() + 1, 0);
        const domStart = serialOf(domStartMs);
        const domEnd = serialOf(domEndMs);
        const totalDays = domEnd - domStart + 1;
        const trackW = Math.ceil(totalDays * px);
        const leftOf = (serial) => (serial - domStart) * px;

        // ── Header tiers ──
        let topCells = cfg.top === 'quarter'
            ? this._quarterCells(domStart, domEnd, leftOf, px)
            : this._monthCells(domStart, domEnd, leftOf, px);

        let bottomCells, weekendStripes = [];
        if (cfg.bottom === 'day') {
            bottomCells = this._dayCells(domStart, domEnd, leftOf, px);
            weekendStripes = bottomCells
                .filter(c => c.weekend)
                .map(c => ({ key: 'we' + c.key, style: `left:${c.left}px;width:${px}px;` }));
        } else if (cfg.bottom === 'week') {
            bottomCells = this._weekCells(domStart, domEnd, leftOf, px);
        } else {
            bottomCells = this._monthCells(domStart, domEnd, leftOf, px).map(c => ({
                key: c.key, label: c.shortLabel, left: c.left, width: c.width
            }));
        }

        const gridLines = bottomCells
            .filter(c => c.left > 0)
            .map(c => ({ key: 'g' + c.key, style: `left:${c.left}px;` }));

        // Absolute positioning style for every header cell
        const withStyle = (arr) => arr.map(c => ({
            ...c, style: `left:${c.left}px;width:${c.width}px;`
        }));
        topCells = withStyle(topCells);
        bottomCells = withStyle(bottomCells);

        // ── Today marker ──
        const todayMs = Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), new Date().getUTCDate());
        const todayS = serialOf(todayMs);
        let todayStyle = 'display:none', todayScrollLeft = null;
        if (todayS >= domStart && todayS <= domEnd) {
            const tLeft = leftOf(todayS);
            todayStyle = `left:${NAME_COL + tLeft}px;`;
            todayScrollLeft = Math.max(0, tLeft - 120);
        }

        // ── Group by resource, lane-pack, build bars ──
        const resMap = new Map();
        for (const a of allocs) {
            if (!resMap.has(a.resourceId)) {
                resMap.set(a.resourceId, {
                    resourceId: a.resourceId,
                    resourceName: a.resourceName || 'Unassigned',
                    role: a.role || '',
                    items: []
                });
            }
            resMap.get(a.resourceId).items.push(a);
        }

        let overCount = 0;
        const rows = [];
        for (const r of resMap.values()) {
            const items = r.items.sort((x, y) => x._s - y._s);

            // Greedy lane packing so concurrent assignments never overlap
            const laneEnds = [];
            for (const it of items) {
                let lane = laneEnds.findIndex(end => end < it._s);
                if (lane === -1) { laneEnds.push(it._e); lane = laneEnds.length - 1; }
                else laneEnds[lane] = it._e;
                it._lane = lane;
            }
            const laneCount = Math.max(1, laneEnds.length);
            const rowH = Math.max(ROW_MIN_H, laneCount * (BAR_H + LANE_GAP) + ROW_PAD * 2 - LANE_GAP);

            // Peak concurrent load (sweepline) → over-allocation
            const events = [];
            for (const it of items) {
                const pct = it.allocationPercent || 0;
                events.push([it._s, pct]);
                events.push([it._e + 1, -pct]);
            }
            events.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
            let running = 0, peak = 0;
            for (const [, delta] of events) { running += delta; if (running > peak) peak = running; }
            const isOver = peak > 100;
            if (isOver) overCount++;

            const bars = items.map(it => {
                const c = it.projectId ? (colors.get(it.projectId) || NO_PROJECT_COLOR) : NO_PROJECT_COLOR;
                const w = Math.max((it._e - it._s + 1) * px, MIN_BAR_W);
                const top = ROW_PAD + it._lane * (BAR_H + LANE_GAP);
                const pct = it.allocationPercent != null ? `${Math.round(it.allocationPercent)}%` : '';
                const wide = w >= 38;
                return {
                    id: it.id,
                    style: `left:${leftOf(it._s)}px;width:${w}px;top:${top}px;height:${BAR_H}px;`
                        + `background:${c.bar};border-color:${c.edge};`,
                    label: wide ? pct : '',
                    showLabel: wide,
                    title: `${r.resourceName} · ${it.projectName || 'No project'}\n`
                        + `${it.wbsItemName || 'Project-wide'} — ${pct}\n`
                        + `${dayMonthLabel(it._s)} → ${dayMonthLabel(it._e)}`
                };
            });

            rows.push({
                resourceId: r.resourceId,
                resourceName: r.resourceName,
                role: r.role,
                peakLabel: `Peak ${Math.round(peak)}%`,
                isOver,
                rowClass: isOver ? 'rt-row rt-row_over' : 'rt-row',
                nameClass: isOver ? 'rt-name rt-name_over' : 'rt-name',
                peakClass: isOver ? 'rt-peak rt-peak_over' : 'rt-peak',
                rowStyle: `height:${rowH}px;`,
                trackStyle: `height:${rowH}px;`,
                bars
            });
        }

        this.view = {
            hasData: true,
            rows,
            topCells,
            bottomCells,
            gridLines,
            weekendStripes,
            todayStyle,
            todayScrollLeft,
            contentStyle: `width:${NAME_COL + trackW}px;`,
            tierStyle: `width:${trackW}px;`,
            bgStyle: `left:${NAME_COL}px;width:${trackW}px;`,
            nameColStyle: `width:${NAME_COL}px;min-width:${NAME_COL}px;`
        };

        const rangeStart = new Date(domStart * DAY);
        const rangeEnd = new Date(domEnd * DAY);
        this.kpi = {
            resources: rows.length,
            over: overCount,
            projects: this.selectedProjectId === 'all'
                ? (this._data?.projects?.length ?? 0) : 1,
            range: `${MONTHS[rangeStart.getUTCMonth()]} ${rangeStart.getUTCFullYear()} – `
                + `${MONTHS[rangeEnd.getUTCMonth()]} ${rangeEnd.getUTCFullYear()}`,
            overClass: overCount > 0 ? 'rt-kpi-num rt-kpi-num_over' : 'rt-kpi-num'
        };
    }

    // ── Cell builders ─────────────────────────────────────────────
    _monthCells(domStart, domEnd, leftOf, px) {
        const cells = [];
        let cur = Date.UTC(new Date(domStart * DAY).getUTCFullYear(), new Date(domStart * DAY).getUTCMonth(), 1);
        while (serialOf(cur) <= domEnd) {
            const d = new Date(cur);
            const start = Math.max(serialOf(cur), domStart);
            const nextMs = Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1);
            const end = Math.min(serialOf(nextMs) - 1, domEnd);
            const yy = String(d.getUTCFullYear()).slice(2);
            cells.push({
                key: 'm' + cur,
                label: `${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`,
                shortLabel: `${MONTHS[d.getUTCMonth()]} '${yy}`,
                left: leftOf(start),
                width: (end - start + 1) * px
            });
            cur = nextMs;
        }
        return cells;
    }

    _quarterCells(domStart, domEnd, leftOf, px) {
        const cells = [];
        const d0 = new Date(domStart * DAY);
        let cur = Date.UTC(d0.getUTCFullYear(), Math.floor(d0.getUTCMonth() / 3) * 3, 1);
        while (serialOf(cur) <= domEnd) {
            const d = new Date(cur);
            const start = Math.max(serialOf(cur), domStart);
            const nextMs = Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 3, 1);
            const end = Math.min(serialOf(nextMs) - 1, domEnd);
            cells.push({
                key: 'q' + cur,
                label: `Q${Math.floor(d.getUTCMonth() / 3) + 1} ${d.getUTCFullYear()}`,
                left: leftOf(start),
                width: (end - start + 1) * px
            });
            cur = nextMs;
        }
        return cells;
    }

    _weekCells(domStart, domEnd, leftOf, px) {
        const cells = [];
        const firstMonday = domStart - ((dowOf(domStart) + 6) % 7);
        for (let m = firstMonday; m <= domEnd; m += 7) {
            const start = Math.max(m, domStart);
            const end = Math.min(m + 6, domEnd);
            cells.push({
                key: 'w' + start,
                label: `${dayMonthLabel(start).split(' ')[0]}`,
                left: leftOf(start),
                width: (end - start + 1) * px
            });
        }
        return cells;
    }

    _dayCells(domStart, domEnd, leftOf, px) {
        const cells = [];
        for (let s = domStart; s <= domEnd; s++) {
            const dow = dowOf(s);
            cells.push({
                key: 'd' + s,
                label: String(new Date(s * DAY).getUTCDate()),
                left: leftOf(s),
                width: px,
                weekend: dow === 0 || dow === 6
            });
        }
        return cells;
    }

    // ── UI handlers ───────────────────────────────────────────────
    handleProjectChange(e) { this.selectedProjectId = e.detail.value; this._scrolledToToday = false; this._build(); }
    setZoomWeek() { this._setZoom('week'); }
    setZoomMonth() { this._setZoom('month'); }
    setZoomQuarter() { this._setZoom('quarter'); }
    _setZoom(z) { if (z !== this.zoom) { this.zoom = z; this._scrolledToToday = false; this._build(); } }
    handleRefresh() { refreshApex(this._wiredResult); }

    get isWeek() { return this.zoom === 'week'; }
    get isMonth() { return this.zoom === 'month'; }
    get isQuarter() { return this.zoom === 'quarter'; }
    get weekBtnClass() { return this.zoom === 'week' ? 'rt-zoom-btn rt-zoom-btn_active' : 'rt-zoom-btn'; }
    get monthBtnClass() { return this.zoom === 'month' ? 'rt-zoom-btn rt-zoom-btn_active' : 'rt-zoom-btn'; }
    get quarterBtnClass() { return this.zoom === 'quarter' ? 'rt-zoom-btn rt-zoom-btn_active' : 'rt-zoom-btn'; }

    get showTimeline() { return !this.isLoading && !this.hasError && this.view.hasData; }
    get isEmpty() { return !this.isLoading && !this.hasError && !this.view.hasData; }
    get hasProjects() { return (this._data?.projects?.length ?? 0) > 0; }
}
