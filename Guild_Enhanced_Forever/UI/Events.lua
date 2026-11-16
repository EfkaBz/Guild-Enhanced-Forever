-- Guild Enhanced Forever: events page.
--   Calendar: raids, dungeons, outings created by guildmates (date, time, place, size); everyone
--   answers Present / Maybe / Absent with a role; past the size, the next "present" go to the
--   waiting list (in the order they signed up), with role counters.
--   Group finder: "looking for 2 dps for Scholomance"; one click sends a join request, the poster
--   gets a pop-up with an Invite button.
-- Shared with the guildmates who have the addon (ns.Sync collections "events", "rsvp", "lfg").
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient
local Sync, Net = ns.Sync, ns.Net
local now = GetServerTime or time

local PAGE = 4
local LIST_W, ROW_H, LFG_H = 330, 54, 50
local page, ui = nil, { rows = {}, lfgRows = {}, people = {} }
local mode, selected = "cal", nil
local requests = {} -- lfg id -> { { name, role, cls, lvl } }

-- Roles ------------------------------------------------------------------------------------------------
local ROLES = {
  { "tank", "Tank", { "Interface\\Icons\\Ability_Defend", "Interface\\Icons\\INV_Shield_06" } },
  { "heal", "Healer", { "Interface\\Icons\\Spell_Holy_FlashHeal", "Interface\\Icons\\Spell_Holy_Heal" } },
  { "dps", "Damage", { "Interface\\Icons\\INV_Sword_04", "Interface\\Icons\\Ability_DualWield" } },
}
local ROLE = {}
for _, r in ipairs(ROLES) do ROLE[r[1]] = r end
ns.ROLES = ROLES

local CLASS_ROLE = { WARRIOR = "tank", PRIEST = "heal", PALADIN = "heal", SHAMAN = "heal", DRUID = "heal" }
function ns.MyRole()
  if ns.db.myRole and ROLE[ns.db.myRole] then return ns.db.myRole end
  local _, file = UnitClass("player")
  return CLASS_ROLE[file] or "dps"
end
function ns.RoleIcon(role) return S.PickIcon(ROLE[role] and ROLE[role][3] or ROLE.dps[3]) end
-- the game's round role icon (its group finder art) on a texture; the spell icon when it lacks it
local GAME_ROLE = { tank = "TANK", heal = "HEALER", dps = "DAMAGER" }
function ns.SetRoleIcon(tex, role)
  role = ROLE[role] and role or "dps"
  if GetTexCoordsForRole then
    tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
    tex:SetTexCoord(GetTexCoordsForRole(GAME_ROLE[role]))
  else
    tex:SetTexture(ns.RoleIcon(role))
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
end
function ns.RoleName(role) return L[ROLE[role] and ROLE[role][2] or "Damage"] end

-- Kinds and places ------------------------------------------------------------------------------------
local KINDS = {
  { "raid", "Raid", { "Interface\\Icons\\INV_Misc_Head_Dragon_01" } },
  { "dungeon", "Dungeon", { "Interface\\Icons\\INV_Misc_Key_03", "Interface\\Icons\\INV_Misc_Key_01" } },
  { "pvp", "PvP", { "Interface\\Icons\\INV_BannerPVP_02", "Interface\\Icons\\INV_Sword_27" } },
  { "outing", "Outing", { "Interface\\Icons\\INV_Misc_Food_15", "Interface\\Icons\\INV_Drink_04" } },
  { "other", "Other", { "Interface\\Icons\\INV_Misc_Note_01" } },
}
local KIND = {}
for _, k in ipairs(KINDS) do KIND[k[1]] = k end

-- the places of each kind: instance map ids -> the client's own (translated) names, English when it
-- does not know them; wings get their own entry ("Scarlet Monastery - Library"), in dungeon order.
-- F marks the new dungeons of the Forever server (no map id: their names come from the locales)
local FOREVER_STAR = "|TInterface\\COMMON\\ReputationStar:14:14:0:0:32:32:0:16:0:16|t"
local function F(english) return { nil, english, forever = true } end
local PLACES = {
  raid = {
    { 309, "Zul'Gurub" }, { 409, "Molten Core" }, { 249, "Onyxia's Lair" }, { 469, "Blackwing Lair" },
    { 509, "Ruins of Ahn'Qiraj" }, { 531, "Temple of Ahn'Qiraj" }, { 533, "Naxxramas" },
  },
  dungeon = {
    { 389, "Ragefire Chasm" }, F("The Hall of Thanes"), F("Ruins of Lordaeron"),
    { 43, "Wailing Caverns" }, { 36, "The Deadmines" }, { 33, "Shadowfang Keep" },
    { 48, "Blackfathom Deeps" }, { 34, "The Stockade" }, F("Excavation Site: Wetlands"), F("City of Dalaran"),
    { 90, "Gnomeregan" }, { 47, "Razorfen Kraul" },
    { 189, "Scarlet Monastery", "Graveyard" }, { 189, "Scarlet Monastery", "Library" },
    { 189, "Scarlet Monastery", "Armory" }, { 189, "Scarlet Monastery", "Cathedral" },
    F("The Drowned City"), { 129, "Razorfen Downs" }, F("Krol'dok Stronghold"),
    { 70, "Uldaman" }, { 209, "Zul'Farrak" }, { 349, "Maraudon" }, F("Alcaz Prison"),
    { 109, "Sunken Temple" }, { 230, "Blackrock Depths" },
    { 229, "Blackrock Spire", "Lower" }, { 229, "Blackrock Spire", "Upper" },
    { 429, "Dire Maul", "East" }, { 429, "Dire Maul", "West" }, { 429, "Dire Maul", "North" },
    { 289, "Scholomance" }, { 329, "Stratholme", "Living side" }, { 329, "Stratholme", "Undead side" },
    F("Blackmaw Hold"), F("Shaper's Terrace"),
  },
  pvp = { { 489, "Warsong Gulch" }, { 529, "Arathi Basin" }, { 30, "Alterac Valley" } },
}
local function placeName(id, english, wing)
  if not id then return L[english] end
  local ok, name = pcall(GetRealZoneText, id)
  if not (ok and type(name) == "string" and name ~= "") then name = english end
  return wing and (name .. " - " .. L[wing]) or name
