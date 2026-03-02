# Automatic File Cleanup

Automatically clean up old files from `~/Downloads` and `~/Screenshots` by moving them to trash after a configurable retention period.

## Features

- **Cross-platform**: Works on macOS (launchd) and Linux (cron)
- **Safe defaults**: 180-day (6 months) retention period
- **Dry run mode**: Preview what would be deleted before committing
- **Configurable**: Adjust retention period and schedule
- **Smart cleanup**: Only removes files that haven't been accessed OR modified in the retention period

## Quick Start

### 1. Test the cleanup script (dry run)

```bash
./cleanup_old_files.sh --dry-run
```

This shows what files would be deleted without actually deleting them.

### 2. Run manual cleanup

```bash
./cleanup_old_files.sh
```

### 3. Install automatic cleanup

```bash
./install.sh
```

This sets up a scheduled job that runs monthly by default.

### 4. Uninstall automatic cleanup

```bash
./uninstall.sh
```

## Usage

### Manual Cleanup

```bash
# Preview cleanup (recommended first run)
./cleanup_old_files.sh --dry-run

# Run cleanup with default settings (180 days)
./cleanup_old_files.sh

# Custom retention period (90 days)
./cleanup_old_files.sh --days 90

# Using environment variable
RETENTION_DAYS=30 ./cleanup_old_files.sh
```

### Automatic Cleanup Installation

```bash
# Install with defaults (180 days, monthly)
./install.sh

# Custom retention period
./install.sh --days 90

# Custom schedule
./install.sh --schedule weekly

# Non-interactive (skip confirmation)
./install.sh -y

# Combine options
./install.sh --days 90 --schedule weekly -y
```

**Schedule options:**
- `daily` - Run every day at 2 AM
- `weekly` - Run every Sunday at 2 AM
- `monthly` - Run on the 1st of each month at 2 AM (default)

### Uninstallation

```bash
# Uninstall with prompts
./uninstall.sh

# Non-interactive uninstall
./uninstall.sh -y
```

## Configuration

### Retention Period

The default retention period is **180 days** (6 months). Files are only deleted if:
- They haven't been **accessed** in the retention period AND
- They haven't been **modified** in the retention period

You can change the retention period:
- During installation: `./install.sh --days 90`
- During manual runs: `./cleanup_old_files.sh --days 90`
- Using environment variable: `RETENTION_DAYS=90 ./cleanup_old_files.sh`

### Directories Cleaned

Currently configured to clean:
- `~/Downloads`
- `~/Screenshots`

To add more directories, edit `cleanup_old_files.sh` and add calls to `clean_directory()`.

## Integration with Dotfiles

You can optionally enable cleanup during dotfiles deployment:

```bash
# Deploy dotfiles with cleanup enabled
./deploy.sh --cleanup

# Or enable later
./scripts/cleanup/install.sh
```

## Logs

### macOS (launchd)
- **Standard output**: `~/Library/Logs/cleanup-old-files.log`
- **Errors**: `~/Library/Logs/cleanup-old-files.error.log`

### Linux (cron)
- **Combined output**: `~/.cleanup-old-files.log`

### Viewing logs

```bash
# macOS
tail -f ~/Library/Logs/cleanup-old-files.log

# Linux
tail -f ~/.cleanup-old-files.log
```

## Checking Job Status

### macOS
```bash
# List all LaunchAgents
launchctl list | grep cleanup

# Check if job is loaded
launchctl list com.user.cleanup-old-files
```

### Linux
```bash
# View crontab
crontab -l | grep cleanup
```

## Safety Features

1. **Dual time check**: Files must be old by BOTH access time AND modification time
2. **Dry run mode**: Always test before actual deletion
3. **Trash, not delete**: Files are moved to trash, not permanently deleted
4. **Shallow search**: Only cleans files in the top level of specified directories (no recursion)
5. **File type only**: Only processes files, not directories

## Examples

### Conservative Cleanup (1 year retention)
```bash
./install.sh --days 365 --schedule monthly
```

### Aggressive Cleanup (30 days, weekly)
```bash
./install.sh --days 30 --schedule weekly
```

### One-time Cleanup Before Travel
```bash
# Preview
./cleanup_old_files.sh --days 90 --dry-run

# Execute
./cleanup_old_files.sh --days 90
```

## Troubleshooting

### Permission denied
```bash
chmod +x cleanup_old_files.sh install.sh uninstall.sh
```

