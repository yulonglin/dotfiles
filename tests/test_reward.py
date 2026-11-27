"""Checks for custom_bins/reward: the swap rules and the seeded flip."""

import importlib.machinery
import importlib.util
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
    assert run().startswith(("HEADS:", "TAILS:"))


def test_list_command_prints_both_sides():
    out = subprocess.run(
        [sys.executable, str(PATH), "list"], capture_output=True, text=True, check=True
    ).stdout
    assert "Heads" in out and "Tails" in out and "messages" in out and "nap" in out
