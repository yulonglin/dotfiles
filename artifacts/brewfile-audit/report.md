# Six Casks Marked for Removal and Twenty-Seven Apps Join the Registry

Audit of this Mac against `config/apps.conf` on 2026-09-03. Inventory came from `brew list --cask`, `brew leaves --installed-on-request`, `brew tap`, and App Store receipts under `/Applications`; last-opened dates are Spotlight's `kMDItemLastUsedDate`, which Safari-extension hosts and daemons never set. Nothing was uninstalled: every removal below is a command for Yulong to run.

## The registry now knows everything installed, and `exclude` keeps rejected apps out

Before this pass the Brewfile listed 40 entries while the Mac carried 53 casks and 20 App Store apps, and nothing compared the two. Three changes close that gap:

- **`default=exclude` in `config/apps.conf`.** An excluded row is never offered in the picker, never written to the Brewfile, and skipped by `mas-get` and `auth-setup`. `app-picker --audit` keeps naming it with an uninstall command until it is gone. The description carries the reason and date.
- **`mas-get` acquires only the Brewfile's App Store lines.** It used to walk the whole registry, which was harmless while every App Store row defaulted on; with GarageBand and iMovie now registered as off, a fresh `install.sh` would have pulled them anyway. Without a Brewfile it falls back to rows with `default=true`.
- **`app-picker --installed`** preselects the picker from what this Mac has, so deselecting a row is the UI for dropping an app. In a terminal it opens the gum toggle list; without one it writes the Brewfile directly.
- **`app-picker --audit`** (also run after every write) prints six sections: excluded-but-installed, installed-but-deselected, selected-but-missing, unregistered casks, unregistered App Store apps with a ready row template, undeclared formulae, and third-party taps. It never proposes `brew bundle cleanup`, which would remove every CLI tool `config.sh` installs because those are not in the Brewfile.

The Brewfile was regenerated with `--installed`, so it now states 65 entries: everything installed and registered, minus the six exclusions. `tests/test_app_picker.zsh` pins the exclude semantics, the `--installed` preselection, the name matching for App Store apps, and the audit sections with a stubbed `brew` (28 checks).

## Uninstall now: six excluded casks and two third-party taps

| Cask | Last opened | Why it goes | Command |
|---|---|---|---|
| cursor | 2026-08-08 | Yulong's call. Zed and Claude Code cover it; `deploy.sh --editor` skips Cursor when its config dir is absent | `brew uninstall --cask cursor` |
| codex-app | never (app gone) | Zombie. `/Applications` has no `Codex.app`; the `chatgpt` cask 26.901 now ships an app whose bundle id is `com.openai.codex` | `brew uninstall --cask codex-app` |
| codexbar | 2026-07-21 | Yulong's call. Menu-bar usage monitor for Codex and Claude | `brew uninstall --cask codexbar` |
| conductor | never | Yulong's call. Claude Code parallelisation UI | `brew uninstall --cask conductor` |
| espanso | 2026-08-11 | Yulong's call. Its match and config dir stays in `~/Library/Application Support/espanso` unless you add `--zap` | `brew uninstall --cask espanso` |
| aqua-voice | never | Superseded by VoiceInk | `brew uninstall --cask aqua-voice` |

The two taps violate the repo's own policy in `claude/rules/safety.md`, which allows no third-party Homebrew taps without approval. Shell history shows `red` used twice and `gt` three times.

| Tap | Formula | Command |
|---|---|---|
| codersauce/tap | red (modal Rust editor) | `brew uninstall red && brew untap codersauce/tap` |
| withgraphite/tap | graphite (`gt`, stacked PRs) | `brew uninstall graphite && brew untap withgraphite/tap` |

`ChatGPT Classic.app` (1.2026.183, the pre-merge ChatGPT, last opened 2026-08-13) is not owned by brew and stays behind after the cask upgrade. Remove it with AppCleaner if the new ChatGPT covers it.

## Still in the picker, but never opened since install

These stay registered with `default=false` so the picker keeps offering them. Each is one toggle in `app-picker --installed`, or the command shown.

| App | Source | Last opened | Note | Command |
|---|---|---|---|---|
| LibreOffice | cask | never | 804 MB office suite | `brew uninstall --cask libreoffice` |
| Visual Studio Code | cask | never | 945 MB; `deploy.sh --editor` merges settings into it if present; Zed and Cursor were the editors in use | `brew uninstall --cask visual-studio-code` |
| Zotero | cask | never | 396 MB; installed 2026-08-27; `zotero-mcp` is gated behind `install.sh --experimental` | `brew uninstall --cask zotero` |
| RemNote | cask | 2026-07-23 | Six weeks idle | `brew uninstall --cask remnote` |
| LuLu | cask | never | Registry default was already off | `brew uninstall --cask lulu` |
| Malwarebytes | cask | never | Registry default was already off; Trellix is the managed AV | `brew uninstall --cask malwarebytes` |
| Numbers | mas | never | Free, reinstallable | `sudo mas uninstall 361304891` |
| GarageBand | mas | never | 1.1 GB; free, reinstallable | `sudo mas uninstall 682658836` |
| iMovie | mas | never | 3.7 GB; free, reinstallable | `sudo mas uninstall 408981434` |
| GoodLinks | mas | 2026-08-08 | Paid; keep if the iOS side is in use | `sudo mas uninstall 1474335294` |
| Highlights | mas | 2026-08-15 | PDF annotation | `sudo mas uninstall 1498912833` |
| Fira Code | cask | n/a | Only a third-choice fallback in `config/vscode_settings.json` | `brew uninstall --cask font-fira-code` |

