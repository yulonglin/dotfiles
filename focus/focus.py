#!/usr/bin/env python3
"""
Focus Mode Manager - Calendar-driven focus sessions with Cold Turkey integration.

Syncs with Apple Calendar to automatically configure focus modes based on events.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

import yaml

# Paths
CONFIG_DIR = Path(__file__).parent
CONFIG_FILE = CONFIG_DIR / "config.yaml"
STATE_FILE = CONFIG_DIR / ".state.json"
COLD_TURKEY_CLI = "/Applications/Cold Turkey Blocker.app/Contents/MacOS/Cold Turkey Blocker"


@dataclass
class Event:
    title: str
    start: datetime
    end: datetime
    calendar: str
    notes: str = ""


@dataclass
class FocusMode:
    name: str
    description: str
    whitelist: list[str]
    block_browsers: bool


def load_config() -> dict:
    """Load configuration from YAML file."""
    if not CONFIG_FILE.exists():
        print(f"Error: Config file not found at {CONFIG_FILE}")
        sys.exit(1)
    with open(CONFIG_FILE) as f:
        return yaml.safe_load(f)


def load_state() -> dict:
    """Load current state (active mode, etc.)."""
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {"active_mode": None, "last_sync": None, "scheduled_notifications": []}


def save_state(state: dict) -> None:
    """Save state to file."""
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2, default=str)


def get_calendar_events(hours_ahead: int = 24) -> list[Event]:
    """Fetch events from Apple Calendar using icalBuddy."""
    try:
        # Get events in a structured format
        result = subprocess.run(
            [
                "icalBuddy",
                "-n",  # Include only events (no tasks)
                "-ea",  # Exclude all-day events
                "-df",
                "%Y-%m-%d",
                "-tf",
                "%H:%M",
                f"eventsFrom:now to:now+{hours_ahead}h",
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        print("Warning: icalBuddy timed out")
        return []
    except FileNotFoundError:
        print("Error: icalBuddy not found. Install with: brew install ical-buddy")
        return []

    events = []
    now = datetime.now()
    today = now.date()
    tomorrow = today + timedelta(days=1)

    # Parse multi-line format
    current_event = None
    current_lines = []

    for line in result.stdout.split("\n"):
        if line.startswith("• "):
            # Save previous event
            if current_event:
                events.append(current_event)

            # Parse new event title and calendar
            # Format: "• Event Title (Calendar Name)"
            match = re.match(r"• (.+?) \(([^)]+)\)$", line)
            if match:
                title, calendar = match.groups()
            else:
                title = line[2:].strip()
                calendar = ""

            current_event = {
                "title": title,
                "calendar": calendar,
                "datetime": None,
                "notes": "",
            }
        elif current_event and line.strip():
            line = line.strip()
            # Check for datetime line
            # Formats: "today at 08:00 - 23:00", "tomorrow at 07:00 - 08:00", "2025-01-03 at 09:00 - 10:00"
            dt_match = re.match(r"(today|tomorrow|\d{4}-\d{2}-\d{2}) at (\d{2}:\d{2}) - (\d{2}:\d{2})", line)
            if dt_match:
                date_part, start_time, end_time = dt_match.groups()
                if date_part == "today":
                    event_date = today
                elif date_part == "tomorrow":
                    event_date = tomorrow
                else:
                    event_date = datetime.strptime(date_part, "%Y-%m-%d").date()

                current_event["datetime"] = {
                    "date": event_date,
                    "start": start_time,
                    "end": end_time,
                }
            elif line.startswith("notes:"):
                current_event["notes"] = line[6:].strip()

    # Don't forget the last event
    if current_event:
        events.append(current_event)

    # Convert to Event objects
    result_events = []
    for e in events:
        if e.get("datetime"):
            dt = e["datetime"]
            try:
                start_dt = datetime.combine(dt["date"], datetime.strptime(dt["start"], "%H:%M").time())
                end_dt = datetime.combine(dt["date"], datetime.strptime(dt["end"], "%H:%M").time())
                result_events.append(Event(
                    title=e["title"],
                    start=start_dt,
                    end=end_dt,
                    calendar=e["calendar"],
                    notes=e.get("notes", ""),
                ))
            except (ValueError, KeyError):
                continue

    return sorted(result_events, key=lambda e: e.start)


def match_event_to_mode(event: Event, config: dict) -> Optional[str]:
    """Match an event to a focus mode based on patterns."""
    event_patterns = config.get("event_patterns", {})
    title_lower = event.title.lower()

    for mode_name, patterns in event_patterns.items():
        for pattern in patterns:
            if re.search(pattern.lower(), title_lower):
                return mode_name

    return config.get("default_mode")


def get_current_event(events: list[Event]) -> Optional[Event]:
    """Get the event happening right now."""
    now = datetime.now()
    for event in events:
        if event.start <= now <= event.end:
            return event
    return None


def get_next_event(events: list[Event]) -> Optional[Event]:
    """Get the next upcoming event."""
    now = datetime.now()
    for event in events:
        if event.start > now:
            return event
    return None


def encode_whitelist(apps: list[str]) -> str:
    """Encode app names to hex format for Micromanager."""
    return ":".join(app.lower().encode().hex() for app in apps)


def decode_whitelist(hex_str: str) -> list[str]:
    """Decode hex whitelist from Micromanager."""
    if not hex_str:
        return []
    return [bytes.fromhex(h).decode() for h in hex_str.split(":")]


def set_micromanager_whitelist(apps: list[str]) -> bool:
    """Set Micromanager's whitelist via defaults."""
    if not apps:
        print("  Skipping Micromanager (no whitelist defined)")
        return True

    whitelist_hex = encode_whitelist(apps)
    try:
        subprocess.run(
            ["defaults", "write", "com.getcoldturkey.micromanager-pro", "whitelist", whitelist_hex],
            check=True,
            capture_output=True,
        )
        print(f"  Micromanager whitelist set: {', '.join(apps)}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"  Error setting Micromanager whitelist: {e}")
        return False


def get_micromanager_whitelist() -> list[str]:
    """Get current Micromanager whitelist."""
    try:
        result = subprocess.run(
            ["defaults", "read", "com.getcoldturkey.micromanager-pro", "whitelist"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            return decode_whitelist(result.stdout.strip())
    except Exception:
        pass
    return []


def start_cold_turkey_block(block_name: str, duration_minutes: int) -> bool:
    """Start a Cold Turkey Blocker block."""
    if not Path(COLD_TURKEY_CLI).exists():
        print(f"  Cold Turkey Blocker not found")
        return False

    try:
        subprocess.run(
            [COLD_TURKEY_CLI, "-start", block_name, "-lock", str(duration_minutes)],
            check=True,
            capture_output=True,
        )
        print(f"  Cold Turkey block '{block_name}' started for {duration_minutes} min")
        return True
    except subprocess.CalledProcessError as e:
        print(f"  Error starting Cold Turkey block: {e}")
        return False


def stop_cold_turkey_block(block_name: str) -> bool:
    """Stop a Cold Turkey Blocker block."""
    if not Path(COLD_TURKEY_CLI).exists():
        return False

    try:
        subprocess.run(
            [COLD_TURKEY_CLI, "-stop", block_name],
            capture_output=True,
        )
        return True
    except subprocess.CalledProcessError:
        return False


def send_notification(title: str, message: str, sound: bool = True) -> None:
    """Send a macOS notification."""
    script = f'''
    display notification "{message}" with title "{title}"{' sound name "Glass"' if sound else ''}
    '''
    subprocess.run(["osascript", "-e", script], capture_output=True)


def is_within_work_hours(config: dict) -> bool:
    """Check if current time is within configured work hours."""
    settings = config.get("settings", {})
    work_hours = settings.get("work_hours", {})

    if not work_hours:
        return True

    now = datetime.now()
    day_abbrev = now.strftime("%a").lower()

    if day_abbrev not in work_hours.get("days", ["mon", "tue", "wed", "thu", "fri"]):
        return False

    start_time = datetime.strptime(work_hours.get("start", "08:00"), "%H:%M").time()
    end_time = datetime.strptime(work_hours.get("end", "20:00"), "%H:%M").time()

    return start_time <= now.time() <= end_time


def cmd_sync(args: argparse.Namespace) -> None:
    """Sync focus mode with calendar."""
    config = load_config()
    state = load_state()

    if not is_within_work_hours(config) and not args.force:
        print("Outside work hours. Use --force to override.")
        return

    print("Fetching calendar events...")
    events = get_calendar_events(hours_ahead=args.hours)

    if not events:
        print("No upcoming events found.")
        return

    print(f"Found {len(events)} events in next {args.hours} hours\n")

    # Check current event
    current = get_current_event(events)
    next_event = get_next_event(events)

    if current:
        mode_name = match_event_to_mode(current, config)
        print(f"Current: {current.title}")
        print(f"  Time: {current.start.strftime('%H:%M')} - {current.end.strftime('%H:%M')}")
        print(f"  Mode: {mode_name or 'none'}")

        if mode_name and mode_name in config.get("modes", {}):
            mode = config["modes"][mode_name]
            print(f"\nConfiguring '{mode_name}' mode...")
            set_micromanager_whitelist(mode.get("whitelist", []))

            if mode.get("block_browsers") and not args.dry_run:
                remaining = int((current.end - datetime.now()).total_seconds() / 60)
                if remaining > 0:
                    start_cold_turkey_block("distractions", remaining)

            state["active_mode"] = mode_name
    else:
        print("No current event.")
        state["active_mode"] = None

    if next_event:
        mode_name = match_event_to_mode(next_event, config)
        time_until = next_event.start - datetime.now()
        minutes_until = int(time_until.total_seconds() / 60)

        print(f"\nNext: {next_event.title}")
        print(f"  Starts in: {minutes_until} minutes")
        print(f"  Mode: {mode_name or 'none'}")

        # Send notification if event is coming up soon
        notify_before = config.get("settings", {}).get("notify_before", 5)
        if 0 < minutes_until <= notify_before and not args.dry_run:
            send_notification(
                f"Focus: {mode_name or 'Event'} starting soon",
                f"{next_event.title} in {minutes_until} min",
            )

    state["last_sync"] = datetime.now().isoformat()
    if not args.dry_run:
        save_state(state)


def cmd_status(args: argparse.Namespace) -> None:
    """Show current focus status."""
    config = load_config()
    state = load_state()

    print("=== Focus Status ===\n")

    # Current mode
    active_mode = state.get("active_mode")
    if active_mode:
        mode = config.get("modes", {}).get(active_mode, {})
        print(f"Active mode: {active_mode}")
        print(f"  {mode.get('description', '')}")
    else:
        print("Active mode: None")

    # Current Micromanager whitelist
    whitelist = get_micromanager_whitelist()
    if whitelist:
        print(f"\nMicromanager whitelist: {', '.join(whitelist)}")

    # Last sync
    last_sync = state.get("last_sync")
    if last_sync:
        print(f"\nLast sync: {last_sync}")

    # Upcoming events
    print("\n=== Upcoming Events ===\n")
    events = get_calendar_events(hours_ahead=8)
    for event in events[:5]:
        mode = match_event_to_mode(event, config)
        print(f"{event.start.strftime('%H:%M')} - {event.end.strftime('%H:%M')}: {event.title}")
        if mode:
            print(f"  -> {mode}")


def cmd_set(args: argparse.Namespace) -> None:
    """Manually set a focus mode."""
    config = load_config()
    state = load_state()

    mode_name = args.mode
    modes = config.get("modes", {})

    if mode_name == "off":
        print("Clearing focus mode...")
        state["active_mode"] = None
        save_state(state)
        # Could clear Micromanager here too
        print("Focus mode disabled.")
        return

    if mode_name not in modes:
        print(f"Error: Unknown mode '{mode_name}'")
        print(f"Available modes: {', '.join(modes.keys())}, off")
        sys.exit(1)

    mode = modes[mode_name]
    print(f"Setting mode: {mode_name}")
    print(f"  {mode.get('description', '')}")

    set_micromanager_whitelist(mode.get("whitelist", []))

    if mode.get("block_browsers") and args.duration:
        start_cold_turkey_block("distractions", args.duration)

    state["active_mode"] = mode_name
    save_state(state)

    send_notification(f"Focus: {mode_name}", f"Mode configured. Start Micromanager when ready.")


def cmd_schedule(args: argparse.Namespace) -> None:
    """Show tomorrow's schedule with focus modes."""
    config = load_config()

    # Get events for tomorrow
    now = datetime.now()
    tomorrow_start = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0)
    hours_until_tomorrow_end = int((tomorrow_start + timedelta(hours=24) - now).total_seconds() / 3600)

    print(f"=== Tomorrow's Schedule ({tomorrow_start.strftime('%A, %B %d')}) ===\n")

    events = get_calendar_events(hours_ahead=hours_until_tomorrow_end)

    # Filter to tomorrow only
    tomorrow_events = [
        e for e in events
        if e.start.date() == tomorrow_start.date()
    ]

    if not tomorrow_events:
        print("No events scheduled for tomorrow.")
        return

    for event in tomorrow_events:
        mode = match_event_to_mode(event, config)
        mode_indicator = f" [{mode}]" if mode else ""
        print(f"{event.start.strftime('%H:%M')} - {event.end.strftime('%H:%M')}: {event.title}{mode_indicator}")


def cmd_list_modes(args: argparse.Namespace) -> None:
    """List all configured modes."""
    config = load_config()
    modes = config.get("modes", {})

    print("=== Available Focus Modes ===\n")
    for name, mode in modes.items():
        print(f"{name}:")
        print(f"  {mode.get('description', '')}")
        print(f"  Apps: {', '.join(mode.get('whitelist', []))}")
        if mode.get("block_browsers"):
            print("  Blocks browsers: Yes")
        print()


def main():
    parser = argparse.ArgumentParser(
        description="Focus Mode Manager - Calendar-driven focus sessions"
    )
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # sync command
    sync_parser = subparsers.add_parser("sync", help="Sync with calendar")
    sync_parser.add_argument("--hours", type=int, default=24, help="Hours ahead to check")
    sync_parser.add_argument("--force", action="store_true", help="Ignore work hours")
    sync_parser.add_argument("--dry-run", action="store_true", help="Don't make changes")
    sync_parser.set_defaults(func=cmd_sync)

    # status command
    status_parser = subparsers.add_parser("status", help="Show current status")
    status_parser.set_defaults(func=cmd_status)

    # set command
    set_parser = subparsers.add_parser("set", help="Manually set a mode")
    set_parser.add_argument("mode", help="Mode name (or 'off')")
    set_parser.add_argument("--duration", type=int, help="Block duration in minutes")
    set_parser.set_defaults(func=cmd_set)

    # schedule command
    schedule_parser = subparsers.add_parser("schedule", help="Show tomorrow's schedule")
    schedule_parser.set_defaults(func=cmd_schedule)

    # modes command
    modes_parser = subparsers.add_parser("modes", help="List available modes")
    modes_parser.set_defaults(func=cmd_list_modes)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()
