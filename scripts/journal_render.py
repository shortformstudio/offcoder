#!/usr/bin/env python3
"""
Offcoder journal renderer — designed A4 folios and generative plates via reportlab.
Reads a JSON spec, writes a PDF. Used by journal.mcp.

Spec:
  {
    "mode": "folio" | "plate",
    "title": "...", "subtitle": "...", "meta": "...",
    "markdown": "...", "caption": "...", "seed": "...",
    "out_path": "/path/to.pdf"
  }
"""

import argparse
import hashlib
import json
import math
import random
import re
import sys
from pathlib import Path

from reportlab.lib.colors import HexColor, Color
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle,
    XPreformatted, KeepTogether,
)

FIELD = HexColor("#e8e6df")
SHEET = HexColor("#FCFCFC")
INK = HexColor("#111111")
BODY = HexColor("#333333")
MUTED = HexColor("#777777")
FAINT = HexColor("#AAAAAA")
RULE = HexColor("#EAEAEA")
CODE_BG = HexColor("#F4F3EF")
GOLD = HexColor("#c9a45c")
ALCHEMY = ["#E6D0CE", "#D4DFD8", "#C4C9D6", "#E8D5B5"]

FONT_DIR = Path.home() / ".offcoder" / "fonts"
AVENIR_TTC = "/System/Library/Fonts/Avenir Next.ttc"
MENLO_TTC = "/System/Library/Fonts/Menlo.ttc"
AVENIR_SUBFONTS = {
    "AvenirNext-UltraLight": ("Avenir Next Ultra Light", 10),
    "AvenirNext-Regular": ("Avenir Next Regular", 7),
    "AvenirNext-Medium": ("Avenir Next Medium", 5),
    "AvenirNext-DemiBold": ("Avenir Next Demi Bold", 2),
    "AvenirNext-Bold": ("Avenir Next Bold", 0),
}
MENLO_SUBFONT = ("Menlo Regular", 0)


def extract_fonts():
    """Extract Avenir Next + Menlo from system TTCs once into ~/.offcoder/fonts."""
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    registered = {}
    try:
        from fontTools.ttLib import TTCollection
    except ImportError:
        return registered

    def extract(ttc_path, subfonts, kind):
        out = {}
        try:
            collection = TTCollection(ttc_path, lazy=True)
        except Exception:
            return out
        for name, (full_name, index) in subfonts.items():
            target = FONT_DIR / f"{name}.ttf"
            if not target.exists():
                try:
                    font = collection.fonts[index]
                    font.save(str(target))
                except Exception:
                    continue
            if target.exists():
                try:
                    pdfmetrics.registerFont(TTFont(name, str(target)))
                    out[kind] = name
                except Exception:
                    pass
        return out

    avenir = extract(AVENIR_TTC, AVENIR_SUBFONTS, "ultra")
    for name in AVENIR_SUBFONTS:
        target = FONT_DIR / f"{name}.ttf"
        if target.exists():
            try:
                pdfmetrics.registerFont(TTFont(name, str(target)))
            except Exception:
                pass
    menlo = extract(MENLO_TTC, {"Menlo": MENLO_SUBFONT}, "mono")

    if "ultra" not in avenir:
        avenir["ultra"] = "Helvetica"
        avenir["regular"] = "Helvetica"
        avenir["medium"] = "Helvetica"
        avenir["bold"] = "Helvetica-Bold"
    else:
        avenir.setdefault("regular", avenir["ultra"])
        avenir.setdefault("medium", avenir["ultra"])
        avenir.setdefault("bold", avenir["ultra"])
    avenir.setdefault("mono", menlo.get("mono", "Courier"))
    return avenir


FONTS = extract_fonts()
F_ULTRA = FONTS.get("ultra", "Helvetica")
F_REG = FONTS.get("regular", F_ULTRA)
F_MED = FONTS.get("medium", F_ULTRA)
F_BOLD = FONTS.get("bold", F_ULTRA)
F_MONO = FONTS.get("mono", "Courier")


# ---------------------------------------------------------------- mandala

