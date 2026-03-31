<#
.SYNOPSIS
    Provisions a new user account in Active Directory and assigns a
    Microsoft 365 license via Microsoft Graph.

.DESCRIPTION
    Accepts a structured payload (from Make.com via Invoke-AutomationWebhook.ps1
    or directly from the command line) and performs the full new-hire
    provisioning sequence:
      1. Validates input
      2. Generates a unique SAM account name and UPN
      3. Creates the AD user
      4. Moves the user to the correct OU based on department
      5. Assigns the specified Microsoft 365 license
      6. Sends a provisioning confirmation record (returned as JSON)

.PARAMETER Payload
    PSCustomObject containing the webhook payload. Used when called from
    Invoke-AutomationWebhook.ps1.

.PARAMETER FirstName
    New employee first name. Used when calling the script directly.

.PARAMETER LastName
    New employee last name.

.PARAMETER Department
    Department for OU placement and AD attribute.

.PARAMETER ManagerEmail
    UPN of the employee's manager.

.PARAMETER StartDate
    ISO 8601 start date (e.g. "2025-08-01").

.PARAMETER License
    Microsoft 365 SKU part number (default: ENTERPRISEPREMIUM = M365 E3).

.PARAMETER DomainFQDN
    Active Directory domain FQDN. Defaults to USERDNSDOMAIN environment variable.

.PARAMETER OUBase
    Base OU path for new accounts. Department sub-OU is appended automatically.

.PARAMETER DemoMode
    When set, skips actual AD/M365 calls and returns simulated output.
    Useful for testing without a live AD environment.

.EXAMPLE
    # Called from Make.com webhook dispatcher
    .\New-UserProvisioning.ps1 -Payload $webhookPayload

    # Called directly
    .\New-UserProvisioning.ps1 -FirstName Jane -LastName Doe `
        -Department Engineering -ManagerEmail mgr@company.com `
        -StartDate 2025-08-01

.EXAMPLE
    # Demo mode (no AD required)
    .\New-UserProvisioning.ps1 -FirstName Test -LastName User `
        -Department IT -ManagerEmail admin@company.com `
        -StartDate 2025-08-01 -DemoMode

.NOTES
    Author : AutomateIQ
    Version: 1.0.0
    Requires: ActiveDirectory RSAT module, Microsoft.Graph module
              (both skipped in DemoMode)
#>

[CmdletBinding(DefaultParameterSetName = "Direct")]
param(
    # Webhook payload (used when dispatched from Invoke-AutomationWebhook.ps1)
    [Parameter(ParameterSetName = "Webhook", Mandatory)]
    [PSCustomObject] $Payload,

    # Direct parameters
    [Parameter(ParameterSetName = "Direct", Mandatory)]
    [ValidatePattern('^[A-Za-z]{1,50}$')]
    [string] $FirstName,

    [Parameter(ParameterSetName = "Direct", Mandatory)]
    [ValidatePattern('^[A-Za-z\-]{1,50}$')]
    [string] $LastName,

    [Parameter(ParameterSetName = "Direct", Mandatory)]
    [ValidateSet("Engineering","Sales","Finance","HR","IT","Marketing","Operations")]
    [string] $Department,

    [Parameter(ParameterSetName = "Direct", Mandatory)]
    [ValidatePattern('^[^@]+@[^@]+\.[^@]+$')]
    [string] $ManagerEmail,

    [Parameter(ParameterSetName = "Direct", Mandatory)]
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string] $StartDate,

    [Parameter(ParameterSetName = "Direct")]
    [string] $License = "ENTERPRISEPREMIUM",

    [string] $DomainFQDN = $env:USERDNSDOMAIN,

    [string] $OUBase = "OU=Employees,DC=company,DC=local",

    [switch] $DemoMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Flatten payload if dispatched from webhook ─────────────────────
if ($PSCmdlet.ParameterSetName -eq "Webhook") {
    $FirstName    = $Payload.firstName
    $LastName     = $Payload.lastName
    $Department   = $Payload.department
    $ManagerEmail = $Payload.managerEmail
    $StartDate    = $Payload.startDate
    $License      = if ($Payload.license) { $Payload.license } else { "ENTERPRISEPREMIUM" }
}

# ── Helpers ────────────────────────────────────────────────────────
function New-SAMAccountName {
    param([string]$First, [string]$Last)
    $base = ($First[0] + $Last).ToLower() -replace '[^a-z0-9]', ''
    $base = $base.Substring(0, [Math]::Min($base.Length, 20))

    if (-not $DemoMode) {
        # Check for conflicts in AD
        $counter = 0
        $candidate = $base
        while (Get-ADUser -Filter "SamAccountName -eq '$candidate'" -ErrorAction SilentlyContinue) {
            $counter++
            $candidate = "${base}${counter}"
        }
        return $candidate
    }
    return $base
}

