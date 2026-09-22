# Mosh into this Mac from the phone

This machine (`m5pro`, tailnet `100.80.44.37`) already accepts ssh from `iphone-14` over Tailscale. Everything below was measured on 2026-09-21.

## The patchy sessions are this Mac sleeping, after one minute

`pmset -g` reports `sleep 1`. The Mac suspends after a single idle minute, and every ssh session dies with it. That is the whole cause — not the network, not the phone, not Tailscale.

The one-minute value was set for **screen lock**, and pmset's `sleep` key took it too. Locking is configured separately, so raising the sleep timer costs nothing there: `displaysleep` stays at 1 and macOS locks on its own schedule.

```
sudo pmset -c sleep 30
```

## Raising the timer is the fix because macOS already does session-aware wake

The instinct is to disable sleep outright, or to park a `caffeinate` process on the machine. Neither is right, and the reason is that macOS already solves this: `ttyskeepawake` is `1` here, and `man pmset` defines it as preventing idle system sleep while any tty — "e.g. remote login session" — is active.

It has never helped, and the same sentence says why: **a tty counts as inactive once its idle time exceeds the system sleep timer**. At one minute, pausing to read output for sixty seconds marks your own live session idle and lets the machine sleep. The guard works exactly as documented; the timer is simply too short for it ever to engage.

So the whole fix is to make the timer longer than a reading pause. At `sleep 30` the Mac stays awake for as long as a session is genuinely connected, and sleeps half an hour after the last one disconnects. No process to supervise, no assertion to leak, and it still sleeps when the machine is actually idle.

**An always-on `caffeinate` was tried here and removed.** A launchd agent holding `caffeinate -s` was deployed on 2026-09-21 and reverted the same day: it worked, but it holds the assertion unconditionally, so the Mac never sleeps on AC whether or not anyone is connected — one instance ran for nearly 17 hours with a single ssh session against it. An unbounded power assertion installed by default on every machine is the wrong shape for a problem the OS already scopes to live sessions. If a machine ever genuinely needs it, `caffeinate -s` on demand is the honest way to ask, and it ends when you end it.

On battery the timer is left short deliberately, so an unplugged laptop still suspends promptly. That does mean a remote session on battery dies quickly; `sudo pmset -b sleep 10` is the middle ground if that matters more than the charge.

## Mosh survives the sleep, which is why it is worth setting up anyway

Fixing `pmset` removes the cause. Mosh is still worth having, because it changes what happens when the Mac *does* go down — on battery, on a lid close, or on any future sleep.

macOS freezes processes on sleep rather than killing them. An ssh session cannot survive that: its TCP connection is reset or times out while the machine is unreachable, and the client comes back to a dead prompt. A mosh session has no connection state to lose — the client keeps sending UDP datagrams into the void, the server resumes on wake with its screen state intact, and the session picks up where it stopped. The same holds for the phone roaming between Wi-Fi and cellular, which changes the phone's address and kills ssh's 4-tuple while mosh simply carries on.

So `pmset` stops the sessions dying, and mosh means the ones that still die come back by themselves.

## What ssh is missing, and it is not why sessions dropped

This Mac's sshd sets neither `ClientAliveInterval` nor `TCPKeepAlive`, so both sit at OpenSSH defaults, and `ClientAliveInterval 0` means the server never probes the client. This does not cause disconnects. It decides how an already-dead session presents: with no probe the server holds it open indefinitely and the client hangs, rather than being told promptly that it is gone.

Worth setting as a comfort fix rather than a cure:

```
sudo tee /etc/ssh/sshd_config.d/60-keepalive.conf >/dev/null <<'CONF'
ClientAliveInterval 30
ClientAliveCountMax 6
CONF
```

No restart is needed and no live session is disturbed: `/System/Library/LaunchDaemons/ssh.plist` declares `Sockets` with `inetdCompatibility` and `Wait = false`, so launchd spawns a fresh sshd per connection and each one reads the config anew. `/etc/ssh/sshd_config` carries `Include /etc/ssh/sshd_config.d/*`, so the drop-in is picked up as written.

## The phone path is DERP-relayed, which costs latency and nothing else

`tailscale ping` from this Mac, 2026-09-21:

| Peer | Path | Latency |
|---|---|---|
| `iphone-14` | DERP relay (sfo) — `direct connection not established` | 9–17 ms |
| `hetzner` | direct, `5.75.164.68:41641` | 165 ms |

Hetzner goes direct because it has a public address and needs no hole-punching. The phone does not, and **the likely reason is local, though this is a hypothesis rather than a measured cause**: NordVPN holds this Mac's default route (`utun7`, `10.5.0.2`, MTU 1420), so Tailscale's UDP discovery leaves through the NordVPN exit and `netcheck` reports an empty `PortMapping:` line — no UPnP, NAT-PMP or PCP. With the Mac's endpoint masked behind a shared VPN exit and the phone behind carrier CGNAT, neither side can hole-punch.

Carrier CGNAT alone can force a relay, so NordVPN may not be the operative cause. Falsifying it takes half a minute: turn NordVPN off and re-run `tailscale ping iphone-14`. If `direct connection established` appears, NordVPN was the cause and a split-tunnel exclusion for Tailscale fixes it permanently.

