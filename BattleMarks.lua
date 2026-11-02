-- BattleMarks (formerly PartyMarks): a raid marker on every hero of a co-op party, you included,
-- when the match loads.
-- You choose your own marker; the others get the free ones in order. Markers are set at the start
-- and for heroes who join later; changes made by hand stay until the next match. The top boss gets
-- the skull and the second the cross (guardians when no boss is up), solo too if you like, and the
-- markers can be announced in party chat.
-- When several heroes run BattleMarks, one of them sets the markers (the leader, else the first by
-- name) and honours everyone's chosen marker. WoW 1.12 / Lua 5.0.

local PREFIX = "BattleMarks"
local NAMES = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }
local COLORS = { "ffff00", "ff8000", "e040ff", "40ff40", "c0d8ff", "40a0ff", "ff4040", "ffffff" }
local PASSES = { 2.5, 5, 8, 12 }   -- seconds after a start or a join: party units arrive late
local BOSS_MARKS = { 8, 7 }        -- skull for the first boss, cross for a second one up at once
local ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local defaults = { enabled = true, mine = 1, button = true, btnAngle = 160, bosses = true, bossesSolo = true,
  announce = true }
local db

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBattleMarks|r " .. msg) end
local function Marker(i) return "|cff" .. COLORS[i] .. NAMES[i] .. "|r" end
local function Title(s) return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2) end

-- a marker kept for bosses while "skull on bosses" is on
local function Reserved(k)
  if not db.bosses then return false end
  for i = 1, table.getn(BOSS_MARKS) do
    if BOSS_MARKS[i] == k then return true end
  end
  return false
end

-- ---------------------------------------------------------------- the party
local function Me() return UnitName("player") end

-- you first, then each party hero whose name is known
local function Members()
  local list = { "player" }
  for i = 1, GetNumPartyMembers() do
    local u = "party" .. i
    local name = UnitExists(u) and UnitName(u)
    if name and name ~= UNKNOWNOBJECT then table.insert(list, u) end
  end
  return list
end

local function InParty(name)
  local units = Members()
  for i = 1, table.getn(units) do
    if UnitName(units[i]) == name then return true end
  end
  return false
end

local function LeaderName()
  local i = GetPartyLeaderIndex()
  if not i or i == 0 then return Me() end
  return UnitName("party" .. i)
end

-- heroes running BattleMarks, by name, with the marker each one chose
local users = {}

-- who sets the markers: the leader when it runs BattleMarks, else the first such hero by name
local function Decider()
  local leader = LeaderName()
  if leader and users[leader] then return leader end
  local best
  for name in pairs(users) do
    if InParty(name) and (not best or name < best) then best = name end
  end
  return best
end

-- ---------------------------------------------------------------- the heroes' markers
-- Who gets which marker. keep: leave every hero who already has one alone and fill the rest.
-- Chosen markers go first (yours, then the other BattleMarks heroes by name), then the free ones
-- in order, skipping the ones turned off for teammates and the bosses' ones.
local function Plan(keep)
  local units = Members()
  local plan, taken, todo = {}, {}, {}
  for k = 1, 8 do
    if Reserved(k) then taken[k] = true end
  end
  for i = 1, table.getn(units) do
    local u = units[i]
    local now = GetRaidTargetIndex(u)
    if keep and now then
      taken[now] = true
    else
      local name = UnitName(u)
      local rank = 3
      if u == "player" then rank = 1 elseif users[name] then rank = 2 end
      table.insert(todo, { unit = u, name = name, rank = rank, pref = (u == "player") and db.mine or users[name] })
    end
  end
  table.sort(todo, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.name < b.name
  end)
  for i = 1, table.getn(todo) do
    local t = todo[i]
    local icon = (t.pref and not taken[t.pref]) and t.pref or nil
    if not icon then
      for k = 1, 8 do
        if not taken[k] and not db.skip[k] then icon = k; break end
      end
    end
    if icon then
      taken[icon] = true
      plan[t.unit] = icon
    end
  end
  return plan
end

local function Apply(keep)
  if GetNumPartyMembers() == 0 then return 0 end
  local n = 0
  for u, icon in pairs(Plan(keep)) do
    if GetRaidTargetIndex(u) ~= icon then
      SetRaidTarget(u, icon)
      n = n + 1
    end
  end
  return n
end

