[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $AccountName,
    [Parameter(Mandatory)] [object] $ExpectedModules,
    [string[]] $ModuleNames = @('Az.Accounts', 'Az.DesktopVirtualization', 'Az.Storage'),
    [int] $MaxAttempts = 90,
    [int] $DelaySeconds = 10
)

# Waits until the Az modules in the Automation account are imported at the configured version.
$ErrorActionPreference = 'Stop'

$subscriptionId = az account show --query id --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Could not determine the deployment subscription.' }

foreach ($moduleName in $ModuleNames) {
    if ($ExpectedModules -is [System.Collections.IDictionary]) {
        $expectedVersion = $ExpectedModules[$moduleName]
    } else {
        $property = $ExpectedModules.PSObject.Properties[$moduleName]
        $expectedVersion = if ($property) { $property.Value } else { $null }
    }
    if ([string]::IsNullOrWhiteSpace([string]$expectedVersion)) { throw "No version configured for Automation module $moduleName." }

    $moduleUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Automation/automationAccounts/$AccountName/modules/${moduleName}?api-version=2023-11-01"
    $moduleReady = $false
    for ($attempt = 0; $attempt -lt $MaxAttempts; $attempt++) {
        $moduleJson = az rest --method get --url $moduleUrl --output json 2>$null
        if ($LASTEXITCODE -eq 0) {
            $module = $moduleJson | ConvertFrom-Json -Depth 10
            if ($module.properties.provisioningState -eq 'Succeeded' -and $module.properties.version -eq $expectedVersion) { $moduleReady = $true; break }
            if ($module.properties.provisioningState -eq 'Failed') { throw "Import of Automation module $moduleName failed: $($module.properties.error.message)" }
        }
        Start-Sleep -Seconds $DelaySeconds
    }
    if (-not $moduleReady) {
        $minutes = [math]::Round($MaxAttempts * $DelaySeconds / 60)
        throw "Automation module $moduleName did not reach version $expectedVersion after $minutes minutes."
    }
}
