# AutomateIQ — AI Automation Agency Portfolio

> **We automate your business operations with AI.**  
> Custom AI agents and workflow automation that save time, reduce costs, and scale with you.

---

## 🚀 What We Do

AutomateIQ builds production-ready AI automations for small and mid-sized businesses. Our three flagship services eliminate the manual work that bogs down your team every day.

| Service | What It Does | Time Saved |
|---|---|---|
| 🎯 **AI Lead Qualifier** | Scores every inbound lead 0–100 with a grade and next-step recommendation | ~15 hrs/week per SDR |
| 📄 **Invoice Processor** | Extracts vendor, line-items, totals & due dates from PDF invoices automatically | ~8 hrs/week per AP clerk |
| 💬 **Support Chatbot** | Answers customer questions 24/7 from your own knowledge base | ~60% fewer Tier-1 tickets |

---

## �� Project Structure

```
ai-automation-agency/
├── index.html                        # Landing page (Tailwind CSS)
├── README.md
└── demos/
    ├── lead-qualifier/
    │   └── lead_qualifier.py         # Claude-powered lead scoring script
    ├── invoice-processor/
    │   ├── invoice_processor.py      # PDF data extraction script
    │   └── sample_invoice.txt        # Sample invoice for reference
    └── support-bot/
        ├── support_bot.py            # Knowledge-base chatbot
        └── knowledge_base/           # Auto-generated on first run
            ├── services.md
            ├── pricing.md
            ├── faq.md
            └── contact.md
```

---

## 💰 ROI Breakdown

### Why AI Automation Pays for Itself

Based on typical client results in the first 90 days:

#### 🎯 Lead Qualifier
- **Problem:** Sales reps spend 3–4 hours/day manually researching and qualifying leads.
- **Solution:** AI scores each lead in seconds with a grade (A–D) and recommended next action.
- **ROI:** At a median SDR salary of $65k/year, recovering 15 hrs/week = **~$24,000/year saved per rep**.

#### 📄 Invoice Processor
- **Problem:** AP teams spend 10–15 minutes manually keying each invoice; errors cause late fees.
- **Solution:** Automated PDF extraction with 95%+ accuracy, direct export to accounting software.
- **ROI:** Processing 400 invoices/month × 12 min saved = **~80 hrs/month** → **~$28,000/year** at $30/hr.

#### 💬 Support Chatbot
- **Problem:** Tier-1 support tickets cost $8–$15 each to resolve by a human agent.
- **Solution:** Knowledge-base bot deflects 60–70% of repetitive questions automatically.
- **ROI:** Deflecting 500 tickets/month × $10 avg cost = **$5,000/month → $60,000/year saved**.

### Blended ROI Summary

| Investment | Annual Savings (typical) | Payback Period |
|---|---|---|
| Starter plan ($1,200/mo) | $28,000–$60,000 | **2–4 months** |
| Growth plan ($2,500/mo) | $60,000–$112,000 | **3–6 months** |
| Enterprise (custom) | $112,000+ | **3–6 months** |

---

## 🔧 Running the Demo Scripts

### Prerequisites

```bash
pip install anthropic pdfplumber
```

> All scripts run in **demo / offline mode** without an API key, so you can explore them immediately.

### 1. Lead Qualifier

```bash
cd demos/lead-qualifier
python lead_qualifier.py
```

Set `ANTHROPIC_API_KEY` for live AI scoring:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
python lead_qualifier.py
```

### 2. Invoice Processor

```bash
cd demos/invoice-processor

# Rule-based extraction (no API key needed):
python invoice_processor.py                      # generates a sample PDF automatically

# AI-powered extraction:
export ANTHROPIC_API_KEY="sk-ant-..."
python invoice_processor.py --ai

# Save output to JSON:
python invoice_processor.py invoice.pdf --output result.json
```

### 3. Support Bot

```bash
cd demos/support-bot

# Demo mode (offline, no API key):
python support_bot.py

# Live AI mode:
export ANTHROPIC_API_KEY="sk-ant-..."
python support_bot.py

# Non-interactive (pipe a question):
echo "What is your refund policy?" | python support_bot.py --once
```

---

## 🌐 Landing Page

Open `index.html` directly in your browser — no build step required.  
It uses the Tailwind CSS CDN so it renders immediately.

```bash
open index.html   # macOS
xdg-open index.html  # Linux
```

---

## 📅 Book a Free Operations Audit

**Ready to see what AI can do for your business?**

Book a free 30-minute operations audit — we'll map your current workflows, identify automation opportunities, and give you a projected ROI estimate with no obligation.

### 👉 [Book Your Free Audit →](https://automateiq.io/book)

Or email us directly: **hello@automateiq.io**

---

## 🛡️ Security & Compliance

- All data encrypted in transit (TLS 1.3) and at rest (AES-256)
- SOC 2 Type II compliant
- GDPR & CCPA ready
- Data Processing Agreements provided to all clients

---

## 📜 License

MIT © 2025 AutomateIQ. See [LICENSE](LICENSE) for details.
