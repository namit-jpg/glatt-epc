trigger WBSItemTrigger on WBS_Item__c (after insert, after update, after delete, after undelete) {
    if (TriggerHelper.isRunning) return;

    Set<Id> projectIds = new Set<Id>();
    List<WBS_Item__c> records = Trigger.isDelete ? Trigger.old : Trigger.new;
    for (WBS_Item__c item : records) {
        if (item.Project__c != null) projectIds.add(item.Project__c);
    }

    // Successor-side dependency links cascade with the master-detail; clean up any
    // links that pointed to a deleted item as their predecessor (lookup, not cascaded).
    if (Trigger.isDelete) {
        List<WBS_Dependency__c> orphans = [
            SELECT Id FROM WBS_Dependency__c WHERE Predecessor__c IN :Trigger.oldMap.keySet()
        ];
        if (!orphans.isEmpty()) delete orphans;
    }

    for (Id projectId : projectIds) {
        CPMEngine.recalculate(projectId);
    }
}
