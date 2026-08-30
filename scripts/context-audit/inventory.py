#!/usr/bin/env python3
"""Inventory every context-consuming Claude Code component.

Three loading tiers:
  TIER 1  always in context  -- rules, CLAUDE.md, active output style, and the
                                one-line name+description of every enabled skill/agent
  TIER 2  loaded on invoke   -- the full SKILL.md body
  TIER 3  loaded on demand   -- references/ files the body points at

Enabled plugins are resolved from ~/.claude/settings.json enabledPlugins, and their
files are read from the plugin CACHE (~/.claude/plugins/cache/<marketplace>/<plugin>/<ver>/),
which is what Claude Code actually loads. Where an editable working copy of the same
component exists under ~/code/marketplaces/, its path is recorded as `edit_path` so
recommendations point somewhere the user can change.
"""
import json, re, yaml
from pathlib import Path
from collections import Counter

OUT = Path(__file__).parent
SETTINGS = json.load(open('/home/yulong/.claude/settings.json'))
ENABLED = {k for k, v in SETTINGS.get('enabledPlugins', {}).items() if v}
CACHE = Path('/home/yulong/.claude/plugins/cache')
EDITABLE = Path('/home/yulong/code/marketplaces')
DF = Path('/home/yulong/code/dotfiles/claude')


def parse_fm(text):
    """Parse YAML frontmatter properly.

    Many skills use folded scalars (`description: >-` continued over several
    indented lines). A line-by-line regex silently truncates those to empty,
    which understates the Tier-1 cost of exactly the verbose skills that matter.
    """
    if not text.startswith('---'):
        return {}, text
    end = text.find('\n---', 3)
    if end == -1:
        return {}, text
    raw, body = text[3:end], text[end + 4:]
    try:
        d = yaml.safe_load(raw)
        if not isinstance(d, dict):
            raise ValueError
        d = {k: (' '.join(str(v).split()) if v is not None else '') for k, v in d.items()}
    except Exception:
        d = {}
        for line in raw.splitlines():
            m = re.match(r'^([a-zA-Z_-]+):\s*(.*)$', line)
            if m:
                d[m.group(1)] = m.group(2).strip()
    return d, body


def toks(s):
    return round(len(s) / 4)


rows = []


def find_editable(marketplace, plugin, kind, name):
    """Locate the same component in the user's editable marketplace checkout."""
    base = EDITABLE / marketplace
    if not base.is_dir():
        return None
    pat = f'{plugin}/skills/{name}/SKILL.md' if kind == 'skill' else f'{plugin}/agents/{name}.md'
    hits = list(base.rglob(pat))
    return str(hits[0]) if hits else None


def add(path, marketplace, plugin, kind, enabled=True):
    p = Path(path)
    try:
        text = p.read_text(errors='replace')
    except Exception:
        return
    fm, body = parse_fm(text)
    name = fm.get('name') or (p.parent.name if p.name == 'SKILL.md' else p.stem)
    desc = fm.get('description', '')
    ref_bytes, ref_files = 0, []
    for rd in [p.parent / 'references', p.parent / 'reference', p.parent / 'assets', p.parent / 'scripts']:
        if rd.is_dir():
            for f in sorted(rd.rglob('*')):
                if f.is_file():
                    try:
                        c = f.read_text(errors='replace')
                        ref_bytes += len(c)
                        # A reference cut mid-word that still looks whole is worse
                        # than one that says it was cut. Keep the cap generous and
                        # always declare the trim.
                        CAP = 120000
                        ref_files.append({'f': str(f.relative_to(p.parent)),
                                          't': toks(c), 'c': c[:CAP],
                                          'cut': max(0, len(c) - CAP)})
                    except Exception:
                        pass
    # A skill with `disable-model-invocation: true` is user-invoked: its
    # description is stripped from the agent's reach entirely, so it costs
    # ZERO Tier-1 tokens. Charging it its description length overstates the
    # always-loaded budget and makes a deliberately-manual skill look like
    # dead weight, when its 0 uses are simply invocations we cannot see.
    user_invoked = str(fm.get('disable-model-invocation', '')).lower() == 'true'
    rows.append({
        'name': name, 'kind': kind, 'source': marketplace, 'plugin': plugin,
        'user_invoked': user_invoked,
        'enabled': enabled, 'path': str(p),
        'edit_path': find_editable(marketplace, plugin, kind, name) if marketplace != 'dotfiles' else str(p),
        'desc': desc,
        'fm_tokens': 0 if user_invoked else toks(f"- {name}: {desc}"),
        'body_tokens': toks(text),
        'ref_tokens': round(ref_bytes / 4),
        'ref_files': ref_files, 'body': body.strip(),
    })


# ---- dotfiles (always active; symlinked to ~/.claude) ----
for d in sorted((DF / 'skills').glob('*/SKILL.md')):
    add(d, 'dotfiles', 'dotfiles', 'skill')
for d in sorted((DF / 'agents').glob('*.md')):
    add(d, 'dotfiles', 'dotfiles', 'agent')
