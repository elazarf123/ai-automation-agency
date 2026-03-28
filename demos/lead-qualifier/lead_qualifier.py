#!/usr/bin/env python3
"""
Lead Qualifier — AutomateIQ Demo
=================================
Scores inbound business leads (0–100) using the Anthropic Claude API.
Each lead is evaluated on five dimensions:
  - Company fit      (industry, size)
  - Budget signals   (mentions of budget / spend)
  - Urgency          (timeline, pain-point language)
  - Decision-maker   (is the contact the right person?)
  - Automation need  (do they have clear manual workflows to replace?)

Usage
-----
    export ANTHROPIC_API_KEY="sk-ant-..."
    python lead_qualifier.py

Or pass leads programmatically by importing `qualify_lead()`.

Requirements
------------
    pip install anthropic
"""

import json
import os
import sys
from typing import Any

try:
    import anthropic
except ImportError:
    print("ERROR: 'anthropic' package not found.  Run:  pip install anthropic")
    sys.exit(1)


# ── Scoring prompt ────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """You are an expert sales qualification analyst for an AI automation agency.
Your job is to evaluate inbound leads and decide which ones deserve immediate sales attention.

For each lead you receive, return a JSON object with exactly these fields:
{
  "score": <integer 0-100>,
  "grade": <"A" | "B" | "C" | "D">,
  "summary": "<2-3 sentence plain-English summary of the lead>",
  "strengths": ["<strength 1>", "<strength 2>", ...],
  "weaknesses": ["<weakness 1>", ...],
  "next_step": "<specific recommended action for the sales rep>",
  "estimated_deal_size": "<small | medium | large | enterprise>"
}

Scoring rubric:
  90-100  Grade A — Hot lead, contact within 1 hour
  70-89   Grade B — Warm lead, contact within 24 hours
  50-69   Grade C — Nurture with email sequence
  0-49    Grade D — Disqualify or park for 90 days

