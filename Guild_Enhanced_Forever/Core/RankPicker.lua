-- Guild Enhanced Forever: the window to give a member another rank.
-- GuildPromote / GuildDemote are protected on this client: an addon calling them is blocked. The
-- game's own slash commands (/gpromote, /gdemote) still work from a macro, so the confirm button is
-- a secure action button. The server takes one step per click (several lines in one macro all land
-- on the same rank), so the window stays open and each click moves the member one rank.
local _, ns = ...
local L, S = ns.L, ns.Skin
local C = S.C

local W, PAD, ROW_H = 340, 12, 22
local win, blocker, card, apply, rows = nil, nil, nil, nil, {}
local current, chosen, now -- now: the member's rank, followed click by click

local PROMOTE = _G.SLASH_GUILD_PROMOTE1 or "/gpromote"
local DEMOTE = _G.SLASH_GUILD_DEMOTE1 or "/gdemote"

-- ranks this member can be given: from just below mine down to the last one; going up needs the
-- promote permission, going down the demote one
local function choices(m)
  local list, names = {}, ns.Ranks()
  local up, down = ns.CanPromote(m), ns.CanDemote(m)
  for i = ns.MyRank() + 1, ns.NumRanks() - 1 do
    if i == m.rankIndex or (i < m.rankIndex and up) or (i > m.rankIndex and down) then
      list[#list + 1] = { index = i, name = names[i] or "" }
    end
  end
  return list
end

-- the click is registered on the edge the game's secure buttons act on (key down or key up)
local function registerClicks()
  local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
  apply:RegisterForClicks(down and "AnyDown" or "AnyUp")
end

local function refreshApply()
  if InCombatLockdown() then return end
  local steps = (current and chosen and now) and (now - chosen) or 0
  if steps == 0 then
    apply:SetAttribute("macrotext", nil)
    apply:SetText(L["Choose a rank"])
    apply:Disable()
    return
  end
  apply:SetAttribute("macrotext", (steps > 0 and PROMOTE or DEMOTE) .. " " .. current.name)
  local n = math.abs(steps)
  apply:SetText((steps > 0 and L["Promote"] or L["Demote"]) .. (n > 1 and (" (" .. n .. ")") or ""))
  apply:SetEnabled(not apply.wait)
end

local function refreshRows()
  for _, row in ipairs(rows) do
    if row:IsShown() then
      local isCurrent = row.rank == now
      row.check:SetShown(row.rank == chosen)
      row.sel:SetShown(row.rank == chosen)
      local c = isCurrent and C.muted or (row.rank == chosen and C.text or C.gold)
      row.text:SetTextColor(c[1], c[2], c[3])
      if isCurrent then
        row.right:SetText(L["Current"])
      elseif row.rank < now then
        row.right:SetText("|cff20ff20" .. L["Promote"] .. "|r")
      else
        row.right:SetText("|cffff6040" .. L["Demote"] .. "|r")
      end
    end
  end
  refreshApply()
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local row = CreateFrame("Button", nil, card)
  row:SetHeight(ROW_H)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  S.Highlight(row.hl, 0.2)
  row.hl:Hide()
  row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.sel:SetAllPoints()
  S.Highlight(row.sel, 0.4)
  row.sel:Hide()
  row.check = row:CreateTexture(nil, "OVERLAY")
  row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  row.check:SetSize(18, 18)
  row.check:SetPoint("LEFT", 2, 0)
  row.text = S.Text(row, 12, "gold")
  row.text:SetPoint("LEFT", 24, 0)
  row.text:SetPoint("RIGHT", -90, 0)
  row.text:SetJustifyH("LEFT")
  row.right = S.Text(row, 11, "muted")
  row.right:SetPoint("RIGHT", -6, 0)
  row:SetScript("OnEnter", function(self) if self.rank ~= now then self.hl:Show() end end)
  row:SetScript("OnLeave", function(self) self.hl:Hide() end)
  row:SetScript("OnClick", function(self)
    if InCombatLockdown() or self.rank == now then return end
    chosen = self.rank
    PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    refreshRows()
  end)
  rows[i] = row
  return row
end

local function hidePicker()
  if blocker and blocker:IsShown() and not InCombatLockdown() then blocker:Hide() end
end

local function build()
  blocker = CreateFrame("Frame", "GuildEnhancedForeverRankBlocker", UIParent)
  blocker:SetAllPoints(UIParent)
  blocker:SetFrameStrata("DIALOG")
  blocker:EnableMouse(true)
  blocker:Hide()

  win = S.Window("GuildEnhancedForeverRankPicker", blocker, W, 200, L["Change rank"], "portrait")
  win:SetFrameStrata("DIALOG")
  win:SetFrameLevel(blocker:GetFrameLevel() + 5)
  win:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
  win.close:SetScript("OnClick", hidePicker)
  if win.titleBar then S.Draggable(win, win.titleBar) end
  if not S.SetPortrait(win, ns.ICON) then
    local icon = win:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 8, -6)
    icon:SetTexture(ns.ICON)
  end

  win.sub = S.Text(win, 12, "dim")
  win.sub:SetPoint("TOPLEFT", 66, -32)
  win.sub:SetPoint("RIGHT", -16, 0)

  card = CreateFrame("Frame", nil, win)
  card:SetPoint("TOPLEFT", 14, -62)
  card:SetPoint("BOTTOMRIGHT", -14, 56)
  S.Card(card, 8)
  card.note = S.Text(card, 11, "muted")
  card.note:SetPoint("BOTTOM", 0, PAD)
  card.note:SetWidth(W - 28 - 2 * PAD)
  card.note:SetJustifyH("CENTER")
  card.note:SetWordWrap(true)
  card.note:SetText(L["One click per rank: the game moves a member one step at a time."])

  local ok, b = pcall(CreateFrame, "Button", "GuildEnhancedForeverRankApply", win,
    "UIPanelButtonTemplate,SecureActionButtonTemplate")
  if not ok or not b then b = CreateFrame("Button", "GuildEnhancedForeverRankApply", win, "SecureActionButtonTemplate") end
  apply = b
  apply:SetSize(140, 26)
  apply:SetPoint("BOTTOMRIGHT", win, "BOTTOM", -6, 16)
  apply:SetNormalFontObject(GameFontNormal)
  apply:SetHighlightFontObject(GameFontHighlight)
  apply:SetDisabledFontObject(GameFontDisable)
  apply:SetAttribute("type", "macro")
  -- one step sent: the member is one rank closer; the button rests a moment (no double step), and
  -- the window closes once the chosen rank is reached
  apply:SetScript("PostClick", function()
    if not now or not chosen or now == chosen then return end
    now = now + (chosen < now and -1 or 1)
    if now == chosen then
      hidePicker()
      C_Timer.After(0.5, ns.RequestRoster)
      return
    end
    apply.wait = true
    apply:Disable()
    refreshRows()
    C_Timer.After(0.6, function()
      apply.wait = nil
      if blocker:IsShown() then refreshApply() end
    end)
  end)

  local cancel = S.Button(win, L["Cancel"], 140, 26, hidePicker)
  cancel:SetPoint("BOTTOMLEFT", win, "BOTTOM", 6, 16)

  tinsert(UISpecialFrames, "GuildEnhancedForeverRankBlocker") -- Escape closes it

  -- never left open in combat: a secure button can't be hidden or changed then
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_REGEN_DISABLED")
  ev:SetScript("OnEvent", hidePicker)

  -- fresh roster: follow the member's real rank, or close (left the guild, no longer allowed)
  ns.On("ROSTER", function()
    if not blocker:IsShown() or not current or InCombatLockdown() then return end
    local m = ns.byName[current.name]
    if not m or not (ns.CanPromote(m) or ns.CanDemote(m)) then hidePicker() return end
    current, now = m, m.rankIndex
    if chosen == now then hidePicker() return end
    refreshRows()
  end)
end

-- opens the window for a member; step: -1 preselects the rank above, 1 the rank below
function ns.ChangeRank(m, step)
  if not m then return end
  m = ns.byName[m.name] or m
  if not (ns.CanPromote(m) or ns.CanDemote(m)) then return end
  if InCombatLockdown() then
    ns.Print(L["Not possible in combat."])
    return
  end
  if not win then build() end
  S.CloseMenu()
  current, now = m, m.rankIndex
  apply.wait = nil

  local list = choices(m)
  chosen = nil
  if step then
    for _, it in ipairs(list) do
      if it.index == m.rankIndex + step then chosen = it.index end
    end
  end

  local y = PAD
  for i, it in ipairs(list) do
    local row = getRow(i)
    row.rank = it.index
    row.text:SetText(it.name)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", PAD, -y)
    row:SetPoint("TOPRIGHT", -PAD, -y)
    row.hl:Hide()
    row:Show()
    y = y + ROW_H
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  local noteH = math.ceil(card.note:GetStringHeight())
  win:SetHeight(62 + y + 8 + noteH + PAD + 56)

  win.sub:SetText("|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r  ·  " .. (m.rank or ""))
  registerClicks()
  refreshRows()
  blocker:Show()
  win:Show()
  PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN or 850)
end
