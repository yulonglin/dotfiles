#!/usr/bin/env python3
import json
import os
import shutil
from pathlib import Path

# Configuration
DOTFILES_DIR = Path(os.path.expanduser("~/code/dotfiles"))
CLAUDE_SKILLS_DIR = DOTFILES_DIR / "claude/skills"
INSTALLED_PLUGINS_JSON = Path(os.path.expanduser("~/.claude/plugins/installed_plugins.json"))
MARKETPLACES_DIR = Path(os.path.expanduser("~/.claude/plugins/marketplaces"))

def load_installed_plugins():
    if not INSTALLED_PLUGINS_JSON.exists():
        print(f"Error: {INSTALLED_PLUGINS_JSON} not found.")
        return {}
    
    with open(INSTALLED_PLUGINS_JSON, 'r') as f:
        data = json.load(f)
    return data.get('plugins', {})

def find_stable_path(plugin_name, skill_name, current_path):
    """
    Attempts to find a stable path in the marketplaces directory.
    Returns the stable path if found, otherwise the current cache path.
    """
    # Heuristic: Check claude-plugins-official
    official_path = MARKETPLACES_DIR / "claude-plugins-official/plugins" / plugin_name / "skills" / skill_name
    if official_path.exists():
        return official_path
    
    # Check external_plugins in official repo (e.g. stripe)
    external_path = MARKETPLACES_DIR / "claude-plugins-official/external_plugins" / plugin_name / "skills" / skill_name
    if external_path.exists():
        return external_path

    return Path(current_path)

def import_skills():
    if not CLAUDE_SKILLS_DIR.exists():
        os.makedirs(CLAUDE_SKILLS_DIR, exist_ok=True)

    plugins = load_installed_plugins()
    print(f"Found {len(plugins)} installed plugins.")

    new_links_count = 0

    for plugin_key, installations in plugins.items():
        # plugin_key is like "plugin-name@registry"
        plugin_name = plugin_key.split('@')[0]
        
        # We generally care about the most recent installation
        if not installations:
            continue
            
        # Sort by installedAt (descending) to get latest
        latest_install = sorted(installations, key=lambda x: x['installedAt'], reverse=True)[0]
        install_path = Path(latest_install['installPath'])
        skills_dir = install_path / "skills"

        if not skills_dir.exists():
            continue

        print(f"Scanning skills for {plugin_name}...")
        
        try:
            for skill_item in skills_dir.iterdir():
                if skill_item.is_dir() or skill_item.suffix == '.md':
                    skill_name = skill_item.name
                    if skill_item.is_file():
                        # For single files, strip extension for the link name
                        link_name = f"{plugin_name}__{skill_item.stem}"
                    else:
                        link_name = f"{plugin_name}__{skill_name}"

                    target_link = CLAUDE_SKILLS_DIR / link_name

                    if target_link.exists():
                        # skip if already exists
                        continue

                    # Determine source path (prefer stable)
                    source_path = find_stable_path(plugin_name, skill_name, skill_item)
                    
                    print(f"  Linking {link_name} -> {source_path}")
                    os.symlink(source_path, target_link)
                    new_links_count += 1
        except PermissionError:
            print(f"  Permission denied accessing {skills_dir}")
        except Exception as e:
            print(f"  Error processing {plugin_name}: {e}")

    print(f"Import complete. Created {new_links_count} new links.")

if __name__ == "__main__":
    import_skills()
