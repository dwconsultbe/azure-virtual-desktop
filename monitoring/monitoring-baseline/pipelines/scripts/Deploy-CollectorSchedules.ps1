[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $DeploymentName,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $AccountName,
    [Parameter(Mandatory)] [string] $NamePrefix,
    [Parameter(Mandatory)] [string] $HostPoolRunbookName,
    [Parameter(Mandatory)] [string] $StorageRunbookName,
    [string[]] $HostPoolResourceIds = @(),
    [string[]] $ScalingPlanResourceIds = @(),
    [string[]] $FileStorageAccountResourceIds = @(),
    [string] $TemplateFile = 'src/collector-schedules.bicep'
)

# Deploys the schedules and reconciles their runbook links. Azure Automation does
# not reliably update an existing jobSchedule through an ARM PUT, so those links
# are managed through the REST API instead of Bicep.
$ErrorActionPreference = 'Stop'

$scheduleParameters = @{
    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters     = @{
        automationAccountName         = @{ value = $AccountName }
        namePrefix                    = @{ value = $NamePrefix }
        fileStorageAccountResourceIds = @{ value = @($FileStorageAccountResourceIds) }
    }
}

# AGENT_TEMPDIRECTORY exists only in Azure DevOps; use the system temp folder elsewhere.
$tempDirectory = if ($env:AGENT_TEMPDIRECTORY) { $env:AGENT_TEMPDIRECTORY } else { [System.IO.Path]::GetTempPath() }
$scheduleFile = Join-Path $tempDirectory 'avd-collector-schedules.parameters.json'
$scheduleParameters | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $scheduleFile

az deployment group create `
    --name $DeploymentName `
    --resource-group $ResourceGroup `
    --template-file $TemplateFile `
    --parameters "@$scheduleFile" `
    --output none
if ($LASTEXITCODE -ne 0) { throw 'Collector schedule deployment failed.' }

$subscriptionId = (az account show --query id --output tsv).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionId)) { throw 'Could not determine the deployment subscription.' }

$baseUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Automation/automationAccounts/$AccountName/jobSchedules"
$existing = @((az rest --method get --url "$baseUrl`?api-version=2023-11-01" --output json | ConvertFrom-Json -Depth 100).value)
if ($LASTEXITCODE -ne 0) { throw 'Could not list existing Automation job schedules.' }

function Remove-JobScheduleLink {
    param([Parameter(Mandatory)] [object] $JobSchedule)

    $jobScheduleId = [string]$JobSchedule.properties.jobScheduleId
    if ([string]::IsNullOrWhiteSpace($jobScheduleId)) {
        throw "Could not determine the job schedule ID for $($JobSchedule.properties.runbook.name)/$($JobSchedule.properties.schedule.name)."
    }
    az rest --method delete --url "$baseUrl/$jobScheduleId`?api-version=2023-11-01" --output none
    if ($LASTEXITCODE -ne 0) { throw "Could not remove existing job schedule $jobScheduleId." }
}

function Sync-JobSchedule {
    param(
        [Parameter(Mandatory)] [string] $RunbookName,
        [Parameter(Mandatory)] [string] $ScheduleName,
        [Parameter(Mandatory)] [hashtable] $Parameters
    )

    $existingLinks = @($existing | Where-Object {
        $_.properties.runbook.name -eq $RunbookName -and $_.properties.schedule.name -eq $ScheduleName
    })
    $current = $existingLinks | Select-Object -First 1
    $same = $null -ne $current
    if ($same) {
        foreach ($key in $Parameters.Keys) {
            if ([string]$current.properties.parameters.$key -ne [string]$Parameters[$key]) { $same = $false }
        }
    }
    if ($same -and $existingLinks.Count -eq 1) { return }

    foreach ($match in $existingLinks) {
        Remove-JobScheduleLink -JobSchedule $match
    }

    $body = @{
        properties = @{
            runbook = @{ name = $RunbookName }
            schedule = @{ name = $ScheduleName }
            parameters = @{}
        }
    }
    foreach ($key in $Parameters.Keys) { $body.properties.parameters[$key] = [string]$Parameters[$key] }
    $jobScheduleId = [guid]::NewGuid().Guid
    # Pass the body as a file with an explicit content type. On Windows, az.cmd mangles the
    # quotes of an inline JSON body, and Azure then rejects it (415 Unsupported Media Type).
    $bodyFile = Join-Path $tempDirectory "avd-job-schedule-$jobScheduleId.json"
    $body | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $bodyFile -Encoding utf8NoBOM
    az rest --method put --url "$baseUrl/$jobScheduleId`?api-version=2023-11-01" --headers 'Content-Type=application/json' --body "@$bodyFile" --output none
    $putExitCode = $LASTEXITCODE
    Remove-Item -LiteralPath $bodyFile -ErrorAction SilentlyContinue
    if ($putExitCode -ne 0) { throw "Could not create job schedule for $RunbookName/$ScheduleName." }
}

$offsets = @(15, 30, 45, 60)
for ($index = 0; $index -lt $offsets.Count; $index++) {
    Sync-JobSchedule `
        -RunbookName $HostPoolRunbookName `
        -ScheduleName "$NamePrefix-host-pool-$index" `
        -Parameters @{
            HostPoolResourceIds = ($HostPoolResourceIds -join ',')
            ScalingPlanResourceIds = ($ScalingPlanResourceIds -join ',')
            CloudEnvironment = 'AzureCloud'
        }
}

if ($FileStorageAccountResourceIds.Count -gt 0) {
    for ($index = 0; $index -lt $offsets.Count; $index++) {
        Sync-JobSchedule `
            -RunbookName $StorageRunbookName `
            -ScheduleName "$NamePrefix-azure-files-$index" `
            -Parameters @{
                StorageAccountResourceIds = ($FileStorageAccountResourceIds -join ',')
                CloudEnvironment = 'AzureCloud'
            }
    }
} else {
    $storageScheduleNames = @($offsets | ForEach-Object -Begin { $index = 0 } -Process { "$NamePrefix-azure-files-$index"; $index++ })
    $storageLinks = @($existing | Where-Object {
        $_.properties.runbook.name -eq $StorageRunbookName -and $_.properties.schedule.name -in $storageScheduleNames
    })
    foreach ($link in $storageLinks) { Remove-JobScheduleLink -JobSchedule $link }

    $otherLinks = @($existing | Where-Object {
        $_.properties.runbook.name -ne $StorageRunbookName -and $_.properties.schedule.name -in $storageScheduleNames
    })
    $scheduleList = az automation schedule list `
        --automation-account-name $AccountName `
        --resource-group $ResourceGroup `
        --output json
    if ($LASTEXITCODE -ne 0) { throw 'Could not list Automation schedules for cleanup.' }
    $scheduleResources = @($scheduleList | ConvertFrom-Json -Depth 100)
    foreach ($schedule in $scheduleResources | Where-Object { $_.name -in $storageScheduleNames }) {
        if ($schedule.name -in @($otherLinks | ForEach-Object { $_.properties.schedule.name })) { continue }

        az automation schedule update `
            --automation-account-name $AccountName `
            --resource-group $ResourceGroup `
            --name $schedule.name `
            --is-enabled false `
            --output none
        if ($LASTEXITCODE -ne 0) { throw "Could not disable obsolete storage schedule $($schedule.name)." }

        az automation schedule delete `
            --automation-account-name $AccountName `
            --resource-group $ResourceGroup `
            --name $schedule.name `
            --yes `
            --output none
        if ($LASTEXITCODE -ne 0) { throw "Could not delete obsolete storage schedule $($schedule.name)." }
    }
}
