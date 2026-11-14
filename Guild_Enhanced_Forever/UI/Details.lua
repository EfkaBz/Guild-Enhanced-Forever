-- Guild Enhanced Forever: member details panel (right of the roster): identity, status, rank,
-- notes, actions; guild summary when nobody is selected
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local panel, content, empty, current
local memberUnit, applyModel -- 3D portrait helpers (defined at the end)

local function infoLine(parent, y, label)
  local l = S.Text(parent, 11, "muted")
  l:SetPoint("TOPLEFT", 14, y)
  l:SetText(label)
  local v = S.Text(parent, 12, "text")
  v:SetPoint("TOPRIGHT", -14, y)
  v:SetJustifyH("RIGHT")
  v:SetWidth(150)
  return v
end

-- note block: section header (with an Edit link) + wrapped text
local function noteBlock(parent, title, officer)
  local h = S.Section(parent, title)
  h:SetPoint("LEFT", 14, 0)
  h:SetPoint("RIGHT", -14, 0)
  local edit = CreateFrame("Button", nil, h)
  edit:SetSize(40, 18)
  edit:SetPoint("RIGHT", 0, 2)
  edit.text = S.Text(edit, 11, "muted")
  edit.text:SetPoint("RIGHT")
  edit.text:SetText(L["Edit"])
  edit:SetScript("OnEnter", function(self) self.text:SetTextColor(color(C.gold)) end)
  edit:SetScript("OnLeave", function(self) self.text:SetTextColor(color(C.muted)) end)
  edit:SetScript("OnClick", function() ns.EditNote(current, officer) end)
  h.edit = edit
  h.body = S.Text(parent, 12, "text")
  h.body:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
  h.body:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", 0, -6)
  h.body:SetWordWrap(true)
  h.body:SetJustifyV("TOP")
  h.body:SetHeight(30)
  return h
end

local function buildEmpty(p)
  empty = CreateFrame("Frame", nil, p)
  empty:SetAllPoints()
  local icon = empty:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ns.ICON)
  icon:SetSize(64, 64)
  icon:SetPoint("TOP", 0, -30)
  local halo = empty:CreateTexture(nil, "BACKGROUND")
  halo:SetTexture(S.MEDIA .. "Glow")
  halo:Hide()
  halo:SetBlendMode("ADD")
  halo:SetSize(130, 130)
  halo:SetPoint("CENTER", icon)
  halo:SetVertexColor(1, 0.75, 0.3, 0.3)
  empty.name = S.Text(empty, 15, "gold")
  empty.name:SetPoint("TOP", icon, "BOTTOM", 0, -12)
  empty.name:SetWidth(220)
  empty.name:SetJustifyH("CENTER")
  local hint = S.Text(empty, 11, "muted")
  hint:SetPoint("TOP", empty.name, "BOTTOM", 0, -6)
  -- held by both sides of the panel: a long sentence wraps, centered, instead of running out
  hint:SetPoint("LEFT", empty, "LEFT", 16, 0)
  hint:SetPoint("RIGHT", empty, "RIGHT", -16, 0)
  hint:SetJustifyH("CENTER")
  hint:SetWordWrap(true)
  hint:SetText(L["Select a member to see the details."])

  local sec = S.Section(empty, L["Online now"])
  -- under the hint, however many lines it takes in the chosen language
  sec:SetPoint("TOP", hint, "BOTTOM", 0, -18)
  sec:SetPoint("LEFT", empty, "LEFT", 14, 0)
  sec:SetPoint("RIGHT", empty, "RIGHT", -14, 0)
  empty.bars = {}
  -- online members by level bracket
  local brackets = { { 60, 60, "60" }, { 50, 59, "50-59" }, { 40, 49, "40-49" }, { 1, 39, "1-39" } }
  for i, br in ipairs(brackets) do
    local y = -30 - (i - 1) * 30 -- from the top of the section
    local lab = S.Text(empty, 11, "dim")
    lab:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, y)
    lab:SetText(string.format(L["Level %s"], br[3]))
    local n = S.Text(empty, 11, "text")
    n:SetPoint("TOPRIGHT", sec, "TOPRIGHT", 0, y)
    local b = S.ProgressBar(empty, 6, C.fill1, C.fill2)
    b:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, y - 15)
    b:SetPoint("TOPRIGHT", sec, "TOPRIGHT", 0, y - 15)
    empty.bars[i] = { bar = b, n = n, lo = br[1], hi = br[2] }
  end
