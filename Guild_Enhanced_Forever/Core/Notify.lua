-- Guild Enhanced Forever: notifications (toasts at the top of the screen, with a sound), their options,
-- favorite guildmates (toast when they come online), mentions of your name in the guild chat,
-- personal notes on guildmates (only for you).
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local TOAST_W, TOAST_H, MAX_TOASTS = 330, 74, 4
local NOTIFY_DEFAULTS = { toast = true, sound = true, favOnline = true, mention = true, keywords = "",
  events = true, lfg = true, crafts = true, board = true, anniv = true }

function ns.NotifyOpt(key)
  local o = ns.db and ns.db.notify
  if not o then return NOTIFY_DEFAULTS[key] end
  if o[key] == nil then return NOTIFY_DEFAULTS[key] end
  return o[key]
end

-- per guild saved tables (favorites, notes, activity...)
function ns.GuildTable(name)
  local g = ns.GuildName()
  if not g or not ns.db then return {} end
  ns.db[name] = ns.db[name] or {}
  ns.db[name][g] = ns.db[name][g] or {}
  return ns.db[name][g]
end

-- Toasts --------------------------------------------------------------------------------------------
local toasts, pool = {}, {}

local function layout(animate)
  for i, t in ipairs(toasts) do
    local y = -110 - (i - 1) * (TOAST_H + 8)
    if animate and t.y and t.y ~= y then
      local from = t.y
      S.Tween(t.posKey, { dur = 0.25, from = from, to = y, ease = "outCubic", set = function(v)
        t.y = v
        t:ClearAllPoints()
        t:SetPoint("TOP", UIParent, "TOP", 0, v)
      end })
    else
      t.y = y
      t:ClearAllPoints()
      t:SetPoint("TOP", UIParent, "TOP", 0, y)
    end
  end
end

local function close(t)
  if t.closing then return end
  t.closing = true
  S.Tween(t, { dur = 0.25, from = 1, to = 0, set = function(v)
    t:SetAlpha(v)
    t:SetScale(math.max(0.05, 0.9 + 0.1 * v))
  end, done = function()
    t:Hide()
    for i, o in ipairs(toasts) do if o == t then table.remove(toasts, i) break end end
    pool[#pool + 1] = t
    layout(true)
  end })
end

local function newToast()
  local t = table.remove(pool)
  if t then return t end
  t = CreateFrame("Button", nil, UIParent)
  t:SetSize(TOAST_W, TOAST_H)
  t:SetFrameStrata("DIALOG")
  t.posKey = {}
  S.Shadow(t, 14, 0.55, { 0.35, 0.18, 0.75 })
  S.Rounded(t, 10)
  S.EdgeGlow(t, 30, 0.18)
  t.bar = t:CreateTexture(nil, "ARTWORK")
  t.bar:SetPoint("TOPLEFT", 8, -1)
  t.bar:SetPoint("TOPRIGHT", -8, -1)
  t.bar:SetHeight(2)
  t.icon = S.Icon(t, 36)
  t.icon:SetPoint("TOPLEFT", 12, -12)
  t.title = S.Text(t, 13, "gold")
  t.title:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, 0)
  t.title:SetPoint("RIGHT", -30, 0)
  t.text = S.Text(t, 11, "text")
  t.text:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -4)
  t.text:SetPoint("RIGHT", -12, 0)
  t.text:SetWordWrap(true)
  t.text:SetJustifyV("TOP")
  t.x = S.CloseButton(t, function() close(t) end)
  t.x:SetScale(0.8)
  t.x:SetPoint("TOPRIGHT", -4, -4)
  t.b1 = S.Button(t, "", 100, 20)
  t.b2 = S.Button(t, "", 100, 20)
  -- the time left: a thin gold line that shrinks
  t.timer = t:CreateTexture(nil, "OVERLAY")
  t.timer:SetPoint("BOTTOMLEFT", 10, 3)
  t.timer:SetHeight(1.5)
  t.timer:SetColorTexture(color(C.gold, 0.6))
  t:SetScript("OnUpdate", function(self, e)
    if self.closing or not self.duration then return end
    if self:IsMouseOver() then return end -- stays while the mouse is on it
    self.left = self.left - e
    self.timer:SetWidth(math.max(0.01, (TOAST_W - 20) * self.left / self.duration))
    if self.left <= 0 then close(self) end
  end)
  t:SetScript("OnClick", function(self) if self.onClick then self.onClick(); close(self) end end)
  return t
