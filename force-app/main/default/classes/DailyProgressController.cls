public with sharing class DailyProgressController {

    @AuraEnabled(cacheable=true)
    public static ProgressBoard getProgressBoard(Id projectId) {
        List<Work_Package__c> wps = [
            SELECT Id, Name, WP_Code__c, Status__c, Planned_Start__c, Planned_End__c,
                   Assigned_To__r.Name,
                   WBS_Item__c, WBS_Item__r.Name, WBS_Item__r.WBS_Code__c
            FROM Work_Package__c
            WHERE WBS_Item__r.Project__c = :projectId
            ORDER BY WBS_Item__r.WBS_Code__c ASC NULLS LAST, Name ASC
        ];

        ProgressBoard board = new ProgressBoard();
        if (wps.isEmpty()) return board;

        Set<Id> wpIds = new Map<Id, Work_Package__c>(wps).keySet();

        List<Daily_Progress__c> allEntries = [
            SELECT Id, Name, Work_Package__c, Progress_Date__c,
                   Percent_Complete_Day__c, Weather__c, Notes__c,
                   Logged_By__r.Name
            FROM Daily_Progress__c
            WHERE Work_Package__c IN :wpIds
            ORDER BY Work_Package__c ASC, Progress_Date__c DESC, CreatedDate DESC
        ];

        Map<Id, List<ProgressEntry>> entriesByWp = new Map<Id, List<ProgressEntry>>();
        Map<Id, Decimal> latestPctByWp = new Map<Id, Decimal>();

        for (Daily_Progress__c dp : allEntries) {
            if (!entriesByWp.containsKey(dp.Work_Package__c)) {
                entriesByWp.put(dp.Work_Package__c, new List<ProgressEntry>());
            }
            List<ProgressEntry> bucket = entriesByWp.get(dp.Work_Package__c);
            if (!latestPctByWp.containsKey(dp.Work_Package__c) && dp.Percent_Complete_Day__c != null) {
                latestPctByWp.put(dp.Work_Package__c, dp.Percent_Complete_Day__c);
            }
            if (bucket.size() < 5) {
                bucket.add(new ProgressEntry(dp));
            }
        }

        Map<Id, WpCard> cardById = new Map<Id, WpCard>();
        for (Work_Package__c wp : wps) {
            WpCard card = new WpCard(wp);
            card.entries = entriesByWp.containsKey(wp.Id) ? entriesByWp.get(wp.Id) : new List<ProgressEntry>();
            card.latestPercent = latestPctByWp.get(wp.Id);
            cardById.put(wp.Id, card);
            board.wpCards.add(card);
        }

        return board;
    }

    @AuraEnabled
    public static void deleteProgress(Id progressId) {
        try {
            delete [SELECT Id FROM Daily_Progress__c WHERE Id = :progressId WITH SECURITY_ENFORCED LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Could not delete entry: ' + e.getMessage());
        }
    }

    public class ProgressBoard {
        @AuraEnabled public List<WpCard> wpCards = new List<WpCard>();
    }

    public class WpCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Date plannedStart;
        @AuraEnabled public Date plannedEnd;
        @AuraEnabled public String assignedTo;
        @AuraEnabled public Id wbsItemId;
        @AuraEnabled public String wbsItemName;
        @AuraEnabled public Decimal latestPercent;
        @AuraEnabled public List<ProgressEntry> entries;

        public WpCard(Work_Package__c wp) {
            this.id          = wp.Id;
            this.name        = DailyProgressController.buildWpDisplayName(wp);
            this.status      = wp.Status__c;
            this.plannedStart = wp.Planned_Start__c;
            this.plannedEnd  = wp.Planned_End__c;
            this.assignedTo  = wp.Assigned_To__r?.Name;
            this.wbsItemId   = wp.WBS_Item__c;
            this.wbsItemName = (wp.WBS_Item__r.WBS_Code__c != null ? wp.WBS_Item__r.WBS_Code__c + ' ' : '')
                               + wp.WBS_Item__r.Name;
        }
    }

    public class ProgressEntry {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public Date    progressDate;
        @AuraEnabled public Decimal percentCompleteDay;
        @AuraEnabled public String  weather;
        @AuraEnabled public String  notes;
        @AuraEnabled public String  loggedBy;

        public ProgressEntry(Daily_Progress__c dp) {
            this.id                 = dp.Id;
            this.name               = dp.Name;
            this.progressDate       = dp.Progress_Date__c;
            this.percentCompleteDay = dp.Percent_Complete_Day__c;
            this.weather            = dp.Weather__c;
            this.notes              = dp.Notes__c;
            this.loggedBy           = dp.Logged_By__r?.Name;
        }
    }

    private static String buildWpDisplayName(Work_Package__c wp) {
        if (wp.WBS_Item__r.WBS_Code__c != null) {
            return wp.WBS_Item__r.WBS_Code__c;
        }
        return wp.Name;
    }
}
