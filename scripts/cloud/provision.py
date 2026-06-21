#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx>=0.27"]
# ///
"""RunPod GPU pod provisioning client for NLA RL training.

REST API base URL: https://rest.runpod.io/v1
Confirmed from: https://docs.runpod.io/api-reference/overview (verified 2026-06-21)

Network volume flow (REQUIRED — volumeInGb in pod POST does NOT create a volume):
  1. POST /networkvolumes  →  capture id
  2. POST /pods with networkVolumeId: <id>

SSH key: injected via PUBLIC_KEY env var (RunPod base images write this to
  /root/.ssh/authorized_keys on container start).

RUNPOD_POD_ID: injected automatically by RunPod at runtime — no need to set it.
RUNPOD_API_KEY: injected explicitly so in-pod teardown traps can call the API.

setup.sh note: orchestrates calling scripts/cloud/setup.sh over SSH (user/SSH/dotfiles
  layer). Does NOT install the ML training stack — that is setup_stack.sh in nla-vs-cot.

Usage:
  uv run scripts/cloud/provision.py provision --image <image>
  uv run scripts/cloud/provision.py provision --image <image> --dry-run
  uv run scripts/cloud/provision.py teardown <pod_id>
  uv run scripts/cloud/provision.py list
  uv run scripts/cloud/provision.py status <pod_id>
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import httpx

# ── Config ────────────────────────────────────────────────────────────────────
BASE_URL = "https://rest.runpod.io/v1"

# GPU type IDs confirmed from https://docs.runpod.io/references/gpu-types (2026-06-21)
# ⚠ UNVERIFIED availability: check current stock in the RunPod dashboard or
#   via the GraphQL API (gpu.maxGpuCount) before provisioning.
#   Other A100-80GB option: "NVIDIA A100 80GB PCIe"
DEFAULT_GPU_TYPE = "NVIDIA A100-SXM4-80GB"
DEFAULT_GPU_COUNT = 8
# 2 TB: keep-last-K=3 pruning bounds the working set to ~180 GB, so this is deep
# headroom; chosen over 1 TB to also cover retaining all checkpoints of a long
# (max_steps=4200) run (~2 TB) without a mid-run overrun — volumes can't be resized
# on an active pod.  Network volume is deletable instantly if oversized.
DEFAULT_VOLUME_GB = 2048

# Data center for network volume creation.  Volume and pod must be co-located,
# and the DC must have the GPU type schedulable.  US-KS-2 chosen: storage-capable,
# has A100-SXM4-80GB AND an in-DC A100-80GB-PCIe fallback if SXM stock (currently
# "Low" everywhere) can't satisfy 8×.  US-WA-1 is nearer SF but has no in-DC
# fallback; US-MO-1 is an equivalent central-US alternative.
# Other storage+A100-SXM DCs: US-MO-1, US-WA-1, EUR-IS-1
DEFAULT_DATA_CENTER = "US-KS-2"

# Local state file tracking provisioned pods (pod_id → metadata + expiry)
STATE_FILE = Path.home() / ".runpod-pods.json"

SETUP_SH_URL = (
    "https://raw.githubusercontent.com/yulonglin/dotfiles/main"
    "/scripts/cloud/setup.sh"
)


# ── API helpers ───────────────────────────────────────────────────────────────


def _api_key() -> str:
    key = os.environ.get("RUNPOD_API_KEY")
    if not key:
        sys.exit(
            "RUNPOD_API_KEY not set.\n"
            "  Run under direnv: direnv exec . python scripts/cloud/provision.py ...\n"
            "  Or export:        export RUNPOD_API_KEY=<your-key>"
        )
    return key


def _client() -> httpx.Client:
    return httpx.Client(
        base_url=BASE_URL,
        headers={
            "Authorization": f"Bearer {_api_key()}",
            "Content-Type": "application/json",
        },
        timeout=30.0,
    )


# ── Local state ───────────────────────────────────────────────────────────────


def _load_state() -> dict[str, Any]:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def _save_state(state: dict[str, Any]) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n")


# ── Network volumes ───────────────────────────────────────────────────────────


def _find_network_volume(client: httpx.Client, name: str, size_gb: int) -> str | None:
    """Return id of an existing volume matching name+size, or None."""
    resp = client.get("/networkvolumes")
    resp.raise_for_status()
    for vol in resp.json():
        if vol.get("name") == name and vol.get("size") == size_gb:
            return vol["id"]
    return None


def _ensure_network_volume(
    client: httpx.Client | None,
    name: str,
    size_gb: int,
    data_center_id: str,
    dry_run: bool,
) -> str:
    """Create or reuse a network volume; return its id (idempotent by name+size).

    Pass client=None when dry_run=True (no network calls are made).
    """
    body: dict[str, Any] = {
        "name": name,
        "size": size_gb,
        "dataCenterId": data_center_id,
    }

    if dry_run:
        print("── [DRY RUN] POST /networkvolumes ────────────────────────────────")
        print(json.dumps(body, indent=2))
        print()
        return "dry-run-volume-id"

    assert client is not None
    existing = _find_network_volume(client, name, size_gb)
    if existing:
        print(f"  ↩  Reusing network volume {existing!r} ({name}, {size_gb}GB)")
        return existing

    resp = client.post("/networkvolumes", json=body)
    resp.raise_for_status()
    vol_id: str = resp.json()["id"]
    print(f"  ✓  Created network volume {vol_id!r} ({size_gb}GB in {data_center_id})")
    return vol_id


# ── SSH public key ────────────────────────────────────────────────────────────


def _local_ssh_pubkey() -> str:
    """Read the user's SSH public key from standard locations."""
    for candidate in (
        "~/.ssh/id_ed25519.pub",
        "~/.ssh/id_rsa.pub",
        "~/.ssh/id_ecdsa.pub",
    ):
        p = Path(candidate).expanduser()
        if p.exists():
            return p.read_text().strip()
    sys.exit(
        "No SSH public key found (checked id_ed25519.pub, id_rsa.pub, id_ecdsa.pub).\n"
        "Generate one with: ssh-keygen -t ed25519"
    )


