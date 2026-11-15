-- Guild Enhanced Forever: a dialog whose confirm button runs one of the game's slash commands.
-- Guild actions (invite...) are protected on this client: an addon calling them is blocked, but
-- the game's own commands (/ginvite...) still work from a secure macro button. Kept apart from the
-- shared dialog: a window holding a secure button can't be hidden in combat, so this one closes
-- when combat starts and doesn't open during it.
-- ns.SecureAsk{ title, text, input, placeholder, maxLetters, accept, macro = function(text) -> macro text }
-- without input (nil), it's a plain confirmation: macro() gets no text
local _, ns = ...
local L, S = ns.L, ns.Skin

local W, PAD = 420, 16
local win, blocker, args

local function hide()
  if blocker and blocker:IsShown() and not InCombatLockdown() then
    win.input:ClearFocus()
    blocker:Hide()
  end
end

local function refreshAccept()
  if InCombatLockdown() then return end
  local text = args.input and strtrim(win.input:GetText() or "") or true
  if text == "" then
    win.accept:SetAttribute("macrotext", nil)
    win.accept:Disable()
  else
    win.accept:SetAttribute("macrotext", args.macro(args.input and text or nil))
    win.accept:Enable()
  end
end

local function build()
  blocker = CreateFrame("Frame", "GuildEnhancedForeverSecureBlocker", UIParent)
  blocker:SetAllPoints(UIParent)
  blocker:SetFrameStrata("DIALOG")
  blocker:EnableMouse(true)
  blocker:Hide()

  win = S.Window("GuildEnhancedForeverSecureDialog", blocker, W, 180, "", "portrait")
  win:SetFrameStrata("DIALOG")
  win:SetFrameLevel(blocker:GetFrameLevel() + 5)
  win:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  win.close:SetScript("OnClick", hide)
  if win.titleBar then S.Draggable(win, win.titleBar) end
  if not S.SetPortrait(win, ns.ICON) then
    local icon = win:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 8, -6)
    icon:SetTexture(ns.ICON)
  end

  win.sub = S.Text(win, 12, "dim")
  win.sub:SetPoint("TOPLEFT", 66, -32)
  win.sub:SetPoint("RIGHT", -16, 0)
  win.sub:SetText("Guild Enhanced Forever")

  local card = CreateFrame("Frame", nil, win)
  card:SetPoint("TOPLEFT", 14, -62)
  card:SetPoint("BOTTOMRIGHT", -14, 56)
  S.Card(card, 8)

  win.text = S.Text(card, 12, "text")
  win.text:SetFontObject(GameFontHighlight)
  win.text:SetPoint("TOP", 0, -PAD)
  win.text:SetWidth(W - 28 - 2 * PAD)
  win.text:SetWordWrap(true)
  win.text:SetJustifyH("CENTER")

  -- Enter can't press a secure button: it only leaves the field, the button is clicked
  win.input = S.EditBox(card, W - 28 - 2 * PAD, 24, "")
  win.input.onChange = refreshAccept
  win.input.edit:SetScript("OnEscapePressed", hide)

  local ok, b = pcall(CreateFrame, "Button", "GuildEnhancedForeverSecureAccept", win,
    "UIPanelButtonTemplate,SecureActionButtonTemplate")
  if not ok or not b then b = CreateFrame("Button", "GuildEnhancedForeverSecureAccept", win, "SecureActionButtonTemplate") end
  win.accept = b
  b:SetSize(140, 26)
  b:SetPoint("BOTTOMRIGHT", win, "BOTTOM", -6, 16)
  b:SetNormalFontObject(GameFontNormal)
  b:SetHighlightFontObject(GameFontHighlight)
  b:SetDisabledFontObject(GameFontDisable)
  b:SetAttribute("type", "macro")
  b:SetScript("PostClick", function()
    hide()
    C_Timer.After(1, ns.RequestRoster)
  end)

  local cancel = S.Button(win, L["Cancel"], 140, 26, hide)
  cancel:SetPoint("BOTTOMLEFT", win, "BOTTOM", 6, 16)

  tinsert(UISpecialFrames, "GuildEnhancedForeverSecureBlocker") -- Escape closes it

  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_REGEN_DISABLED")
  ev:SetScript("OnEvent", hide)
end

function ns.SecureAsk(a)
  if InCombatLockdown() then
    ns.Print(L["Not possible in combat."])
    return
  end
  if not win then build() end
  S.CloseMenu()
  args = a
  win.title:SetText(a.title or "")
  win.text:SetText(a.text or "")
  local th = math.ceil(win.text:GetStringHeight())
  win.input:SetShown(a.input ~= nil)
  win.input:ClearAllPoints()
  win.input:SetPoint("TOP", 0, -(PAD + th + 12))
  win.input.placeholder:SetText(a.placeholder or "")
  win.input:SetMaxLetters(a.maxLetters or 0)
  win.input:SetText(a.input or "")
  win:SetHeight(62 + PAD + th + (a.input and (12 + 24) or 0) + PAD + 56)
  win.accept:SetText(a.accept or L["OK"])
  -- the click is registered on the edge the game's secure buttons act on (key down or key up)
  local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
  win.accept:RegisterForClicks(down and "AnyDown" or "AnyUp")
  refreshAccept()
  blocker:Show()
  win:Show()
  PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN or 850)
  if a.input then win.input:SetFocus() end
end
