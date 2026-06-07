trigger WBSItemTrigger on WBS_Item__c (after insert, after update, after delete, after undelete) {
    if (TriggerHelper.isRunning) return;

    Set<Id> projectIds = new Set<Id>();
    List<WBS_Item__c> records = Trigger.isDelete ? Trigger.old : Trigger.new;
    for (WBS_Item__c item : records) {
        if (item.Project__c != null) projectIds.add(item.Project__c);
    }

    for (Id projectId : projectIds) {
        CPMEngine.recalculate(projectId);
    }
}
