-- Guild Enhanced Forever: input fields, drop-downs, tabs, context menus and dialogs, with the game's
-- own templates and textures
local _, ns = ...
local S = ns.Skin
local C, color = S.C, S.Color

-- Edit box -----------------------------------------------------------------
-- the game's input box, grey placeholder; onEnter(text)
function S.EditBox(parent, width, height, placeholder, onEnter)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(width, height or 24)

  local ok, e = pcall(CreateFrame, "EditBox", nil, holder, "InputBoxTemplate")
  if not ok or not e then
    e = CreateFrame("EditBox", nil, holder)
    e:SetFontObject(ChatFontNormal)
    S.Box(holder, C.well, C.trim)
  end
  e:SetPoint("TOPLEFT", 6, 0)
  e:SetPoint("BOTTOMRIGHT", -2, 0)
  e:SetAutoFocus(false)
  e:SetTextInsets(0, 0, 0, 0)
  holder.edit = e

  local ph = S.Text(holder, 12, "muted")
  ph:SetPoint("LEFT", 8, 0)
  ph:SetPoint("RIGHT", -8, 0)
  ph:SetText(placeholder or "")
  holder.placeholder = ph

  local function refreshPh() ph:SetShown(e:GetText() == "" and not e:HasFocus()) end
  e:SetScript("OnEditFocusGained", function(self) self:HighlightText(); refreshPh() end)
  e:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0); refreshPh() end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onEnter then onEnter(self:GetText()) end
  end)
  e:SetScript("OnTextChanged", function(self, user)
    refreshPh()
    if holder.onChange then holder.onChange(self:GetText(), user) end
  end)
  holder:EnableMouse(true)
  holder:SetScript("OnMouseDown", function() e:SetFocus() end)

  function holder:GetText() return e:GetText() end
  function holder:SetText(t) e:SetText(t or ""); refreshPh() end
  function holder:SetFocus() e:SetFocus() end
  function holder:ClearFocus() e:ClearFocus() end
  function holder:SetMaxLetters(n) e:SetMaxLetters(n) end
  function holder:SetBorderColor(r, g, b, a)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do
      if S.Tbl(e[k]) then e[k]:SetVertexColor(r, g, b, a or 1) end
    end
    if self.borders then for _, t in ipairs(self.borders) do t:SetColorTexture(r, g, b, a or 1) end end
  end
  refreshPh()
  return holder
end

-- multi-line edit box in a scrolling panel; read-only when locked
function S.MultiEdit(parent, maxLetters)
  local holder = CreateFrame("Frame", nil, parent)
  S.Rounded(holder, 6, { 0, 0, 0, 0.75 }, nil, C.trim)
  local sf, content = S.Scroll(holder)
  sf:SetPoint("TOPLEFT", 8, -8)
  sf:SetPoint("BOTTOMRIGHT", -16, 8)
  local e = CreateFrame("EditBox", nil, content)
  e:SetMultiLine(true)
  e:SetAutoFocus(false)
  e:SetFontObject(ChatFontNormal)
  e:SetTextColor(1, 1, 1)
  e:SetPoint("TOPLEFT")
  if maxLetters then e:SetMaxLetters(maxLetters) end
  holder.edit, holder.scroll = e, sf
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  holder:SetScript("OnSizeChanged", function(self, w)
    e:SetWidth(w - 26)
    content:SetWidth(w - 26)
  end)
  e:SetScript("OnTextChanged", function(self, user)
    content:SetHeight(math.max(self:GetHeight(), 10))
    if holder.onChange then holder.onChange(self:GetText(), user) end
  end)
  e:SetScript("OnCursorChanged", function(_, _, y, _, h)
    local top, view = sf:GetVerticalScroll(), sf:GetHeight()
    y = -y
    if y < top then sf.bar:SetValue(y)
    elseif y + h > top + view then sf.bar:SetValue(y + h - view) end
  end)
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() if not holder.locked then e:SetFocus() end end)

  function holder:SetLocked(locked)
    self.locked = locked
    e:EnableMouse(not locked)
    e:EnableKeyboard(not locked)
    if locked then e:ClearFocus() end
    self:SetBorderColor(color(locked and C.rule or C.trim))
  end
  function holder:SetText(t) e:SetText(t or ""); e:SetCursorPosition(0); sf.bar:SetValue(0) end
  function holder:GetText() return e:GetText() end
  return holder
end