def draw_mandala(canvas, cx, cy, size, seed_text):
    rng = random.Random(int(hashlib.sha256(str(seed_text).encode()).hexdigest()[:12], 16))
    rings = 3 + rng.randrange(3)
    canvas.saveState()
    for r in range(rings):
        radius = (size / 2) * (0.24 + 0.24 * r)
        color = HexColor(ALCHEMY[r % len(ALCHEMY)])
        canvas.setStrokeColor(color)
        canvas.setLineWidth(0.9)
        canvas.circle(cx, cy, radius, stroke=1, fill=0)
        petals = 6 + rng.randrange(10)
        for p in range(petals):
            angle = (p / petals) * math.tau + rng.random() * 0.12
            x1 = cx + math.cos(angle) * radius
            y1 = cy + math.sin(angle) * radius
            reach = radius + 6 + rng.random() * 12
            x2 = cx + math.cos(angle) * reach
            y2 = cy + math.sin(angle) * reach
            canvas.setStrokeColor(color)
            canvas.setLineWidth(0.7)
            canvas.line(x1, y1, x2, y2)
            if rng.random() > 0.55:
                canvas.setFillColor(GOLD)
                canvas.circle(x2, y2, 1 + rng.random() * 2, stroke=0, fill=1)
    spokes = 12 + rng.randrange(18)
    for s in range(spokes):
        angle = (s / spokes) * math.tau
        inner = size * 0.16
        outer = size * (0.46 + rng.random() * 0.03)
        canvas.setStrokeColor(GOLD)
        canvas.setLineWidth(0.55)
        canvas.line(cx + math.cos(angle) * inner, cy + math.sin(angle) * inner,
                    cx + math.cos(angle) * outer, cy + math.sin(angle) * outer)
    canvas.setFillColor(GOLD)
    canvas.circle(cx, cy, 4 + rng.random() * 5, stroke=0, fill=1)
    canvas.restoreState()


def draw_page_chrome(canvas, doc):
    width, height = doc.pagesize
    canvas.saveState()
    canvas.setFillColor(FIELD)
    canvas.rect(0, 0, width, height, stroke=0, fill=1)
    canvas.setFillColor(SHEET)
    inset = 24
    canvas.rect(inset, inset, width - 2 * inset, height - 2 * inset, stroke=0, fill=1)

    if doc.page == 1:
        bar_x = 60
        bar_y = height - 78
        bar_w = width - 120
        steps = 96
        for i in range(steps):
            ratio = i / (steps - 1)
            segment = ratio * (len(ALCHEMY) - 1)
            low = min(int(segment), len(ALCHEMY) - 2)
            blend = segment - low
            c1 = HexColor(ALCHEMY[low])
            c2 = HexColor(ALCHEMY[low + 1])
            color = Color(c1.red + (c2.red - c1.red) * blend,
                          c1.green + (c2.green - c1.green) * blend,
                          c1.blue + (c2.blue - c1.blue) * blend)
            canvas.setFillColor(color)
            canvas.rect(bar_x + (bar_w / steps) * i, bar_y, bar_w / steps + 0.6, 2.4, stroke=0, fill=1)

    canvas.setFillColor(FAINT)
    canvas.setFont(F_REG, 6.5)
    canvas.drawCentredString(width / 2, 38, "c e r t i f i e d   —   o f f c o d e r   j o u r n a l   —   t h e   p o n d   r e m e m b e r s")
    canvas.restoreState()


# ---------------------------------------------------------------- markdown

