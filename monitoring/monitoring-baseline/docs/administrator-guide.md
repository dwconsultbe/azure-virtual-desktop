# Administrator guide

**For:** the administrator who deploys and maintains the AVD monitoring baseline.

**Result:** alert rules for your host pools, running collectors, and e-mail notifications for the alerts you choose.

Handling alerts? Use the [helpdesk guide](helpdesk-guide.md). Looking for design details or the full alert list? Use the [technical documentation](technical-documentation.md).

## Deployment in 5 steps

| Step | What you do |
| --- | --- |
| [1. Check the prerequisites](#step-1-check-the-prerequisites) | Workspace, agent and data collection on the session hosts |
| [2. Fill in the parameter file](#step-2-fill-in-the-parameter-file) | Region, e-mail, workspace and host pools |
| [3. Set the permissions](#step-3-set-the-permissions) | Rights for the account that deploys |
| [4. Deploy](#step-4-deploy) | One script from your machine, or the Azure DevOps pipeline |
| [5. Check the data and enable more alerts](#step-5-check-the-data-and-enable-more-alerts) | Confirm data arrives, then switch on more alert sets |

> [!NOTE]
> Only the alerts in the sets you choose are switched on. The example parameter file starts with the **core** set: the alerts that matter most and need no extra setup.

---

## Step 1: Check the prerequisites

- [ ] An existing **Log Analytics workspace**. Note its name and resource group.
- [ ] **Azure Monitor Agent** on every session host.
- [ ] A **data collection rule (DCR)** that sends performance counters and event logs from the session hosts to that workspace, and is associated with every session host. Needed for the `resources` and `fslogix` alert sets; the `core` set works without it.
- [ ] The **name and resource group** of each host pool. The session hosts must be in the same resource group as their host pool.
- [ ] An **e-mail address** (preferably a shared mailbox) for the notifications.
- [ ] To deploy, **one of**:
  - [PowerShell 7](https://aka.ms/powershell) and the [Azure CLI](https://aka.ms/installazurecli) on your machine (easiest), or
  - an **Azure DevOps project** with a service connection to the subscription.

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

Open `parameters/main.example.bicepparam` and replace every `REPLACE_` value. The deployment stops and lists the values that are left.

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
  alertSets: [
    'core'
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

### `additionalResources`: alerts and optional storage

Keep `alertSets: ['core']` for the first deployment. You add more sets in step 5.

| Setting | What it does |
| --- | --- |
| `alertSets` | Groups of alerts to switch on. See the [alert sets](#alert-sets) table in step 5. |
| `enabledAlertRuleIds` | Individual alerts on top of the sets, for example `'cpu95'`. See the [alert catalog](technical-documentation.md#alert-catalog). |
| `fileStorageAccounts` | Azure Files storage accounts with FSLogix profiles: `resourceGroupName`, `name`, optional `subscriptionId`. |
| `anfVolumes` | Azure NetApp Files volumes: `resourceGroupName`, `netAppAccountName`, `capacityPoolName`, `name`, optional `subscriptionId`. |

---

## Step 3: Set the permissions

The account that deploys is **you** (option A in step 4) or the **Azure DevOps service connection** (option B).

| Who | Role | Scope | Why |
| --- | --- | --- | --- |
| The account that deploys | **Contributor** | Deployment subscription | Create the resource group, alerts and Automation Account |
| The account that deploys | **User Access Administrator** (or Owner) | Each host-pool and storage resource group | Give the collectors read access |
| Automation Account identity | Desktop Virtualization Reader | Each host-pool resource group | *Assigned automatically by the deployment* |
| Automation Account identity | Reader | Each Azure Files resource group | *Assigned automatically by the deployment* |

Host pools or storage in another subscription? The account that deploys needs the same rights there.

---

## Step 4: Deploy

Choose one option. Both do the same: a preview of the changes, then the deployment.

### Option A: from your machine (easiest)

1. Open PowerShell 7 in the `monitoring-baseline` folder.
2. Sign in and deploy:

   ```powershell
   az login
   ./deploy.ps1
   ```

3. Check the summary and the preview, then type `yes`.

   > [!TIP]
   > A `*` in the preview means **ignore**: the resource already exists in the resource group but is not part of the template, for example a leftover from an earlier version. The deployment does not touch it.
4. Wait until the script shows **Next steps** (about 5 to 10 minutes).

| Option | Use when |
| --- | --- |
| `-SubscriptionId <id>` | You have several subscriptions. Default: the current Azure CLI subscription. |
| `-ParameterFile <path>` | Your values are in another file. Default: `parameters/main.example.bicepparam`. |
| `-Yes` | You do not want to confirm after the preview. |

### Option B: Azure DevOps pipeline

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

## Step 5: Check the data and enable more alerts

1. Wait about 15 minutes after the deployment. The deployment starts a first collector run itself.
2. In the Log Analytics workspace, run this query. Every source should show a recent `LastSeen`. A missing source or an empty `LastSeen` means that data is not arriving:

   ```kusto
   union isfuzzy=true
     (Perf | where TimeGenerated > ago(30m) | summarize LastSeen = max(TimeGenerated) | extend Source = 'Perf (session hosts)'),
     (Event | where TimeGenerated > ago(30m) | summarize LastSeen = max(TimeGenerated) | extend Source = 'Event (session hosts)'),
     (WVDAgentHealthStatus | where TimeGenerated > ago(30m) | summarize LastSeen = max(TimeGenerated) | extend Source = 'AVD diagnostics'),
     (AzureDiagnostics | where Category == 'JobStreams' and TimeGenerated > ago(30m) | summarize LastSeen = max(TimeGenerated) | extend Source = 'Collectors')
   | project Source, LastSeen
   ```

3. Add more sets to `alertSets` and deploy again. Add one or two sets at a time:

   ```bicep
   alertSets: [
     'core'
     'fslogix'
     'resources'
   ]
   ```

### Alert sets

| Set | What it covers | Needs |
| --- | --- | --- |
| `core` | The monitoring itself, users who cannot connect, failed health checks, a full host pool, Microsoft incidents | Nothing extra. **Start here.** |
| `hostPool` | Capacity at 50, 85 and 95%, connection failures | Nothing extra |
| `sessionHosts` | Health checks, unhealthy personal hosts, agent upgrades, drained idle hosts | Nothing extra |
| `scaling` | Scaling plan disabled or removed, autoscale failures | A scaling plan |
| `resources` | CPU, memory, local disk, OS disk bandwidth | Session-host DCR |
| `fslogix` | Profile space, attach, network, disk in use, service, compaction | Session-host DCR |
| `storage` | Azure Files and Azure NetApp Files capacity, latency, availability, throttling | `fileStorageAccounts` or `anfVolumes` |
| `serviceHealth` | All Microsoft notices: incidents, maintenance, advisories, security | Nothing extra |
| `all` | Everything above | All of the above |

The exact alerts per set are in the [alert catalog](technical-documentation.md#alert-catalog). Want a single alert without its set? Add its ID to `enabledAlertRuleIds`.

> [!TIP]
> A typo in a set name or alert ID stops the deployment with an error that lists the valid values. Nothing is half deployed.

---

## Day-to-day tasks

| When you... | Do this |
| --- | --- |
| Enable more alerts | Add a set to `alertSets` and deploy again. |
| Add a host pool | Add an entry to `hostPools` and deploy again. |
| Add a session host | Associate the DCR with the new VM (or use Azure Policy). The alerts pick it up automatically. |
| Change a pool from Pooled to Personal (or back) | Change `hostPoolType`, deploy again, then delete the alerts that no longer fit (capacity or personal-unhealthy). |
| Add Azure Files storage | Add it to `fileStorageAccounts` and deploy again. |
| Change a threshold | Change it in the module under `src/modules/alerts/` and deploy again. |
| Remove the baseline | Delete the monitoring resource group, the `avd-baseline-...` diagnostic setting on each host pool, and the collector role assignments on the host-pool and storage resource groups. |

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `The parameter file still has ... value(s) to fill in` or `... REPLACE_ placeholders` | A value in the parameter file was not filled in | Replace the listed `REPLACE_` values |
| `You are not signed in to Azure` | No Azure CLI session | Run `az login` |
| `BCP034: The enclosing array expected an item of type ...` | A typo in `alertSets` or `enabledAlertRuleIds` | Use one of the values listed in the error |
| `Data sink ... is already used` | The host pool already sends diagnostics to the workspace | Set `configureDiagnostics: false` for that pool |
| `AuthorizationFailed` on `roleAssignments/write` | The account that deploys cannot assign roles | Give it User Access Administrator on the host-pool resource groups (step 3) |
| `Automation module ... did not reach version` | The PowerShell module import in Automation took too long or failed | Check **Modules** in the Automation Account and deploy again |
| `collectorStale` fires right after deployment | The first collector run did not finish yet | Check **Jobs** in the Automation Account; the alert closes by itself after a successful run |
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
