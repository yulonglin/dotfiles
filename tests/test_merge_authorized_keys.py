"""
Tests for scripts/shared/merge_authorized_keys.py

Run with: pytest tests/test_merge_authorized_keys.py -v
"""
import sys
import textwrap
from pathlib import Path

# Allow importing the script directly
sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts' / 'shared'))
from merge_authorized_keys import merge_files  # noqa: E402

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

def active_blobs(text):
    """Return the set of blobs on non-commented active-key lines."""
    blobs = set()
    for line in text.splitlines():
        s = line.strip()
        if s and not s.startswith('#'):
            parts = s.split()
            if len(parts) >= 2:
                blobs.add(parts[1])
    return blobs


def disabled_blobs_in_output(text):
    """Return the set of blobs in commented-out key lines (tombstones)."""
    blobs = set()
    for line in text.splitlines():
        s = line.strip()
        if s.startswith('#'):
            rest = s[1:].lstrip()
            parts = rest.split()
            if len(parts) >= 2 and any(parts[0].startswith(p) for p in ('ssh-', 'ecdsa-', 'sk-')):
                blobs.add(parts[1])
    return blobs


# ──────────────────────────────────────────────────────────────────────────────
# Fixtures: sample key blobs
# ──────────────────────────────────────────────────────────────────────────────

BLOB_HETZNER   = 'AAAAC3NzaC1lZDI1NTE5AAAAILDs4e7G72qNo07Z8DL_hetzner'
BLOB_IPHONE    = 'AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdH_iphone'
BLOB_M5SILVER  = 'AAAAC3NzaC1lZDI1NTE5AAAAIDgilA5QJWaHW1t4_m5silver'
BLOB_M4PRO     = 'AAAAC3NzaC1lZDI1NTE5AAAAIP3ON920LWKJoPbz_m4pro'
BLOB_RUNPOD    = 'AAAAC3NzaC1lZDI1NTE5AAAAIEHyhnkHfdhyPnOP_runpod'
BLOB_UNKNOWN   = 'AAAAC3NzaC1lZDI1NTE5AAAAICrt3kOSiqZZUUvY_unknown'
BLOB_NEW_GIST  = 'AAAAC3NzaC1lZDI1NTE5AAAAINEWkeyFromGist_new'


# The curated local file (matches the hetzner convention)
LOCAL_CURATED = textwrap.dedent(f"""\
    # hetzner
    ssh-ed25519 {BLOB_HETZNER}

    # iPhone 14
    ecdsa-sha2-nistp256 {BLOB_IPHONE} # Termius

    # m5-silver
    ssh-ed25519 {BLOB_M5SILVER}

    # --- Disabled / pending deletion ---

    # m4pro
    # ssh-ed25519 {BLOB_M4PRO}

    # RunPod
    # ssh-ed25519 {BLOB_RUNPOD}

    # unknown (TODO: delete?)
    # ssh-ed25519 {BLOB_UNKNOWN}
""")

# Gist still has the old active keys (pre-curation), no disabled section
GIST_OLD = textwrap.dedent(f"""\
    ssh-ed25519 {BLOB_HETZNER}
    ecdsa-sha2-nistp256 {BLOB_IPHONE} # Termius
    ssh-ed25519 {BLOB_M5SILVER}
    ssh-ed25519 {BLOB_M4PRO}
    ssh-ed25519 {BLOB_RUNPOD}
    ssh-ed25519 {BLOB_UNKNOWN}
""")


# ──────────────────────────────────────────────────────────────────────────────
# (a) disable-wins: blob active in gist, tombstoned in local → absent from active
# ──────────────────────────────────────────────────────────────────────────────

def test_disable_wins_suppresses_gist_active_key():
    result = merge_files([LOCAL_CURATED, GIST_OLD])
    # The three keys the user left active should be present
    assert BLOB_HETZNER  in active_blobs(result)
    assert BLOB_IPHONE   in active_blobs(result)
    assert BLOB_M5SILVER in active_blobs(result)
    # The tombstoned keys must NOT appear as active
    assert BLOB_M4PRO   not in active_blobs(result)
    assert BLOB_RUNPOD  not in active_blobs(result)
    assert BLOB_UNKNOWN not in active_blobs(result)