for d in sorted((DF / 'rules').glob('*.md')):
    t = d.read_text(errors='replace')
    rows.append({'name': d.stem, 'kind': 'rule', 'source': 'dotfiles', 'plugin': 'dotfiles',
                 'enabled': True, 'path': str(d), 'edit_path': str(d),
                 'desc': '(always loaded - every session)', 'fm_tokens': toks(t), 'body_tokens': toks(t),
                 'ref_tokens': 0, 'ref_files': [], 'body': t.strip()})

# ---- enabled plugins, read from the cache that actually loads ----
for entry in sorted(ENABLED):
    plug, mkt = entry.split('@', 1)
    pdir = CACHE / mkt / plug
    if not pdir.is_dir():
        continue
    versions = sorted([v for v in pdir.iterdir() if v.is_dir()])
    if not versions:
        continue
    root = versions[-1]
    for sk in sorted(root.rglob('skills/*/SKILL.md')):
        add(sk, mkt, plug, 'skill', True)
    for ag in sorted(root.rglob('agents/*.md')):
        add(ag, mkt, plug, 'agent', True)

# ---- installed but NOT enabled (zero context cost; disk only) ----
for mkt_dir in sorted(CACHE.iterdir()) if CACHE.is_dir() else []:
    if not mkt_dir.is_dir() or mkt_dir.name.startswith('temp_git_'):
        continue
    for pdir in sorted(mkt_dir.iterdir()):
        if not pdir.is_dir():
            continue
        if f'{pdir.name}@{mkt_dir.name}' in ENABLED:
            continue
        versions = sorted([v for v in pdir.iterdir() if v.is_dir()])
        if not versions:
            continue
        root = versions[-1]
        for sk in sorted(root.rglob('skills/*/SKILL.md')):
            add(sk, mkt_dir.name, pdir.name, 'skill', False)
        for ag in sorted(root.rglob('agents/*.md')):
            add(ag, mkt_dir.name, pdir.name, 'agent', False)

# ---- always-loaded prose ----
for extra, label in [(DF / 'CLAUDE.md', 'global CLAUDE.md'),
                     (Path('/home/yulong/code/dotfiles/CLAUDE.md'), 'repo CLAUDE.md')]:
    if extra.exists():
        t = extra.read_text(errors='replace')
        rows.append({'name': label, 'kind': 'always', 'source': 'dotfiles', 'plugin': 'dotfiles',
                     'enabled': True, 'path': str(extra), 'edit_path': str(extra),
                     'desc': '(always loaded - every session)', 'fm_tokens': toks(t), 'body_tokens': toks(t),
                     'ref_tokens': 0, 'ref_files': [], 'body': t.strip()})

osd = DF / 'output-styles'
active_style = SETTINGS.get('outputStyle', '')
if osd.is_dir():
    for p in sorted(osd.glob('*.md')):
        t = p.read_text(errors='replace')
        is_active = p.stem == active_style
        rows.append({'name': f'output-style: {p.stem}', 'kind': 'always', 'source': 'dotfiles',
                     'plugin': 'dotfiles', 'enabled': is_active, 'path': str(p), 'edit_path': str(p),
                     'desc': '(ACTIVE output style)' if is_active else '(inactive output style)',
                     'fm_tokens': toks(t) if is_active else 0, 'body_tokens': toks(t),
                     'ref_tokens': 0, 'ref_files': [], 'body': t.strip()})

# dedupe by logical identity
best = {}
for r in rows:
    key = (r['source'], r['plugin'], r['kind'], r['name'])
    if key not in best:
        best[key] = r
out = list(best.values())

json.dump(out, open(OUT / 'inventory.json', 'w'))

en = [r for r in out if r['enabled']]
dis = [r for r in out if not r['enabled']]
print(f"TOTAL on disk: {len(out)}   ENABLED: {len(en)}   DISABLED: {len(dis)}")
print("enabled by kind:", dict(Counter(r['kind'] for r in en)))
print("enabled by plugin:", dict(Counter(r['plugin'] for r in en)))
print("DISABLED by plugin:", dict(Counter(r['plugin'] for r in dis)))
print()
aw = sum(r['fm_tokens'] for r in en if r['kind'] in ('rule', 'always'))
dl = sum(r['fm_tokens'] for r in en if r['kind'] in ('skill', 'agent'))
print(f"[TIER 1] always-loaded prose (rules + CLAUDE.md + active style): {aw:,} tok")
print(f"[TIER 1] skill/agent description lines (enabled only):           {dl:,} tok")
print(f"[TIER 1] TOTAL fixed per-session cost:                           {aw+dl:,} tok")
print(f"[TIER 2] every enabled body, if all were invoked:                {sum(r['body_tokens'] for r in en if r['kind'] in ('skill','agent')):,} tok")
print(f"[TIER 3] references under enabled skills:                        {sum(r['ref_tokens'] for r in en):,} tok")
print(f"  disabled cost 0 tok; they hold {sum(r['body_tokens'] for r in dis):,} tok of dormant text")
print()
print("Top 20 enabled, by Tier-1 (per-session) cost:")
for r in sorted(en, key=lambda x: -x['fm_tokens'])[:20]:
    print(f"  {r['fm_tokens']:>5} tok  {r['kind']:<6} {r['plugin']:<18} {r['name']}")
