#Requires -Version 7.0
<#
.SYNOPSIS
    Reusable PowerShell module for making authenticated REST API calls.

.DESCRIPTION
    PSRestClient provides a clean, consistent interface for HTTP operations
    with support for common authentication schemes (Bearer token, API key,
    Basic auth, Azure Managed Identity), automatic retry with exponential
    backoff, response parsing, and structured error handling.

.NOTES
    Author  : AutomateIQ
    Version : 1.0.0
    Module  : PSRestClient
    Export  : Invoke-RestGet, Invoke-RestPost, Invoke-RestPut,
              Invoke-RestDelete, Get-BearerToken, Get-ManagedIdentityToken
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Private helpers ────────────────────────────────────────────────

function ConvertTo-Base64 {
    param([string]$Value)
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Value))
}

function Get-AuthHeader {
    param(
        [ValidateSet("Bearer","ApiKey","Basic","None")]
        [string]$AuthType = "None",

        [string]$Token,
        [string]$ApiKeyHeader = "X-API-Key",
        [string]$Username,
        [string]$Password
    )

    switch ($AuthType) {
        "Bearer" { return @{ Authorization = "Bearer $Token" } }
        "ApiKey" { return @{ $ApiKeyHeader = $Token } }
        "Basic"  {
            $encoded = ConvertTo-Base64 "${Username}:${Password}"
            return @{ Authorization = "Basic $encoded" }
        }
        "None"   { return @{} }
    }
}

function Invoke-RetriableRequest {
    param(
        [hashtable]$IrmParams,
        [int]$MaxRetries     = 3,
        [int]$RetryDelayBase = 2   # seconds; doubles each retry
    )

    $attempt = 0
    while ($true) {
        try {
            $attempt++
            return Invoke-RestMethod @IrmParams
        }
        catch {
            $statusCode = $_.Exception.Response?.StatusCode.value__

            # Don't retry 4xx client errors (except 429 Too Many Requests)
            $isClientError = $statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -ne 429
            if ($isClientError -or $attempt -ge $MaxRetries) {
                throw
            }

            $delay = [Math]::Pow($RetryDelayBase, $attempt)
            Write-Verbose "Request failed (attempt $attempt/$MaxRetries). Retrying in ${delay}s…"
            Start-Sleep -Seconds $delay
        }
    }
}

# ── Public functions ───────────────────────────────────────────────

<#
.SYNOPSIS  Sends a GET request to a REST endpoint.
.EXAMPLE   Invoke-RestGet -Uri "https://api.example.com/users" -Token $jwt
#>
function Invoke-RestGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]    $Uri,
        [ValidateSet("Bearer","ApiKey","Basic","None")]
        [string]    $AuthType     = "None",
        [string]    $Token,
        [string]    $ApiKeyHeader = "X-API-Key",
        [string]    $Username,
        [string]    $Password,
        [hashtable] $ExtraHeaders = @{},
        [int]       $MaxRetries   = 3,
        [string]    $WebhookSecret
    )

    $headers = Get-AuthHeader -AuthType $AuthType -Token $Token `
                              -ApiKeyHeader $ApiKeyHeader `
                              -Username $Username -Password $Password
    if ($WebhookSecret) { $headers["X-Webhook-Secret"] = $WebhookSecret }
    $ExtraHeaders.GetEnumerator() | ForEach-Object { $headers[$_.Key] = $_.Value }

    $params = @{
        Uri             = $Uri
        Method          = "GET"
        Headers         = $headers
        ContentType     = "application/json"
        UseBasicParsing = $true
    }

    return Invoke-RetriableRequest -IrmParams $params -MaxRetries $MaxRetries
}

<#
.SYNOPSIS  Sends a POST request with a JSON body.
.EXAMPLE   Invoke-RestPost -Uri $webhookUrl -Body @{action="NewUser"} -Token $jwt
#>
function Invoke-RestPost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]    $Uri,
        [Parameter(Mandatory)] [object]    $Body,
        [ValidateSet("Bearer","ApiKey","Basic","None")]
        [string]    $AuthType     = "None",
        [string]    $Token,
        [string]    $ApiKeyHeader = "X-API-Key",
        [string]    $Username,
        [string]    $Password,
        [hashtable] $ExtraHeaders = @{},
        [int]       $MaxRetries   = 3,
        [string]    $WebhookSecret
    )

    $headers = Get-AuthHeader -AuthType $AuthType -Token $Token `
                              -ApiKeyHeader $ApiKeyHeader `
                              -Username $Username -Password $Password
    if ($WebhookSecret) { $headers["X-Webhook-Secret"] = $WebhookSecret }
    $ExtraHeaders.GetEnumerator() | ForEach-Object { $headers[$_.Key] = $_.Value }

    $jsonBody = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 }

    $params = @{
        Uri             = $Uri
        Method          = "POST"
        Headers         = $headers
        Body            = $jsonBody
        ContentType     = "application/json"
        UseBasicParsing = $true
    }

    return Invoke-RetriableRequest -IrmParams $params -MaxRetries $MaxRetries
}

