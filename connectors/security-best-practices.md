# Security Best Practices — Automation Webhooks & API Integration

A comprehensive guide to securing PowerShell + Make.com automation workflows in enterprise environments.

---

## 1. Credential Management

### Never Hardcode Secrets

```powershell
# ❌ Bad — never do this
$password = "P@ssw0rd123"
$apiKey   = "sk-ant-abc123xyz"

# ✅ Good — use environment variables
$password = $env:DB_PASSWORD
$apiKey   = $env:ANTHROPIC_API_KEY
```

### Azure Key Vault (Recommended for Production)

```powershell
# Read secret from Azure Key Vault at runtime
function Get-VaultSecret {
    param([string]$SecretName)

    Import-Module Az.KeyVault -ErrorAction Stop

    # Authenticate using Managed Identity (no credentials needed!)
    Connect-AzAccount -Identity -ErrorAction Stop

    $secret = Get-AzKeyVaultSecret -VaultName $env:KEY_VAULT_NAME `
                                   -Name $SecretName `
                                   -AsPlainText
    return $secret
}

# Usage
$webhookSecret = Get-VaultSecret -SecretName "WebhookSecret"
$dbPassword    = Get-VaultSecret -SecretName "DatabasePassword"
```

### Environment Variable Setup (Azure Functions)

```bash
# Set application settings in Azure Functions
az functionapp config appsettings set \
  --name MyFunctionApp \
  --resource-group MyResourceGroup \
  --settings \
    "WEBHOOK_SECRET=@Microsoft.KeyVault(SecretUri=https://myvault.vault.azure.net/secrets/WebhookSecret/)" \
    "AZURE_TENANT_ID=your-tenant-id" \
    "AZURE_CLIENT_ID=your-client-id"
```

---

## 2. Webhook Authentication

### Shared Secret Header Validation

```powershell
function Test-WebhookSecret {
    param(
        [string]$IncomingSecret,
        [string]$ExpectedSecret
    )

    # Use constant-time comparison to prevent timing attacks
    if ($IncomingSecret.Length -ne $ExpectedSecret.Length) { return $false }

    $result = 0
    for ($i = 0; $i -lt $IncomingSecret.Length; $i++) {
        $result = $result -bor ([int][char]$IncomingSecret[$i] -bxor [int][char]$ExpectedSecret[$i])
    }
    return $result -eq 0
}
```

### HMAC-SHA256 Signature Verification (Stronger)

For production workloads, use HMAC signatures instead of a bare shared secret:

```powershell
function Test-WebhookSignature {
    param(
        [string]$RequestBody,
        [string]$IncomingSignature,
        [string]$Secret
    )

    $hmac      = [System.Security.Cryptography.HMACSHA256]::new(
                     [System.Text.Encoding]::UTF8.GetBytes($Secret))
    $computed  = [Convert]::ToHexString(
                     $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($RequestBody)))
    $expected  = "sha256=$computed"

    return (Test-WebhookSecret -IncomingSecret $IncomingSignature -ExpectedSecret $expected)
}

# In Make.com, compute the signature and include it in the request header:
# Header: X-Hub-Signature-256: sha256=<hmac_hex>
```

---

## 3. Input Validation and Sanitisation

Always validate and sanitise all inputs before passing them to AD cmdlets or database queries:

```powershell
function Invoke-InputValidation {
    param(
        [Parameter(Mandatory)]
        [string]$FirstName,

        [Parameter(Mandatory)]
        [string]$LastName,

        [Parameter(Mandatory)]
        [string]$Department,

        [Parameter(Mandatory)]
        [string]$ManagerEmail
    )

    $errors = @()

    # Name validation — letters and hyphens only, 1–50 chars
    if ($FirstName -notmatch '^[A-Za-z]{1,50}$') {
        $errors += "Invalid FirstName: must be 1–50 letters only"
    }

    if ($LastName -notmatch '^[A-Za-z\-]{1,50}$') {
        $errors += "Invalid LastName: must be 1–50 letters and hyphens only"
    }

    # Email validation
    if ($ManagerEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        $errors += "Invalid ManagerEmail format"
    }

    # Allowlist validation for department
    $validDepartments = @("Engineering","Sales","Finance","HR","IT","Marketing","Operations")
    if ($Department -notin $validDepartments) {
        $errors += "Invalid Department: '$Department' is not in the approved list"
    }

    return @{
        Valid  = $errors.Count -eq 0
        Errors = $errors
    }
}
```

