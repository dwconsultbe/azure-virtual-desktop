targetScope = 'resourceGroup'

param location string
param hostPoolResourceId string
param sessionHostVmResourceGroupId string
param actionGroupResourceId string
param alertNamePrefix string
param enabledAlertRuleIds string[]

var hostPoolName = last(split(hostPoolResourceId, '/'))

var diskThresholds = [
  { id: 'osDiskBandwidth85', threshold: 85, severity: 2 }
  { id: 'osDiskBandwidth95', threshold: 95, severity: 1 }
]

resource diskBandwidthAlerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [for alert in diskThresholds: {
  name: '${alertNamePrefix}-${hostPoolName}-${alert.id}-${uniqueString(hostPoolResourceId)}'
  location: 'global'
  properties: {
    description: 'The OS disk bandwidth of a session host in ${hostPoolName} reached ${alert.threshold}%.'
    enabled: contains(enabledAlertRuleIds, alert.id)
    severity: alert.severity
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    autoMitigate: true
    scopes: [sessionHostVmResourceGroupId]
    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: location
    actions: [{ actionGroupId: actionGroupResourceId }]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [{
        name: alert.id
        criterionType: 'StaticThresholdCriterion'
        metricNamespace: 'Microsoft.Compute/virtualMachines'
        metricName: 'OS Disk Bandwidth Consumed Percentage'
        dimensions: [{
          name: 'LUN'
          operator: 'Include'
          values: ['*']
        }]
        timeAggregation: 'Average'
        operator: 'GreaterThanOrEqual'
        threshold: alert.threshold
      }]
    }
  }
}]
