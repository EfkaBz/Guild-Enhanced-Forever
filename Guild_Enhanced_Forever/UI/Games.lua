-- Guild Enhanced Forever: mini-games page: two-player games between guildmates who have the addon.
-- This file: network (addon messages), presence, challenges (with a toast), matches, page.
-- The games themselves are in UI\GameDefs.lua (ns.RegisterGame).
--
-- Messages (prefix GUIFGames, fields separated by "|"):
--   H|ver        guild: hello (who has the addon?)      P|ver       whisper: I have it
--   C|id|game|r  whisper: challenge (r = rematch)        Y|id / N|id|reason   accept / decline
--   M|id|data    whisper: a move                          F|id        whisper: I leave the match
-- A match against the bot (practice) never touches the network: the game's BotMove(match)
-- picks the bot's moves, played after a short "thinking" delay.
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local PAGE = 11
local PREFIX = "GUIFGames"
local VERSION = "1"
local LEFT_W = 290
local INVITE_TIME = 30

ns.gameDefs, ns.gameOrder = {}, {}
function ns.RegisterGame(def)
  ns.gameDefs[def.id] = def
  ns.gameOrder[#ns.gameOrder + 1] = def
end

local me = UnitName("player")
local function short(name) return name and name:gsub("%-.*", "") or "" end

-- Network ----------------------------------------------------------------------------------------
local CI = C_ChatInfo or {}
local Register = CI.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
local SendAddon = CI.SendAddonMessage or SendAddonMessage
if Register then Register(PREFIX) end

local queue, tokens = {}, 6
local pump = CreateFrame("Frame")
pump:Hide()
pump:SetScript("OnUpdate", function(self, e)
  tokens = math.min(6, tokens + e * 2)
  while tokens >= 1 and queue[1] do
    local q = table.remove(queue, 1)
    SendAddon(PREFIX, q[1], q[2], q[3])
    tokens = tokens - 1
  end
  if not queue[1] then self:Hide() end
end)
local function send(msg, channel, target)
  queue[#queue + 1] = { msg, channel, target }
  pump:Show()
end

-- State ----------------------------------------------------------------------------------------------
local users = {}          -- short name -> { full, t }
local replied = {}        -- short name -> last presence answer
local lastHello = 0
local match               -- { id, game, opp, oppShort, first, over, result, score = { me, opp }, bot }
local outgoing            -- { id, game, opp, t }
local invites = {}        -- { id, game, from, rematch, t }
local page, ui = nil, {}
local selectedGame, selectedOpp

local function newId() return tostring(math.random(100000, 999999)) end
local function online(name)
  local m = ns.byName[name]
  return m and m.online
end

function ns.GameMatch() return match end
function ns.GameMe() return me end

-- status line, badge --------------------------------------------------------------------------------------
local function myTurn()
  if not match or match.over then return false end
  local def = ns.gameDefs[match.game]
  return def and def.IsMyTurn and def.IsMyTurn(match) or false
end

local refreshPage
local botTurn

function ns.GameRefreshStatus()
  if match and match.bot then botTurn() end
  if myTurn() and not (page and page:IsVisible()) then ns.SetTabBadge(PAGE, "!") end
  if not myTurn() then ns.SetTabBadge(PAGE, "") end
  if refreshPage then refreshPage() end
end

-- Presence ------------------------------------------------------------------------------------------------
function ns.GameHello()
  if not IsInGuild() then return end
  lastHello = GetTime()
  send("H|" .. VERSION, "GUILD")
end

local function onlineUsers()
  local list = {}
  for name, u in pairs(users) do
    local m = ns.byName[name]
    if m and m.online and name ~= me then list[#list + 1] = m end
  end
  table.sort(list, function(a, b) return a.short < b.short end)
  return list
end

-- Matches ------------------------------------------------------------------------------------------------------
local function startMatch(id, game, opp, first, bot)
  local def = ns.gameDefs[game]
  if not def then return end
  local same = match and match.oppShort == short(opp) and match.game == game and (match.bot or false) == (bot or false)
  local score = same and match.score or { 0, 0 }
  match = { id = id, game = game, opp = opp, oppShort = short(opp), first = first, score = score, bot = bot }
  outgoing = nil
  ns.OpenPage(PAGE)
  for _, d in ipairs(ns.gameOrder) do if d.frame then d.frame:SetShown(d == def) end end
  ui.result:Hide()
  def.Start(match)
  S.SlideIn(def.frame, 0, -10, 0.3)
  PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN or 875)
  ns.GameRefreshStatus()
end

local RESULT_TEXT = { win = "Victory!", lose = "Defeat", draw = "Draw", left = "Your opponent left the game.",
  gone = "Your opponent logged out." }

function ns.GameEnd(result)
  if not match or match.over then return end
  match.over, match.result = true, result
  local st = ns.db.gameStats or {}
  ns.db.gameStats = st
  st[match.game] = st[match.game] or { w = 0, l = 0, d = 0 }
  -- practice against the bot: only the score of the series, not the record
  local s = match.bot and { w = 0, l = 0, d = 0 } or st[match.game]
  if result == "win" or result == "left" then
    s.w = s.w + 1; match.score[1] = match.score[1] + 1
  elseif result == "lose" then
    s.l = s.l + 1; match.score[2] = match.score[2] + 1
  elseif result == "draw" then
    s.d = s.d + 1
  end
  -- big result text that pops, with a burst of light
  local r = ui.result
  r.text:SetText(L[RESULT_TEXT[result] or "Draw"])
  local col = (result == "win" or result == "left") and C.gold or result == "lose" and C.bad or C.text
  r.text:SetTextColor(color(col))
  r.burst:SetVertexColor(col[1], col[2], col[3], 0.8)
  r:Show()
  S.Tween(r, { dur = 0.6, from = 0, to = 1, ease = "outBack", set = function(v, p)
    r:SetAlpha(math.min(1, p * 3))
    r.text:SetTextHeight(math.max(1, 34 * (0.5 + 0.5 * v)))
    r.burst:SetSize(80 + 360 * p, 80 + 360 * p)
    r.burst:SetAlpha(1 - p)
  end })
  if result == "win" or result == "left" then PlaySound(SOUNDKIT and SOUNDKIT.UI_ACHIEVEMENT_AWARDED or 12891)
  elseif result == "lose" then PlaySound(SOUNDKIT and SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_FINISHED or 25478) end
  ns.SetTabBadge(PAGE, "")
  if not match.bot then
    if ns.ShareGameStats then ns.ShareGameStats() end
    if ns.TourneyReport then ns.TourneyReport(match, result) end
  end
  if refreshPage then refreshPage() end
end

-- a move of mine: sent to the opponent and played here
function ns.GameMove(data)
  if not match or match.over then return end
  if not match.bot then send("M|" .. match.id .. "|" .. data, "WHISPER", match.opp) end
  ns.gameDefs[match.game].OnMove(match, data, true)
end

-- the bot plays when it is its turn, after a short thinking time
botTurn = function()
  local m = match
  if not m or m.over or m.botThinking then return end
  local def = ns.gameDefs[m.game]
  if not def or not def.BotMove or def.IsMyTurn(m) then return end
  m.botThinking = true
  C_Timer.After(0.6 + math.random() * 0.7, function()
    m.botThinking = nil
    if match ~= m or m.over or def.IsMyTurn(m) then return end
    local data = def.BotMove(m)
    if data then def.OnMove(m, tostring(data), false) end
  end)
end

-- a practice match against the bot; who starts alternates from one match to the next
local botFirst = true
function ns.PlayBot(game)
  if not ns.gameDefs[game] then return end
  if match and not match.over and not match.bot then ns.Print(L["Finish your current game first."]) return end
  if match and match.bot and match.game == game and match.over then botFirst = not botFirst end
  startMatch(newId(), game, L["Bot"], botFirst, true)
end

-- runs fn later only if the same match is still going
function ns.GameLater(delay, fn)
  local id = match and match.id
  C_Timer.After(delay, function() if match and match.id == id then fn(match) end end)
end

function ns.Challenge(game, opp, rematch)
  if match and not match.over and not match.bot then ns.Print(L["Finish your current game first."]) return end
  if not opp then return end
  local id = newId()
  outgoing = { id = id, game = game, opp = opp, t = GetTime() }
  send("C|" .. id .. "|" .. game .. (rematch and "|r" or ""), "WHISPER", opp)
  if refreshPage then refreshPage() end
  C_Timer.After(INVITE_TIME + 2, function()
    if outgoing and outgoing.id == id then
      outgoing = nil
      ns.Print(string.format(L["%s did not answer."], short(opp)))
      if refreshPage then refreshPage() end
    end
  end)
end

local function leave()
  if match and not match.over then
    if not match.bot then send("F|" .. match.id, "WHISPER", match.opp) end
    ns.GameEnd("lose")
  end
end

-- Toast (invitations) ----------------------------------------------------------------------------------------
local toast
local showNextInvite

local function buildToast()
  toast = S.Window("GuildEnhancedForeverGameToast", UIParent, 360, 124, "")
  toast:SetFrameStrata("DIALOG")
  toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
  toast.titleBar:SetHeight(30)
  toast.title:SetText(L["Challenge!"])
  toast.close:Hide()
  toast:Hide()
  toast.icon = S.Icon(toast, 40)
  toast.icon:SetPoint("TOPLEFT", 20, -42)
  toast.text = S.Text(toast, 12, "text")
  toast.text:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 10, -2)
  toast.text:SetPoint("RIGHT", -20, 0)
  toast.text:SetWordWrap(true)
  local function answer(yes)
    local inv = toast.invite
    toast.invite = nil
    for i, x in ipairs(invites) do if x == inv then table.remove(invites, i) break end end
    S.Close(toast)
    if inv then
      if yes then
        send("Y|" .. inv.id, "WHISPER", inv.from)
        startMatch(inv.id, inv.game, inv.from, false)
      else
        send("N|" .. inv.id .. "|no", "WHISPER", inv.from)
      end
    end
    C_Timer.After(0.3, showNextInvite)
  end
  toast.accept = S.Button(toast, L["Accept"], 110, 22, function() answer(true) end, "primary")
  toast.accept:SetPoint("BOTTOMRIGHT", -18, 18)
  toast.decline = S.Button(toast, L["Decline"], 90, 22, function() answer(false) end)
  toast.decline:SetPoint("RIGHT", toast.accept, "LEFT", -8, 0)
  -- countdown: a thin gold line that shrinks
  local timer = toast:CreateTexture(nil, "OVERLAY")
  timer:SetPoint("BOTTOMLEFT", 14, 13)
  timer:SetHeight(2)
  gradient(timer, C.fill2, C.fill1, true)
  toast:SetScript("OnUpdate", function()
    local inv = toast.invite
    if not inv then return end
    local left = 1 - (GetTime() - inv.t) / INVITE_TIME
    if left <= 0 then answer(false) return end
    timer:SetWidth(math.max(1, (toast:GetWidth() - 28) * left))
  end)
end

showNextInvite = function()
  if toast and toast.invite then return end
  local inv = invites[1]
  if not inv then return end
  if GetTime() - inv.t > INVITE_TIME then table.remove(invites, 1); return showNextInvite() end
  if not toast then buildToast() end
  local def = ns.gameDefs[inv.game]
  toast.invite = inv
  toast.icon.tex:SetTexture(S.PickIcon(def.icon))
  local m = ns.byName[short(inv.from)]
  local who = m and ("|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r") or short(inv.from)
  toast.text:SetText(string.format(inv.rematch and L["%s wants a rematch of %s."] or L["%s challenges you to %s."],
    who, "|cffffd100" .. L[def.name] .. "|r"))
  toast:Show()
  S.AnimateOpen(toast, 0, 16)
  PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960)
