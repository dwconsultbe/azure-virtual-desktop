# Azure Virtual Desktop monitoring baseline

Proactive alert rules for Azure Virtual Desktop, deployed with Bicep and an Azure DevOps pipeline. Covers host pools, session hosts, FSLogix, scaling plans, Azure Files, Azure NetApp Files and Service Health.

## Which document do I need?

| I want to... | Read |
| --- | --- |
| Deploy or maintain the baseline | [Administrator guide](docs/administrator-guide.md) |
| Understand and handle an alert | [Helpdesk guide](docs/helpdesk-guide.md) |
| See the design and the full alert list | [Technical documentation](docs/technical-documentation.md) |
| Set up data collection on the session hosts | [Sample DCR](samples/session-host-dcr/README.md) |

## What it deploys

| Resource | Purpose |
| --- | --- |
| Alert rules (disabled until you enable them) | Log, metric and Service Health alerts per host pool |
| Automation Account with two collectors | Gather capacity, scaling plan and file share data that Azure Monitor does not provide |
| Action Group | Sends the alerts by e-mail |
| Host-pool diagnostic settings (optional per pool) | Send AVD diagnostics to your workspace |

> [!IMPORTANT]
> The deployment uses an **existing** Log Analytics workspace. Azure Monitor Agent and a data collection rule on the session hosts must already be in place. The [sample DCR](samples/session-host-dcr/README.md) can set that up.

## Quick start

1. Check the prerequisites.
2. Fill in `parameters/main.example.bicepparam`.
3. Give the Azure DevOps service connection the required rights.
4. Run `pipelines/avd-monitoring-baseline.yml`.
5. Check the data and enable alerts step by step.

Each step is explained in the [administrator guide](docs/administrator-guide.md).

## Repository layout

| Path | Contents |
| --- | --- |
| `src/` | Bicep modules, KQL queries and collector scripts |
| `parameters/` | Example parameter file |
| `pipelines/` | Azure DevOps pipeline and deployment scripts |
| `samples/session-host-dcr/` | Optional data collection rule for the session hosts |
| `tests/` | Collector output tests |
| `docs/` | Administrator, helpdesk and technical documentation |

## Credits

The alert set is based on Microsoft's [Azure Monitor Baseline Alerts (AMBA) for Azure Virtual Desktop](https://azure.github.io/azure-monitor-baseline-alerts/patterns/specialized/avd/deploy/Avd-Deploy/index.html). Parts of the KQL and the collector data format are adapted from AMBA. [Durrante's AVDMonitoringBaseline](https://github.com/durrante/AVDMonitoringBaseline) was also reviewed during development. The MIT notice for adapted material is in the [administrator guide](docs/administrator-guide.md#sources-and-license-notice).

## Disclaimer

> [!WARNING]
> This is an open-source example, not an official Microsoft solution. It is provided under the MIT License, without warranty or support. A successful build or what-if does not prove that every alert works with your data. Review the templates, thresholds, permissions and costs, and test outside production first.