### Job not running (macOS)
```bash
# Check logs
cat ~/Library/Logs/cleanup-old-files.error.log

# Reload job
launchctl unload ~/Library/LaunchAgents/com.user.cleanup-old-files.plist
launchctl load ~/Library/LaunchAgents/com.user.cleanup-old-files.plist
```

### Job not running (Linux)
```bash
# Check logs
tail ~/.cleanup-old-files.log

# Verify crontab
crontab -l | grep cleanup

# Check cron service
systemctl status cron  # or 'crond' on some systems
```

## Advanced Configuration

### Custom Directories

Edit `cleanup_old_files.sh` and add your directories:

```bash
# Add after existing clean_directory calls
clean_directory "$HOME/Desktop/temp" "Desktop Temp"
clean_directory "$HOME/Documents/old-projects" "Old Projects"
```

### Different Retention Periods per Directory

Modify the `clean_directory` function to accept a retention parameter, or create separate cleanup scripts.

## Security Considerations

- Scripts are user-level only (no sudo required)
- Only affects your home directory
- Files moved to trash, not permanently deleted
- Logs contain file paths (review before sharing)

## AI Tools Auto-Update

Daily scheduled job (6:00 AM) that updates Claude Code, Gemini CLI, and Codex CLI.

### Features

- **Manager selection**: Uses brew on macOS and bun on Linux for Gemini/Codex updates
- **`claude update`**: Works universally regardless of Claude Code install method
- **Lock file**: Prevents concurrent runs with PID-based stale lock detection
- **`--dry-run`**: Preview what would be updated without executing
- **PATH setup**: Handles minimal launchd/cron PATH by sourcing brew and adding common paths
- **Linux bootstrap**: `setup_ai_update.sh` installs bun automatically if missing

### Manual Usage

```bash
# Preview updates
update-ai-tools --dry-run

# Run updates
update-ai-tools
# Or use the alias:
ai-update
```

### Setup / Uninstall

```bash
# Install scheduled job
scripts/cleanup/setup_ai_update.sh

# Uninstall scheduled job
scripts/cleanup/setup_ai_update.sh --uninstall
```

### Logs

- **macOS**: `~/Library/Logs/com.user.update-ai-tools.log`
- **Linux**: `~/.update-ai-tools.log`

### Checking Job Status

```bash
# macOS
launchctl list | grep update-ai-tools

# Linux
crontab -l | grep update-ai-tools
```

## System Package Auto-Update

Weekly scheduled job (Sunday 5:00 AM) that detects the system package manager and runs update + upgrade + cleanup.

### Supported Package Managers

| Manager | Platform | Update | Upgrade | Cleanup |
|---------|----------|--------|---------|---------|
| **brew** | macOS | `brew update` | `brew upgrade` | `brew cleanup --prune=30` |
| **apt** | Debian/Ubuntu | `apt update` | `apt upgrade -y` | `apt autoremove -y` |
| **dnf** | Fedora/RHEL | (included) | `dnf upgrade -y` | `dnf autoremove -y` |
| **pacman** | Arch | (included) | `pacman -Syu` | — |

### Features

- **Cross-platform**: Auto-detects brew, apt, dnf, or pacman
- **Lock file**: Prevents concurrent runs with PID-based stale lock detection
- **`--dry-run`**: Preview outdated packages without executing
- **Smart sudo**: Uses sudo only when not already root (containers are often root)
- **PATH setup**: Handles minimal launchd/cron PATH

### Manual Usage

```bash
# Preview what's outdated
update-packages --dry-run

# Run full update + upgrade + cleanup
update-packages
# Or use the alias:
pkg-update
```

### Setup / Uninstall

```bash
# Install scheduled job
scripts/cleanup/setup_brew_update.sh

# Uninstall scheduled job
scripts/cleanup/setup_brew_update.sh --uninstall
```

### Logs

- **macOS**: `~/Library/Logs/com.user.update-packages.log`
- **Linux**: `~/.update-packages.log`

### Checking Job Status

```bash
# macOS
launchctl list | grep update-packages

# Linux
crontab -l | grep update-packages
```

## Uninstalling

To completely remove all traces:

```bash
# 1. Uninstall the job
./uninstall.sh -y

# 2. Remove logs (macOS)
rm ~/Library/Logs/cleanup-old-files*.log

# 2. Remove logs (Linux)
rm ~/.cleanup-old-files.log

# 3. (Optional) Remove the scripts
rm -rf scripts/cleanup/
```
