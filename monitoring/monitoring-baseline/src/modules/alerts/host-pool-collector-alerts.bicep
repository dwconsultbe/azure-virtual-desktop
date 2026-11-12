targetScope = 'resourceGroup'

import { hostPoolCollectorName } from '../../naming.bicep'
import { collectorRowsFragment, fillQuery, queryRuleProperties, RuleContext } from '../../rules.bicep'

param location string
param hostPoolResourceId string
param hostPoolType string
param logAnalyticsWorkspaceResourceId string
param actionGroupResourceId string
param alertNamePrefix string
param enabledAlertRuleIds string[]

var hostPoolName = last(split(hostPoolResourceId, '/'))
var ruleContext RuleContext = {
  workspaceResourceId: logAnalyticsWorkspaceResourceId
  actionGroupResourceId: actionGroupResourceId
  enabledAlertRuleIds: enabledAlertRuleIds
}

// The collector emits 15 pipe-delimited fields. Field 12 is the full host pool ID.
// Use the ID as the filter because host pool names need not be unique across subscriptions.
var queryValues = {
  __COLLECTOR_ROWS__: collectorRowsFragment
  __HOST_POOL_ID__: hostPoolResourceId
  __RUNBOOK__: hostPoolCollectorName()
}

// Pooled host pools only: Personal pools have no meaningful session limit, so their load
// would be near 0 or a misleading 100. Their hosts are covered by personalUnhealthy.
var capacityQuery = fillQuery(loadTextContent('../../queries/capacity.kql'), queryValues)

var capacityBands = [
  { id: 'capacity50', shortName: 'capacity-50', lower: 50, upper: 85, severity: 3 }
  { id: 'capacity85', shortName: 'capacity-85', lower: 85, upper: 95, severity: 2 }
  { id: 'capacity95', shortName: 'capacity-95', lower: 95, upper: 101, severity: 1 }
]

resource capacityAlerts 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for band in capacityBands: if (hostPoolType == 'Pooled') {
  name: '${alertNamePrefix}-${hostPoolName}-${band.shortName}-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: band.id
    displayName: 'AVD host pool capacity at least ${band.lower}% (${hostPoolName})'
    description: 'The last two collector runs, 15 minutes apart, both report host pool load at or above ${band.lower}%. The alert value is the load percentage. Check session capacity, unavailable hosts and autoscale.'
    severity: band.severity
    evaluationFrequency: 'PT5M'
    windowSize: 'PT45M'
    query: '${capacityQuery}\n| where HostPoolPercentLoad >= ${band.lower}${band.lower == 95 ? '' : ' and HostPoolPercentLoad < ${band.upper}'}'
    dimensions: ['HostPoolName']
    timeAggregation: 'Maximum'
    metricMeasureColumn: 'HostPoolPercentLoad'
    threshold: band.lower
  })
}]

var scalingDisabledDefinitions = [
  { id: 'scalingPlanDisabled4h', shortName: 'scaling-disabled-4h', hours: 4, minRuns: 12, severity: 3, frequency: 'PT30M', window: 'PT4H' }
  { id: 'scalingPlanDisabled24h', shortName: 'scaling-disabled-24h', hours: 24, minRuns: 72, severity: 2, frequency: 'PT6H', window: 'P1D' }
]

var scalingDisabledTemplate = loadTextContent('../../queries/scaling-disabled.kql')

resource scalingDisabledAlerts 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in scalingDisabledDefinitions: {
  name: '${alertNamePrefix}-${hostPoolName}-${alert.shortName}-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: alert.id
    displayName: 'AVD scaling plan disabled over ${alert.hours} hours (${hostPoolName})'
    description: 'Autoscale has been disabled on this host pool for over ${alert.hours} hours. Review the scaling plan assignment and re-enable autoscale when maintenance ends.'
    severity: alert.severity
    evaluationFrequency: alert.frequency
    windowSize: alert.window
    query: fillQuery(scalingDisabledTemplate, union(queryValues, {
      __HOURS__: string(alert.hours)
      __MIN_RUNS__: string(alert.minRuns)
    }))
    dimensions: ['HostPoolName', 'ScalingPlanName']
  })
}]

var otherAlerts = [
  {
    alertId: 'scalingPlanRemoved'
    shortName: 'scaling-removed'
    displayName: 'AVD scaling plan removed (${hostPoolName})'
    description: 'A scaling plan was removed from this host pool and has not been restored for four hours. The alert fires once per removal. Review the scaling plan Activity Log and assignment.'
    severity: 3
    evaluationFrequency: 'PT1H'
    windowSize: 'PT6H'
    query: fillQuery(loadTextContent('../../queries/scaling-removed.kql'), queryValues)
    dimensions: ['HostPoolName', 'RemovedScalingPlan']
  }
  {
    alertId: 'diagnosticDataMissing'
    shortName: 'diagnostic-data-missing'
    displayName: 'AVD diagnostic data not received (${hostPoolName})'
    description: 'The collector reports active sessions in every recent run, but no agent health diagnostics reached the workspace for one hour. Check the host pool diagnostic settings and workspace destination.'
    severity: 2
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    query: fillQuery(loadTextContent('../../queries/diagnostic-missing.kql'), queryValues)
    dimensions: ['HostPoolName']
  }
]

resource otherAlertRules 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in otherAlerts: {
  name: '${alertNamePrefix}-${hostPoolName}-${alert.shortName}-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, alert)
}]

// A host must be unhealthy in at least two collector runs, and still in the latest one, so a
// restart or a VM starting on connect does not alert. Hosts with status Shutdown (stopped or
// deallocated) are excluded by the collector.
resource personalUnhealthy 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = if (hostPoolType == 'Personal') {
  name: '${alertNamePrefix}-${hostPoolName}-personal-unhealthy-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: 'personalUnhealthy'
    displayName: 'AVD assigned personal host unhealthy (${hostPoolName})'
    description: 'An assigned personal session host has been unhealthy in at least two consecutive collector runs. Hosts with status Shutdown (stopped or deallocated) are not counted. Check the assigned user and the host status.'
    severity: 1
    evaluationFrequency: 'PT5M'
    windowSize: 'PT45M'
    query: fillQuery(loadTextContent('../../queries/personal-unhealthy.kql'), queryValues)
    dimensions: ['HostPoolName', 'PersonalSessionHost', 'PersonalAssignedUser']
  })
}
