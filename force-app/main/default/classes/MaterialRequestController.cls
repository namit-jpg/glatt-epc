public with sharing class MaterialRequestController {

    @AuraEnabled(cacheable=true)
    public static RequestBoard getAllRequests() {
        List<Material_Request__c> reqs = [
            SELECT Id, Name, Material_Name__c, Quantity__c, Unit__c, Required_Date__c,
                   Status__c, Notes__c, Rejection_Reason__c,
                   WBS_Item__c, WBS_Item__r.Name, WBS_Item__r.WBS_Code__c,
                   WBS_Item__r.Project__c, WBS_Item__r.Project__r.Name,
                   Product__c, Product__r.Name,
                   CreatedById, CreatedBy.Name,
                   Approved_By__c, Approved_By__r.Name,
                   (SELECT Id, Name, Status__c FROM RFQs__r ORDER BY CreatedDate DESC LIMIT 1)
            FROM Material_Request__c
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];
        RequestBoard board = new RequestBoard();
        for (Material_Request__c r : reqs) {
            board.requests.add(new RequestRow(r));
        }
        return board;
    }

    @AuraEnabled(cacheable=true)
    public static List<ProjectOption> getProjects() {
        List<ProjectOption> opts = new List<ProjectOption>();
        for (Project__c p : [SELECT Id, Name FROM Project__c ORDER BY Name ASC LIMIT 100]) {
            ProjectOption o = new ProjectOption();
            o.value = p.Id;
            o.label = p.Name;
            opts.add(o);
        }
        return opts;
    }

    @AuraEnabled(cacheable=true)
    public static RequestBoard getRequestsForProject(Id projectId) {
        List<Material_Request__c> reqs = [
            SELECT Id, Name, Material_Name__c, Quantity__c, Unit__c, Required_Date__c,
                   Status__c, Notes__c, Rejection_Reason__c,
                   WBS_Item__c, WBS_Item__r.Name, WBS_Item__r.WBS_Code__c,
                   WBS_Item__r.Project__c, WBS_Item__r.Project__r.Name,
                   Product__c, Product__r.Name,
                   CreatedById, CreatedBy.Name,
                   Approved_By__c, Approved_By__r.Name,
                   (SELECT Id, Name, Status__c, Vendor__c, Expected_Delivery__c, Estimated_Value__c
                    FROM RFQs__r ORDER BY CreatedDate DESC LIMIT 1)
            FROM Material_Request__c
            WHERE WBS_Item__r.Project__c = :projectId
            ORDER BY CreatedDate DESC
        ];

        List<RFQ__c> rfqs = [
            SELECT Id, Name, Status__c, Vendor__c, Expected_Delivery__c, Estimated_Value__c,
                   Notes__c, Material_Request__c, Material_Request__r.Name
            FROM RFQ__c
            WHERE Project__c = :projectId
            ORDER BY CreatedDate DESC
        ];

        RequestBoard board = new RequestBoard();
        for (Material_Request__c r : reqs) {
            board.requests.add(new RequestRow(r));
        }
        for (RFQ__c q : rfqs) {
            board.rfqs.add(new RfqRow(q));
        }
        return board;
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductOption> getProducts() {
        List<ProductOption> opts = new List<ProductOption>();
        for (Product2 p : [
            SELECT Id, Name, ProductCode, Family
            FROM Product2
            WHERE IsActive = true
            ORDER BY Name ASC
            LIMIT 500
        ]) {
            ProductOption o = new ProductOption();
            o.value       = p.Id;
            o.label       = (p.ProductCode != null ? '[' + p.ProductCode + '] ' : '') + p.Name;
            o.family      = p.Family;
            opts.add(o);
        }
        return opts;
    }

    @AuraEnabled(cacheable=true)
    public static List<WbsOption> getWbsItemsForProject(Id projectId) {
        List<WbsOption> opts = new List<WbsOption>();
        for (WBS_Item__c item : [
            SELECT Id, Name, WBS_Code__c
            FROM WBS_Item__c
            WHERE Project__c = :projectId
            ORDER BY WBS_Code__c ASC NULLS LAST, Name ASC
        ]) {
            WbsOption o = new WbsOption();
            o.value = item.Id;
            o.label = (item.WBS_Code__c != null ? item.WBS_Code__c + ' — ' : '') + item.Name;
            opts.add(o);
        }
        return opts;
    }

    @AuraEnabled
    public static Id createRequest(Id wbsItemId, Id productId, Decimal quantity,
                                   String unit, Date requiredDate, String notes) {
        try {
            Product2 prod = [SELECT Id, Name FROM Product2 WHERE Id = :productId LIMIT 1];
            Material_Request__c req = new Material_Request__c(
                WBS_Item__c      = wbsItemId,
                Product__c       = productId,
                Material_Name__c = prod.Name,
                Quantity__c      = quantity,
                Unit__c          = unit,
                Required_Date__c = requiredDate,
                Notes__c         = notes,
                Status__c        = 'Draft'
            );
            insert req;
            return req.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Could not create request: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void submitRequest(Id requestId) {
        try {
            Material_Request__c req = [SELECT Id, Status__c FROM Material_Request__c WHERE Id = :requestId LIMIT 1];
            if (req.Status__c != 'Draft') {
                throw new AuraHandledException('Only Draft requests can be submitted.');
            }
            req.Status__c = 'Submitted';
            update req;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not submit request: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id approveRequest(Id requestId) {
        try {
            Material_Request__c req = [
                SELECT Id, Status__c, Name, Material_Name__c, Quantity__c, Unit__c,
                       Required_Date__c, Notes__c,
                       WBS_Item__c, WBS_Item__r.Name, WBS_Item__r.WBS_Code__c,
                       WBS_Item__r.Project__c, WBS_Item__r.Project__r.Name,
                       CreatedBy.Name
                FROM Material_Request__c WHERE Id = :requestId LIMIT 1
            ];
            if (req.Status__c != 'Submitted') {
                throw new AuraHandledException('Only Submitted requests can be approved.');
            }
            req.Status__c      = 'Approved';
            req.Approved_By__c = UserInfo.getUserId();
            update req;

            String wbsLabel = (req.WBS_Item__r.WBS_Code__c != null
                ? req.WBS_Item__r.WBS_Code__c + ' — ' : '') + req.WBS_Item__r.Name;
            String qtyStr   = req.Quantity__c != null
                ? String.valueOf(req.Quantity__c.stripTrailingZeros().toPlainString())
                  + ' ' + (req.Unit__c ?? '') : '—';
            String reqDate  = req.Required_Date__c != null
                ? req.Required_Date__c.format() : '—';

            String notes = 'Material: '    + (req.Material_Name__c ?? '—') + '\n'
                         + 'Quantity: '    + qtyStr + '\n'
                         + 'Required By: ' + reqDate + '\n'
                         + 'WBS Item: '    + wbsLabel + '\n'
                         + 'Project: '     + (req.WBS_Item__r.Project__r?.Name ?? '—') + '\n'
                         + 'Requested By: '+ req.CreatedBy.Name + '\n'
                         + 'Request #: '   + req.Name;
            if (String.isNotBlank(req.Notes__c)) {
                notes += '\n\nRequester Notes:\n' + req.Notes__c;
            }

            RFQ__c rfq = new RFQ__c(
                Material_Request__c  = req.Id,
                Project__c           = req.WBS_Item__r.Project__c,
                WBS_Item__c          = req.WBS_Item__c,
                Status__c            = 'Draft',
                Expected_Delivery__c = req.Required_Date__c,
                Submission_Date__c   = Date.today(),
                Issued_By__c         = UserInfo.getUserId(),
                Notes__c             = notes
            );
            insert rfq;
            return rfq.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not approve request: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void rejectRequest(Id requestId, String reason) {
        try {
            Material_Request__c req = [SELECT Id, Status__c FROM Material_Request__c WHERE Id = :requestId LIMIT 1];
            if (req.Status__c != 'Submitted') {
                throw new AuraHandledException('Only Submitted requests can be rejected.');
            }
            req.Status__c         = 'Rejected';
            req.Rejection_Reason__c = reason;
            update req;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not reject request: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteRequest(Id requestId) {
        try {
            Material_Request__c req = [SELECT Id, Status__c FROM Material_Request__c WHERE Id = :requestId LIMIT 1];
            if (req.Status__c != 'Draft') {
                throw new AuraHandledException('Only Draft requests can be deleted.');
            }
            delete req;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not delete request: ' + e.getMessage());
        }
    }

    public class RequestBoard {
        @AuraEnabled public List<RequestRow> requests = new List<RequestRow>();
        @AuraEnabled public List<RfqRow>     rfqs     = new List<RfqRow>();
    }

    public class RequestRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  materialName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String  unit;
        @AuraEnabled public Date    requiredDate;
        @AuraEnabled public String  status;
        @AuraEnabled public String  notes;
        @AuraEnabled public Id      wbsItemId;
        @AuraEnabled public String  wbsItemName;
        @AuraEnabled public Id      projectId;
        @AuraEnabled public String  projectName;
        @AuraEnabled public Id      requestedById;
        @AuraEnabled public String  requestedByName;
        @AuraEnabled public String  approvedByName;
        @AuraEnabled public String  rejectionReason;
        @AuraEnabled public Id      productId;
        @AuraEnabled public String  productName;
        @AuraEnabled public Id      rfqId;
        @AuraEnabled public String  rfqName;

        public RequestRow(Material_Request__c r) {
            this.id              = r.Id;
            this.name            = r.Name;
            this.materialName    = r.Material_Name__c;
            this.quantity        = r.Quantity__c;
            this.unit            = r.Unit__c;
            this.requiredDate    = r.Required_Date__c;
            this.status          = r.Status__c;
            this.notes           = r.Notes__c;
            this.wbsItemId       = r.WBS_Item__c;
            this.wbsItemName     = formatWbsLabel(r.WBS_Item__r);
            this.projectId       = r.WBS_Item__r?.Project__c;
            this.projectName     = r.WBS_Item__r?.Project__r?.Name;
            this.requestedById   = r.CreatedById;
            this.requestedByName = r.CreatedBy.Name;
            this.approvedByName  = r.Approved_By__r?.Name;
            this.productId       = r.Product__c;
            this.productName     = r.Product__r?.Name;
            this.rejectionReason = r.Rejection_Reason__c;
            if (!r.RFQs__r.isEmpty()) {
                this.rfqId   = r.RFQs__r[0].Id;
                this.rfqName = r.RFQs__r[0].Name;
            }
        }
    }

    public class ProjectOption {
        @AuraEnabled public Id     value;
        @AuraEnabled public String label;
    }

    public class RfqRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  status;
        @AuraEnabled public String  vendor;
        @AuraEnabled public Date    expectedDelivery;
        @AuraEnabled public Decimal estimatedValue;
        @AuraEnabled public Id      materialRequestId;
        @AuraEnabled public String  materialRequestName;

        public RfqRow(RFQ__c q) {
            this.id                  = q.Id;
            this.name                = q.Name;
            this.status              = q.Status__c;
            this.vendor              = q.Vendor__c;
            this.expectedDelivery    = q.Expected_Delivery__c;
            this.estimatedValue      = q.Estimated_Value__c;
            this.materialRequestId   = q.Material_Request__c;
            this.materialRequestName = q.Material_Request__r?.Name;
        }
    }

    public class WbsOption {
        @AuraEnabled public Id     value;
        @AuraEnabled public String label;
    }

    public class ProductOption {
        @AuraEnabled public Id     value;
        @AuraEnabled public String label;
        @AuraEnabled public String family;
    }

    private static String formatWbsLabel(WBS_Item__c item) {
        if (item == null) return null;
        return (item.WBS_Code__c != null ? item.WBS_Code__c + ' ' : '') + item.Name;
    }
}
