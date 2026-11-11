# Technical documentation

**For:** maintainers and reviewers who want to know how the baseline works.

**Contents:** architecture, data sources, design choices, naming, the full alert catalog and how it relates to AMBA.

Deploying? Use the [administrator guide](administrator-guide.md). Handling alerts? Use the [helpdesk guide](helpdesk-guide.md).

## Architecture

[![Azure Virtual Desktop monitoring architecture](images/avd-monitoring-architecture.png)](images/avd-monitoring-architecture.png)

[Editable Draw.io source](images/avd-monitoring-architecture.drawio)

| Component | Created by the deployment | Purpose |
| --- | --- | --- |
| Log Analytics workspace | No, existing | Stores all data that the log alerts query |
| Azure Monitor Agent + DCR | No, existing ([sample](../samples/session-host-dcr/README.md)) | Sends performance counters and events from the session hosts |
| Host-pool diagnostic setting | Yes (optional per pool) | Sends AVD diagnostics to the workspace |
| Automation Account + 2 runbooks | Yes | The **collectors**: gather data that Azure Monitor does not provide |
| Automation schedules | Yes | Run each collector every 15 minutes (4 hourly schedules, 15 minutes apart) |
| Alert rules | Yes, disabled | Log, metric and Service Health alerts |
| Action Group | Yes | Sends the e-mail notifications |

> [!NOTE]
> A **collector** is a PowerShell runbook in Azure Automation. The host pool collector reports capacity, sessions, unhealthy personal hosts and scaling plan state. The storage collector reports Azure Files share usage. The storage collector only runs when Azure Files accounts are configured.

## Where the data comes from

| Data | Source | Table | Used by |
| --- | --- | --- | --- |
| Connections, errors, agent health, autoscale | Host-pool diagnostic setting | `WVDConnections`, `WVDErrors`, `WVDAgentHealthStatus`, `WVDAutoscaleEvaluationPooled` | Connection, health, agent and autoscale alerts |
| CPU, memory, disk | DCR on the session hosts | `Perf` | Resource alerts |
| FSLogix events | DCR on the session hosts | `Event` | FSLogix alerts |
| Host pool capacity, scaling plan state, personal hosts | Host pool collector | `AzureDiagnostics` (JobStreams) | Capacity, scaling and personal host alerts |
| Azure Files share usage | Storage collector | `AzureDiagnostics` (JobStreams) | File share capacity alerts |
| Collector job status | Automation diagnostic setting | `AzureDiagnostics` (JobLogs) | Collector health alerts |
| OS disk bandwidth, Azure Files, Azure NetApp Files | Azure platform metrics | Metrics | Metric alerts |
| Microsoft incidents and maintenance | Activity log | Service Health | Service Health alerts |

## Design choices

| Choice | Why |
| --- | --- |
| Every rule is deployed; only the chosen **alert sets** and IDs are **enabled** | You switch alerts on only after their data arrives, so the mailbox stays trustworthy. |
| Alert sets and IDs are **typed** in `src/alert-sets.bicep` | A typo fails the build instead of leaving an alert silently disabled. `tests/alert-ids.ps1` checks that the list matches the modules. |
| The deployment starts a **first collector run** | Data arrives within minutes, and `collectorStale` does not fire on a new installation. |
| Each KQL query is a **separate file** in `src/queries/` | Easy to read, test in Log Analytics and review. Bicep fills in placeholders such as `__HOST_POOL_ID__`. |
| Collectors use the **managed identity** | No stored credentials. The identity only gets read roles. |
| `hostPoolType` decides the **pool-specific rules** | Pooled pools get capacity alerts. Personal pools get the unhealthy assigned host alert. |
| Alerts are **stateful** (auto-resolve) | One e-mail when a problem starts and one when it is resolved, not one every evaluation. |
| The DCR is a **prerequisite**, not part of the deployment | Many environments already have one through AVD Insights. A second DCR would ingest and bill the same data twice. |
| Collectors **keep going** when one host pool or storage account fails | The other pools still report; the job still fails at the end, so `collectorFailed` fires. |

## Naming

