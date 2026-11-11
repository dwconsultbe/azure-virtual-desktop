using 'main.bicep'

// Use the same Log Analytics workspace as the monitoring baseline.
param logAnalyticsWorkspaceResourceId = '/subscriptions/REPLACE_SUBSCRIPTION_ID/resourceGroups/REPLACE_WORKSPACE_RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/REPLACE_WORKSPACE_NAME'

// Optional. Keep the microsoft-avdi- prefix if you also use AVD Insights.
// param dataCollectionRuleName = 'microsoft-avdi-session-hosts'

// Optional. Session hosts to associate with the rule. New VMs must be added and the
// deployment repeated, or associated through Azure Policy.
param sessionHostVmResourceIds = [
  // '/subscriptions/REPLACE_SUBSCRIPTION_ID/resourceGroups/rg-avd/providers/Microsoft.Compute/virtualMachines/avd-0'
]
