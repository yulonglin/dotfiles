"""Tests for custom_bins/obs-focusmate-sync."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "custom_bins" / "obs-focusmate-sync"


def _run(args: list[str], obs_running: bool | None = False) -> subprocess.CompletedProcess[str]:
    # Pin the running-OBS check so tests never depend on the real machine.
    state = "unknown" if obs_running is None else ("1" if obs_running else "0")
    env = {**os.environ, "OBS_SYNC_ASSUME_RUNNING": state}
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )


def _sample_ini() -> str:
    return (
        "[General]\n"
        "Name=Untitled\n"
        "\n"
        "[SimpleOutput]\n"
        "FilePath=/Users/alice/Movies\n"
        "\n"
        "[Auth]\n"
        "Token=secret-oauth-token\n"
        "RefreshToken=secret-refresh-token\n"
        "\n"
        "[Video]\n"
        "BaseCX=1280\n"
        "BaseCY=720\n"
        "OutputCX=640\n"
        "OutputCY=360\n"
        "FPSType=1\n"
        "FPSCommon=10\n"
        "\n"
        "[Panels]\n"
        "CookieId=DEADBEEF12345678\n"
    )


def _sample_scene(extra_sources: list[dict] | None = None) -> dict:
    sources: list[dict] = [
        {
            "name": "macOS Screen Capture",
            "id": "screen_capture",
            "settings": {
                "display_uuid": "EEBD150B-6520-42C1-92D8-71CBAE4A60B5",
                "show_cursor": False,
                "hide_obs": False,
            },
            "filters": [
                {
                    "name": "Scaling/Aspect Ratio",
                    "id": "scale_filter",
                    "settings": {"sampling": "bilinear", "resolution": "160x90"},
                }
            ],
        },
        {
            "name": "Video Capture Device",
            "id": "macos-avcapture",
            "settings": {
                "device_name": "Studio Display Camera",
                "device": "0x2014000015bc0000",
                "preset": "AVCaptureSessionPreset960x540",
            },
        },
        {
            "name": "Scene",
            "id": "scene",
            "settings": {"items": []},
        },
    ]
    if extra_sources:
        sources.extend(extra_sources)
    return {
        "name": "Untitled",
        "AuxAudioDevice1": {"settings": {"device_id": "custom-mic-id"}},
        "sources": sources,
        "saved_projectors": [{"monitor": 0, "geometry": "opaque"}],
    }


def _seed_obs(obs_basic: Path, ini_text: str, scene_text: str, name: str = "Focusmate") -> None:
    prof_dir = obs_basic / "profiles" / name
    scenes_dir = obs_basic / "scenes"
    prof_dir.mkdir(parents=True, exist_ok=True)
    scenes_dir.mkdir(parents=True, exist_ok=True)
    (prof_dir / "basic.ini").write_text(ini_text, encoding="utf-8")
    (scenes_dir / f"{name}.json").write_text(scene_text, encoding="utf-8")


def test_capture_allowlists_profile_and_strips_hardware(tmp_path: Path) -> None:
    obs_basic = tmp_path / "obs"
    repo_basic = tmp_path / "repo"
    _seed_obs(obs_basic, _sample_ini(), json.dumps(_sample_scene()), name="Untitled")

    res = _run(
        [
            "--obs-basic",
            str(obs_basic),
            "--repo-basic",
            str(repo_basic),
            "capture",
            "--profile",
            "Untitled",
            "--scene",
            "Untitled",
        ]
    )
    assert res.returncode == 0, res.stderr

    out_ini = (repo_basic / "profiles" / "Focusmate" / "basic.ini").read_text(encoding="utf-8")
    assert "Name=Focusmate" in out_ini
    assert "OutputCX=640" in out_ini
    for forbidden in ("secret-oauth-token", "secret-refresh-token", "DEADBEEF", "/Users/alice"):
        assert forbidden not in out_ini

    out_scene = json.loads((repo_basic / "scenes" / "Focusmate.json").read_text(encoding="utf-8"))
    assert out_scene["name"] == "Focusmate"
    assert out_scene["saved_projectors"] == []
    assert out_scene["AuxAudioDevice1"]["settings"] == {"device_id": "default"}

    by_id = {s["id"]: s for s in out_scene["sources"]}
    assert "display_uuid" not in by_id["screen_capture"]["settings"]
    assert "device" not in by_id["macos-avcapture"]["settings"]
    assert "device_name" not in by_id["macos-avcapture"]["settings"]
    assert by_id["macos-avcapture"]["settings"]["preset"] == "AVCaptureSessionPreset960x540"


def test_capture_rejects_unexpected_source_atomically(tmp_path: Path) -> None:
    obs_basic = tmp_path / "obs"
    repo_basic = tmp_path / "repo"
    bad_scene = _sample_scene(
        extra_sources=[
            {
                "name": "Private Dashboard",
                "id": "browser_source",
                "settings": {"url": "https://private.internal/?token=abc"},
            }
        ]
    )
    _seed_obs(obs_basic, _sample_ini(), json.dumps(bad_scene))

    res = _run(["--obs-basic", str(obs_basic), "--repo-basic", str(repo_basic), "capture"])
    assert res.returncode == 1
    assert "browser_source" in res.stderr
    assert not (repo_basic / "profiles" / "Focusmate" / "basic.ini").exists()
    assert not (repo_basic / "scenes" / "Focusmate.json").exists()


def test_capture_fails_on_malformed_json_without_partial_write(tmp_path: Path) -> None:
    obs_basic = tmp_path / "obs"
    repo_basic = tmp_path / "repo"
    _seed_obs(obs_basic, _sample_ini(), "{not json")

    res = _run(["--obs-basic", str(obs_basic), "--repo-basic", str(repo_basic), "capture"])
    assert res.returncode == 1
    assert not (repo_basic / "profiles" / "Focusmate" / "basic.ini").exists()
    assert not (repo_basic / "scenes" / "Focusmate.json").exists()


def test_apply_preserves_local_profile_state_and_hardware_bindings(tmp_path: Path) -> None:
    obs_basic = tmp_path / "obs"
    repo_basic = tmp_path / "repo"

    # Seed repo with sanitized Focusmate config (FPSCommon=15).
    seed_obs = tmp_path / "seed"
    _seed_obs(
        seed_obs,
        _sample_ini().replace("FPSCommon=10", "FPSCommon=15"),
        json.dumps(_sample_scene()),
    )
    cap = _run(["--obs-basic", str(seed_obs), "--repo-basic", str(repo_basic), "capture"])
    assert cap.returncode == 0, cap.stderr

    # Seed destination machine with its own CookieId, Auth, and hardware UUIDs.
    local_scene = _sample_scene()
    local_scene["sources"][0]["settings"]["display_uuid"] = "LOCAL-DISPLAY-UUID"
    local_scene["sources"][1]["settings"]["device"] = "LOCAL-CAM-ID"
    local_scene["sources"][1]["settings"]["device_name"] = "FaceTime HD Camera"
    _seed_obs(obs_basic, _sample_ini(), json.dumps(local_scene))

    res = _run(["--obs-basic", str(obs_basic), "--repo-basic", str(repo_basic), "apply"])
    assert res.returncode == 0, res.stderr

    merged_ini = (obs_basic / "profiles" / "Focusmate" / "basic.ini").read_text(encoding="utf-8")
    assert "FPSCommon=15" in merged_ini
    assert "CookieId=DEADBEEF12345678" in merged_ini
    assert "Token=secret-oauth-token" in merged_ini

    merged_scene = json.loads((obs_basic / "scenes" / "Focusmate.json").read_text(encoding="utf-8"))
    by_id = {s["id"]: s for s in merged_scene["sources"]}
    assert by_id["screen_capture"]["settings"]["display_uuid"] == "LOCAL-DISPLAY-UUID"
    assert by_id["macos-avcapture"]["settings"]["device"] == "LOCAL-CAM-ID"
    assert by_id["macos-avcapture"]["settings"]["device_name"] == "FaceTime HD Camera"
    assert by_id["macos-avcapture"]["settings"]["preset"] == "AVCaptureSessionPreset960x540"


_USER_INI = (
    "[General]\n"
    "Pre19Defaults=true\n"
    "FirstRun=true\n"
    "ConfirmOnExit=false\n"
    "\n"
    "[BasicWindow]\n"
    "SysTrayEnabled=true\n"
    "geometry=AdnQywADAAAAAAPEAAAA\n"
    "ExtraBrowserDocks=[{\"url\":\"https://private.internal/?token=abc\"}]\n"
    "\n"
    "[Basic]\n"
    "Profile=Untitled\n"
    "ProfileDir=Untitled\n"
    "SceneCollection=Untitled\n"
    "SceneCollectionFile=Untitled.json\n"
)

_GLOBAL_INI = (
    "[General]\n"
    "MaxLogs=10\n"
    "InstallGUID=0123456789abcdef\n"
    "LastVersion=553648131\n"
    "\n"
    "[Video]\n"
    "Renderer=OpenGL\n"
    "\n"
    "[Locations]\n"
    "Configuration=/Users/alice/Library/Application Support\n"
)


def _seed_app_inis(obs_root: Path) -> None:
    (obs_root / "user.ini").write_text(_USER_INI, encoding="utf-8")
    (obs_root / "global.ini").write_text(_GLOBAL_INI, encoding="utf-8")


def test_capture_app_settings_allowlist_only(tmp_path: Path) -> None:
    obs_basic = tmp_path / "obs" / "basic"
    repo_basic = tmp_path / "repo" / "basic"
    _seed_obs(obs_basic, _sample_ini(), json.dumps(_sample_scene()))
    _seed_app_inis(obs_basic.parent)

    res = _run(["--obs-basic", str(obs_basic), "--repo-basic", str(repo_basic), "capture"])
    assert res.returncode == 0, res.stderr

    user = (repo_basic.parent / "user.ini").read_text(encoding="utf-8")
    assert "ConfirmOnExit=false" in user
    assert "SysTrayEnabled=true" in user
    for forbidden in ("FirstRun", "Pre19Defaults", "geometry", "private.internal", "[Basic]"):
        assert forbidden not in user

    glob = (repo_basic.parent / "global.ini").read_text(encoding="utf-8")
    assert "MaxLogs=10" in glob and "Renderer=OpenGL" in glob
    for forbidden in ("InstallGUID", "LastVersion", "/Users/alice", "[Locations]"):
        assert forbidden not in glob


def test_apply_merges_app_settings_and_sets_default_profile(tmp_path: Path) -> None:
    seed_basic = tmp_path / "seed" / "basic"
    repo_basic = tmp_path / "repo" / "basic"
    obs_basic = tmp_path / "obs" / "basic"
    _seed_obs(seed_basic, _sample_ini(), json.dumps(_sample_scene()))
    _seed_app_inis(seed_basic.parent)
    assert _run(["--obs-basic", str(seed_basic), "--repo-basic", str(repo_basic), "capture"]).returncode == 0

    _seed_obs(obs_basic, _sample_ini(), json.dumps(_sample_scene()))
    (obs_basic.parent / "user.ini").write_text(
        _USER_INI.replace("ConfirmOnExit=false", "ConfirmOnExit=true"), encoding="utf-8"
    )
    (obs_basic.parent / "global.ini").write_text(
        _GLOBAL_INI.replace("InstallGUID=0123456789abcdef", "InstallGUID=local-guid"), encoding="utf-8"
    )

    res = _run(["--obs-basic", str(obs_basic), "--repo-basic", str(repo_basic), "apply"])
    assert res.returncode == 0, res.stderr

    user = (obs_basic.parent / "user.ini").read_text(encoding="utf-8")
    assert "ConfirmOnExit=false" in user  # repo value wins for allowlisted keys
    assert "geometry=AdnQywADAAAAAAPEAAAA" in user  # local-only keys survive
    assert "Profile=Focusmate" in user
    assert "SceneCollectionFile=Focusmate.json" in user
    glob = (obs_basic.parent / "global.ini").read_text(encoding="utf-8")
    assert "InstallGUID=local-guid" in glob


def test_apply_refuses_while_obs_running(tmp_path: Path) -> None:
    seed_basic = tmp_path / "seed" / "basic"
    repo_basic = tmp_path / "repo" / "basic"
    obs_basic = tmp_path / "obs" / "basic"
    _seed_obs(seed_basic, _sample_ini().replace("FPSCommon=10", "FPSCommon=15"), json.dumps(_sample_scene()))
    assert _run(["--obs-basic", str(seed_basic), "--repo-basic", str(repo_basic), "capture"]).returncode == 0
    _seed_obs(obs_basic, _sample_ini(), json.dumps(_sample_scene()))
    args = ["--obs-basic", str(obs_basic), "--repo-basic", str(repo_basic), "apply"]

    res = _run(args, obs_running=True)
    assert res.returncode == 75
    assert "FPSCommon=10" in (obs_basic / "profiles" / "Focusmate" / "basic.ini").read_text(encoding="utf-8")

    forced = _run([*args, "--force"], obs_running=True)
    assert forced.returncode == 0, forced.stderr
    assert "FPSCommon=15" in (obs_basic / "profiles" / "Focusmate" / "basic.ini").read_text(encoding="utf-8")


def test_capture_profile_audio_and_hotkeys_without_device_ids(tmp_path: Path) -> None:
    obs_basic = tmp_path / "obs"
    repo_basic = tmp_path / "repo"
    ini = _sample_ini() + (
        "\n[Audio]\nSampleRate=48000\nMonitoringDeviceId=AppleUSBAudioEngine:XYZ\n"
        "MonitoringDeviceName=Studio Display Speakers\n"
        '\n[Hotkeys]\nOBSBasic.StartVirtualCam={"bindings":[{"key":"OBS_KEY_V"}]}\n'
    )
    _seed_obs(obs_basic, ini, json.dumps(_sample_scene()))

    res = _run(["--obs-basic", str(obs_basic), "--repo-basic", str(repo_basic), "capture"])
    assert res.returncode == 0, res.stderr
    out_ini = (repo_basic / "profiles" / "Focusmate" / "basic.ini").read_text(encoding="utf-8")
    assert "SampleRate=48000" in out_ini
    assert "OBSBasic.StartVirtualCam=" in out_ini
    assert "MonitoringDevice" not in out_ini
    assert "Studio Display Speakers" not in out_ini


def test_apply_refuses_when_running_state_unknown(tmp_path: Path) -> None:
    seed_basic = tmp_path / "seed" / "basic"
    repo_basic = tmp_path / "repo" / "basic"
    obs_basic = tmp_path / "obs" / "basic"
    _seed_obs(seed_basic, _sample_ini(), json.dumps(_sample_scene()))
    assert _run(["--obs-basic", str(seed_basic), "--repo-basic", str(repo_basic), "capture"]).returncode == 0
    _seed_obs(obs_basic, _sample_ini(), json.dumps(_sample_scene()))
    res = _run(["--obs-basic", str(obs_basic), "--repo-basic", str(repo_basic), "apply"], obs_running=None)
    assert res.returncode == 75
    assert "may be running" in res.stderr


def test_capture_keeps_empty_video_section_so_apply_accepts_it(tmp_path: Path) -> None:
    obs_basic = tmp_path / "obs"
    repo_basic = tmp_path / "repo"
    _seed_obs(obs_basic, "[General]\nName=X\n\n[Video]\nUnlistedKey=1\n", json.dumps(_sample_scene()))
    assert _run(["--obs-basic", str(obs_basic), "--repo-basic", str(repo_basic), "capture"]).returncode == 0
    assert "[Video]" in (repo_basic / "profiles" / "Focusmate" / "basic.ini").read_text(encoding="utf-8")
    res = _run(["--obs-basic", str(obs_basic), "--repo-basic", str(repo_basic), "apply"])
    assert res.returncode == 0, res.stderr
