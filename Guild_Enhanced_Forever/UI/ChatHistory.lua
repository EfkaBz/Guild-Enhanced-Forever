-- Guild Enhanced Forever: guild chat history kept by the server (the same one the game's Guild &
-- Communities window shows, messages sent while you were offline included). Loaded at login
-- and when the Discussion tab opens, then merged into the addon's own history.
local _, ns = ...

local Club = C_Club
local WANT = 300          -- messages per channel to load at most
local BATCH = 100         -- messages asked per request
local now = GetServerTime or time

local clubId
local streams = {}        -- streamId -> { ch = GUILD | OFFICER, oldest = messageId, done = bool }
local lastSeen            -- last time this guild was seen (before this session), for the unread count

local function classFileOf(classID)
  if not classID then return nil end
  if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
    local info = C_CreatureInfo.GetClassInfo(classID)
    if info then return info.classFile end
  end
  if GetClassInfo then
    local _, file = GetClassInfo(classID)
    return file
  end
end

local function streamChannel(s)
  if ns.Secret(s.streamType, s.streamId) then return nil end -- hidden by the game: unusable
  local T = Enum and Enum.ClubStreamType
  if T then
    if s.streamType == T.Guild then return "GUILD" end
    if s.streamType == T.Officer then return "OFFICER" end
    return nil
  end
  return s.streamType == 1 and "GUILD" or s.streamType == 2 and "OFFICER" or nil
end

-- the author's name; the server history gives "Unknown" while the game has not loaded that
-- member yet: then the GUID or the club member info may know it. nil when nobody knows.
local function known(name)
  return type(name) == "string" and not ns.Secret(name) and name ~= "" and name ~= (UNKNOWNOBJECT or "Unknown") and name or nil
end
local function authorName(a)
  local name = known(a.name)
  if name then return name end
  if a.guid and not ns.Secret(a.guid) and GetPlayerInfoByGUID then
    local ok, _, _, _, _, _, n, realm = pcall(GetPlayerInfoByGUID, a.guid)
    if ok and known(n) then return (realm and realm ~= "") and (n .. "-" .. realm) or n end
  end
  if a.memberId and not ns.Secret(a.memberId) and Club.GetMemberInfo then
    local ok, info = pcall(Club.GetMemberInfo, clubId, a.memberId)
    if ok and info then return known(info.name) end
  end
end
ns.ChatKnownName = known

-- every message the client holds for a stream, turned into history entries
local function collectAll(streamId)
  local st = streams[streamId]
  if not st then return 0 end
  local ok, ranges = pcall(Club.GetMessageRanges, clubId, streamId)
  if not ok or not ranges then return 0 end
  local entries, oldest = {}, nil
  for _, r in ipairs(ranges) do
    if ns.Secret(r.oldestMessageId, r.newestMessageId) then break end
    local ok2, msgs = pcall(Club.GetMessagesInRange, clubId, streamId, r.oldestMessageId, r.newestMessageId)
    if ok2 and msgs then
      for _, m in ipairs(msgs) do
        if not ns.Secret(m.content, m.author and m.author.name, m.messageId and m.messageId.epoch, m.destroyed)
          and not m.destroyed and m.content
          and m.content ~= "" and m.author and authorName(m.author) then
          entries[#entries + 1] = {
            t = math.floor((m.messageId.epoch or 0) / 1000000), -- microseconds
            ch = st.ch, name = authorName(m.author), class = classFileOf(m.author.classID), msg = m.content,
          }
          if not oldest or (m.messageId.epoch or 0) < (oldest.epoch or 0) then oldest = m.messageId end
        end
      end
    end
  end
  -- no older message came back: the beginning of the history is reached
  st.done = #entries >= WANT or (st.oldest and oldest and oldest.epoch == st.oldest.epoch)
  st.oldest = oldest
  return ns.ChatMerge(entries, 120, lastSeen)
end
-- values hidden by the game (secret) can make any read fail: that load is skipped, the next one retries
local function collect(streamId)
  local ok, n = pcall(collectAll, streamId)
  return ok and n or 0
end

-- asks the server for older messages, until WANT are loaded or the history ends
local function requestMore(streamId)
  local st = streams[streamId]
  if not st or st.done then return end
  pcall(Club.RequestMoreMessagesBefore, clubId, streamId, st.oldest, BATCH)
end

function ns.LoadServerHistory()
  if not (Club and Club.GetGuildClubId) or not IsInGuild() then return end
  clubId = Club.GetGuildClubId()
  if not clubId or ns.Secret(clubId) then clubId = nil return end
  local ok, list = pcall(Club.GetStreams, clubId)
  if not ok or not list then return end
  for _, s in ipairs(list) do
    local ch = streamChannel(s)
    if ch then
      streams[s.streamId] = streams[s.streamId] or { ch = ch }
      if Club.FocusStream then pcall(Club.FocusStream, clubId, s.streamId) end
      collect(s.streamId)
      requestMore(s.streamId)
    end
  end
end

-- Events ----------------------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("CLUB_MESSAGE_HISTORY_RECEIVED")
ev:RegisterEvent("CLUB_STREAMS_LOADED")

local function saveLastSeen()
  local g = ns.GuildName()
  if g and ns.db then
    ns.db.lastSeen = ns.db.lastSeen or {}
    ns.db.lastSeen[g] = now()
  end
end

local started
ev:SetScript("OnEvent", function(_, event, cid, streamId)
  if ns.Secret(cid, streamId) then return end
  if event == "PLAYER_ENTERING_WORLD" then
    if started then return end
    started = true
    -- the guild and its chat streams are known a few seconds after login
    C_Timer.After(5, function()
      local g = ns.GuildName()
      lastSeen = g and ns.db and ns.db.lastSeen and ns.db.lastSeen[g]
      saveLastSeen()
      C_Timer.NewTicker(60, saveLastSeen)
      ns.LoadServerHistory()
    end)
  elseif event == "PLAYER_LOGOUT" then
    saveLastSeen()
  elseif event == "CLUB_STREAMS_LOADED" then
    if clubId and cid == clubId then ns.LoadServerHistory() end
  elseif event == "CLUB_MESSAGE_HISTORY_RECEIVED" then
    if clubId and cid == clubId and streams[streamId] then
      collect(streamId)
      requestMore(streamId)
    end
  end
end)
