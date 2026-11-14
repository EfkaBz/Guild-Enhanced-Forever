-- Guild Enhanced Forever: the game's own look. Windows, buttons, check boxes, scroll bars, borders
-- and highlights come from the client's templates and textures; the functions keep the names
-- the pages use, so every page gets the default interface.
local ADDON, ns = ...

local S = {}
ns.Skin = S

local WHITE = "Interface\\Buttons\\WHITE8x8"
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\adds\\UI\\"
S.MEDIA, S.WHITE = MEDIA, WHITE

-- Palette: the default interface colors (gold labels, white text, grey borders) --------
local C = {
  bg1      = { 0.12, 0.12, 0.12, 1 },
  bg2      = { 0.05, 0.05, 0.05, 1 },
  well     = { 0, 0, 0, 0.55 },
  trim     = { 0.45, 0.45, 0.45, 1 }, -- borders
  ring     = { 0.8, 0.8, 0.8, 1 },    -- hover border
  rule     = { 0.32, 0.32, 0.32, 1 }, -- dividers
  bar      = { 0, 0, 0, 0.30 },
  gold     = { 1, 0.82, 0, 1 },       -- NORMAL_FONT_COLOR
  text     = { 1, 1, 1, 1 },          -- HIGHLIGHT_FONT_COLOR
  muted    = { 0.6, 0.6, 0.6, 1 },
  dim      = { 0.82, 0.82, 0.82, 1 },
  good     = { 0.1, 1, 0.1, 1 },
  bad      = { 1, 0.13, 0.13, 1 },
  warn     = { 1, 0.5, 0.1, 1 },
  btn1     = { 0.2, 0.2, 0.2, 1 }, btn2 = { 0.08, 0.08, 0.08, 1 },
  primary1 = { 0.55, 0.08, 0.05, 1 }, primary2 = { 0.3, 0.03, 0.02, 1 },
  danger1  = { 0.55, 0.08, 0.05, 1 }, danger2 = { 0.3, 0.03, 0.02, 1 },
  pill1    = { 0.3, 0.24, 0.08, 1 }, pill2 = { 0.16, 0.12, 0.03, 1 },
  fill1    = { 1, 0.9, 0.4, 1 }, fill2 = { 0.85, 0.6, 0, 1 },
  gold1    = { 1, 0.82, 0, 1 }, gold2 = { 0.75, 0.5, 0, 1 },
  violet   = { 0.6, 0.6, 0.6, 1 },
}
C.accent, C.border, C.card, C.bg = C.gold, C.trim, C.well, C.bg2
S.C = C

local function color(t, a) return t[1], t[2], t[3], a or t[4] end
S.Color = color

local function lerp(a, b, p) return a + (b - a) * p end
local function lerpColor(c1, c2, p)
  return lerp(c1[1], c2[1], p), lerp(c1[2], c2[2], p), lerp(c1[3], c2[3], p), lerp(c1[4] or 1, c2[4] or 1, p)
end
S.Lerp, S.LerpColor = lerp, lerpColor

-- gradient: c1 -> c2, top to bottom (or left to right when horizontal)
local function gradient(tex, c1, c2, horizontal, keepTexture)
  if not keepTexture then tex:SetTexture(WHITE) end
  tex:SetVertexColor(1, 1, 1, 1)
  local o = horizontal and "HORIZONTAL" or "VERTICAL"
  local a, b = c1, c2
  if not horizontal then a, b = c2, c1 end
  if tex.SetGradient then
    local function col(c) return { r = c[1], g = c[2], b = c[3], a = c[4] or 1 } end
    if pcall(tex.SetGradient, tex, o, col(a), col(b)) then return end
  end
  if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, o,
    a[1], a[2], a[3], a[4] or 1, b[1], b[2], b[3], b[4] or 1) then return end
  tex:SetVertexColor(color(c1))
end
S.Gradient = gradient

-- the game's selection / hover light (quest log, drop-down menus); alpha = strength
local HILITE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
function S.Highlight(tex, alpha)
  tex:SetTexture(HILITE)
  tex:SetBlendMode("ADD")
  tex:SetVertexColor(1, 1, 1, math.min(1, (alpha or 0.2) * 3.5))
end

