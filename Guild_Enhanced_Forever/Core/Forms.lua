-- Guild Enhanced Forever: a modal form with several fields (events, group search, announcements,
-- craft requests, tournaments, options), in the game's dialog style: labels on the left, fields on
-- the right. No dimmed screen; with args.anchor the form sits against the left side of that frame.
--
-- S.Form{ title, width, accept, onAccept(values) -> true keeps the form open, fields = {
--   { key, label, kind = "text" | "multi" | "drop" | "check" | "number", value, options (drop),
--     max (letters), placeholder, height (multi), min, maxValue (number), hint } } }
local _, ns = ...
local S = ns.Skin
local C, color = S.C, S.Color

local LABEL_W, ROW_GAP = 120, 10
local form

local function buildForm()
  local blocker = CreateFrame("Frame", "GuildEnhancedForeverFormBlocker", UIParent)
  blocker:SetAllPoints(UIParent)
  blocker:SetFrameStrata("DIALOG")
  blocker:EnableMouse(false) -- holder only: the rest of the screen stays usable
  blocker:Hide()

  form = S.Window("GuildEnhancedForeverForm", blocker, 440, 200, "")
  form:SetFrameStrata("DIALOG")
  form:SetFrameLevel(blocker:GetFrameLevel() + 5)
  form:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  form.titleBar:SetHeight(38)
  form.blocker = blocker
  form.widgets = {}
  form.close:SetScript("OnClick", function() form.Dismiss() end)
  S.Draggable(form, form.titleBar)

  form.accept = S.Button(form, "", 140, 26, function() form.Accept() end, "primary")
  form.accept:SetPoint("BOTTOMRIGHT", form, "BOTTOM", -6, 16)
  form.cancel = S.Button(form, "", 140, 26, function() form.Dismiss() end)
  form.cancel:SetPoint("BOTTOMLEFT", form, "BOTTOM", 6, 16)
  form.error = S.Text(form, 11, "bad")
  form.error:SetPoint("BOTTOM", 0, 50)
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

-- one widget per field, created once per (key, kind) and reused
local function widget(f, width)
  local id = f.key .. ":" .. f.kind .. ":" .. (f.height or 0)
  local w = form.widgets[id]
  if not w then
    if f.kind == "multi" then
      w = S.MultiEdit(form, f.max)
      w:SetSize(width, f.height or 80)
    elseif f.kind == "drop" then
      w = S.Dropdown(form, width, function() return w and w.options or {} end, function() return w and w.value end,
        function(value) w.value = value; if w.onChange then w.onChange(value) end end, width)
    elseif f.kind == "check" then
      w = S.Check(form, "", 18)
    else
      w = S.EditBox(form, width, 24, "", function() form.Accept() end)
      if f.kind == "number" then w.edit:SetNumeric(true) end
    end
    form.widgets[id] = w
  end
  return w
end

function S.Form(args)
  if not form then buildForm() end
  local L = ns.L
  S.CloseMenu(true)
  form.args = args
  local width = args.width or 440
  form:SetWidth(width)
  form.title:SetText(args.title or "")
  for _, w in pairs(form.widgets) do w:Hide(); if w.label then w.label:Hide() end; if w.hint then w.hint:Hide() end end
  local active = {}
  local y = 54
  local fieldW = width - 36 - LABEL_W
  for _, f in ipairs(args.fields) do
    local w = widget(f, fieldW)
    active[f.key] = w
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", 18 + LABEL_W, -y)
    if not w.label then
      w.label = S.Text(form, 12, "dim")
      w.label:SetWidth(LABEL_W - 10)
      w.label:SetJustifyH("LEFT")
      w.hint = S.Text(form, 10, "muted")
      w.hint:SetWidth(fieldW)
      w.hint:SetWordWrap(true)
    end
    w.label:SetText(f.label or "")
    w.label:ClearAllPoints()
    w.label:SetPoint("TOPLEFT", 18, -(y + 5))
    w.label:Show()
    if f.kind == "multi" then
      w:SetText(f.value or "")
      w:SetLocked(false)
    elseif f.kind == "drop" then
      w.options = f.options
      w.value = f.value
      w.onChange = f.onChange
      w:Refresh()
    elseif f.kind == "check" then
      w:SetChecked(f.value and true or false)
    else
      w:SetText(f.value and tostring(f.value) or "")
      w.placeholder:SetText(f.placeholder or "")
      w:SetMaxLetters(f.max or 0)
    end
    w:Show()
    local h = f.kind == "multi" and (f.height or 80) or f.kind == "check" and 18 or 24
    if f.hint then
      w.hint:SetText(f.hint)
      w.hint:ClearAllPoints()
      w.hint:SetPoint("TOPLEFT", w, "BOTTOMLEFT", 0, -4)
      w.hint:Show()
      h = h + 4 + w.hint:GetStringHeight()
    end
    y = y + h + ROW_GAP
  end
  form.active = active
  form.Values = function()
    local v = {}
    for _, f in ipairs(form.args.fields) do
      local w = active[f.key]
      if f.kind == "check" then v[f.key] = w:GetChecked() and true or false
      elseif f.kind == "drop" then v[f.key] = w.value
      elseif f.kind == "number" then v[f.key] = tonumber(w:GetText())
      else v[f.key] = ns.Net.Clean(strtrim(w:GetText() or "")) end
    end
    return v
  end
  form.Error(nil)
  form:SetHeight(y + 70)
  form.accept:SetText(args.accept or L["OK"])
  form.cancel:SetText(args.cancel or L["Cancel"])
  form:ClearAllPoints()
  if args.anchor then
    form:SetPoint("TOPRIGHT", args.anchor, "TOPLEFT", -2, 0)
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
