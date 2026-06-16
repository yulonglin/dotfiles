# Plan: New-Mac App Setup via Brewfile + Toggle TUI + Auth Helpers

Date: 2026-06-16
Branch: `claude/quirky-hypatia-wj5t9g`

## Goal

Make setting up a fresh Mac a one-command, reviewable experience:
- Install the GUI apps you actually use (casks + Mac App Store).
- Browse each app's description and toggle it on/off before installing.
- Reproducible + re-runnable (Brewfile).
- Encode the ChatGPT trust policy (Homebrew only, official casks, **no new taps**, MAS for App Store vendor apps).
- Prune dotfiles cruft that the security policy says to drop.
- Help with the apps that need auth/manual login.

Priority order baked into every decision (from your security note):
**Security > Reliability > Reproducibility > Performance > Novelty.**

---

## 1. Architecture

```
config/apps.conf          # NEW — single source of truth: one line per app
  └─ generates → config/Brewfile        # brew/cask/mas entries (committed, reproducible)
custom_bins/app-picker    # NEW — gum TUI: browse descriptions, toggle, write Brewfile
install.sh  --apps        # NEW component: bootstrap brew+gum → run picker → brew bundle
scripts/setup/auth-setup  # NEW — interactive post-install auth checklist
```

Why Brewfile (your choice) + a registry:
- `brew bundle` natively handles `brew "x"`, `cask "x"`, and `mas "App", id: N` — one mechanism covers CLI tools, GUI casks, and App Store apps.
- The committed `config/Brewfile` is the reproducible lock-ish artifact the policy asks for.
- `config/apps.conf` keeps descriptions + category + trust tier + auth notes that a raw Brewfile can't hold; the picker reads it and emits the Brewfile.

### `config/apps.conf` schema

```
# method | id           | category   | tier | default | name              | description | auth
cask     | notion        | text       | 1    | true    | Notion            | Notes/docs/wiki                 | login
mas      | 904280696     | tasks      | 2    | true    | Things 3          | GTD task manager (App Store)    | things-cloud
brew     | wakatime-cli  | time       | 2    | false   | WakaTime CLI      | Coding time tracker (API key)   | apikey
```

- **method**: `brew` (formula) / `cask` / `mas` (App Store). **Selection rule (per your policy: MAS > vendor download > cask):** prefer `mas` when the app is on the App Store AND its sandboxed MAS build isn't feature-crippled (gives sandbox/least-privilege + notarization + no cask supply-chain surface). Use `cask` only when the app needs unsandboxed system access (accessibility, automation, system/network extensions, SMC) or isn't on MAS. Safari extensions are always `mas`. Caveat: `mas` re-installs Apple-ID-owned apps, but first acquisition of paid apps (e.g. Things 3) is a one-time GUI step.
- **tier**: 1 = official vendor auto-approve, 2 = mature OSS review, 3 = needs explicit approval (per your policy). Drives a color tag in the TUI; tier-3 items default OFF.
- **default**: initial toggle state.
- **auth**: token for the auth-setup checklist (`login`, `apikey`, `pair-phone`, `safari-ext`, `license`, `none`).

### TUI: `gum` (answers your "which needs no install?")

None of gum/fzf/ratatui preship on a clean Mac, but:
- Homebrew is the *only* hard prereq and `install.sh` already installs it first.
- `gum` is a 1-file brew formula already in your package list and already the engine behind `show_component_menu`.
- ratatui would need a full `cargo build` (heavy, slow on fresh machine).

