# iCal Parser + iCloud Calendar QuickApp

A complete iCalendar (RFC 2445) parser library written in Lua, plus a Fibaro HC3 QuickApp for downloading and displaying events from your iCloud calendar.

---

## Components

### 1. `iCal.lua` — Standalone Parser Library

A pure Lua library for parsing iCalendar format. Can be used standalone or embedded in a QuickApp.

**Features:**
- Parses iCalendar (RFC 2445) format
- Extracts VEVENT components with full property support
- Automatic RRULE expansion into individual event instances
- Handles EXDATE exclusions
- Date range filtering (start/end dates)
- Lenient error handling (skips malformed properties, logs warnings)
- Supports DATE, DATE-TIME (local and UTC), and duration fields

**Supported Properties:**
- SUMMARY, DTSTART, DTEND, UID, DESCRIPTION, LOCATION
- ORGANIZER, ATTENDEE (email extraction)
- LAST-MODIFIED, RRULE, EXDATE

**RRULE Support:**
- FREQ: DAILY, WEEKLY, MONTHLY, YEARLY
- COUNT, UNTIL, INTERVAL
- BYDAY, BYMONTHDAY (basic support)

**Example Usage:**
```lua
local iCal = require("iCal")

local icalData = ... -- iCal file contents
local startDate = { year=2026, month=4, day=6 }
local endDate = { year=2026, month=5, day=6 }

local result = iCal:parse(icalData, startDate, endDate)
-- result.events = { { uid, summary, dtstart, dtend, ... }, ... }

for _, event in ipairs(result.events) do
    print(event.summary, "at", os.date("%Y-%m-%d %H:%M", event.dtstart))
end
```

---

### 2. `iCloud_Calendar.lua` — QuickApp

A Fibaro HC3 QuickApp that downloads your iCloud calendar and displays upcoming events.

**Features:**
- Download calendar from webcal:// or https:// URLs
- Parse and display upcoming events
- Configurable date range (default: next 30 days)
- Shows event count, titles, dates, and descriptions
- Error handling and status display
- Lenient parsing (skips malformed events)

**Configuration:**