local function Clear()
  local units = Members()
  for i = 1, table.getn(units) do
    if GetRaidTargetIndex(units[i]) then SetRaidTarget(units[i], 0) end
  end
end

-- ---------------------------------------------------------------- the bosses' markers
-- Skull on the top target, cross on the second: the final boss, then the other bosses in spawn
-- order; with no boss up, the awake guardians. When one dies the next moves up (the cross boss
-- to skull, an unmarked third to cross), and a boss coming up takes the markers from guardians.
-- 1.12 can mark an enemy only through a unit (a target, the mouseover), so a marker goes up once
-- someone targets its enemy; and the game tells a guardian from an elite only for your target.
-- Each placement is made once, so a marker moved by hand stays until the targets change.
local applied = {}   -- marker -> name it was placed on for the current targets
local held = {}      -- marker -> { name, kind } it was last placed on

-- who should hold the bosses' markers, top first
local function Targets()
  local list, awake = {}, {}
  if type(AZS_GetBosses) == "function" then
    local ok, bosses = pcall(AZS_GetBosses)
    if ok and type(bosses) == "table" then
      for pass = 1, 2 do
        for i = 1, table.getn(bosses) do
          local b = bosses[i]
          if b.name and ((pass == 1) == (b.final == true)) then
            table.insert(list, { name = b.name, kind = "boss" })
          end
        end
      end
    end
  end
  if type(AZS_GetGuardians) == "function" then
    local ok, guardians = pcall(AZS_GetGuardians)
    if ok and type(guardians) == "table" then
      local noBoss = table.getn(list) == 0
      for i = 1, table.getn(guardians) do
        local g = guardians[i]
        if g.name and g.awake then
          awake[g.name] = true
          if noBoss then table.insert(list, { name = g.name, kind = "guardian" }) end
        end
      end
    end
  end
  return list, awake
end

local function EnemyUnits()
  local units = { "target", "mouseover", "pettarget" }
  for i = 1, GetNumPartyMembers() do table.insert(units, "party" .. i .. "target") end
  return units
end

local function IsKind(u, kind)
  local ok, k = pcall(AZS_UnitKind, u)
  if not ok then return false end
  if kind == "boss" then return k == "boss" or k == "final" end
  return k == kind
end

local function MarkBosses()
  if not db.bosses or type(AZS_UnitKind) ~= "function" then return end
  if GetNumPartyMembers() == 0 and not db.bossesSolo then return end
  local targets, awake = Targets()
  local want = {}
  for i = 1, table.getn(BOSS_MARKS) do want[BOSS_MARKS[i]] = targets[i] end
  local units = EnemyUnits()
  for i = 1, table.getn(BOSS_MARKS) do
    local icon = BOSS_MARKS[i]
    local t = want[icon]
    if not t then
      applied[icon] = nil
      -- nobody should hold it: a guardian still wearing it loses it once it's in reach
      local h = held[icon]
      if h and h.kind == "guardian" and awake[h.name] then
        for j = 1, table.getn(units) do
          local u = units[j]
          if UnitExists(u) and UnitName(u) == h.name and GetRaidTargetIndex(u) == icon then
            SetRaidTarget(u, 0)
            held[icon] = nil
            break
          end
        end
      else
        held[icon] = nil
      end
    elseif applied[icon] ~= t.name then
      for j = 1, table.getn(units) do
        local u = units[j]
        if UnitExists(u) and not UnitIsDead(u) and UnitName(u) == t.name and IsKind(u, t.kind) then
          -- two targets of one name: leave the one already wearing the other marker
          local now = GetRaidTargetIndex(u)
          local twin = now and now ~= icon and want[now] and want[now].name == t.name and applied[now] == t.name
          if not twin then
            if now ~= icon then SetRaidTarget(u, icon) end
            applied[icon], held[icon] = t.name, t
            break
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------- telling the party
local announced = {}   -- hero names already announced this match

local function Announce()
  if not db.announce or GetNumPartyMembers() == 0 then return end
  local first = next(announced) == nil
  local parts = {}
  local units = Members()
  for i = 1, table.getn(units) do
    local name, icon = UnitName(units[i]), GetRaidTargetIndex(units[i])
    if name and icon and not announced[name] then
      announced[name] = true
      table.insert(parts, name .. " = " .. Title(NAMES[icon]))
    end
  end
  if table.getn(parts) == 0 then return end
  local msg = "Markers: " .. table.concat(parts, ", ")
  if first and db.bosses then msg = msg .. ". Skull = top boss, Cross = second." end
  SendChatMessage(msg, "PARTY")
