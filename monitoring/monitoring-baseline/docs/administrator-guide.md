# Administrator guide

This guide is for the person who installs and configures the monitoring solution.

For alert handling, read the [helpdesk guide](helpdesk-guide.md). For full technical details, read the [technical documentation](technical-documentation.md).

## What the solution does

The solution creates Azure Monitor alerts for Azure Virtual Desktop. It monitors:

- host pool capacity and connections;
- session host health, CPU, memory and disk space;
- FSLogix and profile storage;
- Azure Files and Azure NetApp Files;
- scaling plans and Azure Service Health;
- the monitoring collectors themselves.

## Before you start

You need:

- an Azure subscription;
- a resource group for the monitoring resources, or permission to create one;
- an existing Log Analytics workspace, or permission to create one;
- an existing Action Group, or an email address for a new Action Group;
- the names and resource groups of the host pools and storage resources you want to monitor;
- an Azure DevOps service connection with the permissions listed below.

The solution can use an existing Log Analytics workspace or create one in the monitoring resource group. AVD diagnostics, guest data collection rules and their policy assignments are optional. Set `createMonitoringResourceGroup` to `true` to create the monitoring resource group, or use an existing one. You can also use an existing Action Group or create a new one with the template.

## Files you need

- `src/main.bicep`: main deployment template;
- `src/collector-schedules.bicep`: schedule deployment;
- `parameters/main.example.bicepparam`: example parameters;
- `pipelines/avd-monitoring-baseline.yml`: Azure DevOps pipeline;
- `tests/collector-contract.ps1`: tests that check the data returned by the collectors.

Edit `parameters/main.example.bicepparam` in your private copy of the repository and replace every `REPLACE_*` value. Do not commit completed customer parameters to a public repository.

## Required permissions

The deployment uses the Azure DevOps service connection and the Automation Account identity. If you enable DCR policies, Azure Policy also uses a managed identity for each assignment.

### Azure DevOps service connection

The service connection needs permission to:

- create a deployment at subscription level;
- **Contributor** on the monitoring resource group;
- create role assignments on the resource groups where the Automation identity needs access. **User Access Administrator** or **Owner** can do this.
- when using DCR policies, **Resource Policy Contributor** (or **Owner**) on each host-pool resource group to create policy assignments, and **User Access Administrator** (or **Owner**) there to grant the policy identity its role;

The service connection creates the Automation Account, runbooks, schedules, diagnostic settings, alerts and role assignments. When `createMonitoringResourceGroup` is true, it also needs permission to create a resource group in the subscription.

### Automation Account identity

The template creates a system-assigned identity for the Automation Account. It receives:

- **Desktop Virtualization Reader** on resource groups with the selected host pools and scaling plans;
- **Reader** on resource groups with the selected Azure Files accounts.

The runbooks only read data. They do not need passwords, storage keys or Contributor rights.

The host pool collector uses **Desktop Virtualization Reader** to read host pools, session hosts, user sessions and scaling plans for its capacity, health and scaling checks. The Azure Files collector uses **Reader** to list shares and read their usage and quota values. It does not access file contents.

The template gives these roles to the Automation identity during deployment. When you add a host pool or scaling plan to the parameter file and deploy again, the identity gets access to that resource group. Resources in the same resource group share one role assignment. For a resource in another subscription, add `subscriptionId` to its entry and make sure the service connection can create role assignments there.

When `associateDcrsWithPolicy` is enabled, the template creates one built-in DCR association policy assignment per DCR and host-pool resource group. Each assignment identity gets **Monitoring Contributor** on that resource group so the policy can create DCR associations on matching VMs. This identity does not collect or read the VM data. The policy only applies to supported Windows images, plus any images listed in `customWindowsImageIds`.

To collect data from another Azure Files account, add it to `fileStorageAccounts` and redeploy. The template grants **Reader** on that account's resource group.

You can grant these roles on smaller parts of your Azure setup if your security rules require it.

## Configure the parameters

Open `parameters/main.example.bicepparam` and set:

- the monitoring resource group and Azure region;
- the Log Analytics workspace name and resource group;
- whether to create a Log Analytics workspace in the monitoring resource group or use an existing workspace;
- whether to deploy the AVD guest-data DCR, the separate VM Insights DCR, and DCR association policies;
- the Log Analytics workspace region for DCRs when using an existing workspace;
- whether to configure AVD host-pool and AVD workspace diagnostic settings, and the AVD workspace names when needed;
- the existing Action Group name and resource group, if you are reusing one;
- whether to use an existing Action Group or create a new one;
- the new Action Group name and email receivers, when you create one;
- the host pool names and resource groups;
- session host VMs in the same resource group as their host pool, when OS Disk Bandwidth alerts are needed;
- the Azure Files account, Azure NetApp Files volume and scaling plan names and resource groups, when used;
- the Automation Account name and alert name prefix;
- the Az PowerShell module versions.

Keep `enabledAlertRuleIds` empty for the first deployment. Enable alerts after you confirm that the required diagnostic data is available.

When `createActionGroup` is `false`, set `existingActionGroup` with the existing Action Group's name and resource group. When it is `true`, the template creates the Action Group in the monitoring resource group and uses the configured `actionGroupEmailReceivers`.

