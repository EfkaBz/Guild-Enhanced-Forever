-- Guild Enhanced Forever: roster page: message of the day, search and filters, sortable member
-- list (virtual rows), member details on the right
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local ROW_H = 22
local LIST_W, DETAIL_W = 650, 250
local COLS = {
  { key = "name",  label = "Name",        w = 160 },
  { key = "role",  label = "Role",        w = 48, center = true },
  { key = "level", label = "Lvl",         w = 36, center = true },
  { key = "rank",  label = "Rank",        w = 104 },
  { key = "zone",  label = "Zone",        w = 112 },
  { key = "note",  label = "Note",        w = 100 },
  { key = "last",  label = "Last online", w = 70 },
}
local STATUS_COLORS = {
  online = { 0.42, 0.86, 0.55 }, afk = { 1, 0.78, 0.3 }, dnd = { 1, 0.38, 0.38 },
}

local page, list, rows, bar, footer, motd, classButtons, rankDrop, offlineCheck, search
local view = {} -- filtered + sorted members
local offset, numRows = 0, 0
local searchText = ""

-- Filtering and sorting ---------------------------------------------------------------
local function matches(m)
  local db = ns.db
  if not db.showOffline and not m.online then return false end
  if db.rankFilter >= 0 and m.rankIndex ~= db.rankFilter then return false end
  if next(db.classFilter) and not db.classFilter[m.classFile or ""] then return false end
  if searchText ~= "" then
    local hay = (m.short .. "\1" .. m.zone .. "\1" .. m.note .. "\1" .. m.rank .. "\1" .. m.class .. "\1" ..
      (ns.Can.viewOfficer() and m.onote or "")):lower()
    if not hay:find(searchText, 1, true) then return false end
  end
  return true
end

-- by role: tanks, then healers, then damage; several roles after the single ones; unknown last
local ROLE_RANK = { tank = 1, heal = 2, dps = 3 }
local SORT = {
  name = function(m) return m.short:lower() end,
  role = function(m)
    local list = ns.RolesOf and ns.RolesOf(m)
    if not list then return 99 end
    return ROLE_RANK[list[1]] * 10 + #list
  end,
  level = function(m) return m.level end,
  rank = function(m) return m.rankIndex end,
  zone = function(m) return m.zone:lower() end,
  note = function(m) return m.note:lower() end,
  last = function(m) return m.lastHours end,
}

