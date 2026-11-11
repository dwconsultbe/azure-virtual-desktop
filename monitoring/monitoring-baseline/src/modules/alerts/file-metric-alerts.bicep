targetScope = 'resourceGroup'

param storageAccountResourceId string
param actionGroupResourceId string
param alertNamePrefix string
param enabledAlertRuleIds string[]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: last(split(storageAccountResourceId, '/'))
  scope: resourceGroup(split(storageAccountResourceId, '/')[2], split(storageAccountResourceId, '/')[4])
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' existing = {
  parent: storageAccount
  name: 'default'
}

var fileMetrics = [
  { id: 'filesServerLatency50', metric: 'SuccessServerLatency', threshold: 50, severity: 2, operator: 'GreaterThan', window: 'PT15M' }
  { id: 'filesServerLatency100', metric: 'SuccessServerLatency', threshold: 100, severity: 1, operator: 'GreaterThan', window: 'PT15M' }
  { id: 'filesLatency50', metric: 'SuccessE2ELatency', threshold: 50, severity: 2, operator: 'GreaterThan', window: 'PT15M' }
  { id: 'filesLatency100', metric: 'SuccessE2ELatency', threshold: 100, severity: 1, operator: 'GreaterThan', window: 'PT15M' }
  { id: 'filesAvailability', metric: 'Availability', threshold: 99, severity: 1, operator: 'LessThanOrEqual', window: 'PT5M' }
]

resource fileAlerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [for item in fileMetrics: {
  name: '${alertNamePrefix}-${storageAccount.name}-${item.id}-${uniqueString(storageAccountResourceId)}'
  location: 'global'
  properties: {
    description: 'Azure Files ${item.metric} crossed ${item.threshold} on storage account ${storageAccount.name}. Check share and storage performance.'
    enabled: contains(enabledAlertRuleIds, item.id)
    severity: item.severity
    evaluationFrequency: 'PT5M'
    windowSize: item.window
    autoMitigate: true
    scopes: [fileService.id]
    targetResourceType: 'Microsoft.Storage/storageAccounts/fileServices'
    targetResourceRegion: storageAccount.location
    actions: [{ actionGroupId: actionGroupResourceId }]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [{
        name: item.id
        criterionType: 'StaticThresholdCriterion'
        metricNamespace: 'Microsoft.Storage/storageAccounts/fileServices'
        metricName: item.metric
        timeAggregation: 'Average'
        operator: item.operator
        threshold: item.threshold
      }]
    }
  }
}]

resource shareThrottling 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${alertNamePrefix}-${storageAccount.name}-files-throttling-${uniqueString(storageAccountResourceId)}'
  location: 'global'
  properties: {
    description: 'Azure Files transactions were throttled for a monitored file service on ${storageAccount.name}. Review IOPS and throughput limits.'
    enabled: contains(enabledAlertRuleIds, 'filesThrottling')
    severity: 2
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    autoMitigate: true
    scopes: [fileService.id]
    targetResourceType: 'Microsoft.Storage/storageAccounts/fileServices'
    targetResourceRegion: storageAccount.location
    actions: [{ actionGroupId: actionGroupResourceId }]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [{
        name: 'FilesThrottling'
        criterionType: 'StaticThresholdCriterion'
        metricNamespace: 'Microsoft.Storage/storageAccounts/fileServices'
        metricName: 'Transactions'
        timeAggregation: 'Total'
        operator: 'GreaterThanOrEqual'
        threshold: 1
        dimensions: [{
          name: 'ResponseType'
          operator: 'Include'
          values: [
            'SuccessWithThrottling'
            'SuccessWithShareIopsThrottling'
            'ClientShareIopsThrottlingError'
            'SuccessWithShareEgressThrottling'
            'SuccessWithShareIngressThrottling'
            'ClientShareEgressThrottlingError'
            'ClientShareIngressThrottlingError'
          ]
        }]
      }]
    }
  }
}
