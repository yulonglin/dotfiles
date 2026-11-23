"""Tests for custom_bins/focus: config groups, ScreenZen pattern mapping, settings decoding, agent delay."""

import datetime as dt
import importlib.machinery
import importlib.util
import json
import sys
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
REAL_CAN_SHOW_DIALOG = ct.can_show_dialog
REAL_WAKE = ct.wake_agent  # the autouse fixture stubs ct.wake_agent
REAL_WITHDRAW = ct.withdraw_command  # stubbed too: it would touch the real slot
REAL_LOOSENING_REASON = ct.loosening_reason  # stubbed too; its own tests restore it


@pytest.fixture(autouse=True)
def isolated(monkeypatch, tmp_path):
    # These tests often run inside Claude Code, which sets CLAUDECODE=1; a test that
    # wants agent behaviour sets it itself. The delay queue, the backups and ScreenZen's
    # preferences are never the real ones: a mode switch writes ScreenZen.
    monkeypatch.delenv("CLAUDECODE", raising=False)
    # A missing terminal would otherwise put a real reason dialog on the screen.
    monkeypatch.setattr(ct, "can_show_dialog", lambda: False)
    monkeypatch.setattr(ct, "PENDING", tmp_path / "pending.json")
    monkeypatch.setattr(ct, "BACKUP_DIR", tmp_path / "backups")
    monkeypatch.setattr(ct, "BREAK_FILE", tmp_path / "break.json")
    monkeypatch.setattr(ct, "LAST_BREAK_FILE", tmp_path / "last-break.json")
    monkeypatch.setattr(ct, "ONLY_FILE", tmp_path / "only.json")
    monkeypatch.setattr(ct, "CAPPED_FILE", tmp_path / "capped.json")
    monkeypatch.setattr(ct, "CAPPED_DAY_FILE", tmp_path / "capped-day.json")
    monkeypatch.setattr(ct, "COMMIT_LOG", tmp_path / "commit-log.jsonl")
    monkeypatch.setattr(ct, "AGENT_PLIST", tmp_path / "agent.plist")
    monkeypatch.setattr(ct, "TICK_APP", tmp_path / "Focus Tick.app")
    monkeypatch.setattr(ct, "COMMIT_FILE", tmp_path / "commit.json")
    monkeypatch.setattr(ct, "COMMIT_LOCK", tmp_path / "commit.lock")
    monkeypatch.setattr(ct, "CAPPED_LOCK", tmp_path / "capped.lock")
    monkeypatch.setattr(ct, "DEFAULT_FILE", tmp_path / "default.json")
    monkeypatch.setattr(ct, "SCHEDULED_FILE", tmp_path / "scheduled.json")
    monkeypatch.setattr(ct, "WINDOW_FILE", tmp_path / "window.json")
    monkeypatch.setattr(ct, "CONFIG_PATH", tmp_path / "no-note.md")
    monkeypatch.setattr(ct, "notify", lambda text: None)
    monkeypatch.setattr(ct, "wake_agent", lambda args: None)
    monkeypatch.setattr(ct, "withdraw_command", lambda args: None)
    monkeypatch.setattr(ct, "frontmost_bundle", lambda: None)
    # Most tests switch modes without a person to ask; the reason tests restore it.
    monkeypatch.setattr(ct, "loosening_reason", lambda *a, **k: None)
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
    # The wildcard rule is cut to a prefix that allows more; a cut leaving only a scheme is
    # kept, so local files open without a pause.
    assert ct.sz_allow_sites(cfg) == [
        "file://",
        "localhost",
        "arxiv.org",
        "github.com/",
    ]


def test_screenzen_keeps_a_scheme_cut_and_drops_an_empty_one():
    assert ct.sz_allow_pattern("file://*.*") == "file://"
    assert ct.sz_allow_pattern("*adhd*") is None


def test_conflict_when_a_mode_allows_what_an_always_on_block_bans(cfg):
    assert ct.conflicts(cfg) == []
    cfg["groups"]["papers"]["sites"].append("x.com")
    assert ct.conflicts(cfg) == [
        "'x.com' is allowed in mode 'research' but blocked by 'avoid'",
        "'x.com' is allowed in mode 'writing' but blocked by 'avoid'",
    ]


def test_a_listed_overlap_is_by_design_not_a_conflict(cfg):
    cfg["groups"]["papers"]["sites"].append("x.com")
    cfg["overlaps"] = {"x.com": "opens only on avoid's breaks", "gone.com": "old"}
    assert ct.conflicts(cfg) == []
    lines, stale = ct.deliberate_overlaps(cfg)
    assert lines == [
        "x.com opens in research, writing only while 'avoid' is off or on a break: "
        "opens only on avoid's breaks"
    ]
    assert stale == ["gone.com"]


def test_overlaps_need_a_reason(tmp_path):
    p = tmp_path / "note.md"
    p.write_text(NOTE.replace("blocklists:", "overlaps: [x.com]\nblocklists:"))
    with pytest.raises(SystemExit, match="'overlaps' must map each site"):
        ct.load_config(p)


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
    with pytest.raises(SystemExit, match="did not take these additions"):
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
    out = capsys.readouterr().out
    assert "timer: deep: differs" in out
    assert "Fix: Run 'focus sync', which adds it." in out

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


def fake_front(monkeypatch, app, lag=2):
    """The app is in front until a wake; 'open -b' takes effect after `lag` checks."""
    state = {"front": app, "pending": 0}
    opened = []

    def frontmost():
        if state["pending"]:
            state["pending"] -= 1
            if not state["pending"]:
                state["front"] = app
        return state["front"]

    def run(cmd, **k):
        opened.append(cmd)
        state["pending"] = lag

    def wake(args):
        state["front"] = ct.CT_BUNDLE

    monkeypatch.setattr(ct, "frontmost_bundle", frontmost)
    monkeypatch.setattr(ct.subprocess, "run", run)
    monkeypatch.setattr(ct, "wake_agent", wake)
    monkeypatch.setattr(ct, "ct_send", lambda *a: None)
    monkeypatch.setattr(ct.time, "sleep", lambda s: None)
    return state, opened


def test_the_front_goes_back_to_the_app_that_had_it(monkeypatch):
    state, opened = fake_front(monkeypatch, "com.superlogical.rex")
    assert ct.ct_apply(("-start", "x"), lambda: True)
    assert opened == [["open", "-b", "com.superlogical.rex"]]
    assert state["front"] == "com.superlogical.rex"  # back before ct_apply returns


def test_the_front_goes_back_even_when_nothing_lands(monkeypatch):
    state, opened = fake_front(monkeypatch, "com.superlogical.rex")
    assert not ct.ct_apply(("-start", "x"), lambda: False)
    assert state["front"] == "com.superlogical.rex"


def test_two_commands_in_a_row_both_give_the_front_back(monkeypatch):
    # A mode switch is a start then a stop. 'open' returns before the front moves, so
    # without the wait the second call reads Cold Turkey as the app to go back to.
    state, opened = fake_front(monkeypatch, "com.superlogical.rex")
    ct.ct_apply(("-start", "a"), lambda: True)
    ct.ct_apply(("-stop", "b"), lambda: True)
    assert opened == [["open", "-b", "com.superlogical.rex"]] * 2
    assert state["front"] == "com.superlogical.rex"


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


