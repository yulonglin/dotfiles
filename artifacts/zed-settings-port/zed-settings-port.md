# Zed Now Matches Cursor Where It Should And Diverges Where It Is Better

All decisions below are **applied and live** in `config/zed/settings.json`, which is symlinked to `~/.config/zed/settings.json`. Zed hot-reloads that file, so nothing needs restarting. Every setting was verified against Zed 1.17.2 before being written — twice I caught myself proposing a key that does not exist, and both corrections are recorded below rather than quietly dropped.

Sources read: `config/zed/settings.json`, `config/zed/keymap.json`, `~/Library/Application Support/Cursor/User/settings.json`, `config/vscode_settings.json`, `config/vscode_settings_ty.json`, `config/vscode_extensions.txt`, Zed's annotated defaults ([assets/settings/default.json](https://github.com/zed-industries/zed/blob/main/assets/settings/default.json)), the [Zed Python language docs](https://zed.dev/docs/languages/python), and the live extension registry at `api.zed.dev/extensions`

## Part 1 Is Done: The File Finder Has Its Own Key

The config already had `"search": { "include_ignored": true }`, but that key governs **project search** (cmd-shift-f) only. The command palette file finder (cmd-p) reads a separate key, `file_finder.include_ignored`, whose default is `"smart"` — documented as "be smart and search for ignored when called from a gitignored worktree". A normal repo is not itself gitignored, so `"smart"` silently skipped every gitignored file. That is the whole bug.

Applied to `config/zed/settings.json`:

```jsonc
"file_finder": {
  "include_ignored": "all"
}
```

The enum is `"all"` / `"indexed"` / `"smart"` — **not** `true`. Confirmed twice: in upstream `default.json`, and by `strings` on `/Applications/Zed.app/Contents/MacOS/zed`, which contains the literal line `"all": Use all gitignored files`, so the value is valid in the installed 1.17.2 and not a newer-version-only feature.

Your existing `file_scan_exclusions` still applies on top, so `.venv`, `node_modules`, `__pycache__`, `*.pyc`, `.cache` and `prompt_history` stay out of results. That pairing is why `"all"` is safe here rather than a flood.

To confirm: press cmd-p in `/Users/yulong/code/dotfiles` and type a filename under `tmp/` or `.remember/`. Zed hot-reloads `settings.json`, so no restart is needed.

### One Side Effect Worth Knowing About

Zed's default `file_scan_inclusions` is `[".env*"]`, meaning `.env` files are indexed even when gitignored. With `include_ignored: "all"` they will now appear in cmd-p results. No content leaks — `redact_private_values: true` is already set and `edit_predictions.disabled_globs` already covers `**/.env*` — but the filenames become visible in the picker. Say the word if you would rather I add `"**/.env*"` to `file_scan_exclusions` to hide them entirely.

## Editor Behaviour Ports Cleanly Except Three Conflicts

| Cursor / VSCode setting | Zed equivalent | Lean | Why |
|---|---|---|---|
| `editor.wordWrap: on` / `wordWrapColumn` | `soft_wrap: "editor_width"` | **ALREADY COVERED** | Already set globally |
| `editor.wrappingIndent: indent` | — | **SKIP** | No such Zed setting exists — I checked `default.json` and the 1.17.2 binary for `wrap_indent`/`wrapping_indent` and found nothing. Zed always aligns wrapped lines to the original indent |
| `files.trimTrailingWhitespace: false` | `remove_trailing_whitespace_on_save: false` | **ALREADY COVERED** | Already set |
| `editor.formatOnSave: false` | `format_on_save: "off"` | **ALREADY COVERED** | Already set globally, on per-language |
| `editor.formatOnSaveMode: "file"` | — | **SKIP** | Zed has no modified-lines-only mode; the VSCode value was already whole-file |
| `editor.accessibilitySupport: off` | — | **SKIP** | VSCode-specific screen-reader hint, no Zed analogue |
| `diffEditor.ignoreTrimWhitespace: false` | — | **SKIP** | No Zed setting; Zed's diff already respects whitespace |
| `diffEditor.hideUnchangedRegions.enabled` | — | **SKIP** | Zed multibuffer diffs collapse unchanged regions by default |
| `editor.multiCursorModifier: "alt"` | `multi_cursor_modifier` | **NEEDS YULONG'S CALL** | Direct conflict — see below |
| `editor.minimap.enabled: false` | `minimap.show` | **NEEDS YULONG'S CALL** | Direct conflict — see below |
| `files.autoSave: afterDelay` @ 100ms | `autosave` | **NEEDS YULONG'S CALL** | Direct conflict — see below |

