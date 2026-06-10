public with sharing class EPCDashboardController {

    public class DashboardData {
        @AuraEnabled public Integer projectCount;
        @AuraEnabled public Decimal  totalBudget;
        @AuraEnabled public Decimal  avgProgress;
        @AuraEnabled public Integer  criticalItemCount;
        @AuraEnabled public Integer  atRiskCount;
        @AuraEnabled public List<ProjectRow>   portfolio;
        @AuraEnabled public List<BURow>        buBreakdown;
        @AuraEnabled public List<CriticalRow>  criticalItems;
        @AuraEnabled public List<LogRow>       recentLogs;
        @AuraEnabled public List<StatusCount>  statusBreakdown;
    }

    public class StatusCount {
        @AuraEnabled public String  status;
        @AuraEnabled public Integer count;
        @AuraEnabled public String  statusClass;
    }

    public class ProjectRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  status;
        @AuraEnabled public String  businessUnit;
        @AuraEnabled public String  nature;
        @AuraEnabled public String  location;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Decimal budget;
        @AuraEnabled public Decimal spent;
        @AuraEnabled public Date    startDate;
        @AuraEnabled public Date    endDate;
        @AuraEnabled public String  statusClass;
    }

    public class BURow {
        @AuraEnabled public String  businessUnit;
        @AuraEnabled public Integer projectCount;
        @AuraEnabled public Decimal totalBudget;
        @AuraEnabled public Decimal avgProgress;
    }

    public class CriticalRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  wbsCode;
        @AuraEnabled public String  name;
        @AuraEnabled public String  projectName;
        @AuraEnabled public Integer floatDays;
        @AuraEnabled public Date    endDate;
        @AuraEnabled public String  riskClass;
        @AuraEnabled public String  riskLabel;
    }

    public class LogRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public Date    logDate;
        @AuraEnabled public Decimal percentComplete;
        @AuraEnabled public String  notes;
        @AuraEnabled public String  weather;
        @AuraEnabled public String  wpName;
        @AuraEnabled public String  projectName;
        @AuraEnabled public String  loggedBy;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboard() {
        DashboardData data = new DashboardData();

        // Material spend per project
        Map<Id, Decimal> spentByProject = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT WBS_Item__r.Project__c projId, SUM(Total_Cost__c) spent
            FROM Material_Log__c
            GROUP BY WBS_Item__r.Project__c
        ]) {
            spentByProject.put((Id)ar.get('projId'), (Decimal)ar.get('spent'));
        }

        // Portfolio
        List<Project__c> projects = [
            SELECT Id, Name, Status__c, Business_Unit__c, Project_Nature__c,
                   Overall_Progress__c, Total_Budget__c, Start_Date__c, End_Date__c,
                   Site_Location__c, Country__c
            FROM Project__c
            ORDER BY Start_Date__c ASC NULLS LAST
        ];

        data.projectCount = projects.size();
        Decimal totalBudget = 0, totalProgress = 0;
        Integer withProgress = 0;

        // BU aggregation
        Map<String, BURow> buMap = new Map<String, BURow>();

        List<ProjectRow> portfolio = new List<ProjectRow>();
        for (Project__c p : projects) {
            ProjectRow row = new ProjectRow();
            row.id          = p.Id;
            row.name        = p.Name;
            row.status      = p.Status__c;
            row.businessUnit= p.Business_Unit__c;
            row.nature      = p.Project_Nature__c;
            String loc = '';
            if (p.Site_Location__c != null) loc += p.Site_Location__c;
            if (p.Country__c != null)        loc += (loc.length() > 0 ? ', ' : '') + p.Country__c;
            row.location    = loc;
            row.progress    = p.Overall_Progress__c != null ? p.Overall_Progress__c.setScale(1) : 0;
            row.budget      = p.Total_Budget__c != null ? p.Total_Budget__c : 0;
            row.spent       = spentByProject.containsKey(p.Id) ? spentByProject.get(p.Id) : 0;
            row.startDate   = p.Start_Date__c;
            row.endDate     = p.End_Date__c;
            row.statusClass = statusClass(p.Status__c);
            portfolio.add(row);

            if (p.Total_Budget__c != null) totalBudget += p.Total_Budget__c;
            if (p.Overall_Progress__c != null) { totalProgress += p.Overall_Progress__c; withProgress++; }

            String bu = p.Business_Unit__c != null ? p.Business_Unit__c : 'Other';
            if (!buMap.containsKey(bu)) {
                BURow br = new BURow();
                br.businessUnit  = bu;
                br.projectCount  = 0;
                br.totalBudget   = 0;
                br.avgProgress   = 0;
                buMap.put(bu, br);
            }
            BURow br = buMap.get(bu);
            br.projectCount++;
            br.totalBudget  += row.budget;
            br.avgProgress  += row.progress;
        }

        data.portfolio    = portfolio;
        data.totalBudget  = totalBudget;
        data.avgProgress  = withProgress > 0 ? (totalProgress / withProgress).setScale(1) : 0;

        // Status distribution
        Map<String, Integer> statusMap = new Map<String, Integer>();
        for (Project__c p : projects) {
            String s = p.Status__c != null ? p.Status__c : 'Planning';
            statusMap.put(s, (statusMap.containsKey(s) ? statusMap.get(s) : 0) + 1);
        }
        List<StatusCount> statusCounts = new List<StatusCount>();
        for (String s : statusMap.keySet()) {
            StatusCount sc = new StatusCount();
            sc.status      = s;
            sc.count       = statusMap.get(s);
            sc.statusClass = statusClass(s);
            statusCounts.add(sc);
        }
        data.statusBreakdown = statusCounts;

        List<BURow> buList = new List<BURow>();
        for (BURow br : buMap.values()) {
            br.avgProgress = br.projectCount > 0 ? (br.avgProgress / br.projectCount).setScale(1) : 0;
            buList.add(br);
        }
        data.buBreakdown = buList;

        // Critical path items
        List<WBS_Item__c> critWbs = [
            SELECT Id, Name, WBS_Code__c, Float_Days__c, Start_Date__c, End_Date__c,
                   Project__r.Name
            FROM WBS_Item__c
            WHERE Is_Critical__c = true
            ORDER BY Float_Days__c ASC NULLS FIRST, Project__r.Name ASC
            LIMIT 20
        ];

        // Near-critical (float 1–5, not on critical path)
        Integer nearCrit = [SELECT COUNT() FROM WBS_Item__c
                            WHERE Is_Critical__c = false
                              AND Float_Days__c >= 0 AND Float_Days__c <= 5];

        data.criticalItemCount = critWbs.size();
        data.atRiskCount       = nearCrit;

        List<CriticalRow> critRows = new List<CriticalRow>();
        for (WBS_Item__c w : critWbs) {
            CriticalRow cr = new CriticalRow();
            cr.id          = w.Id;
            cr.wbsCode     = w.WBS_Code__c;
            cr.name        = w.Name;
            cr.projectName = w.Project__r.Name;
            cr.floatDays   = w.Float_Days__c != null ? Integer.valueOf(w.Float_Days__c) : 0;
            cr.endDate     = w.End_Date__c;
            Integer f = cr.floatDays;
            cr.riskClass   = f <= 0 ? 'risk-critical' : (f <= 5 ? 'risk-warn' : 'risk-ok');
            cr.riskLabel   = f <= 0 ? 'Critical' : (f <= 5 ? 'At Risk' : 'Float: ' + f + 'd');
            critRows.add(cr);
        }
        data.criticalItems = critRows;

        // Recent daily logs
        List<Daily_Progress__c> logs = [
            SELECT Id, Progress_Date__c, Percent_Complete_Day__c, Notes__c, Weather__c,
                   Work_Package__r.Name, Project__r.Name, Logged_By__r.Name
            FROM Daily_Progress__c
            ORDER BY Progress_Date__c DESC
            LIMIT 10
        ];
        List<LogRow> logRows = new List<LogRow>();
        for (Daily_Progress__c dp : logs) {
            LogRow lr       = new LogRow();
            lr.id           = dp.Id;
            lr.logDate      = dp.Progress_Date__c;
            lr.percentComplete = dp.Percent_Complete_Day__c;
            lr.notes        = dp.Notes__c;
            lr.weather      = dp.Weather__c;
            lr.wpName       = dp.Work_Package__r.Name;
            lr.projectName  = dp.Project__r != null ? dp.Project__r.Name : '';
            lr.loggedBy     = dp.Logged_By__r != null ? dp.Logged_By__r.Name : '';
            logRows.add(lr);
        }
        data.recentLogs = logRows;

        return data;
    }

    private static String statusClass(String status) {
        if (status == 'In Progress')  return 'status-progress';
        if (status == 'Handed Over')  return 'status-done';
        if (status == 'On Hold')      return 'status-hold';
        return 'status-plan';
    }
}