For each resource, set `name` and `resourceGroupName`.

- Leave out `subscriptionId` when the resource is in the deployment subscription.
- For a resource in another subscription, add `subscriptionId` inside that resource's object.
- The session host VMs must be in the same resource group as their host pool. OS Disk Bandwidth alerts use that resource group.

```bicep
param logAnalyticsWorkspace = {
  subscriptionId: '<workspace-subscription-guid>'
  resourceGroupName: 'rg-monitoring'
  name: 'law-monitoring'
}

param hostPools = [
  {
    resourceGroupName: 'rg-avd'
    name: 'pool-production'
  }
  {
    subscriptionId: '<host-pool-subscription-guid>'
    resourceGroupName: 'rg-avd-personal'
    name: 'pool-personal'
    hostPoolType: 'Personal'
  }
]
```

Add one entry for each host pool to `hostPools`. `hostPoolType` is optional and defaults to `Pooled`; set it to `Personal` for a personal pool. Add scaling plans to `scalingPlans` as a separate list. The order of the two lists does not need to match.

## Optional data collection setup

The example keeps these options off. Turn on only the parts you want to deploy:

- `createLogAnalyticsWorkspace`: creates a workspace in the monitoring resource group. Set `newLogAnalyticsWorkspaceName`; the workspace uses the deployment `location` and the configured retention period.
- `deployAvdGuestDataDcr`: creates a Windows DCR for the `Perf` counters and Windows event logs used by the alerts. It collects System events, Application warnings and errors, Terminal Services events, and FSLogix events. It also includes per-process counters, which can increase data ingestion; check your expected Azure Monitor costs.
- `deployVmInsightsDcr`: creates a separate DCR for VM Insights `DetailedMetrics`. This is not needed by the alert queries in this project and can increase ingestion.
- `associateDcrsWithPolicy`: assigns Microsoft's built-in DCR association policy in each host-pool resource group for every DCR enabled above. The Azure Monitor Agent (AMA) must already be installed on the session hosts. The policy covers supported Windows VMs in those resource groups, not only VMs registered in the host pools. Add custom image resource IDs to `customWindowsImageIds` if needed.
- `configureAvdDiagnostics`: creates diagnostic settings on the host pools and the AVD workspaces listed in `avdWorkspaces`. It sends the categories used by AVD Insights to the selected Log Analytics workspace. It does not configure diagnostics on the Log Analytics workspace itself.

When enabling AVD diagnostics, add each Azure Virtual Desktop workspace (not the Log Analytics workspace) to `avdWorkspaces`:

```bicep
param avdWorkspaces = [
  {
    resourceGroupName: 'rg-avd'
    name: 'workspace-production'
  }
]
```

Set `dataCollectionRuleLocation` to the region of an existing Log Analytics workspace before deploying DCRs. When the template creates the workspace, it uses `location` for both the workspace and DCRs.

Azure Policy applies to new matching VMs after evaluation. After the first deployment, create a remediation task for each DCR policy assignment to associate existing VMs. The policy does not install AMA. If AMA is missing, install it before running remediation. New session hosts in the host-pool resource group are picked up by later policy evaluations.

Review existing diagnostic settings before setting `configureAvdDiagnostics` to `true`. Azure does not allow the same log category to be sent to the same workspace by multiple settings on one resource. This template creates a separate setting; it does not merge or change existing settings.

## Deploy

1. Create an Azure DevOps pipeline from `pipelines/avd-monitoring-baseline.yml`.
2. Check the `projectDir` variable in the YAML. Set it to this project's folder in your repository. That folder must contain `src/main.bicep` and `parameters/`. Pipeline steps run from that folder.
3. Open the pipeline variables and create these variables:
   - `parameterFile`: the path to your completed parameter file, relative to the project folder;
   - `serviceConnection`: the exact name of the Azure DevOps service connection.
4. Do not allow pipeline runs to change these variables. Authorize the pipeline to use the service connection.
5. Configure an approval check for the `avd-monitoring-baseline` environment in Azure DevOps.
6. Run the pipeline and review the what-if results saved by the pipeline.
7. Approve the deployment when the what-if looks correct.

The pipeline only runs when someone starts it. It builds and tests the solution first. After approval, it deploys the main template, waits for the required PowerShell modules, publishes the runbooks, then checks and updates the collector schedule links. This avoids errors when a schedule link already exists.

## Check the first deployment

In the Azure portal:

1. Open the new Automation Account.
2. Check that both runbooks are published.
3. Check the schedules and recent jobs.
4. Open the configured Log Analytics workspace and confirm that collector output is arriving.
5. Check `WVDAgentHealthStatus`, `Perf` and `Event` before enabling alerts that use those tables.

Start with the collector alerts:

- `collectorFailed`
- `collectorStale`

Then enable other alerts in small groups after checking their source data. The complete alert list is in the [technical documentation](technical-documentation.md).

## Privacy and support

Some collector output and alert queries can include assigned user names or FSLogix profile paths. Keep access to the Automation Account, workspace and Action Group restricted. Review alert recipients and retention settings before enabling these alerts.

This open-source project is an example. Test it outside production first. It is not an official Microsoft solution and Microsoft does not support it.

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
