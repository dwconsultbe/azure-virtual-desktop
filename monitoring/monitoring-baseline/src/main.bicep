targetScope = 'subscription'

@description('Existing resource group that will contain the alert rules.')
param monitoringResourceGroupName string

@description('Azure region for scheduled query rules.')
param location string

@description('Create the monitoring resource group when true. When false, the resource group must already exist.')
param createMonitoringResourceGroup bool = false

@description('Tags applied to a newly created monitoring resource group.')
param monitoringResourceGroupTags object = {}

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
}

@description('Existing Log Analytics workspace. Provide its subscription, resource group and name.')
param logAnalyticsWorkspace AzureResourceReference

@description('Set to true to create an Action Group in the monitoring resource group. Keep false to use an existing Action Group.')
param createActionGroup bool = false

@description('Existing Action Group. Required when createActionGroup is false.')
param existingActionGroup AzureResourceReference = {
  subscriptionId: ''
  resourceGroupName: ''
  name: ''
}

@description('Name of the new Action Group. Used only when createActionGroup is true.')
param actionGroupName string = 'avd-monitoring-actions'

@description('Short name shown in notifications. Maximum 12 characters.')
@maxLength(12)
param actionGroupShortName string = 'avdmonitor'

@description('Email receivers for a new Action Group. Each item needs name, emailAddress and useCommonAlertSchema.')
param actionGroupEmailReceivers array = []

resource monitoringResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = if (createMonitoringResourceGroup) {
  name: monitoringResourceGroupName
  location: location
  tags: monitoringResourceGroupTags
}

@description('Host pools to monitor. Each one must send diagnostics to the selected workspace.')
@minLength(1)
param hostPools HostPoolConfig[]

@description('Azure Files storage accounts for metric alerts and share-capacity collection.')
param fileStorageAccounts AzureResourceReference[] = []

@description('Azure NetApp Files volumes for volume capacity alerts.')
param anfVolumes AnfVolumeReference[] = []

@description('Scaling plans. Their resource groups are granted Desktop Virtualization Reader to the collector identity.')
param scalingPlans AzureResourceReference[] = []

@description('Name of the Automation Account that runs the in-repository collectors.')
param automationAccountName string

@description('Optional existing diagnostic setting name on the Automation Account. Leave empty to derive it from alertNamePrefix.')
param jobDiagnosticsSettingName string = ''

@description('Short prefix used in the names of the alert rules, runbooks, schedules and diagnostic setting.')
param alertNamePrefix string

@description('Customer name shown in alert descriptions.')
param customerName string = ''

@description('Pinned PowerShell Gallery versions for Az.Accounts, Az.DesktopVirtualization and Az.Storage, imported into the Automation Account.')
param azModuleVersions object

@description('connectionFailure fires when this many connections fail with the same error within 15 minutes.')
@minValue(1)
param connectionFailureMinFailures int = 5

@description('connectionFailure also requires this many distinct affected users.')
@minValue(1)
param connectionFailureMinUsers int = 3