end

-- ns.Notify{ icon, title, text, buttons = { { text, func, primary } }, sound (soundkit id or false),
--   onClick, duration (seconds, default 10), color }
function ns.Notify(a)
  if not ns.NotifyOpt("toast") then
    -- toasts off: a line in the chat frame instead
    ns.Print((a.title and ("|cffffd100" .. a.title .. "|r  ") or "") .. (a.text or ""))
  else
    local t = newToast()
    t.closing = nil
    t:SetAlpha(1)
    t:SetScale(1)
    t.icon.tex:SetTexture(S.PickIcon(a.icon or ns.ICON))
    t.title:SetText(a.title or "")
    t.text:SetText(a.text or "")
    local col = a.color or C.gold
    gradient(t.bar, { col[1], col[2], col[3], 0 }, { col[1], col[2], col[3], 0.9 }, true)
    t.onClick = a.onClick
    local btns = a.buttons or {}
    for i, b in ipairs({ t.b1, t.b2 }) do
      local spec = btns[i]
      b:SetShown(spec ~= nil)
      if spec then
        b:SetText(spec[1])
        b:SetScript("OnClick", function() spec[2](); close(t) end)
        b:ClearAllPoints()
        if i == 1 then b:SetPoint("BOTTOMRIGHT", -10, 9) else b:SetPoint("RIGHT", t.b1, "LEFT", -6, 0) end
      end
    end
    local h = 30 + t.title:GetStringHeight() + t.text:GetStringHeight() + (#btns > 0 and 28 or 8)
    t:SetHeight(math.max(TOAST_H, h))
    t.duration = a.duration or (#btns > 0 and 25 or 10)
    t.left = t.duration
    t.timer:SetWidth(TOAST_W - 20)
    table.insert(toasts, 1, t)
    while #toasts > MAX_TOASTS do close(toasts[#toasts]); table.remove(toasts) end
    layout(true)
    t:Show()
    t.y = t.y or -110
    S.Tween(t, { dur = 0.35, from = 0, to = 1, ease = "outBack", set = function(v, p)
      t:SetAlpha(math.min(1, p * 2.5))
      t:SetScale(math.max(0.05, 0.85 + 0.15 * v))
    end })
  end
  if a.sound ~= false and ns.NotifyOpt("sound") then
    PlaySound(a.sound or (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081)
  end
end

-- Favorites ------------------------------------------------------------------------------------------
function ns.IsFavorite(m)
  local name = type(m) == "table" and m.short or m
  return name and ns.GuildTable("favorites")[name] and true or false
end

function ns.ToggleFavorite(m)
  local fav = ns.GuildTable("favorites")
  fav[m.short] = not fav[m.short] or nil
  ns.Fire("FAVORITES")
end

-- Personal notes (only on this computer) -----------------------------------------------------------
function ns.PersonalNote(m) return ns.GuildTable("pnotes")[m.short] or "" end
function ns.SetPersonalNote(m, text)
  text = strtrim(text or "")
  ns.GuildTable("pnotes")[m.short] = text ~= "" and text or nil
  ns.Fire("PNOTES")
end
function ns.EditPersonalNote(m)
  S.Dialog({ title = L["Personal note"], text = string.format(L["Only you can see this note on %s."],
    "|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r"), input = ns.PersonalNote(m), maxLetters = 200,
    allowEmpty = true, accept = L["Save"], onAccept = function(text) ns.SetPersonalNote(m, text) end })
end

-- Online watch (favorites) -----------------------------------------------------------------------------
local wasOnline, lastNotified, firstScan = {}, {}, true

local function favoriteOnline(name)
  if not ns.NotifyOpt("favOnline") or not ns.IsFavorite(name) then return end
  if lastNotified[name] and GetTime() - lastNotified[name] < 120 then return end
  lastNotified[name] = GetTime()
  local m = ns.byName[name]
  local label = m and ("|c" .. ns.ClassHex(m.classFile) .. name .. "|r") or name
  ns.Notify({ icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04", title = L["Favorite online"],
    text = string.format(L["%s is now online."], label),
    sound = SOUNDKIT and SOUNDKIT.IG_PLAYER_INVITE or 880,
    buttons = m and { { L["Whisper"], function() ns.Whisper(m) end, true } } or nil })
end

ns.On("ROSTER", function()
  if not IsInGuild() or #ns.members == 0 then return end
  local now = {}
  for _, m in ipairs(ns.members) do
    if m.online then
      now[m.short] = true
      if not firstScan and not wasOnline[m.short] and not ns.IsMe(m) then favoriteOnline(m.short) end
    end
  end
  wasOnline = now
  firstScan = false
end)

-- the roster is asked again every minute, so logins are seen even with the window closed
C_Timer.NewTicker(60, function()
  if IsInGuild() and not (ns.frame and ns.frame:IsShown()) then ns.RequestRoster() end
end)

-- Mentions ---------------------------------------------------------------------------------------------
local me = UnitName("player")

local function words()
  local list = { me:lower() }
  for raw in (ns.NotifyOpt("keywords") or ""):gmatch("[^,]+") do
    local w = strtrim(raw):lower()
    if #w >= 3 then list[#list + 1] = w end
  end
  return list
end

-- a word alone (not inside another word); works with accented letters (bytes above 127 count as letters)
local function hasWord(text, w)
  local start = 1
  while true do
    local a, b = text:find(w, start, true)
    if not a then return false end
    local before, after = text:sub(a - 1, a - 1), text:sub(b + 1, b + 1)
    local function letter(c) return c ~= "" and (c:match("[%w]") or c:byte() > 127) end
    if not letter(before) and not letter(after) then return true end
    start = b + 1
  end
end

local mev = CreateFrame("Frame")
mev:RegisterEvent("CHAT_MSG_GUILD")
mev:RegisterEvent("CHAT_MSG_OFFICER")
mev:RegisterEvent("CHAT_MSG_SYSTEM")
mev:SetScript("OnEvent", function(_, event, msg, author)
  if event == "CHAT_MSG_SYSTEM" then
    -- "[Name] has come online."
    local name = msg and msg:match("|Hplayer:([^:|]+)")
    if name and ERR_FRIEND_ONLINE_SS and msg:find(ERR_FRIEND_ONLINE_SS:match("%]|h(.*)$") or "\001", 1, true) then
      favoriteOnline(ns.Short(name))
    end
    return
  end
  if not ns.NotifyOpt("mention") or not msg or not author then return end
  local who = ns.Short(author)
  if who == me then return end
  -- protected messages (|K) can't be read by an addon
  if msg:find("|K", 1, true) then return end
  local low = msg:lower()
  for _, w in ipairs(words()) do
    if hasWord(low, w) then
      local m = ns.byName[who]
      local label = m and ("|c" .. ns.ClassHex(m.classFile) .. who .. "|r") or who
      ns.Notify({ icon = "Interface\\Icons\\INV_Letter_15", title = string.format(L["%s mentioned you"], label),
        text = msg, sound = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,
        buttons = { { L["Open the chat"], function() ns.OpenPage(ns.PAGE_CHAT or 2) end, true } } })
      return
    end
  end
end)

-- Options ------------------------------------------------------------------------------------------------
function ns.OpenOptions()
  local o = ns.db.notify or {}
  ns.db.notify = o
  local function v(k) return ns.NotifyOpt(k) end
  S.Form({
    title = L["Options"], width = 470, accept = L["Save"], anchor = ns.frame,
    fields = {
      { key = "toast", label = L["Pop-ups"], kind = "check", value = v("toast"),
        hint = L["Off: the notifications go to the chat frame."] },
      { key = "sound", label = L["Sounds"], kind = "check", value = v("sound") },
      { key = "favOnline", label = L["Favorites"], kind = "check", value = v("favOnline"),
        hint = L["When a favorite guildmate comes online (right-click a member: Favorite)."] },
      { key = "mention", label = L["Mentions"], kind = "check", value = v("mention"),
        hint = L["When your name is written in the guild chat."] },
      { key = "keywords", label = L["Other words"], kind = "text", value = v("keywords"), max = 120,
        placeholder = L["raid, heal, tank..."], hint = L["Also notify for these words (separated by commas)."] },
      { key = "events", label = L["Events"], kind = "check", value = v("events") },
      { key = "lfg", label = L["Group finder"], kind = "check", value = v("lfg") },
      { key = "crafts", label = L["Craft requests"], kind = "check", value = v("crafts") },
      { key = "board", label = L["Announcements"], kind = "check", value = v("board") },
      { key = "anniv", label = L["Anniversaries"], kind = "check", value = v("anniv") },
    },
    onAccept = function(values) for k, val in pairs(values) do o[k] = val end end,
  })
end
