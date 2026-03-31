/**
 * AutomateIQ Enterprise Automation Dashboard
 * dashboard.js — form handling, workflow animation, and demo data
 */

"use strict";

/* ─────────────────────────────────────────────
   State
───────────────────────────────────────────── */
const state = {
  provisioned: 0,
  staleAccounts: 0,
  savings: 0,
  hoursSaved: 0,
  activityLog: [],
};

/* ─────────────────────────────────────────────
   Utility helpers
───────────────────────────────────────────── */
function formatCurrency(value) {
  return "$" + value.toLocaleString("en-US", { minimumFractionDigits: 0 });
}

function nowISO() {
  return new Date().toISOString().replace("T", " ").slice(0, 19);
}

function slugify(str) {
  return str.toLowerCase().replace(/[^a-z0-9]/g, "");
}

function generateSAMAccountName(first, last) {
  return (first[0] + last).toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 20);
}

/* ─────────────────────────────────────────────
   Activity Log
───────────────────────────────────────────── */
const logContainer = document.getElementById("activity-log");

function addLogEntry(message, level = "info") {
  const entry = document.createElement("div");
  entry.className = `log-entry log-${level}`;
  entry.innerHTML = `<span class="log-time">[${nowISO()}]</span>${message}`;
  logContainer.appendChild(entry);
  logContainer.scrollTop = logContainer.scrollHeight;

  // Remove placeholder
  const placeholder = logContainer.querySelector(".placeholder-text");
  if (placeholder) placeholder.remove();

  state.activityLog.push({ time: nowISO(), message, level });
}

document.getElementById("clear-log").addEventListener("click", () => {
  logContainer.innerHTML = '<p class="placeholder-text">No activity yet. Trigger a workflow to see entries here.</p>';
  state.activityLog = [];
});

/* ─────────────────────────────────────────────
   Metric counters (animated)
───────────────────────────────────────────── */
function animateCounter(elementId, targetValue, prefix = "", suffix = "") {
  const el = document.getElementById(elementId);
  if (!el) return;
  const start = parseInt(el.dataset.value || "0", 10);
  const duration = 600;
  const steps = 30;
  const delta = targetValue - start;
  let step = 0;

  const timer = setInterval(() => {
    step++;
    const current = Math.round(start + (delta * step) / steps);
    el.textContent = prefix + current.toLocaleString() + suffix;
    if (step >= steps) {
      clearInterval(timer);
      el.textContent = prefix + targetValue.toLocaleString() + suffix;
      el.dataset.value = targetValue;
    }
  }, duration / steps);
}

function updateMetrics() {
  animateCounter("metric-provisioned", state.provisioned);
  animateCounter("metric-stale", state.staleAccounts);
  document.getElementById("metric-savings").textContent = formatCurrency(state.savings);
  document.getElementById("metric-hours").textContent = state.hoursSaved + "h";
}

/* ─────────────────────────────────────────────
   Tab navigation
───────────────────────────────────────────── */
document.querySelectorAll(".nav-tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    const target = tab.dataset.tab;

    document.querySelectorAll(".nav-tab").forEach((t) => {
      t.classList.remove("active");
      t.setAttribute("aria-selected", "false");
    });
    tab.classList.add("active");
    tab.setAttribute("aria-selected", "true");

    document.querySelectorAll(".tab-panel").forEach((panel) => {
      const isTarget = panel.id === `tab-${target}`;
      panel.classList.toggle("active", isTarget);
      panel.hidden = !isTarget;
    });
  });
});

/* ─────────────────────────────────────────────
   Workflow step animator
───────────────────────────────────────────── */
const STEPS = ["form", "makecom", "powershell", "ad", "notify"];

function resetWorkflow() {
  STEPS.forEach((step) => {
    const el = document.querySelector(`.workflow-step[data-step="${step}"]`);
    if (!el) return;
    el.classList.remove("active", "done", "error");
    el.querySelector(".step-status").textContent = step === "form" ? "Waiting for input" : "Idle";
  });
}

function setStepState(stepName, status, statusText) {
  const el = document.querySelector(`.workflow-step[data-step="${stepName}"]`);
  if (!el) return;
  el.classList.remove("active", "done", "error");
  el.classList.add(status);
  el.querySelector(".step-status").textContent = statusText;
}