## Python And Type-Checking Settings Mostly Have No Zed Equivalent

| Cursor / VSCode setting | Zed equivalent | Lean | Why |
|---|---|---|---|
| `[python].editor.wordWrap: wordWrapColumn` | `languages.Python.soft_wrap: "bounded"` | **PORT** | Wraps at `preferred_line_length` (100) or editor width, whichever is smaller — the exact analogue of `wordWrapColumn`. Note the value is `"bounded"`; there is no `"preferred_line_length"` value |
| `[python].editor.formatOnSave: false` | `languages.Python.format_on_save: "off"` | **ALREADY COVERED** | Already set |
| `[python].editor.defaultFormatter: ruff` | `languages.Python.formatter` | **PORT** | Zed currently falls back to the first language server; naming ruff makes it explicit |
| `[python].editor.formatOnType: true` | `languages.Python.use_on_type_format` | **PORT** | Matches Cursor; cheap and reversible |
| `isort.args: --profile black` | ruff's `I` rules in `pyproject.toml` | **SKIP** | Import sorting belongs in each repo's ruff config, not the editor |
| `python.languageServer: "None"` (Cursor) | `languages.Python.language_servers` | **NEEDS YULONG'S CALL** | Cursor disables Pylance in favour of `cursorpyright`; Zed is set to `["pyright", "ruff"]`. If `ty` is your direction, this list should say so |
| `python.analysis.autoImportCompletions` | — | **SKIP** | Pylance-specific; pyright in Zed has no equivalent knob exposed |
| `python.analysis.packageIndexDepths` (7 libs) | — | **SKIP** | Pylance-only indexing hint, no Zed or pyright-LSP surface |
| `mypy.runUsingActiveInterpreter` | — | **SKIP** | Extension-specific; Zed has no mypy integration |
| `ty.*` (9 keys in `vscode_settings_ty.json`) | `lsp.ty.initialization_options` | **NEEDS YULONG'S CALL** | Portable, but only worth doing if you want `ty` as a Zed language server alongside or instead of pyright |

## Jupyter And Notebook Settings Do Not Port At All

Zed's REPL is not a notebook editor — it evaluates code inline in a normal buffer rather than rendering `.ipynb` cells, so none of these five settings has a target.

| Cursor / VSCode setting | Zed equivalent | Lean | Why |
|---|---|---|---|
| `jupyter.runStartupCommands` (`%autoreload 2`) | — | **SKIP** | No Zed startup-command hook; put it in `~/.ipython/profile_default` instead so it applies everywhere |
| `jupyter.askForKernelRestart: false` | — | **SKIP** | No equivalent |
| `jupyter.notebookFileRoot` | — | **SKIP** | No equivalent |
| `jupyter.interactiveWindow.creationMode` | — | **SKIP** | No equivalent |
| `notebook.output.textLineLimit` / `wordWrap` / `formatOnSave` | — | **SKIP** | No equivalent |
| `launch` → `debugpy` remote attach on :5678 | `.zed/debug.json` per project | **NEEDS YULONG'S CALL** | Zed has a debugger with a `debugpy` adapter, but config is per-project, not global. Worth a one-off template if you still attach to remote runs |

## File Scanning Has A Real Gap Worth Closing

