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

@description('Existing Log Analytics workspace. Used when createLogAnalyticsWorkspace is false.')
param logAnalyticsWorkspace AzureResourceReference = {
  subscriptionId: ''
  resourceGroupName: ''
  name: ''
}

@description('Create a Log Analytics workspace in the monitoring resource group.')
param createLogAnalyticsWorkspace bool = false

@description('Name for a new Log Analytics workspace. Used only when createLogAnalyticsWorkspace is true.')
param newLogAnalyticsWorkspaceName string = ''

@description('Workspace data retention in days when creating a new workspace.')
@minValue(30)
@maxValue(730)
param logAnalyticsWorkspaceRetentionInDays int = 30

@description('Location of the Log Analytics workspace for DCRs. Must match the existing workspace location; when creating a workspace, location is used by default.')
param dataCollectionRuleLocation string = ''

@description('Deploy the Windows DCR for AVD performance counters and Windows events.')
param deployAvdGuestDataDcr bool = false

@description('Deploy the separate VM Insights DetailedMetrics DCR.')
param deployVmInsightsDcr bool = false

@description('Assign Azure Policy to associate enabled DCRs with supported Windows VMs in each host-pool resource group. AMA must be installed on the VMs.')
param associateDcrsWithPolicy bool = false

@description('Optional custom Windows image resource IDs to include in the built-in DCR association policy.')
param customWindowsImageIds array = []

@description('Configure AVD host-pool and AVD workspace diagnostic settings to send required logs to Log Analytics.')
param configureAvdDiagnostics bool = false

@description('Azure Virtual Desktop workspaces that should send diagnostic logs to Log Analytics.')
param avdWorkspaces AzureResourceReference[] = []

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

module logAnalyticsWorkspaceDeployment 'modules/data-collection/log-analytics-workspace.bicep' = if (createLogAnalyticsWorkspace) {
  name: 'avd-log-analytics-workspace'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    workspaceName: newLogAnalyticsWorkspaceName
    location: location
    retentionInDays: logAnalyticsWorkspaceRetentionInDays
  }
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

