-- Test suite for iCal.lua. Plain Lua, no plua needed.
-- Run: lua test_ical.lua

local iCal = require("iCal")

local passed, failed = 0, 0
local function ok(cond, msg)
    if cond then
        passed = passed + 1
        print("  PASS: " .. msg)
    else
        failed = failed + 1
        print("  FAIL: " .. msg)
    end
end
local function eq(a, b, msg) ok(a == b, msg .. " (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")") end

local function utcOffset()
    local t = os.time()
    return os.difftime(t, os.time(os.date("!*t", t)))
end
local function utcTs(y, m, d, h, mi, s)
    return os.time({year=y, month=m, day=d, hour=h or 0, min=mi or 0, sec=s or 0}) + utcOffset()
end
local function localTs(y, m, d, h, mi, s)
    return os.time({year=y, month=m, day=d, hour=h or 0, min=mi or 0, sec=s or 0})
end

-- ---------- Test 1: single UTC event ----------
print("Test 1: single UTC event")
do
    local ics = table.concat({
        "BEGIN:VCALENDAR",
        "BEGIN:VEVENT",
        "UID:e1@x",
        "SUMMARY:Hello",
        "DTSTART:20260410T100000Z",
        "DTEND:20260410T110000Z",
        "END:VEVENT",
        "END:VCALENDAR",
    }, "\r\n")
    local r = iCal.parse(ics, utcTs(2026,1,1), utcTs(2026,12,31))
    eq(#r.events, 1, "one event")
    eq(r.events[1].uid, "e1@x", "uid")
    eq(r.events[1].summary, "Hello", "summary")
    eq(r.events[1].dtstart, utcTs(2026,4,10,10,0,0), "dtstart UTC")
    eq(r.events[1].dtend, utcTs(2026,4,10,11,0,0), "dtend UTC")
    eq(r.events[1].isAllDay, false, "not all day")
end

-- ---------- Test 2: all-day event ----------
print("Test 2: all-day event")
do
    local ics = table.concat({
        "BEGIN:VEVENT",
        "UID:e2",
        "SUMMARY:Holiday",
        "DTSTART;VALUE=DATE:20260601",
        "END:VEVENT",
    }, "\r\n")
    local r = iCal.parse(ics, localTs(2026,1,1), localTs(2026,12,31))
    eq(#r.events, 1, "one event")
    eq(r.events[1].isAllDay, true, "is all day")
    eq(r.events[1].dtstart, localTs(2026,6,1,0,0,0), "midnight local")
end

-- ---------- Test 3: RRULE DAILY count ----------
print("Test 3: RRULE DAILY COUNT=3")
do
    local ics = table.concat({
        "BEGIN:VEVENT",
        "UID:e3",
        "SUMMARY:Daily",
        "DTSTART:20260410T100000Z",
        "RRULE:FREQ=DAILY;COUNT=3",
        "END:VEVENT",
    }, "\r\n")
    local r = iCal.parse(ics, utcTs(2026,4,1), utcTs(2026,5,1))
    eq(#r.events, 3, "3 occurrences")
    eq(r.events[1].dtstart, utcTs(2026,4,10,10,0,0), "day 1")
    eq(r.events[2].dtstart, utcTs(2026,4,11,10,0,0), "day 2")
    eq(r.events[3].dtstart, utcTs(2026,4,12,10,0,0), "day 3")
end

-- ---------- Test 4: RRULE WEEKLY UNTIL ----------
print("Test 4: RRULE WEEKLY UNTIL")
do
    local ics = table.concat({
        "BEGIN:VEVENT",
        "UID:e4",
        "SUMMARY:Weekly",
        "DTSTART:20260410T100000Z",
        "RRULE:FREQ=WEEKLY;UNTIL=20260501T100000Z",
        "END:VEVENT",
    }, "\r\n")
    local r = iCal.parse(ics, utcTs(2026,4,1), utcTs(2026,6,1))
    eq(#r.events, 4, "4 weekly occurrences (Apr 10/17/24, May 1)")
end

-- ---------- Test 5: EXDATE ----------
print("Test 5: EXDATE removes occurrence")
do
    local ics = table.concat({
        "BEGIN:VEVENT",
        "UID:e5",
        "SUMMARY:Daily",
        "DTSTART:20260410T100000Z",
        "RRULE:FREQ=DAILY;COUNT=4",
        "EXDATE:20260411T100000Z",
        "END:VEVENT",
    }, "\r\n")
    local r = iCal.parse(ics, utcTs(2026,4,1), utcTs(2026,5,1))
    eq(#r.events, 3, "3 left after exclusion")
    for _, e in ipairs(r.events) do
        ok(e.dtstart ~= utcTs(2026,4,11,10,0,0), "Apr 11 excluded")
    end
end

-- ---------- Test 6: attendees + organizer ----------
print("Test 6: organizer + attendees")
do
    local ics = table.concat({
        "BEGIN:VEVENT",
        "UID:e6",
        "SUMMARY:Meeting",
        "DTSTART:20260410T100000Z",
        "ORGANIZER:mailto:boss@example.com",
        "ATTENDEE;CN=Alice:mailto:alice@example.com",
        "ATTENDEE;CN=Bob:MAILTO:bob@example.com",
        "END:VEVENT",
    }, "\r\n")
    local r = iCal.parse(ics, utcTs(2026,1,1), utcTs(2026,12,31))
    eq(r.events[1].organizer, "boss@example.com", "organizer email")
    eq(#r.events[1].attendees, 2, "2 attendees")
    eq(r.events[1].attendees[1], "alice@example.com", "alice")
    eq(r.events[1].attendees[2], "bob@example.com", "bob (uppercase MAILTO)")
end

-- ---------- Test 7: text escaping ----------
print("Test 7: text escapes")
do
    local ics = table.concat({
        "BEGIN:VEVENT",
        "UID:e7",
        "SUMMARY:Line1\\nLine2\\, with comma\\; semi\\\\ backslash",
        "DTSTART:20260410T100000Z",
        "END:VEVENT",
    }, "\r\n")
    local r = iCal.parse(ics, utcTs(2026,1,1), utcTs(2026,12,31))
    eq(r.events[1].summary, "Line1\nLine2, with comma; semi\\ backslash", "escapes")
end

-- ---------- Test 8: line folding ----------
print("Test 8: line folding")
do
    local ics = "BEGIN:VEVENT\r\nUID:e8\r\nSUMMARY:Hello\r\n World\r\nDTSTART:20260410T100000Z\r\nEND:VEVENT\r\n"
    local r = iCal.parse(ics, utcTs(2026,1,1), utcTs(2026,12,31))
    eq(r.events[1].summary, "HelloWorld", "folded line joined")
end

-- ---------- Test 9: multi-event sort ----------
print("Test 9: multi-event sort")
do
    local ics = table.concat({
        "BEGIN:VEVENT","UID:b","SUMMARY:B","DTSTART:20260412T100000Z","END:VEVENT",
        "BEGIN:VEVENT","UID:a","SUMMARY:A","DTSTART:20260411T100000Z","END:VEVENT",
        "BEGIN:VEVENT","UID:c","SUMMARY:C","DTSTART:20260413T100000Z","END:VEVENT",
    }, "\r\n")
    local r = iCal.parse(ics, utcTs(2026,1,1), utcTs(2026,12,31))
    eq(#r.events, 3, "3 events")
    eq(r.events[1].uid, "a", "sorted #1")
    eq(r.events[2].uid, "b", "sorted #2")
    eq(r.events[3].uid, "c", "sorted #3")
end

-- ---------- Test 10: VTIMEZONE/VTODO ignored, VALARM nested skipped ----------
print("Test 10: ignore VTIMEZONE / VTODO / VALARM")
do
    local ics = table.concat({
        "BEGIN:VCALENDAR",
        "BEGIN:VTIMEZONE","TZID:Europe/Stockholm","END:VTIMEZONE",
        "BEGIN:VTODO","UID:todo1","SUMMARY:nope","END:VTODO",
        "BEGIN:VEVENT",
        "UID:keep","SUMMARY:Keep","DTSTART:20260410T100000Z",
        "BEGIN:VALARM","ACTION:DISPLAY","DESCRIPTION:reminder","END:VALARM",
        "END:VEVENT",
        "END:VCALENDAR",
    }, "\r\n")
    local r = iCal.parse(ics, utcTs(2026,1,1), utcTs(2026,12,31))
    eq(#r.events, 1, "only the VEVENT survives")
    eq(r.events[1].uid, "keep", "right uid")
    eq(r.events[1].summary, "Keep", "VALARM did not overwrite summary")
end

-- ---------- Test 11: window filtering ----------
print("Test 11: window filtering")
do
    local ics = table.concat({
        "BEGIN:VEVENT","UID:1","DTSTART:20260101T100000Z","SUMMARY:before","END:VEVENT",
        "BEGIN:VEVENT","UID:2","DTSTART:20260601T100000Z","SUMMARY:in","END:VEVENT",
        "BEGIN:VEVENT","UID:3","DTSTART:20271201T100000Z","SUMMARY:after","END:VEVENT",
    }, "\r\n")
    local r = iCal.parse(ics, utcTs(2026,5,1), utcTs(2026,12,31))
    eq(#r.events, 1, "only the event in window")
    eq(r.events[1].uid, "2", "right uid")
end

-- ---------- Test 12: ':' in property value ----------
print("Test 12: colon in URI value")
do
    local ics = table.concat({
        "BEGIN:VEVENT",
        "UID:e12",
        "SUMMARY:Notes",
        "DTSTART:20260410T100000Z",
        "DESCRIPTION:see https://example.com:8080/path",
        "END:VEVENT",
    }, "\r\n")
    local r = iCal.parse(ics, utcTs(2026,1,1), utcTs(2026,12,31))
    eq(r.events[1].description, "see https://example.com:8080/path", "URL preserved")
end

print()
print(string.format("=== Summary: %d passed, %d failed ===", passed, failed))
os.exit(failed == 0 and 0 or 1)
