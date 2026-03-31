# PowerShell API Integration Guide

Best practices and patterns for building PowerShell scripts that integrate with Make.com webhooks, REST APIs, and enterprise directory services.

---

## Architecture Overview

```
Make.com Webhook / HTTP Module
        ↓  HTTPS POST (JSON)
PowerShell HTTP Listener
  ├── Azure Function (recommended for cloud)
  ├── AWS Lambda (PowerShell runtime)
  └── IIS / NSSM (on-premises)
        ↓  Parses & validates payload
Business Logic Scripts
  ├── New-UserProvisioning.ps1
  ├── Get-StaleAccounts.ps1
  └── Generate-LicenseReport.ps1
        ↓  Returns JSON response
Make.com ← HTTP response → Data Store / Email
```

---

## Part 1: Hosting PowerShell as an HTTP Endpoint

### Option A — Azure Functions (Recommended)

Azure Functions provides a fully managed, serverless runtime for PowerShell with built-in HTTPS, scaling, and managed identity support.

```powershell
# Azure Function entry point (run.ps1)
using namespace System.Net

param($Request, $TriggerMetadata)

# Validate webhook secret
$secret = $Request.Headers["X-Webhook-Secret"]
if ($secret -ne $env:WEBHOOK_SECRET) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body       = @{ error = "Invalid secret" } | ConvertTo-Json
    })
    return
}

# Parse JSON payload
$payload = $Request.Body | ConvertFrom-Json

# Route to the correct script based on action
$result = switch ($payload.action) {
    "NewUser"      { & "$PSScriptRoot/../scripts/New-UserProvisioning.ps1" -Payload $payload }
    "StaleCheck"   { & "$PSScriptRoot/../scripts/Get-StaleAccounts.ps1"    -Payload $payload }
    "LicenseAudit" { & "$PSScriptRoot/../scripts/Generate-LicenseReport.ps1" -Payload $payload }
    default        { @{ error = "Unknown action: $($payload.action)" } }
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = $result | ConvertTo-Json -Depth 10
})
```

**Deploy steps:**
```bash
# Install Azure Functions Core Tools
npm install -g azure-functions-core-tools@4

# Create and deploy
func init MyAutomationAPI --worker-runtime powershell
func new --name Invoke-AutomationWebhook --template "HTTP trigger"
func azure functionapp publish <YOUR_FUNCTION_APP_NAME>
```

### Option B — Local / On-Premises with NSSM

For on-premises environments without Azure, use `Invoke-AutomationWebhook.ps1` with NSSM as a Windows service:

```powershell
# Install NSSM (Non-Sucking Service Manager) then:
nssm install AutomationWebhook pwsh.exe "-File C:\Automation\scripts\Invoke-AutomationWebhook.ps1"
nssm set AutomationWebhook AppStdout C:\Automation\logs\webhook.log
nssm set AutomationWebhook AppStderr C:\Automation\logs\webhook-error.log
nssm start AutomationWebhook
```

---

## Part 2: Parsing and Validating Incoming Webhooks

Always validate the incoming payload before executing any Active Directory or Microsoft 365 operations.

```powershell
function Invoke-WebhookValidation {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Payload,

        [Parameter(Mandatory)]
        [string[]]$RequiredFields
    )

    $errors = @()

    foreach ($field in $RequiredFields) {
        if ([string]::IsNullOrWhiteSpace($Payload[$field])) {
            $errors += "Missing required field: $field"
        }
    }

    if ($errors.Count -gt 0) {
        return @{
            valid  = $false
            errors = $errors
        }
    }

    return @{ valid = $true }
}

# Usage
$validation = Invoke-WebhookValidation -Payload $payload -RequiredFields @(
    "firstName", "lastName", "department", "startDate"
)

if (-not $validation.valid) {
    # Return 400 Bad Request
}
```

---

## Part 3: Active Directory Integration

### 3.1 Required Modules

```powershell
# Import required modules
Import-Module ActiveDirectory -ErrorAction Stop

# For Microsoft 365 (modern auth)
Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All"
```

### 3.2 Creating a New AD User

```powershell
function New-ADUserFromWebhook {
    param(
        [string]$FirstName,
        [string]$LastName,
        [string]$Department,
        [string]$Manager,
        [string]$OU = "OU=Users,DC=company,DC=local"
    )

    $samAccountName = ($FirstName[0] + $LastName).ToLower() -replace '[^a-z0-9]', ''
    $upn            = "$samAccountName@company.com"
    $displayName    = "$FirstName $LastName"
    $tempPassword   = ConvertTo-SecureString "Temp$(Get-Random -Minimum 1000 -Maximum 9999)!" -AsPlainText -Force

    $params = @{
        Name                  = $displayName
        GivenName             = $FirstName
        Surname               = $LastName
        SamAccountName        = $samAccountName
        UserPrincipalName     = $upn
        Department            = $Department
        Manager               = $Manager
        Path                  = $OU
        AccountPassword       = $tempPassword
        ChangePasswordAtLogon = $true
        Enabled               = $true
    }

    New-ADUser @params

    return @{
        samAccountName = $samAccountName
        upn            = $upn
        displayName    = $displayName
        status         = "created"
    }
}
```

