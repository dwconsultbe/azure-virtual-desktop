# Produces the comma-delimited storage collector JobStreams format consumed by
# the Azure Files share-capacity alerts.
param(
    [Parameter(Mandatory)] [string] $StorageAccountResourceIds,
    [string] $CloudEnvironment = 'AzureCloud'
)

$ErrorActionPreference = 'Stop'
Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity -Environment $CloudEnvironment | Out-Null

$ids = $StorageAccountResourceIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$failures = @()
foreach ($id in $ids) {
    # One storage account must not stop the others: collect the error, keep going and
    # fail the job at the end so the collector-failed alert still fires.
    try {
        $resourceMatch = [regex]::Match($id, '^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.Storage/storageAccounts/([^/]+)$', 'IgnoreCase')
        if (-not $resourceMatch.Success) {
            throw "Invalid storage account resource ID: $id"
        }
        $subscriptionId, $resourceGroupName, $accountName = $resourceMatch.Groups[1].Value, $resourceMatch.Groups[2].Value, $resourceMatch.Groups[3].Value
        Set-AzContext -SubscriptionId $subscriptionId | Out-Null

        $shares = @(Get-AzRmStorageShare -ResourceGroupName $resourceGroupName -StorageAccountName $accountName | Where-Object { $null -ne $_ })
        foreach ($listedShare in $shares) {
            $share = Get-AzRmStorageShare -ResourceGroupName $resourceGroupName -StorageAccountName $accountName -Name $listedShare.Name -GetShareUsage
            $quotaGiB = [double]$share.QuotaGiB
            if ($quotaGiB -le 0) { continue }
            $usedGiB = [double]$share.ShareUsageBytes / 1073741824
            $remaining = 100 - (($usedGiB / $quotaGiB) * 100)
            $fields = @(
                'AzFiles', $subscriptionId, $resourceGroupName, $accountName, $share.Name,
                $quotaGiB.ToString([cultureinfo]::InvariantCulture),
                $usedGiB.ToString([cultureinfo]::InvariantCulture),
                $remaining.ToString([cultureinfo]::InvariantCulture), $share.Id
            )
            Write-Output ($fields -join ',')
        }
    } catch {
        $failures += "$id : $($_.Exception.Message)"
        Write-Warning "Storage collector failed for $id : $($_.Exception.Message)"
    }
}
if ($failures.Count -gt 0) {
    throw "Storage collector failed for $($failures.Count) of $($ids.Count) storage account(s): $($failures -join '; ')"
}
