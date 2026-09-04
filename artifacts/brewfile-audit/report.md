# Seven Casks Marked for Removal and Twenty-Seven Apps Join the Registry

Audit of this Mac against `config/apps.conf` on 2026-09-03, revised after Yulong's review the same evening. Inventory came from `brew list --cask`, `brew leaves --installed-on-request`, `brew tap`, and App Store receipts under `/Applications`; last-opened dates are Spotlight's `kMDItemLastUsedDate`, which Safari-extension hosts and daemons never set. Casks are never uninstalled by this work; the formula and app removals Yulong asked for in review were run and are marked as done.

## Review decisions, 2026-09-03 21:07

| Item | Yulong said | Done |
|---|---|---|
| marp-cli, graphite, age, sops | remove | uninstalled; `withgraphite/tap` untapped; `brew autoremove` found nothing further because opencode still needs node |
| ChatGPT Classic.app | remove | moved to the Trash |
| red | leave in | kept; declared in the new `PACKAGES_TRIAL_MACOS` so the audit treats `codersauce/tap` as an exception on record |
| hunk | trial, alongside red, maybe micro, gitui | `PACKAGES_TRIAL_MACOS` holds hunk and red, with micro as a commented candidate; gitui is already in `PACKAGES_EXTRAS_MACOS` |
| Cloudflare WARP | exclude for now | `default=exclude`; still installed, so the audit lists its uninstall command |
| Visual Studio Code | intend to use | `default=true` |
| LibreOffice | is anything using it? | no: `any2md` converts docx, pptx and xlsx through markitdown, and nothing in the repo shells out to soffice. Left at `default=false` |
| Codex cask | was this ChatGPT.app renamed? | yes in effect, see below. `brew uninstall --cask codex-app` only targets a `Codex.app` that no longer exists and leaves ChatGPT.app alone; do not add `--zap`, which would clear the shared `com.openai.codex` preferences |
| LuLu | what is it? is it useful? | Objective-See's free outbound firewall: it prompts before an app first phones home. Useful when you want to see which apps call out, at the cost of a prompt per new app. It has never been opened here in three months, is not running, and Tailscale plus NordVPN already control the network path, so it is not doing anything for you. Lean: uninstall |
| abseil, brotli, icu4c, jemalloc and the rest | are they useful? document it, without bloating agent context; auto-update | all dependencies of requested tools, none orphaned. Now a generated doc, `docs/brew-formulae.md`, rewritten on every `app-picker` write or `--audit` and printable with `app-picker --deps`; CLAUDE.md links it in one clause under Where To Look and nothing loads it into context |
| tlrc | is it the newer version? | yes: the `tldr` formula is deprecated in Homebrew and tlrc is the official Rust client. `config.sh` now installs tlrc in the two brew arrays and drops `tldr` from `PACKAGES_CORE`, which also feeds apt where tlrc does not exist |

## The registry now knows everything installed, and `exclude` keeps rejected apps out

Before this pass the Brewfile listed 40 entries while the Mac carried 53 casks and 20 App Store apps, and nothing compared the two. Three changes close that gap:

- **`default=exclude` in `config/apps.conf`.** An excluded row is never offered in the picker, never written to the Brewfile, and skipped by `mas-get` and `auth-setup`. `app-picker --audit` keeps naming it with an uninstall command until it is gone. The description carries the reason and date.
- **`mas-get` acquires only the Brewfile's App Store lines.** It used to walk the whole registry, which was harmless while every App Store row defaulted on; with GarageBand and iMovie now registered as off, a fresh `install.sh` would have pulled them anyway. Without a Brewfile it falls back to rows with `default=true`.
- **`app-picker --installed`** preselects the picker from what this Mac has, so deselecting a row is the UI for dropping an app. In a terminal it opens the gum toggle list; without one it writes the Brewfile directly.
- **`app-picker --audit`** (also run after every write) prints: excluded-but-installed, installed-but-deselected, selected-but-missing, unregistered casks, unregistered App Store apps with a ready row template, formulae declared nowhere, and third-party taps, split into policy breaches and taps whose formulae `config.sh` declares. It never proposes `brew bundle cleanup`, which would remove every CLI tool `config.sh` installs because those are not in the Brewfile.

The Brewfile was regenerated with `--installed` after the review and states 64 entries: everything installed and registered, minus the seven exclusions. `tests/test_app_picker.zsh` pins the exclude semantics, the `--installed` preselection, the name matching for App Store apps, the mas-get selection and the audit sections with a stubbed `brew` and `mas` (41 checks).

## Uninstall now: seven excluded casks

