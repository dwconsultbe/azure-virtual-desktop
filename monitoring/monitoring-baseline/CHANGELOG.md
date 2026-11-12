# Changelog

All notable changes to the AVD monitoring baseline. Versions follow [semantic versioning](https://semver.org/).

## 1.0.1 (2026-11-12)

Fewer alerts for short problems, for example while a session host starts.

### Alerts

- `healthCheckFailure` alerts only when a health check keeps failing for at least 5 minutes. A check that fails once while a session host starts, for example `DomainTrust` or `TURNRelayAccessHealthCheck`, no longer sends an alert.
- The `healthCheckFailure` alert data now includes `FirstFailure`, `LastFailure` and `FailedHeartbeats`.
- `cpu85` and `cpu95` ignore the first 10 minutes after a session host starts. Booting no longer looks like high CPU.
- The capacity alerts use the lower load of the last two collector runs, about 15 minutes apart. A short peak, for example before the scaling plan starts extra hosts, no longer sends an alert.
- `collectorFailed` alerts after two failed or suspended jobs in 45 minutes instead of one. `collectorStale` still reports a collector that stops completely.

## 1.0.0 (2026-11-11)

First public release.

### Deploy

- Deploy from your own machine with `./deploy.ps1`, or with the Azure DevOps pipeline.
- `deploy.ps1` checks the prerequisites, shows a summary and a what-if preview with a legend, and asks for confirmation.
- The pipeline runs without input: the service connection and parameter file are set once in the YAML.
- The deployment starts a first collector run, so data arrives within minutes.
- Uses an existing Log Analytics workspace. An optional [sample DCR](samples/session-host-dcr/README.md) sets up the session-host data.

### Alerts

- 45 alert rules for host pools, session hosts, FSLogix, scaling plans, Azure Files, Azure NetApp Files and Service Health.
- Alert sets: `core`, `hostPool`, `sessionHosts`, `resources`, `scaling`, `fslogix`, `storage`, `serviceHealth` and `all`. The example starts with `core`, which needs no session-host DCR.
- A typo in an alert set or alert ID fails the build.
- Alerts for the monitoring itself: failed collector jobs, missing collector output and missing AVD diagnostics.
- Tuned to report problems instead of single events, for example one `noResourcesAvailable` alert per host pool.

### Configuration

- `configureDiagnostics: false` for host pools that already send their diagnostics to the workspace, for example through AVD Insights.
- `hostPoolType` creates only the rules that fit a Pooled or Personal pool.
- Alert names include a unique value per host pool, so pools with the same name do not clash.

### Documentation

- Administrator guide, helpdesk guide and technical documentation with the full alert catalog.

### Credits

Based on Microsoft's [Azure Monitor Baseline Alerts for Azure Virtual Desktop](https://azure.github.io/azure-monitor-baseline-alerts/patterns/specialized/avd/deploy/Avd-Deploy/index.html). See the [README](README.md#credits).
