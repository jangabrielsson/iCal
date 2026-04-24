# Calendar Automation QuickApp

A Fibaro HC3 QuickApp that turns your iCloud / webcal calendar into an HC3
scheduler: tag a calendar event with `#HC3#…` and the QA will call a
matching method on itself when the event starts.

> Source: [Calendar_automation.lua](Calendar_automation.lua) · uses [iCal.lua](iCal.lua)

---

## How it works

1. Every 6 h (and on startup or the **Refresh now** button) the QA downloads
   the calendar via `fibaro.iCal.download`.
2. Each event's `SUMMARY` and `DESCRIPTION` is scanned for lines starting
   with the configured **start-tag prefix** (default `#HC3#`) or
   **end-tag prefix** (default `#/HC3#`).
3. Tagged events are kept; everything else is discarded.
4. A 30 s ticker checks each kept event:
   - When `DTSTART` is reached → fire all `#HC3#…` tags.
   - When `DTEND` is reached  → fire all `#/HC3#…` tags.
   Each tag is dispatched at most once per occurrence
   (`uid + phase + ts` dedup key).
5. Each tag becomes a method call on the QA itself:
   `self:<methodName>(arg1, arg2, …)`.

Why a 30 s ticker instead of `setTimeout`? HC3's `setTimeout` is unreliable
for delays > a few hours; the ticker is robust against reboots, clock
changes, and missed wake-ups.

---

## Tag syntax

```
#HC3#<methodName>[,<arg1>[,<arg2>…]]      ← fires at event start (DTSTART)
#/HC3#<methodName>[,<arg1>[,<arg2>…]]     ← fires at event end   (DTEND)
```

The two prefixes are paired like HTML open/close tags. Use either, both, or
several of each in the same event — they're independent. The line ends at
the next newline; everything after the prefix on that line becomes the call.

Typical "on for the duration of the event" pattern:

```
#HC3#turnOn,88
#/HC3#turnOff,88
```

### Argument coercion

| Token            | Becomes      |
|------------------|--------------|
| `123`, `1.5`     | number       |
| `true` / `false` | boolean      |
| `nil`            | nil          |
| `"hello,there"`  | string `"hello,there"` (commas inside quotes still split — see below) |
| anything else    | string (one layer of `"…"` or `'…'` stripped) |

**Note:** the splitter is a simple `,`-based split. If you need a comma
*inside* a string argument, prefer using a different separator in your
handler — e.g. `#HC3#say,Time-to-leave` and have `say` replace `-` with space.

### Examples

| Tag in event body | Equivalent call | When |
|---|---|---|
| `#HC3#turnOn,88`              | `self:turnOn(88)`         | start |
| `#/HC3#turnOff,88`            | `self:turnOff(88)`        | end   |
| `#HC3#setValue,42,80`         | `self:setValue(42, 80)`   | start |
| `#HC3#scene,17`               | `self:scene(17)`          | start |
| `#HC3#say,"Hej hopp"`         | `self:say("Hej hopp")`    | start |

You can put **multiple tags** on the same event (one per line, in summary
or description). All will fire at their respective phase.

---

## Setup

### 1. Get an iCloud calendar URL

Mac Calendar → right-click your calendar → **Share Calendar** → enable
**Public Calendar** → **Copy URL**. Looks like:

```
webcal://p64-caldav.icloud.com/published/2/<your-token>
```

### 2. Install the QA on HC3

```bash
plua --tool uploadQA Calendar_automation.lua
```

Or copy `Calendar_automation.lua` (and `iCal.lua` — it's pulled in via the
`--%%file:` directive) to a new QuickApp via the HC3 web UI.

### 3. Set QA variables

| Variable        | Default   | Meaning |
|---|---|---|
| `calendarUrl`   | `env.ICAL`| Your webcal/https calendar URL |
| `daysAhead`     | `7`       | How far ahead to look for tagged events |
| `tagPrefix`     | `#HC3#`   | Start-of-event tag prefix |
| `tagPrefixEnd`  | `#/HC3#`  | End-of-event tag prefix |

### 4. Add a calendar event

Make a normal calendar entry. Anywhere in **summary** or **notes**, add a
line like:

```
#HC3#turnOff,88
```

Save. On the next refresh (or click **Refresh now**) the QA will pick it up;
when the event's start time arrives, `self:turnOff(88)` runs.

---

## UI

| Element | Purpose |
|---|---|
| Status        | `Ready` / `Downloading…` / `Complete` / `Error: …` |
| Upcoming      | Next 5 tagged events (date, summary, methods) |
| Last          | Time and summary of the most recently fired event |
| Refresh now   | Manual refresh + dispatch |
| Action log    | Reserved for custom logging if you want it |

---

## Defining your own actions

Open the bottom of [Calendar_automation.lua](Calendar_automation.lua) and add
methods. Each one becomes invocable from a `#HC3#<name>,…` tag.

```lua
-- #HC3#climate,15,21
function QuickApp:climate(deviceId, target)
    deviceId, target = tonumber(deviceId), tonumber(target)
    fibaro.call(deviceId, "setHeatingThermostatSetpoint", target)
end

-- #HC3#vacationOn
function QuickApp:vacationOn()
    fibaro.setGlobalVariable("HouseMode", "vacation")
end
```

The bundled examples (`turnOn`, `turnOff`, `setValue`, `scene`, `say`) are
starters — keep what you use, delete the rest.

### Safety rails built in

- Unknown method names log a warning instead of crashing.
- Each handler runs inside a `pcall`; an error in one tag never blocks the
  ticker or other tags.
- `firedKeys` is keyed by `uid + phase + ts`, so a recurring event fires
  once *per occurrence per phase*, never twice for the same one.

---

## Recurring events

`RRULE` is fully expanded by `iCal.lua` (`DAILY` / `WEEKLY` / `MONTHLY` /
`YEARLY` with `COUNT`, `UNTIL`, `INTERVAL`). Each occurrence of a recurring
event with a `#HC3#…` tag fires independently and exactly once.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Error: No calendar URL set` | `calendarUrl` variable is empty |
| `Error: HTTP 403/404`        | Calendar URL wrong or not public-shared |
| `Refresh: N events, 0 tagged` | No events in the window contain `#HC3#…` — check spelling and that the prefix matches `tagPrefix` |
| `Unknown method '…'` warning | Tag references a method that isn't defined on the QA |
| Method fires twice           | Probably not — but verify `uid` is stable in your calendar (some sync tools rewrite UIDs) |

For local testing without HC3:

```bash
plua --fibaro --offline --nodebugger --run-for 5 Calendar_automation.lua
```

---

## Related

- [README.md](README.md) — main project + parser library API
- [ARCHITECTURE.md](ARCHITECTURE.md) — internal design notes
- [iCloud_Calendar.lua](iCloud_Calendar.lua) — sibling QA that just lists / publishes events
