-- Guild Enhanced Forever: chess. Same contract as UI\GameDefs.lua.
-- Full rules: castling, en passant, promotion (always a queen), check, checkmate, stalemate,
-- draws by the 50-move rule and by insufficient material. The challenger plays white.
-- A move on the network: "from:to" (squares 1-64, a1 = 1, h1 = 8, a8 = 57); both sides check it.
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color = S.C, S.Color
local WHITE, MEDIA = S.WHITE, S.MEDIA

local P1 = { 1, 0.80, 0.32 }   -- gold: white
local P2 = { 0.41, 0.8, 0.94 }  -- blue: black

local function dotMark(col)
  return string.format("|T%sDot:12:12:0:0:64:64:0:64:0:64:%d:%d:%d|t", MEDIA,
    math.floor(col[1] * 255), math.floor(col[2] * 255), math.floor(col[3] * 255))
end

-- Rules ----------------------------------------------------------------------------------------------------
local function sq(f, r) return (r - 1) * 8 + f end
local function fileOf(s) return (s - 1) % 8 + 1 end
local function rankOf(s) return math.floor((s - 1) / 8) + 1 end
local function inside(f, r) return f >= 1 and f <= 8 and r >= 1 and r <= 8 end
local function other(c) return c == "w" and "b" or "w" end

local KNIGHT = { { 1, 2 }, { 2, 1 }, { -1, 2 }, { -2, 1 }, { 1, -2 }, { 2, -1 }, { -1, -2 }, { -2, -1 } }
local KING = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local DIAG = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local ORTH = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function newPosition()
  local b = {}
  local back = { "R", "N", "B", "Q", "K", "B", "N", "R" }
  for f = 1, 8 do
    b[sq(f, 1)] = "w" .. back[f]
    b[sq(f, 2)] = "wP"
    b[sq(f, 7)] = "bP"
    b[sq(f, 8)] = "b" .. back[f]
  end
  return { b = b, turn = "w", cr = { wK = true, wQ = true, bK = true, bQ = true }, ep = nil, half = 0 }
end

-- is square s attacked by the side "by"?
local function attacked(pos, s, by)
  local b = pos.b
  local f, r = fileOf(s), rankOf(s)
  local pr = by == "w" and r - 1 or r + 1
  for _, df in ipairs({ -1, 1 }) do
    if inside(f + df, pr) and b[sq(f + df, pr)] == by .. "P" then return true end
  end
  for _, d in ipairs(KNIGHT) do
    if inside(f + d[1], r + d[2]) and b[sq(f + d[1], r + d[2])] == by .. "N" then return true end
  end
  for _, d in ipairs(KING) do
    if inside(f + d[1], r + d[2]) and b[sq(f + d[1], r + d[2])] == by .. "K" then return true end
  end
  for pass, dirs in ipairs({ DIAG, ORTH }) do
    local a1, a2 = by .. (pass == 1 and "B" or "R"), by .. "Q"
    for _, d in ipairs(dirs) do
      local ff, rr = f + d[1], r + d[2]
      while inside(ff, rr) do
        local p = b[sq(ff, rr)]
        if p then
          if p == a1 or p == a2 then return true end
          break
        end
        ff, rr = ff + d[1], rr + d[2]
      end
    end
  end
  return false
end

local function kingSquare(pos, c)
  for s = 1, 64 do if pos.b[s] == c .. "K" then return s end end
end

local function inCheck(pos, c)
  local k = kingSquare(pos, c)
  return k ~= nil and attacked(pos, k, other(c))
end

