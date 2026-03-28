#!/usr/bin/env python3
"""
Invoice Processor — AutomateIQ Demo
=====================================
Extracts structured data from PDF invoices using pdfplumber (for text-based
PDFs) with an optional AI fallback via Anthropic Claude for scanned / complex
documents.

Extracted fields
----------------
  vendor_name, vendor_address, vendor_email, vendor_phone,
  invoice_number, invoice_date, due_date,
  line_items  [ {description, quantity, unit_price, total} ],
  subtotal, tax, total_amount, currency, payment_terms, notes

Usage
-----
    # Text-based PDF (no API key needed):
    python invoice_processor.py sample_invoice.pdf

    # AI-powered extraction (handles scanned PDFs, complex layouts):
    export ANTHROPIC_API_KEY="sk-ant-..."
    python invoice_processor.py sample_invoice.pdf --ai

    # Output to a JSON file:
    python invoice_processor.py sample_invoice.pdf --output result.json

Requirements
------------
    pip install pdfplumber anthropic
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import pdfplumber
except ImportError:
    print("ERROR: 'pdfplumber' package not found.  Run:  pip install pdfplumber")
    sys.exit(1)


# ── AI extraction (Claude) ────────────────────────────────────────────────────

EXTRACTION_PROMPT = """You are an expert accounts-payable data-extraction assistant.
Given the raw text extracted from an invoice PDF, return a JSON object with exactly
these fields (use null for any field that cannot be determined):

{
  "vendor_name":    "<string>",
  "vendor_address": "<string>",
  "vendor_email":   "<string or null>",
  "vendor_phone":   "<string or null>",
  "invoice_number": "<string>",
  "invoice_date":   "<YYYY-MM-DD or null>",
  "due_date":       "<YYYY-MM-DD or null>",
  "line_items": [
    {
      "description": "<string>",
      "quantity":    <number or null>,
      "unit_price":  <number or null>,
      "total":       <number>
    }
  ],
  "subtotal":       <number or null>,
  "tax":            <number or null>,
  "total_amount":   <number>,
  "currency":       "<3-letter ISO code, e.g. USD>",
  "payment_terms":  "<string or null>",
  "notes":          "<string or null>"
}

