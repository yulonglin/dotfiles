#!/usr/bin/env python3
"""Make the page charset-independent.

The template and the embedded payload both carry typographic characters. If any
host serves the file without a charset declaration they render as mojibake, so
convert HTML-context characters to entities and let json.dumps escape the rest.
"""
from pathlib import Path

p = Path(__file__).parent / 'template.html'
t = p.read_text(encoding='utf-8')

html_map = {'·': '&middot;', '—': '&mdash;', '÷': '&divide;', '±': '&plusmn;',
            '≥': '&ge;', '⠿': '&#10495;', '↵': '&crarr;', '…': '&hellip;',
            '’': '&rsquo;', '“': '&ldquo;', '”': '&rdquo;', '×': '&times;'}
for k, v in html_map.items():
    t = t.replace(k, v)

t = t.replace('−', '\\u2212')        # inside a JS template literal
t = t.replace("'&mdash; '", "'\\u2014 '")

p.write_text(t, encoding='utf-8')
non = sorted({c for c in t if ord(c) > 127})
print('remaining non-ASCII in template:', non if non else 'none')
