/**
 * Critical Path Method engine, modelled on Microsoft Project (desktop) scheduling.
 *
 * Conventions (matching MS Project / standard PDM CPM):
 *  - All scheduling math runs in WORKING-DAY ORDINAL space (integers). Ordinal 0 is
 *    the project start rolled forward to a working day; weekends (Sat/Sun) are skipped.
 *    Ordinals are converted to real calendar Dates only when writing the records.
 *  - A Start is the *beginning* of its day, a Finish the *end* of its day, so
 *    EF = ES + Duration - 1. Only links that cross a start<->finish boundary (FS, SF)
 *    carry the +/- 1 day adjustment; SS and FF do not.
 *  - Early Start = MAX over all predecessor-link constraints. Late Finish = MIN over
 *    all successor-link constraints. A task can have many predecessors (WBS_Dependency__c).
 *  - Total Slack = LF - EF (working days). A leaf task is critical when slack <= 0.
 *  - Summary (parent) tasks are NOT scheduled from their own duration; their dates are
 *    pure rollups of their descendants and they are never flagged critical.
 *
 * Predecessor links come from two sources, unioned: the WBS_Dependency__c junction
 * (multiple predecessors) and the legacy single Predecessor__c lookup on WBS_Item__c
 * (kept for backward compatibility with existing data).
 */
