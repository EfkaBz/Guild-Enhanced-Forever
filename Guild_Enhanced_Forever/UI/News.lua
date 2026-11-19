-- Guild Enhanced Forever: guild news page, like the game's own guild window: equipment looted, crafted or
-- bought by guildmates, and the other news the server keeps. Item icons, tooltips on hover,
-- Shift-click puts the item in the chat line.
-- Boss loot: the items guildmates receive in their bags from a dungeon or raid boss, seen by every
-- player who has the addon (their own loot and the group's loot messages) and shared with the guild.
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local PAGE = 9
local ROW_H = 34
local page, scroll, content, rows, pills, emptyText = nil, nil, nil, {}, {}, nil
local filter = "boss"
local Sync = ns.Sync
local now = GetServerTime or time

-- news types (the game's constants when it has them)
local T = {
  LOOT = NEWS_ITEM_LOOTED or 0, CRAFT = NEWS_ITEM_CRAFTED or 1, BUY = NEWS_ITEM_PURCHASED or 2,
  GUILD_LEVEL = NEWS_GUILD_LEVEL or 3, GUILD_ACH = NEWS_GUILD_ACHIEVEMENT or 4,
  PLAYER_ACH = NEWS_PLAYER_ACHIEVEMENT or 5, BOSS = NEWS_DUNGEON_ENCOUNTER or 6,
  UPGRADE = NEWS_ITEM_UPGRADED or 9, LEGENDARY = NEWS_LEGENDARY_LOOTED or 10,
}
local ITEM_TYPES = { [T.LOOT] = true, [T.CRAFT] = true, [T.BUY] = true, [T.UPGRADE] = true, [T.LEGENDARY] = true }

local FILTERS = { { "boss", "Boss loot" }, { "items", "Equipment" }, { "all", "All" } }

local GetInfo = (C_GuildInfo and C_GuildInfo.GetGuildNewsInfo) or GetGuildNewsInfo
local Query = (C_GuildInfo and C_GuildInfo.QueryGuildNews) or QueryGuildNews
local IconByID = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
-- an item's icon from its link (known without the item being cached)
local function ItemIcon(link)
  local icon = Instant and select(5, Instant(link))
  if icon then return icon end
  local id = tonumber(tostring(link):match("|Hitem:(%d+)"))
  return id and IconByID and IconByID(id) or nil
end

function ns.HasGuildNews() return GetInfo ~= nil and GetNumGuildNews ~= nil end

-- one news line, from either the table (newer clients) or the list of values (older ones)
local function read(i)
  local a, b, c, d, e, f, _, _, _, day, month = GetInfo(i)
  if type(a) == "table" then
    return { sticky = a.isSticky, header = a.isHeader, kind = a.newsType, who = a.whoText, what = a.whatText,
      day = a.day, month = a.month }
  end
  if c == nil then return nil end
  return { sticky = a, header = b, kind = c, who = d, what = e, id = f, day = day, month = month }
end

-- a name in its class color when the roster knows it
local function who(name)
  if not name or name == "" then return "?" end
  local m = ns.byName[name] or ns.byName[ns.Short(name)]
  if m then return "|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r" end
  return "|cffdddddd" .. ns.Short(name) .. "|r"
end

local function describe(n)
  local what = n.what or ""
  if n.kind == T.LOOT or n.kind == T.LEGENDARY or n.kind == T.UPGRADE then
    return string.format(L["%s obtained %s"], who(n.who), what)
  elseif n.kind == T.CRAFT then
    return string.format(L["%s crafted %s"], who(n.who), what)
  elseif n.kind == T.BUY then
    return string.format(L["%s bought %s"], who(n.who), what)
  elseif n.kind == T.PLAYER_ACH then
    return string.format(L["%s earned %s"], who(n.who), "|cffffd100" .. what .. "|r")
  elseif n.kind == T.GUILD_ACH then
    return string.format(L["The guild earned %s"], "|cffffd100" .. what .. "|r")
  elseif n.kind == T.BOSS then
    return string.format(L["The guild defeated %s"], "|cffff8a6b" .. what .. "|r")
  end
  return (n.who and n.who ~= "" and (who(n.who) .. " ") or "") .. what
end

-- day and month come from 0
local function when(n)
  if not n.day or not n.month then return "" end
  local d, m = n.day + 1, n.month + 1
  local now = date("*t")
  if d == now.day and m == now.month then return L["Today"] end
  return string.format("%02d/%02d", d, m)
end

local missingIcon = false

local function row(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, content)
  r:SetHeight(ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
  r:RegisterForClicks("LeftButtonUp")
  local stripe = r:CreateTexture(nil, "BACKGROUND", nil, -2)
  stripe:SetAllPoints()
  stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
  S.RowHighlight(r)
  r.icon = S.Icon(r, 26)
  r.icon:SetPoint("LEFT", 8, 0)
  r.text = S.Text(r, 12, "text")
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
  r.text:SetPoint("RIGHT", -90, 0)
  r.time = S.Text(r, 11, "muted")
  r.time:SetPoint("RIGHT", -10, 0)
  r.time:SetJustifyH("RIGHT")
  r:HookScript("OnEnter", function(self)
    if self.link then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self.link)
      GameTooltip:AddLine(" ")
      if self.boss then GameTooltip:AddLine(string.format(L["Boss: %s"], self.boss), 1, 0.54, 0.42) end
      GameTooltip:AddLine(L["Shift-click: link in chat"], 0.64, 0.6, 0.72)
      GameTooltip:Show()
    end
  end)
  r:HookScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self)
    if not self.link then return end
    if IsModifiedClick("CHATLINK") then
      if ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
    elseif IsModifiedClick() and HandleModifiedItemClick and HandleModifiedItemClick(self.link) then
      return
    elseif ItemRefTooltip then
      -- a plain click opens the item like a link clicked in the chat
      ShowUIPanel(ItemRefTooltip)
      if not ItemRefTooltip:IsShown() then ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
      ItemRefTooltip:SetHyperlink(self.link)
    end
  end)
  rows[i] = r
  return r
