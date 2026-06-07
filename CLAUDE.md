# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Glatt EPC — a Salesforce project-management app built for a client demo (replacing Excel CPM sheets, Webcon GSR, and a disconnected web app). Standard SFDX project, single package directory `force-app`, **API version 60.0 throughout** (`sfdx-project.json`, all `*-meta.xml` files). No namespace, no tests so far (demo org), no git.

Features are built one per session against the build-sequence plan in **`docs/BUILD_PLAN.md`** (full data-model spec, feature statuses, remaining-feature notes): 0–6 done (scaffold, project workspace, WBS builder, Gantt, CPM engine, resource allocation, materials); remaining: daily progress mobile (7), kanban (8), reports (9). Update the status table there when a feature is completed.

## Commands

```bash
# Deploy (the only build step). Default org: glatt@wd.demo
sf project deploy start --source-dir force-app

# Check a failed deploy
sf project deploy report --job-id <id> --json

# Ad-hoc data/queries
sf data query -q "SELECT ..."
sf apex run --file <anon.apex>
```

**Always deploy automatically after editing metadata** — this is an explicit user instruction. If the deploy fails, fix it and redeploy; don't hand the error back.

There is no lint/test tooling: `sf code-analyzer` is installed but its Apex engines (PMD/SFGE) cannot run on this machine (no Java ≥ 11). No Apex test classes exist; the demo org doesn't require them to deploy.

## Architecture

Data model (6 custom objects under `force-app/main/default/objects/`):

```
Project__c ──(MD)── WBS_Item__c ──(MD)── Work_Package__c ──(MD)── Daily_Progress__c
                        │  ├─ self-lookup Parent_WBS_Item__c (tree hierarchy, WBS_Code__c "1.1.2")
                        │  └─ self-lookup Predecessor__c + Dependency_Type__c FS/SS/FF/SF + Lag_Days__c
                        └──(MD)── Material_Log__c
Resource_Allocation__c — lookups to Project__c, WBS_Item__c (optional), User (Resource__c)
```

Apex (4 classes, no framework — keep it that way):

- **`CPMEngine.recalculate(projectId)`** — the core engine. Topological sort of WBS items, forward/backward pass honoring dependency type + lag, writes `Early/Late Start/Finish`, `Float_Days__c`, `Is_Critical__c`, then rolls up budget-weighted progress to `Project__c.Overall_Progress__c` (deliberate design choice: weighted average needs Apex, not a roll-up summary). CPM and progress roll-up live in the same class because they touch the same records.
- **`WBSItemTrigger`** (the only trigger) re-runs `CPMEngine` per project on any WBS DML; **`TriggerHelper.isRunning`** is the recursion guard — `CPMEngine` sets it before its own DML.
- **`WBSTreeController` / `ResourceAllocationController` / `MaterialLogController`** — `@AuraEnabled` controllers for the LWCs. Established pattern: `with sharing`; `cacheable=true` wires returning inner wrapper classes with `@AuraEnabled` fields (no SObjects to the client); deletes via small `@AuraEnabled` methods; **creates/edits are done client-side via `lightning-record-edit-form`, not Apex DML**.

LWCs (all wired to a `Project_Record_Page` flexipage tabset: WBS → Gantt → Resources → Materials → Details → Related):

- `wbsTreeGrid` — `lightning-tree-grid` over `WBSTreeController.getWBSTree`, "Run CPM" button
- `ganttChart` — renders Frappe Gantt from the `frappe_gantt` static resource (MIT-licensed; deliberately chosen over commercial DHTMLX)
- `resourcePlanner` — per-resource load cards (cross-project over-allocation aware) + allocations table
- `resourceDashboard` — org-wide utilization heatmap on the `Resource_Dashboard` app page/tab
- `materialTracker` — cost-type KPIs, per-WBS budget-vs-actual cards, material log table

The WBS data layer (Apex) is intentionally separate from grid rendering so the grid can be swapped independently.

## Conventions that matter

- Copy the existing LWC pattern when adding components: wire + `_wiredResult`/`refreshApex`, `isLoading`/`hasError`/`isEmpty` states, toast helper, SLDS modal with `lightning-record-edit-form` (see `wbsTreeGrid` as the reference implementation).
- LWC CSS: use `var(--slds-g-color-*, #hex)` styling hooks. **Never use `--lwc-*` design tokens as fallbacks** — several (e.g. `colorBackgroundError`) are INTERNAL and fail deployment from the `c` namespace.
- Valid AppPage flexipage template here is `flexipage:defaultAppHomeTemplate` (`flexipage:appHomeTemplateDesktop` does not exist).
- Every new object/field/tab/class must be added to `permissionsets/EPC_Project_User.permissionset-meta.xml` (object + FLS + `classAccesses` + tab visibility) and new tabs to `applications/Glatt_EPC.app-meta.xml`. Exception: required fields and master-detail fields cannot have `fieldPermissions` entries — deployment fails with "cannot deploy to a required field".
- Percent fields store whole numbers (50 = 50%); divide by 100 in LWC for datatable `percent` columns.
- New record-page components target `lightning__RecordPage` scoped to `Project__c` and get their own tab facet in `Project_Record_Page.flexipage-meta.xml`.

## Demo priorities

Features 0–3 (workspace, WBS, Gantt) are demo-critical and must stay solid — don't regress them while adding lower-priority features. The `EPC_Project_User` perm set must be complete before demo day.