var effectiveLogAnalyticsWorkspaceName = createLogAnalyticsWorkspace ? newLogAnalyticsWorkspaceName : logAnalyticsWorkspace.name
var effectiveLogAnalyticsWorkspaceResourceGroupName = createLogAnalyticsWorkspace ? monitoringResourceGroupName : logAnalyticsWorkspace.resourceGroupName
var effectiveLogAnalyticsWorkspaceSubscriptionId = createLogAnalyticsWorkspace ? subscription().subscriptionId : (logAnalyticsWorkspace.?subscriptionId ?? subscription().subscriptionId)
var logAnalyticsWorkspaceResourceId = resourceId(effectiveLogAnalyticsWorkspaceSubscriptionId, effectiveLogAnalyticsWorkspaceResourceGroupName, 'Microsoft.OperationalInsights/workspaces', effectiveLogAnalyticsWorkspaceName)
var effectiveDataCollectionRuleLocation = empty(dataCollectionRuleLocation) ? location : dataCollectionRuleLocation
var existingActionGroupResourceId = empty(existingActionGroup.name) ? '' : resourceId(existingActionGroup.?subscriptionId ?? subscription().subscriptionId, existingActionGroup.resourceGroupName, 'Microsoft.Insights/actionGroups', existingActionGroup.name)
var hostPoolResourceIds = [for pool in hostPools: resourceId(pool.?subscriptionId ?? subscription().subscriptionId, pool.resourceGroupName, 'Microsoft.DesktopVirtualization/hostPools', pool.name)]
var uniqueHostPoolResourceIds = union(hostPoolResourceIds, [])
var avdWorkspaceResourceIds = [for workspace in avdWorkspaces: resourceId(workspace.?subscriptionId ?? subscription().subscriptionId, workspace.resourceGroupName, 'Microsoft.DesktopVirtualization/workspaces', workspace.name)]
var uniqueAvdWorkspaceResourceIds = union(avdWorkspaceResourceIds, [])
var hostPoolResourceGroups = [for pool in hostPools: toLower('/subscriptions/${pool.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${pool.resourceGroupName}')]
var uniqueHostPoolResourceGroups = union(hostPoolResourceGroups, [])
var scalingPlanResourceIds = [for plan in scalingPlans: resourceId(plan.?subscriptionId ?? subscription().subscriptionId, plan.resourceGroupName, 'Microsoft.DesktopVirtualization/scalingPlans', plan.name)]
var scalingPlanResourceGroups = [for plan in scalingPlans: toLower('/subscriptions/${plan.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${plan.resourceGroupName}')]
var avdReaderResourceGroups = union(hostPoolResourceGroups, scalingPlanResourceGroups)
var fileStorageAccountResourceIds = [for account in fileStorageAccounts: resourceId(account.?subscriptionId ?? subscription().subscriptionId, account.resourceGroupName, 'Microsoft.Storage/storageAccounts', account.name)]
var anfVolumeResourceIds = [for volume in anfVolumes: resourceId(volume.?subscriptionId ?? subscription().subscriptionId, volume.resourceGroupName, 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes', volume.netAppAccountName, volume.capacityPoolName, volume.name)]
var storageResourceGroups = [for account in fileStorageAccounts: toLower('/subscriptions/${account.?subscriptionId ?? subscription().subscriptionId}/resourceGroups/${account.resourceGroupName}')]
var storageReaderResourceGroups = union(storageResourceGroups, [])

module actionGroup 'modules/alerts/action-group.bicep' = if (createActionGroup) {
  name: 'avd-action-group'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup]
  params: {
    actionGroupName: actionGroupName
    actionGroupShortName: actionGroupShortName
    emailReceivers: actionGroupEmailReceivers
  }
}

module avdGuestDataDcr 'modules/data-collection/avd-guest-data-dcr.bicep' = if (deployAvdGuestDataDcr) {
  name: 'avd-guest-data-dcr'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, logAnalyticsWorkspaceDeployment]
  params: {
    ruleName: '${take(alertNamePrefix, 34)}-guest-data-${uniqueString(logAnalyticsWorkspaceResourceId)}'
    location: effectiveDataCollectionRuleLocation
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
  }
}

module vmInsightsDcr 'modules/data-collection/vm-insights-dcr.bicep' = if (deployVmInsightsDcr) {
  name: 'avd-vm-insights-dcr'
  scope: resourceGroup(monitoringResourceGroupName)
  dependsOn: [monitoringResourceGroup, logAnalyticsWorkspaceDeployment]
  params: {
    ruleName: '${take(alertNamePrefix, 34)}-vm-insights-${uniqueString(logAnalyticsWorkspaceResourceId)}'
    location: effectiveDataCollectionRuleLocation
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
  }
}

module avdGuestDcrPolicies 'modules/data-collection/dcr-association-policy.bicep' = [for (resourceGroupId, index) in uniqueHostPoolResourceGroups: if (associateDcrsWithPolicy && deployAvdGuestDataDcr) {
  name: 'avd-guest-dcr-policy-${index}-${uniqueString(resourceGroupId)}'
  scope: resourceGroup(split(resourceGroupId, '/')[2], split(resourceGroupId, '/')[4])
  params: {
    assignmentName: '${take(alertNamePrefix, 24)}-guest-dcr-${uniqueString(resourceGroupId)}'
    assignmentLocation: location
    dataCollectionRuleResourceId: avdGuestDataDcr.?outputs.?resourceId ?? ''
    windowsImageIds: customWindowsImageIds
  }
}]

