public with sharing class WBSTreeController {

    @AuraEnabled(cacheable=true)
    public static List<WBSNode> getWBSTree(Id projectId) {
        List<WBS_Item__c> allItems = [
            SELECT Id, Name, WBS_Code__c, Level__c, Duration_Days__c,
                   Budget__c, Progress__c, Start_Date__c, End_Date__c,
                   Early_Start__c, Early_Finish__c, Float_Days__c, Is_Critical__c,
                   Parent_WBS_Item__c,
                   Predecessor__c, Predecessor__r.WBS_Code__c,
                   Dependency_Type__c, Lag_Days__c
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
                   Early_Start__c, Early_Finish__c, Progress__c,
                   Predecessor__c, Is_Critical__c
            FROM WBS_Item__c
            WHERE Project__c = :projectId
              AND (Start_Date__c != null OR Early_Start__c != null)
              AND (End_Date__c   != null OR Early_Finish__c != null)
            ORDER BY WBS_Code__c ASC NULLS LAST
        ];

        List<GanttTask> tasks = new List<GanttTask>();
        for (WBS_Item__c item : items) {
            Date s = item.Early_Start__c  != null ? item.Early_Start__c  : item.Start_Date__c;
            Date e = item.Early_Finish__c != null ? item.Early_Finish__c : item.End_Date__c;
            if (s == null || e == null) continue;

            GanttTask t = new GanttTask();
            t.id           = item.Id;
            t.name         = (item.WBS_Code__c != null ? item.WBS_Code__c + ' ' : '') + item.Name;
            t.start        = String.valueOf(s);
            t.endDate      = String.valueOf(e);
            t.progress     = item.Progress__c != null ? item.Progress__c : 0;
            // Both branches must be String: a mixed Id/String ternary unifies to Id
            // and Id.valueOf('') throws "Invalid id:" for rows without a predecessor
            t.dependencies = item.Predecessor__c != null ? String.valueOf(item.Predecessor__c) : '';
            t.isCritical   = item.Is_Critical__c;
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
        @AuraEnabled public Decimal floatDays;
        @AuraEnabled public Boolean isCritical;
        @AuraEnabled public String  predecessorCode;
        @AuraEnabled public String  dependencyType;
        @AuraEnabled public Decimal lagDays;
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
            this.floatDays       = item.Float_Days__c;
            this.isCritical      = item.Is_Critical__c;
            this.predecessorCode = item.Predecessor__c != null ? item.Predecessor__r.WBS_Code__c : null;
            this.dependencyType  = item.Dependency_Type__c;
            this.lagDays         = item.Lag_Days__c;
        }
    }
}
