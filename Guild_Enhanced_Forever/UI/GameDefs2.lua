-- Guild Enhanced Forever: more mini-games: five in a row, battleship, WoW quiz, dice race.
-- Same contract as UI\GameDefs.lua: id, name, desc, icon, Build(frame), Start(match),
-- OnMove(match, data, mine), IsMyTurn(match), Mark(match, mine), BotMove(match).
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient
local WHITE, MEDIA = S.WHITE, S.MEDIA

local P1 = { 1, 0.80, 0.32 }   -- gold
local P2 = { 0.41, 0.8, 0.94 }  -- blue
local HIT = { 1, 0.36, 0.32 }
local MISS = { 0.55, 0.52, 0.65 }

local function myNum(m) return m.first and 1 or 2 end
local function dotMark(col)
  return string.format("|T%sDot:12:12:0:0:64:64:0:64:0:64:%d:%d:%d|t", MEDIA,
    math.floor(col[1] * 255), math.floor(col[2] * 255), math.floor(col[3] * 255))
end

local function popIn(key, setSize, full, delay)
  setSize(0.01)
  S.Tween(key, { dur = 0.35, delay = delay, from = 0, to = 1, ease = "outBack", set = function(v)
    setSize(math.max(0.01, full * v))
  end })
end

local function pulse(textures)
  local d = CreateFrame("Frame")
  local clock = 0
  d:SetScript("OnUpdate", function(self, e)
    clock = clock + e
    for _, t in ipairs(textures) do t:SetAlpha(0.55 + 0.45 * math.sin(clock * 6)) end
    if clock > 3 then
      for _, t in ipairs(textures) do t:SetAlpha(1) end
      self:SetScript("OnUpdate", nil)
    end
  end)
end

-- a deterministic random generator: both players get the same sequence from the match id
local function seeded(id)
  local s = (tonumber(id) or 12345) % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(n)
    s = (s * 16807) % 2147483647
    return (s % n) + 1
  end
end

