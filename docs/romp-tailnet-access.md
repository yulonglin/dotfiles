<!-- Moved out of the skill list on 2026-08-30: this is break-glass infra documentation, not a skill. -->


# Romp over Tailscale

romp manages parallel Claude Code sessions. It is already installed on **hetzner** at `~/romp`; the kernel runs as a login service, so there is nothing to start by hand.

## The working URL from a phone

```
http://100.116.158.30:8080/?token=<serve-token>
```

Get the token with `romp url` on hetzner (it prints a loopback URL — take only the `token=` value; the `127.0.0.1` host is meaningless on another device). The token also lives at `~/.local/state/romp/serve-token`. After the first visit a year-long cookie authenticates the device, so the bare URL works afterwards.

This is a raw tailnet IP, so it needs **no DNS at all**. That is deliberate — see below.

## Why the hostname URL fails and the IP one works

Two independent mechanisms, and confusing them wastes a lot of time.

**DNS.** `hetzner.taile13c17.ts.net` is a MagicDNS name. It resolves only through Tailscale's own resolver (100.100.100.100); a tailnet-only device has no public A record, because its address is a private 100.x CGNAT one. If the phone has **"Use Tailscale DNS" off**, Safari asks the carrier's resolver instead, gets NXDOMAIN, and reports *"Safari can't open the page because the server can't be found"* — the request never leaves the phone. MagicDNS being enabled tailnet-wide does not help; the per-device toggle is what routes the query.

**Routing is separate from naming.** The WireGuard tunnel carries `100.64.0.0/10` whether or not Tailscale handles DNS. So the IP is reachable exactly when the hostname is not — which is why the IP form is the reliable fallback rather than a lesser one.

**`tailscale serve` routes by Host header.** Pointing a browser at `http://<tailnet-ip>/` returns **404**, not the dashboard, because serve matches the node's DNS name and an IP in the Host header matches no handler. So the IP alone is not enough; it needs a listener that bypasses serve entirely.

That listener is a `socat` TCP forwarder bound to the tailnet IP. TCP-level forwarding (not an HTTP proxy) preserves the WebSocket and SSE streams the dashboard needs for live updates:

```bash
setsid nohup socat TCP-LISTEN:8080,bind=100.116.158.30,fork,reuseaddr TCP:127.0.0.1:29855 \
  > /tmp/claude/socat-romp.log 2>&1 < /dev/null &
```

Exposure is tailnet-only, the same trust boundary as `tailscale serve` — a 100.x address is not reachable from the public internet. **It does not survive a reboot**; re-run the command, or promote it to a systemd user service.

## The proper fix

Turn on **"Use Tailscale DNS"** in the Tailscale app on the phone. Without it, every `.ts.net` name on the tailnet is unreachable, not only romp. Once it is on, `https://hetzner.taile13c17.ts.net/` works and the forwarder can be retired.

## Health check, in the order that isolates the fault

```bash
romp status                    # manager pid + kernel; kernel "main" listens on 29855
tailscale serve status         # confirm / proxies to 29855, NOT a stale port
tailscale dns status           # MagicDNS enabled tailnet-wide?
tailscale ping iphone-14       # is the device actually on the tailnet?
curl -s -m 8 -o /dev/null -w '%{http_code}' http://127.0.0.1:29855/
```

## Traps that have already cost a session

- **Never probe romp ports from inside the Claude Code sandbox.** Loopback is blocked, so a healthy port reads as connection-refused and looks like "romp is not installed". Use `dangerouslyDisableSandbox: true`, or trust `romp status` instead of `curl`.
- **A stale `serve` mapping fails silently.** On 2026-08-19 serve was proxying `/` to a dead port 56781 while the kernel had moved to 29855; everything looked healthy locally and only the remote URL broke. Fix: `tailscale serve --bg 29855`.
- **`tailscale serve` needs root** unless `sudo tailscale set --operator=$USER` has been run once (it has been, on hetzner).
- **Check the response body, not just the status code.** A 200 can be an error page; compare the tailnet response against loopback before declaring it healthy.
