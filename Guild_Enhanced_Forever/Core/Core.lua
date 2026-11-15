-- Guild Enhanced Forever: saved state, guild data (roster, ranks, log), actions, events,
-- replacement of the game's guild window (J key), slash commands
local ADDON, ns = ...
local L = ns.L

ns.ICON = "Interface\\AddOns\\" .. ADDON .. "\\adds\\icon"
ns.PREFIX = "|cffffd100Guild Enhanced|r: "
ns.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
ns.CLASS_ICONS = "Interface\\WorldStateFrame\\Icons-Classes"

local DEFAULTS = {
  showOffline = true,
  sortKey = "rank",
  sortDesc = false,
  blizzard = false, -- true: J opens the game's own guild window
  tab = 1,
  rankFilter = -1,
  classFilter = {},
  scale = 1,
}

-- Small events bus -----------------------------------------------------------
local listeners = {}
function ns.On(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end
function ns.Fire(event, ...)
  for _, fn in ipairs(listeners[event] or {}) do fn(...) end
end

function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. msg) end

-- "secret" values: on this client some event arguments (chat lines, senders) can't be read by an
-- addon (any use is an error); true when one of the values is secret: the event is then skipped
local issecret = issecretvalue
function ns.Secret(...)
  if not issecret then return false end
  for i = 1, select("#", ...) do
    if issecret((select(i, ...))) then return true end
  end
  return false
end