-- Five in a row ---------------------------------------------------------------------------------------------
do
  local G = { id = "gomoku", name = "Five in a row", desc = "Line up five stones on a big board.",
    icon = { "Interface\\Icons\\INV_Misc_Gem_Pearl_04", "Interface\\Icons\\INV_Misc_Gem_Pearl_05" } }
  local N, CELL = 13, 29
  local cells = {}
  local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }

  function G.IsMyTurn(m) return m.turn == myNum(m) end
  function G.Mark(m, mine) return dotMark((mine and myNum(m) or 3 - myNum(m)) == 1 and P1 or P2) end

  local function at(b, x, y)
    if x < 1 or y < 1 or x > N or y > N then return -1 end
    return b[(y - 1) * N + x]
  end

  -- the stones of a line through (x, y) in a direction, and how many ends are open
  local function line(b, x, y, dx, dy, who)
    local n, open, cellsOf = 1, 0, { (y - 1) * N + x }
    for s = -1, 1, 2 do
      local k = 1
      while at(b, x + dx * k * s, y + dy * k * s) == who do
        n = n + 1
        cellsOf[#cellsOf + 1] = (y + dy * k * s - 1) * N + x + dx * k * s
        k = k + 1
      end
      if at(b, x + dx * k * s, y + dy * k * s) == nil then open = open + 1 end
    end
    return n, open, cellsOf
  end

  local function score(b, x, y, who)
    local total = 0
    for _, d in ipairs(DIRS) do
      local n, open = line(b, x, y, d[1], d[2], who)
      if n >= 5 then total = total + 100000
      elseif n == 4 then total = total + (open == 2 and 10000 or open == 1 and 1000 or 0)
      elseif n == 3 then total = total + (open == 2 and 1000 or open == 1 and 100 or 0)
      elseif n == 2 then total = total + (open == 2 and 100 or open == 1 and 10 or 0)
      else total = total + open end
    end
    return total
  end

  -- the bot: attack and defence scores around the stones; sometimes not the best move
  function G.BotMove(m)
    local b, bot, me = m.board, 3 - myNum(m), myNum(m)
    if not next(b) then return math.floor(N * N / 2) + 1 end
    local list = {}
    for y = 1, N do
      for x = 1, N do
        local i = (y - 1) * N + x
        if not b[i] then
          local near = false
          for dy = -2, 2 do for dx = -2, 2 do
            local v = at(b, x + dx, y + dy)
            if v and v ~= -1 then near = true end
          end end
          if near then
            b[i] = bot
            local a = score(b, x, y, bot)
            b[i] = me
            local d = score(b, x, y, me)
            b[i] = nil
            list[#list + 1] = { i = i, s = a * 1.1 + d + math.random() }
          end
        end
      end
    end
    table.sort(list, function(p, q) return p.s > q.s end)
    if #list == 0 then return end
    -- a winning or saving move is always played; otherwise one of the best three now and then
    if list[1].s < 9000 and math.random() < 0.25 then return list[math.random(math.min(3, #list))].i end
    return list[1].i
  end

  function G.Build(f)
    local grid = CreateFrame("Frame", nil, f)
    grid:SetSize(N * CELL + 8, N * CELL + 8)
    grid:SetPoint("CENTER")
    S.Rounded(grid, 10, { 0.16, 0.12, 0.24, 1 }, { 0.08, 0.06, 0.13, 1 }, C.trim)
    for i = 1, N * N do
      local x, y = (i - 1) % N, math.floor((i - 1) / N)
      local c = CreateFrame("Button", nil, grid)
      c:SetSize(CELL, CELL)
      c:SetPoint("TOPLEFT", 4 + x * CELL, -4 - y * CELL)
      local h = c:CreateTexture(nil, "BACKGROUND")
      h:SetColorTexture(color(C.ring, 0.35))
      h:SetPoint("LEFT", 0, 0); h:SetPoint("RIGHT", 0, 0); h:SetHeight(1)
      local v = c:CreateTexture(nil, "BACKGROUND")
      v:SetColorTexture(color(C.ring, 0.35))
      v:SetPoint("TOP", 0, 0); v:SetPoint("BOTTOM", 0, 0); v:SetWidth(1)
      c.hover = c:CreateTexture(nil, "ARTWORK", nil, 1)
      c.hover:SetTexture(MEDIA .. "Dot")
      c.hover:SetSize(CELL - 8, CELL - 8)
      c.hover:SetPoint("CENTER")
      c.hover:SetAlpha(0)
      c.stone = c:CreateTexture(nil, "ARTWORK", nil, 2)
      c.stone:SetTexture(MEDIA .. "Dot")
      c.stone:SetPoint("CENTER")
      c.glow = c:CreateTexture(nil, "ARTWORK", nil, 0)
      c.glow:SetTexture(MEDIA .. "Glow")
      c.glow:SetBlendMode("ADD")
      c.glow:SetSize(CELL * 1.8, CELL * 1.8)
      c.glow:SetPoint("CENTER")
      c.glow:Hide()
      c.index = i
      c:SetScript("OnEnter", function(self)
        local m = ns.GameMatch()
        if m and not m.over and m.game == G.id and G.IsMyTurn(m) and not m.board[self.index] then
          local col = myNum(m) == 1 and P1 or P2
          self.hover:SetVertexColor(col[1], col[2], col[3])
          S.FadeTo(self.hover, 0.35, 0.1)
        end
      end)
      c:SetScript("OnLeave", function(self) S.FadeTo(self.hover, 0, 0.15) end)
      c:SetScript("OnClick", function(self)
        local m = ns.GameMatch()
        if m and not m.over and G.IsMyTurn(m) and not m.board[self.index] then
          self.hover:SetAlpha(0)
          ns.GameMove(tostring(self.index))
        end
      end)
      cells[i] = c
    end
  end

  function G.Start(m)
    m.board, m.turn = {}, 1
    for _, c in ipairs(cells) do c.stone:Hide(); c.glow:Hide(); c.hover:SetAlpha(0) end
  end

  function G.OnMove(m, data, mine)
    local i = tonumber(data)
    if not i or i < 1 or i > N * N or m.board[i] then return end
    local who = m.turn
    if (who == myNum(m)) ~= mine then return end
    m.board[i] = who
    local c, col = cells[i], who == 1 and P1 or P2
    c.stone:SetVertexColor(col[1], col[2], col[3])
    c.stone:Show()
    popIn(c.stone, function(v) c.stone:SetSize(v, v) end, CELL - 6)
    -- the last stone glows softly
    if m.last then cells[m.last].glow:Hide() end
    c.glow:SetVertexColor(col[1], col[2], col[3], 0.35)
    c.glow:Show()
    m.last = i
    PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    local x, y = (i - 1) % N + 1, math.floor((i - 1) / N) + 1
    for _, d in ipairs(DIRS) do
      local n, _, list = line(m.board, x, y, d[1], d[2], who)
      if n >= 5 then
        local glows = {}
        for _, k in ipairs(list) do
          cells[k].glow:SetVertexColor(col[1], col[2], col[3], 0.8)
          cells[k].glow:Show()
          glows[#glows + 1] = cells[k].glow
        end
        pulse(glows)
        ns.GameEnd(who == myNum(m) and "win" or "lose")
        return
      end
    end
    local full = true
    for k = 1, N * N do if not m.board[k] then full = false break end end
    if full then ns.GameEnd("draw") return end
    m.turn = 3 - who
    ns.GameRefreshStatus()
  end
  ns.RegisterGame(G)
end

-- Battleship ------------------------------------------------------------------------------------------------
-- each player places his fleet (at random, "Shuffle" until the first shot); shots alternate. The one
-- who is shot at answers: miss, hit, sunk, or all sunk (the shooter wins).
do
  -- noWatch: each side only knows its own fleet, a spectator could not follow
  local G = { id = "ship", name = "Battleship", desc = "Sink the enemy fleet first.", noWatch = true,
    icon = { "Interface\\Icons\\INV_Misc_Spyglass_03", "Interface\\Icons\\INV_Misc_Spyglass_02" } }
  local N = 8
  local FLEET = { 4, 3, 3, 2, 2 }
  local mine, theirs, shuffle, info = {}, {}, nil, nil

  -- ships placed at random: grid[i] = ship number
  local function place()
    local grid, ships = {}, {}
    for s, len in ipairs(FLEET) do
      while true do
        local horiz = math.random() < 0.5
        local x, y = math.random(1, horiz and N - len + 1 or N), math.random(1, horiz and N or N - len + 1)
        local ok, list = true, {}
        for k = 0, len - 1 do
          local cx, cy = horiz and x + k or x, horiz and y or y + k
          local i = (cy - 1) * N + cx
          -- no ship touching another one
          for dy = -1, 1 do for dx = -1, 1 do
            local nx, ny = cx + dx, cy + dy
            if nx >= 1 and ny >= 1 and nx <= N and ny <= N and grid[(ny - 1) * N + nx] then ok = false end
          end end
          list[#list + 1] = i
        end
        if ok then
          for _, i in ipairs(list) do grid[i] = s end
          ships[s] = { cells = list, hits = 0 }
          break
        end
      end
    end
    return grid, ships
  end

  local function shooter(m) return m.turn end
  function G.IsMyTurn(m)
    local me = myNum(m)
    if m.pending then return m.turn ~= me end -- I have to answer (done by itself)
    return m.turn == me
  end
  function G.Mark(m, isMine) return dotMark((isMine and myNum(m) or 3 - myNum(m)) == 1 and P1 or P2) end

  -- the answer to a shot on a fleet: "m" miss, "h" hit, "k" sunk, "w" the whole fleet is sunk
  local function resolve(grid, ships, i)
    local s = grid[i]
    if not s then return "m" end
    if ships[s].hitCells and ships[s].hitCells[i] then return "h" end
    ships[s].hitCells = ships[s].hitCells or {}
    ships[s].hitCells[i] = true
    ships[s].hits = ships[s].hits + 1
    if ships[s].hits < #ships[s].cells then return "h" end
    for _, sh in ipairs(ships) do if sh.hits < #sh.cells then return "k" end end
    return "w"
  end

  local function paint(c, state)
    c.dot:Hide(); c.x:Hide()
    if state == "m" then
      c.dot:SetVertexColor(MISS[1], MISS[2], MISS[3])
      c.dot:SetSize(8, 8)
      c.dot:Show()
    elseif state == "h" or state == "k" or state == "w" then
      c.dot:SetVertexColor(HIT[1], HIT[2], HIT[3])
      c.dot:Show()
      popIn(c.dot, function(v) c.dot:SetSize(v, v) end, c:GetWidth() - 8)
      c.x:SetShown(state ~= "h")
    end
  end

  local function drawMine(m)
    for i, c in ipairs(mine) do
      c.ship:SetShown(m.myGrid[i] ~= nil)
      paint(c, m.shotAtMe[i])
    end
  end

  -- the bot shoots next to its hits first
  local function botTarget(m)
    local view, me = m.botView, nil
    local cands = {}
    for i, st in pairs(view) do
      if st == "h" then
        local x, y = (i - 1) % N + 1, math.floor((i - 1) / N) + 1
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx, ny = x + d[1], y + d[2]
          local j = (ny - 1) * N + nx
          if nx >= 1 and ny >= 1 and nx <= N and ny <= N and not view[j] then cands[#cands + 1] = j end
        end
      end
    end
    if #cands > 0 and math.random() < 0.9 then return cands[math.random(#cands)] end
    local free = {}
    for i = 1, N * N do
      local x, y = (i - 1) % N, math.floor((i - 1) / N)
      if not view[i] and (x + y) % 2 == 0 then free[#free + 1] = i end
    end
    if #free == 0 then for i = 1, N * N do if not view[i] then free[#free + 1] = i end end end
    return free[math.random(#free)], me
  end

  function G.BotMove(m)
    local me = myNum(m)
    if m.pending and m.turn == me then
      -- answers my shot
      return "R:" .. m.pending .. ":" .. resolve(m.botGrid, m.botShips, m.pending)
    elseif not m.pending and m.turn ~= me then
      return "S:" .. botTarget(m)
    end
  end

  local function grid(f, size, gap, x, clickable)
    local list = {}
    local holder = CreateFrame("Frame", nil, f)
    holder:SetSize(N * (size + gap) - gap + 12, N * (size + gap) - gap + 12)
    holder:SetPoint("TOPLEFT", x, -26)
    S.Rounded(holder, 8, { 0.06, 0.1, 0.2, 1 }, { 0.03, 0.05, 0.11, 1 }, C.trim)
    for i = 1, N * N do
      local cx, cy = (i - 1) % N, math.floor((i - 1) / N)
      local c = CreateFrame("Button", nil, holder)
      c:SetSize(size, size)
      c:SetPoint("TOPLEFT", 6 + cx * (size + gap), -6 - cy * (size + gap))
      local bg = c:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(0.2, 0.35, 0.6, 0.18)
      c.ship = c:CreateTexture(nil, "BORDER")
      c.ship:SetAllPoints()
      c.ship:SetColorTexture(color(C.ring, 0.55))
      c.ship:Hide()
      c.dot = c:CreateTexture(nil, "ARTWORK")
      c.dot:SetTexture(MEDIA .. "Dot")
      c.dot:SetPoint("CENTER")
      c.dot:Hide()
      c.x = c:CreateTexture(nil, "OVERLAY")
      c.x:SetAllPoints()
      c.x:SetColorTexture(1, 0.3, 0.25, 0.25)
      c.x:Hide()
      if clickable then
        c.hl = c:CreateTexture(nil, "HIGHLIGHT")
        c.hl:SetAllPoints()
        c.hl:SetColorTexture(1, 0.85, 0.4, 0.25)
        c.index = i
        c:SetScript("OnClick", function(self)
          local m = ns.GameMatch()
          if m and not m.over and m.game == G.id and not m.pending and m.turn == myNum(m) and not m.myShots[self.index] then
            m.started = true
            shuffle:SetEnabled(false)
            ns.GameMove("S:" .. self.index)
          end
        end)
      else
        c:EnableMouse(false)
      end
      list[i] = c
    end
    return list, holder
  end

  function G.Build(f)
    local a, ha = nil, nil
    a, ha = grid(f, 22, 2, 10, false)
    mine = a
    local b, hb = grid(f, 30, 2, 0, true)
    theirs = b
    hb:ClearAllPoints()
    hb:SetPoint("TOPRIGHT", -10, -26)
    local t1 = S.Text(f, 12, "dim")
    t1:SetPoint("BOTTOMLEFT", ha, "TOPLEFT", 2, 6)
    t1:SetText(L["Your fleet"])
    local t2 = S.Text(f, 12, "gold")
    t2:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 2, 6)
    t2:SetText(L["Enemy waters"])
    shuffle = S.Button(f, L["Shuffle"], 120, 24, function()
      local m = ns.GameMatch()
      if m and not m.over and not m.started then
        m.myGrid, m.myShips = place()
        drawMine(m)
      end
    end)
    shuffle:SetPoint("TOPLEFT", ha, "BOTTOMLEFT", 0, -10)
    info = S.Text(f, 11, "muted")
    info:SetPoint("TOPLEFT", shuffle, "BOTTOMLEFT", 0, -10)
    info:SetWidth(200)
    info:SetWordWrap(true)
  end

  local function refreshInfo(m)
    local sunk = 0
    for _, sh in ipairs(m.myShips) do if sh.hits >= #sh.cells then sunk = sunk + 1 end end
    info:SetText(string.format(L["Enemy ships sunk: %d / %d"], m.enemySunk, #FLEET) .. "\n"
      .. string.format(L["Your ships sunk: %d / %d"], sunk, #FLEET))
  end

  function G.Start(m)
    m.turn, m.pending, m.started = 1, nil, false
    m.myGrid, m.myShips = place()
    m.shotAtMe, m.myShots, m.enemySunk = {}, {}, 0
    if m.bot then m.botGrid, m.botShips = place(); m.botView = {} end
    for _, c in ipairs(theirs) do paint(c, nil); c.ship:Hide() end
    drawMine(m)
    shuffle:SetEnabled(true)
    refreshInfo(m)
  end

  function G.OnMove(m, data, isMine)
    local me = myNum(m)
    local kind, i, res = data:match("^(%a):(%d+):?(%a?)$")
    i = tonumber(i)
    if not kind or not i or i < 1 or i > N * N then return end
    if kind == "S" then
      if m.pending then return end
      if isMine then
        if m.turn ~= me or m.myShots[i] then return end
        m.pending = i
        m.myShots[i] = "?"
      else
        if m.turn == me then return end
        m.pending = i
        m.started = true
        shuffle:SetEnabled(false)
        -- my answer, sent by itself after a short moment
        local answer = resolve(m.myGrid, m.myShips, i)
        ns.GameLater(0.4, function(mm) if mm.pending == i then ns.GameMove("R:" .. i .. ":" .. answer) end end)
      end
      ns.GameRefreshStatus()
    elseif kind == "R" then
      if m.pending ~= i or res == "" then return end
      m.pending = nil
      if isMine then
        -- my answer to the opponent's shot
        m.shotAtMe[i] = res
        paint(mine[i], res)
        if m.bot then m.botView[i] = res == "m" and "m" or "h" end
        PlaySound(SOUNDKIT and (res == "m" and SOUNDKIT.U_CHAT_SCROLL_BUTTON or SOUNDKIT.IG_QUEST_LIST_COMPLETE) or 1115)
        refreshInfo(m)
        if res == "w" then ns.GameEnd("lose") return end
        m.turn = me
      else
        m.myShots[i] = res
        paint(theirs[i], res)
        if res == "k" or res == "w" then m.enemySunk = m.enemySunk + 1 end
        PlaySound(SOUNDKIT and (res == "m" and SOUNDKIT.U_CHAT_SCROLL_BUTTON or SOUNDKIT.IG_QUEST_LIST_COMPLETE) or 1115)
        refreshInfo(m)
        if res == "w" then ns.GameEnd("win") return end
        m.turn = 3 - me
      end
      ns.GameRefreshStatus()
    end
  end
  ns.RegisterGame(G)
end

-- WoW quiz ---------------------------------------------------------------------------------------------------
-- 8 questions, the same for both players (the order comes from the match id). Both answer, then
-- the right answer shows; one point per right answer.
do
  local G = { id = "quiz", name = "WoW quiz", desc = "Eight questions about Azeroth and its lore.",
    icon = { "Interface\\Icons\\INV_Misc_Book_07", "Interface\\Icons\\INV_Misc_Book_09" } }
  local ROUNDS = 8
  local TIME = 10 -- seconds to answer a question; past it, the answer counts as wrong
  -- Answers come from the client when it can (instance, zone, class and race names are then in the
  -- player's language); characters are translated in the locales.
  local MAPS = {
    [409] = "Molten Core", [469] = "Blackwing Lair", [249] = "Onyxia's Lair", [309] = "Zul'Gurub",
    [509] = "Ruins of Ahn'Qiraj", [531] = "Temple of Ahn'Qiraj", [533] = "Naxxramas", [230] = "Blackrock Depths",
    [229] = "Blackrock Spire", [289] = "Scholomance", [329] = "Stratholme", [429] = "Dire Maul",
    [36] = "The Deadmines", [34] = "The Stockade", [189] = "Scarlet Monastery", [109] = "The Temple of Atal'Hakkar",
    [349] = "Maraudon", [209] = "Zul'Farrak", [70] = "Uldaman", [90] = "Gnomeregan", [43] = "Wailing Caverns",
    [33] = "Shadowfang Keep", [47] = "Razorfen Kraul", [48] = "Blackfathom Deeps",
  }
  local ZONES = {
    [1446] = "Tanaris", [1451] = "Silithus", [1413] = "The Barrens", [1441] = "Thousand Needles",
    [1434] = "Stranglethorn Vale", [1436] = "Westfall", [1435] = "Swamp of Sorrows", [1450] = "Moonglade",
    [1448] = "Felwood", [1449] = "Un'Goro Crater", [1423] = "Eastern Plaguelands", [1422] = "Western Plaguelands",
    [1420] = "Tirisfal Glades", [1425] = "The Hinterlands", [1419] = "Blasted Lands", [1428] = "Burning Steppes",
    [1427] = "Searing Gorge", [1418] = "Badlands", [1430] = "Deadwind Pass", [1431] = "Duskwood",
    [1433] = "Redridge Mountains", [1452] = "Winterspring", [1447] = "Azshara", [1411] = "Durotar",
    [1412] = "Mulgore", [1440] = "Ashenvale", [1443] = "Desolace", [1445] = "Dustwallow Marsh", [1444] = "Feralas",
  }
  local RACES = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll" }
  local function sorted(t) local l = {}; for k in pairs(t) do l[#l + 1] = k end; table.sort(l); return l end
  local MAP_IDS, ZONE_IDS = sorted(MAPS), sorted(ZONES)
  local RACE_IDS = { 1, 2, 3, 4, 5, 6, 7, 8 }

  local function className(file) return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file] or file end
  local NAMES = {
    map = function(id)
      local ok, n = pcall(GetRealZoneText, id)
      if ok and type(n) == "string" and n ~= "" then return n end
      return MAPS[id]
    end,
    zone = function(id)
      if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
      end
      return ZONES[id]
    end,
    race = function(id)
      if C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        local ok, info = pcall(C_CreatureInfo.GetRaceInfo, id)
        if ok and type(info) == "table" and type(info.raceName) == "string" and info.raceName ~= "" then return info.raceName end
      end
      return RACES[id]
    end,
    class = className,
    char = function(key) return L[key] end,
  }
  local POOLS = { map = MAP_IDS, zone = ZONE_IDS, race = RACE_IDS }
  local ICONS = {
    map = "Interface\\Icons\\INV_Misc_Head_Dragon_01", zone = "Interface\\Icons\\INV_Misc_Map_01",
    class = "Interface\\Icons\\INV_Misc_Book_09", race = "Interface\\Icons\\INV_Misc_Book_07",
    char = "Interface\\Icons\\INV_Misc_Book_11", trivia = "Interface\\Icons\\INV_Misc_QuestionMark",
  }

  -- question, kind, right answer, then (optional) three wrong ones; without them the wrong answers are
  -- drawn from the same kind
  local LORE = {
    { "In which instance does Ragnaros the Firelord reign?", "map", 409 },
    { "Where does Edwin VanCleef hide the Defias fleet?", "map", 36 },
    { "Where did the Gurubashi trolls summon Hakkar the Soulflayer?", "map", 309 },
    { "In which citadel does Kel'Thuzad await the living?", "map", 533 },
    { "Where did Archmage Arugal unleash his worgen?", "map", 33 },
    { "Where does Princess Theradras hide?", "map", 349 },
    { "Where does Emperor Dagran Thaurissan rule the Dark Iron dwarves?", "map", 230 },
    { "Where does Darkmaster Gandling teach necromancy?", "map", 289 },
    { "In which city does Baron Rivendare await?", "map", 329 },
    { "Where does High Inquisitor Whitemane lead the Scarlet Crusade?", "map", 189 },
    { "Under which temple does the Old God C'Thun stir?", "map", 531 },
    { "Where does Mekgineer Thermaplugg hide?", "map", 90 },
    { "Where does Jammal'an the Prophet serve Hakkar?", "map", 109 },
    { "Where does the hydra Gahz'rilla lurk?", "map", 209 },
    { "Where does Nefarian conduct his experiments?", "map", 469 },
    { "Where does Ossirian the Unscarred lie in wait?", "map", 509 },
    { "Where does Warchief Rend Blackhand command the Dark Horde?", "map", 229 },
    { "Where were the Druids of the Fang corrupted by nightmares?", "map", 43 },
    { "Where does King Gordok rule the ogres?", "map", 429 },
    { "Where does the stone keeper Archaedas guard the Discs of Norgannon?", "map", 70 },
    { "Where does Charlga Razorflank lead the quilboars?", "map", 47 },
    { "Where does Aku'mai, a beast of the Old Gods, lurk?", "map", 48 },
    { "Where did Bazil Thredd lead a prison riot?", "map", 34 },
    { "In which zone is the goblin town of Gadgetzan?", "zone", 1446 },
    { "In which zone is the pirate port of Booty Bay?", "zone", 1434 },
    { "In which zone is Cenarion Hold?", "zone", 1451 },
    { "Where is the Light's Hope Chapel?", "zone", 1423 },
    { "Where does the doom lord Kazzak roam?", "zone", 1419 },
    { "In which zone stands Medivh's tower, Karazhan?", "zone", 1430 },
    { "In which zone is the goblin town of Everlook?", "zone", 1452 },
    { "Where did Grom Hellscream slay the pit lord Mannoroth?", "zone", 1440 },
    { "In which zone stands the Dark Portal?", "zone", 1419 },
    { "In which zone is Jaina Proudmoore's city, Theramore?", "zone", 1445 },
    { "Where is the lair of the black dragon Onyxia?", "zone", 1445 },
    { "Where lies the sunken Temple of Atal'Hakkar?", "zone", 1435 },
    { "In which zone is the Scarlet Monastery?", "zone", 1420 },
    { "In which zone is the city of Stratholme?", "zone", 1423 },
    { "In which zone is the instance Maraudon?", "zone", 1443 },
    { "In which zone is the port of Ratchet?", "zone", 1413 },
    { "What class is Thrall?", "class", "SHAMAN" },
    { "What class was Uther the Lightbringer?", "class", "PALADIN" },
    { "What class is Jaina Proudmoore?", "class", "MAGE" },
    { "What class is Malfurion Stormrage?", "class", "DRUID" },
    { "What class was the orc Gul'dan?", "class", "WARLOCK" },
    { "SI:7, Stormwind's spy network, recruits which class?", "class", "ROGUE" },
    { "What class is Rexxar, the half-ogre beastmaster?", "class", "HUNTER" },
    { "What class was Archbishop Alonsus Faol?", "class", "PRIEST" },
    { "Which race built the city of Gnomeregan?", "race", 7 },
    { "Of which race is Cairne Bloodhoof?", "race", 6 },
    { "Which race has made the Undercity its capital?", "race", 5 },
    { "Of which race is Vol'jin?", "race", 8 },
    { "Which race calls itself the kaldorei?", "race", 4 },
    { "Which race does the Wildhammer clan belong to?", "race", 3 },
    { "Which race does the Frostwolf clan belong to?", "race", 2 },
    { "Which race founded the empire of Arathor?", "race", 1 },
    { "Who is the Warchief of the Horde?", "char", "Thrall", "Cairne Bloodhoof", "Vol'jin", "Ner'zhul" },
    { "Who leads the Forsaken?", "char", "Sylvanas Windrunner", "Arthas Menethil", "Kel'Thuzad", "Jaina Proudmoore" },
    { "Who is the king of Ironforge?", "char", "Magni Bronzebeard", "Muradin Bronzebeard", "Dagran Thaurissan", "Varian Wrynn" },
    { "Who is regent of Stormwind while the king is missing?", "char", "Bolvar Fordragon", "Lady Katrana Prestor", "Anduin Wrynn", "Magni Bronzebeard" },
    { "Which noble disguise hides Onyxia at the Stormwind court?", "char", "Lady Katrana Prestor", "Jaina Proudmoore", "Sylvanas Windrunner", "Aegwynn" },
    { "Who is the father of Onyxia and Nefarian?", "char", "Deathwing", "Ragnaros", "Malygos", "Kel'Thuzad" },
    { "Who is the High Priestess of Elune?", "char", "Tyrande Whisperwind", "Jaina Proudmoore", "Sylvanas Windrunner", "Aegwynn" },
    { "Which Old God is imprisoned beneath Ahn'Qiraj?", "char", "C'Thun", "Yogg-Saron", "Hakkar", "Ragnaros" },
    { "What is the name of the Gurubashi blood god?", "char", "Hakkar", "C'Thun", "Yogg-Saron", "Ragnaros" },
    { "Who was the last Guardian of Tirisfal?", "char", "Medivh", "Aegwynn", "Khadgar", "Kel'Thuzad" },
    { "Who founded the Cult of the Damned?", "char", "Kel'Thuzad", "Arthas Menethil", "Gul'dan", "Medivh" },
    { "Which orc warlock opened the Dark Portal with Medivh?", "char", "Gul'dan", "Ner'zhul", "Thrall", "Kel'Thuzad" },
    { "Which prince of Lordaeron became the Lich King's champion?", "char", "Arthas Menethil", "Varian Wrynn", "Anduin Wrynn", "Bolvar Fordragon" },
    { "Who is the child king of Stormwind?", "char", "Anduin Wrynn", "Varian Wrynn", "Bolvar Fordragon", "Magni Bronzebeard" },
    { "Which Firelord did the Dark Iron dwarves summon?", "char", "Ragnaros", "Hakkar", "Deathwing", "C'Thun" },
    { "Who was Medivh's apprentice?", "char", "Khadgar", "Kel'Thuzad", "Jaina Proudmoore", "Aegwynn" },
    { "Where does Vaelastrasz the Corrupt await?", "map", 469 },
    { "Where does the Prophet Skeram preach?", "map", 531 },
    { "Where does the abomination Patchwerk wait?", "map", 533 },
    { "Where does High Priestess Arlokk serve Hakkar?", "map", 309 },
    { "Where does Ramstein the Gorger guard the slaughterhouse?", "map", 329 },
    { "Where does Herod, the Scarlet Champion, train?", "map", 189 },
    { "In which zone is the city of Orgrimmar?", "zone", 1411 },
    { "In which zone is the city of Thunder Bluff?", "zone", 1412 },
    { "In which zone is the Crossroads?", "zone", 1413 },
    { "In which zone is the town of Darkshire?", "zone", 1431 },
    { "In which zone is the town of Lakeshire?", "zone", 1433 },
    { "In which zone is Sentinel Hill?", "zone", 1436 },
    { "In which zone is the druid town of Nighthaven?", "zone", 1450 },
    { "What class is Khadgar?", "class", "MAGE" },
    { "What class is Tyrande Whisperwind?", "class", "PRIEST" },
    { "What class is Varian Wrynn?", "class", "WARRIOR" },
    { "Of which race is Thrall?", "race", 2 },
    { "Of which race is Magni Bronzebeard?", "race", 3 },
    { "Of which race is Mekgineer Thermaplugg?", "race", 7 },
    { "Who is the brother of Magni Bronzebeard?", "char", "Muradin Bronzebeard", "Dagran Thaurissan", "Varian Wrynn", "Khadgar" },
    { "Which Aspect leads the blue dragonflight?", "char", "Malygos", "Deathwing", "Ragnaros", "Medivh" },
    { "Who was Medivh's mother?", "char", "Aegwynn", "Jaina Proudmoore", "Tyrande Whisperwind", "Sylvanas Windrunner" },
    { "Which orc shaman became the first Lich King?", "char", "Ner'zhul", "Gul'dan", "Thrall", "Kel'Thuzad" },
    { "Which tauren chieftain was Thrall's friend and ally?", "char", "Cairne Bloodhoof", "Vol'jin", "Ner'zhul", "Magni Bronzebeard" },
    { "Who killed his father, King Terenas?", "char", "Arthas Menethil", "Varian Wrynn", "Anduin Wrynn", "Bolvar Fordragon" },
    { "Who rules the Dark Iron dwarves from Shadowforge City?", "char", "Dagran Thaurissan", "Magni Bronzebeard", "Muradin Bronzebeard", "Ragnaros" },
  }
  -- question, right answer, three wrong ones
  local TRIVIA = {
    { "What is the maximum level?", "60", "50", "70", "55" },
    { "How many players in a full Molten Core raid?", "40", "20", "25", "30" },
    { "How many slots does the starting backpack have?", "16", "12", "18", "20" },
    { "What is the maximum skill of a profession?", "300", "250", "350", "375" },
    { "How many primary professions can you learn?", "2", "1", "3", "4" },
    { "At what level can you ride your first mount?", "40", "30", "20", "50" },
    { "How many players in a dungeon group?", "5", "4", "6", "10" },
    { "How many players can enter Zul'Gurub?", "20", "10", "15", "40" },
    { "How many classes are there?", "9", "8", "10", "12" },
    { "How many players can enter Onyxia's Lair?", "40", "20", "25", "10" },
    { "How many bosses are there in Molten Core?", "10", "8", "12", "9" },
    { "How many bosses are there in Blackwing Lair?", "8", "6", "10", "7" },
    { "How many bosses are there in Naxxramas?", "15", "13", "12", "17" },
    { "In which year was World of Warcraft released?", "2004", "2003", "2005", "2006" },
    { "How many players in a Warsong Gulch team?", "10", "15", "20", "5" },
    { "How many players per team in Alterac Valley?", "40", "20", "30", "15" },
    { "How many bosses are there in the Temple of Ahn'Qiraj?", "9", "8", "10", "12" },
    { "How many talent points does a level 60 character have?", "51", "50", "60", "41" },
    { "At what level do you get your first talent point?", "10", "5", "12", "15" },
    { "How many talent trees does each class have?", "3", "2", "4", "5" },
  }
  local qIcon, qText, feedback, scoreText, timerBar, timerText
  local answers = {}

  -- the questions of a match: { text, icon, options = {4}, right = index }. Every random draw only
  -- depends on the match id, never on the client's language, so both players get the same quiz.
  local function makeQuestions(id)
    local rnd = seeded(id)
    local pool = {}
    for _, lq in ipairs(LORE) do pool[#pool + 1] = { kind = lq[2], q = lq } end
    for _, tq in ipairs(TRIVIA) do pool[#pool + 1] = { kind = "trivia", q = tq } end
    for i = #pool, 2, -1 do local j = rnd(i); pool[i], pool[j] = pool[j], pool[i] end
    local list = {}
    for k = 1, ROUNDS do
      local p = pool[k]
      local q = { text = L[p.q[1]], icon = ICONS[p.kind] }
      local right, wrong
      if p.kind == "trivia" then
        right, wrong = p.q[2], { p.q[3], p.q[4], p.q[5] }
      else
        local name = NAMES[p.kind]
        right = name(p.q[3])
        wrong = {}
        if p.q[4] then
          for i = 4, 6 do wrong[#wrong + 1] = name(p.q[i]) end
        else
          local others = {}
          for _, v in ipairs(POOLS[p.kind] or ns.CLASSES) do if v ~= p.q[3] then others[#others + 1] = v end end
          for _ = 1, 3 do wrong[#wrong + 1] = name(table.remove(others, rnd(#others))) end
        end
      end
      local opts = { right, wrong[1], wrong[2], wrong[3] }
      local order = { 1, 2, 3, 4 }
      for i = 4, 2, -1 do local j = rnd(i); order[i], order[j] = order[j], order[i] end
      q.options = {}
      for slot, o in ipairs(order) do
        q.options[slot] = opts[o] or "?"
        if o == 1 then q.right = slot end
      end
      list[k] = q
    end
    return list
  end

  function G.IsMyTurn(m) return m.myPick == nil end
  function G.BotMove(m)
    if m.oppPick then return end
    local q = m.questions[m.round]
    if math.random() < 0.65 then return "A:" .. m.round .. ":" .. q.right end
    local w = {}
    for i = 1, 4 do if i ~= q.right then w[#w + 1] = i end end
    return "A:" .. m.round .. ":" .. w[math.random(3)]
  end

  local function showRound(m)
    local q = m.questions[m.round]
    m.myPick, m.oppPick = nil, nil
    qIcon.tex:SetTexture(q.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    qIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    qText:SetText(string.format(L["Question %d / %d"], m.round, ROUNDS) .. "\n\n" .. q.text)
    for i, b in ipairs(answers) do
      b:SetText(q.options[i])
      b:SetBorderColor(color(C.trim))
      b.text:SetTextColor(color(C.text))
      b.opp:Hide()
      b:SetEnabled(true)
      b:SetAlpha(0)
      S.Tween(b, { dur = 0.25, delay = i * 0.05, from = 0, to = 1, set = function(v) b:SetAlpha(v) end })
    end
    feedback:SetText("")
    scoreText:SetText(string.format("%d  -  %d", m.pts[1], m.pts[2]))
    m.deadline = GetTime() + TIME
    timerBar:Show()
    ns.GameRefreshStatus()
  end

  local function reveal(m)
    local q = m.questions[m.round]
    for i, b in ipairs(answers) do
      if i == q.right then
        b:SetBorderColor(color(C.good)); b.text:SetTextColor(color(C.good))
      elseif i == m.myPick then
        b:SetBorderColor(color(C.bad)); b.text:SetTextColor(color(C.bad))
      end
      b.opp:SetShown(i == m.oppPick)
    end
    if m.myPick == q.right then m.pts[1] = m.pts[1] + 1 end
    if m.oppPick == q.right then m.pts[2] = m.pts[2] + 1 end
    feedback:SetText(m.myPick == q.right and ("|cff1eff00" .. L["Right!"] .. "|r")
      or ("|cffff2020" .. (m.myPick == 0 and L["Time's up!"] or L["Wrong"]) .. "|r"))
    scoreText:SetText(string.format("%d  -  %d", m.pts[1], m.pts[2]))
    PlaySound(SOUNDKIT and (m.myPick == q.right and SOUNDKIT.IG_QUEST_LIST_COMPLETE or SOUNDKIT.U_CHAT_SCROLL_BUTTON) or 1115)
    if m.round >= ROUNDS then
      ns.GameLater(1.6, function(mm)
        if mm.pts[1] > mm.pts[2] then ns.GameEnd("win") elseif mm.pts[1] < mm.pts[2] then ns.GameEnd("lose")
        else ns.GameEnd("draw") end
      end)
    else
      ns.GameLater(2.2, function(mm) mm.round = mm.round + 1; showRound(mm) end)
    end
  end

  function G.Build(f)
    qIcon = S.Icon(f, 48)
    qIcon:SetPoint("TOP", 0, -6)
    qText = S.Text(f, 14, "text")
    qText:SetPoint("TOP", qIcon, "BOTTOM", 0, -10)
    qText:SetWidth(480)
    qText:SetWordWrap(true)
    qText:SetJustifyH("CENTER")
    for i = 1, 4 do
      local b = S.Button(f, "", 230, 40, function(self)
        local m = ns.GameMatch()
        if m and not m.over and m.game == G.id and m.myPick == nil then ns.GameMove("A:" .. m.round .. ":" .. self.slot) end
      end)
      b.slot = i
      b:SetPoint("TOP", (i % 2 == 1) and -122 or 122, -174 - math.floor((i - 1) / 2) * 50)
      b.opp = b:CreateTexture(nil, "OVERLAY")
      b.opp:SetTexture(MEDIA .. "Dot")
      b.opp:SetSize(10, 10)
      b.opp:SetPoint("RIGHT", -8, 0)
      b.opp:SetVertexColor(P2[1], P2[2], P2[3])
      answers[i] = b
    end
    scoreText = S.Text(f, 22, "gold")
    scoreText:SetPoint("BOTTOM", 0, 34)
    scoreText:SetJustifyH("CENTER")
    feedback = S.Text(f, 14, "text")
    feedback:SetPoint("BOTTOM", 0, 8)
    feedback:SetJustifyH("CENTER")
    -- countdown: a bar under the question that empties in TIME seconds; at 0 the answer is "none"
    timerBar = S.ProgressBar(f, 10)
    timerBar:SetPoint("TOP", 0, -150)
    timerBar:SetWidth(470)
    timerBar:SetMinMaxValues(0, TIME)
    timerText = S.Text(timerBar, 11, "text")
    timerText:SetPoint("LEFT", timerBar, "RIGHT", 8, 0)
    timerBar:Hide()
    -- (a frame of its own: the countdown goes on while the guild window is closed)
    local clock = CreateFrame("Frame")
    clock:SetScript("OnUpdate", function()
      local m = ns.GameMatch()
      if not (m and m.game == G.id and m.deadline) then return end
      if m.over or m.myPick ~= nil then
        timerBar:SetValue(0); timerText:SetText("")
        return
      end
      local left = m.deadline - GetTime()
      if left <= 0 then
        m.deadline = nil
        ns.GameMove("A:" .. m.round .. ":0")
        return
      end
      timerBar:SetValue(left)
      timerBar:SetColors(left > 5 and C.gold1 or left > 2.5 and C.warn or C.bad)
      timerText:SetText(math.ceil(left) .. " s")
    end)
    local legend = S.Text(f, 10, "muted")
    legend:SetPoint("BOTTOMRIGHT", -4, 4)
    legend:SetText(dotMark(P2) .. " " .. L["your opponent's answer"])
  end

  function G.Start(m)
    m.questions = makeQuestions(m.id)
    m.round, m.pts = 1, { 0, 0 }
    showRound(m)
  end

  function G.OnMove(m, data, isMine)
    local r, pick = data:match("^A:(%d+):(%d)$")
    r, pick = tonumber(r), tonumber(pick)
    -- pick 0: no answer in time
    if not r or r ~= m.round or not pick or pick < 0 or pick > 4 then return end
    if isMine then
      if m.myPick then return end
      m.myPick = pick
      for i, b in ipairs(answers) do
        b:SetEnabled(false)
        if i == pick then b:SetBorderColor(color(C.gold)); b.text:SetTextColor(color(C.gold)) end
      end
    else
      if m.oppPick then return end
      m.oppPick = pick
    end
    if m.myPick and m.oppPick then reveal(m) else ns.GameRefreshStatus() end
  end
  ns.RegisterGame(G)
end

-- Dice race ----------------------------------------------------------------------------------------------------
-- roll as long as you like: each roll adds up, a 1 loses the points of the turn. Hold banks them.
-- The first to 50 wins.
do
  local G = { id = "pig", name = "Dice race", desc = "Roll or hold: first to %d wins, a 1 loses the turn.",
    descArg = 50, icon = { "Interface\\Icons\\INV_Misc_Dice_02", "Interface\\Icons\\INV_Misc_Dice_01" } }
  local GOAL = 50
  local die, pips, rollBtn, holdBtn, potText, bars, totals, names = nil, {}, nil, nil, nil, {}, {}, {}
  local FACES = { { 5 }, { 1, 9 }, { 1, 5, 9 }, { 1, 3, 7, 9 }, { 1, 3, 5, 7, 9 }, { 1, 3, 4, 6, 7, 9 } }

  function G.IsMyTurn(m) return m.turn == myNum(m) and not m.rolling end
  function G.Mark(m, mine) return dotMark((mine and myNum(m) or 3 - myNum(m)) == 1 and P1 or P2) end

  local function face(n)
    for _, p in ipairs(pips) do p:Hide() end
    for _, k in ipairs(FACES[n] or {}) do pips[k]:Show() end
  end

  local function refresh(m)
    local me = myNum(m)
    for k = 1, 2 do
      local who = k == 1 and me or 3 - me
      totals[k]:SetText(m.tot[who])
      bars[k]:SetValue(math.min(1, m.tot[who] / GOAL))
    end
    potText:SetText(string.format(L["This turn: %d"], m.pot))
    local can = not m.over and G.IsMyTurn(m)
    rollBtn:SetEnabled(can)
    holdBtn:SetEnabled(can and m.pot > 0)
  end

  function G.BotMove(m)
    local bot = 3 - myNum(m)
    if m.pot >= 15 or m.tot[bot] + m.pot >= GOAL then return "H" end
    -- behind by a lot: takes more risks
    if m.pot >= 10 and m.tot[bot] >= m.tot[myNum(m)] then return "H" end
    return "R:" .. math.random(6)
  end

  function G.Build(f)
    local d = CreateFrame("Frame", nil, f)
    d:SetSize(96, 96)
    d:SetPoint("TOP", 0, -20)
    S.Rounded(d, 14, { 0.98, 0.95, 0.88, 1 }, { 0.82, 0.76, 0.64, 1 }, C.gold)
    S.Shadow(d, 10, 0.6)
    for k = 1, 9 do
      local p = d:CreateTexture(nil, "ARTWORK")
      p:SetTexture(MEDIA .. "Dot")
      p:SetSize(16, 16)
      p:SetVertexColor(0.22, 0.12, 0.35)
      p:SetPoint("CENTER", ((k - 1) % 3 - 1) * 26, -(math.floor((k - 1) / 3) - 1) * 26)
      pips[k] = p
    end
    die = d
    potText = S.Text(f, 16, "gold")
    potText:SetPoint("TOP", d, "BOTTOM", 0, -16)
    potText:SetJustifyH("CENTER")
    rollBtn = S.Button(f, L["Roll"], 130, 32, function()
      local m = ns.GameMatch()
      if m and not m.over and m.game == G.id and G.IsMyTurn(m) then ns.GameMove("R:" .. math.random(6)) end
    end, "primary")
    rollBtn:SetPoint("TOPRIGHT", potText, "BOTTOM", -6, -16)
    holdBtn = S.Button(f, L["Hold"], 130, 32, function()
      local m = ns.GameMatch()
      if m and not m.over and m.game == G.id and G.IsMyTurn(m) and m.pot > 0 then ns.GameMove("H") end
    end)
    holdBtn:SetPoint("TOPLEFT", potText, "BOTTOM", 6, -16)
    for k = 1, 2 do
      local y = -250 - (k - 1) * 44
      names[k] = S.Text(f, 12, k == 1 and "gold" or "dim")
      names[k]:SetPoint("TOPLEFT", 40, y)
      bars[k] = S.ProgressBar(f, 10)
      bars[k]:SetPoint("TOPLEFT", 40, y - 18)
      bars[k]:SetPoint("TOPRIGHT", -90, y - 18)
      if k == 2 then bars[k]:SetColors({ 0.8, 0.65, 1, 1 }, { 0.45, 0.3, 0.8, 1 }) end
      totals[k] = S.Text(f, 18, k == 1 and "gold" or "text")
      totals[k]:SetPoint("LEFT", bars[k], "RIGHT", 14, 0)
    end
  end

  function G.Start(m)
    m.turn, m.tot, m.pot = 1, { 0, 0 }, 0
    names[1]:SetText(L["You"])
    names[2]:SetText(m.oppShort)
    face(1)
    refresh(m)
  end

  local function nextTurn(m)
    m.pot = 0
    m.turn = 3 - m.turn
    refresh(m)
    ns.GameRefreshStatus()
  end

  function G.OnMove(m, data, mine)
    if (m.turn == myNum(m)) ~= mine or m.rolling then return end
    if data == "H" then
      if m.pot <= 0 then return end
      m.tot[m.turn] = m.tot[m.turn] + m.pot
      PlaySound(SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND or 120)
      if m.tot[m.turn] >= GOAL then
        refresh(m)
        ns.GameEnd(m.turn == myNum(m) and "win" or "lose")
        return
      end
      nextTurn(m)
      return
    end
    local n = tonumber(data:match("^R:(%d)$"))
    if not n or n < 1 or n > 6 then return end
    -- the die tumbles a moment, then shows the roll
    m.rolling = true
    rollBtn:SetEnabled(false); holdBtn:SetEnabled(false)
    PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    local clock, last = 0, 0
    S.Tween(die, { dur = 0.6, from = 0, to = 1, set = function(v, p)
      clock = p
      if p - last > 0.08 then last = p; face(math.random(6)) end
      die:SetScale(math.max(0.05, 1 + 0.12 * math.sin(p * math.pi)))
    end, done = function()
      die:SetScale(1)
      face(n)
      m.rolling = nil
      if m.over then return end
      if n == 1 then
        potText:SetText("|cffff2020" .. L["Lost!"] .. "|r")
        m.pot = 0
        ns.GameLater(0.9, nextTurn)
      else
        m.pot = m.pot + n
        refresh(m)
        ns.GameRefreshStatus()
      end
    end })
  end
  ns.RegisterGame(G)
end
