-- Guild Enhanced Forever: event log page: joins, departures, promotions, demotions, with filters
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local ROW_H = 26
local page, scroll, content, rows, pills, emptyText, filter = nil, nil, nil, {}, {}, nil, "all"

local KINDS = {
  invite  = { group = "join",    col = { 0.55, 0.75, 1 },    fmt = "GUILDEVENT_TYPE_INVITE",  en = "%s invites %s to the guild." },
  join    = { group = "join",    col = { 0.42, 0.86, 0.55 }, fmt = "GUILDEVENT_TYPE_JOIN",    en = "%s joins the guild." },
  promote = { group = "promote", col = { 0.96, 0.79, 0.36 }, fmt = "GUILDEVENT_TYPE_PROMOTE", en = "%s promotes %s to %s." },
  demote  = { group = "demote",  col = { 1, 0.6, 0.3 },      fmt = "GUILDEVENT_TYPE_DEMOTE",  en = "%s demotes %s to %s." },
  remove  = { group = "leave",   col = { 1, 0.42, 0.42 },    fmt = "GUILDEVENT_TYPE_REMOVE",  en = "%s kicks %s out of the guild." },
  quit    = { group = "leave",   col = { 0.85, 0.45, 0.55 }, fmt = "GUILDEVENT_TYPE_QUIT",    en = "%s has quit the guild." },
}
local FILTERS = {
  { "all", "All" }, { "join", "Joins" }, { "leave", "Departures" }, { "promote", "Promotions" }, { "demote", "Demotions" },
}

-- a name in its class color when the roster knows it
local function who(name)
  if not name or name == "" then return "?" end
  local m = ns.byName[name] or ns.byName[ns.Short(name)]
  if m then return "|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r" end
  return "|cffdddddd" .. ns.Short(name) .. "|r"
end

local function ago(e)
  if e.y > 0 then return string.format(L["%d y ago"], e.y) end
  if e.mo > 0 then return string.format(L["%d mo ago"], e.mo) end
  if e.d > 0 then return string.format(L["%d d ago"], e.d) end
  if e.h > 0 then return string.format(L["%d h ago"], e.h) end
  return L["just now"]
end

local function describe(e)
  local k = KINDS[e.kind]
  local fmt = k and (_G[k.fmt] or k.en) or "%s %s"
  local rank = e.rank and ("|cffffd100" .. e.rank .. "|r") or ""
  if e.kind == "join" or e.kind == "quit" then return string.format(fmt, who(e.p1)) end
  if e.kind == "promote" or e.kind == "demote" then return string.format(fmt, who(e.p1), who(e.p2), rank) end
  return string.format(fmt, who(e.p1), who(e.p2))
end

local function row(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, content)
  r:SetHeight(ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
  r:EnableMouse(true)
  local stripe = r:CreateTexture(nil, "BACKGROUND", nil, -2)
  stripe:SetAllPoints()
  stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
  S.RowHighlight(r)
  r.dot = r:CreateTexture(nil, "ARTWORK")
  r.dot:SetTexture(S.MEDIA .. "Dot")
  r.dot:SetSize(8, 8)
  r.dot:SetPoint("LEFT", 10, 0)
  r.glow = r:CreateTexture(nil, "BACKGROUND")
  r.glow:SetTexture(S.MEDIA .. "Glow")
  r.glow:Hide()
  r.glow:SetBlendMode("ADD")
  r.glow:SetSize(22, 22)
  r.glow:SetPoint("CENTER", r.dot)
  r.text = S.Text(r, 12, "text")
  r.text:SetPoint("LEFT", r.dot, "RIGHT", 10, 0)
  r.text:SetPoint("RIGHT", -110, 0)
  r.time = S.Text(r, 11, "muted")
  r.time:SetPoint("RIGHT", -10, 0)
  r.time:SetJustifyH("RIGHT")
  rows[i] = r
  return r
end

local function refresh(animate)
  if not page then return end
  local list = ns.ScanLog()
  local n = 0
  for _, e in ipairs(list) do
    local k = KINDS[e.kind]
    if filter == "all" or (k and k.group == filter) then
      n = n + 1
      local r = row(n)
      local col = k and k.col or { 0.7, 0.7, 0.7 }
      r.dot:SetVertexColor(col[1], col[2], col[3], 1)
      r.glow:SetVertexColor(col[1], col[2], col[3], 0.5)
      r.text:SetText(describe(e))
      r.time:SetText(ago(e))
      r:Show()
      if animate and n <= 20 then
        r:SetAlpha(0)
        S.Tween(r, { dur = 0.25, delay = (n - 1) * 0.02, from = 0, to = 1, set = function(v) r:SetAlpha(v) end })
      else
        r:SetAlpha(1)
      end
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math.max(1, n * ROW_H))
  emptyText:SetShown(n == 0)
  page.count:SetText(string.format(L["%d events"], n))
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

  local refreshBtn = S.Button(p, L["Refresh"], 100, 22, function() ns.RequestLog() end)
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
  emptyText:SetText(L["No event."])
end

local function onShow()
  ns.RequestLog()
  refresh(true)
end

ns.AddPage(8, "Event log", build, onShow, { "Interface\\Icons\\INV_Scroll_03", "Interface\\Icons\\INV_Scroll_08", "Interface\\Icons\\INV_Misc_Note_02" })

ns.On("LOG", function() if page and page:IsVisible() then refresh(false) end end)
