# Zed Editor Settings Research

## Summary

Comprehensive research on sane default Zed editor settings, mapping from existing VSCode/Cursor config and incorporating Zed-specific features.

## 1. VSCode-to-Zed Setting Mapping

| VSCode Setting | Zed Equivalent | Notes |
|---|---|---|
| `files.autoSave: "afterDelay"` + `100ms` | `"autosave": { "after_delay": { "milliseconds": 100 } }` | Zed supports `"off"`, `"on_focus_change"`, `"on_window_change"`, `{"after_delay": {"milliseconds": N}}` |
| `editor.multiCursorModifier: "alt"` | `"multi_cursor_modifier": "alt"` | Same. Also supports `"cmd_or_ctrl"` |
| `git.autofetch: true` | **No equivalent** | Zed has no `git.autofetch`. Git integration is built-in but limited to gutter/blame/diff. No background fetch |
| `editor.minimap.enabled: false` | `"minimap": { "show": "never" }` | Options: `"never"`, `"always"`, `"auto"` (shows on scroll) |
| `editor.wordWrap: "wordWrapColumn"` | `"soft_wrap": "preferred_line_length"` | Options: `"none"`, `"editor_width"`, `"preferred_line_length"`, `"bounded"`. Use with `"preferred_line_length": 80` |
| `files.trimTrailingWhitespace: false` | `"remove_trailing_whitespace_on_save": false` | Default is `true` in Zed |
| `editor.formatOnSave: false` | `"format_on_save": "off"` | Default is `"on"` in Zed |
| `search.useIgnoreFiles: false` / `search.useGlobalIgnoreFiles: false` | `"search": { "include_ignored": true }` | This includes gitignored files in project search |
| `files.exclude` patterns | `"file_scan_exclusions": [...]` | Glob patterns. Default includes `.git`, `.svn`, `.DS_Store`, etc. |
| `editor.fontFamily: "Menlo, ..."` | `"buffer_font_family": "Menlo"` | Zed accepts a single font family string, not a fallback list |
| `diffEditor.hideUnchangedRegions.enabled: true` | `"diff_view_style": "split"` | Zed has `"split"` or `"inline"` diff. No "hide unchanged" toggle yet |
| `editor.wrappingIndent: "indent"` | **No direct equivalent** | Zed's soft wrap does not have a wrapping indent option |
| `editor.accessibilitySupport: "off"` | **No equivalent needed** | Zed doesn't have an accessibility performance mode toggle |
| `telemetry: disabled` | `"telemetry": { "diagnostics": false, "metrics": false }` | Disables crash reports + usage metrics |
| `workbench.colorTheme: "One Dark Pro"` | `"theme": { "mode": "system", "dark": "One Dark Pro", "light": "One Light" }` | Requires installing "One Dark Pro" extension. `"mode": "system"` auto-switches with OS |
| `files.watcherExclude` | Part of `"file_scan_exclusions"` | Zed combines file scanning and watching exclusions |
| `search.exclude` | Part of `"file_scan_exclusions"` | Combined with file scan exclusions |

## 2. Recommended settings.json