end

-- Receiving ---------------------------------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
local started
ev:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
  if ns.Secret(prefix, msg, channel, sender) then return end
  if event == "PLAYER_ENTERING_WORLD" then
    if not started then
      started = true
      C_Timer.After(10, ns.GameHello)
    end
    return
  end
  if prefix ~= PREFIX or not msg or not sender then return end
  local name = short(sender)
  if name == me then return end
  if not ns.byName[name] then return end -- guildmates only
  local f = { strsplit("|", msg) }
  local kind = f[1]
  users[name] = { full = sender, t = GetTime() }

  if kind == "H" then
    if not replied[name] or GetTime() - replied[name] > 20 then
      replied[name] = GetTime()
      C_Timer.After(0.3 + math.random() * 2, function() send("P|" .. VERSION, "WHISPER", sender) end)
    end
    if refreshPage then refreshPage() end
  elseif kind == "P" then
    if refreshPage then refreshPage() end
  elseif kind == "C" then
    local id, game = f[2], f[3]
    if not ns.gameDefs[game] then return end
    if (match and not match.over and not match.bot) or outgoing then
      send("N|" .. id .. "|busy", "WHISPER", sender)
      return
    end
    invites[#invites + 1] = { id = id, game = game, from = sender, rematch = f[4] == "r", t = GetTime() }
    showNextInvite()
  elseif kind == "Y" then
    if outgoing and outgoing.id == f[2] and short(outgoing.opp) == name then
      startMatch(outgoing.id, outgoing.game, sender, true)
    end
  elseif kind == "N" then
    if outgoing and outgoing.id == f[2] then
      outgoing = nil
      ns.Print(string.format(f[3] == "busy" and L["%s is already playing."] or L["%s declined."], name))
      if refreshPage then refreshPage() end
    end
  elseif kind == "M" then
    if match and not match.over and match.id == f[2] and match.oppShort == name then
      -- the move may contain "|" (it never does in these games, but keep the rest whole)
      local data = msg:match("^M|[^|]*|(.*)$")
      ns.gameDefs[match.game].OnMove(match, data, false)
    end
  elseif kind == "F" then
    if match and not match.over and match.id == f[2] and match.oppShort == name then ns.GameEnd("left") end
  end
end)

