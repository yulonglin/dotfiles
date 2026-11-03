"""Tests for custom_bins/focus: config groups, ScreenZen pattern mapping, settings decoding, agent delay."""

import datetime as dt
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
def isolated(monkeypatch, tmp_path):
    # These tests often run inside Claude Code, which sets CLAUDECODE=1; a test that
    # wants agent behaviour sets it itself. The delay queue, the backups and ScreenZen's
    # preferences are never the real ones: a mode switch writes ScreenZen.
    monkeypatch.delenv("CLAUDECODE", raising=False)
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.setattr(ct, "BACKUP_DIR", tmp_path / "backups")
    monkeypatch.setattr(ct, "BREAK_FILE", tmp_path / "break.json")
    monkeypatch.setattr(ct, "SZ_DOMAIN", tmp_path / "no-screenzen" / "prefs")
    monkeypatch.setattr(
        ct, "sz_export", lambda: pytest.fail("test reached real ScreenZen prefs")
    )


def test_screenzen_follows_the_running_mode(cfg):
    research = ct.sz_allow_sites(cfg, ["research"])
    assert "arxiv.org" in research and "github.com/" in research
    assert "github.com/" not in ct.sz_allow_sites(cfg, ["writing"])


def test_no_mode_is_the_widest_screenzen_list(cfg):
    # Every mode tightens no mode, so a break never pauses its mode's own sites.
    no_mode = set(ct.sz_allow_sites(cfg, []))
    for mode in cfg["modes"]:
        assert set(ct.sz_allow_sites(cfg, [mode])) <= no_mode
    assert {"localhost", "arxiv.org", "github.com/"} <= no_mode


def test_a_switch_waives_the_new_modes_sites_even_though_no_mode_has_them(
    cfg, tmp_path, monkeypatch
):
    # The waiver is measured against the shared list; against the no-mode list, which
    # now holds every mode's sites, it would waive nothing and stall every switch.
    plist = tmp_path / "sz" / "prefs.plist"
    plist.parent.mkdir()
    plist.write_text("")
    monkeypatch.setattr(ct, "SZ_DOMAIN", plist.with_suffix(""))
    monkeypatch.setenv("CLAUDECODE", "1")
    writes = []
    monkeypatch.setattr(
        ct,
        "cmd_screenzen",
        lambda cfg, dry_run, **k: (
            ["✅ focus: writing:+arxiv.org"] if dry_run else writes.append(k["modes"])
        ),
    )
    ct.sz_follow(cfg, ["writing"], switched=True)
    assert writes == [["writing"]]