function New-TemporaryPassword {
    $upper   = [char[]]"ABCDEFGHJKLMNPQRSTUVWXYZ"
    $lower   = [char[]]"abcdefghjkmnpqrstuvwxyz"
    $digits  = [char[]]"23456789"
    $special = [char[]]"!@#$%^&*"

    $pwd = @(
        $upper  | Get-Random -Count 2
        $lower  | Get-Random -Count 4
        $digits | Get-Random -Count 2
        $special| Get-Random -Count 1
    ) | Sort-Object { Get-Random } | Join-String

    return ConvertTo-SecureString $pwd -AsPlainText -Force
}

function Get-DepartmentOU {
    param([string]$Dept)
    return "OU=$Dept,$OUBase"
}

function Write-ProvisionLog {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) { "ERROR" {"Red"} "SUCCESS" {"Green"} "WARN" {"Yellow"} default {"Cyan"} }
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
}

# ── Main provisioning logic ────────────────────────────────────────
try {
    Write-ProvisionLog "Starting provisioning for $FirstName $LastName ($Department)"

    $samAccountName = New-SAMAccountName -First $FirstName -Last $LastName
    $domain         = if ($DomainFQDN) { $DomainFQDN } else { "company.com" }
    $upn            = "$samAccountName@$domain"
    $displayName    = "$FirstName $LastName"
    $targetOU       = Get-DepartmentOU -Dept $Department
    $tempPassword   = New-TemporaryPassword

    Write-ProvisionLog "Generated UPN: $upn"

    if ($DemoMode) {
        Write-ProvisionLog "DEMO MODE — Skipping actual AD/M365 calls" -Level "INFO"
        Start-Sleep -Milliseconds 300  # simulate async work
    }
    else {
        # ── Active Directory ──
        Import-Module ActiveDirectory -ErrorAction Stop

        $adParams = @{
            Name                  = $displayName
            GivenName             = $FirstName
            Surname               = $LastName
            SamAccountName        = $samAccountName
            UserPrincipalName     = $upn
            Department            = $Department
            Manager               = (Get-ADUser -Filter "UserPrincipalName -eq '$ManagerEmail'").DistinguishedName
            Path                  = $targetOU
            AccountPassword       = $tempPassword
            ChangePasswordAtLogon = $true
            Enabled               = $true
            Description           = "Provisioned by AutomateIQ on $(Get-Date -Format 'yyyy-MM-dd')"
        }

        New-ADUser @adParams
        Write-ProvisionLog "AD account created: $upn" -Level SUCCESS

        # ── Microsoft 365 license ──
        Import-Module Microsoft.Graph.Users.Actions -ErrorAction Stop

        $tenantId     = $env:AZURE_TENANT_ID
        $clientId     = $env:AZURE_CLIENT_ID
        $clientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
        $credential   = New-Object System.Management.Automation.PSCredential($clientId, $clientSecret)
        Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -NoWelcome

        $sku = Get-MgSubscribedSku | Where-Object SkuPartNumber -eq $License | Select-Object -First 1
        if (-not $sku) { throw "License SKU '$License' not found in tenant" }

        $licenseBody = @{
            addLicenses    = @(@{ skuId = $sku.SkuId })
            removeLicenses = @()
        }
        Set-MgUserLicense -UserId $upn -BodyParameter $licenseBody
        Write-ProvisionLog "M365 license assigned: $License" -Level SUCCESS
    }

    # ── Return structured response ─────────────────────────────────
    $result = @{
        status         = "success"
        message        = "User provisioned successfully"
        timestamp      = (Get-Date -Format "o")
        data = @{
            samAccountName = $samAccountName
            upn            = $upn
            displayName    = $displayName
            department     = $Department
            managerEmail   = $ManagerEmail
            startDate      = $StartDate
            license        = $License
            targetOU       = $targetOU
            demoMode       = [bool]$DemoMode
        }
    }

    Write-ProvisionLog "Provisioning complete for $upn" -Level SUCCESS
    return $result | ConvertTo-Json -Depth 5
}
catch {
    $errorMsg = $_.Exception.Message
    Write-ProvisionLog "Provisioning failed: $errorMsg" -Level ERROR

    $result = @{
        status    = "error"
        message   = "Provisioning failed: $errorMsg"
        timestamp = (Get-Date -Format "o")
        data      = @{
            firstName = $FirstName
            lastName  = $LastName
        }
    }

    return $result | ConvertTo-Json -Depth 5
}
