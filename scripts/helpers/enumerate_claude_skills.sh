#!/bin/bash

# ==============================================================================
# ENUMERATE CLAUDE SKILLS (with deduplication)
# Shared helper for sync scripts. Discovers all skill sources and deduplicates
# by name using first-wins priority ordering:
#   1. User skills (real directories in claude/skills/)
#   2. Standalone skill files (*.md directly in claude/skills/, not in dirs)
#   3. Plugin skills from marketplaces/ (canonical, git-cloned, always latest)
#   4. Plugin skills from cache/ai-safety-plugins/ (user's custom plugins)
#   5. Plugin skills from remaining cache/ dirs (versioned snapshots, may be stale)
#   6. Agent skills (claude/agents/*.md, wrapped as skills)
#
# Deduplication: Each skill name appears exactly once — first source wins.
# Shadowed skills emit warnings to stderr.
#
# Output format (tab-separated):
#   <type>\t<name>\t<path>
# Types: user_skill, plugin_skill, agent_skill, standalone_skill
# ==============================================================================

# Internal: emit all entries in priority order (may contain duplicates)
_enumerate_raw() {
    local claude_dir="${1:-$HOME/.claude}"

    # 1. User skills (real directories, not symlinks, not hidden)
    for skill in "$claude_dir/skills"/*/; do
        [ -d "$skill" ] || continue
        local name
        name=$(basename "$skill")
        [[ "$name" == .* ]] && continue
        # Skip ALL symlinks — plugin system creates runtime symlinks here
        [ -L "${skill%/}" ] && continue
        printf 'user_skill\t%s\t%s\n' "$name" "${skill%/}"
    done

    # 2. Standalone skill files (*.md directly in skills/, not SKILL.md pattern)
    for skill_file in "$claude_dir/skills"/*.md; do
        [ -f "$skill_file" ] || continue
        local name
        name=$(basename "$skill_file" .md)
        printf 'standalone_skill\t%s\t%s\n' "$name" "$skill_file"
    done

    # 3. Plugin skills from marketplaces/ (canonical — always latest)
    local marketplaces_dir="$claude_dir/plugins/marketplaces"
    if [ -d "$marketplaces_dir" ]; then
        find "$marketplaces_dir" -name "SKILL.md" -type f 2>/dev/null | while IFS= read -r skill_md; do
            local skill_dir name
            skill_dir=$(dirname "$skill_md")
            name=$(basename "$skill_dir")
            printf 'plugin_skill\t%s\t%s\n' "$name" "$skill_dir"
        done
    fi

    # 4. Plugin skills from cache/ai-safety-plugins/ (user custom plugins)
    local custom_mp_cache="$claude_dir/plugins/cache/ai-safety-plugins"
    if [ -d "$custom_mp_cache" ]; then
        find "$custom_mp_cache" -name "SKILL.md" -type f 2>/dev/null | while IFS= read -r skill_md; do
            local skill_dir name
            skill_dir=$(dirname "$skill_md")
            name=$(basename "$skill_dir")
            printf 'plugin_skill\t%s\t%s\n' "$name" "$skill_dir"
        done
    fi

    # 5. Plugin skills from remaining cache/ dirs (versioned, may be stale)
    local cache_dir="$claude_dir/plugins/cache"
    if [ -d "$cache_dir" ]; then
        for subdir in "$cache_dir"/*/; do
            [ -d "$subdir" ] || continue
            local subdir_name
            subdir_name=$(basename "$subdir")
            # Skip ai-safety-plugins (already handled above)
            [ "$subdir_name" = "ai-safety-plugins" ] && continue
            find "$subdir" -name "SKILL.md" -type f 2>/dev/null | while IFS= read -r skill_md; do
                local skill_dir name
                skill_dir=$(dirname "$skill_md")
                name=$(basename "$skill_dir")
                printf 'plugin_skill\t%s\t%s\n' "$name" "$skill_dir"
            done
        done
    fi

    # 6. Agent skills (claude/agents/*.md → can be wrapped as skills)
    for agent in "$claude_dir/agents"/*.md; do
        [ -f "$agent" ] || continue
        local name
        name=$(basename "$agent" .md)
        printf 'agent_skill\t%s\t%s\n' "$name" "$agent"
    done
}

# Public: enumerate with first-wins deduplication on skill name (column 2)
# Emits warnings to stderr for shadowed skills.
enumerate_claude_skills() {
    _enumerate_raw "$@" | awk -F'\t' '{
        if ($2 in seen) {
            # Warn about shadowed skill
            printf "⚠ Skill \"%s\" from %s shadowed by %s\n", $2, $3, seen[$2] > "/dev/stderr"
        } else {
            seen[$2] = $3
            print
        }
    }'
}

# Allow sourcing or direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    enumerate_claude_skills "$@"
fi