| Cursor / VSCode setting | Zed equivalent | Lean | Why |
|---|---|---|---|
| `files.exclude` (`.cache`, `.venv`, `.git`, `.DS_Store`) | `file_scan_exclusions` | **ALREADY COVERED** | All four present |
| `files.watcherExclude` (`prompt_history`, `.git/objects`) | `file_scan_exclusions` | **ALREADY COVERED** | `prompt_history` present; `.git` covers the rest |
| `search.exclude` | `file_scan_exclusions` | **ALREADY COVERED** | Zed uses one list for both |
| `search.useGlobalIgnoreFiles: false` | — | **PORT (as the fix already applied)** | This is the VSCode spelling of the same intent as `file_finder.include_ignored: "all"` |
| Zed default VCS globs dropped | `file_scan_exclusions` | **PORT** | Your list **replaces** Zed's default rather than extending it, silently losing `**/.jj`, `**/.sl`, `**/.repo`, `**/CVS`, `**/.classpath`, `**/.settings`. Re-adding the VCS ones costs nothing |
| `files.associations` (`*.plist`, `*.strings`) | `file_types.XML` | **ALREADY COVERED** | Already mapped — but see the `xml` extension row below |

## UI And Theme Are Already At Parity, With Two Cosmetic Gaps

| Cursor / VSCode setting | Zed equivalent | Lean | Why |
|---|---|---|---|
| `workbench.colorTheme: One Dark Pro` | `theme` | **ALREADY COVERED** | Set, with system light/dark switching |
| `window.autoDetectColorScheme` | `theme.mode: "system"` | **ALREADY COVERED** | Already set |
| `workbench.iconTheme: vscode-icons` | `icon_theme` | **ALREADY COVERED** | Material Icon Theme is the closest Zed equivalent |
| `vsicons.associations.folders` (11 custom folder icons) | — | **SKIP** | Zed icon themes cannot be extended per-folder from `settings.json`; would need a forked icon theme extension |
| `editor.fontFamily: Menlo` | `buffer_font_family` | **ALREADY COVERED** | Already Menlo |
| `window.zoomLevel: 1` | `ui_font_size` / `buffer_font_size` | **ALREADY COVERED** | 16pt already compensates |
| `workbench.sideBar.location: left` | `project_panel.dock: "left"` | **ALREADY COVERED** | Already left |
| `workbench.activityBar.orientation: vertical` | — | **SKIP** | Zed has no activity bar |
| `explorer.confirmDelete: false` | — | **SKIP** | Zed has no such confirmation to disable |
| `explorer.confirmDragAndDrop: false` | — | **SKIP** | Same |
| errorlens extension | `diagnostics.inline.enabled` | **PORT** | Inline diagnostics next to the code is one of your most-used Cursor extensions and is native in Zed |

## Git Settings Are Covered Except Autofetch

| Cursor / VSCode setting | Zed equivalent | Lean | Why |
|---|---|---|---|
| gitlens inline blame | `git.inline_blame` | **ALREADY COVERED** | Already on with 600ms delay |
| `git.autofetch: true` | — | **SKIP** | Zed has no autofetch setting; your shell already handles fetching |
| `git.openRepositoryInParentFolders: "never"` | — | **SKIP** | Zed opens the worktree you point it at, no parent-scan behaviour |
| `git_panel.dock: left` | — | **ALREADY COVERED** | Already set |

## Terminal And Remote Need Nothing New

| Cursor / VSCode setting | Zed equivalent | Lean | Why |
|---|---|---|---|
| `remote.SSH.remotePlatform` (4 hosts) | — | **SKIP** | Zed reads `~/.ssh/config` directly and infers the platform |
| `remote.SSH.maxReconnectionAttempts: 0` | — | **SKIP** | No equivalent |
| `remote.SSH.enableRemoteCommand` | — | **SKIP** | No equivalent |
| `remote.autoForwardPortsSource: hybrid` | — | **SKIP** | Zed forwards on demand |
| Terminal font, venv detection, option-as-meta | `terminal.*` | **ALREADY COVERED** | All three already set |
| `ssh_connections` duplicate `hn` entries | — | **LEAVE ALONE** | Zed's UI writes this array itself; hand-editing it gets overwritten, and the duplicates are harmless machine-local cruft |

