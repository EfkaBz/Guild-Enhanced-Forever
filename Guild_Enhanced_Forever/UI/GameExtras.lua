-- Guild Enhanced Forever: mini-games leaderboard and tournaments.
--   Leaderboard: everyone's record (matches against guildmates only, not the bot), shared with
--   ns.Sync (collection "gstats", one record per player). 3 points a win, 1 a draw.
--   Tournaments: a guildmate creates one (game, 4 or 8 players), the others join, the organizer
--   starts it: the bracket is drawn. Each match is a normal challenge; the result is reported by
--   itself at the end of the match (collections "tourney", "tjoin", "tres").
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient
local Sync = ns.Sync
local now = GetServerTime or time
local me = UnitName("player")

local function nameLabel(name)
  local m = name and ns.byName[name]
  return m and ("|c" .. ns.ClassHex(m.classFile) .. name .. "|r") or ("|cffdddddd" .. (name or "?") .. "|r")
end
local function gameName(id) local d = ns.gameDefs[id]; return d and L[d.name] or id end

-- Leaderboard ------------------------------------------------------------------------------------------------
Sync.Register("gstats", {
  keep = 60 * 86400,
  validate = function(rec) return rec.id == rec.ed and type(rec.s) == "table" end,
  ready = function() ns.ShareGameStats() end,
})

local sharePending
function ns.ShareGameStats()
  if sharePending then return end
  sharePending = true
  C_Timer.After(3, function()
    sharePending = nil
    if not Sync.Started() then return end
    local st = ns.db.gameStats or {}
    local s = {}
    for game, r in pairs(st) do
      if (r.w or 0) + (r.l or 0) + (r.d or 0) > 0 then s[game] = { r.w or 0, r.l or 0, r.d or 0 } end
    end
    if not next(s) then return end
    local old = Sync.Get("gstats", me)
    if old and ns.Net.Encode(old.s) == ns.Net.Encode(s) then return end
    Sync.Put("gstats", { id = me, s = s })
  end)
end

local lb = { rows = {}, game = "all" }

