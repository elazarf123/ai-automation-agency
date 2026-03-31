<#
.SYNOPSIS
    Detects Active Directory user accounts that have been inactive beyond
    a configurable threshold and returns them as structured JSON.

.DESCRIPTION
    Queries Active Directory for enabled user accounts whose LastLogonDate
    is older than $DaysInactive days. Excludes service accounts, admin accounts,
    and other specified OUs. Results are returned as JSON for consumption by
    Make.com or other orchestration tools.

.PARAMETER DaysInactive
    Number of days without a logon before an account is considered stale.
    Default: 90

.PARAMETER ExcludeOUs
    Array of OU path substrings to exclude from the scan.
    Default: "Service Accounts", "Admin Accounts", "Disabled Users"

.PARAMETER OutputFormat
    Output format. "JSON" returns a JSON string; "Object" returns a
    PSCustomObject array for pipeline use. Default: JSON

.PARAMETER DemoMode
    Returns simulated stale account data without querying AD.

.EXAMPLE
    # Return JSON for Make.com
    .\Get-StaleAccounts.ps1 -DaysInactive 90

.EXAMPLE
    # 60-day threshold, exclude additional OU
    .\Get-StaleAccounts.ps1 -DaysInactive 60 -ExcludeOUs "Service Accounts","Contractors"

.EXAMPLE
    # Demo mode (no AD required)
    .\Get-StaleAccounts.ps1 -DemoMode

.NOTES
    Author : AutomateIQ
    Version: 1.0.0
    Requires: ActiveDirectory RSAT module (skipped in DemoMode)
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 365)]
    [int]    $DaysInactive  = 90,

    [string[]] $ExcludeOUs  = @("Service Accounts", "Admin Accounts", "Disabled Users"),

    [ValidateSet("JSON", "Object")]
    [string] $OutputFormat  = "JSON",

    [switch] $DemoMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-ScanLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $(
        switch ($Level) { "ERROR" {"Red"} "SUCCESS" {"Green"} "WARN" {"Yellow"} default {"Cyan"} }
    )
}

# ── Demo data ──────────────────────────────────────────────────────
function Get-DemoStaleAccounts {
    param([int]$Threshold)

    return @(
        [PSCustomObject]@{ SamAccountName="jsmith";  DisplayName="John Smith";  Department="Sales";       LastLogonDate=[datetime]"2025-04-10"; DaysInactive=112; Manager="sales.mgr@company.com";   Enabled=$true  }
        [PSCustomObject]@{ SamAccountName="mwilson"; DisplayName="Mary Wilson"; Department="HR";          LastLogonDate=[datetime]"2025-03-22"; DaysInactive=131; Manager="hr.mgr@company.com";      Enabled=$true  }
        [PSCustomObject]@{ SamAccountName="tdavis";  DisplayName="Tom Davis";   Department="Finance";     LastLogonDate=[datetime]"2025-04-01"; DaysInactive=121; Manager="finance.mgr@company.com"; Enabled=$true  }
        [PSCustomObject]@{ SamAccountName="sgarcia"; DisplayName="Sara Garcia"; Department="Marketing";   LastLogonDate=[datetime]"2025-02-14"; DaysInactive=167; Manager="mkt.mgr@company.com";     Enabled=$true  }
        [PSCustomObject]@{ SamAccountName="bmiller"; DisplayName="Bob Miller";  Department="Engineering"; LastLogonDate=[datetime]"2025-05-05"; DaysInactive=87;  Manager="eng.mgr@company.com";     Enabled=$false }
    ) | Where-Object { $_.DaysInactive -ge $Threshold }
}

# ── Live AD query ──────────────────────────────────────────────────
function Get-LiveStaleAccounts {
    param([int]$Threshold, [string[]]$Exclude)

    Import-Module ActiveDirectory -ErrorAction Stop

    $cutoff = (Get-Date).AddDays(-$Threshold)

    Write-ScanLog "Querying AD for accounts inactive since $($cutoff.ToString('yyyy-MM-dd'))"

    $users = Get-ADUser -Filter {
        Enabled -eq $true -and LastLogonDate -lt $cutoff
    } -Properties LastLogonDate, Department, Manager, DistinguishedName |
        Where-Object {
            $dn = $_.DistinguishedName
            -not ($Exclude | Where-Object { $dn -like "*$_*" })
        }

    $results = foreach ($user in $users) {
        $managerUPN = ""
        if ($user.Manager) {
            try { $managerUPN = (Get-ADUser $user.Manager -Properties UserPrincipalName).UserPrincipalName }
            catch { $managerUPN = $user.Manager }
        }

        [PSCustomObject]@{
            SamAccountName = $user.SamAccountName
            DisplayName    = $user.Name
            Department     = $user.Department
            LastLogonDate  = $user.LastLogonDate
            DaysInactive   = [int]((Get-Date) - $user.LastLogonDate).TotalDays
            Manager        = $managerUPN
            Enabled        = $user.Enabled
        }
    }

    return $results
}

# ── Main ───────────────────────────────────────────────────────────
try {
    Write-ScanLog "Starting stale account scan (threshold: $DaysInactive days)"

    $accounts = if ($DemoMode) {
        Write-ScanLog "DEMO MODE — returning simulated data"
        Get-DemoStaleAccounts -Threshold $DaysInactive
    } else {
        Get-LiveStaleAccounts -Threshold $DaysInactive -Exclude $ExcludeOUs
    }

    Write-ScanLog "Scan complete — found $($accounts.Count) stale account(s)" -Level SUCCESS

    if ($OutputFormat -eq "Object") {
        return $accounts
    }

    # Build JSON response
    $response = @{
        status        = "success"
        generated     = (Get-Date -Format "o")
        threshold_days = $DaysInactive
        total_stale   = $accounts.Count
        accounts      = @(
            $accounts | ForEach-Object {
                @{
                    SamAccountName = $_.SamAccountName
                    DisplayName    = $_.DisplayName
                    Department     = $_.Department
                    LastLogonDate  = $_.LastLogonDate.ToString("o")
                    DaysInactive   = $_.DaysInactive
                    Manager        = $_.Manager
                    Enabled        = $_.Enabled
                }
            }
        )
    }

    return $response | ConvertTo-Json -Depth 10
}
catch {
    $err = @{
        status    = "error"
        message   = $_.Exception.Message
        timestamp = (Get-Date -Format "o")
    }
    Write-ScanLog "Scan failed: $($_.Exception.Message)" -Level ERROR
    return $err | ConvertTo-Json
}
