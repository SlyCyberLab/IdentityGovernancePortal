# ============================================================
# Get-IdentitySnapshot.ps1
# Identity Governance Portal - Phase 2: Snapshot Collector
# Author: Sly Severe | SlyCyberLab
# Description: Collects identity data from Microsoft Graph
#              and outputs a versioned JSON snapshot file.
# ============================================================

# Load credentials from .env file
$envVars = Get-Content ..\.env | ConvertFrom-StringData
$tenantId     = $envVars.TENANT_ID
$clientId     = $envVars.CLIENT_ID
$clientSecret = $envVars.CLIENT_SECRET

# --- Get Access Token ---
$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    scope         = "https://graph.microsoft.com/.default"
}

$tokenResponse = Invoke-RestMethod `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -Method POST `
    -Body $body

$token   = $tokenResponse.access_token
$headers = @{ Authorization = "Bearer $token" }

Write-Host "`nToken acquired successfully." -ForegroundColor Green

# --- Collect Users ---
Write-Host "Collecting users..." -ForegroundColor Cyan
$usersResponse = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,accountEnabled,createdDateTime,userType,department,assignedLicenses&`$top=999" `
    -Headers $headers

$allUsers   = $usersResponse.value
$activeUsers   = $allUsers | Where-Object { $_.accountEnabled -eq $true -and $_.userType -eq "Member" }
$disabledUsers = $allUsers | Where-Object { $_.accountEnabled -eq $false }
$guestUsers    = $allUsers | Where-Object { $_.userType -eq "Guest" }

Write-Host "  Total users: $($allUsers.Count)"
Write-Host "  Active: $($activeUsers.Count) | Disabled: $($disabledUsers.Count) | Guests: $($guestUsers.Count)"

# --- Collect Directory Roles and Members ---
Write-Host "Collecting directory roles..." -ForegroundColor Cyan
$rolesResponse = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/directoryRoles" `
    -Headers $headers

$directoryRoles = @()
$privilegedUsers = @()

foreach ($role in $rolesResponse.value) {
    $membersResponse = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/directoryRoles/$($role.id)/members?`$select=id,displayName,userPrincipalName" `
        -Headers $headers

    $members = $membersResponse.value | ForEach-Object {
        @{
            id                = $_.id
            displayName       = $_.displayName
            userPrincipalName = $_.userPrincipalName
        }
    }

    $directoryRoles += @{
        roleId   = $role.id
        roleName = $role.displayName
        members  = $members
    }

    $privilegedUsers += $membersResponse.value
}

$uniquePrivilegedCount = ($privilegedUsers | Select-Object -ExpandProperty id -Unique).Count
Write-Host "  Privileged users: $uniquePrivilegedCount"

# --- Calculate Governance Score ---
$score = 100

if ($disabledUsers.Count -gt 0)      { $score -= 10 }
if ($guestUsers.Count -gt 5)         { $score -= 10 }
if ($uniquePrivilegedCount -gt 2)    { $score -= 20 }

$disabledWithLicense = ($disabledUsers | Where-Object { $_.assignedLicenses.Count -gt 0 }).Count
if ($disabledWithLicense -gt 0)      { $score -= $disabledWithLicense * 10 }

if ($score -lt 0)                    { $score = 0 }

Write-Host "  Governance score: $score" -ForegroundColor Yellow

# --- Generate Governance Observations ---
$observations = @()

if ($disabledUsers.Count -gt 0) {
    $observations += @{
        severity     = "medium"
        code         = "DISABLED_USERS_EXIST"
        message      = "$($disabledUsers.Count) disabled user account(s) detected."
        affectedUsers = @($disabledUsers | Select-Object -ExpandProperty userPrincipalName)
    }
}

if ($disabledWithLicense -gt 0) {
    $observations += @{
        severity     = "high"
        code         = "DISABLED_WITH_LICENSE"
        message      = "$disabledWithLicense disabled user(s) still have active licenses."
        affectedUsers = @($disabledUsers | Where-Object { $_.assignedLicenses.Count -gt 0 } | Select-Object -ExpandProperty userPrincipalName)
    }
}

if ($guestUsers.Count -eq 0) {
    $observations += @{
        severity = "info"
        code     = "NO_GUEST_USERS"
        message  = "No guest users detected in tenant."
    }
} elseif ($guestUsers.Count -gt 5) {
    $observations += @{
        severity = "medium"
        code     = "HIGH_GUEST_COUNT"
        message  = "$($guestUsers.Count) guest users detected. Review for necessity."
    }
}

if ($uniquePrivilegedCount -gt 2) {
    $observations += @{
        severity = "high"
        code     = "HIGH_PRIVILEGED_USER_COUNT"
        message  = "$uniquePrivilegedCount privileged users detected. Review for least privilege."
    }
}

# --- Build Snapshot Object ---
$snapshotDate = Get-Date -Format "yyyy-MM-dd"

$snapshot = @{
    snapshotMetadata = @{
        snapshotDate    = $snapshotDate
        snapshotVersion = "1.1"
        tenantId        = $tenantId
        tenantDomain    = "slytech.us"
        collectedBy     = "IdentityGovernancePortal"
    }
    summary = @{
        totalUsers       = $allUsers.Count
        activeUsers      = $activeUsers.Count
        disabledUsers    = $disabledUsers.Count
        guestUsers       = $guestUsers.Count
        privilegedUsers  = $uniquePrivilegedCount
        governanceScore  = $score
    }
    users          = @($allUsers | ForEach-Object {
        @{
            id                = $_.id
            displayName       = $_.displayName
            userPrincipalName = $_.userPrincipalName
            accountEnabled    = $_.accountEnabled
            userType          = $_.userType
            createdDateTime   = $_.createdDateTime
            department        = $_.department
            hasLicense        = $_.assignedLicenses.Count -gt 0
        }
    })
    guestUsers     = @($guestUsers | ForEach-Object {
        @{
            id                = $_.id
            displayName       = $_.displayName
            userPrincipalName = $_.userPrincipalName
            createdDateTime   = $_.createdDateTime
        }
    })
    directoryRoles          = $directoryRoles
    governanceObservations  = $observations
}

# --- Output JSON to snapshots/sample folder ---
$outputPath = "..\snapshots\sample\identity-snapshot-$snapshotDate.json"
$snapshot | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding utf8

Write-Host "`nSnapshot saved to: $outputPath" -ForegroundColor Green
Write-Host "Done." -ForegroundColor Green