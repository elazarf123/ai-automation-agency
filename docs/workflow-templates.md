# Workflow Templates — Make.com Automation

Reusable workflow patterns using Make.com orchestration for SMB and enterprise automation scenarios.

---

## Template 1: User Provisioning Workflow

**Trigger**: Web form submission → Make.com webhook → PowerShell → Active Directory / Microsoft 365

### Overview
Automate the end-to-end onboarding process for new employees, reducing provisioning time from hours to minutes.

### Make.com Scenario Steps
1. **Webhook** — Receives new-hire data from the web form (name, department, manager, start date)
2. **Data Store** — Logs the request with a status of `pending`
3. **HTTP Module** — Sends a POST request to your PowerShell webhook endpoint with the payload
4. **Email (SendGrid/Gmail)** — Notifies IT and the hiring manager upon completion
5. **Data Store (update)** — Updates the request status to `completed`

### PowerShell Entry Point
```powershell
# Trigger script: New-UserProvisioning.ps1
# See /scripts/New-UserProvisioning.ps1 for the full implementation
Invoke-AutomationWebhook -Action "NewUser" -Payload $webhookPayload
```

### Data Flow
```
Web Form (HTML)
    ↓  POST /submit
Make.com Webhook
    ↓  HTTP Module
PowerShell Script (Invoke-AutomationWebhook.ps1)
    ↓  New-ADUser / Set-MsolUser
Active Directory / Microsoft 365
    ↓  Confirmation
Make.com Data Store → Email Notification → Dashboard Update
```

### Required Make.com Modules
| Module | Purpose |
|--------|---------|
| Webhooks → Custom webhook | Receive form data |
| Data Store → Add a record | Log the request |
| HTTP → Make a request | Call PowerShell endpoint |
| Email → Send an email | Notify stakeholders |

### PowerShell Variables
| Variable | Description | Example |
|----------|-------------|---------|
| `$FirstName` | Employee first name | `"Jane"` |
| `$LastName` | Employee last name | `"Doe"` |
| `$Department` | Department name | `"Engineering"` |
| `$Manager` | Manager UPN | `"manager@company.com"` |
| `$StartDate` | ISO 8601 start date | `"2025-08-01"` |
| `$License` | M365 license SKU | `"ENTERPRISEPREMIUM"` |

---

## Template 2: Stale Account Detection

**Trigger**: Scheduled Make.com run → PowerShell script → Email notifications

### Overview
Automatically identify and report user accounts that have not logged in within a configurable threshold (default: 90 days), helping maintain security compliance.

### Make.com Scenario Steps
1. **Scheduler** — Runs every Monday at 08:00 AM
2. **HTTP Module** — Calls the PowerShell stale-account endpoint
3. **JSON Parser** — Parses the list of stale accounts returned
4. **Iterator** — Loops through each stale account
5. **Data Store** — Records each stale account with detection timestamp
6. **Email** — Sends a consolidated report to the IT security team

### PowerShell Entry Point
```powershell
# Trigger script: Get-StaleAccounts.ps1
# Returns JSON array of stale accounts
Get-StaleAccounts -DaysInactive 90 -OutputFormat JSON
```

### Data Flow
```
Make.com Scheduler (weekly)
    ↓  HTTP GET
PowerShell: Get-StaleAccounts.ps1
    ↓  Queries Active Directory
Stale Account List (JSON)
    ↓  Parsed by Make.com
Iterator → Data Store record + Email per account
    ↓
IT Security Report (email)
```

### Sample JSON Response
```json
{
  "generated": "2025-07-28T08:00:00Z",
  "threshold_days": 90,
  "total_stale": 12,
  "accounts": [
    {
      "SamAccountName": "jsmith",
      "DisplayName": "John Smith",
      "LastLogonDate": "2025-04-15T09:23:00Z",
      "DaysInactive": 104,
      "Department": "Sales",
      "Manager": "amanager@company.com",
      "Enabled": true
    }
  ]
}
```

---

## Template 3: License Audit & Reporting

**Trigger**: Scheduled Make.com run → PowerShell data collection → Make.com Data Store → Dashboard report

### Overview
Collect Microsoft 365 license utilization data via PowerShell, store it in Make.com's data store, and surface the results in the web dashboard for stakeholder review.

