--%%name:Calendar Automation
--%%type:com.fibaro.deviceController
--%%var:calendarUrl=env.ICAL
--%%var:daysAhead=7
--%%var:tagPrefix="#HC3#"
--%%var:tagPrefixEnd="#/HC3#"
--%%u:{label="status",text="Status: Ready"}
--%%u:{label="upcoming",text="Upcoming: -"}
--%%u:{label="lastFired",text="Last: -"}
--%%u:{button="btnRefresh",text="Refresh now",onReleased="btnRefresh"}
--%%u:{label="actionLog",text=""}
--%%file:iCal.lua,ical

-- %%debug:true
-- %%offline:true
-- %%desktop:true

--[[
Calendar Automation QuickApp
============================

Watches an iCloud / webcal calendar and dispatches QuickApp method calls
when an event reaches DTSTART (or DTEND).

Two tag prefixes, paired like HTML open/close tags. Default:
  #HC3#  ... fires at DTSTART
  #/HC3# ... fires at DTEND

Both prefixes are configurable via QA variables tagPrefix / tagPrefixEnd.
Example event description:

    #HC3#turnOn,88
    #/HC3#turnOff,88

The first token after the prefix is the method name; the rest are
positional arguments. Arguments are coerced:
  - "true" / "false" / "nil"    -> bool / nil
  - "123" / "1.5"               -> number
  - everything else             -> string (surrounding quotes stripped)

The method is invoked on this QuickApp:  self:<method>(arg1, arg2, ...)
Define your own handlers below the boilerplate.
]]

local iCal = fibaro.iCal

local TICKER_PERIOD = 30 * 1000          -- 30 s
local REFRESH_PERIOD = 6 * 60 * 60 * 1000 -- 6 h

-- ---------------------------------------------------------------------------
-- Tag parsing
-- ---------------------------------------------------------------------------

local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function coerce(token)
    token = trim(token)
    if token == ""    then return nil  end
    if token == "true"  then return true  end
    if token == "false" then return false end
    if token == "nil"   then return nil   end
    local n = tonumber(token)
    if n ~= nil then return n end
    -- Strip a single layer of surrounding quotes.
    local stripped = token:match([[^"(.*)"$]]) or token:match([[^'(.*)'$]])
    return stripped or token
end