-- Tweens (kept for the games' small effects) ---------------------------------------
local ease = {
  linear = function(p) return p end,
  outCubic = function(p) return 1 - (1 - p) ^ 3 end,
  inOutCubic = function(p) return p < 0.5 and 4 * p ^ 3 or 1 - (-2 * p + 2) ^ 3 / 2 end,
  outBack = function(p) local c = 1.70158; return 1 + (c + 1) * (p - 1) ^ 3 + c * (p - 1) ^ 2 end,
}
S.Ease = ease

local tweens = {}
local running = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
  wipe(running)
  for key, t in pairs(tweens) do running[key] = t end
  for key, t in pairs(running) do
    if tweens[key] == t then
      t.t = t.t + elapsed
      if t.t >= 0 then
        local p = math.min(1, t.t / t.dur)
        t.set(lerp(t.from, t.to, t.ease(p)), p)
        if p >= 1 and tweens[key] == t then
          tweens[key] = nil
          if t.done then t.done() end
        end
      end
    end
  end
  if not next(tweens) then self:Hide() end
end)

function S.Tween(key, a)
  a.t, a.dur = -(a.delay or 0), a.dur or 0.25
  a.ease = type(a.ease) == "function" and a.ease or ease[a.ease or "outCubic"]
  tweens[key] = a
  driver:Show()
end
function S.StopTween(key) tweens[key] = nil end
function S.IsTweening(key) return tweens[key] ~= nil end

function S.FadeTo(region, alpha, dur, done)
  S.Tween(region, { dur = dur or 0.15, from = region:GetAlpha(), to = alpha,
    set = function(v) region:SetAlpha(v) end, done = done })
end

-- Fonts --------------------------------------------------------------------
local fonts = {}
local function font(size, lang)
  lang = lang or ns.LANG
  local key = lang .. size
  if not fonts[key] then
    local f = CreateFont("GuildEnhancedForeverFont" .. key)
    f:SetFont(ns.FontPath(lang), size, "")
    if not f:GetFont() then f:SetFont(STANDARD_TEXT_FONT, size, "") end
    f:SetShadowColor(0, 0, 0, 1)
    f:SetShadowOffset(1, -1)
    fonts[key] = f
  end
  return fonts[key]
end
S.Font = font

-- a font with its color (for button states)
local cfonts = {}
local function colorFont(size, col)
  local key = size .. col
  if not cfonts[key] then
    local f = CreateFont("GuildEnhancedForeverCFont" .. ns.LANG .. key)
    f:CopyFontObject(font(size))
    f:SetTextColor(color(C[col]))
    cfonts[key] = f
  end
  return cfonts[key]
end

function S.Text(parent, size, col, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFontObject(font(size or 13))
  fs:SetTextColor(color(C[col or "text"]))
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

function S.FitText(fs, maxWidth, size)
  local r, g, b, a = fs:GetTextColor()
  fs:SetWidth(0)
  for s = size, 9, -1 do
    fs:SetFontObject(font(s))
    if fs:GetStringWidth() <= maxWidth then
      fs:SetTextColor(r, g, b, a)
      return
    end
  end
  fs:SetTextColor(r, g, b, a)
  fs:SetWordWrap(false)
  fs:SetWidth(maxWidth)
end

-- Backdrops ----------------------------------------------------------------
local function backdrop(f, def)
  if not f.SetBackdrop and BackdropTemplateMixin then
    Mixin(f, BackdropTemplateMixin)
    f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged)
  end
  if f.SetBackdrop then f:SetBackdrop(def) end
end
S.Backdrop = backdrop

local function backdropBorder(f, r, g, b, a)
  if f.SetBackdropBorderColor then f:SetBackdropBorderColor(r, g, b, a or 1) end
end

-- tooltip-style panel (thin grey border, dark see-through inside)
local PANEL = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 14,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
-- dialog (static pop-up look)
local DIALOG = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
S.PANEL, S.DIALOG = PANEL, DIALOG

-- dark colors become the default black panel; bright ones (game boards, dice) stay
local function panelColor(c, alpha)
  if not c then return 0, 0, 0, alpha or 0.6 end
  if math.max(c[1], c[2], c[3]) < 0.3 then return 0, 0, 0, math.min(c[4] or 1, alpha or 0.6) end
  return c[1], c[2], c[3], c[4] or 1
end

-- Boxes --------------------------------------------------------------------
local function setLineColor(f, r, g, b, a)
  for _, t in ipairs(f.borders) do t:SetColorTexture(r, g, b, a or 1) end
end

