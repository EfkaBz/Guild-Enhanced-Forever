-- Guild Enhanced Forever: guild chat page: guild and officer messages (kept between sessions),
-- input line with a Guild / Officer switch, and the
-- list of members online on the right
local ADDON, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient

local PAGE_INDEX = 2
local MAX_HISTORY = 300
local SIDE_W = 200

local page, smf, input, latest, channelBtn, pills, sideRows, sideScroll, sideContent, sideTitle = nil, nil, nil, nil, nil, {}, {}, nil, nil, nil
local filter, channel, unread = "all", "GUILD", 0
local now = GetServerTime or time -- server clock: the same for every guildmate (sync)

-- History -------------------------------------------------------------------------------------
-- per guild, saved account-wide: { t = time, ch = GUILD|OFFICER|ONLINE|OFFLINE, name, class, msg, src }
-- cleaned once per session (see cleanHistory)
local cleanHistory
local cleaned = {}
local function history()
  local g = ns.GuildName()
  if not g or not ns.db then return nil end
  ns.db.chat = ns.db.chat or {}
  ns.db.chat[g] = ns.db.chat[g] or {}
  local h = ns.db.chat[g]
  if not cleaned[g] then cleaned[g] = true; cleanHistory(h) end
  return h
end

local function chatColor(ch)
  local key = (ch == "OFFICER") and "OFFICER" or "GUILD"
  local info = ChatTypeInfo and ChatTypeInfo[key]
  if info then return info.r, info.g, info.b end
  if key == "OFFICER" then return 0.25, 0.75, 0.25 end
  return 0.25, 1, 0.25
end

local function classHex(e)
  if e.class then return ns.ClassHex(e.class) end
  local m = ns.byName[e.name or ""] or ns.byName[ns.Short(e.name)]
  return m and ns.ClassHex(m.classFile) or "ffd8d0e8"
end

local function format(e)
  local time = "|cff808080" .. date("%H:%M", e.t) .. "|r "
  local short = ns.Short(e.name)
  local link = "|Hplayer:" .. (e.name or "") .. "|h|c" .. classHex(e) .. short .. "|r|h"
  local tag = e.ch == "OFFICER" and ("|cff40c040[" .. L["Officer"] .. "]|r ") or ""
  local r, g, b = chatColor(e.ch)
  return time .. tag .. "[" .. link .. "]: " .. (e.msg or ""), r, g, b
end

local function visible(e)
  -- online / offline notices are no longer shown (old saved ones included)
  if e.ch ~= "GUILD" and e.ch ~= "OFFICER" then return false end
  if filter == "all" then return true end
  if filter == "GUILD" then return e.ch == "GUILD" end
  if filter == "OFFICER" then return e.ch == "OFFICER" end
  return false
end

local function updateLatest()
  if not latest then return end
  local up = smf:GetScrollOffset() > 0
  if up ~= latest.on then
    latest.on = up
    if up then latest:Show(); S.FadeTo(latest, 1, 0.2) else S.FadeTo(latest, 0, 0.2, function() latest:Hide() end) end
  end
end

local dirty = true -- history changed since the list was last drawn
local function rebuild()
  if not smf then return end
  dirty = false
  smf:Clear()
  local h = history() or {}
  for _, e in ipairs(h) do
    if visible(e) then smf:AddMessage(format(e)) end
  end
  smf:ScrollToBottom()
  page.none:SetShown(smf:GetNumMessages() == 0)
  updateLatest()
end

local function setUnread(n)
  unread = n
  ns.SetTabBadge(PAGE_INDEX, n > 0 and (n > 99 and "99+" or tostring(n)) or "")
end

-- Same message twice? The live copy (CHAT_MSG_GUILD) holds the text, but the server history copy
-- often holds a protected string instead ("|Kw1515|k", that the game swaps for the text when it is
-- drawn): both look the same on screen while their texts differ. So a protected copy matches by
-- channel + author + time; plain copies also compare their text (no color codes, links, spaces).
-- Those protected strings only mean something during the session that received them (the same
-- message gets another one after a reconnection), so they are never kept from one session to the
-- next: the server history is loaded again at login anyway.
local MATCH_WINDOW = 600  -- seconds, plain texts: the two clocks can drift apart
local TOKEN_WINDOW = 15   -- seconds, protected copy: the closest message of that author