def test_a_failed_switch_says_the_command_was_taken_back_and_keeps_the_old_mode(
    cfg, monkeypatch
):
    blocks = {
        "mode: research": mode_block(cfg, "research", "true"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    calls = fake_cold_turkey(monkeypatch, blocks, refuse={"mode: writing"})
    with pytest.raises(SystemExit, match="did not start.*took it back"):
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


def test_a_second_break_waits_for_break_every_minutes(cfg, tmp_path, monkeypatch):
    cfg = {**cfg, "break_every_minutes": 60}
    blocks = {"mode: research": mode_block(cfg, "research", "true")}
    fake_cold_turkey(monkeypatch, blocks)
    monkeypatch.setattr(ct, "sz_follow", lambda *a, **k: None)
    monkeypatch.setattr(ct.subprocess, "Popen", lambda cmd, **k: None)
    now = [1_800_000_000.0]
    monkeypatch.setattr(ct.time, "time", lambda: now[0])
    ct.cmd_break(cfg, ["10"])
    now[0] += 11 * 60
    ct.end_break(cfg)
    assert blocks["mode: research"]["enabled"] == "true"
    with pytest.raises(SystemExit, match="one break per 60 min"):
        ct.cmd_break(cfg, ["10"])
    assert blocks["mode: research"]["enabled"] == "true"
    now[0] += 50 * 60  # an hour after the first started
    ct.cmd_break(cfg, ["10"])
    assert blocks["mode: research"]["enabled"] == "false"


def test_an_emergency_break_skips_the_wait_after_a_typed_back_text(
    cfg, tmp_path, monkeypatch
):
    blocks = {"mode: research": mode_block(cfg, "research", "true")}
    fake_cold_turkey(monkeypatch, blocks)
    monkeypatch.setattr(ct, "sz_follow", lambda *a, **k: None)
    monkeypatch.setattr(ct.subprocess, "Popen", lambda cmd, **k: None)
    monkeypatch.setattr(ct.sys.stdin, "isatty", lambda: True)
    lengths = []
    monkeypatch.setattr(ct, "random_text", lambda n: lengths.append(n) or "abc")
    ct.write_state(ct.LAST_BREAK_FILE, {"started": ct.time.time()})
    with pytest.raises(SystemExit, match="--emergency"):
        ct.cmd_break(cfg, ["10"])
    typed = iter(["wrong"])
    monkeypatch.setattr("builtins.input", lambda *a: next(typed))
    monkeypatch.setattr(ct, "read_typed", lambda *a: next(typed))
    with pytest.raises(SystemExit, match="did not match"):
        ct.cmd_break(cfg, ["10"], emergency=True)
    assert blocks["mode: research"]["enabled"] == "true"
    with pytest.raises(SystemExit, match="1 to 30"):  # the cap still holds
        ct.cmd_break(cfg, ["45"], emergency=True)
    typed = iter(["abc", "landlord at the door"])
    ct.cmd_break(cfg, ["10"], emergency=True)
    assert blocks["mode: research"]["enabled"] == "false"
    entry = json.loads(ct.COMMIT_LOG.read_text().splitlines()[-1])
    assert entry["emergency"] and entry["reason"] == "landlord at the door"
    assert set(lengths) == {ct.DEFAULT_EMERGENCY_TEXT}  # shorter than a commitment's


def test_an_agent_cannot_take_an_emergency_break(cfg, monkeypatch):
    blocks = {"mode: research": mode_block(cfg, "research", "true")}
    fake_cold_turkey(monkeypatch, blocks)
    monkeypatch.setenv("CLAUDECODE", "1")
    ct.write_state(ct.LAST_BREAK_FILE, {"started": ct.time.time()})
    with pytest.raises(SystemExit, match="not an agent"):
        ct.cmd_break(cfg, ["10"], emergency=True)
    assert blocks["mode: research"]["enabled"] == "true"


def test_typed_keys_make_the_line_and_a_paste_is_refused():
    keys = [b"a", b"b", b"x", b"\x7f", b"c", b"\x1b[D", b"\r"]
    assert ct.keys_to_line(keys) == "abc"  # backspace edits, an arrow is ignored
    assert ct.keys_to_line([b"ab", b"c\r"]) == "abc"  # two keys can share a read
    with pytest.raises(ct.Pasted):
        ct.keys_to_line([b"abcdef\r"])  # a burst in one read is a paste
    with pytest.raises(ct.Pasted):
        ct.keys_to_line([b"\x1b[200~ab\x1b[201~", b"\r"])  # bracketed paste
    with pytest.raises(EOFError):
        ct.keys_to_line([b"a", b"\x04"])  # Ctrl-D gives up


def test_a_pasted_type_back_changes_nothing(cfg, monkeypatch):
    blocks = {"mode: research": mode_block(cfg, "research", "true")}
    fake_cold_turkey(monkeypatch, blocks)
    monkeypatch.setattr(ct.sys.stdin, "isatty", lambda: True)
    ct.write_state(ct.LAST_BREAK_FILE, {"started": ct.time.time()})

    def pasted(prompt):
        raise ct.Pasted

    monkeypatch.setattr(ct, "read_typed", pasted)
    with pytest.raises(SystemExit, match="pasted, not typed"):
        ct.cmd_break(cfg, ["10"], emergency=True)
    assert blocks["mode: research"]["enabled"] == "true"


@pytest.mark.parametrize(
    "argv", [["break", "10", "--emergency"], ["break", "--emergency", "10"]]
)
def test_the_command_line_accepts_emergency_on_either_side_of_the_minutes(argv):
    # The first version read --emergency inside cmd_break, but argparse refused the
    # flag before cmd_break ran (Yulong, 2026-11-22).
    a = ct.build_parser().parse_intermixed_args(argv)
    assert a.command == "break" and a.args == ["10"] and a.emergency


def test_breaks_are_spaced_an_hour_by_default_and_zero_turns_it_off(cfg):
    ct.write_state(ct.LAST_BREAK_FILE, {"started": ct.time.time()})
    assert ct.next_break_at(cfg) is not None
    assert ct.next_break_at({**cfg, "break_every_minutes": 0}) is None


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
    assert "llms\tllms\tChatGPT, chatgpt.com" in seen["rows"]
    assert picked == [names[0]]


def test_cancelling_the_picker_changes_nothing(only_cfg, session_env, monkeypatch):
    blocks, writes, *_ = session_env
    monkeypatch.setattr(ct, "pick_groups", lambda cfg, exclude, preset=(): [])
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


def test_an_app_token_without_spaces_names_an_ungrouped_app(
    only_cfg, tmp_path, monkeypatch
):
    fake_app(tmp_path, "iPhone Mirroring")
    monkeypatch.setattr(ct, "APP_DIRS", [tmp_path])
    assert ct.pick_token("app:iPhone Mirroring") == "app:iPhoneMirroring"
    assert ct.resolve_pick(only_cfg, "app:iPhoneMirroring") == "app:iPhone Mirroring"
    with pytest.raises(SystemExit, match="no installed app"):
        ct.resolve_pick(only_cfg, "app:Telegram")  # grouped, so not offered as an app


def test_alfred_only_piles_picks_into_the_query(
    only_cfg, tmp_path, capsys, monkeypatch
):
    fake_app(tmp_path, "Zotero")
    fake_app(tmp_path, "iPhone Mirroring")
    monkeypatch.setattr(ct, "APP_DIRS", [tmp_path])
    rows = alfred_rows(capsys, only_cfg, "only ")
    titles = [r["title"] for r in rows]
    assert "bear" in titles and "Zotero" in titles and "base" not in titles
    assert all(not r.get("valid", True) for r in rows)  # nothing to start yet
    mirror = next(r for r in rows if r["title"] == "iPhone Mirroring")
    assert mirror["autocomplete"] == "only app:iPhoneMirroring "

    rows = alfred_rows(capsys, only_cfg, "only bear app:iPhoneMirroring zot")
    start, *rest = rows
    assert start["title"] == "Start: bear, iPhone Mirroring for 30 min"
    assert start["arg"] == "only bear app:iPhoneMirroring 30"
    ticked = [r for r in rest if r["title"].startswith("✓")]
    assert [r["autocomplete"] for r in ticked] == [
        "only app:iPhoneMirroring ",
        "only bear ",
    ]
    assert [r["title"] for r in rest if not r["title"].startswith("✓")] == ["Zotero"]

    start = alfred_rows(capsys, only_cfg, "only bear 45")[0]
    assert start["arg"] == "only bear 45"


def test_alfred_only_adds_to_a_running_session(only_cfg, capsys):
    ct.write_only({"groups": ["bear"], "until": 2e9, "back": []})
    rows = alfred_rows(capsys, only_cfg, "only ")
    assert rows[0]["arg"] == "only end"
    assert "bear" not in [r["title"] for r in rows[1:]]
    rows = alfred_rows(capsys, only_cfg, "only papers ")
    assert rows[0]["title"].startswith("Add papers")
    assert rows[0]["arg"] == "only papers"


def test_alfred_main_list_offers_only(only_cfg, capsys):
    rows = alfred_rows(capsys, only_cfg, "on")
    assert [r["autocomplete"] for r in rows if r["uid"] == "only"] == ["only "]


def test_drift_says_which_side_has_what_and_how_to_fix_it():
    text = ct.describe("extra_exc", ["quantifiedmind.org"])
    assert text == (
        "  Cold Turkey allows quantifiedmind.org, but the note does not.\n"
        "    Fix: In Cold Turkey, remove it from this block's allowed sites "
        "(its exceptions)."
    )
    assert "remove them" in ct.describe("extra_web", ["a.com", "b.com"])
    assert "the apps Slack, Signal" in ct.describe("add_apps", ["Slack", "Signal"])


def test_every_kind_of_difference_has_plain_text(cfg):
    blocks = {"mode: writing": mode_block(cfg, "writing", "false")}
    kinds = set(ct.drift(cfg, blocks, "writing")) - {"exists"}
    assert kinds <= set(ct.DRIFT_TEXT)


def test_sync_explains_a_site_only_cold_turkey_allows(cfg, monkeypatch, capsys):
    block = mode_block(cfg, "writing", "false")
    block["exceptions"].append("quantifiedmind.org")
    blocks = {
        "mode: research": mode_block(cfg, "research", "false"),
        "mode: writing": block,
    }
    fake_cold_turkey(monkeypatch, blocks)
    ct.cmd_sync(cfg)
    out = capsys.readouterr().out
    assert "extra_exc" not in out
    assert "Cold Turkey allows quantifiedmind.org, but the note does not." in out
    assert "remove it from this block's allowed sites" in out


def test_status_leads_with_the_running_mode_and_splits_modes_from_always_on(
    cfg, monkeypatch, capsys
):
    always = {
        "enabled": "true",
        "lock": "delay,1",
        "type": "scheduled",
        "web": [],
        "exceptions": [],
        "apps": [],
    }
    blocks = {
        "night": always,
        "mode: research": mode_block(cfg, "research", "false"),
        "mode: writing": mode_block(cfg, "writing", "true"),
    }
    fake_cold_turkey(monkeypatch, blocks)
    ct.cmd_status(cfg)
    out = capsys.readouterr().out.splitlines()
    assert out[0] == "now: writing mode"
    modes, always_on = out.index("modes"), out.index("always on")
    assert out[modes + 1 : modes + 3] == ["  off      research", "  running  writing"]
    assert out[always_on + 1] == "  enabled  night  (scheduled, lock delay)"


def test_status_headline_names_a_break_an_only_session_and_a_timer(cfg, monkeypatch):
    timer = {
        "enabled": "true",
        "lock": "2026,11,6,21,56",
        "web": [],
        "exceptions": [],
        "apps": [],
    }
    blocks = {
        "mode: research": mode_block(cfg, "research", "false"),
        "timer: deep": timer,
    }
    fake_cold_turkey(monkeypatch, blocks)
    assert ct.status_headline(cfg, blocks) == "now: no mode + deep timer until 21:56"

    until = ct.time.time() + 600
    end = ct.dt.datetime.fromtimestamp(until)
    ct.BREAK_FILE.write_text(ct.json.dumps({"modes": ["research"], "until": until}))
    assert ct.status_headline(cfg, blocks).startswith(
        f"now: break until {end:%H:%M}, then research"
    )

    ct.ONLY_FILE.write_text(
        ct.json.dumps({"groups": ["bear"], "until": until, "back": []})
    )
    assert ct.status_headline(cfg, blocks).startswith(
        f"now: only session until {end:%H:%M} (bear)"
    )


def note_with(tmp_path, extra: str) -> Path:
    """The test note with extra top-level YAML lines in its block."""
    p = tmp_path / "extra.md"
    p.write_text(NOTE.replace("blocklists:", extra.rstrip("\n") + "\nblocklists:"))
    return p


def test_status_warns_when_a_strong_lock_block_has_no_or_a_delay_lock(
    tmp_path, monkeypatch, capsys
):
    cfg = ct.load_config(
        note_with(tmp_path, "strong_lock_blocks: [avoid, night, gone]")
    )
    blank = {"enabled": "true", "web": [], "exceptions": [], "apps": []}
    blocks = {
        "avoid": {**blank, "lock": "none"},
        "night": {**blank, "lock": "delay,5,m,0"},
        "mode: research": mode_block(cfg, "research", "false"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    assert ct.weak_locks(cfg, blocks) == [
        "'avoid' has no lock; a random-text lock is wanted",
        "'night' has a delay lock; a random-text lock is wanted",
        "'gone' is listed under strong_lock_blocks, but Cold Turkey has no such block",
    ]
    blocks["night"]["lock"] = "random,300"  # any other lock counts as strong enough
    assert len(ct.weak_locks(cfg, blocks)) == 2
    fake_cold_turkey(monkeypatch, blocks)
    ct.cmd_status(cfg)
    assert "weak lock: 'avoid' has no lock" in capsys.readouterr().out


def test_no_strong_lock_key_means_no_warning(cfg):
    assert ct.weak_locks(cfg, {"avoid": {"lock": "none"}}) == []


def test_strong_lock_blocks_must_be_a_list_of_names(tmp_path):
    with pytest.raises(SystemExit, match="strong_lock_blocks"):
        ct.load_config(note_with(tmp_path, "strong_lock_blocks: avoid"))


class Clock:
    """A settable time.time for the code under test."""

    def __init__(self, start: float):
        self.now = start

    def __call__(self) -> float:
        return self.now

    def advance(self, minutes: float) -> None:
        self.now += minutes * 60


def at_terminal(monkeypatch, answers: list[str]) -> list[str]:
    """A person at a terminal who types the given answers; returns the prompts shown."""
    prompts = []

    class TTY:
        @staticmethod
        def isatty():
            return True

    monkeypatch.setattr(ct.sys, "stdin", TTY)

    def fake_input(prompt=""):
        prompts.append(prompt)
        return answers.pop(0)

    monkeypatch.setattr("builtins.input", fake_input)
    monkeypatch.setattr(ct, "read_typed", fake_input)  # the key-by-key type-back
    return prompts


def no_terminal(monkeypatch):
    class Pipe:
        @staticmethod
        def isatty():
            return False

    monkeypatch.setattr(ct.sys, "stdin", Pipe)
    monkeypatch.setattr(
        "builtins.input", lambda prompt="": pytest.fail("asked without a terminal")
    )


def log_lines() -> list[dict]:
    if not ct.COMMIT_LOG.exists():
        return []
    return [json.loads(line) for line in ct.COMMIT_LOG.read_text().splitlines()]


CAPPED = "capped_modes: {writing: {minutes: 30, day_minutes: 120, fallback: research}}"


@pytest.fixture
def capped_env(tmp_path, monkeypatch):
    """research running, writing capped at 30 min a stretch and 120 a day."""
    cfg = ct.load_config(note_with(tmp_path, CAPPED))
    blocks = {
        "mode: research": mode_block(cfg, "research", "true"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    fake_cold_turkey(monkeypatch, blocks)
    clock = Clock(dt.datetime(2026, 11, 17, 10, 0).timestamp())
    monkeypatch.setattr(ct.time, "time", clock)
    spawned, notes = [], []
    monkeypatch.setattr(ct, "spawn_self", lambda *a: spawned.append(a))
    monkeypatch.setattr(ct, "sz_follow", lambda *a, **k: None)
    monkeypatch.setattr(ct, "notify", notes.append)
    no_terminal(monkeypatch)
    return cfg, blocks, clock, spawned, notes


def on(blocks):
    return sorted(n for n, b in blocks.items() if b["enabled"] == "true")


SCHEDULED = 'scheduled_mode: {mode: writing, start: "21:30", until: "22:00"}'


def test_the_scheduled_mode_runs_until_its_end_then_leaves_no_mode(
    capped_env, tmp_path
):
    _, blocks, clock, _, notes = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + SCHEDULED))
    at = dt.datetime(2026, 11, 17, 21, 31)
    clock.now = at.timestamp()
    assert ct.scheduled_start(cfg, at) == "writing"
    assert on(blocks) == ["mode: writing"] and "then no mode" in notes[-1]
    # once a day: a later tick in the span, after a manual switch, does nothing
    assert ct.scheduled_start(cfg, at + dt.timedelta(minutes=5)) is None
    assert ct.capped_day()["starts"].get("writing", 0) == 0  # no daily start taken
    clock.now = dt.datetime(2026, 11, 17, 22, 0).timestamp()
    ct.end_capped(cfg)
    assert on(blocks) == []  # not back to research, not the fallback


def test_the_scheduled_mode_waits_for_its_span_and_a_commitment(capped_env, tmp_path):
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + SCHEDULED))
    assert ct.scheduled_start(cfg, dt.datetime(2026, 11, 17, 21, 29)) is None
    assert ct.scheduled_start(cfg, dt.datetime(2026, 11, 17, 22, 0)) is None
    ct.write_commit(
        {"mode": "research", "until": 2_000_000_000, "locked_to": 0, "pending": []}
    )
    assert ct.scheduled_start(cfg, dt.datetime(2026, 11, 17, 21, 45)) is None


def test_a_scheduled_note_is_checked(tmp_path):
    for bad in (
        'scheduled_mode: {mode: research, start: "21:30", until: "22:00"}',
        'scheduled_mode: {mode: writing, start: "22:00", until: "21:30"}',
        'scheduled_mode: {mode: writing, start: "9pm", until: "22:00"}',
    ):
        with pytest.raises(SystemExit, match="scheduled_mode"):
            ct.load_config(note_with(tmp_path, CAPPED + "\n" + bad))


def test_a_capped_note_is_checked(tmp_path):
    for bad in (
        "capped_modes: {nope: {}}",
        "capped_modes: {writing: {fallback: writing}}",
        "capped_modes: {writing: {minutes: 0}}",
        "capped_modes: {writing: {cap: 3}}",
    ):
        with pytest.raises(SystemExit, match="capped"):
            ct.load_config(note_with(tmp_path, bad))


def test_the_first_capped_start_of_the_day_asks_nothing_and_ends_back_where_it_was(
    capped_env,
):
    cfg, blocks, clock, spawned, notes = capped_env
    ct.cmd_capped(cfg, "writing", [])
    assert on(blocks) == ["mode: writing"]
    c = ct.read_capped()
    assert c["back"] == ["research"] and c["until"] == clock.now + 30 * 60
    assert ("capped-wait",) in spawned and log_lines() == []
    clock.advance(29)
    assert not ct.end_capped(cfg) and on(blocks) == ["mode: writing"]
    clock.advance(1)
    ct.cmd_capped_wait(cfg)  # the waiter: the stretch is over
    assert on(blocks) == ["mode: research"]
    assert ct.read_capped() is None
    assert notes == ["writing stretch over: back to research."]


def test_with_no_mode_before_it_a_capped_mode_ends_in_its_fallback(capped_env):
    cfg, blocks, clock, *_ = capped_env
    blocks["mode: research"]["enabled"] = "false"
    ct.cmd_capped(cfg, "writing", ["10"])
    clock.advance(10)
    ct.catch_up(cfg)
    assert on(blocks) == ["mode: research"]


def test_a_stretch_longer_than_the_cap_is_refused(capped_env):
    cfg, *_ = capped_env
    with pytest.raises(SystemExit, match="1 to 30"):
        ct.cmd_capped(cfg, "writing", ["45"])


def test_a_later_start_the_same_day_needs_a_reason_at_a_terminal(
    capped_env, monkeypatch
):
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    clock.advance(30)
    ct.end_capped(cfg)
    with pytest.raises(SystemExit, match="only in a terminal"):
        ct.cmd_capped(cfg, "writing", [])
    assert on(blocks) == ["mode: research"]
    prompts = at_terminal(monkeypatch, ["the draft is due"])
    ct.cmd_capped(cfg, "writing", ["20"])
    assert prompts == ["Why writing again today? One line: "]
    (entry,) = log_lines()
    assert entry["command"] == "focus writing 20"
    assert entry["reason"] == "the draft is due" and "ts" in entry
    assert on(blocks) == ["mode: writing"]


def test_without_a_terminal_a_person_types_the_reason_into_a_dialog(
    capped_env, monkeypatch
):
    # Alfred runs focus with no terminal: the reason comes from a macOS dialog instead.
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    clock.advance(30)
    ct.end_capped(cfg)
    monkeypatch.setattr(ct, "can_show_dialog", lambda: True)
    calls = []

    def fake_run(cmd, **k):
        calls.append(cmd)
        return ct.subprocess.CompletedProcess(cmd, 0, stdout="email the landlord\n")

    monkeypatch.setattr(ct.subprocess, "run", fake_run)
    ct.cmd_capped(cfg, "writing", ["20"])
    assert calls[0][0] == "osascript" and calls[0][-1] == "writing again today"
    (entry,) = log_lines()
    assert entry["reason"] == "email the landlord"
    assert on(blocks) == ["mode: writing"]


def test_cancelling_the_reason_dialog_changes_nothing(capped_env, monkeypatch):
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    clock.advance(30)
    ct.end_capped(cfg)
    monkeypatch.setattr(ct, "can_show_dialog", lambda: True)
    monkeypatch.setattr(
        ct.subprocess,
        "run",
        lambda cmd, **k: ct.subprocess.CompletedProcess(
            cmd, 1, stdout="", stderr="execution error: User canceled. (-128)"
        ),
    )
    with pytest.raises(SystemExit, match="no reason given"):
        ct.cmd_capped(cfg, "writing", [])
    assert on(blocks) == ["mode: research"]


def test_an_agent_never_gets_the_dialog(monkeypatch):
    monkeypatch.setenv("CLAUDECODE", "1")
    assert not REAL_CAN_SHOW_DIALOG()


def test_the_reason_dialog_keeps_its_answer_past_the_gave_up_check():
    # AppleScript's `result` does not survive the `if` line, so reading the typed text
    # from `result` after it failed and every reason typed in Alfred came back as
    # Cancel (22 Nov 2026). The fakes above stub osascript and could not see this.
    assert "of result" not in ct.REASON_DIALOG
    assert "set dialogReply to display dialog" in ct.REASON_DIALOG


@pytest.mark.skipif(sys.platform != "darwin", reason="osascript is macOS-only")
def test_the_reason_dialog_returns_the_typed_text():
    # The real script, with the dialog swapped for the record it returns, so nothing
    # opens. The old script exited 1 here: "The variable result is not defined".
    import re

    canned = '{button returned:"Go on", text returned:"weekend plans", gave up:false}'
    script = re.sub(
        r"display dialog .*?giving up after 300", canned, ct.REASON_DIALOG, flags=re.S
    )
    assert script != ct.REASON_DIALOG
    r = ct.subprocess.run(
        ["osascript", "-e", script, "a break"], capture_output=True, text=True
    )
    if "(-2741)" in r.stderr:  # a sandbox without Standard Additions cannot parse it
        pytest.skip("Standard Additions terms unavailable here")
    assert (r.returncode, r.stdout.strip()) == (0, "weekend plans"), r.stderr


def test_cancelling_the_dialog_is_not_a_failure(monkeypatch):
    monkeypatch.setattr(ct.sys.stdin, "isatty", lambda: False)
    monkeypatch.setattr(ct, "can_show_dialog", lambda: True)
    monkeypatch.setattr(
        ct.subprocess,
        "run",
        lambda cmd, **k: ct.subprocess.CompletedProcess(
            cmd, 1, stdout="", stderr="execution error: User canceled. (-128)"
        ),
    )
    with pytest.raises(ct.Cancelled):
        ct.ask_reason("a break")


def test_a_broken_dialog_is_a_failure_not_a_cancel(monkeypatch):
    # The 22 Nov bug read as Cancel; any non-cancel osascript error must say what broke.
    monkeypatch.setattr(ct.sys.stdin, "isatty", lambda: False)
    monkeypatch.setattr(ct, "can_show_dialog", lambda: True)
    err = "execution error: The variable result is not defined. (-2753)"
    monkeypatch.setattr(
        ct.subprocess,
        "run",
        lambda cmd, **k: ct.subprocess.CompletedProcess(cmd, 1, stdout="", stderr=err),
    )
    with pytest.raises(SystemExit, match="dialog failed.*-2753") as e:
        ct.ask_reason("a break")
    assert not isinstance(e.value, ct.Cancelled)


@pytest.fixture
def alerts(monkeypatch):
    shown, notified = [], []
    monkeypatch.setattr(ct, "alert", shown.append)
    monkeypatch.setattr(ct, "notify", notified.append)
    monkeypatch.delenv("CLAUDECODE", raising=False)
    return shown, notified


def test_a_failure_from_alfred_pops_up_a_dialog(alerts, monkeypatch):
    shown, _ = alerts
    monkeypatch.setenv(ct.ALFRED_ENV, "1")

    def fail():
        sys.exit("focus: Cold Turkey did not start 'mode: messaging'")

    monkeypatch.setattr(ct, "main", fail)
    with pytest.raises(SystemExit):
        ct.run_main()
    assert shown == ["focus: Cold Turkey did not start 'mode: messaging'"]


def test_no_dialog_after_cancel_or_outside_alfred(alerts, monkeypatch):
    shown, _ = alerts

    def cancel():
        raise ct.Cancelled("focus: no reason given; nothing changed")

    monkeypatch.setenv(ct.ALFRED_ENV, "1")
    monkeypatch.setattr(ct, "main", cancel)
    with pytest.raises(SystemExit):
        ct.run_main()
    monkeypatch.delenv(ct.ALFRED_ENV)
    monkeypatch.setattr(ct, "main", lambda: sys.exit("focus: boom"))
    with pytest.raises(SystemExit):
        ct.run_main()
    assert shown == []


def test_report_failure_pops_up_only_for_alfred(alerts, monkeypatch):
    shown, notified = alerts
    ct.report_failure("from the tick")
    monkeypatch.setenv(ct.ALFRED_ENV, "1")
    ct.report_failure("from alfred")
    assert notified == ["from the tick"] and shown == ["from alfred"]


def test_renewing_straight_away_keeps_the_mode_from_before(capped_env, monkeypatch):
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    clock.advance(25)
    at_terminal(monkeypatch, ["one more section"])
    ct.cmd_capped(cfg, "writing", [])  # no cooldown
    c = ct.read_capped()
    assert c["back"] == ["research"] and c["until"] == clock.now + 30 * 60
    clock.advance(30)
    ct.end_capped(cfg)
    assert on(blocks) == ["mode: research"]


def test_a_blank_reason_is_refused_and_asked_again(capped_env, monkeypatch, capsys):
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    clock.advance(30)
    ct.end_capped(cfg)
    prompts = at_terminal(monkeypatch, ["", "  \t ", "the draft is due"])
    ct.cmd_capped(cfg, "writing", [])
    assert len(prompts) == 3
    assert capsys.readouterr().err.count("cannot be empty or only spaces") == 2
    (entry,) = log_lines()
    assert entry["reason"] == "the draft is due"
    assert on(blocks) == ["mode: writing"]


def test_ctrl_c_at_the_reason_prompt_changes_nothing(capped_env, monkeypatch):
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    clock.advance(30)
    ct.end_capped(cfg)
    answers = ["  "]
    at_terminal(monkeypatch, answers)

    def give_up(prompt=""):
        if answers:
            return answers.pop(0)
        raise KeyboardInterrupt

    monkeypatch.setattr("builtins.input", give_up)
    with pytest.raises(SystemExit, match="no reason"):
        ct.cmd_capped(cfg, "writing", [])
    assert on(blocks) == ["mode: research"] and log_lines() == []


def test_a_blank_dialog_answer_shows_the_dialog_again_with_an_error(
    capped_env, monkeypatch
):
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    clock.advance(30)
    ct.end_capped(cfg)
    monkeypatch.setattr(ct, "can_show_dialog", lambda: True)
    answers, calls = [" \n", "email the landlord\n"], []

    def fake_run(cmd, **k):
        calls.append(cmd)
        return ct.subprocess.CompletedProcess(cmd, 0, stdout=answers.pop(0))

    monkeypatch.setattr(ct.subprocess, "run", fake_run)
    ct.cmd_capped(cfg, "writing", [])
    assert calls[0][-1] == "writing again today"
    assert "cannot be empty" in calls[1][-1]
    assert log_lines()[0]["reason"] == "email the landlord"


def test_a_new_day_starts_free_again(capped_env):
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    clock.advance(30)
    ct.end_capped(cfg)
    clock.advance(24 * 60)
    ct.cmd_capped(cfg, "writing", [])  # no terminal needed
    assert on(blocks) == ["mode: writing"]


def test_a_day_stretch_asks_once_and_draws_on_the_budget(capped_env, monkeypatch):
    cfg, blocks, clock, *_ = capped_env
    prompts = at_terminal(monkeypatch, ["a long writing day"])
    ct.cmd_capped(cfg, "writing", [], day=True)
    assert len(prompts) == 1 and log_lines()[0]["command"] == "focus writing --day 120"
    assert ct.read_capped()["until"] == clock.now + 120 * 60
    assert ct.capped_day(clock.now)["used"] == {"writing": 120}
    clock.advance(120)
    ct.end_capped(cfg)
    assert on(blocks) == ["mode: research"]
    at_terminal(monkeypatch, ["again"])
    with pytest.raises(SystemExit, match="used up"):
        ct.cmd_capped(cfg, "writing", [], day=True)
    at_terminal(monkeypatch, ["a normal stretch after the day one"])
    ct.cmd_capped(cfg, "writing", [])
    assert ct.read_capped()["until"] == clock.now + 30 * 60


def test_a_day_stretch_left_early_gives_back_what_it_did_not_use(
    capped_env, monkeypatch
):
    cfg, _, clock, *_ = capped_env
    at_terminal(monkeypatch, ["first part"])
    ct.cmd_capped(cfg, "writing", ["90"], day=True)
    clock.advance(40)
    ct.cmd_start(cfg, "research")  # switching away by hand ends the stretch
    assert ct.read_capped() is None
    assert ct.capped_day(clock.now)["used"] == {"writing": 40}
    at_terminal(monkeypatch, ["second part"])
    ct.cmd_capped(cfg, "writing", [], day=True)  # the rest of the budget
    assert ct.read_capped()["until"] == clock.now + 80 * 60


def test_a_capped_mode_is_never_brought_back_without_its_cap(capped_env):
    cfg, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    # An only session or a break started now must return to research, not writing.
    assert ct.restore_point(cfg, ct.ONLY) == ["research"]


def test_a_break_holds_an_overdue_stretch_until_it_brings_the_mode_back(capped_env):
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    blocks["mode: writing"]["enabled"] = "false"  # a break stopped it
    ct.BREAK_FILE.write_text(
        json.dumps({"modes": ["writing"], "until": clock.now + 3600})
    )
    clock.advance(31)
    assert not ct.end_capped(cfg) and ct.read_capped() is not None
    clock.advance(30)
    ct.catch_up(cfg)  # the break ends, then the stretch it brought back
    assert on(blocks) == ["mode: research"] and ct.read_capped() is None


def test_an_agent_switching_into_a_capped_mode_waits(capped_env, monkeypatch):
    cfg, blocks, *_ = capped_env
    monkeypatch.setenv("CLAUDECODE", "1")
    with pytest.raises(SystemExit) as e:
        ct.cmd_capped(cfg, "writing", [])
    assert e.value.code == 3 and on(blocks) == ["mode: research"]
    assert ct.read_capped() is None


def contended(monkeypatch, name: str, meanwhile):
    """Make the lock `name` contended: before this process gets it, another process
    finishes its own change (meanwhile()), as when two workers race."""
    real = getattr(ct, name)

    @ct.contextmanager
    def lock():
        meanwhile()
        with real():
            yield

    monkeypatch.setattr(ct, name, lock)


def test_an_expiry_that_waited_for_the_lock_spares_a_renewed_stretch(
    capped_env, monkeypatch
):
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    clock.advance(30)  # over: the waiter and the tick both see the old record
    renewed = {**ct.read_capped(), "until": clock.now + 30 * 60}
    contended(
        monkeypatch, "capped_lock", lambda: ct.write_state(ct.CAPPED_FILE, renewed)
    )
    assert not ct.end_capped(cfg)
    assert on(blocks) == ["mode: writing"]
    assert ct.read_capped()["until"] == renewed["until"]


def test_the_state_locks_exclude_other_processes_and_nest_in_one(tmp_path):
    path = tmp_path / "x.lock"
    with ct.file_lock(path):
        with ct.file_lock(path):  # a helper called by a holder does not deadlock
            pass
        with path.open("w") as other:  # another open file, as another process has
            with pytest.raises(BlockingIOError):
                ct.fcntl.flock(other, ct.fcntl.LOCK_EX | ct.fcntl.LOCK_NB)
    with path.open("w") as other:
        ct.fcntl.flock(other, ct.fcntl.LOCK_EX | ct.fcntl.LOCK_NB)  # free again


def test_status_names_the_end_of_a_capped_stretch(capped_env):
    cfg, blocks, clock, *_ = capped_env
    ct.cmd_capped(cfg, "writing", [])
    end = dt.datetime.fromtimestamp(clock.now + 30 * 60)
    assert ct.status_headline(cfg, blocks) == (
        f"now: writing mode until {end:%H:%M}, then research"
    )


def stamp(t: float) -> str:
    """A timed lock's end as Cold Turkey stores it: 'Y,M,D,H,M'."""
    d = dt.datetime.fromtimestamp(t)
    return f"{d.year},{d.month},{d.day},{d.hour},{d.minute}"


def locking_cold_turkey(monkeypatch, blocks, clock):
    """Cold Turkey with locks: '-start B -lock N' starts B and locks it until N minutes
    from now (never shorter); '-stop' and '-add' do nothing to a locked block."""
    calls = []

    def ct_call(*args):
        calls.append(args)
        op, name = args[0], args[1]
        b = blocks[name]
        locked = b["lock"] != "none"
        if op == "-start":
            b["enabled"] = "true"
            if "-lock" in args:
                new = stamp(clock.now + int(args[3]) * 60)
                old = ct.lock_end(b)
                if old is None or ct.lock_end({"lock": new}) > old:
                    b["lock"] = new
        elif op == "-stop" and not locked:
            b["enabled"] = "false"
        elif op == "-add" and not locked:
            b["exceptions" if args[2] == "-exception" else "web"].append(args[3])

    monkeypatch.setattr(ct, "ct_send", ct_call)
    monkeypatch.setattr(ct, "read_blocks", lambda: blocks)
    monkeypatch.setattr(ct.time, "sleep", lambda s: None)
    return calls


def run_out(blocks, name="mode: research"):
    """Cold Turkey's lock runs out: it stops the block."""
    blocks[name].update(enabled="false", lock="none")


TIMER = "timers: {deep: {block: [feeds], minutes: 30}}"


@pytest.fixture
def commit_env(tmp_path, monkeypatch):
    """Both modes off, the launchd job installed, the clock at 10:00."""
    note = note_with(tmp_path, TIMER + "\n" + CAPPED.replace("fallback: research", ""))
    monkeypatch.setattr(ct, "CONFIG_PATH", note)
    cfg = ct.load_config(note)
    blocks = {
        "mode: research": mode_block(cfg, "research", "false"),
        "mode: writing": mode_block(cfg, "writing", "false"),
        "timer: deep": {**mode_block(cfg, "writing", "false"), "web": []},
    }
    clock = Clock(dt.datetime(2026, 11, 17, 10, 0).timestamp())
    monkeypatch.setattr(ct.time, "time", clock)
    calls = locking_cold_turkey(monkeypatch, blocks, clock)
    ct.AGENT_PLIST.write_text("")
    monkeypatch.setattr(ct, "launchd_print", lambda: loaded_job(ct.tick_args()))
    spawned, followed = [], []
    monkeypatch.setattr(ct, "spawn_self", lambda *a: spawned.append(a))
    monkeypatch.setattr(
        ct, "sz_follow", lambda cfg, modes, switched=False: followed.append(modes)
    )
    monkeypatch.setattr(ct, "random_text", lambda n: "x" * 3)
    no_terminal(monkeypatch)
    return cfg, blocks, clock, calls, spawned, followed


def committed(commit_env, minutes="60"):
    cfg, blocks, clock, calls, *_ = commit_env
    ct.cmd_commit(cfg, "research", [minutes])
    calls.clear()
    return cfg, blocks, clock, calls


def loaded_job(args: list[str]) -> str:
    """What 'launchctl print' shows for a loaded job, trimmed to what focus reads."""
    lines = "".join(f"\t\t{a}\n" for a in args)
    return (
        f"gui/501/{ct.AGENT_LABEL} = {{\n\tstate = not running\n\n"
        f"\tprogram = {args[0]}\n\targuments = {{\n{lines}\t}}\n\n"
        "\tinherited environment = {\n\t\tSSH_AUTH_SOCK => /x\n\t}\n}\n"
    )


@pytest.mark.parametrize(
    "printed, why",
    [
        (lambda: None, "no job"),  # the plist exists, but launchd has not loaded it
        (lambda: loaded_job(["/elsewhere/focus", "--config", "/n.md", "tick"]), "runs"),
    ],
)
def test_a_commitment_needs_the_launchd_job_loaded_for_this_focus(
    commit_env, monkeypatch, printed, why
):
    cfg, _, _, calls, spawned, _ = commit_env
    assert ct.AGENT_PLIST.exists()
    monkeypatch.setattr(ct, "launchd_print", printed)
    with pytest.raises(SystemExit, match=f"{why}.*install-agent"):
        ct.cmd_commit(cfg, "research", ["60"])
    assert ct.read_commit() is None and calls == [] and spawned == []


def test_the_loaded_job_is_read_from_launchctl_print(commit_env):
    assert ct.tick_job_problem() is None


def test_a_refused_install_leaves_no_plist(monkeypatch, tmp_path):
    monkeypatch.setattr(ct, "AGENT_PLIST", tmp_path / "agents" / "tick.plist")

    def run(cmd, **k):
        return ct.subprocess.CompletedProcess(
            cmd, 5 if cmd[1] == "bootstrap" else 0, "", "Input/output error"
        )

    monkeypatch.setattr(ct.subprocess, "run", run)
    monkeypatch.setattr(ct, "build_tick_app", lambda: False)
    with pytest.raises(SystemExit, match="refused"):
        ct.cmd_install_agent()
    assert not ct.AGENT_PLIST.exists()


def test_the_job_runs_focus_behind_the_launcher_once_it_is_installed():
    plain = ct.tick_args()
    assert plain[-1] == "tick" and "focus-tick" not in plain[0]
    ct.tick_exe().parent.mkdir(parents=True)
    ct.tick_exe().write_text("")
    assert ct.tick_args() == [str(ct.tick_exe())] + plain


@pytest.mark.skipif(
    sys.platform != "darwin" or not ct.shutil.which("swiftc"), reason="needs swiftc"
)
def test_the_launcher_is_built_signed_once_and_passes_the_exit_status(capsys):
    assert ct.build_tick_app()
    info = ct.plistlib.loads((ct.TICK_APP / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == ct.AGENT_LABEL
    signed = ct.subprocess.run(
        ["codesign", "-dv", str(ct.TICK_APP)], capture_output=True, text=True
    ).stderr
    assert f"Identifier={ct.AGENT_LABEL}" in signed and "Info.plist entries=" in signed
    exe = ct.tick_exe()
    r = ct.subprocess.run(
        [str(exe), "/bin/sh", "-c", "echo hi; exit 3"], capture_output=True, text=True
    )
    assert (r.returncode, r.stdout) == (3, "hi\n")
    # An unchanged source is not rebuilt: a rebuild would cost the macOS grant.
    before = exe.stat().st_mtime_ns
    capsys.readouterr()
    assert ct.build_tick_app()
    assert exe.stat().st_mtime_ns == before and capsys.readouterr().out == ""


def test_a_commitment_leaves_a_keeper_that_ticks_until_it_ends(commit_env, monkeypatch):
    cfg, blocks, clock, calls, spawned, _ = commit_env
    ct.cmd_commit(cfg, "research", ["10"])
    assert ("commit-keep",) in spawned
    calls.clear()

    def sleep(s):  # the launchd job is gone; only the keeper runs
        clock.advance(s / 60)
        if clock.now >= ct.read_commit()["until"]:
            run_out(blocks)

    monkeypatch.setattr(ct.time, "sleep", sleep)
    ct.cmd_commit_keep(cfg)
    assert ct.read_commit() is None
    assert [c[:3] for c in calls if "-lock" in c][0] == (
        "-start",
        "mode: research",
        "-lock",
    )
    assert blocks["mode: research"]["enabled"] == "true"  # the mode stays on, unlocked


def test_a_commitment_starts_the_mode_and_locks_it_one_wait_ahead(commit_env):
    cfg, blocks, clock, calls, *_ = commit_env
    ct.cmd_commit(cfg, "research", ["60"])
    # Started already locked: no plain '-start' leaves it running unlocked first.
    assert calls == [("-start", "mode: research", "-lock", "5")]
    assert blocks["mode: research"]["enabled"] == "true"
    assert blocks["mode: research"]["lock"] == stamp(clock.now + 300)
    s = ct.read_commit()
    assert s["until"] == clock.now + 3600 and s["pending"] == []


def test_committing_the_running_mode_locks_it_where_it_runs(commit_env):
    cfg, blocks, clock, calls, *_ = commit_env
    blocks["mode: research"]["enabled"] = "true"
    ct.cmd_commit(cfg, "research", ["30"])
    assert calls == [("-start", "mode: research", "-lock", "5")]
    assert blocks["mode: research"]["lock"] == stamp(clock.now + 300)


def test_an_allow_still_locks_again_when_the_note_cannot_be_edited(
    commit_env, monkeypatch
):
    cfg, blocks, clock, _ = committed(commit_env)
    request(commit_env, monkeypatch, ct.cmd_allow, ["docs.example.org"], False)
    monkeypatch.setattr(ct, "CONFIG_PATH", ct.CONFIG_PATH.with_name("gone.md"))
    run_out(blocks)
    ct.cmd_commit_wait(cfg)
    b = blocks["mode: research"]
    assert b["enabled"] == "true" and b["lock"] == stamp(clock.now + 300)
    assert "docs.example.org" in b["exceptions"]
    assert ct.read_commit()["pending"] == []
    assert log_lines()[-1]["note_failed"]


def test_any_focus_command_first_keeps_the_commitment(commit_env):
    cfg, blocks, clock, _ = committed(commit_env, "30")
    # Without the launchd job the lock ran out; the next command puts it back.
    clock.advance(10)
    run_out(blocks)
    ct.catch_up(cfg)
    assert blocks["mode: research"]["enabled"] == "true"
    clock.advance(30)
    run_out(blocks)
    ct.catch_up(cfg)  # past the end: cleared, and the mode stays on
    assert ct.read_commit() is None
    ct.cmd_break(cfg, ["10"])  # no longer refused
    assert blocks["mode: research"]["enabled"] == "false"


def test_a_tick_that_waited_for_the_lock_does_not_restart_an_ended_commitment(
    commit_env, monkeypatch
):
    cfg, blocks, clock, calls = committed(commit_env)
    clock.advance(10)
    run_out(blocks)  # stopped: a restart is due, unless the end was applied meanwhile
    contended(monkeypatch, "commit_lock", lambda: ct.COMMIT_FILE.unlink())
    ct.commit_tick(cfg)
    assert calls == [] and blocks["mode: research"]["enabled"] == "false"


def test_a_capped_mode_cannot_be_committed(commit_env):
    cfg, *_ = commit_env
    with pytest.raises(SystemExit, match="capped"):
        ct.cmd_commit(cfg, "writing", ["60"])


@pytest.mark.parametrize(
    "lock_left, until_left, want",
    [
        (None, 3600, 5),  # unlocked or stopped: lock at once
        (240, 3600, None),  # four minutes left: not yet
        (120, 3600, 5),  # two minutes left: extend a full wait
        (120, 150, 3),  # near the end: just past the end, rounded up
        (120, 100, None),  # the lock already reaches the end
        (30, -10, None),  # past the end: let the last lock run out
        (None, 50, 1),
    ],
)
def test_when_and_how_far_the_rolling_lock_is_extended(lock_left, until_left, want):
    now = 1_000_000.0
    lock_to = None if lock_left is None else now + lock_left
    assert ct.lock_minutes(now, lock_to, now + until_left, 5) == want


def test_an_extension_never_asks_for_a_shorter_lock():
    now = 1_000_000.0
    # five minutes of lock left and a five-minute wait: nothing to gain
    assert ct.lock_minutes(now, now + 300, now + 3600, 5, ahead=ct.math.inf) is None


def test_the_tick_extends_the_lock_shortly_before_it_runs_out(commit_env):
    cfg, blocks, clock, calls = committed(commit_env)
    clock.advance(2)
    ct.catch_up(cfg)
    assert calls == []  # three minutes of lock left
    clock.advance(1)
    ct.catch_up(cfg)
    assert calls == [("-start", "mode: research", "-lock", "5")]
    assert blocks["mode: research"]["lock"] == stamp(clock.now + 300)


def refused(fn, *args):
    with pytest.raises(SystemExit) as e:
        fn(*args)
    msg = str(e.value)
    assert "committed block" in msg and "focus allow" in msg and "focus end" in msg


def test_a_commitment_refuses_break_off_only_and_other_modes(
    commit_env, only_cfg, monkeypatch
):
    cfg, blocks, _, calls = committed(commit_env)
    refused(ct.cmd_break, cfg, ["10"])
    refused(ct.cmd_off, cfg)
    refused(ct.cmd_start, cfg, "writing")
    refused(ct.cmd_capped, cfg, "writing", [])
    refused(ct.cmd_commit, cfg, "writing", ["30"])
    refused(ct.cmd_only, only_cfg, ["bear", "5"])
    assert calls == [] and blocks["mode: research"]["enabled"] == "true"
    ct.cmd_start(cfg, "research")  # its own mode: nothing to refuse
    ct.cmd_timer(cfg, "deep", ["30"])  # a timer only tightens
    assert blocks["timer: deep"]["enabled"] == "true"


def test_allow_and_end_refuse_without_a_terminal(commit_env):
    committed(commit_env)
    for fn, args in ((ct.cmd_allow, (["docs.example.org"], False)), (ct.cmd_end, ())):
        with pytest.raises(SystemExit, match="only in a terminal"):
            fn(commit_env[0], *args)
    assert ct.read_commit()["pending"] == [] and log_lines() == []


def test_allow_needs_the_text_typed_back_exactly(commit_env, monkeypatch):
    cfg, *_ = committed(commit_env)
    at_terminal(monkeypatch, ["xx"])
    with pytest.raises(SystemExit, match="did not match"):
        ct.cmd_allow(cfg, ["docs.example.org"], False)
    assert ct.read_commit()["pending"] == []


def test_only_sites_can_be_allowed_and_only_during_a_commitment(commit_env):
    cfg, *_ = commit_env
    with pytest.raises(SystemExit, match="focus add"):
        ct.cmd_allow(cfg, ["docs.example.org"], False)
    committed(commit_env)
    with pytest.raises(SystemExit, match="not apps"):
        ct.cmd_allow(cfg, ["Some App"], True)


def test_an_agent_allow_waits_before_any_prompt(commit_env, monkeypatch):
    cfg, *_ = committed(commit_env)
    monkeypatch.setenv("CLAUDECODE", "1")
    with pytest.raises(SystemExit) as e:
        ct.cmd_allow(cfg, ["docs.example.org"], False)
    assert e.value.code == 3 and ct.read_commit()["pending"] == []


def request(commit_env, monkeypatch, fn, *args):
    at_terminal(monkeypatch, ["xxx", "need the reference docs"])
    fn(commit_env[0], *args)


def test_an_allow_waits_for_the_lock_then_lands_in_the_note_and_the_block(
    commit_env, monkeypatch
):
    cfg, blocks, clock, calls = committed(commit_env)
    spawned = commit_env[4]
    request(commit_env, monkeypatch, ct.cmd_allow, ["docs.example.org"], False)
    (entry,) = log_lines()
    assert entry["command"] == "focus allow docs.example.org"
    assert entry["reason"] == "need the reference docs"
    assert ("commit-wait",) in spawned
    # While the request waits, the tick stops extending the lock.
    clock.advance(4)
    ct.catch_up(cfg)
    assert calls == []
    # The waiter polls until Cold Turkey's lock runs out and the block stops.
    ran_out = []

    def sleep(s):
        if not ran_out:
            ran_out.append(s)
            run_out(blocks)

    monkeypatch.setattr(ct.time, "sleep", sleep)
    ct.cmd_commit_wait(cfg)
    assert ran_out
    assert [c[0] for c in calls] == ["-add", "-start"]  # the exception first
    b = blocks["mode: research"]
    assert "docs.example.org" in b["exceptions"]
    assert b["enabled"] == "true" and b["lock"] == stamp(clock.now + 300)
    assert ct.read_commit()["pending"] == []
    note = ct.load_config(ct.CONFIG_PATH)
    assert note["groups"]["added-research"] == {"sites": ["docs.example.org"]}
    assert "added-research" in note["modes"]["research"]["allow"]
    assert "docs.example.org" in ct.desired_exceptions(note, "research")


def test_an_end_waits_for_the_lock_then_leaves_no_mode(commit_env, monkeypatch):
    cfg, blocks, _, calls = committed(commit_env)
    followed = commit_env[5]
    request(commit_env, monkeypatch, ct.cmd_end)
    assert ct.status_headline(cfg, blocks).endswith(", end requested)")
    run_out(blocks)
    ct.cmd_commit_wait(cfg)
    assert ("-stop", "mode: research") in calls  # sent even though it shows stopped
    assert blocks["mode: research"]["enabled"] == "false"
    assert ct.read_commit() is None and followed[-1] == []


def test_a_dead_waiter_is_covered_by_the_tick(commit_env, monkeypatch):
    cfg, blocks, *_ = committed(commit_env)
    request(commit_env, monkeypatch, ct.cmd_end)
    run_out(blocks)
    ct.catch_up(cfg)
    assert ct.read_commit() is None


def test_a_block_found_stopped_before_the_end_is_locked_again_and_logged(commit_env):
    cfg, blocks, clock, _ = committed(commit_env)
    clock.advance(20)  # the Mac slept through the extensions
    run_out(blocks)
    ct.catch_up(cfg)
    b = blocks["mode: research"]
    assert b["enabled"] == "true" and b["lock"] == stamp(clock.now + 300)
    (entry,) = log_lines()
    assert entry["command"] == "focus tick" and "again" in entry["reason"]


def test_a_restart_that_does_not_land_is_not_logged(commit_env, monkeypatch):
    cfg, blocks, _, _ = committed(commit_env)
    run_out(blocks)
    monkeypatch.setattr(ct, "ct_send", lambda *a: None)  # the screen is locked
    ct.catch_up(cfg)
    assert log_lines() == [] and ct.read_commit() is not None


def test_after_the_end_the_mode_stays_on_unlocked(commit_env):
    cfg, blocks, clock, _ = committed(commit_env, "10")
    for _ in range(10):  # the tick keeps the lock ahead until the end
        clock.advance(1)
        ct.catch_up(cfg)
    assert ct.read_commit() is not None  # the last lock reaches the end
    clock.advance(1)
    run_out(blocks)
    ct.catch_up(cfg)
    b = blocks["mode: research"]
    assert ct.read_commit() is None and b["enabled"] == "true" and b["lock"] == "none"


def test_status_shows_the_commitment(commit_env):
    cfg, blocks, clock, _ = committed(commit_env)
    end = dt.datetime.fromtimestamp(clock.now + 3600)
    assert ct.status_headline(cfg, blocks) == (
        f"now: research mode (committed until {end:%H:%M})"
    )


def test_commit_note_keys_and_reserved_names_are_checked(tmp_path):
    with pytest.raises(SystemExit, match="commit_wait_minutes"):
        ct.load_config(note_with(tmp_path, "commit_wait_minutes: soon"))
    with pytest.raises(SystemExit, match=">= 2"):  # it would lapse between ticks
        ct.load_config(note_with(tmp_path, "commit_wait_minutes: 1"))
    p = tmp_path / "n.md"
    p.write_text(NOTE.replace("writing:", "end:", 1))
    with pytest.raises(SystemExit, match="taken by the command"):
        ct.load_config(p)


def alfred_rows(capsys, cfg, query):
    capsys.readouterr()
    ct.cmd_alfred(cfg, query)
    return json.loads(capsys.readouterr().out)["items"]


def test_alfred_offers_committed_blocks(cfg, capsys, monkeypatch):
    monkeypatch.setattr(ct, "read_blocks", lambda: {})
    rows = alfred_rows(capsys, cfg, "commit")
    assert {r["arg"] for r in rows} == {
        f"{m} {ct.ALFRED_COMMIT_MIN} --commit" for m in cfg["modes"]
    }
    # 'research 25' means a committed research block for 25 minutes, and only that.
    rows = alfred_rows(capsys, cfg, "research 25")
    assert [r["arg"] for r in rows] == ["research 25 --commit"]
    assert [r["arg"] for r in alfred_rows(capsys, cfg, "commit res")] == [
        f"research {ct.ALFRED_COMMIT_MIN} --commit"
    ]


def test_alfred_commit_rows_while_one_runs(cfg, capsys, monkeypatch):
    monkeypatch.setattr(ct, "read_blocks", lambda: {})
    ct.write_commit(
        {"mode": "research", "until": 2_000_000_000, "locked_to": 0, "pending": []}
    )
    rows = alfred_rows(capsys, cfg, "commit")
    assert rows[0]["uid"] == "commit-running" and rows[0]["valid"] is False
    assert all(r["valid"] is False for r in rows if r["uid"] != "commit-running")


@pytest.fixture
def default_cfg(tmp_path, monkeypatch):
    cfg = ct.load_config(note_with(tmp_path, "default_mode: {mode: research}"))
    started = []
    monkeypatch.setattr(ct, "cmd_start", lambda cfg, mode: started.append(mode))
    monkeypatch.setattr(ct, "running_modes", lambda cfg: [])
    return cfg, started


MON_0901 = dt.datetime(2026, 11, 16, 9, 1)  # a Monday


def test_default_mode_starts_once_a_weekday_morning(default_cfg):
    cfg, started = default_cfg
    assert ct.default_start(cfg, MON_0901) == "research"
    assert ct.default_start(cfg, MON_0901 + dt.timedelta(minutes=5)) is None
    assert started == ["research"]
    # the next weekday fires again
    assert ct.default_start(cfg, MON_0901 + dt.timedelta(days=1)) == "research"


@pytest.mark.parametrize(
    "when",
    [
        dt.datetime(2026, 11, 21, 9, 1),  # Saturday
        dt.datetime(2026, 11, 16, 8, 59),  # before start
        dt.datetime(2026, 11, 16, 12, 0),  # at 'until'
    ],
)
def test_default_mode_stays_out_of_its_hours(default_cfg, when):
    cfg, started = default_cfg
    assert ct.default_start(cfg, when) is None and started == []


def test_default_mode_marks_the_day_when_something_runs(default_cfg, monkeypatch):
    cfg, started = default_cfg
    monkeypatch.setattr(ct, "running_modes", lambda cfg: ["writing"])
    assert ct.default_start(cfg, MON_0901) is None
    monkeypatch.setattr(ct, "running_modes", lambda cfg: [])
    # stopped by hand later that morning: not started again the same day
    assert ct.default_start(cfg, MON_0901 + dt.timedelta(hours=1)) is None
    assert started == []


def test_default_mode_config_is_checked(tmp_path):
    for bad in (
        "default_mode: {mode: nosuch}",
        "default_mode: {mode: research, start: '9am'}",
        "default_mode: {mode: research, days: [monday]}",
        "default_mode: {mode: research, when: x}",
    ):
        with pytest.raises(SystemExit, match="default_mode"):
            ct.load_config(note_with(tmp_path, bad))


def test_sync_names_what_a_committed_blocks_lock_keeps_out(
    commit_env, monkeypatch, capsys
):
    cfg, blocks, clock, calls = committed(commit_env)
    blocks["mode: research"]["exceptions"].remove("arxiv.org")
    gated = []
    monkeypatch.setattr(ct, "gate", lambda *a: gated.append(a))
    ct.cmd_sync(cfg)  # no "did not take these additions" exit
    out = capsys.readouterr().out
    assert "committed and locked" in out and "focus allow arxiv.org" in out
    assert not any("mode: research" in c and "-add" in c for c in calls)
    assert gated == []  # nothing for an agent to wait for: it could not land


def test_sync_writes_an_import_file_instead_of_many_cli_adds(
    cfg, monkeypatch, tmp_path, capsys
):
    # Over IMPORT_OVER new sites for one list go to a .txt for Cold Turkey's block-editor
    # import, since each CLI add brings Cold Turkey to the front (2026-11-18).
    monkeypatch.setattr(ct, "IMPORT_OVER", 0)
    monkeypatch.setattr(ct.Path, "home", lambda: tmp_path)
    research = mode_block(cfg, "research", "false")
    research["exceptions"].remove("arxiv.org")
    blocks = {
        "mode: research": research,
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    calls = fake_cold_turkey(monkeypatch, blocks)
    ct.cmd_sync(cfg)
    assert not [c for c in calls if c[0] == "-add"]
    f = tmp_path / "Downloads" / "focus-mode-research-exceptions.txt"
    assert f.read_text() == "arxiv.org\n"
    out = capsys.readouterr().out
    assert "Website Exceptions tab > Import > Websites from file..." in out
    assert str(f) in out


def test_an_allow_of_a_site_the_note_already_has_adds_no_copy(commit_env, monkeypatch):
    cfg, blocks, clock, _ = committed(commit_env)
    blocks["mode: research"]["exceptions"].remove("arxiv.org")
    request(commit_env, monkeypatch, ct.cmd_allow, ["arxiv.org"], False)
    run_out(blocks)
    ct.cmd_commit_wait(cfg)
    assert "arxiv.org" in blocks["mode: research"]["exceptions"]
    assert "added-research" not in ct.CONFIG_PATH.read_text()


def test_a_commitments_end_names_sites_held_out_but_does_not_add_them(
    commit_env, monkeypatch
):
    cfg, blocks, clock, calls = committed(commit_env, "30")
    blocks["mode: research"]["exceptions"].remove("arxiv.org")
    said = []
    monkeypatch.setattr(ct, "notify", said.append)
    clock.advance(40)
    run_out(blocks)
    ct.catch_up(cfg)
    assert ct.read_commit() is None
    assert "focus sync" in said[-1] and "arxiv.org" in said[-1]
    # the tick never loosens by itself
    assert "arxiv.org" not in blocks["mode: research"]["exceptions"]


def test_alfred_capped_mode_passes_typed_minutes(tmp_path, capsys, monkeypatch):
    # 'writing 2' in Alfred used to run the full 30-minute cap: the row's arg was the
    # bare mode name, so the typed minutes never reached 'focus'.
    monkeypatch.setattr(ct, "read_blocks", lambda: {})
    cfg = ct.load_config(note_with(tmp_path, CAPPED))
    assert [r["arg"] for r in alfred_rows(capsys, cfg, "writing 2")] == ["writing 2"]
    assert [r["arg"] for r in alfred_rows(capsys, cfg, "writing")] == ["writing 30"]
    # Past the cap, Alfred offers a day stretch instead of a row 'focus' would refuse.
    assert [r["arg"] for r in alfred_rows(capsys, cfg, "writing 90")] == [
        "writing --day 90"
    ]
    # A running capped mode stays pickable: renewing it is allowed. The row used to be
    # greyed out while it ran, so 'admin' did nothing mid-stretch.
    monkeypatch.setattr(
        ct, "read_blocks", lambda: {ct.PREFIX + "writing": {"enabled": "true"}}
    )
    monkeypatch.setattr(ct, "mode_blocks", lambda b: b)
    rows = alfred_rows(capsys, cfg, "writing")
    assert rows[0].get("valid", True) and "(running)" in rows[0]["title"]
    # An uncapped mode with minutes is still a committed block.
    assert [r["arg"] for r in alfred_rows(capsys, cfg, "research 25")] == [
        "research 25 --commit"
    ]


def test_menu_rows_offer_every_mode_and_ask_minutes_only_where_taken(tmp_path):
    cfg = ct.load_config(note_with(tmp_path, TIMER + "\n" + CAPPED))
    blocks = {ct.PREFIX + "research": {"enabled": "true"}}
    rows = {n: (sec, desc, mins) for sec, n, desc, mins in ct.menu_rows(cfg, blocks)}
    assert set(cfg["modes"]) <= rows.keys()
    assert {"break", "off", "status"} <= rows.keys()
    assert rows["research"][1].startswith("● running")
    assert rows["research"][2] is None  # a plain mode takes no minutes
    assert rows["writing"][2] == 30  # a capped mode asks, defaulting to its cap
    assert rows["deep"] == ("Timers", rows["deep"][1], 30)
    assert all("|" not in n for n in rows)  # the picker splits rows on '|'


def test_bare_focus_falls_back_to_the_list_off_a_terminal(cfg, monkeypatch):
    monkeypatch.setattr(ct.sys.stdin, "isatty", lambda: False)
    monkeypatch.setattr(ct.subprocess, "run", lambda *a, **k: pytest.fail("menu drawn"))
    assert ct.cmd_menu(cfg) is False


def test_bare_focus_piped_gets_the_list_though_stdin_is_a_terminal(cfg, monkeypatch):
    # 'focus | cat' in a shell: stdin and stderr are the terminal, stdout a pipe.
    monkeypatch.setattr(ct.sys.stdin, "isatty", lambda: True)
    monkeypatch.setattr(ct.sys.stderr, "isatty", lambda: True)
    monkeypatch.setattr(ct.sys.stdout, "isatty", lambda: False)
    monkeypatch.setattr(ct.shutil, "which", lambda name: "/bin/claude-tools")
    monkeypatch.setattr(ct.subprocess, "run", lambda *a, **k: pytest.fail("menu drawn"))
    assert ct.cmd_menu(cfg) is False


def avoid_blocks(cfg):
    avoid = {
        "enabled": "true",
        "lock": "none",
        "web": ["x.com", "*casino*"],
        "exceptions": ["file://*.*"],
        "apps": [],
    }
    return {
        "mode: research": mode_block(cfg, "research", "false"),
        "mode: writing": mode_block(cfg, "writing", "false"),
        "avoid": avoid,
    }


def test_sync_adds_an_always_on_blocks_missing_allowed_site(cfg, monkeypatch, capsys):
    # status says "Run 'focus sync', which adds it" for this; sync used to skip it.
    blocks = avoid_blocks(cfg)
    fake_cold_turkey(monkeypatch, blocks)
    assert "avoid:localhost" in ct.sync_loosen(cfg, blocks)  # an agent waits for it
    ct.cmd_sync(cfg)
    assert blocks["avoid"]["exceptions"] == ["file://*.*", "localhost"]
    assert "avoid: added localhost" in capsys.readouterr().out


def test_a_locked_always_on_block_that_refuses_an_allowed_site_is_a_hand_edit(
    cfg, monkeypatch, capsys
):
    fake_cold_turkey(monkeypatch, avoid_blocks(cfg), refuse={"avoid"})
    ct.cmd_sync(cfg)  # not a failed sync: a lock is expected on these blocks
    out = capsys.readouterr().out
    assert "avoid: could not add localhost" in out
    assert "did not take the new allowed site localhost" in out


@pytest.fixture
def picks_cfg(only_cfg, tmp_path, monkeypatch):
    """The only note with defaults: a group, an installed app, and one not installed."""
    fake_app(tmp_path, "Zotero")
    monkeypatch.setattr(ct, "APP_DIRS", [tmp_path])
    p = tmp_path / "default.md"
    p.write_text(
        ONLY_NOTE.replace(
            "  minutes: 30", "  minutes: 30\n  default: [bear, Zotero, Missing]"
        )
    )
    return ct.load_config(p)


def test_defaults_name_groups_and_installed_apps(picks_cfg):
    assert ct.only_defaults(picks_cfg) == ["bear", "app:Zotero"]


def test_named_picks_bring_the_defaults_and_no_leaves_one_out(picks_cfg, session_env):
    ct.cmd_only(picks_cfg, ["llms", "no:zotero", "45"])
    assert ct.read_only()["groups"] == ["bear", "llms"]


def test_the_picker_starts_with_the_defaults_ticked(picks_cfg, monkeypatch):
    monkeypatch.setattr(ct.sys, "stdin", type("T", (), {"isatty": lambda s: True})())
    monkeypatch.setattr(ct.shutil, "which", lambda n: "/bin/fzf")
    seen = {}

    def fake_fzf(cmd, input, **k):
        seen["cmd"], seen["rows"] = cmd, input.split("\n")
        return ct.subprocess.CompletedProcess(cmd, 0, stdout=seen["rows"][1] + "\n")

    monkeypatch.setattr(ct.subprocess, "run", fake_fzf)
    # Unticking bear in fzf leaves Zotero, and that is all that comes back.
    picked = ct.pick_groups(picks_cfg, [], ct.only_defaults(picks_cfg))
    assert picked == ["app:Zotero"]
    assert [r.split("\t")[0] for r in seen["rows"][:2]] == ["bear", "app:Zotero"]
    assert "--bind=load:pos(1)+select+pos(2)+select+first" in seen["cmd"]
    assert f"--header={ct.PICK_HELP}\nPicked 2: bear, Zotero" in seen["cmd"]


def test_a_bare_only_offers_the_defaults_to_the_picker(
    picks_cfg, session_env, monkeypatch
):
    got = []
    monkeypatch.setattr(
        ct, "pick_groups", lambda cfg, exclude, preset=(): got.append(preset) or []
    )
    ct.cmd_only(picks_cfg, [])
    assert got == [["bear", "app:Zotero"]]


def test_no_takes_a_pick_out_of_a_running_session(picks_cfg, session_env):
    _, writes, *_ = session_env
    ct.write_only({"groups": ["bear", "llms"], "until": 2e9, "back": []})
    ct.cmd_only(picks_cfg, ["no:bear"])
    assert ct.read_only()["groups"] == ["llms"]
    assert writes == [[ct.ONLY]]


def test_alfred_starts_from_the_defaults_and_no_drops_one(picks_cfg, capsys):
    rows = alfred_rows(capsys, picks_cfg, "only ")
    assert rows[0]["arg"] == "only bear app:Zotero 30"
    bear = next(r for r in rows if r["title"] == "✓ bear")
    assert bear["subtitle"].startswith("default")
    assert bear["autocomplete"] == "only no:bear "

    rows = alfred_rows(capsys, picks_cfg, "only no:bear ")
    assert rows[0]["arg"] == "only app:Zotero no:bear 30"
    back = next(r for r in rows if r["title"] == "bear")
    assert back["autocomplete"] == "only "  # picking it again drops the no: word


def test_screenzen_leaves_out_apps_the_running_mode_blocks_in_cold_turkey(
    tmp_path, monkeypatch
):
    note = tmp_path / "note.md"
    note.write_text(
        "```yaml\ngroups:\n  chat: {apps: [WhatsApp]}\n  maps: {apps: [Maps]}\n"
        "modes:\n  research: {allow: [], block: [chat]}\n"
        "blocklists:\n  screenzen:\n    '🚫 x': {block: [chat, maps]}\n```\n"
    )
    cfg = ct.load_config(note)
    group = {"groupName": "🚫 x", "isDisabled": False, "customSites": [], "apps": []}
    allow = {
        "groupName": "✅ focus: research",
        "isDisabled": False,
        "alwaysActive": True,
        "customSites": [],
        "apps": [],
        "id": "A",
    }
    monkeypatch.setattr(ct, "sz_export", lambda: b"")
    monkeypatch.setattr(ct, "sz_groups", lambda raw: [group, allow])
    monkeypatch.setattr(
        ct, "sz_app", lambda name, t: {**t, "appName": name, "appBundle": f"id.{name}"}
    )
    held = {"enabled": "true", "apps": ["app:WhatsApp.app:id.WhatsApp"]}
    monkeypatch.setattr(ct, "read_blocks", lambda: {ct.PREFIX + "research": held})
    loosen = ct.cmd_screenzen(cfg, dry_run=True, modes=["research"], quiet=True)
    assert [a["appName"] for a in group["apps"]] == ["Maps"]
    assert not any("WhatsApp" in x for x in loosen)
    # With no mode Cold Turkey holds nothing, so ScreenZen pauses both again.
    ct.cmd_screenzen(cfg, dry_run=True, modes=[], quiet=True)
    assert [a["appName"] for a in group["apps"]] == ["WhatsApp", "Maps"]
    # In an open window with no mode, every focus group in ScreenZen is off.
    cfg["windows"] = ["00:00-23:59"]
    ct.cmd_screenzen(cfg, dry_run=True, modes=[], quiet=True)
    assert group["isDisabled"] and allow["isDisabled"]
    # A mode started by hand in a window still gets its usual groups.
    ct.cmd_screenzen(cfg, dry_run=True, modes=["research"], quiet=True)
    assert not allow["isDisabled"]


WINDOWS = 'windows: ["12:30-13:00"]'


def test_a_window_stops_the_mode_until_it_ends_then_the_mode_comes_back(
    capped_env, tmp_path
):
    _, blocks, clock, _, notes = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + WINDOWS))
    assert ct.window_start(cfg, dt.datetime(2026, 11, 17, 12, 29)) is None
    at = dt.datetime(2026, 11, 17, 12, 31)
    clock.now = at.timestamp()
    assert ct.window_start(cfg, at) == "12:30-13:00"
    assert on(blocks) == [] and "open until 13:00" in notes[-1]
    assert ct.in_off_hours(cfg, at)  # 'focus off' works in a window
    clock.now = dt.datetime(2026, 11, 17, 13, 0).timestamp()
    ct.catch_up(cfg)
    assert on(blocks) == ["mode: research"]  # the break the window took has ended
    # once a day: a mode started by hand later in the window stays on
    assert ct.window_start(cfg, at + dt.timedelta(minutes=5)) is None
    assert on(blocks) == ["mode: research"]


def test_a_commitment_keeps_the_window_closed(capped_env, tmp_path):
    _, blocks, _, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + WINDOWS))
    ct.write_commit(
        {"mode": "research", "until": 2_000_000_000, "locked_to": 0, "pending": []}
    )
    assert ct.window_start(cfg, dt.datetime(2026, 11, 17, 12, 45)) is None
    assert on(blocks) == ["mode: research"]


def test_a_bad_window_is_refused(tmp_path):
    with pytest.raises(SystemExit, match="windows"):
        ct.load_config(note_with(tmp_path, 'windows: ["12:30"]'))


def test_a_window_ends_a_capped_stretch_and_comes_back_to_the_mode_before_it(
    capped_env, tmp_path
):
    _, blocks, clock, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + WINDOWS))
    clock.now = dt.datetime(2026, 11, 17, 12, 15).timestamp()
    ct.cmd_capped(cfg, "writing", [])
    assert on(blocks) == ["mode: writing"]
    at = dt.datetime(2026, 11, 17, 12, 31)
    clock.now = at.timestamp()
    ct.window_start(cfg, at)
    assert on(blocks) == [] and ct.read_capped() is None
    assert ct.read_break()["modes"] == ["research"]
    # whichever runs first at the end, writing never comes back without its cap
    clock.now = dt.datetime(2026, 11, 17, 13, 0).timestamp()
    ct.end_capped(cfg)
    ct.catch_up(cfg)
    assert on(blocks) == ["mode: research"]


