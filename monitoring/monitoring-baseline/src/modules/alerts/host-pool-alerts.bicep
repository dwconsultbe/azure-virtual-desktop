targetScope = 'resourceGroup'

import { fillQuery, hostPoolVmsFragment, queryRuleProperties, RuleContext } from '../../rules.bicep'

param location string
param hostPoolResourceId string
param logAnalyticsWorkspaceResourceId string
param actionGroupResourceId string
param alertNamePrefix string
param customerName string
param enabledAlertRuleIds string[]
param includeAutoscaleFailures bool

var hostPoolName = last(split(hostPoolResourceId, '/'))
var descriptionPrefix = empty(customerName) ? '' : 'Customer: ${customerName}. '

var queryValues = {
  __HOST_POOL_ID__: hostPoolResourceId
  __HOST_POOL_VMS__: hostPoolVmsFragment
}

var ruleContext RuleContext = {
  workspaceResourceId: logAnalyticsWorkspaceResourceId
  actionGroupResourceId: actionGroupResourceId
  enabledAlertRuleIds: enabledAlertRuleIds
}

// The query logic is adapted from the MIT-licensed Microsoft AMBA AVD pattern.
// Stable dimensions keep a persistent problem in one alert instance.
var alertDefinitions = [
  {
    alertId: 'agentUpgrade'
    shortName: 'agent-upgrade'
    displayName: 'AVD agent upgrade failed or stuck (${hostPoolName})'
    description: '${descriptionPrefix}The AVD agent failed to upgrade for over one hour or has been upgrading for over two hours. Drained hosts and normal Pending or Initial states are excluded.'
    severity: 3
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    query: fillQuery(loadTextContent('../../queries/agent-upgrade.kql'), queryValues)
    dimensions: ['SessionHostName', 'SessionHostRG', 'Problem']
  }
  {
    alertId: 'drainedIdle'
    shortName: 'drained-idle'
    displayName: 'AVD session host drained and idle for 24 hours (${hostPoolName})'
    description: '${descriptionPrefix}A session host has stayed in drain mode, powered on, and without sessions for 24 hours. Deallocate or return it to service.'
    severity: 3
    evaluationFrequency: 'PT1H'
    windowSize: 'P1D'
    query: fillQuery(loadTextContent('../../queries/drained-idle.kql'), queryValues)
    dimensions: ['SessionHostName', 'SessionHostRG']
  }
  {
    alertId: 'autoscaleFailures'
    shortName: 'autoscale-failures'
    displayName: 'AVD autoscale failures (${hostPoolName})'
    description: '${descriptionPrefix}At least two autoscale evaluations failed and none succeeded during the past hour. Check LastErrorCode in the query results. Requires pooled autoscale diagnostic logs.'
    severity: 3
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    query: fillQuery(loadTextContent('../../queries/autoscale-failures.kql'), queryValues)
    dimensions: ['ScalingPlanName']
  }
]

resource alertRules 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in alertDefinitions: if (alert.alertId != 'autoscaleFailures' || includeAutoscaleFailures) {
  name: '${alertNamePrefix}-${hostPoolName}-${alert.shortName}-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, alert)
}]

var memoryThresholds = [
  { id: 'memory2GB', mb: 2048, severity: 2 }
  { id: 'memory1GB', mb: 1024, severity: 1 }
]

resource memoryAlerts 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for threshold in memoryThresholds: {
  name: '${alertNamePrefix}-${hostPoolName}-${threshold.id}-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: threshold.id
    displayName: 'AVD available memory below ${threshold.mb} MB (${hostPoolName})'
    description: '${descriptionPrefix}The 15-minute average available memory on a session host is at or below ${threshold.mb} MB. Hosts with less than 10 minutes of samples are excluded. Investigate memory use and session density.'
    severity: threshold.severity
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    query: fillQuery(loadTextContent('../../queries/available-memory.kql'), queryValues)
    dimensions: ['SessionHostName']
    timeAggregation: 'Minimum'
    metricMeasureColumn: 'AvailableMB'
    operator: 'LessThanOrEqual'
    threshold: threshold.mb
  })
}]
