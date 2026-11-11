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

if ([string]::IsNullOrWhiteSpace([string]$built.parameters.deployment.value.location)) {
    throw 'Set deployment.location in the parameter file.'
}
if ([string]::IsNullOrWhiteSpace([string]$built.parameters.deployment.value.notificationEmail)) {
    throw 'Set deployment.notificationEmail in the parameter file.'
}
if (@($built.parameters.hostPools.value).Count -eq 0) {
    throw 'Add at least one host pool to hostPools.'
}

return $built
