[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $AccountName,
    # Runbook name -> path of the script file with its content.
    [Parameter(Mandatory)] [System.Collections.IDictionary] $Runbooks
)

# Replaces the content of the Automation runbooks with the in-repository scripts and publishes them.
$ErrorActionPreference = 'Stop'

foreach ($runbook in $Runbooks.Keys) {
    $scriptPath = $Runbooks[$runbook]
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Runbook script not found: $scriptPath" }

    az automation runbook replace-content `
        --automation-account-name $AccountName `
        --resource-group $ResourceGroup `
        --name $runbook `
        --content "@$scriptPath" `
        --output none
    if ($LASTEXITCODE -ne 0) { throw "Runbook content update failed: $runbook" }

    az automation runbook publish `
        --automation-account-name $AccountName `
        --resource-group $ResourceGroup `
        --name $runbook `
        --output none
    if ($LASTEXITCODE -ne 0) { throw "Runbook publishing failed: $runbook" }
}
