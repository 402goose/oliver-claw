# HEARTBEAT.md — rubail

## Web fetch

Use `mcp__scrape__scrape_url` for any web fetch — shared infra, anti-bot ready.
Hosted at `http://scrape-gateway.railway.internal:8080` (internal — free egress
inside the openclaw Railway project). Per-domain caching means second-call
cache hits don't bill against the daily cap (1k static / 200 js / 50 screenshot
/ 100 extract). If a page 403s, escalate to the `agent-browser` skill.