-- Scan one text blob for tag lines. Returns a list of { method=..., args={...} }.
-- The longer prefix is matched first when both start with the same chars
-- (e.g. "#/HC3#" must win over "#HC3#").
local function extractTagsOnePrefix(text, prefix, phase)
    local out = {}
    if not text or text == "" or not prefix or prefix == "" then return out end
    local pat = prefix:gsub("(%W)", "%%%1") .. "([^\r\n]+)"
    for body in text:gmatch(pat) do
        local parts = {}
        for tok in (body .. ","):gmatch("([^,]*),") do
            parts[#parts+1] = tok
        end
        local method = trim(parts[1] or "")
        if method ~= "" then
            local args = {}
            for i = 2, #parts do args[#args+1] = coerce(parts[i]) end
            out[#out+1] = { method = method, args = args, phase = phase }
        end
    end
    return out
end

-- Strip every occurrence of `prefix...<eol>` from the text so a longer
-- prefix doesn't double-match against a shorter one (e.g. #/HC3# vs #HC3#).
local function stripPrefix(text, prefix)
    if not text or not prefix or prefix == "" then return text or "" end
    local pat = prefix:gsub("(%W)", "%%%1") .. "[^\r\n]*"
    return (text:gsub(pat, ""))
end

local function extractTags(text, startPrefix, endPrefix)
    if not text or text == "" then return {} end
    -- Match end-prefix first, then strip those lines so the start-prefix scan
    -- doesn't also match them when one is a substring of the other.
    local endTags = extractTagsOnePrefix(text, endPrefix, "end")
    local remaining = (endPrefix and endPrefix ~= "")
        and stripPrefix(text, endPrefix) or text
    local startTags = extractTagsOnePrefix(remaining, startPrefix, "start")
    for _, t in ipairs(endTags) do startTags[#startTags+1] = t end
    return startTags
end

local function eventTags(e, startPrefix, endPrefix)
    local tags = extractTags(e.summary, startPrefix, endPrefix)
    for _, t in ipairs(extractTags(e.description, startPrefix, endPrefix)) do
        tags[#tags+1] = t
    end
    return tags
end

-- ---------------------------------------------------------------------------
-- QuickApp lifecycle
-- ---------------------------------------------------------------------------

function QuickApp:onInit()
    self:debug("Calendar Automation started")
    self.events    = {}
    self.firedKeys = {}
    self.lastFiredText = "-"
    self:updateView("status",    "text", "Status: Ready")
    self:updateView("upcoming",  "text", "Upcoming: -")
    self:updateView("lastFired", "text", "Last: -")
    self:updateView("actionLog", "text", "")

    setInterval(function() self:refreshCalendar("periodic") end, REFRESH_PERIOD)
    setInterval(function() self:fireDueEvents() end, TICKER_PERIOD)
    self:refreshCalendar("startup")
end

function QuickApp:btnRefresh()
    self:refreshCalendar("manual")
end

function QuickApp:refreshCalendar(trigger)
    local url = self:getVariable("calendarUrl")
    if url == "" then
        self:updateView("status", "text", "Error: No calendar URL set")
        self:error("calendarUrl variable is empty")
        return
    end

    self:updateView("status", "text", "Status: Downloading...")
    local now = os.time()
    local daysAhead = tonumber(self:getVariable("daysAhead")) or 7

    iCal.download(url, {
        startTs = now - 3600,                  -- include events from the last hour
        endTs   = now + daysAhead * 86400,
        timeout = 10000,
    }, function(err, events)
        if err then
            self:updateView("status", "text", "Error: " .. err)
            self:error("Download failed:", err)
            return
        end
        self:onEvents(events, trigger)
    end)
end

function QuickApp:onEvents(events, trigger)
    -- Keep only events that carry at least one tag.
    local startPrefix = self:getVariable("tagPrefix")
    if startPrefix == "" then startPrefix = "#HC3#" end
    local endPrefix = self:getVariable("tagPrefixEnd")
    if endPrefix == "" then endPrefix = "#/HC3#" end

    local tagged = {}
    for _, e in ipairs(events) do
        local tags = eventTags(e, startPrefix, endPrefix)
        if #tags > 0 then
            e._tags = tags
            tagged[#tagged+1] = e
        end
    end
    self.events = tagged

    self:debug(string.format(
        "Refresh (%s): %d events, %d tagged", trigger, #events, #tagged))

    -- Update UI: list next 5 upcoming tagged actions.
    if #tagged == 0 then
        self:updateView("upcoming", "text", "Upcoming: (none tagged)")
    else
        local lines, max = {}, math.min(5, #tagged)
        for i = 1, max do
            local e = tagged[i]
            local when = os.date("%a %m-%d %H:%M", e.dtstart)
            local methods = {}
            for _, t in ipairs(e._tags) do
                methods[#methods+1] = (t.phase == "end" and "/" or "") .. t.method
            end
            lines[#lines+1] = string.format(
                "%s — %s [%s]", when, e.summary or "(no title)", table.concat(methods, ","))
        end
        if #tagged > max then
            lines[#lines+1] = "... and " .. (#tagged - max) .. " more"
        end
        self:updateView("upcoming", "text", table.concat(lines, "<br>"))
    end

    self:pruneFiredKeys()
    self:updateView("status", "text", "Status: Complete")

    -- Fire any events that already started but were missed (e.g. just after refresh).
    self:fireDueEvents()
end

function QuickApp:fireDueEvents()
    local now = os.time()
    for _, e in ipairs(self.events) do
        -- Start-phase tags fire at dtstart
        if e.dtstart and e.dtstart <= now then
            local key = (e.uid or "?") .. ":start:" .. e.dtstart
            if not self.firedKeys[key] then
                self.firedKeys[key] = true
                self:dispatchEvent(e, "start")
            end
        end
        -- End-phase tags fire at dtend (skip if no dtend)
        if e.dtend and e.dtend <= now then
            local key = (e.uid or "?") .. ":end:" .. e.dtend
            if not self.firedKeys[key] then
                self.firedKeys[key] = true
                self:dispatchEvent(e, "end")
            end
        end
    end
end

function QuickApp:dispatchEvent(event, phase)
    local fired = 0
    for _, tag in ipairs(event._tags or {}) do
        if tag.phase == phase then
            self:invokeTag(event, tag)
            fired = fired + 1
        end
    end
    if fired == 0 then return end
    local stamp = os.date("%H:%M", os.time())
    self.lastFiredText = string.format("%s [%s] %s",
        stamp, phase, event.summary or "(no title)")
    self:updateView("lastFired", "text", "Last: " .. self.lastFiredText)
end

function QuickApp:invokeTag(event, tag)
    local handler = self[tag.method]
    if type(handler) ~= "function" then
        self:warning(string.format(
            "Unknown method '%s' (event: %s)", tag.method, event.summary or "?"))
        return
    end
    self:debug(string.format(
        "Invoke: self:%s(%s)  [event: %s]",
        tag.method, self:argsRepr(tag.args), event.summary or "?"))
    local ok, err = pcall(handler, self, table.unpack(tag.args))
    if not ok then
        self:error(string.format("self:%s failed: %s", tag.method, tostring(err)))
    end
end

function QuickApp:argsRepr(args)
    local parts = {}
    for i, a in ipairs(args) do
        if type(a) == "string" then
            parts[i] = string.format("%q", a)
        else
            parts[i] = tostring(a)
        end
    end
    return table.concat(parts, ", ")
end

function QuickApp:pruneFiredKeys()
    local keep = {}
    for _, e in ipairs(self.events) do
        local sk = (e.uid or "?") .. ":start:" .. (e.dtstart or 0)
        local ek = (e.uid or "?") .. ":end:"   .. (e.dtend or 0)
        if self.firedKeys[sk] then keep[sk] = true end
        if self.firedKeys[ek] then keep[ek] = true end
    end
    self.firedKeys = keep
end

-- ===========================================================================
-- USER-DEFINED ACTION METHODS
-- ===========================================================================
-- Define one function per action you want to call from the calendar.
-- Tag syntax: #HC3#<methodName>,arg1,arg2,...

-- Example: #HC3#turnOn,88
function QuickApp:turnOn(deviceId)
    deviceId = tonumber(deviceId)
    if not deviceId then return self:error("turnOn: deviceId required") end
    fibaro.call(deviceId, "turnOn")
end

-- Example: #HC3#turnOff,88
function QuickApp:turnOff(deviceId)
    deviceId = tonumber(deviceId)
    if not deviceId then return self:error("turnOff: deviceId required") end
    fibaro.call(deviceId, "turnOff")
end

-- Example: #HC3#setValue,88,80
function QuickApp:setValue(deviceId, value)
    deviceId = tonumber(deviceId)
    if not deviceId then return self:error("setValue: deviceId required") end
    fibaro.call(deviceId, "setValue", value)
end

-- Example: #HC3#scene,17
function QuickApp:scene(sceneId)
    sceneId = tonumber(sceneId)
    if not sceneId then return self:error("scene: sceneId required") end
    fibaro.scene("execute", { sceneId })
end

-- Example: #HC3#say,"Time to leave"
function QuickApp:say(text)
    self:debug("SAY:", text)
    -- Replace with your TTS / push notification of choice, e.g.:
    -- fibaro.alert("push", { ownerId }, tostring(text))
end
