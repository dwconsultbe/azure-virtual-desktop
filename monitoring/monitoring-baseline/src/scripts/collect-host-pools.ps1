# Produces the pipe-delimited host pool collector JobStreams format consumed by
# the host pool capacity, scaling plan, and diagnostic-silence alerts.
param(
    [Parameter(Mandatory)] [string] $HostPoolResourceIds,
    [string] $ScalingPlanResourceIds = '',
    [string] $CloudEnvironment = 'AzureCloud'
)

$ErrorActionPreference = 'Stop'
Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity -Environment $CloudEnvironment | Out-Null

$ids = $HostPoolResourceIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$planIds = $ScalingPlanResourceIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
# Session host statuses that mean an assigned personal host was switched off on purpose.
# Shutdown covers a stopped or deallocated VM (confirmed: a deallocated VM reports Shutdown).
# Hibernated VMs are not in the documented status list; measure the status of a hibernated
# host with Get-AzWvdSessionHost and add it here if it is not Shutdown.
$intentionallyOffStatuses = @('Shutdown')
$failures = @()
foreach ($id in $ids) {
    # One host pool must not stop the others: collect the error, keep going and fail
    # the job at the end so the collector-failed alert still fires.
    try {
        $resourceMatch = [regex]::Match($id, '^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.DesktopVirtualization/hostPools/([^/]+)$', 'IgnoreCase')
        if (-not $resourceMatch.Success) {
            throw "Invalid host pool resource ID: $id"
        }
        $subscriptionId, $resourceGroupName, $hostPoolName = $resourceMatch.Groups[1].Value, $resourceMatch.Groups[2].Value, $resourceMatch.Groups[3].Value
        Set-AzContext -SubscriptionId $subscriptionId | Out-Null

        $pool = Get-AzWvdHostPool -Name $hostPoolName -ResourceGroupName $resourceGroupName -SubscriptionId $subscriptionId
        if (-not $pool) { throw "Host pool not found: $id" }
        $hosts = @(Get-AzWvdSessionHost -HostPoolName $hostPoolName -ResourceGroupName $resourceGroupName | Where-Object { $null -ne $_ })
        $sessions = @(Get-AzWvdUserSession -HostPoolName $hostPoolName -ResourceGroupName $resourceGroupName | Where-Object { $null -ne $_ })
        $availableHosts = @($hosts | Where-Object { $_.Status -eq 'Available' -and $_.AllowNewSession }).Count
        $acceptingHosts = @($hosts | Where-Object { $_.AllowNewSession }).Count
        $activeSessions = @($sessions | Where-Object { $_.SessionState -eq 'Active' -and $_.UserPrincipalName }).Count
        $disconnectedSessions = @($sessions | Where-Object { $_.SessionState -eq 'Disconnected' -and $_.UserPrincipalName }).Count
        $unhealthyAssigned = @($hosts | Where-Object { $_.AssignedUser -and $_.Status -ne 'Available' -and $_.Status -notin $intentionallyOffStatuses })
        $unhealthyDetails = if ($unhealthyAssigned.Count -gt 0) {
            ($unhealthyAssigned | ForEach-Object { [pscustomobject]@{ SessionHost = $_.Name; AssignedUser = $_.AssignedUser; Status = "$($_.Status)" } } | ConvertTo-Json -Compress -Depth 3)
        } else { '' }

        $availableSessions = ($pool.MaxSessionLimit * $availableHosts) - $sessions.Count
        $load = if ($sessions.Count -gt 0 -and $pool.MaxSessionLimit -gt 0 -and $availableHosts -gt 0) {
            [math]::Round(($sessions.Count / ($pool.MaxSessionLimit * $availableHosts)) * 100, 2)
        } elseif ($sessions.Count -gt 0) { 100 } else { 0 }

        # The enabled flag is set on the plan's reference to this specific host pool.
        # Unknown means a lookup failed; the alert queries deliberately ignore it.
        $planName = ''
        $planState = 'None'
        $planLookupFailed = $false
        foreach ($planId in $planIds) {
            try {
                $planMatch = [regex]::Match($planId, '^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.DesktopVirtualization/scalingPlans/([^/]+)$', 'IgnoreCase')
                if (-not $planMatch.Success) { throw "Invalid scaling plan resource ID: $planId" }
                $planSubscriptionId, $planResourceGroupName, $requestedPlanName = $planMatch.Groups[1].Value, $planMatch.Groups[2].Value, $planMatch.Groups[3].Value
                Set-AzContext -SubscriptionId $planSubscriptionId | Out-Null
                $plan = Get-AzWvdScalingPlan -Name $requestedPlanName -ResourceGroupName $planResourceGroupName -SubscriptionId $planSubscriptionId -ErrorAction Stop
                $reference = $plan.HostPoolReference | Where-Object { "$($_.HostPoolArmPath)".Trim() -eq $id } | Select-Object -First 1
                if ($reference) {
                    $planName = $plan.Name
                    $planState = if ($reference.ScalingPlanEnabled) { 'Enabled' } else { 'Disabled' }
                    break
                }
            } catch {
                $planLookupFailed = $true
                Write-Warning "Scaling plan lookup failed for $planId : $($_.Exception.Message)"
            }
        }
        # Unknown only when no plan matched and at least one lookup failed. A match found
        # in another plan is reliable even if an unrelated plan could not be read.
        if (-not $planName -and $planLookupFailed) { $planState = 'Unknown' }

        $fields = @(
            $hostPoolName, $resourceGroupName, $pool.HostPoolType, $pool.MaxSessionLimit,
            $hosts.Count, $sessions.Count, $disconnectedSessions, $activeSessions,
            $availableSessions, $load.ToString([cultureinfo]::InvariantCulture),
            $unhealthyAssigned.Count, $unhealthyDetails, $id, $planName, $planState
        )
        Write-Output ($fields -join '|')
    } catch {
        $failures += "$id : $($_.Exception.Message)"
        Write-Warning "Host pool collector failed for $id : $($_.Exception.Message)"
    }
}
if ($failures.Count -gt 0) {
    throw "Host pool collector failed for $($failures.Count) of $($ids.Count) host pool(s): $($failures -join '; ')"
}
