$ErrorActionPreference = 'Stop'

function Disable-AzContextAutosave { param($Scope) }
function Connect-AzAccount { param([switch] $Identity, [string] $Environment) }
function Set-AzContext { param([string] $SubscriptionId) }
function Get-AzWvdHostPool {
    param($Name, $ResourceGroupName, $SubscriptionId)
    if ($Name -eq 'badpool') { throw 'simulated host pool API failure' }
    if ($Name -eq 'personalpool') { return [pscustomobject]@{ HostPoolType = 'Personal'; MaxSessionLimit = 999999 } }
    [pscustomobject]@{ HostPoolType = 'Pooled'; MaxSessionLimit = 10 }
}
function Get-AzWvdSessionHost {
    param($HostPoolName, $ResourceGroupName)
    if ($HostPoolName -eq 'personalpool') {
        return @(
            [pscustomobject]@{ Name = 'personalpool/off1'; Status = 'Shutdown'; AllowNewSession = $true; AssignedUser = 'a@example.com' },
            [pscustomobject]@{ Name = 'personalpool/bad1'; Status = 'NoHeartbeat'; AllowNewSession = $true; AssignedUser = 'c@example.com' }
        )
    }
    [pscustomobject]@{ Name = 'pool/host1'; Status = 'Available'; AllowNewSession = $true; AssignedUser = $null }
}
function Get-AzWvdUserSession {
    param($HostPoolName, $ResourceGroupName)
    [pscustomobject]@{ SessionState = 'Active'; UserPrincipalName = 'user@example.com' }
}
function Get-AzWvdScalingPlan {
    param($Name, $ResourceGroupName, $SubscriptionId, $ErrorAction)
    [pscustomobject]@{
        Name = 'plan1'
        HostPoolReference = @([pscustomobject]@{
            HostPoolArmPath = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/pool1'
            ScalingPlanEnabled = $false
        })
    }
}
function Get-AzRmStorageShare {
    param($ResourceGroupName, $StorageAccountName, $Name, [switch] $GetShareUsage)
    if ($StorageAccountName -eq 'badstorage') { throw 'simulated storage API failure' }
    if ($GetShareUsage) {
        return [pscustomobject]@{
            Name = $Name; QuotaGiB = 100; ShareUsageBytes = 53687091200
            Id = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-storage/providers/Microsoft.Storage/storageAccounts/stprofiles/fileServices/default/shares/profiles'
        }
    }
    [pscustomobject]@{ Name = 'profiles' }
}

$project = Split-Path $PSScriptRoot -Parent
$poolId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/pool1'
$planId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/scalingPlans/plan1'
$hostOutput = & (Join-Path $project 'src/scripts/collect-host-pools.ps1') -HostPoolResourceIds $poolId -ScalingPlanResourceIds $planId
$hostFields = $hostOutput -split '\|'
if ($hostFields.Count -ne 15 -or $hostFields[5] -ne '1' -or $hostFields[9] -ne '10' -or $hostFields[14] -ne 'Disabled') {
    throw "Host pool collector output contract failed: $hostOutput"
}

$storageId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-storage/providers/Microsoft.Storage/storageAccounts/stprofiles'
$storageOutput = & (Join-Path $project 'src/scripts/collect-azure-files.ps1') -StorageAccountResourceIds $storageId
$storageFields = $storageOutput -split ','
if ($storageFields.Count -ne 9 -or $storageFields[4] -ne 'profiles' -or $storageFields[7] -ne '50') {
    throw "Storage collector output contract failed: $storageOutput"
}

# A failing host pool or storage account must not stop the others, and the job must
# still fail at the end so the collector-failed alert fires.
$badPoolId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/badpool'
$lines = [System.Collections.Generic.List[string]]::new()
$threw = $false
try {
    & (Join-Path $project 'src/scripts/collect-host-pools.ps1') -HostPoolResourceIds "$badPoolId,$poolId" -ScalingPlanResourceIds $planId 3>$null |
        ForEach-Object { $lines.Add([string]$_) }
} catch { $threw = $true }
if (-not $threw) { throw 'Host pool collector must fail the job when one host pool fails.' }
if ($lines.Count -ne 1 -or ($lines[0] -split '\|')[0] -ne 'pool1') {
    throw "Host pool collector must still report the healthy pool after a failure: $($lines -join ' / ')"
}

$badStorageId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-storage/providers/Microsoft.Storage/storageAccounts/badstorage'
$lines = [System.Collections.Generic.List[string]]::new()
$threw = $false
try {
    & (Join-Path $project 'src/scripts/collect-azure-files.ps1') -StorageAccountResourceIds "$badStorageId,$storageId" 3>$null |
        ForEach-Object { $lines.Add([string]$_) }
} catch { $threw = $true }
if (-not $threw) { throw 'Storage collector must fail the job when one storage account fails.' }
if ($lines.Count -ne 1 -or ($lines[0] -split ',')[4] -ne 'profiles') {
    throw "Storage collector must still report the healthy account after a failure: $($lines -join ' / ')"
}

# An unreadable scaling plan must not hide a plan that was read successfully.
$badPlanId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/scalingPlans/not-a-plan-id/extra'
$unknownOutput = & (Join-Path $project 'src/scripts/collect-host-pools.ps1') -HostPoolResourceIds $poolId -ScalingPlanResourceIds $badPlanId 3>$null
if (($unknownOutput -split '\|')[14] -ne 'Unknown') {
    throw "Unreadable scaling plan must report Unknown: $unknownOutput"
}
$mixedOutput = & (Join-Path $project 'src/scripts/collect-host-pools.ps1') -HostPoolResourceIds $poolId -ScalingPlanResourceIds "$badPlanId,$planId" 3>$null
if (($mixedOutput -split '\|')[14] -ne 'Disabled') {
    throw "A readable matching plan must win over an unreadable one: $mixedOutput"
}

# Hosts that are shut down (stopped or deallocated) are off on purpose; only a real problem counts.
$personalId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/personalpool'
$personalOutput = & (Join-Path $project 'src/scripts/collect-host-pools.ps1') -HostPoolResourceIds $personalId
$personalFields = $personalOutput -split '\|'
if ($personalFields.Count -ne 15 -or $personalFields[2] -ne 'Personal' -or $personalFields[10] -ne '1') {
    throw "Personal pool must count only the host that is really unhealthy: $personalOutput"
}
$personalHosts = @($personalFields[11] | ConvertFrom-Json)
if ($personalHosts.Count -ne 1 -or $personalHosts[0].SessionHost -ne 'personalpool/bad1' -or $personalHosts[0].Status -ne 'NoHeartbeat') {
    throw "Personal pool details must list the unhealthy host with its status: $($personalFields[11])"
}

Write-Output 'Collector output contracts passed.'
