-- Guild Enhanced Forever: "What's new" window. Shown once after an update (not on a first install);
-- /gef new shows it again.
local ADDON, ns = ...
local S, L = ns.Skin, ns.L

-- the new things of this version: icon, title, text (English keys, translated in the locales)
local NEWS = {
  { "Interface\\Icons\\INV_Misc_Head_Dragon_01", "Boss loot",
    "The News page now lists the items guildmates receive from dungeon and raid bosses, in their rarity color." },
  { "Interface\\Icons\\INV_Misc_Bag_10", "Clickable items",
    "Click an item in the news to open it like a chat link; Shift-click links it in chat." },
}

local function version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return get and get(ADDON, "Version") or "?"
end

local win
local W, ROW = 460, 52

local function build()
  win = S.Window("GuildEnhancedForeverWhatsNew", UIParent, W, 120 + #NEWS * ROW, "", "portrait")
  win:SetFrameStrata("DIALOG")
  win:SetToplevel(true)
  win:SetPoint("CENTER", 0, 60)
  win:Hide()
  S.Draggable(win, win.titleBar)
  if not S.SetPortrait(win, ns.ICON) then
    local icon = win:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 8, -6)
    icon:SetTexture(ns.ICON)
  end
  win.close:SetScript("OnClick", function() win:Hide() end)
  tinsert(UISpecialFrames, "GuildEnhancedForeverWhatsNew")
  win.title:SetText(string.format(L["What's new in %s"], "Guild Enhanced " .. version()))

  local card = CreateFrame("Frame", nil, win)
  card:SetPoint("TOPLEFT", 12, -64)
  card:SetPoint("BOTTOMRIGHT", -12, 48)
  S.Card(card, 6)
  for i, n in ipairs(NEWS) do
    local y = -10 - (i - 1) * ROW
    local icon = S.Icon(card, 36)
    icon:SetPoint("TOPLEFT", 12, y)
    icon.tex:SetTexture(S.PickIcon({ n[1], "Interface\\Icons\\INV_Misc_QuestionMark" }))
    local t = S.Text(card, 13, "gold")
    t:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    t:SetText(L[n[2]])
    local d = S.Text(card, 11, "text")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
    d:SetWidth(W - 100)
    d:SetWordWrap(true)
    d:SetText(L[n[3]])
  end
  local hint = S.Text(win, 11, "muted")
  hint:SetPoint("BOTTOMLEFT", 20, 22)
  hint:SetText(L["Type /gef new to see this window again."])
  local ok = S.Button(win, L["OK"], 100, 24, function() win:Hide() end, "primary")
  ok:SetPoint("BOTTOMRIGHT", -16, 16)
end

function ns.ShowWhatsNew()
  if not win then build() end
  win:Show()
  win:Raise()
end

-- once per version, a few seconds after logging in
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  if not ns.db then return end
  local v = version()
  if ns.db.seenVersion == v then return end
  local updated = not ns.freshInstall
  ns.db.seenVersion = v
  if updated then C_Timer.After(6, ns.ShowWhatsNew) end
end)

-- /gef new: the window again; /gef anything else: same as /gui
SLASH_GUILDENHANCEDFOREVERGEF1 = "/gef"
SlashCmdList.GUILDENHANCEDFOREVERGEF = function(msg)
  local m = strtrim(msg or ""):lower()
  if m == "new" or m == "news" then
    ns.ShowWhatsNew()
  else
    SlashCmdList.GUILDENHANCEDFOREVER(msg)
  end
end