| Resource | Name |
| --- | --- |
| Alert rule (per host pool) | `<prefix>-avd-ar-<host pool>-<alert>-<unique>` |
| Alert rule (per storage account) | `<prefix>-avd-ar-<storage account>-<alert>-<unique>` |
| Collector alert rules | `<prefix>-avd-ar-collector-failed-<unique>`, `...-collector-stale-<unique>` |
| Automation Account | `<prefix>-aa-avd-<unique>` |
| Action Group | `<prefix>-ag-avd-<unique>` |
| Runbooks | `avd-host-pool-collector`, `avd-storage-collector` |
| Host-pool diagnostic setting | `avd-baseline-<unique>` |

`<prefix>` is the optional `resourcePrefix` (without a prefix, names start with `avd-ar-`, `aa-avd-` or `ag-avd-`). `<unique>` is derived from the full resource ID, so host pools with the same name in different resource groups do not clash.

> [!IMPORTANT]
> Azure does not rename resources. A changed name creates a **new** resource and leaves the old one in place. This also applies when you change `hostPoolType`: delete the capacity or personal-unhealthy rules that no longer fit.

## Alert sets

Switch alerts on per set in `additionalResources.alertSets`, or per ID in `additionalResources.enabledAlertRuleIds`. Both can be combined. The sets are defined in `src/alert-sets.bicep`.

| Set | Alert IDs |
| --- | --- |
| `core` | `collectorFailed`, `collectorStale`, `diagnosticDataMissing`, `noResourcesAvailable`, `healthCheckFailure`, `capacity95`, `personalUnhealthy`, `serviceHealthIncident` |
| `hostPool` | `capacity50`, `capacity85`, `capacity95`, `connectionFailure`, `noResourcesAvailable` |
| `sessionHosts` | `healthCheckFailure`, `personalUnhealthy`, `agentUpgrade`, `drainedIdle` |
| `resources` | `cpu85`, `cpu95`, `memory2GB`, `memory1GB`, `localDiskFree10`, `localDiskFree5`, `osDiskBandwidth85`, `osDiskBandwidth95` |
| `scaling` | `scalingPlanDisabled4h`, `scalingPlanDisabled24h`, `scalingPlanRemoved`, `autoscaleFailures` |
| `fslogix` | `fslogixFree5`, `fslogixFree2`, `fslogixDiskInUse`, `fslogixAttach`, `fslogixNetwork`, `fslogixServiceDisabled`, `fslogixCompaction` |
| `storage` | `fileShareCapacity15`, `fileShareCapacity5`, `filesAvailability`, `filesLatency50`, `filesLatency100`, `filesServerLatency50`, `filesServerLatency100`, `filesThrottling`, `anfVolumeFree15`, `anfVolumeFree5` |
| `serviceHealth` | `serviceHealthIncident`, `serviceHealthMaintenance`, `serviceHealthAdvisory`, `serviceHealthSecurity` |
| `all` | All of the above |

`core` only uses data that the baseline sets up itself (AVD diagnostics and the collectors), so it works without a session-host DCR. A rule that does not apply is simply not created: for example `capacity95` on a Personal pool, or `storage` without storage accounts.

## Alert catalog

The name of each alert rule contains the short name shown in the [helpdesk guide](helpdesk-guide.md).

Frequency = how often the rule runs. Window = how much data it looks at.

### Monitoring health

| ID | Alert | Sev | Frequency / window | Data |
| --- | --- | --- | --- | --- |
| `collectorFailed` | Collector runbook job failed or suspended | 2 | 15 min / 30 min | Automation job logs |
| `collectorStale` | No collector output for 45 minutes | 2 | 15 min / 2 h | Collector output |
| `diagnosticDataMissing` | Collector sees sessions, but no AVD agent health data for 1 hour | 2 | 15 min / 1 h | Collector + `WVDAgentHealthStatus` |

`collectorFailed` and `collectorStale` are shared by all host pools. All other rules are created per host pool or per storage account.

### Host pool capacity and connections

