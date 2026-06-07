# Glatt EPC — Build Plan

Salesforce EPC project-management app for a client demo (Glatt). Replaces manual tools: Excel CPM sheets, Webcon GSR, and a disconnected web app. Built feature-by-feature, one per session.

## Build sequence

| # | Feature | Priority | Status |
|---|---------|----------|--------|
| 0 | Project scaffold & data model | Demo-critical | Done |
| 1 | Project workspace (record page) | Demo-critical | Done |
| 2 | WBS Builder (tree grid) | Demo-critical | Done |
| 3 | Gantt chart (Frappe Gantt static resource) | Demo-critical | Done |
| 4 | Critical path engine (Apex CPM + progress roll-up) | High | Done |
| 5 | Resource allocation + dashboard | High | Done |
| 6 | Materials against tasks | Medium | Done |
| 7 | Daily progress capture (mobile) | Medium | Done |
| 8 | Kanban / task board | Low | Done |
| 9 | Reports & OEM dashboard | Medium | Done |
| — | Access & security (`EPC_Project_User` perm set kept complete) | Before demo | Ongoing — update with every feature |

## Data model spec (6 custom objects)

All objects are deployed (Feature 0). This is the reference spec.

### Project__c
- Name: auto-number `PRJ-{YYYY}-{0000}`
- Business_Unit__c: picklist — OEM, Steriles, OSD
- Project_Nature__c: picklist — Greenfield, Brownfield
- Total_Budget__c: currency
- Start_Date__c, End_Date__c: date
- Duration_Days__c: formula (End − Start)
- Overall_Progress__c: percent (Apex roll-up, budget-weighted — written by `CPMEngine`)
- Status__c: picklist — Planning, In Progress, Handed Over, On Hold
- Site_Location__c: text; Country__c: text

### WBS_Item__c
- Name: text; WBS_Code__c: text (e.g. "1.1.2")
- Project__c: master-detail → Project__c
- Parent_WBS_Item__c: lookup → WBS_Item__c (self-referencing hierarchy); Level__c: number
- Predecessor__c: lookup → WBS_Item__c; Dependency_Type__c: picklist — FS, SS, FF, SF; Lag_Days__c: number (can be negative)
- Duration_Days__c: number; Budget__c: currency; Progress__c: percent
- Start_Date__c, End_Date__c: date
- CPM fields: Early_Start__c, Early_Finish__c, Late_Start__c, Late_Finish__c (date), Float_Days__c (number), Is_Critical__c (checkbox)

### Work_Package__c
- Name: auto-number `WP-{0000}`
- WBS_Item__c: master-detail → WBS_Item__c
- Status__c: picklist — Planned, In Progress, Blocked, Complete
- Planned_Start__c, Planned_End__c: date
- Assigned_To__c: lookup → User

### Resource_Allocation__c
- Name: auto-number
- Project__c: lookup → Project__c; WBS_Item__c: lookup → WBS_Item__c (optional)
- Resource__c: lookup → User; Role__c: text
- Allocation_Percent__c: percent
- Start_Date__c, End_Date__c: date

### Material_Log__c
- Name: auto-number
- WBS_Item__c: master-detail → WBS_Item__c
- Material_Name__c: text; Quantity__c: number; Unit__c: text
- Cost_Type__c: picklist — Work, Material, Cost
- Rate__c: currency; Total_Cost__c: formula (Quantity × Rate)

### Daily_Progress__c
- Name: auto-number
- Work_Package__c: master-detail → Work_Package__c
- Project__c: lookup (denormalised for reporting)
- Progress_Date__c: date; Percent_Complete_Day__c: percent
- Weather__c: picklist — Sunny, Cloudy, Rain, Other
- Notes__c: long text
- Logged_By__c: lookup → User (default current user)

## Remaining feature notes

### Feature 7 — Daily progress capture (mobile)
Field-friendly entry of `Daily_Progress__c` against a `Work_Package__c`: pick work package, log % complete for the day, weather, notes. Should work well in the Salesforce mobile app (small form factor — keep the LWC mobile-aware). Logging progress should feed the Work_Package__c → WBS_Item__c progress picture that `CPMEngine` rolls up to `Project__c.Overall_Progress__c`.

### Feature 8 — Kanban / task board
Board view of `Work_Package__c` by `Status__c` (Planned / In Progress / Blocked / Complete), drag-to-move. Low priority — skip if time is short.

### Feature 9 — Reports & OEM dashboard
Report types + dashboard for management: project portfolio by Business_Unit__c, progress vs budget, critical-path slippage, resource utilisation. `Daily_Progress__c.Project__c` lookup exists specifically to make these reports easy.

## Key design decisions (do not relitigate)
- `Overall_Progress__c` is a budget-weighted average — needs Apex (`CPMEngine`), deliberately NOT a roll-up summary.
- CPM recalc and progress roll-up live in the same class (`CPMEngine`) because they touch the same records.
- WBS Apex data layer is separate from grid rendering so the grid can be swapped independently.
- Gantt: Frappe Gantt (MIT, `frappe_gantt` static resource), NOT DHTMLX (commercial).
- API version 60.0 throughout.
- No test classes (demo org doesn't require them); no Apex framework — keep it that way.

## Demo-day minimum
Features 0–3 (workspace, WBS, Gantt) must stay solid — don't regress them while adding lower-priority features. `EPC_Project_User` perm set must be complete before demo day.