# ── Pod request body ──────────────────────────────────────────────────────────


def _build_pod_body(
    gpu_type: str,
    gpu_count: int,
    image: str,
    name: str,
    network_volume_id: str,
    pubkey: str | None = None,
) -> dict[str, Any]:
    """Build the POST /pods request body with SSH key and secret injection."""
    if pubkey is None:
        pubkey = _local_ssh_pubkey()
    return {
        "name": name,
        "imageName": image,
        "cloudType": "SECURE",
        "gpuTypeIds": [gpu_type],
        "gpuCount": gpu_count,
        # Container-local scratch disk (separate from network volume)
        "containerDiskInGb": 50,
        "volumeMountPath": "/workspace",
        # Attach the pre-created network volume (volumeInGb alone does NOT create one)
        "networkVolumeId": network_volume_id,
        # RunPod assigns an external port for 22/tcp; retrieve from portMappings["22"]
        "ports": ["22/tcp"],
        "env": {
            # RunPod base images write PUBLIC_KEY → /root/.ssh/authorized_keys on boot
            "PUBLIC_KEY": pubkey,
            # Needed so in-pod teardown traps can call DELETE /pods/{id} via REST
            # RUNPOD_POD_ID is also injected automatically by RunPod at runtime
            "RUNPOD_API_KEY": _api_key(),
        },
    }


# ── Pod polling ───────────────────────────────────────────────────────────────


def _poll_pod(
    client: httpx.Client,
    pod_id: str,
    timeout_s: int = 600,
    poll_interval: int = 15,
) -> dict[str, Any]:
    """Poll GET /pods/{id} until desiredStatus==RUNNING and publicIp is set."""
    deadline = time.monotonic() + timeout_s
    print(f"  Polling pod {pod_id!r} (timeout {timeout_s}s)...")
    while time.monotonic() < deadline:
        resp = client.get(f"/pods/{pod_id}")
        resp.raise_for_status()
        pod = resp.json()
        status = pod.get("desiredStatus", "")
        ip = pod.get("publicIp")
        if status == "RUNNING" and ip:
            print(f"  ✓  Pod RUNNING  ip={ip}")
            return pod
        print(f"      status={status!r}  ip={ip!r}  — waiting {poll_interval}s...")
        time.sleep(poll_interval)
    sys.exit(f"Pod {pod_id!r} did not reach RUNNING+publicIp within {timeout_s}s")


# ── SSH reachability ──────────────────────────────────────────────────────────


def _wait_for_ssh(
    host: str,
    port: int,
    timeout_s: int = 300,
    poll_interval: int = 10,
) -> None:
    """Block until the SSH TCP port is open, or timeout."""
    deadline = time.monotonic() + timeout_s
    print(f"  Waiting for SSH on {host}:{port} (timeout {timeout_s}s)...")
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=5):
                print(f"  ✓  SSH reachable at {host}:{port}")
                return
        except OSError:
            time.sleep(poll_interval)
    sys.exit(f"SSH on {host}:{port} not reachable after {timeout_s}s")


