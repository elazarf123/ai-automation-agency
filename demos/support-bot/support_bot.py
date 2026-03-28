#!/usr/bin/env python3
"""
Support Bot — AutomateIQ Demo
================================
A terminal-based AI support chatbot that answers customer questions using a
local Markdown knowledge base.  When a user asks a question, the bot:

  1. Searches the knowledge base for the most relevant sections (TF-IDF / keyword
     overlap — no external vector DB required).
  2. Passes the retrieved context + conversation history to Claude (or runs in
     offline demo mode without an API key).
  3. Streams or prints the answer, then loops for the next question.

Usage
-----
    # Demo mode (no API key needed — uses canned responses):
    python support_bot.py

    # Live mode with Claude:
    export ANTHROPIC_API_KEY="sk-ant-..."
    python support_bot.py

    # Use a custom knowledge base directory:
    python support_bot.py --kb ./my_knowledge_base

    # Non-interactive: pipe questions in
    echo "What is your refund policy?" | python support_bot.py --once

Requirements
------------
    pip install anthropic   # optional — only needed for live AI mode
"""

import argparse
import math
import os
import re
import sys
from pathlib import Path
from typing import NamedTuple


# ── Knowledge base path ───────────────────────────────────────────────────────

DEFAULT_KB_DIR = Path(__file__).parent / "knowledge_base"


# ── Document model ────────────────────────────────────────────────────────────

class Document(NamedTuple):
    title: str
    content: str
    source: str


# ── Knowledge base loader ─────────────────────────────────────────────────────

def load_knowledge_base(kb_dir: Path) -> list[Document]:
    """Load all Markdown (.md) and text (.txt) files from kb_dir."""
    docs: list[Document] = []
    for path in sorted(kb_dir.glob("**/*.md")) + sorted(kb_dir.glob("**/*.txt")):
        text = path.read_text(encoding="utf-8", errors="replace")
        # Use first H1 heading or filename as title
        title_match = re.search(r"^#\s+(.+)", text, re.MULTILINE)
        title = title_match.group(1).strip() if title_match else path.stem.replace("_", " ").title()
        docs.append(Document(title=title, content=text, source=str(path.relative_to(kb_dir))))
    return docs


# ── TF-IDF retrieval (no external dependencies) ───────────────────────────────