def test_a_break_that_ends_inside_a_window_is_stretched_to_its_end(
    capped_env, tmp_path
):
    _, blocks, clock, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, WINDOWS))
    ct.switch("mode: research", on=False)
    end_of_break = dt.datetime(2026, 11, 17, 12, 40).timestamp()
    ct.BREAK_FILE.write_text(json.dumps({"modes": ["research"], "until": end_of_break}))
    at = dt.datetime(2026, 11, 17, 12, 31)
    clock.now = at.timestamp()
    ct.window_start(cfg, at)
    assert ct.read_break()["until"] == dt.datetime(2026, 11, 17, 13, 0).timestamp()
    clock.now = end_of_break
    ct.catch_up(cfg)
    assert on(blocks) == []  # still open at 12:40


def test_automatic_starts_wait_for_an_open_window(capped_env, tmp_path):
    _, blocks, _, _, _ = capped_env
    sched = 'scheduled_mode: {mode: writing, start: "12:00", until: "13:30"}'
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + WINDOWS + "\n" + sched))
    assert ct.scheduled_start(cfg, dt.datetime(2026, 11, 17, 12, 45)) is None
    assert on(blocks) == ["mode: research"]
    assert ct.read_state(ct.SCHEDULED_FILE) is None  # the day is not used up