## Five Extensions Were Added And csv Was Swapped For rainbow-csv

Every key in the paste-block below was verified against Zed 1.17.2 — two of my first-draft leans were wrong and are corrected above. All extension IDs were checked against the live Zed extension registry (`https://api.zed.dev/extensions`), so none is a guess. Your `auto_install_extensions` currently lists `one-dark-pro`, `ruff`, `toml`, `dockerfile`, `git-firefly`, `csv`, `just`, `html`.

| Cursor / VSCode extension | Zed extension ID | Lean | Why |
|---|---|---|---|
| `dnicolson.binary-plist`, `dotjoshjohnson.xml` | `xml` | **PORT** | Your `file_types` already maps `*.plist` and `*.strings` to XML, but without this extension there is no XML grammar to highlight them with |
| `james-yu.latex-workshop` | `latex` | **PORT** | You write papers in this repo's orbit |
| `mermaidchart.vscode-mermaid-chart` | `mermaid` | **PORT** | Diagrams in specs and artifacts |
| `davidanson.vscode-markdownlint` | `markdownlint` | **PORT** | Enforces the one-paragraph-one-line convention mechanically |
| — | `env` | **PORT** | `.env` files now surface in cmd-p after the Part 1 fix; syntax highlighting makes them readable |
| `mechatroner.rainbow-csv` | `rainbow-csv` | **APPLIED (swap)** | `rainbow-csv` supersedes plain `csv`, so the `csv` entry was removed rather than kept alongside. Removing the entry stops Zed reinstalling it but does not uninstall the copy already there — drop it from the extensions panel if you want it gone |
| `wakatime.vscode-wakatime` | `wakatime` | **SKIP** | Telemetry is off everywhere else in this config; porting time-tracking contradicts that |
| `Gruntfuggly.todo-tree`, `aaron-bond.better-comments`, `oderwat.indent-rainbow`, `johnpapa.vscode-peacock`, `alefragnani.project-manager` | — | **SKIP** | No Zed equivalents; `indent_guides` already covers indent-rainbow's main use |
| `eamodio.gitlens` | `git-firefly` + native blame | **ALREADY COVERED** | Both already in place |
| `redhat.vscode-yaml`, `esbenp.prettier-vscode`, `rust-lang.rust-analyzer` | built-in | **ALREADY COVERED** | Zed ships YAML, Rust and Prettier support without extensions |

## Five Zed-Native Settings Have No Cursor Counterpart But Are Worth Having

These come from Zed's own annotated defaults rather than from your Cursor config, so nothing prompts them during a straight port. Every default quoted below was read from `default.json` and re-checked against the installed 1.17.2 binary.

| Zed setting | Zed default | Lean | Why |
|---|---|---|---|
| `wrap_guides: [100]` | `[]` | **PORT** | `show_wrap_guides` is already `true` by default, but with an empty `wrap_guides` list nothing is drawn. Setting `[100]` gives you the vertical ruler at the same column as the `preferred_line_length: 100` you already run for Python and Rust |
| `use_smartcase_search: true` | `false` | **ALREADY COVERED** | Already set — worth naming because it is a non-default you would lose in a rewrite |
| `seed_search_query_from_cursor: "selection"` | `"always"` | **NEEDS YULONG'S CALL** | The default pre-fills the search box from the word under the cursor even with nothing selected, which overwrites a query you were about to retype. `"selection"` only seeds from a real selection. Mild preference, easy to revert |
| `confirm_quit: true` | `false` | **NEEDS YULONG'S CALL** | Zed quits without asking today. With `autosave: "on_focus_change"` nothing is lost, so this is purely about avoiding an accidental cmd-Q |
| `restore_on_startup` | `"last_session"` | **LEAVE ALONE** | Already restores all workspaces from the last session, which matches how you work across many repos and worktrees |
| `redact_private_values` | `false` | **ALREADY COVERED** | You have it `true`, which is the setting that keeps `.env` values hidden now that those files surface in cmd-p |