def _tokenize(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", text.lower())


def _tf(tokens: list[str]) -> dict[str, float]:
    freq: dict[str, int] = {}
    for t in tokens:
        freq[t] = freq.get(t, 0) + 1
    n = len(tokens) or 1
    return {t: c / n for t, c in freq.items()}


def build_idf(docs: list[Document]) -> dict[str, float]:
    N = len(docs)
    df: dict[str, int] = {}
    for doc in docs:
        tokens = set(_tokenize(doc.content))
        for t in tokens:
            df[t] = df.get(t, 0) + 1
    return {t: math.log((N + 1) / (count + 1)) + 1 for t, count in df.items()}


def score_document(query_tokens: list[str], doc: Document, idf: dict[str, float]) -> float:
    doc_tf = _tf(_tokenize(doc.content))
    score = 0.0
    for token in query_tokens:
        tf_val = doc_tf.get(token, 0.0)
        idf_val = idf.get(token, 1.0)
        score += tf_val * idf_val
    return score


def retrieve(query: str, docs: list[Document], idf: dict[str, float], top_k: int = 3) -> list[Document]:
    """Return the top-k most relevant documents for the query."""
    query_tokens = _tokenize(query)
    if not query_tokens:
        return docs[:top_k]
    scored = [(score_document(query_tokens, doc, idf), doc) for doc in docs]
    scored.sort(key=lambda x: x[0], reverse=True)
    return [doc for _, doc in scored[:top_k]]


# ── Context builder ───────────────────────────────────────────────────────────

MAX_CONTEXT_CHARS = 4000


def build_context(relevant_docs: list[Document]) -> str:
    parts: list[str] = []
    total = 0
    for doc in relevant_docs:
        snippet = doc.content[:MAX_CONTEXT_CHARS // len(relevant_docs)]
        parts.append(f"### {doc.title} (source: {doc.source})\n\n{snippet}")
        total += len(snippet)
    return "\n\n---\n\n".join(parts)


# ── Conversation history ──────────────────────────────────────────────────────

MAX_HISTORY = 10  # keep last N turns to avoid token overflow


class ConversationHistory:
    def __init__(self) -> None:
        self._turns: list[dict] = []

    def add(self, role: str, content: str) -> None:
        self._turns.append({"role": role, "content": content})
        if len(self._turns) > MAX_HISTORY * 2:
            self._turns = self._turns[-(MAX_HISTORY * 2):]

    def as_list(self) -> list[dict]:
        return list(self._turns)


# ── AI answer generation ──────────────────────────────────────────────────────

SYSTEM_PROMPT_TEMPLATE = """You are a friendly and knowledgeable customer support agent for AutomateIQ, 
an AI automation agency. You answer questions based ONLY on the provided knowledge base context.

Rules:
1. Answer concisely and helpfully.
2. If the answer is not in the context, say: "I don't have that information right now. 
   Please email support@automateiq.io or book a call at automateiq.io/book."
3. Never make up information not present in the context.
4. Keep responses under 200 words unless a detailed explanation is clearly needed.
5. Be friendly, professional, and solution-oriented.

Knowledge Base Context:
-----------------------
{context}
-----------------------"""


def get_ai_answer(
    question: str,
    context: str,
    history: ConversationHistory,
    model: str = "claude-3-5-haiku-20241022",
) -> str:
    """Ask Claude using the retrieved context and conversation history."""
    try:
        import anthropic
    except ImportError:
        raise ImportError("Run:  pip install anthropic")

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError("ANTHROPIC_API_KEY not set.")

    client = anthropic.Anthropic(api_key=api_key)

    messages = history.as_list() + [{"role": "user", "content": question}]

    response = client.messages.create(
        model=model,
        max_tokens=512,
        system=SYSTEM_PROMPT_TEMPLATE.format(context=context),
        messages=messages,
    )
    return response.content[0].text.strip()


# ── Offline demo mode ─────────────────────────────────────────────────────────

DEMO_RESPONSES: dict[str, str] = {
    "default": (
        "Great question! Based on our knowledge base, AutomateIQ specialises in three core services: "
        "AI Lead Qualification, Automated Invoice Processing, and 24/7 Support Chatbots. "
        "Would you like to know more about any of these?"
    ),
    "price": (
        "Our pricing starts at $1,200/month for the Monthly Automation Retainer. "
        "Setup fees vary by project complexity. Book a free audit at automateiq.io/book "
        "and we'll give you a custom quote within 24 hours."
    ),
    "refund": (
        "We offer a 30-day satisfaction guarantee on all pilot projects. "
        "If you're not happy with the results in the first 30 days, we'll refund your setup fee — no questions asked."
    ),
    "integration": (
        "We integrate with HubSpot, Salesforce, QuickBooks, Xero, Slack, Zapier, and most REST APIs. "
        "Custom integrations are also available — just ask!"
    ),
    "time": (
        "Most implementations are live within 2–4 weeks. "
        "Simple automations (e.g., a single workflow) can be deployed in as little as 5 business days."
    ),
}


def get_demo_answer(question: str, context: str) -> str:
    """Return a canned demo response based on keyword matching."""
    q_lower = question.lower()
    if any(w in q_lower for w in ["price", "cost", "fee", "how much", "pricing"]):
        return DEMO_RESPONSES["price"]
    if any(w in q_lower for w in ["refund", "guarantee", "money back", "cancel"]):
        return DEMO_RESPONSES["refund"]
    if any(w in q_lower for w in ["integrat", "connect", "crm", "hubspot", "salesforce", "quickbooks"]):
        return DEMO_RESPONSES["integration"]
    if any(w in q_lower for w in ["how long", "timeline", "when", "days", "weeks"]):
        return DEMO_RESPONSES["time"]
    return DEMO_RESPONSES["default"]


# ── Chat loop ─────────────────────────────────────────────────────────────────

def chat_loop(
    docs: list[Document],
    idf: dict[str, float],
    use_ai: bool,
    once: bool = False,
) -> None:
    history = ConversationHistory()
    print("\n" + "=" * 60)
    print("  🤖  AutomateIQ Support Bot")
    mode_label = "AI mode (Claude)" if use_ai else "Demo mode (offline)"
    print(f"  Mode: {mode_label}")
    print(f"  Knowledge base: {len(docs)} document(s) loaded")
    print("  Type 'exit' or 'quit' to end the session.")
    print("=" * 60 + "\n")

    while True:
        if once:
            question = sys.stdin.readline().strip()
            if not question:
                break
        else:
            try:
                question = input("You: ").strip()
            except (EOFError, KeyboardInterrupt):
                print("\n\n👋  Goodbye!")
                break

        if not question:
            continue
        if question.lower() in {"exit", "quit", "bye", "goodbye"}:
            print("\n👋  Thanks for chatting! Have a great day.\n")
            break

        # Retrieve relevant context
        relevant = retrieve(question, docs, idf, top_k=3)
        context = build_context(relevant)

        # Generate answer
        if use_ai:
            try:
                answer = get_ai_answer(question, context, history)
            except Exception as exc:
                answer = f"[AI error: {exc}] Falling back to demo mode.\n" + get_demo_answer(question, context)
        else:
            answer = get_demo_answer(question, context)

        print(f"\n🤖  Bot: {answer}\n")
        history.add("user", question)
        history.add("assistant", answer)

        if once:
            break


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="AutomateIQ Support Bot — Knowledge-base-powered customer support chatbot.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--kb",
        default=str(DEFAULT_KB_DIR),
        metavar="DIR",
        help="Path to the knowledge base directory (default: ./knowledge_base).",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Read a single question from stdin, print the answer, and exit.",
    )
    parser.add_argument(
        "--model",
        default="claude-3-5-haiku-20241022",
        help="Anthropic model to use when ANTHROPIC_API_KEY is set.",
    )
    args = parser.parse_args()

    kb_dir = Path(args.kb)
    if not kb_dir.exists():
        print(f"⚠️  Knowledge base directory not found: {kb_dir}")
        print("   Using built-in demo knowledge base …\n")
        kb_dir = DEFAULT_KB_DIR
        kb_dir.mkdir(parents=True, exist_ok=True)
        _write_default_kb(kb_dir)

    docs = load_knowledge_base(kb_dir)
    if not docs:
        print(f"⚠️  No documents found in {kb_dir}.  Writing default knowledge base …")
        _write_default_kb(kb_dir)
        docs = load_knowledge_base(kb_dir)

    idf = build_idf(docs)
    use_ai = bool(os.environ.get("ANTHROPIC_API_KEY"))

    chat_loop(docs, idf, use_ai=use_ai, once=args.once)


def _write_default_kb(kb_dir: Path) -> None:
    """Write the default knowledge base documents to kb_dir."""
    for filename, content in DEFAULT_KB_DOCS.items():
        (kb_dir / filename).write_text(content, encoding="utf-8")
    print(f"   Default knowledge base written to: {kb_dir}\n")


# ── Default knowledge base content ───────────────────────────────────────────

DEFAULT_KB_DOCS: dict[str, str] = {
    "services.md": """\
# AutomateIQ Services

## AI Lead Qualification
AutomateIQ's lead qualifier uses large language models to score every inbound lead on five dimensions:
company fit, budget signals, urgency, decision-maker status, and automation readiness.
Leads receive a score from 0–100 and a grade (A–D) with a recommended next step.

## Automated Invoice Processing
Our invoice processor extracts vendor details, line items, totals, and due dates from PDF invoices
with 95%+ accuracy. Outputs can be pushed directly to QuickBooks, Xero, or any REST API.

## 24/7 AI Support Chatbot
Our chatbots are trained on your own documentation and FAQs. They answer customer questions
instantly, reduce Tier-1 support tickets by up to 70%, and escalate complex issues to a human agent.
""",
    "pricing.md": """\
# Pricing & Packages

## Starter — $1,200/month
- 1 automated workflow
- Up to 500 documents/leads per month
- Email support

## Growth — $2,500/month
- Up to 3 workflows
- Unlimited volume
- Priority support + monthly strategy call

## Enterprise — Custom pricing
- Unlimited workflows
- Dedicated account manager
- SLA guarantees
- On-premise deployment available

## Setup Fees
- Simple workflow: $1,500 one-time
- Complex multi-system integration: $3,000–$8,000 one-time

All plans include a 30-day satisfaction guarantee.
""",
    "faq.md": """\
# Frequently Asked Questions

## How long does implementation take?
Most implementations are complete within 2–4 weeks. Simple single-workflow automations
can go live in as little as 5 business days.

## What integrations do you support?
We integrate with HubSpot, Salesforce, Pipedrive, QuickBooks, Xero, Slack, Zapier,
Make (Integromat), and any system with a REST API.

## Is my data secure?
Yes. All data is encrypted in transit (TLS 1.3) and at rest (AES-256). We are SOC 2
Type II compliant and sign a Data Processing Agreement with every client.

## What if I'm not satisfied?
We offer a 30-day money-back guarantee on setup fees. If the automation does not
perform as agreed, we will refund your setup cost in full.

## Do you offer a free trial?
Yes — we offer a free 30-minute operations audit and a pilot project scoping session
at no cost. Book yours at automateiq.io/book.

## What industries do you work with?
We primarily serve SaaS, financial services, professional services, e-commerce,
healthcare administration, and logistics companies.
""",
    "contact.md": """\
# Contact & Support

## Email
support@automateiq.io  — response within 4 business hours

## Book a Call
https://automateiq.io/book — free 30-minute operations audit

## Emergency Support (Enterprise clients)
+1 (415) 555-0192 — available 24/7 for P1 incidents

## Office Hours
Monday–Friday, 9 AM – 6 PM Pacific Time
""",
}


if __name__ == "__main__":
    main()
