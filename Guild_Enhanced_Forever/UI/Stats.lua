-- Guild Enhanced Forever: statistics page.
--   Most active members of the last 7 days (time seen online, counted while you are online too),
--   newcomers of the week, levels and classes charts, seniority and guild anniversaries.
-- Join dates: from the guild event log and from new names in the roster; shared with the
-- guildmates who have the addon (collection "joined": the earliest known date wins). An
-- anniversary shows a pop-up with a Congratulate button that only fills your chat line: you send it.
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient
local Sync = ns.Sync
local now = GetServerTime or time

local PAGE = 7
local COL_W = 292
local page, ui = nil, { active = {}, newbies = {}, levels = {}, classes = {}, seniors = {} }
local me = UnitName("player")
ns.OnMyName(function(n) me = n end) -- full roster name once known
local DAY = 86400

-- Activity ----------------------------------------------------------------------------------------------
local function dayNum(t) return math.floor((t or now()) / DAY) end

-- every 5 minutes: 5 minutes for each guildmate online
C_Timer.NewTicker(300, function()
  if not IsInGuild() or #ns.members == 0 or not ns.db then return end
  local act = ns.GuildTable("activity")
  local d = dayNum()
  act[d] = act[d] or {}
  for _, m in ipairs(ns.members) do
    if m.online then act[d][m.short] = (act[d][m.short] or 0) + 5 end
  end
  for k in pairs(act) do if k < d - 14 then act[k] = nil end end
end)

