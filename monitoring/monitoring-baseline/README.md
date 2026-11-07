# Proactive Azure Virtual Desktop monitoring with alert rules

This repository contains Bicep templates and an Azure DevOps pipeline for monitoring Azure Virtual Desktop host pools, session hosts, FSLogix and storage. It is an independent project.

## 🏅 Credits

This project's alert set is based on Microsoft's [Azure Monitor Baseline Alerts for Azure Virtual Desktop](https://azure.github.io/azure-monitor-baseline-alerts/patterns/specialized/avd/deploy/Avd-Deploy/index.html). Parts of the KQL queries and the collector data format were also adapted from AMBA. I also reviewed [Durrante's AVDMonitoringBaseline](https://github.com/durrante/AVDMonitoringBaseline) during development. The Bicep templates, pipeline, query files and deployment steps were developed for this project.

Microsoft does not provide or support this project. See the [administrator guide](docs/administrator-guide.md) for the original MIT license notice.

Here, a **collector** is a PowerShell runbook in Azure Automation that gathers extra monitoring data.

## What it deploys

- Azure Monitor alert rules for host pools, session hosts, FSLogix, Azure Files, Azure NetApp Files and Service Health.
- An Azure Automation Account with two PowerShell collectors.
- Alerts that check the collectors, with runs spread out over time.
- KQL queries stored as separate files.
- A pipeline that builds the Bicep templates, runs tests and shows a what-if preview before deployment. Deployment waits for approval only when an approval check is set on the Azure DevOps environment.

## Before you deploy

Read the [administrator guide](docs/administrator-guide.md) first. It explains the values you need to change and the permissions needed by the Azure DevOps service connection and the Automation Account identity.

The example parameter file is not ready to deploy. Replace every `REPLACE_*` value first. The pipeline stops if any are left. Review the what-if output. If you set an approval check, do this before approving the deployment.

## Repository layout

- `src/`: Bicep modules, KQL queries and PowerShell collectors.
- `parameters/`: example deployment parameters.
- `pipelines/`: Azure DevOps pipeline definition.
- `tests/`: tests that check the data returned by the collectors.
- `docs/`: administrator, helpdesk and technical documentation.

## Validation status

The collector tests pass locally. A successful Bicep build or what-if preview does not prove that every alert works with live Azure data. Test the diagnostics, permissions, collectors and alert rules in a test subscription before using this in production.

## Disclaimer

This open-source project is an example of monitoring an Azure Virtual Desktop environment. It is not an official Microsoft solution, and it has not been tested with every Azure setup.

Before deployment, review the templates, queries, permissions, alert thresholds and Azure costs. Test the solution outside production first.

This project is provided under the MIT License, without warranty or official support.
