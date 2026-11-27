"""Checks for custom_bins/reward: the swap rules and the seeded flip."""

import importlib.machinery
import importlib.util
import os
import pathlib
import random
import subprocess
import sys

PATH = pathlib.Path(__file__).resolve().parent.parent / "custom_bins/reward"
loader = importlib.machinery.SourceFileLoader("reward", str(PATH))
spec = importlib.util.spec_from_loader("reward", loader)
reward = importlib.util.module_from_spec(spec)
loader.exec_module(reward)


def test_heads_swaps_are_only_options_listed_above():
    for seed in range(500):
        r = reward.flip(random.Random(seed))
        if r["side"] == "heads":
            i = reward.HEADS.index(r["assigned"])
            assert r["swaps"] == reward.HEADS[:i]


def test_tails_swaps_are_every_other_dry_option():
    for seed in range(500):
        r = reward.flip(random.Random(seed))
        if r["side"] == "tails":
            assert set(r["swaps"]) | {r["assigned"]} == set(reward.TAILS)
            assert r["assigned"] not in r["swaps"]


def test_both_sides_and_every_option_occur():
    results = [reward.flip(random.Random(s)) for s in range(2000)]
    heads = sum(r["side"] == "heads" for r in results)
    assert 850 < heads < 1150
    assert {r["assigned"] for r in results} == set(reward.HEADS) | set(reward.TAILS)


def test_seeded_cli_is_deterministic():
    run = lambda: (
        subprocess.run(
            [sys.executable, str(PATH), "--seed", "3"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    )
    assert run() == run()
    assert "HEADS" in run() or "TAILS" in run()


def test_list_command_prints_both_sides():
    out = subprocess.run(
        [sys.executable, str(PATH), "list"], capture_output=True, text=True, check=True
    ).stdout
    assert "Heads" in out and "Tails" in out and "messages" in out and "nap" in out


def _run(*args, **env):
    full_env = {
        k: v for k, v in os.environ.items() if k not in ("NO_COLOR", "FORCE_COLOR")
    }
    full_env.update(env)
    return subprocess.run(
        [sys.executable, str(PATH), *args],
        capture_output=True,
        text=True,
        check=True,
        env=full_env,
    ).stdout


def test_piped_output_has_no_colour_codes():
    assert "\033[" not in _run("--seed", "1")


def test_force_colour_adds_codes_and_no_color_wins():
    assert "\033[" in _run("--seed", "1", FORCE_COLOR="1")
    assert "\033[" not in _run("--seed", "1", FORCE_COLOR="1", NO_COLOR="1")


def test_every_option_has_an_emoji():
    assert set(reward.EMOJI) == set(reward.HEADS) | set(reward.TAILS)
