-- Guild Enhanced Forever: board page: announcements written by the officers (guild master and the rank
-- right under), pinned ones first, with the message of the day on top. New announcements: a
-- pop-up and a counter on the tab until read. Shared with ns.Sync (collection "board").
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient
local Sync = ns.Sync

local PAGE = 3
local page, ui = nil, { cards = {} }
local me = UnitName("player")
ns.OnMyName(function(n) me = n end) -- full roster name once known

local CATS = {
  { "info", "Information", { "Interface\\Icons\\INV_Misc_Note_01" }, C.gold },
  { "raid", "Raid", { "Interface\\Icons\\INV_Misc_Head_Dragon_01" }, C.bad },
  { "rule", "Rules", { "Interface\\Icons\\INV_Misc_Book_11", "Interface\\Icons\\INV_Misc_Book_09" }, C.ring },
  { "fun", "Fun", { "Interface\\Icons\\INV_Misc_Gift_02", "Interface\\Icons\\INV_Misc_Toy_10" }, C.good },
}
local CAT = {}
for _, c in ipairs(CATS) do CAT[c[1]] = c end

local function canPost() return Sync.IsOfficer(me) end

local function nameLabel(name)
  local m = name and ns.byName[name]
  return m and ("|c" .. ns.ClassHex(m.classFile) .. name .. "|r") or ("|cffdddddd" .. (name or "?") .. "|r")
end

local function seen() return ns.GuildTable("boardSeen") end

local function posts()
  local list = Sync.All("board")
  table.sort(list, function(a, b)
    if (a.pin or false) ~= (b.pin or false) then return a.pin and true or false end
    return (a.at or a.v or 0) > (b.at or b.v or 0)
  end)
  return list
end

local function unread()
  local n, s = 0, seen()
  for _, p in ipairs(Sync.All("board")) do if p.by ~= me and s[p.id] ~= p.v then n = n + 1 end end
  return n
end
local function refreshBadge()
  local n = unread()
  ns.SetTabBadge(PAGE, n > 0 and tostring(n) or "")
end

Sync.Register("board", {
  keep = 14 * 86400,
  validate = function(rec) return Sync.IsOfficer(rec.ed) end,
  changed = function(rec, old)
    refreshBadge()
    if rec.del or rec.ed == me or not Sync.Started() or not ns.NotifyOpt("board") then return end
    if not old or old.text ~= rec.text then
      local c = CAT[rec.cat] or CAT.info
      ns.Notify({ icon = c[3], title = old and L["Announcement updated"] or L["New announcement"],
        text = "|cffffd100" .. (rec.title or "") .. "|r  ·  " .. nameLabel(rec.by), color = c[4],
        buttons = { { L["Read"], function() ns.OpenPage(PAGE) end, true } } })
    end
  end,
  ready = refreshBadge,
})

local function edit(post)
  local cats = {}
  for _, c in ipairs(CATS) do cats[#cats + 1] = { c[1], L[c[2]] } end
  S.Form({
    title = post and L["Edit the announcement"] or L["New announcement"], width = 500,
    accept = post and L["Save"] or L["Publish"],
    fields = {
      { key = "title", label = L["Title"], kind = "text", value = post and post.title, max = 70, required = true },
      { key = "cat", label = L["Category"], kind = "drop", value = post and post.cat or "info", options = cats },
      { key = "text", label = L["Text"], kind = "multi", value = post and post.text, max = 900, height = 150 },
      { key = "pin", label = L["Pinned"], kind = "check", value = post and post.pin,
        hint = L["Pinned announcements stay at the top."] },
    },
    onAccept = function(v, err)
      if v.text == "" then err(string.format(L["Please fill in: %s"], L["Text"])) return true end
      local rec = post and CopyTable(post) or { id = me .. "-" .. (GetServerTime or time)(), at = (GetServerTime or time)() }
      rec.title, rec.cat, rec.text, rec.pin, rec.del = v.title, v.cat, v.text, v.pin or nil, nil
      Sync.Put("board", rec)
      ns.RefreshBoard(true)
    end,
  })
end

-- Cards ------------------------------------------------------------------------------------------------
local function card(i)
  if ui.cards[i] then return ui.cards[i] end
  local c = CreateFrame("Frame", nil, ui.content)
  S.Rounded(c, 10, { 0.11, 0.08, 0.19, 0.95 }, { 0.05, 0.035, 0.09, 0.95 }, C.rule)
  c.band = c:CreateTexture(nil, "ARTWORK")
  c.band:SetPoint("TOPLEFT", 1, -1)
  c.band:SetPoint("BOTTOMLEFT", 1, 1)
  c.band:SetWidth(3)
  c.icon = S.Icon(c, 30)
  c.icon:SetPoint("TOPLEFT", 14, -12)
  c.title = S.Text(c, 15, "gold")
  c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, 0)
  c.title:SetPoint("RIGHT", -200, 0)
  c.meta = S.Text(c, 10, "muted")
  c.meta:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 10, 0)
  c.new = S.Text(c, 10, "good")
  c.new:SetPoint("LEFT", c.meta, "RIGHT", 8, 0)
  c.pin = c:CreateTexture(nil, "OVERLAY")
  c.pin:SetSize(16, 16)
  c.pin:SetPoint("TOPRIGHT", -12, -12)
  c.pin:SetTexture(S.PickIcon({ "Interface\\Icons\\INV_Misc_Ribbon_01", "Interface\\Icons\\INV_Misc_Note_02" }))
  c.pin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  c.text = S.Text(c, 12, "text")
  c.text:SetPoint("TOPLEFT", c.icon, "BOTTOMLEFT", 0, -10)
  c.text:SetPoint("RIGHT", -16, 0)
  c.text:SetWordWrap(true)
  c.text:SetJustifyV("TOP")
  c.text:SetSpacing(2)
  c.del = S.Button(c, L["Delete"], 70, 20, nil, "danger")
  c.del:SetPoint("TOPRIGHT", -36, -10)
  c.edit = S.Button(c, L["Edit"], 70, 20)
  c.edit:SetPoint("RIGHT", c.del, "LEFT", -6, 0)
  ui.cards[i] = c
  return c