local function frameLines(f, layer, sub, inset)
  local t, b, l, r = f:CreateTexture(nil, layer, nil, sub), f:CreateTexture(nil, layer, nil, sub),
    f:CreateTexture(nil, layer, nil, sub), f:CreateTexture(nil, layer, nil, sub)
  t:SetPoint("TOPLEFT", inset, -inset); t:SetPoint("TOPRIGHT", -inset, -inset); t:SetHeight(1)
  b:SetPoint("BOTTOMLEFT", inset, inset); b:SetPoint("BOTTOMRIGHT", -inset, inset); b:SetHeight(1)
  l:SetPoint("TOPLEFT", inset, -inset); l:SetPoint("BOTTOMLEFT", inset, inset); l:SetWidth(1)
  r:SetPoint("TOPRIGHT", -inset, -inset); r:SetPoint("BOTTOMRIGHT", -inset, inset); r:SetWidth(1)
  return { t, b, l, r }
end

-- flat box: background + 1px border (false: none)
function S.Box(f, bg, border)
  f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  f.bg:SetAllPoints()
  if bg and type(bg[1]) == "table" then bg = bg[1] end
  f.bg:SetColorTexture(panelColor(bg or C.well, 0.55))
  if border ~= false then
    f.borders = frameLines(f, "BORDER", 0, 0)
    f.SetBorderColor = setLineColor
    f:SetBorderColor(color(border or C.trim))
  end
  return f
end

function S.Shadow(f)
  local holder = CreateFrame("Frame", nil, f)
  holder:SetAllPoints()
  f.shadow = holder
  return holder
end

function S.EdgeGlow() end