| ID | Alert | Sev | Frequency / window | Data |
| --- | --- | --- | --- | --- |
| `capacity50` | Host pool load 50% to 85% (Pooled only) | 3 | 5 min / 30 min | Collector |
| `capacity85` | Host pool load 85% to 95% (Pooled only) | 2 | 5 min / 30 min | Collector |
| `capacity95` | Host pool load 95% or more (Pooled only) | 1 | 5 min / 30 min | Collector |
| `connectionFailure` | 5+ failed connections from 3+ users with the same error in 15 min | 3 | 15 min / 15 min | `WVDConnections`, `WVDErrors` |
| `noResourcesAvailable` | Connections failed because no session host was available (one alert per host pool) | 1 | 15 min / 15 min | `WVDConnections`, `WVDErrors` |

Load = sessions ÷ (max sessions per host × available hosts). With autoscale, the capacity alerts can fire during a normal scale-out.

### Session host health

| ID | Alert | Sev | Frequency / window | Data |
| --- | --- | --- | --- | --- |
| `healthCheckFailure` | A session host health check failed | 1 | 15 min / 15 min | `WVDAgentHealthStatus` |
| `personalUnhealthy` | Assigned personal host unhealthy in 2 runs in a row (Personal only) | 1 | 5 min / 45 min | Collector |
| `agentUpgrade` | AVD agent upgrade failed for 1 h or stuck for 2 h | 3 | 1 h / 1 h | `WVDAgentHealthStatus` |
| `drainedIdle` | Host in drain mode, running and empty for 24 h | 3 | 1 h / 1 day | `WVDAgentHealthStatus` |
| `autoscaleFailures` | 2+ failed autoscale evaluations and none succeeded in 1 h (Pooled with a scaling plan) | 3 | 15 min / 1 h | `WVDAutoscaleEvaluationPooled` |

### Session host resources

| ID | Alert | Sev | Frequency / window | Data |
| --- | --- | --- | --- | --- |
| `cpu85` | Average CPU 85% or more | 2 | 30 min / 1 h | `Perf` |
| `cpu95` | Average CPU 95% or more | 1 | 5 min / 15 min | `Perf` |
| `memory2GB` | Available memory 2 GB or less | 2 | 5 min / 15 min | `Perf` |
| `memory1GB` | Available memory 1 GB or less | 1 | 5 min / 15 min | `Perf` |
| `localDiskFree10` | A drive (except `D:`) has 10% free or less | 2 | 15 min / 15 min | `Perf` |
| `localDiskFree5` | A drive (except `D:`) has 5% free or less | 1 | 15 min / 15 min | `Perf` |
| `osDiskBandwidth85` | OS disk bandwidth 85% or more | 2 | 5 min / 15 min | VM metric |
| `osDiskBandwidth95` | OS disk bandwidth 95% or more | 1 | 5 min / 15 min | VM metric |

### Scaling plan

| ID | Alert | Sev | Frequency / window | Data |
| --- | --- | --- | --- | --- |
| `scalingPlanDisabled4h` | Scaling plan disabled for 4 hours | 3 | 30 min / 4 h | Collector |
| `scalingPlanDisabled24h` | Scaling plan disabled for 24 hours | 2 | 6 h / 1 day | Collector |
| `scalingPlanRemoved` | Scaling plan removed from the host pool for 4 hours | 3 | 1 h / 6 h | Collector |

### FSLogix

| ID | Alert | Sev | Frequency / window | Data |
| --- | --- | --- | --- | --- |
| `fslogixFree5` | Profile below 5% free (event 34) | 2 | 5 min / 15 min | `Event` |
| `fslogixFree2` | Profile below 2% free (event 33) | 1 | 5 min / 15 min | `Event` |
| `fslogixDiskInUse` | Profile disk in use on another VM (event 51) | 2 | 5 min / 30 min | `Event` |
| `fslogixAttach` | Profile disk failed to attach (events 40, 52) | 1 | 5 min / 1 h | `Event` |
| `fslogixNetwork` | Profile failed due to a network issue (event 43) | 1 | 5 min / 1 h | `Event` |
| `fslogixServiceDisabled` | Profile service disabled (event 60) | 1 | 5 min / 1 h | `Event` |
| `fslogixCompaction` | Profile disk compaction failed (events 62, 63) | 2 | 5 min / 1 h | `Event` |

### Azure Files (only when `fileStorageAccounts` is set)