end
-- the places offered for a kind (none for an outing or "other": the free text is used)
local function placeOptions(kind)
  local list = { { "", L["(none)"] } }
  for _, p in ipairs(PLACES[kind] or {}) do
    local n = placeName(p[1], p[2], p[3])
    -- the menu marks the Forever dungeons with a gold star; the place itself stays the plain name
    list[#list + 1] = { n, p.forever and (FOREVER_STAR .. " " .. n .. " |cffd4a017(Forever)|r") or n }
  end
  return list
end

-- Dates ---------------------------------------------------------------------------------------------------
local function weekday(t)
  local names = { strsplit(",", L["Sun,Mon,Tue,Wed,Thu,Fri,Sat"]) }
  return names[tonumber(date("%w", t)) + 1] or ""
end
function ns.FormatDay(t) return weekday(t) .. " " .. date("%d/%m", t) end
function ns.FormatTime(t) return date("%H:%M", t) end
local function dayStart(t)
  local d = date("*t", t)
  d.hour, d.min, d.sec = 0, 0, 0
  return time(d)
end
-- "today", "tomorrow", or the day
local function relDay(t)
  local diff = math.floor((dayStart(t) - dayStart(time())) / 86400 + 0.5)
  if diff == 0 then return L["Today"] elseif diff == 1 then return L["Tomorrow"] end
  return ns.FormatDay(t)
end
local function inTime(t)
  local d = t - now()
  if d <= 0 then return L["started"] end
  if d < 3600 then return string.format(L["in %d min"], math.ceil(d / 60)) end
  if d < 86400 then return string.format(L["in %d h"], math.floor(d / 3600)) end
  return string.format(L["in %d days"], math.floor(d / 86400))
end

local function nameLabel(name)
  local m = ns.byName[name]
  return m and ("|c" .. ns.ClassHex(m.classFile) .. name .. "|r") or ("|cffdddddd" .. (name or "?") .. "|r")
end

-- Data ------------------------------------------------------------------------------------------------------
-- me: my full roster name ("Daeler Backbi"), so two players sharing a first name stay apart
local joinBlock -- (below)
local function isMine(name) return ns.SameAuthor(ns.MyName(), name) end
local function canEdit(ev) return ev and (isMine(ev.by) or Sync.IsOfficer(ns.MyName())) end

local function signups(evId)
  local list = {}
  for _, r in ipairs(Sync.All("rsvp")) do
    -- old answers saved under a first name alone are ambiguous when two members share it
    if r.ev == evId and not (ns.sharedFirst and ns.sharedFirst[r.who or ""]) then list[#list + 1] = r end
  end
  table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
  return list
end

-- present (within the size), waiting list, maybe, absent; role counters of the present ones
local function sortSignups(ev)
  local res = { yes = {}, wait = {}, maybe = {}, no = {}, roles = { tank = 0, heal = 0, dps = 0 } }
  for _, r in ipairs(signups(ev.id)) do
    if r.st == "yes" then
      if ev.size and ev.size > 0 and #res.yes >= ev.size then
        res.wait[#res.wait + 1] = r
      else
        res.yes[#res.yes + 1] = r
        res.roles[r.role] = (res.roles[r.role] or 0) + 1
      end
    elseif r.st == "maybe" then res.maybe[#res.maybe + 1] = r
    elseif r.st == "no" then res.no[#res.no + 1] = r end
  end
  return res
end

local function myAnswer(evId) return Sync.Get("rsvp", evId .. "@" .. ns.MyName()) end

local function answer(ev, st)
  local old = myAnswer(ev.id)
  local _, cls = UnitClass("player")
  Sync.Put("rsvp", { id = ev.id .. "@" .. ns.MyName(), ev = ev.id, who = ns.MyName(), st = st, role = ns.MyRole(), cls = cls,
    lvl = UnitLevel("player"),
    -- the place in the waiting list is kept unless you were not "present" before
    at = (old and old.st == "yes" and st == "yes") and old.at or now() })
end

local function upcoming()
  local list, t = {}, now()
  for _, e in ipairs(Sync.All("events")) do
    if type(e.t) == "number" and e.t > t - 6 * 3600 then list[#list + 1] = e end
  end
  table.sort(list, function(a, b) return a.t < b.t end)
  return list
end

Sync.Register("events", {
  keep = 7 * 86400,
  expired = function(r, t) return type(r.t) == "number" and r.t < t - 3 * 86400 end,
  validate = function(rec, old)
    if not old then return ns.byName[rec.ed or rec.by] ~= nil end
    return ns.SameAuthor(rec.ed, old.by) or Sync.IsOfficer(rec.ed)
  end,
  changed = function(rec, old)
    if not old and not rec.del and not isMine(rec.by) and type(rec.t) == "number" and rec.t > now()
      and ns.NotifyOpt("events") and Sync.Started() then
      local k = KIND[rec.kind] or KIND.other
      ns.Notify({ icon = k[3], title = L["New event"],
        text = string.format("%s  ·  %s %s  ·  %s", rec.title or "", relDay(rec.t), ns.FormatTime(rec.t), nameLabel(rec.by)),
        buttons = { { L["View"], function() selected = rec.id; mode = "cal"; ns.OpenPage(PAGE) end, true } } })
    end
  end,
})
Sync.Register("rsvp", {
  keep = 7 * 86400,
  expired = function(r, t) return (r.at or 0) < t - 21 * 86400 end,
  validate = function(rec) return rec.ed == rec.who or Sync.IsOfficer(rec.ed) end,
})
Sync.Register("lfg", {
  keep = 86400,
  expired = function(r, t) return (r.exp or 0) < t - 3600 end,
  validate = function(rec, old) return (not old) or ns.SameAuthor(rec.ed, old.by) or Sync.IsOfficer(rec.ed) end,
  changed = function(rec, old)
    if not old and not rec.del and not isMine(rec.by) and (rec.exp or 0) > now() and ns.NotifyOpt("lfg")
      and Sync.Started() then
      ns.Notify({ icon = { "Interface\\Icons\\INV_Misc_GroupNeedMore", "Interface\\Icons\\INV_Misc_Note_06" },
        title = L["Group search"],
        text = string.format("%s: %s", nameLabel(rec.by), rec.what or ""),
        buttons = joinBlock(rec) and { { L["View"], function() mode = "lfg"; ns.OpenPage(PAGE) end, true } }
          or { { L["Join"], function() ns.LfgJoin(rec) end, true },
          { L["View"], function() mode = "lfg"; ns.OpenPage(PAGE) end } } })
    end
  end,
})

-- Group finder: join requests (whispered to the poster) --------------------------------------------------------
-- why I cannot ask to join (a short text), or nil when I can
joinBlock = function(rec)
  if rec.asked then return L["Request sent"] end
  if UnitLevel("player") < (rec.lvl or 1) then
    local t = string.format(L["level %d+"], rec.lvl or 1)
    return (t:gsub("^%l", string.upper))
  end
  local m = ns.byName[rec.by]
  if not (m and m.online) then return L["Offline"] end
end

function ns.LfgJoin(rec)
  if not rec or isMine(rec.by) or joinBlock(rec) then return end
  local _, cls = UnitClass("player")
  Net.Send("LJ", { id = rec.id, who = ns.MyName(), role = ns.MyRole(), cls = cls, lvl = UnitLevel("player") },
    "WHISPER", rec.by)
  rec.asked = true
  ns.Print(string.format(L["Request sent to %s."], rec.by))
  if page and page:IsVisible() then ns.RefreshEvents() end
end

Net.On("LJ", function(d, sender)
  if type(d) ~= "table" then return end
  local rec = Sync.Get("lfg", tostring(d.id))
  if not rec or not isMine(rec.by) then return end
  -- the full name sent along tells apart two players sharing a first name
  if type(d.who) == "string" and ns.byName[d.who] and ns.Short(d.who):match("^%S+") == sender then sender = d.who end
  requests[rec.id] = requests[rec.id] or {}
  for _, q in ipairs(requests[rec.id]) do if q.name == sender then return end end
  local role = ROLE[d.role] and d.role or "dps"
  table.insert(requests[rec.id], { name = sender, role = role, cls = d.cls, lvl = tonumber(d.lvl) })
  local m = ns.byName[sender]
  ns.Notify({ icon = ns.RoleIcon(role), title = L["Join request"],
    text = string.format(L["%s (%s, %s) wants to join: %s"], nameLabel(sender), ns.RoleName(role),
      tostring(d.lvl or "?"), rec.what or ""),
    sound = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, duration = 40,
    buttons = { { L["Invite"], function() if m then ns.GroupInvite(m) else InviteUnit(sender) end end, true },
      { L["Whisper"], function() ChatFrame_SendTell(sender) end } } })
  if page and page:IsVisible() then ns.RefreshEvents() end
end)

-- Reminders: the creator of an event (or an officer) alerts again the guildmates who have not
-- answered it yet. Sent to the guild; each one checks on their side whether they answered.
local REMIND_COOLDOWN = 60
local lastRemind = {} -- event id -> time of my last reminder

local function canRemind(ev)
  return ev and not ev.del and type(ev.t) == "number" and ev.t > now() - 3600
    and (isMine(ev.by) or Sync.IsOfficer(ns.MyName()))
end

local function remind(ev)
  if not canRemind(ev) then return end
  local left = REMIND_COOLDOWN - (GetTime() - (lastRemind[ev.id] or -1000))
  if left > 0 then
    ns.Print(string.format(L["Wait %d s before sending another reminder."], math.ceil(left)))
    return
  end
  lastRemind[ev.id] = GetTime()
  -- the event goes along: a guildmate who never received it still gets the alert
  Net.Send("ER", { id = ev.id, who = ns.MyName(), title = ev.title, t = ev.t, kind = ev.kind, by = ev.by }, "GUILD")
  local s = sortSignups(ev)
  ns.Print(string.format(L["Reminder sent for %s (%d answers so far)."], "|cffffd100" .. (ev.title or "") .. "|r",
    #s.yes + #s.wait + #s.maybe + #s.no))
end

Net.On("ER", function(d, sender)
  if type(d) ~= "table" then return end
  local ev = Sync.Get("events", tostring(d.id))
  if not ev then
    if type(d.by) ~= "string" or type(d.t) ~= "number" then return end
    ev = { id = tostring(d.id), title = type(d.title) == "string" and Net.Clean(d.title) or "", t = d.t,
      kind = d.kind, by = d.by }
  end
  if ev.del or isMine(ev.by) or myAnswer(ev.id) then return end
  if type(ev.t) ~= "number" or ev.t < now() - 3600 then return end
  -- the full name sent along tells apart two players sharing a first name
  local who = sender
  if type(d.who) == "string" and ns.byName[d.who] and ns.Short(d.who):match("^%S+") == sender then who = d.who end
  if not (ns.SameAuthor(who, ev.by) or who == ev.by or Sync.IsOfficer(who)) then return end
  local k = KIND[ev.kind] or KIND.other
  ns.Notify({ icon = k[3], title = L["Event reminder"],
    text = string.format(L["%s reminds you of %s  ·  %s %s. You have not answered yet."], nameLabel(who),
      "|cffffd100" .. (ev.title or "") .. "|r", relDay(ev.t), ns.FormatTime(ev.t)),
    sound = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, duration = 30,
    buttons = { { L["View"], function() selected = ev.id; mode = "cal"; ns.OpenPage(PAGE) end, true } } })
end)

-- Forms ----------------------------------------------------------------------------------------------------
local function dayOptions()
  local list, t = {}, time()
  for i = 0, 27 do
    local d = dayStart(t) + i * 86400 + 3 * 3600 -- (mid-day: daylight saving shifts stay inside the day)
    list[#list + 1] = { i, i == 0 and L["Today"] or i == 1 and L["Tomorrow"] or ns.FormatDay(d) }
  end
  return list
end
local function hourOptions()
  local list = {}
  for h = 0, 23 do list[#list + 1] = { h, string.format("%02d h", h) } end
  return list
end
local MINUTES = { { 0, "00" }, { 15, "15" }, { 30, "30" }, { 45, "45" } }
local SIZES = { { 0, "—" }, { 5, "5" }, { 10, "10" }, { 15, "15" }, { 20, "20" }, { 40, "40" } }

local function editEvent(ev)
  local kinds = {}
  for _, k in ipairs(KINDS) do kinds[#kinds + 1] = { k[1], L[k[2]] } end
  local t = ev and ev.t or (dayStart(time()) + 86400 + 20 * 3600 + 30 * 60)
  local d = date("*t", t)
  local dayIndex = math.max(0, math.floor((dayStart(t) - dayStart(time())) / 86400 + 0.5))
  local kind = ev and ev.kind or "raid"
  local preset, other = "", ev and ev.place or ""
  for _, p in ipairs(placeOptions(kind)) do if p[1] ~= "" and p[1] == other then preset, other = p[1], "" end end
  S.Form({
    title = ev and L["Edit the event"] or L["New event"], width = 500, accept = ev and L["Save"] or L["Create"],
    sub = L["Shared with the guildmates who have Guild Enhanced."],
    fields = {
      { kind = "section", key = "s1", label = L["Event"] },
      { key = "title", label = L["Title"], kind = "text", value = ev and ev.title, max = 60, required = true,
        placeholder = L["Molten Core, Friday raid..."] },
      { key = "kind", label = L["Type"], kind = "drop", value = kind, options = kinds, size = 0.5,
        onChange = function(v, f)
          -- the places follow the type
          kind = v
          local w = f.active.preset
          if w then w.value = ""; w:Refresh() end
        end },
      { key = "preset", label = L["Place"], kind = "drop", value = preset, size = 0.5,
        options = function() return placeOptions(kind) end },
      { key = "other", label = L["Or another place"], kind = "text", value = other, max = 40 },
      { kind = "section", key = "s2", label = L["When"] },
      { key = "now", label = L["Right now (no set time)"], kind = "check", value = false,
        onChange = function(on, f)
          -- now: the day and the time are not used
          for _, k in ipairs({ "day", "hour", "min" }) do
            local w = f.active[k]
            if w and w.SetEnabled then w:SetEnabled(not on) end
            if w then w:SetAlpha(on and 0.5 or 1) end
          end
        end },
      { key = "day", label = L["Day"], kind = "drop", value = dayIndex, options = dayOptions(), size = 1 / 3 },
      { key = "hour", label = L["Hour"], kind = "drop", value = d.hour, options = hourOptions(), size = 1 / 3 },
      { key = "min", label = L["Minutes"], kind = "drop", value = d.min - d.min % 15, options = MINUTES, size = 1 / 3 },
      { key = "size", label = L["Places"], kind = "drop", value = ev and ev.size or 0, options = SIZES,
        hint = L["Past this number, the next ones go to the waiting list."] },
      { key = "notes", label = L["Notes"], kind = "multi", value = ev and ev.notes, max = 200, height = 54 },
    },
    onAccept = function(v)
      local base = date("*t", dayStart(time()) + v.day * 86400 + 3 * 3600)
      base.hour, base.min, base.sec = v.hour, v.min, 0
      local when = v.now and now() or time(base)
      local rec = ev and CopyTable(ev) or { id = ns.MyName() .. "-" .. now() .. "-" .. math.random(99) }
      rec.title, rec.kind, rec.t, rec.size, rec.notes = v.title, v.kind, when, v.size, v.notes
      rec.place = v.other ~= "" and v.other or v.preset
      rec.del = nil
      Sync.Put("events", rec)
      selected = rec.id
      ns.RefreshEvents(true)
    end,
  })
end

local function postSearch()
  local function counts() local l = {}; for i = 0, 4 do l[#l + 1] = { i, tostring(i) } end; return l end
  S.Form({
    title = L["Looking for group"], width = 450, accept = L["Post"],
    fields = {
      { key = "what", label = L["For"], kind = "text", max = 70, required = true,
        placeholder = L["Scholomance, elite quests, Onyxia..."] },
      { key = "tank", label = L["Tanks needed"], kind = "drop", value = 0, options = counts() },
      { key = "heal", label = L["Healers needed"], kind = "drop", value = 0, options = counts() },
      { key = "dps", label = L["Damage needed"], kind = "drop", value = 1, options = counts() },
      { key = "lvl", label = L["Minimum level"], kind = "number", value = math.max(1, UnitLevel("player") - 5) },
      { key = "dur", label = L["Visible for"], kind = "drop", value = 60,
        options = { { 30, "30 min" }, { 60, "1 h" }, { 120, "2 h" } } },
    },
    onAccept = function(v)
      local rec = { id = ns.MyName() .. "-" .. now(), what = v.what, nt = v.tank, nh = v.heal, nd = v.dps,
        lvl = v.lvl or 1, exp = now() + v.dur * 60 }
      Sync.Put("lfg", rec)
      mode = "lfg"
      ns.RefreshEvents(true)
    end,
  })
end

-- Calendar list -----------------------------------------------------------------------------------------------
local function eventRow(i)
  if ui.rows[i] then return ui.rows[i] end
  local r = CreateFrame("Button", nil, ui.listContent)
  r:SetHeight(ROW_H - 4)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
  S.Rounded(r, 8, { 0.1, 0.07, 0.17, 0.9 }, { 0.05, 0.035, 0.09, 0.9 }, C.rule)
  r.sel = r:CreateTexture(nil, "BACKGROUND", nil, -6)
  r.sel:SetPoint("TOPLEFT", 1, -1); r.sel:SetPoint("BOTTOMRIGHT", -1, 1)
  S.Highlight(r.sel, 0.16)
  r.sel:SetAlpha(0)
  r.date = CreateFrame("Frame", nil, r)
  r.date:SetSize(40, 40)
  r.date:SetPoint("LEFT", 6, 0)
  S.Rounded(r.date, 6, C.pill1, C.pill2, C.ring)
  r.day = S.Text(r.date, 16, "gold")
  r.day:SetPoint("CENTER", 0, 5)
  r.wd = S.Text(r.date, 9, "dim")
  r.wd:SetPoint("BOTTOM", 0, 4)
  r.icon = S.Icon(r, 18)
  r.icon:SetPoint("TOPLEFT", r.date, "TOPRIGHT", 10, -1)
  r.title = S.Text(r, 13, "text")
  r.title:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.title:SetPoint("RIGHT", -60, 0)
  r.sub = S.Text(r, 11, "muted")
  r.sub:SetPoint("BOTTOMLEFT", r.date, "BOTTOMRIGHT", 10, 2)
  r.sub:SetPoint("RIGHT", -60, 0)
  r.count = S.Text(r, 12, "dim")
  r.count:SetPoint("TOPRIGHT", -10, -9)
  r.count:SetJustifyH("RIGHT")
  r.mine = S.Text(r, 10, "good")
  r.mine:SetPoint("BOTTOMRIGHT", -10, 8)
  r.mine:SetJustifyH("RIGHT")
  r:SetScript("OnEnter", function(self) if selected ~= self.ev.id then self:SetBorderColor(color(C.ring)) end end)
  r:SetScript("OnLeave", function(self) if selected ~= self.ev.id then self:SetBorderColor(color(C.rule)) end end)
  r:SetScript("OnClick", function(self)
    selected = self.ev.id
    ns.RefreshEvents()
    S.SlideIn(ui.detail.inner, 10, 0, 0.22)
  end)
  ui.rows[i] = r
  return r
end

local ST_TEXT = { yes = "|cff1eff00%s|r", maybe = "|cffff8000%s|r", no = "|cffff2020%s|r" }
local ST_LABEL = { yes = "Present", maybe = "Maybe", no = "Absent" }

-- Detail card -------------------------------------------------------------------------------------------------
local function personRow(i)
  if ui.people[i] then return ui.people[i] end
  local r = CreateFrame("Button", nil, ui.peopleContent)
  r:SetHeight(20)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  S.RowHighlight(r)
  r.role = r:CreateTexture(nil, "ARTWORK")
  r.role:SetSize(14, 14)
  r.role:SetPoint("LEFT", 4, 0)
  r.role:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = S.Text(r, 12, "text")
  r.name:SetPoint("LEFT", r.role, "RIGHT", 6, 0)
  r.right = S.Text(r, 10, "muted")
  r.right:SetPoint("RIGHT", -4, 0)
  r.header = S.Text(r, 11, "gold")
  r.header:SetPoint("LEFT", 2, -2)
  r:SetScript("OnClick", function(self, button)
    local m = self.who and ns.byName[self.who]
    if not m then return end
    if button == "RightButton" then ns.MemberMenu(self, m) else ns.Whisper(m) end
  end)
  ui.people[i] = r
  return r
end

local function fillPeople(groups)
  local i, y = 0, 0
  for _, g in ipairs(groups) do
    if #g.list > 0 then
      i = i + 1
      local h = personRow(i)
      h.who = nil
      h.header:SetText(g.title .. "  |cff999999" .. #g.list .. "|r")
      h.header:Show(); h.role:Hide(); h.name:SetText(""); h.right:SetText("")
      h:SetPoint("TOPLEFT", 0, -y); h:SetPoint("TOPRIGHT", 0, -y)
      h:Show()
      y = y + 22
      for _, r in ipairs(g.list) do
        i = i + 1
        local p = personRow(i)
        p.who = r.who
        p.header:Hide()
        p.role:Show()
        ns.SetRoleIcon(p.role, r.role)
        local m = ns.byName[r.who]
        p.name:SetText((m and m.online and "" or "|cff999999") .. (r.who or "?") .. "|r")
        p.name:SetTextColor(ns.ClassColor(m and m.classFile or r.cls))
        p.right:SetText(ns.RoleName(r.role) .. (r.lvl and ("  ·  " .. r.lvl) or ""))
        p:SetPoint("TOPLEFT", 0, -y); p:SetPoint("TOPRIGHT", 0, -y)
        p:Show()
        y = y + 20
      end
      y = y + 6
    end
  end
  for k = i + 1, #ui.people do ui.people[k]:Hide() end
  ui.peopleContent:SetHeight(math.max(1, y))
end

local function refreshDetail(ev)
  local d = ui.detail
  d.inner:SetShown(ev ~= nil)
  d.empty:SetShown(ev == nil)
  if not ev then return end
  local k = KIND[ev.kind] or KIND.other
  d.icon.tex:SetTexture(S.PickIcon(k[3]))
  d.title:SetText(ev.title or "")
  d.when:SetText(string.format("%s  ·  %s  ·  |cff999999%s|r", relDay(ev.t), ns.FormatTime(ev.t), inTime(ev.t)))
  d.place:SetText((ev.place and ev.place ~= "" and (ev.place .. "  ·  ") or "") .. L[k[2]] .. "  ·  "
    .. string.format(L["by %s"], nameLabel(ev.by)))
  d.notes:SetText(ev.notes or "")
  local s = sortSignups(ev)
  local size = (ev.size and ev.size > 0) and ev.size or nil
  d.count:SetText(size and string.format(L["%d / %d present"], #s.yes, size) or string.format(L["%d present"], #s.yes))
  d.bar:SetShown(size ~= nil)
  if size then d.bar:SetValue(math.min(1, #s.yes / size)) end
  for _, c in ipairs(d.roleCounts) do c.text:SetText(s.roles[c.role] or 0) end
  -- my answer
  local mine = myAnswer(ev.id)
  for _, b in ipairs(d.answers) do
    local on = mine and mine.st == b.st
    b:SetBorderColor(color(on and C.gold or C.trim))
    b.text:SetTextColor(color(on and C.gold or C.text))
  end
  local waiting
  for pos, r in ipairs(s.wait) do if isMine(r.who) then waiting = pos end end
  d.myState:SetText(waiting and string.format(L["Waiting list: position %d"], waiting) or "")
  d.role:Refresh()
  d.edit:SetShown(canEdit(ev))
  d.delete:SetShown(canEdit(ev))
  d.inviteAll:SetShown(isMine(ev.by) or Sync.IsOfficer(ns.MyName()))
  d.remind:SetShown(canRemind(ev))
  fillPeople({
    { title = L["Present"], list = s.yes }, { title = L["Waiting list"], list = s.wait },
    { title = L["Maybe"], list = s.maybe }, { title = L["Absent"], list = s.no },
  })
end

-- invites the online "present" ones (a raid group when more than 5)
local function inviteAll(ev)
  local s = sortSignups(ev)
  local n = 0
  for _, r in ipairs(s.yes) do
    local m = ns.byName[r.who]
    if m and m.online and not ns.IsMe(m) and not UnitInParty(m.name) and not UnitInRaid(m.name) then
      if n >= 4 and not IsInRaid() and ConvertToRaid then ConvertToRaid() end
      ns.GroupInvite(m)
      n = n + 1
    end
  end
  ns.Print(string.format(L["%d invitations sent."], n))
end

-- Group finder list --------------------------------------------------------------------------------------------
local function lfgRow(i)
  if ui.lfgRows[i] then return ui.lfgRows[i] end
  local r = CreateFrame("Frame", nil, ui.lfgContent)
  r:SetHeight(LFG_H - 4)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * LFG_H)
  r:SetPoint("TOPRIGHT", 0, -(i - 1) * LFG_H)
  S.Rounded(r, 8, { 0.1, 0.07, 0.17, 0.9 }, { 0.05, 0.035, 0.09, 0.9 }, C.rule)
  r.classIcon = r:CreateTexture(nil, "ARTWORK")
  r.classIcon:SetSize(28, 28)
  r.classIcon:SetPoint("LEFT", 10, 0)
  r.what = S.Text(r, 13, "text")
  r.what:SetPoint("TOPLEFT", r.classIcon, "TOPRIGHT", 10, 1)
  r.what:SetPoint("RIGHT", -330, 0)
  r.who = S.Text(r, 11, "muted")
  r.who:SetPoint("BOTTOMLEFT", r.classIcon, "BOTTOMRIGHT", 10, -1)
  r.who:SetPoint("RIGHT", -330, 0)
  r.needs = {}
  for k, role in ipairs({ "tank", "heal", "dps" }) do
    local n = CreateFrame("Frame", nil, r)
    n:SetSize(44, 22)
    n:SetPoint("RIGHT", -310 + (k - 1) * 48, 0)
    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetSize(18, 18)
    n.icon:SetPoint("LEFT")
    ns.SetRoleIcon(n.icon, role)
    n.text = S.Text(n, 13, "gold")
    n.text:SetPoint("LEFT", n.icon, "RIGHT", 5, 0)
    S.Tooltip(n, ns.RoleName(role))
    r.needs[role] = n
  end
  r.left = S.Text(r, 11, "muted")
  r.left:SetPoint("RIGHT", -132, 0)
  r.left:SetJustifyH("RIGHT")
  r.btn = S.Button(r, "", 110, 24)
  r.btn:SetPoint("RIGHT", -10, 0)
  r.cancel = S.Button(r, L["Cancel"], 80, 24)
  r.cancel:SetPoint("RIGHT", r.btn, "LEFT", -6, 0)
  ui.lfgRows[i] = r
  return r
end

local function refreshLfg(animate)
  local list, t = {}, now()
  for _, rec in ipairs(Sync.All("lfg")) do if (rec.exp or 0) > t then list[#list + 1] = rec end end
  table.sort(list, function(a, b) return (a.v or 0) > (b.v or 0) end)
  for i, rec in ipairs(list) do
    local r = lfgRow(i)
    local m = ns.byName[rec.by]
    ns.SetClassIcon(r.classIcon, m and m.classFile)
    r.what:SetText(rec.what or "")
    r.who:SetText(nameLabel(rec.by) .. "  ·  " .. string.format(L["level %d+"], rec.lvl or 1))
    r.needs.tank.text:SetText(rec.nt or 0)
    r.needs.heal.text:SetText(rec.nh or 0)
    r.needs.dps.text:SetText(rec.nd or 0)
    r.left:SetText(string.format(L["%d min left"], math.max(0, math.ceil((rec.exp - t) / 60))))
    local mine = isMine(rec.by)
    r.cancel:SetShown(mine)
    r.left:ClearAllPoints()
    r.left:SetPoint("RIGHT", mine and -218 or -132, 0)
    for k, role in ipairs({ "tank", "heal", "dps" }) do
      r.needs[role]:ClearAllPoints()
      r.needs[role]:SetPoint("RIGHT", (mine and -396 or -310) + (k - 1) * 48, 0)
    end
    r.what:SetPoint("RIGHT", mine and -416 or -330, 0)
    r.who:SetPoint("RIGHT", mine and -416 or -330, 0)
    if mine then
      r.cancel:SetScript("OnClick", function()
        Sync.Delete("lfg", rec.id)
        requests[rec.id] = nil
        ns.RefreshEvents()
      end)
      local q = requests[rec.id] or {}
      r.btn:SetText(string.format(L["Requests (%d)"], #q))
      r.btn:SetEnabled(#q > 0)
      r.btn:SetScript("OnClick", function(self)
        local items = { { text = rec.what, title = true } }
        for _, p in ipairs(q) do
          local pm = ns.byName[p.name]
          items[#items + 1] = { text = string.format("%s  ·  %s  ·  %s", nameLabel(p.name), ns.RoleName(p.role),
            tostring(p.lvl or "?")), func = function() if pm then ns.GroupInvite(pm) else InviteUnit(p.name) end end }
        end
        if #q > 0 then items[#items + 1] = { separator = true } end
        items[#items + 1] = { text = L["Close the search"], color = C.bad, func = function()
          Sync.Delete("lfg", rec.id)
          requests[rec.id] = nil
          ns.RefreshEvents()
        end }
        S.OpenMenu(self, items, { width = 240 })
      end)
    else
      -- the button says why it cannot be used (same rules as the notification)
      local why = joinBlock(rec)
      r.btn:SetText(why or L["Join"])
      r.btn:SetEnabled(why == nil)
      r.btn:SetScript("OnClick", function() ns.LfgJoin(rec) end)
    end
    r:Show()
    if animate and i <= 10 then S.SlideIn(r, 0, -8, 0.25, i * 0.03) end
  end
  for i = #list + 1, #ui.lfgRows do ui.lfgRows[i]:Hide() end
  ui.lfgContent:SetHeight(math.max(1, #list * LFG_H))
  ui.lfgEmpty:SetShown(#list == 0)
  return #list
end

-- Refresh --------------------------------------------------------------------------------------------------------
function ns.RefreshEvents(animate)
  if not page then return end
  for _, p in ipairs(ui.pills) do p:SetActive(p.key == mode) end
  ui.cal:SetShown(mode == "cal")
  ui.lfg:SetShown(mode == "lfg")
  ui.new:SetText(mode == "cal" and L["New event"] or L["Post a search"])
  ui.myRole:Refresh()
  local nLfg = refreshLfg(animate and mode == "lfg")
  ui.pills[2]:SetLabel(L["Group finder"] .. (nLfg > 0 and ("  |cffffd100" .. nLfg .. "|r") or ""))
  ui.pills[1]:SetPoint("TOPLEFT", 0, 0)
  ui.pills[2]:SetPoint("TOPLEFT", ui.pills[1]:GetWidth() + 6, 0)
  if mode ~= "cal" then return end
  local list = upcoming()
  local found
  for i, ev in ipairs(list) do
    local r = eventRow(i)
    r.ev = ev
    if ev.id == selected then found = ev end
    local k = KIND[ev.kind] or KIND.other
    r.icon.tex:SetTexture(S.PickIcon(k[3]))
    r.day:SetText(date("%d", ev.t))
    r.wd:SetText(weekday(ev.t))
    r.title:SetText(ev.title or "")
    r.sub:SetText(ns.FormatTime(ev.t) .. ((ev.place and ev.place ~= "") and ("  ·  " .. ev.place) or ""))
    local s = sortSignups(ev)
    r.count:SetText((ev.size and ev.size > 0) and (#s.yes .. "/" .. ev.size) or tostring(#s.yes))
    local mine = myAnswer(ev.id)
    r.mine:SetText(mine and ST_TEXT[mine.st]:format(L[ST_LABEL[mine.st]]) or "")
    r:SetAlpha(ev.t < now() and 0.55 or 1)
    r:Show()
    if animate and i <= 9 then S.SlideIn(r, -10, 0, 0.25, i * 0.03) end
  end
  for i = #list + 1, #ui.rows do ui.rows[i]:Hide() end
  ui.listContent:SetHeight(math.max(1, #list * ROW_H))
  ui.calEmpty:SetShown(#list == 0)
  if not found and list[1] then found = list[1]; selected = found.id end
  for _, r in ipairs(ui.rows) do
    if r:IsShown() then
      local on = r.ev.id == selected
      r:SetBorderColor(color(on and C.gold or C.rule))
      r.sel:SetAlpha(on and 1 or 0)
    end
  end
  refreshDetail(found)
end

-- Build ------------------------------------------------------------------------------------------------------------
local function build(p)
  page = p
  ui.pills = {}
  local x = 0
  for i, spec in ipairs({ { "cal", L["Calendar"], { "Interface\\Icons\\INV_Misc_PocketWatch_01", "Interface\\Icons\\INV_Misc_Note_01" } },
      { "lfg", L["Group finder"], { "Interface\\Icons\\INV_Misc_GroupNeedMore", "Interface\\Icons\\INV_Misc_GroupLooking", "Interface\\Icons\\Ability_Warrior_BattleShout" } } }) do
    local pill = S.ModeTab(p, spec[2], spec[3], function()
      mode = spec[1]
      ns.RefreshEvents(true)
    end)
    pill.key = spec[1]
    pill:SetPoint("TOPLEFT", x, 0)
    x = x + pill:GetWidth() + 6
    ui.pills[i] = pill
  end
  ui.new = S.Button(p, "", 150, 22, function() if mode == "cal" then editEvent() else postSearch() end end, "primary")
  ui.new:SetPoint("TOPRIGHT", 0, -4)
  -- my role (used for the answers and the join requests)
  -- the three roles side by side, an icon and a check box each (like the game's group finder):
  -- the checked one is my role
  local function setRole(v)
    ns.db.myRole = v
    -- the answers already given follow the new role
    for _, r in ipairs(Sync.All("rsvp")) do
      if isMine(r.who) and r.role ~= v then
        local copy = CopyTable(r); copy.role = v
        Sync.Put("rsvp", copy)
      end
    end
    ns.RefreshEvents()
  end
  -- the game's own role art (its group finder): the round icons with the copper ring on their
  -- colored glow, the check box at the bottom left
  local ROLE_W, ROLE_SIZE = 50, 36
  ui.myRole = CreateFrame("Frame", nil, p)
  ui.myRole:SetSize(#ROLES * ROLE_W, ROLE_SIZE)
  ui.myRole:SetPoint("RIGHT", ui.new, "LEFT", -14, -6)
  ui.myRole.buttons = {}
  for k, r in ipairs(ROLES) do
    local b = CreateFrame("Button", nil, ui.myRole)
    b:SetSize(ROLE_SIZE, ROLE_SIZE)
    b:SetPoint("LEFT", (k - 1) * ROLE_W, 0)
    local gr = GAME_ROLE[r[1]]
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetPoint("CENTER")
    b.glow:SetSize(ROLE_SIZE * 1.25, ROLE_SIZE * 1.25)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    ns.SetRoleIcon(b.icon, r[1])
    if GetBackgroundTexCoordsForRole then
      b.glow:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLEBACKGROUNDS")
      b.glow:SetTexCoord(GetBackgroundTexCoordsForRole(gr))
      b.glow:SetAlpha(0.6)
    else
      b.glow:Hide()
    end
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b.check = S.Check(b, nil, 12)
    b.check:SetPoint("BOTTOMLEFT", -6, -6)
    local function pick() setRole(r[1]) end
    b:SetScript("OnClick", pick)
    b.check:SetScript("OnClick", pick)
    for _, f in ipairs({ b, b.check }) do
      f:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L[r[2]])
        GameTooltip:Show()
      end)
      f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    b.role = r[1]
    ui.myRole.buttons[k] = b
  end
  function ui.myRole:Refresh()
    local mine = ns.MyRole()
    for _, b in ipairs(self.buttons) do
      local on = b.role == mine
      b.check:SetChecked(on)
    end
  end
  ui.myRole:Refresh()
  local roleLabel = S.Text(p, 11, "muted")
  roleLabel:SetPoint("RIGHT", ui.myRole, "LEFT", -8, 0)
  roleLabel:SetText(L["My role"])

  -- calendar ------------------------------------------------------------------
  local cal = CreateFrame("Frame", nil, p)
  cal:SetPoint("TOPLEFT", 0, -40)
  cal:SetPoint("BOTTOMRIGHT")
  ui.cal = cal
  local listBox = CreateFrame("Frame", nil, cal)
  listBox:SetPoint("TOPLEFT")
  listBox:SetPoint("BOTTOMLEFT")
  listBox:SetWidth(LIST_W)
  local sf, content = S.Scroll(listBox)
  sf:SetPoint("TOPLEFT")
  sf:SetPoint("BOTTOMRIGHT", -12, 0)
  content:SetWidth(LIST_W - 14)
  ui.listContent = content
  ui.calEmpty = S.Text(listBox, 12, "muted")
  ui.calEmpty:SetPoint("TOPLEFT", 10, -20)
  ui.calEmpty:SetPoint("TOPRIGHT", -20, -20)
  ui.calEmpty:SetWordWrap(true)
  ui.calEmpty:SetJustifyH("CENTER")
  ui.calEmpty:SetText(L["No event planned. Create the first one!"])

  local card = CreateFrame("Frame", nil, cal)
  card:SetPoint("TOPLEFT", LIST_W + 12, 0)
  card:SetPoint("BOTTOMRIGHT")
  S.Card(card, 10)
  S.EdgeGlow(card, 24, 0.1)
  local d = { roleCounts = {}, answers = {} }
  ui.detail = d
  d.empty = S.Text(card, 13, "muted")
  d.empty:SetPoint("CENTER")
  d.empty:SetText(L["Pick an event on the left."])
  local inner = CreateFrame("Frame", nil, card)
  inner:SetPoint("TOPLEFT", 16, -14)
  inner:SetPoint("BOTTOMRIGHT", -16, 14)
  d.inner = inner
  d.icon = S.Icon(inner, 40)
  d.icon:SetPoint("TOPLEFT")
  d.title = S.Text(inner, 17, "gold")
  d.title:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 12, -1)
  d.title:SetPoint("RIGHT", -180, 0)
  d.when = S.Text(inner, 12, "text")
  d.when:SetPoint("BOTTOMLEFT", d.icon, "BOTTOMRIGHT", 12, 1)
  d.place = S.Text(inner, 11, "dim")
  d.place:SetPoint("TOPLEFT", d.icon, "BOTTOMLEFT", 0, -8)
  d.place:SetPoint("RIGHT")
  d.delete = S.Button(inner, L["Delete"], 80, 22, function()
    local ev = Sync.Get("events", selected)
    if not ev then return end
    S.Dialog({ title = L["Delete"], text = string.format(L["Delete the event %s?"], "|cffffd100" .. (ev.title or "") .. "|r"),
      accept = L["Delete"], danger = true, onAccept = function() Sync.Delete("events", ev.id); ns.RefreshEvents() end })
  end, "danger")
  d.delete:SetPoint("TOPRIGHT")
  d.edit = S.Button(inner, L["Edit"], 80, 22, function() editEvent(Sync.Get("events", selected)) end)
  d.edit:SetPoint("RIGHT", d.delete, "LEFT", -6, 0)
  d.notes = S.Text(inner, 11, "muted")
  d.notes:SetPoint("TOPLEFT", d.place, "BOTTOMLEFT", 0, -6)
  d.notes:SetPoint("RIGHT")
  d.notes:SetWordWrap(true)
  d.notes:SetMaxLines(3)

  -- answer buttons
  local ans = CreateFrame("Frame", nil, inner)
  ans:SetPoint("TOPLEFT", 0, -118)
  ans:SetPoint("TOPRIGHT", 0, -118)
  ans:SetHeight(28)
  for k, st in ipairs({ "yes", "maybe", "no" }) do
    local b = S.Button(ans, L[ST_LABEL[st]], 96, 26, function()
      local ev = Sync.Get("events", selected)
      if ev then answer(ev, st); ns.RefreshEvents() end
    end, st == "yes" and "primary" or nil)
    b.st = st
    b:SetPoint("LEFT", (k - 1) * 102, 0)
    d.answers[k] = b
  end
  d.myState = S.Text(ans, 11, "warn")
  d.myState:SetPoint("LEFT", 312, 0)
  d.myState:SetTextColor(color(C.warn))
  d.role = ui.myRole -- (refreshed with the page)

  -- counters
  local counters = CreateFrame("Frame", nil, inner)
  counters:SetPoint("TOPLEFT", ans, "BOTTOMLEFT", 0, -12)
  counters:SetPoint("TOPRIGHT", ans, "BOTTOMRIGHT", 0, -12)
  counters:SetHeight(24)
  for k, role in ipairs({ "tank", "heal", "dps" }) do
    local c = CreateFrame("Frame", nil, counters)
    c:SetSize(70, 24)
    c:SetPoint("LEFT", (k - 1) * 76, 0)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(20, 20)
    c.icon:SetPoint("LEFT")
    ns.SetRoleIcon(c.icon, role)
    c.text = S.Text(c, 15, "gold")
    c.text:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
    c.role = role
    S.Tooltip(c, ns.RoleName(role))
    d.roleCounts[k] = c
  end
  d.count = S.Text(counters, 12, "text")
  d.count:SetPoint("LEFT", 240, 0)
  d.bar = S.ProgressBar(counters, 8)
  d.bar:SetPoint("LEFT", d.count, "RIGHT", 12, 0)
  d.bar:SetPoint("RIGHT")

  -- people
  local box = CreateFrame("Frame", nil, inner)
  box:SetPoint("TOPLEFT", counters, "BOTTOMLEFT", 0, -10)
  box:SetPoint("BOTTOMRIGHT", 0, 32)
  S.Box(box, { 0.03, 0.02, 0.05, 0.6 }, C.rule)
  local psf, pcontent = S.Scroll(box)
  psf:SetPoint("TOPLEFT", 6, -6)
  psf:SetPoint("BOTTOMRIGHT", -14, 6)
  pcontent:SetWidth(ns.PAGE_W - LIST_W - 12 - 32 - 30)
  ui.peopleContent = pcontent
  d.inviteAll = S.Button(inner, L["Invite the present ones"], 190, 24, function()
    local ev = Sync.Get("events", selected)
    if ev then inviteAll(ev) end
  end)
  d.inviteAll:SetPoint("BOTTOMRIGHT")
  d.remind = S.Button(inner, L["Remind"], 110, 24, function() remind(Sync.Get("events", selected)) end)
  d.remind:SetPoint("RIGHT", d.inviteAll, "LEFT", -6, 0)
  S.Tooltip(d.remind, { L["Remind"], L["Alert again the guildmates who have not answered this event yet."] })
  local hint = S.Text(inner, 10, "muted")
  hint:SetPoint("BOTTOMLEFT", 0, 6)
  hint:SetPoint("RIGHT", d.remind, "LEFT", -10, 0)
  hint:SetText(L["Shared with the guildmates who have Guild Enhanced."])

  -- group finder -----------------------------------------------------------------
  local lfg = CreateFrame("Frame", nil, p)
  lfg:SetPoint("TOPLEFT", 0, -40)
  lfg:SetPoint("BOTTOMRIGHT")
  S.Card(lfg, 8)
  ui.lfg = lfg
  local lsf, lcontent = S.Scroll(lfg)
  lsf:SetPoint("TOPLEFT", 8, -8)
  lsf:SetPoint("BOTTOMRIGHT", -16, 30)
  lcontent:SetWidth(ns.PAGE_W - 26)
  ui.lfgContent = lcontent
  ui.lfgEmpty = S.Text(lfg, 13, "muted")
  ui.lfgEmpty:SetPoint("CENTER", 0, 10)
  ui.lfgEmpty:SetText(L["Nobody is looking for a group right now."])
  local lhint = S.Text(lfg, 10, "muted")
  lhint:SetPoint("BOTTOMLEFT", 12, 10)
  lhint:SetText(L["Join sends a request: the player gets a pop-up to invite you in one click."])
end

local function onShow() ns.RefreshEvents(true) end

ns.AddPage(PAGE, "Events", build, onShow, { "Interface\\Icons\\INV_Misc_Note_06", "Interface\\Icons\\INV_Scroll_08",
  "Interface\\Icons\\INV_Misc_Book_09" })

local function later()
  if page and page:IsVisible() then ns.RefreshEvents() end
end
ns.On("SYNC_EVENTS", later)
ns.On("SYNC_RSVP", later)
ns.On("SYNC_LFG", later)
ns.On("ROSTER", later)

-- reminders: 15 minutes before an event you answered present or maybe; badge with the count of
-- events of the next 24 h you have not answered
local reminded = {}
C_Timer.NewTicker(30, function()
  if not IsInGuild() or not ns.db then return end
  local t, open = now(), 0
  for _, ev in ipairs(upcoming()) do
    local mine = myAnswer(ev.id)
    if ev.t > t and ev.t - t < 86400 and not mine then open = open + 1 end
    if mine and mine.st ~= "no" and ev.t > t and ev.t - t <= 15 * 60 and not reminded[ev.id] then
      reminded[ev.id] = true
      if ns.NotifyOpt("events") then
        local k = KIND[ev.kind] or KIND.other
        ns.Notify({ icon = k[3], title = L["Soon"], text = string.format(L["%s starts %s."], ev.title or "", inTime(ev.t)),
          sound = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960,
          buttons = { { L["View"], function() selected = ev.id; mode = "cal"; ns.OpenPage(PAGE) end, true } } })
      end
    end
  end
  ns.SetTabBadge(PAGE, open > 0 and tostring(open) or "")
  if page and page:IsVisible() then
    -- the "in x min" texts move
    if mode == "lfg" then refreshLfg(false) end
  end
end)