def asleep_display(monkeypatch):
    """Drop every Cold Turkey command while asleep[0] is True, as the agent does with
    the display off (21 Nov 2026: the 21:30 start and the 22:00 stop were never read)."""
    send, asleep = ct.ct_send, [True]
    monkeypatch.setattr(ct, "ct_send", lambda *a: None if asleep[0] else send(*a))
    return asleep


def test_a_scheduled_start_cold_turkey_missed_is_retried(
    capped_env, tmp_path, monkeypatch
):
    _, blocks, clock, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + SCHEDULED))
    asleep = asleep_display(monkeypatch)
    at = dt.datetime(2026, 11, 17, 21, 30)
    clock.now = at.timestamp()
    with pytest.raises(SystemExit, match="did not"):
        ct.scheduled_start(cfg, at)
    assert ct.read_state(ct.SCHEDULED_FILE) is None  # the day is not used up
    asleep[0] = False
    at += dt.timedelta(minutes=6)
    clock.now = at.timestamp()
    assert ct.scheduled_start(cfg, at) == "writing"
    assert on(blocks) == ["mode: writing"] and ct.read_capped()["off_after"]


def test_a_window_stop_cold_turkey_missed_is_retried(
    capped_env, tmp_path, monkeypatch
):
    _, blocks, clock, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + WINDOWS))
    asleep = asleep_display(monkeypatch)
    at = dt.datetime(2026, 11, 17, 12, 30)
    clock.now = at.timestamp()
    with pytest.raises(SystemExit, match="did not stop 'mode: research'"):
        ct.window_start(cfg, at)
    assert ct.read_state(ct.WINDOW_FILE) is None and on(blocks) == ["mode: research"]
    asleep[0] = False
    at += dt.timedelta(minutes=18)
    clock.now = at.timestamp()
    assert ct.window_start(cfg, at) == "12:30-13:00"
    assert on(blocks) == [] and ct.read_break()["modes"] == ["research"]
    clock.now = dt.datetime(2026, 11, 17, 13, 0).timestamp()
    ct.catch_up(cfg)
    assert on(blocks) == ["mode: research"]


