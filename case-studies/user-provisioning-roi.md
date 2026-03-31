# Case Study: User Provisioning Automation — ROI Analysis

**Client Profile**: Mid-size technology company, 650 employees, Microsoft 365 E3 tenant  
**Industry**: Software & Technology  
**Challenge**: Manual new-hire IT provisioning taking 3–4 hours per employee

---

## Executive Summary

By implementing the AutomateIQ User Provisioning Workflow (PowerShell + Make.com), this client reduced account provisioning time from **3.5 hours to under 8 minutes**, saving over **$47,000 annually** in IT labour costs and eliminating provisioning errors entirely.

---

## Before Automation: Manual Process

### Steps Required (Manual)
1. HR emails IT helpdesk with new hire information
2. IT technician creates AD account (15–20 min)
3. IT manually assigns group memberships based on department (10–15 min)
4. IT submits M365 license assignment ticket (5 min + approval queue)
5. License assigned by admin (up to 24h wait)
6. IT creates shared drive/SharePoint access (20–30 min)
7. IT emails manager with account credentials (10 min)
8. Follow-up to confirm all access is working (variable)

### Before Metrics

| Metric | Value |
|--------|-------|
| Average provisioning time | 3.5 hours |
| IT technician hourly rate | $45/hour |
| Cost per provisioning | **$157.50** |
| Monthly new hires | 12 |
| Monthly IT provisioning cost | **$1,890** |
| Annual IT provisioning cost | **$22,680** |
| Error rate (wrong group, missing license) | 23% |
| Average time to resolve provisioning errors | 45 minutes |
| Annual error-resolution cost | **$2,808** |
| **Total annual cost** | **$25,488** |

---

## After Automation: AutomateIQ Workflow

### Automated Steps
1. HR submits web form (2 min)
2. Make.com webhook triggers instantly
3. PowerShell creates AD account (< 30 seconds)
4. Department-based group memberships assigned automatically
5. M365 license assigned via Microsoft Graph (< 30 seconds)
6. SharePoint/OneDrive provisioned
7. Manager receives automated email with credentials
8. Dashboard updated with new user entry

### After Metrics

| Metric | Value |
|--------|-------|
| Average provisioning time | **7 minutes** (HR form + automated) |
| IT technician involvement | **0 minutes** (fully automated) |
| Cost per provisioning | **$5.25** (infrastructure only) |
| Monthly new hires | 12 |
| Monthly IT provisioning cost | **$63** |
| Annual IT provisioning cost | **$756** |
| Error rate | **0%** (validated input, consistent logic) |
| Annual error-resolution cost | **$0** |
| **Total annual cost** | **$756** |

---

## ROI Summary

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Provisioning time | 3.5 hours | 7 minutes | **97% faster** |
| Cost per provisioning | $157.50 | $5.25 | **97% cheaper** |
| Annual cost | $25,488 | $756 | **$24,732 saved** |
| Error rate | 23% | 0% | **100% reduction** |
| HR wait time | 1–3 days | Instant | **Immediate** |

### Automation Implementation Cost
| Item | Cost |
|------|------|
| AutomateIQ setup & configuration | $2,400 (one-time) |
| Make.com Core plan (monthly) | $9/month = $108/year |
| Azure Functions hosting | ~$5/month = $60/year |
| **Total first-year cost** | **$2,568** |

### Net First-Year Savings
```
$24,732 (labour savings) − $2,568 (implementation) = $22,164 net savings
ROI = 763%
Payback period = 5.4 weeks
```

---

## Additional Intangible Benefits

- **New hires productive on Day 1** — no waiting for IT to provision accounts
- **Consistent security posture** — every account receives exactly the right permissions
- **Audit trail** — every provisioning action logged in Make.com Data Store
- **IT team time reallocated** — 42 hours/month freed for higher-value work
- **HR satisfaction** — self-service form replaces email back-and-forth

---

## Technical Implementation

- **Frontend**: HTML5 web form deployed on company intranet
- **Orchestration**: Make.com scenario with Custom Webhook + HTTP modules
- **Backend**: PowerShell 7 (`New-UserProvisioning.ps1`) running on Azure Functions
- **Directory**: Active Directory + Microsoft 365 (Microsoft Graph API)
- **Notifications**: Make.com SendGrid module

See [`../scripts/New-UserProvisioning.ps1`](../scripts/New-UserProvisioning.ps1) and [`../docs/workflow-templates.md`](../docs/workflow-templates.md) for implementation details.
