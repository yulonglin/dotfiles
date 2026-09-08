#!/bin/bash
# Compatibility entry point for sessions that cached the previous manifest.
set -euo pipefail
exec python3 "$(dirname "$0")/context.py" modern-tools