def test_disable_wins_keeps_tombstones_in_disabled_block():
    result = merge_files([LOCAL_CURATED, GIST_OLD])
    disabled = disabled_blobs_in_output(result)
    assert BLOB_M4PRO   in disabled
    assert BLOB_RUNPOD  in disabled
    assert BLOB_UNKNOWN in disabled


# ──────────────────────────────────────────────────────────────────────────────
# (b) disable-wins regardless of file order (local wins even if gist is "base")
# ──────────────────────────────────────────────────────────────────────────────

def test_disable_wins_when_gist_is_first_arg():
    # Even if we accidentally pass gist first, tombstones from local suppress keys
    result = merge_files([GIST_OLD, LOCAL_CURATED])
    assert BLOB_M4PRO   not in active_blobs(result)
    assert BLOB_RUNPOD  not in active_blobs(result)


# ──────────────────────────────────────────────────────────────────────────────
# (c) section header NOT mistaken for tombstone
# ──────────────────────────────────────────────────────────────────────────────

def test_section_header_not_treated_as_tombstone():
    content = textwrap.dedent(f"""\
        # hetzner
        ssh-ed25519 {BLOB_HETZNER}
    """)
    result = merge_files([content])
    # 'hetzner' isn't a blob, but make sure the header line didn't break anything
    assert BLOB_HETZNER in active_blobs(result)
    assert disabled_blobs_in_output(result) == set()


# ──────────────────────────────────────────────────────────────────────────────
# (d) base label wins for blob present in both with different notes
# ──────────────────────────────────────────────────────────────────────────────

def test_base_label_wins():
    base = f'ecdsa-sha2-nistp256 {BLOB_IPHONE} # Termius\n'
    other = f'ecdsa-sha2-nistp256 {BLOB_IPHONE} # Mobile\n'
    result = merge_files([base, other])
    assert '# Termius' in result
    assert '# Mobile' not in result


# ──────────────────────────────────────────────────────────────────────────────
# (e) intra-file duplicate active blob → only one in output
# ──────────────────────────────────────────────────────────────────────────────

def test_intra_file_duplicate_collapsed():
    content = textwrap.dedent(f"""\
        ssh-ed25519 {BLOB_HETZNER} # first
        ssh-ed25519 {BLOB_HETZNER} # second
    """)
    result = merge_files([content])
    assert result.count(BLOB_HETZNER) == 1


# ──────────────────────────────────────────────────────────────────────────────
# (f) active keys unique to other file are appended
# ──────────────────────────────────────────────────────────────────────────────

def test_unique_key_from_gist_is_added():
    gist_with_new = GIST_OLD + f'ssh-ed25519 {BLOB_NEW_GIST} # NewMachine\n'
    result = merge_files([LOCAL_CURATED, gist_with_new])
    assert BLOB_NEW_GIST in active_blobs(result), \
        'Genuinely new key from gist should be added'
    # The disabled ones must still be suppressed
    assert BLOB_M4PRO not in active_blobs(result)


# ──────────────────────────────────────────────────────────────────────────────
# (g) round-trip idempotence: single-file merge returns file unchanged
# ──────────────────────────────────────────────────────────────────────────────

def test_single_file_round_trip():
    result = merge_files([LOCAL_CURATED])
    assert result == LOCAL_CURATED


def test_two_identical_files_round_trip():
    result = merge_files([LOCAL_CURATED, LOCAL_CURATED])
    assert active_blobs(result) == active_blobs(LOCAL_CURATED)
    assert disabled_blobs_in_output(result) == disabled_blobs_in_output(LOCAL_CURATED)


# ──────────────────────────────────────────────────────────────────────────────
# Core scenario: the exact hetzner situation that triggered this fix
# ──────────────────────────────────────────────────────────────────────────────

def test_hetzner_gist_sync_scenario():
    """
    Local (curated): 3 active + disabled section.
    Gist (stale):    same 3 active + the 3 disabled ones still listed as active.
    Merged: only the 3 active survive; disabled block preserved.
    """
    result = merge_files([LOCAL_CURATED, GIST_OLD])

    # Active region: exactly the 3 curated keys
    assert active_blobs(result) == {BLOB_HETZNER, BLOB_IPHONE, BLOB_M5SILVER}

    # Disabled block still present
    assert '# --- Disabled' in result
    disabled = disabled_blobs_in_output(result)
    assert {BLOB_M4PRO, BLOB_RUNPOD, BLOB_UNKNOWN}.issubset(disabled)

    # Labels from local win
    assert '# Termius' in result