| Cask | Last opened | Why it goes | Command |
|---|---|---|---|
| cursor | 2026-08-08 | Yulong's call. Zed and Claude Code cover it; `deploy.sh --editor` skips Cursor when its config dir is absent | `brew uninstall --cask cursor` |
| codex-app | never (app gone) | Zombie, see below | `brew uninstall --cask codex-app` |
| codexbar | 2026-07-21 | Yulong's call. Menu-bar usage monitor for Codex and Claude | `brew uninstall --cask codexbar` |
| conductor | never | Yulong's call. Claude Code parallelisation UI | `brew uninstall --cask conductor` |
| espanso | 2026-08-11 | Yulong's call. Its match and config dir stays in `~/Library/Application Support/espanso` unless you add `--zap` | `brew uninstall --cask espanso` |
| aqua-voice | never | Superseded by VoiceInk | `brew uninstall --cask aqua-voice` |
| cloudflare-warp | 2026-08-29 | Yulong's call, "for now". Daemon still running until removed | `brew uninstall --cask cloudflare-warp` |

**What happened to Codex.app.** The `codex-app` cask installed `Codex.app` on 2026-06-17. On 2026-07-10 the old ChatGPT was renamed `ChatGPT Classic.app` (version 1.2026.183, now in the Trash), and the app at `/Applications/ChatGPT.app` today carries the bundle id `com.openai.codex` at version 26.901, installed by the `chatgpt` cask. So the Codex desktop app became ChatGPT, OpenAI's updater or the cask upgrade renamed it in place, and the `codex-app` receipt in the Caskroom points at an app directory with no readable bundle id. The registry keeps `chatgpt` and retires `codex-app`. Confidence about 75 percent; it rests on bundle ids and dates, not on a vendor note.

The third-party taps after review: `withgraphite/tap` is gone with graphite. `codersauce/tap` stays for red and is listed by the audit as an exception on record, not a breach.

## Still in the picker, but never opened since install

These stay registered with `default=false` so the picker keeps offering them. Each is one toggle in `app-picker --installed`, or the command shown. Visual Studio Code left this table: Yulong intends to use it.

| App | Source | Last opened | Note | Command |
|---|---|---|---|---|
| LibreOffice | cask | never | 804 MB; no tool here uses it | `brew uninstall --cask libreoffice` |
| Zotero | cask | never | 396 MB; installed 2026-08-27; `zotero-mcp` is gated behind `install.sh --experimental` | `brew uninstall --cask zotero` |
| RemNote | cask | 2026-07-23 | Six weeks idle | `brew uninstall --cask remnote` |
| LuLu | cask | never | Objective-See outbound firewall; not running | `brew uninstall --cask lulu` |
| Malwarebytes | cask | never | Registry default was already off; Trellix is the managed AV | `brew uninstall --cask malwarebytes` |
| Numbers | mas | never | Free, reinstallable | `sudo mas uninstall 361304891` |
| GarageBand | mas | never | 1.1 GB; free, reinstallable | `sudo mas uninstall 682658836` |
| iMovie | mas | never | 3.7 GB; free, reinstallable | `sudo mas uninstall 408981434` |
| GoodLinks | mas | 2026-08-08 | Paid; keep if the iOS side is in use | `sudo mas uninstall 1474335294` |
| Highlights | mas | 2026-08-15 | PDF annotation | `sudo mas uninstall 1498912833` |
| Fira Code | cask | n/a | Only a third-choice fallback in `config/vscode_settings.json` | `brew uninstall --cask font-fira-code` |

## Added to the registry: fifteen casks and twelve App Store apps that were installed around it

Default `true` means a fresh machine gets it; the choice follows whether it is running, a login item, or opened this fortnight, then Yulong's review.

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
| Visual Studio Code | cask | editor | true | Yulong's review: intends to use it |
| Thaw | cask | misc | true | running, login item |
| Cloudflare WARP | cask | vpn | exclude | Yulong's review: exclude for now |
| Dropover | mas 1355679052 | productivity | true | login item, opened 2026-09-02 |
| Keynote | mas 361285480 | productivity | true | opened 2026-08-18 |
| Pages | mas 361309726 | productivity | true | opened 2026-08-25 |
| Noir | mas 1592917505 | safari | true | paid Safari extension |
| Speed Player | mas 1521133201 | safari | true | Safari extension |
| Flighty | mas 1358823008 | misc | true | opened 2026-09-03 |
| TestFlight | mas 899247664 | misc | false | opened 2026-08-26 |
| RemNote, LibreOffice, Zotero, Fira Code | cask | various | false | table above |
| Numbers, GarageBand, iMovie, GoodLinks, Highlights | mas | various | false | table above |

App Store ids came from Apple's lookup API by bundle id, because `mas list` hangs on this Mac (mas 7.0.0 on macOS 26; a 25 second timeout printed nothing). One App Store app has no resolvable id: **Lettera** (`net.shinyfrog.lettera`, Shiny Frog, opened today) returns no match on App Store search, so it is probably a TestFlight build. The audit will keep listing it with a row template until an id exists.

## What cannot move into the Brewfile