## The Three Conflicts Are Resolved, One Each Way

**Multi-cursor modifier — switched to `alt`.** The setting decides which modifier key, held while clicking, adds a second cursor; the *other* modifier then means go-to-definition. Zed was on `cmd_or_ctrl`, so cmd-click added a cursor and you had no cmd-click go-to-definition. Cursor and VSCode both use `alt`, and `base_keymap` was already `"VSCode"`, so the old value was fighting the keymap it was meant to match. Now: **alt-click adds a cursor, cmd-click jumps to definition** — same as Cursor. Revert by setting `"multi_cursor_modifier": "cmd_or_ctrl"`.

**Minimap — left on `"auto"`.** Cursor disables it outright. Zed's `"auto"` shows it only when a file is long enough to be worth scrubbing, which beats both always-on and always-off, and it carries no muscle memory.

**Autosave — left on `on_focus_change`.** Cursor saves 100ms after you stop typing. With `format_on_save` enabled for TypeScript, JavaScript and Rust, that would fire the formatter mid-edit and move your cursor. If you want faster saves without that, `{"after_delay": {"milliseconds": 1000}}` is the safe middle.

## Two Type Checkers Cannot Coexist, So ty Replaces Pyright Outright

You asked whether pyright could run alongside ty "if it doesn't interfere". It does interfere, and Zed's own configuration is the evidence: the shipped default for Python is

```jsonc
"language_servers": ["basedpyright", "ruff", "!ty", "!pyrefly", "!pyright", "!pylsp", "..."]
```

The `!` prefix disables a server, so Zed enables exactly one type checker and explicitly switches off the other four. Zed's Python documentation makes the same move in its own worked example — enabling `ty` there is paired with `"!basedpyright"` in the same list. The reason is that two type checkers both publish diagnostics for the same lines, so you get every error twice, from two engines that disagree at the edges.

So the answer is pick one, and ty is now the one:

```jsonc
"language_servers": ["ty", "ruff", "!basedpyright", "!pyright", "!pylsp"]
```

Three things worth knowing about this. **ty, pyright, basedpyright and pylsp are all built into Zed** — none needs an extension, which is why none was added to `auto_install_extensions`. **The list is explicit rather than ending in `"..."`**, because that wildcard re-enables every remaining registered server, which would put pyright back and undo the point. **ty is pre-1.0 and still alpha** — the version number I can see is the registry extension's, not the built-in server's, so I am not quoting it — and if go-to-definition or completions feel thin, swap `"ty"` and `"!basedpyright"` in that list and you are back on Zed's default in one edit.

Your previous value was `["pyright", "ruff"]`, which was already off Zed's default in a way that cost you something: plain pyright lacks the inlay-hint support basedpyright and ty have, so the `inlay_hints: { "enabled": true }` you had set was only partly doing anything. Moving to ty fixes that as a side effect.

The nine `ty.*` keys in `config/vscode_settings_ty.json` were **not** ported. They are VSCode-extension plumbing — `ty.trace.server`, `ty.logLevel`, `ty.importStrategy` — not LSP initialization options, and porting them into an `lsp.ty` block untested is exactly the invented-key mistake this document already caught twice. They are easy to add later if ty misbehaves.

## The Debugger Template And The env Rows Were Left Alone

The `debugpy` remote-attach launch config on port 5678 was **not** ported. Zed does ship a debugpy adapter, but its configuration is per-project in `.zed/debug.json` rather than global, so a template only pays off if you are still attaching to remote runs. Say the word and it takes one file.

`.env` files are now hidden from cmd-p, via two globs added to `file_scan_exclusions`. Zed's default `file_scan_inclusions` is `[".env*"]`, which force-indexes them even though they are gitignored, and Part 1 then makes indexed-but-ignored files reachable — so the exclusion is the only thing that actually hides them, since `file_scan_exclusions` takes precedence over inclusions.