-- name and icon of a spell, with the old API (GetSpellInfo) or the new one (C_Spell, a table)
function ns.SpellInfo(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" then return info.name, info.iconID or info.originalIconID end
  end
  if GetSpellInfo then
    local ok, name, _, icon = pcall(GetSpellInfo, id)
    if ok then return name, icon end
  end
  return nil, nil
end

-- API (with fallbacks between client versions) ------------------------------------
local G = C_GuildInfo or {}
local function call(...)
  for i = 1, select("#", ...) do
    local f = select(i, ...)
    if f then return f end
  end
  return function() end
end
local RequestRoster   = call(G.GuildRoster, GuildRoster)
local Leave           = call(GuildLeave, G.Leave)
local SetMOTD         = call(GuildSetMOTD, G.SetMOTD)
local InviteGroup     = call(C_PartyInfo and C_PartyInfo.InviteUnit, InviteUnit)
local function canViewOfficer()
  local f = G.CanViewOfficerNote or CanViewOfficerNote
  return f and f() or false
end
local function can(name) local f = _G[name] or G[name]; return f and f() and true or false end

-- Roster -------------------------------------------------------------------------
ns.members = {}
ns.byName = {}

local function classColor(file)
  local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[file or ""]
  if c then return c.r, c.g, c.b end
  return 0.75, 0.75, 0.75
end
ns.ClassColor = classColor

function ns.ClassHex(file)
  local r, g, b = classColor(file)
  return string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- class icon on a texture (cropped)
function ns.SetClassIcon(tex, file)
  local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[file or ""]
  if tc then
    tex:SetTexture(ns.CLASS_ICONS)
    local inset = 0.012
    tex:SetTexCoord(tc[1] + inset, tc[2] - inset, tc[3] + inset, tc[4] - inset)
  else
    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
end

-- my full roster name: on WoW Forever several players share a first name ("Daeler Backbi",
-- "Daeler Smith") and UnitName gives the first name alone; found by GUID in the roster
function ns.MyName() return ns.myName or UnitName("player") end
-- the same author? "by" may be an old first name alone ("Daeler"), the same player when no
-- other member shares that first name
function ns.SameAuthor(ed, by)
  if not ed or not by then return false end
  if ed == by then return true end
  local m = ns.byName[by]
  return m ~= nil and m.name ~= by and m.name == ed and not (ns.sharedFirst and ns.sharedFirst[by])
end
local nameHooks = {}
-- fn(fullName) now if known, and whenever it becomes known
function ns.OnMyName(fn)
  nameHooks[#nameHooks + 1] = fn
  if ns.myName then fn(ns.myName) end
end
-- an old record saved under the first name alone ("Daeler"), before full names were used: hidden
-- when that first name is shared, or when the same player already has a record under the full name
function ns.IsOldAlias(id, coll)
  local m = id and ns.byName[id]
  if not m or m.name == id then return false end
  if ns.sharedFirst and ns.sharedFirst[id] then return true end
  return coll ~= nil and ns.Sync.Get(coll, m.name) ~= nil
end

function ns.Short(name) return name and (Ambiguate and Ambiguate(name, "guild") or name:gsub("%-.*", "")) or "" end

function ns.LastOnlineText(m)
  if m.online then return L["Online"] end
  local y, mo, d, h = m.lastY or 0, m.lastM or 0, m.lastD or 0, m.lastH or 0
  if y > 0 then return string.format(L["%d y"], y) end
  if mo > 0 then return string.format(L["%d mo"], mo) end
  if d > 0 then return string.format(L["%d d"], d) end
  if h > 0 then return string.format(L["%d h"], h) end
  return L["< 1 h"]
end

local function statusOf(online, status)
  if not online then return "offline" end
  if status == 1 or status == "<AFK>" or status == CHAT_FLAG_AFK then return "afk" end
  if status == 2 or status == "<DND>" or status == CHAT_FLAG_DND then return "dnd" end
  return "online"
end

function ns.ScanRoster()
  wipe(ns.members)
  wipe(ns.byName)
  ns.sharedFirst = {}
  if not IsInGuild() then return end
  local total = GetNumGuildMembers() or 0
  local online = 0
  for i = 1, total do
    local name, rank, rankIndex, level, class, zone, note, onote, isOnline, status, classFile, _, _, isMobile, _, _, guid =
      GetGuildRosterInfo(i)
    if name then
      local y, mo, d, h = GetGuildRosterLastOnline(i)
      local m = {
        index = i, name = name, short = ns.Short(name), rank = rank or "", rankIndex = rankIndex or 0,
        level = level or 0, class = class or "", classFile = classFile, zone = zone or "",
        note = note or "", onote = onote or "", online = isOnline and not isMobile and true or false,
        guid = guid, lastY = y, lastM = mo, lastD = d, lastH = h,
      }
      m.status = statusOf(m.online, status)
      m.lastHours = m.online and -1 or (((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 24 + (h or 0))
      if m.online then online = online + 1 end
      if guid and UnitGUID and guid == UnitGUID("player") then ns.myName = name end
      ns.members[#ns.members + 1] = m
      ns.byName[name] = m
      ns.byName[m.short] = ns.byName[m.short] or m
      -- WoW Forever: the roster shows "Daeler Backbi" (name + surname) while UnitName and the
      -- senders of addon messages give the name alone ("Daeler"): index that too
      local first = m.short:match("^(%S+)%s")
      if first then
        if ns.byName[first] and ns.byName[first] ~= m then ns.sharedFirst[first] = true end
        ns.byName[first] = ns.byName[first] or m
      end
    end
  end
  ns.numOnline = online
  if ns.myName and ns.myName ~= ns.myNameSent then
    ns.myNameSent = ns.myName
    for _, fn in ipairs(nameHooks) do pcall(fn, ns.myName) end
  end
end

-- asks the server for a fresh roster (it answers with GUILD_ROSTER_UPDATE; throttled server side)
function ns.RequestRoster()
  if not IsInGuild() then return end
  if SetGuildRosterShowOffline and GetGuildRosterShowOffline and not GetGuildRosterShowOffline() then
    SetGuildRosterShowOffline(true)
  end
  RequestRoster()
end

-- finds the current roster index of a member (it moves when the game re-sorts the roster)
function ns.IndexOf(name)
  for i = 1, GetNumGuildMembers() or 0 do
    if GetGuildRosterInfo(i) == name then return i end
  end
end

-- Guild and ranks -----------------------------------------------------------------
function ns.GuildName()
  local name = GetGuildInfo("player")
  return name
end

function ns.MyRank()
  local _, rankName, rankIndex = GetGuildInfo("player")
  return rankIndex or 99, rankName or ""
end

function ns.NumRanks() return GuildControlGetNumRanks and GuildControlGetNumRanks() or 0 end

-- rank names; index 0 = guild master (roster convention)
function ns.Ranks()
  local list = {}
  for i = 1, ns.NumRanks() do list[i - 1] = GuildControlGetRankName(i) or "" end
  return list
end

-- Permissions -----------------------------------------------------------------------
ns.Can = {
  invite = function() return can("CanGuildInvite") end,
  motd = function() return can("CanEditMOTD") end,
  info = function() return can("CanEditGuildInfo") end,
  publicNote = function() return can("CanEditPublicNote") end,
  officerNote = function() return can("CanEditOfficerNote") end,
  viewOfficer = canViewOfficer,
  leader = function() return IsGuildLeader and IsGuildLeader() and true or false end,
}

local function isMe(m)
  if not m then return false end
  if ns.myName then return m.name == ns.myName end
  return m.name == UnitName("player") or m.short == UnitName("player")
end
ns.IsMe = isMe

function ns.CanPromote(m)
  return m and not isMe(m) and can("CanGuildPromote") and m.rankIndex > ns.MyRank() + 1
end
function ns.CanDemote(m)
  return m and not isMe(m) and can("CanGuildDemote") and m.rankIndex > ns.MyRank() and m.rankIndex < ns.NumRanks() - 1
end
function ns.CanRemove(m)
  return m and not isMe(m) and can("CanGuildRemove") and m.rankIndex > ns.MyRank()
end
function ns.CanMakeLeader(m) return m and not isMe(m) and ns.Can.leader() end

-- Actions -----------------------------------------------------------------------------
function ns.Whisper(m) if m then ChatFrame_SendTell(m.name) end end
function ns.GroupInvite(m) if m then InviteGroup(m.name) end end
-- promote / demote open the rank window (Core\RankPicker.lua), the next rank up or down preselected
function ns.Promote(m) if ns.CanPromote(m) then ns.ChangeRank(m, -1) end end
function ns.Demote(m) if ns.CanDemote(m) then ns.ChangeRank(m, 1) end end

function ns.Remove(m)
  if not ns.CanRemove(m) then return end
  -- GuildUninvite is protected on this client: the game's /gremove runs from a secure button
  local cmd = _G.SLASH_GUILD_UNINVITE1 or "/gremove"
  ns.SecureAsk({
    title = L["Remove from guild"],
    text = string.format(L["Remove %s from the guild?"], "|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r"),
    accept = L["Remove"],
    macro = function() return cmd .. " " .. m.name end,
  })
end

function ns.MakeLeader(m)
  if not ns.CanMakeLeader(m) then return end
  -- GuildSetLeader is protected on this client: the game's /gleader runs from a secure button
  local cmd = _G.SLASH_GUILD_LEADER1 or "/gleader"
  ns.SecureAsk({
    title = L["Promote to guild master"],
    text = string.format(L["Give the guild leadership to %s? You can't undo this yourself."],
      "|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r"),
    accept = L["Make leader"],
    macro = function() return cmd .. " " .. m.name end,
  })
end

function ns.EditNote(m, officer)
  if not m then return end
  if officer and not ns.Can.officerNote() then return end
  if not officer and not ns.Can.publicNote() then return end
  ns.Skin.Dialog({
    title = officer and L["Officer note"] or L["Public note"],
    text = "|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r",
    input = officer and m.onote or m.note, maxLetters = 31, allowEmpty = true,
    accept = L["Save"],
    onAccept = function(text)
      local i = ns.IndexOf(m.name)
      if not i then return end
      if officer then GuildRosterSetOfficerNote(i, text) else GuildRosterSetPublicNote(i, text) end
      ns.RequestRoster()
    end,
  })
end

-- GuildInvite is for the game's own interface alone on this server: an addon, a macro, a script,
-- the "Add member" box opened by a script and even /ginvite are blocked or ignored. Only the game's
-- right-click menu on a player ("Guild invite") works: the button explains it.
function ns.InviteToGuild()
  ns.Skin.Dialog({
    title = L["Invite to guild"],
    text = L["To invite a player, right-click their name (in the chat, on their portrait or their character) and choose \"Guild invite\". On this server, only the game's own menu can send a guild invitation: no addon can do it."],
    accept = L["OK"],
  })
end

-- Message of the day: GetGuildRosterMOTD() is protected on this client (an addon calling it is
-- blocked), so the text is kept from what the game sends: the GUILD_MOTD event and the line shown
-- in the chat at login. Saved per guild, so it shows at once next time.
local function storeMOTD(text)
  if not ns.db or type(text) ~= "string" then return end
  ns.db.motd = { guild = ns.GuildName(), text = text }
end
function ns.GetMOTD()
  local c = ns.db and ns.db.motd
  if not c then return "" end
  local guild = ns.GuildName()
  if c.guild == nil and guild then c.guild = guild end -- stored at login before the guild name was known
  if c.guild ~= nil and guild and c.guild ~= guild then return "" end
  return c.text or ""
end

local motdPattern
if type(GUILD_MOTD_TEMPLATE) == "string" then
  local esc = GUILD_MOTD_TEMPLATE:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  local pat, n = esc:gsub("%%%%s", "(.*)", 1)
  if n == 1 then motdPattern = "^" .. pat .. "$" end
end

function ns.SetMOTD(text)
  SetMOTD(text or "")
  storeMOTD(text or "")
  ns.Queue("guild")
end

function ns.LeaveGuild()
  ns.Skin.Dialog({
    title = L["Leave guild"],
    text = string.format(L["Leave %s?"], "|cffffd100" .. (ns.GuildName() or "") .. "|r"),
    accept = L["Leave"], danger = true,
    onAccept = function() Leave() end,
  })
end

-- right-click menu of a member
function ns.MemberMenu(owner, m)
  if not m then return end
  local items = {
    { text = "|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r", title = true },
    { text = L["Whisper"], func = function() ns.Whisper(m) end, disabled = isMe(m) },
    { text = L["Invite to group"], func = function() ns.GroupInvite(m) end, disabled = isMe(m) or not m.online },
    { text = L["Copy name"], func = function() ns.CopyName(m) end },
    { text = ns.IsFavorite(m) and L["Remove from favorites"] or L["Add to favorites"], func = function() ns.ToggleFavorite(m) end,
      disabled = isMe(m) },
    { text = L["Personal note"], func = function() ns.EditPersonalNote(m) end },
    { separator = true },
    { text = L["Promote"], func = function() ns.Promote(m) end, disabled = not ns.CanPromote(m) },
    { text = L["Demote"], func = function() ns.Demote(m) end, disabled = not ns.CanDemote(m) },
    { text = L["Edit public note"], func = function() ns.EditNote(m) end, disabled = not ns.Can.publicNote() },
  }
  if ns.Can.viewOfficer() then
    items[#items + 1] = { text = L["Edit officer note"], func = function() ns.EditNote(m, true) end,
      disabled = not ns.Can.officerNote() }
  end
  items[#items + 1] = { separator = true }
  items[#items + 1] = { text = L["Remove from guild"], func = function() ns.Remove(m) end,
    disabled = not ns.CanRemove(m), color = ns.Skin.C.bad }
  if ns.Can.leader() and not isMe(m) then
    items[#items + 1] = { text = L["Make leader"], func = function() ns.MakeLeader(m) end, color = ns.Skin.C.warn }
  end
  ns.Skin.OpenMenu(owner, items, { width = 180 })
end

-- puts the name in a dialog field, selected, ready for Ctrl+C
function ns.CopyName(m)
  ns.Skin.Dialog({
    title = L["Copy name"], text = L["Press Ctrl+C to copy."],
    input = m.name, accept = L["OK"],
  })
end

-- Event log -----------------------------------------------------------------------------
function ns.RequestLog() if QueryGuildEventLog then QueryGuildEventLog() end end

function ns.ScanLog()
  local list = {}
  for i = 1, (GetNumGuildEvents and GetNumGuildEvents() or 0) do
    local kind, p1, p2, rank, y, mo, d, h = GetGuildEventInfo(i)
    if kind then
      list[#list + 1] = { kind = kind, p1 = p1, p2 = p2, rank = rank, y = y or 0, mo = mo or 0, d = d or 0, h = h or 0,
        age = (((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 24 + (h or 0)), order = i }
    end
  end
  table.sort(list, function(a, b)
    if a.age ~= b.age then return a.age < b.age end
    return a.order > b.order
  end)
  return list
end

-- Open / close and the J key ---------------------------------------------------------------
local origToggle

function ns.Toggle()
  if ns.frame and ns.frame:IsShown() and not ns.frame.closing then ns.Hide() else ns.Show() end
end

-- the game's own window (Friends frame, Guild tab), opened on purpose
function ns.OpenBlizzard()
  ns.allowBlizzard = true
  if origToggle then origToggle() end
  ns.allowBlizzard = false
end

-- after the Guild tab of the Friends window shows: back to the Friends tab, and ours instead
local function redirectFromFriends()
  if ns.db.blizzard or ns.allowBlizzard then return end
  C_Timer.After(0, function()
    if FriendsFrame and FriendsFrame:IsShown() then
      local tab = _G.FriendsFrameTab1
      if tab and tab.Click then pcall(tab.Click, tab) end
      HideUIPanel(FriendsFrame)
    end
    ns.Show()
  end)
end

local function hookGameWindow()
  if ToggleGuildFrame and not origToggle then
    origToggle = ToggleGuildFrame
    ToggleGuildFrame = function(...)
      if ns.db.blizzard then return origToggle(...) end
      ns.Toggle()
    end
  end
  if GuildFrame and not ns.hookedGuildFrame then
    ns.hookedGuildFrame = true
    GuildFrame:HookScript("OnShow", redirectFromFriends)
  end
end

-- Events --------------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_GUILD_UPDATE")
ev:RegisterEvent("GUILD_MOTD")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:RegisterEvent("GUILD_RANKS_UPDATE")
ev:RegisterEvent("GUILD_EVENT_LOG_UPDATE")
pcall(ev.RegisterEvent, ev, "GUILD_INFO_TEXT_CHANGED")

local pending, scheduled = {}, false
local function flush()
  scheduled = false
  if pending.roster then ns.ScanRoster() end
  for k in pairs(pending) do ns.Fire(k:upper()) end
  wipe(pending)
end
-- groups bursts of events into one refresh
local function queue(what)
  pending[what] = true
  if not scheduled then
    scheduled = true
    C_Timer.After(0.15, flush)
  end
end
ns.Queue = queue

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then
      GuildEnhancedForeverDB = GuildEnhancedForeverDB or {}
      for k, v in pairs(DEFAULTS) do
        if GuildEnhancedForeverDB[k] == nil then
          GuildEnhancedForeverDB[k] = type(v) == "table" and CopyTable(v) or v
        end
      end
      ns.db = GuildEnhancedForeverDB
      ns.ApplyLanguage(ns.db.lang)
      hookGameWindow()
    elseif arg1 == "Blizzard_GuildUI" or arg1 == "Blizzard_Communities" then
      hookGameWindow()
    end
  elseif event == "PLAYER_LOGIN" then
    hookGameWindow()
    ns.RequestRoster()
  elseif event == "GUILD_ROSTER_UPDATE" then
    queue("roster")
  elseif event == "PLAYER_GUILD_UPDATE" then
    queue("roster"); queue("guild")
    ns.RequestRoster()
  elseif event == "GUILD_MOTD" then
    if not ns.Secret(arg1) then storeMOTD(arg1) end
    queue("guild")
  elseif event == "CHAT_MSG_SYSTEM" then
    if ns.Secret(arg1) then return end
    local text = motdPattern and type(arg1) == "string" and arg1:match(motdPattern)
    if text then storeMOTD(text); queue("guild") end
  elseif event == "GUILD_RANKS_UPDATE" then
    queue("ranks"); queue("roster")
  elseif event == "GUILD_EVENT_LOG_UPDATE" then
    queue("log")
  elseif event == "GUILD_INFO_TEXT_CHANGED" then
    queue("guild")
  end
end)

-- Slash commands --------------------------------------------------------------------------------
SLASH_GUILDENHANCEDFOREVER1 = "/gui"
SLASH_GUILDENHANCEDFOREVER2 = "/guildui"
SLASH_GUILDENHANCEDFOREVER3 = "/guildenhanced"
SlashCmdList.GUILDENHANCEDFOREVER = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "blizzard" then
    ns.db.blizzard = not ns.db.blizzard
    ns.Print(ns.db.blizzard and L["J now opens the game's guild window."] or L["J now opens Guild Enhanced."])
  elseif msg == "reset" then
    ns.db.point = nil
    ns.db.scale = 1
    if ns.frame then ns.ResetPosition() end
    ns.Print(L["Window position reset."])
  elseif msg:match("^scale") then
    local v = tonumber(msg:match("^scale%s+([%d%.]+)"))
    if v and v >= 0.6 and v <= 1.6 then
      ns.db.scale = v
      if ns.frame then ns.frame:SetScale(v) end
    else
      ns.Print("/gui scale 0.6 - 1.6")
    end
  elseif msg == "net" and ns.Net then
    ns.Net.Debug()
  elseif msg == "prof" and ns.ProfDebug then
    ns.ProfDebug()
  elseif msg == "help" then
    ns.Print("/gui — " .. L["open or close the window"])
    ns.Print("/gui blizzard — " .. L["J opens the game's guild window instead (toggle)"])
    ns.Print("/gui scale <0.6-1.6> — " .. L["window size"])
    ns.Print("/gui reset — " .. L["reset the window position"])
  else
    ns.Toggle()
  end
end
