#!/usr/bin/env python3
"""Build classifier-rate-limits-2026-09.html from data.json.

Static page: prose + two inline SVG charts (drawn here, colours from the house
tokens in lib/plotting/tokens.json) + one mermaid diagram the Artifact viewer
renders natively. md2artifact cannot carry SVG (it parses with html off), so
this page is built directly and gets its annotation layer from annotate-html:

    python3 build.py
    annotate-html classifier-rate-limits-2026-09.html --key review-classifier-rate-limits-2026-09

Every number on the page comes from data.json, which is a transcription of
data-snapshot-2026-09-10.md (the measured inputs; the transcripts they were
measured from move on, so the snapshot is the record).
"""

from __future__ import annotations

import html
import json
import math
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = json.loads((HERE / "data.json").read_text())
OUT = HERE / "classifier-rate-limits-2026-09.html"

# House tokens (lib/plotting/tokens.json): ink #141413, ivory #FAF9F5,
# emphasis #D97757. The gateway-off blue is the "brand" cycle blue #40668C
# nudged to #3B6FA6 so the pair passes the dataviz palette validator in light
# mode; the dark pair #D0693F / #3F7FC4 passes against the dark surface.
LIGHT = {
    "ground": "#FAF9F5", "panel": "#FFFFFF", "ink": "#141413", "muted": "#6B6963",
    "hair": "#E6E2D8", "hair2": "#F0EDE6", "on": "#D97757", "off": "#3B6FA6",
    "on_wash": "rgba(217,119,87,0.10)", "code": "#F2EFE8", "mark": "#FBE6A2",
}
DARK = {
    "ground": "#1C1B19", "panel": "#242320", "ink": "#ECE9E2", "muted": "#A39F95",
    "hair": "#35332F", "hair2": "#2B2A26", "on": "#D0693F", "off": "#3F7FC4",
    "on_wash": "rgba(208,105,63,0.14)", "code": "#2A2926", "mark": "#5C4A15",
}


def esc(s: object) -> str:
    return html.escape(str(s), quote=True)


def wilson(k: int, n: int, z: float = 1.96) -> tuple[float, float]:
    """95% Wilson score interval for k/n, as fractions."""
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def fmt_int(n: int) -> str:
    return f"{n:,}"


def tokens_css(t: dict[str, str]) -> str:
    return "".join(f"--{k.replace('_', '-')}:{v};" for k, v in t.items())