### Make.com Scenario Steps
1. **Scheduler** — Runs on the 1st of each month
2. **HTTP Module** — Calls `Generate-LicenseReport.ps1` endpoint
3. **JSON Parser** — Parses license utilization data
4. **Data Store** — Stores snapshot for trend analysis
5. **Google Sheets / Excel Online** — Appends data to audit workbook
6. **Email** — Sends PDF report to Finance and IT leadership

### PowerShell Entry Point
```powershell
# Trigger script: Generate-LicenseReport.ps1
Generate-LicenseReport -ReportMonth (Get-Date).Month -OutputFormat JSON
```

### Data Flow
```
Make.com Scheduler (monthly)
    ↓  HTTP GET
PowerShell: Generate-LicenseReport.ps1
    ↓  Queries Microsoft Graph / MSOnline
License Data (JSON)
    ↓
Make.com Data Store (monthly snapshot)
    ↓
Google Sheets / Excel Online (audit trail)
    ↓
Email Report → Finance & IT Leadership
```

### Sample JSON Response
```json
{
  "report_date": "2025-07-01",
  "tenant": "company.onmicrosoft.com",
  "licenses": [
    {
      "SkuPartNumber": "ENTERPRISEPREMIUM",
      "FriendlyName": "Microsoft 365 E3",
      "Total": 250,
      "Assigned": 198,
      "Unassigned": 52,
      "CostPerLicense": 36.00,
      "MonthlyCost": 7128.00,
      "UnusedCost": 1872.00
    }
  ],
  "total_monthly_spend": 9840.00,
  "potential_savings": 2340.00
}
```

---

### Template 4: AI Lead Qualifier & CRM Router

**Trigger**: Typeform new response → OpenAI GPT-4o scoring → Slack + Pipedrive (high priority) or Mailchimp (low priority)

### Overview
Score every inbound lead in seconds using GPT-4o, route hot leads directly to Slack and Pipedrive for immediate follow-up, and add low-scoring leads to a Mailchimp nurture sequence — all without manual review.

### Make.com Scenario Steps
1. **Typeform → TriggerNewEntry** — Receives new form responses via webhook
2. **OpenAI → CreateChatCompletion** — Scores the lead 0–100 with grade A–D and priority using GPT-4o
3. **Router** — Branches on `parseJSON(2.choices[].message.content).score`
4. *High Priority (≥ 70):* **Slack → CreateMessage** — Posts alert to `#sales-alerts`
5. *High Priority (≥ 70):* **Pipedrive → CreateDeal** — Creates deal, person, and organisation
6. *Low Priority (< 70):* **Mailchimp → AddUpdateSubscriber** — Adds contact to nurture audience with grade tags

### Importable Blueprint
The full Make.com scenario blueprint is at `demos/lead-qualifier/make_blueprint.json`. See the complete setup guide at `docs/lead-qualifier-crm-router.md`.

### Data Flow
```
Typeform (new response)
    ↓  Webhook
Make.com: OpenAI GPT-4o
    ↓  JSON score object
Router (score ≥ 70 / < 70)
    ├── Slack alert + Pipedrive deal
    └── Mailchimp nurture subscriber
```

### Required Make.com Modules
| Module | Purpose |
|--------|---------|
| Typeform → TriggerNewEntry | Instant webhook trigger on new response |
| OpenAI → CreateChatCompletion | GPT-4o lead scoring (model: `gpt-4o`) |
| builtin → BasicRouter | Conditional routing by AI score |
| Slack → CreateMessage | Sales-team alert for hot leads |
| Pipedrive → CreateDeal | Auto-create CRM deal with AI note |
| Mailchimp → AddUpdateSubscriber | Add low-priority leads to nurture audience |

### Impact
| Metric | Result |
|--------|--------|
| Manual lead-sorting time | Reduced by ~90% |
| Time-to-Slack for hot leads | < 15 seconds |
| Cost per scored lead | ~$0.01 (GPT-4o) |

---

## Template Customisation Checklist

Before deploying any template, complete the following:

- [ ] Replace `WEBHOOK_SECRET` with a strong random string in both Make.com and your PowerShell environment
- [ ] Update `$Domain` variable to match your Active Directory / Microsoft 365 tenant
- [ ] Configure SMTP or SendGrid credentials in Make.com for email notifications
- [ ] Set up Make.com Data Store schema to match the JSON fields above
- [ ] Test in a non-production environment before enabling the Make.com scheduler
- [ ] Review PowerShell execution policy (`Set-ExecutionPolicy RemoteSigned`)
- [ ] Confirm the service account running PowerShell has the minimum required AD/M365 permissions
