# AI Lead Qualifier & CRM Router — Make.com Setup Guide

Automate inbound lead triage with a Make.com scenario that scores every new Typeform submission using GPT-4o and routes the result to either Pipedrive (high-priority) or Mailchimp (nurture).

**Potential Impact:** Workflows like this typically reduce manual lead-sorting time by ~90% and cut median time-to-contact for high-value prospects from 4+ hours to under 15 minutes.

---

## Overview

```
Typeform (new response)
    │
    ▼
OpenAI GPT-4o — score 0–100, grade A–D, priority high/low
    │
    ▼
Router
    ├── Score ≥ 70 (High Priority)
    │       ├── Slack  → #sales-alerts channel
    │       └── Pipedrive → create Deal + Person + Organisation
    │
    └── Score < 70 (Low Priority)
            └── Mailchimp → add to "Nurture" audience with tags
```

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Make.com account (Core plan or higher) | Free tier has a 1,000 ops/month limit |
| Typeform account | Any paid plan supports webhooks |
| OpenAI API key (GPT-4o access) | Platform → API keys |
| Slack workspace (admin or bot-token permissions) | For #sales-alerts channel |
| Pipedrive account | CRM — any plan |
| Mailchimp account | For the nurture audience |

---

## Part 1: Design the Typeform

Create a new Typeform with the following fields and note each field's **Field ID** (visible in the Share → Connect → Webhooks panel, or via the Typeform API).

| Field Label | Type | Suggested Field ID variable |
|-------------|------|-----------------------------|
| Full Name | Short text | `YOUR_NAME_FIELD_ID` |
| Work Email | Email | `YOUR_EMAIL_FIELD_ID` |
| Company Name | Short text | `YOUR_COMPANY_FIELD_ID` |
| Job Title | Short text | `YOUR_TITLE_FIELD_ID` |
| Company Size | Multiple choice (1-10 / 11-50 / 51-200 / 201-500 / 500+) | `YOUR_SIZE_FIELD_ID` |
| Monthly Automation Budget | Multiple choice (<$500 / $500-$2k / $2k-$5k / $5k-$10k / $10k+) | `YOUR_BUDGET_FIELD_ID` |
| Implementation Timeline | Multiple choice (ASAP / 1-3 months / 3-6 months / 6+ months) | `YOUR_TIMELINE_FIELD_ID` |
| Describe your automation need | Long text | `YOUR_USECASE_FIELD_ID` |

> **Tip:** You can add `source` as a **Hidden Field** (Typeform Settings → Hidden fields) and populate it via UTM parameters or embed code so the AI has referral context.

---

## Part 2: Import the Make.com Blueprint

1. In Make.com, click **Create a new scenario**.
2. Click the **⋯ (More)** menu → **Import blueprint**.
3. Upload `demos/lead-qualifier/make_blueprint.json` from this repository.
4. The scenario imports with 6 modules pre-wired: Typeform → OpenAI → Router → (Slack + Pipedrive) / Mailchimp.

---

## Part 3: Configure Each Module

### 3.1 Typeform Trigger (Module 1)

1. Click the Typeform module → **Add** a new connection (OAuth).
2. Select your form from the **Form** dropdown.
3. Make.com auto-generates a webhook URL — copy it.
4. In Typeform → **Connect** → **Webhooks** → paste the URL and click **Save webhook**.
5. Click **Send test request** in Typeform to confirm Make.com receives the payload.

> Typeform sends each field answer keyed by its field ID. Replace every `YOUR_*_FIELD_ID` placeholder in the blueprint with the actual IDs from your form.
>
> **How to find field IDs:** In Make.com, after a successful test, click the Typeform module bubble → **Output** tab. Each answer is listed with its real field ID.

### 3.2 OpenAI Chat Completion (Module 2)