The globs are `"**/.env"` and `"**/.env.*"`, deliberately **not** the obvious `"**/.env*"`. That single-glob version also matches `.envrc`, which is direnv configuration you write by hand and need to keep reachable — it is not a secret, it is the file that *fetches* secrets from Bitwarden. Checked across `~/code`: zero `.env` files exist and exactly one `.envrc` does, so the one-character difference between those globs is the entire practical effect of this change.

One consequence worth naming: `file_scan_exclusions` means "excluded by Zed entirely", so an excluded file also disappears from the project file tree. `.env.example` matches `**/.env.*` and is hidden too, despite usually being a safe committed template. None exist today; if one appears and you want it back, narrow the second glob to `"**/.env.local"` and `"**/.env.*.local"`.

## What Was Actually Written To settings.json

Merged into the existing keys rather than appended, so there are no duplicates. This is a record of what is live, not a block to paste.

```jsonc
{
  // Part 1: the finder has its own key, separate from `search`
  "file_finder": { "include_ignored": "all" },

  // alt-click adds a cursor; cmd-click becomes go to definition (Cursor parity)
  "multi_cursor_modifier": "alt",

  // Native replacement for the errorlens extension (Zed default is false)
  "diagnostics": { "inline": { "enabled": true } },

  // show_wrap_guides is already true, but the guide list is empty by default,
  // so no ruler is drawn until a column is named here
  "wrap_guides": [100],

  // Re-adds the six Zed default VCS globs this list was silently replacing,
  // and hides .env from cmd-p without catching .envrc
  "file_scan_exclusions": [
    "**/.git", "**/.svn", "**/.hg", "**/.jj", "**/.sl", "**/.repo",
    "**/CVS", "**/.classpath", "**/.settings",
    "**/.DS_Store", "**/Thumbs.db", "**/.cache", "**/.venv",
    "**/node_modules", "**/__pycache__", "**/*.pyc", "**/prompt_history",
    "**/.env", "**/.env.*"
  ],

  // csv swapped for rainbow-csv; five added
  "auto_install_extensions": {
    "one-dark-pro": true, "ruff": true, "toml": true, "dockerfile": true,
    "git-firefly": true, "rainbow-csv": true, "just": true, "html": true,
    "xml": true, "latex": true, "mermaid": true, "markdownlint": true, "env": true
  },

  "languages": {
    "Python": {
      "tab_size": 4,
      "format_on_save": "off",
      "preferred_line_length": 100,
      "soft_wrap": "bounded",
      "use_on_type_format": true,
      "formatter": { "language_server": { "name": "ruff" } },
      "language_servers": ["ty", "ruff", "!basedpyright", "!pyright", "!pylsp"]
    }
  }
}
```

## Every Question Is Answered, And Two Of Them Needed No Change

| Question | Answer | Reversible by |
|---|---|---|
| Multi-cursor `alt` vs `cmd_or_ctrl` | `alt`, matching Cursor and the VSCode base keymap | one key |
| Minimap, autosave | Both left on Zed's behaviour | one key each |
| `ty` alongside pyright | Not possible — ty replaces it, pyright and basedpyright disabled | swap two list entries |
| `debugpy` remote attach | Not ported; needs a per-project `.zed/debug.json` if still used | new file |
| `csv` vs `rainbow-csv` | Swapped to `rainbow-csv` | one key |
| `.env*` visible in cmd-p | Hidden — `**/.env` and `**/.env.*`, chosen so `.envrc` stays reachable | two globs |
| `confirm_quit` | Left `false` — unsaved buffers are restored on restart, so nothing can be lost | one key |
| `seed_search_query_from_cursor` | Left `"always"` — the seeded text is selected, so typing replaces it | one key |

Both of the rows I had failed to ask about are now settled, and neither needed a change.

