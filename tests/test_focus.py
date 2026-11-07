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
REAL_WAKE = ct.wake_agent  # the autouse fixture stubs ct.wake_agent


@pytest.fixture(autouse=True)
def isolated(monkeypatch, tmp_path):
    # These tests often run inside Claude Code, which sets CLAUDECODE=1; a test that
    # wants agent behaviour sets it itself. The delay queue, the backups and ScreenZen's
    # preferences are never the real ones: a mode switch writes ScreenZen.
    monkeypatch.delenv("CLAUDECODE", raising=False)
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.setattr(ct, "BACKUP_DIR", tmp_path / "backups")
    monkeypatch.setattr(ct, "BREAK_FILE", tmp_path / "break.json")
    monkeypatch.setattr(ct, "ONLY_FILE", tmp_path / "only.json")
    monkeypatch.setattr(ct, "notify", lambda text: None)
    monkeypatch.setattr(ct, "wake_agent", lambda args: None)
    monkeypatch.setattr(ct, "frontmost_bundle", lambda: None)
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
        if name not in refuse:
            if op in ("-start", "-stop"):
                blocks[name]["enabled"] = "true" if op == "-start" else "false"
                if "-lock" in args:
                    blocks[name]["lock"] = "2026,11,6,21,56"  # the end time, as stored
            elif op == "-add":
                kind = "exceptions" if args[2] == "-exception" else "web"
                blocks[name][kind].append(args[3])

    monkeypatch.setattr(ct, "ct_send", ct_call)
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


def test_sync_adds_a_timers_new_site_and_status_says_sync_can(
    tmp_path, monkeypatch, capsys
):
    p = tmp_path / "note.md"
    p.write_text(
        NOTE.replace(
            "blocklists:\n",
            "timers:\n  deep: {block: [papers], minutes: 30}\nblocklists:\n",
        )
    )
    cfg = ct.load_config(p)
    timer = {"enabled": "false", "web": [], "exceptions": ["file://*.*"], "apps": []}
    blocks = {
        "mode: research": mode_block(cfg, "research", "false"),
        "mode: writing": mode_block(cfg, "writing", "false"),
        "timer: deep": timer,
    }
    fake_cold_turkey(monkeypatch, blocks)

    ct.cmd_status(cfg)
    assert "timer: deep: differs (focus sync adds these)" in capsys.readouterr().out

    ct.cmd_sync(cfg)
    assert timer["web"] == ["arxiv.org"]
    assert "timer: deep: added arxiv.org" in capsys.readouterr().out


def test_sync_reports_every_addition_that_fails(cfg, monkeypatch):
    research, writing = (
        mode_block(cfg, "research", "false"),
        mode_block(cfg, "writing", "false"),
    )
    research["exceptions"].remove("arxiv.org")
    writing["exceptions"].remove("arxiv.org")
    blocks = {"mode: research": research, "mode: writing": writing}
    fake_cold_turkey(monkeypatch, blocks, refuse=set(blocks))
    with pytest.raises(SystemExit, match=r"(?s)research.*writing"):
        ct.cmd_sync(cfg)


def test_sync_lands_each_add_before_sending_the_next(cfg, monkeypatch, capsys):
    # The real slot holds one command and only a wake reads it, so a second add sent
    # without one replaces the first. That is how a site went missing on 4 Nov 2026.
    research = mode_block(cfg, "research", "false")
    writing = mode_block(cfg, "writing", "false")
    research["exceptions"].remove("arxiv.org")
    writing["exceptions"].remove("arxiv.org")
    blocks = {"mode: research": research, "mode: writing": writing}
    slot = []

    def send(*args):
        slot[:] = [args]

    def wake(args):
        for _, name, _, site in slot:
            blocks[name]["exceptions"].append(site)
        slot.clear()

    monkeypatch.setattr(ct, "ct_send", send)
    monkeypatch.setattr(ct, "wake_agent", wake)
    monkeypatch.setattr(ct, "read_blocks", lambda: blocks)
    monkeypatch.setattr(ct.time, "sleep", lambda s: None)
    ct.cmd_sync(cfg)
    assert "arxiv.org" in research["exceptions"]
    assert "arxiv.org" in writing["exceptions"]
    assert "mode: writing: added 1 site(s)" in capsys.readouterr().out