# --------------------------------------------------------------------------
# Chart 1: failures per 100 bound calls by day, with an exposure strip.
# --------------------------------------------------------------------------
def chart_by_day() -> str:
    rows = {r["day"]: r for r in DATA["by_day"]}
    d0 = date.fromisoformat("2026-08-19")
    d1 = date.fromisoformat("2026-09-09")
    days = [d0 + timedelta(days=i) for i in range((d1 - d0).days + 1)]
    W, ML, MR = 680, 40, 14
    TOP = 34            # room for the period and event labels
    H1 = 170            # rate panel
    GAP = 34            # between panels (holds the exposure panel's title)
    H2 = 64             # exposure panel
    BOT = 40            # date axis
    H = TOP + H1 + GAP + H2 + BOT
    slot = (W - ML - MR) / len(days)
    bar = 16
    ymax1, ymax2 = 30.0, 4000.0
    p1_top, p1_base = TOP, TOP + H1
    p2_top, p2_base = TOP + H1 + GAP, TOP + H1 + GAP + H2

    def x_of(d: date) -> float:
        return ML + (d - d0).days * slot

    def y1(v: float) -> float:
        return p1_base - v / ymax1 * H1

    def y2(v: float) -> float:
        return p2_base - v / ymax2 * H2

    out: list[str] = []
    out.append(
        f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" '
        f'aria-labelledby="c1-title c1-desc" xmlns="http://www.w3.org/2000/svg">'
    )
    out.append('<title id="c1-title">Classifier failures per 100 bound calls by day, 19 Aug to 9 Sep 2026</title>')
    out.append(
        '<desc id="c1-desc">Zero failures on every day the gateway was off; 8.1, 2.3, 16.2 and 25.5 per 100 '
        'on the four days after it was rewired on 6 Sep. The lower strip shows bound calls per day.</desc>'
    )
    # gateway-on wash spanning both panels
    x_on = x_of(date.fromisoformat("2026-09-06"))
    out.append(f'<rect x="{x_on:.1f}" y="{p1_top - 4}" width="{W - MR - x_on:.1f}" height="{p2_base - p1_top + 4}" fill="var(--on-wash)"/>')
    out.append(f'<text x="{ML}" y="12" class="lbl muted">gateway off</text>')
    out.append(f'<text x="{W - MR}" y="12" class="lbl muted" text-anchor="end">gateway on</text>')
    # gridlines + ticks, panel 1
    for v in (0, 10, 20, 30):
        y = y1(v)
        out.append(f'<line x1="{ML}" x2="{W - MR}" y1="{y:.1f}" y2="{y:.1f}" class="grid"/>')
        out.append(f'<text x="{ML - 6}" y="{y + 3.5:.1f}" class="tick" text-anchor="end">{v}</text>')
    out.append(f'<text x="{ML}" y="26" class="lbl muted">failures per 100 bound calls (lower is better)</text>')
    # gridlines + ticks, panel 2
    for v, lab in ((0, "0"), (2000, "2k"), (4000, "4k")):
        y = y2(v)
        out.append(f'<line x1="{ML}" x2="{W - MR}" y1="{y:.1f}" y2="{y:.1f}" class="grid"/>')
        out.append(f'<text x="{ML - 6}" y="{y + 3.5:.1f}" class="tick" text-anchor="end">{lab}</text>')
    out.append(f'<text x="{ML}" y="{p2_top - 8}" class="lbl muted">bound calls per day (exposure; the 0 above means less on a 23-call day than on a 3,998-call day)</text>')
    # bars
    for d in days:
        r = rows.get(d.isoformat())
        cx = x_of(d) + slot / 2
        if r is None:
            out.append(f'<g><title>{d.strftime("%-d %b")}: no bound calls recorded</title>'
                       f'<text x="{cx:.1f}" y="{p2_base - 4}" class="tick muted" text-anchor="middle">&#8211;</text></g>')
            continue
        col = "var(--on)" if r["gateway"] == "on" else "var(--off)"
        rate = 100 * r["failures"] / r["bound"]
        tip = (f'{d.strftime("%-d %b")}: {fmt_int(r["failures"])} failures / {fmt_int(r["bound"])} bound calls'
               f' = {rate:.1f} per 100; CLI {r["cli"]}; gateway {r["gateway"]}')
        out.append('<g class="hit">')
        out.append(f'<title>{esc(tip)}</title>')
        out.append(f'<rect x="{x_of(d):.1f}" y="{p1_top - 4}" width="{slot:.1f}" height="{p2_base - p1_top + 4}" fill="transparent"/>')
        if r["failures"] == 0:
            out.append(f'<circle cx="{cx:.1f}" cy="{p1_base - 3:.1f}" r="3" fill="{col}"/>')
        else:
            top = y1(rate)
            out.append(f'<rect x="{cx - bar / 2:.1f}" y="{top:.1f}" width="{bar}" height="{p1_base - top:.1f}" rx="3" fill="{col}"/>')
            out.append(f'<rect x="{cx - bar / 2:.1f}" y="{p1_base - 3:.1f}" width="{bar}" height="3" fill="{col}"/>')
            out.append(f'<text x="{cx:.1f}" y="{top - 5:.1f}" class="val" text-anchor="middle">{rate:.1f}</text>')
        top2 = y2(r["bound"])
        out.append(f'<rect x="{cx - bar / 2:.1f}" y="{top2:.1f}" width="{bar}" height="{max(1.0, p2_base - top2):.1f}" fill="var(--muted)" opacity="0.45"/>')
        out.append("</g>")
    # event markers
    ev = {e["day"]: e["label"] for e in DATA["events"]}
    x3 = x_of(date.fromisoformat("2026-09-03")) + slot / 2
    out.append(f'<line x1="{x3:.1f}" x2="{x3:.1f}" y1="{p1_top - 4}" y2="{p1_base}" class="event"/>')
    out.append(f'<text x="{x3 - 5:.1f}" y="{p1_top + 4}" class="lbl" text-anchor="end">3 Sep: {esc(ev["2026-09-03"])}</text>')
    out.append(f'<line x1="{x_on:.1f}" x2="{x_on:.1f}" y1="{p1_top - 4}" y2="{p1_base}" class="event"/>')
    out.append(f'<text x="{x_on + 5:.1f}" y="{p1_top + 4}" class="lbl" text-anchor="start">6 Sep: {esc(ev["2026-09-06"])}</text>')
    # baselines
    out.append(f'<line x1="{ML}" x2="{W - MR}" y1="{p1_base}" y2="{p1_base}" class="axis"/>')
    out.append(f'<line x1="{ML}" x2="{W - MR}" y1="{p2_base}" y2="{p2_base}" class="axis"/>')
    # date axis: every other day, month row
    for d in days:
        cx = x_of(d) + slot / 2
        if d.day % 2 == 1 or d == d1:
            out.append(f'<text x="{cx:.1f}" y="{p2_base + 14}" class="tick" text-anchor="middle">{d.day}</text>')
        if d.day == 1 or d == d0:
            out.append(f'<text x="{x_of(d):.1f}" y="{p2_base + 30}" class="lbl muted">{d.strftime("%b")}</text>')
    out.append("</svg>")
    return "\n".join(out)


