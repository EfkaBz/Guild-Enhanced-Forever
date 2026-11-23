-- Guild Enhanced Forever: data shared between guildmates who have the addon.
--
-- Transport: addon messages (prefix GUIFData) cut into pieces of ~230 bytes and put back together,
-- sent through a throttled queue (urgent messages first, bulk sync after).
-- Serializer: length-prefixed values (strings can hold anything), nested tables.
-- Shared records ("Sync"): collections of records { id, v = version (server time), by = author,
-- del = deleted }, kept per guild. A change is broadcast to the guild; at login a player asks for
-- everything changed since he was last online, and the others answer (the first answer of a record
-- cancels the same answer pending elsewhere).
local _, ns = ...

local PREFIX = "GUIFData"
local CHUNK = 230
local now = GetServerTime or time

local CI = C_ChatInfo or {}
local Register = CI.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
local SendAddon = CI.SendAddonMessage or SendAddonMessage
if Register then Register(PREFIX) end

local Net = {}
ns.Net = Net

-- Serializer ----------------------------------------------------------------------------------------
local function ser(v, out)
  local t = type(v)
  if t == "string" then
    out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "number" then
    out[#out + 1] = "n" .. tostring(v) .. ";"
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif t == "table" then
    out[#out + 1] = "t"
    for k, val in pairs(v) do
      if type(k) == "string" or type(k) == "number" then
        local vt = type(val)
        if vt == "string" or vt == "number" or vt == "boolean" or vt == "table" then
          ser(k, out)
          ser(val, out)
        end
      end
    end
    out[#out + 1] = "e"
  end
end

function Net.Encode(v)
  local out = {}
  ser(v, out)
  return table.concat(out)
end

local function de(s, i, depth)
  local c = s:sub(i, i)
  if c == "s" then
    local colon = s:find(":", i + 1, true)
    if not colon then return nil, nil end
    local len = tonumber(s:sub(i + 1, colon - 1))
    if not len then return nil, nil end
    return s:sub(colon + 1, colon + len), colon + len + 1
  elseif c == "n" then
    local semi = s:find(";", i + 1, true)
    if not semi then return nil, nil end
    return tonumber(s:sub(i + 1, semi - 1)), semi + 1
  elseif c == "T" then
    return true, i + 1
  elseif c == "F" then
    return false, i + 1
  elseif c == "t" then
    if depth > 8 then return nil, nil end
    local t, j = {}, i + 1
    while j <= #s and s:sub(j, j) ~= "e" do
      local k, v
      k, j = de(s, j, depth + 1)
      if k == nil or not j then return nil, nil end
      v, j = de(s, j, depth + 1)
      if v == nil or not j then return nil, nil end
      t[k] = v
    end
    return t, j + 1
  end
  return nil, nil
end

function Net.Decode(s)
  if type(s) ~= "string" or s == "" then return nil end
  local ok, v = pcall(de, s, 1, 0)
  return ok and v or nil
end

-- user text: no control characters that the transport uses
function Net.Clean(text)
  return (tostring(text or ""):gsub("[%z\1-\9\11-\31]", ""))
end

-- Throttled queue -----------------------------------------------------------------------------------
local queues = { {}, {} } -- 1 urgent, 2 bulk
local tokens, MAX_TOKENS, RATE = 6, 6, 1
local RESULT = Enum and Enum.SendAddonMessageResult or {}
local function throttled(res)
  return res ~= nil and (res == RESULT.AddonMessageThrottle or res == RESULT.ChannelThrottle)
end
-- chat lockdown: the game locks addon messages in some situations (instances, encounters, PvP):
-- what we receive is hidden and what we send is dropped. Messages wait in the queue meanwhile and
-- leave as soon as it ends; then we ask the guild for what we missed (see "Lockdown" below).
local function locked()
  return CI.InChatMessagingLockdown and CI.InChatMessagingLockdown() and true or false
end
Net.Locked = locked

local pump = CreateFrame("Frame")
pump:Hide()
pump:SetScript("OnUpdate", function(self, e)
  tokens = math.min(MAX_TOKENS, tokens + e * RATE)
  if locked() then return end -- kept for later
  while tokens >= 1 do
    local q = queues[1][1] and queues[1] or queues[2][1] and queues[2]
    if not q then break end
    local m = table.remove(q, 1)
    if not m.cancel or not m.cancel() then
      local res = SendAddon(PREFIX, m.text, m.channel, m.target)
      if throttled(res) then
        -- the game refused it (too many messages): tried again a moment later
        m.tries = (m.tries or 0) + 1
        if m.tries < 10 then table.insert(q, 1, m) end
        tokens = 0
        break
      end
      tokens = tokens - 1
    end
  end
  if not queues[1][1] and not queues[2][1] then self:Hide() end
end)

-- cuts on a character boundary (no half UTF-8 character at the end of a piece)
local function cut(s, size)
  local parts, i = {}, 1
  while i <= #s do
    local j = math.min(#s, i + size - 1)
    while j < #s and j > i do
      local b = s:byte(j + 1)
      if b < 0x80 or b >= 0xC0 then break end
      j = j - 1
    end
    parts[#parts + 1] = s:sub(i, j)
    i = j + 1
  end
  if #parts == 0 then parts[1] = "" end
  return parts
end

local msgCounter = math.random(1, 9999)
local sentIds = {} -- ids of our own messages (the guild channel sends them back to us)

-- kind: short tag; data: any value; channel "GUILD" or "WHISPER" (target); bulk: lower priority;
-- cancel(): checked right before each piece leaves (true = not sent)
function Net.Send(kind, data, channel, target, bulk, cancel)
  if not SendAddon then return end
  if channel == "GUILD" and not IsInGuild() then return end
  local payload = Net.Encode(data):gsub("\n", "\29")
  msgCounter = (msgCounter % 99999) + 1
  sentIds[msgCounter] = GetTime()
  local parts = cut(payload, CHUNK)
  local q = queues[bulk and 2 or 1]
  for i, p in ipairs(parts) do
    q[#q + 1] = { text = kind .. "\31" .. msgCounter .. "\31" .. i .. "\31" .. #parts .. "\31" .. p,
      channel = channel, target = target, cancel = cancel }
  end
  pump:Show()
end

local handlers = {}
function Net.On(kind, fn)
  handlers[kind] = handlers[kind] or {}
  table.insert(handlers[kind], fn)
end

local buffers = {} -- sender .. id -> { parts, n, t }
-- last messages seen (/gui net)
local netLog = {}
function Net.Log(sender, kind, what)
  table.insert(netLog, string.format("%s %s %s: %s", date("%H:%M:%S"), tostring(sender), tostring(kind), tostring(what)))
  if #netLog > 30 then table.remove(netLog, 1) end
end
function Net.Debug()
  ns.Print("me " .. tostring(UnitName("player")) .. ", full name " .. tostring(ns.MyName()) .. ", sync " .. tostring(ns.Sync.Started())
    .. ", chat lockdown " .. tostring(locked()) .. ", waiting " .. (#queues[1] + #queues[2]))
  if #netLog == 0 then ns.Print("nothing received yet") end
  for _, l in ipairs(netLog) do ns.Print(l) end
end
local me = UnitName("player")

local hidden = 0 -- messages the game hid from us
local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
  if ns.Secret(prefix, text, channel, sender) then
    -- chat lockdown: unreadable, caught up when it ends (see "Lockdown" below)
    hidden = hidden + 1
    Net.MissedSince()
    if hidden == 1 or hidden % 20 == 0 then Net.Log("?", "?", "hidden by the game (chat lockdown): " .. hidden) end
    return
  end
  if prefix ~= PREFIX or not text or not sender then return end
  local name = ns.Short(sender)
  if not ns.byName[name] then Net.Log(sender, text:match("^[^\31]+"), "not in guild") return end
  local kind, id, i, n, piece = text:match("^([^\31]+)\31(%d+)\31(%d+)\31(%d+)\31(.*)$")
  if not kind then return end
  -- our own message coming back (the sender is "Name Surname" or "Name"; another player can
  -- share our first name: check the id too)
  if (name == ns.MyName() or name == me) and sentIds[tonumber(id)] then return end
  if i == "1" then Net.Log(sender, kind, "received " .. id .. " (" .. n .. " pieces)") end
  i, n = tonumber(i), tonumber(n)
  local key = name .. "\31" .. id
  local buf = buffers[key]
  if not buf then
    buf = { parts = {}, got = 0, n = n, t = GetTime() }
    buffers[key] = buf
  end
  if not buf.parts[i] then
    buf.parts[i] = piece
    buf.got = buf.got + 1
  end
  if buf.got < buf.n then return end
  buffers[key] = nil
  local data = Net.Decode((table.concat(buf.parts):gsub("\29", "\n")))
  if data == nil then return end
  for _, fn in ipairs(handlers[kind] or {}) do
    local ok, err = pcall(fn, data, name, channel, sender)
    if not ok then geterrorhandler()(err) end
  end
end)

-- forgets pieces of messages that never completed
C_Timer.NewTicker(30, function()
  local t = GetTime()
  for k, b in pairs(buffers) do if t - b.t > 60 then buffers[k] = nil end end
  for k, st in pairs(sentIds) do if t - st > 120 then sentIds[k] = nil end end
end)

-- Shared records ------------------------------------------------------------------------------------
local Sync = {}
ns.Sync = Sync
local colls = {}       -- name -> { validate(rec, sender), changed(rec, old), keep = seconds }
local pendingSend = {} -- coll .. id -> version waiting to be sent (answers)
local started

local function store(coll)
  local g = ns.GuildName()
  if not g or not ns.db then return nil end
  ns.db.sync = ns.db.sync or {}
  local gs = ns.db.sync[g]
  if not gs then gs = {}; ns.db.sync[g] = gs end
  gs[coll] = gs[coll] or {}
  return gs[coll]
end
Sync.Store = store

-- collection: name; opts = { validate = fn(rec) -> bool, changed = fn(rec, old), keep = seconds a
-- deleted or old record is kept (default 30 days) }
function Sync.Register(coll, opts)
  colls[coll] = opts or {}
end

-- rank index of a guildmate (0 = guild master); 99 when unknown
function Sync.RankOf(name)
  local m = name and ns.byName[name]
  return m and m.rankIndex or 99
end
-- officers: the guild master and the rank right under
function Sync.IsOfficer(name) return Sync.RankOf(name) <= 1 end
function Sync.Me() return ns.MyName() end
function Sync.Started() return started end

function Sync.Get(coll, id)
  local s = store(coll)
  local r = s and s[id]
  if r and not r.del then return r end
end

-- every live record of a collection (not deleted)
function Sync.All(coll)
  local s, list = store(coll), {}
  if s then for _, r in pairs(s) do if not r.del then list[#list + 1] = r end end end
  return list
end

local function apply(coll, rec, fromNet, sender)
  local opts = colls[coll]
  if not opts or type(rec) ~= "table" or type(rec.id) ~= "string" or type(rec.v) ~= "number" then return false end
  if type(rec.by) ~= "string" or rec.by == "" then return false end
  local s = store(coll)
  if not s then return false end
  local old = s[rec.id]
  if old and old.v > rec.v then return false end
  -- same version from two players (changed in the same second): the same winner everywhere
  if old and old.v == rec.v and not ((rec.ed or "") > (old.ed or "")) then return false end
  if fromNet and opts.validate and not opts.validate(rec, old, sender) then
    Net.Log(sender, coll, "refused " .. rec.id .. " by " .. tostring(rec.ed))
    return false
  end
  if fromNet then Net.Log(sender, coll, "kept " .. rec.id) end
  rec.lt = now() -- when this copy changed here (what the login question compares)
  s[rec.id] = rec
  if opts.changed then
    local ok, err = pcall(opts.changed, rec, old)
    if not ok then geterrorhandler()(err) end
  end
  ns.Fire("SYNC_" .. coll:upper(), rec, old)
  return true
end

-- writes a record (new version) and broadcasts it (bulk: behind the urgent messages)
function Sync.Put(coll, rec, bulk)
  local s = store(coll)
  if not s then return end
  local old = s[rec.id]
  local opts = colls[coll] or {}
  rec.v = opts.version and opts.version(rec) or math.max(now(), old and (old.v + 1) or 0)
  rec.by = rec.by or ns.MyName()
  rec.ed = ns.MyName() -- who made this change (full name)
  apply(coll, rec, false)
  Net.Send("P", { c = coll, r = rec }, "GUILD", nil, bulk)
  return rec
end

function Sync.Delete(coll, id)
  local s = store(coll)
  local old = s and s[id]
  if not old then return end
  local rec = CopyTable(old)
  rec.del = true
  Sync.Put(coll, rec)
end

Net.On("P", function(d, sender)
  if type(d) ~= "table" or type(d.c) ~= "string" or not colls[d.c] then return end
  local rec = d.r
  if type(rec) ~= "table" or type(rec.id) ~= "string" then return end
  -- somebody already sent it: our pending answer of the same record is useless
  local key = d.c .. "\31" .. rec.id
  if pendingSend[key] and type(rec.v) == "number" and rec.v >= pendingSend[key] then pendingSend[key] = nil end
  apply(d.c, rec, true, sender)
end)

-- "what changed since t?" (asked at login); the answer goes to the whole guild
Net.On("Q", function(d)
  if type(d) ~= "table" or type(d.since) ~= "number" then return end
  local delay = 0.5 + math.random() * 4
  C_Timer.After(delay, function()
    for coll in pairs(colls) do
      local s = store(coll)
      if s then
        for id, r in pairs(s) do
          if (r.lt or r.v) > d.since then
            local key = coll .. "\31" .. id
            pendingSend[key] = r.v
            local v = r.v
            Net.Send("P", { c = coll, r = r }, "GUILD", nil, true, function()
              -- cancelled when someone else sent it first
              return pendingSend[key] ~= v
            end)
          end
        end
      end
    end
  end)
end)

-- old deleted records and records past their keeping time go away
local function prune()
  local t = now()
  for coll, opts in pairs(colls) do
    local s = store(coll)
    if s then
      local keep = opts.keep or 30 * 86400
      for id, r in pairs(s) do
        local expired = opts.expired and opts.expired(r, t)
        if (r.del and t - r.v > keep) or expired then s[id] = nil end
      end
    end
  end
end

local missedSince, lastAsk = nil, 0
local function seenKey() return ns.GuildName() end
local function markSeen()
  local g = seenKey()
  if g and ns.db then
    ns.db.syncSeen = ns.db.syncSeen or {}
    local t = now()
    if missedSince or locked() then
      t = math.min(t, missedSince or t)
      ns.db.syncSeen[g] = math.min(ns.db.syncSeen[g] or t, t)
    else
      ns.db.syncSeen[g] = t
    end
  end
end

function Sync.Start()
  if started or not IsInGuild() or not ns.GuildName() then return end
  started = true
  prune()
  local g = seenKey()
  local since = ns.db.syncSeen and ns.db.syncSeen[g] or 0
  -- a little margin for clocks and messages in flight
  Net.Send("Q", { since = math.max(0, since - 600) }, "GUILD")
  -- my own changes that may not have left (logout with messages waiting, chat lockdown): sent again;
  -- the others keep them only when newer
  local mine = ns.MyName()
  for coll in pairs(colls) do
    local s = store(coll)
    if s then
      for _, r in pairs(s) do
        if r.ed == mine and (r.lt or r.v) > since - 600 then Net.Send("P", { c = coll, r = r }, "GUILD", nil, true) end
      end
    end
  end
  markSeen()
  C_Timer.NewTicker(60, markSeen)
  ns.Fire("SYNC_READY")
  for _, opts in pairs(colls) do if opts.ready then opts.ready() end end
end

local sev = CreateFrame("Frame")
sev:RegisterEvent("PLAYER_ENTERING_WORLD")
sev:RegisterEvent("PLAYER_GUILD_UPDATE")
sev:RegisterEvent("PLAYER_LOGOUT")
sev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGOUT" then markSeen() return end
  if started then return end
  -- the roster must be known first (guildmates only)
  C_Timer.After(12, function()
    if #ns.members == 0 then ns.RequestRoster(); C_Timer.After(8, Sync.Start) else Sync.Start() end
  end)
end)

-- Lockdown -------------------------------------------------------------------------------------------
-- while the game locks addon messages nothing can be read or sent (no addon can get around it).
-- When it ends: the waiting messages leave (queue above) and we ask the guild for every record
-- changed meanwhile, so the shared data is complete again a few seconds later.
function Net.MissedSince()
  missedSince = missedSince or now()
end

local function catchUp()
  if not missedSince or not started or locked() then return end
  if GetTime() - lastAsk < 30 then return end
  lastAsk = GetTime()
  local since = missedSince
  missedSince = nil
  Net.Send("Q", { since = math.max(0, since - 120) }, "GUILD")
  Net.Log("me", "Q", "lockdown over, asking for what was missed")
  if pump then pump:Show() end
end

local lev = CreateFrame("Frame")
lev:RegisterEvent("PLAYER_ENTERING_WORLD")
lev:RegisterEvent("PLAYER_REGEN_ENABLED")
if C_EventUtils == nil or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("ADDON_RESTRICTION_STATE_CHANGED") then
  pcall(lev.RegisterEvent, lev, "ADDON_RESTRICTION_STATE_CHANGED")
end
lev:SetScript("OnEvent", function()
  if locked() then Net.MissedSince() end
  C_Timer.After(2, catchUp)
end)
-- events can be missed: a light check every few seconds
C_Timer.NewTicker(5, function()
  if locked() then Net.MissedSince() else catchUp() end
end)
