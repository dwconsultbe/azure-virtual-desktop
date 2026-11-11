// Names shared between the Bicep that creates the collector resources, the KQL that reads
// their output and the schedules. Keep them in one place so they cannot drift apart.
// Changing a name creates a new resource next to the old one in Azure.

@export()
func hostPoolCollectorName() string => 'avd-host-pool-collector'

@export()
func storageCollectorName() string => 'avd-storage-collector'

@export()
func jobDiagnosticsName(prefix string) string => '${prefix}-monitoring-jobs-to-law'

@export()
func hostPoolScheduleName(prefix string, index int) string => '${prefix}-host-pool-${index}'

@export()
func azureFilesScheduleName(prefix string, index int) string => '${prefix}-azure-files-${index}'
