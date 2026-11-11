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

// 3. Alerts and optional storage.
// alertSets switches on groups of alerts. Start with 'core': it needs no extra setup.
// Add more sets once the session-host data arrives:
//   'hostPool', 'sessionHosts', 'resources', 'scaling', 'fslogix', 'storage', 'serviceHealth' or 'all'.
// See docs/technical-documentation.md for the alerts in each set.
param additionalResources = {
  alertSets: [
    'core'
  ]
  // Individual alerts on top of the sets, for example:
  // enabledAlertRuleIds: [
  //   'cpu95'
  // ]

  // Azure Files and Azure NetApp Files with FSLogix profiles. subscriptionId is needed
  // only when the resource is in another subscription.
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
}
