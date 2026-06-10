/**
 * Serves resource allocation data for the Resource Plan (project record page)
 * and the org-wide Resource Dashboard utilization heatmap.
 */
public with sharing class ResourceAllocationController {

    private static final Integer OVER_ALLOCATION_THRESHOLD = 100;
    private static final Integer WARN_THRESHOLD = 80;
    private static final Integer DEFAULT_MONTHS = 6;
    private static final Integer MAX_MONTHS = 12;

    /**
     * Returns all allocations for a project plus a per-resource summary that
     * includes each resource's total load across ALL projects (active today),
     * so over-allocation is visible even when caused by other projects.
     *
     * @param projectId The Project__c record Id
     * @return ResourcePlan with allocation rows and resource summaries
     */
    @AuraEnabled(cacheable=true)
    public static ResourcePlan getResourcePlan(Id projectId) {
        List<Resource_Allocation__c> allocations = [
            SELECT Id, Name, Resource__c, Resource__r.Name, Role__c,
                   Allocation_Percent__c, Start_Date__c, End_Date__c,
                   WBS_Item__c, WBS_Item__r.Name, WBS_Item__r.WBS_Code__c
            FROM Resource_Allocation__c
            WHERE Project__c = :projectId
            ORDER BY Resource__r.Name ASC, Start_Date__c ASC NULLS LAST
        ];

        ResourcePlan plan = new ResourcePlan();
        Set<Id> resourceIds = new Set<Id>();
        Map<Id, ResourceSummary> summariesByResource = new Map<Id, ResourceSummary>();

        for (Resource_Allocation__c alloc : allocations) {
            plan.allocations.add(new AllocationRow(alloc));
            if (alloc.Resource__c == null) continue;
            resourceIds.add(alloc.Resource__c);

            ResourceSummary summary = summariesByResource.get(alloc.Resource__c);
            if (summary == null) {
                summary = new ResourceSummary(alloc.Resource__c, alloc.Resource__r.Name, alloc.Role__c);
                summariesByResource.put(alloc.Resource__c, summary);
            }
            summary.projectAllocation += zeroIfNull(alloc.Allocation_Percent__c);
        }

        // Total load per resource across all projects, for allocations active today
        Date today = Date.today();
        for (AggregateResult agg : [
            SELECT Resource__c resourceId, SUM(Allocation_Percent__c) totalLoad
            FROM Resource_Allocation__c
            WHERE Resource__c IN :resourceIds
              AND Start_Date__c <= :today
              AND End_Date__c >= :today
            GROUP BY Resource__c
        ]) {
            ResourceSummary summary = summariesByResource.get((Id) agg.get('resourceId'));
            if (summary != null) {
                summary.currentLoad = zeroIfNull((Decimal) agg.get('totalLoad'));
                summary.isOverAllocated = summary.currentLoad > OVER_ALLOCATION_THRESHOLD;
            }
        }

        plan.resources = summariesByResource.values();
        return plan;
    }

    /**
     * Builds an org-wide utilization matrix: one row per resource, one cell per
     * month. A cell's load is the sum of allocation percentages of every
     * allocation overlapping that month.
     *
     * @param monthsAhead Number of months to include, starting with the current month (max 12)
     * @return UtilizationMatrix with month labels, resource rows, and KPI totals
     */
    @AuraEnabled(cacheable=true)
    public static UtilizationMatrix getUtilizationMatrix(Integer monthsAhead) {
        Integer months = (monthsAhead == null || monthsAhead < 1) ? DEFAULT_MONTHS
            : Math.min(monthsAhead, MAX_MONTHS);

        Date windowStart = Date.today().toStartOfMonth();
        Date windowEnd = windowStart.addMonths(months).addDays(-1);

        UtilizationMatrix matrix = new UtilizationMatrix();
        for (Integer i = 0; i < months; i++) {
            matrix.monthLabels.add(formatMonth(windowStart.addMonths(i)));
        }

        List<Resource_Allocation__c> allocations = [
            SELECT Resource__c, Resource__r.Name, Allocation_Percent__c,
                   Start_Date__c, End_Date__c, Project__r.Name
            FROM Resource_Allocation__c
            WHERE Resource__c != null
              AND Start_Date__c <= :windowEnd
              AND End_Date__c >= :windowStart
            ORDER BY Resource__r.Name ASC
        ];

        Map<Id, UtilizationRow> rowsByResource = new Map<Id, UtilizationRow>();
        for (Resource_Allocation__c alloc : allocations) {
            UtilizationRow row = rowsByResource.get(alloc.Resource__c);
            if (row == null) {
                row = new UtilizationRow(alloc.Resource__c, alloc.Resource__r.Name, months);
                rowsByResource.put(alloc.Resource__c, row);
            }
            row.projectNames.add(alloc.Project__r.Name);

            for (Integer i = 0; i < months; i++) {
                Date monthStart = windowStart.addMonths(i);
                Date monthEnd = monthStart.addMonths(1).addDays(-1);
                if (alloc.Start_Date__c <= monthEnd && alloc.End_Date__c >= monthStart) {
                    row.cells[i].load += zeroIfNull(alloc.Allocation_Percent__c);
                }
            }
        }

        Decimal loadSum = 0;
        Integer loadedCellCount = 0;
        for (UtilizationRow row : rowsByResource.values()) {
            Boolean rowOver = false;
            for (UtilizationCell cell : row.cells) {
                cell.status = statusFor(cell.load);
                if (cell.load > 0) {
                    loadSum += cell.load;
                    loadedCellCount++;
                }
                if (cell.load > OVER_ALLOCATION_THRESHOLD) rowOver = true;
            }
            row.isOverAllocated = rowOver;
            row.projectCount = row.projectNames.size();
            if (rowOver) matrix.overAllocatedCount++;
        }

        matrix.rows = rowsByResource.values();
        matrix.resourceCount = matrix.rows.size();
        matrix.averageLoad = loadedCellCount > 0
            ? (loadSum / loadedCellCount).setScale(0)
            : 0;
        return matrix;
    }

    /**
     * Returns every resource allocation across all projects (those with a
     * resource and a start/end date) plus the distinct project list, for the
     * org-wide Resource Timeline app page. The component groups the flat rows
     * by resource and lays them out on a time axis client-side, so the Apex
     * stays a thin data feed.
     *
     * @return TimelineData with flat allocation rows and project options
     */
    @AuraEnabled(cacheable=true)
    public static TimelineData getResourceTimeline() {
        List<Resource_Allocation__c> allocations = [
            SELECT Id, Resource__c, Resource__r.Name, Role__c,
                   Allocation_Percent__c, Start_Date__c, End_Date__c,
                   Project__c, Project__r.Name,
                   WBS_Item__c, WBS_Item__r.Name, WBS_Item__r.WBS_Code__c
            FROM Resource_Allocation__c
            WHERE Resource__c != null
              AND Start_Date__c != null
              AND End_Date__c != null
            ORDER BY Resource__r.Name ASC, Start_Date__c ASC
        ];

        TimelineData data = new TimelineData();
        Map<Id, String> projectNames = new Map<Id, String>();
        for (Resource_Allocation__c alloc : allocations) {
            data.allocations.add(new TimelineRow(alloc));
            if (alloc.Project__c != null) {
                projectNames.put(alloc.Project__c, alloc.Project__r.Name);
            }
        }
        for (Id projId : projectNames.keySet()) {
            data.projects.add(new ProjectOption(projId, projectNames.get(projId)));
        }
        return data;
    }

    /**
     * Returns the allocations tied to a single WBS item, for inline management
     * from the WBS tab. Not cacheable so the list can be re-fetched imperatively
     * after add/delete.
     *
     * @param wbsItemId The WBS_Item__c record Id
     * @return Allocation rows for that WBS item
     */
    @AuraEnabled
    public static List<AllocationRow> getAllocationsForWBSItem(Id wbsItemId) {
        List<AllocationRow> rows = new List<AllocationRow>();
        for (Resource_Allocation__c alloc : [
            SELECT Id, Name, Resource__c, Resource__r.Name, Role__c,
                   Allocation_Percent__c, Start_Date__c, End_Date__c,
                   WBS_Item__c, WBS_Item__r.Name, WBS_Item__r.WBS_Code__c
            FROM Resource_Allocation__c
            WHERE WBS_Item__c = :wbsItemId
            ORDER BY Resource__r.Name ASC, Start_Date__c ASC NULLS LAST
        ]) {
            rows.add(new AllocationRow(alloc));
        }
        return rows;
    }

    /**
     * Deletes a single resource allocation.
     *
     * @param allocationId The Resource_Allocation__c record Id
     */
    @AuraEnabled
    public static void deleteAllocation(Id allocationId) {
        try {
            delete [SELECT Id FROM Resource_Allocation__c WHERE Id = :allocationId WITH SECURITY_ENFORCED LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Could not delete allocation: ' + e.getMessage());
        }
    }

    private static String statusFor(Decimal load) {
        if (load == 0) return 'empty';
        if (load <= WARN_THRESHOLD) return 'ok';
        if (load <= OVER_ALLOCATION_THRESHOLD) return 'warn';
        return 'over';
    }

    private static String formatMonth(Date monthStart) {
        return Datetime.newInstance(monthStart, Time.newInstance(12, 0, 0, 0)).format('MMM yyyy');
    }

    private static Decimal zeroIfNull(Decimal value) {
        return value != null ? value : 0;
    }

    public class ResourcePlan {
        @AuraEnabled public List<AllocationRow> allocations = new List<AllocationRow>();
        @AuraEnabled public List<ResourceSummary> resources = new List<ResourceSummary>();
    }

    public class AllocationRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public Id      resourceId;
        @AuraEnabled public String  resourceName;
        @AuraEnabled public String  role;
        @AuraEnabled public Decimal allocationPercent;
        @AuraEnabled public Date    startDate;
        @AuraEnabled public Date    endDate;
        @AuraEnabled public String  wbsItemName;

        public AllocationRow(Resource_Allocation__c alloc) {
            this.id                = alloc.Id;
            this.name              = alloc.Name;
            this.resourceId        = alloc.Resource__c;
            this.resourceName      = alloc.Resource__r?.Name;
            this.role              = alloc.Role__c;
            this.allocationPercent = alloc.Allocation_Percent__c;
            this.startDate         = alloc.Start_Date__c;
            this.endDate           = alloc.End_Date__c;
            this.wbsItemName       = alloc.WBS_Item__c != null
                ? (alloc.WBS_Item__r.WBS_Code__c != null ? alloc.WBS_Item__r.WBS_Code__c + ' ' : '') + alloc.WBS_Item__r.Name
                : null;
        }
    }

    public class ResourceSummary {
        @AuraEnabled public Id      resourceId;
        @AuraEnabled public String  resourceName;
        @AuraEnabled public String  role;
        @AuraEnabled public Decimal projectAllocation = 0;
        @AuraEnabled public Decimal currentLoad = 0;
        @AuraEnabled public Boolean isOverAllocated = false;

        public ResourceSummary(Id resourceId, String resourceName, String role) {
            this.resourceId   = resourceId;
            this.resourceName = resourceName;
            this.role         = role;
        }
    }

    public class UtilizationMatrix {
        @AuraEnabled public List<String> monthLabels = new List<String>();
        @AuraEnabled public List<UtilizationRow> rows = new List<UtilizationRow>();
        @AuraEnabled public Integer resourceCount = 0;
        @AuraEnabled public Integer overAllocatedCount = 0;
        @AuraEnabled public Decimal averageLoad = 0;
    }

    public class UtilizationRow {
        @AuraEnabled public Id      resourceId;
        @AuraEnabled public String  resourceName;
        @AuraEnabled public Boolean isOverAllocated = false;
        @AuraEnabled public Integer projectCount = 0;
        @AuraEnabled public List<UtilizationCell> cells = new List<UtilizationCell>();
        public transient Set<String> projectNames = new Set<String>();

        public UtilizationRow(Id resourceId, String resourceName, Integer months) {
            this.resourceId   = resourceId;
            this.resourceName = resourceName;
            for (Integer i = 0; i < months; i++) {
                this.cells.add(new UtilizationCell());
            }
        }
    }

    public class UtilizationCell {
        @AuraEnabled public Decimal load = 0;
        @AuraEnabled public String  status = 'empty';
    }

    public class TimelineData {
        @AuraEnabled public List<TimelineRow> allocations = new List<TimelineRow>();
        @AuraEnabled public List<ProjectOption> projects = new List<ProjectOption>();
    }

    public class TimelineRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public Id      resourceId;
        @AuraEnabled public String  resourceName;
        @AuraEnabled public String  role;
        @AuraEnabled public Id      projectId;
        @AuraEnabled public String  projectName;
        @AuraEnabled public String  wbsItemName;
        @AuraEnabled public Decimal allocationPercent;
        @AuraEnabled public Date    startDate;
        @AuraEnabled public Date    endDate;

        public TimelineRow(Resource_Allocation__c alloc) {
            this.id                = alloc.Id;
            this.resourceId        = alloc.Resource__c;
            this.resourceName      = alloc.Resource__r?.Name;
            this.role              = alloc.Role__c;
            this.projectId         = alloc.Project__c;
            this.projectName       = alloc.Project__r?.Name;
            this.allocationPercent = alloc.Allocation_Percent__c;
            this.startDate         = alloc.Start_Date__c;
            this.endDate           = alloc.End_Date__c;
            this.wbsItemName       = alloc.WBS_Item__c != null
                ? (alloc.WBS_Item__r.WBS_Code__c != null ? alloc.WBS_Item__r.WBS_Code__c + ' ' : '') + alloc.WBS_Item__r.Name
                : null;
        }
    }

    public class ProjectOption {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;

        public ProjectOption(Id id, String name) {
            this.id   = id;
            this.name = name;
        }
    }
}
