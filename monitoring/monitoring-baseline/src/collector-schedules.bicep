targetScope = 'resourceGroup'

import { azureFilesScheduleName, hostPoolScheduleName } from 'naming.bicep'

@description('Existing collector Automation Account name.')
param automationAccountName string

@description('Prefix that the runbook and schedule names are derived from. Use the alertNamePrefix of the main deployment.')
param namePrefix string

@description('Azure Files storage account resource IDs, passed to the storage runbook.')
param fileStorageAccountResourceIds string[] = []

@description('UTC timestamp at least five minutes in the future. Four hourly schedules are staggered by 15 minutes.')
param scheduleStartTime string = utcNow()

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' existing = {
  name: automationAccountName
}

var offsets = [15, 30, 45, 60]

resource hostSchedules 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = [for (offset, index) in offsets: {
  parent: automationAccount
  name: hostPoolScheduleName(namePrefix, index)
  properties: {
    description: 'Hourly AVD host pool collector, offset ${offset} minutes.'
    frequency: 'Hour'
    interval: 1
    startTime: dateTimeAdd(scheduleStartTime, 'PT${offset}M')
    timeZone: 'Etc/UTC'
  }
}]
resource storageSchedules 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = [for (offset, index) in offsets: if (!empty(fileStorageAccountResourceIds)) {
  parent: automationAccount
  name: azureFilesScheduleName(namePrefix, index)
  properties: {
    description: 'Hourly Azure Files collector, offset ${offset} minutes.'
    frequency: 'Hour'
    interval: 1
    startTime: dateTimeAdd(scheduleStartTime, 'PT${offset}M')
    timeZone: 'Etc/UTC'
  }
}]