def test_a_change_stays_unlanded_until_the_agent_is_woken(cfg, monkeypatch):
    blocks = {"mode: writing": mode_block(cfg, "writing", "false")}
    monkeypatch.setattr(ct, "ct_send", lambda *a: None)
    monkeypatch.setattr(ct, "read_blocks", lambda: blocks)
    monkeypatch.setattr(ct.time, "sleep", lambda s: None)
    with pytest.raises(SystemExit, match="did not start"):  # nothing read the slot
        ct.switch("mode: writing", on=True)

    def wake(args):
        blocks["mode: writing"]["enabled"] = "true"

    monkeypatch.setattr(ct, "wake_agent", wake)
    ct.switch("mode: writing", on=True)


def test_the_front_goes_back_to_the_app_that_had_it(monkeypatch):
    fronts = iter(["com.superlogical.rex", ct.CT_BUNDLE])
    monkeypatch.setattr(ct, "frontmost_bundle", lambda: next(fronts))
    monkeypatch.setattr(ct, "ct_send", lambda *a: None)
    ran = []
    monkeypatch.setattr(ct.subprocess, "run", lambda cmd, **k: ran.append(cmd))
    assert ct.ct_apply(("-start", "x"), lambda: True)
    assert ran == [["open", "-b", "com.superlogical.rex"]]


def test_the_front_goes_back_even_when_nothing_lands(monkeypatch):
    fronts = iter(["com.superlogical.rex", ct.CT_BUNDLE])
    monkeypatch.setattr(ct, "frontmost_bundle", lambda: next(fronts))
    monkeypatch.setattr(ct, "ct_send", lambda *a: None)
    monkeypatch.setattr(ct.time, "sleep", lambda s: None)
    ran = []
    monkeypatch.setattr(ct.subprocess, "run", lambda cmd, **k: ran.append(cmd))
    assert not ct.ct_apply(("-start", "x"), lambda: False)
    assert ran == [["open", "-b", "com.superlogical.rex"]]


@pytest.mark.parametrize("front", [None, "com.apple.loginwindow", ct.CT_BUNDLE])
def test_nothing_is_raised_when_there_is_no_app_to_go_back_to(monkeypatch, front):
    monkeypatch.setattr(ct, "frontmost_bundle", lambda: front)
    monkeypatch.setattr(ct, "ct_send", lambda *a: None)
    monkeypatch.setattr(
        ct.subprocess, "run", lambda cmd, **k: pytest.fail("raised an app")
    )
    assert ct.ct_apply(("-start", "x"), lambda: True)


def test_the_wake_goes_to_the_agent_after_the_command_is_in_the_slot(monkeypatch):
    # Woken too early, the agent reads an empty slot; and the idling CLI shares its
    # bundle id, so the wake goes by the pid of the '-agent' process.
    slots = iter(["", '("/app", "-start", "mode: writing")'])
    ran = []

    def fake_run(cmd, **k):
        ran.append(cmd)
        out = ""
        if cmd[0] == "defaults":
            out = next(slots)
        elif cmd[0] == "pgrep":
            out = "84514\n"
        return type("R", (), {"stdout": out, "returncode": 0})()

    monkeypatch.setattr(ct.subprocess, "run", fake_run)
    monkeypatch.setattr(ct.time, "sleep", lambda s: None)
    REAL_WAKE(("-start", "mode: writing"))
    assert [c[0] for c in ran] == ["defaults", "defaults", "pgrep", "osascript"]
    assert "Cold Turkey Blocker -agent" in ran[2][-1]
    assert "(84514)" in ran[3][-1]


