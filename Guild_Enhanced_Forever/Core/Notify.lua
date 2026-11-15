-- Guild Enhanced Forever: notifications (toasts at the top of the screen, with a sound), their options,
-- favorite guildmates (toast when they come online), mentions of your name in the guild chat,
-- personal notes on guildmates (only for you).
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local TOAST_W, TOAST_H = 330, 74
-- toastTime: seconds on screen (0 = until closed; doubled for a toast with buttons); toastPos: top,
-- middle or bottom of the screen; toastScale: size; toastMax: shown at once; noCombat: during a
-- fight they go to the chat frame
local NOTIFY_DEFAULTS = { toast = true, sound = true, favOnline = true, mention = true, keywords = "",
  events = true, lfg = true, crafts = true, board = true, anniv = true,
  toastTime = 10, toastPos = "top", toastScale = 1, toastMax = 4, noCombat = false }

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

-- where the toasts stack: anchor point on the screen, first offset, direction
local POS = {
  top = { "TOP", "TOP", -110, -1 },
  middle = { "TOP", "CENTER", 160, -1 },
  bottom = { "BOTTOM", "BOTTOM", 190, 1 },
}
local function place(t, y)
  local p = POS[ns.NotifyOpt("toastPos")] or POS.top
  local sc = ns.NotifyOpt("toastScale") or 1
  t:ClearAllPoints()
  t:SetPoint(p[1], UIParent, p[2], 0, y / sc) -- (offsets are in the toast's own scale)
end
local function layout(animate)
  local p = POS[ns.NotifyOpt("toastPos")] or POS.top
  local sc = ns.NotifyOpt("toastScale") or 1
  local y = p[3]
  for _, t in ipairs(toasts) do
    local target = y
    y = y + p[4] * ((t:GetHeight() or TOAST_H) + 8) * sc
    if animate and t.y and t.y ~= target then
      local from = t.y
      S.Tween(t.posKey, { dur = 0.25, from = from, to = target, ease = "outCubic", set = function(v)
        t.y = v
        place(t, v)
      end })
    else
      t.y = target
      place(t, target)
    end
  end
end

local function close(t)
  if t.closing then return end
  t.closing = true
  S.Tween(t, { dur = 0.25, from = 1, to = 0, set = function(v)
    t:SetAlpha(v)
    t:SetScale(math.max(0.05, (0.9 + 0.1 * v) * (ns.NotifyOpt("toastScale") or 1)))
    place(t, t.y or 0)
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
    if self.closing or not self.duration or self.duration <= 0 then return end
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
  local inFight = ns.NotifyOpt("noCombat") and InCombatLockdown and InCombatLockdown()
  if not ns.NotifyOpt("toast") or inFight then
    -- toasts off: a line in the chat frame instead
    ns.Print((a.title and ("|cffffd100" .. a.title .. "|r  ") or "") .. (a.text or ""))
  else
    local t = newToast()
    t.closing = nil
    t:SetAlpha(1)
    local sc = ns.NotifyOpt("toastScale") or 1
    t:SetScale(sc)
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
    local base = ns.NotifyOpt("toastTime") or 10
    t.duration = a.duration or (base <= 0 and 0) or (#btns > 0 and base * 2 or base)
    t.left = t.duration
    t.timer:SetWidth(TOAST_W - 20)
    t.timer:SetShown(t.duration > 0)
    table.insert(toasts, 1, t)
    local max = ns.NotifyOpt("toastMax") or 4
    while #toasts > max do close(toasts[#toasts]); table.remove(toasts) end
    t.y = nil
    layout(true)
    t:Show()
    S.Tween(t, { dur = 0.35, from = 0, to = 1, ease = "outBack", set = function(v, p)
      t:SetAlpha(math.min(1, p * 2.5))
      t:SetScale(math.max(0.05, (0.85 + 0.15 * v) * sc))
      place(t, t.y or 0)
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
  if ns.Secret(msg, author) then return end
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
-- a window of its own in the addon's look (the game's portrait frame with the guild crest), in three
-- sections; every label is shown in full (check box on the left, label and explanation on the right)
local OPT_W, PAD, INNER = 520, 16, 520 - 2 * 30
local opt

local function buildOptions()
  opt = S.Window("GuildEnhancedForeverOptions", UIParent, OPT_W, 400, L["Options"], "portrait")
  opt:SetFrameStrata("DIALOG")
  opt:SetToplevel(true)
  opt:Hide()
  S.Draggable(opt, opt.titleBar)
  if not S.SetPortrait(opt, ns.ICON) then
    local icon = opt:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 8, -6)
    icon:SetTexture(ns.ICON)
  end
  opt.close:SetScript("OnClick", function() opt:Hide() end)
  tinsert(UISpecialFrames, "GuildEnhancedForeverOptions") -- Escape closes it

  opt.sub = S.Text(opt, 12, "dim")
  opt.sub:SetPoint("TOPLEFT", 66, -32)
  opt.sub:SetText(L["Notify me about:"])

  local card = CreateFrame("Frame", nil, opt)
  card:SetPoint("TOPLEFT", 14, -62)
  card:SetPoint("BOTTOMRIGHT", -14, 52)
  S.Card(card, 8)
  opt.card = card
  opt.checks = {}
  opt.drops = {}
  opt.pending = {}

  local y = 12
  local function section(text)
    local h = S.Section(card, text)
    h:SetPoint("TOPLEFT", PAD, -y)
    h:SetPoint("TOPRIGHT", -PAD, -y)
    y = y + 30
  end
  -- a check box with its full label; hint: an explanation under the label; x, w: its column
  local function check(key, label, hint, x, w)
    x, w = x or PAD, w or (INNER - PAD)
    local c = S.Check(card, label, 18)
    c:SetPoint("TOPLEFT", x, -y)
    c.text:SetFontObject(GameFontHighlight)
    c.text:SetWidth(w - 30)
    c.text:SetWordWrap(true)
    c:SetHitRectInsets(0, -(w - 30), 0, 0)
    c.key = key
    opt.checks[#opt.checks + 1] = c
    local h = 26
    if hint then
      local t = S.Text(card, 11, "muted")
      t:SetPoint("TOPLEFT", c.text, "BOTTOMLEFT", 0, -3)
      t:SetWidth(w - 30)
      t:SetWordWrap(true)
      t:SetText(hint)
      h = h + math.ceil(t:GetStringHeight()) + 2
    end
    return h
  end

  section(L["Notifications"])
  y = y + check("toast", L["Pop-ups"], L["Off: the notifications go to the chat frame."])
  y = y + check("sound", L["Sounds"])
  y = y + check("noCombat", L["Not during combat"], L["During a fight the notifications go to the chat frame."]) + 4
  -- display: two columns of a label above a menu
  local colW = math.floor((INNER - PAD) / 2)
  local function choice(key, label, options, col)
    local x = PAD + 4 + col * colW
    local t = S.Text(card, 12, "text")
    t:SetFontObject(GameFontHighlight)
    t:SetPoint("TOPLEFT", x, -y)
    t:SetText(label)
    local d = S.Dropdown(card, colW - 24, options, function() return opt.pending[key] end, function(v)
      opt.pending[key] = v
    end, colW - 24)
    d:SetPoint("TOPLEFT", x - 2, -(y + 18))
    opt.drops[#opt.drops + 1] = d
  end
  local function secs(n) return { n, L["%d seconds"]:format(n) } end
  choice("toastTime", L["Display time"], { secs(5), secs(10), secs(15), secs(20), secs(30), secs(60),
    { 0, L["Until closed"] } }, 0)
  choice("toastPos", L["Position"], { { "top", L["Top of the screen"] }, { "middle", L["Middle of the screen"] },
    { "bottom", L["Bottom of the screen"] } }, 1)
  y = y + 50
  choice("toastScale", L["Size"], { { 0.8, "80 %" }, { 0.9, "90 %" }, { 1, "100 %" }, { 1.1, "110 %" },
    { 1.25, "125 %" }, { 1.5, "150 %" } }, 0)
  choice("toastMax", L["Shown at once"], { { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" }, { 5, "5" }, { 6, "6" } }, 1)
  y = y + 50
  local hint = S.Text(card, 11, "muted")
  hint:SetPoint("TOPLEFT", PAD + 4, -y)
  hint:SetWidth(INNER - PAD - 130)
  hint:SetWordWrap(true)
  hint:SetText(L["The time is doubled for a notification with buttons."])
  opt.test = S.Button(card, L["Test"], 110, 22, function()
    -- shown with the choices of this window, even before saving
    local o = ns.db.notify or {}
    ns.db.notify = o
    local saved = { toast = o.toast }
    for k, v in pairs(opt.pending) do saved[k] = o[k]; o[k] = v end
    o.toast = true
    ns.Notify({ title = L["Options"], text = L["This is how your notifications will look."] })
    for k in pairs(opt.pending) do o[k] = saved[k] end
    o.toast = saved.toast
  end)
  opt.test:SetPoint("TOPRIGHT", -PAD, -(y - 2))
  y = y + math.max(26, math.ceil(hint:GetStringHeight()) + 8) + 6

  section(L["Guildmates"])
  y = y + check("favOnline", L["Favorites"], L["When a favorite guildmate comes online (right-click a member: Favorite)."])
  y = y + check("mention", L["Mentions"], L["When your name is written in the guild chat."])
  local kw = S.Text(card, 12, "text")
  kw:SetFontObject(GameFontHighlight)
  kw:SetPoint("TOPLEFT", PAD + 4, -(y + 4))
  kw:SetText(L["Other words"])
  opt.keywords = S.EditBox(card, INNER - PAD - 20, 24, L["raid, heal, tank..."])
  opt.keywords:SetPoint("TOPLEFT", PAD + 4, -(y + 22))
  opt.keywords:SetMaxLetters(120)
  local kwHint = S.Text(card, 11, "muted")
  kwHint:SetPoint("TOPLEFT", opt.keywords, "BOTTOMLEFT", 0, -4)
  kwHint:SetWidth(INNER - PAD - 20)
  kwHint:SetWordWrap(true)
  kwHint:SetText(L["Also notify for these words (separated by commas)."])
  y = y + 22 + 24 + 6 + math.ceil(kwHint:GetStringHeight()) + 14

  section(L["Guild activity"])
  local items = { { "events", L["Events"] }, { "lfg", L["Group finder"] }, { "crafts", L["Craft requests"] },
    { "board", L["Announcements"] }, { "anniv", L["Anniversaries"] } }
  for i, it in ipairs(items) do
    local col = (i - 1) % 2
    check(it[1], it[2], nil, PAD + col * colW, colW)
    if col == 1 or i == #items then y = y + 28 end
  end
  y = y + 6

  opt:SetHeight(62 + y + 52)

  opt.save = S.Button(opt, L["Save"], 140, 26, function()
    local o = ns.db.notify or {}
    ns.db.notify = o
    for _, c in ipairs(opt.checks) do o[c.key] = c:GetChecked() and true or false end
    o.keywords = ns.Net.Clean(strtrim(opt.keywords:GetText() or ""))
    for k, v in pairs(opt.pending) do o[k] = v end
    opt:Hide()
  end, "primary")
  opt.save:SetPoint("BOTTOMRIGHT", opt, "BOTTOM", -6, 16)
  opt.cancel = S.Button(opt, L["Cancel"], 140, 26, function() opt:Hide() end)
  opt.cancel:SetPoint("BOTTOMLEFT", opt, "BOTTOM", 6, 16)
end

function ns.CloseOptions() if opt then opt:Hide() end end

function ns.OpenOptions()
  if not opt then buildOptions() end
  S.FormDismiss()
  for _, c in ipairs(opt.checks) do c:SetChecked(ns.NotifyOpt(c.key) and true or false) end
  opt.keywords:SetText(ns.NotifyOpt("keywords") or "")
  for _, k in ipairs({ "toastTime", "toastPos", "toastScale", "toastMax" }) do opt.pending[k] = ns.NotifyOpt(k) end
  for _, d in ipairs(opt.drops) do d:Refresh() end
  opt:ClearAllPoints()
  if ns.frame and ns.frame:IsShown() then
    opt:SetPoint("TOPRIGHT", ns.frame, "TOPLEFT", -4, 0)
  else
    opt:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  end
  opt:Show()
  opt:Raise()
end