end

-- ---------------------------------------------------------------- talking to other copies
local lastReply = 0
local function Hello(ask)
  if GetNumPartyMembers() == 0 or not SendAddonMessage then return end
  SendAddonMessage(PREFIX, "HI:" .. db.mine .. ":" .. (ask and "?" or ""), "PARTY")
end

-- ---------------------------------------------------------------- when to act
local passes = {}    -- { at = GetTime() to run, keep = true/false, announce = true/false }

local function Schedule(keep)
  -- a match's plan-from-scratch pass still waiting survives a party change rescheduling it
  local fresh = not keep
  for i = 1, table.getn(passes) do
    if not passes[i].keep then fresh = true end
  end
  passes = {}
  local now = GetTime()
  for i = 1, table.getn(PASSES) do
    -- only the first pass plans from scratch; the later ones fill gaps and announce
    table.insert(passes, { at = now + PASSES[i], keep = not fresh or i > 1, announce = i > 1 })
  end
end

local function Start(keep)
  users = { [Me()] = db.mine }
  announced, applied, held = {}, {}, {}
  -- after a /reload mid-match the markers were already announced
  if keep then
    local units = Members()
    for i = 1, table.getn(units) do announced[UnitName(units[i]) or ""] = true end
  end
  if not db.enabled or GetNumPartyMembers() == 0 then passes = {}; return end
  Hello(true)
  Schedule(keep)
end

local function Phase()
  if type(AZS_GetPhase) ~= "function" then return nil end
  local ok, ph = pcall(AZS_GetPhase)
  return ok and ph or nil
end

local function InRun(ph) return ph and ph ~= "dead" and ph ~= "victory" end

local f = CreateFrame("Frame", "BattleMarksFrame")
local lastPhase, seen = nil, false
local tick = 0
f:SetScript("OnUpdate", function()
  if not db then return end
  tick = tick + arg1
  if tick < 0.25 then return end
  tick = 0
  local ph = Phase()
  if ph ~= lastPhase then
    if InRun(ph) and not InRun(lastPhase) then
      -- a new match; or, the first phase this UI sees, a /reload in the middle of one:
      -- then keep what is already set
      Start(not seen and ph ~= "ready")
    end
    if not ph then passes = {} end
    lastPhase, seen = ph, true
  end
  if not db.enabled then return end
  local now = GetTime()
  while passes[1] and passes[1].at <= now do
    local p = table.remove(passes, 1)
    if Decider() == Me() then
      Apply(p.keep)
      if p.announce then Announce() end
    end
  end
  if InRun(ph) then MarkBosses() end
end)

f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    BattleMarksDB = BattleMarksDB or {}
    db = BattleMarksDB
    for k, v in pairs(defaults) do
      if db[k] == nil then db[k] = v end
    end
    -- markers not handed out to teammates: skull and cross unless changed
    if type(db.skip) ~= "table" then db.skip = { [7] = true, [8] = true } end
    users[Me() or ""] = db.mine
  elseif not db then
    return
  elseif event == "PARTY_MEMBERS_CHANGED" then
    -- someone joined or left during a match: mark the newcomers, leave everyone else alone
    if db.enabled and InRun(Phase()) and GetNumPartyMembers() > 0 then
      Hello(true)
      Schedule(true)
    end
  elseif event == "CHAT_MSG_ADDON" and arg1 == PREFIX and arg4 and arg4 ~= Me() then
    local _, _, icon, ask = string.find(arg2 or "", "^HI:(%d):(%??)$")
    icon = tonumber(icon)
    if icon and icon >= 1 and icon <= 8 then
      users[arg4] = icon
      if ask == "?" and GetTime() - lastReply > 1 then
        lastReply = GetTime()
        Hello(false)
      end
    end
  end
end)

-- ---------------------------------------------------------------- choosing markers
-- the eight markers sit on one sheet, four to a row
local function MarkerCoords(tex, i)
  local col, row = math.mod(i - 1, 4), math.floor((i - 1) / 4)
  tex:SetTexCoord(col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25)
end

local Refresh, ButtonShown, ButtonLook   -- set below