end

local function refreshEmpty(animate)
  empty.name:SetText(ns.GuildName() or "")
  local counts, max = {}, 1
  for i, br in ipairs(empty.bars) do
    local c = 0
    for _, m in ipairs(ns.members) do
      if m.online and m.level >= br.lo and m.level <= br.hi then c = c + 1 end
    end
    counts[i] = c
    if c > max then max = c end
  end
  for i, br in ipairs(empty.bars) do
    br.n:SetText(counts[i])
    br.bar:SetMinMaxValues(0, max)
    br.bar:SetValue(counts[i])
    if animate then br.bar:Replay(0.05 * i) end
  end
end

function ns.BuildDetails(p, width)
  panel = CreateFrame("Frame", nil, p)
  panel:SetPoint("TOPRIGHT", 0, -42)
  panel:SetPoint("BOTTOMRIGHT", 0, 0)
  panel:SetWidth(width)
  S.Card(panel, 10)
  S.EdgeGlow(panel, 24, 0.12)

  buildEmpty(panel)

  content = CreateFrame("Frame", nil, panel)
  content:SetPoint("TOPLEFT")
  content:SetSize(width, 460)
  content:Hide()

  -- identity: the 3D portrait when the game can show the player, the class icon otherwise
  local icon = S.Icon(content, 46)
  icon:SetPoint("TOPLEFT", 14, -12)
  content.icon = icon
  local model = CreateFrame("PlayerModel", nil, icon)
  model:SetPoint("TOPLEFT", 1, -1)
  model:SetPoint("BOTTOMRIGHT", -1, 1)
  model:Hide()
  content.model = model
  model:SetScript("OnShow", function(self)
    -- the model is cleared while hidden: load it again if this member can still be seen
    if not current or content.modelFor ~= current.name or self.loading then return end
    local unit = content.modelUnit
    if unit ~= "player" and not (UnitExists(unit) and UnitName(unit) == current.short) then unit = memberUnit(current) end
    if unit then
      content.modelUnit = unit
      self.loading = true
      applyModel(self, unit)
      self.loading = nil
    end
  end)
  local bg = icon:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetPoint("TOPLEFT", 1, -1)
  bg:SetPoint("BOTTOMRIGHT", -1, 1)
  bg:SetColorTexture(0.08, 0.08, 0.08, 1)
  S.Tooltip(icon, function()
    if model:IsShown() then return nil end
    return { L["3D portrait"], L["Shown when the player is near you: yourself, your target, your group or a visible name plate."] }
  end, "ANCHOR_RIGHT")
  local halo = content:CreateTexture(nil, "BACKGROUND")
  halo:SetTexture(S.MEDIA .. "Glow")
  halo:Hide()
  halo:SetBlendMode("ADD")
  halo:SetSize(90, 90)
  halo:SetPoint("CENTER", icon)
  content.halo = halo
  content.name = S.Text(content, 16, "text")
  content.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  content.name:SetWidth(width - 80)
  content.sub = S.Text(content, 11, "dim")
  content.sub:SetPoint("TOPLEFT", content.name, "BOTTOMLEFT", 0, -4)
  content.sub:SetWidth(width - 80)

  -- status pill: pulsing dot + text
  local status = CreateFrame("Frame", nil, content)
  status:SetSize(width - 28, 24)
  status:SetPoint("TOPLEFT", 14, -64)
  S.Rounded(status, 6, { 0.06, 0.04, 0.1, 0.9 }, { 0.04, 0.03, 0.07, 0.9 }, C.rule)
  status.dot = status:CreateTexture(nil, "ARTWORK")
  status.dot:SetTexture(S.MEDIA .. "Dot")
  status.dot:SetSize(8, 8)
  status.dot:SetPoint("LEFT", 10, 0)
  status.ring = status:CreateTexture(nil, "ARTWORK")
  status.ring:SetTexture(S.MEDIA .. "Ring")
  status.ring:SetPoint("CENTER", status.dot)
  status.text = S.Text(status, 12, "text")
  status.text:SetPoint("LEFT", status.dot, "RIGHT", 8, 0)
  status.ring:Hide()
  content.status = status

  content.rank = infoLine(content, -100, L["Rank"])
  content.zone = infoLine(content, -120, L["Zone"])
  content.last = infoLine(content, -140, L["Last online"])

  content.note = noteBlock(content, L["Public note"], false)
  content.note:SetPoint("TOP", 0, -164)
  content.onote = noteBlock(content, L["Officer note"], true)
  content.onote:SetPoint("TOP", 0, -230)
  -- personal note: only on this computer
  content.pnote = noteBlock(content, L["Personal note"], false)
  content.pnote.edit:SetScript("OnClick", function() if current then ns.EditPersonalNote(current) end end)
  content.pnote.label:SetTextColor(0.68, 0.48, 1)
  content.pnote.body:SetHeight(28)
  -- favorite: a pop-up when this guildmate comes online
  content.fav = S.Check(content, nil, 16)
  content.fav:SetPoint("TOPRIGHT", -14, -16)
  content.fav:SetScript("OnClick", function(self)
    if current and (ns.IsFavorite(current) ~= (self:GetChecked() and true or false)) then ns.ToggleFavorite(current) end
  end)
  S.Tooltip(content.fav, { L["Favorite"], L["When a favorite guildmate comes online (right-click a member: Favorite)."] })

  -- actions (2 columns)
  local bw = math.floor((width - 28 - 8) / 2)
  local function btn(label, fn, style)
    return S.Button(content, label, bw, 24, function() fn(current) end, style)
  end
  content.whisper = btn(L["Whisper"], ns.Whisper)
  content.group = btn(L["Invite to group"], ns.GroupInvite)
  content.promote = btn(L["Promote"], ns.Promote)
  content.demote = btn(L["Demote"], ns.Demote)
  content.remove = btn(L["Remove"], ns.Remove, "danger")
  content.leader = btn(L["Make leader"], ns.MakeLeader)
  local grid = { { content.whisper, content.group }, { content.promote, content.demote }, { content.remove, content.leader } }
  for r, pair in ipairs(grid) do
    for c, b in ipairs(pair) do
      b:SetPoint("BOTTOMLEFT", content:GetParent(), "BOTTOMLEFT", 14 + (c - 1) * (bw + 8), 14 + (3 - r) * 30)
    end
  end
  S.Tooltip(content.promote, function()
    local ranks = ns.Ranks()
    return current and ns.CanPromote(current) and { L["Promote"], string.format(L["To: %s"], ranks[current.rankIndex - 1] or "") }
  end)
  S.Tooltip(content.demote, function()
    local ranks = ns.Ranks()
    return current and ns.CanDemote(current) and { L["Demote"], string.format(L["To: %s"], ranks[current.rankIndex + 1] or "") }
  end)

  local actions = S.Section(content, L["Actions"])
  actions:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 14 + 3 * 30 + 2)
  actions:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 14 + 3 * 30 + 2)
