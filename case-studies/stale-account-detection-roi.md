# Case Study: Stale Account Detection Automation — ROI Analysis

**Client Profile**: Financial services firm, 1,200 employees, hybrid AD environment  
**Industry**: Financial Services / Banking  
**Challenge**: Security audits repeatedly finding active accounts belonging to departed employees

---

## Executive Summary

By deploying the AutomateIQ Stale Account Detection workflow, this client reduced the time to identify and disable stale accounts from **4–6 weeks (manual audit cycle)** to **weekly automated detection**, resulting in a significantly improved security posture, $18,000+ in annual savings, and elimination of two compliance findings.

---

## The Security Risk Context

Stale accounts — user accounts that remain active after an employee leaves or changes roles — represent one of the most common and preventable security vulnerabilities in enterprise environments.

**Industry data:**
- 58% of data breaches involve compromised credentials (Verizon DBIR 2024)
- The average stale account remains active for **97 days** after an employee departs
- A single breached stale account costs an average of **$4.35 million** in a financial services breach

---

## Before Automation: Manual Audit Process

### Quarterly Manual Audit Steps
1. IT security engineer exports AD user list (1 hour)
2. Cross-references against HR termination records (2–3 hours)
3. Identifies accounts not matching active employees (2 hours)
4. Manually checks last logon dates (1–2 hours)
5. Submits disable requests via ticketing system (1 hour)
6. Waits for manager approval (1–5 business days)
7. IT disables accounts (1 hour)
8. Documents findings for compliance report (2 hours)

### Before Metrics

| Metric | Value |
|--------|-------|
| Audit frequency | Quarterly |
| IT security engineer hours per audit | 12 hours |
| Hours per year (audits + remediation) | 48+ hours |
| Hourly rate (security engineer) | $85/hour |
| Annual IT security audit cost | **$4,080** |
| Average days stale account remains active | 97 days |
| Stale accounts found per audit | 18–25 |
| Compliance findings per year (stale accounts) | 2 |
| Compliance remediation cost per finding | **$7,500** |
| Annual compliance cost | **$15,000** |
| **Total annual cost** | **$19,080** |

---

## After Automation: AutomateIQ Stale Account Workflow

### Automated Weekly Process
1. Make.com scheduler fires every Monday at 08:00 AM
2. HTTP module calls `Get-StaleAccounts.ps1`
3. PowerShell queries AD for accounts inactive > 90 days
4. JSON response parsed by Make.com iterator
5. Each stale account logged to Data Store
6. Consolidated email report sent to IT Security team
7. Accounts reviewed and disabled same day via dashboard
8. Audit log auto-generated for compliance

### After Metrics

| Metric | Value |
|--------|-------|
| Detection frequency | **Weekly** |
| IT security engineer hours per week | **30 minutes** (review only) |
| Annual review hours | 26 hours |
| Annual IT security review cost | **$2,210** |
| Average days stale account remains active | **< 7 days** |
| Stale accounts found per scan | Identified within 7 days |
| Compliance findings per year | **0** |
| Annual compliance cost | **$0** |
| **Total annual cost** | **$2,210** |

---

## ROI Summary

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Detection cycle | Quarterly | Weekly | **12× more frequent** |
| Time to remediate | 97 days avg. | < 7 days | **93% faster** |
| Annual IT security cost | $4,080 | $2,210 | **$1,870 saved** |
| Annual compliance cost | $15,000 | $0 | **$15,000 saved** |
| Compliance findings | 2/year | 0/year | **100% eliminated** |
| **Total annual savings** | — | — | **$16,870** |

### Automation Implementation Cost
| Item | Cost |
|------|------|
| AutomateIQ setup & configuration | $1,800 (one-time) |
| Make.com Core plan (shared with other scenarios) | $0 additional |
| Azure Functions hosting (shared) | $0 additional |
| **Total first-year cost** | **$1,800** |

### Net First-Year Savings
```
$16,870 (labour + compliance savings) − $1,800 (implementation) = $15,070 net savings
ROI = 737%
Payback period = 6.4 weeks
```

---

## Compliance and Regulatory Impact

For financial services clients subject to SOX, PCI DSS, or ISO 27001:

| Standard | Requirement | Status Before | Status After |
|----------|-------------|---------------|-------------|
| SOX | Timely account deprovisioning | Finding | **Compliant** |
| PCI DSS 8.1.4 | Remove inactive accounts within 90 days | At-risk | **Compliant** |
| ISO 27001 A.9.2.6 | Removal of access rights on departure | Manual | **Automated** |

---

## Technical Implementation

- **Orchestration**: Make.com Scheduler → HTTP Module → Data Store → Email
- **Backend**: PowerShell 7 (`Get-StaleAccounts.ps1`) on Azure Functions
- **Directory**: Active Directory (RSAT ActiveDirectory module)
- **Reporting**: Make.com Data Store + Weekly email digest

See [`../scripts/Get-StaleAccounts.ps1`](../scripts/Get-StaleAccounts.ps1) for implementation details.
