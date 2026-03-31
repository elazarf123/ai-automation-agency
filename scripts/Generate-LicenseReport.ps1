<#
.SYNOPSIS
    Generates a Microsoft 365 license utilisation report and returns the
    data as structured JSON for Make.com ingestion.

.DESCRIPTION
    Connects to Microsoft Graph, retrieves all subscribed SKUs, calculates
    assigned vs. available counts, estimates monthly costs, and identifies
    potential savings from unused licenses.

    The JSON response is designed to be stored in a Make.com Data Store
    and/or appended to a Google Sheets / Excel Online audit workbook.

.PARAMETER ReportMonth
    Month number (1–12) for the report period. Defaults to current month.

.PARAMETER ReportYear
    Year for the report period. Defaults to current year.

.PARAMETER CostOverride
    Hashtable of SKU → monthly cost per license for cost calculations.
    If not provided, well-known SKU costs are used as defaults.

.PARAMETER OutputFormat
    "JSON" for a JSON string, "Object" for a PSCustomObject. Default: JSON

.PARAMETER DemoMode
    Returns simulated license data without connecting to Microsoft Graph.

.EXAMPLE
    # Current month report
    .\Generate-LicenseReport.ps1

.EXAMPLE
    # Specific month with custom costs
    .\Generate-LicenseReport.ps1 -ReportMonth 7 -ReportYear 2025

.EXAMPLE
    # Demo mode
    .\Generate-LicenseReport.ps1 -DemoMode

.NOTES
    Author : AutomateIQ
    Version: 1.0.0
    Requires: Microsoft.Graph module (skipped in DemoMode)
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 12)]
    [int] $ReportMonth = (Get-Date).Month,

    [int] $ReportYear  = (Get-Date).Year,

    [hashtable] $CostOverride = @{},

    [ValidateSet("JSON", "Object")]
    [string] $OutputFormat = "JSON",

    [switch] $DemoMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Known SKU → friendly name and default per-seat cost (USD/month) ─
$SkuDefaults = @{
    ENTERPRISEPREMIUM        = @{ Name = "Microsoft 365 E3";              Cost = 36.00 }
    SPE_E5                   = @{ Name = "Microsoft 365 E5";              Cost = 57.00 }
    O365_BUSINESS_ESSENTIALS = @{ Name = "Microsoft 365 Business Basic";  Cost = 6.00  }
    O365_BUSINESS_PREMIUM    = @{ Name = "Microsoft 365 Business Premium";Cost = 22.00 }
    DESKLESSPACK             = @{ Name = "Microsoft 365 F3 (Frontline)";  Cost = 8.00  }
    EXCHANGESTANDARD         = @{ Name = "Exchange Online Plan 1";        Cost = 4.00  }
    SHAREPOINTSTANDARD       = @{ Name = "SharePoint Online Plan 1";      Cost = 5.00  }
}

function Write-ReportLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $(
        switch ($Level) { "ERROR" {"Red"} "SUCCESS" {"Green"} default {"Cyan"} }
    )
}

function Get-LicenseCost {
    param([string]$Sku)
    if ($CostOverride.ContainsKey($Sku)) { return $CostOverride[$Sku] }
    if ($SkuDefaults.ContainsKey($Sku))  { return $SkuDefaults[$Sku].Cost }
    return 0.00
}

function Get-LicenseName {
    param([string]$Sku)
    if ($SkuDefaults.ContainsKey($Sku)) { return $SkuDefaults[$Sku].Name }
    return $Sku
}

# ── Demo data ──────────────────────────────────────────────────────
function Get-DemoLicenseData {
    return @(
        [PSCustomObject]@{ SkuPartNumber="ENTERPRISEPREMIUM";        Total=250; Assigned=198 }
        [PSCustomObject]@{ SkuPartNumber="SPE_E5";                   Total=50;  Assigned=47  }
        [PSCustomObject]@{ SkuPartNumber="O365_BUSINESS_ESSENTIALS"; Total=100; Assigned=61  }
        [PSCustomObject]@{ SkuPartNumber="DESKLESSPACK";             Total=75;  Assigned=68  }
    )
}

# ── Live Graph query ───────────────────────────────────────────────
function Get-GraphLicenseData {
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop

    $tenantId     = $env:AZURE_TENANT_ID
    $clientId     = $env:AZURE_CLIENT_ID
    $clientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
    $credential   = New-Object System.Management.Automation.PSCredential($clientId, $clientSecret)

    Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -NoWelcome

    $skus = Get-MgSubscribedSku -All

    return $skus | ForEach-Object {
        [PSCustomObject]@{
            SkuPartNumber = $_.SkuPartNumber
            Total         = $_.PrepaidUnits.Enabled
            Assigned      = $_.ConsumedUnits
        }
    }
}

# ── Main ───────────────────────────────────────────────────────────
try {
    Write-ReportLog "Generating license report for $ReportYear-$('{0:D2}' -f $ReportMonth)"

    $rawData = if ($DemoMode) {
        Write-ReportLog "DEMO MODE — using simulated license data"
        Get-DemoLicenseData
    } else {
        Get-GraphLicenseData
    }

    $licenseDetails  = [System.Collections.Generic.List[hashtable]]::new()
    $totalMonthly    = 0.0
    $potentialSavings= 0.0

    foreach ($sku in $rawData) {
        $cost        = Get-LicenseCost -Sku $sku.SkuPartNumber
        $name        = Get-LicenseName -Sku $sku.SkuPartNumber
        $unused      = $sku.Total - $sku.Assigned
        $monthlySpend= $sku.Assigned * $cost
        $unusedCost  = $unused * $cost
        $utilPct     = if ($sku.Total -gt 0) { [Math]::Round(($sku.Assigned / $sku.Total) * 100, 1) } else { 0 }

        $totalMonthly    += $monthlySpend
        $potentialSavings+= $unusedCost

        $licenseDetails.Add(@{
            SkuPartNumber    = $sku.SkuPartNumber
            FriendlyName     = $name
            Total            = $sku.Total
            Assigned         = $sku.Assigned
            Unassigned       = $unused
            UtilisationPct   = $utilPct
            CostPerLicense   = $cost
            MonthlySpend     = [Math]::Round($monthlySpend, 2)
            UnusedMonthlyCost= [Math]::Round($unusedCost, 2)
        })
    }

    $report = @{
        status              = "success"
        report_date         = "$ReportYear-$('{0:D2}' -f $ReportMonth)-01"
        generated           = (Get-Date -Format "o")
        tenant              = $env:AZURE_TENANT_DOMAIN ?? "company.onmicrosoft.com"
        total_monthly_spend = [Math]::Round($totalMonthly, 2)
        potential_savings   = [Math]::Round($potentialSavings, 2)
        annual_savings      = [Math]::Round($potentialSavings * 12, 2)
        licenses            = $licenseDetails.ToArray()
    }

    Write-ReportLog "Report complete — spend: `$$([Math]::Round($totalMonthly,2))/mo, savings opportunity: `$$([Math]::Round($potentialSavings,2))/mo" -Level SUCCESS

    if ($OutputFormat -eq "Object") { return $report }
    return $report | ConvertTo-Json -Depth 10
}
catch {
    $err = @{
        status    = "error"
        message   = $_.Exception.Message
        timestamp = (Get-Date -Format "o")
    }
    Write-ReportLog "Report generation failed: $($_.Exception.Message)" -Level ERROR
    return $err | ConvertTo-Json
}
