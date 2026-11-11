targetScope = 'resourceGroup'

import { fillQuery, hostPoolVmsFragment, queryRuleProperties, RuleContext } from '../../rules.bicep'

param location string
param hostPoolResourceId string
param logAnalyticsWorkspaceResourceId string
param actionGroupResourceId string
param alertNamePrefix string
param enabledAlertRuleIds string[]

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

// Adapted from the MIT-licensed AMBA AVD FSLogix Event ID 51 alert. The inner
// join confines events to session hosts in this host pool.
resource profileDiskInUse 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: '${alertNamePrefix}-${hostPoolName}-fslogix-disk-in-use-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: 'fslogixDiskInUse'
    displayName: 'FSLogix profile disk in use on another VM (${hostPoolName})'
    description: 'FSLogix Event ID 51 indicates a profile disk is already in use. Investigate the user, profile path, and session host.'
    severity: 2
    evaluationFrequency: 'PT5M'
    windowSize: 'PT30M'
    query: fillQuery(loadTextContent('../../queries/fslogix-disk-in-use.kql'), queryValues)
    dimensions: ['SessionHostName', 'UserName', 'ProfilePath']
  })
}

// Window and grouping decide how many alerts a problem produces. The alerts are stateful
// (autoMitigate): while matching events keep arriving inside the window, one alert stays open
// and sends no new notification, and it resolves by itself once the last event is older than
// the window. A short window therefore resolves quickly, and the 15-minute free-space windows
// also survive a few minutes of Event ingestion delay.
// perUser = false collapses the alert to the session host, because these problems are caused
// by the host or by the storage behind it. The query result still shows how many users were
// affected. Free-space warnings stay per user, because each profile is a separate problem.
var fslogixEvents = [
  { alertId: 'fslogixFree5', shortName: 'free-5', title: 'Profile below 5% free', eventIds: '34', level: 'Warning', window: 'PT15M', lookback: '15m', severity: 2, perUser: true }
  { alertId: 'fslogixFree2', shortName: 'free-2', title: 'Profile below 2% free', eventIds: '33', level: 'Error', window: 'PT15M', lookback: '15m', severity: 1, perUser: true }
  { alertId: 'fslogixNetwork', shortName: 'network', title: 'Profile failed due to network issue', eventIds: '43', level: 'Error', window: 'PT1H', lookback: '1h', severity: 1, perUser: false }
  { alertId: 'fslogixAttach', shortName: 'attach', title: 'Profile disk failed to attach', eventIds: '52, 40', level: 'Error', window: 'PT1H', lookback: '1h', severity: 1, perUser: false }
  { alertId: 'fslogixServiceDisabled', shortName: 'service-disabled', title: 'Profile service disabled', eventIds: '60', level: 'Warning', window: 'PT1H', lookback: '1h', severity: 1, perUser: false }
  { alertId: 'fslogixCompaction', shortName: 'compaction', title: 'Profile disk compaction failed', eventIds: '62, 63', level: 'Error', window: 'PT1H', lookback: '1h', severity: 2, perUser: false }
]

var perUserOutput = '| project SessionHostName, UserName, RenderedDescription'
var perHostOutput = '| summarize Events = count(), Users = dcount(UserName), LastEvent = max(TimeGenerated), Example = take_any(RenderedDescription) by SessionHostName'

var fslogixQueryTemplate = loadTextContent('../../queries/fslogix-event.kql')

resource fslogixEventAlerts 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in fslogixEvents: {
  name: '${alertNamePrefix}-${hostPoolName}-fslogix-${alert.shortName}-${uniqueString(hostPoolResourceId)}'
  location: location
  kind: 'LogAlert'
  properties: queryRuleProperties(ruleContext, {
    alertId: alert.alertId
    displayName: 'FSLogix ${alert.title} (${hostPoolName})'
    description: 'FSLogix reports: ${alert.title}. ${alert.perUser ? 'Inspect the event description, user and session host.' : 'One alert per session host; the query result shows the number of affected users and an example event.'}'
    severity: alert.severity
    evaluationFrequency: 'PT5M'
    windowSize: alert.window
    query: fillQuery(fslogixQueryTemplate, union(queryValues, {
      __WINDOW__: alert.lookback
      __LEVEL__: alert.level
      __EVENT_IDS__: alert.eventIds
      __OUTPUT__: alert.perUser ? perUserOutput : perHostOutput
    }))
    dimensions: alert.perUser ? ['SessionHostName', 'UserName'] : ['SessionHostName']
  })
}]