Ghostty is already a Brewfile cask installed by brew, as are Tailscale, NordVPN, Malwarebytes, Cold Turkey and Google Drive; their installers are `.pkg` files, so no `.app` sits in the Caskroom and a naive scan misreads them as hand-installed. The apps genuinely outside brew:

| App | What it is | Action |
|---|---|---|
| Google Docs, Sheets, Slides | Shortcut apps Google Drive creates and owns | none |
| Cold Turkey Micromanager Pro | Ships inside the Cold Turkey Blocker installer | none |
| Revealer (`com.apollo.revealer`) | No cask; opened 2026-08-09 | keep or trash by hand |
| Silico (`ai.goodfire.silico`) | No cask; opened 2026-08-11 | keep or trash by hand |
| mytello | No cask, no bundle id; opened 2026-08-04 | keep or trash by hand |

## CLI formulae stay in `config.sh`, with a trial list for the ones under evaluation

Cross-platform CLI tools are the `PACKAGES_*` arrays in `config.sh`, not the Brewfile, because Linux installs the same list through Linuxbrew or apt; the registry's scope note now says so. The audit treats anything named in `config.sh` or `scripts/shared/helpers.sh` as declared, which is also what keeps the `codex` and `antigravity-cli` casks (installed by `install.sh --ai-tools`) out of the unregistered list.

`PACKAGES_TRIAL_MACOS` is new: tools installed by hand while being evaluated, which `install.sh` does not install but the audit counts as declared. Date each entry; promote it to a real array or uninstall it when the trial ends.

| Formula | Installed | History hits | After review |
|---|---|---|---|
| hunk | 2026-09-03 | 7 | trial list |
| red | 2026-08-26 | 2 | trial list; its tap is the one sanctioned exception |
| micro | not installed | n/a | commented candidate in the trial list |
| marp-cli | 2026-07-19 | 5 | removed |
| graphite | 2026-07-27 | 3 | removed, tap untapped |
| age, sops | 2026-09-03, 2026-08-05 | n/a | removed. `install_age` and `install_sops` exist in helpers.sh but nothing calls them, and the secrets engine never used either |
| tlrc | 2026-06-27 | n/a | now declared: `config.sh` installs tlrc in `PACKAGES_MACOS` and `PACKAGES_LINUX_BREW`; the deprecated `tldr` left `PACKAGES_CORE` |

**simdjson** was never requested. It is a dependency of `node`, which `opencode` pulls in (and marp-cli did, until it was removed), and its install receipt says `installed_on_request: false`. It disappears on its own when nothing needs node.

## Every library formula is a dependency of something requested, and the doc now regenerates itself

Of 79 formulae installed after the review, 39 were requested and 40 came in as dependencies; none is orphaned. The full table lives in `docs/brew-formulae.md`, a generated file: `app-picker` rewrites it after every Brewfile write and every `--audit`, and `app-picker --deps` prints it. That is the auto-update: it refreshes whenever the machine's package state is being looked at. A timer was rejected because this repo deploys no user-level launchd jobs and a scheduled rewrite would leave uncommitted drift with nobody to commit it. The doc is linked from CLAUDE.md in one clause and is never loaded into agent context on its own. The ones Yulong asked about, traced to the requested tool that needs them:

| Formula | Needed by |
|---|---|
| abseil | mosh |
| ada-url, brotli, c-ares, fmt, hdrhistogram_c, libffi, libnghttp2, libnghttp3, libngtcp2, libuv | opencode (through node) |
| llhttp | opencode through node, and bat, eza, git-delta through libgit2 |
| libgit2, libssh2 | bat, eza, git-delta |
| jemalloc, libevent | tmux |
| gmp | coreutils, shellcheck |
| gettext, libunistring | direnv |
| lz4 | opencode, rsync |
| icu4c | opencode through node (installed as a versioned formula) |
| fpart, git-delta | requested directly: `PACKAGES_MACOS` in `config.sh` |

`brew autoremove` is the command that drops dependencies nobody needs any more; it removed nothing after the review because opencode still holds node.

## Decisions still open

- Run the seven cask uninstalls above. The registry already says they are gone; the audit will nag until the Mac agrees.
- Pick from the never-opened table; the fastest way is `app-picker --installed` in a terminal, deselect, then run the commands the audit prints.
- `mas-get` and the post-install check in `install.sh` still shell out to `mas list` and will hang the same way on this machine. They need a `timeout` or the receipt scan the audit uses. Not changed here.
- The `CLAUDE.md` learning from 2026-08-30 says this box has no Zotero installed; it does, via brew, never opened. Fix the line or remove the app.
- The keyboard-navigable verdicts and per-item comment boxes Yulong asked for in artifacts are filed as [issue 90](https://github.com/yulonglin/dotfiles/issues/90).

## Commands

```
app-picker --installed        # toggle what this Mac keeps; writes config/Brewfile and audits
app-picker --audit            # audit only, no writes
brew bundle --file=config/Brewfile
zsh tests/test_app_picker.zsh
```
