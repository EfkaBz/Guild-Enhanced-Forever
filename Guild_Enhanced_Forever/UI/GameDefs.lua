-- Guild Enhanced Forever: the mini-games. Each one: id, name, desc, icon, Build(frame),
-- Start(match), OnMove(match, data, mine), IsMyTurn(match), Mark(match, mine) (optional),
-- BotMove(match): the move the practice bot plays (it is never perfect, so it can be beaten).
-- The player who challenged plays first (player 1).
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient
local WHITE, MEDIA = S.WHITE, S.MEDIA

local P1 = { 1, 0.80, 0.32 }   -- gold
local P2 = { 0.41, 0.8, 0.94 }  -- blue

local function myNum(m) return m.first and 1 or 2 end

local outBounce = function(p)
  local n, d = 7.5625, 2.75
  if p < 1 / d then return n * p * p
  elseif p < 2 / d then p = p - 1.5 / d; return n * p * p + 0.75
  elseif p < 2.5 / d then p = p - 2.25 / d; return n * p * p + 0.9375
  else p = p - 2.625 / d; return n * p * p + 0.984375 end
end

-- pops a size in (from nothing, with an overshoot)
local function popIn(key, setSize, full, delay)
  setSize(0.01)
  S.Tween(key, { dur = 0.35, delay = delay, from = 0, to = 1, ease = "outBack", set = function(v)
    setSize(math.max(0.01, full * v))
  end })
end

-- gentle pulse of winning pieces
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

