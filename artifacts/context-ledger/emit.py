#!/usr/bin/env python3
"""Inject the payload into the template and write the publishable artifact."""
from pathlib import Path

OUT = Path(__file__).parent
tpl = (OUT / 'template.html').read_text()
payload = (OUT / 'payload.json').read_text()

# The payload embeds whole SKILL.md bodies, several of which contain literal HTML
# (`</script>`, `</body></html>`). Two things break on that: the HTML parser closes
# this script early, and `annotate-html` injects its layer before the FIRST `</body>`
# it finds -- which would be inside our data. Escaping every `<` as the JSON escape
# < keeps the strings identical after parsing while leaving no HTML-looking text.
payload = payload.replace('<', '\\u003c')

assert '__PAYLOAD__' in tpl, 'placeholder missing'
html = tpl.replace('__PAYLOAD__', payload)

dest = OUT / 'context-ledger.html'
dest.write_text(html)
print(f'wrote {dest}  {len(html)/1e6:.2f} MB')
for bad in ['<!doctype', '<html', '<head>', '<body>']:
    if bad in html.lower():
        print('WARNING: contains', bad)