| ID | Alert | Sev | Frequency / window | Data |
| --- | --- | --- | --- | --- |
| `fileShareCapacity15` | A share has 15% of its quota free or less | 2 | 10 min / 1 h | Storage collector |
| `fileShareCapacity5` | A share has 5% of its quota free or less | 1 | 10 min / 1 h | Storage collector |
| `filesAvailability` | Availability 99% or less | 1 | 5 min / 5 min | Metric |
| `filesLatency50` | End-to-end latency above 50 ms | 2 | 5 min / 15 min | Metric |
| `filesLatency100` | End-to-end latency above 100 ms | 1 | 5 min / 15 min | Metric |
| `filesServerLatency50` | Server latency above 50 ms | 2 | 5 min / 15 min | Metric |
| `filesServerLatency100` | Server latency above 100 ms | 1 | 5 min / 15 min | Metric |
| `filesThrottling` | Transactions were throttled | 2 | 5 min / 15 min | Metric |

> [!TIP]
> The latency thresholds suit Premium file shares. On Standard shares, 50 ms is often normal; raise the thresholds or leave these alerts off.

### Azure NetApp Files (only when `anfVolumes` is set)

| ID | Alert | Sev | Frequency / window | Data |
| --- | --- | --- | --- | --- |
| `anfVolumeFree15` | Volume 85% full or more | 2 | 1 h / 1 h | Metric |
| `anfVolumeFree5` | Volume 95% full or more | 1 | 1 h / 1 h | Metric |

### Service Health (deployment subscription)

| ID | Alert |
| --- | --- |
| `serviceHealthIncident` | Microsoft reports an AVD incident |
| `serviceHealthMaintenance` | Microsoft plans AVD maintenance |
| `serviceHealthAdvisory` | Information or action required for AVD |
| `serviceHealthSecurity` | Security notice for AVD |

## How this project relates to AMBA

Most alert ideas, parts of the KQL and the collector output format come from the [AMBA pattern for Azure Virtual Desktop](https://azure.github.io/azure-monitor-baseline-alerts/patterns/specialized/avd/deploy/Avd-Deploy/index.html). The differences are mainly in packaging and operation:

| Area | This project | AMBA |
| --- | --- | --- |
| Deployment | Azure DevOps pipeline with build, tests and what-if | Portal form |
| Queries | One `.kql` file per query | Mostly inline in the Bicep template |
| Alert selection | Enable individual rules by ID | Selection in the deployment form |
| Pool type | `hostPoolType` decides which pool-specific rules exist | Personal-host health query available |
| Collector scripts | Stored with the code and published by the pipeline | Loaded from a separate location |
| Schedules | Later runs update the existing runbook links | |
| 24/72-hour disconnected-session rules | Left out: the query measures connection duration, not time disconnected | Included |

Source: [AMBA AVD Bicep template](https://github.com/Azure/azure-monitor-baseline-alerts/blob/main/patterns/avd/templates/deploy.bicep), [deployment UI](https://github.com/Azure/azure-monitor-baseline-alerts/blob/main/patterns/avd/avdCustomUi.json), [AVD pattern folder](https://github.com/Azure/azure-monitor-baseline-alerts/tree/main/patterns/avd). This project is not an official Microsoft product.

## Repository map

| Path | Contents |
| --- | --- |
| `src/main.bicep` | Main template (subscription scope) |
| `src/modules/alerts/` | Alert rules and Action Group |
| `src/modules/collectors/` | Automation Account, runbooks, collector roles |
| `src/modules/data-collection/` | Host-pool diagnostic settings |
| `src/queries/` | KQL for the log alerts |
| `src/scripts/` | Collector runbooks |
| `src/collector-schedules.bicep` | Automation schedules |
| `src/alert-sets.bicep` | Alert IDs and alert sets |
| `src/rules.bicep`, `src/naming.bicep` | Shared rule properties and names |
| `deploy.ps1` | Deploy from your own machine |
| `parameters/` | Example parameter file |
| `pipelines/` | Pipeline, step template and deployment scripts |
| `samples/session-host-dcr/` | Optional DCR for the session hosts |
| `tests/` | Collector output and alert ID tests |
