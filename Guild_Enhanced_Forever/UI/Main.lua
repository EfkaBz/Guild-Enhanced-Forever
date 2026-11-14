-- Guild Enhanced Forever: main window: header (emblem, guild name, counts), side tabs, pages
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color = S.C, S.Color

local W, H = 940, 600
ns.PAGE_W, ns.PAGE_H = W - 28, H - 72
ns.pages = {}

-- pages register themselves: ns.AddPage(index, label, builder(frame), onShow(frame), icon or icon candidates)
local builders = {}
function ns.AddPage(index, label, build, onShow, icon)
  builders[index] = { label = label, build = build, onShow = onShow, icon = icon }
end

local f
local badges = {}

-- Bug report: the Discord link, selected, ready for Ctrl+C -------------------------------------
ns.DISCORD = "https://discord.com/invite/2WXxyC84NJ"
function ns.ReportBug()
  S.Dialog({ title = L["Report a bug"], text = L["Report a bug on Discord: press Ctrl+C to copy the link."],
    input = ns.DISCORD, locked = true, accept = L["OK"] })
end

-- Language button: Auto + the 10 languages, each written in its own alphabet; asks to reload
function ns.LanguageSelector(parent)
  local options = { { "auto", L["Auto"], L["Automatic (game language)"] } }
  for _, l in ipairs(ns.LANGS) do options[#options + 1] = { l[1], l[2], l[3], l[1] } end
  local b = S.Dropdown(parent, 64, options, function() return ns.db.lang or "auto" end, function(value)
    if (ns.db.lang or "auto") == value then return end
    S.Dialog({ title = L["Language"], text = L["The interface will be reloaded to apply the language."],
      accept = L["Reload"], onAccept = function()
        ns.db.lang = value ~= "auto" and value or nil
        ReloadUI()
      end })
  end, 190)
  S.Tooltip(b, L["Language"], "ANCHOR_BOTTOM")
  return b
end

-- counter bubble on a side tab (unread messages, your turn); nil or "" hides it
function ns.SetTabBadge(i, text)
  badges[i] = text
  local t = f and f.tabs and f.tabs.tabs[i]
  if t then t:SetBadge(text) end
end

-- opens the window on a page
function ns.OpenPage(i)
  ns.db.tab = i
  ns.Show()
  if f.tabs.selected ~= i then f.tabs:Select(i) end
end

function ns.ResetPosition()
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
  f:SetScale(ns.db.scale or 1)
  local p, rel, rp, x, y = f:GetPoint(1)
  f.home = { p, rel, rp, x, y }
end

-- header text: name, then "12 online · 87 members · your rank"
function ns.RefreshHeader()
  if not f then return end
  local name = ns.GuildName()
  if not IsInGuild() or not name then
    f.title:SetText(L["Guild"])
    f.sub:SetText(L["You are not in a guild."])
    f.invite:Hide()
    return
  end
  f.title:SetText(name)
  local _, rankName = ns.MyRank()
  local total = #ns.members
  local acc = ns.db.accounts
  if acc and acc.guild == name and acc.n then
    -- the real players: alts of the same account count once
    f.sub:SetText(string.format(L["|cff1eff00%d|r online  ·  %d accounts (%d characters)  ·  %s"], ns.numOnline or 0,
      acc.n, total, "|cffffd100" .. rankName .. "|r"))
  else
    f.sub:SetText(string.format(L["|cff1eff00%d|r online  ·  %d members  ·  %s"], ns.numOnline or 0, total,
      "|cffffd100" .. rankName .. "|r"))
  end
  f.invite:SetShown(ns.Can.invite())
end

-- Accounts: only the server knows them, in its answer to /ginfo ("Guild created 11-5-2026,
-- 85 players, 74 accounts"). The addon asks quietly when the window opens and hides that answer.
local function esc(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local infoPattern, infoOrder
do
  local t = GUILD_INFO_TEMPLATE
  if type(t) == "string" then
    local pat, order, pos = "", {}, 1
    while true do
      local s, e, num = t:find("%%(%d*)%$?d", pos)
      if not s then pat = pat .. esc(t:sub(pos)); break end
      pat = pat .. esc(t:sub(pos, s - 1)) .. "(%d+)"
      order[#order + 1] = tonumber(num) or (#order + 1)
      pos = e + 1
    end
    if #order >= 5 then infoPattern, infoOrder = pat, order end
  end
end

-- number of accounts in a /ginfo answer, or nil
local function parseAccounts(msg)
  if ns.Secret(msg) or type(msg) ~= "string" then return nil end
  if infoPattern then
    local caps = { msg:match(infoPattern) }
    if #caps == #infoOrder then
      local v = {}
      for k, num in ipairs(infoOrder) do v[num] = tonumber(caps[k]) end
      if v[5] then return v[5] end
    end
  end
  local _, accounts = msg:match("(%d+) players?, (%d+) accounts?")
  return tonumber(accounts)
end
ns.ParseGuildAccounts = parseAccounts

local askedAt, lastAsk = nil, -1000
function ns.RequestGuildInfo()
  if not GuildInfo or not IsInGuild() or GetTime() - lastAsk < 60 then return end
  lastAsk, askedAt = GetTime(), GetTime()
  GuildInfo()
end

local infoEvents = CreateFrame("Frame")
infoEvents:RegisterEvent("CHAT_MSG_SYSTEM")
infoEvents:SetScript("OnEvent", function(_, _, msg)
  local n = parseAccounts(msg)
  if not n or not ns.db then return end
  ns.db.accounts = { n = n, guild = ns.GuildName() }
  ns.RefreshHeader()
  if ns.RefreshOverview then ns.RefreshOverview() end
end)
-- the answer the addon asked for stays out of the chat (a /ginfo typed by the player still shows)
if ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    return askedAt and GetTime() - askedAt < 8 and parseAccounts(msg) ~= nil
  end)
end

local function selectPage(i)
  ns.db.tab = i
  for j, p in pairs(ns.pages) do
    if j ~= i and p:IsShown() then p:Hide() end
  end
  local page = ns.pages[i]
  if not page then
    local b = builders[i]
    page = CreateFrame("Frame", nil, f.body)
    page:SetPoint("TOPLEFT")
    page:SetSize(ns.PAGE_W, ns.PAGE_H)
    b.build(page)
    ns.pages[i] = page
  end
  page:Show()
  S.SlideIn(page, 14, 0, 0.28)
  if builders[i].onShow then builders[i].onShow(page) end
end

local function build()
  f = S.Window("GuildEnhancedForeverFrame", UIParent, W, H, "", "portrait")
  ns.frame = f
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:Hide()
  f.close:SetScript("OnClick", function() ns.Hide() end)
  tinsert(UISpecialFrames, "GuildEnhancedForeverFrame") -- Escape closes it
  S.Draggable(f, f.titleBar, function(self)
    local p, _, rp, x, y = self:GetPoint(1)
    ns.db.point = { p, rp, x, y }
  end)
  -- the guild emblem: the addon icon in the round portrait
  if not S.SetPortrait(f, ns.ICON) then
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 8, -6)
    icon:SetTexture(ns.ICON)
  end

  -- header row under the title: counts on the left, buttons on the right
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", 62, -26)
  header:SetPoint("TOPRIGHT", -10, -26)
  header:SetHeight(28)
  f.header = header
  f.sub = S.Text(header, 12, "text")
  f.sub:SetPoint("LEFT", 4, 0)

  f.invite = S.Button(header, L["Invite"], 104, 22, function() ns.InviteToGuild() end, "primary")
  f.invite:SetPoint("RIGHT", 0, 0)
  S.Tooltip(f.invite, { L["Invite to guild"], L["Invite a player into the guild."] })

  f.blizz = S.Button(header, L["Classic window"], 116, 22, function()
    ns.Hide()
    ns.OpenBlizzard()
  end)
  f.blizz:SetPoint("RIGHT", f.invite, "LEFT", -4, 0)
  S.Tooltip(f.blizz, { L["Classic window"], L["Open the game's own guild window."],
    L["Type /gui blizzard to make J open it."] })

  f.lang = ns.LanguageSelector(header)
  f.lang:SetPoint("RIGHT", f.blizz, "LEFT", -6, 0)
  f.bug = S.Button(header, L["Bug"], 50, 22, ns.ReportBug)
  f.bug:SetPoint("RIGHT", f.lang, "LEFT", -6, 0)
  S.Tooltip(f.bug, { L["Report a bug"], L["Copy the link of the Discord server"] })
  f.options = S.Button(header, L["Options"], 90, 22, function() ns.OpenOptions() end)
  f.options:SetPoint("RIGHT", f.bug, "LEFT", -4, 0)
  S.Tooltip(f.options, { L["Options"], L["Notifications: pop-ups, sounds, favorites, mentions."] })

  -- tabs: the spellbook's icon tabs along the right edge
  local items = {}
  for i, b in ipairs(builders) do items[i] = { L[b.label], b.icon or "Interface\\Icons\\INV_Misc_QuestionMark" } end
  f.tabs = S.SideTabs(f, items, selectPage)
  f.tabs:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -50)
  for i, text in pairs(badges) do ns.SetTabBadge(i, text) end

  -- the pages sit in the game's dark inset
  local ok, inset = pcall(CreateFrame, "Frame", nil, f, "InsetFrameTemplate")
  if not ok or not inset then
    inset = CreateFrame("Frame", nil, f)
    S.Card(inset, 6, 0.4)
  end
  inset:SetPoint("TOPLEFT", 8, -56)
  inset:SetPoint("BOTTOMRIGHT", -8, 6)
  f.inset = inset

  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", 14, -62)
  f.body:SetPoint("BOTTOMRIGHT", -14, 10)
  f.body:SetFrameLevel(inset:GetFrameLevel() + 2)

  -- not in a guild
  f.empty = CreateFrame("Frame", nil, f)
  f.empty:SetAllPoints(f.body)
  f.empty:SetFrameLevel(f.body:GetFrameLevel() + 20)
  local et = S.Text(f.empty, 15, "muted")
  et:SetPoint("CENTER", 0, 20)
  et:SetText(L["You are not in a guild."])
  local big = f.empty:CreateTexture(nil, "ARTWORK")
  big:SetTexture(ns.ICON)
  big:SetSize(72, 72)
  big:SetPoint("BOTTOM", et, "TOP", 0, 14)
  big:SetDesaturated(true)
  big:SetAlpha(0.5)

  -- roster refresh every 20 s while open (the server throttles it anyway)
  local tick = 0
  f:SetScript("OnUpdate", function(_, e)
    tick = tick + e
    if tick > 20 then tick = 0; ns.RequestRoster() end
  end)
  f:SetScript("OnShow", function()
    tick = 0
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
  end)
  f:SetScript("OnHide", function()
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840)
    S.CloseMenu(true)
    S.FormDismiss(f) -- the options sit against the window: they close with it
  end)

  -- position
  if ns.db.point then
    local p = ns.db.point
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    f:SetScale(ns.db.scale or 1)
    local a, rel, rp, x, y = f:GetPoint(1)
    f.home = { a, rel, rp, x, y }
  else
    ns.ResetPosition()
  end
