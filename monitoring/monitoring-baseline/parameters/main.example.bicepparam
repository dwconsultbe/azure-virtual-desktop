using '../src/main.bicep'

// 1. Set the deployment region, alert email and existing Log Analytics workspace.
// Add subscriptionId only when the workspace is in another subscription.
// The monitoring resource group is created if it does not exist. Keep its name stable:
// a new name creates a new Automation Account, Action Group and alert rules next to the old ones.
// Optional alert-name prefix. For example, 'org-env' produces 'org-env-avd-ar-...'.
param deployment = {
  location: 'REPLACE_LOCATION'
  notificationEmail: 'REPLACE_NOTIFICATION_EMAIL'
  logAnalyticsWorkspace: {
    resourceGroupName: 'REPLACE_WORKSPACE_RESOURCE_GROUP'
    name: 'REPLACE_WORKSPACE_NAME'
    // subscriptionId: 'REPLACE_WORKSPACE_SUBSCRIPTION_ID'
  }
  monitoringResourceGroupName: 'REPLACE_MONITORING_RESOURCE_GROUP'
  // resourcePrefix: 'org-env'
}

// 2. Add each host pool. Host pools and their session hosts must share a resource group.
// Add subscriptionId only when the host pool is in another subscription.
param hostPools = [
  {
    resourceGroupName: 'REPLACE_HOST_POOL_RESOURCE_GROUP'
    name: 'REPLACE_HOST_POOL_NAME'
    // Optional. Defaults to Pooled. Set to Personal for a personal host pool.
    // hostPoolType: 'Personal'
    // Optional. The scaling plan is expected in this same resource group/subscription.
    // scalingPlanName: 'plan-production'
    // Optional. Defaults to true. Set to false when the host pool already sends its
    // diagnostics to this workspace (for example through AVD Insights). See the administrator guide.
    // configureDiagnostics: false
  }
]

// 3. Optional extras. Leave empty for the standard deployment.
// Add resources using their names and resource groups; subscriptionId is needed only
// when a resource is in another subscription. Alert IDs are listed in docs/technical-documentation.md.
param additionalResources = {
  // fileStorageAccounts: [
  //   {
  //     resourceGroupName: 'rg-storage'
  //     name: 'stprofiles'
  //   }
  // ]
  // anfVolumes: [
  //   {
  //     resourceGroupName: 'rg-netapp'
  //     netAppAccountName: 'netapp-prod'
  //     capacityPoolName: 'pool-profiles'
  //     name: 'avd-profiles'
  //   }
  // ]
  // enabledAlertRuleIds: [
  //   'collectorFailed'
  //   'collectorStale'
  // ]
}
