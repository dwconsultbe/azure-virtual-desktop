# Administrator guide

This guide explains how to deploy the monitoring baseline and prepare the data it needs.

For alert handling, read the [helpdesk guide](helpdesk-guide.md). For the design and alert list, read the [technical documentation](technical-documentation.md).

## What it creates

The deployment creates a monitoring resource group, Action Group, Automation Account, runbooks, schedules, host-pool diagnostic settings and alert rules. It uses an existing Log Analytics workspace. It does not create a workspace or a guest-data DCR.

Alert rules are created disabled. Add the alert IDs you want to enable to `additionalResources.enabledAlertRuleIds` after checking that their source data is available.

## Before you start

Before deployment, you need:

- an Azure subscription and permission to create the resources listed above;
- the name and resource group of each host pool;
- an existing Log Analytics workspace, including its name and resource group;
- Azure Monitor Agent installed on each session-host VM, with a DCR associated to each VM;
- an email address for alert notifications;
- an Azure DevOps service connection with the permissions below.

The DCR must send Windows performance counters to the `Perf` table and Windows event logs to the `Event` table in the workspace. Collect the counters used by the alerts, including processor, memory, disk, process and Terminal Services counters. Collect `System`, `Application` warnings and errors, `Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin`, `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational`, and `Microsoft-FSLogix-Apps` Admin and Operational events. Configure this before deploying the baseline, and check that the data is arriving. The baseline configures host-pool diagnostic settings to send AVD diagnostics to the same workspace.

## Set the three parameter blocks

Edit `parameters/main.example.bicepparam` in your clone and replace the `REPLACE_` values. The pipeline stops if any remain:

1. `deployment`: set the Azure region, notification email and existing workspace name and resource group inside `logAnalyticsWorkspace`. Add `subscriptionId` there only if the workspace is in another subscription. Set `monitoringResourceGroupName`; the template creates the group if it does not exist. Keep this name stable, because a new name creates a new Automation Account, Action Group and alert rules next to the old ones. Earlier versions generated a `rg-avdmon-<unique>` name when it was omitted; for an existing deployment, enter that existing name. You can optionally set `resourcePrefix`. For example, `resourcePrefix: 'org-env'` makes alert names start with `org-env-avd-ar-` and the Action Group name start with `org-env-ag-avd-`. Without a prefix, these names start with `avd-ar-` and `ag-avd-` respectively.
2. `hostPools`: add one entry for each host pool. Set `resourceGroupName` and `name`. Add `subscriptionId` only when that pool is in another subscription. Set `hostPoolType` to `Personal` only for personal pools. Put its scaling plan in `scalingPlanName`; it is expected to be in the same subscription and resource group as the pool. Set `configureDiagnostics` to `false` when the pool already sends its diagnostics to the workspace (see below).
3. `additionalResources`: optional. Add Azure Files accounts or Azure NetApp Files volumes if you need their alerts. Add alert IDs here to turn on selected rules. Leave the block empty for the first deployment.

### Existing host-pool diagnostic settings

By default the deployment adds a diagnostic setting to each host pool. Azure does not allow two diagnostic settings on the same resource to send the same log category to the same workspace. If a host pool already sends its diagnostics to the workspace, for example because AVD Insights was configured, the deployment fails with a "Data sink is already used" error. Set `configureDiagnostics: false` for that pool and make sure the existing setting includes the `Management`, `Connection`, `Error`, `Checkpoint`, `HostRegistration` and `AgentHealthStatus` categories, plus `AutoscaleEvaluationPooled` when the pool uses a scaling plan.

The host pool and its session-host VMs must be in the same resource group. You do not enter session-host VM IDs. The template uses the host pool's resource group for VM metric alerts.

Changing `resourcePrefix` changes the Automation Account, alert-rule and Action Group names. Azure creates new resources and does not remove the old ones. A new Automation Account can leave the old collector schedules running, so check and disable or remove the old account's schedules after confirming the new deployment works. Remove old alert rules and Action Groups after confirming the new ones work.

Example for a host pool in another subscription:

```bicep
param hostPools = [
  {
    subscriptionId: '<subscription-guid>'
    resourceGroupName: 'rg-avd'
    name: 'pool-production'
  }
]
```

The Automation Account name uses the optional prefix followed by `aa-avd-` and a unique suffix (for example, `org-env-aa-avd-<unique>`). The Action Group name uses the prefix followed by `ag-avd-` and a unique suffix. The runbooks use the fixed names `avd-host-pool-collector` and `avd-storage-collector`. The Action Group sends notifications to `deployment.notificationEmail`. Default alert rules are disabled until selected by ID.

## Required permissions

### Azure DevOps service connection

The service connection needs permission to:

- create a subscription deployment and resource groups;
- create resources in the monitoring resource group;
- create role assignments in each host-pool and storage resource group.

The last permission is normally provided by **User Access Administrator** or **Owner** at the required scopes. Cross-subscription host pools or storage also need permission in those subscriptions.

### Automation Account identity

The deployment assigns the Automation Account's managed identity:

- **Desktop Virtualization Reader** on each host-pool and scaling-plan resource group;
- **Reader** on each Azure Files resource group.

The runbooks only read Azure configuration and usage data. They do not need storage keys or write access.

## Create and run the pipeline

1. Create an Azure DevOps pipeline from `pipelines/avd-monitoring-baseline.yml`.
2. Add the pipeline variables `parameterFile` and `serviceConnection`. Set `parameterFile` to `parameters/main.example.bicepparam` (relative to the project folder), and set `serviceConnection` to the exact service connection name. Do not allow users to override these variables when they run the pipeline. The pipeline finds the project folder automatically, so the repository folder structure does not need to be configured.
3. Authorize the pipeline to use the service connection.
4. Run the pipeline. Review the what-if output; the deployment stage runs after the what-if stage. It waits for approval only if an approval check is configured on the `avd-monitoring-baseline` environment.

After the Bicep deployment, the pipeline waits for the PowerShell modules, publishes the runbooks and creates or updates their schedules.

## Check data and enable alerts

1. Open the Log Analytics workspace and check that `Perf` and `Event` data arrive from every session-host VM. Check `WVDAgentHealthStatus` and collector tables as well.
2. Add selected alert IDs to `additionalResources.enabledAlertRuleIds` and redeploy. Start with `collectorFailed` and `collectorStale`, then enable other alerts when their data is available.

For every new session-host VM, install or confirm the Azure Monitor Agent and associate the existing DCR. This is not automatic.

## Privacy and support

Some collector output and alert queries can include user names or FSLogix profile paths. Restrict access to the Automation Account, workspace and Action Group, and review alert recipients and retention requirements.

This project is an open-source example, not an official Microsoft solution. Test it outside production first. Microsoft does not provide support for it.

## Sources and license notice

The alert ideas, parts of the KQL and collector output formats were adapted from [Microsoft AMBA for Azure Virtual Desktop](https://azure.github.io/azure-monitor-baseline-alerts/patterns/specialized/avd/deploy/Avd-Deploy/index.html).

Adapted Microsoft source material remains subject to its original MIT license notice:

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
