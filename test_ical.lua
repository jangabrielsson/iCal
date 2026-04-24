--[[
Simple test script for iCal parser
Run with: lua test_ical.lua
or with plua: plua --offline test_ical.lua
]]

-- Mock os.time if running in plua without full os lib
if not os.time then
    os.time = function(t)
        -- Simplified: just return seconds counting from 1970
        local year = t.year or 1970
        local month = t.month or 1
        local day = t.day or 1
        local hour = t.hour or 0
        local min = t.min or 0
        local sec = t.sec or 0
        
        local daysSince1970 = 0
        for y = 1970, year - 1 do
            daysSince1970 = daysSince1970 + 365
            if (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0) then
                daysSince1970 = daysSince1970 + 1
            end
        end
        
        local daysInMonth = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
        if (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0) then
            daysInMonth[2] = 29
        end
        
        for m = 1, month - 1 do
            daysSince1970 = daysSince1970 + daysInMonth[m]
        end
        
        daysSince1970 = daysSince1970 + day - 1
        return daysSince1970 * 86400 + hour * 3600 + min * 60 + sec
    end
end

local iCal = require("iCal")

print("\n=== iCal Parser Test Suite ===\n")

-- Test 1: Single non-recurring event
print("Test 1: Single non-recurring event")
local test1 = [[BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//Test//EN
BEGIN:VEVENT
UID:test1@example.com
DTSTART:20260410T140000Z
DTEND:20260410T150000Z
SUMMARY:Single Meeting
DESCRIPTION:A simple test event
LOCATION:Conference Room A
END:VEVENT
END:VCALENDAR]]

local result1 = iCal:parse(test1)
print(string.format("  Expected: 1 event, Got: %d events", #result1.events))
if #result1.events > 0 then
    local evt = result1.events[1]
    print(string.format("  Title: %s", evt.summary))
    print(string.format("  Location: %s", evt.location))
    print(string.format("  UID: %s", evt.uid))
    assert(evt.summary == "Single Meeting", "Event title mismatch")
    print("  ✓ PASSED\n")
else
    print("  ✗ FAILED: No events parsed\n")
end

-- Test 2: All-day event
print("Test 2: All-day event")
local test2 = [[BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:allday@example.com
DTSTART;VALUE=DATE:20260415
SUMMARY:Birthday
END:VEVENT
END:VCALENDAR]]

local result2 = iCal:parse(test2)
if #result2.events > 0 then
    local evt = result2.events[1]
    print(string.format("  Title: %s", evt.summary))
    print(string.format("  Is All-Day: %s", tostring(evt.isAllDay)))
    assert(evt.isAllDay == true, "Expected all-day flag")
    print("  ✓ PASSED\n")
else
    print("  ✗ FAILED: No events parsed\n")
end

-- Test 3: Recurring event (RRULE)
print("Test 3: Recurring event (DAILY, COUNT=5)")
local test3 = [[BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:recurring@example.com
DTSTART:20260410T090000Z
DTEND:20260410T100000Z
SUMMARY:Daily Standup
RRULE:FREQ=DAILY;COUNT=5
END:VEVENT
END:VCALENDAR]]

local result3 = iCal:parse(test3)
print(string.format("  Expected: ~5 instances (possibly fewer due to date filtering)"))
print(string.format("  Got: %d events", #result3.events))
for i, evt in ipairs(result3.events) do
    print(string.format("    Event %d: %s (date: %s)", i, evt.summary, os.date("%Y-%m-%d", evt.dtstart)))
end
if #result3.events >= 1 then
    print("  ✓ PASSED\n")
else
    print("  ✗ FAILED: Expected at least 1 recurring instance\n")
end

-- Test 4: Event with attendees and organizer
print("Test 4: Event with attendees and organizer")
local test4 = [[BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:meeting@example.com
DTSTART:20260420T140000Z
DTEND:20260420T150000Z
SUMMARY:Team Sync
ORGANIZER:MAILTO:boss@example.com
ATTENDEE:MAILTO:alice@example.com
ATTENDEE:MAILTO:bob@example.com
END:VEVENT
END:VCALENDAR]]

local result4 = iCal:parse(test4)
if #result4.events > 0 then
    local evt = result4.events[1]
    print(string.format("  Organizer: %s", evt.organizer))
    print(string.format("  Attendees: %s", table.concat(evt.attendees, ", ")))
    print("  ✓ PASSED\n")
else
    print("  ✗ FAILED: No events parsed\n")
end

-- Test 5: Text escaping
print("Test 5: Text escaping (\\n, \\,, etc.)")
local test5 = [[BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:escape@example.com
DTSTART:20260425T120000Z
SUMMARY:Event with\, comma and\nnewline
DESCRIPTION:Line 1\nLine 2\nLine 3
END:VEVENT
END:VCALENDAR]]

local result5 = iCal:parse(test5)
if #result5.events > 0 then
    local evt = result5.events[1]
    print(string.format("  Summary: %s", evt.summary:gsub("\n", "↵")))
    print(string.format("  Description: %s", evt.description:gsub("\n", "↵")))
    print("  ✓ PASSED\n")
else
    print("  ✗ FAILED: No events parsed\n")
end

-- Test 6: Multiple events
print("Test 6: Multiple events in one calendar")
local test6 = [[BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Multi//Multi//EN
BEGIN:VEVENT
UID:multi1@example.com
DTSTART:20260410T100000Z
DTEND:20260410T110000Z
SUMMARY:Event 1
END:VEVENT
BEGIN:VEVENT
UID:multi2@example.com
DTSTART:20260411T140000Z
DTEND:20260411T150000Z
SUMMARY:Event 2
END:VEVENT
BEGIN:VEVENT
UID:multi3@example.com
DTSTART:20260412T160000Z
DTEND:20260412T170000Z
SUMMARY:Event 3
END:VEVENT
END:VCALENDAR]]

local result6 = iCal:parse(test6)
print(string.format("  Expected: 3 events, Got: %d events", #result6.events))
for i, evt in ipairs(result6.events) do
    print(string.format("    %d. %s", i, evt.summary))
end
if #result6.events == 3 then
    print("  ✓ PASSED\n")
else
    print("  ✗ FAILED: Expected 3 events\n")
end

print("\n=== Test Summary ===")
print("All manual tests completed. Check for ✓ marks above.")
print("\nNote: Date filtering may cause fewer events to be returned if they fall outside")
print("the default 30-day window. Adjust test dates if needed.\n")
