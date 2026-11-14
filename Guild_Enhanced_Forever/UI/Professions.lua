-- Guild Enhanced Forever: professions page.
--   Directory: the professions of every guildmate who has the addon (level, and the recipes they
--   know, read when they open their profession window), searchable by recipe or name.
--   Craft requests: "who can make me 2 Major Healing Potions?", taken by a crafter, then done.
-- Each player only shares his own professions (ns.Sync collection "prof", one record per player);
-- requests are the collection "craft".
local _, ns = ...
local S, L = ns.Skin, ns.L
local C, color, gradient = S.C, S.Color, S.Gradient
local Sync = ns.Sync
local now = GetServerTime or time

local PAGE = 5
local PROF_W, MEM_W, PROF_H, ROW_H, RECIPE_H, REQ_H = 200, 290, 36, 40, 26, 46
local page, ui = nil, { rows = {}, recipes = {}, reqs = {}, profRows = {} }
local mode, search, profSel, selected = "dir", "", nil, nil
local profPicked -- the player clicked a profession (else: the first one someone has)
local me = UnitName("player")

-- the professions: key -> spell (its name is the profession, in the client's language)
local PROFS = {
  { "alch", 2259, "Trade_Alchemy" }, { "bs", 2018, "Trade_BlackSmithing" }, { "ench", 7411, "Trade_Engraving" },
  { "eng", 4036, "Trade_Engineering" }, { "herb", 2366, "Spell_Nature_NatureTouchGrow" },
  { "lw", 2108, "Trade_LeatherWorking" }, { "mine", 2575, "Trade_Mining" }, { "skin", 8613, "INV_Misc_Pelt_Wolf_01" },
  { "tail", 3908, "Trade_Tailoring" }, { "cook", 2550, "INV_Misc_Food_15" }, { "aid", 3273, "Spell_Holy_SealOfSacrifice" },
  { "fish", 7620, "Trade_Fishing" },
}
local PROF, byLocalName = {}, {}
for _, p in ipairs(PROFS) do
  local name = ns.SpellInfo(p[2])
  p.name = name or p[1]
  p.icon = "Interface\\Icons\\" .. p[3]
  PROF[p[1]] = p
  if name then byLocalName[name] = p[1] end
end
-- the spell names may not be known yet when the addon loads: asked again before each read
local function ensureNames()
  for _, p in ipairs(PROFS) do
    if p.name == p[1] then
      local name = ns.SpellInfo(p[2])
      if name then p.name = name; byLocalName[name] = p[1] end
    end
  end
end
local function profName(key) return PROF[key] and PROF[key].name or key end
local function profIcon(key) return PROF[key] and PROF[key].icon or "Interface\\Icons\\INV_Misc_QuestionMark" end

-- items: name, link, icon, quality (asks the server when the client does not know it yet)
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local ItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local missing = false
-- a recipe code: "123" (item made) or "e123" (enchantment spell)
local function recipeInfo(code)
  local ench = code:match("^e(%d+)$")
  if ench then
    local id = tonumber(ench)
    local name, icon = ns.SpellInfo(id)
    return name or ("#" .. id), "|cffffd000|Henchant:" .. id .. "|h[" .. (name or id) .. "]|h|r", icon or profIcon("ench"), 1
  end
  local id = tonumber(code)
  if not id then return "?", nil, nil, 1 end
  local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(id)
  if not name then missing = true end
  return name or ("#" .. id), link, icon or (ItemIcon and ItemIcon(id)), quality or 1
end

-- My professions -----------------------------------------------------------------------------------
local myProfs = {} -- key -> { r, m, rc = { codes } }

-- skill line ids of the professions (the modern profession API gives them)
local SKILL = { [171] = "alch", [164] = "bs", [333] = "ench", [202] = "eng", [182] = "herb", [165] = "lw",
  [186] = "mine", [393] = "skin", [197] = "tail", [185] = "cook", [129] = "aid", [356] = "fish" }

local function readSkills()
  ensureNames()
  local found, read = {}, false
  local function add(name, rank, maxRank, skillLine)
    local key = (name and byLocalName[name]) or SKILL[skillLine or 0]
    if key then
      found[key] = true
      myProfs[key] = myProfs[key] or { rc = {} }
      myProfs[key].r, myProfs[key].m = rank or 0, maxRank or 0
    end
  end
  local SI = C_SkillInfo
  if SI and SI.GetNumSkillLines and SI.GetSkillLineInfo then
    -- WoW Forever: the skill lines are in C_SkillInfo (one table per line)
    for i = 1, SI.GetNumSkillLines() or 0 do
      local ok, s = pcall(SI.GetSkillLineInfo, i)
      if ok and type(s) == "table" then
        read = true
        if not s.isHeader then
          add(s.name, s.rank, s.maxRank or s.max or s.skillMaxRank, s.skillLineID or s.skillLine or s.id)
        end
      end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() or 0 do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      read = true
      if not isHeader then add(name, rank, maxRank) end
    end
  elseif GetProfessions and GetProfessionInfo then
    for _, idx in pairs({ GetProfessions() }) do
      if idx then
        local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
        read = true
        add(name, rank, maxRank, skillLine)
      end
    end
  end
  -- forgotten professions go away (only when the skills were read: the list is never empty)
  if read then
    for key in pairs(myProfs) do if not found[key] then myProfs[key] = nil end end
  end
end

-- WoW Forever: the profession window works with C_TradeSkillUI (the modern API)
local function readModernTradeSkill()
  ensureNames()
  local T = C_TradeSkillUI
  local ok, info = pcall(T.GetBaseProfessionInfo)
  if not ok or type(info) ~= "table" then return end
  -- someone else's recipes (a link) or an NPC: not mine
  if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
    or (T.IsNPCCrafting and T.IsNPCCrafting()) then return end
  local key = SKILL[info.professionID or 0] or SKILL[info.parentProfessionID or 0]
    or byLocalName[info.parentProfessionName or ""] or byLocalName[info.professionName or ""]
  if not key then return end
  local ids = T.GetAllRecipeIDs and T.GetAllRecipeIDs() or {}
  local codes, seen = {}, {}
  for _, id in ipairs(ids) do
    local rok, r = pcall(T.GetRecipeInfo, id)
    if rok and type(r) == "table" and r.learned then
      local link = T.GetRecipeItemLink and T.GetRecipeItemLink(id)
      local item = link and link:match("item:(%d+)")
      if not item and T.GetRecipeSchematic then
        local sok, sch = pcall(T.GetRecipeSchematic, id, false)
        if sok and type(sch) == "table" and sch.outputItemID then item = tostring(sch.outputItemID) end
      end
      local code
      if link and (link:find("enchant:") or r.isEnchantingRecipe) then code = "e" .. id
      elseif item then code = item end
      if code and not seen[code] then seen[code] = true; codes[#codes + 1] = code end
    end
  end
  if #codes == 0 then return end
  myProfs[key] = myProfs[key] or {}
  local p = myProfs[key]
  p.r = info.skillLevel or p.r or 0
  p.m = info.maxSkillLevel or p.m or 0
  p.rc = codes
end

local function readTradeSkill()
  if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then return readModernTradeSkill() end
  if not GetTradeSkillLine then return end
  local name, rank, maxRank = GetTradeSkillLine()
  local key = name and byLocalName[name]
  if not key then return end
  local codes, n = {}, GetNumTradeSkills() or 0
  for i = 1, n do
    local _, kind = GetTradeSkillInfo(i)
    if kind and kind ~= "header" then
      local link = GetTradeSkillItemLink(i)
      local id = link and link:match("item:(%d+)")
      if id then codes[#codes + 1] = id end
    end
  end
  if #codes == 0 then return end
  myProfs[key] = myProfs[key] or {}
  myProfs[key].r, myProfs[key].m, myProfs[key].rc = rank, maxRank, codes
end

local function readCraft()
  if not GetCraftDisplaySkillLine then return end
  local name, rank, maxRank = GetCraftDisplaySkillLine()
  local key = name and byLocalName[name]
  if not key then return end -- (the hunter's beast training uses the same window)
  local codes = {}
  for i = 1, GetNumCrafts() or 0 do
    local _, _, kind = GetCraftInfo(i)
    if kind and kind ~= "header" then
      local link = GetCraftItemLink and GetCraftItemLink(i)
      local id = link and (link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
      local item = link and link:match("item:(%d+)")
      if id then codes[#codes + 1] = "e" .. id elseif item then codes[#codes + 1] = item end
    end
  end
  if #codes == 0 then return end
  myProfs[key] = myProfs[key] or {}
  myProfs[key].r, myProfs[key].m, myProfs[key].rc = rank, maxRank, codes
end

-- /gui prof: what the addon reads (to understand an empty directory)
function ns.ProfDebug()
  local out = {}
  local function say(s) out[#out + 1] = s end
  say("sync " .. tostring(Sync.Started()) .. ", me " .. tostring(me) .. " -> " .. tostring(ns.byName[me] and ns.byName[me].name))
  say("C_SkillInfo " .. tostring(C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetNumSkillLines())
    .. ", GetNumSkillLines " .. tostring(GetNumSkillLines and GetNumSkillLines())
    .. ", C_TradeSkillUI " .. tostring(C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and true))
  readSkills()
  readTradeSkill()
  for key, p in pairs(myProfs) do say(profName(key) .. " " .. tostring(p.r) .. "/" .. tostring(p.m) .. ", " .. #(p.rc or {}) .. " recipes") end
  if not next(myProfs) and C_SkillInfo and C_SkillInfo.GetSkillLineInfo then
    for i = 1, math.min(C_SkillInfo.GetNumSkillLines() or 0, 12) do
      local s = C_SkillInfo.GetSkillLineInfo(i)
      if type(s) == "table" then say("  line " .. i .. ": " .. tostring(s.name) .. " " .. tostring(s.skillLineID)) end
    end
  end
  say("shared records: " .. #Sync.All("prof"))
  for _, s in ipairs(out) do ns.Print(s) end
  if ns.ProfPush then ns.ProfPush() end
end

local function encode()
  local list = {}
  for key, p in pairs(myProfs) do
    list[#list + 1] = { k = key, r = p.r or 0, m = p.m or 0, rc = table.concat(p.rc or {}, ",") }
  end
  table.sort(list, function(a, b) return a.k < b.k end)
  return list
end

local pushPending
-- shares my professions when they changed (a few seconds after the last change)
local function push()
  if pushPending then return end
  pushPending = true
  C_Timer.After(5, function()
    pushPending = nil
    if not Sync.Started() then return end
    local list = encode()
    local old = Sync.Get("prof", me)
    if old and ns.Net.Encode(old.p or {}) == ns.Net.Encode(list) then return end
    Sync.Put("prof", { id = me, p = list })
  end)
end
ns.ProfPush = push

Sync.Register("prof", {
  keep = 30 * 86400,
  validate = function(rec) return rec.id == rec.ed and rec.by == rec.id end,
  ready = function()
    -- what was shared last time is the start (recipes are read again when the windows open)
    local old = Sync.Get("prof", me)
    for _, p in ipairs(old and old.p or {}) do
      local cur = myProfs[p.k]
      if not (cur and cur.rc and #cur.rc > 0) then -- (a window read before the start wins)
        local codes = {}
        for c in (p.rc or ""):gmatch("[^,]+") do codes[#codes + 1] = c end
        myProfs[p.k] = { r = cur and cur.r or p.r, m = cur and cur.m or p.m, rc = codes }
      end
    end
    readSkills()
    push()
  end,
})

local pev = CreateFrame("Frame")
for _, e in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE",
  "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED" }) do
  pcall(pev.RegisterEvent, pev, e)
end
-- the recipe list fires many updates in a row: read once, a moment after the last one
local readPending
pev:SetScript("OnEvent", function(_, event)
  if event == "SKILL_LINES_CHANGED" then readSkills()
  elseif event:find("^CRAFT") then readCraft()
  else
    if readPending then return end
    readPending = true
    C_Timer.After(0.5, function()
      readPending = nil
      readTradeSkill()
      push()
    end)
    return
  end
  push()
end)

-- Directory -----------------------------------------------------------------------------------------
-- every (player, profession), with its recipes
local function entries()
  local list = {}
  for _, rec in ipairs(Sync.All("prof")) do
    if ns.byName[rec.id] then
      for _, p in ipairs(rec.p or {}) do
        local codes = {}
        for c in (p.rc or ""):gmatch("[^,]+") do codes[#codes + 1] = c end
        list[#list + 1] = { who = rec.id, disp = ns.byName[rec.id].short or rec.id, key = p.k, r = p.r or 0, m = p.m or 0, codes = codes, id = rec.id .. ":" .. p.k }
      end
    end
  end
  return list
end

local function matches(e, text)
  if text == "" then return true, nil end
  if (e.disp or e.who):lower():find(text, 1, true) or profName(e.key):lower():find(text, 1, true) then return true, nil end
  local hits = 0
  for _, code in ipairs(e.codes) do
    local name = recipeInfo(code)
    if name:lower():find(text, 1, true) then hits = hits + 1 end
  end
  return hits > 0, hits
end

-- a profession in the left column: icon, name, how many guildmates have it
local function profRow(i)
  if ui.profRows[i] then return ui.profRows[i] end
  local r = CreateFrame("Button", nil, ui.profList)
  r:SetHeight(PROF_H - 2)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * PROF_H)
  r:SetPoint("TOPRIGHT", 0, -(i - 1) * PROF_H)
  S.RowHighlight(r)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints()
  S.Highlight(r.sel, 0.25)
  r.icon = S.Icon(r, 24)
  r.icon:SetPoint("LEFT", 6, 0)
  r.name = S.Text(r, 12, "text")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.name:SetPoint("RIGHT", -34, 0)
  r.name:SetJustifyH("LEFT")
  r.count = S.Text(r, 12, "gold")
  r.count:SetPoint("RIGHT", -10, 0)
  r.count:SetJustifyH("RIGHT")
  r:SetScript("OnClick", function(self)
    profSel, profPicked = self.key, true
    selected = nil
    ns.RefreshProfessions(true)
  end)
  ui.profRows[i] = r
  return r
end

local function entryRow(i)
  if ui.rows[i] then return ui.rows[i] end
  local r = CreateFrame("Button", nil, ui.listContent)
  r:SetHeight(ROW_H - 4)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  S.RowHighlight(r)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints()
  S.Highlight(r.sel, 0.2)
  r.icon = S.Icon(r, 28)
  r.icon:SetPoint("LEFT", 6, 0)
  r.name = S.Text(r, 12, "text")
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 0)
  r.name:SetPoint("RIGHT", -100, 0)
  r.name:SetJustifyH("LEFT")
  r.prof = S.Text(r, 10, "muted")
  r.prof:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 0)
  r.bar = S.ProgressBar(r, 6)
  r.bar:SetPoint("RIGHT", -10, -6)
  r.bar:SetWidth(80)
  r.lvl = S.Text(r, 11, "dim")
  r.lvl:SetPoint("BOTTOMRIGHT", r.bar, "TOPRIGHT", 0, 3)
  r.lvl:SetJustifyH("RIGHT")
  r:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      local m = ns.byName[self.entry.who]
      if m then ns.MemberMenu(self, m) end
      return
    end
    selected = self.entry.id
    ns.RefreshProfessions()
    S.SlideIn(ui.recipeBox, 10, 0, 0.2)
  end)
  ui.rows[i] = r
  return r
end

local function recipeRow(i)
  if ui.recipes[i] then return ui.recipes[i] end
  local r = CreateFrame("Button", nil, ui.recipeContent)
  r:SetHeight(RECIPE_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * RECIPE_H)
  r:SetPoint("TOPRIGHT", 0, -(i - 1) * RECIPE_H)
  local stripe = r:CreateTexture(nil, "BACKGROUND", nil, -2)
  stripe:SetAllPoints()
  stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
  S.RowHighlight(r)
  r.icon = S.Icon(r, 20)
  r.icon:SetPoint("LEFT", 6, 0)
  r.name = S.Text(r, 12, "text")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.name:SetPoint("RIGHT", -110, 0)
  r.ask = S.Button(r, L["Request"], 90, 20)
  r.ask:SetPoint("RIGHT", -6, 0)
  r:HookScript("OnEnter", function(self)
    if self.link then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self.link)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Shift-click: link in chat"], 0.64, 0.6, 0.72)
      GameTooltip:Show()
    end
  end)
  r:HookScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self)
    if self.link and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
  end)
  ui.recipes[i] = r
  return r
end

-- Craft requests ---------------------------------------------------------------------------------------
local ST = { open = { "Open", C.gold }, taken = { "In progress", C.warn }, done = { "Done", C.good } }

local function nameLabel(name)
  local m = name and ns.byName[name]
  return m and ("|c" .. ns.ClassHex(m.classFile) .. name .. "|r") or ("|cffdddddd" .. (name or "?") .. "|r")
end

local function crafterOptions(code, key)
  local list = { { "", L["Anyone"] } }
  for _, e in ipairs(entries()) do
    if e.who ~= me and (not key or e.key == key) then
      local ok = not code
      if code then for _, c in ipairs(e.codes) do if c == code then ok = true break end end end
      if ok then list[#list + 1] = { e.who, e.who .. "  (" .. profName(e.key) .. " " .. e.r .. ")" } end
    end
  end
  return list
end

-- code: the recipe (optional); to: a crafter (optional)
function ns.CraftRequest(code, to, key)
  local name = code and recipeInfo(code) or ""
  S.Form({
    title = L["Craft request"], width = 460, accept = L["Send"],
    fields = {
      { key = "what", label = L["Item"], kind = "text", value = name, max = 60, required = true },
      { key = "qty", label = L["Quantity"], kind = "number", value = 1 },
      { key = "to", label = L["Crafter"], kind = "drop", value = to or "", options = crafterOptions(code, key) },
      { key = "note", label = L["Note"], kind = "text", max = 100,
        placeholder = L["I bring the materials, tip offered..."] },
    },
    onAccept = function(v)
      Sync.Put("craft", { id = me .. "-" .. now(), what = v.what, code = code, qty = math.max(1, math.min(99, v.qty or 1)),
        to = v.to or "", st = "open", note = v.note })
      mode = "req"
      ns.RefreshProfessions(true)
    end,
  })
end

local function setState(rec, st)
  local copy = CopyTable(rec)
  copy.st = st
  if st == "taken" then copy.crafter = me end
  Sync.Put("craft", copy)
end

Sync.Register("craft", {
  keep = 7 * 86400,
  expired = function(r, t)
    local age = t - (r.v or 0)
    return (r.st == "done" and age > 7 * 86400) or age > 30 * 86400
  end,
  validate = function(rec) return ns.byName[rec.ed or ""] ~= nil end,
  changed = function(rec, old)
    if rec.del or not Sync.Started() or rec.ed == me or not ns.NotifyOpt("crafts") then return end
    local icon = rec.code and select(3, recipeInfo(rec.code)) or "Interface\\Icons\\Trade_BlackSmithing"
    local function go() mode = "req"; ns.OpenPage(PAGE) end
    if not old and rec.to == me then
      ns.Notify({ icon = icon, title = L["Craft request"], text = string.format(L["%s asks you: %d x %s"],
        nameLabel(rec.by), rec.qty or 1, rec.what or ""), buttons = { { L["View"], go, true } } })
    elseif old and rec.by == me and old.st ~= rec.st and (rec.st == "taken" or rec.st == "done") then
      ns.Notify({ icon = icon, title = L["Craft request"], text = string.format(
        rec.st == "taken" and L["%s is making your %s."] or L["%s made your %s."], nameLabel(rec.crafter), rec.what or ""),
        buttons = { { L["Whisper"], function() ChatFrame_SendTell(rec.crafter) end, true } } })
    end
  end,
})

local function reqRow(i)
  if ui.reqs[i] then return ui.reqs[i] end
  local r = CreateFrame("Frame", nil, ui.reqContent)
  r:SetHeight(REQ_H - 4)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * REQ_H)
  r:SetPoint("TOPRIGHT", 0, -(i - 1) * REQ_H)
  S.Rounded(r, 8, { 0.1, 0.07, 0.17, 0.9 }, { 0.05, 0.035, 0.09, 0.9 }, C.rule)
  r.icon = S.Icon(r, 30)
  r.icon:SetPoint("LEFT", 8, 0)
  r.what = S.Text(r, 13, "text")
  r.what:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 0)
  r.what:SetPoint("RIGHT", -360, 0)
  r.sub = S.Text(r, 10, "muted")
  r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 0)
  r.sub:SetPoint("RIGHT", -360, 0)
  r.state = CreateFrame("Frame", nil, r)
  r.state:SetSize(100, 20)
  r.state:SetPoint("RIGHT", -240, 0)
  S.Rounded(r.state, 6, C.btn1, C.btn2, C.trim)
  r.state.text = S.Text(r.state, 11, "text")
  r.state.text:SetPoint("CENTER")
  r.crafter = S.Text(r, 11, "dim")
  r.crafter:SetPoint("LEFT", r.state, "RIGHT", 10, 0)
  r.crafter:SetWidth(110)
  r.b1 = S.Button(r, "", 104, 22)
  r.b1:SetPoint("RIGHT", -8, 0)
  ui.reqs[i] = r
  return r
end

local function refreshRequests(animate)
  local list = Sync.All("craft")
  table.sort(list, function(a, b)
    local order = { open = 1, taken = 2, done = 3 }
    if a.st ~= b.st then return (order[a.st] or 9) < (order[b.st] or 9) end
    return (a.v or 0) > (b.v or 0)
  end)
  local open = 0
  for i, rec in ipairs(list) do
    if rec.st ~= "done" then open = open + 1 end
    local r = reqRow(i)
    local _, _, icon = recipeInfo(rec.code or "0")
    r.icon.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_Bag_10")
    r.what:SetText((rec.qty or 1) .. " x  " .. (rec.what or ""))
    r.sub:SetText(string.format(L["by %s"], nameLabel(rec.by)) .. ((rec.note and rec.note ~= "") and ("  ·  " .. rec.note) or ""))
    local st = ST[rec.st] or ST.open
    r.state.text:SetText(L[st[1]])
    r.state.text:SetTextColor(color(st[2]))
    r.state:SetBorderColor(color(st[2], 0.6))
    r.crafter:SetText(rec.crafter and nameLabel(rec.crafter) or (rec.to ~= "" and rec.to and ("→ " .. nameLabel(rec.to)) or ""))
    local action
    if rec.by == me then
      action = rec.st == "done" and { L["Remove"], function() Sync.Delete("craft", rec.id) end }
        or { L["Cancel"], function() Sync.Delete("craft", rec.id) end }
    elseif rec.st == "open" and (rec.to == "" or rec.to == nil or rec.to == me) then
      action = { L["I'll make it"], function() setState(rec, "taken") end, true }
    elseif rec.st == "taken" and rec.crafter == me then
      action = { L["Done"], function() setState(rec, "done") end, true }
    elseif rec.st ~= "done" then
      action = { L["Whisper"], function() ChatFrame_SendTell(rec.by) end }
    end
    r.b1:SetShown(action ~= nil)
    if action then
      r.b1:SetText(action[1])
      r.b1:SetScript("OnClick", function() action[2](); ns.RefreshProfessions() end)
    end
    r:Show()
    if animate and i <= 10 then S.SlideIn(r, 0, -8, 0.25, i * 0.03) end
  end
  for i = #list + 1, #ui.reqs do ui.reqs[i]:Hide() end
  ui.reqContent:SetHeight(math.max(1, #list * REQ_H))
  ui.reqEmpty:SetShown(#list == 0)
  return open
end

-- Refresh -------------------------------------------------------------------------------------------------
function ns.RefreshProfessions(animate)
  if not page then return end
  missing = false
  for _, p in ipairs(ui.pills) do p:SetActive(p.key == mode) end
  ui.dir:SetShown(mode == "dir")
  ui.req:SetShown(mode == "req")
  local open = refreshRequests(animate and mode == "req")
  ui.pills[2].text:SetText(L["Craft requests"] .. (open > 0 and ("  |cffffd100" .. open .. "|r") or ""))
  ui.pills[2]:SetWidth(ui.pills[2].text:GetStringWidth() + 20)
  ns.SetTabBadge(PAGE, "")
  if mode ~= "dir" then return end

  local text = search:lower()
  local all = entries()
  -- professions column: how many guildmates have each one (matching the search)
  local counts, byProf = {}, {}
  for _, e in ipairs(all) do
    local ok, hits = matches(e, text)
    if ok then
      e.hits = hits
      counts[e.key] = (counts[e.key] or 0) + 1
      byProf[e.key] = byProf[e.key] or {}
      table.insert(byProf[e.key], e)
    end
  end
  local profs = {}
  for _, pr in ipairs(PROFS) do profs[#profs + 1] = pr end
  table.sort(profs, function(a, b) return a.name < b.name end)
  -- default: the first profession someone has
  if not profSel or (not counts[profSel] and (text ~= "" or not profPicked)) then
    profSel = nil
    for _, pr in ipairs(profs) do if counts[pr[1]] then profSel = pr[1] break end end
    profSel = profSel or profs[1][1]
  end
  for i, pr in ipairs(profs) do
    local r = profRow(i)
    r.key = pr[1]
    r.icon.tex:SetTexture(pr.icon)
    r.name:SetText(pr.name)
    local n = counts[pr[1]] or 0
    r.count:SetText(n > 0 and n or "")
    r.name:SetAlpha(n > 0 and 1 or 0.5)
    r.icon:SetAlpha(n > 0 and 1 or 0.5)
    r.sel:SetShown(pr[1] == profSel)
    r:Show()
  end
  ui.profTitle.right:SetText(#all > 0 and #all or "")

  -- members column: the guildmates with the selected profession, best level first
  local list = byProf[profSel] or {}
  table.sort(list, function(a, b)
    if a.r ~= b.r then return a.r > b.r end
    return (a.disp or a.who) < (b.disp or b.who)
  end)
  ui.memTitle.label:SetText(profName(profSel))
  ui.memTitle.right:SetText(#list > 0 and #list or "")
  local found
  for i, e in ipairs(list) do
    local r = entryRow(i)
    r.entry = e
    if e.id == selected then found = e end
    local m = ns.byName[e.who]
    ns.SetClassIcon(r.icon.tex, m and m.classFile)
    r.name:SetText((e.disp or e.who) .. (m and m.online and "" or "  |cff999999·|r"))
    r.name:SetTextColor(ns.ClassColor(m and m.classFile))
    r.name:SetAlpha(m and m.online and 1 or 0.65)
    r.prof:SetText((m and m.online and ("|cff1eff00" .. L["Online"] .. "|r  ·  ") or "")
      .. (e.hits and string.format(L["%d matching"], e.hits) or string.format(L["%d recipes"], #e.codes)))
    r.lvl:SetText(e.r .. " / " .. e.m)
    r.bar:SetValue(e.m > 0 and e.r / e.m or 0)
    r:Show()
    if animate and i <= 12 then S.SlideIn(r, -10, 0, 0.22, i * 0.02) end
  end
  for i = #list + 1, #ui.rows do ui.rows[i]:Hide() end
  ui.listContent:SetHeight(math.max(1, #list * ROW_H))
  ui.dirEmpty:SetShown(#list == 0)
  ui.dirEmpty:SetText(#all == 0 and L["Nobody has shared professions yet. Open your profession windows once: Guild Enhanced shares your recipes with the guild."]
    or text ~= "" and L["No result."] or L["Nobody in the guild has shared this profession yet."])
  if not found then found = list[1]; selected = found and found.id end
  for _, r in ipairs(ui.rows) do if r:IsShown() then r.sel:SetShown(r.entry.id == selected) end end

  -- recipes of the selected one
  ui.recipeTitle.label:SetText(found and string.format(L["Recipes of %s"], found.disp or found.who) or L["Recipes"])
  local n = 0
  if found then
    local recs = {}
    for _, code in ipairs(found.codes) do
      local name, link, icon, quality = recipeInfo(code)
      if text == "" or name:lower():find(text, 1, true) or found.who:lower():find(text, 1, true)
        or profName(found.key):lower():find(text, 1, true) then
        recs[#recs + 1] = { code = code, name = name, link = link, icon = icon, q = quality }
      end
    end
    table.sort(recs, function(a, b) return a.name < b.name end)
    for i, rc in ipairs(recs) do
      n = i
      local r = recipeRow(i)
      r.link = rc.link
      r.icon.tex:SetTexture(rc.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[rc.q or 1]
      r.name:SetText((qc and qc.hex or "") .. rc.name .. "|r")
      r.ask:SetShown(found.who ~= me)
      r.ask:SetScript("OnClick", function() ns.CraftRequest(rc.code, found.who, found.key) end)
      r:Show()
    end
  end
  for i = n + 1, #ui.recipes do ui.recipes[i]:Hide() end
  ui.recipeContent:SetHeight(math.max(1, n * RECIPE_H))
  ui.recipeTitle.right:SetText(found and n or "")
  ui.recipeEmpty:SetShown(found ~= nil and n == 0)
  ui.recipeEmpty:SetText(found and #found.codes == 0 and L["Recipes not shared yet (the crafter has to open the profession window once)."]
    or L["No result."])
end

-- Build ------------------------------------------------------------------------------------------------------
local function build(p)
  page = p
  ui.pills = {}
  local x = 0
  for i, spec in ipairs({ { "dir", L["Directory"] }, { "req", L["Craft requests"] } }) do
    local pill = S.Pill(p, spec[2], function() mode = spec[1]; ns.RefreshProfessions(true) end)
    pill.key = spec[1]
    pill:SetPoint("TOPLEFT", x, 0)
    x = x + pill:GetWidth() + 6
    ui.pills[i] = pill
  end
  ui.newReq = S.Button(p, L["New request"], 140, 22, function() ns.CraftRequest() end, "primary")
  ui.newReq:SetPoint("TOPRIGHT")
  ui.search = S.EditBox(p, 220, 22, L["Search a recipe or a name"])
  ui.search:SetPoint("RIGHT", ui.newReq, "LEFT", -8, 0)
  local pendingSearch
  ui.search.onChange = function(t)
    search = t or ""
    if pendingSearch then return end
    pendingSearch = true
    C_Timer.After(0.25, function() pendingSearch = nil; selected = nil; ns.RefreshProfessions() end)
  end

  -- directory
  local dir = CreateFrame("Frame", nil, p)
  dir:SetPoint("TOPLEFT", 0, -32)
  dir:SetPoint("BOTTOMRIGHT")
  ui.dir = dir
  -- 1. the professions
  local profBox = CreateFrame("Frame", nil, dir)
  profBox:SetPoint("TOPLEFT")
  profBox:SetPoint("BOTTOMLEFT")
  profBox:SetWidth(PROF_W)
  S.Card(profBox, 8)
  ui.profTitle = S.Section(profBox, L["Professions"])
  ui.profTitle:SetPoint("TOPLEFT", 12, -10)
  ui.profTitle:SetPoint("TOPRIGHT", -12, -10)
  ui.profList = CreateFrame("Frame", nil, profBox)
  ui.profList:SetPoint("TOPLEFT", 6, -40)
  ui.profList:SetPoint("BOTTOMRIGHT", -6, 6)

  -- 2. the guildmates with the selected profession
  local left = CreateFrame("Frame", nil, dir)
  left:SetPoint("TOPLEFT", PROF_W + 10, 0)
  left:SetPoint("BOTTOMLEFT", PROF_W + 10, 0)
  left:SetWidth(MEM_W)
  S.Card(left, 8)
  ui.memTitle = S.Section(left, "")
  ui.memTitle:SetPoint("TOPLEFT", 12, -10)
  ui.memTitle:SetPoint("TOPRIGHT", -12, -10)
  local sf, content = S.Scroll(left)
  sf:SetPoint("TOPLEFT", 6, -40)
  sf:SetPoint("BOTTOMRIGHT", -14, 6)
  content:SetWidth(MEM_W - 22)
  ui.listContent = content
  ui.dirEmpty = S.Text(left, 12, "muted")
  ui.dirEmpty:SetPoint("TOPLEFT", 16, -60)
  ui.dirEmpty:SetPoint("TOPRIGHT", -16, -60)
  ui.dirEmpty:SetWordWrap(true)
  ui.dirEmpty:SetJustifyH("CENTER")

  -- 3. the recipes of the selected guildmate
  local right = CreateFrame("Frame", nil, dir)
  right:SetPoint("TOPLEFT", PROF_W + MEM_W + 20, 0)
  right:SetPoint("BOTTOMRIGHT")
  S.Card(right, 10)
  S.EdgeGlow(right, 24, 0.1)
  ui.recipeBox = right
  ui.recipeTitle = S.Section(right, L["Recipes"])
  ui.recipeTitle:SetPoint("TOPLEFT", 14, -10)
  ui.recipeTitle:SetPoint("TOPRIGHT", -14, -10)
  local rsf, rcontent = S.Scroll(right)
  rsf:SetPoint("TOPLEFT", 10, -40)
  rsf:SetPoint("BOTTOMRIGHT", -18, 10)
  rcontent:SetWidth(ns.PAGE_W - PROF_W - MEM_W - 20 - 30)
  ui.recipeContent = rcontent
  ui.recipeEmpty = S.Text(right, 12, "muted")
  ui.recipeEmpty:SetPoint("TOPLEFT", 20, -60)
  ui.recipeEmpty:SetPoint("TOPRIGHT", -20, -60)
  ui.recipeEmpty:SetWordWrap(true)
  ui.recipeEmpty:SetJustifyH("CENTER")

  -- requests
  local req = CreateFrame("Frame", nil, p)
  req:SetPoint("TOPLEFT", 0, -32)
  req:SetPoint("BOTTOMRIGHT")
  S.Card(req, 8)
  ui.req = req
  local qsf, qcontent = S.Scroll(req)
  qsf:SetPoint("TOPLEFT", 8, -8)
  qsf:SetPoint("BOTTOMRIGHT", -16, 8)
  qcontent:SetWidth(ns.PAGE_W - 26)
  ui.reqContent = qcontent
  ui.reqEmpty = S.Text(req, 13, "muted")
  ui.reqEmpty:SetPoint("CENTER")
  ui.reqEmpty:SetText(L["No craft request. Ask from a recipe in the directory, or with New request."])
end

local function onShow()
  readSkills()
  ns.RefreshProfessions(true)
end

ns.AddPage(PAGE, "Professions", build, onShow, { "Interface\\Icons\\Trade_BlackSmithing", "Interface\\Icons\\Trade_Engineering",
  "Interface\\Icons\\INV_Hammer_20" })

local pending
local function later()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function()
    pending = nil
    if page and page:IsVisible() then ns.RefreshProfessions() end
  end)
end
ns.On("SYNC_PROF", later)
ns.On("SYNC_CRAFT", function(rec)
  later()
  if rec and not rec.del and rec.to == me and rec.st == "open" and not (page and page:IsVisible()) then
    ns.SetTabBadge(PAGE, "!")
  end
end)
local iev = CreateFrame("Frame")
pcall(iev.RegisterEvent, iev, "GET_ITEM_INFO_RECEIVED")
iev:SetScript("OnEvent", function() if missing then later() end end)