def test_a_missed_window_stop_keeps_a_capped_stretch_capped_on_retry(
    capped_env, tmp_path, monkeypatch
):
    _, blocks, clock, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + WINDOWS))
    clock.now = dt.datetime(2026, 11, 17, 12, 15).timestamp()
    ct.cmd_capped(cfg, "writing", [])
    asleep = asleep_display(monkeypatch)
    at = dt.datetime(2026, 11, 17, 12, 30)
    clock.now = at.timestamp()
    with pytest.raises(SystemExit):
        ct.window_start(cfg, at)
    assert ct.read_capped()["mode"] == "writing"  # put back with the window marker
    asleep[0] = False
    at += dt.timedelta(minutes=10)
    clock.now = at.timestamp()
    assert ct.window_start(cfg, at) == "12:30-13:00"
    assert ct.read_break()["modes"] == ["research"]  # never writing without its cap
    clock.now = dt.datetime(2026, 11, 17, 13, 0).timestamp()
    ct.end_capped(cfg)
    ct.catch_up(cfg)
    assert on(blocks) == ["mode: research"]


def test_a_window_retry_brings_back_a_mode_the_failed_attempt_did_stop(
    capped_env, tmp_path, monkeypatch
):
    # Found by review: two modes on, the first stop lands, the second is missed.
    _, blocks, clock, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + WINDOWS))
    blocks["mode: writing"]["enabled"] = "true"
    send, drop = ct.ct_send, [True]
    monkeypatch.setattr(
        ct,
        "ct_send",
        lambda *a: None if a[:2] == ("-stop", "mode: writing") and drop[0] else send(*a),
    )
    at = dt.datetime(2026, 11, 17, 12, 30)
    clock.now = at.timestamp()
    with pytest.raises(SystemExit, match="did not stop 'mode: writing'"):
        ct.window_start(cfg, at)
    assert on(blocks) == ["mode: writing"]
    drop[0] = False
    at += dt.timedelta(minutes=1)
    clock.now = at.timestamp()
    assert ct.window_start(cfg, at) == "12:30-13:00"
    assert on(blocks) == []
    clock.now = dt.datetime(2026, 11, 17, 13, 0).timestamp()
    ct.catch_up(cfg)
    assert on(blocks) == ["mode: research", "mode: writing"]