Return ONLY the raw JSON — no markdown fences, no commentary."""


def extract_with_ai(text: str, model: str = "claude-3-5-haiku-20241022") -> dict[str, Any]:
    """Use Claude to extract structured data from raw invoice text."""
    try:
        import anthropic
    except ImportError:
        raise ImportError("Run:  pip install anthropic")

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError("Set ANTHROPIC_API_KEY environment variable to use AI extraction.")

    client = anthropic.Anthropic(api_key=api_key)
    message = client.messages.create(
        model=model,
        max_tokens=2048,
        system=EXTRACTION_PROMPT,
        messages=[{"role": "user", "content": f"Invoice text:\n\n{text}"}],
    )
    raw = message.content[0].text.strip()
    return json.loads(raw)


# ── Rule-based extraction helpers ─────────────────────────────────────────────

def _find(pattern: str, text: str, group: int = 1, flags: int = re.IGNORECASE) -> str | None:
    m = re.search(pattern, text, flags)
    return m.group(group).strip() if m else None


def _parse_amount(value: str | None) -> float | None:
    if value is None:
        return None
    cleaned = re.sub(r"[^\d.]", "", value)
    try:
        return float(cleaned)
    except ValueError:
        return None


def extract_with_rules(text: str) -> dict[str, Any]:
    """
    Lightweight rule-based extraction using regular expressions.
    Works well for standard, text-based invoice PDFs.
    """
    # Common date formats: 2024-12-31 / 31/12/2024 / December 31, 2024
    date_re = r"(\d{4}-\d{2}-\d{2}|\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}|[A-Z][a-z]+ \d{1,2},? \d{4})"

    invoice_number = _find(r"invoice\s*(?:#|no\.?|number)\s*:?\s*([A-Z0-9][A-Z0-9\-]{2,})", text)
    invoice_date_raw = _find(rf"invoice\s+date\s*:?\s*{date_re}", text)
    due_date_raw = _find(rf"due\s+date\s*:?\s*{date_re}", text)
    total_raw = _find(r"(?:total\s+amount|amount\s+due|total)\s*:?\s*\$?([\d,]+\.?\d*)", text)
    subtotal_raw = _find(r"subtotal\s*:?\s*\$?([\d,]+\.?\d*)", text)
    tax_raw = _find(r"\b(?:tax|gst|vat|hst)\b[^:$\n]*:?\s*\$?([\d,]+\.?\d*)", text)

    # Naïve vendor — first non-empty line is often the vendor name
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    vendor_name = lines[0] if lines else None

    # Currency detection
    currency = "USD"
    if "£" in text or "GBP" in text:
        currency = "GBP"
    elif "€" in text or "EUR" in text:
        currency = "EUR"
    elif "CAD" in text:
        currency = "CAD"

    return {
        "vendor_name": vendor_name,
        "vendor_address": None,
        "vendor_email": _find(r"([\w.+-]+@[\w-]+\.[a-zA-Z]+)", text),
        "vendor_phone": _find(r"(\+?1?[-.\s]?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4})", text),
        "invoice_number": invoice_number,
        "invoice_date": invoice_date_raw,
        "due_date": due_date_raw,
        "line_items": [],
        "subtotal": _parse_amount(subtotal_raw),
        "tax": _parse_amount(tax_raw),
        "total_amount": _parse_amount(total_raw),
        "currency": currency,
        "payment_terms": _find(r"payment\s+terms?\s*:?\s*([^\n]+)", text),
        "notes": None,
    }


# ── PDF text extraction ───────────────────────────────────────────────────────

def extract_text_from_pdf(pdf_path: str) -> str:
    """Extract all text from a PDF using pdfplumber."""
    text_parts: list[str] = []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            page_text = page.extract_text()
            if page_text:
                text_parts.append(page_text)
    return "\n\n".join(text_parts)


# ── Main processing function ──────────────────────────────────────────────────

def process_invoice(pdf_path: str, use_ai: bool = False) -> dict[str, Any]:
    """
    Process a PDF invoice and return extracted structured data.

    Parameters
    ----------
    pdf_path : str
        Path to the PDF invoice file.
    use_ai : bool
        If True, use Claude for extraction (requires ANTHROPIC_API_KEY).

    Returns
    -------
    dict
        Structured invoice data.
    """
    path = Path(pdf_path)
    if not path.exists():
        raise FileNotFoundError(f"Invoice file not found: {pdf_path}")
    if path.suffix.lower() != ".pdf":
        raise ValueError(f"Expected a .pdf file, got: {path.suffix}")

    print(f"📄  Extracting text from {path.name} ...", end="", flush=True)
    raw_text = extract_text_from_pdf(pdf_path)
    print(f" {len(raw_text)} characters extracted.")

    if not raw_text.strip():
        raise ValueError(
            "No text found in PDF. This may be a scanned (image-only) PDF. "
            "Use --ai mode with ANTHROPIC_API_KEY for OCR-based extraction."
        )

    if use_ai:
        print("🤖  Running AI extraction with Claude ...", end="", flush=True)
        data = extract_with_ai(raw_text)
        print(" done.")
    else:
        print("⚙️   Running rule-based extraction ...", end="", flush=True)
        data = extract_with_rules(raw_text)
        print(" done.")

    data["_meta"] = {
        "source_file": path.name,
        "extraction_method": "ai" if use_ai else "rules",
        "processed_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "raw_character_count": len(raw_text),
    }

    return data


def _create_sample_pdf() -> str:
    """
    Create a minimal sample invoice PDF for demonstration when no file is provided.
    Returns the file path.
    """
    sample_path = Path("/tmp/sample_invoice.pdf")
    sample_text = (
        "AutomateIQ Solutions LLC\n"
        "123 Innovation Drive, San Francisco, CA 94105\n"
        "billing@automateiq.io  |  +1 (415) 555-0192\n\n"
        "INVOICE\n\n"
        "Invoice #: INV-2025-0042\n"
        "Invoice Date: 2025-03-15\n"
        "Due Date: 2025-04-14\n"
        "Payment Terms: Net 30\n\n"
        "Bill To:\n"
        "TechScale Inc.\n"
        "456 Market Street, Suite 800\n"
        "San Francisco, CA 94105\n\n"
        "Description                          Qty   Unit Price    Total\n"
        "-----------------------------------------------------------\n"
        "AI Lead Qualifier Setup                1    $2,500.00   $2,500.00\n"
        "Monthly Automation Retainer            1    $1,200.00   $1,200.00\n"
        "Custom CRM Integration                 1      $800.00     $800.00\n\n"
        "Subtotal: $4,500.00\n"
        "Tax (8.5%): $382.50\n"
        "Total Amount: $4,882.50\n\n"
        "Notes: Thank you for your business! Please remit payment via ACH or wire."
    )

    # Use reportlab if available, otherwise write a raw minimal PDF
    try:
        from reportlab.lib.pagesizes import letter
        from reportlab.pdfgen import canvas as rl_canvas

        c = rl_canvas.Canvas(str(sample_path), pagesize=letter)
        c.setFont("Helvetica", 10)
        y = 720
        for line in sample_text.splitlines():
            c.drawString(50, y, line)
            y -= 14
        c.save()
    except ImportError:
        # Write a bare-bones but valid PDF with embedded text
        pdf_bytes = _minimal_pdf(sample_text)
        sample_path.write_bytes(pdf_bytes)

    return str(sample_path)


def _minimal_pdf(text: str) -> bytes:
    """Generate a minimal but standards-compliant single-page PDF containing `text`."""
    escaped = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    lines = escaped.splitlines()
    stream_lines = ["BT", "/F1 10 Tf", "50 750 Td", "12 TL"]
    for line in lines:
        stream_lines.append(f"({line}) Tj T*")
    stream_lines.append("ET")
    stream = "\n".join(stream_lines)
    stream_bytes = stream.encode("latin-1", errors="replace")

    objects: list[bytes] = []

    def obj(n: int, content: str) -> bytes:
        return f"{n} 0 obj\n{content}\nendobj\n".encode()

    objects.append(obj(1, "<< /Type /Catalog /Pages 2 0 R >>"))
    objects.append(obj(2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"))
    objects.append(obj(3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>"))
    objects.append(obj(4, f"<< /Length {len(stream_bytes)} >>\nstream\n".encode() + stream_bytes + b"\nendstream"))
    objects.append(obj(5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"))

    header = b"%PDF-1.4\n"
    body = b"".join(objects)
    xref_offset = len(header) + len(body)
    xref = (
        f"xref\n0 6\n0000000000 65535 f \n"
        + "".join(
            f"{len(header) + sum(len(o) for o in objects[:i]):010d} 00000 n \n"
            for i in range(len(objects))
        )
    ).encode()
    trailer = f"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref_offset + len(xref)}\n%%EOF\n".encode()
    return header + body + xref + trailer


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="AutomateIQ Invoice Processor — Extract structured data from PDF invoices.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "pdf_file",
        nargs="?",
        help="Path to the PDF invoice (omit to use a generated sample).",
    )
    parser.add_argument(
        "--ai",
        action="store_true",
        help="Use Claude AI for extraction instead of rule-based parsing.",
    )
    parser.add_argument(
        "--output",
        "-o",
        metavar="FILE",
        help="Write extracted JSON to this file (default: print to stdout).",
    )
    args = parser.parse_args()

    print("\n🧾  AutomateIQ — Invoice Processor Demo\n")

    pdf_path = args.pdf_file
    if not pdf_path:
        print("No PDF supplied — generating sample invoice …")
        pdf_path = _create_sample_pdf()
        print(f"Sample invoice created at: {pdf_path}\n")

    try:
        result = process_invoice(pdf_path, use_ai=args.ai)
    except (FileNotFoundError, ValueError) as exc:
        print(f"\n❌  Error: {exc}")
        sys.exit(1)

    output_json = json.dumps(result, indent=2, ensure_ascii=False)

    if args.output:
        Path(args.output).write_text(output_json, encoding="utf-8")
        print(f"\n✅  Extracted data written to: {args.output}")
    else:
        print("\n📊  Extracted Invoice Data:\n")
        print(output_json)

    print(
        f"\n✅  Done.  Total: {result.get('total_amount')} {result.get('currency')}  |  "
        f"Invoice #{result.get('invoice_number')}\n"
    )


if __name__ == "__main__":
    main()
