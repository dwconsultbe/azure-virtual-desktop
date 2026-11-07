// Shared building blocks for the scheduled query rules, so that every alert module only
// describes what is specific to its alert: the query, the dimensions and the thresholds.
// The fixed part (scope, action group, autoMitigate, failingPeriods) lives here, once.

@description('What every rule needs from the deployment.')
@export()
type RuleContext = {
  @description('Log Analytics workspace the rule queries.')
  workspaceResourceId: string

  @description('Action group that receives the notification.')
  actionGroupResourceId: string

  @description('Alert ids that are enabled. Rules whose alertId is not listed are deployed disabled.')
  enabledAlertRuleIds: string[]
}

@description('The parts of a scheduled query rule that differ per alert.')
@export()
type RuleDefinition = {
  @description('Alert rule key used in enabledAlertRuleIds.')
  alertId: string
  displayName: string
  description: string
  severity: 0 | 1 | 2 | 3 | 4
  evaluationFrequency: string
  windowSize: string
  query: string

  @description('Query columns that become alert dimensions. One alert instance per distinct combination.')
  dimensions: string[]

  @description('Defaults to Count.')
  timeAggregation: ('Count' | 'Minimum' | 'Maximum' | 'Average' | 'Total')?

  @description('Column that holds the value to compare. Required for every aggregation except Count.')
  metricMeasureColumn: string?

  @description('Defaults to GreaterThanOrEqual.')
  operator: ('GreaterThanOrEqual' | 'LessThanOrEqual' | 'GreaterThan' | 'LessThan' | 'Equal')?

  @description('Defaults to 1, which for Count means: at least one row.')
  threshold: int?
}

// Query fragments shared by several alerts. They hold placeholders; fillQuery replaces them.
@description('Session hosts of one host pool, as the HostPoolVMs table. Placeholder: __HOST_POOL_ID__.')
@export()
var hostPoolVmsFragment = loadTextContent('queries/_host-pool-vms.kql')

@description('Rows written by the host pool collector for one host pool. Placeholders: __RUNBOOK__, __HOST_POOL_ID__.')
@export()
var collectorRowsFragment = loadTextContent('queries/_collector-rows.kql')

@description('Replaces the placeholders in a query. Values may contain placeholders themselves (a fragment that holds __HOST_POOL_ID__), so the replacement runs twice.')
@export()
func fillQuery(template string, values { *: string }) string =>
  reduce(
    objectKeys(values),
    reduce(objectKeys(values), template, (text, placeholder) => replace(text, placeholder, values[placeholder])),
    (text, placeholder) => replace(text, placeholder, values[placeholder]))

@description('The properties of a scheduled query rule.')
@export()
func queryRuleProperties(context RuleContext, rule RuleDefinition) object => {
  displayName: rule.displayName
  description: rule.description
  enabled: contains(context.enabledAlertRuleIds, rule.alertId)
  severity: rule.severity
  evaluationFrequency: rule.evaluationFrequency
  windowSize: rule.windowSize
  autoMitigate: true
  scopes: [context.workspaceResourceId]
  actions: { actionGroups: [context.actionGroupResourceId] }
  criteria: {
    allOf: [
      union(
        {
          query: rule.query
          timeAggregation: rule.?timeAggregation ?? 'Count'
          dimensions: map(rule.dimensions, name => { name: name, operator: 'Include', values: ['*'] })
          operator: rule.?operator ?? 'GreaterThanOrEqual'
          threshold: rule.?threshold ?? 1
          failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 }
        },
        empty(rule.?metricMeasureColumn ?? '') ? {} : { metricMeasureColumn: rule.?metricMeasureColumn }
      )
    ]
  }
}