module vmInsightsDcrPolicies 'modules/data-collection/dcr-association-policy.bicep' = [for (resourceGroupId, index) in uniqueHostPoolResourceGroups: if (associateDcrsWithPolicy && deployVmInsightsDcr) {
  name: 'avd-vminsights-dcr-policy-${index}-${uniqueString(resourceGroupId)}'
  scope: resourceGroup(split(resourceGroupId, '/')[2], split(resourceGroupId, '/')[4])
  params: {
    assignmentName: '${take(alertNamePrefix, 24)}-vm-insights-${uniqueString(resourceGroupId)}'
    assignmentLocation: location
    dataCollectionRuleResourceId: vmInsightsDcr.?outputs.?resourceId ?? ''
    windowsImageIds: customWindowsImageIds
  }
}]

module hostPoolDiagnostics 'modules/data-collection/avd-host-pool-diagnostics.bicep' = [for (hostPoolId, index) in uniqueHostPoolResourceIds: if (configureAvdDiagnostics) {
  name: 'avd-host-pool-diagnostics-${index}-${uniqueString(hostPoolId)}'
  scope: resourceGroup(split(hostPoolId, '/')[2], split(hostPoolId, '/')[4])
  params: {
    hostPoolName: last(split(hostPoolId, '/'))
    diagnosticSettingName: take('avd-baseline-${uniqueString(hostPoolId)}', 64)
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    includeAutoscaleFailures: includeAutoscaleFailures
  }
}]

module workspaceDiagnostics 'modules/data-collection/avd-workspace-diagnostics.bicep' = [for (workspaceId, index) in uniqueAvdWorkspaceResourceIds: if (configureAvdDiagnostics) {
  name: 'avd-workspace-diagnostics-${index}-${uniqueString(workspaceId)}'
  scope: resourceGroup(split(workspaceId, '/')[2], split(workspaceId, '/')[4])
  params: {
    avdWorkspaceName: last(split(workspaceId, '/'))
    diagnosticSettingName: take('avd-baseline-${uniqueString(workspaceId)}', 64)
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
  }
}]

var effectiveActionGroupResourceId = actionGroup.?outputs.?resourceId ?? existingActionGroupResourceId

module collectorInfrastructure 'modules/collectors/collector-infrastructure.bicep' = {
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

module collectorHealthAlerts 'modules/alerts/collector-health-alerts.bicep' = {
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

module hostPoolAlerts 'modules/alerts/host-pool-alerts.bicep' = [for (hostPoolId, index) in hostPoolResourceIds: {
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

module hostPoolCollectorAlerts 'modules/alerts/host-pool-collector-alerts.bicep' = [for (pool, index) in hostPools: {
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

module hostPoolHealthAlerts 'modules/alerts/host-pool-health-alerts.bicep' = [for (hostPoolId, index) in hostPoolResourceIds: {
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

module sessionHostMetricAlerts 'modules/alerts/session-host-metric-alerts.bicep' = [for (pool, index) in hostPools: {
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

module fslogixAlerts 'modules/alerts/fslogix-alerts.bicep' = [for (hostPoolId, index) in hostPoolResourceIds: {
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

module fileMetricAlerts 'modules/alerts/file-metric-alerts.bicep' = [for (storageId, index) in fileStorageAccountResourceIds: {
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

module storageShareAlerts 'modules/alerts/storage-share-alerts.bicep' = [for (storageId, index) in fileStorageAccountResourceIds: {
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

module anfVolumeAlerts 'modules/alerts/anf-volume-alerts.bicep' = [for (volumeId, index) in anfVolumeResourceIds: {
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

module serviceHealthAlerts 'modules/alerts/service-health-alerts.bicep' = {
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
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspaceResourceId
output avdGuestDataDcrResourceId string = avdGuestDataDcr.?outputs.?resourceId ?? ''
output vmInsightsDcrResourceId string = vmInsightsDcr.?outputs.?resourceId ?? ''
output avdWorkspaceResourceIds array = avdWorkspaceResourceIds
output hostPoolResourceIds array = hostPoolResourceIds
output scalingPlanResourceIds array = scalingPlanResourceIds
output fileStorageAccountResourceIds array = fileStorageAccountResourceIds
