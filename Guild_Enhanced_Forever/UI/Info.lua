-- Guild Enhanced Forever: information page: message of the day, guild information text (both
-- editable with the right permissions), overview tiles and class composition
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local LEFT_W = 520
local page, motdBox, motdSave, info, infoSave, infoRevert, infoState, tiles, classRows

local function getInfoText() return GetGuildInfoText and GetGuildInfoText() or "" end
local function setInfoText(t) if SetGuildInfoText then SetGuildInfoText(t) end end

-- stat tile: big number that counts up, label under it
local function tile(parent, label, width)
  local t = CreateFrame("Frame", nil, parent)
  t:SetSize(width, 62)
  S.Card(t, 8)
  local shine = t:CreateTexture(nil, "BACKGROUND", nil, -6)
  shine:SetPoint("TOPLEFT", 1, -1); shine:SetPoint("BOTTOMRIGHT", -1, 1)
  shine:Hide()
  t.value = S.Text(t, 20, "gold")
  t.value:SetPoint("TOP", 0, -10)
  t.value:SetJustifyH("CENTER")
  t.label = S.Text(t, 10, "muted")
  t.label:SetPoint("BOTTOM", 0, 9)
  t.label:SetText(label)
  S.FitText(t.label, width - 6, 10)
  t.n = 0
  function t:Set(n, animate, delay)
    self.n = n
    if not n then self.value:SetText("?") return end
    if not animate then self.value:SetText(n) return end
    S.Tween(self.value, { dur = 0.9, delay = delay, from = 0, to = n, ease = "outCubic", set = function(v)
      self.value:SetText(math.floor(v + 0.5))
    end })
  end
  return t
end

local function refreshInfoButtons()
  local can = ns.Can.info()
  local dirty = can and info:GetText() ~= getInfoText()
  infoSave:SetShown(can)
  infoRevert:SetShown(can)
  infoSave:SetEnabled(dirty)
  infoRevert:SetEnabled(dirty)
  infoState:SetText(can and (dirty and ("|cffff8000" .. L["Unsaved changes"] .. "|r") or "") or L["Read only"])
end

local function refreshTexts(force)
  local canMotd = ns.Can.motd()
  if force or not motdBox.edit:HasFocus() then motdBox:SetText(ns.GetMOTD() or "") end
  motdBox.edit:EnableMouse(canMotd)
  motdBox.edit:EnableKeyboard(canMotd)
  motdBox:EnableMouse(canMotd)
  motdSave:SetShown(canMotd)
  motdBox:SetWidth(canMotd and (LEFT_W - 96) or LEFT_W)
  motdSave:SetEnabled((motdBox:GetText() or "") ~= (ns.GetMOTD() or ""))

  if force or not info.edit:HasFocus() then info:SetText(getInfoText()) end
  info:SetLocked(not ns.Can.info())
  refreshInfoButtons()
end

local function refreshStats(animate)
  local total, online, maxed, levels = #ns.members, 0, 0, 0
  local byClass, onlineByClass = {}, {}
  for _, m in ipairs(ns.members) do
    if m.online then online = online + 1 end
    if m.level >= (MAX_PLAYER_LEVEL or 60) then maxed = maxed + 1 end
    levels = levels + m.level
    if m.classFile then
      byClass[m.classFile] = (byClass[m.classFile] or 0) + 1
      if m.online then onlineByClass[m.classFile] = (onlineByClass[m.classFile] or 0) + 1 end
    end
  end
  local acc = ns.db.accounts
  tiles[1]:Set(acc and acc.guild == ns.GuildName() and acc.n or nil, animate, 0)
  tiles[2]:Set(total, animate, 0.05)
  tiles[3]:Set(online, animate, 0.1)
  tiles[4]:Set(maxed, animate, 0.15)
  tiles[5]:Set(total > 0 and math.floor(levels / total + 0.5) or 0, animate, 0.2)

  local most = 1
  for _, n in pairs(byClass) do if n > most then most = n end end
  for i, row in ipairs(classRows) do
    local n = byClass[row.class] or 0
    row.count:SetText(string.format("%d  |cff999999(%d %s)|r", n, onlineByClass[row.class] or 0, L["online"]))
    row.bar:SetMinMaxValues(0, most)
    row.bar:SetValue(n)
    if animate then row.bar:Replay(0.04 * i) end
  end
end

