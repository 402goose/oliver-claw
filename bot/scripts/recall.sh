#!/bin/sh
# recall.sh — priority-ranked retrieval. Wrap recall.mjs.
# Usage: recall.sh "<query>" [k]
exec node /data/scripts/recall.mjs "$@"