```jsonc
// ~/.config/zed/settings.json
{
  // === Theme & Appearance ===
  "theme": {
    "mode": "system",
    "dark": "One Dark Pro",
    "light": "One Light"
  },
  "icon_theme": "VSCode Icons for Zed (Dark Angular)",
  "ui_font_size": 15,
  "buffer_font_family": "Menlo",
  "buffer_font_size": 15,
  "buffer_font_weight": 400,
  "buffer_line_height": "comfortable",

  // === Editor Behavior ===
  "base_keymap": "VSCode",
  "vim_mode": false,
  "autosave": {
    "after_delay": {
      "milliseconds": 100
    }
  },
  "format_on_save": "off",
  "remove_trailing_whitespace_on_save": false,
  "ensure_final_newline_on_save": true,
  "multi_cursor_modifier": "alt",
  "soft_wrap": "preferred_line_length",
  "preferred_line_length": 100,
  "tab_size": 4,
  "hard_tabs": false,
  "auto_indent_on_paste": true,
  "confirm_quit": false,
  "cursor_blink": true,
  "cursor_shape": "bar",
  "extend_comment_on_newline": true,
  "use_autoclose": true,
  "linked_edits": true,

  // === Display ===
  "current_line_highlight": "all",
  "show_whitespaces": "selection",
  "minimap": {
    "show": "never"
  },
  "scrollbar": {
    "show": "auto",
    "cursors": true,
    "git_diff": true,
    "search_results": true,
    "selected_text": true,
    "diagnostics": true
  },
  "gutter": {
    "line_numbers": true,
    "folds": true,
    "runnables": true,
    "breakpoints": true
  },
  "indent_guides": {
    "enabled": true,
    "line_width": 1,
    "active_line_width": 1,
    "coloring": "fixed"
  },
  "show_wrap_guides": true,
  "wrap_guides": [100],
  "scroll_beyond_last_line": "one_page",

  // === Search ===
  "search": {
    "include_ignored": true,
    "regex": false,
    "case_sensitive": false,
    "whole_word": false
  },
  "use_smartcase_search": true,
  "seed_search_query_from_cursor": "always",

  // === File Scanning ===
  "file_scan_exclusions": [
    "**/.git",
    "**/.svn",
    "**/.hg",
    "**/.jj",
    "**/.DS_Store",
    "**/Thumbs.db",
    "**/.classpath",
    "**/.settings",
    "**/.cache",
    "**/.venv",
    "**/node_modules",
    "**/__pycache__",
    "**/*.pyc",
    "**/prompt_history"
  ],
  "file_scan_inclusions": [
    ".env*",
    ".claude/**"
  ],

  // === Git ===
  "git": {
    "git_gutter": "tracked_files",
    "inline_blame": {
      "enabled": true,
      "delay_ms": 600,
      "show_commit_summary": true,
      "min_column": 40
    },
    "hunk_style": "staged_hollow"
  },

  // === Diff ===
  "diff_view_style": "split",

  // === Completions & Intelligence ===
  "show_completions_on_input": true,
  "show_completion_documentation": true,
  "inlay_hints": {
    "enabled": true,
    "show_type_hints": true,
    "show_parameter_hints": false,
    "show_other_hints": true,
    "show_background": true
  },

  // === Edit Predictions (Zeta - Zed's native AI completion) ===
  "show_edit_predictions": true,
  "edit_predictions": {
    "mode": "eager",
    "disabled_globs": [
      "**/.env*",
      "**/secrets*"
    ]
  },

  // === AI / Agent ===
  "agent": {
    "dock": "right",
    "default_model": {
      "provider": "zed.dev",
      "model": "claude-sonnet-4-5"
    },
    "inline_alternatives": [
      {
        "provider": "zed.dev",
        "model": "claude-sonnet-4-5"
      }
    ]
  },

  // === Telemetry (disabled) ===
  "telemetry": {
    "diagnostics": false,
    "metrics": false
  },

  // === Terminal ===
  "terminal": {
    "shell": "system",
    "dock": "bottom",
    "working_directory": "current_project_directory",
    "cursor_shape": "bar",
    "blinking": "terminal_controlled",
    "option_as_meta": true,
    "copy_on_select": false,
    "font_family": "Menlo",
    "font_size": 14,
    "line_height": "comfortable",
    "detect_venv": {
      "on": {
        "directories": [".venv", "venv", ".env", "env"],
        "activate_script": "default"
      }
    },
    "toolbar": {
      "breadcrumbs": true
    }
  },

  // === Panels ===
  "project_panel": {
    "dock": "left"
  },
  "outline_panel": {
    "dock": "right"
  },
  "notification_panel": {
    "dock": "left"
  },

  // === Session ===
  "restore_on_startup": "last_session",
  "session": {
    "restore_unsaved_buffers": true
  },
  "auto_update": true,

  // === Language Overrides ===
  "languages": {
    "Python": {
      "tab_size": 4,
      "format_on_save": "off",
      "preferred_line_length": 100,
      "language_servers": ["pyright", "ruff"]
    },
    "TypeScript": {
      "tab_size": 2,
      "format_on_save": "on",
      "formatter": "language_server"
    },
    "JavaScript": {
      "tab_size": 2,
      "format_on_save": "on"
    },
    "JSON": {
      "tab_size": 2
    },
    "JSONC": {
      "tab_size": 2
    },
    "YAML": {
      "tab_size": 2
    },
    "Markdown": {
      "soft_wrap": "editor_width",
      "show_edit_predictions": false
    },
    "Rust": {
      "tab_size": 4,
      "format_on_save": "on",
      "formatter": "language_server",
      "preferred_line_length": 100
    }
  },

  // === File Types ===
  "file_types": {
    "JSONC": ["**/.zed/**/*.json", "tsconfig.json", "tsconfig.*.json"]
  }
}
```

## 3. Recommended keymap.json