-- Dropdown -----------------------------------------------------------------
-- the game's drop-down look: a framed field with the round arrow button on the right; the list
-- opens below. options: { {value, text}, ... } or a function returning that
local MENU_ROW, MENU_PAD = 16, 14
local BORDER = "Interface\\Common\\Common-Input-Border"
function S.Dropdown(parent, width, options, getValue, onSelect, menuWidth)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 24)
  local l = b:CreateTexture(nil, "BACKGROUND")
  l:SetTexture(BORDER); l:SetTexCoord(0, 0.0625, 0, 0.625)
  l:SetSize(8, 20); l:SetPoint("LEFT", 0, 0)
  local r = b:CreateTexture(nil, "BACKGROUND")
  r:SetTexture(BORDER); r:SetTexCoord(0.9375, 1, 0, 0.625)
  r:SetSize(8, 20); r:SetPoint("RIGHT", 0, 0)
  local m = b:CreateTexture(nil, "BACKGROUND")
  m:SetTexture(BORDER); m:SetTexCoord(0.0625, 0.9375, 0, 0.625)
  m:SetHeight(20); m:SetPoint("LEFT", l, "RIGHT"); m:SetPoint("RIGHT", r, "LEFT")

  local arrow = CreateFrame("Button", nil, b)
  arrow:SetSize(22, 22)
  arrow:SetPoint("RIGHT", 1, 0)
  arrow:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  arrow:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
  arrow:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
  arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  arrow:SetScript("OnClick", function() b:Click() end)

  b.text = S.Text(b, 12, "text")
  b.text:SetPoint("LEFT", 8, 0)
  b.fitWidth = width - 32
  function b:SetText(t)
    self.text:SetText(t or "")
    S.FitText(self.text, self.fitWidth, 12)
  end
  hooksecurefunc(b, "SetEnabled", function(self, on)
    arrow:SetEnabled(on)
    self.text:SetTextColor(color(on and C.text or C.muted))
  end)

  local function opts() return type(options) == "function" and options() or options end

  local function refreshLabel()
    local v = getValue()
    for _, o in ipairs(opts()) do
      if o[1] == v then b:SetText(o[2]) return end
    end
    b:SetText("")
  end

  b:SetScript("OnClick", function(self)
    if S.MenuOwner() == self then S.CloseMenu() return end
    local list = {}
    local v = getValue()
    for _, o in ipairs(opts()) do
      list[#list + 1] = { text = o[3] or o[2], lang = o[4], checked = o[1] == v, func = function()
        onSelect(o[1])
        refreshLabel()
      end }
    end
    S.OpenMenu(self, list, { width = menuWidth or math.max(width, 140), anchor = "below" })
  end)
  b.Refresh = refreshLabel
  refreshLabel()
  return b
end

-- Slider -------------------------------------------------------------------
-- the game's options slider (min and max under the ends); onChange(value) with whole steps
local sliders = 0
function S.Slider(parent, width, lo, hi, step, onChange)
  sliders = sliders + 1
  local name = "GuildEnhancedForeverSlider" .. sliders
  local ok, s = pcall(CreateFrame, "Slider", name, parent, "OptionsSliderTemplate")
  if not ok or not s then
    s = CreateFrame("Slider", name, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(17)
    S.Backdrop(s, { bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
      edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8,
      insets = { left = 3, right = 3, top = 6, bottom = 6 } })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  end
  s:SetWidth(width)
  s:SetMinMaxValues(lo, hi)
  s:SetValueStep(step or 1)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local low = _G[name .. "Low"] or S.Tbl(s.Low)
  local high = _G[name .. "High"] or S.Tbl(s.High)
  local text = _G[name .. "Text"] or S.Tbl(s.Text)
  if low then low:SetText(lo) end
  if high then high:SetText(hi) end
  if text then text:SetText("") end
  s:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / (step or 1) + 0.5) * (step or 1)
    if onChange then onChange(v) end
  end)
  return s
end

-- Context menu ---------------------------------------------------------------
-- one shared menu in the game's drop-down list style: items { text, func, disabled, checked,
-- color, title, separator }
local menu, catcher, menuRows, menuOwner, menuOnClose = nil, nil, {}, nil, nil

function S.MenuOwner() return menu and menu:IsShown() and menuOwner end

function S.CloseMenu()
  if not menu or not menu:IsShown() then return end
  catcher:Hide()
  local cb = menuOnClose
  menuOwner, menuOnClose = nil, nil
  if cb then cb() end
  menu:Hide()
end