def test_a_window_that_never_opened_resumes_nothing_beside_a_capped_mode(
    capped_env, tmp_path, monkeypatch
):
    # Found by review: the break listed the stretch's fallback before any stop landed.
    _, blocks, clock, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + WINDOWS))
    clock.now = dt.datetime(2026, 11, 17, 12, 45).timestamp()
    ct.cmd_capped(cfg, "writing", [])  # until 13:15
    asleep_display(monkeypatch)
    for minute in (46, 50, 59):
        at = dt.datetime(2026, 11, 17, 12, minute)
        clock.now = at.timestamp()
        with pytest.raises(SystemExit):
            ct.window_start(cfg, at)
    assert ct.read_break() is None
    clock.now = dt.datetime(2026, 11, 17, 13, 1).timestamp()
    ct.catch_up(cfg)
    assert on(blocks) == ["mode: writing"]  # research not started beside it


def test_a_window_keeps_a_stretch_started_while_it_was_stopping(
    capped_env, tmp_path, monkeypatch
):
    # Found by review: the window cleared whatever stretch was current at its end.
    _, blocks, clock, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + WINDOWS))
    clock.now = dt.datetime(2026, 11, 17, 12, 15).timestamp()
    ct.cmd_capped(cfg, "writing", [])
    newer = {"mode": "writing", "until": 1.0, "back": ["research"], "day": 0}
    send = ct.ct_send

    def renew_during_stop(*a):
        if a[:2] == ("-stop", "mode: writing"):
            ct.write_state(ct.CAPPED_FILE, newer)
        send(*a)

    monkeypatch.setattr(ct, "ct_send", renew_during_stop)
    at = dt.datetime(2026, 11, 17, 12, 31)
    clock.now = at.timestamp()
    assert ct.window_start(cfg, at) == "12:30-13:00"
    assert ct.read_state(ct.CAPPED_FILE) == newer


