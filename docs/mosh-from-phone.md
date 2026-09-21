# Mosh into this Mac from the phone

This machine (`m5pro`, tailnet `100.80.44.37`) is reachable from `iphone-14` over Tailscale. Everything below was measured on 2026-09-21; the parts needing root are listed separately because they are the only steps a Claude Code session cannot do for you.

Read the diagnosis section first if the question is "why is ssh from my phone so patchy" — the answer is mostly not about this Mac, which until today was not accepting ssh at all.

## Mosh replaces ssh here because the phone's problem is TCP, not bandwidth

An ssh session is one TCP connection pinned to a 4-tuple. Three things routinely invalidate that tuple on a phone, and each one hangs the session rather than closing it cleanly, which is what "patchy" feels like from the client end:

- **iOS suspends the app.** Backgrounding Termius stops it servicing the socket; the peer eventually resets it. The session is dead before you look at the screen again.
- **The phone roams.** Wi-Fi to cellular, or one cell tower to the next, changes the phone's source address. The old tuple is gone and ssh freezes.
- **A NAT idles the mapping out.** Carrier NATs drop idle mappings aggressively, so a session left alone for a few minutes is silently unmapped.

Mosh is built for exactly these: it runs over UDP with its own session key, so roaming changes nothing, and it keeps the authoritative screen state on the server, so a suspended client resynchronises instead of reconnecting. It also echoes your keystrokes locally, which is what removes the typing lag on a slow path.

Mosh does not fix a *sleeping* server — see the `pmset` step below.

## The patchy sessions were to hetzner, and hetzner has two fixable faults

This Mac's sshd was **not listening** until the steps below were run, so no ssh session from the phone has ever terminated here. The patchiness is on the path to `hetzner`, and measuring from hetzner itself found two things.

**No server-side keepalive.** `/etc/ssh/sshd_config` and its drop-ins set neither `ClientAliveInterval` nor `TCPKeepAlive`, so both sit at the OpenSSH defaults — and the default `ClientAliveInterval 0` means the server never probes the client at all. When the phone suspends or roams, nothing detects it: the server holds the session open indefinitely and the client hangs rather than failing fast. Setting an interval does not stop the disconnect, but it converts a silent hang into a prompt, honest death, and it keeps the NAT mapping warm so idle sessions stop being reaped in the first place.

**A cross-continent relay.** Tailscale places the phone's home relay in San Francisco and hetzner's in Nuremberg, and hetzner has no direct path to the phone — `tailscale ping iphone-14` from hetzner timed out on every probe while the phone was simultaneously listed as `active`. So a phone session addressed to hetzner's tailnet IP (`100.116.158.30`, which is what `Host hn*` in `~/.ssh/config` resolves to) is relayed between two DERP regions on opposite sides of the Atlantic.

That matters because **DERP is a TCP relay**. An ssh session across it is TCP inside TCP: one lost packet stalls everything queued behind it in *both* the inner and outer stream, which is the head-of-line blocking that turns ordinary cellular loss into a visibly stuttering shell.

Mosh does not escape the relay's outer TCP, and it is worth being precise that its packets head-of-line block too. What it avoids is stacking a *second* retransmitting, ordered stream on top of the first, and it holds screen state server-side while echoing locally — so a relay stall shows up as lag that catches up, not as a session that silently dies. **`mosh-server` 1.4.0 is already installed on hetzner** at `/usr/bin/mosh-server`, so switching that connection to mosh needs no install, only the `Use Mosh` toggle in the host entry.

## This Mac's own path to the phone is relayed too, probably because of NordVPN

`tailscale ping` from this Mac, 2026-09-21:

| Peer | Path | Latency |
|---|---|---|
| `iphone-14` | DERP relay (sfo) — `direct connection not established` | 9–17 ms |
| `hetzner` | direct, `5.75.164.68:41641` | 165 ms |

Hetzner goes direct because it has a public address and needs no hole-punching. The phone does not, and **the likely reason is local, though this is a hypothesis rather than a measured cause**: NordVPN holds this Mac's default route (`utun7`, `10.5.0.2`, MTU 1420), so Tailscale's UDP discovery leaves through the NordVPN exit, and `netcheck` reports an empty `PortMapping:` line — no UPnP, NAT-PMP or PCP. With the Mac's endpoint masked behind a shared VPN exit and the phone behind carrier CGNAT, neither side can hole-punch.

Carrier CGNAT alone is capable of forcing a relay, so NordVPN may not be the operative cause. Falsifying it takes half a minute: turn NordVPN off and re-run `tailscale ping iphone-14`. If `direct connection established` appears, NordVPN was the cause and a split-tunnel exclusion for Tailscale fixes it permanently; if it stays on DERP, the phone's NAT is responsible and NordVPN is irrelevant here.

Either way, 9–17 ms over the SFO relay is perfectly usable, so **you do not need to change anything about NordVPN to make mosh work**. This only decides whether the Mac path is relayed or direct.

## Steps that need root

These four are the entire manual part on this Mac. Run them together; each is one command and each reverses cleanly.

```
sudo systemsetup -setremotelogin on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
  --add /opt/homebrew/bin/mosh-server
sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
  --unblockapp /opt/homebrew/bin/mosh-server
sudo pmset -c sleep 0
```

What each one is for:

- **`setremotelogin on`** starts sshd, which was not listening — this is why nothing could reach the Mac. If it refuses with a Full Disk Access error (recent macOS restricts `systemsetup` to terminals holding FDA), use System Settings → General → Sharing → **Remote Login** instead; the effect is identical. Your account is already in the `com.apple.access_ssh` ACL group, so no allow-list edit is needed afterwards.
- **The two `socketfilterfw` lines** add `mosh-server` to the application firewall, which is on. Mosh binds a UDP port in 60000–61000 per session. An unsigned Homebrew binary launched over ssh may either raise a GUI prompt on the Mac's own screen — useless when you are holding the phone — or have its traffic dropped outright; the allow rule pre-empts both. The symptom it prevents is mosh hanging at `Connecting...` *after* a successful ssh handshake. Stealth mode is off, so nothing else needs changing.
- **`pmset -c sleep 0`** stops the Mac sleeping while on AC. It sleeps after 1 minute idle and was only awake because something held a `caffeinate`. Mosh survives a dropped network but not a server that has gone to sleep. Battery behaviour is untouched, so unplugged it still sleeps normally. Reverse with `sudo pmset -c sleep 1`.

The hetzner keepalive fix is separate and also needs root, on that host:

```
ssh hn
sudo tee /etc/ssh/sshd_config.d/60-keepalive.conf <<'CONF'
ClientAliveInterval 30
ClientAliveCountMax 6
CONF
sudo systemctl reload ssh
```

That probes an idle client every 30 s and gives up after 6 missed replies, so a genuinely dead phone session is closed in about 3 minutes instead of never.

## Termius needs no new keys

Termius supports mosh on iOS — its own documentation covers the mobile setup and states that [mosh 1.3.0 and newer are supported](https://docs.termius.com/organize-and-connect-to-hosts/connecting-to-a-server), and both this Mac and hetzner run 1.4.0. Which pricing tier exposes it is not stated in those docs, so check the app rather than trusting a number from anywhere else. Your `~/.ssh/authorized_keys` already carries several Termius-labelled keys, so the phone should authenticate without adding anything.

In the host entry on the phone, enable the **Use Mosh** setting, then:

- **Address** `100.80.44.37` — the tailnet IP, not the MagicDNS name. [docs/romp-tailnet-access.md](romp-tailnet-access.md) records that this phone has had "Use Tailscale DNS" switched off, which makes every `.ts.net` name fail to resolve while the 100.x address keeps working. Fixing the toggle is the better end state; the IP is what works regardless.
- **Username** `yulong`
- Leave the mosh-server path and any custom port range empty — `config/zshenv.sh` puts the Homebrew prefix on the PATH of non-interactive shells, so a bare `mosh-server` resolves, and the default 60000–61000 range is what the firewall rule above allows. Termius documents a `mosh-server new -s -l LANG=en_US.UTF-8 -p <from>:<to>` form if you ever need to pin the range; pinning it means narrowing the firewall rule to match.

## Why the PATH fix lives in `~/.zshenv`

Mosh does not run a login shell. It runs `mosh-server` through a non-interactive ssh shell, and zsh reads **only** `~/.zshenv` for those — not `.zprofile`, not `.zshrc`, and `/usr/libexec/path_helper` never runs. Homebrew's prefix is therefore missing and mosh reports `mosh-server: command not found` on a host where plain ssh works, which is the single most common way a Mac mosh setup fails.

`config/zshenv.sh` fixes it server-side, once, for every client and device. `deploy.sh` appends a `source` line for it to `~/.zshenv` behind a `grep` guard — not through `$OP`, which is `>` unless `--append` and would drop the rustup line that also lives in that file.

## Verifying it, in the order that isolates the fault

Run these on the Mac after the sudo block. Each clears a distinct failure, so a break tells you which step did not take.

```bash
lsof -nP -iTCP:22 -sTCP:LISTEN          # sshd actually listening?
ssh localhost 'command -v mosh-server'  # PATH fix visible to a non-interactive shell?
ssh localhost 'mosh-server new -s -c 256 -l LANG=en_US.UTF-8'   # prints MOSH CONNECT <port> <key>
```

The third prints a port and a one-time key and leaves a detached server behind; kill it by the pid it reports. A `MOSH CONNECT` line means everything except the firewall is right — the firewall cannot fail here, because loopback is not filtered.

Then, from the phone, connect once and confirm it survives a deliberate network change: start a session, switch Wi-Fi off, and check the shell resumes on cellular rather than hanging. That round-trip is the only test covering the firewall rule and the relay path together, and it cannot be run from this machine.

## Traps already paid for

- **Do not probe these ports from inside the Claude Code sandbox.** Loopback and most outbound sockets are blocked there, so a healthy sshd reads as connection-refused. Use `dangerouslyDisableSandbox: true`, as [docs/romp-tailnet-access.md](romp-tailnet-access.md) already records for romp.
- **`mosh` is aliased** to `LANG=en_US.UTF-8 mosh --no-init` in `config/aliases/net.sh`, which preserves scrollback. That is the outbound client on this Mac and is unrelated to serving.
- **OSC 52 clipboard is broken under mosh** (upstream PRs #1054/#1104 unmerged as of 2026), so tmux copy-to-system-clipboard will not work from a phone session. `config/tmux.conf` documents the two workarounds.
- **Truecolor is suppressed under mosh** by `config/zshrc.sh`, deliberately — mosh 1.4.0 garbles 24-bit SGR sequences, so `COLORTERM` is left unset and apps fall back to 256 colours.
