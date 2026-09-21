# Mosh into this Mac from the phone

This machine (`m5pro`, tailnet `100.80.44.37`) is reachable from `iphone-14` over Tailscale. Everything below was measured on 2026-09-21; the parts needing root are listed separately because they are the only steps a Claude Code session cannot do for you.

## Mosh replaces ssh here because the phone's problem is TCP, not bandwidth

An ssh session is one TCP connection pinned to a 4-tuple. Three things routinely invalidate that tuple on a phone, and each one hangs the session rather than closing it cleanly, which is what "patchy" feels like from the client end:

- **iOS suspends the app.** Backgrounding Termius stops it servicing the socket; the peer eventually resets it. The session is dead before you look at the screen again.
- **The phone roams.** Wi-Fi to cellular, or one cell tower to the next, changes the phone's source address. The old tuple is gone and ssh freezes until `ServerAliveCountMax` gives up.
- **A NAT idles the mapping out.** Carrier NATs drop idle UDP/TCP mappings aggressively, so a session left alone for a few minutes is silently unmapped.

Mosh is built for exactly these: it runs over UDP with its own session key, so roaming changes nothing, and it keeps the authoritative screen state on the server, so a suspended client resynchronises instead of reconnecting. It also echoes your keystrokes locally, which is what removes the typing lag over a relayed path.

Mosh does not fix a *sleeping* server — see the `pmset` step below.

## The measured path is relayed, and that is the second half of the patchiness

`tailscale ping` from this Mac, 2026-09-21:

| Peer | Path | Latency |
|---|---|---|
| `iphone-14` | DERP relay (sfo) — `direct connection not established` | 9–17 ms |
| `hetzner` | direct, `5.75.164.68:41641` | 165 ms |

Hetzner goes direct because it has a public address and needs no hole-punching. The phone does not, and the reason is local: **NordVPN holds this Mac's default route** (`utun7`, `10.5.0.2`, MTU 1420), so Tailscale's UDP discovery leaves through the NordVPN exit and `netcheck` reports the public endpoint as `187.14.91.8` with an empty `PortMapping:` line — no UPnP, NAT-PMP or PCP. With the Mac's endpoint masked behind a shared VPN exit and the phone behind carrier CGNAT, neither side can hole-punch, so the pair falls back to a DERP relay.

That matters more than the latency number suggests, because **DERP is a TCP relay**. Running ssh across it is TCP inside TCP: the inner and outer connections both retransmit, and one lost packet stalls everything behind it — the head-of-line blocking that turns a slightly lossy cellular link into a visibly stuttering shell. Mosh's UDP datagrams are carried over the same relay but do not stack a second reliable stream on top of a first, so loss degrades smoothly instead of stalling.

9–17 ms over the SFO relay is perfectly usable, so **you do not have to change anything about NordVPN to make this work**. Turning it off, or excluding Tailscale from it, is what would let the phone and Mac negotiate a direct path and drop the relay entirely. That is a judgement call about what NordVPN is there for, so it is left as yours.

## Steps that need root

These four are the entire manual part. Run them together; each is one command and each reverses cleanly.

```
sudo systemsetup -setremotelogin on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
  --add /opt/homebrew/bin/mosh-server
sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
  --unblockapp /opt/homebrew/bin/mosh-server
sudo pmset -c sleep 0
```

What each one is for:

- **`setremotelogin on`** starts sshd, which is currently not listening — this is why nothing can reach the Mac today. If it refuses with a Full Disk Access error (recent macOS restricts `systemsetup` to terminals holding FDA), use System Settings → General → Sharing → **Remote Login** instead; the effect is identical. Your account is already in the `com.apple.access_ssh` ACL group, so no allow-list edit is needed after it starts.
- **The two `socketfilterfw` lines** add `mosh-server` to the application firewall, which is on. Mosh binds a UDP port in 60000–61000 per session, and the firewall will not raise a GUI prompt for a non-GUI Homebrew binary launched over ssh — it just drops the traffic, which presents as mosh hanging at `Connecting...` after a successful ssh handshake. Stealth mode is off, so nothing else needs changing.
- **`pmset -c sleep 0`** stops the Mac sleeping while on AC. It currently sleeps after 1 minute idle and is only awake now because something holds a `caffeinate`. Mosh survives a dropped network but not a server that has gone to sleep. Battery behaviour is untouched, so unplugged it still sleeps normally. Reverse with `sudo pmset -c sleep 1`.