local function activity()
  local act, d, sum = ns.GuildTable("activity"), dayNum(), {}
  for k, list in pairs(act) do
    if k > d - 7 then for name, min in pairs(list) do sum[name] = (sum[name] or 0) + min end end
  end
  local list = {}
  for name, min in pairs(sum) do if ns.byName[name] then list[#list + 1] = { name = name, min = min } end end
  table.sort(list, function(a, b) return a.min > b.min end)
  return list
end

local function duration(min)
  if min < 60 then return string.format(L["%d min"], min) end
  return string.format(L["%d h %02d"], math.floor(min / 60), min % 60)
end

-- Join dates ------------------------------------------------------------------------------------------------
Sync.Register("joined", {
  keep = 400 * DAY,
  -- the earliest date has the highest version: it always wins
  version = function(rec) return 4000000000 - (rec.d or 0) end,
  validate = function(rec) return type(rec.d) == "number" and rec.d > 1000000000 and rec.d <= now() + DAY end,
})

local function joinDate(name)
  local r = Sync.Get("joined", name)
  return r and r.d
end

local function learn(name, d)
  if not name or not d or not Sync.Started() then return end
  name = ns.Short(name)
  local old = joinDate(name)
  if old and old <= d + 6 * 3600 then return end
  Sync.Put("joined", { id = name, d = d })
end

-- the log: "X joined the guild" (with how long ago)
local function readLog()
  for _, e in ipairs(ns.ScanLog()) do
    if e.kind == "join" and e.p1 then learn(e.p1, now() - e.age * 3600) end
  end
end

-- new names in the roster (once a first roster was known in this guild)
local function readRoster()
  if #ns.members == 0 then return end
  local known = ns.GuildTable("known")
  local first = not next(known)
  for _, m in ipairs(ns.members) do
    if not known[m.short] then
      known[m.short] = now()
      if not first then learn(m.short, now()) end
    end
  end
end

ns.On("LOG", function() if Sync.Started() then readLog() end end)
ns.On("ROSTER", function() if Sync.Started() then readRoster() end end)
ns.On("SYNC_READY", function()
  readRoster()
  ns.RequestLog()
  C_Timer.After(20, function() ns.CheckAnniversaries() end)
end)

-- Anniversaries ---------------------------------------------------------------------------------------------
-- years in the guild today (0 when not today)
local function yearsToday(d)
  local a, t = date("*t", d), date("*t")
  if a.month == t.month and a.day == t.day and t.year > a.year then return t.year - a.year end
  return 0
end

local function nextAnniversary(d)
  local a, t = date("*t", d), date("*t")
  local years = t.year - a.year
  local this = time({ year = t.year, month = a.month, day = a.day, hour = 12 })
  if this < time({ year = t.year, month = t.month, day = t.day, hour = 0 }) then
    this = time({ year = t.year + 1, month = a.month, day = a.day, hour = 12 })
    years = years + 1
  end
  return this, years
end

-- opens the chat line with a message ready: the player sends it himself (Enter)
function ns.Congratulate(name, years)
  local text = string.format(L["Happy guild anniversary %s: %d year(s) with us!"], name, years)
  if ChatFrame_OpenChat then
    ChatFrame_OpenChat("/g " .. text)
  end
end

function ns.CheckAnniversaries()
  if not IsInGuild() or not ns.NotifyOpt("anniv") then return end
  local done = ns.GuildTable("annivShown")
  local today = date("%Y-%m-%d")
  for _, m in ipairs(ns.members) do
    local d = joinDate(m.short)
    local y = d and yearsToday(d) or 0
    if y > 0 and done[m.short] ~= today then
      done[m.short] = today
      local label = "|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r"
      local isMe = m.short == me
      ns.Notify({ icon = { "Interface\\Icons\\INV_Misc_Gift_03", "Interface\\Icons\\INV_Misc_Gift_02" },
        title = L["Guild anniversary"],
        text = isMe and string.format(L["You joined the guild %d year(s) ago today!"], y)
          or string.format(L["%s joined the guild %d year(s) ago today."], label, y),
        sound = SOUNDKIT and SOUNDKIT.UI_ACHIEVEMENT_AWARDED or 12891,
        buttons = (not isMe) and { { L["Congratulate"], function() ns.Congratulate(m.short, y) end, true } } or nil })
    end
  end
end

-- Page ------------------------------------------------------------------------------------------------------------
local function column(p, x, title, w)
  local box = CreateFrame("Frame", nil, p)
  box:SetPoint("TOPLEFT", x, 0)
  box:SetPoint("BOTTOMLEFT", x, 0)
  box:SetWidth(w or COL_W)
  S.Card(box, 10)
  local s = S.Section(box, title)
  s:SetPoint("TOPLEFT", 12, -10)
  s:SetPoint("TOPRIGHT", -12, -10)
  box.section = s
  return box
end

-- a line with a name, a bar and a value
local function barRow(parent, list, i, y)
  local r = list[i]
  if not r then
    r = CreateFrame("Button", nil, parent)
    r:SetHeight(20)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.rank = S.Text(r, 10, "muted")
    r.rank:SetPoint("LEFT", 0, 0)
    r.rank:SetWidth(16)
    r.name = S.Text(r, 12, "text")
    r.name:SetPoint("LEFT", 18, 0)
    r.name:SetWidth(100)
    r.bar = S.ProgressBar(r, 6)
    r.bar:SetPoint("LEFT", 122, 0)
    r.bar:SetPoint("RIGHT", -62, 0)
    r.value = S.Text(r, 11, "dim")
    r.value:SetPoint("RIGHT")
    r.value:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self, button)
      local m = self.who and ns.byName[self.who]
      if not m then return end
      if button == "RightButton" then ns.MemberMenu(self, m) else ns.Whisper(m) end
    end)
    list[i] = r
  end
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", 12, y)
  r:SetPoint("TOPRIGHT", -12, y)
  r:Show()
  return r
end

