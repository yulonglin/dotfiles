# aliases/editors.sh — quick-open aliases for dotfiles, editor shortcuts

# Quick open in editor (functions instead of aliases so zsh-syntax-highlighting recognizes them)
edit-dotfiles()  { ${=EDITOR} "$DOT_DIR"; }
edit-aliases()   { ${=EDITOR} "$DOT_DIR/config/aliases/"; }
edit-ssh()       { ${=EDITOR} ~/.ssh/config; }
edit-claude()    { ${=EDITOR} "$DOT_DIR/claude/settings.json"; }
edit-profiles()  { ${=EDITOR} "$DOT_DIR/claude/templates/contexts/profiles.yaml"; }
edit-voiceink()  { ${=EDITOR} "$DOT_DIR/config/transcription/voiceink/macOS/prompts/"; }
