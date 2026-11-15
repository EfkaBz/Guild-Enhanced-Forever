-- Guild Enhanced Forever: a form window with several fields (events, group search, announcements,
-- craft requests, tournaments), in the addon's look like the Options window: the game's portrait frame
-- with the guild crest, the fields on a card, every label above its field and shown in full.
-- No dimmed screen; with args.anchor the form sits against the left side of that frame.
--
-- S.Form{ title, sub (line under the title), width, accept, cancel, onAccept(values, showError) -> true
--   keeps the form open, fields = {
--   { key, label, kind = "text" | "multi" | "drop" | "check" | "number" | "section", value,
--     options (drop: list or function), onChange(value, form) (drop, check), max (letters), placeholder,
--     height (multi), hint, size = 1 | 0.5 | 1/3 (part of the row: fields of one row sit side by side) } } }
local _, ns = ...
local S = ns.Skin
local C, color = S.C, S.Color

local PAD, GAP, LABEL_H = 16, 12, 18
local form

local function buildForm()
  local blocker = CreateFrame("Frame", "GuildEnhancedForeverFormBlocker", UIParent)
  blocker:SetAllPoints(UIParent)
  blocker:SetFrameStrata("DIALOG")
  blocker:EnableMouse(false) -- holder only: the rest of the screen stays usable
  blocker:Hide()

  form = S.Window("GuildEnhancedForeverForm", blocker, 480, 300, "", "portrait")
  form:SetFrameStrata("DIALOG")
  form:SetFrameLevel(blocker:GetFrameLevel() + 5)
  form:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  form.blocker = blocker
  form.widgets = {}
  form.close:SetScript("OnClick", function() form.Dismiss() end)
  S.Draggable(form, form.titleBar)
  if not S.SetPortrait(form, ns.ICON) then
    local icon = form:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 8, -6)
    icon:SetTexture(ns.ICON)
  end

  form.sub = S.Text(form, 12, "dim")
  form.sub:SetPoint("TOPLEFT", 66, -32)
  form.sub:SetPoint("RIGHT", -16, 0)

  form.card = CreateFrame("Frame", nil, form)
  form.card:SetPoint("TOPLEFT", 14, -62)
  form.card:SetPoint("BOTTOMRIGHT", -14, 60)
  S.Card(form.card, 8)

  form.accept = S.Button(form, "", 140, 26, function() form.Accept() end, "primary")
  form.accept:SetPoint("BOTTOMRIGHT", form, "BOTTOM", -6, 16)
  form.cancel = S.Button(form, "", 140, 26, function() form.Dismiss() end)
  form.cancel:SetPoint("BOTTOMLEFT", form, "BOTTOM", 6, 16)
  form.error = S.Text(form, 11, "bad")
  form.error:SetPoint("BOTTOM", 0, 44)
  form.error:SetTextColor(color(C.bad))

  function form.Dismiss()
    for _, w in pairs(form.widgets) do if w.ClearFocus then w:ClearFocus() end end
    S.CloseMenu(true)
    blocker:Hide()
  end
  function form.Error(text)
    form.error:SetText(text or "")
    if text then
      form.error:SetAlpha(0)
      S.FadeTo(form.error, 1, 0.2)
    end
  end
  function form.Accept()
    local a = form.args
    local values = form.Values()
    for _, f in ipairs(a.fields) do
      if f.required and (values[f.key] == nil or values[f.key] == "") then
        form.Error(ns.L["Please fill in: %s"]:format(f.label))
        return
      end
    end
    if a.onAccept and a.onAccept(values, form.Error) then return end
    form.Dismiss()
  end
  tinsert(UISpecialFrames, "GuildEnhancedForeverFormBlocker") -- Escape closes it
end

-- one widget per field, created once per (key, kind) and reused; width set at each layout
local function widget(f, width)
  local id = f.key .. ":" .. f.kind .. ":" .. (f.height or 0)
  local w = form.widgets[id]
  if not w then
    if f.kind == "multi" then
      w = S.MultiEdit(form, f.max)
    elseif f.kind == "drop" then
      w = S.Dropdown(form, width, function()
        local o = w and w.options or {}
        return type(o) == "function" and o() or o
      end, function() return w and w.value end,
        function(value) w.value = value; if w.onChange then w.onChange(value, form) end end, width)
    elseif f.kind == "check" then
      w = S.Check(form, "", 18)
      w.text = S.Text(w, 12, "text")
      w.text:SetFontObject(GameFontHighlight)
      w.text:SetPoint("LEFT", w, "RIGHT", 4, 1)
      w.text:SetWordWrap(true)
      w:SetScript("OnClick", function() if w.onChange then w.onChange(w:GetChecked() and true or false, form) end end)
    else
      w = S.EditBox(form, width, 24, "", function() form.Accept() end)
      if f.kind == "number" then w.edit:SetNumeric(true) end
    end
    form.widgets[id] = w
  end
  if f.kind == "multi" then
    w:SetSize(width, f.height or 80)
  elseif f.kind == "drop" then
    w:SetWidth(width)
    w.fitWidth = width - 32
  elseif f.kind == "check" then
    w.text:SetWidth(width - 30)
    w:SetHitRectInsets(0, -(width - 30), 0, 0)
  else
    w:SetWidth(width)
  end
  return w
end

local function label(key)
  form.labels = form.labels or {}
  local t = form.labels[key]
  if not t then
    t = S.Text(form, 12, "text")
    t:SetFontObject(GameFontHighlight)
    t:SetJustifyH("LEFT")
    form.labels[key] = t
  end
  return t