-- panel with the tooltip border (the name stays from the old rounded boxes)
function S.Rounded(f, r, top, bottom, border)
  backdrop(f, PANEL)
  if top then
    local r1, g1, b1, a1 = panelColor(top, 0.6)
    local r2, g2, b2, a2 = panelColor(bottom or top, 0.6)
    if f.SetBackdropColor then f:SetBackdropColor((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2) end
  elseif f.SetBackdropColor then
    f:SetBackdropColor(0, 0, 0, 0.6)
  end
  f.SetBorderColor = backdropBorder
  f:SetBorderColor(color(border or C.trim))
  return f
end

function S.Card(f, r, alpha)
  S.Rounded(f, r, { 0, 0, 0, alpha or 0.5 }, nil, C.trim)
  return f
end

-- thin divider fading out on both sides
function S.Rule(parent, col, alpha)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(1)
  col = { 0.5, 0.5, 0.5 }
  local c1, c2 = { col[1], col[2], col[3], 0 }, { col[1], col[2], col[3], alpha or 0.6 }
  local l = holder:CreateTexture(nil, "ARTWORK")
  l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMRIGHT", holder, "BOTTOM")
  gradient(l, c1, c2, true)
  local r = holder:CreateTexture(nil, "ARTWORK")
  r:SetPoint("TOPLEFT", holder, "TOP"); r:SetPoint("BOTTOMRIGHT")
  gradient(r, c2, c1, true)
  return holder
end

-- icon with a thin black frame, cropped edges
function S.Icon(parent, size, layer)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(size, size)
  S.Box(holder, { 0, 0, 0, 1 }, { 0, 0, 0, 1 })
  local tex = holder:CreateTexture(nil, layer or "ARTWORK")
  tex:SetPoint("TOPLEFT", 1, -1)
  tex:SetPoint("BOTTOMRIGHT", -1, 1)
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  holder.tex = tex
  return holder
end

function S.HoverFade(frame, region, alpha)
  region:SetAlpha(0)
  frame:HookScript("OnEnter", function() region:SetAlpha(alpha or 1) end)
  frame:HookScript("OnLeave", function() region:SetAlpha(0) end)
end

-- row hover: the game's highlight bar
function S.RowHighlight(row)
  local hl = CreateFrame("Frame", nil, row)
  hl:SetAllPoints()
  local t = hl:CreateTexture(nil, "BACKGROUND", nil, 1)
  t:SetAllPoints()
  S.Highlight(t, 0.2)
  S.HoverFade(row, hl)
  return hl
end

-- Close button ----------------------------------------------------------------------
function S.CloseButton(parent, onClick)
  local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelCloseButton")
  if not ok or not b then
    b = CreateFrame("Button", nil, parent)
    b:SetSize(32, 32)
    b:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
  end
  b:SetScript("OnClick", onClick or function() S.Close(parent) end)
  return b
end

-- Windows: shown and hidden at once, like the game's own ------------------------------
function S.AnimateOpen(f)
  S.StopTween(f)
  f:SetAlpha(1)
end

function S.Close(f)
  S.StopTween(f)
  f:Hide()
  f:SetAlpha(1)
end

function S.AnimateClose(f)
  if not f:IsShown() then return end
  S.Close(f)
end

function S.SlideIn(f)
  S.StopTween(f)
  f:SetAlpha(1)
end

-- collapsible section: clicking the header folds the body, with the game's +/- buttons
function S.Collapsible(header, body, height, isOpen, setOpen)
  if body.SetClipsChildren then pcall(body.SetClipsChildren, body, true) end
  S.Foldable(header, isOpen, setOpen, function(p)
    body:SetHeight(math.max(0.01, height * p))
    body:SetAlpha(p)
    body:SetShown(p > 0.01)
  end)
end

function S.Foldable(header, isOpen, setOpen, apply, anchor)
  header:EnableMouse(true)
  local sign = header:CreateTexture(nil, "OVERLAY")
  sign:SetSize(14, 14)
  if anchor then sign:SetPoint("RIGHT", anchor, "LEFT", -8, 0) else sign:SetPoint("RIGHT", 0, 2) end
  local function step(v)
    sign:SetTexture(v > 0.5 and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    apply(v)
  end
  step(isOpen() and 1 or 0)
  header.foldShown = function() return isOpen() and 1 or 0 end
  header:SetScript("OnMouseUp", function()
    local open = not isOpen()
    setOpen(open)
    step(open and 1 or 0)
  end)
  header:SetScript("OnEnter", function() header.label:SetTextColor(1, 1, 1) end)
  header:SetScript("OnLeave", function() header.label:SetTextColor(color(C.gold)) end)
end

-- the title text of a template frame (the field moved between client versions)
local function tbl(x) return type(x) == "table" and x or nil end
S.Tbl = tbl
local function templateTitle(f)
  return (tbl(f.TitleContainer) and tbl(f.TitleContainer.TitleText)) or tbl(f.TitleText)
end

local function setPortrait(f, texture)
  if f.SetPortraitToAsset and pcall(f.SetPortraitToAsset, f, texture) then return true end
  if f.SetPortraitTextureRaw and pcall(f.SetPortraitTextureRaw, f, texture) then return true end
  local tex = (tbl(f.PortraitContainer) and tbl(f.PortraitContainer.portrait)) or tbl(f.portrait) or tbl(f.Portrait)
  if tex and tex.SetTexture then
    if SetPortraitToTexture and pcall(SetPortraitToTexture, tex, texture) then return true end
    tex:SetTexture(texture)
    return true
  end
end
S.SetPortrait = setPortrait

-- S.Window(name, parent, width, height, title, kind)
--   kind "portrait": the game's portrait frame (main window), with f.portrait set by S.SetPortrait
--   kind "panel": the same frame without portrait
--   otherwise: a dialog (static pop-up look)
-- fields: f.titleBar (drag handle / header row), f.title, f.close
function S.Window(name, parent, width, height, title, kind)
  local f
  if kind == "portrait" or kind == "panel" then
    local ok, frame = pcall(CreateFrame, "Frame", name, parent or UIParent,
      kind == "portrait" and "PortraitFrameTemplate" or "ButtonFrameTemplate")
    if ok and frame then
      f = frame
      if kind == "panel" then
        if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, f) end
        if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, f) end
        if tbl(f.Inset) then f.Inset:Hide() end
      end
      f.templated = true
    end
  end
  if not f then
    f = CreateFrame("Frame", name, parent or UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    backdrop(f, DIALOG)
  end
  f:SetSize(width, height)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)

  local bar = CreateFrame("Frame", nil, f)
  f.titleBar = bar
  if f.templated then
    bar:SetPoint("TOPLEFT", kind == "portrait" and 58 or 4, 0)
    bar:SetPoint("TOPRIGHT", -26, 0)
    bar:SetHeight(22)
    f.title = templateTitle(f)
    f.close = tbl(f.CloseButton)
    if not f.title then
      f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      f.title:SetPoint("TOP", 0, -5)
    end
    if not f.close then
      f.close = S.CloseButton(f)
      f.close:SetPoint("TOPRIGHT", 2, 1)
    end
  else
    bar:SetPoint("TOPLEFT", 12, -12)
    bar:SetPoint("TOPRIGHT", -12, -12)
    bar:SetHeight(34)
    f.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", bar, "TOP", 0, -6)
    f.title:SetPoint("LEFT", bar, "LEFT", 24, 0)
    f.title:SetPoint("RIGHT", bar, "RIGHT", -24, 0)
    f.close = S.CloseButton(f)
    f.close:SetPoint("TOPRIGHT", -5, -5)
    f.close:SetFrameLevel(bar:GetFrameLevel() + 5)
  end
  f.title:SetText(title or "")
  f.close:SetScript("OnClick", function() S.Close(f) end)
  return f