public with sharing class CPMEngine {

    // Internal per-link edge: predecessor -> successor with type + lag.
    private class Link {
        Id predId;
        Id succId;
        String type;
        Integer lag;
        Link(Id predId, Id succId, String type, Integer lag) {
            this.predId = predId; this.succId = succId;
            this.type = (type != null ? type : 'FS');
            this.lag = (lag != null ? lag : 0);
        }
    }

    public static void recalculate(Id projectId) {
        Project__c proj = [SELECT Id, Start_Date__c FROM Project__c WHERE Id = :projectId LIMIT 1];
        Date projectStartRaw = proj.Start_Date__c != null ? proj.Start_Date__c : Date.today();
        Date origin = rollForward(projectStartRaw); // ordinal 0 = first working day

        List<WBS_Item__c> items = [
            SELECT Id, Name, WBS_Code__c, Duration_Days__c, Predecessor__c,
                   Dependency_Type__c, Lag_Days__c, Parent_WBS_Item__c,
                   Budget__c, Progress__c, Actual_Start__c, Actual_Finish__c
            FROM WBS_Item__c
            WHERE Project__c = :projectId
            ORDER BY WBS_Code__c ASC NULLS LAST
        ];
        if (items.isEmpty()) return;

        Map<Id, WBS_Item__c> itemMap = new Map<Id, WBS_Item__c>(items);

        // ── Which items are summaries (have children)? ────────────────
        Set<Id> hasChildren = new Set<Id>();
        Map<Id, List<Id>> childMap = new Map<Id, List<Id>>();
        for (WBS_Item__c it : items) childMap.put(it.Id, new List<Id>());
        for (WBS_Item__c it : items) {
            if (it.Parent_WBS_Item__c != null && itemMap.containsKey(it.Parent_WBS_Item__c)) {
                hasChildren.add(it.Parent_WBS_Item__c);
                childMap.get(it.Parent_WBS_Item__c).add(it.Id);
            }
        }

        // ── Collect dependency links (junction + legacy single lookup) ─
        List<Link> links = buildLinks(projectId, items, itemMap);

        // predecessor list per successor, successor list per predecessor
        Map<Id, List<Link>> predLinks = new Map<Id, List<Link>>();
        Map<Id, List<Link>> succLinks = new Map<Id, List<Link>>();
        for (Id id : itemMap.keySet()) {
            predLinks.put(id, new List<Link>());
            succLinks.put(id, new List<Link>());
        }
        for (Link l : links) {
            predLinks.get(l.succId).add(l);
            succLinks.get(l.predId).add(l);
        }

        // ── Topological order over the dependency graph ───────────────
        List<Id> sorted = topoSort(itemMap, links);

        // ── Forward pass (working-day ordinals) ───────────────────────
        Map<Id, Integer> es = new Map<Id, Integer>();
        Map<Id, Integer> ef = new Map<Id, Integer>();
        for (Id id : sorted) {
            Integer dur = dur(itemMap.get(id));
            Integer start = 0; // project start floor
            for (Link l : predLinks.get(id)) {
                if (!ef.containsKey(l.predId)) continue;
                Integer pEF = ef.get(l.predId);
                Integer pES = es.get(l.predId);
                Integer cand;
                if (l.type == 'SS') {
                    cand = pES + l.lag;
                } else if (l.type == 'FF') {
                    cand = (pEF + l.lag) - dur + 1;
                } else if (l.type == 'SF') {
                    cand = (pES + l.lag) - dur;
                } else { // FS
                    cand = pEF + l.lag + 1;
                }
                if (cand > start) start = cand;
            }
            es.put(id, start);
            ef.put(id, start + dur - 1);
        }

        // ── Project finish = max Early Finish across leaf tasks ────────
        Integer projectEnd = 0;
        for (Id id : ef.keySet()) {
            if (!hasChildren.contains(id) && ef.get(id) > projectEnd) projectEnd = ef.get(id);
        }

        // ── Backward pass ─────────────────────────────────────────────
        Map<Id, Integer> ls = new Map<Id, Integer>();
        Map<Id, Integer> lf = new Map<Id, Integer>();
        for (Integer i = sorted.size() - 1; i >= 0; i--) {
            Id id = sorted.get(i);
            Integer dur = dur(itemMap.get(id));
            Integer late = projectEnd; // ceiling / no-successor default
            for (Link l : succLinks.get(id)) {
                if (!ls.containsKey(l.succId)) continue;
                Integer sLS = ls.get(l.succId);
                Integer sLF = lf.get(l.succId);
                Integer cand;
                if (l.type == 'SS') {
                    cand = (sLS - l.lag) + dur - 1;
                } else if (l.type == 'FF') {
                    cand = sLF - l.lag;
                } else if (l.type == 'SF') {
                    cand = (sLF - l.lag) + dur;
                } else { // FS
                    cand = sLS - l.lag - 1;
                }
                if (cand < late) late = cand;
            }
            lf.put(id, late);
            ls.put(id, late - dur + 1);
        }

        // ── Summary rollup of ordinals (bottom-up, multi-pass) ─────────
        for (Integer pass = 0; pass < 20; pass++) {
            Boolean changed = false;
            for (WBS_Item__c it : items) {
                List<Id> kids = childMap.get(it.Id);
                if (kids == null || kids.isEmpty()) continue;
                Integer minES = null, maxEF = null, minLS = null, maxLF = null;
                for (Id k : kids) {
                    minES = (minES == null || es.get(k) < minES) ? es.get(k) : minES;
                    maxEF = (maxEF == null || ef.get(k) > maxEF) ? ef.get(k) : maxEF;
                    minLS = (minLS == null || ls.get(k) < minLS) ? ls.get(k) : minLS;
                    maxLF = (maxLF == null || lf.get(k) > maxLF) ? lf.get(k) : maxLF;
                }
                if (es.get(it.Id) != minES || ef.get(it.Id) != maxEF
                        || ls.get(it.Id) != minLS || lf.get(it.Id) != maxLF) {
                    es.put(it.Id, minES); ef.put(it.Id, maxEF);
                    ls.put(it.Id, minLS); lf.put(it.Id, maxLF);
                    changed = true;
                }
            }
            if (!changed) break;
        }

        // ── Write schedule + float + critical flag ─────────────────────
        for (WBS_Item__c it : items) {
            it.Early_Start__c  = dateForOrdinal(origin, es.get(it.Id));
            it.Early_Finish__c = dateForOrdinal(origin, ef.get(it.Id));
            it.Late_Start__c   = dateForOrdinal(origin, ls.get(it.Id));
            it.Late_Finish__c  = dateForOrdinal(origin, lf.get(it.Id));
            Integer slack      = lf.get(it.Id) - ef.get(it.Id);
            it.Float_Days__c   = slack;
            // Summary tasks are never on the critical path (MS Project convention).
            it.Is_Critical__c  = !hasChildren.contains(it.Id) && slack <= 0;
        }

        // ── Auto actual dates on leaves (from progress) ────────────────
        Date today = Date.today();
        for (WBS_Item__c it : items) {
            if (hasChildren.contains(it.Id)) continue;
            Decimal prog = it.Progress__c != null ? it.Progress__c : 0;
            if (prog > 0 && it.Actual_Start__c == null) it.Actual_Start__c = today;
            if (prog >= 100) {
                if (it.Actual_Finish__c == null) it.Actual_Finish__c = today;
            } else if (it.Actual_Finish__c != null) {
                it.Actual_Finish__c = null;
            }
        }

        // ── Progress roll-up (budget-weighted, leaf -> root) ───────────
        rollupProgress(items, itemMap, childMap);

        // ── Actual-date roll-up to summaries (bottom-up) ───────────────
        rollupActuals(items, childMap);

        // ── Persist ───────────────────────────────────────────────────
        TriggerHelper.isRunning = true;
        update items;
        TriggerHelper.isRunning = false;

        // ── Project overall progress (budget-weighted over roots) ──────
        Set<Id> allIds = itemMap.keySet();
        Decimal totalBudget = 0, weightedProg = 0;
        for (WBS_Item__c it : items) {
            if (it.Parent_WBS_Item__c == null || !allIds.contains(it.Parent_WBS_Item__c)) {
                Decimal b = it.Budget__c != null ? it.Budget__c : 0;
                Decimal p = it.Progress__c != null ? it.Progress__c : 0;
                totalBudget += b;
                weightedProg += b * p;
            }
        }
        Decimal overall = totalBudget > 0 ? (weightedProg / totalBudget).setScale(2) : 0;
        TriggerHelper.isRunning = true;
        update new Project__c(Id = projectId, Overall_Progress__c = overall);
        TriggerHelper.isRunning = false;
    }

    // ── Build the union of dependency links ───────────────────────────
    private static List<Link> buildLinks(Id projectId, List<WBS_Item__c> items, Map<Id, WBS_Item__c> itemMap) {
        List<Link> links = new List<Link>();

        // Junction object — multiple predecessors per task.
        for (WBS_Dependency__c d : [
                SELECT Successor__c, Predecessor__c, Dependency_Type__c, Lag_Days__c
                FROM WBS_Dependency__c
                WHERE Successor__r.Project__c = :projectId
                  AND Predecessor__c != null AND Successor__c != null
        ]) {
            if (itemMap.containsKey(d.Successor__c) && itemMap.containsKey(d.Predecessor__c)
                    && d.Successor__c != d.Predecessor__c) {
                links.add(new Link(d.Predecessor__c, d.Successor__c, d.Dependency_Type__c,
                                   d.Lag_Days__c != null ? (Integer) d.Lag_Days__c : 0));
            }
        }

        // Legacy single-lookup predecessor on the WBS item itself.
        for (WBS_Item__c it : items) {
            if (it.Predecessor__c != null && itemMap.containsKey(it.Predecessor__c)
                    && it.Predecessor__c != it.Id) {
                links.add(new Link(it.Predecessor__c, it.Id, it.Dependency_Type__c,
                                   it.Lag_Days__c != null ? (Integer) it.Lag_Days__c : 0));
            }
        }
        return links;
    }

    // ── Topological sort (Kahn) over predecessor -> successor edges ────
    private static List<Id> topoSort(Map<Id, WBS_Item__c> itemMap, List<Link> links) {
        Map<Id, Integer> inDeg = new Map<Id, Integer>();
        Map<Id, List<Id>> adj  = new Map<Id, List<Id>>();
        for (Id id : itemMap.keySet()) { inDeg.put(id, 0); adj.put(id, new List<Id>()); }
        for (Link l : links) {
            adj.get(l.predId).add(l.succId);
            inDeg.put(l.succId, inDeg.get(l.succId) + 1);
        }

        List<Id> queue = new List<Id>();
        List<Id> result = new List<Id>();
        for (Id id : inDeg.keySet()) if (inDeg.get(id) == 0) queue.add(id);

        Integer idx = 0;
        while (idx < queue.size()) {
            Id curr = queue.get(idx++);
            result.add(curr);
            for (Id next : adj.get(curr)) {
                Integer deg = inDeg.get(next) - 1;
                inDeg.put(next, deg);
                if (deg == 0) queue.add(next);
            }
        }
        // Any items left out are in a cycle — append so they still get scheduled.
        Set<Id> seen = new Set<Id>(result);
        for (Id id : itemMap.keySet()) if (!seen.contains(id)) result.add(id);
        return result;
    }

    // ── Progress roll-up (budget-weighted, multi-pass until stable) ────
    private static void rollupProgress(List<WBS_Item__c> items, Map<Id, WBS_Item__c> itemMap, Map<Id, List<Id>> childMap) {
        for (Integer pass = 0; pass < 20; pass++) {
            Boolean changed = false;
            for (WBS_Item__c item : items) {
                List<Id> kids = childMap.get(item.Id);
                if (kids == null || kids.isEmpty()) continue;
                Decimal totalB = 0, weighted = 0;
                for (Id kid : kids) {
                    Decimal b = itemMap.get(kid).Budget__c  != null ? itemMap.get(kid).Budget__c  : 0;
                    Decimal p = itemMap.get(kid).Progress__c != null ? itemMap.get(kid).Progress__c : 0;
                    totalB   += b;
                    weighted += b * p;
                }
                Decimal newP = totalB > 0
                    ? (weighted / totalB).setScale(2)
                    : avgProgress(kids, itemMap);
                if (item.Progress__c != newP) { item.Progress__c = newP; changed = true; }
            }
            if (!changed) break;
        }
    }

    // ── Actual-date roll-up to summaries (bottom-up, multi-pass) ───────
    private static void rollupActuals(List<WBS_Item__c> items, Map<Id, List<Id>> childMap) {
        Map<Id, WBS_Item__c> byId = new Map<Id, WBS_Item__c>(items);
        for (Integer pass = 0; pass < 20; pass++) {
            Boolean changed = false;
            for (WBS_Item__c item : items) {
                List<Id> kids = childMap.get(item.Id);
                if (kids == null || kids.isEmpty()) continue;
                Date minStart = null, maxFinish = null;
                Boolean allFinished = true;
                for (Id kid : kids) {
                    WBS_Item__c c = byId.get(kid);
                    if (c.Actual_Start__c != null && (minStart == null || c.Actual_Start__c < minStart)) {
                        minStart = c.Actual_Start__c;
                    }
                    if (c.Actual_Finish__c == null) allFinished = false;
                    else if (maxFinish == null || c.Actual_Finish__c > maxFinish) maxFinish = c.Actual_Finish__c;
                }
                Date newFinish = allFinished ? maxFinish : null;
                if (item.Actual_Start__c != minStart || item.Actual_Finish__c != newFinish) {
                    item.Actual_Start__c  = minStart;
                    item.Actual_Finish__c = newFinish;
                    changed = true;
                }
            }
            if (!changed) break;
        }
    }

    private static Decimal avgProgress(List<Id> kids, Map<Id, WBS_Item__c> itemMap) {
        Decimal s = 0;
        for (Id k : kids) s += itemMap.get(k).Progress__c != null ? itemMap.get(k).Progress__c : 0;
        return kids.isEmpty() ? 0 : (s / kids.size()).setScale(2);
    }

    // ── Working-day helpers (Standard calendar: Mon–Fri) ──────────────
    // Reference Monday for day-of-week math (Apex Date has no native weekday).
    private static final Date MONDAY_REF = Date.newInstance(2020, 1, 6);

    private static Boolean isWeekend(Date d) {
        Integer dow = Math.mod(MONDAY_REF.daysBetween(d), 7); // 0=Mon … 5=Sat, 6=Sun
        if (dow < 0) dow += 7;
        return dow >= 5;
    }

    private static Date rollForward(Date d) {
        while (isWeekend(d)) d = d.addDays(1);
        return d;
    }

    // Calendar date for a working-day ordinal relative to origin (ordinal 0 = origin).
    private static Date dateForOrdinal(Date origin, Integer ord) {
        if (ord == null) return null;
        Date d = origin;
        Integer step = ord >= 0 ? 1 : -1;
        Integer remaining = Math.abs(ord);
        while (remaining > 0) {
            d = d.addDays(step);
            if (!isWeekend(d)) remaining--;
        }
        return d;
    }

    // ── Misc helpers ──────────────────────────────────────────────────
    private static Integer dur(WBS_Item__c item) {
        return item.Duration_Days__c != null && item.Duration_Days__c > 0
            ? (Integer) item.Duration_Days__c : 1;
    }
}
