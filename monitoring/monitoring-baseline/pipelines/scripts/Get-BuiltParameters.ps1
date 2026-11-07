[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ParameterFile
)

# Compiles a .bicepparam file and returns the resulting parameters object.
$ErrorActionPreference = 'Stop'

$raw = az bicep build-params --file $ParameterFile --stdout
if ($LASTEXITCODE -ne 0) { throw "Bicep parameter build failed for $ParameterFile." }

$buildOutput = $raw | Out-String | ConvertFrom-Json -Depth 100
$built = $buildOutput.parametersJson | ConvertFrom-Json -Depth 100

if (-not $built.parameters.location.value) { throw 'The parameter file must define location.' }

$parameters = $built.parameters
$createWorkspace = [bool]$parameters.createLogAnalyticsWorkspace.value
$createDcr = [bool]$parameters.deployAvdGuestDataDcr.value -or [bool]$parameters.deployVmInsightsDcr.value

if ($createWorkspace -and [string]::IsNullOrWhiteSpace([string]$parameters.newLogAnalyticsWorkspaceName.value)) {
    throw 'Set newLogAnalyticsWorkspaceName when createLogAnalyticsWorkspace is true.'
}

if (-not $createWorkspace) {
    $workspace = $parameters.logAnalyticsWorkspace.value
    if ([string]::IsNullOrWhiteSpace([string]$workspace.name) -or [string]::IsNullOrWhiteSpace([string]$workspace.resourceGroupName)) {
        throw 'Set logAnalyticsWorkspace name and resourceGroupName, or enable createLogAnalyticsWorkspace.'
    }
}

if ([bool]$parameters.associateDcrsWithPolicy.value -and -not $createDcr) {
    throw 'Enable at least one DCR when associateDcrsWithPolicy is true.'
}

if ($createDcr -and -not $createWorkspace -and [string]::IsNullOrWhiteSpace([string]$parameters.dataCollectionRuleLocation.value)) {
    throw 'Set dataCollectionRuleLocation to the region of the existing Log Analytics workspace before deploying a DCR.'
}

return $built