### 3.3 Querying Stale Accounts

```powershell
function Get-StaleADAccounts {
    param(
        [int]$DaysInactive = 90
    )

    $cutoffDate = (Get-Date).AddDays(-$DaysInactive)

    $filter = {
        Enabled         -eq $true     -and
        LastLogonDate   -lt $cutoffDate -and
        DistinguishedName -notlike "*OU=Service Accounts*"
    }

    Get-ADUser -Filter $filter -Properties LastLogonDate, Department, Manager |
        Select-Object SamAccountName, Name, LastLogonDate, Department,
                      @{ N = "DaysInactive"; E = { ((Get-Date) - $_.LastLogonDate).Days } },
                      @{ N = "Manager";      E = { (Get-ADUser $_.Manager).UserPrincipalName } }
}
```

---

## Part 4: Microsoft 365 Integration via Microsoft Graph

### 4.1 App Registration (Service Principal)

1. Go to **Azure Portal** → **Azure Active Directory** → **App registrations** → **New registration**.
2. Name: `AutomationWebhook-SP`
3. Under **API permissions**, add:
   - `User.ReadWrite.All` (Application)
   - `Directory.ReadWrite.All` (Application)
4. Create a **Client secret** and note the value.

### 4.2 Connecting in PowerShell

```powershell
# Store credentials securely (never hardcode)
$tenantId     = $env:AZURE_TENANT_ID
$clientId     = $env:AZURE_CLIENT_ID
$clientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force

$credential = New-Object System.Management.Automation.PSCredential($clientId, $clientSecret)

Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential
```

### 4.3 Assigning an M365 License

```powershell
function Set-M365License {
    param(
        [string]$UserPrincipalName,
        [string]$SkuPartNumber = "ENTERPRISEPREMIUM"
    )

    $sku  = Get-MgSubscribedSku | Where-Object SkuPartNumber -eq $SkuPartNumber
    $body = @{
        addLicenses    = @(@{ skuId = $sku.SkuId })
        removeLicenses = @()
    }

    Set-MgUserLicense -UserId $UserPrincipalName -BodyParameter $body
}
```

---

## Part 5: Returning Structured JSON Responses

All scripts should return a consistent JSON structure so Make.com can reliably parse the response.

```powershell
# Standard response helper
function New-AutomationResponse {
    param(
        [ValidateSet("success", "error", "warning")]
        [string]$Status,

        [string]$Message,

        [hashtable]$Data = @{}
    )

    return @{
        status    = $Status
        message   = $Message
        data      = $Data
        timestamp = (Get-Date -Format "o")  # ISO 8601
    }
}

# Success example
$response = New-AutomationResponse -Status "success" -Message "User created" -Data @{
    samAccountName = "jdoe"
    upn            = "jdoe@company.com"
}

# Error example
$response = New-AutomationResponse -Status "error" -Message "User already exists" -Data @{
    conflictingUPN = "jdoe@company.com"
}

$response | ConvertTo-Json -Depth 5
```

---

## Part 6: Logging and Auditing

```powershell
function Write-AutomationLog {
    param(
        [string]$Action,
        [string]$Status,
        [string]$Details,
        [string]$LogPath = "C:\Automation\logs\automation.log"
    )

    $entry = [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Action    = $Action
        Status    = $Status
        Details   = $Details
        User      = $env:USERNAME
        Host      = $env:COMPUTERNAME
    }

    # Append to log file
    $entry | Export-Csv -Path $LogPath -Append -NoTypeInformation

    # Also write to Windows Event Log
    Write-EventLog -LogName Application -Source "AutomationWebhook" `
        -EventId 1000 -EntryType Information `
        -Message "$Action | $Status | $Details"
}
```

---

## Part 7: Security Best Practices

1. **Never hardcode credentials** — use environment variables or Azure Key Vault
2. **Validate all inputs** — sanitise strings before passing to AD cmdlets
3. **Use least-privilege service accounts** — grant only the permissions each script needs
4. **Enforce HTTPS** — reject HTTP connections at the IIS or Azure Functions level
5. **Rotate webhook secrets** regularly — treat them like passwords
6. **Log all actions** — maintain an audit trail for compliance
7. **Use `[ValidateSet]` and `[ValidatePattern]`** on all script parameters

```powershell
# Input validation example
function New-UserProvisioning {
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]{1,50}$')]
        [string]$FirstName,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z\-]{1,50}$')]
        [string]$LastName,

        [Parameter(Mandatory)]
        [ValidateSet("Engineering", "Sales", "Finance", "HR", "IT", "Marketing", "Operations")]
        [string]$Department
    )
    # ...
}
```

---

## Module Dependencies

| Module | Install Command | Purpose |
|--------|----------------|---------|
| `ActiveDirectory` | Built-in (RSAT) | AD user management |
| `Microsoft.Graph` | `Install-Module Microsoft.Graph` | M365 management |
| `PSRestClient` | See `/connectors/PSRestClient.psm1` | REST API calls |
| `SqlServer` | `Install-Module SqlServer` | Database logging |
| `Az.KeyVault` | `Install-Module Az.KeyVault` | Secret management |
