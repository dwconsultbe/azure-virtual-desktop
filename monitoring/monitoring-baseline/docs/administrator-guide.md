# Administrator guide

**For:** the administrator who deploys and maintains the AVD monitoring baseline.

**Result:** alert rules for your host pools, running collectors, and e-mail notifications for the alerts you choose.

Handling alerts? Use the [helpdesk guide](helpdesk-guide.md). Looking for design details or the full alert list? Use the [technical documentation](technical-documentation.md).

## Deployment in 5 steps

| Step | What you do |
| --- | --- |
| [1. Check the prerequisites](#step-1-check-the-prerequisites) | Workspace, agent and data collection on the session hosts |
| [2. Fill in the parameter file](#step-2-fill-in-the-parameter-file) | Region, e-mail, workspace and host pools |
| [3. Set the permissions](#step-3-set-the-permissions) | Rights for the Azure DevOps service connection |
| [4. Run the pipeline](#step-4-run-the-pipeline) | Build, preview and deploy |
| [5. Check the data and enable alerts](#step-5-check-the-data-and-enable-alerts) | Confirm data arrives, then switch alerts on |

> [!NOTE]
> All alert rules are created **disabled**. Nothing sends e-mail until you enable alerts in step 5.

---

## Step 1: Check the prerequisites

- [ ] An existing **Log Analytics workspace**. Note its name and resource group.
- [ ] **Azure Monitor Agent** on every session host.
- [ ] A **data collection rule (DCR)** that sends performance counters and event logs from the session hosts to that workspace, and is associated with every session host.
- [ ] The **name and resource group** of each host pool. The session hosts must be in the same resource group as their host pool.
- [ ] An **e-mail address** (preferably a shared mailbox) for the notifications.
- [ ] An **Azure DevOps project** with a service connection to the subscription.

> [!TIP]
> No DCR yet? The sample in [`samples/session-host-dcr`](../samples/session-host-dcr/README.md) creates one with exactly the data the alerts need, and can associate it with your session hosts.

<details>
<summary>What the DCR must collect</summary>

| Data | Needed for |
| --- | --- |
| `Processor Information(_Total)\% Processor Time` | CPU alerts |
| `Memory\Available MBytes` | Memory alerts |
| `LogicalDisk(<drive>)\% Free Space` | Local disk alerts |
| `Microsoft-FSLogix-Apps/Admin` and `/Operational` events | FSLogix alerts |

Sending these to the `Perf` and `Event` tables is enough for the baseline. AVD Insights uses more counters and logs; the sample DCR includes those too.

</details>

---

## Step 2: Fill in the parameter file

Open `parameters/main.example.bicepparam` and replace every `REPLACE_` value. The pipeline stops if one is left.

### Complete example

```bicep
using '../src/main.bicep'

param deployment = {
  location: 'westeurope'
  notificationEmail: 'avd-alerts@contoso.com'
  logAnalyticsWorkspace: {
    resourceGroupName: 'rg-monitoring'
    name: 'law-avd-prod'
  }
  monitoringResourceGroupName: 'rg-avd-monitoring'
}

param hostPools = [
  {
    resourceGroupName: 'rg-avd-prod'
    name: 'hp-avd-prod'
    scalingPlanName: 'sp-avd-prod'
  }
  {
    resourceGroupName: 'rg-avd-personal'
    name: 'hp-avd-personal'
    hostPoolType: 'Personal'
  }
]

param additionalResources = {
  enabledAlertRuleIds: [
    'collectorFailed'
    'collectorStale'
  ]
}
```

### `deployment`: where and who

| Setting | Required | What to enter | Example |
| --- | --- | --- | --- |
| `location` | Yes | Azure region for the monitoring resources | `westeurope` |
| `notificationEmail` | Yes | Mailbox that receives the alerts | `avd-alerts@contoso.com` |
| `logAnalyticsWorkspace.name` | Yes | Name of the existing workspace | `law-avd-prod` |
| `logAnalyticsWorkspace.resourceGroupName` | Yes | Resource group of the workspace | `rg-monitoring` |
| `logAnalyticsWorkspace.subscriptionId` | No | Only when the workspace is in another subscription | |
| `monitoringResourceGroupName` | Yes | Resource group for the monitoring resources. Created if it does not exist. | `rg-avd-monitoring` |
| `resourcePrefix` | No | Prefix for alert, Action Group and Automation Account names | `org-prod` |

> [!IMPORTANT]
> **Keep `monitoringResourceGroupName` and `resourcePrefix` the same** after the first deployment. A new value creates a second Automation Account, Action Group and set of alerts next to the old ones.
>
> Upgrading from a version where the resource group name was optional? Enter the existing `rg-avdmon-...` name.

### `hostPools`: one entry per host pool

| Setting | Required | What to enter | Example |
| --- | --- | --- | --- |
| `name` | Yes | Host pool name | `hp-avd-prod` |
| `resourceGroupName` | Yes | Resource group of the host pool **and** its session hosts | `rg-avd-prod` |
| `subscriptionId` | No | Only when the host pool is in another subscription | |
| `hostPoolType` | No | `Pooled` (default) or `Personal` | `Personal` |
| `scalingPlanName` | No | Scaling plan of this pool, in the same resource group | `sp-avd-prod` |
| `configureDiagnostics` | No | `true` (default). Set to `false` when the pool already sends its diagnostics to the workspace, for example through AVD Insights. | `false` |

> [!WARNING]
> **Error "Data sink is already used"?** The host pool already has a diagnostic setting that sends to this workspace. Set `configureDiagnostics: false` for that pool. Make sure the existing setting includes `Management`, `Connection`, `Error`, `Checkpoint`, `HostRegistration` and `AgentHealthStatus`, plus `AutoscaleEvaluationPooled` when the pool uses a scaling plan.

### `additionalResources`: optional extras

Leave this block empty for the first deployment, or enable only the two collector alerts as in the example.

| Setting | What it does |
| --- | --- |
| `enabledAlertRuleIds` | Alert IDs to switch on. See the [alert catalog](technical-documentation.md#alert-catalog). |
| `fileStorageAccounts` | Azure Files storage accounts with FSLogix profiles: `resourceGroupName`, `name`, optional `subscriptionId`. |
| `anfVolumes` | Azure NetApp Files volumes: `resourceGroupName`, `netAppAccountName`, `capacityPoolName`, `name`, optional `subscriptionId`. |

---

## Step 3: Set the permissions

| Who | Role | Scope | Why |
| --- | --- | --- | --- |
| Azure DevOps service connection | **Contributor** | Deployment subscription | Create the resource group, alerts and Automation Account |
| Azure DevOps service connection | **User Access Administrator** (or Owner) | Each host-pool and storage resource group | Give the collectors read access |
| Automation Account identity | Desktop Virtualization Reader | Each host-pool resource group | *Assigned automatically by the deployment* |
| Automation Account identity | Reader | Each Azure Files resource group | *Assigned automatically by the deployment* |

Host pools or storage in another subscription? Give the service connection the same rights there.

---

## Step 4: Run the pipeline

1. In Azure DevOps, go to **Pipelines > New pipeline** and select `pipelines/avd-monitoring-baseline.yml`.
2. Select **Run pipeline** and fill in:

   | Parameter | Value |
   | --- | --- |
   | Azure service connection | The exact name of your service connection |
   | Parameter file | Leave the default, unless your values are in another file |

3. On the first run, select **Permit** when Azure DevOps asks for access to the service connection and the `avd-monitoring-baseline` environment.
4. Open the **what-if** artifact and review the planned changes.
5. Wait for the **Deploy** stage to finish. It also imports the PowerShell modules, publishes the runbooks and creates the schedules.

> [!TIP]
> Want the pipeline to wait for your approval after the what-if? Add an approval in **Pipelines > Environments > avd-monitoring-baseline > Approvals and checks**.

---

## Step 5: Check the data and enable alerts

1. Wait about 30 minutes after the deployment.
2. In the Log Analytics workspace, run this query. Every source should show a recent `LastSeen`. A missing source or an empty `LastSeen` means that data is not arriving:

   ```kusto
   union isfuzzy=true
     (Perf | where TimeGenerated > ago(30m) | summarize LastSeen = max(TimeGenerated) | extend Source = 'Perf (session hosts)'),
     (Event | where TimeGenerated > ago(30m) | summarize LastSeen = max(TimeGenerated) | extend Source = 'Event (session hosts)'),
     (WVDAgentHealthStatus | where TimeGenerated > ago(30m) | summarize LastSeen = max(TimeGenerated) | extend Source = 'AVD diagnostics'),
     (AzureDiagnostics | where Category == 'JobStreams' and TimeGenerated > ago(30m) | summarize LastSeen = max(TimeGenerated) | extend Source = 'Collectors')
   | project Source, LastSeen
   ```

3. Enable alerts **in small groups** by adding their IDs to `enabledAlertRuleIds` and running the pipeline again:

   | Round | Enable | Why first |
   | --- | --- | --- |
   | 1 | `collectorFailed`, `collectorStale`, `diagnosticDataMissing` | Tells you when the monitoring itself stops working |
   | 2 | `noResourcesAvailable`, `healthCheckFailure`, `capacity95`, `personalUnhealthy` | Users cannot work |
   | 3 | FSLogix, memory, disk and CPU alerts | Problems that affect users soon |
   | 4 | Everything else you need | After a week, when you know the normal behaviour |

> [!NOTE]
> An alert ID that does not exist is ignored without an error. Copy IDs from the [alert catalog](technical-documentation.md#alert-catalog).

---

## Day-to-day tasks

| When you... | Do this |
| --- | --- |
| Add a host pool | Add an entry to `hostPools` and run the pipeline. |
| Add a session host | Associate the DCR with the new VM (or use Azure Policy). The alerts pick it up automatically. |
| Change a pool from Pooled to Personal (or back) | Change `hostPoolType`, run the pipeline, then delete the alerts that no longer fit (capacity or personal-unhealthy). |
| Add Azure Files storage | Add it to `fileStorageAccounts` and run the pipeline. |
| Change a threshold | Change it in the module under `src/modules/alerts/` and run the pipeline. |
| Remove the baseline | Delete the monitoring resource group, the `avd-baseline-...` diagnostic setting on each host pool, and the collector role assignments on the host-pool and storage resource groups. |

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Parameter file still contains REPLACE_ placeholders` | A value in the parameter file was not filled in | Replace every `REPLACE_` value |
| `Data sink ... is already used` | The host pool already sends diagnostics to the workspace | Set `configureDiagnostics: false` for that pool |
| `AuthorizationFailed` on `roleAssignments/write` | The service connection cannot assign roles | Give it User Access Administrator on the host-pool resource groups (step 3) |
| `Automation module ... did not reach version` | The PowerShell module import in Automation took too long or failed | Check **Modules** in the Automation Account and run the pipeline again |
| `collectorStale` fires right after deployment | The collectors have not run yet | Wait for the first runs (within 15 minutes); the alert closes by itself |
| No `Perf` or `Event` data | The DCR is missing or not associated with the VM | Check the DCR association and the Azure Monitor Agent on the session host |

---

## Privacy

Alerts and collector output can contain user names and FSLogix profile paths.

- Limit access to the workspace, Automation Account and Action Group.
- Check who receives the alert e-mails.
- Check the retention of the workspace against your privacy rules.

## Sources and license notice

This is an open-source example, not an official Microsoft solution. Microsoft does not support it. Test it outside production first.

The alert ideas, parts of the KQL and the collector output formats were adapted from [Microsoft AMBA for Azure Virtual Desktop](https://azure.github.io/azure-monitor-baseline-alerts/patterns/specialized/avd/deploy/Avd-Deploy/index.html).

<details>
<summary>MIT notice for adapted source material</summary>

MIT License

Copyright (c) Microsoft Corporation.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

</details>