local plainCache = setmetatable({}, { __mode = "k" })
local function plain(e)
  local p = plainCache[e]
  if not p then
    local msg = (e.msg or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    msg = msg:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("%s+", " ")
    p = (msg:gsub("^ ", ""):gsub(" $", "")):lower()
    plainCache[e] = p
  end
  return p
end
local function protected(e) return e.msg ~= nil and e.msg:find("|K", 1, true) ~= nil end
local authorCache = setmetatable({}, { __mode = "k" })
local function author(e)
  local a = authorCache[e]
  if not a then a = ns.Short(e.name or ""):lower(); authorCache[e] = a end
  return a
end

-- seconds between two copies of the same message, or nil when they are different messages
-- (cheapest tests first: this runs for every pair when the server history comes in)
local function sameGap(a, b)
  if a.ch ~= b.ch then return nil end
  local dt = math.abs((a.t or 0) - (b.t or 0))
  if dt > MATCH_WINDOW or author(a) ~= author(b) then return nil end
  local pa, pb = protected(a), protected(b)
  if pa and pb then return dt <= 1 and dt or nil end -- two server copies: same moment
  if pa ~= pb then return dt <= TOKEN_WINDOW and dt or nil end
  if dt <= MATCH_WINDOW and plain(a) == plain(b) then return dt end
end

-- index (in h) of the closest entry holding the same message and not already paired
local function findSame(h, e, used)
  local best, bestDt
  local p = protected(e) -- a server copy can come twice (several loads): it may match a paired one
  for i = #h, 1, -1 do
    local o = h[i]
    if p or not (used and used[o]) then
      local dt = sameGap(o, e)
      if dt and (not bestDt or dt < bestDt) then best, bestDt = i, dt end
    end
  end
  return best
end

-- the text is better than a protected string (kept in the history, shown the same)
local function keepText(kept, other)
  if protected(kept) and not protected(other) then kept.msg = other.msg; plainCache[kept] = nil end
end

-- removes the copies already saved (one live and one from the server history, or saved by an older
-- version), keeping the first; two messages of the same origin are never merged
local function dedupe(h)
  local out, absorbed = {}, {}
  for _, e in ipairs(h) do
    local dup
    if e.ch == "GUILD" or e.ch == "OFFICER" then
      for j = #out, math.max(1, #out - 80), -1 do
        local o = out[j]
        -- a server copy (protected) may match a message already paired; two plain texts of the same
        -- origin are two real messages
        local p = protected(e) or protected(o)
        if (p or not absorbed[o]) and (p or not (o.src and e.src and o.src == e.src)) and sameGap(o, e) then
          dup = o
          break
        end
      end
    end
    if dup then
      absorbed[dup] = true
      keepText(dup, e)
    else
      out[#out + 1] = e
    end
  end
  for i = #h, 1, -1 do h[i] = nil end
  for i, e in ipairs(out) do h[i] = e end
end

-- once per session: drops the protected strings of past sessions (no longer readable; the server
-- history brings them back with fresh ones), then the copies saved twice
cleanHistory = function(h)
  for i = #h, 1, -1 do
    if protected(h[i]) then table.remove(h, i) end
  end
  dedupe(h)
end

local function add(e)
  local h = history()
  if not h then return end
  -- the server history may already have brought this very message
  if (e.ch == "GUILD" or e.ch == "OFFICER") then
    local i = findSame(h, e)
    if i and h[i].src == "club" and not h[i].paired then
      h[i].paired = true
      keepText(h[i], e)
      return
    end
  end
  e.src = "live"
  h[#h + 1] = e
  while #h > MAX_HISTORY do table.remove(h, 1) end
  if page and page:IsVisible() and not dirty then
    if visible(e) then
      smf:AddMessage(format(e))
      page.none:Hide()
      updateLatest()
    end
  else
    dirty = true
    if e.ch == "GUILD" or e.ch == "OFFICER" then setUnread(unread + 1) end
  end
end

-- adds older messages (server history) where they belong in time; those newer than
-- unreadAfter count as unread; returns how many were new. Each saved message pairs with one
-- history message only, so the same text really sent twice still shows twice.
function ns.ChatMerge(entries, window, unreadAfter)
  local h = history()
  if not h then return 0 end
  local n, fresh, used = 0, 0, {}
  for _, e in ipairs(entries) do
    if e.t and e.name then
      local i = findSame(h, e, used)
      if i then
        used[h[i]] = true
      else
        e.src = "club"
        h[#h + 1] = e
        used[e] = true
        n = n + 1
        if unreadAfter and e.t > unreadAfter then fresh = fresh + 1 end
      end
    end
  end
  if n == 0 then return 0 end
  table.sort(h, function(a, b) return a.t < b.t end)
  while #h > MAX_HISTORY do table.remove(h, 1) end
  if page and page:IsVisible() then
    rebuild()
  else
    dirty = true
    if fresh > 0 then setUnread(unread + fresh) end
  end
  return n
end

-- Capture (always on, even while the window is closed) -----------------------------------------------
local function classOf(guid)
  if guid and guid ~= "" and GetPlayerInfoByGUID then
    local _, cls = GetPlayerInfoByGUID(guid)
    return cls
  end
end

local cap = CreateFrame("Frame")
cap:RegisterEvent("CHAT_MSG_GUILD")
cap:RegisterEvent("CHAT_MSG_OFFICER")
cap:SetScript("OnEvent", function(_, event, msg, sender, _, _, _, _, _, _, _, _, _, guid)
  if not ns.db or not IsInGuild() or ns.Secret(msg, sender, guid) then return end
  add({ t = now(), ch = event == "CHAT_MSG_GUILD" and "GUILD" or "OFFICER", name = sender,
    class = classOf(guid), msg = msg })
end)

-- Online list (right) -------------------------------------------------------------------------------
local function refreshSide()
  if not sideContent then return end
  local list = {}
  for _, m in ipairs(ns.members) do if m.online then list[#list + 1] = m end end
  table.sort(list, function(a, b)
    if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
    return a.short < b.short
  end)
  sideTitle.right:SetText(#list)
  for i, m in ipairs(list) do
    local r = sideRows[i]
    if not r then
      r = CreateFrame("Button", nil, sideContent)
      r:SetHeight(20)
      r:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
      r:SetPoint("TOPRIGHT", 0, -(i - 1) * 20)
      r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      S.RowHighlight(r)
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(14, 14)
      r.icon:SetPoint("LEFT", 6, 0)
      r.dot = r:CreateTexture(nil, "OVERLAY")
      r.dot:SetTexture(S.MEDIA .. "Dot")
      r.dot:SetSize(6, 6)
      r.dot:SetPoint("CENTER", r.icon, "BOTTOMRIGHT", -1, 1)
      r.name = S.Text(r, 12, "text")
      r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
      r.name:SetWidth(SIDE_W - 70)
      r.lvl = S.Text(r, 11, "muted")
      r.lvl:SetPoint("RIGHT", -6, 0)
      r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then ns.MemberMenu(self, self.member)
        elseif not ns.IsMe(self.member) then
          -- whisper from our own input line
          input:SetText("/w " .. self.member.name .. " ")
          input:SetFocus()
        end
      end)
      r:HookScript("OnEnter", function(self)
        local m2 = self.member
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(m2.short, ns.ClassColor(m2.classFile))
        GameTooltip:AddLine(string.format(L["Level %d %s"], m2.level, m2.class), 1, 1, 1)
        GameTooltip:AddLine(m2.rank, color(C.gold))
        if m2.zone ~= "" then GameTooltip:AddLine(m2.zone, 0.7, 0.66, 0.8) end
        GameTooltip:AddLine(L["Click: whisper  ·  Right-click: actions"], 0.55, 0.5, 0.65)
        GameTooltip:Show()
      end)
      r:HookScript("OnLeave", function() GameTooltip:Hide() end)
      sideRows[i] = r
    end
    r.member = m
    ns.SetClassIcon(r.icon, m.classFile)
    r.name:SetText(m.short)
    r.name:SetTextColor(ns.ClassColor(m.classFile))
    r.lvl:SetText(m.level)
    local sc = ({ afk = C.warn, dnd = C.bad })[m.status] or C.good
    r.dot:SetVertexColor(color(sc))
    r:Show()
  end
  for i = #list + 1, #sideRows do sideRows[i]:Hide() end
  sideContent:SetHeight(math.max(1, #list * 20))
end

-- Input ------------------------------------------------------------------------------------------------
local function setChannel(ch)
  channel = ch
  local officer = ch == "OFFICER"
  channelBtn:SetText(officer and L["Officer"] or L["Guild"])
  local r, g, b = chatColor(ch)
  channelBtn.text:SetTextColor(r, g, b)
  input.edit:SetTextColor(r, g, b)
end

local function send(text)
  text = strtrim(text or "")
  if text == "" then return end
  local target, rest = text:match("^/[wW]%s+(%S+)%s+(.+)$")
  if not target then target, rest = text:match("^/[cC][hH][uU][cC][hH][oO][tT][eE][rR]%s+(%S+)%s+(.+)$") end
  if target then
    SendChatMessage(rest, "WHISPER", nil, target)
  elseif text:match("^/[oO]%s+") then
    SendChatMessage(text:gsub("^/[oO]%s+", ""), "OFFICER")
  elseif text:match("^/[gG]%s+") then
    SendChatMessage(text:gsub("^/[gG]%s+", ""), "GUILD")
  else
    SendChatMessage(text, channel)
  end
end

-- Page ---------------------------------------------------------------------------------------------------
local FILTERS = { { "all", "All" }, { "GUILD", "Guild" }, { "OFFICER", "Officer" } }

local function build(p)
  page = p
  local chatW = ns.PAGE_W - SIDE_W - 14

  -- filters
  local x = 0
  for i, f in ipairs(FILTERS) do
    local pill = S.Pill(p, L[f[2]], function()
      filter = f[1]
      for _, q in ipairs(pills) do q:SetActive(q.key == filter) end
      rebuild()
    end)
    pill.key = f[1]
    pill:SetPoint("TOPLEFT", x, 0)
    x = x + pill:GetWidth() + 6
    pill:SetActive(f[1] == filter)
    pills[i] = pill
  end
  local clear = S.Button(p, L["Clear history"], 120, 22, function()
    S.Dialog({ title = L["Clear history"], text = L["Delete the saved guild chat history?"], accept = L["Delete"],
      danger = true, onAccept = function()
        local h = history()
        if h then wipe(h) end
        rebuild()
      end })
  end)
  clear:SetPoint("TOPLEFT", chatW - 120, 0)

  -- messages
  local card = CreateFrame("Frame", nil, p)
  card:SetPoint("TOPLEFT", 0, -32)
  card:SetSize(chatW, ns.PAGE_H - 32 - 40)
  S.Card(card, 8)
  S.EdgeGlow(card, 24, 0.08)

  smf = CreateFrame("ScrollingMessageFrame", nil, card)
  smf:SetPoint("TOPLEFT", 12, -10)
  smf:SetPoint("BOTTOMRIGHT", -12, 10)
  smf:SetFontObject(S.Font(13))
  smf:SetJustifyH("LEFT")
  smf:SetFading(false)
  smf:SetMaxLines(MAX_HISTORY + 50)
  if smf.SetIndentedWordWrap then smf:SetIndentedWordWrap(true) end
  smf:SetSpacing(3)
  smf:SetHyperlinksEnabled(true)
  smf:SetScript("OnHyperlinkClick", function(self, link, text, button) SetItemRef(link, text, button, self) end)
  smf:SetScript("OnHyperlinkEnter", function(self, link)
    local kind = link:match("^(%a+):")
    if kind == "item" or kind == "spell" or kind == "enchant" or kind == "quest" then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      pcall(GameTooltip.SetHyperlink, GameTooltip, link)
      GameTooltip:Show()
    end
  end)
  smf:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  smf:EnableMouseWheel(true)
  smf:SetScript("OnMouseWheel", function(self, d)
    if IsShiftKeyDown() then
      if d > 0 then self:ScrollToTop() else self:ScrollToBottom() end
    else
      for _ = 1, 3 do if d > 0 then self:ScrollUp() else self:ScrollDown() end end
    end
    updateLatest()
  end)

  p.none = S.Text(card, 13, "muted")
  p.none:SetPoint("CENTER")
  p.none:SetText(L["No message yet. Messages are kept from now on."])

  -- back to the latest messages (shown when scrolled up)
  latest = S.Button(card, L["Latest messages"], 140, 22, function()
    smf:ScrollToBottom()
    updateLatest()
  end, "primary")
  latest:SetPoint("BOTTOMRIGHT", -14, 10)
  latest:SetFrameLevel(smf:GetFrameLevel() + 5)
  latest:SetAlpha(0)
  latest:Hide()

  -- input line
  channelBtn = S.Button(p, L["Guild"], 90, 28, function()
    setChannel(channel == "GUILD" and "OFFICER" or "GUILD")
  end)
  channelBtn:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -10)
  S.Tooltip(channelBtn, { L["Channel"], L["Click to switch between guild and officer chat."],
    L["You can also type /g, /o or /w name."] })
  input = S.EditBox(p, chatW - 98, 28, L["Write to the guild..."], nil)
  input:SetPoint("LEFT", channelBtn, "RIGHT", 8, 0)
  input:SetMaxLetters(255)
  input.edit:SetScript("OnEnterPressed", function(self)
    send(self:GetText())
    self:SetText("")
    -- stays focused for the next message, like the game's chat
  end)
  input.edit:SetScript("OnTabPressed", function()
    setChannel(channel == "GUILD" and "OFFICER" or "GUILD")
  end)
  setChannel("GUILD")

  -- online members
  local side = CreateFrame("Frame", nil, p)
  side:SetPoint("TOPRIGHT")
  side:SetPoint("BOTTOMRIGHT")
  side:SetWidth(SIDE_W)
  S.Card(side, 10)
  sideTitle = S.Section(side, L["Online now"])
  sideTitle:SetPoint("TOPLEFT", 12, -8)
  sideTitle:SetPoint("TOPRIGHT", -12, -8)
  sideScroll, sideContent = S.Scroll(side)
  sideScroll:SetPoint("TOPLEFT", 6, -38)
  sideScroll:SetPoint("BOTTOMRIGHT", -14, 8)
  sideContent:SetWidth(SIDE_W - 20)
  -- a hidden input must not keep the keyboard
  p:SetScript("OnHide", function() input:ClearFocus() end)
end

local lastServerLoad = 0
local function onShow()
  local g = ns.GuildName()
  -- drawn again only when something changed while the tab was closed
  if dirty or g ~= page.guild then page.guild = g; rebuild() end
  -- anything new on the server: asked once the tab animation is over, at most once a minute
  -- (live messages arrive by themselves)
  if ns.LoadServerHistory and GetTime() - lastServerLoad > 60 then
    lastServerLoad = GetTime()
    C_Timer.After(0.4, function() if page:IsVisible() then ns.LoadServerHistory() end end)
  end
  refreshSide()
  setUnread(0)
  pills[3]:SetShown(ns.Can.viewOfficer())
  channelBtn:SetEnabled(ns.Can.viewOfficer())
  if not ns.Can.viewOfficer() and channel == "OFFICER" then setChannel("GUILD") end
end

ns.AddPage(PAGE_INDEX, "Chat", build, onShow, { "Interface\\Icons\\INV_Letter_15", "Interface\\Icons\\INV_Letter_09", "Interface\\Icons\\INV_Misc_Note_01" })

ns.On("ROSTER", function() if page and page:IsVisible() then refreshSide() end end)
ns.On("GUILD", function()
  -- another guild (joined or left): its own history
  local g = ns.GuildName()
  if page and page:IsVisible() and g ~= page.guild then page.guild = g; rebuild() end
end)
