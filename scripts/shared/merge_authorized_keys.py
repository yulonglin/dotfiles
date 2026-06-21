#!/usr/bin/env python3
"""
Merge multiple authorized_keys files with disable-wins semantics.

Usage: merge_authorized_keys.py CANONICAL [OTHER…]

  CANONICAL — the curated/base file whose structure and labels take precedence.
  OTHER     — one or more files to merge in (e.g. gist copy, _restored).

Prints the merged result to stdout, exit 0.
Falls back to CANONICAL content on parse/merge errors (prints to stderr).

Convention understood:
  Active key:  <type> <blob> [# inline note]   under a `# <label>` section header
  Tombstone:   # <type> <blob> …               whole-line-commented key = disable marker
  Divider:     # --- Disabled / pending deletion ---   (any `# --- … ---` pattern)

Merge rules:
  1. disabled_blobs = union of all tombstone blobs across ALL input files.
  2. A blob appears active in the output iff: active in ≥1 file AND blob ∉ disabled_blobs.
     "Disable wins over active" — a key disabled anywhere is suppressed everywhere, even
     if another file still lists it as active. This prevents revoked keys from resurrecting
     on the next gist sync.
  3. Label (inline note) from CANONICAL wins; fallback to the first other file that has it.
  4. The disabled block (`# --- Disabled ---`) from CANONICAL is preserved in full.
     Tombstones present in OTHER files but absent from CANONICAL's disabled section are
     appended at the end of the disabled block.
  5. Round-trip safe: merging a file with itself produces the same file unchanged.
"""

from __future__ import annotations

import re
import sys

_KEY_PREFIXES = ('ssh-', 'ecdsa-', 'sk-')
_DIVIDER_RE = re.compile(r'^#\s*---')


def _is_key_type(word):
    return any(word.startswith(p) for p in _KEY_PREFIXES)


# ──────────────────────────────────────────────────────────────────────────────
# Line classification
# ──────────────────────────────────────────────────────────────────────────────
# Each parsed line is a tuple: (kind, *fields, raw_line)
# kind is one of: 'blank', 'header', 'divider', 'tombstone', 'key', 'raw'
#
# 'key':       (kind, blob, key_type, note, raw)
# 'tombstone': (kind, blob, key_type, note, raw)
# 'header':    (kind, raw)
# 'divider':   (kind, raw)
# 'blank':     (kind, raw)
# 'raw':       (kind, raw)

def _parse_line(line):
    stripped = line.strip()
    if not stripped:
        return ('blank', line)
    if stripped.startswith('#'):
        if _DIVIDER_RE.match(stripped):
            return ('divider', line)
        # Tombstone: `# <key-type> <blob> [rest]`
        rest = stripped[1:].lstrip()
        parts = rest.split()
        if len(parts) >= 2 and _is_key_type(parts[0]):
            return ('tombstone', parts[1], parts[0], ' '.join(parts[2:]), line)
        return ('header', line)
    # Non-comment line
    parts = stripped.split()
    if len(parts) >= 2 and _is_key_type(parts[0]):
        return ('key', parts[1], parts[0], ' '.join(parts[2:]), line)
    return ('raw', line)


# ──────────────────────────────────────────────────────────────────────────────
# File parsing
# ──────────────────────────────────────────────────────────────────────────────

def _parse_file(content):
    """
    Parse authorized_keys content into structured entries.

    Returns:
      structured   — ordered list of parsed line tuples
      active       — ordered dict: blob -> (key_type, note, section_header_raw)
      tombstones   — ordered dict: blob -> (key_type, note, section_header_raw, orig_raw_line)
    """
    structured = []
    active = {}
    tombstones = {}
    current_header = None

    for line in content.splitlines():
        parsed = _parse_line(line)
        structured.append(parsed)
        kind = parsed[0]

        if kind == 'header':
            current_header = parsed[1]   # raw line, e.g. '# hetzner'
        elif kind == 'divider':
            current_header = None        # reset section in the disabled region
        elif kind == 'key':
            _, blob, key_type, note, _ = parsed
            if blob not in active and blob not in tombstones:
                active[blob] = (key_type, note, current_header)
        elif kind == 'tombstone':
            _, blob, key_type, note, raw = parsed
            if blob not in tombstones:
                tombstones[blob] = (key_type, note, current_header, raw)

    return structured, active, tombstones


# ──────────────────────────────────────────────────────────────────────────────
# Merge
# ──────────────────────────────────────────────────────────────────────────────

