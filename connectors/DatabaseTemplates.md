# Database Connection Templates

Ready-to-use database connection patterns for PowerShell automation scripts. Includes SQL Server, Azure SQL, and PostgreSQL examples.

---

## SQL Server / Azure SQL (SqlServer Module)

### Installation
```powershell
Install-Module SqlServer -Scope CurrentUser -Force
```

### Connection String Templates

```powershell
# SQL Server (Windows Authentication)
$connStr = "Server=SQLSERVER01;Database=AutomationDB;Integrated Security=True;TrustServerCertificate=True"

# SQL Server (SQL Authentication — use Azure Key Vault for credentials in production)
$user    = $env:DB_USER
$pass    = $env:DB_PASSWORD
$connStr = "Server=SQLSERVER01;Database=AutomationDB;User Id=$user;Password=$pass;TrustServerCertificate=True"

# Azure SQL (Azure AD with Managed Identity — recommended for Azure Functions)
$connStr = "Server=yourserver.database.windows.net;Database=AutomationDB;Authentication=Active Directory Managed Identity"
```

### Logging Automation Events

```powershell
function Write-AutomationEvent {
    param(
        [string] $Action,
        [string] $Status,
        [string] $Details,
        [string] $ConnectionString
    )

    $query = @"
INSERT INTO dbo.AutomationLog (Action, Status, Details, CreatedAt, ComputerName)
VALUES (@Action, @Status, @Details, GETUTCDATE(), @ComputerName)
"@

    $params = @{
        "@Action"       = $Action
        "@Status"       = $Status
        "@Details"      = $Details
        "@ComputerName" = $env:COMPUTERNAME
    }

    Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query -Variable $params
}
```

### Creating the Log Table

```sql
CREATE TABLE dbo.AutomationLog (
    Id           INT IDENTITY(1,1) PRIMARY KEY,
    Action       NVARCHAR(100)  NOT NULL,
    Status       NVARCHAR(50)   NOT NULL,
    Details      NVARCHAR(MAX),
    CreatedAt    DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    ComputerName NVARCHAR(100),
    RequestId    UNIQUEIDENTIFIER
);

CREATE INDEX IX_AutomationLog_CreatedAt ON dbo.AutomationLog (CreatedAt DESC);
CREATE INDEX IX_AutomationLog_Action    ON dbo.AutomationLog (Action);
```

---

## PostgreSQL (Npgsql / psql)

### Installation
```powershell
# Install Npgsql .NET driver
Install-Package Npgsql -Scope CurrentUser
```

### Connection and Query Pattern

```powershell
function Invoke-PostgresQuery {
    param(
        [string]   $ConnectionString,
        [string]   $Query,
        [hashtable]$Parameters = @{}
    )

    Add-Type -AssemblyName "Npgsql"

    $conn = [Npgsql.NpgsqlConnection]::new($ConnectionString)
    $conn.Open()

    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query

        foreach ($key in $Parameters.Keys) {
            $cmd.Parameters.AddWithValue($key, $Parameters[$key]) | Out-Null
        }

        $reader = $cmd.ExecuteReader()
        $results = [System.Collections.Generic.List[hashtable]]::new()

        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $row[$reader.GetName($i)] = $reader.GetValue($i)
            }
            $results.Add($row)
        }

        return $results
    }
    finally {
        $conn.Close()
    }
}

# Usage example
$pg = "Host=pgserver.company.com;Username=automation;Password=$env:PG_PASSWORD;Database=automationdb"
$rows = Invoke-PostgresQuery -ConnectionString $pg `
    -Query "SELECT * FROM automation_log WHERE status = @status" `
    -Parameters @{ "@status" = "pending" }
```

### PostgreSQL Schema

```sql
CREATE TABLE automation_log (
    id           SERIAL PRIMARY KEY,
    action       VARCHAR(100) NOT NULL,
    status       VARCHAR(50)  NOT NULL,
    details      TEXT,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    computer_name VARCHAR(100),
    request_id   UUID
);

CREATE INDEX idx_automation_log_created_at ON automation_log (created_at DESC);
CREATE INDEX idx_automation_log_action     ON automation_log (action);
```

---

## Azure Cosmos DB (NoSQL)

For cloud-native Make.com → PowerShell → Cosmos DB pipelines:

```powershell
function Write-CosmosDocument {
    param(
        [string]    $AccountEndpoint,
        [string]    $DatabaseName,
        [string]    $ContainerName,
        [hashtable] $Document
    )

    $key     = $env:COSMOS_PRIMARY_KEY
    $utcNow  = [DateTime]::UtcNow.ToString("R")
    $method  = "POST"
    $resType = "docs"
    $resLink = "dbs/$DatabaseName/colls/$ContainerName"
    $url     = "$AccountEndpoint/$resLink/docs"

    # Compute authorisation signature
    $stringToSign = "$($method.ToLower())`n$($resType.ToLower())`n$resLink`n$($utcNow.ToLower())`n`n"
    $hmac  = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($key))
    $hash  = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign))
    $sig   = [Convert]::ToBase64String($hash)
    $auth  = [Uri]::EscapeDataString("type=master&ver=1.0&sig=$sig")

    $headers = @{
        "Authorization"           = $auth
        "x-ms-date"               = $utcNow
        "x-ms-version"            = "2018-12-31"
        "x-ms-documentdb-partitionkey" = '["' + $Document.id + '"]'
    }

    Invoke-RestMethod -Uri $url -Method POST -Headers $headers `
        -ContentType "application/json" `
        -Body ($Document | ConvertTo-Json -Depth 10)
}
```

---

## Best Practices

1. **Never hardcode credentials** — use environment variables or Azure Key Vault
2. **Use parameterised queries** to prevent SQL injection
3. **Always close connections** in `finally` blocks
4. **Use connection pooling** for high-frequency scripts
5. **Index your log table** on `CreatedAt` and `Action` for fast Make.com queries
6. **Rotate database passwords** on a schedule using Azure Key Vault rotation policies
7. **Limit database user permissions** — the automation service account should only have `INSERT` and `SELECT` on the log table