-- opponent logged out
ns.On("ROSTER", function()
  if match and not match.over and not match.bot and not online(match.oppShort) then ns.GameEnd("gone") end
  if refreshPage then refreshPage() end
end)

-- Page --------------------------------------------------------------------------------------------------------------
local CARD_W, CARD_H, CARD_GAP = (LEFT_W - 6) / 2, 40, 6
local function gameCard(parent, def, i)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(CARD_W, CARD_H)
  b:SetPoint("TOPLEFT", ((i - 1) % 2) * (CARD_W + 6), -30 - math.floor((i - 1) / 2) * (CARD_H + CARD_GAP))
  S.Rounded(b, 8, { 0.1, 0.07, 0.17, 0.9 }, { 0.05, 0.035, 0.09, 0.9 }, C.rule)
  local hl = b:CreateTexture(nil, "BACKGROUND", nil, -6)
  hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
  S.Highlight(hl, 0.14)
  b.sel = hl
  hl:SetAlpha(0)
  local icon = S.Icon(b, 28)
  icon:SetPoint("LEFT", 6, 0)
  icon.tex:SetTexture(S.PickIcon(def.icon))
  local name = S.Text(b, 12, "text")
  name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
  name:SetText(L[def.name])
  S.FitText(name, CARD_W - 48, 12)
  b.name = name
  b.def = def
  b:SetScript("OnEnter", function(self)
    if selectedGame ~= self.def.id then self:SetBorderColor(color(C.ring)) end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L[def.name], color(C.gold))
    GameTooltip:AddLine(string.format(L[def.desc], def.descArg or 0), 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    if selectedGame ~= self.def.id then self:SetBorderColor(color(C.rule)) end
    GameTooltip:Hide()
  end)
  b:SetScript("OnClick", function(self)
    selectedGame = self.def.id
    refreshPage()
  end)
  return b