def test_a_failed_switch_says_the_command_may_still_run_and_keeps_the_old_mode(
    cfg, monkeypatch
):
    blocks = {
        "mode: research": mode_block(cfg, "research", "true"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    calls = fake_cold_turkey(monkeypatch, blocks, refuse={"mode: writing"})
    with pytest.raises(SystemExit, match="did not start.*can run when Cold Turkey"):
        ct.cmd_start(cfg, "writing")
    assert blocks["mode: research"]["enabled"] == "true"  # fail closed
    assert not [c for c in calls if c[0] == "-stop"]


def test_a_switch_returns_when_the_database_changes_not_when_the_cli_exits(
    cfg, monkeypatch
):
    blocks = {"mode: writing": mode_block(cfg, "writing", "false")}
    launched = []

    class SlowCli:  # the real CLI idles for 5 s; waiting on it would fail this test
        def __init__(self, cmd, **kwargs):
            launched.append((cmd, kwargs))
            blocks["mode: writing"]["enabled"] = "true"

        def wait(self, *a, **k):
            pytest.fail("focus waited for the CLI to exit")

    monkeypatch.setattr(ct.subprocess, "Popen", SlowCli)
    monkeypatch.setattr(ct, "read_blocks", lambda: blocks)
    ct.switch("mode: writing", on=True)
    ((cmd, kwargs),) = launched
    assert cmd[1:] == ["-start", "mode: writing"]
    assert kwargs["start_new_session"]  # it outlives focus, which has moved on


def test_a_lock_timer_reports_what_the_database_shows(cfg, monkeypatch, capsys):
    # It used to exit on the CLI's "isn't responding", so 'focus deep' reported a
    # failure even for a block that had started.
    cfg["timers"] = {"deep": {}}
    block = {**mode_block(cfg, "writing", "false")}
    blocks = {ct.TIMER_PREFIX + "deep": block}
    calls = fake_cold_turkey(monkeypatch, blocks)
    ct.cmd_timer(cfg, "deep", ["1"])
    assert calls == [("-start", ct.TIMER_PREFIX + "deep", "-lock", "1")]
    assert "locked until" in capsys.readouterr().out


def test_a_running_unlocked_timer_is_not_called_locked_when_the_lock_never_lands(
    cfg, monkeypatch
):
    # Already enabled, so 'enabled' alone would pass while nothing holds the lock.
    cfg["timers"] = {"deep": {}}
    blocks = {ct.TIMER_PREFIX + "deep": mode_block(cfg, "writing", "true")}
    fake_cold_turkey(monkeypatch, blocks, refuse=set(blocks))
    with pytest.raises(SystemExit, match="did not start"):
        ct.cmd_timer(cfg, "deep", ["1"])


def test_a_lock_timer_that_never_lands_says_so(cfg, monkeypatch):
    cfg["timers"] = {"deep": {}}
    blocks = {ct.TIMER_PREFIX + "deep": mode_block(cfg, "writing", "false")}
    fake_cold_turkey(monkeypatch, blocks, refuse=set(blocks))
    with pytest.raises(SystemExit, match="did not start"):
        ct.cmd_timer(cfg, "deep", ["1"])


def installed_screenzen(tmp_path, monkeypatch):
    plist = tmp_path / "sz" / "prefs.plist"
    plist.parent.mkdir()
    plist.write_text("")
    monkeypatch.setattr(ct, "SZ_DOMAIN", plist.with_suffix(""))


def test_a_person_gets_screenzen_in_the_background(cfg, tmp_path, monkeypatch, capsys):
    installed_screenzen(tmp_path, monkeypatch)
    spawned = []
    monkeypatch.setattr(ct, "spawn_self", lambda *a: spawned.append(a))
    monkeypatch.setattr(
        ct, "cmd_screenzen", lambda *a, **k: pytest.fail("wrote in the foreground")
    )
    ct.sz_follow(cfg, ["writing"], switched=True)
    assert spawned == [("sz-apply",)]
    assert "sites without a pause screen" in capsys.readouterr().out


def test_an_agent_stays_in_the_foreground_so_it_sees_the_gate(
    cfg, tmp_path, monkeypatch
):
    installed_screenzen(tmp_path, monkeypatch)
    monkeypatch.setenv("CLAUDECODE", "1")
    monkeypatch.setattr(
        ct, "spawn_self", lambda *a: pytest.fail("an agent skipped the gate")
    )
    writes = []
    monkeypatch.setattr(
        ct,
        "cmd_screenzen",
        lambda cfg, dry_run, **k: [] if dry_run else writes.append(k["modes"]),
    )
    ct.sz_follow(cfg, ["writing"], switched=True)
    assert writes == [["writing"]]


def test_the_background_write_follows_what_is_running_when_it_gets_the_lock(
    cfg, tmp_path, monkeypatch
):
    monkeypatch.setattr(ct, "SZ_LOCK", tmp_path / "state" / "screenzen.lock")
    kwargs = []
    monkeypatch.setattr(ct, "cmd_screenzen", lambda cfg, **k: kwargs.append(k))
    ct.cmd_sz_apply(cfg)
    assert kwargs == [{"dry_run": False, "quiet": True}]  # no modes, and still gated


def test_an_agent_cannot_call_the_background_write_to_skip_the_gate(
    cfg, tmp_path, monkeypatch
):
    monkeypatch.setattr(ct, "SZ_LOCK", tmp_path / "state" / "screenzen.lock")
    monkeypatch.setenv("CLAUDECODE", "1")
    allow = {
        "groupName": "✅ always",
        "id": "1",
        "isDisabled": False,
        "alwaysActive": True,
        "customSites": [],
        "apps": [],
    }
    monkeypatch.setattr(ct, "sz_export", lambda: sz_prefs([allow]))
    monkeypatch.setattr(ct, "running_modes", lambda cfg: ["writing"])
    monkeypatch.setattr(ct, "read_only", lambda: None)
    told = []
    monkeypatch.setattr(ct, "notify", told.append)
    ct.cmd_sz_apply(cfg)
    assert told  # queued by the gate, not written
    assert not (ct.BACKUP_DIR).exists()


def test_the_background_write_is_dispatched_without_ending_breaks(
    cfg, tmp_path, monkeypatch
):
    note = tmp_path / "note.md"
    note.write_text(NOTE)
    monkeypatch.setattr(ct.sys, "argv", ["focus", "--config", str(note), "sz-apply"])
    ran = []
    monkeypatch.setattr(ct, "cmd_sz_apply", lambda cfg: ran.append("apply"))
    monkeypatch.setattr(ct, "end_break", lambda cfg: ran.append("end_break"))
    monkeypatch.setattr(ct, "end_only", lambda cfg: ran.append("end_only"))
    ct.main()
    assert ran == ["apply"]


@pytest.mark.parametrize(
    "failure", [SystemExit("read-back differs"), OSError("no such file")]
)
def test_a_failed_background_write_notifies_because_no_terminal_is_watching(
    cfg, tmp_path, monkeypatch, failure
):
    monkeypatch.setattr(ct, "SZ_LOCK", tmp_path / "state" / "screenzen.lock")

    def broken(cfg, **k):
        raise failure

    monkeypatch.setattr(ct, "cmd_screenzen", broken)
    told = []
    monkeypatch.setattr(ct, "notify", told.append)
    ct.cmd_sz_apply(cfg)
    assert len(told) == 1 and "focus screenzen" in told[0]


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
        ct, "ct_send", lambda *a: pytest.fail(f"Cold Turkey CLI called: {a}")
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
        ct, "ct_send", lambda *a: pytest.fail(f"Cold Turkey CLI called: {a}")
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
        ct, "ct_send", lambda *a: pytest.fail(f"Cold Turkey CLI called: {a}")
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
        ct, "ct_send", lambda *a: pytest.fail(f"Cold Turkey CLI called: {a}")
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


# --- focus only ---------------------------------------------------------------------

ONLY_NOTE = """# Test note

```yaml
groups:
  base: {sites: ["file://*.*", localhost]}
  tools: {apps: [Ghostty]}
  papers: {sites: [arxiv.org]}
  llms: {sites: [chatgpt.com], apps: [ChatGPT]}
  bear: {apps: [Bear]}
  chat: {apps: [Telegram]}
  feeds: {sites: [x.com], apps: [Grind]}
always_allow: [base, llms]
modes:
  research: {allow: [papers], block: [chat]}
only:
  keep: [base, tools]
  minutes: 30
blocklists:
  screenzen:
    "🚫 msgs": {block: [chat], off_in: [none]}
  cold_turkey:
    avoid: {block: [feeds], allow: [base]}
```
"""


@pytest.fixture
def only_cfg(tmp_path):
    p = tmp_path / "only.md"
    p.write_text(ONLY_NOTE)
    ct.APP_DIRS, saved = [], ct.APP_DIRS  # this Mac's apps stay out of the tests
    yield ct.load_config(p)
    ct.APP_DIRS = saved


@pytest.fixture
def session_env(only_cfg, monkeypatch, tmp_path):
    """Cold Turkey with research running, ScreenZen present but its write recorded."""
    plist = tmp_path / "sz" / "prefs.plist"
    plist.parent.mkdir()
    plist.write_text("")
    monkeypatch.setattr(ct, "SZ_DOMAIN", plist.with_suffix(""))
    blocks = {"mode: research": mode_block(only_cfg, "research", "true")}
    fake_cold_turkey(monkeypatch, blocks)
    writes, notes, spawned = [], [], []
    monkeypatch.setattr(
        ct, "cmd_screenzen", lambda cfg, dry_run, **k: writes.append(k.get("modes"))
    )
    monkeypatch.setattr(ct, "notify", notes.append)
    monkeypatch.setattr(ct, "spawn_self", lambda *a: spawned.append(a))
    return blocks, writes, notes, spawned


def test_the_only_section_adds_no_mode(only_cfg):
    # Everything that walks the modes (sync, export, status) must not expect a block.
    assert list(only_cfg["modes"]) == ["research"]


def test_a_mode_named_only_clashes_with_the_section(tmp_path):
    p = tmp_path / "n.md"
    p.write_text(ONLY_NOTE.replace("research:", "only:", 1))
    with pytest.raises(SystemExit, match="taken"):
        ct.load_config(p)


def test_groups_an_always_on_block_bans_cannot_be_picked(only_cfg):
    assert "feeds" not in ct.only_pool(only_cfg)
    assert {"papers", "llms", "bear", "chat"} <= set(ct.only_pool(only_cfg))


def test_a_pick_is_a_group_name_or_a_word_in_one_group(only_cfg):
    assert ct.resolve_pick(only_cfg, "bear") == "bear"
    assert ct.resolve_pick(only_cfg, "chatgpt") == "llms"
    assert ct.resolve_pick(only_cfg, "ARXIV") == "papers"


def test_an_unknown_or_ambiguous_pick_is_refused(only_cfg):
    with pytest.raises(SystemExit, match="no group or app"):
        ct.resolve_pick(only_cfg, "x.com")
    with pytest.raises(SystemExit, match="it is in"):
        ct.resolve_pick(only_cfg, "a")


def test_a_session_allows_keep_and_picks_and_drops_always_allow(only_cfg):
    ct.write_only({"groups": ["papers"], "until": 2e9, "back": []})
    sites = ct.sz_allow_sites(only_cfg, [ct.ONLY])
    assert "arxiv.org" in sites and "localhost" in sites
    assert "chatgpt.com" not in sites  # always_allow, but not picked


def test_every_configured_block_group_stands_aside_for_a_session(only_cfg):
    bl = only_cfg["blocklists"]["screenzen"]["🚫 msgs"]
    assert ct.sz_group_off(bl, [ct.ONLY])
    assert not ct.sz_group_off(bl, ["research"])


def fake_app(root, name, **info):
    contents = root / f"{name}.app" / "Contents"
    contents.mkdir(parents=True)
    with (contents / "Info.plist").open("wb") as f:
        ct.plistlib.dump({"CFBundleIdentifier": f"id.{name}", **info}, f)


def test_installed_apps_skips_menu_bar_agents_and_broken_bundles(tmp_path, monkeypatch):
    fake_app(tmp_path, "Bear")
    fake_app(tmp_path, "Alfred", LSUIElement=True)
    fake_app(tmp_path, "Stats", LSUIElement="1")
    fake_app(tmp_path, "Helper", LSBackgroundOnly=True)
    (tmp_path / "Broken.app").mkdir()
    monkeypatch.setattr(ct, "APP_DIRS", [tmp_path, tmp_path / "absent"])
    assert ct.installed_apps() == ["Bear"]


def only_block_groups():
    return [
        {
            "groupName": "🚫 msgs",
            "alwaysActive": True,
            "isDisabled": False,
            "id": "A",
            "customSites": [],
            "apps": [],
            "pauseTimeIndex": 1,
        }
    ]


def test_the_session_block_group_pauses_every_app_not_allowed(
    only_cfg, tmp_path, monkeypatch
):
    for name in ("Bear", "Ghostty", "Telegram"):
        fake_app(tmp_path, name)
    monkeypatch.setattr(ct, "APP_DIRS", [tmp_path])
    ct.write_only({"groups": ["bear"], "until": 2e9, "back": []})
    groups = only_block_groups()
    ct.sz_only_block(only_cfg, groups, [ct.ONLY])
    made = groups[-1]
    assert made["groupName"] == ct.SZ_ONLY_BLOCK and not made["isDisabled"]
    assert made["pauseTimeIndex"] == 1  # the template's pause, so it can be passed
    assert [a["appName"] for a in made["apps"]] == ["Telegram"]
    assert made["apps"][0]["appBundle"] == "id.Telegram"


def test_the_session_block_group_is_off_after_and_not_made_before(only_cfg):
    groups = only_block_groups()
    assert ct.sz_only_block(only_cfg, groups, ["research"]) == []
    assert len(groups) == 1  # no session yet: nothing created
    groups.append({"groupName": ct.SZ_ONLY_BLOCK, "isDisabled": False, "apps": []})
    ct.sz_only_block(only_cfg, groups, [])
    assert groups[-1]["isDisabled"]


def test_starting_a_session_stops_the_mode_after_screenzen(only_cfg, session_env):
    blocks, writes, _, spawned = session_env
    ct.cmd_only(only_cfg, ["bear", "chatgpt", "20"])
    s = ct.read_only()
    assert s["groups"] == ["bear", "llms"] and s["back"] == ["research"]
    assert writes == [[ct.ONLY]]
    assert blocks["mode: research"]["enabled"] == "false"
    assert spawned == [("only-wait",)]


def test_a_failed_screenzen_write_leaves_the_mode_on_and_no_session(
    only_cfg, session_env, monkeypatch
):
    blocks, *_ = session_env

    def broken(cfg, dry_run, **k):
        raise OSError("no write")

    monkeypatch.setattr(ct, "cmd_screenzen", broken)
    with pytest.raises(OSError):
        ct.cmd_only(only_cfg, ["bear", "5"])
    assert blocks["mode: research"]["enabled"] == "true"
    assert ct.read_only()["until"] == 0  # the record stays, so the write is retried
    monkeypatch.setattr(ct, "cmd_screenzen", lambda cfg, dry_run, **k: None)
    assert ct.end_only(only_cfg)
    assert ct.read_only() is None


def test_a_failed_mode_stop_puts_screenzen_back(only_cfg, session_env, monkeypatch):
    blocks, writes, *_ = session_env
    fake_cold_turkey(monkeypatch, blocks, refuse=("mode: research",))
    with pytest.raises(SystemExit):
        ct.cmd_only(only_cfg, ["bear", "5"])
    assert writes == [[ct.ONLY], ["research"]]
    assert ct.read_only() is None
    assert blocks["mode: research"]["enabled"] == "true"


def test_a_failed_screenzen_return_keeps_the_record_to_retry(
    only_cfg, session_env, monkeypatch
):
    _, _, notes, _ = session_env

    def broken(cfg, dry_run, **k):
        raise OSError("no write")

    ct.write_only({"groups": ["bear"], "until": 1.0, "back": []})
    monkeypatch.setattr(ct, "cmd_screenzen", broken)
    assert not ct.end_only(only_cfg)
    assert ct.read_only() is not None and not notes
    monkeypatch.setattr(ct, "cmd_screenzen", lambda cfg, dry_run, **k: None)
    assert ct.end_only(only_cfg)
    assert ct.read_only() is None and notes


def test_ending_early_with_a_failed_write_is_retried_on_the_next_tick(
    only_cfg, session_env, monkeypatch
):
    def broken(cfg, dry_run, **k):
        raise OSError("no write")

    ct.write_only({"groups": ["bear"], "until": 2e9, "back": []})
    monkeypatch.setattr(ct, "cmd_screenzen", broken)
    assert not ct.end_only(only_cfg, force=True)
    assert ct.read_only()["until"] == 0  # no longer waits for the original end


def test_a_locked_mode_cannot_be_replaced(only_cfg, session_env):
    blocks, writes, *_ = session_env
    blocks["mode: research"]["lock"] = "delay,5,m"
    with pytest.raises(SystemExit, match="locked"):
        ct.cmd_only(only_cfg, ["bear", "5"])
    assert ct.read_only() is None and writes == []


def test_an_agent_replacing_a_mode_waits_and_writes_nothing(
    only_cfg, session_env, monkeypatch
):
    blocks, writes, *_ = session_env
    monkeypatch.setenv("CLAUDECODE", "1")
    with pytest.raises(SystemExit) as e:
        ct.cmd_only(only_cfg, ["bear", "5"])
    assert e.value.code == 3
    assert ct.read_only() is None and writes == []
    assert blocks["mode: research"]["enabled"] == "true"


def test_an_agent_starting_from_no_mode_waits_too(only_cfg, session_env, monkeypatch):
    blocks, writes, *_ = session_env
    blocks["mode: research"]["enabled"] = "false"
    monkeypatch.setenv("CLAUDECODE", "1")
    with pytest.raises(SystemExit) as e:
        ct.cmd_only(only_cfg, ["chat", "5"])
    assert e.value.code == 3
    assert ct.read_only() is None and writes == []


def test_an_agent_leaving_a_session_for_a_mode_waits(
    only_cfg, session_env, monkeypatch
):
    blocks, writes, *_ = session_env
    blocks["mode: research"]["enabled"] = "false"
    ct.write_only({"groups": ["bear"], "until": 2e9, "back": []})
    monkeypatch.setenv("CLAUDECODE", "1")
    with pytest.raises(SystemExit) as e:
        ct.cmd_start(only_cfg, "research")
    assert e.value.code == 3
    assert ct.read_only() is not None and writes == []
    assert blocks["mode: research"]["enabled"] == "false"


def test_an_agent_retiming_a_session_waits(only_cfg, session_env, monkeypatch):
    ct.write_only({"groups": ["bear"], "until": 2e9, "back": []})
    monkeypatch.setenv("CLAUDECODE", "1")
    with pytest.raises(SystemExit) as e:
        ct.cmd_only(only_cfg, ["600"])
    assert e.value.code == 3
    assert ct.read_only()["until"] == 2e9


def test_approving_one_session_does_not_approve_another(
    only_cfg, session_env, monkeypatch
):
    monkeypatch.setenv("CLAUDECODE", "1")
    with pytest.raises(SystemExit):
        ct.cmd_only(only_cfg, ["bear", "5"])
    queued = ct.json.loads(ct.PENDING.read_text())
    ct.PENDING.write_text(ct.json.dumps({k: 0 for k in queued}))
    with pytest.raises(SystemExit) as e:
        ct.cmd_only(only_cfg, ["papers", "5"])
    assert e.value.code == 3


def test_adding_to_a_session_rewrites_screenzen_and_keeps_the_end(
    only_cfg, session_env
):
    _, writes, *_ = session_env
    ct.write_only({"groups": ["bear"], "until": 2e9, "back": ["research"]})
    ct.cmd_only(only_cfg, ["papers"])
    s = ct.read_only()
    assert s["groups"] == ["bear", "papers"] and s["until"] == 2e9
    assert writes == [[ct.ONLY]]


def test_minutes_alone_retime_a_session_without_a_screenzen_write(
    only_cfg, session_env
):
    _, writes, *_ = session_env
    ct.write_only({"groups": ["bear"], "until": 1.0, "back": []})
    ct.cmd_only(only_cfg, ["20"])
    assert ct.read_only()["until"] > 1.0 and writes == []


def test_a_session_ends_on_time_back_in_the_old_mode(only_cfg, session_env):
    blocks, writes, notes, _ = session_env
    blocks["mode: research"]["enabled"] = "false"
    ct.write_only({"groups": ["bear"], "until": 1.0, "back": ["research"]})
    assert ct.end_only(only_cfg)
    assert blocks["mode: research"]["enabled"] == "true"
    assert writes == [["research"]]
    assert ct.read_only() is None and "research" in notes[0]


def test_a_session_not_yet_over_is_left_alone(only_cfg, session_env):
    _, writes, notes, _ = session_env
    ct.write_only({"groups": ["bear"], "until": 2e9, "back": []})
    assert not ct.end_only(only_cfg)
    assert ct.read_only() and not writes and not notes


def test_only_end_ends_it_early(only_cfg, session_env):
    blocks, *_ = session_env
    blocks["mode: research"]["enabled"] = "false"
    ct.write_only({"groups": ["bear"], "until": 2e9, "back": ["research"]})
    ct.cmd_only(only_cfg, ["end"])
    assert ct.read_only() is None
    assert blocks["mode: research"]["enabled"] == "true"


def test_a_failed_return_keeps_the_record_to_retry(only_cfg, session_env, monkeypatch):
    blocks, *_ = session_env
    blocks["mode: research"]["enabled"] = "false"
    fake_cold_turkey(monkeypatch, blocks, refuse=("mode: research",))
    ct.write_only({"groups": ["bear"], "until": 1.0, "back": ["research"]})
    with pytest.raises(SystemExit):
        ct.end_only(only_cfg)
    assert ct.read_only() is not None


def test_starting_a_mode_ends_a_session(only_cfg, session_env, monkeypatch):
    blocks, *_ = session_env
    blocks["mode: research"]["enabled"] = "false"
    ct.write_only({"groups": ["bear"], "until": 2e9, "back": []})
    _, writes, notes, _ = session_env
    ct.cmd_start(only_cfg, "research")
    assert ct.read_only() is None
    assert writes == [["research"]] and not notes
    assert blocks["mode: research"]["enabled"] == "true"


def test_a_break_and_off_point_at_only_end_during_a_session(
    only_cfg, session_env, capsys
):
    ct.write_only({"groups": ["bear"], "until": 2e9, "back": []})
    with pytest.raises(SystemExit, match="only end"):
        ct.cmd_break(only_cfg, ["10"])
    ct.cmd_off(only_cfg)
    assert "focus only end" in capsys.readouterr().out
    assert ct.read_only() is not None


def test_a_session_started_during_a_break_returns_to_the_broken_mode(
    only_cfg, session_env
):
    blocks, *_ = session_env
    blocks["mode: research"]["enabled"] = "false"
    ct.BREAK_FILE.write_text(ct.json.dumps({"modes": ["research"], "until": 2e9}))
    ct.cmd_only(only_cfg, ["bear", "5"])
    assert ct.read_only()["back"] == ["research"]
    assert not ct.BREAK_FILE.exists()


def test_a_session_with_no_screenzen_is_refused(only_cfg, monkeypatch):
    fake_cold_turkey(monkeypatch, {})
    with pytest.raises(SystemExit, match="ScreenZen"):
        ct.cmd_only(only_cfg, ["bear", "5"])


def test_only_needs_the_section_in_the_note(cfg):
    with pytest.raises(SystemExit, match="only:"):
        ct.cmd_only(cfg, ["bear"])


def test_the_picker_refuses_without_a_terminal(only_cfg, monkeypatch):
    monkeypatch.setattr(ct.sys, "stdin", type("T", (), {"isatty": lambda s: False})())
    with pytest.raises(SystemExit, match="name the groups"):
        ct.pick_groups(only_cfg, [])


def test_the_picker_offers_contents_and_hides_keep_and_current_picks(
    only_cfg, monkeypatch
):
    monkeypatch.setattr(ct.sys, "stdin", type("T", (), {"isatty": lambda s: True})())
    monkeypatch.setattr(ct.shutil, "which", lambda n: "/bin/fzf")
    seen = {}

    def fake_fzf(cmd, input, **k):
        seen["rows"] = input.split("\n")
        return ct.subprocess.CompletedProcess(
            cmd, 0, stdout=input.split("\n")[0] + "\n"
        )

    monkeypatch.setattr(ct.subprocess, "run", fake_fzf)
    picked = ct.pick_groups(only_cfg, ["bear"])
    names = [r.split("\t")[0] for r in seen["rows"]]
    assert "base" not in names and "tools" not in names and "bear" not in names
    assert "llms\tChatGPT, chatgpt.com" in seen["rows"]
    assert picked == [names[0]]


def test_cancelling_the_picker_changes_nothing(only_cfg, session_env, monkeypatch):
    blocks, writes, *_ = session_env
    monkeypatch.setattr(ct, "pick_groups", lambda cfg, exclude: [])
    ct.cmd_only(only_cfg, [])
    assert ct.read_only() is None and not writes
    assert blocks["mode: research"]["enabled"] == "true"


def test_a_corrupt_session_file_ends_cleanly(only_cfg, session_env):
    ct.ONLY_FILE.write_text("{not json")
    assert ct.read_only() == {"groups": [], "until": 0, "back": []}
    assert ct.end_only(only_cfg)
    assert ct.read_only() is None


def test_a_word_in_no_group_finds_one_installed_app(only_cfg, tmp_path, monkeypatch):
    for name in ("Zotero", "Notes", "Antinote", "Bear", "Telegram"):
        fake_app(tmp_path, name)
    monkeypatch.setattr(ct, "APP_DIRS", [tmp_path])
    assert ct.resolve_pick(only_cfg, "zotero") == "app:Zotero"
    assert ct.resolve_pick(only_cfg, "notes") == "app:Notes"  # exact beats a partial
    assert ct.resolve_pick(only_cfg, "bear") == "bear"  # a group wins over the app
    with pytest.raises(SystemExit, match="it is in"):
        ct.resolve_pick(only_cfg, "note")


def test_a_picked_app_is_left_out_of_the_session_block_group(
    only_cfg, tmp_path, monkeypatch
):
    for name in ("Zotero", "Notes"):
        fake_app(tmp_path, name)
    monkeypatch.setattr(ct, "APP_DIRS", [tmp_path])
    ct.write_only({"groups": ["app:Zotero"], "until": 2e9, "back": []})
    groups = only_block_groups()
    ct.sz_only_block(only_cfg, groups, [ct.ONLY])
    assert [a["appName"] for a in groups[-1]["apps"]] == ["Notes"]


def test_the_picker_lists_ungrouped_apps_only(only_cfg, tmp_path, monkeypatch):
    for name in ("Zotero", "Notes", "Telegram", "Grind"):
        fake_app(tmp_path, name)
    monkeypatch.setattr(ct, "APP_DIRS", [tmp_path])
    monkeypatch.setattr(ct.sys, "stdin", type("T", (), {"isatty": lambda s: True})())
    monkeypatch.setattr(ct.shutil, "which", lambda n: "/bin/fzf")
    seen = {}

    def fake_fzf(cmd, input, **k):
        seen["rows"] = input.split("\n")
        return ct.subprocess.CompletedProcess(cmd, 1, stdout="")

    monkeypatch.setattr(ct.subprocess, "run", fake_fzf)
    assert ct.pick_groups(only_cfg, ["app:Notes"]) == []
    apps = [r.split("\t")[0] for r in seen["rows"] if r.startswith("app:")]
    assert apps == ["app:Zotero"]  # Telegram and Grind have groups; Notes is picked