# ── Commands ──────────────────────────────────────────────────────────────────


def cmd_provision(args: argparse.Namespace) -> None:
    name = args.name or f"nla-rl-{int(time.time())}"
    vol_name = f"{name}-vol"
    dry = args.dry_run

    print(f"\n== Provisioning pod {name!r} ==")
    print(f"   GPU:         {args.gpu_count}× {args.gpu_type}")
    print(f"   Image:       {args.image}")
    print(f"   Volume:      {args.volume_gb}GB  ({vol_name})")
    print(f"   Data center: {args.data_center}")

    if dry:
        # Dry-run: print both request bodies without making any network calls
        _ensure_network_volume(None, vol_name, args.volume_gb, args.data_center, dry_run=True)  # type: ignore[arg-type]
        pod_body = _build_pod_body(
            gpu_type=args.gpu_type,
            gpu_count=args.gpu_count,
            image=args.image,
            name=name,
            network_volume_id="dry-run-volume-id",
            pubkey="ssh-ed25519 AAAA...YOUR_PUBLIC_KEY (dry-run placeholder)",
        )
        print("── [DRY RUN] POST /pods ──────────────────────────────────────────")
        display = dict(pod_body)
        display["env"] = {
            k: ("***REDACTED***" if k == "RUNPOD_API_KEY" else v)
            for k, v in display.get("env", {}).items()
        }
        print(json.dumps(display, indent=2))
        return

    with _client() as client:
        # Step 1: Network volume (separate API call — required before pod creation)
        vol_id = _ensure_network_volume(
            client,
            name=vol_name,
            size_gb=args.volume_gb,
            data_center_id=args.data_center,
            dry_run=False,
        )

        # Step 2: Build and POST the pod
        pod_body = _build_pod_body(
            gpu_type=args.gpu_type,
            gpu_count=args.gpu_count,
            image=args.image,
            name=name,
            network_volume_id=vol_id,
        )
        resp = client.post("/pods", json=pod_body)
        resp.raise_for_status()
        pod_id: str = resp.json()["id"]
        print(f"  ✓  Pod created: {pod_id}")

    # Step 3: Poll until RUNNING + publicIp
    with _client() as client:
        pod = _poll_pod(client, pod_id)

    public_ip: str = pod["publicIp"]
    # portMappings maps container port → assigned external port, e.g. {"22": 10341}
    port_mappings: dict[str, Any] = pod.get("portMappings", {})
    ssh_port: int = int(port_mappings.get("22", 22))

    # Step 4: Wait for SSH TCP reachability
    _wait_for_ssh(public_ip, ssh_port)

    # Step 5: Persist state
    now = datetime.now(timezone.utc)
    entry: dict[str, Any] = {
        "pod_id": pod_id,
        "name": name,
        "public_ip": public_ip,
        "ssh_port": ssh_port,
        "volume_id": vol_id,
        "provisioned_at": now.isoformat(),
    }
    if args.max_lifetime:
        expiry = now + timedelta(hours=args.max_lifetime)
        entry["expires_at"] = expiry.isoformat()

    state = _load_state()
    state[pod_id] = entry
    _save_state(state)

    # Step 6: Run setup.sh over SSH (non-interactive)
    # - setup.sh detects RUNPOD_POD_ID env → sets PROVIDER=runpod, symlinks /workspace
    # - Interactive prompts (BWS token, Tailscale, age key) are skipped when /dev/tty
    #   is absent — run them manually after login via: ssh -p <port> yulong@<ip>
    print(f"\n  Running setup.sh on pod (non-interactive)...")
    result = subprocess.run(
        [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=10",
            "-p", str(ssh_port),
            f"root@{public_ip}",
            f"curl -fsSL {SETUP_SH_URL} | bash",
        ]
    )
    if result.returncode != 0:
        print(
            f"  ⚠  setup.sh exited {result.returncode} — check pod manually.\n"
            f"     ssh -p {ssh_port} root@{public_ip}"
        )

    # Summary
    print(f"\n{'='*60}")
    print(f"  Pod ID:    {pod_id}")
    print(f"  SSH:       ssh -p {ssh_port} yulong@{public_ip}")
    print(f"  SSH root:  ssh -p {ssh_port} root@{public_ip}")
    print(f"  Teardown:  uv run scripts/cloud/provision.py teardown {pod_id}")
    if args.max_lifetime:
        print(f"  ⚠  Max lifetime: {args.max_lifetime}h — expires {entry['expires_at']}")
        print(f"     Run teardown above by then (no auto-teardown scheduled)")
    print(f"  Next: ssh in and run secrets-init, secrets-init-bws, tailscale up")
    print(f"  ML stack: run setup_stack.sh from nla-vs-cot repo (not done here)")
    print(f"{'='*60}")


