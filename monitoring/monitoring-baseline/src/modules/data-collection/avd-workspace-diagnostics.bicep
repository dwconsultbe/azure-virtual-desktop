param avdWorkspaceName string
param diagnosticSettingName string
param logAnalyticsWorkspaceResourceId string

resource avdWorkspace 'Microsoft.DesktopVirtualization/workspaces@2024-04-03' existing = {
  name: avdWorkspaceName
}

var categories = [
  'Management'
  'Feed'
  'Error'
  'Checkpoint'
]

resource diagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingName
  scope: avdWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspaceResourceId
    logs: [for category in categories: {
      category: category
      enabled: true
      retentionPolicy: {
        enabled: false
        days: 0
      }
    }]
    metrics: []
  }
}

output resourceId string = diagnosticSetting.id