async function runWorkflowAnimation(formPayload, webhookUrl) {
  const resultBox = document.getElementById("provision-result");
  resultBox.className = "result-box hidden";

  const stepDefs = [
    { step: "form",       activeText: "Submitting form data…",         doneText: "Form submitted ✓" },
    { step: "makecom",    activeText: "Triggering Make.com webhook…",   doneText: "Webhook received ✓" },
    { step: "powershell", activeText: "Running PowerShell script…",     doneText: "Script executed ✓" },
    { step: "ad",         activeText: "Provisioning AD / M365 account…",doneText: "Account created ✓" },
    { step: "notify",     activeText: "Sending email notification…",    doneText: "Notification sent ✓" },
  ];

  let response = null;
  let webhookError = null;

  for (let i = 0; i < stepDefs.length; i++) {
    const { step, activeText, doneText } = stepDefs[i];
    setStepState(step, "active", activeText);

    // Actually call the webhook at step 1 (makecom)
    if (step === "makecom" && webhookUrl) {
      try {
        addLogEntry(`POST ${webhookUrl}`, "info");
        const res = await fetch(webhookUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(formPayload),
        });
        response = { status: res.status, ok: res.ok };
        if (!res.ok) {
          webhookError = `Webhook returned HTTP ${res.status}`;
        }
      } catch (err) {
        webhookError = err.message;
      }
    }

    // Simulate async delay for each step
    await delay(600 + Math.random() * 400);

    if (webhookError && step === "makecom") {
      setStepState(step, "error", `Error: ${webhookError}`);
      addLogEntry(`Webhook error: ${webhookError}`, "error");

      resultBox.className = "result-box error";
      resultBox.textContent = `⚠️ Webhook failed: ${webhookError}. Running in demo mode — the remaining steps are simulated.`;
      resultBox.classList.remove("hidden");
      webhookError = null; // continue in demo mode
    } else {
      setStepState(step, "done", doneText);
    }
  }

  return response;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/* ─────────────────────────────────────────────
   User Provisioning Form
───────────────────────────────────────────── */
const provisioningForm = document.getElementById("provisioning-form");
const provisionBtn = document.getElementById("provision-btn");

provisioningForm.addEventListener("submit", async (e) => {
  e.preventDefault();

  // Basic validation
  let valid = true;
  provisioningForm.querySelectorAll("[required]").forEach((field) => {
    field.classList.remove("invalid");
    if (!field.value.trim()) {
      field.classList.add("invalid");
      valid = false;
    }
  });
  if (!valid) {
    addLogEntry("Form validation failed — required fields missing", "warn");
    return;
  }

  const formData = Object.fromEntries(new FormData(provisioningForm).entries());
  const webhookUrl = formData.webhookUrl || "";
  delete formData.webhookUrl;

  const samAccountName = generateSAMAccountName(formData.firstName, formData.lastName);
  const payload = {
    action: "NewUser",
    ...formData,
    samAccountName,
    email: `${samAccountName}@company.com`,
    requestedAt: nowISO(),
  };

  provisionBtn.disabled = true;
  provisionBtn.innerHTML = '<span>⏳</span> Processing…';
  resetWorkflow();

  addLogEntry(`Provisioning request submitted for ${formData.firstName} ${formData.lastName}`, "info");

  await runWorkflowAnimation(payload, webhookUrl);

  // Update metrics
  state.provisioned += 1;
  state.hoursSaved += 2;  // ~2h saved per manual provisioning
  updateMetrics();

  // Show result
  const resultBox = document.getElementById("provision-result");
  if (!resultBox.classList.contains("error")) {
    resultBox.className = "result-box success";
    resultBox.innerHTML = `
      <strong>✅ User provisioned successfully (demo)</strong><br/>
      <strong>Name:</strong> ${formData.firstName} ${formData.lastName}<br/>
      <strong>Username:</strong> ${samAccountName}<br/>
      <strong>Email:</strong> ${samAccountName}@company.com<br/>
      <strong>Department:</strong> ${formData.department}<br/>
      <strong>License:</strong> ${formData.license}
    `;
    resultBox.classList.remove("hidden");
    addLogEntry(`User ${samAccountName} provisioned — AD account + M365 license assigned`, "success");
  }

  provisionBtn.disabled = false;
  provisionBtn.innerHTML = '<span>🚀</span> Provision User';
});

/* ─────────────────────────────────────────────
   Stale Account Scanner (demo data)
───────────────────────────────────────────── */
const DEMO_STALE_ACCOUNTS = [
  { sam: "jsmith",    name: "John Smith",     dept: "Sales",       lastLogon: "2025-04-10", daysInactive: 112, enabled: true  },
  { sam: "mwilson",   name: "Mary Wilson",    dept: "HR",          lastLogon: "2025-03-22", daysInactive: 131, enabled: true  },
  { sam: "tdavis",    name: "Tom Davis",      dept: "Finance",     lastLogon: "2025-04-01", daysInactive: 121, enabled: true  },
  { sam: "sgarcia",   name: "Sara Garcia",    dept: "Marketing",   lastLogon: "2025-02-14", daysInactive: 167, enabled: true  },
  { sam: "bmiller",   name: "Bob Miller",     dept: "Engineering", lastLogon: "2025-05-05", daysInactive: 87,  enabled: false },
];

function getDaysBadge(days) {
  if (days >= 150) return `<span class="badge badge-red">${days}d</span>`;
  if (days >= 120) return `<span class="badge badge-orange">${days}d</span>`;
  return `<span class="badge badge-yellow">${days}d</span>`;
}