-- Tic-tac-toe ---------------------------------------------------------------------------------------------
do
  local G = { id = "ttt", name = "Tic-tac-toe", desc = "Line up three marks first.",
    icon = { "Interface\\Icons\\INV_Misc_Note_02", "Interface\\Icons\\INV_Misc_Note_01" } }
  local CELL, GAP = 96, 10
  local cells = {}
  local LINES = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 }, { 1, 5, 9 }, { 3, 5, 7 } }

  function G.IsMyTurn(m) return m.turn == myNum(m) end
  function G.Mark(m, mine)
    local n = mine and myNum(m) or 3 - myNum(m)
    return n == 1 and "|cffffcc52X|r" or "|cff69ccf0O|r"
  end

  local function drawMark(c, who, animate)
    c.x1:Hide(); c.x2:Hide(); c.o:Hide()
    if not who then return end
    if who == 1 then
      c.x1:Show(); c.x2:Show()
      local function size(v) c.x1:SetSize(v, 9); c.x2:SetSize(v, 9) end
      if animate then popIn(c.x1, size, 66) else size(66) end
    else
      c.o:Show()
      local function size(v) c.o:SetSize(v, v) end
      if animate then popIn(c.o, size, 64) else size(64) end
    end
  end

  function G.Build(f)
    local grid = CreateFrame("Frame", nil, f)
    local total = 3 * CELL + 2 * GAP
    grid:SetSize(total, total)
    grid:SetPoint("CENTER")
    for i = 1, 9 do
      local c = CreateFrame("Button", nil, grid)
      c:SetSize(CELL, CELL)
      c:SetPoint("TOPLEFT", ((i - 1) % 3) * (CELL + GAP), -math.floor((i - 1) / 3) * (CELL + GAP))
      S.Rounded(c, 10, C.btn1, C.bg2, C.trim)
      local hl = c:CreateTexture(nil, "BACKGROUND", nil, -6)
      hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
      S.Highlight(hl, 0.18)
      hl:SetAlpha(0)
      c.hl = hl
      c.win = c:CreateTexture(nil, "BACKGROUND", nil, -5)
      c.win:SetTexture(MEDIA .. "Glow")
      c.win:SetBlendMode("ADD")
      c.win:SetPoint("CENTER")
      c.win:SetSize(CELL * 1.6, CELL * 1.6)
      c.win:Hide()
      c.x1 = c:CreateTexture(nil, "ARTWORK"); c.x1:SetTexture(WHITE); c.x1:SetPoint("CENTER"); c.x1:SetRotation(math.rad(45))
      c.x2 = c:CreateTexture(nil, "ARTWORK"); c.x2:SetTexture(WHITE); c.x2:SetPoint("CENTER"); c.x2:SetRotation(math.rad(-45))
      c.x1:SetVertexColor(P1[1], P1[2], P1[3]); c.x2:SetVertexColor(P1[1], P1[2], P1[3])
      c.o = c:CreateTexture(nil, "ARTWORK"); c.o:SetTexture(MEDIA .. "Ring"); c.o:SetPoint("CENTER")
      c.o:SetVertexColor(P2[1], P2[2], P2[3])
      c.index = i
      c:SetScript("OnEnter", function(self)
        local m = ns.GameMatch()
        if m and not m.over and G.IsMyTurn(m) and not m.board[self.index] then
          S.FadeTo(self.hl, 1, 0.12); self:SetBorderColor(color(C.gold))
        end
      end)
      c:SetScript("OnLeave", function(self) S.FadeTo(self.hl, 0, 0.2); self:SetBorderColor(color(C.trim)) end)
      c:SetScript("OnClick", function(self)
        local m = ns.GameMatch()
        if m and not m.over and G.IsMyTurn(m) and not m.board[self.index] then
          S.FadeTo(self.hl, 0, 0.2)
          ns.GameMove(tostring(self.index))
        end
      end)
      cells[i] = c
    end
  end

  -- the bot: wins if it can, usually blocks, likes the center then the corners
  function G.BotMove(m)
    local bot, me = 3 - myNum(m), myNum(m)
    local free = {}
    for i = 1, 9 do if not m.board[i] then free[#free + 1] = i end end
    if #free == 0 then return end
    local function finishing(who)
      for _, l in ipairs(LINES) do
        local n, empty = 0, nil
        for _, k in ipairs(l) do
          if m.board[k] == who then n = n + 1 elseif not m.board[k] then empty = k end
        end
        if n == 2 and empty then return empty end
      end
    end
    local w = finishing(bot)
    if w then return w end
    if math.random() < 0.85 then
      local b = finishing(me)
      if b then return b end
      if not m.board[5] then return 5 end
      local corners = {}
      for _, k in ipairs({ 1, 3, 7, 9 }) do if not m.board[k] then corners[#corners + 1] = k end end
      if #corners > 0 then return corners[math.random(#corners)] end
    end
    return free[math.random(#free)]
  end

  function G.Start(m)
    m.board, m.turn = {}, 1
    for i, c in ipairs(cells) do
      drawMark(c, nil)
      c.win:Hide()
      c:SetAlpha(0)
      S.Tween(c, { dur = 0.25, delay = i * 0.03, from = 0, to = 1, set = function(v) c:SetAlpha(v) end })
    end
  end

  function G.OnMove(m, data, mine)
    local i = tonumber(data)
    if not i or i < 1 or i > 9 or m.board[i] then return end
    local who = m.turn
    if (who == myNum(m)) ~= mine then return end
    m.board[i] = who
    drawMark(cells[i], who, true)
    PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    for _, l in ipairs(LINES) do
      if m.board[l[1]] == who and m.board[l[2]] == who and m.board[l[3]] == who then
        local glows = {}
        for _, k in ipairs(l) do
          local col = who == 1 and P1 or P2
          cells[k].win:SetVertexColor(col[1], col[2], col[3], 0.6)
          cells[k].win:Show()
          glows[#glows + 1] = cells[k].win
        end
        pulse(glows)
        ns.GameEnd(who == myNum(m) and "win" or "lose")
        return
      end
    end
    local full = true
    for k = 1, 9 do if not m.board[k] then full = false end end
    if full then ns.GameEnd("draw") return end
    m.turn = 3 - who
    ns.GameRefreshStatus()
  end
  ns.RegisterGame(G)
end

-- Connect four --------------------------------------------------------------------------------------------
do
  local G = { id = "c4", name = "Connect four", desc = "Drop discs, line up four.",
    icon = { "Interface\\Icons\\INV_Misc_Coin_01", "Interface\\Icons\\INV_Misc_Coin_02" } }
  local COLS, ROWS, CELL, PAD = 7, 6, 52, 10
  local discs, holes, colButtons = {}, {}, {}
  local boardFrame, ghost

  function G.IsMyTurn(m) return m.turn == myNum(m) end
  function G.Mark(m, mine)
    local n = mine and myNum(m) or 3 - myNum(m)
local col = n == 1 and P1 or P2
    return string.format("|T%sDot:12:12:0:0:32:32:0:32:0:32:%d:%d:%d|t", MEDIA, math.floor(col[1] * 255), math.floor(col[2] * 255), math.floor(col[3] * 255))
  end

  local function cellCenter(c, r) -- r = 1 at the bottom
    return PAD + (c - 0.5) * CELL, PAD + (r - 0.5) * CELL
  end

  function G.Build(f)
    local w, h = COLS * CELL + 2 * PAD, ROWS * CELL + 2 * PAD
    boardFrame = CreateFrame("Frame", nil, f)
    boardFrame:SetSize(w, h)
    boardFrame:SetPoint("CENTER", 0, -14)
    S.Rounded(boardFrame, 12, { 0.2, 0.13, 0.36, 1 }, { 0.1, 0.06, 0.2, 1 }, C.ring)
    -- the disc layer sits under the holes' rims
    local discLayer = CreateFrame("Frame", nil, f)
    discLayer:SetAllPoints(boardFrame)
    discLayer:SetFrameLevel(boardFrame:GetFrameLevel() + 2)
    for c = 1, COLS do
      discs[c], holes[c] = {}, {}
      for r = 1, ROWS do
        local x, y = cellCenter(c, r)
        local hole = boardFrame:CreateTexture(nil, "ARTWORK")
        hole:SetTexture(MEDIA .. "Dot")
        hole:SetSize(40, 40)
        hole:SetPoint("CENTER", boardFrame, "BOTTOMLEFT", x, y)
        hole:SetVertexColor(0.03, 0.02, 0.06, 1)
        holes[c][r] = hole
        local d = discLayer:CreateTexture(nil, "ARTWORK")
        d:SetTexture(MEDIA .. "Dot")
        d:SetSize(40, 40)
        d.shine = discLayer:CreateTexture(nil, "OVERLAY")
        d.shine:SetTexture(MEDIA .. "Dot")
        d.shine:SetSize(14, 14)
        d.shine:SetPoint("CENTER", d, "CENTER", -7, 7)
        d.shine:SetVertexColor(1, 1, 1, 0.35)
        d.glow = discLayer:CreateTexture(nil, "BACKGROUND")
        d.glow:SetTexture(MEDIA .. "Glow")
        d.glow:SetBlendMode("ADD")
        d.glow:SetSize(70, 70)
        d.glow:SetPoint("CENTER", d)
        d.x, d.y = x, y
        discs[c][r] = d
      end
    end
    -- rims drawn over the discs
    local rims = CreateFrame("Frame", nil, f)
    rims:SetAllPoints(boardFrame)
    rims:SetFrameLevel(discLayer:GetFrameLevel() + 1)
    for c = 1, COLS do
      for r = 1, ROWS do
        local x, y = cellCenter(c, r)
        local rim = rims:CreateTexture(nil, "ARTWORK")
        rim:SetTexture(MEDIA .. "Ring")
        rim:SetSize(44, 44)
        rim:SetPoint("CENTER", boardFrame, "BOTTOMLEFT", x, y)
        rim:SetVertexColor(0.45, 0.32, 0.7, 0.9)
      end
    end
    -- hover disc above the column
    ghost = discLayer:CreateTexture(nil, "OVERLAY")
    ghost:SetTexture(MEDIA .. "Dot")
    ghost:SetSize(36, 36)
    ghost:Hide()
    -- one invisible button per column
    for c = 1, COLS do
      local b = CreateFrame("Button", nil, f)
      b:SetFrameLevel(rims:GetFrameLevel() + 2)
      b:SetSize(CELL, h + 40)
      b:SetPoint("BOTTOMLEFT", boardFrame, "BOTTOMLEFT", PAD + (c - 1) * CELL, 0)
      local hl = b:CreateTexture(nil, "BACKGROUND")
      hl:SetPoint("BOTTOMLEFT", 2, PAD); hl:SetPoint("TOPRIGHT", -2, -40 - PAD)
      gradient(hl, { 1, 0.85, 0.5, 0.0 }, { 1, 0.85, 0.5, 0.12 })
      hl:SetAlpha(0)
      b.col, b.hl = c, hl
      b:SetScript("OnEnter", function(self)
        local m = ns.GameMatch()
        if not (m and not m.over and G.IsMyTurn(m)) or m.grid[self.col][ROWS] then return end
        S.FadeTo(self.hl, 1, 0.12)
        local col = myNum(m) == 1 and P1 or P2
        ghost:SetVertexColor(col[1], col[2], col[3], 0.6)
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", boardFrame, "BOTTOMLEFT", cellCenter(self.col, ROWS + 0.75))
        ghost:Show()
      end)
      b:SetScript("OnLeave", function(self) S.FadeTo(self.hl, 0, 0.2); ghost:Hide() end)
      b:SetScript("OnClick", function(self)
        local m = ns.GameMatch()
        if m and not m.over and G.IsMyTurn(m) and not m.grid[self.col][ROWS] then
          ghost:Hide()
          S.FadeTo(self.hl, 0, 0.2)
          ns.GameMove(tostring(self.col))
        end
      end)
      colButtons[c] = b
    end
  end

  function G.Start(m)
    m.grid, m.turn = {}, 1
    for c = 1, COLS do
      m.grid[c] = {}
      for r = 1, ROWS do
        local d = discs[c][r]
        d:Hide(); d.shine:Hide(); d.glow:Hide()
      end
    end
    ghost:Hide()
  end

  local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }
  local function line(m, c, r, who)
    for _, d in ipairs(DIRS) do
      local cells = { { c, r } }
      for s = -1, 1, 2 do
        local x, y = c + d[1] * s, r + d[2] * s
        while m.grid[x] and m.grid[x][y] == who do
          cells[#cells + 1] = { x, y }
          x, y = x + d[1] * s, y + d[2] * s
        end
      end
      if #cells >= 4 then return cells end
    end
  end

  local function dropRow(m, c)
    for r = 1, ROWS do if not m.grid[c][r] then return r end end
  end

  -- the bot: wins if it can, usually blocks, avoids giving a win just above, prefers the center
  function G.BotMove(m)
    local bot, me = 3 - myNum(m), myNum(m)
    local cols = {}
    for c = 1, COLS do if dropRow(m, c) then cols[#cols + 1] = c end end
    if #cols == 0 then return end
    local function wins(c, who)
      local r = dropRow(m, c)
      if not r then return false end
      m.grid[c][r] = who
      local ok = line(m, c, r, who) ~= nil
      m.grid[c][r] = nil
      return ok
    end
    for _, c in ipairs(cols) do if wins(c, bot) then return c end end
    local careful = math.random() < 0.85
    if careful then
      for _, c in ipairs(cols) do if wins(c, me) then return c end end
    end
    local best, bestScore
    for _, c in ipairs(cols) do
      local score = 4 - math.abs(c - 4) + math.random() * 1.5
      if careful then
        local r = dropRow(m, c)
        m.grid[c][r] = bot
        if wins(c, me) then score = score - 10 end
        m.grid[c][r] = nil
      end
      if not bestScore or score > bestScore then best, bestScore = c, score end
    end
    return best
  end

  function G.OnMove(m, data, mine)
    local c = tonumber(data)
    if not c or c < 1 or c > COLS then return end
    local who = m.turn
    if (who == myNum(m)) ~= mine then return end
    local r
    for k = 1, ROWS do if not m.grid[c][k] then r = k break end end
    if not r then return end
    m.grid[c][r] = who
    local d = discs[c][r]
    local col = who == 1 and P1 or P2
    d:SetVertexColor(col[1], col[2], col[3], 1)
    d:Show(); d.shine:Show()
    -- falls from above the board and bounces
    local top = PAD + (ROWS + 0.75) * CELL
    S.Tween(d, { dur = 0.25 + 0.06 * (ROWS - r), from = top, to = d.y, ease = outBounce, set = function(v)
      d:ClearAllPoints()
      d:SetPoint("CENTER", boardFrame, "BOTTOMLEFT", d.x, v)
    end })
    PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    local won = line(m, c, r, who)
    if won then
      ns.GameLater(0.6, function()
        local glows = {}
        for _, p in ipairs(won) do
          local g = discs[p[1]][p[2]].glow
          g:SetVertexColor(col[1], col[2], col[3], 0.7)
          g:Show()
          glows[#glows + 1] = g
        end
        pulse(glows)
      end)
      ns.GameEnd(who == myNum(m) and "win" or "lose")
      return
    end
    local full = true
    for k = 1, COLS do if not m.grid[k][ROWS] then full = false end end
    if full then ns.GameEnd("draw") return end
    m.turn = 3 - who
    ns.GameRefreshStatus()
  end
  ns.RegisterGame(G)
end

-- Rock, paper, scissors ------------------------------------------------------------------------------------
do
  local G = { id = "rps", name = "Rock, paper, scissors", desc = "First to three rounds wins.",
    icon = { "Interface\\Icons\\INV_Misc_Bandage_15", "Interface\\Icons\\INV_Gauntlets_04" } }
  local WIN_AT = 3
  local CHOICES = {
    R = { "Rock", { "Interface\\Icons\\INV_Stone_15", "Interface\\Icons\\INV_Ore_Copper_01" } },
    P = { "Paper", { "Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\INV_Scroll_03" } },
    S = { "Scissors", { "Interface\\Icons\\INV_Weapon_ShortBlade_05", "Interface\\Icons\\INV_Weapon_ShortBlade_01" } },
  }
  local BEATS = { R = "S", P = "R", S = "P" }
  local mine, theirs, score, buttons = nil, nil, nil, {}

  function G.IsMyTurn(m) return m.myPick == nil end
  -- the bot picks once you have picked (it never sees your choice)
  function G.BotMove(m)
    if m.oppPick then return end
    local keys = { "R", "P", "S" }
    return keys[math.random(3)]
  end

  local function card(f, x)
    local c = CreateFrame("Frame", nil, f)
    c:SetSize(120, 120)
    c:SetPoint("TOP", x, -10)
    S.Rounded(c, 12, C.btn1, C.bg2, C.trim)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("CENTER")
    c.icon:SetSize(80, 80)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.q = S.Text(c, 40, "muted")
    c.q:SetPoint("CENTER")
    c.q:SetJustifyH("CENTER")
    c.label = S.Text(c, 12, "dim")
    c.label:SetPoint("TOP", c, "BOTTOM", 0, -6)
    c.label:SetJustifyH("CENTER")
    c.glow = c:CreateTexture(nil, "BACKGROUND", nil, -8)
    c.glow:SetTexture(MEDIA .. "Glow")
    c.glow:SetBlendMode("ADD")
    c.glow:SetPoint("CENTER")
    c.glow:SetSize(220, 220)
    c.glow:Hide()
    function c:SetHidden(text)
      self.icon:Hide()
      self.q:Show()
      self.q:SetFontObject(S.Font(text and 16 or 40))
      self.q:SetText(text or "?")
    end
    function c:Reveal(choice, animate)
      self.q:Hide()
      self.icon:Show()
      self.icon:SetTexture(S.PickIcon(CHOICES[choice][2]))
      if animate then
        -- flips: width closes and opens again
        S.Tween(self, { dur = 0.35, from = 0, to = 1, set = function(v)
          self.icon:SetWidth(math.max(1, 80 * math.abs(1 - 2 * v)))
        end })
      end
    end
    return c
  end

  function G.Build(f)
    mine = card(f, -110)
    theirs = card(f, 110)
    score = S.Text(f, 26, "gold")
    score:SetPoint("TOP", 0, -52)
    score:SetJustifyH("CENTER")
    local vs = S.Text(f, 11, "muted")
    vs:SetPoint("TOP", score, "BOTTOM", 0, -4)
    vs:SetText("VS")
    for n, key in ipairs({ "R", "P", "S" }) do
      local ch = CHOICES[key]
      local b = CreateFrame("Button", nil, f)
      b:SetSize(96, 96)
      b:SetPoint("BOTTOM", (n - 2) * 116, 20)
      S.Rounded(b, 10, C.btn1, C.bg2, C.trim)
      b.icon = b:CreateTexture(nil, "ARTWORK")
      b.icon:SetPoint("TOP", 0, -10)
      b.icon:SetSize(56, 56)
      b.icon:SetTexture(S.PickIcon(ch[2]))
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b.label = S.Text(b, 12, "text")
      b.label:SetPoint("BOTTOM", 0, 8)
      b.label:SetText(L[ch[1]])
      b.key = key
      b:SetScript("OnEnter", function(self)
        local m = ns.GameMatch()
        if m and not m.over and G.IsMyTurn(m) then self:SetBorderColor(color(C.gold)) end
      end)
      b:SetScript("OnLeave", function(self) self:SetBorderColor(color(C.trim)) end)
      b:SetScript("OnClick", function(self)
        local m = ns.GameMatch()
        if m and not m.over and G.IsMyTurn(m) then ns.GameMove(self.key) end
      end)
      buttons[n] = b
    end
  end

  local function refresh(m)
    score:SetText(m.r[1] .. "  -  " .. m.r[2])
    for _, b in ipairs(buttons) do b:SetAlpha((not m.over and m.myPick == nil) and 1 or 0.4) end
  end

  local function newRound(m)
    m.myPick, m.oppPick = nil, nil
    mine:SetHidden(); theirs:SetHidden()
    mine.glow:Hide(); theirs.glow:Hide()
    mine:SetBorderColor(color(C.trim)); theirs:SetBorderColor(color(C.trim))
    refresh(m)
    ns.GameRefreshStatus()
  end

  function G.Start(m)
    m.r = { 0, 0 }
    mine.label:SetText(L["You"])
    theirs.label:SetText(m.oppShort)
    newRound(m)
  end

  local function resolve(m)
    mine:Reveal(m.myPick, true)
    theirs:Reveal(m.oppPick, true)
    local a, b = m.myPick, m.oppPick
    local winner = (a == b) and 0 or (BEATS[a] == b and 1 or 2)
    if winner > 0 then
      m.r[winner] = m.r[winner] + 1
      local c = winner == 1 and mine or theirs
      c.glow:SetVertexColor(1, 0.8, 0.35, 0.6)
      c.glow:Show()
      c:SetBorderColor(color(C.gold))
    end
    refresh(m)
    if m.r[1] >= WIN_AT then ns.GameEnd("win") return end
    if m.r[2] >= WIN_AT then ns.GameEnd("lose") return end
    ns.GameLater(1.8, newRound)
  end

  function G.OnMove(m, data, isMine)
    if not CHOICES[data] then return end
    if isMine then
      if m.myPick then return end
      m.myPick = data
      mine:Reveal(data, true)
    else
      if m.oppPick then return end
      m.oppPick = data
      theirs:SetHidden(L["Ready"])
    end
    refresh(m)
    if m.myPick and m.oppPick then resolve(m) else ns.GameRefreshStatus() end
  end

  ns.RegisterGame(G)
end

-- Death roll -----------------------------------------------------------------------------------------------
-- the famous guild game: each player /rolls 1-N with N = the last roll; whoever rolls 1 loses.
-- The real /roll is used (visible around you); the result is sent to the opponent.
do
  local START = 1000
  local G = { id = "dr", name = "Death roll", desc = "/roll from %d down; whoever rolls 1 loses.", descArg = START,
    icon = { "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", "Interface\\Icons\\INV_Misc_Bone_ElfSkull_01" } }
  local big, sub, rollBtn, logLines = nil, nil, nil, {}
  local waiting -- max of the roll I asked for

  function G.IsMyTurn(m) return m.turn == myNum(m) end
  function G.BotMove(m) return math.random(1, m.max) end

  -- "%s rolls %d (%d-%d)" from the game, as a pattern
  local ROLL
  do
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    ROLL = "^" .. fmt:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
  end

  local function refresh(m)
    big:SetText(m.max)
    sub:SetText(string.format(L["Next roll: 1 - %d"], m.max))
    rollBtn:SetEnabled(not m.over and G.IsMyTurn(m) and not waiting)
  end

  local function log(m)
    for i, line in ipairs(logLines) do
      local e = m.log[#m.log - i + 1]
      if e then
        local who = e.mine and ("|cffffd100" .. L["You"] .. "|r") or m.oppShort
        line:SetText(string.format(L["%s rolled %d (1-%d)"], who, e.v, e.max))
        line:SetAlpha(1 - (i - 1) * 0.12)
        line:Show()
      else
        line:Hide()
      end
    end
  end

  function G.Build(f)
    big = S.Text(f, 48, "gold")
    big:SetPoint("TOP", 0, -24)
    big:SetJustifyH("CENTER")
    local halo = f:CreateTexture(nil, "BACKGROUND")
    halo:SetTexture(MEDIA .. "Glow")
    halo:SetBlendMode("ADD")
    halo:SetSize(220, 120)
    halo:SetPoint("CENTER", big)
    halo:SetVertexColor(1, 0.7, 0.3, 0.3)
    sub = S.Text(f, 12, "dim")
    sub:SetPoint("TOP", big, "BOTTOM", 0, -8)
    sub:SetJustifyH("CENTER")
    rollBtn = S.Button(f, L["Roll!"], 160, 34, function()
      local m = ns.GameMatch()
      if m and not m.over and G.IsMyTurn(m) and not waiting then
        -- against the bot the roll stays in the addon (no /roll spam around you)
        if m.bot then ns.GameMove(tostring(math.random(1, m.max))) return end
        waiting = m.max
        rollBtn:SetEnabled(false)
        RandomRoll(1, m.max)
        -- no result seen (should not happen): allow another try
        C_Timer.After(4, function() if waiting then waiting = nil; refresh(m) end end)
      end
    end, "primary")
    rollBtn:SetPoint("TOP", sub, "BOTTOM", 0, -18)
    rollBtn.text:SetFontObject(S.Font(15))
    for i = 1, 8 do
      local fs = S.Text(f, 12, "text")
      fs:SetPoint("TOP", rollBtn, "BOTTOM", 0, -18 - (i - 1) * 20)
      fs:SetJustifyH("CENTER")
      logLines[i] = fs
    end
    -- my own roll result
    local ev = CreateFrame("Frame", nil, f)
    ev:RegisterEvent("CHAT_MSG_SYSTEM")
    ev:SetScript("OnEvent", function(_, _, msg)
      if not waiting or not msg then return end
      local who, v, lo, hi = msg:match(ROLL)
      if who and ns.Short(who) == ns.GameMe() and tonumber(lo) == 1 and tonumber(hi) == waiting then
        waiting = nil
        ns.GameMove(v)
      end
    end)
  end

  function G.Start(m)
    m.max, m.turn, m.log = START, 1, {}
    waiting = nil
    log(m)
    refresh(m)
  end

  function G.OnMove(m, data, mine)
    local v = tonumber(data)
    if not v or v < 1 or v > m.max then return end
    local who = m.turn
    if (who == myNum(m)) ~= mine then return end
    table.insert(m.log, { v = v, max = m.max, mine = mine })
    -- the number counts down to the roll
    local from = m.max
    S.Tween(big, { dur = 0.6, from = from, to = v, ease = "outCubic", set = function(x) big:SetText(math.floor(x + 0.5)) end })
    log(m)
    if v == 1 then
      big:SetTextColor(color(C.bad))
      ns.GameLater(0.7, function() big:SetTextColor(color(C.gold)) end)
      m.max = 1
      ns.GameEnd(mine and "lose" or "win")
      refresh(m)
      return
    end
    m.max = v
    m.turn = 3 - who
    refresh(m)
    big:SetText(from)
    ns.GameRefreshStatus()
  end
  ns.RegisterGame(G)
end