local function buildMenu()
  catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:SetFrameLevel(10)
  catcher:RegisterForClicks("AnyUp")
  catcher:SetScript("OnClick", function() S.CloseMenu() end)
  catcher:Hide()

  menu = CreateFrame("Frame", nil, UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetFrameLevel(20)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  S.Backdrop(menu, {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 9 },
  })
  menu:Hide()
end

local function menuRow(i)
  local row = menuRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, menu)
  row:SetHeight(MENU_ROW)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  S.Highlight(row.hl, 0.25)
  row.hl:Hide()
  row.check = row:CreateTexture(nil, "OVERLAY")
  row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  row.check:SetSize(16, 16)
  row.check:SetPoint("LEFT", 0, 0)
  row.text = S.Text(row, 11)
  row.text:SetPoint("LEFT", 18, 0)
  row.text:SetPoint("RIGHT", -4, 0)
  row.sep = row:CreateTexture(nil, "ARTWORK")
  row.sep:SetPoint("LEFT", 2, 0); row.sep:SetPoint("RIGHT", -2, 0); row.sep:SetHeight(1)
  row.sep:SetColorTexture(0.5, 0.5, 0.5, 0.5)
  row:HookScript("OnEnter", function(self)
    if not (self.item.disabled or self.item.title or self.item.separator) then self.hl:Show() end
  end)
  row:HookScript("OnLeave", function(self) self.hl:Hide() end)
  row:SetScript("OnClick", function(self)
    local it = self.item
    if it.disabled or it.title or it.separator then return end
    S.CloseMenu()
    if it.func then it.func() end
  end)
  menuRows[i] = row
  return row
end

-- owner: frame it belongs to; opts: width, anchor ("below" the owner, or at the cursor), onClose
function S.OpenMenu(owner, items, opts)
  opts = opts or {}
  if not menu then buildMenu() end
  S.CloseMenu()
  local width = (opts.width or 170) + 10
  local y = MENU_PAD
  for i, it in ipairs(items) do
    local row = menuRow(i)
    row.item = it
    local h = it.separator and 8 or MENU_ROW
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", MENU_PAD + 2, -y)
    row:SetPoint("TOPRIGHT", -MENU_PAD, -y)
    y = y + h
    row.hl:Hide()
    row.sep:SetShown(it.separator and true or false)
    row.text:SetShown(not it.separator)
    row.check:SetShown(it.checked and true or false)
    row.text:SetFontObject(S.Font(11, it.lang))
    row.text:SetText(it.text or "")
    row.text:SetPoint("LEFT", it.title and 0 or 18, 0)
    local c = it.title and C.gold or it.disabled and C.muted or it.color or C.text
    row.text:SetTextColor(c[1], c[2], c[3])
    row:Show()
  end
  for i = #items + 1, #menuRows do menuRows[i]:Hide() end
  -- wider when an entry needs it: every entry is read in full, never cut
  for i = 1, #items do
    local it, row = items[i], menuRows[i]
    if not it.separator then
      local need = math.ceil(row.text:GetStringWidth()) + (it.title and 0 or 18) + 2 * MENU_PAD + 14
      if need > width then width = need end
    end
  end
  width = math.min(width, math.floor(UIParent:GetWidth() * 0.6))
  menu:SetSize(width, y + MENU_PAD)
  menu:ClearAllPoints()
  if opts.anchor == "below" then
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", -6, 2)
  else
    local scale = UIParent:GetEffectiveScale()
    local x, cy = GetCursorPosition()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 6, cy / scale + 6)
  end
  menuOwner, menuOnClose = owner, opts.onClose
  GameTooltip:Hide()
  catcher:Show()
  menu:Show()
  PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
end

-- an icon path from a list of candidates: the first one the client has
function S.PickIcon(list)
  if type(list) == "string" or type(list) == "number" then return list end -- a path or a file id
  if type(list) ~= "table" then return "Interface\\Icons\\INV_Misc_QuestionMark" end
  for _, p in ipairs(list) do
    if not GetFileIDFromPath or GetFileIDFromPath(p) then return p end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Side tabs ------------------------------------------------------------------------
