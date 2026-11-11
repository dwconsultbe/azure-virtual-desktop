// Alert IDs and alert sets. The types make Bicep reject an unknown ID or set name at build
// time, so a typo fails the build instead of silently leaving an alert disabled.
// When you add an alert rule, add its ID to AlertRuleId and to at least one set.

@export()
@description('Every alert rule ID that can be enabled.')
type AlertRuleId =
  | 'collectorFailed'
  | 'collectorStale'
  | 'diagnosticDataMissing'
  | 'capacity50'
  | 'capacity85'
  | 'capacity95'
  | 'connectionFailure'
  | 'noResourcesAvailable'
  | 'healthCheckFailure'
  | 'personalUnhealthy'
  | 'agentUpgrade'
  | 'drainedIdle'
  | 'autoscaleFailures'
  | 'cpu85'
  | 'cpu95'
  | 'memory2GB'
  | 'memory1GB'
  | 'localDiskFree10'
  | 'localDiskFree5'
  | 'osDiskBandwidth85'
  | 'osDiskBandwidth95'
  | 'scalingPlanDisabled4h'
  | 'scalingPlanDisabled24h'
  | 'scalingPlanRemoved'
  | 'fslogixFree5'
  | 'fslogixFree2'
  | 'fslogixDiskInUse'
  | 'fslogixAttach'
  | 'fslogixNetwork'
  | 'fslogixServiceDisabled'
  | 'fslogixCompaction'
  | 'fileShareCapacity15'
  | 'fileShareCapacity5'
  | 'filesAvailability'
  | 'filesLatency50'
  | 'filesLatency100'
  | 'filesServerLatency50'
  | 'filesServerLatency100'
  | 'filesThrottling'
  | 'anfVolumeFree15'
  | 'anfVolumeFree5'
  | 'serviceHealthIncident'
  | 'serviceHealthMaintenance'
  | 'serviceHealthAdvisory'
  | 'serviceHealthSecurity'

@export()
@description('Named groups of alerts. Use them in additionalResources.alertSets.')
type AlertSet = 'core' | 'hostPool' | 'sessionHosts' | 'resources' | 'scaling' | 'fslogix' | 'storage' | 'serviceHealth' | 'all'

// core: the monitoring itself, users who cannot work, and Microsoft incidents. These only use
// data that the baseline sets up itself (AVD diagnostics and the collectors), so they work
// without a session-host DCR.
var core = [
  'collectorFailed'
  'collectorStale'
  'diagnosticDataMissing'
  'noResourcesAvailable'
  'healthCheckFailure'
  'capacity95'
  'personalUnhealthy'
  'serviceHealthIncident'
]
var hostPool = [
  'capacity50'
  'capacity85'
  'capacity95'
  'connectionFailure'
  'noResourcesAvailable'
]
var sessionHosts = [
  'healthCheckFailure'
  'personalUnhealthy'
  'agentUpgrade'
  'drainedIdle'
]
// resources and fslogix need the session-host DCR (Perf and Event data).
var resources = [
  'cpu85'
  'cpu95'
  'memory2GB'
  'memory1GB'
  'localDiskFree10'
  'localDiskFree5'
  'osDiskBandwidth85'
  'osDiskBandwidth95'
]
var scaling = [
  'scalingPlanDisabled4h'
  'scalingPlanDisabled24h'
  'scalingPlanRemoved'
  'autoscaleFailures'
]
var fslogix = [
  'fslogixFree5'
  'fslogixFree2'
  'fslogixDiskInUse'
  'fslogixAttach'
  'fslogixNetwork'
  'fslogixServiceDisabled'
  'fslogixCompaction'
]
// storage only creates rules when fileStorageAccounts or anfVolumes are configured.
var storage = [
  'fileShareCapacity15'
  'fileShareCapacity5'
  'filesAvailability'
  'filesLatency50'
  'filesLatency100'
  'filesServerLatency50'
  'filesServerLatency100'
  'filesThrottling'
  'anfVolumeFree15'
  'anfVolumeFree5'
]
var serviceHealth = [
  'serviceHealthIncident'
  'serviceHealthMaintenance'
  'serviceHealthAdvisory'
  'serviceHealthSecurity'
]

@export()
@description('Alert IDs per alert set.')
var alertSetDefinitions = {
  core: core
  hostPool: hostPool
  sessionHosts: sessionHosts
  resources: resources
  scaling: scaling
  fslogix: fslogix
  storage: storage
  serviceHealth: serviceHealth
  all: union(core, hostPool, sessionHosts, resources, scaling, fslogix, storage, serviceHealth)
}
