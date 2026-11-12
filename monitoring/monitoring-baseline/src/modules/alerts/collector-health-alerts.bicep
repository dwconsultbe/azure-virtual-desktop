targetScope = 'resourceGroup'

import { fillQuery, queryRuleProperties, RuleContext } from '../../rules.bicep'

param location string
param logAnalyticsWorkspaceResourceId string
param actionGroupResourceId string
param alertNamePrefix string
param enabledAlertRuleIds string[]

@description('Name of the host pool collector runbook.')
param hostPoolRunbookName string

@description('Name of the storage collector runbook. Only monitored when includeStorageCollector is true.')
param storageRunbookName string

@description('True when storage collector schedules are deployed. Otherwise that runbook never runs and must not be reported as stale.')
param includeStorageCollector bool

var runbookNames = includeStorageCollector ? [hostPoolRunbookName, storageRunbookName] : [hostPoolRunbookName]
var runbookList = join(map(runbookNames, name => '\'${name}\''), ', ')

// The capacity, scaling plan, personal host and file share alerts read the collector output.
// When a collector stops or fails they find no rows and resolve as if nothing were wrong,
// so these two rules watch the collectors themselves.
var jobFailedQuery = fillQuery(loadTextContent('../../queries/collector-job-failed.kql'), { __RUNBOOKS__: runbookList })
var outputStaleQuery = fillQuery(loadTextContent('../../queries/collector-output-stale.kql'), { __RUNBOOKS__: runbookList })

var ruleContext RuleContext = {
  workspaceResourceId: logAnalyticsWorkspaceResourceId
  actionGroupResourceId: actionGroupResourceId
  enabledAlertRuleIds: enabledAlertRuleIds
}

var collectorAlerts = [
  {
    alertId: 'collectorFailed'
    shortName: 'collector-failed'
    displayName: 'AVD collector runbook job failed'
    description: 'At least two collector runbook jobs failed or were suspended in 45 minutes. Alerts that depend on collector output stop updating until the next successful run. Check the job Errors and Warnings in the Automation Account.'
    severity: 2
    evaluationFrequency: 'PT15M'
    windowSize: 'PT45M'
    query: jobFailedQuery
    dimensions: ['RunbookName_s']
  }
  {
    alertId: 'collectorStale'
    shortName: 'collector-stale'
    displayName: 'AVD collector output missing for 45 minutes'
    description: 'A collector runbook has written no output for 45 minutes. Alerts that depend on collector output are not evaluating real data. Check the schedules, the job history and the Automation Account diagnostic settings.'
    severity: 2
    evaluationFrequency: 'PT15M'
    windowSize: 'PT2H'
    query: outputStaleQuery
    dimensions: ['RunbookName_s']
  }
]

resource alertRules 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in collectorAlerts: {
  name: '${alertNamePrefix}-${alert.shortName}-${uniqueString(logAnalyticsWorkspaceResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, alert)
}]
