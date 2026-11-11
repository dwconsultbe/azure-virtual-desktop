# Checks that src/alert-sets.bicep matches the alert rules in src/modules/alerts:
# - every alert ID used by a module is in the AlertRuleId type, and the other way round;
# - every ID in an alert set exists, and every alert ID is in at least one set.
$ErrorActionPreference = 'Stop'

$project = Split-Path $PSScriptRoot -Parent
$setsFile = Get-Content (Join-Path $project 'src/alert-sets.bicep') -Raw

$typeBlock = [regex]::Match($setsFile, '(?s)type AlertRuleId =(.*?)\r?\n\r?\n').Groups[1].Value
$typeIds = @([regex]::Matches($typeBlock, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })

$setIds = @{}
foreach ($m in [regex]::Matches($setsFile, "(?s)\nvar (\w+) = \[(.*?)\]")) {
    $setIds[$m.Groups[1].Value] = @([regex]::Matches($m.Groups[2].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
}

$moduleIds = @(Get-ChildItem (Join-Path $project 'src/modules/alerts') -Filter *.bicep | ForEach-Object {
    $text = Get-Content $_.FullName -Raw
    [regex]::Matches($text, "(?:alertId|\bid):\s*'([A-Za-z0-9]+)'") | ForEach-Object { $_.Groups[1].Value }
    [regex]::Matches($text, "contains\(enabledAlertRuleIds, '([^']+)'\)") | ForEach-Object { $_.Groups[1].Value }
} | Sort-Object -Unique)

$problems = @()
if ($typeIds.Count -lt 10) { $problems += "Could not read the AlertRuleId type ($($typeIds.Count) IDs found)." }
if ($setIds.Count -lt 5) { $problems += "Could not read the alert sets ($($setIds.Count) found)." }
$problems += $moduleIds | Where-Object { $_ -notin $typeIds } | ForEach-Object { "Alert ID '$_' is used in a module but missing from AlertRuleId." }
$problems += $typeIds | Where-Object { $_ -notin $moduleIds } | ForEach-Object { "AlertRuleId '$_' is not used by any alert module." }
foreach ($set in $setIds.Keys) {
    $problems += $setIds[$set] | Where-Object { $_ -notin $typeIds } | ForEach-Object { "Alert set '$set' contains unknown ID '$_'." }
}
$inASet = $setIds.Values | ForEach-Object { $_ }
$problems += $typeIds | Where-Object { $_ -notin $inASet } | ForEach-Object { "Alert ID '$_' is not in any alert set." }

if ($problems) { throw "Alert ID check failed:`n- $($problems -join "`n- ")" }
Write-Output "Alert ID check passed: $($typeIds.Count) alert IDs, $($setIds.Count) alert sets."