end

-- makes a frame draggable by a handle (onStop: after moving)
function S.Draggable(f, handle, onStop)
  f:SetMovable(true)
  handle = handle or f
  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")
  handle:SetScript("OnDragStart", function() S.StopTween(f); f:SetAlpha(1); f:StartMoving() end)
  handle:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local p, rel, rp, x, y = f:GetPoint(1)
    f.home = { p, rel, rp, x, y }
    if onStop then onStop(f) end
  end)
end

-- Section header: gold label, optional right text, grey divider
function S.Section(parent, text)
  local h = CreateFrame("Frame", nil, parent)
  h:SetHeight(22)
  h.label = S.Text(h, 13, "gold")
  h.label:SetPoint("LEFT", 0, 2)
  h.label:SetText(text or "")
  h.right = S.Text(h, 12, "muted")
  h.right:SetPoint("RIGHT", 0, 2)
  local line = h:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
  gradient(line, { 0.6, 0.6, 0.6, 0.6 }, { 0.6, 0.6, 0.6, 0 }, true)
  return h
end

-- Buttons ------------------------------------------------------------------
-- the game's red panel button; the text shrinks (12 down to 9) to fit
local function isNeutral(r, g, b)
  for _, c in ipairs({ C.trim, C.rule }) do
    if math.abs(r - c[1]) < 0.02 and math.abs(g - c[2]) < 0.02 and math.abs(b - c[3]) < 0.02 then return true end
  end
end

local function buttonFonts(b, size)
  b:SetNormalFontObject(colorFont(size, "gold"))
  b:SetHighlightFontObject(colorFont(size, "text"))
  b:SetDisabledFontObject(colorFont(size, "muted"))
end

local function fitButton(b)
  local fs = b.text
  if not fs then return end
  fs:SetWidth(0)
  for s = 12, 9, -1 do
    buttonFonts(b, s)
    if fs:GetStringWidth() <= b.fitWidth then return end
  end
  fs:SetWidth(b.fitWidth)
  fs:SetWordWrap(false)
end

function S.Button(parent, text, width, height, onClick, style)
  if style == true then style = "primary" end
  local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
  if not ok or not b then
    b = CreateFrame("Button", nil, parent)
    b:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    b:SetDisabledTexture("Interface\\Buttons\\UI-Panel-Button-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
    for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetDisabledTexture(), b:GetHighlightTexture() }) do
      t:SetTexCoord(0, 0.625, 0, 0.6875)
    end
  end
  b:SetSize(width or 120, height or 22)
  b.fitWidth = (width or 120) - 12
  buttonFonts(b, 12)
  local setText = b.SetText
  b:SetText(text or "")
  b.text = tbl(b:GetFontString()) or tbl(b.Text)
  if not b.text then
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetPoint("CENTER")
    b:SetFontString(b.text)
    buttonFonts(b, 12)
    setText(b, text or "")
  end
  b.textColor = "gold"
  fitButton(b)
  b:SetScript("OnClick", onClick)
  b:SetMotionScriptsWhileDisabled(true)
  function b:SetText(t)
    setText(self, t or "")
    fitButton(self)
  end
  -- a colored border means "selected / right / wrong": the button keeps its highlight
  function b:SetBorderColor(r, g, bl)
    if isNeutral(r, g, bl) then self:UnlockHighlight() else self:LockHighlight() end
  end
  if style == "primary" then b.isPrimary = true end
  return b
end

