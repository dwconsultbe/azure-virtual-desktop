targetScope = 'resourceGroup'

import { hostPoolCollectorName, jobDiagnosticsName, storageCollectorName } from '../../naming.bicep'

param location string
param automationAccountName string

@description('Prefix that the runbook and diagnostic setting names are derived from.')
param namePrefix string
param logAnalyticsWorkspaceResourceId string

@description('Pinned PowerShell Gallery versions of the Az modules the collector runbooks need, keyed by module name.')
param azModuleVersions object

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
  }
}

// Az.Accounts must be imported first: the other two modules depend on it. batchSize(1)
// deploys the modules one at a time in list order. The import itself continues in
// Azure Automation after this deployment ends; the pipeline waits for it.
var azModuleNames = [
  'Az.Accounts'
  'Az.DesktopVirtualization'
  'Az.Storage'
]

@batchSize(1)
resource azModules 'Microsoft.Automation/automationAccounts/modules@2023-11-01' = [for moduleName in azModuleNames: {
  parent: automationAccount
  name: moduleName
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/${moduleName}/${azModuleVersions[moduleName]}'
      version: azModuleVersions[moduleName]
    }
  }
}]

resource jobDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: jobDiagnosticsName(namePrefix)
  scope: automationAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceResourceId
    logs: [
      { category: 'JobLogs', enabled: true }
      { category: 'JobStreams', enabled: true }
    ]
  }
}

resource hostPoolRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: hostPoolCollectorName()
  location: location
  dependsOn: [azModules]
  properties: {
    description: 'Collects selected AVD host pool and scaling plan state for Azure Monitor.'
    runbookType: 'PowerShell'
    logProgress: false
    logVerbose: false
  }
}

resource storageRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: storageCollectorName()
  location: location
  dependsOn: [azModules]
  properties: {
    description: 'Collects selected Azure Files share capacity for Azure Monitor.'
    runbookType: 'PowerShell'
    logProgress: false
    logVerbose: false
  }
}

output hostPoolRunbookName string = hostPoolRunbook.name
output storageRunbookName string = storageRunbook.name
output principalId string = automationAccount.identity.principalId
output automationAccountResourceId string = automationAccount.id
