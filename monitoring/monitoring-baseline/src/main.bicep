targetScope = 'subscription'

import { AlertRuleId, AlertSet, alertSetDefinitions } from 'alert-sets.bicep'

type WorkspaceReference = {
  subscriptionId: string?
  resourceGroupName: string
  name: string
}

type DeploymentConfig = {
  location: string
  notificationEmail: string
  logAnalyticsWorkspace: WorkspaceReference
  @description('Monitoring resource group. Keep this name stable: changing it creates a new Automation Account, Action Group and alert rules.')
  @minLength(1)
  @maxLength(90)
  monitoringResourceGroupName: string
  resourcePrefix: string?
}

type AzureResourceReference = {
  subscriptionId: string?
  resourceGroupName: string
  name: string
}

type AnfVolumeReference = {
  subscriptionId: string?
  resourceGroupName: string
  netAppAccountName: string
  capacityPoolName: string
  name: string
}

type HostPoolConfig = {
  subscriptionId: string?
  resourceGroupName: string
  name: string
  hostPoolType: ('Pooled' | 'Personal')?
  scalingPlanName: string?
  @description('Defaults to true. Set to false when the host pool already sends its diagnostics to the workspace, for example through AVD Insights.')
  configureDiagnostics: bool?
}

type AdditionalResources = {
  fileStorageAccounts: AzureResourceReference[]?
  anfVolumes: AnfVolumeReference[]?
  @description('Alert sets to enable, for example [\'core\']. See src/alert-sets.bicep.')
  alertSets: AlertSet[]?
  @description('Individual alert IDs to enable, on top of the alert sets.')
  enabledAlertRuleIds: AlertRuleId[]?
}

@description('Deployment region, alert email, existing Log Analytics workspace, monitoring resource group name and optional resource prefix.')
param deployment DeploymentConfig

@description('Host pools to monitor. Add subscriptionId only for pools in another subscription. Set hostPoolType to Personal only for personal pools. A scaling plan, when used, belongs to this host pool.')
@minLength(1)
param hostPools HostPoolConfig[]

@description('Optional storage resources and alert selection. Leave empty for the standard host-pool deployment.')
param additionalResources AdditionalResources = {}

var monitoringResourceGroupName = deployment.monitoringResourceGroupName
var collectorNamePrefix = 'avd-${uniqueString(subscription().subscriptionId, monitoringResourceGroupName)}'
var configuredResourcePrefix = deployment.?resourcePrefix ?? ''
var automationAccountPrefix = empty(configuredResourcePrefix) ? '' : '${take(configuredResourcePrefix, 29)}-'
var alertNamePrefix = empty(configuredResourcePrefix) ? 'avd-ar' : '${configuredResourcePrefix}-avd-ar'
var automationAccountName = take('${automationAccountPrefix}aa-${collectorNamePrefix}', 50)
var actionGroupName = empty(configuredResourcePrefix) ? 'ag-${collectorNamePrefix}' : '${configuredResourcePrefix}-ag-${collectorNamePrefix}'
var actionGroupShortName = take(collectorNamePrefix, 12)
var actionGroupEmailReceivers = [
  {
    name: 'AVD monitoring'
    emailAddress: deployment.notificationEmail
    useCommonAlertSchema: true
  }
]
var alertSetRuleIds = flatten(map(additionalResources.?alertSets ?? [], set => alertSetDefinitions[set]))
var enabledAlertRuleIds = union(alertSetRuleIds, additionalResources.?enabledAlertRuleIds ?? [])
var azModuleVersions = {
  'Az.Accounts': '5.5.3'
  'Az.DesktopVirtualization': '6.0.0'
  'Az.Storage': '9.7.2'
}
var connectionFailureMinFailures = 5
var connectionFailureMinUsers = 3
var ignoredConnectionErrorCodes = [
  'ActivityTimeout'
  'AccountExpired'
  'AccountLockedOut'
  'AuthenticationLogonFailed'
  'AutoReconnectNoCookie'
  'CM_ERR_MISSED_HEARTBEAT_THRESHOLD_EXCEEDED'
  'ConnectionBrokenMissedHeartbeatThresholdExceeded'
  'ConnectionFailedClientDisconnect'
  'ConnectionFailedNoHealthyRdshAvailable'
  'FreshCredsRequired'
  'InvalidCredentials'
  'LogonFailed'
  'NL_DISCONNECT_ERROR'
  'PasswordExpired'
  'SavedCredentialsNotAllowed'
]
var serviceHealthServiceName = 'Azure Virtual Desktop'

resource monitoringResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: monitoringResourceGroupName
  location: deployment.location
  tags: {
    solution: 'avd-monitoring-baseline'
  }
}

