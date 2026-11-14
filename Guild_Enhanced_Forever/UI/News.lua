-- Guild Enhanced Forever: guild news page, like the game's own guild window: equipment looted, crafted or
-- bought by guildmates, and the other news the server keeps. Item icons, tooltips on hover,
-- Shift-click puts the item in the chat line.
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local PAGE = 9
local ROW_H = 34
local page, scroll, content, rows, pills, emptyText = nil, nil, nil, {}, {}, nil
local filter = "items"

-- news types (the game's constants when it has them)
local T = {
  LOOT = NEWS_ITEM_LOOTED or 0, CRAFT = NEWS_ITEM_CRAFTED or 1, BUY = NEWS_ITEM_PURCHASED or 2,
  GUILD_LEVEL = NEWS_GUILD_LEVEL or 3, GUILD_ACH = NEWS_GUILD_ACHIEVEMENT or 4,
  PLAYER_ACH = NEWS_PLAYER_ACHIEVEMENT or 5, BOSS = NEWS_DUNGEON_ENCOUNTER or 6,
  UPGRADE = NEWS_ITEM_UPGRADED or 9, LEGENDARY = NEWS_LEGENDARY_LOOTED or 10,
}
local ITEM_TYPES = { [T.LOOT] = true, [T.CRAFT] = true, [T.BUY] = true, [T.UPGRADE] = true, [T.LEGENDARY] = true }

local FILTERS = { { "items", "Equipment" }, { "all", "All" } }

local GetInfo = (C_GuildInfo and C_GuildInfo.GetGuildNewsInfo) or GetGuildNewsInfo
local Query = (C_GuildInfo and C_GuildInfo.QueryGuildNews) or QueryGuildNews
local ItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

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
      GameTooltip:AddLine(L["Shift-click: link in chat"], 0.64, 0.6, 0.72)
      GameTooltip:Show()
    end
  end)
  r:HookScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self)
    if self.link and IsModifiedClick("CHATLINK") then
      if ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
    end
  end)
  rows[i] = r
  return r
end

local function refresh(animate)
  if not page then return end
  local n = 0
  missingIcon = false
  local total = ns.HasGuildNews() and GetNumGuildNews() or 0
  for i = 1, total do
    local news = read(i)
    if news and not news.header and (filter == "all" or ITEM_TYPES[news.kind]) then
      n = n + 1
      local r = row(n)
      local isItem = ITEM_TYPES[news.kind] and news.what and news.what:find("|H", 1, true)
      r.link = isItem and news.what or nil
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
      r:Show()
      if animate and n <= 16 then
        r:SetAlpha(0)
        S.Tween(r, { dur = 0.25, delay = (n - 1) * 0.02, from = 0, to = 1, set = function(v) r:SetAlpha(v) end })
      else
        r:SetAlpha(1)
      end
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math.max(1, n * ROW_H))
  emptyText:SetText(ns.HasGuildNews() and L["No news."] or L["Guild news is not available in this version of the game."])
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