end

local function refreshGuildState()
  if not f then return end
  local inGuild = IsInGuild()
  f.empty:SetShown(not inGuild)
  f.body:SetShown(inGuild)
  f.tabs:SetShown(inGuild)
  ns.RefreshHeader()
end

function ns.Show()
  if not f then build() end
  -- reopened while it was fading out: back home, then opens again
  local reopening = f.closing
  if reopening then
    S.StopTween(f)
    f.closing = nil
    f:SetAlpha(1)
    local h = f.home
    f:ClearAllPoints()
    f:SetPoint(h[1], h[2], h[3], h[4], h[5])
  end
  ns.ScanRoster()
  ns.RequestRoster()
  ns.RequestGuildInfo()
  refreshGuildState()
  local wasShown = f:IsShown() and not reopening
  f:Show()
  f:Raise()
  if not f.tabs.selected then
    f.tabs:Select(math.min(ns.db.tab or 1, #f.tabs.tabs), true)
  else
    local i = f.tabs.selected
    if builders[i].onShow and ns.pages[i] then builders[i].onShow(ns.pages[i]) end
  end
  if not wasShown then
    S.AnimateOpen(f, 0, -14)
    f.tabs:Cascade()
  end
end

function ns.Hide()
  if f then S.AnimateClose(f, 0, -14) end
end

ns.On("ROSTER", function() if f and f:IsShown() then refreshGuildState() end end)
ns.On("GUILD", function() if f and f:IsShown() then refreshGuildState() end end)
