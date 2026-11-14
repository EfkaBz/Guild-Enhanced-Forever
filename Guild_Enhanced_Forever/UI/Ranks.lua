-- Guild Enhanced Forever: ranks page: rank list with member counts, and the members of the selected rank.
-- Rank names and permissions can't be read or changed by an addon in this client (GuildControlSetRank
-- is protected): the guild master edits them in the game's own guild window, one click away.
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local LIST_W, ROW_H, MEMBER_H = 300, 40, 24
local page, listRows, memberRows, members, membersTitle, none, note, editBtn = nil, {}, {}, nil, nil, nil, nil, nil
local selected = 1

-- members and online members of a rank (1-based)
local function counts(i)
  local n, on = 0, 0
  for _, m in ipairs(ns.members) do
    if m.rankIndex == i - 1 then
      n = n + 1
      if m.online then on = on + 1 end
    end
  end
  return n, on
end

-- the members of a rank: online first, then by name
local function rankMembers(i)
  local list = {}
  for _, m in ipairs(ns.members) do
    if m.rankIndex == i - 1 then list[#list + 1] = m end
  end
  table.sort(list, function(a, b)
    if a.online ~= b.online then return a.online end
    return a.short < b.short
  end)
  return list
end

local function memberRow(i)
  if memberRows[i] then return memberRows[i] end
  local r = CreateFrame("Button", nil, members.content)
  r:SetHeight(MEMBER_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * MEMBER_H)
  r:SetPoint("TOPRIGHT", 0, -(i - 1) * MEMBER_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local stripe = r:CreateTexture(nil, "BACKGROUND", nil, -2)
  stripe:SetAllPoints()
  stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
  S.RowHighlight(r)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 8, 0)
  r.name = S.Text(r, 12, "text")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.name:SetWidth(170)
  r.lvl = S.Text(r, 11, "dim")
  r.lvl:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
  r.lvl:SetWidth(30)
  r.zone = S.Text(r, 11, "muted")
  r.zone:SetPoint("LEFT", r.lvl, "RIGHT", 6, 0)
  r.zone:SetPoint("RIGHT", -100, 0)
  r.last = S.Text(r, 11, "muted")
  r.last:SetPoint("RIGHT", -10, 0)
  r.last:SetJustifyH("RIGHT")
  r:SetScript("OnClick", function(self, button)
    if not self.member then return end
    if button == "RightButton" then ns.MemberMenu(self, self.member) else ns.Whisper(self.member) end
  end)
  S.Tooltip(r, L["Click: whisper  ·  Right-click: actions"])
  memberRows[i] = r
  return r
end

local function showMembers(i, animate)
  local list = rankMembers(i)
  for k, m in ipairs(list) do
    local r = memberRow(k)
    r.member = m
    ns.SetClassIcon(r.icon, m.classFile)
    r.name:SetText(m.short)
    r.name:SetTextColor(ns.ClassColor(m.classFile))
    r.name:SetAlpha(m.online and 1 or 0.6)
    r.lvl:SetText(m.level)
    r.zone:SetText(m.zone)
    r.last:SetText(m.online and ("|cff1eff00" .. L["Online"] .. "|r") or ns.LastOnlineText(m))
    r:Show()
    if animate and k <= 16 then
      r:SetAlpha(0)
      S.Tween(r, { dur = 0.22, delay = (k - 1) * 0.015, from = 0, to = 1, set = function(v) r:SetAlpha(v) end })
    else
      r:SetAlpha(1)
    end
  end
  for k = #list + 1, #memberRows do memberRows[k]:Hide() end
  members.content:SetHeight(math.max(1, #list * MEMBER_H))
  none:SetShown(#list == 0)
  local n, on = counts(i)
  membersTitle.right:SetText(string.format(L["%d members  ·  %d online"], n, on))
end

local function selectRank(i, animate)
  selected = i
  for j, r in ipairs(listRows) do r.sel:SetAlpha(j == i and 1 or 0) end
  membersTitle.label:SetText((GuildControlGetRankName(i) or "") .. "  ·  " .. L["Members of this rank"])
  if animate then members.bar:SetValue(0) end
  showMembers(i, animate)
end

local function refresh(animate)
  if not page then return end
  local num = ns.NumRanks()
  for i = 1, math.max(num, #listRows) do
    local r = listRows[i]
    if i <= num then
      if not r then
        r = CreateFrame("Button", nil, page.list)
        r:SetHeight(ROW_H - 4)
        r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * ROW_H)
        S.RowHighlight(r)
        r.sel = CreateFrame("Frame", nil, r)
        r.sel:SetAllPoints()
        local w = r.sel:CreateTexture(nil, "BACKGROUND")
        w:SetAllPoints()
        S.Highlight(w, 0.2)
        local b = r.sel:CreateTexture(nil, "ARTWORK")
        b:SetPoint("TOPLEFT"); b:SetPoint("BOTTOMLEFT"); b:SetWidth(2); b:Hide()
        b:SetColorTexture(color(C.gold))
        r.sel:SetAlpha(0)
        r.badge = CreateFrame("Frame", nil, r)
        r.badge:SetSize(24, 24)
        r.badge:SetPoint("LEFT", 8, 0)
        S.Rounded(r.badge, 6, C.pill1, C.pill2, C.ring)
        r.num = S.Text(r.badge, 12, "gold")
        r.num:SetPoint("CENTER", 0, 0)
        r.name = S.Text(r, 13, "text")
        r.name:SetPoint("TOPLEFT", r.badge, "TOPRIGHT", 10, 0)
        r.name:SetWidth(LIST_W - 70)
        r.count = S.Text(r, 10, "muted")
        r.count:SetPoint("BOTTOMLEFT", r.badge, "BOTTOMRIGHT", 10, 0)
        r.index = i
        r:SetScript("OnClick", function(self) selectRank(self.index, true) end)
        listRows[i] = r
      end
      r:Show()
      r.num:SetText(i)
      r.name:SetText(GuildControlGetRankName(i) or "")
      r.name:SetTextColor(color(i == 1 and C.gold or C.text))
      local n, on = counts(i)
      r.count:SetText(string.format(L["%d members  ·  %d online"], n, on))
      if animate then S.SlideIn(r, -10, 0, 0.25, i * 0.03) end
    elseif r then
      r:Hide()
    end
  end
  if selected > num then selected = math.max(1, num) end
  local leader = ns.Can.leader()
  editBtn:SetShown(leader)
  note:SetText(leader and L["Rank names and permissions are protected by the game: they can only be changed in its own guild window."]
    or L["Only the guild master can change the ranks."])
  if num > 0 then selectRank(selected, animate) end
end

local function build(p)
  page = p
  local list = CreateFrame("Frame", nil, p)
  list:SetPoint("TOPLEFT")
  list:SetPoint("BOTTOMLEFT")
  list:SetWidth(LIST_W)
  S.Card(list, 10)
  p.list = list

  local right = CreateFrame("Frame", nil, p)
  right:SetPoint("TOPLEFT", LIST_W + 16, 0)
  right:SetPoint("BOTTOMRIGHT")
  S.Card(right, 10)
  S.EdgeGlow(right, 24, 0.1)

  membersTitle = S.Section(right, "")
  membersTitle:SetPoint("TOPLEFT", 16, -12)
  membersTitle:SetPoint("TOPRIGHT", -16, -12)

  local box = CreateFrame("Frame", nil, right)
  box:SetPoint("TOPLEFT", membersTitle, "BOTTOMLEFT", 0, -8)
  box:SetPoint("BOTTOMRIGHT", -16, 64)
  local sf, content = S.Scroll(box)
  sf:SetPoint("TOPLEFT")
  sf:SetPoint("BOTTOMRIGHT", -10, 0)
  content:SetWidth(ns.PAGE_W - LIST_W - 16 - 32 - 14)
  members = { content = content, bar = sf.bar or { SetValue = function() end } }
  none = S.Text(box, 12, "muted")
  none:SetPoint("TOP", 0, -20)
  none:SetText(L["Nobody holds this rank."])

  -- rank names and permissions: the game's own window
  editBtn = S.Button(right, L["Edit in the game's window"], 200, 26, function()
    ns.Hide()
    ns.OpenBlizzard()
  end, "primary")
  editBtn:SetPoint("BOTTOMRIGHT", -16, 14)
  note = S.Text(right, 11, "muted")
  note:SetPoint("BOTTOMLEFT", 16, 14)
  note:SetPoint("RIGHT", editBtn, "LEFT", -12, 0)
  note:SetHeight(40)
  note:SetJustifyV("MIDDLE")
  note:SetWordWrap(true)
end

local function onShow() refresh(true) end

ns.AddPage(10, "Ranks", build, onShow, { "Interface\\Icons\\INV_Crown_01", "Interface\\Icons\\INV_Misc_Ribbon_01", "Interface\\Icons\\Ability_Warrior_BattleShout" })

ns.On("RANKS", function() if page and page:IsVisible() then refresh(false) end end)
ns.On("ROSTER", function() if page and page:IsVisible() then refresh(false) end end)
