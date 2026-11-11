param(
    [Parameter(Mandatory)] [string] $ParameterFile,
    [Parameter(Mandatory)] [string] $DeploymentName,
    [Parameter(Mandatory)] [string] $ScheduleDeploymentName
)

# Deploys the baseline: subscription template, Automation modules, runbooks, schedules and a
# first collector run. Used by the Azure DevOps pipeline and by deploy.ps1.
$ErrorActionPreference = 'Stop'

$projectDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ParameterFile = (Resolve-Path -LiteralPath $ParameterFile).Path

$built = & (Join-Path $PSScriptRoot 'Get-BuiltParameters.ps1') -ParameterFile $ParameterFile
$location = $built.parameters.deployment.value.location

Write-Host 'Deploying the monitoring baseline template...'
$deploymentJson = az deployment sub create `
    --name $DeploymentName `
    --location $location `
    --parameters $ParameterFile `
    --output json
if ($LASTEXITCODE -ne 0) { throw 'AVD monitoring deployment failed.' }

$outputs = ($deploymentJson | Out-String | ConvertFrom-Json -Depth 100).properties.outputs
$resourceGroup = $outputs.monitoringResourceGroupName.value
$account = $outputs.automationAccountName.value
Write-Host "Monitoring resource group: $resourceGroup"
Write-Host "Log Analytics workspace: $($outputs.logAnalyticsWorkspaceResourceId.value)"

az extension add --name automation --yes --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Azure Automation CLI extension installation failed.' }

Write-Host 'Waiting for the PowerShell modules in the Automation Account...'
& (Join-Path $PSScriptRoot 'Wait-AutomationModules.ps1') `
    -ResourceGroup $resourceGroup `
    -AccountName $account `
    -ExpectedModules $outputs.azModuleVersions.value

Write-Host 'Publishing the collector runbooks...'
$runbooks = [ordered]@{
    $outputs.hostPoolRunbookName.value = Join-Path $projectDir 'src/scripts/collect-host-pools.ps1'
    $outputs.storageRunbookName.value  = Join-Path $projectDir 'src/scripts/collect-azure-files.ps1'
}
& (Join-Path $PSScriptRoot 'Publish-Runbooks.ps1') `
    -ResourceGroup $resourceGroup `
    -AccountName $account `
    -Runbooks $runbooks

Write-Host 'Creating the collector schedules...'
$hostPoolParameters = @{
    HostPoolResourceIds    = @($outputs.hostPoolResourceIds.value) -join ','
    ScalingPlanResourceIds = @($outputs.scalingPlanResourceIds.value) -join ','
    CloudEnvironment       = 'AzureCloud'
}
$storageIds = @($outputs.fileStorageAccountResourceIds.value)
& (Join-Path $PSScriptRoot 'Deploy-CollectorSchedules.ps1') `
    -DeploymentName $ScheduleDeploymentName `
    -ResourceGroup $resourceGroup `
    -AccountName $account `
    -NamePrefix $outputs.collectorNamePrefix.value `
    -HostPoolRunbookName $outputs.hostPoolRunbookName.value `
    -StorageRunbookName $outputs.storageRunbookName.value `
    -HostPoolResourceIds @($outputs.hostPoolResourceIds.value) `
    -ScalingPlanResourceIds @($outputs.scalingPlanResourceIds.value) `
    -FileStorageAccountResourceIds $storageIds `
    -TemplateFile (Join-Path $projectDir 'src/collector-schedules.bicep')

# Start each collector once, so data arrives within minutes instead of at the first
# scheduled run, and collectorStale does not fire on a new installation.
Write-Host 'Starting a first collector run...'
$subscriptionId = (az account show --query id --output tsv).Trim()
$jobsUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Automation/automationAccounts/$account/jobs"
$firstRuns = @(@{ Runbook = $outputs.hostPoolRunbookName.value; Parameters = $hostPoolParameters })
if ($storageIds.Count -gt 0) {
    $firstRuns += @{ Runbook = $outputs.storageRunbookName.value; Parameters = @{ StorageAccountResourceIds = $storageIds -join ','; CloudEnvironment = 'AzureCloud' } }
}
foreach ($run in $firstRuns) {
    $bodyFile = Join-Path ([System.IO.Path]::GetTempPath()) "avd-collector-job-$([guid]::NewGuid().Guid).json"
    @{ properties = @{ runbook = @{ name = $run.Runbook }; parameters = $run.Parameters } } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $bodyFile -Encoding utf8NoBOM
    az rest --method put --url "$jobsUrl/$([guid]::NewGuid().Guid)?api-version=2023-11-01" --headers 'Content-Type=application/json' --body "@$bodyFile" --output none
    if ($LASTEXITCODE -ne 0) { Write-Warning "Could not start $($run.Runbook). The first scheduled run starts within 15 minutes." }
    Remove-Item -LiteralPath $bodyFile -ErrorAction SilentlyContinue
}

Write-Host 'Deployment finished.'