# --------------------------------------------------------------------------
# Chart 2: failures / bound calls by session model, faceted, three periods.
# --------------------------------------------------------------------------
def chart_by_model() -> str:
    periods = DATA["periods"]
    models = DATA["by_model"]
    W = 680
    L_LAB = 128           # left label column
    R_LAB = 150           # right value column
    PL, PR = L_LAB + 8, W - R_LAB
    ROW = 22
    HEAD = 20
    FGAP = 16
    TOP = 26
    xmax = 40.0
    facet_h = HEAD + ROW * len(periods)
    H = TOP + len(models) * (facet_h + FGAP) + 24

    def x_of(pct: float) -> float:
        return PL + pct / xmax * (PR - PL)

    out: list[str] = []
    out.append(
        f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" '
        f'aria-labelledby="c2-title c2-desc" xmlns="http://www.w3.org/2000/svg">'
    )
    out.append('<title id="c2-title">Failures per 100 bound calls by session model and period, with 95% Wilson intervals</title>')
    out.append('<desc id="c2-desc">Fable 5.1 sessions through the gateway fail on 22.8 per 100 bound calls; Opus 5, Sonnet 5 and GPT sessions on the same days stay under 2, and every model is at zero in the gateway-off period.</desc>')
    # x grid + ticks (top)
    for v in (0, 10, 20, 30, 40):
        x = x_of(v)
        out.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{TOP - 6}" y2="{H - 20}" class="grid"/>')
        out.append(f'<text x="{x:.1f}" y="{TOP - 10}" class="tick" text-anchor="middle">{v}</text>')
    out.append(f'<text x="{PR}" y="{H - 4}" class="lbl muted" text-anchor="end">failures per 100 bound calls (lower is better); whiskers are 95% Wilson intervals</text>')
    y = TOP
    for m in models:
        out.append(f'<text x="0" y="{y + 13}" class="facet">{esc(m["model"])}</text>')
        out.append(f'<line x1="0" x2="{W}" y1="{y + HEAD - 2}" y2="{y + HEAD - 2}" class="hair"/>')
        for i, p in enumerate(periods):
            ry = y + HEAD + i * ROW
            cy = ry + ROW / 2
            col = "var(--on)" if p["gateway"] == "on" else "var(--off)"
            out.append(f'<text x="{L_LAB}" y="{cy + 3.5:.1f}" class="lbl" text-anchor="end">{esc(p["label"])}</text>')
            cell = m[p["id"]]
            if cell is None:
                out.append(f'<text x="{PL + 4}" y="{cy + 3.5:.1f}" class="lbl muted">no sessions</text>')
                continue
            k, n = cell
            pct = 100 * k / n
            lo, hi = (100 * v for v in wilson(k, n))
            tip = f'{m["model"]}, {p["label"]}, gateway {p["gateway"]}: {fmt_int(k)} failures / {fmt_int(n)} bound calls = {pct:.1f} per 100 (95% Wilson {lo:.1f}-{hi:.1f})'
            out.append('<g class="hit">')
            out.append(f'<title>{esc(tip)}</title>')
            out.append(f'<rect x="{PL - 4}" y="{ry}" width="{W - PL + 4}" height="{ROW}" fill="transparent"/>')
            if k == 0:
                out.append(f'<circle cx="{x_of(0):.1f}" cy="{cy:.1f}" r="4" fill="{col}"/>')
            else:
                out.append(f'<rect x="{x_of(0):.1f}" y="{cy - 7:.1f}" width="{x_of(pct) - x_of(0):.1f}" height="14" rx="3" fill="{col}"/>')
                out.append(f'<rect x="{x_of(0):.1f}" y="{cy - 7:.1f}" width="3" height="14" fill="{col}"/>')
            # whisker
            out.append(f'<line x1="{x_of(lo):.1f}" x2="{x_of(hi):.1f}" y1="{cy:.1f}" y2="{cy:.1f}" class="ci"/>')
            out.append(f'<line x1="{x_of(hi):.1f}" x2="{x_of(hi):.1f}" y1="{cy - 4:.1f}" y2="{cy + 4:.1f}" class="ci"/>')
            label = f"{fmt_int(k)} / {fmt_int(n)}  ·  {pct:.1f}"
            out.append(f'<text x="{PR + 8}" y="{cy + 3.5:.1f}" class="val">{esc(label)}</text>')
            out.append("</g>")
        y += facet_h + FGAP
    out.append("</svg>")
    return "\n".join(out)


