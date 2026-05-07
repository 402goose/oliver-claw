#!/bin/sh
# whisper-bridge-supervisor.sh — keep the whisper-bridge alive across crashes.
# Boot script launches this in the background; it never returns.
LOG=/data/logs/whisper-bridge.log
cd /data/scripts || exit 1
while true; do
  echo "[$(date -Iseconds)] [whisper-bridge-sv] starting bridge" >> "$LOG"
  node whisper-bridge.mjs >> "$LOG" 2>&1
  RC=$?
  echo "[$(date -Iseconds)] [whisper-bridge-sv] bridge exited code=$RC, restarting in 3s" >> "$LOG"
  sleep 3
done
