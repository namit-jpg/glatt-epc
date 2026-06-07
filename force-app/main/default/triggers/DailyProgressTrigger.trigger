trigger DailyProgressTrigger on Daily_Progress__c (after insert, after update, after delete, after undelete) {
    if (TriggerHelper.isRunning) return;

    Set<Id> wpIds = new Set<Id>();
    List<Daily_Progress__c> records = Trigger.isDelete ? Trigger.old : Trigger.new;
    for (Daily_Progress__c dp : records) {
        if (dp.Work_Package__c != null) wpIds.add(dp.Work_Package__c);
    }
    if (wpIds.isEmpty()) return;

    // Resolve WBS items for affected work packages
    Set<Id> wbsIds = new Set<Id>();
    Map<Id, Id> wpToWbs = new Map<Id, Id>();
    for (Work_Package__c wp : [SELECT Id, WBS_Item__c FROM Work_Package__c WHERE Id IN :wpIds]) {
        if (wp.WBS_Item__c != null) {
            wpToWbs.put(wp.Id, wp.WBS_Item__c);
            wbsIds.add(wp.WBS_Item__c);
        }
    }
    if (wbsIds.isEmpty()) return;

    // All work packages under the affected WBS items
    List<Work_Package__c> allWps = [SELECT Id, WBS_Item__c FROM Work_Package__c WHERE WBS_Item__c IN :wbsIds];
    Set<Id> allWpIds = new Set<Id>();
    Map<Id, List<Id>> wbsToWps = new Map<Id, List<Id>>();
    for (Work_Package__c wp : allWps) {
        allWpIds.add(wp.Id);
        if (!wbsToWps.containsKey(wp.WBS_Item__c)) wbsToWps.put(wp.WBS_Item__c, new List<Id>());
        wbsToWps.get(wp.WBS_Item__c).add(wp.Id);
    }

    // Latest Percent_Complete_Day per work package (most recent date wins)
    Map<Id, Decimal> latestPctByWp = new Map<Id, Decimal>();
    for (Daily_Progress__c dp : [
        SELECT Work_Package__c, Percent_Complete_Day__c
        FROM Daily_Progress__c
        WHERE Work_Package__c IN :allWpIds AND Percent_Complete_Day__c != null
        ORDER BY Work_Package__c ASC, Progress_Date__c DESC NULLS LAST, CreatedDate DESC
    ]) {
        if (!latestPctByWp.containsKey(dp.Work_Package__c)) {
            latestPctByWp.put(dp.Work_Package__c, dp.Percent_Complete_Day__c);
        }
    }

    // Compute average latest progress per WBS item and update
    List<WBS_Item__c> updates = new List<WBS_Item__c>();
    for (Id wbsId : wbsIds) {
        List<Id> wps = wbsToWps.get(wbsId);
        if (wps == null || wps.isEmpty()) continue;

        Decimal total = 0;
        Integer count = 0;
        for (Id wpId : wps) {
            if (latestPctByWp.containsKey(wpId)) {
                total += latestPctByWp.get(wpId);
                count++;
            }
        }
        if (count > 0) {
            updates.add(new WBS_Item__c(Id = wbsId, Progress__c = (total / count).setScale(2)));
        }
    }

    if (!updates.isEmpty()) {
        update updates; // fires WBSItemTrigger -> CPMEngine
    }
}
