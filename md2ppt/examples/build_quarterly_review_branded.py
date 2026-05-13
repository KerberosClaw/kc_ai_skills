#!/usr/bin/env python3
"""md2ppt — example branded build script (abstract content, abstract template).

Reference for what a brand-mode build script looks like. Subject and template
path are both placeholders to demonstrate the pattern without leaking any
real-world brand asset.

To run, set MD2PPT_BRAND_TEMPLATE env var to a real template path:

    MD2PPT_BRAND_TEMPLATE=/path/to/your-brand.pptx \\
        ~/.venv_pptx/bin/python build_quarterly_review_branded.py

Output:
    quarterly_review_branded.pptx (in current dir)

Differences from build_quarterly_review.py (content version):
- Uses init_deck_from_template() instead of init_deck()
- Cover slide uses template's title-slide layout (placeholder fill)
- Q&A slide uses template's title-slide layout
- All content slides still hand-coded with add_blank_slide for layout freedom
- Theme (colors / fonts / logo / chrome) inherited from template
"""

import os
import sys
from pathlib import Path

# Adjust this path to wherever the skill helpers live (symlinked into ~/.claude/skills/)
sys.path.insert(0, str(Path.home() / ".claude/skills/md2ppt/scripts"))

from pptx_helpers import (
    init_deck_from_template, add_blank_slide,
    add_cover_from_template, add_section_divider_from_template,
    add_textbox, add_title_bar, add_bullets, add_table, add_log_bar, save,
    Inches, Pt, PP_ALIGN,
    COLOR_TITLE, COLOR_TEXT, COLOR_ACCENT, COLOR_OK, COLOR_BAR, COLOR_MUTED,
)

# ============================================================
# Brand template path — env var with relative-path fallback for portability
# ============================================================
TEMPLATE_PATH = os.environ.get(
    "MD2PPT_BRAND_TEMPLATE",
    "<your-brand-template.pptx>"  # placeholder — replace per project
)

prs = init_deck_from_template(TEMPLATE_PATH)


# ============================================================
# Slide 1 — Cover (template's title-slide layout)
# ============================================================
add_cover_from_template(
    prs,
    layout_name="標題投影片",   # adjust per template's layout naming
    title="Q4 Product Metrics Review",
    subtitle="Adoption + Reliability + Roadmap Signals",
)


# ============================================================
# Slide 2 — Headline (blank layout, hand-coded for content freedom)
# ============================================================
s = add_blank_slide(prs)
add_title_bar(s, "Headline", "Three signals to act on this quarter")

add_bullets(s, Inches(0.8), Inches(2.0), Inches(12.0), Inches(2.5), [
    "Active users grew 38% QoQ; activation rate flat — onboarding is the choke point",
    "p95 API latency drifted from 180ms to 420ms after the v3 deploy — not regressed yet",
    "Customer support tickets dominated by a single feature gap (export to CSV)",
], size=20)

add_textbox(s, Inches(0.6), Inches(5.5), Inches(12.1), Inches(1.5),
            "Recommendation: ship CSV export + invest one cycle in onboarding redesign\nbefore opening top-of-funnel further.",
            size=18, bold=True, color=COLOR_ACCENT, line_spacing=1.4)


# ============================================================
# Slide 3 — Adoption table
# ============================================================
s = add_blank_slide(prs)
add_title_bar(s, "Adoption Metrics", "QoQ comparison, signed-up vs activated")

add_table(s, Inches(0.5), Inches(1.9), Inches(12.3), Inches(3.8), [
    ["Metric",            "Q3",       "Q4",       "Delta"],
    ["Sign-ups",          "12,400",   "17,100",   "+38%"],
    ["Activated (D7)",    "4,090",    "5,300",    "+30%"],
    ["Activation rate",   "33.0%",    "31.0%",    "-2 pp"],
    ["WAU peak",          "8,250",    "11,400",   "+38%"],
    ["DAU/MAU",           "27%",      "26%",      "-1 pp"],
], font_size=14, col_widths=[Inches(3.5), Inches(2.8), Inches(2.8), Inches(3.2)])


# ============================================================
# Slide 4 — Throughput bar comparison
# ============================================================
s = add_blank_slide(prs)
add_title_bar(s, "API Throughput by Endpoint", "p50 RPS — log scale visualization")

add_textbox(s, Inches(0.6), Inches(1.9), Inches(12.0), Inches(0.5),
            "Higher = better. Search dominates traffic; export is rarely used.",
            size=14, color=COLOR_MUTED)

bars = [
    ("/search",       8500, "8,500 rps", COLOR_OK),
    ("/list",         3200, "3,200 rps", COLOR_OK),
    ("/detail",       1800, "1,800 rps", COLOR_BAR),
    ("/upload",        420, "420 rps",   COLOR_BAR),
    ("/export-csv",     12, "12 rps",    COLOR_ACCENT),
]
top0 = Inches(2.6)
gap = Inches(0.85)
for i, (label, val, val_lbl, color) in enumerate(bars):
    add_log_bar(s, label, val, val_lbl, top=top0 + gap * i, color=color, max_kbps=20000)


# ============================================================
# Slide 5 — Section divider (template layout)
# ============================================================
add_section_divider_from_template(
    prs,
    layout_name="章節標題",
    title="Next Cycle Focus",
)


# ============================================================
# Slide 6 — Roadmap focus
# ============================================================
s = add_blank_slide(prs)
add_title_bar(s, "Next Cycle Focus", "Two bets, one validation")

add_table(s, Inches(0.4), Inches(1.8), Inches(12.5), Inches(4.0), [
    ["#", "Bet",                              "Why now",                      "Owner"],
    ["1", "CSV export GA",                    "Top support volume",           "Backend + FE"],
    ["2", "Onboarding redesign A/B",          "Activation flat 2 quarters",   "Growth team"],
    ["3", "Latency drift root cause",         "p95 trending 2x worse",        "SRE"],
], font_size=15, col_widths=[Inches(0.7), Inches(4.5), Inches(4.0), Inches(3.3)])

add_textbox(s, Inches(0.6), Inches(6.3), Inches(12.1), Inches(0.6),
            "Bets 1 and 2 ship; bet 3 is investigation only — no commitments until root cause known.",
            size=14, color=COLOR_MUTED)


# ============================================================
# Slide 7 — Q&A (template's title-slide variant)
# ============================================================
add_cover_from_template(
    prs,
    layout_name="3_標題投影片",   # adjust per template
    title="Discussion",
    subtitle="Q&A / commit owner sign-off",
)


# ============================================================
save(prs, "quarterly_review_branded.pptx")
