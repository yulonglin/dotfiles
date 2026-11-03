-- Rex keybindings. Lives in dotfiles (config/rex/init.lua); deploy.sh --rex symlinks it to ~/.config/rex/init.lua.
-- UI layout prefs (sidebar, tabs, padding) are app defaults, not Lua: see config/rex/ui-prefs.tsv.
-- Migrated from tmux (~/.tmux.conf -> ~/code/dotfiles/config/tmux.conf) and Ghostty.
-- tmux prefix ctrl+b becomes the first key of each sequence.

-- Send ctrl+b itself through to programs that use it.
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })

-- tmux.conf:46-50 splits
rex.bind("ctrl+b>-", "pane.split", { direction = "down" })
rex.bind("ctrl+b>v", "pane.split", { direction = "down" })
rex.bind("ctrl+b>shift+\\", "pane.split", { direction = "right" })
rex.bind("ctrl+b>h", "pane.split", { direction = "right" })

-- tmux.conf:52 reload config
rex.bind("ctrl+b>r", "client.config.reload")

-- tmux.conf:59-62 resize panes with prefix + uiop
rex.bind("ctrl+b>u", "pane.resize", { amount = 5, direction = "up" })
rex.bind("ctrl+b>p", "pane.resize", { amount = 5, direction = "down" })
rex.bind("ctrl+b>i", "pane.resize", { amount = 5, direction = "left" })
rex.bind("ctrl+b>o", "pane.resize", { amount = 5, direction = "right" })
