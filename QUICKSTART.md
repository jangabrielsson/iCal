# Quick Start Guide — iCal Parser + iCloud Calendar QA

## 📋 What You Got

- **`iCal.lua`** — Full-featured iCalendar parser library with RRULE expansion
- **`iCloud_Calendar.lua`** — QuickApp for downloading & displaying your iCloud calendar
- **`README.md`** — Complete documentation with examples
- **`test_ical.lua`** — Test suite to verify the parser works
- **`QUICKSTART.md`** — This file 😉

---

## 🚀 5-Minute Setup

### Step 1: Get Your iCloud Calendar Link

1. On **iPhone/Mac**, go to: Settings → [Your Name] → iCloud → Calendars
2. Find the calendar you want to share
3. Tap it and select **Share Calendar**
4. Tap **Shared With Only Me** or change to **Public**
5. **Copy the link** that looks like:
   ```
   webcal://p64-caldav.icloud.com/published/2/MTMxNjYxNDMwMT...
   ```

### Step 2: Add QuickApp to HC3

1. **Upload the QuickApp file:**
   - In HC3 web UI, go to **Devices** → **QuickApps** → **Add**
   - Click **Upload JSON/LUA file**
   - Choose `iCloud_Calendar.lua`

2. **Configure the QuickApp:**
   - In **QuickApp settings**, find these variables:
     - **`calendarUrl`** — Paste your calendar link here
     - **`daysAhead`** — Number of days to show (default: 30)
   - **Save**

### Step 3: Download Your Calendar

1. In the QuickApp UI, click **"Download Calendar"**
2. Wait for status to show "**Status: Complete**"
3. View your events in the list below

---

## 🧪 Testing (Optional)

### Test the Parser Library

Run the included test suite to verify parsing works:

```bash
# Using standalone Lua:
lua test_ical.lua

# Using plua (Fibaro emulator):
plua --offline test_ical.lua
```

**Expected output:** All tests should show `✓ PASSED`.

### Test the QuickApp Locally

```bash
# Start QuickApp in plua:
plua --fibaro --run-for 0 iCloud_Calendar.lua

# In another terminal, trigger the button:
curl -X POST http://localhost:8172 \
  -H "Content-Type: application/json" \
  -d '{"method":"call","target":{"deviceId":"quiz","name":"btnDownload"}}'
```

---

## 📝 Configuration Reference

### QuickApp Variables

| Variable | Type | Example | Purpose |
|----------|------|---------|---------|
| **calendarUrl** | String | `webcal://p64-caldav.icloud.com/published/2/...` | Your iCloud calendar link |
| **daysAhead** | Number | `30` | How many days in the future to fetch |

### UI Buttons & Labels

| UI Element | Type | Function |
|------------|------|----------|
| **Download Calendar** | Button | Click to download & parse calendar |
| **Status** | Label | Shows current operation (Ready, Downloading, Complete, Error) |
| **Events** | Label | Count of events found |
| **Event List** | Label | Shows first 5 upcoming events |
| **Last Event** | Label | Date & title of the last event |

---

## 🛠️ Common Tasks

### Change the Date Range

Edit the **`daysAhead`** variable in the QuickApp:

- **Next 7 days:** Set to `7`
- **Next 60 days:** Set to `60`
- **Next year:** Set to `365`

### Use a Different Calendar

1. Get a new calendar's share link (see Step 1 again)
2. Update the **`calendarUrl`** variable in the QuickApp
3. Click **"Download Calendar"** again

### Parse an iCal File in Lua Code

```lua
-- In your own Lua script:
local iCal = require("iCal")

local file = io.open("my_calendar.ics", "r")
local icalData = file:read("*a")
file:close()

local result = iCal:parse(icalData)

for _, event in ipairs(result.events) do
    print(event.summary .. " at " .. os.date("%Y-%m-%d %H:%M", event.dtstart))
end
```

---

## ⚠️ Troubleshooting

### "Error: No calendar URL set"
**Solution:** Make sure the **`calendarUrl`** QuickApp variable is filled in.

### "Error: HTTP 404" or "HTTP 403"
**Solution:** 
- Verify your calendar link is correct
- Make sure the calendar is shared publicly
- Try the link in a web browser to test

### "Events: 0"
**Solution:**
- Increase **`daysAhead`** to look further ahead
- Check that your calendar has events in that time range
- Look at HC3 debug console for warnings

### Text looks garbled
**Solution:** The parser automatically unescapes iCal escape sequences (`\n`, `\,`, etc.). If text still looks wrong, your calendar may have special encoding—check your calendar app.

---

## 📚 For More Info

See **`README.md`** for:
- Full API reference for the iCal library
- Detailed date format examples
- How RRULE expansion works
- RFC 2445 compliance notes
- Future enhancements
- Full troubleshooting guide

---

## ✨ Quick Tips

1. **Recurring events** — The parser automatically expands them into individual instances ✓
2. **All-day events** — Shown with "(all-day)" label ✓
3. **Time zones** — Converted to your local time automatically ✓
4. **Private calendars** — Use your personal share link (with auth token in URL) ✓
5. **Multiple calendars** — Create multiple QuickApps, one per calendar ✓

---

## 🎯 Next Steps

1. ✅ Add the QuickApp to your HC3
2. ✅ Set your calendar URL in the variables
3. ✅ Click "Download Calendar"
4. ✅ Enjoy automatic iCloud calendar integration!

Need help? Check **README.md** for comprehensive documentation.

Happy calendaring! 📅
