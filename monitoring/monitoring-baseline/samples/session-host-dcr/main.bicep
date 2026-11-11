// Optional sample: a data collection rule (DCR) for AVD session hosts.
// It collects the Perf and Event data that the monitoring baseline alerts read, plus the
// counters and logs that the AVD Insights workbook uses, so one rule serves both.
// Deploy it to any resource group; it does not install Azure Monitor Agent.
targetScope = 'resourceGroup'

@description('DCR name. AVD Insights only recognizes rules whose name starts with microsoft-avdi-.')
param dataCollectionRuleName string = 'microsoft-avdi-session-hosts'

@description('DCR region. Use the region of the session hosts.')
param location string = resourceGroup().location

@description('Resource ID of the existing Log Analytics workspace used by the monitoring baseline.')
param logAnalyticsWorkspaceResourceId string

@description('Seconds between performance counter samples. The memory alert needs at least two samples in 10 minutes.')
@minValue(10)
@maxValue(300)
param samplingFrequencyInSeconds int = 60

@description('Optional session-host VM resource IDs to associate with this rule. Repeat the deployment for new VMs, or use Azure Policy.')
param sessionHostVmResourceIds string[] = []

var workspaceDestination = 'workspace'

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dataCollectionRuleName
  location: location
  kind: 'Windows'
  properties: {
    description: 'AVD session host performance counters and event logs for the monitoring baseline and AVD Insights.'
    dataSources: {
      performanceCounters: [
        {
          name: 'avdPerformanceCounters'
          streams: ['Microsoft-Perf']
          samplingFrequencyInSeconds: samplingFrequencyInSeconds
          counterSpecifiers: [
            // Used by the baseline alerts (cpu, memory and local disk).
            '\\Processor Information(_Total)\\% Processor Time'
            '\\Memory\\Available MBytes'
            // The local disk alert checks every drive letter except D:. Add data disks here if needed.
            '\\LogicalDisk(C:)\\% Free Space'
            // Used by AVD Insights.
            '\\LogicalDisk(C:)\\Avg. Disk Queue Length'
            '\\LogicalDisk(C:)\\Current Disk Queue Length'
            '\\LogicalDisk(C:)\\Avg. Disk sec/Transfer'
            '\\Memory\\Page Faults/sec'
            '\\Memory\\Pages/sec'
            '\\Memory\\% Committed Bytes In Use'
            '\\PhysicalDisk(*)\\Avg. Disk Queue Length'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Read'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Transfer'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Write'
            '\\Process(*)\\% Processor Time'
            '\\Process(*)\\Working Set'
            '\\User Input Delay per Process(*)\\Max Input Delay'
            '\\User Input Delay per Session(*)\\Max Input Delay'
            '\\RemoteFX Network(*)\\Current TCP RTT'
            '\\RemoteFX Network(*)\\Current UDP Bandwidth'
            '\\Terminal Services(*)\\Active Sessions'
            '\\Terminal Services(*)\\Inactive Sessions'
            '\\Terminal Services(*)\\Total Sessions'
          ]
        }
      ]
      windowsEventLogs: [
        {
          name: 'avdEventLogs'
          streams: ['Microsoft-Event']
          xPathQueries: [
            // FSLogix Admin and Operational logs are used by the FSLogix alerts.
            'Microsoft-FSLogix-Apps/Admin!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]'
            'Microsoft-FSLogix-Apps/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]'
            // Used by AVD Insights.
            'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]'
            'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]'
            'System!*'
            'Application!*[System[(Level=2 or Level=3)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: workspaceDestination
          workspaceResourceId: logAnalyticsWorkspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Perf', 'Microsoft-Event']
        destinations: [workspaceDestination]
      }
    ]
  }
}

module associations 'modules/dcr-association.bicep' = [for (vmId, index) in sessionHostVmResourceIds: {
  name: 'dcr-association-${index}-${uniqueString(vmId)}'
  scope: resourceGroup(split(vmId, '/')[2], split(vmId, '/')[4])
  params: {
    vmName: last(split(vmId, '/'))
    dataCollectionRuleResourceId: dataCollectionRule.id
    associationName: '${dataCollectionRuleName}-association'
  }
}]

output dataCollectionRuleResourceId string = dataCollectionRule.id