def inline(text):
    out = (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
    out = re.sub(r"`([^`]+)`", r'<font face="%s" size="8.5" color="#444444">\1</font>' % F_MONO, out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", out)
    out = re.sub(r"\*([^*]+)\*", r"<i>\1</i>", out)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<link href="\2" color="#111111"><u>\1</u></link>', out)
    return out


def styles():
    return {
        "h1": ParagraphStyle("h1", fontName=F_ULTRA, fontSize=20, leading=25, textColor=INK, spaceBefore=20, spaceAfter=9),
        "h2": ParagraphStyle("h2", fontName=F_MED, fontSize=13, leading=17, textColor=INK, spaceBefore=16, spaceAfter=7),
        "h3": ParagraphStyle("h3", fontName=F_MED, fontSize=10, leading=13, textColor=HexColor("#555555"), spaceBefore=13, spaceAfter=5),
        "h4": ParagraphStyle("h4", fontName=F_REG, fontSize=9.5, leading=12, textColor=HexColor("#666666"), spaceBefore=10, spaceAfter=4),
        "p": ParagraphStyle("p", fontName=F_REG, fontSize=10, leading=15.5, textColor=BODY, spaceAfter=8),
        "li": ParagraphStyle("li", fontName=F_REG, fontSize=10, leading=15, textColor=BODY, leftIndent=14, bulletIndent=4, spaceAfter=4),
        "quote": ParagraphStyle("quote", fontName=F_ULTRA, fontSize=11, leading=16, textColor=HexColor("#555555"), spaceAfter=10),
        "code": ParagraphStyle("code", fontName=F_MONO, fontSize=8, leading=11.5, textColor=HexColor("#333333")),
    }


def markdown_blocks(markdown, st):
    flow = []
    lines = (markdown or "").split("\n")
    in_code = False
    code_lines = []
    list_mode = None

    def flush_code():
        nonlocal code_lines, in_code
        if code_lines:
            pre = XPreformatted("\n".join(code_lines), st["code"])
            table = Table([[pre]], colWidths=[460])
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, -1), CODE_BG),
                ("LINEBEFORE", (0, 0), (0, -1), 2, HexColor("#DDDDDD")),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]))
            flow.append(KeepTogether(table))
            flow.append(Spacer(1, 10))
        code_lines = []
        in_code = False

    for line in lines:
        fence = re.match(r"^```(\w*)\s*$", line)
        if fence:
            if in_code:
                flush_code()
            else:
                in_code = True
                code_lines = []
            continue
        if in_code:
            code_lines.append(line)
            continue

        if not line.strip():
            list_mode = None
            continue

        heading = re.match(r"^(#{1,4})\s+(.*)$", line)
        if heading:
            flow.append(Paragraph(inline(heading.group(2)), st[f"h{len(heading.group(1))}"]))
            continue
        if re.match(r"^(-{3,}|\*{3,})\s*$", line):
            flow.append(Spacer(1, 6))
            rule = Table([[""]], colWidths=[460], rowHeights=[1])
            rule.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), RULE)]))
            flow.append(rule)
            flow.append(Spacer(1, 10))
            continue
        if line.lstrip().startswith(">"):
            content = inline(line.lstrip()[1:].strip())
            quote = Table([[Paragraph(content, st["quote"])]], colWidths=[460])
            quote.setStyle(TableStyle([
                ("LINEBEFORE", (0, 0), (0, -1), 2, GOLD),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
            ]))
            flow.append(KeepTogether(quote))
            flow.append(Spacer(1, 8))
            continue
        bullet = re.match(r"^\s*[-*]\s+(.*)$", line)
        if bullet:
            list_mode = "ul"
            flow.append(Paragraph(inline(bullet.group(1)), st["li"], bulletText="•"))
            continue
        numbered = re.match(r"^\s*(\d+)[.)]\s+(.*)$", line)
        if numbered:
            list_mode = "ol"
            flow.append(Paragraph(inline(numbered.group(2)), st["li"], bulletText=f"{numbered.group(1)}."))
            continue
        flow.append(Paragraph(inline(line), st["p"]))

    if in_code:
        flush_code()
    return flow


# ---------------------------------------------------------------- build

class JournalDoc(BaseDocTemplate):
    def __init__(self, path, **kwargs):
        super().__init__(path, pagesize=(595.27, 841.89), **kwargs)
        frame = Frame(60, 64, 475, 690, leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
        self.addPageTemplates([PageTemplate(id="folio", frames=[frame], onPage=draw_page_chrome)])


def build(spec):
    out_path = Path(spec["out_path"])
    out_path.parent.mkdir(parents=True, exist_ok=True)
    mode = spec.get("mode", "folio")
    st = styles()

    story = []
    story.append(Spacer(1, 6))
    title_style = ParagraphStyle("title", fontName=F_ULTRA, fontSize=30, leading=36, textColor=INK)
    story.append(Paragraph(inline(spec.get("title", "untitled folio")).lower(), title_style))
    story.append(Spacer(1, 4))
    if spec.get("subtitle"):
        story.append(Paragraph(inline(spec["subtitle"]).lower(),
                               ParagraphStyle("sub", fontName=F_REG, fontSize=8.5, leading=12, textColor=MUTED)))
    story.append(Spacer(1, 8))
    meta = spec.get("meta") or ""
    story.append(Paragraph(" ".join(meta.upper()),
                           ParagraphStyle("meta", fontName=F_REG, fontSize=7, leading=10, textColor=FAINT)))

    story.append(Spacer(1, 10))
    ornament_seed = spec.get("seed") or spec.get("title", "offcoder")
    ornament_size = 240 if mode == "folio" else 420
    story.append(Ornament(ornament_seed, ornament_size))
    story.append(Spacer(1, 14))

    if mode == "plate":
        if spec.get("caption"):
            story.append(Paragraph(inline(spec["caption"]), st["p"]))
    else:
        story.extend(markdown_blocks(spec.get("markdown", ""), st))

    doc = JournalDoc(str(out_path))
    doc.build(story)
    return out_path


class Ornament(Spacer):
    """A flowable that draws the seeded mandala plate."""

    def __init__(self, seed, size):
        super().__init__(475, size)
        self.seed = seed
        self.size = size

    def draw(self):
        canvas = self.canv
        cx = self.width / 2
        cy = self.size / 2
        draw_mandala(canvas, cx, cy, self.size * 0.92, self.seed)


def main():
    parser = argparse.ArgumentParser(description="Offcoder journal renderer")
    parser.add_argument("--spec", required=True, help="path to JSON spec")
    args = parser.parse_args()

    spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    out = build(spec)
    print(json.dumps({"ok": True, "pdf_path": str(out), "bytes": out.stat().st_size}))


if __name__ == "__main__":
    main()