```jsonc
// ~/.config/zed/keymap.json
[
  // Cmd+K for inline AI assist (VSCode-style)
  {
    "context": "Editor && mode == full",
    "bindings": {
      "cmd-k": "assistant::InlineAssist"
    }
  },
  // Quick save (redundant with autosave, but muscle memory)
  {
    "context": "Editor",
    "bindings": {
      "cmd-s": "workspace::Save"
    }
  },
  // Toggle terminal
  {
    "context": "Workspace",
    "bindings": {
      "ctrl-`": "workspace::ToggleBottomDock"
    }
  }
]
```

**Important note on Cmd+K:** Zed uses `cmd-k` as a chord prefix (e.g., `cmd-k cmd-s` opens keymap). Rebinding `cmd-k` directly to inline assist will break all `cmd-k <X>` chord keybindings. Two alternatives:

1. **Use `ctrl-enter`** (Zed's default for inline assist) — no conflicts
2. **Use `cmd-i`** — commonly used in other editors for inline AI, no conflict with Zed defaults
3. **Use `cmd-k cmd-k`** — a double-tap chord that preserves other `cmd-k <X>` bindings:
   ```json
   {
     "context": "Editor && mode == full",
     "bindings": {
       "cmd-k cmd-k": "assistant::InlineAssist"
     }
   }
   ```

## 4. Zed-Specific Features Worth Enabling (No VSCode Equivalent)

| Feature | Setting | Why |
|---|---|---|
| **Edit Predictions (Zeta)** | `"show_edit_predictions": true` | Zed's native AI completion model, predicts multi-line edits. Free tier: 2000/month, Pro: unlimited |
| **Inline Blame** | `"git.inline_blame.enabled": true` | Shows git blame inline (like GitLens but built-in) |
| **Semantic Tokens** | `"semantic_tokens": "combined"` | Richer syntax highlighting via LSP. Options: `"off"`, `"combined"`, `"full"` |
| **Smartcase Search** | `"use_smartcase_search": true` | Auto case-sensitive when query has uppercase (vim-style) |
| **System Theme Switching** | `"theme.mode": "system"` | Auto dark/light based on OS appearance |
| **Auto-install Extensions** | `"auto_install_extensions": {...}` | Declaratively install extensions |
| **Python venv Detection** | `"terminal.detect_venv"` | Auto-activates Python virtualenvs in terminal |
| **Option as Meta** | `"terminal.option_as_meta": true` | macOS: Option key works as Meta in terminal (for emacs bindings, tmux) |
| **Linked Edits** | `"linked_edits": true` | Edit matching HTML tags simultaneously |
| **Runnables** | `"gutter.runnables": true` | Run tests/scripts from gutter icons |
| **Breakpoints** | `"gutter.breakpoints": true` | Built-in debugger support |
| **LSP Document Colors** | `"lsp_document_colors": "inlay"` | Shows CSS colors inline |

## 5. Extensions to Install

Add to settings.json for declarative installation:

```json
"auto_install_extensions": {
  "one-dark-pro": true,
  "ruff": true,
  "toml": true,
  "dockerfile": true,
  "git-firefly": true,
  "csv": true,
  "just": true,
  "html": true
}
```

## 6. Search Settings — Including Gitignored Files

The key setting is:
```json
"search": {
  "include_ignored": true
}
```

This makes project-wide search (Cmd+Shift+F) include files that are in `.gitignore`. Combined with `file_scan_inclusions`, this gives you full visibility.

**For adding external directories to search scope:** Zed uses the concept of "worktrees" — you add folders to your workspace via `File > Add Folder to Project` or `zed <dir1> <dir2>` from CLI. There's no `search.additionalDirectories` setting.

## 7. Settings File Location

- macOS: `~/.config/zed/settings.json`
- Linux: `~/.config/zed/settings.json` (or `$XDG_CONFIG_HOME/zed/settings.json`)
- Keymap: `~/.config/zed/keymap.json`

## 8. Notable Differences from VSCode

1. **No git autofetch** — Zed doesn't background-fetch git remotes
2. **No wrapping indent control** — soft wrap doesn't have indent options
3. **No font fallback chains** — single `buffer_font_family` string
4. **No files.watcherExclude** — combined into `file_scan_exclusions`
5. **No search.exclude** — combined into `file_scan_exclusions`
6. **No accessibility toggle** — not needed (Zed is performant by default)
7. **Telemetry** — only 2 toggles (diagnostics + metrics), not the granular VSCode telemetry
8. **Extensions** — installed via command palette or `auto_install_extensions`, not a marketplace CLI
9. **Diff editor** — `"split"` or `"inline"` only, no "hide unchanged regions"
10. **Format on save** — `"on"` or `"off"` only (no `"modifications"` mode)

## Sources

- [Zed All Settings Reference](https://zed.dev/docs/reference/all-settings)
- [Zed Configuring Zed](https://zed.dev/docs/configuring-zed)
- [Zed Telemetry](https://zed.dev/docs/telemetry)
- [Zed Edit Prediction](https://zed.dev/docs/ai/edit-prediction)
- [Zed Inline Assistant](https://zed.dev/docs/ai/inline-assistant)
- [Zed Key Bindings](https://zed.dev/docs/key-bindings)
- [Zed Terminal](https://zed.dev/docs/terminal)
- [Zed Themes](https://zed.dev/docs/themes)
- [Zed Default Settings (GitHub)](https://github.com/zed-industries/zed/blob/main/assets/settings/default.json)
- [jellydn/zed-101-setup](https://github.com/jellydn/zed-101-setup)
- [HitBlast - Zed Daily Driving Config](https://dev.to/hitblast/how-i-configured-the-zed-editor-for-daily-driving-4k2k)
- [PanKUN Blog - Recommended Settings](https://breadmotion.github.io/WebSite/blog/en/blog_00023.html)
- [One Dark Pro Zed Extension](https://zed.dev/extensions/one-dark-pro)
