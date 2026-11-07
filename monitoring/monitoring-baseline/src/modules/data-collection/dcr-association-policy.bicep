param assignmentName string
param assignmentLocation string
param dataCollectionRuleResourceId string
param windowsImageIds array = []

resource assignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: assignmentName
  location: assignmentLocation
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Associate Windows VMs with the AVD monitoring DCR'
    description: 'Associates supported Windows VMs in this resource group with an Azure Monitor data collection rule.'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/eab1f514-22e3-42e3-9a1f-e1dc9199355c'
    parameters: {
      effect: {
        value: 'DeployIfNotExists'
      }
      scopeToSupportedImages: {
        value: true
      }
      listOfWindowsImageIdToInclude: {
        value: windowsImageIds
      }
      DcrResourceId: {
        value: dataCollectionRuleResourceId
      }
      resourceType: {
        value: 'Microsoft.Insights/dataCollectionRules'
      }
    }
  }
}

var monitoringContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '749f88d5-cbae-40b8-bcfc-e573ddc772fa')

resource remediationRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, assignmentName, monitoringContributorRoleId)
  properties: {
    principalId: assignment.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: monitoringContributorRoleId
  }
}

output assignmentId string = assignment.id
output principalId string = assignment.identity.principalId