Return ONLY the raw JSON object — no markdown fences, no extra text."""


def qualify_lead(lead_data: dict[str, Any], model: str = "claude-3-5-haiku-20241022") -> dict[str, Any]:
    """
    Score a single lead using Claude.

    Parameters
    ----------
    lead_data : dict
        Arbitrary key/value information about the lead (name, company, message, etc.)
    model : str
        Anthropic model ID to use.

    Returns
    -------
    dict
        Parsed JSON result from Claude, containing score, grade, summary, etc.
    """
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError(
            "ANTHROPIC_API_KEY environment variable is not set.\n"
            "Get your key at https://console.anthropic.com/ and export it:\n"
            "  export ANTHROPIC_API_KEY='sk-ant-...'"
        )

    client = anthropic.Anthropic(api_key=api_key)

    user_message = f"Please qualify the following lead:\n\n{json.dumps(lead_data, indent=2)}"

    message = client.messages.create(
        model=model,
        max_tokens=1024,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_message}],
    )

    raw_text = message.content[0].text.strip()

    try:
        result = json.loads(raw_text)
    except json.JSONDecodeError:
        # Fallback: return raw text if Claude didn't produce valid JSON
        result = {"error": "Could not parse JSON response", "raw": raw_text}

    return result


def print_result(lead_name: str, result: dict[str, Any]) -> None:
    """Pretty-print a qualification result to stdout."""
    grade_colors = {"A": "\033[92m", "B": "\033[94m", "C": "\033[93m", "D": "\033[91m"}
    reset = "\033[0m"
    grade = result.get("grade", "?")
    color = grade_colors.get(grade, "")

    print("\n" + "=" * 60)
    print(f"  Lead: {lead_name}")
    print(f"  Score: {result.get('score', '?')} / 100   Grade: {color}{grade}{reset}")
    print(f"  Est. Deal Size: {result.get('estimated_deal_size', 'unknown')}")
    print("-" * 60)
    print(f"  Summary: {result.get('summary', '')}")
    if result.get("strengths"):
        print("\n  ✅ Strengths:")
        for s in result["strengths"]:
            print(f"     • {s}")
    if result.get("weaknesses"):
        print("\n  ⚠️  Weaknesses:")
        for w in result["weaknesses"]:
            print(f"     • {w}")
    print(f"\n  👉 Next Step: {result.get('next_step', '')}")
    print("=" * 60)


# ── Sample leads ─────────────────────────────────────────────────────────────

SAMPLE_LEADS = [
    {
        "name": "Marcus Webb",
        "title": "VP of Operations",
        "company": "TechScale Inc.",
        "company_size": "120 employees",
        "industry": "SaaS",
        "message": (
            "Hi, we process around 400 vendor invoices per month entirely by hand. "
            "Our AP team is drowning and we're already budgeted $3k/month for a solution. "
            "We need something running before our Q3 close. Can you help?"
        ),
        "email": "marcus@techscale.io",
        "source": "Contact form",
    },
    {
        "name": "Jenny Park",
        "title": "Marketing Coordinator",
        "company": "Local Bakery Co.",
        "company_size": "8 employees",
        "industry": "Food & Beverage",
        "message": "Heard AI is cool, just exploring options, no real budget yet.",
        "email": "jenny@localbakery.com",
        "source": "Referral",
    },
    {
        "name": "David Osei",
        "title": "CEO",
        "company": "Meridian Financial Group",
        "company_size": "350 employees",
        "industry": "Financial Services",
        "message": (
            "We're evaluating AI vendors to automate our client onboarding workflow. "
            "Currently takes 5 days manually; we want it under 4 hours. "
            "We have executive sign-off and a $25k pilot budget. Timeline: 60 days."
        ),
        "email": "d.osei@meridianfg.com",
        "source": "LinkedIn outbound",
    },
]


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    print("\n🚀 AutomateIQ — Lead Qualifier Demo")
    print("   Scoring leads with Claude AI...\n")

    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("⚠️  ANTHROPIC_API_KEY not set — running in MOCK mode.\n")
        _run_mock()
        return

    for lead in SAMPLE_LEADS:
        lead_name = f"{lead['name']} ({lead['company']})"
        print(f"Qualifying: {lead_name} ...", end="", flush=True)
        try:
            result = qualify_lead(lead)
            print(" done.")
            print_result(lead_name, result)
        except Exception as exc:
            print(f"\n  ERROR: {exc}")

    print("\n✅ Qualification run complete.\n")


def _run_mock() -> None:
    """Simulate qualification results when no API key is present."""
    mock_results = [
        {
            "score": 88,
            "grade": "B",
            "summary": "Strong operational pain point with a defined budget. VP-level contact in a scaling SaaS company. High urgency due to Q3 deadline.",
            "strengths": ["Decision-maker title", "Defined budget ($3k/mo)", "Clear automation use-case"],
            "weaknesses": ["Not yet confirmed as final decision-maker"],
            "next_step": "Book 30-minute discovery call within 24 hours; demo the invoice processor.",
            "estimated_deal_size": "medium",
        },
        {
            "score": 22,
            "grade": "D",
            "summary": "No budget, no urgency, non-decision-maker. Small business unlikely to benefit from enterprise AI tooling at this stage.",
            "strengths": ["Referral source"],
            "weaknesses": ["No budget", "No clear use-case", "Not a decision-maker"],
            "next_step": "Add to a 90-day nurture email sequence.",
            "estimated_deal_size": "small",
        },
        {
            "score": 97,
            "grade": "A",
            "summary": "CEO with executive buy-in, defined budget, and a specific timeline. Ideal enterprise prospect in financial services — a high-value vertical.",
            "strengths": ["CEO / decision-maker", "$25k pilot budget", "60-day timeline", "Clear ROI target"],
            "weaknesses": ["Competitive evaluation under way"],
            "next_step": "Call within the hour. Prepare a custom onboarding-workflow demo and an ROI projection.",
            "estimated_deal_size": "enterprise",
        },
    ]

    for lead, result in zip(SAMPLE_LEADS, mock_results):
        lead_name = f"{lead['name']} ({lead['company']})"
        print(f"[MOCK] Qualifying: {lead_name}")
        print_result(lead_name, result)

    print("\n✅ Mock qualification complete.  Set ANTHROPIC_API_KEY to use real AI scoring.\n")


if __name__ == "__main__":
    main()
