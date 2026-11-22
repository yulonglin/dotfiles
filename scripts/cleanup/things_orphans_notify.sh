#!/usr/bin/env zsh
# launchd entry point: the scheduler's plist runs one executable with no arguments.
exec "${0:A:h:h:h}/custom_bins/things-orphans" --notify