local function SetMine(i)
  if Reserved(i) then
    Print(Marker(i) .. " is kept for bosses while \"Skull on bosses\" is on.")
    return false
  end
  db.mine = i
  users[Me()] = i
  Hello(false)
  if ButtonLook then ButtonLook() end
  return true
end

-- ---------------------------------------------------------------- the settings window
local cfg = CreateFrame("Frame", "BattleMarksConfig", UIParent)
cfg:SetWidth(310)
cfg:SetHeight(424)
cfg:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
cfg:SetFrameStrata("DIALOG")
cfg:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 } })
cfg:SetMovable(true)
cfg:EnableMouse(true)
cfg:RegisterForDrag("LeftButton")
cfg:SetScript("OnDragStart", function() this:StartMoving() end)
cfg:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
cfg:Hide()
table.insert(UISpecialFrames, "BattleMarksConfig")   -- Escape closes it

local title = cfg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", cfg, "TOP", 0, -18)
title:SetText("BattleMarks")

local close = CreateFrame("Button", nil, cfg, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -6, -6)

local function Check(name, label, y, onClick, x)
  local c = CreateFrame("CheckButton", name, cfg, "UICheckButtonTemplate")
  c:SetPoint("TOPLEFT", cfg, "TOPLEFT", x or 20, y)
  c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  c.label:SetPoint("LEFT", c, "RIGHT", 0, 1)
  c.label:SetText(label)
  c:SetScript("OnClick", onClick)
  return c
end

local cEnabled = Check("BattleMarksCheckEnabled", "Mark the party when a co-op match loads", -46, function()
  db.enabled = this:GetChecked() and true or false
  if not db.enabled then passes = {} end
  ButtonLook()
end)
local cBosses = Check("BattleMarksCheckBosses", "Skull and cross on bosses (or guardians)", -72, function()
  db.bosses = this:GetChecked() and true or false
  -- your own marker can't be a boss marker
  if Reserved(db.mine) then
    for k = 1, 8 do
      if not Reserved(k) and not db.skip[k] then SetMine(k); break end
    end
  end
  Refresh()
end)
local cSolo = Check("BattleMarksCheckSolo", "Also when playing solo", -96, function()
  db.bossesSolo = this:GetChecked() and true or false
end, 44)
local cAnnounce = Check("BattleMarksCheckAnnounce", "Tell the party the markers in chat", -122, function()
  db.announce = this:GetChecked() and true or false
end)
local cButton = Check("BattleMarksCheckButton", "Show the minimap button", -148, function()
  db.button = this:GetChecked() and true or false
  ButtonShown()
  if not db.button then Print("minimap button hidden: /bmarks opens the settings.") end
end)

local function Label(text, y)
  local t = cfg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", cfg, "TOPLEFT", 24, y)
  t:SetText(text)
  return t
end

-- a row of the eight markers
local function MarkerRow(y, onClick, onEnter)
  local row = {}
  for i = 1, 8 do
    local b = CreateFrame("Button", nil, cfg)
    b:SetWidth(28)
    b:SetHeight(28)
    b:SetPoint("TOPLEFT", cfg, "TOPLEFT", 26 + (i - 1) * 32, y)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexture(ICONS)
    MarkerCoords(b.icon, i)
    b.frame = b:CreateTexture(nil, "OVERLAY")
    b.frame:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.frame:SetBlendMode("ADD")
    b.frame:SetVertexColor(1, 0.82, 0)
    b.frame:SetWidth(50)
    b.frame:SetHeight(50)
    b.frame:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.frame:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b.index = i
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row[i] = b
  end
  return row
end

Label("Your marker:", -188)
local mineName = cfg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mineName:SetPoint("TOPLEFT", cfg, "TOPLEFT", 112, -188)
local mineRow = MarkerRow(-208, function()
  if SetMine(this.index) then Refresh() end
end, function()
  GameTooltip:SetOwner(this, "ANCHOR_TOP")
  GameTooltip:AddLine(Title(NAMES[this.index]), 1, 0.82, 0)
  if Reserved(this.index) then GameTooltip:AddLine("Kept for bosses", 1, 0.3, 0.3) end
  GameTooltip:Show()
end)

