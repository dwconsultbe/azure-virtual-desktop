using '../src/main.bicep'

// Replace the example values below before deploying. The pipeline uses location
// for both subscription deployment metadata and regional resources.
param monitoringResourceGroupName = 'REPLACE_MONITORING_RESOURCE_GROUP'
// Example: 'northeurope'
param location = 'REPLACE_LOCATION'
param createMonitoringResourceGroup = false
param monitoringResourceGroupTags = {
  workload: 'avd-monitoring'
}

// Existing workspace. The deployment subscription is used unless overridden.
param logAnalyticsWorkspace = {
  // Uncomment and set this property if the workspace is in another subscription.
  // subscriptionId: 'REPLACE_SUBSCRIPTION_ID'
  resourceGroupName: 'REPLACE_WORKSPACE_RESOURCE_GROUP'
  name: 'REPLACE_WORKSPACE_NAME'
}
// Keep false to use an existing Action Group. Set true to create one in the monitoring resource group.
param createActionGroup = false
// Required only when createActionGroup is false.
param existingActionGroup = {
  // Uncomment and set this property if the Action Group is in another subscription.
  // subscriptionId: 'REPLACE_SUBSCRIPTION_ID'
  resourceGroupName: 'REPLACE_ACTION_GROUP_RESOURCE_GROUP'
  name: 'REPLACE_ACTION_GROUP_NAME'
}
// Examples: 'avd-monitoring-actions' and 'avdmonitor'
param actionGroupName = ''
param actionGroupShortName = ''
// Add objects with name, emailAddress and useCommonAlertSchema when creating a new Action Group.
param actionGroupEmailReceivers = []

// Add one object per host pool. Host pool and session host VMs must share a resource group.
param hostPools = [
  {
    // Add subscriptionId inside each object if this host pool is in another subscription.
    // subscriptionId: 'REPLACE_SUBSCRIPTION_ID'
    resourceGroupName: 'REPLACE_HOST_POOL_RESOURCE_GROUP'
    name: 'REPLACE_HOST_POOL_NAME'
  }
]

// Optional Azure Files accounts. Provide resourceGroupName and name; subscriptionId is optional.
param fileStorageAccounts = []

// No Azure NetApp Files volume was found in this subscription.
param anfVolumes = []

// Optional scaling plans. Provide resourceGroupName and name; subscriptionId is optional.
param scalingPlans = []

// PowerShell Gallery versions imported into the Automation Account. Read the versions
// that work today with: az automation module list --automation-account-name <account>
// --resource-group <rg> --query "[?name=='Az.Accounts' || name=='Az.DesktopVirtualization' || name=='Az.Storage'].{name:name, version:properties.version}"
// Use versions that are supported in your Automation Account
// (Az.DesktopVirtualization 6.0.0 needs Az.Accounts >= 5.5.0, Az.Storage 9.7.2 needs >= 5.5.2).
// The pipeline refuses to run while a REPLACE_ placeholder remains.
param azModuleVersions = {
  'Az.Accounts': '5.5.3'
  'Az.DesktopVirtualization': '6.0.0'
  'Az.Storage': '9.7.2'
}

param automationAccountName = 'REPLACE_AUTOMATION_ACCOUNT_NAME'
// Example: 'avd-monitoring'
param alertNamePrefix = 'REPLACE_ALERT_NAME_PREFIX'
param customerName = ''

// Keep the first deployment disabled until collector jobs and KQL data are
// verified. To enable alerts later, copy their exact IDs from the alert catalog
// in docs/technical-documentation.md into this list.
// Add collectorFailed and collectorStale first: they watch the collectors that the
// capacity, scaling plan, personal host and file share rules depend on.
param enabledAlertRuleIds = []

// Pooled host pools only; enable when WVDAutoscaleEvaluationPooled is collected.
param includeAutoscaleFailures = false
