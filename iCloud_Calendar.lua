--%%name:iCloud Calendar
--%%type:com.fibaro.deviceController
--%%var:calendarUrl=env.ICAL
--%%var:daysAhead=7
--%%var:eventGlobalVar="iCalCurrentEvent"
--%%u:{label="status",text="Status: Ready"}
--%%u:{label="eventCount",text="Events: 0"}
--%%u:{label="lastEvent",text="Last: -"}
--%%u:{button="btnDownload",text="Download Calendar",onReleased="btnDownload"}
--%%u:{label="eventList",text=""}
--%%file:speed.lua,speed

-- %%debug:true
--%%offline:true
--%%desktop:true
--%%speed:24*2*7

-- Embedded iCal parser (simplified version)

local weekRef = nil
local function runWeekly(fun)
  if weekRef then
    clearTimeout(weekRef)
  end
  local t = os.time()
  local function weekLoop()
    fun()
    t = t+7 * 24 * 60 * 60
    weekRef = setTimeout(weekLoop,1000*(t-os.time()))
  end
  weekRef = setTimeout(weekLoop,1000 * 7 * 24 * 60 * 60)
end


local function parseDateTimeValue(value)
    local y, m, d = value:match("^(%d%d%d%d)(%d%d)(%d%d)$")
    if y and m and d then
        return os.time({
            year = tonumber(y),
            month = tonumber(m),
            day = tonumber(d),
            hour = 0,
            min = 0,
            sec = 0,
        }), true
    end

    local yy, mm, dd, h, mi, s = value:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z?$")
    if yy and mm and dd and h and mi and s then
        return os.time({
            year = tonumber(yy),
            month = tonumber(mm),
            day = tonumber(dd),
            hour = tonumber(h),
            min = tonumber(mi),
            sec = tonumber(s),
        }), false
    end

    return nil, false
end

local function parseRRULE(rrule)
    local out = {}
    if not rrule or rrule == "" then return out end
    for part in rrule:gmatch("[^;]+") do
        local k, v = part:match("([^=]+)=(.+)")
        if k and v then
            out[k:upper()] = v
        end
    end
    return out
end

local function addOccurrence(events, e, ts)
    local ev = {
        uid = e.uid,
        summary = e.summary,
        description = e.description,
        location = e.location,
        dtstart = ts,
        dtend = e.duration and (ts + e.duration) or e.dtend,
        isAllDay = e.isAllDay,
        organizer = e.organizer,
    }
    table.insert(events, ev)
end

local function formatDuration(seconds, isAllDay)
    if not seconds or seconds <= 0 then
        return ""
    end

    if isAllDay and seconds % 86400 == 0 then
        local days = math.floor(seconds / 86400)
        if days == 1 then
            return " [duration: 1 day]"
        end
        return string.format(" [duration: %d days]", days)
    end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 and minutes > 0 then
        return string.format(" [duration: %dh %dm]", hours, minutes)
    end
    if hours > 0 then
        return string.format(" [duration: %dh]", hours)
    end
    return string.format(" [duration: %dm]", minutes)
end

local function formatEventForLog(event, index)
    local dateStr
    if event.isAllDay then
        dateStr = os.date("%Y-%m-%d", event.dtstart) .. " (all-day)"
    else
        dateStr = os.date("%Y-%m-%d %H:%M", event.dtstart)
    end

    local summary = event.summary ~= "" and event.summary or "(no summary)"
    local location = event.location ~= "" and (" @ " .. event.location) or ""
    local duration = formatDuration(event.dtend and (event.dtend - event.dtstart) or event.duration, event.isAllDay)
    return string.format("Event %d: %s - %s%s%s", index, dateStr, summary, location, duration)
end