## Termius needs no new keys

Termius supports mosh on iOS — its own documentation covers the mobile setup and states that [mosh 1.3.0 and newer are supported](https://docs.termius.com/organize-and-connect-to-hosts/connecting-to-a-server), and this Mac has 1.4.0. Which pricing tier exposes it is not stated in those docs, so check the app rather than trusting a number from anywhere else. Your `~/.ssh/authorized_keys` already carries several Termius-labelled keys, so the phone should authenticate without adding anything.

In the host entry on the phone, enable the **Use Mosh** setting, then:

- **Address** `100.80.44.37` — the tailnet IP, not the MagicDNS name. [docs/romp-tailnet-access.md](romp-tailnet-access.md) records that this phone has had "Use Tailscale DNS" switched off, which makes every `.ts.net` name fail to resolve while the 100.x address keeps working. Fixing the toggle is the better end state; the IP is what works regardless.
- **Username** `yulong`
- Leave the mosh-server path and any custom port range empty — `config/zshenv.sh` puts the Homebrew prefix on the PATH of non-interactive shells, so a bare `mosh-server` resolves, and the default 60000–61000 range is what the firewall rule above allows. Termius documents a `mosh-server new -s -l LANG=en_US.UTF-8 -p <from>:<to>` form if you ever need to pin the range; pinning it means narrowing the firewall rule to match.

## Why the PATH fix lives in `~/.zshenv`

Mosh does not run a login shell. It runs `mosh-server` through a non-interactive ssh shell, and zsh reads **only** `~/.zshenv` for those — not `.zprofile`, not `.zshrc`, and `/usr/libexec/path_helper` never runs. Homebrew's prefix is therefore missing and mosh reports `mosh-server: command not found` on a host where plain ssh works, which is the single most common way a Mac mosh setup fails.

`config/zshenv.sh` fixes it server-side, once, for every client and device. `deploy.sh` appends a `source` line for it to `~/.zshenv` behind a `grep` guard — not through `$OP`, which is `>` unless `--append` and would drop the rustup line that also lives in that file.

## Verifying it, in the order that isolates the fault

Run these on the Mac after the sudo block. Each one clears a distinct failure, so a break tells you which step above did not take.

```bash
lsof -nP -iTCP:22 -sTCP:LISTEN          # sshd actually listening?
ssh localhost 'command -v mosh-server'  # PATH fix visible to a non-interactive shell?
ssh localhost 'mosh-server new -s -c 256 -l LANG=en_US.UTF-8'   # prints MOSH CONNECT <port> <key>
```

The third prints a port and a one-time key and leaves a detached server behind; kill it by the pid it reports. A `MOSH CONNECT` line means everything except the firewall is right — the firewall only shows up as a failure from an actual remote client, because loopback is not filtered.

Then, from the phone, connect once and confirm it survives a deliberate network change: start a session, switch Wi-Fi off, and check the shell resumes on cellular rather than hanging. That round-trip is the only test that covers the firewall rule and the relay path together, and it cannot be run from this machine.

## Traps already paid for

- **Do not probe these ports from inside the Claude Code sandbox.** Loopback and most outbound sockets are blocked there, so a healthy sshd reads as connection-refused. Use `dangerouslyDisableSandbox: true`, as [docs/romp-tailnet-access.md](romp-tailnet-access.md) already records for romp.
- **`mosh` is aliased** to `LANG=en_US.UTF-8 mosh --no-init` in `config/aliases/net.sh`, which preserves scrollback. That is the outbound client on this Mac and is unrelated to serving.
- **OSC 52 clipboard is broken under mosh** (upstream PRs #1054/#1104 unmerged as of 2026), so tmux copy-to-system-clipboard will not work from a phone session. `config/tmux.conf` documents the two workarounds.
- **Truecolor is suppressed under mosh** by `config/zshrc.sh`, deliberately — mosh 1.4.0 garbles 24-bit SGR sequences, so `COLORTERM` is left unset and apps fall back to 256 colours.