local function rebuildView()
  wipe(view)
  for _, m in ipairs(ns.members) do
    if matches(m) then view[#view + 1] = m end
  end
  local key, desc = SORT[ns.db.sortKey] or SORT.rank, ns.db.sortDesc
  table.sort(view, function(a, b)
    if a.online ~= b.online then return a.online end -- online members first
    local va, vb = key(a), key(b)
    if va ~= vb then
      if desc then return va > vb end
      return va < vb
    end
    return a.short < b.short
  end)
end

-- Rows ------------------------------------------------------------------------------------
local function fillRow(row, m)
  row.member = m
  if not m then row:Hide() return end
  row:Show()
  local r, g, b = ns.ClassColor(m.classFile)
  local fade = m.online and 1 or 0.5
  row.name:SetText(m.short)
  row.name:SetTextColor(r, g, b, m.online and 1 or 0.75)
  ns.SetClassIcon(row.icon, m.classFile)
  row.icon:SetDesaturated(not m.online)
  row.icon:SetAlpha(m.online and 1 or 0.6)
  local sc = STATUS_COLORS[m.status]
  row.dot:SetShown(sc ~= nil)
  if sc then row.dot:SetVertexColor(sc[1], sc[2], sc[3], 1) end

  local roles = ns.RolesOf and ns.RolesOf(m)
  local n = ns.SetRoleIcons(row.roleIcons, roles)
  -- centered in the column
  for k = 1, n do
    local t = row.roleIcons[k]
    t:ClearAllPoints()
    t:SetPoint("CENTER", row.roleBox, "CENTER", (k - (n + 1) / 2) * 14, 0)
    t:SetAlpha(m.online and 1 or 0.55)
    t:SetDesaturated(not m.online)
  end
  row.level:SetText(m.level)
  local qc = GetQuestDifficultyColor and m.online and GetQuestDifficultyColor(m.level)
  if qc then row.level:SetTextColor(qc.r, qc.g, qc.b) else row.level:SetTextColor(color(C.dim, fade)) end
  row.rank:SetText(m.rank)
  row.rank:SetTextColor(color(m.rankIndex == 0 and C.gold or C.text, fade))
  row.zone:SetText(m.online and m.zone or (m.zone ~= "" and m.zone or "-"))
  row.zone:SetTextColor(color(C.dim, fade))
  row.note:SetText(m.note)
  row.note:SetTextColor(color(C.muted, m.online and 1 or 0.7))
  row.last:SetText(ns.LastOnlineText(m))
  if m.online then
    row.last:SetTextColor(color(C.good))
  else
    local hours = m.lastHours
    -- colder with time: a week, a month
    if hours > 24 * 30 then row.last:SetTextColor(color(C.bad, 0.8))
    elseif hours > 24 * 7 then row.last:SetTextColor(color(C.warn, 0.8))
    else row.last:SetTextColor(color(C.muted)) end
  end
  local sel = ns.selected == m.name
  row.sel:SetAlpha(sel and 1 or 0)
end

local function refreshRows()
  for i, row in ipairs(rows) do
    row.stripe:SetShown((i + offset) % 2 == 0)
    fillRow(row, view[i + offset])
  end
end

-- staggered fade-in of the visible rows (after a filter or sort change)
local function cascade()
  for i, row in ipairs(rows) do
    if row:IsShown() then
      row:SetAlpha(0)
      S.Tween(row, { dur = 0.22, delay = (i - 1) * 0.012, from = 0, to = 1, set = function(v) row:SetAlpha(v) end })
    end
  end
end

local function updateScroll()
  local max = math.max(0, #view - numRows)
  bar:SetMinMaxValues(0, max)
  bar:SetShown(max > 0)
  local h = bar:GetHeight()
  if h > 0 and #view > 0 then bar:SetThumbHeight(math.max(24, h * numRows / #view)) end
  if offset > max then offset = max end
  bar:SetValue(offset)
end

local function updateFooter()
  local total = #ns.members
  footer.left:SetText(string.format(L["%d of %d members shown"], #view, total))
end

-- full refresh: animate = staggered fade (filters, sort); keep scroll position otherwise
function ns.RefreshRoster(animate)
  if not page then return end
  rebuildView()
  updateScroll()
  refreshRows()
  updateFooter()
  if animate then cascade() end
  -- keeps the selection on the same member after a new scan
  local m = ns.selected and ns.byName[ns.selected]
  if not m then ns.selected = nil end
  ns.ShowMember(m, not animate)
end

local function sortBy(key)
  if ns.db.sortKey == key then ns.db.sortDesc = not ns.db.sortDesc
  else ns.db.sortKey, ns.db.sortDesc = key, false end
  page.header:Refresh()
  ns.RefreshRoster(true)
end

function ns.SelectMember(m)
  ns.selected = m and m.name or nil
  refreshRows()
  ns.ShowMember(m)
end

-- tooltip of a row
local function rowTooltip(row)
  local m = row.member
  if not m then return end
  GameTooltip:SetOwner(row, "ANCHOR_NONE")
  GameTooltip:SetPoint("LEFT", row, "RIGHT", 12 + DETAIL_W, 0)
  local r, g, b = ns.ClassColor(m.classFile)
  GameTooltip:AddLine(m.short, r, g, b)
  GameTooltip:AddLine(string.format(L["Level %d %s"], m.level, m.class), 1, 1, 1)
  GameTooltip:AddDoubleLine(L["Rank"], m.rank, 0.6, 0.55, 0.7, color(C.gold))
  local roles = ns.RolesOf and ns.RolesOf(m)
  if roles then GameTooltip:AddDoubleLine(L["Role"], ns.RolesName(roles), 0.6, 0.55, 0.7, 1, 1, 1) end
  if m.zone ~= "" then GameTooltip:AddDoubleLine(L["Zone"], m.zone, 0.6, 0.55, 0.7, 1, 1, 1) end
  GameTooltip:AddDoubleLine(L["Last online"], ns.LastOnlineText(m), 0.6, 0.55, 0.7, 1, 1, 1)
  if m.note ~= "" then GameTooltip:AddLine(" "); GameTooltip:AddLine(L["Note"] .. ": |cffffffff" .. m.note .. "|r", 0.6, 0.55, 0.7, true) end
  if ns.Can.viewOfficer() and m.onote ~= "" then
    GameTooltip:AddLine(L["Officer note"] .. ": |cffffffff" .. m.onote .. "|r", 0.6, 0.55, 0.7, true)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(L["Double-click: whisper  ·  Right-click: actions"], 0.55, 0.5, 0.65)
  GameTooltip:Show()
end

local function makeRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -2)
  row.stripe:SetAllPoints()
  row.stripe:SetColorTexture(1, 1, 1, 0.025)
  S.RowHighlight(row)

  -- selected: steady wash and bar
  row.sel = CreateFrame("Frame", nil, row)
  row.sel:SetAllPoints()
  local w = row.sel:CreateTexture(nil, "BACKGROUND", nil, 0)
  w:SetAllPoints()
  S.Highlight(w, 0.2)
  local b = row.sel:CreateTexture(nil, "ARTWORK")
  b:SetPoint("TOPLEFT"); b:SetPoint("BOTTOMLEFT"); b:SetWidth(2); b:Hide()
  b:SetColorTexture(color(C.gold))
  row.sel:SetAlpha(0)

  row.dot = row:CreateTexture(nil, "ARTWORK")
  row.dot:SetTexture(S.MEDIA .. "Dot")
  row.dot:SetSize(6, 6)
  row.dot:SetPoint("LEFT", 6, 0)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", 16, 0)

  local x = 0
  for _, col in ipairs(COLS) do
    if col.key == "role" then
      -- the role icons (up to three), centered in the column
      row.roleBox = CreateFrame("Frame", nil, row)
      row.roleBox:SetPoint("LEFT", x, 0)
      row.roleBox:SetSize(col.w, ROW_H)
      row.roleIcons = {}
      for k = 1, 3 do
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetSize(13, 13)
        t:Hide()
        row.roleIcons[k] = t
      end
    end
    local fs = S.Text(row, 12, "text")
    if col.key == "role" then
      fs:Hide()
    elseif col.key == "name" then
      fs:SetPoint("LEFT", 38, 0)
      fs:SetWidth(col.w - 42)
    else
      fs:SetPoint("LEFT", x + 4, 0)
      fs:SetWidth(col.w - 8)
    end
    if col.center then fs:SetJustifyH("CENTER") end
    row[col.key] = fs
    x = x + col.w
  end

  row:SetScript("OnClick", function(self, button)
    local m = self.member
    if not m then return end
    if button == "RightButton" then
      ns.SelectMember(m)
      ns.MemberMenu(self, m)
    else
      ns.SelectMember(ns.selected ~= m.name and m or nil) -- a second click deselects
    end
  end)
  row:SetScript("OnDoubleClick", function(self)
    if self.member and not ns.IsMe(self.member) then ns.Whisper(self.member) end
  end)
  row:HookScript("OnEnter", rowTooltip)
  row:HookScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

-- Column header with a sort chevron ---------------------------------------------------------
local function buildHeader(parent)
  local h = CreateFrame("Frame", nil, parent)
  h:SetHeight(24)
  local bg = h:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  gradient(bg, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.0 })
  local line = h:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
  gradient(line, { C.ring[1], C.ring[2], C.ring[3], 0.6 }, { C.ring[1], C.ring[2], C.ring[3], 0.1 }, true)
  h.cols = {}

  -- chevron made of two rotated bars; points up (ascending) or down
  local chev = CreateFrame("Frame", nil, h)
  chev:SetSize(10, 6)
  local l1 = chev:CreateTexture(nil, "OVERLAY"); l1:SetTexture(S.WHITE); l1:SetSize(6, 1.6)
  local l2 = chev:CreateTexture(nil, "OVERLAY"); l2:SetTexture(S.WHITE); l2:SetSize(6, 1.6)
  l1:SetPoint("CENTER", -2.2, 0); l2:SetPoint("CENTER", 2.2, 0)
  l1:SetVertexColor(color(C.gold)); l2:SetVertexColor(color(C.gold))
  local angle = 40
  local function setChev(a)
    angle = a
    l1:SetRotation(math.rad(a)); l2:SetRotation(math.rad(-a))
  end
  setChev(angle)

  local x = 0
  for _, col in ipairs(COLS) do
    local b = CreateFrame("Button", nil, h)
    b:SetPoint("TOPLEFT", x, 0)
    b:SetSize(col.w, 24)
    b.key = col.key
    b.text = S.Text(b, 11, "muted")
    if col.key == "name" then b.text:SetPoint("LEFT", 38, 0)
    elseif col.center then b.text:SetPoint("CENTER")
    else b.text:SetPoint("LEFT", 4, 0) end
    b.text:SetText(L[col.label])
    local hl = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    hl:SetAllPoints()
    S.Highlight(hl, 0.12)
    S.HoverFade(b, hl)
    b:HookScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
    b:HookScript("OnLeave", function(self) h:Refresh() end)
    b:SetScript("OnClick", function(self) sortBy(self.key) end)
    h.cols[#h.cols + 1] = b
    x = x + col.w
  end

  function h:Refresh()
    for _, b in ipairs(self.cols) do
      local on = b.key == ns.db.sortKey
      b.text:SetTextColor(color(on and C.gold or C.muted))
      if on then
        chev:ClearAllPoints()
        chev:SetPoint("LEFT", b.text, "RIGHT", 5, 0)
      end
    end
    local to = ns.db.sortDesc and -40 or 40
    if to ~= angle then S.Tween(chev, { dur = 0.2, from = angle, to = to, set = setChev }) end
  end
  return h
end

-- Message of the day strip ---------------------------------------------------------------------
local function buildMOTD(parent)
  local m = CreateFrame("Button", nil, parent)
  m:SetHeight(32)
  S.Card(m, 8)
  local glow = m:CreateTexture(nil, "BACKGROUND", nil, -6)
  glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("BOTTOMRIGHT", -1, 1)
  glow:Hide()
  local label = S.Text(m, 11, "gold")
  label:SetPoint("LEFT", 12, 0)
  label:SetText(L["MOTD"])
  local sep = m:CreateTexture(nil, "ARTWORK")
  sep:SetSize(1, 16)
  sep:SetPoint("LEFT", label, "RIGHT", 10, 0)
  sep:SetColorTexture(color(C.trim))
  m.text = S.Text(m, 12, "text")
  m.text:SetPoint("LEFT", sep, "RIGHT", 10, 0)
  m.text:SetPoint("RIGHT", -70, 0)
  m.edit = S.Text(m, 11, "muted")
  m.edit:SetPoint("RIGHT", -12, 0)
  m.edit:SetText(L["Edit"])
  local hl = m:CreateTexture(nil, "BACKGROUND", nil, -5)
  hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
  S.Highlight(hl, 0.08)
  S.HoverFade(m, hl)
  m:HookScript("OnEnter", function(self)
    if ns.Can.motd() then self.edit:SetTextColor(color(C.gold)) end
    local t = ns.GetMOTD() or ""
    if t ~= "" then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(L["Message of the day"], color(C.gold))
      GameTooltip:AddLine(t, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  m:HookScript("OnLeave", function(self) self.edit:SetTextColor(color(C.muted)); GameTooltip:Hide() end)
  m:SetScript("OnClick", function()
    if not ns.Can.motd() then return end
    S.Dialog({ title = L["Message of the day"], input = ns.GetMOTD() or "", maxLetters = 128,
      allowEmpty = true, accept = L["Save"], onAccept = function(t) ns.SetMOTD(t) end })
  end)
  function m:Refresh()
    local t = ns.GetMOTD() or ""
    self.text:SetText(t ~= "" and t or ("|cff999999" .. L["No message of the day."] .. "|r"))
    self.edit:SetShown(ns.Can.motd())
  end
  return m
end

-- Class filter icons -----------------------------------------------------------------------------
local function refreshClassButtons()
  local any = next(ns.db.classFilter) ~= nil
  for _, b in ipairs(classButtons) do
    local on = ns.db.classFilter[b.class]
    b.tex:SetDesaturated(any and not on)
    S.FadeTo(b, (not any or on) and 1 or 0.4, 0.15)
    b:SetBorderColor(color(on and C.gold or C.trim))
    b.glow:SetShown(on and true or false)
  end
end

local function buildClassButtons(parent)
  classButtons = {}
  local prev
  for _, cls in ipairs(ns.CLASSES) do
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    S.Box(b, { 0, 0, 0, 1 }, C.trim)
    b.class = cls
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1); b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    ns.SetClassIcon(b.tex, cls)
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    b.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.glow:SetBlendMode("ADD")
    b.glow:SetDrawLayer("OVERLAY")
    b.glow:SetAllPoints()
    b.glow:Hide()
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) end
    prev = b
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
      if button == "RightButton" then
        wipe(ns.db.classFilter)
      else
        ns.db.classFilter[self.class] = not ns.db.classFilter[self.class] or nil
      end
      refreshClassButtons()
      offset = 0
      ns.RefreshRoster(true)
    end)
    b:SetScript("OnEnter", function(self)
      local total, online = 0, 0
      for _, m in ipairs(ns.members) do
        if m.classFile == self.class then
          total = total + 1
          if m.online then online = online + 1 end
        end
      end
      local r, g, bl = ns.ClassColor(self.class)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine((LOCALIZED_CLASS_NAMES_MALE or {})[self.class] or self.class, r, g, bl)
      GameTooltip:AddLine(string.format(L["%d online / %d"], online, total), 1, 1, 1)
      GameTooltip:AddLine(L["Click: filter  ·  Right-click: clear"], 0.55, 0.5, 0.65)
      GameTooltip:Show()
      if not ns.db.classFilter[self.class] then self:SetBorderColor(color(C.ring)) end
    end)
    b:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
      if not ns.db.classFilter[self.class] then self:SetBorderColor(color(C.trim)) end
    end)
    classButtons[#classButtons + 1] = b
  end
  return classButtons[1]
end

-- Page --------------------------------------------------------------------------------------------
-- Saved filters and export ------------------------------------------------------------------------------
local function applyFilter(f)
  ns.db.showOffline = f.showOffline and true or false
  ns.db.rankFilter = f.rankFilter or -1
  ns.db.classFilter = CopyTable(f.classFilter or {})
  offlineCheck:SetChecked(ns.db.showOffline)
  rankDrop.Refresh()
  refreshClassButtons()
  search:SetText(f.search or "") -- (refreshes the list)
  searchText = strtrim(f.search or ""):lower()
  offset = 0
  ns.RefreshRoster(true)
end

local function filterMenu(owner)
  ns.db.savedFilters = ns.db.savedFilters or {}
  local saved = ns.db.savedFilters
  local items = { { text = L["Saved filters"], title = true } }
  for _, f in ipairs(saved) do items[#items + 1] = { text = f.name, func = function() applyFilter(f) end } end
  if #saved == 0 then items[#items + 1] = { text = L["(none)"], disabled = true } end
  items[#items + 1] = { separator = true }
  items[#items + 1] = { text = L["Save the current filters"], func = function()
    S.Dialog({ title = L["Save the current filters"], text = L["Name of this filter:"], input = "", maxLetters = 30,
      accept = L["Save"], onAccept = function(name)
        name = strtrim(name)
        for i = #saved, 1, -1 do if saved[i].name == name then table.remove(saved, i) end end
        saved[#saved + 1] = { name = name, showOffline = ns.db.showOffline, rankFilter = ns.db.rankFilter,
          classFilter = CopyTable(ns.db.classFilter), search = search:GetText() }
      end })
  end }
  if #saved > 0 then
    items[#items + 1] = { text = L["Delete a filter"], color = C.bad, func = function()
      local del = { { text = L["Delete a filter"], title = true } }
      for i, f in ipairs(saved) do
        del[#del + 1] = { text = f.name, color = C.bad, func = function() table.remove(saved, i) end }
      end
      C_Timer.After(0, function() S.OpenMenu(owner, del, { width = 200 }) end)
    end }
  end
  items[#items + 1] = { text = L["Reset the filters"], func = function()
    applyFilter({ showOffline = true, rankFilter = -1, classFilter = {}, search = "" })
  end }
  S.OpenMenu(owner, items, { width = 200 })
end

-- the members of the list as text (one line each), ready to copy
local exportWin
local function export()
  local lines = { table.concat({ L["Name"], L["Level"], L["Class"], L["Rank"], L["Zone"], L["Last online"], L["Public note"] }, ";") }
  for _, m in ipairs(view) do
    lines[#lines + 1] = table.concat({ m.short, m.level, m.class, m.rank, m.zone,
      m.online and L["Online"] or ns.LastOnlineText(m), (m.note or ""):gsub(";", ",") }, ";")
  end
  if not exportWin then
    exportWin = S.Window("GuildEnhancedForeverExport", UIParent, 560, 420, L["Export"])
    exportWin:SetFrameStrata("DIALOG")
    exportWin:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    exportWin.close:SetScript("OnClick", function() S.AnimateClose(exportWin, 0, -10) end)
    S.Draggable(exportWin, exportWin.titleBar)
    tinsert(UISpecialFrames, "GuildEnhancedForeverExport")
    exportWin.box = S.MultiEdit(exportWin)
    exportWin.box:SetPoint("TOPLEFT", 16, -56)
    exportWin.box:SetPoint("BOTTOMRIGHT", -16, 44)
    exportWin.hint = S.Text(exportWin, 11, "muted")
    exportWin.hint:SetPoint("BOTTOMLEFT", 18, 16)
    exportWin.hint:SetText(L["Ctrl+A then Ctrl+C to copy. Separator: semicolon (opens in a spreadsheet)."])
  end
  exportWin.title:SetText(string.format(L["Export: %d members"], #view))
  exportWin.box:SetText(table.concat(lines, "\n"))
  exportWin:Show()
  S.AnimateOpen(exportWin, 0, -10)
  exportWin.box.edit:SetFocus()
  exportWin.box.edit:HighlightText()
end

local function build(p)
  page = p

  -- my roles, at the right of the message of the day (several can be checked)
  local picker = ns.RolePicker(p, 26, 34)
  picker:SetPoint("TOPRIGHT", -4, -3)
  local pickLabel = S.Text(p, 11, "muted")
  pickLabel:SetPoint("RIGHT", picker, "LEFT", -10, 0)
  pickLabel:SetText(L["My roles"])

  motd = buildMOTD(p)
  motd:SetPoint("TOPLEFT")
  motd:SetPoint("TOPRIGHT", -(4 + picker:GetWidth() + 10 + math.ceil(pickLabel:GetStringWidth()) + 14), 0)

  -- toolbar
  search = S.EditBox(p, 190, 24, L["Search name, zone, note..."])
  search:SetPoint("TOPLEFT", 0, -42)
  search.onChange = function(t)
    searchText = strtrim(t or ""):lower()
    offset = 0
    ns.RefreshRoster(true)
  end
  -- magnifier: a ring and a handle
  local ring = search:CreateTexture(nil, "OVERLAY")
  ring:SetTexture(S.MEDIA .. "Ring")
  ring:SetSize(11, 11)
  ring:SetPoint("RIGHT", -12, 1)
  ring:SetVertexColor(color(C.muted))
  local handle = search:CreateTexture(nil, "OVERLAY")
  handle:SetTexture(S.WHITE)
  handle:SetSize(5, 1.6)
  handle:SetPoint("CENTER", ring, "BOTTOMRIGHT", 0, 0)
  handle:SetRotation(math.rad(-45))
  handle:SetVertexColor(color(C.muted))

  rankDrop = S.Dropdown(p, 140, function()
    local o = { { -1, L["All ranks"] } }
    local ranks = ns.Ranks()
    for i = 0, ns.NumRanks() - 1 do o[#o + 1] = { i, ranks[i] } end
    return o
  end, function() return ns.db.rankFilter end, function(v)
    ns.db.rankFilter = v
    offset = 0
    ns.RefreshRoster(true)
  end)
  rankDrop:SetPoint("LEFT", search, "RIGHT", 8, 0)

  local first = buildClassButtons(p)
  first:SetPoint("LEFT", rankDrop, "RIGHT", 12, 0)
  refreshClassButtons()

  offlineCheck = S.Check(p, L["Offline"], 16)
  offlineCheck:SetPoint("LEFT", classButtons[#classButtons], "RIGHT", 12, 0)
  offlineCheck:SetChecked(ns.db.showOffline)
  offlineCheck:SetScript("OnClick", function(self)
    ns.db.showOffline = self:GetChecked() and true or false
    offset = 0
    ns.RefreshRoster(true)
  end)
  S.Tooltip(offlineCheck, L["Show offline members"])

  -- list card
  list = CreateFrame("Frame", nil, p)
  list:SetPoint("TOPLEFT", 0, -74)
  list:SetSize(LIST_W, ns.PAGE_H - 74 - 24)
  S.Card(list, 8)

  page.header = buildHeader(list)
  page.header:SetPoint("TOPLEFT", 4, -4)
  page.header:SetPoint("TOPRIGHT", -12, -4)

  local area = CreateFrame("Frame", nil, list)
  area:SetPoint("TOPLEFT", 4, -30)
  area:SetPoint("BOTTOMRIGHT", -12, 6)
  numRows = math.floor((list:GetHeight() - 36) / ROW_H)
  rows = {}
  for i = 1, numRows do rows[i] = makeRow(area, i) end

  bar = S.ScrollBar(list)
  bar:SetPoint("TOPRIGHT", -5, -32)
  bar:SetPoint("BOTTOMRIGHT", -5, 8)
  bar:SetValueStep(1)
  bar:SetScript("OnValueChanged", function(_, v)
    local o = math.floor(v + 0.5)
    if o ~= offset then
      offset = o
      refreshRows()
    end
  end)
  area:EnableMouseWheel(true)
  area:SetScript("OnMouseWheel", function(_, d)
    local _, hi = bar:GetMinMaxValues()
    bar:SetValue(math.max(0, math.min(hi, offset - d * 3)))
  end)

  -- empty list
  page.none = S.Text(area, 13, "muted")
  page.none:SetPoint("CENTER")
  page.none:SetText(L["No member matches."])
  page.none:Hide()

  footer = CreateFrame("Frame", nil, p)
  footer:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 4, -4)
  footer:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -4, -4)
  footer:SetHeight(18)
  footer.left = S.Text(footer, 11, "muted")
  footer.left:SetPoint("LEFT")
  footer.right = S.Text(footer, 11, "muted")
  footer.right:SetPoint("RIGHT")
  footer.right:SetText(L["Double-click: whisper  ·  Right-click: actions"])
  local exp = S.Button(footer, L["Export"], 70, 18, export)
  exp:SetPoint("RIGHT", footer.right, "LEFT", -14, 0)
  S.Tooltip(exp, { L["Export"], L["The members of the list as text, to copy."] })
  local fil = S.Button(footer, L["Filters"], 70, 18, function(self) filterMenu(self) end)
  fil:SetPoint("RIGHT", exp, "LEFT", -6, 0)
  S.Tooltip(fil, { L["Filters"], L["Save the current filters, or use a saved one."] })

  -- details panel (UI\Details.lua)
  ns.BuildDetails(p, DETAIL_W)

  page.header:Refresh()
  hooksecurefunc(ns, "RefreshRoster", function() page.none:SetShown(#view == 0) end)
end

local function onShow()
  motd:Refresh()
  rankDrop.Refresh()
  ns.RefreshRoster(true)
end

ns.AddPage(1, "Roster", build, onShow, { "Interface\\Icons\\INV_Misc_GroupNeedMore", "Interface\\Icons\\INV_Misc_GroupLooking", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude" })

ns.On("ROSTER", function() if page and page:IsVisible() then ns.RefreshRoster() end end)
local function rolesChanged() if page and page:IsVisible() then ns.RefreshRoster() end end
ns.On("SYNC_ROLES", rolesChanged)
ns.On("MYROLES", rolesChanged)
ns.On("GUILD", function() if motd then motd:Refresh() end end)
ns.On("RANKS", function() if rankDrop then rankDrop.Refresh() end end)
