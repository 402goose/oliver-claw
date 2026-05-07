#!/bin/sh
# digest.sh — wrapper for digest.mjs. Outputs digest to stdout.
# Usage: digest.sh [hours_back]   default: 24
exec node /data/scripts/digest.mjs "$@"