end

local bossLoot -- defined below (Boss loot)

local function fade(r, n, animate)
  r:Show()
  if animate and n <= 16 then
    r:SetAlpha(0)
    S.Tween(r, { dur = 0.25, delay = (n - 1) * 0.02, from = 0, to = 1, set = function(v) r:SetAlpha(v) end })
  else
    r:SetAlpha(1)
  end
end

local function lootWhen(t)
  local d, today = date("*t", t), date("*t")
  if d.day == today.day and d.month == today.month and d.year == today.year then
    return L["Today"] .. " " .. date("%H:%M", t)
  end
  return date("%d/%m %H:%M", t)
end

local function refresh(animate)
  if not page then return end
  local n = 0
  missingIcon = false
  if filter == "boss" or filter == "all" then
    for _, rec in ipairs(bossLoot()) do
      n = n + 1
      local r = row(n)
      r.link, r.boss = rec.link, rec.boss
      local icon = ItemIcon and ItemIcon(rec.link)
      if not icon then missingIcon = true end
      r.icon.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      r.text:SetText(string.format(L["%s obtained %s"], who(rec.who), rec.link))
      r.time:SetText(lootWhen(rec.t))
      fade(r, n, animate)
    end
  end
  local total = (filter ~= "boss" and ns.HasGuildNews()) and GetNumGuildNews() or 0
  for i = 1, total do
    local news = read(i)
    if news and not news.header and (filter == "all" or ITEM_TYPES[news.kind]) then
      n = n + 1
      local r = row(n)
      local isItem = ITEM_TYPES[news.kind] and news.what and news.what:find("|H", 1, true)
      r.link, r.boss = isItem and news.what or nil, nil
      local icon
      if r.link then
        icon = ItemIcon and ItemIcon(r.link)
        if not icon then missingIcon = true end
      elseif news.kind == T.BOSS then
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01"
      elseif news.kind == T.PLAYER_ACH or news.kind == T.GUILD_ACH or news.kind == T.GUILD_LEVEL then
        icon = "Interface\\Icons\\INV_Misc_Trophy_01"
      end
      r.icon.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      r.text:SetText(describe(news))
      r.time:SetText(when(news))
      fade(r, n, animate)
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math.max(1, n * ROW_H))
  if filter == "boss" then
    emptyText:SetText(L["No boss loot yet."])
  else
    emptyText:SetText(ns.HasGuildNews() and L["No news."] or L["Guild news is not available in this version of the game."])
  end
  emptyText:SetShown(n == 0)
  page.count:SetText(string.format(L["%d news"], n))
