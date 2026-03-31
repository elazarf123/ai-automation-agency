<#
.SYNOPSIS
    HTTP listener that receives Make.com webhooks and routes them to the
    appropriate automation script.

.DESCRIPTION
    Acts as the entry point for all Make.com → PowerShell integrations.
    Validates the shared secret, parses the JSON payload, dispatches to the
    correct child script, and returns a structured JSON response.

    Can be deployed as:
      - An Azure Function (recommended)
      - An AWS Lambda (PowerShell runtime)
      - A local HTTP listener (for development/on-premises)

.PARAMETER Port
    TCP port for the built-in HTTP listener. Default: 8080.
    Not used when running inside Azure Functions or AWS Lambda.

.PARAMETER SecretEnvVar
    Name of the environment variable holding the webhook shared secret.
    Default: WEBHOOK_SECRET

.EXAMPLE
    # Start local listener
    .\Invoke-AutomationWebhook.ps1 -Port 8080

.NOTES
    Author : AutomateIQ
    Version: 1.0.0
    Requires: PowerShell 7+
#>

[CmdletBinding()]
param(
    [int]    $Port          = 8080,
    [string] $SecretEnvVar  = "WEBHOOK_SECRET"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Script root (resolves both direct execution and dot-sourcing) ──
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }

# ── Logging helper ─────────────────────────────────────────────────
function Write-WebhookLog {
    param(
        [string] $Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string] $Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "ERROR"   { Write-Error   $line }
        "WARN"    { Write-Warning $line }
        "SUCCESS" { Write-Host    $line -ForegroundColor Green }
        default   { Write-Host    $line -ForegroundColor Cyan  }
    }

    # Append to log file
    $logDir = Join-Path $ScriptDir "..\logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    Add-Content -Path (Join-Path $logDir "webhook.log") -Value $line
}

# ── Response builder ───────────────────────────────────────────────
function New-JsonResponse {
    param(
        [ValidateSet("success","error","warning")]
        [string]    $Status,
        [string]    $Message,
        [hashtable] $Data = @{}
    )

    return @{
        status    = $Status
        message   = $Message
        data      = $Data
        timestamp = (Get-Date -Format "o")
    } | ConvertTo-Json -Depth 10
}

# ── Input validation ───────────────────────────────────────────────
function Test-WebhookPayload {
    param(
        [PSCustomObject] $Payload,
        [string[]]       $RequiredFields
    )

    $missing = $RequiredFields | Where-Object { [string]::IsNullOrWhiteSpace($Payload.$_) }

    if ($missing.Count -gt 0) {
        return @{ Valid = $false; Missing = $missing }
    }
    return @{ Valid = $true; Missing = @() }
}

# ── Request dispatcher ─────────────────────────────────────────────
function Invoke-WebhookAction {
    param([PSCustomObject] $Payload)

    switch ($Payload.action) {

        "NewUser" {
            Write-WebhookLog "Dispatching to New-UserProvisioning.ps1"
            & (Join-Path $ScriptDir "New-UserProvisioning.ps1") -Payload $Payload
        }

        "StaleCheck" {
            Write-WebhookLog "Dispatching to Get-StaleAccounts.ps1"
            $days = if ($Payload.daysInactive) { [int]$Payload.daysInactive } else { 90 }
            & (Join-Path $ScriptDir "Get-StaleAccounts.ps1") -DaysInactive $days
        }

        "LicenseAudit" {
            Write-WebhookLog "Dispatching to Generate-LicenseReport.ps1"
            & (Join-Path $ScriptDir "Generate-LicenseReport.ps1") -Payload $Payload
        }

        default {
            Write-WebhookLog "Unknown action: $($Payload.action)" -Level WARN
            return New-JsonResponse -Status "error" -Message "Unknown action: $($Payload.action)"
        }
    }
}

# ── HTTP listener (local / on-premises mode) ───────────────────────
function Start-WebhookListener {
    param([int] $ListenPort)

    $prefix = "http://+:$ListenPort/api/"
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($prefix)
    $listener.Start()

    Write-WebhookLog "Webhook listener started on $prefix" -Level SUCCESS
    Write-WebhookLog "Press Ctrl+C to stop"

    try {
        while ($true) {
            $context  = $listener.GetContext()
            $request  = $context.Request
            $response = $context.Response

            try {
                # Validate secret
                $incomingSecret = $request.Headers["X-Webhook-Secret"]
                $expectedSecret = [System.Environment]::GetEnvironmentVariable($SecretEnvVar)

                if (-not $expectedSecret) {
                    Write-WebhookLog "Environment variable '$SecretEnvVar' is not set — skipping secret check" -Level WARN
                } elseif ($incomingSecret -ne $expectedSecret) {
                    Write-WebhookLog "Unauthorised request from $($request.RemoteEndPoint)" -Level WARN
                    $response.StatusCode = 401
                    $body = New-JsonResponse -Status "error" -Message "Invalid webhook secret"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                    $response.ContentType   = "application/json"
                    $response.ContentLength64 = $bytes.Length
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $response.Close()
                    continue
                }

                # Parse body
                $reader  = [System.IO.StreamReader]::new($request.InputStream)
                $rawBody = $reader.ReadToEnd()
                $payload = $rawBody | ConvertFrom-Json

                Write-WebhookLog "Received action: $($payload.action) from $($request.RemoteEndPoint)"

                # Dispatch
                $result = Invoke-WebhookAction -Payload $payload

                $response.StatusCode = 200
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentType    = "application/json"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            catch {
                Write-WebhookLog "Error processing request: $_" -Level ERROR
                $response.StatusCode = 500
                $body  = New-JsonResponse -Status "error" -Message $_.Exception.Message
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $response.ContentType    = "application/json"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            finally {
                $response.Close()
            }
        }
    }
    finally {
        $listener.Stop()
        Write-WebhookLog "Listener stopped"
    }
}

# ── Azure Function entry point ─────────────────────────────────────
# When running as an Azure Function, $Request is injected by the runtime.
if ($null -ne (Get-Variable -Name Request -ErrorAction SilentlyContinue)) {

    using namespace System.Net

    $incomingSecret = $Request.Headers["X-Webhook-Secret"]
    $expectedSecret = $env:WEBHOOK_SECRET

    if ($expectedSecret -and ($incomingSecret -ne $expectedSecret)) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Unauthorized
            Body       = New-JsonResponse -Status "error" -Message "Invalid secret"
        })
        return
    }

    $payload = $Request.Body | ConvertFrom-Json
    $result  = Invoke-WebhookAction -Payload $payload

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $result
    })
}
else {
    # Run standalone HTTP listener
    Start-WebhookListener -ListenPort $Port
}
