#!/bin/sh
# oliver-speak.sh — generate Oliver Birwadker's cloned voice for a given text.
# Mirrors dee-speak.sh. Reads ELEVENLABS_OLIVER_VOICE_ID from env (set on Railway),
# POSTs to ElevenLabs TTS for opus_48000_64 (Telegram voice format),
# prints absolute path of resulting .ogg to stdout.
set -e
TEXT="$*"
[ -z "$TEXT" ] && { echo "usage: oliver-speak.sh '<text>'" >&2; exit 1; }

KEY="${ELEVENLABS_API_KEY:-}"
VID="${ELEVENLABS_OLIVER_VOICE_ID:-5o2pDlnMrnBdPB4nkPMl}"
MODEL="${ELEVENLABS_MODEL_ID:-eleven_multilingual_v2}"
VS='{"stability":0.50,"similarity_boost":0.85,"style":0.10,"use_speaker_boost":true}'

if [ -z "$KEY" ]; then
  echo "ELEVENLABS_API_KEY env var not set" >&2
  exit 1
fi

OUTDIR=/data/media/outbound
mkdir -p "$OUTDIR"
ID=$(date +%s%N | tail -c 12)
OGG="$OUTDIR/oliver-$ID.ogg"

BODY=$(node -e "
const text = process.argv[1];
const model = process.argv[2];
const vs = JSON.parse(process.argv[3]);
console.log(JSON.stringify({ text, model_id: model, voice_settings: vs }));
" "$TEXT" "$MODEL" "$VS")

HTTP=$(curl -sS -o "$OGG" -w "%{http_code}" \
  -X POST "https://api.elevenlabs.io/v1/text-to-speech/$VID?output_format=opus_48000_64" \
  -H "xi-api-key: $KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/ogg" \
  --data "$BODY")
if [ "$HTTP" != "200" ] || [ ! -s "$OGG" ]; then
  echo "ElevenLabs $HTTP: $(head -c 300 "$OGG")" >&2
  rm -f "$OGG"
  exit 2
fi

echo "$OGG"