## Added to the registry: fifteen casks and twelve App Store apps that were installed around it

Default `true` means a fresh machine gets it; the choice follows whether it is running, a login item, or opened this fortnight.

| App | Method | Category | Default | Evidence |
|---|---|---|---|---|
| Obsidian | cask | text | true | running, login item, `deploy.sh` vault sync reads it |
| Google Chrome | cask | browser | true | running, Finicky target |
| Telegram | cask | messaging | true | running, opened today |
| WhatsApp | cask | messaging | true | running, opened today |
| Signal | cask | messaging | true | opened 2026-08-31 |
| Discord | cask | messaging | true | opened 2026-08-27 |
| Zoom | cask | meetings | true | Finicky routes zoom links to it; `app-lifecycle.yaml` spares it |
| ActivityWatch (beta) | cask | time | true | running (`aw-watcher-*`), login item |
| Cloudflare WARP | cask | vpn | true | daemon running; opened 2026-08-29 |
| Thaw | cask | misc | true | running, login item |
| Dropover | mas 1355679052 | productivity | true | login item, opened 2026-09-02 |
| Keynote | mas 361285480 | productivity | true | opened 2026-08-18 |
| Pages | mas 361309726 | productivity | true | opened 2026-08-25 |
| Noir | mas 1592917505 | safari | true | paid Safari extension |
| Speed Player | mas 1521133201 | safari | true | Safari extension |
| Flighty | mas 1358823008 | misc | true | opened 2026-09-03 |
| TestFlight | mas 899247664 | misc | false | opened 2026-08-26 |
| RemNote, LibreOffice, VS Code, Zotero, Fira Code | cask | various | false | table above |
| Numbers, GarageBand, iMovie, GoodLinks, Highlights | mas | various | false | table above |

App Store ids came from Apple's lookup API by bundle id, because `mas list` hangs on this Mac (mas 7.0.0 on macOS 26; a 25 second timeout printed nothing). One App Store app has no resolvable id: **Lettera** (`net.shinyfrog.lettera`, Shiny Frog, opened today) returns no match on App Store search, so it is probably a TestFlight build. The audit will keep listing it with a row template until an id exists.

## What cannot move into the Brewfile

Ghostty is already a Brewfile cask installed by brew, as are Tailscale, NordVPN, Malwarebytes, Cold Turkey and Google Drive; their installers are `.pkg` files, so no `.app` sits in the Caskroom and a naive scan misreads them as hand-installed. The apps genuinely outside brew:

| App | What it is | Action |
|---|---|---|
| Google Docs, Sheets, Slides | Shortcut apps Google Drive creates and owns | none |
| Cold Turkey Micromanager Pro | Ships inside the Cold Turkey Blocker installer | none |
| ChatGPT Classic | Displaced pre-merge ChatGPT, see above | AppCleaner if unused |
| Revealer (`com.apollo.revealer`) | No cask; opened 2026-08-09 | keep or trash by hand |
| Silico (`ai.goodfire.silico`) | No cask; opened 2026-08-11 | keep or trash by hand |
| mytello | No cask, no bundle id; opened 2026-08-04 | keep or trash by hand |

## CLI formulae stay in `config.sh`, and five are declared nowhere

Cross-platform CLI tools are the `PACKAGES_*` arrays in `config.sh`, not the Brewfile, because Linux installs the same list through Linuxbrew or apt; the registry's scope note now says so. The audit therefore treats anything named in `config.sh` or `scripts/shared/helpers.sh` as declared, which is also what keeps the `codex` and `antigravity-cli` casks (installed by `install.sh --ai-tools`) out of the unregistered list. Five requested formulae are named nowhere:

| Formula | Installed | History hits | Recommendation |
|---|---|---|---|
| tlrc | 2026-06-27 | n/a | `config.sh` installs `tldr` instead, the older Node client, which is not what this Mac runs. Replace `tldr` with `tlrc` in `PACKAGES_CORE`, or uninstall tlrc |
| marp-cli | 2026-07-19 | 5 | Add to `PACKAGES_EXTRAS_MACOS` if decks still go through Marp, else `brew uninstall marp-cli` (this also drops node and simdjson) |
| hunk | 2026-09-03 | 7 | Installed today. Add to `PACKAGES_EXTRAS_MACOS` once it sticks |
| red | 2026-08-26 | 2 | Third-party tap, above |
| graphite | 2026-07-27 | 3 | Third-party tap, above |

**simdjson** is the one Yulong asked about: it was never requested. It is a dependency of `node`, which `marp-cli` and `opencode` pull in (`brew uses --installed simdjson`), and its install receipt says `installed_on_request: false`. It disappears on its own when nothing needs node.

## Decisions for Yulong

- Run the six cask uninstalls and the two untaps above, or edit the `exclude` rows back if any call was wrong.
- Pick from the never-opened table; the fastest way is `app-picker --installed` in a terminal, deselect, then run the commands the audit prints.
- `tldr` versus `tlrc` in `config.sh`, and whether `marp-cli` and `hunk` earn a `PACKAGES_EXTRAS_MACOS` line. Not changed here.
- `mas-get` and the post-install check in `install.sh` still shell out to `mas list` and will hang the same way on this machine. They need a `timeout` or the receipt scan the audit uses. Not changed here.
- The `CLAUDE.md` learning from 2026-08-30 says this box has no Zotero installed; it does, via brew, never opened. Fix the line or remove the app.

## Commands

```
app-picker --installed        # toggle what this Mac keeps; writes config/Brewfile and audits
app-picker --audit            # audit only, no writes
brew bundle --file=config/Brewfile
zsh tests/test_app_picker.zsh
```
