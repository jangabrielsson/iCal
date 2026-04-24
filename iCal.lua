--[[
iCal Parser Library (RFC 2445)
Parses iCalendar format and returns structured event table with RRULE expansion.
]]

local iCal = {}

-- Helper: Convert iCal datetime to Unix timestamp
-- Supports UTC (20260406T143000Z), local (20260406T143000), and DATE (20260406)
local function parseDateTime(dtString, isDate)
    if not dtString then return nil end
    
    dtString = tostring(dtString):gsub("Z$", "")  -- Remove Z suffix for UTC
    
    if isDate or #dtString == 8 then
        -- DATE format: YYYYMMDD
        local y, m, d = dtString:match("(%d%d%d%d)(%d%d)(%d%d)")
        if y and m and d then
            return { year = tonumber(y), month = tonumber(m), day = tonumber(d), 
                     hour = 0, min = 0, sec = 0, isDate = true }
        end
    else
        -- DATETIME format: YYYYMMDDThhmmss
        local y, m, d, h, mi, s = dtString:match("(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)")
        if y and m and d then
            return { year = tonumber(y), month = tonumber(m), day = tonumber(d), 
                     hour = tonumber(h), min = tonumber(mi), sec = tonumber(s), isDate = false }
        end
    end
    return nil
end

-- Helper: Convert Lua date table to Unix timestamp
local function dateToTimestamp(tbl)
    if not tbl then return nil end
    -- Simplified: use os.time() with UTC assumption
    return os.time(tbl)
end

-- Helper: Check if date is within range
local function dateInRange(dateTable, startTs, endTs)
    if not dateTable then return false end
    local ts = dateToTimestamp(dateTable)
    if not ts then return false end
    return ts >= startTs and ts <= endTs
end

-- Helper: Add days to date table
local function addDays(dateTable, days)
    if not dateTable then return nil end
    local ts = dateToTimestamp(dateTable) + (days * 86400)
    return os.date("*t", ts)
end