-- moves that follow the pieces' paths, without checking that the own king stays safe
local function pseudo(pos)
  local b, me = pos.b, pos.turn
  local opp = other(me)
  local list = {}
  local function add(from, to, extra)
    local mv = { from = from, to = to }
    if extra then for k, v in pairs(extra) do mv[k] = v end end
    list[#list + 1] = mv
  end
  for s = 1, 64 do
    local p = b[s]
    if p and p:sub(1, 1) == me then
      local t = p:sub(2, 2)
      local f, r = fileOf(s), rankOf(s)
      if t == "P" then
        local dr = me == "w" and 1 or -1
        local last, start = me == "w" and 8 or 1, me == "w" and 2 or 7
        local r1 = r + dr
        if inside(f, r1) and not b[sq(f, r1)] then
          add(s, sq(f, r1), r1 == last and { promo = "Q" } or nil)
          if r == start and not b[sq(f, r + 2 * dr)] then add(s, sq(f, r + 2 * dr), { double = true }) end
        end
        for _, df in ipairs({ -1, 1 }) do
          if inside(f + df, r1) then
            local to = sq(f + df, r1)
            local q = b[to]
            if q and q:sub(1, 1) == opp then
              add(s, to, r1 == last and { promo = "Q" } or nil)
            elseif to == pos.ep then
              add(s, to, { ep = sq(f + df, r) })
            end
          end
        end
      elseif t == "N" or t == "K" then
        for _, d in ipairs(t == "N" and KNIGHT or KING) do
          local ff, rr = f + d[1], r + d[2]
          if inside(ff, rr) then
            local q = b[sq(ff, rr)]
            if not q or q:sub(1, 1) == opp then add(s, sq(ff, rr)) end
          end
        end
        if t == "K" then
          local home = me == "w" and 1 or 8
          if s == sq(5, home) and not attacked(pos, s, opp) then
            if pos.cr[me .. "K"] and b[sq(8, home)] == me .. "R" and not b[sq(6, home)] and not b[sq(7, home)]
              and not attacked(pos, sq(6, home), opp) and not attacked(pos, sq(7, home), opp) then
              add(s, sq(7, home), { rf = sq(8, home), rt = sq(6, home) })
            end
            if pos.cr[me .. "Q"] and b[sq(1, home)] == me .. "R" and not b[sq(2, home)] and not b[sq(3, home)]
              and not b[sq(4, home)] and not attacked(pos, sq(4, home), opp) and not attacked(pos, sq(3, home), opp) then
              add(s, sq(3, home), { rf = sq(1, home), rt = sq(4, home) })
            end
          end
        end
      else
        local dirs = t == "B" and DIAG or t == "R" and ORTH or KING
        for _, d in ipairs(dirs) do
          local ff, rr = f + d[1], r + d[2]
          while inside(ff, rr) do
            local q = b[sq(ff, rr)]
            if q then
              if q:sub(1, 1) == opp then add(s, sq(ff, rr)) end
              break
            end
            add(s, sq(ff, rr))
            ff, rr = ff + d[1], rr + d[2]
          end
        end
      end
    end
  end
  return list
end

-- the position after a move (a new table: the old one is kept)
local function play(pos, mv)
  local b = {}
  for i = 1, 64 do b[i] = pos.b[i] end
  local me = pos.turn
  local p = b[mv.from]
  local captured = b[mv.to]
  b[mv.to] = mv.promo and (me .. mv.promo) or p
  b[mv.from] = nil
  if mv.ep then captured = b[mv.ep]; b[mv.ep] = nil end
  if mv.rf then b[mv.rt] = b[mv.rf]; b[mv.rf] = nil end
  local cr = { wK = pos.cr.wK, wQ = pos.cr.wQ, bK = pos.cr.bK, bQ = pos.cr.bQ }
  if p == me .. "K" then cr[me .. "K"], cr[me .. "Q"] = false, false end
  for _, x in ipairs({ mv.from, mv.to }) do
    if x == 1 then cr.wQ = false elseif x == 8 then cr.wK = false
    elseif x == 57 then cr.bQ = false elseif x == 64 then cr.bK = false end
  end
  local ep = mv.double and (mv.from + mv.to) / 2 or nil
  local half = (p:sub(2, 2) == "P" or captured) and 0 or pos.half + 1
  return { b = b, turn = other(me), cr = cr, ep = ep, half = half, captured = captured }
end

local function legalMoves(pos)
  local list = {}
  for _, mv in ipairs(pseudo(pos)) do
    local np = play(pos, mv)
    if not inCheck(np, pos.turn) then list[#list + 1] = mv end
  end
  return list
end

-- only kings, or a king with one bishop or knight against a lone king: nobody can win
local function insufficient(pos)
  local minor = 0
  for s = 1, 64 do
    local p = pos.b[s]
    if p then
      local t = p:sub(2, 2)
      if t == "P" or t == "R" or t == "Q" then return false end
      if t == "B" or t == "N" then minor = minor + 1 end
    end
  end
  return minor <= 1
end

-- "mate", "stalemate", "fifty", "material" or nil (the game goes on)
local function outcome(pos)
  if #legalMoves(pos) == 0 then return inCheck(pos, pos.turn) and "mate" or "stalemate" end
  if pos.half >= 100 then return "fifty" end
  if insufficient(pos) then return "material" end
end

-- Bot: looks two half-moves ahead (its move, your best answer), material plus a little
-- position, with some noise so it can be beaten ------------------------------------------------------------------
local VALUE = { P = 100, N = 320, B = 330, R = 500, Q = 900, K = 0 }
local function evaluate(pos, side)
  local score = 0
  for s = 1, 64 do
    local p = pos.b[s]
    if p then
      local t = p:sub(2, 2)
      local f, r = fileOf(s), rankOf(s)
      local v = VALUE[t]
      if t == "N" or t == "B" or t == "P" then
        -- the center is worth a little, pawns like to move up
        v = v + (4 - math.abs(4.5 - f)) * 4 + (4 - math.abs(4.5 - r)) * 3
        if t == "P" then v = v + (p:sub(1, 1) == "w" and (r - 2) or (7 - r)) * 6 end
      end
      score = score + (p:sub(1, 1) == side and v or -v)
    end
  end
  return score
end

local function botChoice(pos)
  local side = pos.turn
  local moves = legalMoves(pos)
  if #moves == 0 then return end
  local best, bestScore = nil, -math.huge
  for _, mv in ipairs(moves) do
    local np = play(pos, mv)
    local replies = legalMoves(np)
    local score
    if #replies == 0 then
      score = inCheck(np, np.turn) and 100000 or 0
    else
      score = math.huge
      for _, rp in ipairs(replies) do
        local v = evaluate(play(np, rp), side)
        if v < score then score = v end
        if score <= bestScore then break end -- this move is already worse than the best one
      end
    end
    score = score + math.random(0, 45)
    if score > bestScore then best, bestScore = mv, score end
  end
  return best
end

-- Game -------------------------------------------------------------------------------------------------
do
  local G = { id = "chess", name = "Chess", desc = "Checkmate the enemy king.",
    icon = { "Interface\\Icons\\INV_Crown_01", "Interface\\Icons\\INV_Crown_02" } }
  local CELL = 46
  local LIGHT, DARK = { 0.86, 0.78, 0.6 }, { 0.45, 0.32, 0.2 }
  local ICONS = {
    K = { "Interface\\Icons\\INV_Crown_01", "Interface\\Icons\\INV_Helmet_25" },
    Q = { "Interface\\Icons\\INV_Crown_02", "Interface\\Icons\\INV_Jewelry_Necklace_01" },
    R = { "Interface\\Icons\\INV_Shield_06", "Interface\\Icons\\INV_Shield_04" },
    B = { "Interface\\Icons\\INV_Staff_08", "Interface\\Icons\\INV_Staff_13" },
    N = { "Interface\\Icons\\Ability_Mount_RidingHorse", "Interface\\Icons\\Ability_Hunter_Pet_Horse" },
    P = { "Interface\\Icons\\INV_Sword_04", "Interface\\Icons\\INV_Sword_27" },
  }
  local NAMES = { K = "King", Q = "Queen", R = "Rook", B = "Bishop", N = "Knight", P = "Pawn" }
  local LETTER = { K = "K", Q = "Q", R = "R", B = "B", N = "N", P = "" }
  local cells, files, ranks = {}, {}, {}
  local info, capturedMine, capturedTheirs, history, checkText

  local function myColor(m) return m.first and "w" or "b" end
  function G.IsMyTurn(m) return m.pos ~= nil and m.pos.turn == myColor(m) end
  function G.Mark(m, mine)
    local c = mine and myColor(m) or other(myColor(m))
    return dotMark(c == "w" and P1 or P2)
  end
  function G.BotMove(m)
    local mv = botChoice(m.pos)
    return mv and (mv.from .. ":" .. mv.to)
  end

  local function squareName(s) return string.char(96 + fileOf(s)) .. rankOf(s) end

  -- the square shown at screen column x, row y (1, 1 = top left): your own pieces at the bottom
  local function squareAt(m, x, y)
    if myColor(m) == "w" then return sq(x, 9 - y) end
    return sq(9 - x, y)
  end

  local function refresh(m)
    local pos = m.pos
    local check = inCheck(pos, pos.turn) and kingSquare(pos, pos.turn)
    local targets = {}
    if m.sel then
      for _, mv in ipairs(m.legal) do if mv.from == m.sel then targets[mv.to] = mv end end
    end
    for y = 1, 8 do
      for x = 1, 8 do
        local c = cells[(y - 1) * 8 + x]
        local s = squareAt(m, x, y)
        c.square = s
        local p = pos.b[s]
        if p then
          c.piece:Show()
          local col = p:sub(1, 1) == "w" and P1 or P2
          c.disc:SetVertexColor(col[1], col[2], col[3], 1)
          c.icon:SetTexture(S.PickIcon(ICONS[p:sub(2, 2)]))
          c.icon:SetDesaturated(p:sub(1, 1) == "b")
          c.icon:SetVertexColor(1, 1, 1)
          if p:sub(1, 1) == "b" then c.icon:SetVertexColor(0.7, 0.85, 1) end
        else
          c.piece:Hide()
        end
        c.last:SetShown(m.lastFrom == s or m.lastTo == s)
        c.selTex:SetShown(m.sel == s)
        c.check:SetShown(check == s)
        c.dot:SetShown(targets[s] ~= nil and not p)
        c.ring:SetShown(targets[s] ~= nil and p ~= nil)
      end
    end
    for i = 1, 8 do
      files[i]:SetText(string.char(96 + fileOf(squareAt(m, i, 8))))
      ranks[i]:SetText(rankOf(squareAt(m, 1, i)))
    end
    -- captured pieces: what each side has taken
    local count = { w = {}, b = {} }
    for _, t in ipairs({ "P", "N", "B", "R", "Q" }) do count.w[t], count.b[t] = 0, 0 end
    for s = 1, 64 do
      local p = pos.b[s]
      if p and count[p:sub(1, 1)][p:sub(2, 2)] then
        count[p:sub(1, 1)][p:sub(2, 2)] = count[p:sub(1, 1)][p:sub(2, 2)] + 1
      end
    end
    local START = { P = 8, N = 2, B = 2, R = 2, Q = 1 }
    local function lost(c)
      local parts = {}
      for _, t in ipairs({ "Q", "R", "B", "N", "P" }) do
        local n = START[t] - count[c][t]
        if n > 0 then parts[#parts + 1] = string.format("|T%s:16:16|t%s", S.PickIcon(ICONS[t]), n > 1 and ("x" .. n) or "") end
      end
      return #parts > 0 and table.concat(parts, " ") or "|cff777777-|r"
    end
    capturedMine:SetText(lost(other(myColor(m))))
    capturedTheirs:SetText(lost(myColor(m)))
    -- the last moves, numbered
    local lines = {}
    local first = math.max(1, #m.hist - 13)
    if first % 2 == 0 then first = first - 1 end
    for i = first, #m.hist, 2 do
      lines[#lines + 1] = string.format("|cff999999%d.|r %s  %s", (i + 1) / 2, m.hist[i], m.hist[i + 1] or "")
    end
    history:SetText(table.concat(lines, "\n"))
    checkText:SetText(check and not m.over and ("|cffff2020" .. L["Check!"] .. "|r") or "")
  end

  local function clickSquare(m, s)
    if m.over or m.watch or not G.IsMyTurn(m) then return end
    local p = m.pos.b[s]
    if m.sel then
      for _, mv in ipairs(m.legal) do
        if mv.from == m.sel and mv.to == s then
          m.sel = nil
          ns.GameMove(mv.from .. ":" .. mv.to)
          return
        end
      end
    end
    if p and p:sub(1, 1) == myColor(m) and m.sel ~= s then
      m.sel = s
      PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    else
      m.sel = nil
    end
    refresh(m)
  end

  function G.Build(f)
    local board = CreateFrame("Frame", nil, f)
    board:SetSize(CELL * 8 + 4, CELL * 8 + 4)
    board:SetPoint("TOPLEFT", 18, -2)
    S.Box(board, { 0, 0, 0, 1 }, C.trim)
    for y = 1, 8 do
      for x = 1, 8 do
        local c = CreateFrame("Button", nil, board)
        c:SetSize(CELL, CELL)
        c:SetPoint("TOPLEFT", 2 + (x - 1) * CELL, -2 - (y - 1) * CELL)
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(WHITE)
        local col = ((x + y) % 2 == 0) and LIGHT or DARK
        bg:SetVertexColor(col[1], col[2], col[3], 1)
        c.last = c:CreateTexture(nil, "BORDER")
        c.last:SetAllPoints()
        c.last:SetTexture(WHITE)
        c.last:SetVertexColor(1, 0.85, 0.2, 0.35)
        c.check = c:CreateTexture(nil, "BORDER", nil, 1)
        c.check:SetAllPoints()
        c.check:SetTexture(MEDIA .. "Glow")
        c.check:SetVertexColor(1, 0.1, 0.1, 0.9)
        c.selTex = c:CreateTexture(nil, "BORDER", nil, 2)
        c.selTex:SetAllPoints()
        c.selTex:SetTexture(WHITE)
        c.selTex:SetVertexColor(0.3, 0.9, 0.3, 0.45)
        c.piece = CreateFrame("Frame", nil, c)
        c.piece:SetAllPoints()
        c.disc = c.piece:CreateTexture(nil, "ARTWORK")
        c.disc:SetTexture(MEDIA .. "Dot")
        c.disc:SetSize(CELL - 6, CELL - 6)
        c.disc:SetPoint("CENTER")
        c.icon = c.piece:CreateTexture(nil, "ARTWORK", nil, 1)
        c.icon:SetSize(CELL - 16, CELL - 16)
        c.icon:SetPoint("CENTER")
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.dot = c:CreateTexture(nil, "OVERLAY")
        c.dot:SetTexture(MEDIA .. "Dot")
        c.dot:SetSize(14, 14)
        c.dot:SetPoint("CENTER")
        c.dot:SetVertexColor(0.1, 0.1, 0.1, 0.55)
        c.ring = c:CreateTexture(nil, "OVERLAY")
        c.ring:SetTexture(MEDIA .. "Ring")
        c.ring:SetAllPoints()
        c.ring:SetVertexColor(1, 0.25, 0.2, 0.9)
        c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        c:SetScript("OnClick", function(self)
          local m = ns.GameMatch()
          if m and m.game == G.id and m.pos then clickSquare(m, self.square) end
        end)
        c:SetScript("OnEnter", function(self)
          local m = ns.GameMatch()
          local p = m and m.game == G.id and m.pos and m.pos.b[self.square]
          if not p then return end
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:AddLine(L[NAMES[p:sub(2, 2)]], color(p:sub(1, 1) == "w" and P1 or P2))
          GameTooltip:AddLine(L[p:sub(1, 1) == "w" and "White" or "Black"] .. "  ·  " .. squareName(self.square), 1, 1, 1)
          GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cells[(y - 1) * 8 + x] = c
      end
    end
    -- coordinates around the board
    for i = 1, 8 do
      files[i] = S.Text(f, 10, "muted")
      files[i]:SetPoint("TOP", board, "BOTTOMLEFT", 2 + (i - 0.5) * CELL, -2)
      ranks[i] = S.Text(f, 10, "muted")
      ranks[i]:SetPoint("RIGHT", board, "TOPLEFT", -5, -2 - (i - 0.5) * CELL)
    end

    -- side panel: check, captured pieces, last moves
    local side = CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT", board, "TOPRIGHT", 16, 0)
    side:SetPoint("BOTTOMRIGHT", 0, 0)
    checkText = S.Text(side, 18, "gold")
    checkText:SetPoint("TOPLEFT", 0, -2)
    local s1 = S.Section(side, L["Captured"])
    s1:SetPoint("TOPLEFT", 0, -30)
    s1:SetPoint("TOPRIGHT", 0, -30)
    local you = S.Text(side, 11, "dim")
    you:SetPoint("TOPLEFT", s1, "BOTTOMLEFT", 0, -8)
    you:SetText(L["You"])
    capturedMine = S.Text(side, 11, "text")
    capturedMine:SetPoint("TOPLEFT", you, "BOTTOMLEFT", 0, -4)
    capturedMine:SetPoint("RIGHT")
    capturedMine:SetWordWrap(true)
    local them = S.Text(side, 11, "dim")
    them:SetPoint("TOPLEFT", capturedMine, "BOTTOMLEFT", 0, -10)
    them:SetText(L["Opponent"])
    capturedTheirs = S.Text(side, 11, "text")
    capturedTheirs:SetPoint("TOPLEFT", them, "BOTTOMLEFT", 0, -4)
    capturedTheirs:SetPoint("RIGHT")
    capturedTheirs:SetWordWrap(true)
    local s2 = S.Section(side, L["Moves"])
    s2:SetPoint("TOPLEFT", 0, -170)
    s2:SetPoint("TOPRIGHT", 0, -170)
    history = S.Text(side, 11, "text")
    history:SetPoint("TOPLEFT", s2, "BOTTOMLEFT", 0, -8)
    history:SetPoint("RIGHT")
    history:SetJustifyV("TOP")
    history:SetWordWrap(true)
    history:SetSpacing(3)
    info = S.Text(side, 10, "muted")
    info:SetPoint("BOTTOMLEFT", 0, 2)
    info:SetPoint("RIGHT")
    info:SetWordWrap(true)
    info:SetText(L["Click a piece, then its square. A pawn reaching the last row becomes a queen."])
  end

  function G.Start(m)
    m.pos = newPosition()
    m.legal = legalMoves(m.pos)
    m.hist, m.sel, m.lastFrom, m.lastTo = {}, nil, nil, nil
    refresh(m)
  end

  function G.OnMove(m, data)
    local from, to = (data or ""):match("^(%d+):(%d+)$")
    from, to = tonumber(from), tonumber(to)
    if not from then return end
    local mv
    for _, x in ipairs(m.legal) do if x.from == from and x.to == to then mv = x break end end
    if not mv then return end
    local pos = m.pos
    local p = pos.b[from]
    local np = play(pos, mv)
    local capture = np.captured ~= nil
    -- written like "Nf3", "exd5", "O-O", "e8=Q", with + or #
    local note
    if mv.rf then
      note = mv.to > mv.from and "O-O" or "O-O-O"
    else
      local t = p:sub(2, 2)
      note = (t == "P" and capture and squareName(from):sub(1, 1) or LETTER[t]) .. (capture and "x" or "")
        .. squareName(to) .. (mv.promo and "=Q" or "")
    end
    m.pos, m.sel, m.lastFrom, m.lastTo = np, nil, from, to
    m.legal = legalMoves(np)
    local res = outcome(np)
    note = note .. (res == "mate" and "#" or inCheck(np, np.turn) and "+" or "")
    m.hist[#m.hist + 1] = note
    refresh(m)
    local snd = SOUNDKIT and (capture and SOUNDKIT.IG_ABILITY_ICON_DROP or SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    PlaySound(snd or 1115)
    if res == "mate" then
      ns.GameLater(0.4, function() ns.GameEnd(np.turn == myColor(m) and "lose" or "win") end)
    elseif res then
      if res == "stalemate" then ns.Print(L["Stalemate"]) end
      ns.GameLater(0.4, function() ns.GameEnd("draw") end)
    else
      ns.GameRefreshStatus()
    end
  end

  ns.RegisterGame(G)
end