local function refresh(animate)
  if not page then return end
  -- most active
  local act = activity()
  local top = act[1] and act[1].min or 1
  for i = 1, 10 do
    local a = act[i]
    if a then
      local r = barRow(ui.colA, ui.active, i, -40 - (i - 1) * 22)
      local m = ns.byName[a.name]
      r.who = a.name
      r.rank:SetText(i)
      r.name:SetText(a.name)
      r.name:SetTextColor(ns.ClassColor(m and m.classFile))
      r.bar:SetValue(a.min / top, animate and i * 0.04 or nil)
      r.value:SetText(duration(a.min))
    elseif ui.active[i] then
      ui.active[i]:Hide()
    end
  end
  ui.activeEmpty:SetShown(#act == 0)

  -- newcomers (7 days)
  local news, t = {}, now()
  for _, m in ipairs(ns.members) do
    local d = joinDate(m.short)
    if d and t - d < 7 * DAY then news[#news + 1] = { m = m, d = d } end
  end
  table.sort(news, function(a, b) return a.d > b.d end)
  ui.newTitle.right:SetText(#news)
  for i = 1, 8 do
    local n = news[i]
    if n then
      local r = barRow(ui.colA, ui.newbies, i, -300 - (i - 1) * 22)
      r.who = n.m.short
      r.rank:SetText("")
      r.name:SetText(n.m.short)
      r.name:SetWidth(150)
      r.name:SetTextColor(ns.ClassColor(n.m.classFile))
      r.bar:Hide()
      r.value:SetText(ns.FormatDay(n.d))
    elseif ui.newbies[i] then
      ui.newbies[i]:Hide()
    end
  end
  ui.newEmpty:SetShown(#news == 0)

  -- levels: 1-9 ... 50-59, 60
  local buckets, maxB = { 0, 0, 0, 0, 0, 0, 0 }, 1
  local classes, maxC = {}, 1
  for _, m in ipairs(ns.members) do
    local b = m.level >= 60 and 7 or math.floor(m.level / 10) + 1
    buckets[b] = buckets[b] + 1
    if m.classFile then classes[m.classFile] = (classes[m.classFile] or 0) + 1 end
  end
  for _, v in ipairs(buckets) do maxB = math.max(maxB, v) end
  for i, col in ipairs(ui.levels) do
    local h = math.max(2, 110 * buckets[i] / maxB)
    col.value:SetText(buckets[i])
    if animate then
      col.fill:SetHeight(2)
      S.Tween(col.fill, { dur = 0.6, delay = i * 0.05, from = 2, to = h, ease = "outCubic", set = function(v) col.fill:SetHeight(v) end })
    else
      col.fill:SetHeight(h)
    end
  end
  for _, file in ipairs(ns.CLASSES) do maxC = math.max(maxC, classes[file] or 0) end
  local shown = 0
  for _, file in ipairs(ns.CLASSES) do
    local n = classes[file] or 0
    if n > 0 or file ~= "SHAMAN" and file ~= "PALADIN" then
      shown = shown + 1
      local r = barRow(ui.colB, ui.classes, shown, -230 - (shown - 1) * 22)
      r.who = nil
      r.rank:SetText("")
      r.name:SetText(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file] or file)
      r.name:SetTextColor(ns.ClassColor(file))
      local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
      if cc then r.bar:SetColors({ cc.r, cc.g, cc.b, 1 }, { cc.r * 0.55, cc.g * 0.55, cc.b * 0.55, 1 }) end
      r.bar:SetValue(n / maxC, animate and shown * 0.04 or nil)
      r.value:SetText(n)
    end
  end
  for i = shown + 1, #ui.classes do ui.classes[i]:Hide() end

  -- seniority and anniversaries
  local list = {}
  for _, m in ipairs(ns.members) do
    local d = joinDate(m.short)
    if d then
      local nextT, years = nextAnniversary(d)
      list[#list + 1] = { m = m, d = d, nextT = nextT, years = years, today = yearsToday(d) }
    end
  end
  table.sort(list, function(a, b)
    if (a.today > 0) ~= (b.today > 0) then return a.today > 0 end
    return a.d < b.d
  end)
  for i = 1, 16 do
    local e = list[i]
    local r = ui.seniors[i]
    if e then
      if not r then
        r = CreateFrame("Frame", nil, ui.colC)
        r:SetHeight(22)
        r.name = S.Text(r, 12, "text")
        r.name:SetPoint("LEFT")
        r.since = S.Text(r, 10, "muted")
        r.since:SetPoint("RIGHT")
        r.since:SetJustifyH("RIGHT")
        r.btn = S.Button(r, L["Congratulate"], 96, 20, nil, "primary")
        r.btn:SetPoint("RIGHT")
        ui.seniors[i] = r
      end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 12, -40 - (i - 1) * 24)
      r:SetPoint("TOPRIGHT", -12, -40 - (i - 1) * 24)
      r.name:SetText(e.m.short .. (e.today > 0 and ("  |cffffd100" .. string.format(L["%d year(s)"], e.today) .. "|r") or ""))
      r.name:SetTextColor(ns.ClassColor(e.m.classFile))
      local isToday = e.today > 0 and e.m.short ~= me
      r.btn:SetShown(isToday)
      r.since:SetShown(not isToday)
      r.since:SetText(string.format(L["since %s"], date("%d/%m/%Y", e.d)))
      r.btn:SetScript("OnClick", function() ns.Congratulate(e.m.short, e.today) end)
      r:Show()
    elseif r then
      r:Hide()
    end
  end
  ui.seniorEmpty:SetShown(#list == 0)
end

local function build(p)
  page = p
  local gap = (ns.PAGE_W - 3 * COL_W) / 2
  ui.colA = column(p, 0, L["Most active (7 days)"])
  ui.activeEmpty = S.Text(ui.colA, 11, "muted")
  ui.activeEmpty:SetPoint("TOPLEFT", 14, -42)
  ui.activeEmpty:SetPoint("RIGHT", -14, 0)
  ui.activeEmpty:SetWordWrap(true)
  ui.activeEmpty:SetText(L["Counted while you are online: come back in a few minutes."])
  ui.newTitle = S.Section(ui.colA, L["Newcomers (7 days)"])
  ui.newTitle:SetPoint("TOPLEFT", 12, -270)
  ui.newTitle:SetPoint("TOPRIGHT", -12, -270)
  ui.newEmpty = S.Text(ui.colA, 11, "muted")
  ui.newEmpty:SetPoint("TOPLEFT", 14, -302)
  ui.newEmpty:SetText(L["No newcomer this week."])
  local hint = S.Text(ui.colA, 9, "muted")
  hint:SetPoint("BOTTOMLEFT", 12, 10)
  hint:SetPoint("RIGHT", -12, 0)
  hint:SetWordWrap(true)
  hint:SetText(L["Time seen online by Guild Enhanced while you are online."])

  ui.colB = column(p, COL_W + gap, L["Levels"])
  local chart = CreateFrame("Frame", nil, ui.colB)
  chart:SetPoint("TOPLEFT", 16, -40)
  chart:SetPoint("TOPRIGHT", -16, -40)
  chart:SetHeight(150)
  local labels = { "1-9", "10+", "20+", "30+", "40+", "50+", "60" }
  local colW = (COL_W - 32) / 7
  for i = 1, 7 do
    local col = CreateFrame("Frame", nil, chart)
    col:SetSize(colW - 8, 150)
    col:SetPoint("BOTTOMLEFT", (i - 1) * colW + 4, 0)
    col.fill = col:CreateTexture(nil, "ARTWORK")
    col.fill:SetPoint("BOTTOMLEFT", 0, 18)
    col.fill:SetPoint("BOTTOMRIGHT", 0, 18)
    col.fill:SetHeight(2)
    gradient(col.fill, C.gold1, C.gold2)
    col.value = S.Text(col, 10, "gold")
    col.value:SetPoint("BOTTOM", col.fill, "TOP", 0, 3)
    col.label = S.Text(col, 9, "muted")
    col.label:SetPoint("BOTTOM", 0, 2)
    col.label:SetText(labels[i])
    ui.levels[i] = col
  end
  local cs = S.Section(ui.colB, L["Classes"])
  cs:SetPoint("TOPLEFT", 12, -200)
  cs:SetPoint("TOPRIGHT", -12, -200)

  ui.colC = column(p, 2 * (COL_W + gap), L["Seniority and anniversaries"])
  ui.seniorEmpty = S.Text(ui.colC, 11, "muted")
  ui.seniorEmpty:SetPoint("TOPLEFT", 14, -42)
  ui.seniorEmpty:SetPoint("RIGHT", -14, 0)
  ui.seniorEmpty:SetWordWrap(true)
  ui.seniorEmpty:SetText(L["Join dates come from the guild log and from the guildmates who have Guild Enhanced."])
  local h2 = S.Text(ui.colC, 9, "muted")
  h2:SetPoint("BOTTOMLEFT", 12, 10)
  h2:SetPoint("RIGHT", -12, 0)
  h2:SetWordWrap(true)
  h2:SetText(L["Congratulate fills your chat line: press Enter to send it."])
end

local function onShow()
  ns.RequestLog()
  refresh(true)
end

ns.AddPage(PAGE, "Statistics", build, onShow, { "Interface\\Icons\\INV_Misc_Spyglass_02", "Interface\\Icons\\INV_Scroll_05",
  "Interface\\Icons\\INV_Misc_Book_09" })

local pending
local function later()
  if pending then return end
  pending = true
  C_Timer.After(0.4, function()
    pending = nil
    if page and page:IsVisible() then refresh(false) end
  end)
end
ns.On("ROSTER", later)
ns.On("SYNC_JOINED", later)