end

local function oppRow(parent, i)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(22)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
  r:SetPoint("TOPRIGHT", 0, -(i - 1) * 22)
  S.RowHighlight(r)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints()
  S.Highlight(r.sel, 0.2)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 6, 0)
  r.name = S.Text(r, 12, "text")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.lvl = S.Text(r, 11, "muted")
  r.lvl:SetPoint("RIGHT", -8, 0)
  r:SetScript("OnClick", function(self)
    selectedOpp = self.member.short
    refreshPage()
  end)
  r:SetScript("OnDoubleClick", function(self)
    selectedOpp = self.member.short
    if selectedGame then ns.Challenge(selectedGame, users[selectedOpp] and users[selectedOpp].full or selectedOpp) end
  end)
  return r
end

refreshPage = function()
  if not page then return end
  -- game cards
  for _, b in ipairs(ui.cards) do
    local on = b.def.id == selectedGame
    b:SetBorderColor(color(on and C.gold or C.rule))
    S.FadeTo(b.sel, on and 1 or 0, 0.2)
    b.name:SetTextColor(color(on and C.gold or C.text))
  end
  -- opponents
  local list = onlineUsers()
  ui.oppTitle.right:SetText(#list)
  for i, m in ipairs(list) do
    ui.oppRows[i] = ui.oppRows[i] or oppRow(ui.oppContent, i)
    local r = ui.oppRows[i]
    r.member = m
    ns.SetClassIcon(r.icon, m.classFile)
    r.name:SetText(m.short)
    r.name:SetTextColor(ns.ClassColor(m.classFile))
    r.lvl:SetText(match and not match.over and not match.bot and match.oppShort == m.short and L["playing"] or m.level)
    r.sel:SetShown(selectedOpp == m.short)
    r:Show()
  end
  for i = #list + 1, #ui.oppRows do ui.oppRows[i]:Hide() end
  ui.oppContent:SetHeight(math.max(1, #list * 22))
  ui.none:SetShown(#list == 0)
  if selectedOpp and not users[selectedOpp] then selectedOpp = nil end

  local busy = (match and not match.over and not match.bot) or outgoing
  ui.challenge:SetEnabled(selectedGame and selectedOpp and not busy and true or false)
  ui.challenge:SetText(outgoing and string.format(L["Waiting for %s..."], short(outgoing.opp)) or L["Challenge"])

  -- board side
  local def = match and ns.gameDefs[match.game]
  ui.placeholder:SetShown(not match)
  ui.bot:SetEnabled(selectedGame and not outgoing and true or false)
  local sel = selectedGame and ns.gameDefs[selectedGame]
  ui.botHint:SetText(sel and ("|cffffd100" .. L[sel.name] .. "|r  ·  " .. L["Practice: not counted in your record."]) or "")
  ui.header:SetShown(match ~= nil)
  ui.buttons:SetShown(match ~= nil)
  if not match then
    for _, d in ipairs(ns.gameOrder) do if d.frame then d.frame:Hide() end end
    local v = ui.views[ui.view or "play"]
    if v and v.Refresh and ui.view ~= "play" then v.Refresh(false) end
    local st = ns.db.gameStats or {}
    for i, d in ipairs(ns.gameOrder) do
      local s = st[d.id] or { w = 0, l = 0, d = 0 }
      ui.stats[i]:SetText(string.format("%s  |cff1eff00%d|r / |cffff2020%d|r / |cffbbbbbb%d|r", L[d.name], s.w, s.l, s.d))
    end
    return
  end
  local m = not match.bot and ns.byName[match.oppShort]
  local oppName = m and ("|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r")
    or match.bot and ("|cffbbbbbb" .. match.oppShort .. "|r") or match.oppShort
  ui.gameName:SetText(L[def.name])
  ui.vs:SetText(string.format(L["You %s  %d - %d  %s"], def.Mark and def.Mark(match, true) or "",
    match.score[1], match.score[2], oppName .. (def.Mark and (" " .. def.Mark(match, false)) or "")))
  local status
  if match.over then
    status = L[RESULT_TEXT[match.result] or "Draw"]
  elseif myTurn() then
    status = "|cffffd100" .. L["Your turn"] .. "|r"
  else
    status = string.format(L["Waiting for %s..."], oppName)
  end
  ui.status:SetText(status)
  ui.pulse = myTurn()
  ui.rematch:SetShown(match.over and (match.bot or online(match.oppShort)) and true or false)
  ui.rematch:SetEnabled(not outgoing)
  ui.leave:SetText(match.over and L["Close"] or L["Leave"])
end

local function build(p)
  page = p
  ui.cards = {}
  local s1 = S.Section(p, L["Games"])
  s1:SetPoint("TOPLEFT")
  s1:SetWidth(LEFT_W)
  for i, def in ipairs(ns.gameOrder) do ui.cards[i] = gameCard(p, def, i) end
  selectedGame = selectedGame or (ns.gameOrder[1] and ns.gameOrder[1].id)

  local y = -30 - math.ceil(#ns.gameOrder / 2) * (CARD_H + CARD_GAP) - 6
  ui.oppTitle = S.Section(p, L["Guildmates with Guild Enhanced"])
  ui.oppTitle:SetPoint("TOPLEFT", 0, y)
  ui.oppTitle:SetWidth(LEFT_W)
  local box = CreateFrame("Frame", nil, p)
  box:SetPoint("TOPLEFT", 0, y - 28)
  box:SetPoint("BOTTOMLEFT", 0, 36)
  box:SetWidth(LEFT_W)
  S.Card(box, 8)
  local sf, content = S.Scroll(box)
  sf:SetPoint("TOPLEFT", 4, -4)
  sf:SetPoint("BOTTOMRIGHT", -12, 4)
  content:SetWidth(LEFT_W - 16)
  ui.oppContent, ui.oppRows = content, {}
  ui.none = S.Text(box, 11, "muted")
  ui.none:SetPoint("TOPLEFT", 10, -10)
  ui.none:SetPoint("TOPRIGHT", -10, -10)
  ui.none:SetWordWrap(true)
  ui.none:SetText(L["Nobody online has Guild Enhanced yet. They need it to play with you."])

  ui.challenge = S.Button(p, L["Challenge"], LEFT_W - 80, 28, function()
    if selectedGame and selectedOpp then
      ns.Challenge(selectedGame, users[selectedOpp] and users[selectedOpp].full or selectedOpp)
    end
  end, "primary")
  ui.challenge:SetPoint("BOTTOMLEFT")
  local refresh = S.Button(p, L["Refresh"], 72, 28, function() ns.GameHello() end)
  refresh:SetPoint("BOTTOMRIGHT", p, "BOTTOMLEFT", LEFT_W, 0)

  -- board side
  local x = LEFT_W + 16
  local card = CreateFrame("Frame", nil, p)
  card:SetPoint("TOPLEFT", x, 0)
  card:SetPoint("BOTTOMRIGHT")
  S.Card(card, 10)
  S.EdgeGlow(card, 32, 0.12)
  ui.card = card

  ui.header = CreateFrame("Frame", nil, card)
  ui.header:SetPoint("TOPLEFT", 16, -12)
  ui.header:SetPoint("TOPRIGHT", -16, -12)
  ui.header:SetHeight(44)
  ui.gameName = S.Text(ui.header, 16, "gold")
  ui.gameName:SetPoint("TOPLEFT")
  ui.vs = S.Text(ui.header, 12, "text")
  ui.vs:SetPoint("BOTTOMLEFT")
  ui.status = S.Text(ui.header, 14, "text")
  ui.status:SetPoint("RIGHT", 0, 0)
  ui.status:SetJustifyH("RIGHT")
  local clock = 0
  ui.header:SetScript("OnUpdate", function(_, e)
    clock = clock + e
    ui.status:SetAlpha(ui.pulse and (0.65 + 0.35 * math.sin(clock * 5)) or 1)
  end)
  local rule = S.Rule(ui.header, C.gold, 0.4)
  rule:SetPoint("TOPLEFT", ui.header, "BOTTOMLEFT", 0, -4)
  rule:SetPoint("TOPRIGHT", ui.header, "BOTTOMRIGHT", 0, -4)

  -- the games draw in this area
  local board = CreateFrame("Frame", nil, card)
  board:SetPoint("TOPLEFT", 16, -66)
  board:SetPoint("BOTTOMRIGHT", -16, 52)
  for _, def in ipairs(ns.gameOrder) do
    def.frame = CreateFrame("Frame", nil, board)
    def.frame:SetAllPoints()
    def.frame:Hide()
    def.Build(def.frame)
  end

  ui.buttons = CreateFrame("Frame", nil, card)
  ui.buttons:SetPoint("BOTTOMLEFT", 16, 14)
  ui.buttons:SetPoint("BOTTOMRIGHT", -16, 14)
  ui.buttons:SetHeight(28)
  ui.leave = S.Button(ui.buttons, L["Leave"], 110, 28, function()
    if match and match.over then
      match = nil
      refreshPage()
    else
      S.Dialog({ title = L["Leave"], text = L["Leave the game? It counts as a defeat."], accept = L["Leave"],
        danger = true, onAccept = leave })
    end
  end)
  ui.leave:SetPoint("RIGHT")
  ui.rematch = S.Button(ui.buttons, L["Rematch"], 120, 28, function()
    if match and match.bot then ns.PlayBot(match.game)
    elseif match then ns.Challenge(match.game, match.opp, true) end
  end, "primary")
  ui.rematch:SetPoint("RIGHT", ui.leave, "LEFT", -8, 0)

  -- result text over the board
  local r = CreateFrame("Frame", nil, card)
  r:SetAllPoints(board)
  r:SetFrameLevel(board:GetFrameLevel() + 30)
  r.burst = r:CreateTexture(nil, "BACKGROUND")
  r.burst:SetTexture(S.MEDIA .. "Glow")
  r.burst:SetBlendMode("ADD")
  r.burst:SetPoint("CENTER")
  r.text = S.Text(r, 34, "gold")
  r.text:SetPoint("CENTER")
  r.text:SetJustifyH("CENTER")
  r:EnableMouse(false)
  r:Hide()
  r:SetScript("OnMouseDown", nil)
  ui.result = r
  -- the result fades away after a while so the final board stays visible
  hooksecurefunc(r, "Show", function()
    C_Timer.After(2.5, function() if r:IsShown() then S.FadeTo(r, 0, 0.8, function() r:Hide(); r:SetAlpha(1) end) end end)
  end)

  -- no game going: how it works + your record
  local holder = CreateFrame("Frame", nil, card)
  holder:SetAllPoints()
  ui.placeholder = holder
  ui.views, ui.viewPills = {}, {}
  local px = 16
  for i, spec in ipairs({ { "play", L["Play"] }, { "board", L["Leaderboard"] }, { "tourney", L["Tournaments"] } }) do
    local v = CreateFrame("Frame", nil, holder)
    v:SetPoint("TOPLEFT", 0, -40)
    v:SetPoint("BOTTOMRIGHT")
    v:Hide()
    ui.views[spec[1]] = v
    local pill = S.Pill(holder, spec[2], function() ns.GameView(spec[1]) end)
    pill.key = spec[1]
    pill:SetPoint("TOPLEFT", px, -12)
    px = px + pill:GetWidth() + 6
    ui.viewPills[i] = pill
  end
  local ph = ui.views.play
  if ns.BuildLeaderboard then ns.BuildLeaderboard(ui.views.board) end
  if ns.BuildTourneys then ns.BuildTourneys(ui.views.tourney) end
  ns.GameView(ui.view or "play", true)
  local big = ph:CreateTexture(nil, "ARTWORK")
  big:SetTexture(S.PickIcon({ "Interface\\Icons\\INV_Misc_Dice_01", "Interface\\Icons\\INV_Misc_Dice_02",
    "Interface\\Icons\\INV_Misc_Toy_10", "Interface\\Icons\\INV_Misc_Gift_02" }))
  big:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  big:SetSize(64, 64)
  big:SetPoint("TOP", 0, -14)
  local halo = ph:CreateTexture(nil, "BACKGROUND")
  halo:SetTexture(S.MEDIA .. "Glow")
  halo:Hide()
  halo:SetBlendMode("ADD")
  halo:SetSize(160, 160)
  halo:SetPoint("CENTER", big)
  halo:SetVertexColor(1, 0.75, 0.3, 0.3)
  local t1 = S.Text(ph, 15, "gold")
  t1:SetPoint("TOP", big, "BOTTOM", 0, -16)
  t1:SetText(L["Play with your guild"])
  local t2 = S.Text(ph, 12, "dim")
  t2:SetPoint("TOP", t1, "BOTTOM", 0, -8)
  t2:SetWidth(440)
  t2:SetWordWrap(true)
  t2:SetJustifyH("CENTER")
  t2:SetText(L["Pick a game and a guildmate on the left, then challenge them. Double-click a name to challenge right away."])
  -- practice against the bot, with the game picked on the left
  ui.bot = S.Button(ph, L["Play against a bot"], 200, 30, function()
    if selectedGame then ns.PlayBot(selectedGame) end
  end, "primary")
  ui.bot:SetPoint("TOP", t2, "BOTTOM", 0, -18)
  ui.botHint = S.Text(ph, 11, "muted")
  ui.botHint:SetPoint("TOP", ui.bot, "BOTTOM", 0, -8)
  ui.botHint:SetJustifyH("CENTER")
  local s2 = S.Section(ph, L["Your record (won / lost / draw)"])
  s2:SetPoint("TOP", ui.botHint, "BOTTOM", 0, -18)
  s2:SetWidth(500)
  ui.stats = {}
  for i = 1, #ns.gameOrder do
    local fs = S.Text(ph, 12, "text")
    fs:SetPoint("TOPLEFT", s2, "BOTTOMLEFT", 10 + ((i - 1) % 2) * 250, -10 - math.floor((i - 1) / 2) * 22)
    fs:SetWidth(240)
    ui.stats[i] = fs
  end
end

function ns.GameView(key, instant)
  ui.view = key
  for k, v in pairs(ui.views) do
    if k == key then
      v:Show()
      if not instant then S.SlideIn(v, 0, -8, 0.22) end
      if v.Refresh then v.Refresh(not instant) end
    else
      v:Hide()
    end
  end
  for _, p in ipairs(ui.viewPills) do p:SetActive(p.key == key) end
end

local function onShow()
  if GetTime() - lastHello > 30 then ns.GameHello() end
  if myTurn() then ns.SetTabBadge(PAGE, "") end
  refreshPage()
end

ns.PAGE_GAMES = PAGE
ns.AddPage(PAGE, "Mini-games", build, onShow, { "Interface\\Icons\\INV_Misc_Dice_01", "Interface\\Icons\\INV_Misc_Dice_02",
  "Interface\\Icons\\INV_Misc_Toy_10", "Interface\\Icons\\INV_Misc_Gift_02" })
