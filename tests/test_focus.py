"""Tests for custom_bins/focus: config groups, ScreenZen pattern mapping, settings decoding, agent delay."""

import importlib.machinery
import importlib.util
import json
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "custom_bins" / "focus"


def load():
    loader = importlib.machinery.SourceFileLoader("focus", str(SCRIPT))
    spec = importlib.util.spec_from_loader("focus", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


ct = load()


@pytest.fixture(autouse=True)
def not_an_agent(monkeypatch, tmp_path):
    # These tests often run inside Claude Code, which sets CLAUDECODE=1; a test that
    # wants agent behaviour sets it itself. The delay queue never touches the real one.
    monkeypatch.delenv("CLAUDECODE", raising=False)
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")


NOTE = """# Test note

```yaml
groups:
  base: {sites: ["file://*.*", localhost]}
  papers: {sites: [arxiv.org]}
  review: {sites: ["github.com/*/*/pull/*"]}
  chat: {apps: [Telegram]}
  feeds: {sites: [x.com, "*casino*"]}
always_allow: [base]
modes:
  research: {allow: [papers, review], block: [chat]}
  writing: {allow: [papers]}
blocklists:
  cold_turkey:
    avoid: {block: [feeds], allow: [base]}
```
"""


@pytest.fixture
def cfg(tmp_path):
    p = tmp_path / "note.md"
    p.write_text(NOTE)
    return ct.load_config(p)


def test_mode_exceptions_are_shared_plus_mode_groups(cfg):
    assert ct.desired_exceptions(cfg, "research") == [
        "file://*.*",
        "localhost",
        "arxiv.org",
        "github.com/*/*/pull/*",
    ]
    assert ct.desired_exceptions(cfg, "writing") == [
        "file://*.*",
        "localhost",
        "arxiv.org",
    ]


def test_unknown_group_is_refused(tmp_path):
    p = tmp_path / "note.md"
    p.write_text(NOTE.replace("allow: [papers]}", "allow: [nope]}"))
    with pytest.raises(SystemExit, match="unknown group 'nope'"):
        ct.load_config(p)


def test_screenzen_allow_list_is_a_superset_of_every_mode(cfg):
    # The wildcard rule is cut to a prefix that allows more; a cut with no domain is dropped.
    assert ct.sz_allow_sites(cfg) == ["localhost", "arxiv.org", "github.com/"]


def test_conflict_when_a_mode_allows_what_an_always_on_block_bans(cfg):
    assert ct.conflicts(cfg) == []
    cfg["groups"]["papers"]["sites"].append("x.com")
    assert ct.conflicts(cfg) == [
        "'x.com' is allowed in mode 'research' but blocked by 'avoid'",
        "'x.com' is allowed in mode 'writing' but blocked by 'avoid'",
    ]


def test_decode_settings_round_trip():
    payload = json.dumps({"blocks": {"b": {"web": ["*.*"]}}}).encode()
    encoded = "CTB17" + "".join(f"{(c + 0x11) % 256:02X}" for c in payload)
    assert ct.decode_settings(encoded) == {"blocks": {"b": {"web": ["*.*"]}}}


def test_agent_loosening_waits_then_runs(cfg, tmp_path, monkeypatch):
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.setenv("CLAUDECODE", "1")
    now = [1_000_000.0]
    monkeypatch.setattr(ct.time, "time", lambda: now[0])
    with pytest.raises(SystemExit) as e:
        ct.gate(cfg, "off", "stopping")
    assert e.value.code == 3
    now[0] += 5 * 60  # still inside the 10-minute delay
    with pytest.raises(SystemExit):
        ct.gate(cfg, "off", "stopping")
    now[0] += 6 * 60
    ct.gate(cfg, "off", "stopping")  # returns: the request may run
    with pytest.raises(SystemExit):  # and it was used up
        ct.gate(cfg, "off", "stopping")


def test_a_due_request_expires(cfg, tmp_path, monkeypatch):
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.setenv("CLAUDECODE", "1")
    now = [1_000_000.0]
    monkeypatch.setattr(ct.time, "time", lambda: now[0])
    with pytest.raises(SystemExit):
        ct.gate(cfg, "off", "stopping")
    now[0] += 10 * 60 + ct.EXPIRE_S + 1
    with pytest.raises(SystemExit):  # queued afresh, not run
        ct.gate(cfg, "off", "stopping")


def test_people_are_never_delayed(cfg, tmp_path, monkeypatch):
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.delenv("CLAUDECODE", raising=False)
    ct.gate(cfg, "off", "stopping")
    assert not (tmp_path / "pending.json").exists()


def test_screenzen_allow_list_leaves_out_what_its_own_groups_block(tmp_path):
    p = tmp_path / "note.md"
    p.write_text(
        NOTE.replace(
            "blocklists:\n",
            "blocklists:\n  screenzen:\n    pause: {block: [papers]}\n",
        )
    )
    cfg = ct.load_config(p)
    assert "arxiv.org" not in ct.sz_allow_sites(cfg)
    assert "arxiv.org" in ct.desired_exceptions(cfg, "writing")


def test_add_to_note_keeps_comments_and_skips_duplicates(tmp_path):
    p = tmp_path / "note.md"
    p.write_text(NOTE.replace("  papers:", "  # the papers group\n  papers:"))
    assert ct.add_to_note(p, "papers", ["openreview.net", "arxiv.org"], "sites") == [
        "openreview.net"
    ]
    text = p.read_text()
    assert "# the papers group" in text and text.startswith("# Test note")
    assert ct.load_config(p)["groups"]["papers"]["sites"] == [
        "arxiv.org",
        "openreview.net",
    ]
    with pytest.raises(SystemExit, match="no group 'nope'"):
        ct.add_to_note(p, "nope", ["x.org"], "sites")


def test_timer_blocks_its_groups_and_is_exported(tmp_path, monkeypatch):
    p = tmp_path / "note.md"
    p.write_text(
        NOTE.replace(
            "blocklists:\n",
            "timers:\n  deep: {block: [papers], minutes: 30}\nblocklists:\n",
        )
    )
    cfg = ct.load_config(p)
    web, apps, missing = ct.timer_lists(cfg, "deep")
    assert (web, apps, missing) == (["arxiv.org"], [], [])
    out = tmp_path / "x.ctbbl"
    ct.cmd_export(cfg, out)
    data = json.loads(out.read_text())
    assert data["timer: deep"]["web"] == ["arxiv.org"]
    assert data["mode: research"]["web"] == ["*.*"]


def test_timer_may_not_share_a_mode_name(tmp_path):
    p = tmp_path / "note.md"
    p.write_text(
        NOTE.replace(
            "blocklists:\n", "timers:\n  writing: {block: [papers]}\nblocklists:\n"
        )
    )
    with pytest.raises(SystemExit, match="same name as a mode"):
        ct.load_config(p)


def test_pull_copies_cold_turkey_additions_into_from_groups(tmp_path, monkeypatch):
    p = tmp_path / "note.md"
    p.write_text(NOTE)
    cfg = ct.load_config(p)
    blocks = {
        "mode: research": {
            "web": ["*.*"],
            "exceptions": ct.desired_exceptions(cfg, "research") + ["openreview.net"],
            "apps": ["app:Telegram.app:ru.keepcoder.Telegram"],
        },
        "avoid": {
            "web": ["x.com", "*casino*", "reddit.com"],
            "exceptions": ["file://*.*", "localhost"],
            "apps": [],
        },
    }
    monkeypatch.setattr(ct, "read_blocks", lambda: blocks)
    monkeypatch.setattr(
        ct,
        "resolve_app",
        lambda name: (Path(f"/Applications/{name}.app"), "ru.keepcoder.Telegram"),
    )
    ct.cmd_pull(p, dry_run=False)
    new = ct.load_config(p)
    assert new["groups"]["from-mode-research"]["sites"] == ["openreview.net"]
    assert "from-mode-research" in new["modes"]["research"]["allow"]
    assert new["groups"]["from-avoid"]["sites"] == ["reddit.com"]
    assert "from-avoid" in new["blocklists"]["cold_turkey"]["avoid"]["block"]
    assert "openreview.net" in ct.desired_exceptions(new, "research")
    monkeypatch.setattr(ct, "read_blocks", lambda: {**blocks})
    assert ct.pull_plan(new, blocks) == []  # a second pull finds nothing


def fake_cold_turkey(monkeypatch, blocks, refuse=()):
    """Stand in for Cold Turkey: -start/-stop flip 'enabled', -add appends, unless refused."""
    calls = []

    def ct_call(*args):
        calls.append(args)
        op, name = args[0], args[1]
        if name in refuse:
            return  # exits 0 and changes nothing, as the real CLI can
        if op in ("-start", "-stop"):
            blocks[name]["enabled"] = "true" if op == "-start" else "false"
        elif op == "-add":
            kind = "exceptions" if args[2] == "-exception" else "web"
            blocks[name][kind].append(args[3])

    monkeypatch.setattr(ct, "ct", ct_call)
    monkeypatch.setattr(ct, "read_blocks", lambda: blocks)
    monkeypatch.setattr(ct.time, "sleep", lambda s: None)
    monkeypatch.delenv("CLAUDECODE", raising=False)
    return calls


def mode_block(cfg, mode, enabled):
    return {
        "enabled": enabled,
        "lock": "none",
        "web": ["*.*"],
        "exceptions": list(ct.desired_exceptions(cfg, mode)),
        "apps": [],
    }


def test_a_failed_switch_leaves_the_old_mode_running(cfg, monkeypatch):
    blocks = {
        "mode: research": mode_block(cfg, "research", "true"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    calls = fake_cold_turkey(monkeypatch, blocks, refuse={"mode: writing"})
    with pytest.raises(SystemExit, match="did not start"):
        ct.cmd_start(cfg, "writing")
    assert blocks["mode: research"]["enabled"] == "true"  # fail closed
    assert not [c for c in calls if c[0] == "-stop"]


def test_a_switch_starts_the_target_before_stopping_the_old_mode(cfg, monkeypatch):
    blocks = {
        "mode: research": mode_block(cfg, "research", "true"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    calls = fake_cold_turkey(monkeypatch, blocks)
    ct.cmd_start(cfg, "writing")
    assert [c[:2] for c in calls] == [
        ("-start", "mode: writing"),
        ("-stop", "mode: research"),
    ]
    assert blocks["mode: research"]["enabled"] == "false"


def test_sync_fails_when_the_cli_silently_drops_an_addition(cfg, monkeypatch):
    block = mode_block(cfg, "writing", "false")
    block["exceptions"].remove("arxiv.org")
    blocks = {
        "mode: research": mode_block(cfg, "research", "false"),
        "mode: writing": block,
    }
    fake_cold_turkey(monkeypatch, blocks, refuse={"mode: writing"})
    with pytest.raises(SystemExit, match="did not appear"):
        ct.cmd_sync(cfg)


def test_a_repeated_add_still_syncs_both_apps(tmp_path, monkeypatch):
    p = tmp_path / "note.md"
    p.write_text(NOTE)
    ran = []
    monkeypatch.setattr(ct, "read_blocks", lambda: {})
    monkeypatch.setattr(ct, "sync_loosen", lambda cfg, blocks: [])
    monkeypatch.setattr(
        ct, "cmd_sync", lambda cfg, gated=True: ran.append(("sync", gated))
    )
    monkeypatch.setattr(
        ct,
        "cmd_screenzen",
        lambda cfg, dry_run, gated=True: ran.append(("sz", dry_run, gated)) or [],
    )
    ct.cmd_add(p, "papers", ["arxiv.org"], app=False)  # already listed
    assert ("sync", False) in ran and ("sz", False, False) in ran


def test_a_queued_agent_add_leaves_the_note_unchanged(tmp_path, monkeypatch):
    p = tmp_path / "note.md"
    p.write_text(NOTE)
    before = p.read_text()
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.setenv("CLAUDECODE", "1")
    monkeypatch.setattr(ct, "read_blocks", lambda: {})
    monkeypatch.setattr(ct, "sync_loosen", lambda cfg, blocks: ["writing:new.org"])
    monkeypatch.setattr(ct, "cmd_screenzen", lambda cfg, dry_run, gated=True: [])
    with pytest.raises(SystemExit) as e:
        ct.cmd_add(p, "papers", ["new.org"], app=False)
    assert e.value.code == 3
    assert p.read_text() == before


def test_an_approved_switch_does_not_cover_a_different_switch(
    cfg, tmp_path, monkeypatch
):
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.setenv("CLAUDECODE", "1")
    now = [1_000_000.0]
    monkeypatch.setattr(ct.time, "time", lambda: now[0])
    blocks = {
        "mode: research": mode_block(cfg, "research", "true"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    monkeypatch.setattr(ct, "read_blocks", lambda: blocks)
    # A regression must never reach the real Cold Turkey CLI from a test.
    monkeypatch.setattr(
        ct, "ct", lambda *a: pytest.fail(f"Cold Turkey CLI called: {a}")
    )
    with pytest.raises(SystemExit):
        ct.cmd_start(cfg, "writing")  # queued: research -> writing
    now[0] += 11 * 60
    blocks["mode: research"]["enabled"] = "false"
    blocks["mode: admin"] = {**mode_block(cfg, "writing", "true")}
    cfg["modes"]["admin"] = {"allow": ["papers"]}
    with pytest.raises(SystemExit) as e:  # admin -> writing is a different request
        ct.cmd_start(cfg, "writing")
    assert e.value.code == 3


def test_off_reports_a_locked_mode_without_queueing(cfg, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.setenv("CLAUDECODE", "1")
    locked = {**mode_block(cfg, "research", "true"), "lock": "delay,5,m"}
    monkeypatch.setattr(ct, "read_blocks", lambda: {"mode: research": locked})
    monkeypatch.setattr(
        ct, "ct", lambda *a: pytest.fail(f"Cold Turkey CLI called: {a}")
    )
    ct.cmd_off(cfg)  # returns: nothing stoppable, so nothing to wait for
    assert "locked" in capsys.readouterr().out
    assert not (tmp_path / "pending.json").exists()


def test_screenzen_block_covers_allowed_paths_and_subdomains(tmp_path):
    p = tmp_path / "note.md"
    p.write_text(
        NOTE.replace(
            "  papers: {sites: [arxiv.org]}",
            '  papers: {sites: [arxiv.org, "x.com/*", m.x.com]}',
        ).replace(
            "blocklists:\n", "blocklists:\n  screenzen:\n    pause: {block: [feeds]}\n"
        )
    )
    cfg = ct.load_config(p)
    allowed = ct.sz_allow_sites(cfg)
    assert (
        "x.com/" not in allowed and "m.x.com" not in allowed and "arxiv.org" in allowed
    )


def test_an_agent_pull_into_an_allow_list_waits(tmp_path, monkeypatch):
    p = tmp_path / "note.md"
    p.write_text(NOTE)
    cfg = ct.load_config(p)
    before = p.read_text()
    blocks = {
        "mode: research": {
            "web": ["*.*"],
            "exceptions": ct.desired_exceptions(cfg, "research") + ["reddit.com"],
            "apps": [],
        }
    }
    monkeypatch.setattr(ct, "read_blocks", lambda: blocks)
    monkeypatch.setattr(ct, "resolve_app", lambda name: None)
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.setenv("CLAUDECODE", "1")
    with pytest.raises(SystemExit) as e:
        ct.cmd_pull(p, dry_run=False)
    assert e.value.code == 3 and p.read_text() == before


def test_an_app_add_does_not_wait_for_pending_site_syncs(tmp_path, monkeypatch):
    p = tmp_path / "note.md"
    p.write_text(NOTE)
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.setenv("CLAUDECODE", "1")
    monkeypatch.setattr(ct, "read_blocks", lambda: {})
    monkeypatch.setattr(ct, "sync_loosen", lambda cfg, blocks: ["writing:other.org"])
    ran = []
    monkeypatch.setattr(ct, "cmd_sync", lambda cfg, gated=True: ran.append("sync"))
    monkeypatch.setattr(
        ct, "cmd_screenzen", lambda cfg, dry_run, gated=True: ran.append("sz") or []
    )
    ct.cmd_add(p, "chat", ["Signal"], app=True)  # tightening only: runs at once
    assert "sync" not in ran and ran.count("sz") == 2


def test_a_pull_into_a_reused_group_counts_as_loosening(tmp_path, monkeypatch):
    # An existing from-avoid group is also named by research's allow list, so pulling a
    # banned site into it would allow that site in research.
    p = tmp_path / "note.md"
    p.write_text(
        NOTE.replace(
            "  chat: {apps: [Telegram]}",
            "  chat: {apps: [Telegram]}\n  from-avoid: {sites: [old.org]}",
        ).replace(
            "research: {allow: [papers, review]",
            "research: {allow: [papers, review, from-avoid]",
        )
    )
    cfg = ct.load_config(p)
    before = p.read_text()
    blocks = {
        "avoid": {
            "web": ["x.com", "*casino*", "reddit.com"],
            "exceptions": ["file://*.*", "localhost"],
            "apps": [],
        }
    }
    monkeypatch.setattr(ct, "read_blocks", lambda: blocks)
    monkeypatch.setattr(ct, "resolve_app", lambda name: None)
    monkeypatch.setenv("CLAUDECODE", "1")
    with pytest.raises(SystemExit) as e:
        ct.cmd_pull(p, dry_run=False)
    assert e.value.code == 3 and p.read_text() == before
