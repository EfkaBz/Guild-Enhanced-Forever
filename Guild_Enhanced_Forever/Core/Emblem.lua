-- Guild Enhanced Forever: the guild emblem from the guild tabard, as the game's Guild & Communities
-- micro button shows it: the emblem in its color on the tabard's background color. Without a
-- tabard (or out of a guild), the addon icon stays in its place.
local _, ns = ...

local emblems = {}

local function tbl(x) return type(x) == "table" and x or nil end

-- a color as r, g, b (0-1) from a ColorMixin, a table or 0-255 numbers
local function rgb(c, g, b)
  if type(c) == "table" then
    if c.GetRGB then return c:GetRGB() end
    return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1
  end
  if type(c) == "number" then
    if c > 1 or (g or 0) > 1 or (b or 0) > 1 then return c / 255, (g or 0) / 255, (b or 0) / 255 end
    return c, g or 0, b or 0
  end
end

-- the tabard: { bg = {r, g, b}, emblem = {r, g, b}, file = emblem file } or nil
local function tabard()
  if not IsInGuild() then return end
  local t
  if GetGuildLogoInfo then
    local r = { pcall(GetGuildLogoInfo, "player") }
    if r[1] then
      if type(r[2]) == "table" then -- colors (background, border, emblem), then the emblem file
        if r[5] and r[5] ~= -1 then t = { bg = { rgb(r[2]) }, emblem = { rgb(r[4]) }, file = r[5] } end
      elseif r[11] then             -- 9 color numbers (0-255), then the emblem file
        t = { bg = { rgb(r[2], r[3], r[4]) }, emblem = { rgb(r[8], r[9], r[10]) }, file = r[11] }
      end
    end
  end
  if not t and C_GuildInfo and C_GuildInfo.GetGuildTabardInfo then
    local ok, info = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
    if ok and type(info) == "table" and info.emblemFileID and info.emblemFileID ~= -1 then
      t = { bg = { rgb(info.backgroundColor) }, emblem = { rgb(info.emblemColor) }, file = info.emblemFileID }
    end
  end
  return t
end

local function apply(e)
  local t = tabard()
  local done = false
  if t then
    -- the emblem's picture: the game's own helper picks the file and its crop, like the micro button
    for _, setter in ipairs({ SetLargeGuildTabardTextures, SetSmallGuildTabardTextures }) do
      if not done and type(setter) == "function" then
        done = pcall(setter, "player", e.emblem, e.scratch, e.border) and e.emblem:GetTexture() ~= nil
      end
    end
    if not done and type(t.file) == "number" then
      e.emblem:SetTexture(t.file)
      e.emblem:SetTexCoord(0, 1, 0, 1)
      done = true
    end
    if done then
      -- the colors of the tabard, set here: the emblem in its color, on a plain disc of the background color
      e.emblem:SetVertexColor(t.emblem[1] or 1, t.emblem[2] or 1, t.emblem[3] or 1)
      -- a round disc (the addon's own texture) in the background color: no mask needed
      e.bg:SetTexture(ns.Skin.MEDIA .. "Dot")
      e.bg:SetVertexColor(t.bg[1] or 0.1, t.bg[2] or 0.1, t.bg[3] or 0.1, 1)
    end
  end
  e.bg:SetShown(done)
  e.emblem:SetShown(done)
  e.border:Hide()
  e.scratch:Hide()
  if e.fallback then e.fallback:SetShown(not done) end
end

-- the guild emblem as textures on parent (draw layer, first sub-level), in the box of anchor;
-- fallback: a texture shown instead when there is no emblem (the addon icon); round: a disc
function ns.GuildEmblem(parent, layer, sub, anchor, fallback, round)
  sub = math.min(sub or 1, 5)
  local e = {
    bg = parent:CreateTexture(nil, layer, nil, sub),
    border = parent:CreateTexture(nil, layer, nil, sub + 1),
    -- (the game's helper draws its background here, hidden: a masked texture can't take its crop)
    scratch = parent:CreateTexture(nil, layer, nil, sub),
    emblem = parent:CreateTexture(nil, layer, nil, sub + 2),
    fallback = fallback,
  }
  -- round: a little inside the portrait, so the disc stays within the gold ring
  local inset = round and 3 or 0
  e.bg:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
  e.bg:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
  e.border:SetAllPoints(anchor)
  e.border:Hide()
  e.scratch:Hide()
  local size = anchor:GetWidth()
  if not size or size <= 0 then size = 60 end
  e.emblem:SetSize(size * 0.78, size * 0.78)
  e.emblem:SetPoint("CENTER", anchor, "CENTER")
  emblems[#emblems + 1] = e
  apply(e)
  return e
end

-- the emblem in the round portrait of a window made with S.Window(..., "portrait")
function ns.PortraitEmblem(f)
  local tex = (tbl(f.PortraitContainer) and tbl(f.PortraitContainer.portrait)) or tbl(f.portrait) or tbl(f.Portrait)
  if not (tex and tex.GetDrawLayer and tex.GetParent) then return end
  local layer, sub = tex:GetDrawLayer()
  return ns.GuildEmblem(tex:GetParent(), layer, (sub or 0) + 1, tex, tex, true)
end

function ns.RefreshEmblems()
  for _, e in ipairs(emblems) do apply(e) end
end

-- a new tabard, joining or leaving a guild; and each time the game updates its micro button
local ev = CreateFrame("Frame")
for _, name in ipairs({ "PLAYER_GUILD_UPDATE", "GUILDTABARD_UPDATE", "PLAYER_ENTERING_WORLD" }) do
  pcall(ev.RegisterEvent, ev, name)
end
local hooked
ev:SetScript("OnEvent", function()
  if not hooked and type(_G.GuildMicroButton_UpdateTabard) == "function" then
    hooked = true
    hooksecurefunc("GuildMicroButton_UpdateTabard", function() C_Timer.After(0, ns.RefreshEmblems) end)
  end
  C_Timer.After(0.5, ns.RefreshEmblems)
end)
