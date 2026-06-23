# ============================================================
# Compare-IdentitySnapshots.ps1
# Identity Governance Portal - Phase 3: Drift Detection Engine
# Author: Sly Severe | SlyCyberLab
# Description: Compares two weekly identity snapshots and
#              outputs governance drift and delta report.
# ============================================================

# --- Load Snapshots ---
$snapshotsPath = "..\snapshots\sample"

$snapshotFiles = Get-ChildItem -Path $snapshotsPath -Filter "identity-snapshot-*.json" |
    Sort-Object Name -Descending

if ($snapshotFiles.Count -lt 2) {
    Write-Host "Need at least 2 snapshots to compare. Run Get-IdentitySnapshot.ps1 first." -ForegroundColor Red
    exit
}

$currentFile  = $snapshotFiles[0]
$previousFile = $snapshotFiles[1]

Write-Host "`nComparing snapshots:" -ForegroundColor Cyan
Write-Host "  Current:  $($currentFile.Name)"
Write-Host "  Previous: $($previousFile.Name)"

$current  = Get-Content $currentFile.FullName  | ConvertFrom-Json
$previous = Get-Content $previousFile.FullName | ConvertFrom-Json

# --- User Delta ---
$currentUPNs  = $current.users  | Select-Object -ExpandProperty userPrincipalName
$previousUPNs = $previous.users | Select-Object -ExpandProperty userPrincipalName

$newUsers     = $currentUPNs  | Where-Object { $_ -notin $previousUPNs }
$removedUsers = $previousUPNs | Where-Object { $_ -notin $currentUPNs }

# --- Disabled Account Delta ---
$currentDisabled  = $current.users  | Where-Object { $_.accountEnabled -eq $false } |
    Select-Object -ExpandProperty userPrincipalName
$previousDisabled = $previous.users | Where-Object { $_.accountEnabled -eq $false } |
    Select-Object -ExpandProperty userPrincipalName

$newlyDisabled  = $currentDisabled  | Where-Object { $_ -notin $previousDisabled }
$reEnabledUsers = $previousDisabled | Where-Object { $_ -notin $currentDisabled }

# --- Guest Delta ---
$currentGuests  = $current.guestUsers  | Select-Object -ExpandProperty userPrincipalName
$previousGuests = $previous.guestUsers | Select-Object -ExpandProperty userPrincipalName

$newGuests     = $currentGuests  | Where-Object { $_ -notin $previousGuests }
$removedGuests = $previousGuests | Where-Object { $_ -notin $currentGuests }

# --- Privileged Role Delta ---
$currentPriv  = $current.directoryRoles  | ForEach-Object {
    $role = $_.roleName
    $_.members | ForEach-Object { "$role`: $($_.userPrincipalName)" }
}
$previousPriv = $previous.directoryRoles | ForEach-Object {
    $role = $_.roleName
    $_.members | ForEach-Object { "$role`: $($_.userPrincipalName)" }
}

$newPrivileged     = $currentPriv  | Where-Object { $_ -notin $previousPriv }
$removedPrivileged = $previousPriv | Where-Object { $_ -notin $currentPriv }

# --- Governance Score Delta ---
$scoreDelta = $current.summary.governanceScore - $previous.summary.governanceScore

# --- Build Delta Report ---
$deltaReport = @{
    reportMetadata = @{
        generatedAt      = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        currentSnapshot  = $currentFile.Name
        previousSnapshot = $previousFile.Name
    }
    summaryDelta = @{
        totalUsers      = $current.summary.totalUsers      - $previous.summary.totalUsers
        activeUsers     = $current.summary.activeUsers     - $previous.summary.activeUsers
        disabledUsers   = $current.summary.disabledUsers   - $previous.summary.disabledUsers
        guestUsers      = $current.summary.guestUsers      - $previous.summary.guestUsers
        privilegedUsers = $current.summary.privilegedUsers - $previous.summary.privilegedUsers
        governanceScore = $scoreDelta
    }
    userDelta = @{
        newUsers       = @($newUsers)
        removedUsers   = @($removedUsers)
        newlyDisabled  = @($newlyDisabled)
        reEnabledUsers = @($reEnabledUsers)
    }
    guestDelta = @{
        newGuests     = @($newGuests)
        removedGuests = @($removedGuests)
    }
    privilegedAccessDelta = @{
        newPrivilegedAssignments     = @($newPrivileged)
        removedPrivilegedAssignments = @($removedPrivileged)
    }
    driftObservations = @()
}

