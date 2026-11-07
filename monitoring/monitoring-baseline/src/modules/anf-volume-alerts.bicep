targetScope = 'resourceGroup'

param volumeResourceId string
param actionGroupResourceId string
param alertNamePrefix string
param customerName string
param enabledAlertRuleIds string[]

resource volume 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes@2024-07-01' existing = {
  name: '${split(volumeResourceId, '/')[8]}/${split(volumeResourceId, '/')[10]}/${split(volumeResourceId, '/')[12]}'
  scope: resourceGroup(split(volumeResourceId, '/')[2], split(volumeResourceId, '/')[4])
}

var volumeName = last(split(volumeResourceId, '/'))
var descriptionPrefix = empty(customerName) ? '' : 'Customer: ${customerName}. '
var thresholds = [
  { id: 'anfVolumeFree15', consumed: 85, severity: 2 }
  { id: 'anfVolumeFree5', consumed: 95, severity: 1 }
]

resource volumeAlerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [for alert in thresholds: {
  name: '${alertNamePrefix}-${alert.id}-${uniqueString(volumeResourceId)}'
  location: 'global'
  properties: {
    description: '${descriptionPrefix}Azure NetApp Files volume ${volumeName} has reached ${alert.consumed}% consumed capacity. Expand the volume or free space.'
    enabled: contains(enabledAlertRuleIds, alert.id)
    severity: alert.severity
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    autoMitigate: true
    scopes: [volumeResourceId]
    targetResourceType: 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes'
    targetResourceRegion: volume.location
    actions: [{ actionGroupId: actionGroupResourceId }]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [{
        name: alert.id
        criterionType: 'StaticThresholdCriterion'
        metricNamespace: 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes'
        metricName: 'VolumeConsumedSizePercentage'
        timeAggregation: 'Average'
        operator: 'GreaterThanOrEqual'
        threshold: alert.consumed
      }]
    }
  }
}]
