public with sharing class WBSTreeController {

    @AuraEnabled(cacheable=true)
    public static List<WBSNode> getWBSTree(Id projectId) {
        List<WBS_Item__c> allItems = [
            SELECT Id, Name, WBS_Code__c, Level__c, Duration_Days__c,
                   Budget__c, Progress__c, Start_Date__c, End_Date__c,
                   Early_Start__c, Early_Finish__c, Float_Days__c, Is_Critical__c,
                   Actual_Start__c, Actual_Finish__c,
                   Parent_WBS_Item__c,
                   Predecessor__c, Predecessor__r.WBS_Code__c,
                   Dependency_Type__c, Lag_Days__c,
                   (SELECT Id FROM Predecessor_Links__r)
            FROM WBS_Item__c
            WHERE Project__c = :projectId
            ORDER BY WBS_Code__c ASC NULLS LAST
        ];

        Map<Id, WBSNode> nodeMap = new Map<Id, WBSNode>();
        for (WBS_Item__c item : allItems) {
            nodeMap.put(item.Id, new WBSNode(item));
        }

        List<WBSNode> roots = new List<WBSNode>();
        for (WBS_Item__c item : allItems) {
            WBSNode node = nodeMap.get(item.Id);
            if (item.Parent_WBS_Item__c != null && nodeMap.containsKey(item.Parent_WBS_Item__c)) {
                nodeMap.get(item.Parent_WBS_Item__c).children.add(node);
            } else {
                roots.add(node);
            }
        }
        return roots;
    }

    @AuraEnabled(cacheable=true)
    public static List<GanttTask> getWBSFlat(Id projectId) {
        List<WBS_Item__c> items = [
            SELECT Id, Name, WBS_Code__c, Start_Date__c, End_Date__c,
                   Early_Start__c, Early_Finish__c, Actual_Start__c, Actual_Finish__c,
                   Progress__c, Predecessor__c, Is_Critical__c
            FROM WBS_Item__c
            WHERE Project__c = :projectId
              AND (Start_Date__c != null OR Early_Start__c != null)
              AND (End_Date__c   != null OR Early_Finish__c != null)
            ORDER BY WBS_Code__c ASC NULLS LAST
        ];

        // All predecessor ids per task: junction links + legacy single lookup.
        Map<Id, List<String>> predIds = new Map<Id, List<String>>();
        for (WBS_Dependency__c d : [
                SELECT Successor__c, Predecessor__c
                FROM WBS_Dependency__c
                WHERE Successor__r.Project__c = :projectId
                  AND Predecessor__c != null AND Successor__c != null
        ]) {
            if (!predIds.containsKey(d.Successor__c)) predIds.put(d.Successor__c, new List<String>());
            predIds.get(d.Successor__c).add(String.valueOf(d.Predecessor__c));
        }

        List<GanttTask> tasks = new List<GanttTask>();
        for (WBS_Item__c item : items) {
            Date s = item.Early_Start__c  != null ? item.Early_Start__c  : item.Start_Date__c;
            Date e = item.Early_Finish__c != null ? item.Early_Finish__c : item.End_Date__c;
            if (s == null || e == null) continue;

            Set<String> deps = new Set<String>();
            if (predIds.containsKey(item.Id)) deps.addAll(predIds.get(item.Id));
            if (item.Predecessor__c != null) deps.add(String.valueOf(item.Predecessor__c));

            GanttTask t = new GanttTask();
            t.id           = item.Id;
            t.name         = (item.WBS_Code__c != null ? item.WBS_Code__c + ' ' : '') + item.Name;
            t.start        = String.valueOf(s);
            t.endDate      = String.valueOf(e);
            t.progress     = item.Progress__c != null ? item.Progress__c : 0;
            // Frappe Gantt accepts a comma-separated list of predecessor ids.
            t.dependencies = String.join(new List<String>(deps), ',');
            t.isCritical   = item.Is_Critical__c;
            t.actualStart  = item.Actual_Start__c  != null ? String.valueOf(item.Actual_Start__c)  : null;
            t.actualFinish = item.Actual_Finish__c != null ? String.valueOf(item.Actual_Finish__c) : null;
            tasks.add(t);
        }
        return tasks;
    }

    @AuraEnabled
    public static void runCPM(Id projectId) {
        CPMEngine.recalculate(projectId);
    }

    @AuraEnabled
    public static void deleteWBSItem(Id itemId) {
        delete [SELECT Id FROM WBS_Item__c WHERE Id = :itemId WITH SECURITY_ENFORCED LIMIT 1];
    }

    @AuraEnabled
    public static void saveProgress(Id itemId, Decimal progressPct, Id projectId) {
        WBS_Item__c item = new WBS_Item__c(Id = itemId, Progress__c = progressPct);
        update item;
        CPMEngine.recalculate(projectId);
    }

    public class GanttTask {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  start;
        @AuraEnabled public String  endDate;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public String  dependencies;
        @AuraEnabled public Boolean isCritical;
        @AuraEnabled public String  actualStart;
        @AuraEnabled public String  actualFinish;
    }

    @AuraEnabled(cacheable=true)
    public static List<DependencyRow> getDependencies(Id wbsItemId) {
        List<DependencyRow> rows = new List<DependencyRow>();
        for (WBS_Dependency__c d : [
                SELECT Id, Predecessor__c, Predecessor__r.Name, Predecessor__r.WBS_Code__c,
                       Dependency_Type__c, Lag_Days__c
                FROM WBS_Dependency__c
                WHERE Successor__c = :wbsItemId AND Predecessor__c != null
                ORDER BY Predecessor__r.WBS_Code__c ASC NULLS LAST
        ]) {
            DependencyRow r = new DependencyRow();
            r.id              = d.Id;
            r.predecessorId   = d.Predecessor__c;
            r.predecessorName = d.Predecessor__r.Name;
            r.predecessorCode = d.Predecessor__r.WBS_Code__c;
            r.dependencyType  = d.Dependency_Type__c;
            r.lagDays         = d.Lag_Days__c;
            rows.add(r);
        }
        return rows;
    }

    @AuraEnabled
    public static void deleteDependency(Id dependencyId) {
        delete [SELECT Id FROM WBS_Dependency__c WHERE Id = :dependencyId WITH SECURITY_ENFORCED LIMIT 1];
    }

    public class DependencyRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public Id      predecessorId;
        @AuraEnabled public String  predecessorName;
        @AuraEnabled public String  predecessorCode;
        @AuraEnabled public String  dependencyType;
        @AuraEnabled public Decimal lagDays;
    }

    public class WBSNode {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  wbsCode;
        @AuraEnabled public Decimal level;
        @AuraEnabled public Decimal durationDays;
        @AuraEnabled public Decimal budget;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Date    startDate;
        @AuraEnabled public Date    endDate;
        @AuraEnabled public Date    earlyStart;
        @AuraEnabled public Date    earlyFinish;
        @AuraEnabled public Date    actualStart;
        @AuraEnabled public Date    actualFinish;
        @AuraEnabled public Decimal floatDays;
        @AuraEnabled public Boolean isCritical;
        @AuraEnabled public String  predecessorCode;
        @AuraEnabled public String  dependencyType;
        @AuraEnabled public Decimal lagDays;
        @AuraEnabled public Integer predecessorCount;
        @AuraEnabled public List<WBSNode> children = new List<WBSNode>();

        public WBSNode(WBS_Item__c item) {
            this.id              = item.Id;
            this.name            = item.Name;
            this.wbsCode         = item.WBS_Code__c;
            this.level           = item.Level__c;
            this.durationDays    = item.Duration_Days__c;
            this.budget          = item.Budget__c;
            this.progress        = item.Progress__c;
            this.startDate       = item.Start_Date__c;
            this.endDate         = item.End_Date__c;
            this.earlyStart      = item.Early_Start__c;
            this.earlyFinish     = item.Early_Finish__c;
            this.actualStart     = item.Actual_Start__c;
            this.actualFinish    = item.Actual_Finish__c;
            this.floatDays       = item.Float_Days__c;
            this.isCritical      = item.Is_Critical__c;
            this.predecessorCode = item.Predecessor__c != null ? item.Predecessor__r.WBS_Code__c : null;
            this.dependencyType  = item.Dependency_Type__c;
            this.lagDays         = item.Lag_Days__c;
            this.predecessorCount = (item.Predecessor_Links__r != null ? item.Predecessor_Links__r.size() : 0)
                                    + (item.Predecessor__c != null ? 1 : 0);
        }
    }
}
