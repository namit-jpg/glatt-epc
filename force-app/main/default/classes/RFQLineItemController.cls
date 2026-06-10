/**
 * Serves RFQ Line Item (product) data for the Line Items related list on the
 * RFQ record page. Mirrors the established controller pattern: with sharing,
 * cacheable wire returning @AuraEnabled wrapper rows (no SObjects to client),
 * and a small delete method. Creates/edits are done client-side via
 * lightning-record-edit-form.
 */
public with sharing class RFQLineItemController {

    /**
     * Returns the line items for an RFQ plus a roll-up total.
     *
     * @param rfqId The RFQ__c record Id
     * @return LineItemBoard with rows and total value
     */
    @AuraEnabled(cacheable=true)
    public static LineItemBoard getLineItems(Id rfqId) {
        List<RFQ_Line_Item__c> items = [
            SELECT Id, Name, Material_Name__c, Product__c, Product__r.Name,
                   Quantity__c, Unit__c, Unit_Price__c, Total_Price__c, Notes__c
            FROM RFQ_Line_Item__c
            WHERE RFQ__c = :rfqId
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
        ];

        LineItemBoard board = new LineItemBoard();
        for (RFQ_Line_Item__c li : items) {
            board.rows.add(new LineItemRow(li));
            board.totalValue += (li.Total_Price__c == null ? 0 : li.Total_Price__c);
        }
        return board;
    }

    /**
     * Deletes a single RFQ line item.
     *
     * @param lineItemId The RFQ_Line_Item__c record Id
     */
    @AuraEnabled
    public static void deleteLineItem(Id lineItemId) {
        delete [SELECT Id FROM RFQ_Line_Item__c WHERE Id = :lineItemId WITH SECURITY_ENFORCED LIMIT 1];
    }

    public class LineItemBoard {
        @AuraEnabled public List<LineItemRow> rows = new List<LineItemRow>();
        @AuraEnabled public Decimal totalValue = 0;
    }

    public class LineItemRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String materialName;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String unit;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal totalPrice;
        @AuraEnabled public String notes;

        public LineItemRow(RFQ_Line_Item__c li) {
            this.id           = li.Id;
            this.name         = li.Name;
            this.materialName = li.Material_Name__c;
            this.productName  = li.Product__r != null ? li.Product__r.Name : null;
            this.quantity     = li.Quantity__c;
            this.unit         = li.Unit__c;
            this.unitPrice    = li.Unit_Price__c;
            this.totalPrice   = li.Total_Price__c;
            this.notes        = li.Notes__c;
        }
    }
}