// Credential, account and client-disconnect errors are caused by users, not by the platform.
// ConnectionFailedNoHealthyRdshAvailable has its own rule (noResourcesAvailable). The list is
// adapted from community guidance (ITProCloud, Marcel Meurer); review it per environment with:
// WVDErrors | summarize count() by CodeSymbolic, Message | order by count_ desc
@description('WVDErrors CodeSymbolic values that connectionFailure ignores because they are not platform problems.')
param ignoredConnectionErrorCodes string[] = [
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

@description('Alert IDs to enable. All other rules remain disabled.')
param enabledAlertRuleIds string[] = []

@description('Service Health service name shown by Azure for AVD in this subscription. Confirm the value in Service Health metadata before enabling the rule.')
param serviceHealthServiceName string = 'Azure Virtual Desktop'

@description('Deploy the Autoscale Failures rule only when pooled autoscale diagnostics are collected.')
param includeAutoscaleFailures bool = false

var logAnalyticsWorkspaceResourceId = resourceId(logAnalyticsWorkspace.?subscriptionId ?? subscription().subscriptionId, logAnalyticsWorkspace.resourceGroupName, 'Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspace.name)
var existingActionGroupResourceId = empty(existingActionGroup.name) ? '' : resourceId(existingActionGroup.?subscriptionId ?? subscription().subscriptionId, existingActionGroup.resourceGroupName, 'Microsoft.Insights/actionGroups', existingActionGroup.name)
var hostPoolResourceIds = [for pool in hostPools: resourceId(pool.?subscriptionId ?? subscription().subscriptionId, pool.resourceGroupName, 'Microsoft.DesktopVirtualization/hostPools', pool.name)]
var hostPoolResourceGroups = [for pool in hostPools: toLower('/subscriptions/${pool.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${pool.resourceGroupName}')]
var scalingPlanResourceIds = [for plan in scalingPlans: resourceId(plan.?subscriptionId ?? subscription().subscriptionId, plan.resourceGroupName, 'Microsoft.DesktopVirtualization/scalingPlans', plan.name)]
var scalingPlanResourceGroups = [for plan in scalingPlans: toLower('/subscriptions/${plan.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${plan.resourceGroupName}')]
var avdReaderResourceGroups = union(hostPoolResourceGroups, scalingPlanResourceGroups)
var fileStorageAccountResourceIds = [for account in fileStorageAccounts: resourceId(account.?subscriptionId ?? subscription().subscriptionId, account.resourceGroupName, 'Microsoft.Storage/storageAccounts', account.name)]
var anfVolumeResourceIds = [for volume in anfVolumes: resourceId(volume.?subscriptionId ?? subscription().subscriptionId, volume.resourceGroupName, 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes', volume.netAppAccountName, volume.capacityPoolName, volume.name)]
var storageResourceGroups = [for account in fileStorageAccounts: toLower('/subscriptions/${account.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${account.resourceGroupName}')]
var storageReaderResourceGroups = union(storageResourceGroups, [])

module actionGroup 'modules/action-group.bicep' = if (createActionGroup) {
  name: 'avd-action-group'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    actionGroupName: actionGroupName
    actionGroupShortName: actionGroupShortName
    emailReceivers: actionGroupEmailReceivers
  }
}

var effectiveActionGroupResourceId = actionGroup.?outputs.?resourceId ?? existingActionGroupResourceId

module collectorInfrastructure 'modules/collector-infrastructure.bicep' = {
  name: 'avd-collector-infrastructure'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    location: location
    automationAccountName: automationAccountName
    namePrefix: alertNamePrefix
    jobDiagnosticsSettingName: jobDiagnosticsSettingName
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    azModuleVersions: azModuleVersions
  }
}

module collectorHealthAlerts 'modules/collector-health-alerts.bicep' = {
  name: 'avd-collector-health-alerts'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    location: location
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    customerName: customerName
    enabledAlertRuleIds: enabledAlertRuleIds
    hostPoolRunbookName: collectorInfrastructure.outputs.hostPoolRunbookName
    storageRunbookName: collectorInfrastructure.outputs.storageRunbookName
    includeStorageCollector: !empty(fileStorageAccountResourceIds)
  }
}

module avdReader 'modules/collector-reader-role.bicep' = [for (rgId, index) in avdReaderResourceGroups: {
  name: 'avd-collector-avd-reader-${index}-${uniqueString(rgId)}'
  scope: resourceGroup(split(rgId, '/')[2], split(rgId, '/')[4])
  params: {
    principalId: collectorInfrastructure.outputs.principalId
    roleDefinitionGuid: '49a72310-ab8d-41df-bbb0-79b649203868'
  }
}]

module storageReader 'modules/collector-reader-role.bicep' = [for (rgId, index) in storageReaderResourceGroups: {
  name: 'avd-collector-storage-reader-${index}-${uniqueString(rgId)}'
  scope: resourceGroup(split(rgId, '/')[2], split(rgId, '/')[4])
  params: {
    principalId: collectorInfrastructure.outputs.principalId
    roleDefinitionGuid: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  }
}]

module hostPoolAlerts 'modules/host-pool-alerts.bicep' = [for (hostPoolId, index) in hostPoolResourceIds: {
  name: 'avd-log-alerts-${index}-${uniqueString(hostPoolId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    location: location
    hostPoolResourceId: hostPoolId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    customerName: customerName
    enabledAlertRuleIds: enabledAlertRuleIds
    includeAutoscaleFailures: includeAutoscaleFailures
  }
}]

