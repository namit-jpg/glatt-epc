public with sharing class CPMEngine {

    public static void recalculate(Id projectId) {
        Project__c proj = [SELECT Id, Start_Date__c FROM Project__c WHERE Id = :projectId LIMIT 1];
        Date projectStart = proj.Start_Date__c != null ? proj.Start_Date__c : Date.today();

        List<WBS_Item__c> items = [
            SELECT Id, Name, WBS_Code__c, Duration_Days__c, Predecessor__c,
                   Dependency_Type__c, Lag_Days__c, Parent_WBS_Item__c,
                   Budget__c, Progress__c
            FROM WBS_Item__c
            WHERE Project__c = :projectId
            ORDER BY WBS_Code__c ASC NULLS LAST
        ];

        if (items.isEmpty()) return;

        Map<Id, WBS_Item__c> itemMap = new Map<Id, WBS_Item__c>(items);

        // ── Forward pass ──────────────────────────────────────────────
        List<Id> sorted = topoSort(items, itemMap);

        Map<Id, Date> es = new Map<Id, Date>(); // Early Start
        Map<Id, Date> ef = new Map<Id, Date>(); // Early Finish

        for (Id id : sorted) {
            WBS_Item__c item = itemMap.get(id);
            Integer dur = dur(item);
            Date earlyStart = projectStart;

            if (item.Predecessor__c != null && ef.containsKey(item.Predecessor__c)) {
                String dt  = depType(item);
                Integer lag = lag(item);

                if (dt == 'FS') {
                    earlyStart = ef.get(item.Predecessor__c).addDays(1 + lag);
                } else if (dt == 'SS') {
                    earlyStart = es.get(item.Predecessor__c).addDays(lag);
                } else if (dt == 'FF') {
                    earlyStart = ef.get(item.Predecessor__c).addDays(lag - dur + 1);
                } else if (dt == 'SF') {
                    earlyStart = es.get(item.Predecessor__c).addDays(lag - dur + 1);
                }
            }

            es.put(id, earlyStart);
            ef.put(id, earlyStart.addDays(dur - 1));
        }

        // ── Project end = max Early Finish ────────────────────────────
        Date projectEnd = projectStart;
        for (Date d : ef.values()) {
            if (d > projectEnd) projectEnd = d;
        }

        // ── Backward pass ─────────────────────────────────────────────
        Map<Id, Date> ls = new Map<Id, Date>(); // Late Start
        Map<Id, Date> lf = new Map<Id, Date>(); // Late Finish

        for (Id id : itemMap.keySet()) {
            Integer d = dur(itemMap.get(id));
            lf.put(id, projectEnd);
            ls.put(id, projectEnd.addDays(-(d - 1)));
        }

        // Successor map
        Map<Id, List<Id>> succs = new Map<Id, List<Id>>();
        for (WBS_Item__c item : items) {
            if (!succs.containsKey(item.Id)) succs.put(item.Id, new List<Id>());
            if (item.Predecessor__c != null && itemMap.containsKey(item.Predecessor__c)) {
                succs.get(item.Predecessor__c).add(item.Id);
            }
        }

        // Process reverse topological order
        for (Integer i = sorted.size() - 1; i >= 0; i--) {
            Id id = sorted.get(i);
            List<Id> children = succs.get(id);
            if (children == null || children.isEmpty()) continue;

            Integer d = dur(itemMap.get(id));
            Date minLF = null;

            for (Id succId : children) {
                WBS_Item__c succ = itemMap.get(succId);
                String dt   = depType(succ);
                Integer lag = lag(succ);
                Date lateF;

                if (dt == 'FS') {
                    lateF = ls.get(succId).addDays(-1 - lag);
                } else if (dt == 'SS') {
                    lateF = ls.get(succId).addDays(-lag).addDays(d - 1);
                } else if (dt == 'FF') {
                    lateF = lf.get(succId).addDays(-lag);
                } else { // SF
                    lateF = lf.get(succId).addDays(-lag).addDays(d - 1);
                }

                if (minLF == null || lateF < minLF) minLF = lateF;
            }

            if (minLF != null) {
                lf.put(id, minLF);
                ls.put(id, minLF.addDays(-(d - 1)));
            }
        }

        // ── Float & critical flag ─────────────────────────────────────
        for (WBS_Item__c item : items) {
            item.Early_Start__c  = es.get(item.Id);
            item.Early_Finish__c = ef.get(item.Id);
            item.Late_Start__c   = ls.get(item.Id);
            item.Late_Finish__c  = lf.get(item.Id);
            Integer floatDays    = es.get(item.Id).daysBetween(ls.get(item.Id));
            item.Float_Days__c   = floatDays;
            item.Is_Critical__c  = (floatDays <= 0);
        }

        // ── Progress roll-up (leaf → root) ────────────────────────────
        rollupProgress(items, itemMap);

        // ── Persist ───────────────────────────────────────────────────
        TriggerHelper.isRunning = true;
        update items;
        TriggerHelper.isRunning = false;

        // ── Project overall progress ──────────────────────────────────
        Set<Id> allIds = itemMap.keySet();
        Decimal totalBudget = 0, weightedProg = 0;
        for (WBS_Item__c item : items) {
            if (item.Parent_WBS_Item__c == null || !allIds.contains(item.Parent_WBS_Item__c)) {
                Decimal b = item.Budget__c != null ? item.Budget__c : 0;
                Decimal p = item.Progress__c != null ? item.Progress__c : 0;
                totalBudget += b;
                weightedProg += b * p;
            }
        }
        Decimal overall = totalBudget > 0 ? (weightedProg / totalBudget).setScale(2) : 0;
        TriggerHelper.isRunning = true;
        update new Project__c(Id = projectId, Overall_Progress__c = overall);
        TriggerHelper.isRunning = false;
    }

    // ── Topological sort (Kahn's algorithm on predecessor graph) ──────
    private static List<Id> topoSort(List<WBS_Item__c> items, Map<Id, WBS_Item__c> itemMap) {
        Map<Id, Integer> inDeg = new Map<Id, Integer>();
        Map<Id, List<Id>> adj  = new Map<Id, List<Id>>();

        for (WBS_Item__c item : items) {
            inDeg.put(item.Id, 0);
            adj.put(item.Id, new List<Id>());
        }
        for (WBS_Item__c item : items) {
            if (item.Predecessor__c != null && itemMap.containsKey(item.Predecessor__c)) {
                adj.get(item.Predecessor__c).add(item.Id);
                inDeg.put(item.Id, inDeg.get(item.Id) + 1);
            }
        }

        List<Id> queue  = new List<Id>();
        List<Id> result = new List<Id>();
        for (Id id : inDeg.keySet()) {
            if (inDeg.get(id) == 0) queue.add(id);
        }

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

        // Handle any cycles (add remaining items)
        Set<Id> seen = new Set<Id>(result);
        for (Id id : itemMap.keySet()) {
            if (!seen.contains(id)) result.add(id);
        }
        return result;
    }

    // ── Progress roll-up (multi-pass until stable) ────────────────────
    private static void rollupProgress(List<WBS_Item__c> items, Map<Id, WBS_Item__c> itemMap) {
        Map<Id, List<Id>> childMap = new Map<Id, List<Id>>();
        for (WBS_Item__c item : items) {
            if (!childMap.containsKey(item.Id)) childMap.put(item.Id, new List<Id>());
            if (item.Parent_WBS_Item__c != null && itemMap.containsKey(item.Parent_WBS_Item__c)) {
                childMap.get(item.Parent_WBS_Item__c).add(item.Id);
            }
        }

        for (Integer pass = 0; pass < 10; pass++) {
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

    private static Decimal avgProgress(List<Id> kids, Map<Id, WBS_Item__c> itemMap) {
        Decimal s = 0;
        for (Id k : kids) s += itemMap.get(k).Progress__c != null ? itemMap.get(k).Progress__c : 0;
        return kids.isEmpty() ? 0 : (s / kids.size()).setScale(2);
    }

    // ── Helpers ───────────────────────────────────────────────────────
    private static Integer dur(WBS_Item__c item) {
        return item.Duration_Days__c != null && item.Duration_Days__c > 0
            ? (Integer) item.Duration_Days__c : 1;
    }
    private static String depType(WBS_Item__c item) {
        return item.Dependency_Type__c != null ? item.Dependency_Type__c : 'FS';
    }
    private static Integer lag(WBS_Item__c item) {
        return item.Lag_Days__c != null ? (Integer) item.Lag_Days__c : 0;
    }
}