def cmd_teardown(args: argparse.Namespace) -> None:
    pod_id = args.pod_id

    if args.dry_run:
        print(f"[DRY RUN] Would DELETE /pods/{pod_id}")
        return

    print(f"Tearing down pod {pod_id!r}...")
    with _client() as client:
        resp = client.delete(f"/pods/{pod_id}")
        if resp.status_code == 404:
            print(f"  Pod {pod_id!r} not found — already deleted or invalid id")
        elif resp.status_code == 204:
            print(f"  ✓  Deleted (204 No Content)")
        else:
            resp.raise_for_status()

        # Idempotency: confirm deletion via follow-up GET
        time.sleep(3)
        check = client.get(f"/pods/{pod_id}")
        if check.status_code == 404:
            print(f"  ✓  Confirmed gone (404)")
        else:
            pod = check.json()
            status = pod.get("desiredStatus", "?")
            print(f"  ⚠  Pod still present — desiredStatus={status!r}; retry or check dashboard")

    # Remove from local state file
    state = _load_state()
    if pod_id in state:
        del state[pod_id]
        _save_state(state)
        print(f"  ✓  Removed from {STATE_FILE}")


def cmd_list(args: argparse.Namespace) -> None:
    with _client() as client:
        resp = client.get("/pods")
        resp.raise_for_status()
    pods = resp.json()
    if not pods:
        print("No pods found.")
        return
    print(f"{'ID':<26}  {'Name':<32}  {'Status':<12}  IP")
    print("-" * 80)
    for pod in pods:
        print(
            f"  {pod.get('id', '?'):<24}"
            f"  {pod.get('name', '?'):<32}"
            f"  {pod.get('desiredStatus', '?'):<12}"
            f"  {pod.get('publicIp') or 'no-ip'}"
        )


def cmd_status(args: argparse.Namespace) -> None:
    with _client() as client:
        resp = client.get(f"/pods/{args.pod_id}", params={"includeMachine": "true"})
        resp.raise_for_status()
    print(json.dumps(resp.json(), indent=2))


# ── CLI entrypoint ────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="provision",
        description="RunPod GPU pod provisioning client for NLA RL training.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print volume-create + pod-POST bodies without making any API calls",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    # provision
    p = sub.add_parser("provision", help="Create network volume + pod, wait for SSH, run setup.sh")
    p.add_argument(
        "--gpu-type",
        default=DEFAULT_GPU_TYPE,
        help=f"GPU type ID (default: {DEFAULT_GPU_TYPE!r}). "
        "⚠ Verify availability on RunPod dashboard before use. "
        "Alt: 'NVIDIA A100 80GB PCIe'",
    )
    p.add_argument("--gpu-count", type=int, default=DEFAULT_GPU_COUNT, help=f"Number of GPUs (default: {DEFAULT_GPU_COUNT})")
    p.add_argument("--volume-gb", type=int, default=DEFAULT_VOLUME_GB, help=f"Network volume size in GB (default: {DEFAULT_VOLUME_GB})")
    p.add_argument("--image", required=True, help="Container image (e.g. runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04)")
    p.add_argument("--name", default=None, help="Pod name (default: nla-rl-<unix-timestamp>)")
    p.add_argument("--data-center", default=DEFAULT_DATA_CENTER, help=f"Data center ID for network volume (default: {DEFAULT_DATA_CENTER!r}). Must match pod location.")
    p.add_argument("--max-lifetime", type=float, metavar="HOURS", help="Arm lifetime guard: prints expiry time and teardown command prominently")
    p.set_defaults(func=cmd_provision)

    # teardown
    p = sub.add_parser("teardown", help="DELETE a pod by id (idempotent, confirms via follow-up GET)")
    p.add_argument("pod_id", help="Pod ID to delete")
    p.set_defaults(func=cmd_teardown)

    # list
    p = sub.add_parser("list", help="List all pods (GET /pods)")
    p.set_defaults(func=cmd_list)

    # status
    p = sub.add_parser("status", help="Show full detail for a single pod")
    p.add_argument("pod_id", help="Pod ID")
    p.set_defaults(func=cmd_status)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