def test_a_scheduled_start_whose_old_stop_is_missed_still_ends_on_time(
    capped_env, tmp_path, monkeypatch
):
    _, blocks, clock, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, CAPPED + "\n" + SCHEDULED))
    send, stops_dropped = ct.ct_send, [True]
    monkeypatch.setattr(
        ct,
        "ct_send",
        lambda *a: None if a[0] == "-stop" and stops_dropped[0] else send(*a),
    )
    at = dt.datetime(2026, 11, 17, 21, 30)
    clock.now = at.timestamp()
    with pytest.raises(SystemExit, match="did not stop 'mode: research'"):
        ct.scheduled_start(cfg, at)
    assert on(blocks) == ["mode: research", "mode: writing"]
    assert ct.read_capped()["off_after"]  # writing has its end even now
    assert ct.read_state(ct.SCHEDULED_FILE) is None
    stops_dropped[0] = False
    at += dt.timedelta(minutes=1)
    clock.now = at.timestamp()
    assert ct.scheduled_start(cfg, at) == "writing"
    assert on(blocks) == ["mode: writing"]
    clock.now = dt.datetime(2026, 11, 17, 22, 0).timestamp()
    ct.end_capped(cfg)
    assert on(blocks) == []


def test_a_window_close_that_fails_is_retried(capped_env, tmp_path, monkeypatch):
    _, blocks, clock, _, _ = capped_env
    cfg = ct.load_config(note_with(tmp_path, WINDOWS))
    ct.switch("mode: research", on=False)
    ct.write_state(ct.WINDOW_FILE, {"key": "k", "until": clock.now - 1})
    results = [False, True]
    monkeypatch.setattr(ct, "sz_follow", lambda *a, **k: results.pop(0))
    assert ct.window_end(cfg) is False
    assert ct.window_end(cfg) is True
    assert ct.window_end(cfg) is False and results == []  # done: no third write


