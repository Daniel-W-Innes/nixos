# Loki playbook (mcp-grafana)


1. **Discover labels first.** `list_loki_label_names` → `list_loki_label_values` for the window.
2. **Size-check cheaply.** `query_loki_stats` on the selector before pulling lines.
3. **Narrow windows + `direction="forward"`.** Default is backward + limit — in a chatty window "the 100 newest lines" can cover only 5–20 seconds. If you want the *start* of a window, use forward; if you want a specific moment, bound it tightly (±2 min). With no explicit start/end the lookback is 1 h (the `hints` field says so) — pass `startRfc3339` every time.
4. **Oversized results get saved to a file** under `~/.claude/projects/-home-daniel-repos-nixos/<session>/tool-results/` when they exceed the token limit. Parse them immediately with the script below (do not use Read — the file is one giant line). The harness requires the full file be read before summarizing; the script does that compactly.
5. **Exclude loki's own query logs** when scanning broadly: append `!= "\"SYSLOG_IDENTIFIER\":\"loki\""`.
6. Prefer `limit` ≤ 50 and the most specific filter that can work: `|=` (substring/regex on the raw line) is enough since the line embeds all journald fields as JSON text.

Parse helper — write to `/tmp/parse_loki.py` (no python3 on onion; use nix-shell):

```python
import json, sys, datetime
obj = json.load(open(sys.argv[1]))
data = obj["data"] if isinstance(obj, dict) else obj
def ts(t):
    return datetime.datetime.fromtimestamp(int(str(t).strip('"'))/1e9, datetime.timezone.utc).strftime("%m-%d %H:%M:%S")
rows = []
for e in data:
    try:
        m = json.loads(e["line"]); msg = m.get("MESSAGE",""); unit = m.get("_SYSTEMD_UNIT","?")
    except Exception:
        msg, unit = e["line"], "?"
    rows.append((e["timestamp"], unit, msg))
rows.sort(key=lambda r: r[0])
seen = {}
for t,u,m in rows:
    seen[m] = seen.get(m,0)+1
    if seen[m]==1: print(ts(t), f"[{u}]", m[:250])
```

Run: `nix-shell -p python3 --run "python3 /tmp/parse_loki.py <saved-file>" | head -150`

