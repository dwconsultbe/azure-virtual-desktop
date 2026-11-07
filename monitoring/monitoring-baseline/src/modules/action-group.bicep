targetScope = 'resourceGroup'

@description('Name of the Action Group.')
param actionGroupName string

@description('Short name shown in notifications.')
@maxLength(12)
param actionGroupShortName string

@description('Email receivers for the Action Group.')
param emailReceivers array = []

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: emailReceivers
  }
}

output resourceId string = actionGroup.id