**`confirm_quit` stays `false`.** Your condition was "unless we'll delete unsaved work", and Zed does not: `session.restore_unsaved_buffers` defaults to `true`, documented as "if this is true, user won't be prompted whether to save/discard dirty files when closing the application". Unsaved buffers survive the quit and come back on restart. That is precisely *why* Zed ships `confirm_quit: false` — the prompt would guard against a loss that cannot happen. Combined with `autosave: "on_focus_change"` and `restore_on_startup: "last_session"`, there are three independent reasons quitting is safe.

**`seed_search_query_from_cursor` stays `"always"`.** It controls what the search box is pre-filled with when you open it: `"always"` seeds it with the word under the cursor, `"selection"` only with a real selection, `"never"` leaves it empty. My earlier objection was that `"always"` overwrites a query you were about to type — but the pre-filled text arrives selected, so typing replaces it in one keystroke. Not worth a non-default.

## Two Of My Own Recommendations Were Wrong And Were Caught Before Shipping

Recording these because the failure mode they represent — a plausible-looking setting key that does not exist — survives review easily and breaks silently, since Zed ignores unknown keys rather than erroring.

`preserve_wrap_indent` was in my first draft as the port of Cursor's `editor.wrappingIndent`. **No such setting exists.** Grepping `default.json` and the 1.17.2 binary for `wrap_indent` and `wrapping_indent` returns nothing; Zed always aligns wrapped lines to the original indent, so there was nothing to configure.

`"soft_wrap": "preferred_line_length"` was my first draft's Python wrap value. **The valid values are `"none"`, `"editor_width"` and `"bounded"`** — the analogue of Cursor's `wordWrapColumn` is `"bounded"`, which wraps at `preferred_line_length` or the editor width, whichever is smaller. That is what was written.

## 2026-09-03: The Port Was Pruned To An Overlay On Zed's Defaults

A key-by-key diff of the file above against Zed 1.17.2's upstream `assets/settings/default.json` found 18 lines that restated a default, one key that no longer exists (`notification_panel`), one no-op (`terminal.detect_venv` was the default list reordered), and two overrides that *shrank* a default list rather than extending it: `edit_predictions.disabled_globs` had dropped `*.pem`, `*.key`, `*.cert`, `*.crt` and `secrets.yml`, and `file_types.JSONC` had dropped `.vscode/**/*.json`. All were removed or restored, and `theme` keeps all three keys because it is a whole-object field. The file is now 355 → 271 lines, most of the remainder being the machine-owned `ssh_connections` block, which was preserved byte-for-byte.

Which settings the community actually changes was measured rather than guessed: 87 public `zed/settings.json` files from GitHub code search were parsed and every key counted against the 1.17.2 default. The sample was found by searching for `base_keymap`, so the sample skews toward editor-switchers, who override more; treat the rates as an upper bound. Beyond what this file already had, the overrides that recur are `vim_mode: true` (60%), `telemetry` off (53%), `autosave: "on_focus_change"` (31%), `tabs.git_status` and `tabs.file_icons` (16–20%). The last two were added; `vim_mode` was not, as it conflicts with the deliberate VSCode keymap. The `biome` extension (0.3.1 in the registry) was added with `lsp.biome.settings.require_config_file: true`, so it only runs in projects that ship a `biome.json`; it was deliberately not set as a global TypeScript formatter, because what Zed does on save when a named formatter's server is not running was not verified — Biome's own Zed reference shows that setting per-project in `.zed/settings.json`. The `ty`-over-basedpyright decision from the section above stands.

Two things a reader should know. `edit_predictions.disabled_globs` and `file_scan_exclusions` *replace* Zed's default list rather than merging with it, so each restates the defaults before adding to them; `file_types` merges per key, but each key's array replaces, which is why the shrunken `JSONC` entry was dropped and only `XML` kept. And `WebFetch` hangs indefinitely inside a sandboxed `claude -p` child while `curl` from the same sandbox works — two ten-minute research runs died on this before it was isolated; the fix is `dangerouslyDisableSandbox` for that one process. Scripts: `tmp/zed-research/{jsonc_diff,community_freq}.py`.
