param ruleName string
param location string
param logAnalyticsWorkspaceResourceId string

var performanceCounters = [
  '\\LogicalDisk(C:)\\Avg. Disk Queue Length'
  '\\LogicalDisk(C:)\\Current Disk Queue Length'
  '\\Memory\\Available MBytes'
  '\\Memory\\Page Faults/sec'
  '\\Memory\\Pages/sec'
  '\\Memory\\% Committed Bytes In Use'
  '\\PhysicalDisk(*)\\Avg. Disk Queue Length'
  '\\PhysicalDisk(*)\\Avg. Disk sec/Read'
  '\\PhysicalDisk(*)\\Avg. Disk sec/Transfer'
  '\\PhysicalDisk(*)\\Avg. Disk sec/Write'
  '\\Processor(_Total)\\% Processor Time'
  '\\Processor Information(_Total)\\% Processor Time'
  '\\Process(*)\\% Processor Time'
  '\\Process(*)\\Working Set'
  '\\User Input Delay per Process(*)\\Max Input Delay'
  '\\User Input Delay per Session(*)\\Max Input Delay'
  '\\RemoteFX Network(*)\\Current TCP RTT'
  '\\RemoteFX Network(*)\\Current UDP Bandwidth'
  '\\LogicalDisk(*)\\% Free Space'
  '\\LogicalDisk(*)\\Avg. Disk sec/Transfer'
  '\\Terminal Services(*)\\Active Sessions'
  '\\Terminal Services(*)\\Inactive Sessions'
  '\\Terminal Services(*)\\Total Sessions'
]

var windowsEventQueries = [
  'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]'
  'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]'
  'System!*'
  'Microsoft-FSLogix-Apps/Operational!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]'
  'Microsoft-FSLogix-Apps/Admin!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]'
  'Application!*[System[(Level=2 or Level=3)]]'
]

resource rule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: ruleName
  location: location
  kind: 'Windows'
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'avdPerformanceCounters'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 180
          counterSpecifiers: performanceCounters
        }
      ]
      windowsEventLogs: [
        {
          name: 'avdWindowsEvents'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: windowsEventQueries
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'avdLogAnalytics'
          workspaceResourceId: logAnalyticsWorkspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
          'Microsoft-Event'
        ]
        destinations: [
          'avdLogAnalytics'
        ]
      }
    ]
  }
}

output resourceId string = rule.id
output name string = rule.name
