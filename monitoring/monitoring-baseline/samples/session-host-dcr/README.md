# Sample: session-host data collection rule

The monitoring baseline does not create a data collection rule (DCR). This optional sample creates one that sends the `Perf` and `Event` data the alerts need to your Log Analytics workspace. It also collects the counters and event logs that the AVD Insights workbook uses, so one DCR can serve both.

## What it collects

| Data | Used by |
| --- | --- |
| `Processor Information(_Total)\% Processor Time` | `cpu85`, `cpu95` |
| `Memory\Available MBytes` | `memory2GB`, `memory1GB` |
| `LogicalDisk(C:)\% Free Space` | `localDiskFree10`, `localDiskFree5` |
| `Microsoft-FSLogix-Apps/Admin` and `/Operational` events | all `fslogix*` alerts |
| Other disk, process, input delay, RemoteFX and Terminal Services counters; System, Application and Terminal Services events | AVD Insights |

The local disk alert checks every drive letter except `D:` (the temporary disk). Add `\LogicalDisk(E:)\% Free Space` or similar if your session hosts have data disks.

## Before you deploy

- **Azure Monitor Agent** must be installed on every session host, with a system-assigned managed identity. This sample does not install it. Use Azure Policy, your image build, or for example:

  ```powershell
  az vm identity assign --ids <vm-resource-id>
  az vm extension set --ids <vm-resource-id> --name AzureMonitorWindowsAgent --publisher Microsoft.Azure.Monitor --enable-auto-upgrade true
  ```

- **AVD Insights already configured?** Insights creates a DCR whose name starts with `microsoft-avdi-`. Check whether that rule already collects the data in the table above. If it does, you do not need this sample. Do not associate two DCRs with the same counters to one VM, because that ingests and bills the data twice.

## Deploy

1. Copy `main.example.bicepparam`, set the workspace resource ID and optionally list the session-host VM resource IDs.
2. Deploy to a resource group, preferably the monitoring resource group:

   ```powershell
   az deployment group create --resource-group <monitoring-resource-group> --parameters main.bicepparam
   ```

3. Within about 10 minutes, check the workspace:

   ```kusto
   Perf
   | where TimeGenerated > ago(15m)
   | summarize Samples = count() by Computer, ObjectName, CounterName
   ```

Associations are created only for the VMs you list. Add new session hosts to the list and deploy again, or assign the DCR with Azure Policy (built-in: *Configure Windows Machines to be associated with a Data Collection Rule*).

## Sampling and cost

`samplingFrequencyInSeconds` defaults to 60. The `Process(*)` counters and `System!*` produce most of the volume. Remove them if you do not use AVD Insights. The baseline alerts only need the first three counters and the FSLogix logs.