var location = deployment.location

var logAnalyticsWorkspaceResourceId = resourceId(deployment.logAnalyticsWorkspace.?subscriptionId ?? subscription().subscriptionId, deployment.logAnalyticsWorkspace.resourceGroupName, 'Microsoft.OperationalInsights/workspaces', deployment.logAnalyticsWorkspace.name)
var hostPoolResourceIds = [for pool in hostPools: resourceId(pool.?subscriptionId ?? subscription().subscriptionId, pool.resourceGroupName, 'Microsoft.DesktopVirtualization/hostPools', pool.name)]
var hostPoolResourceGroups = [for pool in hostPools: toLower('/subscriptions/${pool.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${pool.resourceGroupName}')]
var poolsWithScalingPlans = filter(hostPools, pool => !empty(pool.?scalingPlanName ?? ''))
var scalingPlanResourceIds = [for pool in poolsWithScalingPlans: resourceId(pool.?subscriptionId ?? subscription().subscriptionId, pool.resourceGroupName, 'Microsoft.DesktopVirtualization/scalingPlans', pool.scalingPlanName!)]
var scalingPlanResourceGroups = [for pool in poolsWithScalingPlans: toLower('/subscriptions/${pool.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${pool.resourceGroupName}')]
var avdReaderResourceGroups = union(hostPoolResourceGroups, scalingPlanResourceGroups)
var fileStorageAccounts = additionalResources.?fileStorageAccounts ?? []
var anfVolumes = additionalResources.?anfVolumes ?? []
var fileStorageAccountResourceIds = [for account in fileStorageAccounts: resourceId(account.?subscriptionId ?? subscription().subscriptionId, account.resourceGroupName, 'Microsoft.Storage/storageAccounts', account.name)]
var anfVolumeResourceIds = [for volume in anfVolumes: resourceId(volume.?subscriptionId ?? subscription().subscriptionId, volume.resourceGroupName, 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes', volume.netAppAccountName, volume.capacityPoolName, volume.name)]
var storageResourceGroups = [for account in fileStorageAccounts: toLower('/subscriptions/${account.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${account.resourceGroupName}')]
var storageReaderResourceGroups = union(storageResourceGroups, [])

module actionGroup 'modules/alerts/action-group.bicep' = {
  name: 'avd-action-group'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    actionGroupName: actionGroupName
    actionGroupShortName: actionGroupShortName
    emailReceivers: actionGroupEmailReceivers
  }
}

module hostPoolDiagnostics 'modules/data-collection/avd-host-pool-diagnostics.bicep' = [for (pool, index) in hostPools: if (pool.?configureDiagnostics ?? true) {
  name: 'avd-host-pool-diagnostics-${index}-${uniqueString(hostPoolResourceIds[index])}'
  scope: resourceGroup(split(hostPoolResourceIds[index], '/')[2], split(hostPoolResourceIds[index], '/')[4])
  params: {
    hostPoolName: last(split(hostPoolResourceIds[index], '/'))
    diagnosticSettingName: take('avd-baseline-${uniqueString(hostPoolResourceIds[index])}', 64)
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    includeAutoscaleFailures: (pool.?hostPoolType ?? 'Pooled') == 'Pooled' && !empty(pool.?scalingPlanName ?? '')
  }
}]

var effectiveActionGroupResourceId = actionGroup.outputs.resourceId

module collectorInfrastructure 'modules/collectors/collector-infrastructure.bicep' = {
  name: 'avd-collector-infrastructure'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    location: location
    automationAccountName: automationAccountName
    namePrefix: collectorNamePrefix
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    azModuleVersions: azModuleVersions
  }
}

module collectorHealthAlerts 'modules/alerts/collector-health-alerts.bicep' = {
  name: 'avd-collector-health-alerts'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    location: location
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
    hostPoolRunbookName: collectorInfrastructure.outputs.hostPoolRunbookName
    storageRunbookName: collectorInfrastructure.outputs.storageRunbookName
    includeStorageCollector: !empty(fileStorageAccountResourceIds)
  }
}

module avdReader 'modules/collectors/collector-reader-role.bicep' = [for (rgId, index) in avdReaderResourceGroups: {
  name: 'avd-collector-avd-reader-${index}-${uniqueString(rgId)}'
  scope: resourceGroup(split(rgId, '/')[2], split(rgId, '/')[4])
  params: {
    principalId: collectorInfrastructure.outputs.principalId
    roleDefinitionGuid: '49a72310-ab8d-41df-bbb0-79b649203868'
  }
}]

