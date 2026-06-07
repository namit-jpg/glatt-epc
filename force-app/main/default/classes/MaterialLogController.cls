/**
 * Serves material log data for the Materials tab on the project record page:
 * cost totals by cost type, per-WBS-item budget consumption, and the raw log.
 */
public with sharing class MaterialLogController {

    /**
     * Returns all material logs for a project (via its WBS items) plus
     * cost-type totals and a per-WBS-item budget-vs-actual summary.
     *
     * @param projectId The Project__c record Id
     * @return MaterialBoard with log rows, WBS summaries, and totals
     */
    @AuraEnabled(cacheable=true)
    public static MaterialBoard getMaterialBoard(Id projectId) {
        List<Material_Log__c> logs = [
            SELECT Id, Name, Material_Name__c, Quantity__c, Unit__c,
                   Cost_Type__c, Rate__c, Total_Cost__c,
                   WBS_Item__c, WBS_Item__r.Name, WBS_Item__r.WBS_Code__c,
                   WBS_Item__r.Budget__c
            FROM Material_Log__c
            WHERE WBS_Item__r.Project__c = :projectId
            ORDER BY WBS_Item__r.WBS_Code__c ASC NULLS LAST, Material_Name__c ASC
        ];

        MaterialBoard board = new MaterialBoard();
        Map<Id, WbsCostSummary> summariesByWbsItem = new Map<Id, WbsCostSummary>();

        for (Material_Log__c log : logs) {
            board.rows.add(new MaterialRow(log));

            Decimal cost = zeroIfNull(log.Total_Cost__c);
            board.grandTotal += cost;
            if (log.Cost_Type__c == 'Work') {
                board.workTotal += cost;
            } else if (log.Cost_Type__c == 'Material') {
                board.materialTotal += cost;
            } else {
                board.costTotal += cost;
            }

            WbsCostSummary summary = summariesByWbsItem.get(log.WBS_Item__c);
            if (summary == null) {
                summary = new WbsCostSummary(log.WBS_Item__r);
                summariesByWbsItem.put(log.WBS_Item__c, summary);
            }
            summary.totalCost += cost;
            summary.entryCount++;
        }

        for (WbsCostSummary summary : summariesByWbsItem.values()) {
            if (summary.budget != null && summary.budget > 0) {
                summary.percentOfBudget = (summary.totalCost / summary.budget * 100).setScale(0);
                summary.isOverBudget = summary.totalCost > summary.budget;
            }
        }

        board.wbsSummaries = summariesByWbsItem.values();
        return board;
    }

    /**
     * Deletes a single material log entry.
     *
     * @param materialId The Material_Log__c record Id
     */
    @AuraEnabled
    public static void deleteMaterial(Id materialId) {
        try {
            delete [SELECT Id FROM Material_Log__c WHERE Id = :materialId WITH SECURITY_ENFORCED LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Could not delete material entry: ' + e.getMessage());
        }
    }

    private static Decimal zeroIfNull(Decimal value) {
        return value != null ? value : 0;
    }

    public class MaterialBoard {
        @AuraEnabled public List<MaterialRow> rows = new List<MaterialRow>();
        @AuraEnabled public List<WbsCostSummary> wbsSummaries = new List<WbsCostSummary>();
        @AuraEnabled public Decimal workTotal = 0;
        @AuraEnabled public Decimal materialTotal = 0;
        @AuraEnabled public Decimal costTotal = 0;
        @AuraEnabled public Decimal grandTotal = 0;
    }

    public class MaterialRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  materialName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String  unit;
        @AuraEnabled public String  costType;
        @AuraEnabled public Decimal rate;
        @AuraEnabled public Decimal totalCost;
        @AuraEnabled public Id      wbsItemId;
        @AuraEnabled public String  wbsItemName;

        public MaterialRow(Material_Log__c log) {
            this.id           = log.Id;
            this.name         = log.Name;
            this.materialName = log.Material_Name__c;
            this.quantity     = log.Quantity__c;
            this.unit         = log.Unit__c;
            this.costType     = log.Cost_Type__c;
            this.rate         = log.Rate__c;
            this.totalCost    = log.Total_Cost__c;
            this.wbsItemId    = log.WBS_Item__c;
            this.wbsItemName  = formatWbsLabel(log.WBS_Item__r);
        }
    }

    public class WbsCostSummary {
        @AuraEnabled public Id      wbsItemId;
        @AuraEnabled public String  wbsItemName;
        @AuraEnabled public Decimal budget;
        @AuraEnabled public Decimal totalCost = 0;
        @AuraEnabled public Integer entryCount = 0;
        @AuraEnabled public Decimal percentOfBudget;
        @AuraEnabled public Boolean isOverBudget = false;

        public WbsCostSummary(WBS_Item__c item) {
            this.wbsItemId   = item.Id;
            this.wbsItemName = formatWbsLabel(item);
            this.budget      = item.Budget__c;
        }
    }

    private static String formatWbsLabel(WBS_Item__c item) {
        if (item == null) return null;
        return (item.WBS_Code__c != null ? item.WBS_Code__c + ' ' : '') + item.Name;
    }
}