document.getElementById("run-stale-scan").addEventListener("click", async () => {
  const btn = document.getElementById("run-stale-scan");
  btn.disabled = true;
  btn.innerHTML = "⏳ Scanning…";
  addLogEntry("Stale account scan initiated (Get-StaleAccounts.ps1 — demo)", "info");

  await delay(1500);

  const tbody = document.getElementById("stale-tbody");
  tbody.innerHTML = "";

  DEMO_STALE_ACCOUNTS.forEach((acct) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><code>${acct.sam}</code></td>
      <td>${acct.name}</td>
      <td>${acct.dept}</td>
      <td>${acct.lastLogon}</td>
      <td>${getDaysBadge(acct.daysInactive)}</td>
      <td>${acct.enabled
          ? '<span class="badge badge-green">Enabled</span>'
          : '<span class="badge badge-red">Disabled</span>'}</td>
      <td>
        <button class="btn btn-ghost" onclick="disableAccount('${acct.sam}', this)">Disable</button>
      </td>
    `;
    tbody.appendChild(tr);
    addLogEntry(`Stale account found: ${acct.sam} (${acct.daysInactive} days inactive)`, "warn");
  });

  state.staleAccounts = DEMO_STALE_ACCOUNTS.length;
  updateMetrics();

  btn.disabled = false;
  btn.innerHTML = "🔍 Run Scan (Demo)";
  addLogEntry(`Scan complete — ${DEMO_STALE_ACCOUNTS.length} stale accounts found`, "success");
});

window.disableAccount = async function (sam, btn) {
  btn.disabled = true;
  btn.textContent = "⏳";
  await delay(800);
  btn.textContent = "✅ Disabled";
  addLogEntry(`Account disabled: ${sam} (Set-ADUser -Enabled $false)`, "success");
  state.hoursSaved += 0.5;
  updateMetrics();
};

/* ─────────────────────────────────────────────
   License Audit (demo data)
───────────────────────────────────────────── */
const DEMO_LICENSES = [
  { sku: "ENTERPRISEPREMIUM", name: "Microsoft 365 E3",             total: 250, assigned: 198, cost: 36.00  },
  { sku: "SPE_E5",             name: "Microsoft 365 E5",            total: 50,  assigned: 47,  cost: 57.00  },
  { sku: "O365_BUSINESS",      name: "M365 Business Basic",         total: 100, assigned: 61,  cost: 6.00   },
  { sku: "DESKLESSPACK",       name: "Microsoft 365 F3 (Frontline)", total: 75,  assigned: 68,  cost: 8.00   },
];

document.getElementById("run-license-audit").addEventListener("click", async () => {
  const btn = document.getElementById("run-license-audit");
  btn.disabled = true;
  btn.innerHTML = "⏳ Auditing…";
  addLogEntry("License audit initiated (Generate-LicenseReport.ps1 — demo)", "info");

  await delay(1800);

  const container = document.getElementById("license-summary");
  let totalSavings = 0;

  const gridHTML = DEMO_LICENSES.map((lic) => {
    const pct = Math.round((lic.assigned / lic.total) * 100);
    const unused = lic.total - lic.assigned;
    const unusedCost = unused * lic.cost;
    totalSavings += unusedCost;

    return `
      <div class="license-card">
        <div class="license-card-name">${lic.name}</div>
        <div class="license-bar-wrap">
          <div class="license-bar" style="width: ${pct}%"></div>
        </div>
        <div class="license-stats">
          <span>${lic.assigned}/${lic.total} assigned (${pct}%)</span>
          <span>${unused} unused — ${formatCurrency(unusedCost)}/mo</span>
        </div>
      </div>
    `;
  }).join("");

  container.innerHTML = `
    <div class="license-grid">${gridHTML}</div>
    <div class="savings-banner">
      💰 Potential monthly savings by reclaiming unused licenses: <strong>${formatCurrency(totalSavings)}</strong>
      &nbsp;(${formatCurrency(totalSavings * 12)}/year)
    </div>
  `;

  state.savings = totalSavings;
  state.hoursSaved += 4;
  updateMetrics();

  addLogEntry(`License audit complete — potential savings: ${formatCurrency(totalSavings)}/mo`, "success");

  btn.disabled = false;
  btn.innerHTML = "🔄 Refresh (Demo)";
});

/* ─────────────────────────────────────────────
   Init
───────────────────────────────────────────── */
(function init() {
  // Set the 1st of next month as the default start date
  const nextMonth = new Date();
  nextMonth.setDate(1);
  nextMonth.setMonth(nextMonth.getMonth() + 1);
  const yyyy = nextMonth.getFullYear();
  const mm = String(nextMonth.getMonth() + 1).padStart(2, "0");
  const startDateInput = document.getElementById("startDate");
  if (startDateInput) {
    startDateInput.value = `${yyyy}-${mm}-01`;
  }

  updateMetrics();
  addLogEntry("Dashboard initialised — connected to AutomateIQ demo environment", "info");
})();