-- the spellbook's icon tabs, in a column along the right edge of a window; the label shows
-- on hover; a counter bubble per tab. items: { { label, icon }, ... }
local TAB_SIZE, TAB_STEP = 32, 46
function S.SideTabs(parent, items, onSelect)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetSize(TAB_SIZE + 8, #items * TAB_STEP)
  bar.tabs = {}

  for i, it in ipairs(items) do
    local t = CreateFrame("CheckButton", nil, bar)
    t.index = i
    t:SetSize(TAB_SIZE, TAB_SIZE)
    t:SetPoint("TOPLEFT", 0, -(i - 1) * TAB_STEP)
    local back = t:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    back:SetSize(64, 64)
    back:SetPoint("TOPLEFT", -3, 11)
    t:SetNormalTexture(S.PickIcon(it[2]))
    t.icon = S.Tbl(t:GetNormalTexture())
    t:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    t:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    if S.Tbl(t:GetCheckedTexture()) then t:GetCheckedTexture():SetBlendMode("ADD") end

    -- counter bubble (top right corner)
    local bubble = CreateFrame("Frame", nil, t)
    bubble:SetSize(18, 18)
    bubble:SetPoint("CENTER", t, "TOPRIGHT", -2, -2)
    bubble:SetFrameLevel(t:GetFrameLevel() + 6)
    local disc = bubble:CreateTexture(nil, "ARTWORK")
    disc:SetAllPoints()
    disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    disc:SetVertexColor(0.8, 0.08, 0.06, 1)
    bubble.text = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bubble.text:SetPoint("CENTER", 0, 0)
    bubble:Hide()
    t.bubble = bubble
    function t:SetBadge(text)
      if not text or text == "" then bubble:Hide() return end
      bubble.text:SetText(text)
      bubble:SetWidth(math.max(18, bubble.text:GetStringWidth() + 8))
      bubble:Show()
    end

    t:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(it[1], 1, 1, 1)
      GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    t:SetScript("OnClick", function(self)
      self:SetChecked(bar.selected == self.index)
      if bar.selected ~= self.index then
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841)
        bar:Select(self.index)
      end
    end)
    bar.tabs[i] = t
  end

  function bar:Select(i)
    if self.selected == i then return end
    self.selected = i
    for j, t in ipairs(self.tabs) do t:SetChecked(j == i) end
    onSelect(i)
  end
  function bar:Cascade() end
  return bar
end

-- Pill toggles (log filters): small panel buttons that stay lit while on ---------------------
function S.Pill(parent, text, onClick)
  -- measured at full size first (a narrow button would shrink the font before it is measured), then
  -- sized to the label: every pill keeps the same font and shows its whole word
  local p = S.Button(parent, "", 400, 24, onClick)
  p.fitWidth = 1000
  p:SetText(text)
  p:SetWidth(math.max(70, math.ceil(p.text:GetStringWidth()) + 32))
  function p:SetActive(a)
    self.active = a
    if a then self:LockHighlight() else self:UnlockHighlight() end
  end
  return p
end

-- a page's view switch (Calendar / Group finder...): a large game button with an icon and a
-- bigger label; the active one stays pressed with a white label, the others are gold
function S.ModeTab(parent, text, icon, onClick)
  local b = S.Button(parent, "", 170, 30, onClick)
  b:SetText("")
  b.icon = b:CreateTexture(nil, "OVERLAY")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("LEFT", 10, 0)
  b.icon:SetTexture(S.PickIcon(icon))
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
  b.label:SetWordWrap(false)
  b.text = b.label -- (callers set the label through .text)
  function b:SetLabel(t)
    self.label:SetText(t or "")
    self:SetWidth(math.max(150, math.ceil(self.label:GetStringWidth()) + 54))
  end
  function b:SetActive(a)
    self.active = a
    if a then
      self:LockHighlight()
      self:SetButtonState("PUSHED", true)
      self.label:SetTextColor(1, 1, 1)
      self.icon:SetDesaturated(false)
      self.icon:SetAlpha(1)
    else
      self:UnlockHighlight()
      self:SetButtonState("NORMAL")
      self.label:SetTextColor(1, 0.82, 0)
      self.icon:SetDesaturated(true)
      self.icon:SetAlpha(0.8)
    end
  end
  b:SetLabel(text)
  b:SetActive(false)
  return b
end