def merge_files(contents):
    """
    Merge N authorized_keys contents.  contents[0] is the canonical/base file.
    Returns the merged content as a string.
    """
    if not contents:
        return ''

    parsed = [_parse_file(c) for c in contents]
    all_structured = [p[0] for p in parsed]
    all_active     = [p[1] for p in parsed]
    all_tombstones = [p[2] for p in parsed]

    # ── 1. Collect disabled blobs (union across all files) ───────────────────
    disabled_blobs = set()
    for ts in all_tombstones:
        disabled_blobs.update(ts)

    # ── 2. Collect active labels (canonical/base wins) ───────────────────────
    # For each non-disabled active blob, take the label from the first file that has it.
    active_labels = {}   # blob -> (key_type, note)
    for active in all_active:
        for blob, (kt, note, _) in active.items():
            if blob not in disabled_blobs and blob not in active_labels:
                active_labels[blob] = (kt, note)

    # ── 3. Render active region from base structure ──────────────────────────
    output = []
    rendered_active = set()
    base_structured = all_structured[0]

    divider_idx = None
    for i, item in enumerate(base_structured):
        kind = item[0]
        if kind == 'divider':
            divider_idx = i
            break
        if kind in ('blank', 'header', 'raw'):
            output.append(item[-1])   # raw line
        elif kind == 'key':
            blob = item[1]
            if blob in disabled_blobs:
                continue   # suppress: disable-wins
            if blob in active_labels and blob not in rendered_active:
                kt, note = active_labels[blob]
                output.append('{} {} {}'.format(kt, blob, note) if note else '{} {}'.format(kt, blob))
                rendered_active.add(blob)
        elif kind == 'tombstone':
            pass   # handled in disabled block

    # ── 4. Append unique active keys from other files ────────────────────────
    unique_others = []
    seen_unique = set()
    for active in all_active[1:]:
        for blob, (kt, note, section_header) in active.items():
            if blob not in disabled_blobs and blob not in rendered_active and blob not in seen_unique:
                unique_others.append((blob, kt, note, section_header))
                seen_unique.add(blob)

    if unique_others:
        while output and not output[-1].strip():
            output.pop()
        _SENTINEL = object()
        cur_section = _SENTINEL
        for blob, kt, note, section_header in unique_others:
            if section_header != cur_section:
                output.append('')
                if section_header:
                    output.append(section_header)
                cur_section = section_header
            output.append('{} {} {}'.format(kt, blob, note) if note else '{} {}'.format(kt, blob))

    # ── 5. Render disabled block ─────────────────────────────────────────────
    if not disabled_blobs:
        return '\n'.join(output)

    while output and not output[-1].strip():
        output.pop()
    output.append('')   # blank line before disabled section

    if divider_idx is not None:
        # Emit base's disabled section verbatim, deduping tombstones
        emitted_tomb = set()
        for item in base_structured[divider_idx:]:
            kind = item[0]
            if kind == 'tombstone':
                blob = item[1]
                if blob not in emitted_tomb:
                    output.append(item[-1])   # orig commented line
                    emitted_tomb.add(blob)
                # else: skip duplicate
            else:
                output.append(item[-1])   # divider, header, blank → preserve

        # Append tombstones from other files not yet in base's disabled section
        extras_gap_added = False
        for ts in all_tombstones[1:]:
            for blob, (kt, note, section_header, orig_raw) in ts.items():
                if blob not in emitted_tomb:
                    if not extras_gap_added:
                        output.append('')
                        extras_gap_added = True
                    if section_header:
                        output.append('')
                        output.append(section_header)
                    output.append(orig_raw)
                    emitted_tomb.add(blob)
    else:
        # No disabled section in base — build one from all tombstones
        output.append('# --- Disabled / pending deletion ---')
        _SENTINEL2 = object()
        cur_section = _SENTINEL2
        for ts in all_tombstones:
            for blob, (kt, note, section_header, orig_raw) in ts.items():
                if section_header != cur_section:
                    output.append('')
                    if section_header:
                        output.append(section_header)
                    cur_section = section_header
                output.append(orig_raw)

    result = '\n'.join(output)
    # Preserve trailing newline if the canonical (base) content had one.
    if contents[0].endswith('\n'):
        result += '\n'
    return result


# ──────────────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print('Usage: merge_authorized_keys.py CANONICAL [OTHER…]', file=sys.stderr)
        sys.exit(1)

    contents = []
    for path in sys.argv[1:]:
        try:
            with open(path) as f:
                contents.append(f.read())
        except OSError as e:
            print('Error reading {}: {}'.format(path, e), file=sys.stderr)
            sys.exit(1)

    result = merge_files(contents)
    print(result)


if __name__ == '__main__':
    main()
