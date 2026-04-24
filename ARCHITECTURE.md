# Architecture

Short notes on how the pieces fit together. User-facing docs live in [README.md](README.md).

## Files

| File | Role |
|------|------|
| [iCal.lua](iCal.lua) | Parser library + `iCal.download` HTTP helper |
| [iCloud_Calendar.lua](iCloud_Calendar.lua) | Sample HC3 QuickApp |
| [test_ical.lua](test_ical.lua) | Standalone Lua test suite (33 assertions) |
| [speed.lua](speed.lua) | Time-acceleration helper for local testing |

## Library (`iCal.lua`)

Single module, no external dependencies. Exposed two ways:

- **HC3 / QuickApp:** assigns itself to `fibaro.iCal` (no `require()` available on HC3).
- **Plain Lua:** `return iCal` at end of file works with `require("iCal")`.

### Public API

- `iCal.parse(text, startTs, endTs) → { events = {...} }` — pure, synchronous.
- `iCal.download(url, opts, callback)` — async; uses `net.HTTPClient`, follows 3xx, calls `iCal.parse` under `pcall`.
- `iCal:parse_(...)` — colon-form alias kept for backwards compatibility.

### Internals (top-down)

```
iCal.parse(text, s, e)
  ├─ unfold(text)              -- join CRLF + space continuation lines
  ├─ for each line:
  │    parseLine(line)         -- name, params, value (skips ':' inside quoted params)
  ├─ build VEVENT records      -- skips VTIMEZONE / VTODO / VALARM nesting
  ├─ unescapeText(value)       -- \n \, \; \\  (uses \0 marker to handle \\\\)
  ├─ parseDateTime(v, …)       -- returns Unix ts; honors trailing 'Z' as UTC
  ├─ expandRRULE(event, s, e)  -- DAILY/WEEKLY by seconds (DST-safe);
  │                               MONTHLY/YEARLY by date arithmetic;
  │                               applies COUNT/UNTIL/INTERVAL/EXDATE;
  │                               hard cap 5000 instances
  └─ filter to [s,e], sort by dtstart
```

### Date / DST handling

- Date tables passed to `os.time` deliberately omit `isdst` (letting `os.time` resolve DST). Pinning `isdst=false` caused 1-hour drift across DST boundaries in DAILY/WEEKLY expansion.
- Local↔UTC offset is computed once via `os.difftime(os.time(), os.time(os.date("!*t", os.time())))`.
- `Z` timestamps: parse as if local, then add the offset, giving a true Unix ts.

## Sample QuickApp (`iCloud_Calendar.lua`)

Loads the library through plua's include directive:

```lua
--%%file:iCal.lua,ical
local iCal = fibaro.iCal
```

### Lifecycle

```
onInit
  ├─ refreshCalendar()                    -- initial fetch
  ├─ setInterval(refreshCalendar, 7 days) -- weekly re-fetch
  └─ setInterval(fireDueEvents, 30 s)     -- ticker

refreshCalendar
  └─ iCal.download(url, {startTs=now-1d, endTs=now+daysAhead*86400}, cb)
       cb → displayCalendar(events, windowStart, "trigger")
              ├─ updates UI labels
              └─ fires any events already past dtstart

fireDueEvents (every 30 s)
  └─ for each event with e.dtstart <= now and key not in firedKeys:
       firedKeys[uid..":"..dtstart] = true
       fibaro.setGlobalVariable(eventGlobalVar, json.encode(payload))
```

### Why a ticker, not `setTimeout`?

HC3's `setTimeout` is unreliable for delays beyond a few hours (system clock changes, sleep, firmware quirks). A 30-second poll over an in-memory `firedKeys` set is robust and cheap; the set is pruned on each refresh to drop entries outside the window.

## Tests (`test_ical.lua`)

Plain Lua; runs without plua. 33 hard assertions covering UTC parsing, all-day, DAILY/WEEKLY/UNTIL RRULE, EXDATE, attendees, escaping, line folding, sort order, VTIMEZONE/VTODO/VALARM skipping, window filtering, and `:` in property values.

Run: `lua test_ical.lua` → `=== Summary: 33 passed, 0 failed ===`.