end
local function hintText(key)
  form.hints = form.hints or {}
  local t = form.hints[key]
  if not t then
    t = S.Text(form, 11, "muted")
    t:SetWordWrap(true)
    t:SetJustifyH("LEFT")
    form.hints[key] = t
  end
  return t
end
local function section(key)
  form.sections = form.sections or {}
  local h = form.sections[key]
  if not h then
    h = S.Section(form, "")
    form.sections[key] = h
  end
  return h
end

function S.Form(args)
  if not form then buildForm() end
  local L = ns.L
  S.CloseMenu(true)
  if ns.CloseOptions then ns.CloseOptions() end
  form.args = args
  local width = math.max(args.width or 480, 440)
  form:SetWidth(width)
  form.title:SetText(args.title or "")
  form.sub:SetText(args.sub or "")
  for _, w in pairs(form.widgets) do w:Hide() end
  for _, t in pairs(form.labels or {}) do t:Hide() end
  for _, t in pairs(form.hints or {}) do t:Hide() end
  for _, h in pairs(form.sections or {}) do h:Hide() end

  local inner = width - 28 - 2 * PAD -- usable width in the card
  local left = 14 + PAD
  local active = {}
  local y = 62 + 12 -- from the top of the window
  local rowX, rowH, rowUsed = 0, 0, 0

  local function endRow()
    if rowUsed > 0 then y = y + rowH + GAP end
    rowX, rowH, rowUsed = 0, 0, 0
  end

  for _, f in ipairs(args.fields) do
    if f.kind == "section" then
      endRow()
      local h = section(f.key or f.label)
      h.label:SetText(f.label or "")
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", left, -y)
      h:SetWidth(inner)
      h:Show()
      y = y + 30
    else
      local size = f.size or 1
      if rowUsed + size > 1.001 then endRow() end
      local gap = size < 1 and GAP or 0
      local fw = math.floor(inner * size - (size < 1 and gap * (1 - size) or 0))
      local x = left + rowX
      local w = widget(f, fw)
      active[f.key] = w
      local h = 0
      if f.kind == "check" then
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", x - 4, -y)
        w.text:SetText(f.label or "")
        w:SetChecked(f.value and true or false)
        w.onChange = f.onChange
        h = 26
      else
        local lbl = label(f.key)
        lbl:SetText(f.label or "")
        lbl:SetWidth(fw)
        lbl:ClearAllPoints()
        lbl:SetPoint("TOPLEFT", x, -y)
        lbl:Show()
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", x - (f.kind == "drop" and 2 or 0), -(y + LABEL_H))
        if f.kind == "multi" then
          w:SetText(f.value or "")
          w:SetLocked(false)
        elseif f.kind == "drop" then
          w.options = f.options
          w.value = f.value
          w.onChange = f.onChange
          if w.SetEnabled then w:SetEnabled(true) end -- (a check box of the form may grey it again)
          w:Refresh()
        else
          w:SetText(f.value and tostring(f.value) or "")
          w.placeholder:SetText(f.placeholder or "")
          w:SetMaxLetters(f.max or 0)
        end
        h = LABEL_H + (f.kind == "multi" and (f.height or 80) or 24)
      end
      w:Show()
      if f.hint then
        local t = hintText(f.key)
        t:SetWidth(fw)
        t:SetText(f.hint)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, -(y + h + 4))
        t:Show()
        h = h + 4 + math.ceil(t:GetStringHeight())
      end
      rowX = rowX + fw + gap
      rowH = math.max(rowH, h)
      rowUsed = rowUsed + size
      if rowUsed >= 0.999 then endRow() end
    end
  end
  endRow()

  form.active = active
  -- check boxes that change other fields apply their starting value
  for _, f in ipairs(args.fields) do
    if f.kind == "check" and f.onChange then f.onChange(f.value and true or false, form) end
  end
  form.Values = function()
    local v = {}
    for _, f in ipairs(form.args.fields) do
      local w = active[f.key]
      if w then
        if f.kind == "check" then v[f.key] = w:GetChecked() and true or false
        elseif f.kind == "drop" then v[f.key] = w.value
        elseif f.kind == "number" then v[f.key] = tonumber(w:GetText())
        else v[f.key] = ns.Net.Clean(strtrim(w:GetText() or "")) end
      end
    end
    return v
  end
  form.Error(nil)
  form:SetHeight(y - GAP + 12 + 60)
  form.accept:SetText(args.accept or L["OK"])
  form.cancel:SetText(args.cancel or L["Cancel"])
  form:ClearAllPoints()
  if args.anchor then
    form:SetPoint("TOPRIGHT", args.anchor, "TOPLEFT", -4, 0)
  elseif ns.frame and ns.frame:IsShown() then
    form:SetPoint("TOPRIGHT", ns.frame, "TOPLEFT", -4, 0)
  else
    form:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  end
  form.blocker:SetAlpha(1)
  form.blocker:Show()
  form:Show()
  S.AnimateOpen(form, 0, -10)
  for _, f in ipairs(args.fields) do
    if f.kind == "text" or f.kind == "number" then active[f.key]:SetFocus() break end
  end
  return form
end

-- closes the form; with anchor, only when the form is docked to that frame
function S.FormDismiss(anchor)
  if not form or not form.blocker:IsShown() then return end
  if anchor and form.args.anchor ~= anchor then return end
  form.Dismiss()
end
