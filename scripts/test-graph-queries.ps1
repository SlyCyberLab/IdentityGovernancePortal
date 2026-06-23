# ============================================================
# test-graph-queries.ps1
# Identity Governance Portal - Phase 1: Graph API Validation
# Author: Sly Severe | SlyCyberLab
# Description: Validates Microsoft Graph API connectivity and
#              returns identity data for schema planning.
# Note: MFA and sign-in activity endpoints require Entra P1/P2
#       and are excluded from MVP scope.
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

# --- Query 1: All Users ---
Write-Host "`n[1/3] Fetching users..." -ForegroundColor Cyan
$users = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,accountEnabled,createdDateTime,userType&`$top=20" `
    -Headers $headers

$users.value | Select-Object displayName, userPrincipalName, accountEnabled, userType | Format-Table

# --- Query 2: Directory Roles ---
Write-Host "[2/3] Fetching directory roles..." -ForegroundColor Cyan
$roles = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/directoryRoles" `
    -Headers $headers

$roles.value | Select-Object displayName, id | Format-Table

# --- Query 3: Guest Users ---
Write-Host "[3/3] Fetching guest users..." -ForegroundColor Cyan
$guests = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,displayName,userPrincipalName,createdDateTime" `
    -Headers $headers

if ($guests.value.Count -eq 0) {
    Write-Host "No guest users found." -ForegroundColor Yellow
} else {
    $guests.value | Select-Object displayName, userPrincipalName, createdDateTime | Format-Table
}

Write-Host "`nAll queries complete." -ForegroundColor Green