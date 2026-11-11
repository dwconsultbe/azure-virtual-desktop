<#
.SYNOPSIS
    Deploys the AVD monitoring baseline from your own machine. No Azure DevOps needed.

.DESCRIPTION
    1. Checks PowerShell 7, the Azure CLI, your Azure sign-in and the parameter file.
    2. Shows a preview (what-if) of the changes and asks for confirmation.
    3. Deploys the template, publishes the collectors, creates the schedules and starts a
       first collector run.

.EXAMPLE
    az login
    ./deploy.ps1

.EXAMPLE
    ./deploy.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -ParameterFile parameters/prod.bicepparam
#>
[CmdletBinding()]
param(
    # Parameter file, relative to this folder or absolute.
    [string] $ParameterFile = 'parameters/main.example.bicepparam',
    # Subscription to deploy to. Defaults to the current Azure CLI subscription.
    [string] $SubscriptionId,
    # Skip the confirmation after the preview.
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'
# Paths are relative to this folder, so the script works from any working directory.
if (-not [System.IO.Path]::IsPathRooted($ParameterFile) -and -not (Test-Path -LiteralPath $ParameterFile)) {
    $ParameterFile = Join-Path $PSScriptRoot $ParameterFile
}

function Write-Step([string] $Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }
function Stop-WithHint([string] $Problem, [string] $Fix) {
    Write-Host "`n$Problem" -ForegroundColor Red
    Write-Host "Fix: $Fix" -ForegroundColor Yellow
    exit 1
}

# --- 1. Checks ---------------------------------------------------------------------
Write-Step 'Checking prerequisites'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Stop-WithHint 'PowerShell 7 or later is required.' 'Install it from https://aka.ms/powershell and run this script with pwsh.'
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Stop-WithHint 'The Azure CLI is not installed.' 'Install it from https://aka.ms/installazurecli and open a new terminal.'
}

if ($SubscriptionId) {
    az account set --subscription $SubscriptionId 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-WithHint "Cannot select subscription $SubscriptionId." 'Run az login, or check the subscription ID.' }
}
$accountJson = az account show --output json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $accountJson) { Stop-WithHint 'You are not signed in to Azure.' 'Run az login and start this script again.' }
$account = $accountJson | ConvertFrom-Json

az bicep install --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0) { Stop-WithHint 'Bicep could not be installed.' 'Run az bicep install and check the error.' }

if (-not (Test-Path -LiteralPath $ParameterFile -PathType Leaf)) {
    Stop-WithHint "Parameter file not found: $ParameterFile" 'Use -ParameterFile, or fill in parameters/main.example.bicepparam.'
}
$placeholders = @(Get-Content -LiteralPath $ParameterFile | Where-Object { $_ -notmatch '^\s*//' -and $_ -match 'REPLACE_' })
if ($placeholders.Count -gt 0) {
    Stop-WithHint "The parameter file still has $($placeholders.Count) value(s) to fill in:`n$(($placeholders | ForEach-Object { '  ' + $_.Trim() }) -join "`n")" `
        "Open $ParameterFile and replace every REPLACE_ value. See docs/administrator-guide.md, step 2."
}

$built = & (Join-Path $PSScriptRoot "pipelines/scripts/Get-BuiltParameters.ps1") -ParameterFile $ParameterFile
$settings = $built.parameters
$alertSets = @($settings.additionalResources.value.alertSets) | Where-Object { $_ }
$alertIds = @($settings.additionalResources.value.enabledAlertRuleIds) | Where-Object { $_ }

Write-Host "Subscription:      $($account.name) ($($account.id))"
Write-Host "Signed in as:      $($account.user.name)"
Write-Host "Region:            $($settings.deployment.value.location)"
Write-Host "Resource group:    $($settings.deployment.value.monitoringResourceGroupName)"
Write-Host "Host pools:        $((@($settings.hostPools.value) | ForEach-Object { $_.name }) -join ', ')"
Write-Host "Alert sets:        $(if ($alertSets) { $alertSets -join ', ' } else { 'none' })"
if ($alertIds) { Write-Host "Extra alert IDs:   $($alertIds -join ', ')" }
Write-Host "Notifications to:  $($settings.deployment.value.notificationEmail)"

# --- 2. Preview --------------------------------------------------------------------
Write-Step 'Preview of the changes (what-if)'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
az deployment sub what-if `
    --name "avd-monitoring-$stamp" `
    --location $settings.deployment.value.location `
    --parameters $ParameterFile `
    --result-format ResourceIdOnly
if ($LASTEXITCODE -ne 0) { Stop-WithHint 'The preview failed.' 'Read the error above. The administrator guide has a troubleshooting table.' }

if (-not $Yes) {
    $answer = Read-Host "`nDeploy these changes to '$($account.name)'? Type yes to continue"
    if ($answer -ne 'yes') { Write-Host 'Stopped. Nothing was changed.'; exit 0 }
}

# --- 3. Deploy ---------------------------------------------------------------------
Write-Step 'Deploying (this takes about 5 to 10 minutes)'
& (Join-Path $PSScriptRoot "pipelines/scripts/Deploy-MonitoringBaseline.ps1") `
    -ParameterFile $ParameterFile `
    -DeploymentName "avd-monitoring-$stamp" `
    -ScheduleDeploymentName "avd-collector-schedules-$stamp"

Write-Step 'Next steps'
Write-Host '1. Wait about 15 minutes for the first data.'
Write-Host '2. Check the data with the query in docs/administrator-guide.md, step 5.'
Write-Host '3. Enable more alert sets in the parameter file and run this script again.'
