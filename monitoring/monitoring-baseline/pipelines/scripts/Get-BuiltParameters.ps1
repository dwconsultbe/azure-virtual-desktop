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

return $built