# --------------------------------------------------------------------------
# Tables (the WCAG twin of each chart), collapsed.
# --------------------------------------------------------------------------
def table_by_day() -> str:
    rows = []
    for r in DATA["by_day"]:
        rate = 100 * r["failures"] / r["bound"]
        rows.append(f'<tr><td>{r["day"]}</td><td class="num">{fmt_int(r["failures"])}</td><td class="num">{fmt_int(r["bound"])}</td>'
                    f'<td class="num">{rate:.1f}</td><td>{esc(r["cli"])}</td><td>{r["gateway"]}</td></tr>')
    return ('<table><thead><tr><th>day</th><th class="num">failures</th><th class="num">bound calls</th>'
            '<th class="num">per 100</th><th>CLI versions</th><th>gateway</th></tr></thead><tbody>'
            + "".join(rows) + "</tbody></table>")


def table_by_model_day() -> str:
    cols = ["Fable 5.1", "Opus 5", "Sonnet 5", "GPT-5.6 Sol", "GPT-6 Astra"]
    rows = []
    for r in DATA["by_model_by_day"]:
        cells = []
        for c in cols:
            v = r[c]
            cells.append('<td class="num">—</td>' if v is None else f'<td class="num">{v[0]}/{fmt_int(v[1])}</td>')
        rows.append(f'<tr><td>{r["day"]}</td>{"".join(cells)}<td>{esc(r["classifier"])}</td></tr>')
    head = "".join(f'<th class="num">{esc(c)}</th>' for c in cols)
    return (f'<table><thead><tr><th>day</th>{head}<th>classifier named in failures</th></tr></thead><tbody>'
            + "".join(rows) + "</tbody></table>")


def table_by_model() -> str:
    rows = []
    for m in DATA["by_model"]:
        cells = []
        for p in DATA["periods"]:
            v = m[p["id"]]
            if v is None:
                cells.append('<td class="num">—</td>')
            else:
                lo, hi = (100 * x for x in wilson(*v))
                cells.append(f'<td class="num">{v[0]}/{fmt_int(v[1])} ({100 * v[0] / v[1]:.1f}; {lo:.1f}–{hi:.1f})</td>')
        rows.append(f'<tr><td>{esc(m["model"])}</td>{"".join(cells)}</tr>')
    head = "".join(f'<th class="num">{esc(p["label"])}<br><span class="muted">gateway {p["gateway"]}</span></th>' for p in DATA["periods"])
    return (f'<table><thead><tr><th>session model</th>{head}</tr></thead><tbody>' + "".join(rows)
            + '</tbody></table><p class="note">Cells are failures/bound calls (per 100; 95% Wilson interval).</p>')