-- Helper: Parse RRULE string and generate occurrences
-- Supports: FREQ, COUNT, UNTIL, INTERVAL, BYDAY, BYMONTHDAY
local function parseRRULE(rruleStr, dtstart, endTs)
    if not rruleStr or not dtstart then return {} end
    
    local rules = {}
    for part in rruleStr:gmatch("([^;]+)") do
        local k, v = part:match("([^=]+)=(.+)")
        if k and v then
            rules[k:upper()] = v
        end
    end
    
    local occurrences = {}
    local freq = rules.FREQ
    local count = tonumber(rules.COUNT) or 999999
    local until_val = rules.UNTIL and parseDateTime(rules.UNTIL) or nil
    local interval = tonumber(rules.INTERVAL) or 1
    local byday = rules.BYDAY and rules.BYDAY:gmatch("%w%w") or {}
    local bymonthday = rules.BYMONTHDAY and rules.BYMONTHDAY:gmatch("[^,]+") or {}
    
    local current = dtstart
    local occurrenceCount = 0
    
    if not freq then return {} end
    
    -- Generate occurrences (simplified implementation)
    for i = 1, count do
        local ts = dateToTimestamp(current)
        
        if ts > endTs then break end
        if until_val and ts > dateToTimestamp(until_val) then break end
        
        occurrences[#occurrences + 1] = current
        occurrenceCount = occurrenceCount + 1
        
        -- Increment by frequency (simplified: only support basic increments)
        if freq == "DAILY" then
            current = addDays(current, interval)
        elseif freq == "WEEKLY" then
            current = addDays(current, 7 * interval)
        elseif freq == "MONTHLY" then
            current.month = current.month + interval
            if current.month > 12 then
                current.year = current.year + 1
                current.month = current.month - 12
            end
        elseif freq == "YEARLY" then
            current.year = current.year + interval
        else
            break
        end
    end
    
    return occurrences
end

-- Helper: Unescape iCal text (reverse of escaping)
local function unescapeText(text)
    if not text then return "" end
    return text:gsub("\\n", "\n"):gsub("\\,", ","):gsub("\\;", ";"):gsub("\\\\", "\\")
end

-- Helper: Parse a content line (handles line folding)
local function parseContentLine(line)
    -- Line format: PROPERTY;PARAM1=VALUE1;PARAM2=VALUE2:VALUE
    local before_colon, value = line:match("^(.-)%s*:%s*(.*)$")
    if not before_colon or not value then
        return nil, nil, nil
    end
    
    local parts = {}
    for part in before_colon:gmatch("[^;]+") do
        table.insert(parts, part)
    end
    
    local property = parts[1]:upper()
    local params = {}
    
    for i = 2, #parts do
        local k, v = parts[i]:match("^([^=]+)=(.*)$")
        if k and v then
            params[k:upper()] = v
        end
    end
    
    return property, params, value
end

-- Main parser function
function iCal:parse(icalData, startDate, endDate)
    startDate = startDate or os.date("*t", os.time())
    endDate = endDate or os.date("*t", os.time() + 30 * 86400)  -- 30 days default
    
    local startTs = dateToTimestamp(startDate)
    local endTs = dateToTimestamp(endDate)
    
    local result = { events = {} }
    local lines = {}
    local inComponent = false
    local componentType = nil
    local currentEvent = nil
    local lineBuffer = ""
    
    -- Split into lines and handle folding
    for line in icalData:gmatch("[^\r\n]+") do
        if line:match("^ ") then
            -- Continuation line (folded)
            lineBuffer = lineBuffer .. line:sub(2)
        else
            if lineBuffer ~= "" then
                table.insert(lines, lineBuffer)
            end
            lineBuffer = line
        end
    end
    if lineBuffer ~= "" then
        table.insert(lines, lineBuffer)
    end
    
    -- Parse lines
    for _, line in ipairs(lines) do
        local prop, params, value = parseContentLine(line)
        
        if not prop then
            -- Malformed line, skip
            goto continue
        end
        
        if prop == "BEGIN" then
            if value:upper() == "VEVENT" then
                currentEvent = {
                    uid = "",
                    summary = "",
                    description = "",
                    location = "",
                    dtstart = nil,
                    dtend = nil,
                    isAllDay = false,
                    organizer = "",
                    attendees = {},
                    lastModified = nil,
                    rrule = "",
                    exdate = {},
                }
                inComponent = true
                componentType = "VEVENT"
            end
        elseif prop == "END" then
            if value:upper() == "VEVENT" and currentEvent then
                inComponent = false
                
                -- If event has RRULE, expand it
                if currentEvent.rrule ~= "" then
                    local occurrences = parseRRULE(currentEvent.rrule, currentEvent.dtstart, endTs)
                    for _, occ in ipairs(occurrences) do
                        local occTs = dateToTimestamp(occ)
                        
                        -- Skip if in EXDATE
                        local isExcluded = false
                        for _, exdate in ipairs(currentEvent.exdate) do
                            if dateToTimestamp(exdate) == occTs then
                                isExcluded = true
                                break
                            end
                        end
                        
                        if not isExcluded and dateInRange(occ, startTs, endTs) then
                            local eventCopy = {}
                            for k, v in pairs(currentEvent) do
                                if k ~= "exdate" then
                                    eventCopy[k] = v
                                end
                            end
                            eventCopy.dtstart = occTs
                            if currentEvent.dtend then
                                local duration = dateToTimestamp(currentEvent.dtend) - dateToTimestamp(currentEvent.dtstart)
                                eventCopy.dtend = occTs + duration
                            end
                            if eventCopy.lastModified then
                                eventCopy.lastModified = dateToTimestamp(eventCopy.lastModified)
                            end
                            table.insert(result.events, eventCopy)
                        end
                    end
                else
                    -- Non-recurring event: add if in range
                    if currentEvent.dtstart then
                        if dateInRange(currentEvent.dtstart, startTs, endTs) then
                            local eventCopy = {}
                            for k, v in pairs(currentEvent) do
                                if k ~= "exdate" then
                                    eventCopy[k] = v
                                end
                            end
                            eventCopy.dtstart = dateToTimestamp(currentEvent.dtstart)
                            if currentEvent.dtend then
                                eventCopy.dtend = dateToTimestamp(currentEvent.dtend)
                            end
                            if currentEvent.lastModified then
                                eventCopy.lastModified = dateToTimestamp(currentEvent.lastModified)
                            end
                            table.insert(result.events, eventCopy)
                        end
                    end
                end
                
                currentEvent = nil
                componentType = nil
            end
        elseif inComponent and componentType == "VEVENT" and currentEvent then
            -- Parse VEVENT properties
            if prop == "SUMMARY" then
                currentEvent.summary = unescapeText(value)
            elseif prop == "DTSTART" then
                currentEvent.dtstart = parseDateTime(value, params.VALUE == "DATE")
                currentEvent.isAllDay = params.VALUE == "DATE"
            elseif prop == "DTEND" then
                currentEvent.dtend = parseDateTime(value, params.VALUE == "DATE")
            elseif prop == "UID" then
                currentEvent.uid = value
            elseif prop == "DESCRIPTION" then
                currentEvent.description = unescapeText(value)
            elseif prop == "LOCATION" then
                currentEvent.location = unescapeText(value)
            elseif prop == "ORGANIZER" then
                currentEvent.organizer = value:match("MAILTO:(.+)") or value
            elseif prop == "ATTENDEE" then
                local email = value:match("MAILTO:(.+)") or value
                table.insert(currentEvent.attendees, email)
            elseif prop == "LAST-MODIFIED" then
                currentEvent.lastModified = parseDateTime(value)
            elseif prop == "RRULE" then
                currentEvent.rrule = value
            elseif prop == "EXDATE" then
                table.insert(currentEvent.exdate, parseDateTime(value, params.VALUE == "DATE"))
            end
        end
        
        ::continue::
    end
    
    return result
end

return iCal