-- Dialog -----------------------------------------------------------------------
-- one shared modal, in the look of the Options and form windows (the game's portrait frame with the
-- guild crest, the message on a card, the buttons under it):
-- S.Dialog{ title, sub, text, input = default text | nil, placeholder, maxLetters, accept, cancel,
--   danger, onAccept(text) }
local dlg
local DLG_W, DLG_PAD = 420, 16
local function buildDialog()
  local blocker = CreateFrame("Frame", "GuildEnhancedForeverDialogBlocker", UIParent)
  blocker:SetAllPoints(UIParent)
  blocker:SetFrameStrata("DIALOG")
  blocker:EnableMouse(true)
  blocker:Hide()

  dlg = S.Window("GuildEnhancedForeverDialog", blocker, DLG_W, 200, "", "portrait")
  dlg:SetFrameStrata("DIALOG")
  dlg:SetFrameLevel(blocker:GetFrameLevel() + 5)
  dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  dlg.blocker = blocker
  dlg.close:SetScript("OnClick", function() dlg.Dismiss() end)
  if dlg.titleBar then S.Draggable(dlg, dlg.titleBar) end
  if not S.SetPortrait(dlg, ns.ICON) then
    local icon = dlg:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 8, -6)
    icon:SetTexture(ns.ICON)
  end

  dlg.sub = S.Text(dlg, 12, "dim")
  dlg.sub:SetPoint("TOPLEFT", 66, -32)
  dlg.sub:SetPoint("RIGHT", -16, 0)

  dlg.card = CreateFrame("Frame", nil, dlg)
  dlg.card:SetPoint("TOPLEFT", 14, -62)
  dlg.card:SetPoint("BOTTOMRIGHT", -14, 56)
  S.Card(dlg.card, 8)

  dlg.text = S.Text(dlg.card, 12, "text")
  dlg.text:SetFontObject(GameFontHighlight)
  dlg.text:SetPoint("TOP", 0, -DLG_PAD)
  dlg.text:SetWidth(DLG_W - 28 - 2 * DLG_PAD)
  dlg.text:SetWordWrap(true)
  dlg.text:SetJustifyH("CENTER")
  dlg.text:SetJustifyV("TOP")

  dlg.input = S.EditBox(dlg.card, DLG_W - 28 - 2 * DLG_PAD, 24, "", function() dlg.Accept() end)
  dlg.accept = S.Button(dlg, "", 140, 26, function() dlg.Accept() end, "primary")
  dlg.accept:SetPoint("BOTTOMRIGHT", dlg, "BOTTOM", -6, 16)
  dlg.cancel = S.Button(dlg, "", 140, 26, function() dlg.Dismiss() end)
  dlg.cancel:SetPoint("BOTTOMLEFT", dlg, "BOTTOM", 6, 16)
  dlg.input.edit:SetScript("OnEscapePressed", function() dlg.Dismiss() end)

  function dlg.Dismiss()
    dlg.input:ClearFocus()
    blocker:Hide()
  end
  function dlg.Accept()
    local a = dlg.args
    if a.input and dlg.input:GetText():gsub("%s", "") == "" and not a.allowEmpty then return end
    dlg.Dismiss()
    if a.onAccept then a.onAccept(a.input and dlg.input:GetText() or nil) end
  end
  tinsert(UISpecialFrames, "GuildEnhancedForeverDialogBlocker") -- Escape closes it
end

function S.Dialog(args)
  if not dlg then buildDialog() end
  local L = ns.L
  S.CloseMenu(true)
  dlg.args = args
  dlg.title:SetText(args.title or "")
  dlg.sub:SetText(args.sub or "Guild Enhanced Forever")
  dlg.text:SetText(args.text or "")
  dlg.text:SetShown(args.text ~= nil)
  local th = args.text and math.ceil(dlg.text:GetStringHeight()) or 0
  local h = DLG_PAD + th -- inside the card
  if args.input then
    dlg.input:Show()
    dlg.input:ClearAllPoints()
    dlg.input:SetPoint("TOP", 0, -(DLG_PAD + th + (th > 0 and 12 or 0)))
    dlg.input:SetText(args.input)
    dlg.input.placeholder:SetText(args.placeholder or "")
    dlg.input:SetMaxLetters(args.maxLetters or 0)
    dlg.input.onChange = args.locked and function(t)
      if t ~= args.input then
        dlg.input:SetText(args.input)
        dlg.input.edit:HighlightText()
      end
    end or nil
    h = h + (th > 0 and 12 or 0) + 24
  else
    dlg.input:Hide()
  end
  h = h + DLG_PAD
  dlg:SetHeight(62 + math.max(h, 44) + 56)
  dlg.accept:SetText(args.accept or L["OK"])
  dlg.cancel:SetText(args.cancel or L["Cancel"])
  dlg.blocker:Show()
  dlg:Show()
  if S.AnimateOpen then S.AnimateOpen(dlg, 0, -10) end
  PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN or 850)
  if args.input then
    dlg.input:SetFocus()
    dlg.input.edit:HighlightText()
  end
end
