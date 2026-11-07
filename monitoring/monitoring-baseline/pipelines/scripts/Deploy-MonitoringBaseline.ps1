param(
    [Parameter(Mandatory)] [string] $ParameterFile,
    [Parameter(Mandatory)] [string] $DeploymentName,
    [Parameter(Mandatory)] [string] $ScheduleDeploymentName
)

$ErrorActionPreference = 'Stop'

$built = & (Join-Path $PSScriptRoot 'Get-BuiltParameters.ps1') -ParameterFile $ParameterFile
$location = $built.parameters.location.value

$deploymentJson = az deployment sub create `
    --name $DeploymentName `
    --location $location `
    --parameters $ParameterFile `
    --output json
if ($LASTEXITCODE -ne 0) { throw 'AVD monitoring deployment failed.' }

$outputs = ($deploymentJson | Out-String | ConvertFrom-Json -Depth 100).properties.outputs
$resourceGroup = $built.parameters.monitoringResourceGroupName.value
$account = $outputs.automationAccountName.value

az extension add --name automation --yes
if ($LASTEXITCODE -ne 0) { throw 'Azure Automation CLI extension installation failed.' }

& (Join-Path $PSScriptRoot 'Wait-AutomationModules.ps1') `
    -ResourceGroup $resourceGroup `
    -AccountName $account `
    -ExpectedModules $built.parameters.azModuleVersions.value

$runbooks = [ordered]@{
    $outputs.hostPoolRunbookName.value = 'src/scripts/collect-host-pools.ps1'
    $outputs.storageRunbookName.value = 'src/scripts/collect-azure-files.ps1'
}
& (Join-Path $PSScriptRoot 'Publish-Runbooks.ps1') `
    -ResourceGroup $resourceGroup `
    -AccountName $account `
    -Runbooks $runbooks

& (Join-Path $PSScriptRoot 'Deploy-CollectorSchedules.ps1') `
    -DeploymentName $ScheduleDeploymentName `
    -ResourceGroup $resourceGroup `
    -AccountName $account `
    -NamePrefix $built.parameters.alertNamePrefix.value `
    -HostPoolResourceIds @($outputs.hostPoolResourceIds.value) `
    -ScalingPlanResourceIds @($outputs.scalingPlanResourceIds.value) `
    -FileStorageAccountResourceIds @($outputs.fileStorageAccountResourceIds.value)