module hostPoolCollectorAlerts 'modules/host-pool-collector-alerts.bicep' = [for (pool, index) in hostPools: {
  name: 'avd-collector-alerts-${index}-${uniqueString(hostPoolResourceIds[index])}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    location: location
    hostPoolResourceId: hostPoolResourceIds[index]
    hostPoolType: pool.?hostPoolType ?? 'Pooled'
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    customerName: customerName
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module hostPoolHealthAlerts 'modules/host-pool-health-alerts.bicep' = [for (hostPoolId, index) in hostPoolResourceIds: {
  name: 'avd-health-alerts-${index}-${uniqueString(hostPoolId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    location: location
    hostPoolResourceId: hostPoolId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    customerName: customerName
    enabledAlertRuleIds: enabledAlertRuleIds
    connectionFailureMinFailures: connectionFailureMinFailures
    connectionFailureMinUsers: connectionFailureMinUsers
    ignoredConnectionErrorCodes: ignoredConnectionErrorCodes
  }
}]

module sessionHostMetricAlerts 'modules/session-host-metric-alerts.bicep' = [for (pool, index) in hostPools: {
  name: 'avd-session-host-metrics-${index}-${uniqueString(hostPoolResourceIds[index])}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    location: location
    hostPoolResourceId: hostPoolResourceIds[index]
    sessionHostVmResourceGroupId: '/subscriptions/${pool.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${pool.resourceGroupName}'
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    customerName: customerName
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module fslogixAlerts 'modules/fslogix-alerts.bicep' = [for (hostPoolId, index) in hostPoolResourceIds: {
  name: 'avd-fslogix-alerts-${index}-${uniqueString(hostPoolId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    location: location
    hostPoolResourceId: hostPoolId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    customerName: customerName
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module fileMetricAlerts 'modules/file-metric-alerts.bicep' = [for (storageId, index) in fileStorageAccountResourceIds: {
  name: 'avd-files-metric-alerts-${index}-${uniqueString(storageId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    storageAccountResourceId: storageId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    customerName: customerName
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module storageShareAlerts 'modules/storage-share-alerts.bicep' = [for (storageId, index) in fileStorageAccountResourceIds: {
  name: 'avd-storage-share-alerts-${index}-${uniqueString(storageId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    location: location
    storageAccountResourceId: storageId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    customerName: customerName
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module anfVolumeAlerts 'modules/anf-volume-alerts.bicep' = [for (volumeId, index) in anfVolumeResourceIds: {
  name: 'avd-anf-volume-alerts-${index}-${uniqueString(volumeId)}'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    volumeResourceId: volumeId
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    customerName: customerName
    enabledAlertRuleIds: enabledAlertRuleIds
  }
}]

module serviceHealthAlerts 'modules/service-health-alerts.bicep' = {
  name: 'avd-service-health-alerts'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    actionGroupResourceId: effectiveActionGroupResourceId
    alertNamePrefix: alertNamePrefix
    enabledAlertRuleIds: enabledAlertRuleIds
    serviceHealthServiceName: serviceHealthServiceName
  }
}

// The pipeline reads these to publish the runbooks and to create the schedules.
output automationAccountName string = automationAccountName
output hostPoolRunbookName string = collectorInfrastructure.outputs.hostPoolRunbookName
output storageRunbookName string = collectorInfrastructure.outputs.storageRunbookName
output actionGroupResourceId string = effectiveActionGroupResourceId
output hostPoolResourceIds array = hostPoolResourceIds
output scalingPlanResourceIds array = scalingPlanResourceIds
output fileStorageAccountResourceIds array = fileStorageAccountResourceIds
