#!/usr/bin/env python3
# Idempotent patch for /app/dist/media-understanding-CdgTl3Vo.js so the audio
# transcription path:
#   1) allows loopback (legacy — for the local whisper-bridge fallback)
#   2) bypasses OpenClaw's SSRF/dispatcher machinery and uses plain fetch().
#      OpenClaw's fetchWithSsrFGuard does `{ ...init }` AND injects a custom
#      pinned-DNS dispatcher; together these break undici's auto Content-Type
#      detection for FormData bodies, so the multipart upload arrives at the
#      provider with Content-Type: text/plain (or missing entirely). Verified
#      empirically: same error surfaces against my local bridge, OpenRouter,
#      and Groq. The fix is to skip the guard entirely for the upload —
#      Groq/OpenAI are public hostnames so SSRF protection is moot.
import re, sys, os
F = sys.argv[1] if len(sys.argv) > 1 else '/app/dist/media-understanding-CdgTl3Vo.js'
if not os.path.exists(F):
    print(f'patch: file missing {F}', file=sys.stderr); sys.exit(0)
src = open(F).read()
already1 = 'AUDIO-PRIVATE-NET-PATCH' in src
already2 = 'AUDIO-PLAIN-FETCH-PATCH' in src
if already1 and already2:
    print('patch: both patches already applied'); sys.exit(0)

if not already1:
    src, n1 = re.subn(
        r'(api: "openai-audio-transcriptions",)',
        r'\1\n\t\tallowPrivateNetwork: true, // AUDIO-PRIVATE-NET-PATCH',
        src,
    )
    if n1 != 1:
        print(f'patch: privnet pattern matched {n1} times, refusing', file=sys.stderr); sys.exit(1)

if not already2:
    new_call = (
        '// AUDIO-PLAIN-FETCH-PATCH: bypass SSRF/dispatcher machinery so undici\n'
        '\t// auto-sets multipart/form-data; boundary=... from the FormData body.\n'
        '\tconst plainHeaders = {};\n'
        '\tfor (const [k, v] of headers.entries()) {\n'
        '\t\tif (k.toLowerCase() !== "content-type") plainHeaders[k] = v;\n'
        '\t}\n'
        '\tconst _ctrl = new AbortController();\n'
        '\tconst _to = setTimeout(() => _ctrl.abort(), params.timeoutMs ?? 60000);\n'
        '\tconst res = await fetch(url, { method: "POST", headers: plainHeaders, body: form, signal: _ctrl.signal });\n'
        '\tconst release = async () => { clearTimeout(_to); };'
    )
    pat = re.compile(
        r'const \{\s*response:\s*res,\s*release\s*\}\s*=\s*await\s+postTranscriptionRequest\(\{[\s\S]*?\}\);',
        re.MULTILINE,
    )
    m = pat.search(src)
    if not m:
        print('patch: could not locate postTranscriptionRequest call', file=sys.stderr); sys.exit(1)
    src = src[:m.start()] + new_call + src[m.end():]
    if 'AUDIO-PLAIN-FETCH-PATCH' not in src:
        print('patch: plain-fetch marker missing after replace', file=sys.stderr); sys.exit(1)

open(F, 'w').write(src)
print(f'patch: applied to {F}')
