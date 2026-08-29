#!/usr/bin/env python3
"""Attach real invocation counts to the inventory.

Counts come from ripgrep over ~/.claude/projects/**/*.jsonl:
  skills  -> occurrences of "skill":"<name>"
  agents  -> occurrences of "subagent_type":"<name>"

ALIASES matter: several skills were renamed on 2026-08-28, so the current name
has near-zero hits while its predecessor carries the real history. Counting the
current name alone would wrongly mark a heavily-used skill as dead.
"""
import json, re, subprocess
from pathlib import Path

OUT = Path(__file__).parent
PROJ = '/home/yulong/.claude/projects/'


def counts(field):
    try:
        r = subprocess.run(
            ['rg', '-o', rf'"{field}"\s*:\s*"[^"]+"', PROJ, '-g', '*.jsonl', '--no-filename'],
            capture_output=True, text=True, timeout=600)
    except Exception:
        return {}
    c = {}
    for line in r.stdout.splitlines():
        m = re.search(r':\s*"([^"]+)"', line)
        if m:
            c[m.group(1)] = c.get(m.group(1), 0) + 1
    return c


skill_counts = counts('skill')
agent_counts = counts('subagent_type')

# Renames verified from `git log --diff-filter=R` in the dotfiles repo (commit
# 5b2bb67, 2026-08-28). Predecessor usage belongs to the successor.
ALIASES = {
    'interview-me': ['grilling', 'grill-me'],
    'house-plots': ['pastelplot', 'anthropic-style'],
    'spec-artifact': ['writing-spec'],
    'externalise-handover': ['handoff', 'workflow:externalise-handover'],
    'remember': ['remember:remember'],
    'writing-plans': ['superpowers:writing-plans'],
}

inv = json.load(open(OUT / 'inventory.json'))


def lookup(r):
    """Total invocations for a component, summing plugin-qualified, bare and alias names."""
    name = r['name']
    pool = agent_counts if r['kind'] == 'agent' else skill_counts
    keys = {name, f"{r['plugin']}:{name}"}
    for a in ALIASES.get(name, []):
        keys.add(a)
    total, hits = 0, {}
    for k in keys:
        if pool.get(k):
            total += pool[k]
            hits[k] = pool[k]
    return total, hits


for r in inv:
    if r['kind'] in ('rule', 'always'):
        r['uses'] = None          # always loaded; "usage" is not meaningful
        r['use_detail'] = {}
    else:
        r['uses'], r['use_detail'] = lookup(r)

json.dump(inv, open(OUT / 'inventory.json', 'w'))

en = [r for r in inv if r['enabled'] and r['kind'] in ('skill', 'agent')]
zero = [r for r in en if r['uses'] == 0]
print(f"enabled skills+agents: {len(en)}   never invoked: {len(zero)}")
print(f"Tier-1 tokens held by never-invoked components: "
      f"{sum(r['fm_tokens'] for r in zero):,} tok")
print()
print("MOST USED:")
for r in sorted(en, key=lambda x: -x['uses'])[:18]:
    d = ' '.join(f'{k}={v}' for k, v in sorted(r['use_detail'].items(), key=lambda kv: -kv[1]))
    print(f"  {r['uses']:>4}x  {r['kind']:<6} {r['plugin']:<14} {r['name']:<32} [{d}]")
print()
print(f"NEVER INVOKED ({len(zero)}):")
for r in sorted(zero, key=lambda x: (x['plugin'], x['name'])):
    print(f"   {r['fm_tokens']:>4} tok  {r['kind']:<6} {r['plugin']:<14} {r['name']}")