local function parseICalEvents(icalData, daysAhead)
    local events = {}
    local now = os.time() - 86400  -- include events from yesterday to avoid missing all-day/early events
    local endTime = now + (tonumber(daysAhead) or 30) * 86400
    
    local lines = {}
    local lineBuffer = ""
    
    -- Parse lines and handle folding (space continuation)
    for line in icalData:gmatch("[^\r\n]+") do
        line = line:gsub("\r$", "")
        if line:match("^ ") then
            -- Continuation line
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
    
    local currentEvent = nil
    local inVEvent = false
    
    for _, line in ipairs(lines) do
        -- Parse property line: PROPERTY;PARAMS:VALUE
        local prop, value = line:match("^([A-Z%-]+)%s*:%s*(.*)$")
        if not prop and line:find(":") then
            -- Try with parameters
            local fullProp
            fullProp, value = line:match("^([A-Z%-][^:]*):(.*)$")
            if fullProp then
                prop = fullProp:match("^([A-Z%-]+)")
            end
        end
        
        if not prop then goto continue end
        
        if line:match("^BEGIN:VEVENT") then
            currentEvent = {
                uid = "",
                summary = "",
                description = "",
                location = "",
                dtstart = nil,
                dtend = nil,
                duration = nil,
                isAllDay = false,
                organizer = "",
                rrule = "",
            }
            inVEvent = true
        elseif line:match("^END:VEVENT") then
            if currentEvent and currentEvent.dtstart then
                if currentEvent.rrule ~= "" then
                    local rule = parseRRULE(currentEvent.rrule)
                    local freq = rule.FREQ
                    local interval = tonumber(rule.INTERVAL) or 1
                    local count = tonumber(rule.COUNT) or 200
                    local untilTs = nil

                    if rule.UNTIL then
                        untilTs = parseDateTimeValue(rule.UNTIL)
                    end

                    local ts = currentEvent.dtstart
                    local i = 0
                    while i < count and ts <= endTime do
                        if not untilTs or ts <= untilTs then
                            if ts >= now and ts <= endTime then
                                addOccurrence(events, currentEvent, ts)
                            end
                        end

                        if freq == "DAILY" then
                            ts = ts + 86400 * interval
                        elseif freq == "WEEKLY" then
                            ts = ts + 7 * 86400 * interval
                        elseif freq == "MONTHLY" then
                            local t = os.date("*t", ts)
                            t.month = t.month + interval
                            ts = os.time(t)
                        elseif freq == "YEARLY" then
                            local t = os.date("*t", ts)
                            t.year = t.year + interval
                            ts = os.time(t)
                        else
                            break
                        end
                        i = i + 1
                    end
                else
                    table.insert(events, currentEvent)
                end
            end
            currentEvent = nil
            inVEvent = false
        elseif inVEvent and currentEvent then
            if prop == "SUMMARY" then
                currentEvent.summary = value:gsub("\\n", " "):gsub("\\,", ","):gsub("\\;", ";")
            elseif prop == "DTSTART" then
                local ts, allDay = parseDateTimeValue(value)
                currentEvent.dtstart = ts
                currentEvent.isAllDay = allDay
            elseif prop == "DTEND" then
                currentEvent.dtend = parseDateTimeValue(value)
            elseif prop == "UID" then
                currentEvent.uid = value
            elseif prop == "DESCRIPTION" then
                currentEvent.description = value:sub(1, 100)
            elseif prop == "LOCATION" then
                currentEvent.location = value
            elseif prop == "ORGANIZER" then
                currentEvent.organizer = value:match("MAILTO:(.+)") or value
            elseif prop == "RRULE" then
                currentEvent.rrule = value
            end

            if currentEvent.dtstart and currentEvent.dtend and not currentEvent.duration then
                currentEvent.duration = currentEvent.dtend - currentEvent.dtstart
            end
        end
        
        ::continue::
    end
    
    -- Filter to date range and sort
    local filtered = {}
    for _, e in ipairs(events) do
        if e.dtstart >= now and e.dtstart <= endTime then
            table.insert(filtered, e)
        end
    end
    
    table.sort(filtered, function(a, b) return a.dtstart < b.dtstart end)
    return filtered
end

function QuickApp:onInit()
    self:debug("iCloud Calendar QA started")
    self.events = {}
    self.eventTimers = {}
    self:updateView("status", "text", "Status: Ready")
    self:updateView("eventCount", "text", "Events: 0")
    self:startWeeklyRefresh()
    self:refreshCalendar("startup")
end

function QuickApp:btnDownload()
    self:debug("Download button pressed")
    self:refreshCalendar("manual")
end

function QuickApp:startWeeklyRefresh()
    runWeekly(function()
        self:debug("Weekly refresh triggered")
        self:refreshCalendar("weekly")
    end)
end

function QuickApp:refreshCalendar(trigger)
    trigger = trigger or "manual"
    self:updateView("status", "text", "Status: Downloading...")
    self:debug("Refreshing calendar (trigger:", trigger .. ")")
    
    local url = self:getVariable("calendarUrl")
    if url == "" then
        self:updateView("status", "text", "Error: No calendar URL set")
        self:error("Calendar URL is empty. Please set calendarUrl variable.")
        return
    end
    
    -- Convert webcal:// to https://
    url = url:gsub("^webcal://", "https://"):gsub("^webcal%-s://", "https://")
    
    self:debug("Downloading from:", url)

    self:fetchCalendar(url, 0, trigger)
end