At 9–17 ms this is a latency detail, not a fault, and it was **not** why sessions were dropping. A relayed path does make ssh feel worse under loss, because DERP is a TCP relay and ssh across it is TCP inside TCP, where one lost packet stalls everything queued behind it. Mosh does not escape that outer TCP either — its packets head-of-line block too — but it does not stack a second ordered, retransmitting stream on top, and it echoes locally, so a stall reads as lag that catches up rather than a frozen terminal.

## Steps that need root

sshd is **already running** and Remote Login is already on, so there is nothing to enable. Checking that with `lsof -nP -iTCP:22 -sTCP:LISTEN` as a normal user is misleading: it cannot see root-owned listening sockets and prints nothing on a perfectly healthy machine. Use `netstat -an | grep '\.22'`, which needs no privilege and also shows the live sessions.

```
sudo pmset -c sleep 30

sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
  --add /opt/homebrew/bin/mosh-server

sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
  --unblockapp /opt/homebrew/bin/mosh-server
```

The two `socketfilterfw` lines add `mosh-server` to the application firewall, which is on. Mosh binds a UDP port in 60000–61000 per session. An unsigned Homebrew binary launched over ssh may either raise a GUI prompt on the Mac's own screen — useless when you are holding the phone — or have its traffic dropped outright; the allow rule pre-empts both. The symptom it prevents is mosh hanging at `Connecting...` *after* a successful ssh handshake. Stealth mode is off, so nothing else needs changing.

## Termius needs no new keys

Termius supports mosh on iOS — its own documentation covers the mobile setup and states that [mosh 1.3.0 and newer are supported](https://docs.termius.com/organize-and-connect-to-hosts/connecting-to-a-server), and this Mac runs 1.4.0. Which pricing tier exposes it is not stated in those docs, so check the app rather than trusting a number from anywhere else. Your `~/.ssh/authorized_keys` already carries several Termius-labelled keys and the phone connects today, so authentication needs nothing new.

In the host entry on the phone, enable the **Use Mosh** setting, then:

- **Address** `100.80.44.37` — the tailnet IP, not the MagicDNS name. [docs/romp-tailnet-access.md](romp-tailnet-access.md) records that this phone has had "Use Tailscale DNS" switched off, which makes every `.ts.net` name fail to resolve while the 100.x address keeps working.
- **Username** `yulong`
- Leave the mosh-server path and any custom port range empty — `config/zshenv.sh` puts the Homebrew prefix on the PATH of non-interactive shells, so a bare `mosh-server` resolves, and the default 60000–61000 range is what the firewall rule above allows. Termius documents a `mosh-server new -s -l LANG=en_US.UTF-8 -p <from>:<to>` form if you ever need to pin the range; pinning it means narrowing the firewall rule to match.

## Why the PATH fix lives in `~/.zshenv`

Mosh does not run a login shell. It runs `mosh-server` through a non-interactive ssh shell, and zsh reads **only** `~/.zshenv` for those — not `.zprofile`, not `.zshrc`, and `/usr/libexec/path_helper` never runs. Homebrew's prefix is therefore missing and mosh reports `mosh-server: command not found` on a host where plain ssh works, which is the single most common way a Mac mosh setup fails.

`config/zshenv.sh` fixes it server-side, once, for every client and device. `deploy.sh` appends a `source` line for it to `~/.zshenv` behind a `grep` guard — not through `$OP`, which is `>` unless `--append` and would drop the rustup line that also lives in that file.

## Verifying it

```bash
netstat -an | grep '\.22'                 # sshd listening, and who is connected
ssh localhost 'command -v mosh-server'    # PATH fix visible to a non-interactive shell?
ssh localhost 'mosh-server new -s -c 256 -l LANG=en_US.UTF-8'   # prints MOSH CONNECT <port> <key>
pmset -g | grep ' sleep'                  # must read 30, not 1, after the pmset step
```

The third prints a port and a one-time key and leaves a detached server behind; kill it by the pid it reports. It cannot exercise the firewall rule, because loopback is not filtered — only a real connection from the phone tests that.

## Traps already paid for

- **`lsof -i` lies about sshd when you are not root.** It reported no listener on a machine that had three live phone sessions at that moment, which sent the first pass of this investigation to the wrong host entirely. `netstat -an` needs no privilege and shows both the listener and the sessions.
- **Do not probe these ports from inside the Claude Code sandbox.** Loopback and most outbound sockets are blocked there, and `netstat` is refused outright, so a healthy sshd reads as absent. Use `dangerouslyDisableSandbox: true`, as [docs/romp-tailnet-access.md](romp-tailnet-access.md) already records for romp.
- **`mosh` is aliased** to `LANG=en_US.UTF-8 mosh --no-init` in `config/aliases/net.sh`, which preserves scrollback. That is the outbound client on this Mac and is unrelated to serving.
- **OSC 52 clipboard is broken under mosh** (upstream PRs #1054/#1104 unmerged as of 2026), so tmux copy-to-system-clipboard will not work from a phone session. `config/tmux.conf` documents the two workarounds.
- **Truecolor is suppressed under mosh** by `config/zshrc.sh`, deliberately — mosh 1.4.0 garbles 24-bit SGR sequences, so `COLORTERM` is left unset and apps fall back to 256 colours.