Set these QuickApp variables:

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `calendarUrl` | string | Your iCloud calendar URL (webcal:// or https://) | (empty) |
| `daysAhead` | number | Days into the future to fetch events | 30 |

**How to Set Up:**

1. **Get your iCloud calendar URL:**
   - On your iPhone/Mac: Settings → [Your Name] → iCloud → Calendars → Share Calendar
   - Copy the public "Calendar Link" (looks like `webcal://p64-caldav.icloud.com/published/...`)
   - Or use the `https://` variant if available

2. **Add the QuickApp to your HC3:**
   - Copy `iCloud_Calendar.lua` to your HC3
   - Create a Device/QuickApp with the file
   - Edit the QuickApp properties and set `calendarUrl` to your calendar link
   - Optionally adjust `daysAhead` for a different time window

3. **Download Events:**
   - Click the "Download Calendar" button in the QuickApp UI
   - Wait for "Status: Complete"
   - View parsed events in the UI

**UI Elements:**

| Element | Purpose |
|---------|---------|
| **Status** | Shows current operation status (Ready, Downloading, Complete, Error) |
| **Events** | Count of events found in the date range |
| **Download Calendar** | Button to trigger download & parse |
| **Event List** | Shows first 5 upcoming events with dates and titles |
| **Last Event** | Date and title of the last event in range |

---

## Usage Examples

### Downloads raw iCal from URL
```bash
# If testing locally with plua:
plua --fibaro --run-for 0 iCloud_Calendar.lua
# Set calendarUrl via plua environment or QuickApp variable
```

### Parse a local iCal file
```lua
local iCal = require("iCal")
local file = io.open("calendar.ics", "r")
local data = file:read("*a")
file:close()

local result = iCal:parse(data)
for _, event in ipairs(result.events) do
    print(event.summary)
end
```

---

## Date Formats

The parser automatically detects and converts three iCalendar date formats:

| Format | Example | Meaning |
|--------|---------|---------|
| **DATE** | `20260406` | April 6, 2026 (all-day event) |
| **DATE-TIME (local)** | `20260406T143000` | April 6, 2026 at 2:30 PM (floating time) |
| **DATE-TIME (UTC)** | `20260406T143000Z` | April 6, 2026 at 2:30 PM UTC |

All times are converted to Unix timestamps (seconds since 1970-01-01 UTC) for comparison and filtering.

---

## Recurrence Processing

### How RRULE Works

When an event has a recurrence rule (RRULE), the parser expands it into individual event instances:

**Input (Single Recurring Event):**
```
BEGIN:VEVENT
UID:event123@example.com
SUMMARY:Team Meeting
DTSTART:20260410T100000Z
DTEND:20260410T110000Z
RRULE:FREQ=WEEKLY;COUNT=5;BYDAY=TH
END:VEVENT
```

**Output (5 Expanded Events):**
- April 10, 2026 10:00 - Team Meeting
- April 17, 2026 10:00 - Team Meeting
- April 24, 2026 10:00 - Team Meeting
- May 1, 2026 10:00 - Team Meeting
- May 8, 2026 10:00 - Team Meeting

### EXDATE (Exception Dates)

If an event has exceptions (e.g., the April 24 meeting was cancelled):

```
EXDATE:20260424T100000Z
```

That instance is automatically excluded from the expanded set.

---

## Limitations & Known Issues

1. **Timezone Handling (SIMPLIFIED)**
   - The parser does not deeply parse TZID parameters or VTIMEZONE components.
   - All non-UTC times are treated as "floating" times and converted to Unix timestamps as-is.
   - *Future enhancement:* Parse VTIMEZONE blocks and apply TZID offsets.

2. **RRULE Support (BASIC)**
   - Only basic recurrence rules are supported (DAILY, WEEKLY, MONTHLY, YEARLY with COUNT/UNTIL/INTERVAL/BYDAY/BYMONTHDAY).
   - Complex rules (e.g., BYSETPOS, BYHOUR, BYMINUTE) are not yet implemented.
   - *Future enhancement:* Add full RFC 2445 RRULE support.

3. **Performance**
   - For calendars with > 1000 recurring instances, performance may degrade.
   - HC3 memory limits may be hit with very large calendars.

4. **Components Ignored (Out of Scope)**
   - VALARM (alarms/notifications)
   - VTODO (to-do items)
   - VJOURNAL (journal entries)
   - VFREEBUSY (free/busy information)
   - Only VEVENT components are parsed.

5. **Error Recovery**
   - Malformed properties are skipped (lenient mode).
   - Invalid lines don't halt parsing; they're logged and skipped.
   - If a critical property (UID, DTSTART) is missing, the entire VEVENT is dropped.

---

## Testing

### Manual Test with plua

1. **Test the parser library locally:**
   ```bash
   plua --offline iCal.lua
   ```

2. **Test the QuickApp:**
   ```bash
   plua --fibaro --nodebugger iCloud_Calendar.lua
   ```
   - Set the `calendarUrl` variable before running.
   - Trigger the download via debug console or plua HTTP API.

### Unit Tests (Example)

```lua
-- test_ical.lua
local iCal = require("iCal")

-- Test 1: Single event
local input1 = [[BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//Test//EN
BEGIN:VEVENT
UID:test1@example.com
DTSTART:20260410T140000Z
DTEND:20260410T150000Z
SUMMARY:Test Event
END:VEVENT
END:VCALENDAR]]

local result = iCal:parse(input1)
assert(#result.events == 1, "Expected 1 event")
assert(result.events[1].summary == "Test Event", "Event summary mismatch")
print("✓ Test 1 passed: Single event")

-- Test 2: Recurring event (5 instances)
local input2 = [[BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:recurring@example.com
DTSTART:20260410T100000Z
DTEND:20260410T110000Z
SUMMARY:Recurring Meeting
RRULE:FREQ=WEEKLY;COUNT=5
END:VEVENT
END:VCALENDAR]]

local result2 = iCal:parse(input2)
assert(#result2.events == 5, "Expected 5 recurring instances")
print("✓ Test 2 passed: RRULE expansion")

-- Test 3: All-day event
local input3 = [[BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:allday@example.com
DTSTART;VALUE=DATE:20260410
SUMMARY:All-Day Event
END:VEVENT
END:VCALENDAR]]

local result3 = iCal:parse(input3)
assert(result3.events[1].isAllDay == true, "Expected all-day flag")
print("✓ Test 3 passed: All-day event")

print("\nAll tests passed!")
```

---

## Output Structure

### Events Table

Each event in the results table has this structure:

```lua
{
    uid = "unique-identifier@domain.com",
    summary = "Event Title",
    description = "Full description text (if available)",
    location = "Meeting room or address (if available)",
    dtstart = 1744065000,           -- Unix timestamp (seconds)
    dtend = 1744072200,             -- Unix timestamp (seconds)
    isAllDay = false,               -- true for DATE-only events
    organizer = "organizer@example.com",
    attendees = {                   -- Array of email addresses
        "person1@example.com",
        "person2@example.com"
    },
    lastModified = 1744000000,      -- Last modification time
    rrule = "FREQ=WEEKLY;COUNT=10"  -- Original recurrence rule (if was recurring, empty otherwise)
}
```

---

## iCloud Calendar Share Link Format

**Public (Read-Only) Link:**
```
webcal://p64-caldav.icloud.com/published/2/MTMxNjYxNDMwMTMxNjYxNN60jsE0ciSlGdK4hSjmZOZF01LBw1p8vFrjxFq9NvCD
```

**Notes:**
- Replace `webcal://` with `https://` if needed
- The long token at the end (starting with `2/MTM...`) is unique to your calendar
- Do not share this link with anyone you don't trust; it grants read access to your calendar

---

## Future Enhancements

1. **Full RRULE Support**
   - Implement BYSETPOS, BYHOUR, BYMINUTE
   - Handle complex weekly recurrence rules
   
2. **Timezone Awareness**
   - Parse VTIMEZONE components
   - Apply TZID offsets to event times
   - Support DST transitions

3. **Component Expansion**
   - Add VTODO parsing (to-do items)
   - Add VALARM parsing (alarm/notification details)
   - Add VJOURNAL parsing (journal entries)

4. **QuickApp Enhancements**
   - Display alarm information
   - Show attendee list with RSVP status
   - Sync to HC3 scenes/automations
   - Schedule actions based on upcoming events

5. **Performance Optimization**
   - Pagination for large calendars
   - Incremental parsing (stream-based)
   - Caching of parsed results

---

## Development Notes

### RFC 2445 Compliance

The parser implements a **subset** of RFC 2445 (iCalendar specification):

- ✅ **Implemented:** VCALENDAR, VEVENT, SUMMARY, DTSTART, DTEND, UID, DESCRIPTION, LOCATION, ORGANIZER, ATTENDEE, RRULE, EXDATE, LAST-MODIFIED
- ⚠️ **Partial:** Line folding, property parameters (VALUE, TZID, LANGUAGE)
- ❌ **Not Implemented:** VALARM, VTODO, VJOURNAL, VFREEBUSY, VTIMEZONE, RECURRENCE-ID, time zone offsets

For full RFC 2445 documentation, see: https://www.ietf.org/rfc/rfc2445.txt

### Code Architecture

```
iCloud_Calendar.lua (QuickApp main)
    ├── parseICalEvents()     -- Embedded simple parser
    ├── onInit()              -- Setup
    ├── btnDownload()         -- Download button handler
    └── parseAndDisplayCalendar() -- Process & display

iCal.lua (Standalone library)
    ├── parseDateTime()       -- Convert iCal date to table
    ├── dateToTimestamp()     -- Convert date table to Unix time
    ├── parseRRULE()          -- Expand recurrence
    ├── parseContentLine()    -- Parse property lines
    └── iCal:parse()          -- Main parser
```

---

## Support & Troubleshooting

### "Error: No calendar URL set"
- Add your iCloud calendar URL to the `calendarUrl` QuickApp variable.
- Format: `webcal://p64-caldav.icloud.com/published/2/...`

### "Error: HTTP 404" or "HTTP 403"
- Verify the calendar URL is correct and accessible.
- If using a private calendar, ensure the share link grants public access.
- Try accessing the URL in a browser to verify.

### "Error: Network failure"
- Check HC3 internet connectivity.
- Verify the URL is reachable from your network.
- Try a different calendar URL to test.

### "Events: 0" (No events found)
- Increase the `daysAhead` variable to look further into the future.
- Check that your calendar actually has events in the specified date range.
- Review the HC3 debug log for parser warnings.

### Malformed events are skipped
- The parser operates in lenient mode: badly-formed events are logged and skipped.
- Check the debug console for "Skipped" messages.
- Consider exporting your calendar to a desktop app to validate it first.

---

## License & Attribution

This iCal parser is provided as-is for use with Fibaro HC3 QuickApps.

RFC 2445 (iCalendar) specification courtesy of the IETF.

---

## Version History

- **v1.0** (2026-04-06) — Initial release
  - Basic iCal parser
  - Simple RRULE expansion (DAILY, WEEKLY, MONTHLY, YEARLY)
  - QuickApp for iCloud calendar download
  - Date range filtering