module storageReader 'modules/collectors/collector-reader-role.bicep' = [for (rgId, index) in storageReaderResourceGroups: {
  name: 'avd-collector-storage-reader-${index}-${uniqueString(rgId)}'
  scope: resourceGroup(split(rgId, '/')[2], split(rgId, '/')[4])
  params: {
    principalId: collectorInfrastructure.outputs.principalId
    roleDefinitionGuid: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  }
}]

module hostPoolAlerts 'modules/alerts/host-pool-alerts.bicep' = [for (pool, index) in hostPools: {
  name: 'avd-log-alerts-${index}-${uniqueString(hostPoolResourceIds[index])}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, collectorHealthAlerts]
  params: {
    location: location
    hostPoolResourceId: hostPoolResourceIds[index]
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
    includeAutoscaleFailures: (pool.?hostPoolType ?? 'Pooled') == 'Pooled' && !empty(pool.?scalingPlanName ?? '')
  }
}]

module hostPoolCollectorAlerts 'modules/alerts/host-pool-collector-alerts.bicep' = [for (pool, index) in hostPools: {
  name: 'avd-collector-alerts-${index}-${uniqueString(hostPoolResourceIds[index])}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, hostPoolAlerts]
  params: {
    location: location
    hostPoolResourceId: hostPoolResourceIds[index]
    hostPoolType: pool.?hostPoolType ?? 'Pooled'
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module hostPoolHealthAlerts 'modules/alerts/host-pool-health-alerts.bicep' = [for (hostPoolId, index) in hostPoolResourceIds: {
  name: 'avd-health-alerts-${index}-${uniqueString(hostPoolId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, hostPoolCollectorAlerts]
  params: {
    location: location
    hostPoolResourceId: hostPoolId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
    connectionFailureMinFailures: connectionFailureMinFailures
    connectionFailureMinUsers: connectionFailureMinUsers
    ignoredConnectionErrorCodes: ignoredConnectionErrorCodes
  }
}]

module sessionHostMetricAlerts 'modules/alerts/session-host-metric-alerts.bicep' = [for (pool, index) in hostPools: {
  name: 'avd-session-host-metrics-${index}-${uniqueString(hostPoolResourceIds[index])}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, hostPoolHealthAlerts]
  params: {
    location: location
    hostPoolResourceId: hostPoolResourceIds[index]
    sessionHostVmResourceGroupId: '/subscriptions/${pool.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${pool.resourceGroupName}'
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module fslogixAlerts 'modules/alerts/fslogix-alerts.bicep' = [for (hostPoolId, index) in hostPoolResourceIds: {
  name: 'avd-fslogix-alerts-${index}-${uniqueString(hostPoolId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, sessionHostMetricAlerts]
  params: {
    location: location
    hostPoolResourceId: hostPoolId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module fileMetricAlerts 'modules/alerts/file-metric-alerts.bicep' = [for (storageId, index) in fileStorageAccountResourceIds: {
  name: 'avd-files-metric-alerts-${index}-${uniqueString(storageId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, fslogixAlerts]
  params: {
    storageAccountResourceId: storageId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module storageShareAlerts 'modules/alerts/storage-share-alerts.bicep' = [for (storageId, index) in fileStorageAccountResourceIds: {
  name: 'avd-storage-share-alerts-${index}-${uniqueString(storageId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, fileMetricAlerts]
  params: {
    location: location
    storageAccountResourceId: storageId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module anfVolumeAlerts 'modules/alerts/anf-volume-alerts.bicep' = [for (volumeId, index) in anfVolumeResourceIds: {
  name: 'avd-anf-volume-alerts-${index}-${uniqueString(volumeId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, storageShareAlerts]
  params: {
    volumeResourceId: volumeId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module serviceHealthAlerts 'modules/alerts/service-health-alerts.bicep' = {
  name: 'avd-service-health-alerts'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, anfVolumeAlerts]
  params: {
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
    serviceHealthServiceName: serviceHealthServiceName
  }
}

// The pipeline reads these to publish the runbooks and to create the schedules.
output automationAccountName string = automationAccountName
output monitoringResourceGroupName string = monitoringResourceGroupName
output collectorNamePrefix string = collectorNamePrefix
output alertNamePrefix string = alertNamePrefix
output hostPoolRunbookName string = collectorInfrastructure.outputs.hostPoolRunbookName
output storageRunbookName string = collectorInfrastructure.outputs.storageRunbookName
output azModuleVersions object = azModuleVersions
output actionGroupResourceId string = effectiveActionGroupResourceId
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspaceResourceId
output hostPoolResourceIds array = hostPoolResourceIds
output scalingPlanResourceIds array = scalingPlanResourceIds
output fileStorageAccountResourceIds array = fileStorageAccountResourceIds
