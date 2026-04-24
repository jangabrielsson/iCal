--%%name:iCloud Calendar
--%%type:com.fibaro.deviceController
--%%var:calendarUrl=env.ICAL
--%%var:daysAhead=30
--%%var:eventGlobalVar="iCalCurrentEvent"
--%%u:{label="status",text="Status: Ready"}
--%%u:{label="eventCount",text="Events: 0"}
--%%u:{label="lastEvent",text="Last: -"}
--%%u:{button="btnDownload",text="Download Calendar",onReleased="btnDownload"}
--%%u:{label="eventList",text=""}
--%%file:iCal.lua,ical

-- %%debug:true
-- %%offline:true
-- %%desktop:true

local iCal = fibaro.iCal

local WEEK_SECONDS  = 7 * 24 * 60 * 60
local TICKER_PERIOD = 30 * 1000   -- 30 s

local function fmtEventDate(e)
    if e.isAllDay then
        return os.date("%Y-%m-%d", e.dtstart) .. " (all-day)"
    end
    return os.date("%Y-%m-%d %H:%M", e.dtstart)
end

function QuickApp:onInit()
    self:debug("iCloud Calendar QA started")
    self.events     = {}
    self.firedKeys  = {}
    self.lastWindowStart = os.time()
    self:updateView("status",     "text", "Status: Ready")
    self:updateView("eventCount", "text", "Events: 0")
    self:updateView("lastEvent",  "text", "Last: -")
    self:updateView("eventList",  "text", "")
    setInterval(function() self:refreshCalendar("weekly") end, WEEK_SECONDS * 1000)
    setInterval(function() self:fireDueEvents() end, TICKER_PERIOD)
    self:refreshCalendar("startup")
end

function QuickApp:btnDownload()
    self:debug("Download button pressed")
    self:refreshCalendar("manual")
end

function QuickApp:refreshCalendar(trigger)
    trigger = trigger or "manual"
    self:updateView("status", "text", "Status: Downloading...")

    local url = self:getVariable("calendarUrl")
    if url == "" then
        self:updateView("status", "text", "Error: No calendar URL set")
        self:error("calendarUrl variable is empty")
        return
    end

    local daysAhead = tonumber(self:getVariable("daysAhead")) or 30
    local now = os.time()
    self.lastWindowStart = now - 86400

    iCal.download(url, {
        startTs = self.lastWindowStart,
        endTs   = now + daysAhead * 86400,
        timeout = 10000,
    }, function(err, events)
        if err then
            self:updateView("status", "text", "Error: " .. err)
            self:error("Download failed:", err)
            return
        end
        self:displayCalendar(events, self.lastWindowStart, trigger)
    end)
end

function QuickApp:displayCalendar(events, windowStart, trigger)
    self.events = events
    self:debug("Parsed events count:", #events, "(trigger: " .. tostring(trigger) .. ")")

    self:pruneFiredKeys(windowStart)

    self:updateView("eventCount", "text", "Events: " .. #events)
    if #events == 0 then
        self:updateView("eventList", "text", "No events in window.")
        self:updateView("lastEvent", "text", "Last: -")
    else
        local lines, max = {}, 5
        for i = 1, math.min(#events, max) do
            local e = events[i]
            lines[#lines+1] = string.format("%d. %s  %s", i, fmtEventDate(e), e.summary)
        end
        if #events > max then
            lines[#lines+1] = "... and " .. (#events - max) .. " more"
        end
        self:updateView("eventList", "text", table.concat(lines, "<br>"))
        local last = events[#events]
        self:updateView("lastEvent", "text", "Last: " .. fmtEventDate(last) .. " (" .. last.summary .. ")")
    end

    self:updateView("status", "text", "Status: Complete")

    -- Fire any events already past dtstart in the new window
    self:fireDueEvents()
end

function QuickApp:fireDueEvents()
    local now = os.time()
    local globalVar = self:getVariable("eventGlobalVar")
    for _, e in ipairs(self.events) do
        if e.dtstart <= now then
            local key = (e.uid or "?") .. ":" .. e.dtstart
            if not self.firedKeys[key] then
                self.firedKeys[key] = true
                if globalVar and globalVar ~= "" then
                    local payload = {
                        uid         = e.uid,
                        summary     = e.summary,
                        description = e.description,
                        location    = e.location,
                        dtstart     = e.dtstart,
                        dtend       = e.dtend,
                        isAllDay    = e.isAllDay,
                        duration    = e.dtend and (e.dtend - e.dtstart) or nil,
                        triggeredAt = now,
                    }
                    fibaro.setGlobalVariable(globalVar, json.encode(payload))
                    self:debug("Fired event:", e.summary, "->", globalVar)
                end
            end
        end
    end
end

function QuickApp:pruneFiredKeys(windowStart)
    local keep = {}
    for _, e in ipairs(self.events) do
        local key = (e.uid or "?") .. ":" .. e.dtstart
        if self.firedKeys[key] then keep[key] = true end
    end
    self.firedKeys = keep
end