So: **bootstrap `gum` immediately after Homebrew**, then reuse the existing menu pattern. The picker shows `name — description` rows grouped by category, with a tier tag, full description visible inline (gum) — space toggles, enter confirms, writes `config/Brewfile`. (If you'd prefer a full-description side panel, fzf `--preview` is a drop-in alternative; gum is the lower-friction default.)

---

## 2. App → install-method mapping (verified)

Legend: ✅ cask · 🛒 Mac App Store (mas) · ⌘ formula · ⚙️ already has dotfiles *config* (install layer is new)

| Category | App | Method | Cask/ID | Tier | Notes |
|---|---|---|---|---|---|
| text | Bear | 🛒 | `1091189122` | 2 | App Store only; `bearcli` deploy already symlinks CLI |
| text | Notion | ✅ | `notion` | 1 | |
| tasks | Things 3 | 🛒 | `904280696` | 2 | App Store only |
| coding/editor | Cursor | ✅ | `cursor` | 1 | editor config already deployed |
| coding/editor | Antigravity | ✅ | `antigravity` | 1 | Google; config already deployed |
| coding/editor | Zed | ✅ | `zed` | 1 | config already deployed ⚙️ |
| coding/LLM | ChatGPT | ✅ | `chatgpt` | 1 | OpenAI |
| coding/LLM | Claude | ✅ | `claude` | 1 | Anthropic desktop |
| coding/LLM | Codex CLI | ⌘ | (npm, existing `ai-tools`) | 1 | already installed |
| coding/CLI | Ghostty | ✅ | `ghostty` | 1 | config already deployed ⚙️ |
| meetings | Granola | ✅ | `granola` | 2 | |
| cloud | Dropbox | ✅ | `dropbox` | 1 | |
| cloud | Google Drive | ✅ | `google-drive` | 1 | optional (default OFF) |
| search | Alfred | ✅ | `alfred` | 2 | prefs sync from Dropbox (manual: set sync folder + Powerpack license) |
| messaging | Slack | ✅ | `slack` | 1 | |
| messaging | Spark | 🛒 or ✅ | mas (verify id) / `readdle-spark` cask | 2 | MAS build is full-featured (not crippled) → MAS preferred for sandbox; cask also fine |
| productivity | Mouseless | ✅ | `mouseless` | 2 | config already deployed ⚙️; needs accessibility → cask |
| productivity | PopClip | ✅ | `popclip` | 2 | **Use cask, NOT MAS** — MAS edition abandoned at v2023.9; standalone is sandbox-free + current |
| time | Super Productivity | ✅ | `super-productivity` | 2 | |
| time | WakaTime CLI | ⌘ | `wakatime-cli` | 2 | optional; API key via secrets |
| voice | VoiceInk | ✅ | `voiceink` | 2 | config already deployed ⚙️; downloads model on first run |
| vpn | NordVPN | ✅ | `nordvpn` | 2 | `vpn` deploy already configures split tunnel ⚙️ |
| auth | Bitwarden | ✅ or 🛒 | `bitwarden` cask / mas `1352778147` | 1 | Desktop app **has a cask**. Safari extension ships **only** in the MAS build → use mas if you want the Safari ext (covers both) |
| auth | 2FAS | 🛒 | *verify id* | 2 | mainly phone-paired; Safari ext |
| auth | Tailscale | ✅ | `tailscale-app` | 1 | `vpn` deploy already configures ⚙️ |
| safari-ext | uBlock Origin Lite | 🛒 | `6745342698` | 2 | enable manually in Safari |
| safari-ext | Userscripts | 🛒 | `1463298887` *verify* | 2 | enable manually in Safari |
| safari-ext | 2FAS / Bitwarden | 🛒 | (above) | — | enable manually in Safari |
| music | Spotify | ✅ | `spotify` | 1 | |
| misc | AlDente | ✅ | `aldente` | 2 | |
| misc | Finicky | ✅ | `finicky` | 2 | currently installed inline → fold into Brewfile ⚙️ |
| misc | AppCleaner | ✅ | `appcleaner` | 2 | |
| misc | CleanShot X | ✅ | `cleanshot` | 1 | |
| misc | Stats | ✅ | `stats` | 2 | |
| misc | KeyboardCleanTool | ✅ | `keyboardcleantool` | 2 | |
| misc | BeardedSpice | ✅ | `beardedspice` | 2 | |
| antivirus | Malwarebytes | ✅ | `malwarebytes` | 2 | **optional, default OFF**; lightweight on-demand scanner. **Recommended** AV for personal use |
| antivirus | Trellix | ❌ | — | 3 | Personal install, no cask → checklist manual-install note. **Don't run real-time alongside Malwarebytes.** Recommend skip (heavy enterprise EDR, low value for dev threat model) |

IDs marked *verify* get a `mas search` / `brew info` check during implementation before committing (policy: `brew info` before install, verify vendor/homepage). Safari extensions can be *installed* but must be *enabled* in Safari manually — the auth checklist will list them.

### "settings → dotfiles" (menu bar / accessibility / dock)
These aren't apps — they're system defaults. Already handled by `config/macos_settings.sh`. I'll extend it with:
- Dock: which apps are pinned (set from the installed-apps list) + autohide behaviour.
- Menu bar items (where scriptable; Stats/AlDente handle most).
Treated as a follow-up sub-task, not part of the Brewfile.

---

## 3. Auth / manual-setup helper

New `scripts/setup/auth-setup` (run after `brew bundle`): an interactive gum checklist that, per app needing setup, prints the action and offers to open the app / URL:

- **git / gh** — already covered (gist sync + `gh auth login`); checklist just verifies.
- **API-key apps (WakaTime)** — wire into existing secrets system (`setup-envrc` / `with-secrets`); no plaintext.
- **GUI logins** (Dropbox, Slack, Spark, Granola, Bitwarden, NordVPN, Tailscale, ChatGPT, Claude, Things Cloud, Spotify) — open app, check off when logged in. Can't be automated (interactive OAuth/passwords) — checklist only.
- **Alfred** — open prefs, point sync folder at Dropbox, apply Powerpack license.
- **Safari extensions** — open Safari → Settings → Extensions, enable uBlock Origin Lite / Bitwarden / 2FAS / Userscripts.
- **VoiceInk** — first-run model download.

No secrets are stored in plaintext; anything key-based flows through the existing SOPS/BWS path.

---

## 4. Proposed pruning (per-item approval — your choice)

Driven by your policy ("prefer mature, boring"; "never auto-add taps"; "revisit ZeroBrew in 6–12 months"; "cautious with MCP/random tools"):

**APPROVED for removal:**

| # | Remove | Where | Rationale |
|---|---|---|---|
| P1 | **zerobrew** | `install.sh` experimental | Experimental pkg mgr; your note says revisit in 6–12mo. `curl\|bash` install. |
| P3 | **Coven** + `brew tap Crazytieguy/tap` | `install.sh` ai-tools | Third-party tap — violates "never auto-add taps". |

**KEEP (you declined):** ty type checker, zotero-mcp-server → so the `experimental` component stays.
`OFFICIAL_PLUGINS` audit deferred (can revisit separately).

---

## 5. Policy documentation

- Extend `claude/rules/supply-chain-security.md` (or add `config/apps.conf` header) with the tier model + "no new taps without approval" + "`brew info` before adding any app".
- Note in `CLAUDE.md` how to add an app (one line in `apps.conf` → re-run picker) and the Brewfile regen flow (`brew bundle dump`-style).
- Optional, not auto-applied: your note prefers `~/code/dotfiles` over `~/.dotfiles`. `DOT_DIR` is auto-detected so nothing breaks either way — I'll mention it but not move the repo.

---

## 6. Malicious apps & executables — install integrity + runtime defense

Trust tiers gate *what* we install; this section gates *integrity* (is the bytes what the vendor shipped?) and *runtime* (is a trusted-looking app misbehaving?). All additions are official/mature, free unless noted.

### Already covered
- **macOS**: Gatekeeper + notarization (blocks unsigned/un-notarized on launch), XProtect + XProtect Remediator (Apple malware scanner, auto-updated), App Store sandboxing (MAS apps = highest trust → "MAS-first" rule), TCC permission prompts.
- **Brew casks**: pinned **sha256** verified on download → tampered artifact aborts.
- **Dev deps** (existing): `min-release-age` 7-day quarantine, `ignore-scripts`, weekly `dep-audit`, Socket CLI, gitleaks, pip-audit.

### Additions (all selected)
1. **Enforce quarantine policy** — never `--no-quarantine` in any cask/Brewfile entry; document that Gatekeeper/notarization must stay enabled. Pure policy, zero cost. → `claude/rules/supply-chain-security.md`.
2. **Signature-verify step in `auth-setup`** — after install, run `spctl --assess --type execute` + `codesign -dv --verbose=4` per app; report any unsigned/un-notarized app before you trust it. Free.
3. **LuLu** (Objective-See, free OSS outbound firewall) — optional cask, **default OFF** (prompts a lot). Fills the runtime/egress gap: catches a signed-but-compromised app phoning home. Document KnockKnock (persistence enumeration) + BlockBlock (persistence alerts) as further optional Objective-See tools.
4. **Harden `curl|bash` installers** — resolves "is official-page curl|bash ok?":
   - Official page gives **authenticity** (HTTPS cert proves the domain) but NOT **integrity-over-time** (runs whatever's live, unseen), **pinning** (no agreed sha → tamper passes), or **reproducibility**.
   - **Rule, best→worst:** (a) use the official **brew formula** if it exists — `uv`, `rustup-init`, `bun` all do; you get the vendor's artifact + sha pin + reviewed PR + reproducible re-run. (b) No formula → `curl -o` the script to a versioned URL and **verify the vendor's published checksum/signature** if they offer one (this is the actual tamper-evidence). (c) blind `curl … | sh` only as last resort, HTTPS-to-official-domain only.
   - **Note on manual inspection:** eyeballing the script ("glance at it") is a low-effort smell test for *gross* tampering (second payloads, surprise `sudo`), NOT an integrity control — a competent attacker defeats it, and you're reading the installer not the binary it fetches. Don't treat it as a safeguard; the safeguards are (a)/(b).
   - Migrate existing blind pipes in `install.sh` (uv, rust) to brew formulae / fetch-verify-run.

---

## 7. Files to change

- **NEW** `config/apps.conf` — app registry (the table above).
- **NEW** `config/Brewfile` — generated, committed.
- **NEW** `custom_bins/app-picker` — gum toggle TUI → writes Brewfile.
- **NEW** `scripts/setup/auth-setup` — auth checklist + `spctl`/`codesign` signature-verify step (§6.2).
- **EDIT** `config.sh` — add `apps` to `INSTALL_REGISTRY`; remove pruned items; add LuLu (optional, OFF) to apps.conf.
- **EDIT** `install.sh` — `--apps` block: bootstrap gum, run picker, `brew bundle --file=config/Brewfile`; remove inline Finicky + pruned experimental/coven blocks; migrate uv/rust `curl|bash` → brew formulae / fetch-verify-run (§6.4).
- **EDIT** `scripts/shared/helpers.sh` — small `brew bundle` + `mas` helpers if needed.
- **EDIT** `claude/rules/supply-chain-security.md`, `CLAUDE.md` — policy + how-to + quarantine/no-`--no-quarantine` rule + curl|bash hardening rule.
- **EDIT** `config/macos_settings.sh` — dock/menu-bar follow-up (optional, can defer).

## 8. Verification

- `mas search` / `brew info` each *verify*-flagged id before committing the Brewfile.
- `brew bundle check --file=config/Brewfile` (dry, on a Mac) — can't run here (Linux container); will gate behind a note for you to run, or validate syntax with a parser.
- `app-picker` run with `--dry-run` to confirm it emits a valid Brewfile without installing.
- Shellcheck the new scripts.

## 9. Resolved decisions

1. **Prune**: zerobrew + Coven/tap only (P1, P3). ty, zotero-mcp, `experimental` component all stay.
2. **Antivirus**: Trellix = university-managed (checklist note, not Brewfile). Malwarebytes = optional cask, default OFF, conflict note.
3. **Optional apps**: Google Drive + WakaTime default OFF (toggle on in picker).
4. **TUI**: gum (bootstrapped after Homebrew). fzf `--preview` remains a drop-in alt.
5. **Malicious apps/executables** (§6): enforce quarantine policy + `spctl`/`codesign` verify step + LuLu (optional, OFF) + harden `curl|bash` → prefer brew formula, else fetch-verify-run. All four selected.

All open questions resolved — ready to implement on approval.
