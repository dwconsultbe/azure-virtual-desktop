targetScope = 'resourceGroup'

@description('Name of an existing session-host VM in this resource group.')
param vmName string

@description('Resource ID of the data collection rule.')
param dataCollectionRuleResourceId string

@description('Association name. One VM can have several associations, each with its own name.')
param associationName string

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource association 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: associationName
  scope: vm
  properties: {
    description: 'Sends AVD session host performance counters and event logs to Log Analytics.'
    dataCollectionRuleId: dataCollectionRuleResourceId
  }
}