Label("Markers for teammates:", -250)
local teamHint = cfg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
teamHint:SetPoint("TOPLEFT", cfg, "TOPLEFT", 24, -266)
teamHint:SetText("Click to turn one off or on.")
local teamRow = MarkerRow(-284, function()
  local i = this.index
  if Reserved(i) then
    Print(Marker(i) .. " is kept for bosses while \"Skull on bosses\" is on.")
    return
  end
  if db.skip[i] then db.skip[i] = nil else db.skip[i] = true end
  Refresh()
end, function()
  GameTooltip:SetOwner(this, "ANCHOR_TOP")
  GameTooltip:AddLine(Title(NAMES[this.index]), 1, 0.82, 0)
  if Reserved(this.index) then
    GameTooltip:AddLine("Kept for bosses", 1, 0.3, 0.3)
  elseif db.skip[this.index] then
    GameTooltip:AddLine("Not handed out. Click to use it.", 1, 1, 1)
  else
    GameTooltip:AddLine("Handed out. Click to skip it.", 1, 1, 1)
  end
  GameTooltip:Show()
end)

local who = cfg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
who:SetPoint("TOPLEFT", cfg, "TOPLEFT", 24, -326)
who:SetWidth(262)
who:SetJustifyH("LEFT")

local function PanelButton(text, x, onClick)
  local b = CreateFrame("Button", nil, cfg, "UIPanelButtonTemplate")
  b:SetWidth(120)
  b:SetHeight(22)
  b:SetPoint("BOTTOM", cfg, "BOTTOM", x, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end
PanelButton("Set markers now", -64, function()
  if GetNumPartyMembers() == 0 then Print("you're not in a party."); return end
  users[Me()] = db.mine
  Apply(false)
end)
PanelButton("Clear markers", 64, function() Clear() end)

Refresh = function()
  if not db or not cfg:IsShown() then return end
  cEnabled:SetChecked(db.enabled and 1 or nil)
  cBosses:SetChecked(db.bosses and 1 or nil)
  cSolo:SetChecked(db.bossesSolo and 1 or nil)
  if db.bosses then cSolo:Enable(); cSolo.label:SetTextColor(1, 1, 1) else cSolo:Disable(); cSolo.label:SetTextColor(0.5, 0.5, 0.5) end
  cAnnounce:SetChecked(db.announce and 1 or nil)
  cButton:SetChecked(db.button and 1 or nil)
  mineName:SetText(Marker(db.mine))
  for i = 1, 8 do
    local reserved = Reserved(i)
    if i == db.mine then mineRow[i].frame:Show() else mineRow[i].frame:Hide() end
    if reserved then mineRow[i].icon:SetVertexColor(0.3, 0.3, 0.3) else mineRow[i].icon:SetVertexColor(1, 1, 1) end
    if reserved or db.skip[i] then teamRow[i].icon:SetVertexColor(0.3, 0.3, 0.3) else teamRow[i].icon:SetVertexColor(1, 1, 1) end
  end
  if GetNumPartyMembers() == 0 then
    who:SetText("Not in a party right now. Markers go up when a co-op match loads.")
  else
    local d = Decider()
    who:SetText("In this party the markers are set by " .. (d == Me() and "you" or ("|cffffffff" .. tostring(d) .. "|r"))
      .. (d ~= Me() and d and " (they run BattleMarks too; your chosen marker is honoured)." or "."))
  end
end
cfg:SetScript("OnShow", Refresh)
-- the party can change while the window is open
local cfgTick = 0
cfg:SetScript("OnUpdate", function()
  cfgTick = cfgTick + arg1
  if cfgTick < 1 then return end
  cfgTick = 0
  Refresh()
end)

local function ToggleConfig()
  if cfg:IsShown() then cfg:Hide() else cfg:Show() end
end

-- ---------------------------------------------------------------- the minimap button
local function SquareMinimap()
  if type(GetMinimapShape) == "function" then
    local ok, shape = pcall(GetMinimapShape)
    if ok and shape then return shape == "SQUARE" end
  end
  return DFRL ~= nil   -- SurvivorsDragonUi's minimap is square
end

local btn = CreateFrame("Button", "BattleMarksMinimapButton", Minimap)
btn:SetWidth(31)
btn:SetHeight(31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local btnIcon = btn:CreateTexture(nil, "BACKGROUND")
btnIcon:SetWidth(18)
btnIcon:SetHeight(18)
btnIcon:SetTexture(ICONS)
btnIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -6)
local btnRing = btn:CreateTexture(nil, "OVERLAY")
btnRing:SetWidth(53)
btnRing:SetHeight(53)
btnRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
btnRing:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

-- angle in degrees, 0 = east, counterclockwise; on a square minimap it sits on the square's edge
local function PlaceButton()
  local a = math.rad(db.btnAngle)
  local x, y = math.cos(a), math.sin(a)
  if SquareMinimap() then
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m, y / m
  end
  local r = (Minimap:GetWidth() or 140) / 2 + 8
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

ButtonShown = function()
  if db.button then btn:Show() else btn:Hide() end
end

-- the button wears the skull, dimmed while BattleMarks is off
ButtonLook = function()
  MarkerCoords(btnIcon, 8)
  if db.enabled then btnIcon:SetVertexColor(1, 1, 1) else btnIcon:SetVertexColor(0.35, 0.35, 0.35) end
  if Refresh then Refresh() end
end

btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetScript("OnClick", function()
  if not db then return end
  if arg1 == "RightButton" then
    db.enabled = not db.enabled
    if not db.enabled then passes = {} end
    ButtonLook()
    Print(db.enabled and "on." or "off.")
  else
    ToggleConfig()
  end
end)
btn:SetScript("OnDragStart", function()
  this:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local s = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    db.btnAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
    PlaceButton()
  end)
end)
btn:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
btn:SetScript("OnEnter", function()
  GameTooltip:SetOwner(this, "ANCHOR_LEFT")
  GameTooltip:AddLine("BattleMarks", 0.4, 0.8, 1)
  GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
  GameTooltip:AddLine("Right-click: on or off", 1, 1, 1)
  GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
  GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- registered after the main frame's, so db is ready when this runs
btn:RegisterEvent("VARIABLES_LOADED")
btn:SetScript("OnEvent", function()
  -- a marker chosen before skull and cross went to the bosses
  if Reserved(db.mine) then db.mine = 1 end
  PlaceButton()
  ButtonShown()
  ButtonLook()
end)

-- ---------------------------------------------------------------- /bmarks
local function ParseMarker(s)
  local n = tonumber(s)
  if n and n >= 1 and n <= 8 then return n end
  for i = 1, 8 do
    if NAMES[i] == s then return i end
  end
end

SLASH_BATTLEMARKS1 = "/bmarks"
SLASH_BATTLEMARKS2 = "/battlemarks"
SlashCmdList["BATTLEMARKS"] = function(msg)
  if not db then return end
  local _, _, cmd, val = string.find(string.lower(msg or ""), "^%s*(%S*)%s*(.-)%s*$")
  if cmd == "me" or cmd == "mine" then
    local i = ParseMarker(val)
    if not i then
      local list = {}
      for k = 1, 8 do table.insert(list, k .. " " .. Marker(k)) end
      Print("usage: /bmarks me star  (" .. table.concat(list, ", ") .. ")")
      return
    end
    if SetMine(i) then Print("your marker: " .. Marker(i) .. ".") end
  elseif cmd == "on" or cmd == "off" then
    db.enabled = (cmd == "on")
    if not db.enabled then passes = {} end
    ButtonLook()
    Print(db.enabled and "on: markers are set when a co-op match loads." or "off.")
  elseif cmd == "button" then
    db.button = not db.button
    ButtonShown()
    if Refresh then Refresh() end
    Print(db.button and "minimap button shown." or "minimap button hidden.")
  elseif cmd == "now" then
    if GetNumPartyMembers() == 0 then Print("you're not in a party."); return end
    users[Me()] = db.mine
    local n = Apply(false)
    Print("markers set (" .. n .. " changed).")
  elseif cmd == "clear" then
    Clear()
    Print("markers cleared.")
  elseif cmd == "" then
    ToggleConfig()
  elseif cmd == "status" then
    Print((db.enabled and "on" or "off") .. ", your marker: " .. Marker(db.mine) .. ", bosses: "
      .. (db.bosses and (db.bossesSolo and "on, solo too" or "on, in a party") or "off") .. ", party chat: " .. (db.announce and "on" or "off") .. ".")
    if GetNumPartyMembers() > 0 then
      local d = Decider()
      Print("in this party the markers are set by " .. (d == Me() and "you" or tostring(d)) .. ".")
    end
  else
    Print("commands: /bmarks (settings), /bmarks me <marker>, /bmarks on|off, /bmarks now, /bmarks clear, /bmarks status, /bmarks button")
  end
end
