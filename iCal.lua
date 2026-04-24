--[[
iCal Parser Library (RFC 5545 / RFC 2445)

Parses iCalendar text into a flat list of expanded events filtered to a
[startTs, endTs] window. Also offers an HTTP download helper.

Loading:
  -- HC3 / QuickApp (no require()):
  --%%file:iCal.lua,ical
  local iCal = fibaro.iCal

  -- Plain Lua / tests:
  local iCal = require("iCal")

API:
  iCal.parse(text, startTs, endTs)       -> { events = {...} }
  iCal.download(url, opts, callback)     callback(err, events, raw)
]]

local iCal = {}

-- ---------------------------------------------------------------------------
-- Time helpers
-- ---------------------------------------------------------------------------

local function localUtcOffset()
    local t = os.time()
    return os.difftime(t, os.time(os.date("!*t", t)))
end

local function cleanDateTable(t)
    return { year = t.year, month = t.month, day = t.day,
             hour = t.hour or 0, min = t.min or 0, sec = t.sec or 0 }
end

local function parseDateTime(value, forceDate)
    if not value then return nil, false end
    value = tostring(value)

    if forceDate or #value == 8 then
        local y, m, d = value:match("^(%d%d%d%d)(%d%d)(%d%d)$")
        if y then
            return os.time(cleanDateTable{year=tonumber(y), month=tonumber(m), day=tonumber(d)}), true
        end
        return nil, false
    end

    local isUtc = value:sub(-1) == "Z"
    if isUtc then value = value:sub(1, -2) end

    local y, m, d, h, mi, s =
        value:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)$")
    if not y then return nil, false end

    local ts = os.time(cleanDateTable{
        year=tonumber(y), month=tonumber(m), day=tonumber(d),
        hour=tonumber(h), min=tonumber(mi), sec=tonumber(s),
    })
    if isUtc then ts = ts + localUtcOffset() end
    return ts, false
end

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

local function unescapeText(s)
    if not s then return "" end
    s = s:gsub("\\\\", "\0")
    s = s:gsub("\\[nN]", "\n")
    s = s:gsub("\\,", ",")
    s = s:gsub("\\;", ";")
    s = s:gsub("\0", "\\")
    return s
end

