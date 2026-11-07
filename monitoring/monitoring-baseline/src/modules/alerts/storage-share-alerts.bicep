targetScope = 'resourceGroup'

import { storageCollectorName } from '../../naming.bicep'
import { fillQuery, queryRuleProperties, RuleContext } from '../../rules.bicep'

param location string
param storageAccountResourceId string
param logAnalyticsWorkspaceResourceId string
param actionGroupResourceId string
param alertNamePrefix string
param customerName string
param enabledAlertRuleIds string[]

var storageAccountName = last(split(storageAccountResourceId, '/'))
var descriptionPrefix = empty(customerName) ? '' : 'Customer: ${customerName}. '

var ruleContext RuleContext = {
  workspaceResourceId: logAnalyticsWorkspaceResourceId
  actionGroupResourceId: actionGroupResourceId
  enabledAlertRuleIds: enabledAlertRuleIds
}

// The collector reports share ID in field 8. Group by share ID, never share name alone.
var shareQuery = fillQuery(loadTextContent('../../queries/share-capacity.kql'), {
  __STORAGE_ID__: storageAccountResourceId
  __RUNBOOK__: storageCollectorName(alertNamePrefix)
})

var thresholds = [
  { id: 'fileShareCapacity15', shortName: 'file-share-free-15', threshold: 15, severity: 2 }
  { id: 'fileShareCapacity5', shortName: 'file-share-free-5', threshold: 5, severity: 1 }
]

resource shareCapacityAlerts 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in thresholds: {
  name: '${alertNamePrefix}-${alert.shortName}-${uniqueString(storageAccountResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: alert.id
    displayName: 'Azure Files share at or below ${alert.threshold}% free (${storageAccountName})'
    description: '${descriptionPrefix}A monitored Azure Files share has ${alert.threshold}% or less of its quota remaining. The alert value is the free percentage. Increase quota or free space.'
    severity: alert.severity
    evaluationFrequency: 'PT10M'
    windowSize: 'PT1H'
    query: '${shareQuery}\n| where PercentAvailable <= ${alert.threshold}'
    dimensions: ['StorageAccount', 'Share']
    timeAggregation: 'Minimum'
    metricMeasureColumn: 'PercentAvailable'
    operator: 'LessThanOrEqual'
    threshold: alert.threshold
  })
}]