end

function ns.RefreshBoard(animate)
  if not page then return end
  local list = posts()
  local y = 0
  local width = ui.content:GetWidth()
  -- message of the day first
  local motd = ns.GetMOTD()
  local items = {}
  if motd ~= "" then
    items[1] = { motd = true, title = L["Message of the day"], text = motd, cat = "info" }
  end
  for _, p in ipairs(list) do items[#items + 1] = p end
  local s = seen()
  for i, p in ipairs(items) do
    local c = card(i)
    local cat = CAT[p.cat] or CAT.info
    c.icon.tex:SetTexture(p.motd and ns.ICON or S.PickIcon(cat[3]))
    c.band:SetColorTexture(color(p.motd and C.gold or cat[4]))
    c.title:SetText(p.title or "")
    c.meta:SetText(p.motd and L["Guild"] or (L[cat[2]] .. "  ·  " .. nameLabel(p.by) .. "  ·  "
      .. ns.FormatDay(p.at or p.v) .. " " .. ns.FormatTime(p.at or p.v)))
    local isNew = not p.motd and p.by ~= me and s[p.id] ~= p.v
    c.new:SetText(isNew and L["New"] or "")
    c.pin:SetShown(p.pin and true or false)
    c.text:SetWidth(width - 32)
    c.text:SetText(p.text or "")
    local mine = not p.motd and canPost()
    c.edit:SetShown(mine)
    c.del:SetShown(mine)
    c.edit:SetScript("OnClick", function() edit(p) end)
    c.del:SetScript("OnClick", function()
      S.Dialog({ title = L["Delete"], text = string.format(L["Delete the announcement %s?"], "|cffffd100" .. (p.title or "") .. "|r"),
        accept = L["Delete"], danger = true, onAccept = function() Sync.Delete("board", p.id); ns.RefreshBoard() end })
    end)
    local h = 12 + 30 + 10 + c.text:GetStringHeight() + 16
    c:SetHeight(h)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", 0, -y)
    c:SetPoint("TOPRIGHT", 0, -y)
    c:SetBorderColor(color(isNew and C.gold or C.rule))
    c:Show()
    if animate and i <= 8 then S.SlideIn(c, 0, -10, 0.28, i * 0.04) end
    y = y + h + 10
  end
  for i = #items + 1, #ui.cards do ui.cards[i]:Hide() end
  ui.content:SetHeight(math.max(1, y))
  ui.empty:SetShown(#items == 0)
  ui.new:SetShown(canPost())
  ui.hint:SetText(canPost() and L["Your announcements are shared with the guildmates who have Guild Enhanced."]
    or L["Announcements are written by the officers."])
end

local function markRead()
  local s = seen()
  for _, p in ipairs(Sync.All("board")) do s[p.id] = p.v end
  refreshBadge()
end

local function build(p)
  page = p
  local title = S.Section(p, L["Announcements"])
  title:SetPoint("TOPLEFT")
  title:SetPoint("TOPRIGHT", -160, 0)
  ui.new = S.Button(p, L["New announcement"], 150, 22, function() edit() end, "primary")
  ui.new:SetPoint("TOPRIGHT")
  local box = CreateFrame("Frame", nil, p)
  box:SetPoint("TOPLEFT", 0, -32)
  box:SetPoint("BOTTOMRIGHT", 0, 22)
  local sf, content = S.Scroll(box)
  sf:SetPoint("TOPLEFT")
  sf:SetPoint("BOTTOMRIGHT", -12, 0)
  content:SetWidth(ns.PAGE_W - 14)
  ui.content = content
  ui.empty = S.Text(box, 13, "muted")
  ui.empty:SetPoint("CENTER")
  ui.empty:SetText(L["No announcement yet."])
  ui.hint = S.Text(p, 10, "muted")
  ui.hint:SetPoint("BOTTOMLEFT", 2, 4)
end

local function onShow()
  ns.RefreshBoard(true)
  -- read once seen for a moment
  C_Timer.After(1.5, function() if page and page:IsVisible() then markRead() end end)
end

ns.AddPage(PAGE, "Board", build, onShow, { "Interface\\Icons\\INV_Misc_Note_02", "Interface\\Icons\\INV_Scroll_03",
  "Interface\\Icons\\INV_Misc_Note_01" })

ns.On("SYNC_BOARD", function() if page and page:IsVisible() then ns.RefreshBoard() end end)
ns.On("GUILD", function() if page and page:IsVisible() then ns.RefreshBoard() end end)
