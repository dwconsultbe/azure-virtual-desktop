param hostPoolName string
param diagnosticSettingName string
param logAnalyticsWorkspaceResourceId string
param includeAutoscaleFailures bool = false

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2024-04-03' existing = {
  name: hostPoolName
}

var categories = concat([
  'Management'
  'Connection'
  'Error'
  'Checkpoint'
  'HostRegistration'
  'AgentHealthStatus'
], includeAutoscaleFailures ? [
  'AutoscaleEvaluationPooled'
] : [])

resource diagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingName
  scope: hostPool
  properties: {
    workspaceId: logAnalyticsWorkspaceResourceId
    logs: [for category in categories: {
      category: category
      enabled: true
    }]
    metrics: []
  }
}

output resourceId string = diagnosticSetting.id