local function build(p)
  page = p

  -- message of the day
  local s1 = S.Section(p, L["Message of the day"])
  s1:SetPoint("TOPLEFT", 0, 0)
  s1:SetWidth(LEFT_W)
  motdBox = S.EditBox(p, LEFT_W - 96, 26, L["No message of the day."], function(t) ns.SetMOTD(t) end)
  motdBox:SetPoint("TOPLEFT", 0, -30)
  motdBox:SetMaxLetters(128)
  motdBox.onChange = function(t) motdSave:SetEnabled(t ~= (ns.GetMOTD() or "")) end
  motdSave = S.Button(p, L["Save"], 88, 26, function()
    ns.SetMOTD(motdBox:GetText())
    motdBox:ClearFocus()
  end, "primary")
  motdSave:SetPoint("LEFT", motdBox, "RIGHT", 8, 0)

  -- guild information
  local s2 = S.Section(p, L["Guild information"])
  s2:SetPoint("TOPLEFT", 0, -76)
  s2:SetWidth(LEFT_W)
  info = S.MultiEdit(p, 500)
  info:SetPoint("TOPLEFT", 0, -104)
  info:SetSize(LEFT_W, ns.PAGE_H - 104 - 40)
  info.onChange = function() refreshInfoButtons() end
  infoSave = S.Button(p, L["Save"], 100, 26, function()
    setInfoText(info:GetText())
    info.edit:ClearFocus()
    C_Timer.After(0.3, refreshInfoButtons)
  end, "primary")
  infoSave:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -8)
  infoRevert = S.Button(p, L["Revert"], 100, 26, function()
    info:SetText(getInfoText())
    refreshInfoButtons()
  end)
  infoRevert:SetPoint("LEFT", infoSave, "RIGHT", 8, 0)
  infoState = S.Text(p, 11, "muted")
  infoState:SetPoint("TOPRIGHT", info, "BOTTOMRIGHT", 0, -15)

  -- overview
  local rx = LEFT_W + 28
  local rw = ns.PAGE_W - rx
  local s3 = S.Section(p, L["Overview"])
  s3:SetPoint("TOPLEFT", rx, 0)
  s3:SetWidth(rw)
  -- accounts first: the real number of players (alts of the same account count once)
  local gap = 6
  local tw = math.floor((rw - 4 * gap) / 5)
  tiles = {
    tile(p, L["Accounts"], tw), tile(p, L["Members"], tw), tile(p, L["Online"], tw),
    tile(p, string.format(L["Level %d"], MAX_PLAYER_LEVEL or 60), tw), tile(p, L["Average level"], tw),
  }
  for i, t in ipairs(tiles) do t:SetPoint("TOPLEFT", rx + (i - 1) * (tw + gap), -30) end
  S.Tooltip(tiles[1], { L["Accounts"], L["The real number of players: the alts of the same account count once. Given by the server (/ginfo)."] })
  S.Tooltip(tiles[2], { L["Members"], L["Characters in the guild, alts included."] })

  -- classes
  local s4 = S.Section(p, L["Classes"])
  s4:SetPoint("TOPLEFT", rx, -108)
  s4:SetWidth(rw)
  classRows = {}
  for i, cls in ipairs(ns.CLASSES) do
    local y = -138 - (i - 1) * 28
    local row = CreateFrame("Frame", nil, p)
    row:SetPoint("TOPLEFT", rx, y)
    row:SetSize(rw, 24)
    row.class = cls
    local ic = row:CreateTexture(nil, "ARTWORK")
    ic:SetSize(18, 18)
    ic:SetPoint("LEFT")
    ns.SetClassIcon(ic, cls)
    local r, g, b = ns.ClassColor(cls)
    local name = S.Text(row, 12, "text")
    name:SetPoint("LEFT", ic, "RIGHT", 8, 0)
    name:SetWidth(90)
    name:SetText((LOCALIZED_CLASS_NAMES_MALE or {})[cls] or cls)
    name:SetTextColor(r, g, b)
    row.count = S.Text(row, 11, "text")
    row.count:SetPoint("RIGHT")
    row.count:SetJustifyH("RIGHT")
    row.bar = S.ProgressBar(row, 8, { math.min(1, r * 1.25), math.min(1, g * 1.25), math.min(1, b * 1.25), 1 },
      { r * 0.55, g * 0.55, b * 0.55, 1 })
    row.bar:SetPoint("LEFT", ic, "RIGHT", 104, 0)
    row.bar:SetPoint("RIGHT", -96, 0)
    classRows[i] = row
  end

  -- leave
  local leave = S.Button(p, L["Leave guild"], 130, 26, function() ns.LeaveGuild() end, "danger")
  leave:SetPoint("BOTTOMRIGHT", 0, 0)
  S.Tooltip(leave, function()
    return ns.Can.leader() and { L["Leave guild"], L["As guild master, you must give the leadership to someone else first."] }
  end)
  page.leave = leave
end

local function onShow()
  refreshTexts(true)
  refreshStats(true)
  page.leave:SetEnabled(not ns.Can.leader())
end

ns.AddPage(6, "Information", build, onShow, { "Interface\\Icons\\INV_Misc_Book_09", "Interface\\Icons\\INV_Misc_Book_11", "Interface\\Icons\\INV_Misc_Book_01" })

-- the accounts arrive later than the roster (answer to /ginfo)
function ns.RefreshOverview() if page and page:IsVisible() then refreshStats(false) end end

ns.On("GUILD", function() if page and page:IsVisible() then refreshTexts() end end)
ns.On("ROSTER", function() if page and page:IsVisible() then refreshStats(false); refreshTexts() end end)
