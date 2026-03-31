# Case Study: License Audit & Reporting Automation — ROI Analysis

**Client Profile**: Professional services firm, 480 employees, Microsoft 365 E3 + E5 mix  
**Industry**: Professional Services / Consulting  
**Challenge**: No visibility into M365 license utilisation; suspected significant over-licensing

---

## Executive Summary

AutomateIQ's License Audit workflow delivered **$8,640 in immediate annual savings** by identifying 48 unused Microsoft 365 licenses, plus an additional **$14,400/year** in ongoing efficiency savings from automated monthly reporting — replacing a manual process that cost the IT director nearly a full day every month.

---

## The Hidden Cost of Over-Licensing

Microsoft 365 licenses are commonly over-purchased for several reasons:
- Employees leave but licenses are not reclaimed
- Departments request "buffer" licenses for anticipated hires
- License types are mis-matched to actual usage needs
- No automated tracking of license consumption vs. allocation

**Industry benchmark**: The average enterprise wastes **22% of its SaaS spend** on unused licenses (Gartner, 2024).

---

## Before Automation: Manual Monthly Audit

### Monthly Process Steps
1. IT Director logs into Microsoft 365 Admin Center
2. Exports license assignment report (CSV)
3. Cross-references with HR employee roster (Excel)
4. Identifies accounts with assigned but unused licenses
5. Checks last activity date for each flagged account
6. Compiles findings into a Word/Excel report
7. Emails report to Finance and IT leadership
8. Finance manually calculates variance vs. budget

### Before Metrics

| Metric | Value |
|--------|-------|
| IT Director hours per monthly report | 6 hours |
| IT Director hourly rate (fully-loaded) | $100/hour |
| Monthly reporting cost | $600 |
| Annual reporting cost | **$7,200** |
| Report accuracy | ~85% (manual errors, stale data) |
| Average time from discovery to action | 3–4 weeks |
| Unused licenses at audit discovery | 48 (on 480-seat tenant) |
| Monthly waste from unused licenses | **$720** |
| Annual waste from unused licenses | **$8,640** |
| **Total annual cost** | **$15,840** |

*48 unused E3 licenses × $36/seat/month × 12 months = $20,736 — but many went undetected for months, so average discovered waste was $8,640/year*

---

## After Automation: AutomateIQ License Audit Workflow

### Automated Monthly Process
1. Make.com scheduler fires on 1st of each month at 07:00 AM
2. HTTP module calls `Generate-LicenseReport.ps1`
3. PowerShell queries Microsoft Graph for all subscribed SKUs
4. JSON response stored in Make.com Data Store (trend history)
5. Data appended to Google Sheets audit workbook
6. Professional PDF report emailed to Finance + IT leadership
7. Dashboard updated with current month snapshot
8. Slack alert sent if unused licenses exceed threshold

### After Metrics

| Metric | Value |
|--------|-------|
| IT Director hours per monthly report | **0 hours** (automated) |
| Monthly reporting cost | **$0** |
| Annual reporting cost | **$0** |
| Report accuracy | **100%** (direct Graph API query) |
| Average time from discovery to action | **Same day** |
| Unused licenses at first automated audit | 48 |
| Action taken (licenses reclaimed) | 44 of 48 within 2 weeks |
| Monthly savings from reclaimed licenses | **$1,584** |
| Annual savings from reclaimed licenses | **$19,008** |
| **Total annual cost** | **$240** (infrastructure only) |

---

## ROI Summary

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Monthly reporting hours | 6 hours | 0 hours | **100% automated** |
| Annual IT reporting cost | $7,200 | $0 | **$7,200 saved** |
| Report accuracy | 85% | 100% | **15% improvement** |
| Time to act on findings | 3–4 weeks | Same day | **21× faster** |
| Unused licenses identified | 48 | 48 → 4 | **92% reclaimed** |
| Annual license waste | $8,640 | $144 | **$8,496 saved** |
| **Total annual savings** | — | — | **$15,696** |

### Automation Implementation Cost
| Item | Cost |
|------|------|
| AutomateIQ setup & configuration | $2,200 (one-time) |
| Make.com Core plan | $108/year |
| Azure Functions hosting | $60/year |
| **Total first-year cost** | **$2,368** |

### Net First-Year Savings
```
$15,696 (labour + license savings) − $2,368 (implementation) = $13,328 net savings
ROI = 462%
Payback period = 8.8 weeks
```

---

## Three-Year Projection

| Year | Savings | Costs | Net |
|------|---------|-------|-----|
| Year 1 | $15,696 | $2,368 | **$13,328** |
| Year 2 | $15,696 | $168 (ops) | **$15,528** |
| Year 3 | $15,696 | $168 (ops) | **$15,528** |
| **3-Year Total** | $47,088 | $2,704 | **$44,384** |

---

## Additional Business Benefits

- **Finance team confidence** — Monthly reports arrive automatically, on time, every time
- **Budget accuracy** — IT can now forecast M365 spend within 2% accuracy
- **Right-sizing licenses** — Monthly trend data enables license type optimisation (E5 → E3 downgrades where E5 features unused)
- **Vendor negotiation leverage** — Accurate utilisation data strengthens Microsoft EA renewal negotiations

---

## Technical Implementation

- **Orchestration**: Make.com Scheduler → HTTP Module → Data Store → Google Sheets → Email
- **Backend**: PowerShell 7 (`Generate-LicenseReport.ps1`) on Azure Functions
- **API**: Microsoft Graph (`Get-MgSubscribedSku`)
- **Storage**: Make.com Data Store + Google Sheets (12-month rolling history)
- **Alerting**: Slack Incoming Webhook for threshold breaches

See [`../scripts/Generate-LicenseReport.ps1`](../scripts/Generate-LicenseReport.ps1) and [`../docs/workflow-templates.md`](../docs/workflow-templates.md) for implementation details.