def test_a_dropped_stop_is_sent_again_and_the_old_mode_ends(cfg, monkeypatch):
    # 20 Nov 2026: a switch to comms left research running, so Messages stayed blocked.
    blocks = {
        "mode: research": mode_block(cfg, "research", "true"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    calls = fake_cold_turkey(monkeypatch, blocks)
    send = ct.ct_send
    dropped = []

    def drop_first_stop(*args):
        if args[0] == "-stop" and not dropped:
            dropped.append(args)  # the agent never read it
            return
        send(*args)

    monkeypatch.setattr(ct, "ct_send", drop_first_stop)
    ct.cmd_start(cfg, "writing")
    assert blocks["mode: research"]["enabled"] == "false"
    assert dropped and calls[-1][:2] == ("-stop", "mode: research")


def test_a_stop_that_never_lands_notifies_as_well_as_exits(cfg, monkeypatch):
    blocks = {
        "mode: research": mode_block(cfg, "research", "true"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    fake_cold_turkey(monkeypatch, blocks, refuse={"mode: research"})
    told = []
    monkeypatch.setattr(ct, "notify", told.append)
    with pytest.raises(SystemExit, match="did not stop 'mode: research'"):
        ct.cmd_start(cfg, "writing")
    assert told and "mode: research" in told[0]


def test_a_mode_started_during_the_switch_is_stopped_too(cfg, monkeypatch):
    # The running list is read before the gate and the reason prompt; a mode a waiter
    # or the tick starts in between must not stay on beside the new one.
    blocks = {
        "mode: research": mode_block(cfg, "research", "false"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    fake_cold_turkey(monkeypatch, blocks)

    def prepare():
        blocks["mode: research"]["enabled"] = "true"

    ct.cmd_start(cfg, "writing", prepare=prepare)
    assert blocks["mode: writing"]["enabled"] == "true"
    assert blocks["mode: research"]["enabled"] == "false"


@pytest.fixture
def reasons(cfg, monkeypatch):
    """research running, the real reason prompt back in place."""
    monkeypatch.setattr(ct, "loosening_reason", REAL_LOOSENING_REASON)
    blocks = {
        "mode: research": mode_block(cfg, "research", "true"),
        "mode: writing": mode_block(cfg, "writing", "false"),
    }
    fake_cold_turkey(monkeypatch, blocks)
    monkeypatch.setattr(ct, "sz_follow", lambda *a, **k: None)
    monkeypatch.setattr(ct, "spawn_self", lambda *a: None)
    return blocks


def test_a_switch_that_opens_an_app_needs_a_reason(cfg, reasons, monkeypatch):
    # research blocks Telegram and writing does not (Yulong, 2026-11-20).
    with pytest.raises(SystemExit, match="only in a terminal"):
        ct.cmd_start(cfg, "writing")
    assert on(reasons) == ["mode: research"]
    prompts = at_terminal(monkeypatch, ["need to message the editor"])
    ct.cmd_start(cfg, "writing")
    assert prompts == ["Why switching from research to writing? One line: "]
    (entry,) = log_lines()
    assert entry["command"] == "focus writing"
    assert entry["reason"] == "need to message the editor"
    assert on(reasons) == ["mode: writing"]


def test_a_blank_switch_reason_is_asked_again(cfg, reasons, monkeypatch):
    prompts = at_terminal(monkeypatch, [" ", "need to message the editor"])
    ct.cmd_start(cfg, "writing")
    assert len(prompts) == 2 and on(reasons) == ["mode: writing"]


def test_a_switch_that_opens_no_app_asks_nothing(cfg, reasons, monkeypatch):
    reasons["mode: research"]["enabled"] = "false"
    reasons["mode: writing"]["enabled"] = "true"
    prompts = at_terminal(monkeypatch, [])
    ct.cmd_start(cfg, "research")  # research blocks more apps than writing
    assert prompts == [] and on(reasons) == ["mode: research"]


def test_a_capped_target_always_loosens(tmp_path):
    cfg = ct.load_config(note_with(tmp_path, CAPPED))
    assert ct.switch_loosens(cfg, ["research"], "writing")
    assert ct.switch_loosens(cfg, [], "writing")  # leaving an only session for it
    assert not ct.switch_loosens(cfg, ["writing"], "research")


def test_a_break_and_off_need_a_reason(cfg, reasons, monkeypatch):
    monkeypatch.setattr(ct, "in_off_hours", lambda cfg, now=None: True)
    with pytest.raises(SystemExit, match="only in a terminal"):
        ct.cmd_break(cfg, ["10"])
    with pytest.raises(SystemExit, match="only in a terminal"):
        ct.cmd_off(cfg)
    assert on(reasons) == ["mode: research"]
    at_terminal(monkeypatch, ["lunch with Mia"])
    ct.cmd_break(cfg, ["10"])
    assert on(reasons) == []
    assert log_lines()[-1]["command"] == "focus break 10"


def test_an_agent_is_delayed_not_asked(cfg, reasons, monkeypatch):
    monkeypatch.setenv("CLAUDECODE", "1")
    asked = []
    monkeypatch.setattr(ct, "ask_reason", lambda what: asked.append(what) or "x")
    with pytest.raises(SystemExit) as e:
        ct.cmd_start(cfg, "writing")
    assert e.value.code == 3 and asked == []  # queued by the gate, no prompt


def test_a_tick_writes_screenzen_even_when_cold_turkey_misses_a_command(
    cfg, tmp_path, monkeypatch
):
    # 20 Nov 2026: a Cold Turkey command went unread, the tick exited before ScreenZen,
    # and ScreenZen kept the old mode's 🚫 group on through a messaging stretch.
    plist = tmp_path / "sz" / "prefs.plist"
    plist.parent.mkdir()
    plist.write_text("")
    monkeypatch.setattr(ct, "SZ_DOMAIN", plist.with_suffix(""))
    monkeypatch.setattr(ct, "SZ_LOCK", tmp_path / "screenzen.lock")

    def unread(cfg):
        sys.exit("focus: Cold Turkey did not start 'mode: research'")

    monkeypatch.setattr(ct, "catch_up", unread)
    writes = []
    monkeypatch.setattr(
        ct, "cmd_screenzen", lambda cfg, dry_run, **k: writes.append(dry_run)
    )
    with pytest.raises(SystemExit):
        ct.cmd_tick(cfg)
    assert writes == [False]


def test_a_tick_without_screenzen_installed_writes_nothing(cfg, monkeypatch):
    for step in ("catch_up", "default_start", "scheduled_start", "window_start"):
        monkeypatch.setattr(ct, step, lambda cfg: None)
    monkeypatch.setattr(
        ct, "cmd_screenzen", lambda *a, **k: pytest.fail("wrote ScreenZen")
    )
    ct.cmd_tick(cfg)


def test_an_unread_command_is_taken_back_so_it_cannot_run_hours_later(
    cfg, monkeypatch
):
    # 23 Nov 2026: a start missed in a 09:14 dark wake waited in the slot and ran when
    # the lid opened at 12:48, inside the lunch window.
    blocks = {"mode: research": mode_block(cfg, "research", "false")}
    fake_cold_turkey(monkeypatch, blocks, refuse=set(blocks))
    withdrawn = []
    monkeypatch.setattr(ct, "withdraw_command", withdrawn.append)
    with pytest.raises(SystemExit, match="took it back"):
        ct.switch("mode: research", on=True)
    assert withdrawn == [("-start", "mode: research")] * 2  # once per send


def test_a_command_that_lands_is_not_taken_back(cfg, monkeypatch):
    blocks = {"mode: research": mode_block(cfg, "research", "false")}
    fake_cold_turkey(monkeypatch, blocks)
    monkeypatch.setattr(ct, "withdraw_command", lambda a: pytest.fail("withdrew"))
    ct.switch("mode: research", on=True)
    assert blocks["mode: research"]["enabled"] == "true"


@pytest.mark.parametrize(
    "slot, deleted",
    [
        ('("/app", "-start", "mode: research")', True),
        ('("/app", "-stop", "mode: writing")', False),  # another command: left alone
        ("", False),  # the agent read it meanwhile
    ],
)
def test_withdrawing_deletes_the_slot_only_while_it_holds_this_command(
    monkeypatch, slot, deleted
):
    ran = []

    def fake_run(cmd, **k):
        ran.append(cmd)
        return type("R", (), {"stdout": slot if cmd[1] == "read" else ""})()

    monkeypatch.setattr(ct.subprocess, "run", fake_run)
    REAL_WITHDRAW(("-start", "mode: research"))
    assert [c[1] for c in ran] == (["read", "delete"] if deleted else ["read"])
    if deleted:
        assert ran[1] == ["defaults", "delete", ct.CT_DEFAULTS, "commandArgs"]


def test_a_default_start_cold_turkey_missed_is_retried(
    capped_env, tmp_path, monkeypatch
):
    _, blocks, clock, _, _ = capped_env
    note = CAPPED + "\ndefault_mode: {mode: research}"
    cfg = ct.load_config(note_with(tmp_path, note))
    blocks["mode: research"]["enabled"] = "false"
    asleep = asleep_display(monkeypatch)
    at = dt.datetime(2026, 11, 16, 9, 14)  # a Monday, the display off
    clock.now = at.timestamp()
    with pytest.raises(SystemExit, match="did not start"):
        ct.default_start(cfg, at)
    assert ct.read_state(ct.DEFAULT_FILE) is None  # the day is not used up
    asleep[0] = False
    at += dt.timedelta(minutes=1)
    clock.now = at.timestamp()
    assert ct.default_start(cfg, at) == "research"
    assert on(blocks) == ["mode: research"]


def test_the_tick_log_has_a_time_on_every_line(monkeypatch):
    import io

    class Frozen(dt.datetime):
        @classmethod
        def now(cls, tz=None):
            return dt.datetime(2026, 11, 23, 12, 48, 5)

    monkeypatch.setattr(ct.dt, "datetime", Frozen)
    out = io.StringIO()
    s = ct.Stamped(out)
    s.write("break over")
    s.write(": research running again\nScreenZen: 102 sites\n")
    print("third", file=s)
    assert out.getvalue().splitlines() == [
        "2026-11-23 12:48:05 break over: research running again",
        "2026-11-23 12:48:05 ScreenZen: 102 sites",
        "2026-11-23 12:48:05 third",
    ]