---

## 4. Least-Privilege Service Accounts

### Active Directory Service Account

Create a dedicated AD service account with minimum required permissions:

```powershell
# Create restricted service account
New-ADUser -Name "svc-automation" `
    -SamAccountName "svc-automation" `
    -UserPrincipalName "svc-automation@company.com" `
    -AccountPassword (ConvertTo-SecureString "$(New-Guid)" -AsPlainText -Force) `
    -PasswordNeverExpires $true `
    -Enabled $true `
    -Description "AutomateIQ automation service account — DO NOT DELETE"

# Grant Create User permission on specific OU only
$ou = "OU=Employees,DC=company,DC=local"
$acl = Get-Acl "AD:\$ou"
# ... add specific ACE for user creation
Set-Acl "AD:\$ou" $acl
```

### Microsoft Graph Application Permissions

Use the minimum required Graph API permissions:

| Script | Required Permission | Scope |
|--------|-------------------|-------|
| `New-UserProvisioning.ps1` | `User.ReadWrite.All` | Application |
| `New-UserProvisioning.ps1` | `Directory.ReadWrite.All` | Application |
| `Get-StaleAccounts.ps1` | `User.Read.All` | Application |
| `Generate-LicenseReport.ps1` | `Organization.Read.All` | Application |

---

## 5. HTTPS Enforcement

All endpoints must use HTTPS. Reject HTTP requests at the infrastructure level:

```powershell
# Azure Functions — enforce HTTPS in host.json
# host.json
{
  "version": "2.0",
  "extensions": {
    "http": {
      "routePrefix": "api",
      "maxConcurrentRequests": 10
    }
  }
}

# Also set in Azure portal: Function App → TLS/SSL settings → HTTPS Only = On
```

---

## 6. Logging and Audit Trails

Log every action with enough detail for forensic investigation:

```powershell
function Write-SecurityLog {
    param(
        [string]$EventType,   # e.g. "ACCOUNT_CREATED", "AUTH_FAILURE", "SCAN_COMPLETE"
        [string]$Actor,       # who triggered the action (webhook source IP or user)
        [string]$Target,      # the resource affected (e.g. username)
        [string]$Outcome,     # SUCCESS or FAILURE
        [string]$Details
    )

    $event = [PSCustomObject]@{
        Timestamp = (Get-Date -Format "o")
        EventType = $EventType
        Actor     = $Actor
        Target    = $Target
        Outcome   = $Outcome
        Details   = $Details
        Host      = $env:COMPUTERNAME
        ProcessId = $PID
    }

    # Write to structured log file (JSON Lines format — easy to ingest into SIEM)
    $event | ConvertTo-Json -Compress | Add-Content -Path "C:\Automation\logs\security.jsonl"

    # High-severity events → Windows Security Event Log
    if ($Outcome -eq "FAILURE") {
        Write-EventLog -LogName Security -Source "AutomateIQ" `
            -EventId 4625 -EntryType Warning `
            -Message "$EventType | $Actor → $Target | $Details"
    }
}
```

---

## 7. Secret Rotation Checklist

Rotate secrets on the following schedule:

| Secret | Rotation Frequency | Method |
|--------|-------------------|--------|
| Webhook shared secret | Every 90 days | Azure Key Vault rotation policy |
| Service account password | Every 180 days | AD fine-grained password policy |
| Azure App client secret | Every 12 months | Azure AD App registration |
| Database passwords | Every 90 days | Azure Key Vault + rotation function |
| SendGrid API key | Every 12 months | SendGrid dashboard |

---

## 8. Network Security

- **Restrict webhook endpoint access** to Make.com IP ranges: `https://www.make.com/en/help/app/webhooks`
- **Use Azure Private Endpoints** for database connections inside a VNet
- **Enable Azure DDoS Protection** on the Function App's App Service Plan
- **Configure IP allowlisting** in Azure Functions **Networking → Access Restrictions**

```json
// Example access restriction — allow Make.com + internal IPs only
{
  "ipSecurityRestrictions": [
    { "ipAddress": "185.189.40.0/22", "action": "Allow", "name": "MakeCom", "priority": 100 },
    { "ipAddress": "10.0.0.0/8",      "action": "Allow", "name": "Internal", "priority": 200 },
    { "ipAddress": "0.0.0.0/0",       "action": "Deny",  "name": "DenyAll",  "priority": 300 }
  ]
}
```