<#
.SYNOPSIS  Sends a PUT request with a JSON body.
#>
function Invoke-RestPut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]    $Uri,
        [Parameter(Mandatory)] [object]    $Body,
        [ValidateSet("Bearer","ApiKey","Basic","None")]
        [string]    $AuthType     = "None",
        [string]    $Token,
        [string]    $ApiKeyHeader = "X-API-Key",
        [string]    $Username,
        [string]    $Password,
        [hashtable] $ExtraHeaders = @{},
        [int]       $MaxRetries   = 3
    )

    $headers = Get-AuthHeader -AuthType $AuthType -Token $Token `
                              -ApiKeyHeader $ApiKeyHeader `
                              -Username $Username -Password $Password
    $ExtraHeaders.GetEnumerator() | ForEach-Object { $headers[$_.Key] = $_.Value }

    $jsonBody = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 }

    $params = @{
        Uri             = $Uri
        Method          = "PUT"
        Headers         = $headers
        Body            = $jsonBody
        ContentType     = "application/json"
        UseBasicParsing = $true
    }

    return Invoke-RetriableRequest -IrmParams $params -MaxRetries $MaxRetries
}

<#
.SYNOPSIS  Sends a DELETE request.
#>
function Invoke-RestDelete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]    $Uri,
        [ValidateSet("Bearer","ApiKey","Basic","None")]
        [string]    $AuthType     = "None",
        [string]    $Token,
        [string]    $ApiKeyHeader = "X-API-Key",
        [string]    $Username,
        [string]    $Password,
        [hashtable] $ExtraHeaders = @{},
        [int]       $MaxRetries   = 3
    )

    $headers = Get-AuthHeader -AuthType $AuthType -Token $Token `
                              -ApiKeyHeader $ApiKeyHeader `
                              -Username $Username -Password $Password
    $ExtraHeaders.GetEnumerator() | ForEach-Object { $headers[$_.Key] = $_.Value }

    $params = @{
        Uri             = $Uri
        Method          = "DELETE"
        Headers         = $headers
        ContentType     = "application/json"
        UseBasicParsing = $true
    }

    return Invoke-RetriableRequest -IrmParams $params -MaxRetries $MaxRetries
}

<#
.SYNOPSIS  Obtains a Bearer token using client credentials flow (OAuth 2.0).
.EXAMPLE
    $token = Get-BearerToken -TenantId $tid -ClientId $cid -ClientSecret $secret `
                             -Scope "https://graph.microsoft.com/.default"
#>
function Get-BearerToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TenantId,
        [Parameter(Mandatory)] [string] $ClientId,
        [Parameter(Mandatory)] [string] $ClientSecret,
        [Parameter(Mandatory)] [string] $Scope
    )

    $body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
    }

    $response = Invoke-RestMethod `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Method POST `
        -Body $body `
        -ContentType "application/x-www-form-urlencoded"

    return $response.access_token
}

<#
.SYNOPSIS  Obtains an access token from the Azure Instance Metadata Service
           (for Managed Identity authentication inside Azure).
.EXAMPLE
    $token = Get-ManagedIdentityToken -Resource "https://graph.microsoft.com/"
#>
function Get-ManagedIdentityToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Resource
    )

    $imdsUri = "http://169.254.169.254/metadata/identity/oauth2/token" +
               "?api-version=2019-08-01&resource=$([Uri]::EscapeDataString($Resource))"

    $response = Invoke-RestMethod -Uri $imdsUri -Headers @{ Metadata = "true" }
    return $response.access_token
}

# ── Module exports ─────────────────────────────────────────────────
Export-ModuleMember -Function @(
    "Invoke-RestGet",
    "Invoke-RestPost",
    "Invoke-RestPut",
    "Invoke-RestDelete",
    "Get-BearerToken",
    "Get-ManagedIdentityToken"
)