def test_a_switch_points_screenzen_at_the_new_mode(cfg, monkeypatch):
    blocks = {
        "mode: research": mode_block(cfg, "research", "true"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    fake_cold_turkey(monkeypatch, blocks)
    followed = []
    monkeypatch.setattr(
        ct, "sz_follow", lambda cfg, modes, switched: followed.append((modes, switched))
    )
    ct.cmd_start(cfg, "writing")
    assert followed == [(["writing"], True)]
    ct.cmd_start(cfg, "writing")  # already running: nothing switched
    assert followed[-1] == (["writing"], False)


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
    # sync applies the note to both apps; the gate already ran once, in add itself
    assert ("sync", False) in ran


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


def test_a_switch_waits_on_screenzen_loosening_beyond_the_mode(
    cfg, tmp_path, monkeypatch
):
    plist = tmp_path / "sz" / "prefs.plist"
    plist.parent.mkdir()
    plist.write_text("")
    monkeypatch.setattr(ct, "SZ_DOMAIN", plist.with_suffix(""))
    monkeypatch.setenv("CLAUDECODE", "1")
    writes = []

    def fake_sz(cfg, dry_run, gated=True, modes=None, quiet=False):
        if not dry_run:
            writes.append(modes)
        # the mode's own site, plus a 🚫 entry removed by a note edit
        return ["✅ always:+arxiv.org", "🚫 pause:-x.com"]

    monkeypatch.setattr(ct, "cmd_screenzen", fake_sz)
    ct.sz_follow(cfg, ["research"], switched=True)
    assert writes == []  # queued, not written
    monkeypatch.setattr(
        ct,
        "cmd_screenzen",
        lambda cfg, dry_run, **k: (
            ["✅ always:+arxiv.org"] if dry_run else writes.append(k["modes"])
        ),
    )
    ct.sz_follow(cfg, ["research"])  # same mode re-run: approved nothing, so it waits
    assert writes == []
    ct.sz_follow(
        cfg, ["research"], switched=True
    )  # a real switch approved the mode's sites
    assert writes == [["research"]]


def sz_prefs(groups):
    import plistlib as pl

    return pl.dumps({"pauseShieldInstances": json.dumps(groups).encode()})


def test_screenzen_gets_one_group_per_mode_and_only_the_running_one_is_on(
    cfg, monkeypatch
):
    template = {
        "groupName": "✅ always 💯",
        "id": "OLD",
        "isDisabled": False,
        "alwaysActive": True,
        "customSites": [],
        "apps": [],
    }
    monkeypatch.setattr(ct, "sz_export", lambda: sz_prefs([template]))
    loosen = ct.cmd_screenzen(cfg, dry_run=True, modes=["research"], quiet=True)
    assert "screenzen:+arxiv.org" in loosen  # research's sites now pass
    assert "screenzen:+localhost" in loosen
    # the template itself is left as it was; only the dry run's copy changed
    assert template["isDisabled"] is False


def test_a_screenzen_block_group_stands_aside_in_its_off_in_modes(
    tmp_path, monkeypatch
):
    p = tmp_path / "note.md"
    p.write_text(
        NOTE.replace(
            "blocklists:\n",
            'blocklists:\n  screenzen:\n    "🚫 chat": {block: [chat], off_in: [writing]}\n',
        )
    )
    cfg = ct.load_config(p)
    groups = [
        {
            "groupName": "✅ always",
            "id": "A",
            "isDisabled": False,
            "alwaysActive": True,
            "customSites": [],
            "apps": [],
        },
        {
            "groupName": "🚫 chat",
            "id": "B",
            "isDisabled": False,
            "alwaysActive": True,
            "customSites": [],
            "apps": [],
        },
    ]
    monkeypatch.setattr(ct, "sz_export", lambda: sz_prefs(groups))
    monkeypatch.setattr(
        ct, "resolve_app", lambda name: (Path(f"/Applications/{name}.app"), "x")
    )
    assert "🚫 chat:off" in ct.cmd_screenzen(
        cfg, dry_run=True, modes=["writing"], quiet=True
    )
    assert "🚫 chat:off" not in ct.cmd_screenzen(
        cfg, dry_run=True, modes=["research"], quiet=True
    )
    bad = tmp_path / "bad.md"
    bad.write_text(p.read_text().replace("off_in: [writing]", "off_in: [nope]"))
    with pytest.raises(SystemExit, match="unknown mode 'nope'"):
        ct.load_config(bad)


def test_off_says_so_when_no_mode_is_running(cfg, monkeypatch, capsys):
    monkeypatch.setattr(
        ct,
        "read_blocks",
        lambda: {"mode: research": mode_block(cfg, "research", "false")},
    )
    monkeypatch.setattr(
        ct, "ct", lambda *a: pytest.fail(f"Cold Turkey CLI called: {a}")
    )
    ct.cmd_off(cfg)
    assert "no mode was running" in capsys.readouterr().out


def test_off_hours_spans_including_past_midnight():
    cfg = {"off_hours": ["22:00-23:15", "23:50-00:30"]}
    at = lambda h, m: dt.datetime(2026, 10, 30, h, m)  # noqa: E731
    assert ct.in_off_hours(cfg, at(22, 30)) and not ct.in_off_hours(cfg, at(23, 15))
    assert ct.in_off_hours(cfg, at(0, 10)) and not ct.in_off_hours(cfg, at(12, 0))


def test_off_outside_off_hours_points_to_a_break(cfg, monkeypatch):
    cfg["off_hours"] = ["22:00-23:15"]
    monkeypatch.setattr(ct, "in_off_hours", lambda cfg: False)
    monkeypatch.setattr(
        ct,
        "read_blocks",
        lambda: {"mode: research": mode_block(cfg, "research", "true")},
    )
    monkeypatch.setattr(
        ct, "ct", lambda *a: pytest.fail(f"Cold Turkey CLI called: {a}")
    )
    with pytest.raises(SystemExit, match="focus break"):
        ct.cmd_off(cfg)


def test_a_break_stops_the_mode_and_the_waiter_starts_it_again(
    cfg, tmp_path, monkeypatch
):
    monkeypatch.setattr(ct, "BREAK_FILE", tmp_path / "break.json")
    blocks = {"mode: research": mode_block(cfg, "research", "true")}
    fake_cold_turkey(monkeypatch, blocks)
    monkeypatch.setattr(ct, "sz_follow", lambda *a, **k: None)
    spawned = []
    monkeypatch.setattr(ct.subprocess, "Popen", lambda cmd, **k: spawned.append(cmd))
    ct.cmd_break(cfg, ["10"])
    assert blocks["mode: research"]["enabled"] == "false" and spawned[0][-1] == "resume"
    with pytest.raises(SystemExit, match="1 to 30"):
        ct.cmd_break(cfg, ["45"])
    # the waiter: once the break is over, research comes back
    b = json.loads((tmp_path / "break.json").read_text())
    (tmp_path / "break.json").write_text(json.dumps({**b, "until": 0}))
    ct.cmd_resume(cfg)
    assert blocks["mode: research"]["enabled"] == "true"
    assert not (tmp_path / "break.json").exists()


def test_a_block_group_off_in_none_stands_aside_with_no_mode(cfg):
    bl = {"off_in": ["admin", "none"]}
    assert ct.sz_group_off(bl, []) and ct.sz_group_off(bl, ["admin"])
    assert not ct.sz_group_off(bl, ["research"])


def test_an_expired_break_is_ended_by_any_command_and_restores_every_mode(
    cfg, tmp_path, monkeypatch
):
    blocks = {
        "mode: research": mode_block(cfg, "research", "false"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    fake_cold_turkey(monkeypatch, blocks)
    monkeypatch.setattr(ct, "sz_follow", lambda *a, **k: None)
    (tmp_path / "break.json").write_text(
        json.dumps({"modes": ["research", "writing"], "until": 0})
    )
    assert ct.end_break(cfg)
    assert blocks["mode: research"]["enabled"] == "true"
    assert blocks["mode: writing"]["enabled"] == "true"
    assert not (tmp_path / "break.json").exists()


def test_a_malformed_break_file_never_blocks(cfg, tmp_path, monkeypatch):
    monkeypatch.setattr(ct, "read_blocks", lambda: {})
    (tmp_path / "break.json").write_text("{not json")
    assert ct.end_break(cfg) and not (tmp_path / "break.json").exists()
    (tmp_path / "break.json").write_text(json.dumps({"until": "soon"}))
    assert ct.end_break(cfg)


def test_no_mode_stops_when_the_break_timer_cannot_start(cfg, tmp_path, monkeypatch):
    blocks = {"mode: research": mode_block(cfg, "research", "true")}
    fake_cold_turkey(monkeypatch, blocks)

    def no_spawn(*a, **k):
        raise OSError("no fork")

    monkeypatch.setattr(ct.subprocess, "Popen", no_spawn)
    with pytest.raises(SystemExit, match="no mode was stopped"):
        ct.cmd_break(cfg, ["10"])
    assert blocks["mode: research"]["enabled"] == "true"
    assert not (tmp_path / "break.json").exists()


def test_a_failed_restore_keeps_the_break_record_for_a_retry(
    cfg, tmp_path, monkeypatch
):
    blocks = {"mode: research": mode_block(cfg, "research", "false")}
    fake_cold_turkey(monkeypatch, blocks, refuse={"mode: research"})
    (tmp_path / "break.json").write_text(
        json.dumps({"modes": ["research"], "until": 0})
    )
    with pytest.raises(SystemExit):
        ct.end_break(cfg)
    assert (tmp_path / "break.json").exists()


def test_the_waiter_gets_the_same_config_and_a_failed_start_keeps_the_break(
    cfg, tmp_path, monkeypatch
):
    monkeypatch.setattr(ct, "CONFIG_PATH", tmp_path / "other-note.md")
    monkeypatch.setattr(ct, "AGENT_PLIST", tmp_path / "agent.plist")
    blocks = {"mode: research": mode_block(cfg, "research", "true")}
    fake_cold_turkey(monkeypatch, blocks)
    monkeypatch.setattr(ct, "sz_follow", lambda *a, **k: None)
    spawned = []
    monkeypatch.setattr(ct.subprocess, "Popen", lambda cmd, **k: spawned.append(cmd))
    ct.cmd_break(cfg, ["5"])
    assert spawned[0][-3:] == ["--config", str(tmp_path / "other-note.md"), "resume"]
    # starting a mode by hand that fails leaves the break in place
    fake_cold_turkey(monkeypatch, blocks, refuse={"mode: research"})
    with pytest.raises(SystemExit):
        ct.cmd_start(cfg, "research")
    assert (tmp_path / "break.json").exists()


def test_uninstall_agent_boots_out_and_removes_the_plist_then_is_quiet(
    tmp_path, monkeypatch, capsys
):
    plist = tmp_path / "agent.plist"
    plist.write_text("<plist/>")
    monkeypatch.setattr(ct, "AGENT_PLIST", plist)
    calls = []

    class Done:
        def __init__(self, rc):
            self.returncode = rc

    loaded = [True]

    def fake_run(cmd, **k):
        calls.append(cmd)
        rc = 0 if loaded[0] else 3  # launchctl bootout fails for a job not loaded
        loaded[0] = False
        return Done(rc)

    monkeypatch.setattr(ct.subprocess, "run", fake_run)
    ct.cmd_uninstall_agent()
    assert calls == [["launchctl", "bootout", f"gui/{ct.os.getuid()}/{ct.AGENT_LABEL}"]]
    assert not plist.exists()
    assert ct.AGENT_LABEL in capsys.readouterr().out
    # a second run finds nothing: it succeeds and prints nothing
    ct.cmd_uninstall_agent()
    assert len(calls) == 2
    assert capsys.readouterr().out == ""


def test_uninstall_agent_runs_without_a_config_note(tmp_path, monkeypatch):
    # deploy.sh --no-focus must remove the job even on a machine whose note is gone
    ran = []
    monkeypatch.setattr(ct, "cmd_uninstall_agent", lambda: ran.append(True))
    monkeypatch.setattr(
        ct.sys,
        "argv",
        ["focus", "--config", str(tmp_path / "gone.md"), "uninstall-agent"],
    )
    ct.main()
    assert ran == [True]


def test_screenzen_follows_an_app_whose_bundle_id_changed(
    tmp_path, monkeypatch, capsys
):
    p = tmp_path / "note.md"
    p.write_text(
        NOTE.replace(
            "blocklists:\n",
            'blocklists:\n  screenzen:\n    "🚫 chat": {block: [chat]}\n',
        )
    )
    cfg = ct.load_config(p)
    old = {
        **ct.APP_TEMPLATE,
        "appName": "Telegram",
        "appBundle": "old.id",
        "appUrl": "/x",
    }
    groups = [
        {
            "groupName": "✅ always",
            "id": "A",
            "isDisabled": False,
            "alwaysActive": True,
            "customSites": [],
            "apps": [],
        },
        {
            "groupName": "🚫 chat",
            "id": "B",
            "isDisabled": False,
            "alwaysActive": True,
            "customSites": [],
            "apps": [old],
        },
    ]
    monkeypatch.setattr(ct, "sz_export", lambda: sz_prefs(groups))
    monkeypatch.setattr(
        ct, "resolve_app", lambda name: (Path(f"/Applications/{name}.app"), "new.id")
    )
    ct.cmd_screenzen(cfg, dry_run=True, modes=[])
    assert "Telegram (now new.id)" in capsys.readouterr().out


REX = "com.superlogical.rex"


def fake_screenzen_launch(monkeypatch, windows, active):
    """Feed hand_back_focus a sequence of (on screen, on top) window states and a fixed
    front app; record the 'open' calls it makes. The last state repeats."""
    states = iter(windows)
    last = [windows[-1]]
    opened = []

    def sz_window():
        last[0] = next(states, last[0])
        return last[0]

    monkeypatch.setattr(ct, "sz_window", sz_window)
    monkeypatch.setattr(ct, "close_sz_window", lambda: False)  # no Accessibility
    monkeypatch.setattr(ct, "frontmost_bundle", lambda: active)
    monkeypatch.setattr(ct.time, "sleep", lambda s: None)
    monkeypatch.setattr(
        ct.subprocess, "run", lambda cmd, **k: opened.append(cmd) or None
    )
    return opened


def test_focus_is_handed_back_once_screenzen_window_is_up(monkeypatch):
    # ScreenZen took the front: 'open -b' the previous app is enough, and only once
    # the window exists (handing back before it existed let it land on top).
    opened = fake_screenzen_launch(
        monkeypatch,
        [(False, False), (False, False), (True, True), (True, False)],
        active=ct.SZ_BUNDLE,
    )
    ct.hand_back_focus(REX)
    assert opened == [["open", "-b", REX]]


def test_no_second_raise_while_macos_slides_back_to_a_full_screen_app(monkeypatch):
    # Handing back to a full-screen app slides Spaces for up to a second, during which
    # ScreenZen still lists on top with the app already active. Bouncing through Finder
    # then left Finder in front (2026-11-03), so wait instead.
    states = iter([(True, True), (True, True), (True, True), (False, False)])
    fronts = iter([ct.SZ_BUNDLE, REX, REX, REX])
    opened = fake_screenzen_launch(monkeypatch, [(True, True)], active=None)
    monkeypatch.setattr(ct, "sz_window", lambda: next(states))
    monkeypatch.setattr(ct, "frontmost_bundle", lambda: next(fronts))
    ct.hand_back_focus(REX)
    assert opened == [["open", "-b", REX]]


def test_window_that_comes_back_on_top_is_raised_again_at_most_three_times(
    monkeypatch,
):
    opened = fake_screenzen_launch(
        monkeypatch,
        [(True, True), (True, False), (True, True), (True, False), (True, False)],
        active=ct.SZ_BUNDLE,
    )
    ct.hand_back_focus(REX)
    assert opened == [["open", "-b", REX]] * 2
    opened.clear()
    clock = iter(range(100))
    monkeypatch.setattr(ct.time, "monotonic", lambda: next(clock) * 0.3)
    stuck = fake_screenzen_launch(monkeypatch, [(True, True)], active=ct.SZ_BUNDLE)
    ct.hand_back_focus(REX)
    assert stuck == [["open", "-b", REX]] * 3


def test_no_hand_back_when_screenzen_window_never_appears(monkeypatch, tmp_path):
    clock = iter(range(100))
    monkeypatch.setattr(ct.time, "monotonic", lambda: next(clock))
    monkeypatch.setattr(ct, "SZ_TRACE", tmp_path / "trace.log")
    monkeypatch.setenv("FOCUS_TRACE", "1")
    opened = fake_screenzen_launch(monkeypatch, [(False, False)], active=REX)
    ct.hand_back_focus(REX)
    assert opened == []
    assert f"front was {REX}" in (tmp_path / "trace.log").read_text()
    # nothing to do when ScreenZen itself was in front, the screen was locked, or
    # nothing was in front
    ct.hand_back_focus(ct.SZ_BUNDLE)
    ct.hand_back_focus("com.apple.loginwindow")
    ct.hand_back_focus(None)
    assert opened == []


def test_screenzen_window_is_closed_then_the_front_handed_back(monkeypatch):
    # Over a full-screen app no raise gets above ScreenZen's window, so close it.
    opened = fake_screenzen_launch(
        monkeypatch, [(False, False), (True, True)], active=ct.SZ_BUNDLE
    )
    closed = []
    monkeypatch.setattr(ct, "close_sz_window", lambda: closed.append(1) or True)
    ct.hand_back_focus(REX)
    assert closed == [1]
    assert opened == [["open", "-b", REX]]