1. Click the OpenAI module → **Add** a new connection → paste your **OpenAI API key**.
2. Verify the **Model** is set to `gpt-4o`.
3. The system prompt is pre-configured with a scoring rubric and JSON output schema. After importing, edit it directly in the Make.com UI (click the module → expand the **Messages** field) rather than modifying the blueprint JSON. See [Part 7](#part-7-tuning-the-scoring-prompt) for customisation options.
4. The user message maps Typeform answers to the prompt. After receiving a live test response, confirm the field IDs are correct.

**Expected AI response shape:**

```json
{
  "score": 84,
  "grade": "B",
  "priority": "high",
  "summary": "VP-level contact at a 200-person SaaS company with a clear invoice-automation pain point, defined budget, and a Q3 deadline.",
  "strengths": ["Decision-maker title", "Defined $3k/month budget", "Hard deadline"],
  "weaknesses": ["Evaluating 2 other vendors"],
  "next_step": "Book a 30-minute discovery call within 24 hours and demo the invoice processor.",
  "estimated_deal_value": 36000
}
```

> **Cost estimate:** Each lead scoring call uses ~600–900 tokens with GPT-4o. At $5/M input + $15/M output tokens, scoring 100 leads/day ≈ **$0.50–$0.80/day**.

### 3.3 Router (Module 3)

The router splits execution into two routes based on the AI score:

| Route | Condition |
|-------|-----------|
| High Priority | `parseJSON(2.choices[].message.content).score ≥ 70` |
| Low Priority | `parseJSON(2.choices[].message.content).score < 70` |

No configuration needed — both filters are pre-set in the blueprint.

### 3.4 Slack Alert (Module 4 — High Priority route)

1. Click the Slack module → **Add** a connection → authorise your workspace.
2. Set **Channel** to your `#sales-alerts` channel (or any channel where the sales team should be pinged).
3. The message template is pre-built and includes: lead name, company, grade, score, AI summary, strengths/weaknesses, recommended next step, and estimated deal value.

**Sample Slack message:**

```
🔥 HIGH-PRIORITY LEAD — B (84/100)

Name:    Marcus Webb
Email:   marcus@techscale.io
Company: TechScale Inc. · 120 employees
Title:   VP of Operations
Budget:  $2k-$5k/month
Timeline:ASAP

AI Summary:
VP-level contact at a 200-person SaaS company with a clear invoice-automation
pain point, defined budget, and a Q3 deadline.

✅ Strengths: Decision-maker title · Defined $3k/month budget · Hard deadline
⚠️ Weaknesses: Evaluating 2 other vendors

👉 Next Step: Book a 30-minute discovery call within 24 hours and demo the invoice processor.
💰 Est. Deal Value: $36,000/yr
```

### 3.5 Pipedrive Create Deal (Module 5 — High Priority route)

1. Click the Pipedrive module → **Add** a connection → authorise with your Pipedrive API token.
2. The mapper pre-fills:
   - **Title:** `<Company> — AI Automation (<Grade> Lead)`
   - **Value:** the AI `estimated_deal_value` field
   - **Expected Close Date:** 30 days from submission
   - **Note:** full AI analysis pasted into the deal note
   - **Person:** created or matched by name + email
   - **Organisation:** created or matched by company name
3. Optionally map the deal to a specific **Pipeline** and **Stage** (e.g., "Inbound → New Lead").

> **Tip:** Add a fourth module in this route — **Pipedrive → Create Activity** — to auto-schedule a follow-up call task for the assigned sales rep.

### 3.6 Mailchimp Add/Update Subscriber (Module 6 — Low Priority route)

1. Click the Mailchimp module → **Add** a connection → authorise with your Mailchimp API key.
2. Set **Audience** to your nurture list (e.g., "Prospects — Nurture Sequence").
3. The mapper pre-fills:
   - `FNAME`, `LNAME`, `COMPANY`, `JOBTITLE` — from Typeform answers
   - `SCORE`, `GRADE` — from the AI result, useful for Mailchimp segmentation
   - Tags: `nurture`, `grade-b` (or c/d), `ai-qualified`
4. In Mailchimp, create a **Tag-based automation** (Customer Journeys) triggered by the `nurture` tag to send a 5-email drip sequence over 30 days.

---

## Part 4: Environment Variables

Store secrets in Make.com (**Organisation → Environment Variables**) and reference them in module connections rather than hardcoding credentials.

| Variable | Description |
|----------|-------------|
| `OPENAI_API_KEY` | OpenAI platform key |
| `SLACK_BOT_TOKEN` | Slack bot OAuth token |
| `PIPEDRIVE_API_TOKEN` | Pipedrive personal API token |
| `MAILCHIMP_API_KEY` | Mailchimp API key |

---

## Part 5: Error Handling

Add error handlers to the OpenAI and Pipedrive modules to avoid silent failures:

1. Right-click the OpenAI module → **Add error handler** → choose **Commit**.
2. In the error route, add a **Slack → Create Message** module pointing to `#ops-alerts`:
   ```
   ⚠️ Lead Qualifier error on run {{executionId}}
   Module: OpenAI — {{error.message}}
   Lead: {{1.answers.YOUR_NAME_FIELD_ID.text}} ({{1.answers.YOUR_EMAIL_FIELD_ID.email}})
   ```
3. Enable **Allow storing incomplete executions** in scenario settings so failed runs can be manually replayed.

---

## Part 6: Testing Checklist

- [ ] Submit a test Typeform response and confirm Make.com receives the webhook payload
- [ ] Verify all Typeform field IDs are mapped correctly in the OpenAI user message
- [ ] Confirm OpenAI returns valid JSON (check execution output in Make.com history)
- [ ] Test the high-priority route: submit a lead that should score ≥ 70
  - [ ] Slack message appears in `#sales-alerts`
  - [ ] Pipedrive deal is created with the correct title, value, and note
- [ ] Test the low-priority route: submit a lead that should score < 70
  - [ ] Mailchimp subscriber is added/updated with correct tags
- [ ] Trigger an error intentionally (e.g., remove the OpenAI key) and verify the Slack error alert fires
- [ ] Review Make.com execution logs for timing (target < 8 seconds end-to-end)

---

## Part 7: Tuning the Scoring Prompt

The GPT-4o system prompt in Module 2 can be customised for your specific business:

- **Raise the high-priority threshold** — change the router filter from `≥ 70` to `≥ 80` if you only want to Slack-alert on Grade A leads.
- **Add industry weighting** — append instructions like: *"If the company is in Financial Services, Healthcare, or SaaS, add 10 bonus points."*
- **Budget floors** — add: *"Any lead mentioning a budget below $500/month should score no higher than 40."*
- **Disqualifier rules** — add: *"If the message contains 'just looking' or 'student project', cap the score at 20."*

---

## ROI Summary

| Metric | Before | After |
|--------|--------|-------|
| Daily leads reviewed manually | 100+ | 0 (fully automated) |
| High-priority leads missed | ~15% | <2% |
| Time-to-Slack for hot leads | 4+ hours | <15 seconds |
| Manual lead-sorting hours/week | ~15 hrs | ~1.5 hrs |
| **Time saved** | — | **~90%** |