end

-- shows a member (nil: the guild summary); quiet = refresh without the slide animation
function ns.ShowMember(m, quiet)
  if not panel then return end
  local changed = (current and current.name) ~= (m and m.name)
  current = m
  if not m then
    content:Hide()
    if not empty:IsShown() or not quiet then
      empty:Show()
      refreshEmpty(not quiet)
      if not quiet then S.SlideIn(empty, 0, -8, 0.25) end
    else
      refreshEmpty(false)
    end
    return
  end
  empty:Hide()
  content:Show()

  local r, g, b = ns.ClassColor(m.classFile)
  ns.SetClassIcon(content.icon.tex, m.classFile)
  if changed then content.modelFor = nil end
  ns.RefreshPortrait()
  content.icon:SetBorderColor(r, g, b, 1)
  content.halo:SetVertexColor(r, g, b, 0.35)
  content.name:SetText(m.short)
  content.name:SetTextColor(r, g, b)
  S.FitText(content.name, 150, 16)
  content.sub:SetText(string.format(L["Level %d %s"], m.level, m.class))

  local st = content.status
  local sc = ({ online = C.good, afk = C.warn, dnd = C.bad })[m.status] or C.muted
  st.dot:SetVertexColor(color(sc))
  st.ring:SetVertexColor(color(sc))
  st.pulse = m.online
  local stText = ({ online = L["Online"], afk = L["Away"], dnd = L["Busy"] })[m.status]
    or string.format(L["Offline for %s"], ns.LastOnlineText(m))
  st.text:SetText(stText)
  st.text:SetTextColor(color(m.online and C.text or C.muted))

  content.rank:SetText(m.rank)
  content.rank:SetTextColor(color(C.gold))
  content.zone:SetText(m.zone ~= "" and m.zone or "-")
  content.last:SetText(ns.LastOnlineText(m))

  content.note.body:SetText(m.note ~= "" and m.note or ("|cff999999" .. L["(empty)"] .. "|r"))
  content.note.edit:SetShown(ns.Can.publicNote())
  local viewOfficer = ns.Can.viewOfficer()
  content.onote:SetShown(viewOfficer)
  content.onote.body:SetShown(viewOfficer)
  content.onote.body:SetText(m.onote ~= "" and m.onote or ("|cff999999" .. L["(empty)"] .. "|r"))
  content.onote.edit:SetShown(ns.Can.officerNote())
  local pn = ns.PersonalNote(m)
  content.pnote:ClearAllPoints()
  content.pnote:SetPoint("LEFT", 14, 0)
  content.pnote:SetPoint("RIGHT", -14, 0)
  content.pnote:SetPoint("TOP", 0, viewOfficer and -296 or -230)
  content.pnote.body:SetText(pn ~= "" and pn or ("|cff999999" .. L["Only you can see it."] .. "|r"))
  content.fav:SetChecked(ns.IsFavorite(m))
  content.fav:SetShown(not ns.IsMe(m))

  local me = ns.IsMe(m)
  content.whisper:SetEnabled(not me)
  content.group:SetEnabled(not me and m.online)
  content.promote:SetEnabled(ns.CanPromote(m) and true or false)
  content.demote:SetEnabled(ns.CanDemote(m) and true or false)
  content.remove:SetEnabled(ns.CanRemove(m) and true or false)
  content.leader:SetShown(ns.Can.leader())
  content.leader:SetEnabled(ns.CanMakeLeader(m) and true or false)

  if changed and not quiet then S.SlideIn(content, 12, 0, 0.25) end
