"""Pure-logic checks for custom_bins/app-usage; the collectors need a real Mac."""

import datetime as dt
import importlib.machinery
import importlib.util
import pathlib
import sys

PATH = pathlib.Path(__file__).resolve().parent.parent / "custom_bins/app-usage"
loader = importlib.machinery.SourceFileLoader("app_usage", str(PATH))
spec = importlib.util.spec_from_loader("app_usage", loader)
app_usage = importlib.util.module_from_spec(spec)
sys.modules["app_usage"] = app_usage  # dataclasses look the module up by name
loader.exec_module(app_usage)

TODAY = dt.date(2026, 11, 5)


def status(last, running=False, extension_on=False):
    return app_usage.classify(last, running, extension_on, TODAY, 30)


def test_recent_use_is_ok():
    assert status(dt.date(2026, 10, 6)) == "ok"


def test_past_threshold_is_idle():
    assert status(dt.date(2026, 10, 5)) == "idle"


def test_no_use_is_never():
    assert status(None) == "never"


def test_running_beats_no_use():
    assert status(None, running=True) == "ok"


def test_enabled_extension_is_not_flagged_as_unused():
    assert status(dt.date(2026, 6, 28), extension_on=True) == "extension"
    assert status(None, extension_on=True) == "extension"


def test_cask_key_meets_pkg_cask_tokens():
    assert app_usage.cask_key("zoom.us") == app_usage.cask_key("zoom")
    assert app_usage.cask_key("Google Drive") == app_usage.cask_key("google-drive")
    assert app_usage.cask_key("Tailscale") == app_usage.cask_key("tailscale-app")


def test_extension_matches_host_app_only():
    assert app_usage.owns_extension("com.twofas.org.browser", "com.twofas.org.browser.extension")
    assert not app_usage.owns_extension("com.apple.iMovieApp", "com.bitwarden.desktop.safari")
    assert not app_usage.owns_extension("", "com.bitwarden.desktop.safari")


def test_overlapping_sources_are_not_summed():
    records = [(81.3, dt.date(2026, 10, 21)), (6.8, dt.date(2026, 11, 4))]
    assert app_usage.merge_usage(records, None) == (81.3, dt.date(2026, 11, 4))


def test_no_usage_records_keep_the_spotlight_date():
    assert app_usage.merge_usage([], dt.date(2026, 9, 1)) == (0.0, dt.date(2026, 9, 1))
