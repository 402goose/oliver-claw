#!/bin/sh
# intel.sh — drop a URL, get a Jack-shaped intel summary back.
# Usage: intel.sh "<url>"
# Auto-detects: YouTube → audio → Groq STT → text
#               Spotify → tries yt-dlp, else falls back to web title scrape
#               X / Twitter → embed page text
#               Article (default) → curl + pandoc → text
# Output: prints the raw extracted text to stdout. Caller (the agent) then
# summarizes in Jack's voice using its own LLM context.
set -e
URL="$1"
[ -z "$URL" ] && { echo "usage: intel.sh '<url>'" >&2; exit 1; }

WORK=/tmp/intel-$$
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

CFG=/data/openclaw.json
GROQ_KEY=$(node -e "console.log(require('$CFG').tools.media.audio.request.auth.token)")

case "$URL" in
  *youtube.com/watch*|*youtu.be/*|*youtube.com/shorts*)
    echo "[intel] type=youtube url=$URL" >&2
    # PRIMARY: openclaw's `summarize` skill (steipete). Has its own caption +
    # scraper chain that handles many bot-gated cases without yt-dlp at all.
    if command -v summarize >/dev/null 2>&1; then
      if SUMTXT=$(summarize "$URL" --youtube auto --extract-only 2>"$WORK/sum.err") && [ -n "$SUMTXT" ] && [ ${#SUMTXT} -gt 200 ]; then
        echo "# YouTube transcript (via summarize): $URL"
        echo
        echo "$SUMTXT"
        exit 0
      fi
      echo "[intel] summarize returned empty/short; falling back to yt-dlp" >&2
    fi
    # FALLBACK: yt-dlp on cloud IPs sometimes hits YouTube's anti-bot. If a cookies file
    # is mounted, use it. Else try without; fall back to auto-captions API.
    YTOPTS=""
    [ -f /data/youtube-cookies.txt ] && YTOPTS="--cookies /data/youtube-cookies.txt"
    if ! yt-dlp -q $YTOPTS -x --audio-format mp3 --audio-quality 5 \
        -o "$WORK/audio.%(ext)s" "$URL" 2>"$WORK/yt.err"; then
      # Fallback: pull auto-captions directly from YouTube's TimedText API
      VID=$(echo "$URL" | grep -oE '(v=|youtu\.be/|/shorts/)[A-Za-z0-9_-]{11}' | tr -d 'v=/' | head -c 11)
      if [ -n "$VID" ]; then
        echo "[intel] yt-dlp blocked; trying auto-captions API for $VID" >&2
        TXT=$(curl -sS --max-time 30 "https://www.youtube.com/api/timedtext?lang=en&v=$VID&fmt=json3" \
          | python3 -c "import json,sys;d=json.load(sys.stdin);print(' '.join(s.get('utf8','') for ev in d.get('events',[]) for s in ev.get('segs',[])).strip())" 2>/dev/null)
        if [ -n "$TXT" ] && [ ${#TXT} -gt 100 ]; then
          echo "# YouTube auto-captions for $URL"
          echo
          echo "$TXT"
          exit 0
        fi
      fi
      echo "[intel] yt-dlp failed AND auto-captions empty/blocked. Paste the transcript directly." >&2
      cat "$WORK/yt.err" >&2 | tail -3
      exit 2
    fi
    AUDIO=$(ls "$WORK"/audio.* 2>/dev/null | head -1)
    [ -z "$AUDIO" ] && { echo "[intel] no audio extracted" >&2; exit 2; }
    SIZE=$(wc -c < "$AUDIO")
    if [ "$SIZE" -gt 26214400 ]; then
      # Groq's 25MB cap — slice to first 25 min and warn
      ffmpeg -y -loglevel error -i "$AUDIO" -t 1500 -c copy "$WORK/clipped.mp3" 2>/dev/null
      AUDIO="$WORK/clipped.mp3"
      echo "[intel] audio >25MB, clipped to first 25 min" >&2
    fi
    HTTP=$(curl -sS --max-time 180 -o "$WORK/transcript.json" -w "%{http_code}" \
      -X POST https://api.groq.com/openai/v1/audio/transcriptions \
      -H "Authorization: Bearer $GROQ_KEY" \
      -F "file=@$AUDIO;type=audio/mpeg" \
      -F "model=whisper-large-v3" \
      -F "response_format=verbose_json")
    [ "$HTTP" != "200" ] && { echo "[intel] Groq http $HTTP" >&2; cat "$WORK/transcript.json" >&2; exit 3; }
    TITLE=$(yt-dlp --get-title "$URL" 2>/dev/null || echo "(unknown title)")
    echo "# YouTube transcript: $TITLE"
    echo "Source: $URL"
    echo
    python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('text','').strip())" "$WORK/transcript.json"
    ;;

  *open.spotify.com/episode/*)
    echo "[intel] type=spotify url=$URL" >&2
    # Spotify episodes are auth-walled — try yt-dlp (sometimes works for podcasts that have a YouTube mirror), else fail with explanation
    if yt-dlp -q -x --audio-format mp3 -o "$WORK/audio.%(ext)s" "$URL" 2>/dev/null; then
      AUDIO=$(ls "$WORK"/audio.* | head -1)
      HTTP=$(curl -sS --max-time 180 -o "$WORK/transcript.json" -w "%{http_code}" \
        -X POST https://api.groq.com/openai/v1/audio/transcriptions \
        -H "Authorization: Bearer $GROQ_KEY" \
        -F "file=@$AUDIO;type=audio/mpeg" \
        -F "model=whisper-large-v3" \
        -F "response_format=verbose_json")
      [ "$HTTP" = "200" ] && python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('text','').strip())" "$WORK/transcript.json"
    else
      echo "# Spotify episode (audio not extractable from $URL)"
      echo
      echo "Spotify auth-wall blocks direct audio download. Workaround: ask the speaker for a YouTube/RSS mirror, or paste the transcript directly. Episode page metadata follows:"
      echo
      curl -sSL --max-time 30 -A "Mozilla/5.0" "$URL" 2>/dev/null | pandoc -f html -t plain 2>/dev/null | head -200
    fi
    ;;

  *twitter.com/*|*x.com/*)
    echo "[intel] type=tweet url=$URL" >&2
    # PRIMARY: openclaw's `bird` skill (cookie auth — full threads + replies,
    # richer than the v2 API). Reads $X_AUTH_TOKEN + $X_CT0 from env.
    if command -v bird >/dev/null 2>&1 && [ -n "$X_AUTH_TOKEN" ] && [ -n "$X_CT0" ]; then
      if BIRDOUT=$(bird --auth-token "$X_AUTH_TOKEN" --ct0 "$X_CT0" --plain thread "$URL" 2>"$WORK/bird.err"); then
        echo "# X thread (via bird): $URL"
        echo
        echo "$BIRDOUT"
        exit 0
      elif BIRDOUT=$(bird --auth-token "$X_AUTH_TOKEN" --ct0 "$X_CT0" --plain read "$URL" 2>"$WORK/bird.err"); then
        echo "# X tweet (via bird): $URL"
        echo
        echo "$BIRDOUT"
        exit 0
      fi
      echo "[intel] bird failed; falling back to page scrape" >&2
    fi
    # FALLBACK: simple curl + pandoc (gets only X's empty JS shell)
    curl -sSL --max-time 30 -A "Mozilla/5.0" "$URL" -o "$WORK/page.html"
    echo "# Tweet thread: $URL"
    echo
    pandoc -f html -t plain "$WORK/page.html" 2>/dev/null | head -200
    ;;

  *.mp3|*.m4a|*.wav|*.ogg|*.opus|*.mp3\?*|*.m4a\?*)
    # Direct audio URL (e.g., podcast RSS-derived .mp3). Download, transcribe via Groq.
    echo "[intel] type=audio url=$URL" >&2
    HTTP=$(curl -sSL --max-time 180 -A "Mozilla/5.0" -o "$WORK/audio.mp3" -w "%{http_code}" "$URL")
    [ "$HTTP" != "200" ] && [ "$HTTP" != "301" ] && [ "$HTTP" != "302" ] && { echo "[intel] audio http $HTTP" >&2; exit 2; }
    SIZE=$(wc -c < "$WORK/audio.mp3")
    AUDIO="$WORK/audio.mp3"
    if [ "$SIZE" -gt 26214400 ]; then
      ffmpeg -y -loglevel error -i "$AUDIO" -t 1500 -c copy "$WORK/clipped.mp3" 2>/dev/null
      AUDIO="$WORK/clipped.mp3"
      echo "[intel] audio >25MB, clipped to first 25 min" >&2
    fi
    HTTP=$(curl -sS --max-time 180 -o "$WORK/transcript.json" -w "%{http_code}" \
      -X POST https://api.groq.com/openai/v1/audio/transcriptions \
      -H "Authorization: Bearer $GROQ_KEY" \
      -F "file=@$AUDIO;type=audio/mpeg" \
      -F "model=whisper-large-v3" \
      -F "response_format=verbose_json")
    [ "$HTTP" != "200" ] && { echo "[intel] Groq http $HTTP" >&2; cat "$WORK/transcript.json" >&2; exit 3; }
    echo "# Audio transcript"
    echo "Source: $URL"
    echo
    python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('text','').strip())" "$WORK/transcript.json"
    ;;

  *)
    echo "[intel] type=article url=$URL" >&2
    HTTP=$(curl -sSL --max-time 30 -A "Mozilla/5.0" -o "$WORK/page.html" -w "%{http_code}" "$URL")
    [ "$HTTP" != "200" ] && [ "$HTTP" != "301" ] && [ "$HTTP" != "302" ] && { echo "[intel] http $HTTP" >&2; }
    TITLE=$(grep -oE '<title[^>]*>[^<]+</title>' "$WORK/page.html" | head -1 | sed 's/<[^>]*>//g' | head -c 200)
    echo "# Article: $TITLE"
    echo "Source: $URL"
    echo
    pandoc -f html -t plain "$WORK/page.html" 2>/dev/null | head -800
    ;;
esac