# --- Generate Drift Observations ---
if ($newPrivileged.Count -gt 0) {
    $deltaReport.driftObservations += @{
        severity = "high"
        code     = "NEW_PRIVILEGED_ASSIGNMENT"
        message  = "$($newPrivileged.Count) new privileged role assignment(s) detected since last scan."
        details  = @($newPrivileged)
    }
}

if ($newlyDisabled.Count -gt 0) {
    $deltaReport.driftObservations += @{
        severity = "medium"
        code     = "ACCOUNTS_NEWLY_DISABLED"
        message  = "$($newlyDisabled.Count) account(s) newly disabled since last scan."
        details  = @($newlyDisabled)
    }
}

if ($newGuests.Count -gt 0) {
    $deltaReport.driftObservations += @{
        severity = "medium"
        code     = "NEW_GUEST_ACCOUNTS"
        message  = "$($newGuests.Count) new guest account(s) added since last scan."
        details  = @($newGuests)
    }
}

if ($newUsers.Count -gt 0) {
    $deltaReport.driftObservations += @{
        severity = "info"
        code     = "NEW_USERS_ADDED"
        message  = "$($newUsers.Count) new user(s) added since last scan."
        details  = @($newUsers)
    }
}

if ($scoreDelta -lt 0) {
    $deltaReport.driftObservations += @{
        severity = "medium"
        code     = "GOVERNANCE_SCORE_DECREASED"
        message  = "Governance score decreased by $([Math]::Abs($scoreDelta)) points since last scan."
    }
} elseif ($scoreDelta -gt 0) {
    $deltaReport.driftObservations += @{
        severity = "info"
        code     = "GOVERNANCE_SCORE_IMPROVED"
        message  = "Governance score improved by $scoreDelta points since last scan."
    }
}

if ($deltaReport.driftObservations.Count -eq 0) {
    $deltaReport.driftObservations += @{
        severity = "info"
        code     = "NO_DRIFT_DETECTED"
        message  = "No significant identity drift detected since last scan."
    }
}

# --- Output Delta Report to File ---
$outputPath = "..\snapshots\sample\drift-report-$($current.snapshotMetadata.snapshotDate).json"
$deltaReport | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding utf8

# --- Print Summary to Terminal ---
Write-Host "`n====== DRIFT REPORT ======" -ForegroundColor Yellow
Write-Host "Period: $($previous.snapshotMetadata.snapshotDate) -> $($current.snapshotMetadata.snapshotDate)"
Write-Host ""
Write-Host "Summary Delta:"

$totalSign    = if ($deltaReport.summaryDelta.totalUsers    -gt 0) { "+" } else { "" }
$disabledSign = if ($deltaReport.summaryDelta.disabledUsers -gt 0) { "+" } else { "" }
$guestSign    = if ($deltaReport.summaryDelta.guestUsers    -gt 0) { "+" } else { "" }
$scoreSign    = if ($scoreDelta                             -gt 0) { "+" } else { "" }

Write-Host "  Total Users:      $totalSign$($deltaReport.summaryDelta.totalUsers)"
Write-Host "  Disabled Users:   $disabledSign$($deltaReport.summaryDelta.disabledUsers)"
Write-Host "  Guest Users:      $guestSign$($deltaReport.summaryDelta.guestUsers)"
Write-Host "  Governance Score: $scoreSign$scoreDelta"
Write-Host ""
Write-Host "Drift Observations:"

foreach ($obs in $deltaReport.driftObservations) {
    $color = switch ($obs.severity) {
        "high"   { "Red" }
        "medium" { "Yellow" }
        "info"   { "Cyan" }
        default  { "White" }
    }
    Write-Host "  [$($obs.severity.ToUpper())] $($obs.message)" -ForegroundColor $color
}

Write-Host ""
Write-Host "Delta report saved to: $outputPath" -ForegroundColor Green
Write-Host "Done." -ForegroundColor Green