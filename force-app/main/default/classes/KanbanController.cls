public with sharing class KanbanController {

    @AuraEnabled(cacheable=true)
    public static List<KanbanCard> getWorkPackages(Id projectId) {
        List<Work_Package__c> wps = [
            SELECT Id, Name, Status__c, Planned_Start__c, Planned_End__c,
                   Assigned_To__c, Assigned_To__r.Name,
                   WBS_Item__c, WBS_Item__r.Name, WBS_Item__r.WBS_Code__c
            FROM Work_Package__c
            WHERE WBS_Item__r.Project__c = :projectId
            ORDER BY WBS_Item__r.WBS_Code__c ASC NULLS LAST, Name ASC
        ];

        List<KanbanCard> cards = new List<KanbanCard>();
        for (Work_Package__c wp : wps) {
            KanbanCard c = new KanbanCard();
            c.id           = wp.Id;
            c.name         = wp.Name;
            c.status       = wp.Status__c;
            c.plannedStart = wp.Planned_Start__c;
            c.plannedEnd   = wp.Planned_End__c;
            c.assigneeId   = wp.Assigned_To__c;
            c.assigneeName = wp.Assigned_To__c != null ? wp.Assigned_To__r.Name : null;
            c.wbsId        = wp.WBS_Item__c;
            c.wbsName      = wp.WBS_Item__r.Name;
            c.wbsCode      = wp.WBS_Item__r.WBS_Code__c;
            cards.add(c);
        }
        return cards;
    }

    @AuraEnabled
    public static void updateStatus(Id workPackageId, String newStatus) {
        update new Work_Package__c(Id = workPackageId, Status__c = newStatus);
    }

    public class KanbanCard {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Date   plannedStart;
        @AuraEnabled public Date   plannedEnd;
        @AuraEnabled public Id     assigneeId;
        @AuraEnabled public String assigneeName;
        @AuraEnabled public Id     wbsId;
        @AuraEnabled public String wbsName;
        @AuraEnabled public String wbsCode;
    }
}