end

local function build(p)
  page = p
  local x = 0
  for i, f in ipairs(FILTERS) do
    local pill = S.Pill(p, L[f[2]], function()
      filter = f[1]
      for _, q in ipairs(pills) do q:SetActive(q.key == filter) end
      scroll.bar:SetValue(0)
      refresh(true)
    end)
    pill.key = f[1]
    pill:SetPoint("TOPLEFT", x, 0)
    x = x + pill:GetWidth() + 6
    pills[i] = pill
    pill:SetActive(f[1] == filter)
  end

  local refreshBtn = S.Button(p, L["Refresh"], 100, 22, function() if Query then Query() end end)
  refreshBtn:SetPoint("TOPRIGHT", 0, 0)
  p.count = S.Text(p, 11, "muted")
  p.count:SetPoint("RIGHT", refreshBtn, "LEFT", -12, 0)

  local card = CreateFrame("Frame", nil, p)
  card:SetPoint("TOPLEFT", 0, -32)
  card:SetPoint("BOTTOMRIGHT", 0, 0)
  S.Card(card, 8)
  scroll, content = S.Scroll(card)
  scroll:SetPoint("TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -14, 6)
  content:SetWidth(ns.PAGE_W - 20)
  emptyText = S.Text(card, 13, "muted")
  emptyText:SetPoint("CENTER")
end

local function onShow()
  if Query then Query() end -- the answer comes with GUILD_NEWS_UPDATE
  refresh(true)
end

ns.AddPage(PAGE, "News", build, onShow, { "Interface\\Icons\\INV_Box_02", "Interface\\Icons\\INV_Misc_Bag_10",
  "Interface\\Icons\\INV_Chest_Plate16", "Interface\\Icons\\INV_Misc_Coin_02" })

-- Events --------------------------------------------------------------------------------------------
local pending
local function later()
  if pending then return end
  pending = true
  C_Timer.After(0.2, function()
    pending = nil
    if page and page:IsVisible() then refresh(false) end
  end)
end

local ev = CreateFrame("Frame")
-- an event this client would not know must not break the file
pcall(ev.RegisterEvent, ev, "GUILD_NEWS_UPDATE")
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
ev:SetScript("OnEvent", function(_, event)
  if event == "GET_ITEM_INFO_RECEIVED" and not missingIcon then return end
  later()
end)
ns.On("SYNC_BOSSLOOT", later)
ns.On("ROSTER", later)

-- Boss loot -------------------------------------------------------------------------------------------
-- How an item is known to come from a boss:
--  * the boss: encounter units (boss1-5), creatures dying when the encounter ends, and units the game
--    shows as bosses (skull level / "worldboss");
--  * its items: what the boss corpse holds (loot window), and the rolls opened right after the kill
--    while nothing else has died;
--  * the looter: "X receives loot: [item]" (the item is in his bags). Without having seen the
--    corpse: loot received right after the kill, nothing else dead since, uncommon or better.
local COLL = "bossloot"
local WINDOW = 300 -- seconds after a kill
local KEEP = 30 * 86400
local LINK = "|c[^|]+|Hitem:[^|]+|h%[[^%]]+%]|h|r"
local GetInfoItem = (C_Item and C_Item.GetItemInfo) or GetItemInfo

Sync.Register(COLL, {
  keep = KEEP,
  expired = function(r, t) return (r.t or 0) < t - KEEP end,
  validate = function(rec)
    return type(rec.link) == "string" and #rec.link < 400 and rec.link:match("^" .. LINK .. "$") ~= nil
      and type(rec.who) == "string" and type(rec.t) == "number"
      and ns.byName[rec.ed or ""] ~= nil and (ns.byName[rec.who] or ns.byName[ns.Short(rec.who)]) ~= nil
  end,
})

-- for fun: always at the bottom of the list (the game's release day), never sent
local LEGEND = { who = "Daeler Backbi", boss = "Baron Geddon", t = 1101168000 }
local LEGEND_LINK = "|cffff8000|Hitem:19019::::::::60:::::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"

function bossLoot()
  local list = {}
  for _, r in ipairs(Sync.All(COLL)) do
    if type(r.link) == "string" and type(r.t) == "number" then list[#list + 1] = r end
  end
  LEGEND.link = select(2, GetInfoItem(19019)) or LEGEND_LINK -- in the client's language once cached
  list[#list + 1] = LEGEND
  table.sort(list, function(a, b) return a.t > b.t end)
  return list
end

local function itemID(link) return link and tonumber(link:match("|Hitem:(%d+)")) end

-- rarity: from the game, or from the link's color while the item is not cached
local function quality(link)
  local q = select(3, GetInfoItem(link))
  if q then return q end
  local hex = (link:match("^|c(%x%x%x%x%x%x%x%x)") or ""):lower()
  for i = 0, 8 do
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[i]
    if c and c.hex and c.hex:lower():find(hex, 1, true) then return i end
  end
  return 2
end

local bossGUIDs = {} -- guid -> boss name
local seenBoss = {}  -- guid -> name: units the game shows as bosses
local fighting = {}  -- guid -> name: encounter units (boss1-5) of the current fight
local lastKill       -- { name, t }
local trashSince     -- a new fight started after the last kill (the combat log is protected here)
local bossItems = {} -- itemID -> { boss, t }

-- a GUID usable as a table key (secret values can't index a table)
local function safeGUID(g)
  if g == nil or (issecretvalue and issecretvalue(g)) then return nil end
  return g
end

local function inInstance()
  local inside, kind = IsInInstance()
  return inside and (kind == "party" or kind == "raid")
end

local function killed(name, guid)
  lastKill = { name = name, t = GetTime() }
  trashSince = false
  if guid then bossGUIDs[guid] = name end
end

local function watchUnit(unit)
  if not UnitExists(unit) or UnitIsPlayer(unit) or not inInstance() then return end
  local guid = safeGUID(UnitGUID(unit))
  if not guid then return end
  if UnitClassification(unit) == "worldboss" or UnitLevel(unit) == -1 then
    seenBoss[guid] = UnitName(unit)
  end
  -- a boss seen dead: its kill (bosses without encounter events)
  if seenBoss[guid] and UnitIsDead(unit) and not bossGUIDs[guid] then killed(seenBoss[guid], guid) end
end

local function addBossItem(link, boss)
  local id = itemID(link)
  if id and boss then bossItems[id] = { boss = boss, t = GetTime() } end
end

local function afterKill()
  return lastKill and GetTime() - lastKill.t < WINDOW and lastKill or nil
end

-- the loot window: items of a boss corpse
local function scanLoot()
  if not inInstance() or not GetNumLootItems then return end
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    if link then
      local boss
      if GetLootSourceInfo then
        local src = { GetLootSourceInfo(slot) }
        for i = 1, #src, 2 do
          local g = safeGUID(src[i])
          if g and (bossGUIDs[g] or seenBoss[g]) then boss = bossGUIDs[g] or seenBoss[g] end
        end
      elseif UnitExists("target") and UnitIsDead("target") then
        local g = safeGUID(UnitGUID("target"))
        boss = g and (bossGUIDs[g] or seenBoss[g])
      end
      addBossItem(link, boss)
    end
  end
end

-- the game's own loot sentences ("%s receives loot: %s.") as patterns, in the client's language
local function toPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  fmt = fmt:gsub("%%%d%$", "%%")
  fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  fmt = fmt:gsub("%%s", "(.+)")
  fmt = fmt:gsub("%%d", "%%d+")
  return "^" .. fmt .. "$"
end
local SELF, OTHERS = {}, {}
for _, k in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF" }) do
  local p = toPattern(_G[k]); if p then SELF[#SELF + 1] = p end
end
for _, k in ipairs({ "LOOT_ITEM_MULTIPLE", "LOOT_ITEM", "LOOT_ITEM_PUSHED_MULTIPLE", "LOOT_ITEM_PUSHED" }) do
  local p = toPattern(_G[k]); if p then OTHERS[#OTHERS + 1] = p end
end

-- who received what (nil when it is not a loot line)
local function parseLoot(text)
  for _, p in ipairs(SELF) do
    if text:match(p) then return ns.MyName(), text:match(LINK) end
  end
  for _, p in ipairs(OTHERS) do
    local a, b = text:match(p)
    if a and b then
      if a:find("|Hitem:", 1, true) then a, b = b, a end -- languages that name the item first
      return a, b:match(LINK)
    end
  end
end

local function record(name, link, boss)
  local m = ns.byName[name] or ns.byName[ns.Short(name)]
  if not m or not Sync.Started() then return end -- guildmates only
  local id, t = itemID(link), now()
  local key = m.name .. "|" .. id .. "|" .. math.floor(t / 1800)
  if Sync.Get(COLL, key) then return end
  -- the same item for the same player a moment ago (seen by another guildmate, other key)
  for _, r in ipairs(Sync.All(COLL)) do
    if r.who == m.name and itemID(r.link) == id and math.abs((r.t or 0) - t) < 1800 then return end
  end
  Sync.Put(COLL, { id = key, who = m.name, link = link, boss = boss, t = t })
end

local function onLoot(text)
  if type(text) ~= "string" or not inInstance() then return end
  local name, link = parseLoot(text)
  if not name or not link then return end
  local known = bossItems[itemID(link)]
  if known and GetTime() - known.t < 3600 then
    if quality(link) >= 1 then record(name, link, known.boss) end
    return
  end
  local k = afterKill()
  if k and not trashSince and quality(link) >= 2 then record(name, link, k.name) end
end

local lev = CreateFrame("Frame")
for _, e in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "PLAYER_TARGET_CHANGED",
  "UPDATE_MOUSEOVER_UNIT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "LOOT_OPENED", "LOOT_READY",
  "START_LOOT_ROLL", "CHAT_MSG_LOOT" }) do
  -- (no combat log: protected for addons on this client)
  if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(e) then
    pcall(lev.RegisterEvent, lev, e)
  end
end
lev:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_LOOT" then
    onLoot(...)
  elseif event == "ENCOUNTER_START" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
    if event == "ENCOUNTER_START" then wipe(fighting) end
    for i = 1, 5 do
      local u = "boss" .. i
      local g = UnitExists(u) and safeGUID(UnitGUID(u))
      if g then fighting[g] = UnitName(u) end
      watchUnit(u)
    end
  elseif event == "ENCOUNTER_END" then
    local _, name, _, _, success = ...
    if success ~= 1 and success ~= true then return end
    killed(name)
    for g in pairs(fighting) do bossGUIDs[g] = name end
    wipe(fighting)
    -- the boss in target, dead: its corpse
    if UnitExists("target") and not UnitIsPlayer("target") and UnitIsDead("target") then
      local g = safeGUID(UnitGUID("target"))
      if g then bossGUIDs[g] = name end
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- a new fight after the kill: what drops next may be trash
    if lastKill and GetTime() - lastKill.t > 3 then trashSince = true end
  elseif event == "PLAYER_REGEN_ENABLED" then
    watchUnit("target")
  elseif event == "PLAYER_TARGET_CHANGED" then
    watchUnit("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    watchUnit("mouseover")
  elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
    scanLoot()
  elseif event == "START_LOOT_ROLL" then
    local link = GetLootRollItemLink and GetLootRollItemLink((...))
    local k = afterKill()
    if link and k and not trashSince then addBossItem(link, k.name) end
  end
end)
