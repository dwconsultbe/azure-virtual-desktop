param workspaceName string
param location string
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    retentionInDays: retentionInDays
  }
}

output resourceId string = workspace.id
output name string = workspace.name
output location string = workspace.location
output customerId string = workspace.properties.customerId
