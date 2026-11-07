// Names of the collector resources, derived from one prefix (the alertNamePrefix parameter).
// The Bicep that creates a resource and the KQL that reads its output both use these functions,
// so a name cannot differ between them. With the prefix avd-monitoring they give the names that the
// first deployment already created, so nothing is renamed.

@export()
func hostPoolCollectorName(prefix string) string => '${prefix}-host-pool-collector'

@export()
func storageCollectorName(prefix string) string => '${prefix}-storage-collector'

@export()
func jobDiagnosticsName(prefix string) string => '${prefix}-monitoring-jobs-to-law'

@export()
func hostPoolScheduleName(prefix string, index int) string => '${prefix}-host-pool-${index}'

@export()
func azureFilesScheduleName(prefix string, index int) string => '${prefix}-azure-files-${index}'