-- tooltip on any frame: lines = string or { title, line, line... } or function returning that
function S.Tooltip(frame, lines, anchor)
  frame:HookScript("OnEnter", function(self)
    local t = type(lines) == "function" and lines(self) or lines
    if not t then return end
    GameTooltip:SetOwner(self, anchor or "ANCHOR_TOP")
    if type(t) == "string" then
      GameTooltip:AddLine(t, 1, 1, 1, true)
    else
      for i, l in ipairs(t) do
        if i == 1 then GameTooltip:AddLine(l, color(C.gold))
        else GameTooltip:AddLine(l, 1, 1, 1, true) end
      end
    end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Checkbox -----------------------------------------------------------------
function S.Check(parent, label, size)
  size = (size or 18) + 6
  local ok, c = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
  if not ok or not c then
    c = CreateFrame("CheckButton", nil, parent)
    c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    c:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  end
  c:SetSize(size, size)
  for _, k in ipairs({ "text", "Text" }) do
    if tbl(c[k]) and c[k].SetText then c[k]:SetText(""); c[k]:Hide() end
  end
  c:SetMotionScriptsWhileDisabled(true)
  if label then
    c.text = S.Text(c, 12, "text")
    c.text:SetPoint("LEFT", c, "RIGHT", 2, 1)
    c.text:SetText(label)
    c:SetHitRectInsets(0, -(c.text:GetStringWidth() + 6), 0, 0)
    hooksecurefunc(c, "SetEnabled", function(self, on) self.text:SetTextColor(color(on and C.text or C.muted)) end)
    function c:FitLabel(maxWidth)
      S.FitText(self.text, maxWidth, 12)
      self:SetHitRectInsets(0, -(math.min(self.text:GetStringWidth(), maxWidth) + 6), 0, 0)
    end
  end
  return c
end

-- Progress bar -------------------------------------------------------------
-- the game's status bar texture in a thin border
function S.ProgressBar(parent, height, c1)
  height = height or 12
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(height)
  backdrop(bar, { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 } })
  if bar.SetBackdropColor then
    bar:SetBackdropColor(0, 0, 0, 0.7)
    bar:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end
  local sb = CreateFrame("StatusBar", nil, bar)
  sb:SetPoint("TOPLEFT", 2, -2)
  sb:SetPoint("BOTTOMRIGHT", -2, 2)
  sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  sb:SetMinMaxValues(0, 1)
  sb:SetValue(0)
  bar.status = sb
  bar.min, bar.max, bar.value = 0, 1, 0
  function bar:SetColors(a) sb:SetStatusBarColor(a[1], a[2], a[3], 1) end
  bar:SetColors(c1 or C.gold1)
  function bar:SetMinMaxValues(lo, hi)
    self.min, self.max = lo, hi
    sb:SetMinMaxValues(lo, hi > lo and hi or lo + 1)
  end
  function bar:SetValue(v)
    self.value = v
    sb:SetValue(v)
  end
  function bar:Replay() end
  return bar
end

-- Scroll frame -------------------------------------------------------------
-- returns the scroll frame and its content (the caller sets the content width); smooth wheel
function S.Scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(1, 1)
  sf:SetScrollChild(content)

  local bar = S.ScrollBar(parent)
  bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 2, -2)
  bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2, 2)
  bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)

  sf:SetScript("OnScrollRangeChanged", function(self)
    local range = self:GetVerticalScrollRange()
    bar:SetMinMaxValues(0, range)
    bar:SetShown(range > 0)
    if bar:GetValue() > range then bar:SetValue(range) end
  end)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, d)
    local _, hi = bar:GetMinMaxValues()
    bar:SetValue(math.max(0, math.min(hi, bar:GetValue() - d * 40)))
  end)
  bar:Hide()
  sf.bar = bar
  return sf, content
end

-- thin bar with the game's scroll knob
function S.ScrollBar(parent)
  local bar = CreateFrame("Slider", nil, parent)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(10)
  bar:SetHitRectInsets(-3, -3, 0, 0)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("TOP")
  track:SetPoint("BOTTOM")
  track:SetWidth(6)
  track:SetColorTexture(0, 0, 0, 0.45)
  local thumb = bar:CreateTexture(nil, "OVERLAY")
  thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  thumb:SetTexCoord(0.2, 0.8, 0.125, 0.875)
  thumb:SetSize(12, 22)
  bar:SetThumbTexture(thumb)
  bar:SetMinMaxValues(0, 0)
  bar:SetValue(0)
  function bar:SetThumbHeight() end
  return bar
end
