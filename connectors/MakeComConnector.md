# Make.com Connector Guide

Complete reference for integrating Make.com (formerly Integromat) with PowerShell automation scripts and enterprise IT systems.

---

## Overview

Make.com acts as the central orchestration layer, connecting:
- **Web forms** (triggers)
- **PowerShell scripts** (via HTTP module)
- **Data stores** (logging and persistence)
- **Email / Slack** (notifications)
- **Google Sheets / Excel Online** (reporting)

---

## Module Reference

### Webhooks — Custom Webhook

The primary trigger for form-based workflows.

| Setting | Value |
|---------|-------|
| Type | Custom webhook |
| Method | POST |
| Content-Type | application/json |
| Authentication | Shared secret header (`X-Webhook-Secret`) |

**Webhook URL format:**
```
https://hook.us1.make.com/{unique_id}
```

**Test with curl:**
```bash
curl -X POST https://hook.us1.make.com/YOUR_WEBHOOK_ID \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: your-secret-here" \
  -d '{"action":"NewUser","firstName":"Test","lastName":"User","department":"IT"}'
```

---

### HTTP — Make a Request

Calls your PowerShell endpoint from Make.com.

| Field | Value |
|-------|-------|
| URL | `https://your-function.azurewebsites.net/api/Invoke-AutomationWebhook` |
| Method | POST |
| Headers | `X-Webhook-Secret: {{env.WEBHOOK_SECRET}}` |
| Body type | Raw |
| Content type | `application/json` |
| Parse response | Yes (JSON) |
| Timeout | 30 seconds |

**Map webhook data to request body:**
```json
{
  "action": "{{1.action}}",
  "firstName": "{{1.firstName}}",
  "lastName": "{{1.lastName}}",
  "department": "{{1.department}}",
  "managerEmail": "{{1.managerEmail}}",
  "startDate": "{{1.startDate}}",
  "license": "{{1.license}}"
}
```

---

### Data Store — Schema

Create a Data Store named `AutomationLogs` with this structure:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `requestId` | Text | Yes | Use `{{uuid()}}` |
| `action` | Text | Yes | `NewUser`, `StaleCheck`, `LicenseAudit` |
| `status` | Text | Yes | `pending`, `completed`, `failed` |
| `payload` | Text | No | `{{toJSON(1)}}` |
| `result` | Text | No | `{{toJSON(3.data)}}` |
| `createdAt` | Date | Yes | `{{now}}` |
| `completedAt` | Date | No | Set in update module |
| `triggeredBy` | Text | No | Username or email |

---

### Scheduler Module (for recurring workflows)

| Setting | Stale Account Detection | License Audit |
|---------|------------------------|---------------|
| Interval | Weekly | Monthly |
| Day | Monday | 1st |
| Time | 08:00 AM | 07:00 AM |
| Timezone | Your local timezone | Your local timezone |

---

## Environment Variables

Store secrets in Make.com as **environment variables** (not hardcoded in scenarios):

1. Go to **Organization** → **Environment Variables**.
2. Add the following:

| Variable Name | Description | Example |
|---------------|-------------|---------|
| `WEBHOOK_SECRET` | Shared secret for PowerShell validation | `wh_abc123xyz` |
| `ADMIN_EMAIL` | IT admin email for notifications | `it@company.com` |
| `SENDGRID_API_KEY` | SendGrid key for email modules | `SG.xxxx` |

Reference in modules using: `{{env.VARIABLE_NAME}}`

---

## Error Handling Pattern

Add an error handler to every scenario:

```
Main flow:
  Webhook → Data Store (add) → HTTP → Data Store (update) → Email

Error route (on HTTP module):
  → Data Store (update status=failed) → Slack alert → Email to IT admin
```

**Error handler configuration:**
1. Right-click the HTTP module → **Add error handler**
2. Select **Commit** (log and continue, don't roll back)
3. Add **Slack → Create a message** with error details
4. Add **Data Store → Update a record** to set `status = "failed"`

---

## Scenario Import / Export

Export a scenario as a blueprint for sharing:

1. Open the scenario → **⋯ (More)** → **Export blueprint**
2. Save the `.json` file
3. To import: **Create a new scenario** → **⋯** → **Import blueprint**

> Blueprint files can be version-controlled alongside your PowerShell scripts in this repository.

---

## Rate Limits and Quotas

| Plan | Operations/month | Scenario runs/month |
|------|-----------------|---------------------|
| Free | 1,000 | 1,000 |
| Core | 10,000 | Unlimited |
| Pro | 40,000 | Unlimited |

For enterprise IT automation, the **Core** plan ($9/month) is typically sufficient for:
- 50 user provisionings/month
- Weekly stale account scans
- Monthly license audits

---

## Useful Make.com Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `uuid()` | Generate a unique ID | `{{uuid()}}` |
| `now` | Current datetime | `{{now}}` |
| `toJSON(data)` | Serialise to JSON string | `{{toJSON(1)}}` |
| `parseJSON(str)` | Parse JSON string | `{{parseJSON(1.result)}}` |
| `ifempty(a, b)` | Fallback value | `{{ifempty(1.license, "ENTERPRISEPREMIUM")}}` |
| `formatDate(date, format)` | Format date | `{{formatDate(now, "YYYY-MM-DD")}}` |