local function unfold(text)
    local out = {}
    local buf
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw:gsub("\r$", "")
        if line:match("^[ \t]") then
            if buf then buf = buf .. line:sub(2) end
        else
            if buf then out[#out+1] = buf end
            buf = line
        end
    end
    if buf and buf ~= "" then out[#out+1] = buf end
    return out
end

local function parseLine(line)
    local i, n, inQuote = 1, #line, false
    while i <= n do
        local c = line:sub(i, i)
        if c == '"' then
            inQuote = not inQuote
        elseif c == ":" and not inQuote then
            break
        end
        i = i + 1
    end
    if i > n then return nil end

    local head = line:sub(1, i-1)
    local value = line:sub(i+1)

    local name, paramStr = head:match("^([^;]+)(.*)$")
    if not name then return nil end
    name = name:upper()

    local params = {}
    for k, v in (paramStr or ""):gmatch(";([^=]+)=([^;]+)") do
        params[k:upper()] = v:gsub('^"', ""):gsub('"$', "")
    end
    return name, params, value
end

-- ---------------------------------------------------------------------------
-- RRULE expansion
-- ---------------------------------------------------------------------------

local MAX_INSTANCES = 5000

local function parseRRULE(rule)
    local out = {}
    for kv in rule:gmatch("[^;]+") do
        local k, v = kv:match("^([^=]+)=(.+)$")
        if k then out[k:upper()] = v end
    end
    return out
end

local function stepDateByMonths(ts, months)
    local d = os.date("*t", ts)
    d.month = d.month + months
    return os.time(cleanDateTable(d))
end

local function expandRRULE(event, windowStart, windowEnd)
    local rule = parseRRULE(event.rrule)
    local freq = rule.FREQ
    if not freq then return { event.dtstart } end

    local interval = tonumber(rule.INTERVAL) or 1
    local count = tonumber(rule.COUNT) or MAX_INSTANCES
    local untilTs
    if rule.UNTIL then
        untilTs = parseDateTime(rule.UNTIL)
    end

    local instances = {}
    local ts = event.dtstart
    local n = 0

    while n < count and #instances < MAX_INSTANCES do
        if untilTs and ts > untilTs then break end
        if ts > windowEnd then break end
        if ts >= windowStart then
            instances[#instances+1] = ts
        end
        n = n + 1

        if freq == "DAILY" then
            ts = ts + 86400 * interval
        elseif freq == "WEEKLY" then
            ts = ts + 7 * 86400 * interval
        elseif freq == "MONTHLY" then
            ts = stepDateByMonths(ts, interval)
        elseif freq == "YEARLY" then
            ts = stepDateByMonths(ts, 12 * interval)
        else
            break
        end
    end
    return instances
end

-- ---------------------------------------------------------------------------
-- Main parse
-- ---------------------------------------------------------------------------

function iCal.parse(text, startTs, endTs)
    startTs = startTs or os.time()
    endTs   = endTs   or (startTs + 30 * 86400)

    local lines = unfold(text or "")
    local events = {}
    local cur, skipDepth = nil, 0

    for _, line in ipairs(lines) do
        local name, params, value = parseLine(line)
        if name then
            if name == "BEGIN" then
                local v = value:upper()
                if v == "VEVENT" then
                    cur = { attendees = {}, exdates = {} }
                elseif v == "VCALENDAR" then
                    -- transparent
                else
                    skipDepth = skipDepth + 1
                end
            elseif name == "END" then
                local v = value:upper()
                if v == "VEVENT" then
                    if cur and cur.dtstart then
                        if cur.rrule then
                            local times = expandRRULE(cur, startTs, endTs)
                            local exclude = {}
                            for _, ex in ipairs(cur.exdates) do exclude[ex] = true end
                            local duration = cur.dtend and (cur.dtend - cur.dtstart) or nil
                            for _, t in ipairs(times) do
                                if not exclude[t] then
                                    events[#events+1] = {
                                        uid = cur.uid, summary = cur.summary or "",
                                        description = cur.description or "",
                                        location = cur.location or "",
                                        organizer = cur.organizer,
                                        attendees = cur.attendees,
                                        dtstart = t,
                                        dtend = duration and (t + duration) or nil,
                                        isAllDay = cur.isAllDay or false,
                                        lastModified = cur.lastModified,
                                    }
                                end
                            end
                        elseif cur.dtstart >= startTs and cur.dtstart <= endTs then
                            events[#events+1] = {
                                uid = cur.uid, summary = cur.summary or "",
                                description = cur.description or "",
                                location = cur.location or "",
                                organizer = cur.organizer,
                                attendees = cur.attendees,
                                dtstart = cur.dtstart, dtend = cur.dtend,
                                isAllDay = cur.isAllDay or false,
                                lastModified = cur.lastModified,
                            }
                        end
                    end
                    cur = nil
                elseif v == "VCALENDAR" then
                    -- transparent
                else
                    if skipDepth > 0 then skipDepth = skipDepth - 1 end
                end
            elseif skipDepth == 0 and cur then
                local isDate = (params.VALUE or ""):upper() == "DATE"
                if name == "SUMMARY" then
                    cur.summary = unescapeText(value)
                elseif name == "DESCRIPTION" then
                    cur.description = unescapeText(value)
                elseif name == "LOCATION" then
                    cur.location = unescapeText(value)
                elseif name == "UID" then
                    cur.uid = value
                elseif name == "DTSTART" then
                    local ts, allDay = parseDateTime(value, isDate)
                    cur.dtstart = ts
                    cur.isAllDay = allDay
                elseif name == "DTEND" then
                    cur.dtend = parseDateTime(value, isDate)
                elseif name == "RRULE" then
                    cur.rrule = value
                elseif name == "EXDATE" then
                    for v2 in value:gmatch("[^,]+") do
                        local t = parseDateTime(v2, isDate)
                        if t then cur.exdates[#cur.exdates+1] = t end
                    end
                elseif name == "ORGANIZER" then
                    cur.organizer = (value:lower():match("mailto:(.+)")) or value
                elseif name == "ATTENDEE" then
                    local m = value:lower():match("mailto:(.+)")
                    cur.attendees[#cur.attendees+1] = m or value
                elseif name == "LAST-MODIFIED" then
                    cur.lastModified = parseDateTime(value)
                end
            end
        end
    end

    table.sort(events, function(a, b) return a.dtstart < b.dtstart end)
    return { events = events }
end

-- Backwards-compat alias for callers using the colon form.
function iCal:parse_(text, s, e) return iCal.parse(text, s, e) end

-- ---------------------------------------------------------------------------
-- HTTP download helper (HC3 — uses net.HTTPClient)
-- ---------------------------------------------------------------------------

local function normalizeUrl(url)
    if not url then return nil end
    url = url:gsub("^webcal%-s://", "https://")
            :gsub("^webcals://",   "https://")
            :gsub("^webcal://",    "https://")
    return url
end

function iCal.download(url, opts, callback)
    opts = opts or {}
    callback = callback or function() end
    local startTs = opts.startTs or os.time()
    local endTs   = opts.endTs   or (startTs + (opts.daysAhead or 30) * 86400)
    local timeout = opts.timeout or 10000
    local maxRedirects = opts.maxRedirects or 3

    if type(net) ~= "table" or type(net.HTTPClient) ~= "function" then
        callback("net.HTTPClient unavailable (not running under Fibaro)", {}, nil)
        return
    end

    local fetch
    fetch = function(u, hops)
        if hops > maxRedirects then
            callback("too many redirects ("..hops..")", {}, nil); return
        end
        local http = net.HTTPClient()
        http:request(u, {
            options = { method = "GET", timeout = timeout },
            success = function(resp)
                local s = resp.status or 0
                if (s == 301 or s == 302 or s == 307 or s == 308)
                   and resp.headers and resp.headers.Location then
                    fetch(normalizeUrl(resp.headers.Location), hops + 1); return
                end
                if s ~= 200 then
                    callback("HTTP "..s, {}, resp.data); return
                end
                if not resp.data or resp.data == "" then
                    callback("empty response", {}, ""); return
                end
                local ok, result = pcall(iCal.parse, resp.data, startTs, endTs)
                if not ok then
                    callback("parse failed: "..tostring(result), {}, resp.data); return
                end
                callback(nil, result.events, resp.data)
            end,
            error = function(err)
                callback("network error: "..tostring(err), {}, nil)
            end,
        })
    end

    fetch(normalizeUrl(url), 0)
end

-- ---------------------------------------------------------------------------
-- Publish (HC3 has no require — use the global fibaro table)
-- ---------------------------------------------------------------------------

if type(fibaro) == "table" then
    fibaro.iCal = iCal
end

return iCal
