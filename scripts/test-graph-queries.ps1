# ============================================================
# test-graph-queries.ps1
# Identity Governance Portal - Phase 1: Graph API Validation
# Author: Sly Severe | SlyCyberLab
# Description: Validates Microsoft Graph API connectivity and
#              returns identity data for schema planning.
# ============================================================

# Load credentials from .env file
$env = Get-Content ..\.env | ConvertFrom-StringData
$tenantId     = $env.TENANT_ID
$clientId     = $env.CLIENT_ID
$clientSecret = $env.CLIENT_SECRET

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

# --- Query 1: Users ---
Write-Host "`n[1/5] Fetching users..." -ForegroundColor Cyan
$users = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,accountEnabled,createdDateTime,userType&`$top=10" `
    -Headers $headers

$users.value | Select-Object displayName, userPrincipalName, accountEnabled, userType | Format-Table

# --- Query 2: Directory Roles ---
Write-Host "[2/5] Fetching directory roles..." -ForegroundColor Cyan
$roles = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/directoryRoles" `
    -Headers $headers

$roles.value | Select-Object displayName, id | Format-Table

# --- Query 3: Guest Users ---
Write-Host "[3/5] Fetching guest users..." -ForegroundColor Cyan
$guests = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,displayName,userPrincipalName,createdDateTime" `
    -Headers $headers

$guests.value | Select-Object displayName, userPrincipalName, createdDateTime | Format-Table

# --- Query 4: MFA Registration Details ---
Write-Host "[4/5] Fetching MFA registration details..." -ForegroundColor Cyan
$mfa = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/reports/credentialUserRegistrationDetails" `
    -Headers $headers

$mfa.value | Select-Object userPrincipalName, isMfaRegistered, isMfaCapable | Select-Object -First 10 | Format-Table

# --- Query 5: Sign-In Activity (requires Entra ID P1/P2) ---
Write-Host "[5/5] Fetching sign-in activity (beta endpoint)..." -ForegroundColor Cyan
$signIn = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/beta/users?`$select=id,displayName,userPrincipalName,signInActivity&`$top=5" `
    -Headers $headers

$signIn.value | ForEach-Object {
    [PSCustomObject]@{
        UPN        = $_.userPrincipalName
        LastSignIn = $_.signInActivity.lastSignInDateTime
    }
} | Format-Table

Write-Host "All queries complete." -ForegroundColor Green