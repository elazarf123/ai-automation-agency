# Enterprise Automation Dashboard — Setup Instructions

Interactive web dashboard for demonstrating PowerShell + Make.com automation workflows.

---

## What This Demo Does

The dashboard provides a working UI for three enterprise automation workflows:

| Tab | Workflow | Backend Script |
|-----|----------|---------------|
| **User Provisioning** | Submit a new-hire form → Make.com → PowerShell | `New-UserProvisioning.ps1` |
| **Stale Accounts** | Trigger account scan and view inactive users | `Get-StaleAccounts.ps1` |
| **License Audit** | View M365 license utilisation and savings | `Generate-LicenseReport.ps1` |
| **Activity Log** | Real-time log of all automation actions | All scripts |

---

## Quick Start (Demo Mode — No Backend Required)

Open `index.html` directly in your browser:

```bash
# macOS / Linux
open demo/index.html

# Windows
start demo/index.html

# Or serve with any static file server:
npx serve demo/
python -m http.server 8080 --directory demo/
```

In demo mode, all workflows simulate the backend responses locally using JavaScript. No Make.com account or PowerShell endpoint is needed.

---

## Connecting to a Real Make.com Webhook

1. Create a Make.com scenario with a **Custom Webhook** trigger.
2. Copy the generated webhook URL.
3. In the **User Provisioning** tab, paste the URL into the **Make.com Webhook URL** field.
4. Submit the form — the dashboard will POST the payload to Make.com and animate the workflow steps.

See [`../docs/make-com-setup.md`](../docs/make-com-setup.md) for full Make.com configuration instructions.

---

## Payload Structure

The dashboard sends the following JSON to the Make.com webhook:

```json
{
  "action": "NewUser",
  "firstName": "Jane",
  "lastName": "Doe",
  "department": "Engineering",
  "managerEmail": "manager@company.com",
  "startDate": "2025-08-01",
  "license": "ENTERPRISEPREMIUM",
  "samAccountName": "jdoe",
  "email": "jdoe@company.com",
  "requestedAt": "2025-07-28 10:34:12"
}
```

---

## File Structure

```
demo/
├── index.html       # Dashboard HTML — three workflow tabs + activity log
├── dashboard.css    # All styles — brand colours, cards, tables, log
├── dashboard.js     # Tab navigation, form handling, workflow animation
└── README.md        # This file
```

---

## Customisation

### Change the Brand Colour
Edit the `:root` CSS variables in `dashboard.css`:

```css
:root {
  --brand-600: #2255cc;  /* Primary button / metric colour */
  --brand-700: #1a3fa0;  /* Header background */
}
```

### Add a New Workflow Tab

1. Add a `<button class="nav-tab" data-tab="myworkflow">` in `index.html`.
2. Add a `<section id="tab-myworkflow" class="tab-panel" hidden>` panel.
3. Wire up the form/button logic in `dashboard.js`.

### Point to a Different Endpoint

Replace the fetch call in `dashboard.js` `runWorkflowAnimation()` to POST to your own API endpoint instead of Make.com.

---

## Browser Compatibility

Works in all modern browsers (Chrome 90+, Firefox 88+, Safari 14+, Edge 90+). No build step or dependencies required — pure HTML/CSS/JavaScript.