function QuickApp:fetchCalendar(url, redirects, trigger)
    redirects = redirects or 0
    if redirects > 3 then
        self:updateView("status", "text", "Error: Too many redirects")
        self:error("Too many redirects while downloading calendar")
        return
    end

    local http = net.HTTPClient()
    http:request(url, {
        options = { method = "GET", timeout = 10000 },
        success = function(response)
            self:debug("HTTP response:", response.status)

            if (response.status == 301 or response.status == 302 or response.status == 307 or response.status == 308)
                and response.headers and response.headers.Location then
                self:debug("Following redirect to:", response.headers.Location)
                self:fetchCalendar(response.headers.Location, redirects + 1, trigger)
                return
            end

            if response.status == 200 then
                if not response.data or response.data == "" then
                    self:updateView("status", "text", "Error: Empty calendar response")
                    self:error("Empty response from calendar URL")
                    return
                end
                self:parseAndDisplayCalendar(response.data, trigger)
            else
                self:updateView("status", "text", "Error: HTTP " .. response.status)
                self:error("HTTP error:", response.status)
            end
        end,
        error = function(err)
            self:updateView("status", "text", "Error: Network failure")
            self:error("Download error:", tostring(err))
        end
    })
end

function QuickApp:clearEventTimers()
    for _, ref in ipairs(self.eventTimers) do
        clearTimeout(ref)
    end
    self.eventTimers = {}
end

function QuickApp:publishEventToGlobal(event, index)
    local globalVar = self:getVariable("eventGlobalVar")
    if globalVar == "" then
        self:error("eventGlobalVar is empty, cannot publish event")
        return
    end

    local payload = {
        index = index,
        uid = event.uid,
        summary = event.summary,
        description = event.description,
        location = event.location,
        organizer = event.organizer,
        dtstart = event.dtstart,
        dtend = event.dtend,
        isAllDay = event.isAllDay,
        duration = event.dtend and (event.dtend - event.dtstart) or event.duration,
        triggeredAt = os.time(),
    }

    local ok, encoded = pcall(json.encode, payload)
    if not ok then
        self:error("Failed to encode event payload for global variable")
        return
    end

    local setOk, setErr = pcall(function()
        fibaro.setGlobalVariable(globalVar, encoded)
    end)

    if not setOk then
        self:error("Failed setting global variable", globalVar, tostring(setErr))
        return
    end

    self:debug("Set global variable", globalVar, "for event", index, payload.summary or "")
end

function QuickApp:rescheduleEventTimers(events)
    self:clearEventTimers()

    local now = os.time()
    local scheduled = 0
    for i, event in ipairs(events) do
        local delaySeconds = event.dtstart - now
        if delaySeconds > 0 then
            local delayMs = delaySeconds * 1000
            local ref = setTimeout(function()
                self:publishEventToGlobal(event, i)
            end, delayMs)
            table.insert(self.eventTimers, ref)
            scheduled = scheduled + 1
        end
    end

    self:debug("Scheduled", scheduled, "event start trigger(s)")
end

function QuickApp:parseAndDisplayCalendar(icalData, trigger)
    self:debug("Parsing calendar data, length:", #icalData)
    
    local daysAhead = tonumber(self:getVariable("daysAhead")) or 7
    local events = parseICalEvents(icalData, daysAhead)
    self.events = events
    
    self:debug("Parsed events count:", #events, "(trigger:", (trigger or "unknown") .. ")")
    if #events == 0 then
        self:debug("No events found in the configured date range")
    else
        for i, event in ipairs(events) do
            self:debug(formatEventForLog(event, i))
        end
    end

    self:rescheduleEventTimers(events)
    
    -- Update event count
    self:updateView("eventCount", "text", "Events: " .. tostring(#events))
    
    -- Display event list
    local eventList = ""
    if #events == 0 then
        eventList = "No events found in the specified range."
    else
        local eventLines = {}
        local maxEvents = 5  -- Show first 5 events
        for i = 1, math.min(#events, maxEvents) do
            local e = events[i]
            local dateStr = os.date("%Y-%m-%d %H:%M", e.dtstart)
            if e.isAllDay then
                dateStr = os.date("%Y-%m-%d", e.dtstart) .. " (all-day)"
            end
            table.insert(eventLines, string.format("%d. %s  %s", i, dateStr, e.summary))
        end
        if #events > maxEvents then
            table.insert(eventLines, "... and " .. (#events - maxEvents) .. " more events")
        end
        eventList = table.concat(eventLines, "<br>")
    end
    
    self:updateView("eventList", "text", eventList)
    
    -- Update last event info
    if #events > 0 then
        local lastEvent = events[#events]
        local lastDateStr = os.date("%Y-%m-%d", lastEvent.dtstart)
        self:updateView("lastEvent", "text", "Last: " .. lastDateStr .. " (" .. lastEvent.summary .. ")")
    else
        self:updateView("lastEvent", "text", "Last: -")
    end
    
    self:updateView("status", "text", "Status: Complete")
    self:debug("Calendar parsed successfully")
end