end

-- 3D portrait ------------------------------------------------------------------------------------
-- the game only knows the look of players near you: a unit token that is this member, if any
function memberUnit(m)
  if ns.IsMe(m) then return "player" end
  local function same(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
    local name = UnitName(unit)
    return name == m.short and (not UnitIsVisible or UnitIsVisible(unit))
  end
  for _, u in ipairs({ "target", "mouseover", "focus" }) do
    if same(u) then return u end
  end
  if IsInRaid and IsInRaid() then
    for i = 1, 40 do if same("raid" .. i) then return "raid" .. i end end
  else
    for i = 1, 4 do if same("party" .. i) then return "party" .. i end end
  end
  for i = 1, 40 do if same("nameplate" .. i) then return "nameplate" .. i end end
end

-- loads the model; a hidden model ignores SetUnit, so it is shown first, and loaded again every
-- time it shows (the window closed and opened, another page and back)
function applyModel(model, unit)
  model:Show()
  model:ClearModel()
  model:SetUnit(unit)
  if model.SetPortraitZoom then model:SetPortraitZoom(1) end
  if model.SetCamDistanceScale then model:SetCamDistanceScale(1) end
  if model.SetPosition then model:SetPosition(0, 0, 0) end
end

-- shows the model once found; it stays for this member while the unit can be seen
function ns.RefreshPortrait()
  if not content or not current then return end
  local model, tex = content.model, content.icon.tex
  if content.modelFor ~= current.name then
    local unit = memberUnit(current)
    content.modelFor, content.modelUnit = unit and current.name, unit
  end
  local shown = content.modelFor == current.name
  tex:SetShown(not shown)
  if shown then applyModel(model, content.modelUnit) else model:Hide() end
end

local portraitEvents = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "GROUP_ROSTER_UPDATE",
  "NAME_PLATE_UNIT_ADDED", "PLAYER_FOCUS_CHANGED" }) do
  pcall(portraitEvents.RegisterEvent, portraitEvents, e)
end
portraitEvents:SetScript("OnEvent", function()
  if content and content:IsVisible() and current and content.modelFor ~= current.name then ns.RefreshPortrait() end
end)

ns.On("PNOTES", function() if current then ns.ShowMember(current, true) end end)
ns.On("FAVORITES", function() if current then ns.ShowMember(current, true) end end)