local function standings(game)
  local list = {}
  for _, rec in ipairs(Sync.All("gstats")) do
    if ns.byName[rec.id] then
      local w, l, d = 0, 0, 0
      for g, r in pairs(rec.s or {}) do
        if game == "all" or g == game then w, l, d = w + (r[1] or 0), l + (r[2] or 0), d + (r[3] or 0) end
      end
      if w + l + d > 0 then list[#list + 1] = { who = rec.id, w = w, l = l, d = d, pts = w * 3 + d, s = rec.s } end
    end
  end
  table.sort(list, function(a, b)
    if a.pts ~= b.pts then return a.pts > b.pts end
    if a.w ~= b.w then return a.w > b.w end
    return a.who < b.who
  end)
  return list
end

function ns.BuildLeaderboard(v)
  lb.view = v
  local opts = { { "all", L["All games"] } }
  for _, d in ipairs(ns.gameOrder) do opts[#opts + 1] = { d.id, L[d.name] } end
  local drop = S.Dropdown(v, 170, opts, function() return lb.game end, function(val) lb.game = val; v.Refresh(true) end)
  drop:SetPoint("TOPRIGHT", -16, 0)
  local head = CreateFrame("Frame", nil, v)
  head:SetPoint("TOPLEFT", 16, -32)
  head:SetPoint("TOPRIGHT", -16, -32)
  head:SetHeight(18)
  local function col(text, x, right)
    local fs = S.Text(head, 10, "muted")
    if right then fs:SetPoint("RIGHT", x, 0); fs:SetJustifyH("RIGHT") else fs:SetPoint("LEFT", x, 0) end
    fs:SetText(text)
  end
  col("#", 4); col(L["Name"], 36); col(L["Won"], -180, true); col(L["Lost"], -130, true); col(L["Draw"], -80, true)
  col(L["Points"], -8, true)
  local box = CreateFrame("Frame", nil, v)
  box:SetPoint("TOPLEFT", 16, -52)
  box:SetPoint("BOTTOMRIGHT", -16, 30)
  local sf, content = S.Scroll(box)
  sf:SetPoint("TOPLEFT")
  sf:SetPoint("BOTTOMRIGHT", -12, 0)
  content:SetWidth(ns.PAGE_W - 290 - 16 - 32 - 14)
  lb.content = content
  local empty = S.Text(box, 12, "muted")
  empty:SetPoint("TOP", 0, -30)
  empty:SetText(L["No match played yet."])
  local hint = S.Text(v, 10, "muted")
  hint:SetPoint("BOTTOMLEFT", 16, 10)
  hint:SetText(L["Matches between guildmates who have Guild Enhanced (not against the bot). Win 3 points, draw 1."])

  function v.Refresh(animate)
    local list = standings(lb.game)
    for i, e in ipairs(list) do
      local r = lb.rows[i]
      if not r then
        r = CreateFrame("Button", nil, content)
        r:SetHeight(24)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * 24)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        S.RowHighlight(r)
        r.medal = r:CreateTexture(nil, "BACKGROUND")
        r.medal:SetAllPoints()
        r.pos = S.Text(r, 12, "dim"); r.pos:SetPoint("LEFT", 4, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 30, 0)
        r.name = S.Text(r, 12, "text"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.w = S.Text(r, 12, "good"); r.w:SetPoint("RIGHT", -180, 0); r.w:SetJustifyH("RIGHT")
        r.l = S.Text(r, 12, "bad"); r.l:SetPoint("RIGHT", -130, 0); r.l:SetJustifyH("RIGHT")
        r.d = S.Text(r, 12, "dim"); r.d:SetPoint("RIGHT", -80, 0); r.d:SetJustifyH("RIGHT")
        r.pts = S.Text(r, 13, "gold"); r.pts:SetPoint("RIGHT", -8, 0); r.pts:SetJustifyH("RIGHT")
        r:SetScript("OnClick", function(self, button)
          local m = ns.byName[self.who]
          if m and button == "RightButton" then ns.MemberMenu(self, m) elseif m then ns.Whisper(m) end
        end)
        S.Tooltip(r, function()
          local lines = { r.who }
          for _, d in ipairs(ns.gameOrder) do
            local s = r.s and r.s[d.id]
            if s then lines[#lines + 1] = string.format("%s:  |cff1eff00%d|r / |cffff2020%d|r / |cffbbbbbb%d|r", L[d.name], s[1], s[2], s[3]) end
          end
          return lines
        end)
        lb.rows[i] = r
      end
      local m = ns.byName[e.who]
      r.who, r.s = e.who, e.s
      local medal = ({ C.gold, { 0.8, 0.82, 0.9, 1 }, { 0.85, 0.55, 0.3, 1 } })[i]
      if medal then
        gradient(r.medal, { medal[1], medal[2], medal[3], 0.22 }, { medal[1], medal[2], medal[3], 0 }, true)
        r.medal:Show()
      else
        r.medal:Hide()
      end
      r.pos:SetText(i)
      ns.SetClassIcon(r.icon, m and m.classFile)
      r.name:SetText(e.who)
      r.name:SetTextColor(ns.ClassColor(m and m.classFile))
      r.w:SetText(e.w); r.l:SetText(e.l); r.d:SetText(e.d); r.pts:SetText(e.pts)
      r:Show()
      if animate and i <= 14 then
        r:SetAlpha(0)
        S.Tween(r, { dur = 0.22, delay = i * 0.025, from = 0, to = 1, set = function(a) r:SetAlpha(a) end })
      else
        r:SetAlpha(1)
      end
    end
    for i = #list + 1, #lb.rows do lb.rows[i]:Hide() end
    content:SetHeight(math.max(1, #list * 24))
    empty:SetShown(#list == 0)
  end
end

-- Tournaments ----------------------------------------------------------------------------------------------------
local function isOrganizer(t) return t and (t.by == me or Sync.IsOfficer(me)) end

Sync.Register("tourney", {
  keep = 14 * 86400,
  expired = function(r, t) return (r.at or r.v or 0) < t - 30 * 86400 end,
  validate = function(rec, old)
    if not old then return ns.byName[rec.ed or ""] ~= nil end
    return rec.ed == old.by or Sync.IsOfficer(rec.ed)
  end,
  changed = function(rec, old)
    if not old and not rec.del and rec.by ~= me and Sync.Started() and ns.NotifyOpt("events") then
      ns.Notify({ icon = { "Interface\\Icons\\INV_Misc_Trophy_01", "Interface\\Icons\\INV_Misc_Ribbon_01" },
        title = L["New tournament"], text = string.format("%s  ·  %s  ·  %s", rec.title or "", gameName(rec.game), nameLabel(rec.by)),
        buttons = { { L["View"], function() ns.OpenPage(ns.PAGE_GAMES); ns.GameView("tourney") end, true } } })
    end
  end,
})
Sync.Register("tjoin", {
  keep = 14 * 86400,
  expired = function(r, t) return (r.v or 0) < t - 30 * 86400 end,
  validate = function(rec) return rec.ed == rec.who end,
})
Sync.Register("tres", {
  keep = 14 * 86400,
  expired = function(r, t) return (r.v or 0) < t - 30 * 86400 end,
  validate = function(rec)
    local tour = Sync.Get("tourney", rec.t or "")
    return tour ~= nil and (rec.ed == rec.a or rec.ed == rec.b or rec.ed == tour.by or Sync.IsOfficer(rec.ed))
  end,
})

local function entrants(tid)
  local list = {}
  for _, j in ipairs(Sync.All("tjoin")) do if j.t == tid then list[#list + 1] = j end end
  table.sort(list, function(a, b) return (a.v or 0) < (b.v or 0) end)
  return list
end

-- the bracket: rounds[r][k] = { a, b, w }; an empty seat is a bye (the other one goes through)
local function bracket(t)
  local size, players = t.size or 8, t.players or {}
  local rounds, r = { {} }, 1
  for k = 1, size / 2 do
    local a, b = players[2 * k - 1], players[2 * k]
    rounds[1][k] = { a = a, b = b, byeA = not a, byeB = not b, empty = not a and not b }
  end
  while true do
    for k, mt in ipairs(rounds[r]) do
      local res = Sync.Get("tres", t.id .. ":" .. r .. ":" .. k)
      if res and mt.a and mt.b and (res.w == mt.a or res.w == mt.b) then mt.w = res.w
      elseif mt.a and not mt.b and mt.byeB then mt.w = mt.a
      elseif mt.b and not mt.a and mt.byeA then mt.w = mt.b end
    end
    if #rounds[r] <= 1 then break end
    local nextR = {}
    for k = 1, #rounds[r] / 2 do
      local x, y = rounds[r][2 * k - 1], rounds[r][2 * k]
      nextR[k] = { a = x.w, b = y.w, byeA = x.empty, byeB = y.empty, empty = x.empty and y.empty }
    end
    r = r + 1
    rounds[r] = nextR
  end
  return rounds
end

-- my match to play (round, slot, opponent)
local function myMatch(t)
  if not t or t.st ~= "run" then return end
  for r, list in ipairs(bracket(t)) do
    for k, mt in ipairs(list) do
      if not mt.w and mt.a and mt.b and (mt.a == me or mt.b == me) then return r, k, mt.a == me and mt.b or mt.a end
    end
  end
end

-- end of a match against a guildmate: a tournament match? (both players report the same thing)
function ns.TourneyReport(m, result)
  if not Sync.Started() or not m or m.bot then return end
  local winner = (result == "win" or result == "left") and me or result == "lose" and m.oppShort or nil
  if not winner then return end -- a draw: the match is played again
  for _, t in ipairs(Sync.All("tourney")) do
    if t.game == m.game then
      local r, k, opp = myMatch(t)
      if r and opp == m.oppShort then
        local mt = bracket(t)[r][k]
        Sync.Put("tres", { id = t.id .. ":" .. r .. ":" .. k, t = t.id, a = mt.a, b = mt.b, w = winner })
        ns.Print(string.format(L["Tournament %s: result recorded."], "|cffffd100" .. (t.title or "") .. "|r"))
        return
      end
    end
  end
end

local tv = { selected = nil, rows = {}, boxes = {} }

local function createTourney()
  local games = {}
  for _, d in ipairs(ns.gameOrder) do games[#games + 1] = { d.id, L[d.name] } end
  S.Form({
    title = L["New tournament"], width = 440, accept = L["Create"],
    fields = {
      { key = "title", label = L["Title"], kind = "text", max = 40, required = true, placeholder = L["Spring cup..."] },
      { key = "game", label = L["Game"], kind = "drop", value = ns.gameOrder[1] and ns.gameOrder[1].id, options = games },
      { key = "size", label = L["Players"], kind = "drop", value = 8, options = { { 4, "4" }, { 8, "8" } } },
    },
    onAccept = function(v)
      local rec = { id = me .. "-" .. now(), title = v.title, game = v.game, size = v.size, st = "open", at = now() }
      Sync.Put("tourney", rec)
      Sync.Put("tjoin", { id = rec.id .. "@" .. me, t = rec.id, who = me })
      tv.selected = rec.id
      if tv.view then tv.view.Refresh(true) end
    end,
  })
end

local function startTourney(t)
  local list = entrants(t.id)
  local players = {}
  for _, j in ipairs(list) do if #players < t.size then players[#players + 1] = j.who end end
  if #players < 2 then ns.Print(L["At least 2 players are needed."]) return end
  -- shuffled, byes spread over the bracket
  for i = #players, 2, -1 do local j = math.random(i); players[i], players[j] = players[j], players[i] end
  local seats = {}
  local n = #players
  for k = 1, t.size / 2 do
    seats[2 * k - 1] = players[k]
  end
  local idx = t.size / 2 + 1
  for k = 1, t.size / 2 do
    if idx <= n then seats[2 * k] = players[idx]; idx = idx + 1 end
  end
  local copy = CopyTable(t)
  copy.players, copy.st = seats, "run"
  Sync.Put("tourney", copy)
end

function ns.BuildTourneys(v)
  tv.view = v
  local create = S.Button(v, L["New tournament"], 150, 22, createTourney, "primary")
  create:SetPoint("TOPRIGHT", -16, 0)
  local listBox = CreateFrame("Frame", nil, v)
  listBox:SetPoint("TOPLEFT", 16, -30)
  listBox:SetPoint("TOPRIGHT", -16, -30)
  listBox:SetHeight(96)
  S.Box(listBox, { 0.03, 0.02, 0.05, 0.6 }, C.rule)
  local sf, content = S.Scroll(listBox)
  sf:SetPoint("TOPLEFT", 4, -4)
  sf:SetPoint("BOTTOMRIGHT", -12, 4)
  content:SetWidth(ns.PAGE_W - 290 - 16 - 32 - 32 - 16)
  tv.content = content
  local empty = S.Text(listBox, 12, "muted")
  empty:SetPoint("CENTER")
  empty:SetText(L["No tournament. Create one!"])

  local title = S.Section(v, "")
  title:SetPoint("TOPLEFT", 16, -136)
  title:SetPoint("TOPRIGHT", -16, -136)
  local area = CreateFrame("Frame", nil, v)
  area:SetPoint("TOPLEFT", 16, -164)
  area:SetPoint("BOTTOMRIGHT", -16, 40)
  local champion = S.Text(v, 15, "gold")
  champion:SetPoint("BOTTOM", area, "BOTTOM", 0, 4)
  champion:SetJustifyH("CENTER")
  local bJoin = S.Button(v, "", 110, 24)
  bJoin:SetPoint("BOTTOMLEFT", 16, 10)
  local bStart = S.Button(v, L["Start"], 100, 24, nil, "primary")
  bStart:SetPoint("LEFT", bJoin, "RIGHT", 6, 0)
  local bPlay = S.Button(v, L["Play my match"], 150, 24, nil, "primary")
  bPlay:SetPoint("LEFT", bStart, "RIGHT", 6, 0)
  local bDel = S.Button(v, L["Delete"], 80, 24, nil, "danger")
  bDel:SetPoint("BOTTOMRIGHT", -16, 10)
  local info = S.Text(v, 11, "muted")
  info:SetPoint("LEFT", bPlay, "RIGHT", 10, 0)
  info:SetPoint("RIGHT", bDel, "LEFT", -10, 0)

  local function box(i)
    if tv.boxes[i] then return tv.boxes[i] end
    local b = CreateFrame("Frame", nil, area)
    b:SetSize(140, 40)
    S.Rounded(b, 6, { 0.11, 0.08, 0.19, 1 }, { 0.06, 0.04, 0.1, 1 }, C.rule)
    b.a = S.Text(b, 11, "text"); b.a:SetPoint("TOPLEFT", 8, -5); b.a:SetWidth(124)
    b.b = S.Text(b, 11, "text"); b.b:SetPoint("BOTTOMLEFT", 8, 5); b.b:SetWidth(124)
    local mid = b:CreateTexture(nil, "ARTWORK")
    mid:SetPoint("LEFT", 6, 0); mid:SetPoint("RIGHT", -6, 0); mid:SetHeight(1)
    mid:SetColorTexture(color(C.rule))
    b.link = area:CreateTexture(nil, "BACKGROUND")
    b.link:SetColorTexture(color(C.ring, 0.5))
    tv.boxes[i] = b
    return b
  end

  function v.Refresh(animate)
    local list = Sync.All("tourney")
    table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
    local sel
    for i, t in ipairs(list) do
      local r = tv.rows[i]
      if not r then
        r = CreateFrame("Button", nil, content)
        r:SetHeight(22)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * 22)
        S.RowHighlight(r)
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints()
        S.Highlight(r.sel, 0.2)
        r.text = S.Text(r, 12, "text"); r.text:SetPoint("LEFT", 6, 0)
        r.state = S.Text(r, 11, "muted"); r.state:SetPoint("RIGHT", -6, 0); r.state:SetJustifyH("RIGHT")
        r:SetScript("OnClick", function(self) tv.selected = self.tid; v.Refresh(true) end)
        tv.rows[i] = r
      end
      r.tid = t.id
      if not tv.selected then tv.selected = t.id end
      if t.id == tv.selected then sel = t end
      r.text:SetText("|cffffd100" .. (t.title or "") .. "|r  ·  " .. gameName(t.game) .. "  ·  " .. nameLabel(t.by))
      r.state:SetText(t.st == "open" and string.format(L["Sign-ups: %d / %d"], #entrants(t.id), t.size or 8)
        or L["In progress"])
      r.sel:SetShown(t.id == tv.selected)
      r:Show()
    end
    for i = #list + 1, #tv.rows do tv.rows[i]:Hide() end
    content:SetHeight(math.max(1, #list * 22))
    empty:SetShown(#list == 0)
    if not sel and list[1] then sel = list[1]; tv.selected = sel.id end

    for _, b in ipairs(tv.boxes) do b:Hide(); b.link:Hide() end
    champion:SetText("")
    for _, b in ipairs({ bJoin, bStart, bPlay, bDel }) do b:Hide() end
    info:SetText("")
    title.label:SetText(sel and (sel.title or "") or "")
    title.right:SetText(sel and gameName(sel.game) or "")
    if not sel then return end
    bDel:SetShown(isOrganizer(sel))
    bDel:SetScript("OnClick", function()
      S.Dialog({ title = L["Delete"], text = string.format(L["Delete the tournament %s?"], "|cffffd100" .. (sel.title or "") .. "|r"),
        accept = L["Delete"], danger = true, onAccept = function() Sync.Delete("tourney", sel.id); tv.selected = nil; v.Refresh() end })
    end)

    if sel.st == "open" then
      local ents = entrants(sel.id)
      local joined = Sync.Get("tjoin", sel.id .. "@" .. me) ~= nil
      bJoin:Show()
      bJoin:SetText(joined and L["Leave"] or L["Join"])
      bJoin:SetEnabled(joined or #ents < (sel.size or 8))
      bJoin:SetScript("OnClick", function()
        if joined then Sync.Delete("tjoin", sel.id .. "@" .. me)
        else Sync.Put("tjoin", { id = sel.id .. "@" .. me, t = sel.id, who = me }) end
        v.Refresh()
      end)
      bStart:SetShown(isOrganizer(sel))
      bStart:SetEnabled(#ents >= 2)
      bStart:SetScript("OnClick", function() startTourney(sel); v.Refresh(true) end)
      -- the players signed up, in a grid
      for i, j in ipairs(ents) do
        local b = box(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ((i - 1) % 4) * 146, -math.floor((i - 1) / 4) * 48)
        b.a:SetText(nameLabel(j.who))
        b.b:SetText("")
        b:SetBorderColor(color(j.who == me and C.gold or C.rule))
        b:Show()
        if animate then S.SlideIn(b, 0, -6, 0.2, i * 0.03) end
      end
      info:SetText(string.format(L["Sign-ups: %d / %d"], #ents, sel.size or 8))
      return
    end

    -- bracket
    local rounds = bracket(sel)
    local n = 0
    local colW = (area:GetWidth() > 0 and area:GetWidth() or 540) / #rounds
    local H = area:GetHeight() > 0 and area:GetHeight() - 30 or 240
    local pos = {}
    for r, list in ipairs(rounds) do
      pos[r] = {}
      for k, mt in ipairs(list) do
        n = n + 1
        local b = box(n)
        local slotH = H / #list
        local y = -(k - 1) * slotH - slotH / 2 + 20
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", (r - 1) * colW, y)
        pos[r][k] = { x = (r - 1) * colW, y = y }
        local function who(name, waiting)
          if not name then return waiting and "|cff999999…|r" or "|cff999999—|r" end
          local label = nameLabel(name)
          if mt.w == name then return label .. "  |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t" end
          if mt.w and mt.w ~= name then return "|cff999999" .. name .. "|r" end
          return label
        end
        b.a:SetText(who(mt.a, not mt.byeA))
        b.b:SetText(who(mt.b, not mt.byeB))
        local mine = (mt.a == me or mt.b == me) and not mt.w
        b:SetBorderColor(color(mine and C.gold or mt.w and C.ring or C.rule))
        b:Show()
        if r > 1 then
          b.link:ClearAllPoints()
          b.link:SetPoint("RIGHT", b, "LEFT", 0, 0)
          b.link:SetSize(colW - 140, 1)
          b.link:Show()
        end
        if animate then S.SlideIn(b, -8, 0, 0.22, n * 0.03) end
      end
    end
    local final = rounds[#rounds][1]
    if final and final.w then
      champion:SetText(string.format(L["Champion: %s"], nameLabel(final.w)))
      S.Tween(champion, { dur = 0.5, from = 0, to = 1, ease = "outBack", set = function(a) champion:SetAlpha(math.min(1, a)) end })
    end
    local r, _, opp = myMatch(sel)
    bPlay:SetShown(r ~= nil)
    if r then
      local m = ns.byName[opp]
      bPlay:SetEnabled(m and m.online or false)
      bPlay:SetScript("OnClick", function() ns.Challenge(sel.game, m and m.name or opp) end)
      info:SetText(string.format(L["Your match: against %s"], nameLabel(opp)) .. ((m and m.online) and "" or ("  ·  " .. L["offline"])))
    end
  end
end

local function later()
  if tv.view and tv.view:IsVisible() then tv.view.Refresh(false) end
end
ns.On("SYNC_TOURNEY", later)
ns.On("SYNC_TJOIN", later)
ns.On("SYNC_TRES", later)
ns.On("SYNC_GSTATS", function() if lb.view and lb.view:IsVisible() then lb.view.Refresh(false) end end)