def table_router() -> str:
    rows = []
    for r in DATA["router_log"]:
        rows.append(f'<tr><td>{r["day"]}</td><td class="num">{fmt_int(r["claude-opus-5"])}</td><td class="num">{fmt_int(r["claude-fable-5-1"])}</td>'
                    f'<td class="num">{fmt_int(r["claude-sonnet-5"])}</td><td class="num">{fmt_int(r["haiku-4-5"])}</td>'
                    f'<td class="num">{fmt_int(r["sol"])} / {fmt_int(r["astra"])}</td></tr>')
    return ('<table><thead><tr><th>day</th><th class="num">claude-opus-5</th><th class="num">claude-fable-5-1</th>'
            '<th class="num">claude-sonnet-5</th><th class="num">haiku-4-5</th><th class="num">sol / astra</th></tr></thead><tbody>'
            + "".join(rows) + "</tbody></table>")


# --------------------------------------------------------------------------
# Page
# --------------------------------------------------------------------------
def page() -> str:
    S = DATA["sources"]
    by_day = DATA["by_day"]
    off_days = [r for r in by_day if r["gateway"] == "off"]
    on_days = [r for r in by_day if r["gateway"] == "on"]
    off_bound = sum(r["bound"] for r in off_days)
    on_fail = sum(r["failures"] for r in on_days)
    on_bound = sum(r["bound"] for r in on_days)
    fable = next(m for m in DATA["by_model"] if m["model"] == "Fable 5.1")["bad"]
    fable_share = 100 * fable[0] / on_fail

    css = f"""
<title>Fable sessions through the gateway trip the classifier</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root{{{tokens_css(LIGHT)}}}
@media (prefers-color-scheme: dark){{:root:not([data-theme="light"]){{{tokens_css(DARK)}}}}}
:root[data-theme="dark"]{{{tokens_css(DARK)}}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--ground);color:var(--ink);font:16px/1.55 "IBM Plex Sans",system-ui,-apple-system,"Segoe UI",sans-serif;padding-block:32px 56px;padding-inline:clamp(16px,4vw,40px)}}
main{{max-width:760px;margin:0 auto}}
h1{{font-size:clamp(26px,4.2vw,34px);line-height:1.15;font-weight:600;letter-spacing:-0.01em;text-wrap:balance;margin:0 0 8px}}
h2{{font-size:20px;line-height:1.3;font-weight:600;text-wrap:balance;margin:44px 0 10px}}
p{{margin:0 0 14px;max-width:66ch}}
.sub{{color:var(--muted);margin-bottom:28px}}
a{{color:inherit;text-decoration-color:var(--off);text-underline-offset:3px}}
a:hover{{text-decoration-color:var(--on)}}
code{{font:0.88em "IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--code);padding:1px 5px;border-radius:4px}}
figure{{margin:18px 0 8px}}
figcaption{{font-size:14px;color:var(--muted);margin-top:8px;max-width:72ch}}
figcaption b{{color:var(--ink);font-weight:600}}
svg.chart{{display:block;width:100%;height:auto;max-width:100%;overflow:visible}}
svg .tick{{font:11px "IBM Plex Mono",ui-monospace,monospace;fill:var(--muted);font-variant-numeric:tabular-nums}}
svg .lbl{{font:11px "IBM Plex Sans",system-ui,sans-serif;fill:var(--ink)}}
svg .muted{{fill:var(--muted)}}
svg .val{{font:11.5px "IBM Plex Mono",ui-monospace,monospace;fill:var(--ink);font-variant-numeric:tabular-nums}}
svg .facet{{font:600 12.5px "IBM Plex Sans",system-ui,sans-serif;fill:var(--ink)}}
svg .grid{{stroke:var(--hair);stroke-width:1}}
svg .hair{{stroke:var(--hair2);stroke-width:1}}
svg .axis{{stroke:var(--muted);stroke-width:1}}
svg .event{{stroke:var(--ink);stroke-width:1;stroke-dasharray:3 3}}
svg .ci{{stroke:var(--ink);stroke-width:1.2;opacity:0.7}}
svg .hit rect[fill="transparent"]{{pointer-events:all}}
svg .hit:hover rect:not([fill="transparent"]),svg .hit:hover circle{{filter:brightness(0.85)}}
.legend{{display:flex;flex-wrap:wrap;gap:6px 18px;font-size:13px;color:var(--muted);margin:4px 0 0}}
.legend span::before{{content:"";display:inline-block;width:12px;height:12px;border-radius:3px;margin-right:6px;vertical-align:-2px;background:var(--sw)}}
details{{margin:8px 0 4px;font-size:14px}}
summary{{cursor:pointer;color:var(--muted)}}
.tablewrap{{overflow-x:auto;margin-top:8px}}
table{{border-collapse:collapse;font-size:13.5px;min-width:100%}}
th,td{{padding:5px 10px 5px 0;border-bottom:1px solid var(--hair);text-align:left;vertical-align:top;white-space:nowrap}}
th{{font-weight:600;color:var(--muted)}}
td.num,th.num{{text-align:right;font-variant-numeric:tabular-nums;font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:12.5px}}
.note{{font-size:13px;color:var(--muted)}}
table.fixes th,table.fixes td{{white-space:normal;font-size:14px;padding:8px 12px 8px 0}}
table.fixes td:first-child{{font-family:"IBM Plex Mono",ui-monospace,monospace;color:var(--muted)}}
.term{{border-left:3px solid var(--off);padding:8px 14px;margin:18px 0;background:var(--panel);font-size:14.5px}}
.term p{{margin:0 0 6px}}
.term p:last-child{{margin:0}}
pre.mermaid{{background:transparent;overflow-x:auto;margin:16px 0 4px}}
footer{{margin-top:56px;padding-top:14px;border-top:1px solid var(--hair);font-size:13px;color:var(--muted)}}
@media (prefers-reduced-motion: reduce){{*{{transition:none!important}}}}
</style>
"""

    body = f"""
<main>
<h1>Fable sessions through the gateway trip the classifier</h1>
<p class="sub">Why Claude Code's auto-mode classifier started returning <code>rate-limited</code> on this machine on 6 September 2026, what fixes it, and the one test still owed. Measured from local transcripts, 2026-09-09/10.</p>

<p>Auto mode approves each shell or agent call with a separate classifier model. From 19 August to 5 September the model-router gateway was off and the classifier never failed once in {fmt_int(off_bound)} classifier-bound calls. The gateway was rewired on 6 September and failures began the same day; over 6 to 9 September, {fable_share:.0f}% of the {fmt_int(on_fail)} failures came from sessions running Fable 5.1, while Opus 5 and Sonnet 5 sessions through the same gateway on the same days stayed at zero. Every failure from a Fable 5.1 session names the 1M-context Opus variant as the classifier that was rate-limited. The cheapest fix is a non-Fable default model, and it is already in place; the open question is why the gateway makes the Fable sessions' Opus classifier hit its limit, and one hour of Fable work with the gateway off settles it.</p>

<div class="term">
<p><b>Native failure</b> — a tool result that reads <code>&lt;model&gt; is temporarily unavailable (rate-limited), so auto mode cannot determine the safety of &lt;tool&gt; right now</code>; counted once per tool call. The <a href="{S["docs_errors"]}">errors reference</a> lists it: Claude Code blocked the call without a verdict.</p>
<p><b>Bound call</b> — a Bash, PowerShell, Monitor, Agent or Task call, the tools that reach the classifier in auto mode. It is an upper bound on classifier calls: allow rules and cached verdicts skip it.</p>
<p><b>Gateway</b> — the model-router loopback proxy set as the API base URL. On before 18 August, off 18 August to 6 September, on since.</p>
</div>

<h2>Failures began the day the gateway was rewired</h2>
<figure>
{chart_by_day()}
<div class="legend"><span style="--sw:var(--off)">gateway off</span><span style="--sw:var(--on)">gateway on</span><span style="--sw:var(--muted);opacity:.6">bound calls</span></div>
<figcaption><b>Zero on all 16 gateway-off days, then 8.1 to 25.5 per 100 on the four gateway-on days.</b> Dots at the baseline are days with zero failures; bars are failures per 100 bound calls. The dashed lines mark the default model changing to Fable 5.1 on 3 September, three days before any failure, and the gateway rewire on 6 September. The lower strip is exposure: 22 and 23 August recorded no bound calls, and 4 and 5 September carried only 23 and 24, so their zeros are weak evidence. Source: <a href="{S["audit"]["url"]}"><code>claude-usage-audit --model-usage --days 21</code></a> at commit 3a1cdaf.</figcaption>
</figure>
<details><summary>Table view</summary><div class="tablewrap">{table_by_day()}</div></details>

<h2>Fable 5.1 sessions carry {fable_share:.0f}% of the failures</h2>
<figure>
{chart_by_model()}
<div class="legend"><span style="--sw:var(--off)">gateway off</span><span style="--sw:var(--on)">gateway on</span></div>
<figcaption><b>Through the gateway, Fable 5.1 sessions fail on 22.8 of every 100 bound calls; Opus 5, Sonnet 5 and GPT sessions on the same days stay under 2.</b> Each panel is a session model; each row a period, coloured by gateway state. A dot at zero is a measured zero: 0 of 627 Opus 5 and 0 of 176 Sonnet 5 bound calls on the bad days, and zero for every model in the gateway-off period. The Fable 5 row shows the gateway also cost Fable sessions in August, at a far lower rate; no Fable 5 session ran in the 6 to 9 September period. Source: <a href="{S["exposure"]["url"]}"><code>exposure_by_session_model.py</code></a> over the same transcripts.</figcaption>
</figure>
<details><summary>Table view: by model and period, and by model and day</summary><div class="tablewrap">{table_by_model()}</div><div class="tablewrap">{table_by_model_day()}</div>
<p class="note">On 6 September the five Opus 5 failures named <code>astra</code> as the classifier, which is a GPT route: the session-model label is the newest assistant model earlier in the same transcript, so a mid-session model switch can misattribute a row. Every other failure named the Opus 1M variant.</p></details>

<h2>The chain from session model to 429 has one open link</h2>
<p>The <a href="{S["docs_permission_modes"]}">permission-modes docs</a> say the classifier "runs on Claude Sonnet 5 by default rather than on your <code>/model</code> selection … or on an Opus model when the session runs on a Fable model", and that after the session's first auto-mode request "the classifier's model doesn't change for the session". The router log agrees: on 8 September Opus 5 sessions made 144 bound calls while the router carried 2,341 Opus 5 requests, so most Opus traffic through the gateway is the Fable sessions' classifier. What is not established is who turns that Opus request into the 1M-context variant the failures name.</p>
<pre class="mermaid">
flowchart TD
  A["Session model: Fable 5.1"] --> B["Classifier model per the docs:<br/>an Opus model for Fable sessions,<br/>Sonnet 5 for every other session"]
  B --> C{{"Gateway"}}
  C -->|"off, 19 Aug to 5 Sep"| D["0 failures in 6,711<br/>Fable bound calls"]
  C -->|"on, 6 to 9 Sep"| E["Router log shows the request<br/>as claude-opus-5<br/>(beta headers are not logged)"]
  E -.->|"OPEN: which side adds<br/>the 1M-context variant?"| F["Failure text names<br/>claude-opus-5 with the 1m suffix"]
  F --> G["429 rate-limited on that model<br/>call blocked, no verdict, no client retry"]
  classDef open stroke-dasharray:5 4;
  class F open;
</pre>
<p class="note">Solid arrows are measured or quoted from the docs; the dashed arrow is the open link. Quota alone does not explain the pattern: the gateway-off period spanned three Fable weekly resets with Fable sessions active and zero failures, and on 9 September the Fable-scoped seven-day quota read 100% while the all-models quota read 59%. Router log: <a href="#router-log">table</a>.</p>
<details id="router-log"><summary>Router log: requests routed per day, model as requested (no status codes in the log)</summary><div class="tablewrap">{table_router()}</div></details>

<h2>Switching the session model is the cheapest fix</h2>
<div class="tablewrap"><table class="fixes">
<thead><tr><th>rank</th><th>fix</th><th>evidence</th><th>cost</th><th>state</th></tr></thead>
<tbody>
<tr><td>1</td><td><b>Session model off Fable</b> (Opus 5 or Sonnet 5), so the classifier runs on Sonnet 5.</td><td>0 / 627 Opus 5 and 0 / 176 Sonnet 5 bound calls through the gateway on the bad days.</td><td>Fable stops being the default. Background jobs inherit the default; <code>claude --bg --model</code> overrides per job.</td><td>Done: default <code>model</code> is <code>opus</code> since 2026-09-10 05:08Z.</td></tr>
<tr><td>2</td><td><b>Gateway off for Fable sessions</b>, per session with the <code>CLAUDE_RC_OVERRIDE=1</code> wrapper or globally with <code>model-router-wire off</code>.</td><td>0 / 6,194 Fable 5 and 0 / 517 Fable 5.1 bound calls in the gateway-off period.</td><td>The foreign-model picker rows and agents go with it (globally), or Remote Control comes back for that one session (per session).</td><td>Available.</td></tr>
<tr><td>3</td><td><b>Narrow allow rules</b> of the form <code>Bash(&lt;cmd&gt; &lt;sub&gt; *)</code> in global settings, so fewer calls reach the classifier at all.</td><td>The <a href="{S["docs_auto_mode_config"]}">auto-mode config docs</a>: narrow rules "stay in effect in auto mode, and Claude Code resolves them before the classifier runs"; broad rules such as <code>Bash(*)</code>, interpreters and Monitor are suspended.</td><td>Partial, and each rule is a command class that runs unclassified.</td><td>Candidates being mined.</td></tr>
<tr><td>—</td><td><b>Not available</b>: choosing the classifier model; a client-side retry of the classifier call; broad <code>permissions.allow</code> rules.</td><td>Docs: "Claude Code selects the classifier model, so which reason you see isn't something you configure." Claude Code does not retry the classifier request itself; the model may re-issue the tool call (<a href="{S["issue_74248"]}">issue 74248</a> reports the same shape on an earlier Opus 1M classifier). Broad rules are dropped in auto mode.</td><td>—</td><td>—</td></tr>
</tbody></table></div>

<h2>One hour off the gateway settles the open question</h2>
<p>Run one Fable 5.1 session with the gateway off for an hour of shell work. Zero failures reproduces the gateway-off period. If a failure occurs, read the classifier name in its diagnostic: the 1M suffix absent means the gateway adds the 1M-context variant; present means the cause lies elsewhere. Either outcome is decisive, and fix 1 holds in the meantime.</p>

<h2>Limits</h2>
<p>Failures are counted from retained tool-result rows only; the CLI records no successful classifier call, so every rate is failures over an upper bound on calls, and the true per-call rate is higher than shown. The session model behind a failure is the newest assistant model earlier in the same transcript, which a mid-session model switch blurs. The failure parser is locked to the wording of CLI 2.1.263 and 2.1.266. The router log carries no status codes and no beta headers. Both charts are read against a null of zero: the gateway-off period is the control, not a modelled baseline. Comparisons here were not pre-registered; the by-model split was run after the by-day pattern was seen, on the same transcripts, so it is a finding to confirm with the test above rather than an independent replication.</p>

<footer>Built by Claude Fable 5.1 on 2026-09-10 from <code>data.json</code> (a transcription of the measured snapshot <code>{esc(S["snapshot"])}</code>) in <code>artifacts/classifier-rate-limits-2026-09/</code>; accounting change under review in <a href="{S["pr"]}">PR #110</a>. Select any text to leave a comment or suggest an edit.</footer>
</main>
"""
    return css + body


if __name__ == "__main__":
    OUT.write_text(page())
    print(f"wrote {OUT} ({OUT.stat().st_size:,} bytes)")
