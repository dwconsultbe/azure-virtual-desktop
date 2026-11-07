targetScope = 'resourceGroup'

param actionGroupResourceId string
param alertNamePrefix string
param enabledAlertRuleIds string[]
param serviceHealthServiceName string

var incidentTypes = [
  { id: 'serviceHealthIncident', shortName: 'incident', types: ['Incident'] }
  { id: 'serviceHealthMaintenance', shortName: 'maintenance', types: ['Maintenance'] }
  { id: 'serviceHealthAdvisory', shortName: 'advisory', types: ['Informational', 'ActionRequired'] }
  { id: 'serviceHealthSecurity', shortName: 'security', types: ['Security'] }
]

resource serviceHealthAlerts 'Microsoft.Insights/activityLogAlerts@2020-10-01' = [for incident in incidentTypes: {
  name: '${alertNamePrefix}-service-health-${incident.shortName}'
  location: 'global'
  properties: {
    enabled: contains(enabledAlertRuleIds, incident.id)
    scopes: [subscription().id]
    condition: {
      allOf: [
        { field: 'category', equals: 'ServiceHealth' }
        { field: 'properties.impactedServices[*].ServiceName', containsAny: [serviceHealthServiceName] }
        { anyOf: [for type in incident.types: { field: 'properties.incidentType', equals: type }] }
      ]
    }
    actions: { actionGroups: [{ actionGroupId: actionGroupResourceId }] }
  }
}]
