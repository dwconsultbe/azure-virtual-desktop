targetScope = 'resourceGroup'

import { fillQuery, hostPoolVmsFragment, queryRuleProperties, RuleContext } from '../../rules.bicep'

param location string
param hostPoolResourceId string
param logAnalyticsWorkspaceResourceId string
param actionGroupResourceId string
param alertNamePrefix string
param enabledAlertRuleIds string[]

@description('Failed connections with the same error within 15 minutes before connectionFailure fires.')
@minValue(1)
param connectionFailureMinFailures int = 5

@description('Distinct users affected by those failed connections before connectionFailure fires.')
@minValue(1)
param connectionFailureMinUsers int = 3

@description('WVDErrors CodeSymbolic values that connectionFailure ignores, for errors that are known noise in this environment.')
param ignoredConnectionErrorCodes string[] = []

var hostPoolName = last(split(hostPoolResourceId, '/'))

var queryValues = {
  __HOST_POOL_ID__: hostPoolResourceId
  __HOST_POOL_VMS__: hostPoolVmsFragment
}

var ruleContext RuleContext = {
  workspaceResourceId: logAnalyticsWorkspaceResourceId
  actionGroupResourceId: actionGroupResourceId
  enabledAlertRuleIds: enabledAlertRuleIds
}

var diskThresholds = [
  { id: 'localDiskFree10', threshold: 10, severity: 2 }
  { id: 'localDiskFree5', threshold: 5, severity: 1 }
]

var localDiskQuery = fillQuery(loadTextContent('../../queries/local-disk.kql'), queryValues)

var cpuThresholds = [
  { id: 'cpu85', threshold: 85, severity: 2, evaluationFrequency: 'PT30M', windowSize: 'PT1H' }
  { id: 'cpu95', threshold: 95, severity: 1, evaluationFrequency: 'PT5M', windowSize: 'PT15M' }
]

var cpuQuery = fillQuery(loadTextContent('../../queries/cpu-usage.kql'), queryValues)

resource localDiskAlerts 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in diskThresholds: {
  name: '${alertNamePrefix}-${hostPoolName}-${alert.id}-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: alert.id
    displayName: 'AVD local disk below ${alert.threshold}% free (${hostPoolName})'
    description: 'A session host local disk has ${alert.threshold}% or less free space. The alert value is free disk percentage. Check disk use and available capacity.'
    severity: alert.severity
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    query: '${localDiskQuery}\n| where FreePercent <= ${alert.threshold}'
    dimensions: ['SessionHostName', 'Disk']
    timeAggregation: 'Minimum'
    metricMeasureColumn: 'FreePercent'
    operator: 'LessThanOrEqual'
    threshold: alert.threshold
  })
}]

resource cpuAlerts 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in cpuThresholds: {
  name: '${alertNamePrefix}-${hostPoolName}-${alert.id}-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: alert.id
    displayName: 'AVD session host CPU above ${alert.threshold}% (${hostPoolName})'
    description: 'A session host has average CPU usage at or above ${alert.threshold}%. The alert value is the average CPU percentage.'
    severity: alert.severity
    evaluationFrequency: alert.evaluationFrequency
    windowSize: alert.windowSize
    query: '${cpuQuery}\n| where CpuPercent >= ${alert.threshold}'
    dimensions: ['SessionHostName']
    timeAggregation: 'Maximum'
    metricMeasureColumn: 'CpuPercent'
    operator: 'GreaterThanOrEqual'
    threshold: alert.threshold
  })
}]

resource healthCheckFailure 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: '${alertNamePrefix}-${hostPoolName}-health-check-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: 'healthCheckFailure'
    displayName: 'AVD session host health check failed (${hostPoolName})'
    description: 'A session host health check failed. The health check name and host are in the alert dimensions, including checks 11 and 19.'
    severity: 1
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    query: fillQuery(loadTextContent('../../queries/health-check.kql'), queryValues)
    dimensions: ['SessionHostName', 'SessionHostRG', 'HealthCheckDesc']
  })
}

// Single failed connections are normal (wrong password, closed client). The rule reports a
// pattern: several failures with the same error, affecting several users. Grouping by error
// code only catches both one bad host and a pool-wide problem that spreads over several hosts.
var ignoredCodesFilter = empty(ignoredConnectionErrorCodes) ? '' : '| where CodeSymbolic !in~ (${join(map(ignoredConnectionErrorCodes, code => '\'${code}\''), ', ')})\n'

var connectionFailureQuery = fillQuery(loadTextContent('../../queries/connection-failure.kql'), union(queryValues, {
  __IGNORED_FILTER__: ignoredCodesFilter
  __MIN_FAILURES__: string(connectionFailureMinFailures)
  __MIN_USERS__: string(connectionFailureMinUsers)
}))

resource connectionFailure 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: '${alertNamePrefix}-${hostPoolName}-connection-failure-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: 'connectionFailure'
    displayName: 'AVD user connection failed (${hostPoolName})'
    description: 'At least ${connectionFailureMinFailures} connections from ${connectionFailureMinUsers} or more users failed with the same error in the last 15 minutes. The query results show the error code and the affected session hosts.'
    severity: 3
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    query: connectionFailureQuery
    dimensions: ['ErrorShort']
  })
}

resource noResourcesAvailable 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: '${alertNamePrefix}-${hostPoolName}-no-resources-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: 'noResourcesAvailable'
    displayName: 'AVD no resources available (${hostPoolName})'
    description: 'Connections failed because no healthy session host was available. One alert per host pool; the query results show the number of failed connections and affected users, with example user names. Check host health, drain mode and autoscale.'
    severity: 1
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    query: fillQuery(loadTextContent('../../queries/no-resources.kql'), queryValues)
    dimensions: ['HostPoolName']
  })
}
