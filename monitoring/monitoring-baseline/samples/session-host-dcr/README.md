# Sample: session-host data collection rule

**For:** administrators who do not have a data collection rule (DCR) on their session hosts yet.

**Result:** a DCR that sends the performance counters and event logs the baseline alerts need to your Log Analytics workspace, optionally associated with your session hosts. It also collects what AVD Insights uses, so one DCR serves both.

## In 4 steps

1. [Check the prerequisites](#1-check-the-prerequisites)
2. [Fill in the parameter file](#2-fill-in-the-parameter-file)
3. [Deploy](#3-deploy)
4. [Check the data](#4-check-the-data)

## 1. Check the prerequisites

- [ ] **Azure Monitor Agent** is installed on every session host.
- [ ] Every session host has a **system-assigned managed identity**.
- [ ] You know the **resource ID** of the Log Analytics workspace.

Agent or identity missing? Run this per VM, or use Azure Policy or your image build:

```powershell
az vm identity assign --ids <vm-resource-id>
az vm extension set --ids <vm-resource-id> --name AzureMonitorWindowsAgent --publisher Microsoft.Azure.Monitor --enable-auto-upgrade true
```

> [!WARNING]
> **AVD Insights already configured?** Insights creates its own DCR, with a name that starts with `microsoft-avdi-`. Check whether it already collects the data in the table below. If it does, you do not need this sample. Two DCRs with the same counters on one VM ingest and bill the data twice.

## 2. Fill in the parameter file

Copy `main.example.bicepparam` to `main.bicepparam` and fill in:

| Setting | Required | What to enter | Default |
| --- | --- | --- | --- |
| `logAnalyticsWorkspaceResourceId` | Yes | Resource ID of the workspace used by the baseline | |
| `sessionHostVmResourceIds` | No | Resource IDs of the session hosts to associate | none |
| `dataCollectionRuleName` | No | Name of the DCR. Keep the `microsoft-avdi-` prefix if you use AVD Insights. | `microsoft-avdi-session-hosts` |
| `location` | No | Region of the DCR. Use the region of the session hosts. | Region of the resource group |
| `samplingFrequencyInSeconds` | No | Seconds between counter samples (10–300) | `60` |

## 3. Deploy

Deploy to a resource group, for example the monitoring resource group:

```powershell
az deployment group create --resource-group <monitoring-resource-group> --parameters main.bicepparam
```

> [!IMPORTANT]
> Only the VMs in `sessionHostVmResourceIds` are associated. For **new session hosts**, add them to the list and deploy again, or assign the DCR with the built-in Azure Policy *Configure Windows Machines to be associated with a Data Collection Rule*.

## 4. Check the data

After about 10 minutes, run this in the workspace:

```kusto
Perf
| where TimeGenerated > ago(15m)
| summarize Samples = count() by Computer, ObjectName, CounterName
```

Every session host should appear with processor, memory and disk counters.

## What it collects

| Data | Used by |
| --- | --- |
| `Processor Information(_Total)\% Processor Time` | Alerts `cpu85`, `cpu95` |
| `Memory\Available MBytes` | Alerts `memory2GB`, `memory1GB` |
| `LogicalDisk(C:)\% Free Space` | Alerts `localDiskFree10`, `localDiskFree5` |
| `Microsoft-FSLogix-Apps/Admin` and `/Operational` events | All `fslogix*` alerts |
| Disk, process, input delay, RemoteFX and Terminal Services counters; System, Application and Terminal Services events | AVD Insights |

> [!TIP]
> **Data disks?** The local disk alerts check every drive letter except `D:` (the temporary disk). Add for example `\LogicalDisk(E:)\% Free Space` to `main.bicep`.
>
> **Lower cost?** The `Process(*)` counters and `System!*` events produce most of the volume. Remove them if you do not use AVD Insights. The baseline alerts only need the first four rows of the table.
