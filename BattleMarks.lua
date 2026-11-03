-- BattleMarks (formerly PartyMarks): a raid marker on every hero of a co-op party, you included,
-- when the match loads.
-- Markers are numbered: 1 is you, 2 to 5 the party's slots, and bosses and guardians get their own
-- (skull and cross unless changed, up to all eight). They're set at the start and for heroes who
-- join later; changes made by hand stay until the next match. Solo too if you like, and the markers
-- can be announced in party chat.
-- When several heroes run BattleMarks, one of them sets the markers (the leader, else the first by
-- name) and honours everyone's chosen marker. WoW 1.12 / Lua 5.0.

local PREFIX = "BattleMarks"
local NAMES = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }
local COLORS = { "ffff00", "ff8000", "e040ff", "40ff40", "c0d8ff", "40a0ff", "ff4040", "ffffff" }
local PASSES = { 2.5, 5, 8, 12 }   -- seconds after a start or a join: party units arrive late
local ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- what the party is told; {markers}, {first}, {second} and {kind} are filled in
local SAY_MARKERS = "Markers: {markers}."
local SAY_BOSSES = "{first} = top {kind}, {second} = second."
local defaults = { enabled = true, button = true, btnAngle = 160, announce = true,
  markBosses = true, markGuardians = true, bossesSolo = true, selfSolo = false, guardiansFirst = false, fillGaps = false,
  announceText = SAY_MARKERS, announceBossMarks = false, bossText = SAY_BOSSES }
local db

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBattleMarks|r " .. msg) end
local function Marker(i) return "|cff" .. COLORS[i] .. NAMES[i] .. "|r" end
local function Title(s) return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2) end

-- The markers are numbered slots: db.partyMarks[1] is yours and 2 to 5 belong to the party's slots
-- (a party is you and four more); db.bossMarks[1] goes to the top boss or guardian, [2] to the next,
-- up to all eight. An empty slot marks no one, so a row can use as few markers as wanted, or none.
-- db.mine mirrors your slot.
local PARTY_MAX, BOSS_MAX = 5, 8

-- a slot table's markers in order, empty slots left out
local function Compact(slots, max)
  local list = {}
  for n = 1, max do
    if slots[n] then table.insert(list, slots[n]) end
  end
  return list
end

-- one of the bosses' markers, while bosses or guardians are marked
local function Reserved(k)
  if not k or (not db.markBosses and not db.markGuardians) then return false end
  for n = 1, BOSS_MAX do
    if db.bossMarks[n] == k then return true end
  end
  return false
end

-- the party gives up any marker the bosses now use; your own is its first slot
local function ClearConflicts()
  for n = 1, PARTY_MAX do
    if Reserved(db.partyMarks[n]) then db.partyMarks[n] = nil end
  end
  db.mine = db.partyMarks[1]
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
-- Each hero has a number: you 1, the party's slots 2 to 5. You wear marker 1; the other BattleMarks
-- heroes wear what they chose; everyone else wears their number's marker. A hero whose marker
-- went to someone's choice takes a party marker no one wears; a number left empty marks no one.
-- Never the bosses' markers.
local function Plan(keep)
  local units = Members()
  local plan, taken, heroes = {}, {}, {}
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
      local number = (u == "player") and 1 or ((tonumber(string.sub(u, 6)) or 0) + 1)
      local pref = (u ~= "player") and users[name] or nil
      if pref and not NAMES[pref] then pref = nil end   -- a hero with no marker of its own sends 0
      table.insert(heroes, { unit = u, name = name, number = number, pref = pref })
    end
  end
  local function Give(h, k)
    if k and not taken[k] and not plan[h.unit] then
      taken[k] = true
      plan[h.unit] = k
    end
  end
  -- you first, then the other BattleMarks heroes' choices, by name so every copy agrees
  table.sort(heroes, function(a, b)
    if (a.unit == "player") ~= (b.unit == "player") then return a.unit == "player" end
    if (a.pref ~= nil) ~= (b.pref ~= nil) then return a.pref ~= nil end
    if a.pref then return a.name < b.name end
    return a.number < b.number
  end)
  for i = 1, table.getn(heroes) do
    local h = heroes[i]
    if h.unit == "player" then Give(h, db.partyMarks[1]) else Give(h, h.pref) end
  end
  -- then everyone's own number
  for i = 1, table.getn(heroes) do
    local h = heroes[i]
    Give(h, db.partyMarks[h.number])
  end
  -- a number whose marker someone else chose takes one of the party's markers no one wears
  local spare = Compact(db.partyMarks, PARTY_MAX)
  for i = 1, table.getn(heroes) do
    local h = heroes[i]
    if not plan[h.unit] and (db.partyMarks[h.number] or h.pref) then
      for n = 1, table.getn(spare) do Give(h, spare[n]) end
    end
  end
  return plan
end

local function Apply(keep)
  if GetNumPartyMembers() == 0 and not db.selfSolo then return 0 end
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

-- who should hold the bosses' markers, top first: bosses (the final boss first, then the others
-- in the order they came) and awake guardians, whichever ranks first; the other kind only when
-- none of the first is up, or to fill an empty marker when "Fill empty markers" is on
local function Targets()
  local bosses, guardians, awake = {}, {}, {}
  if db.markBosses and type(AZS_GetBosses) == "function" then
    local ok, list = pcall(AZS_GetBosses)
    if ok and type(list) == "table" then
      for pass = 1, 2 do
        for i = 1, table.getn(list) do
          local b = list[i]
          if b.name and ((pass == 1) == (b.final == true)) then
            table.insert(bosses, { name = b.name, kind = "boss" })
          end
        end
      end
    end
  end
  if type(AZS_GetGuardians) == "function" then
    local ok, list = pcall(AZS_GetGuardians)
    if ok and type(list) == "table" then
      for i = 1, table.getn(list) do
        local g = list[i]
        if g.name and g.awake then
          awake[g.name] = true
          if db.markGuardians then table.insert(guardians, { name = g.name, kind = "guardian" }) end
        end
      end
    end
  end
  local first, second = bosses, guardians
  if db.guardiansFirst then first, second = guardians, bosses end
  local targets = {}
  for i = 1, table.getn(first) do table.insert(targets, first[i]) end
  if table.getn(targets) == 0 or db.fillGaps then
    for i = 1, table.getn(second) do table.insert(targets, second[i]) end
  end
  return targets, awake
end

-- the boss markers were changed: place them afresh
local function ResetBossMarks()
  applied, held = {}, {}
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
  if (not db.markBosses and not db.markGuardians) or type(AZS_UnitKind) ~= "function" then return end
  if GetNumPartyMembers() == 0 and not db.bossesSolo then return end
  local targets, awake = Targets()
  local want = {}
  local marks = Compact(db.bossMarks, BOSS_MAX)
  for i = 1, table.getn(marks) do want[marks[i]] = targets[i] end
  local units = EnemyUnits()
  for i = 1, table.getn(marks) do
    local icon = marks[i]
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
local bossesTold        -- the bosses' markers were told this match

-- fills a message's {words}; one the message doesn't know stays as written. A | would break
-- the chat line, so it's taken out.
local function Fill(text, words)
  text = string.gsub(text, "{(%a+)}", function(w) return words[w] end)
  text = string.gsub(text, "|", "/")
  return string.sub(text, 1, 255)
end

local function Announce()
  if GetNumPartyMembers() == 0 then return end
  local said = {}
  if db.announce then
    local parts = {}
    local units = Members()
    for i = 1, table.getn(units) do
      local name, icon = UnitName(units[i]), GetRaidTargetIndex(units[i])
      if name and icon and not announced[name] then
        announced[name] = true
        table.insert(parts, name .. " = " .. Title(NAMES[icon]))
      end
    end
    if table.getn(parts) > 0 then
      table.insert(said, Fill(db.announceText, { markers = table.concat(parts, ", ") }))
    end
  end
  -- the bosses' markers, once a match
  local marks = Compact(db.bossMarks, BOSS_MAX)
  if db.announceBossMarks and not bossesTold and (db.markBosses or db.markGuardians) and marks[1] then
    bossesTold = true
    local kind = db.markBosses and (db.markGuardians and "boss or guardian" or "boss") or "guardian"
    table.insert(said, Fill(db.bossText, { first = Title(NAMES[marks[1]]),
      second = marks[2] and Title(NAMES[marks[2]]) or "none", kind = kind }))
  end
  local msg = table.concat(said, " ")
  if msg ~= "" then SendChatMessage(string.sub(msg, 1, 255), "PARTY") end
end

-- ---------------------------------------------------------------- talking to other copies
local lastReply = 0
local function Hello(ask)
  if GetNumPartyMembers() == 0 or not SendAddonMessage then return end
  SendAddonMessage(PREFIX, "HI:" .. (db.mine or 0) .. ":" .. (ask and "?" or ""), "PARTY")
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
  announced, applied, held, bossesTold = {}, {}, {}, nil
  -- after a /reload mid-match the markers were already announced
  if keep then
    bossesTold = true
    local units = Members()
    for i = 1, table.getn(units) do announced[UnitName(units[i]) or ""] = true end
  end
  if not db.enabled or (GetNumPartyMembers() == 0 and not db.selfSolo) then passes = {}; return end
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
    -- 0.5.0's one switch for bosses (and guardians) became two
    if db.bosses ~= nil then
      db.markBosses, db.markGuardians, db.bosses = db.bosses, db.bosses, nil
    end
    for k, v in pairs(defaults) do
      if db[k] == nil then db[k] = v end
    end
    -- markers not handed out to teammates: skull and cross unless changed
    db.announceBosses = nil
    local function Valid(k) return type(k) == "number" and NAMES[k] ~= nil end
    -- the bosses' two markers: skull and cross unless changed
    if type(db.bossMarks) ~= "table" then db.bossMarks = { 8, 7 } end
    local seen = {}
    for n = 1, BOSS_MAX do
      local k = db.bossMarks[n]
      if not Valid(k) or seen[k] then db.bossMarks[n] = nil else seen[k] = true end
    end
    -- the party's five: 0.5.0 kept your marker in db.mine and the teammates' as the ones not
    -- skipped; new ones get star for you, then circle, diamond, triangle and square
    if type(db.partyMarks) ~= "table" then
      -- (0.5.0's own default, cross and skull skipped, counts as no choice made)
      local skip, count = db.skip, 0
      if type(skip) == "table" then for _ in pairs(skip) do count = count + 1 end end
      if type(skip) ~= "table" or (count == 2 and skip[7] and skip[8]) then
        skip = { [5] = true, [7] = true, [8] = true }
      end
      local mine = Valid(db.mine) and not Reserved(db.mine) and db.mine or 1
      local slots, n = { mine }, 1
      for k = 1, 8 do
        if n < PARTY_MAX and k ~= mine and not skip[k] and not Reserved(k) then
          n = n + 1
          slots[n] = k
        end
      end
      db.partyMarks = slots
    end
    db.skip = nil
    seen = {}
    for n = 1, PARTY_MAX do
      local k = db.partyMarks[n]
      if not Valid(k) or seen[k] then db.partyMarks[n] = nil else seen[k] = true end
    end
    ClearConflicts()
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
    if icon and icon >= 0 and icon <= 8 then
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
    Print(Marker(i) .. " is one of the Bosses / Guardians markers: let it go there to use it.")
    return false
  end
  -- it moves to the first slot; one of the teammates' slots holding it gives it up
  for n = 2, PARTY_MAX do
    if db.partyMarks[n] == i then db.partyMarks[n] = nil end
  end
  db.partyMarks[1] = i
  db.mine = i
  users[Me()] = i
  Hello(false)
  if ButtonLook then ButtonLook() end
  return true
end

-- ---------------------------------------------------------------- the settings window
-- The settings window keeps its own locals in a block of its own.
local ToggleConfig
do
-- Drawn to match the game's own Options window, as ClearHits' is: near-black panels with thin
-- gold edges, gold labels, square checkboxes and dark red for what's selected.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local UI = {
  top = { 0.078, 0.059, 0.035, 0.90 }, bottom = { 0.031, 0.024, 0.016, 0.93 },   -- window shading
  well = { 0.012, 0.012, 0.008 },
  selTop = { 0.231, 0.051, 0.043 }, selBottom = { 0.102, 0.020, 0.020 },
  pressTop = { 0.227, 0.031, 0.024 }, pressBottom = { 0.133, 0.016, 0.016 },
  outer = { 0.427, 0.333, 0.145 }, dim = { 0.427, 0.333, 0.145 }, edge = { 0.690, 0.541, 0.227 },
  hot = { 0.973, 0.824, 0.416 }, panelEdge = { 0.169, 0.129, 0.071 },
  gold = { 0.973, 0.824, 0.416 }, title = { 0.973, 0.824, 0.416 }, chosen = { 1, 0.914, 0.659 },
  text = { 0.949, 0.902, 0.788 }, muted = { 0.725, 0.663, 0.510 },
}
local UI_FONT, TITLE_FONT = "Fonts\\FRIZQT__.TTF", "Fonts\\MORPHEUS.TTF"
local SCALE = 0.65   -- the sizes below are the game's Options window's; this brings them to screen size
local W = 620
local THICK = 1.25   -- buttons, checkboxes and panels have a heavier edge than the window
local CX = 230       -- where every control starts, clear of the longest label

local function Solid(f, layer, c)
  local t = f:CreateTexture(nil, layer)
  t:SetTexture(WHITE)
  t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  return t
end

-- shaded top to bottom, as the game's panels and red buttons are
local function Shade(t, top, bottom)
  t:SetVertexColor(1, 1, 1, top[4] or 1)
  if t.SetGradient then
    t:SetGradient("VERTICAL", bottom[1], bottom[2], bottom[3], top[1], top[2], top[3])
  else
    t:SetVertexColor(top[1], top[2], top[3], top[4] or 1)
  end
  -- this client's gradient keeps no see-through of its own; the texture's own alpha does
  t:SetAlpha(((top[4] or 1) + (bottom[4] or 1)) / 2)
end

-- A rounded rectangle from pieces that never overlap: a tall strip, two side bands and four
-- quarter circles (corner.tga, flipped for each corner). r = 0 gives a plain rectangle.
local MEDIA = "Interface\\AddOns\\BattleMarks\\media\\"
local CORNERS = {   -- point, x sign, y sign, texture coordinates
  { "TOPLEFT", 1, -1, 0, 1, 0, 1 }, { "TOPRIGHT", -1, -1, 1, 0, 0, 1 },
  { "BOTTOMLEFT", 1, 1, 0, 1, 1, 0 }, { "BOTTOMRIGHT", -1, 1, 1, 0, 1, 0 },
}
-- quarter rings for the edges' corners, by how much of the radius the edge is (ring08 ... ring50)
local RINGS = { 8, 16, 31, 40, 42, 50 }
local function RoundRect(f, layer, inset, r)
  local shape = { tall = Solid(f, layer, { 1, 1, 1 }) }
  if r <= 0 then
    shape.tall:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    shape.tall:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    return shape
  end
  shape.tall:SetPoint("TOPLEFT", f, "TOPLEFT", inset + r, -inset)
  shape.tall:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset - r, inset)
  shape.left = Solid(f, layer, { 1, 1, 1 })
  shape.left:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset - r)
  shape.left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset + r)
  shape.left:SetWidth(r)
  shape.right = Solid(f, layer, { 1, 1, 1 })
  shape.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset - r)
  shape.right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset + r)
  shape.right:SetWidth(r)
  shape.corners = {}
  for i, c in ipairs(CORNERS) do
    local t = f:CreateTexture(nil, layer)
    t:SetTexture(MEDIA .. "corner")
    t:SetTexCoord(c[4], c[5], c[6], c[7])
    t:SetWidth(r)
    t:SetHeight(r)
    t:SetPoint(c[1], f, c[1], c[2] * inset, c[3] * inset)
    shape.corners[i] = t
  end
  return shape
end

-- an edge of the given width around a rounded rectangle: four strips and the four corners
local function RoundRing(f, layer, width, r)
  local shape = { strips = {} }
  local cut = math.max(r, 0)
  local sides = {
    { "TOPLEFT", cut, 0, "TOPRIGHT", -cut, 0, "height" }, { "BOTTOMLEFT", cut, 0, "BOTTOMRIGHT", -cut, 0, "height" },
    { "TOPLEFT", 0, -cut, "BOTTOMLEFT", 0, cut, "width" }, { "TOPRIGHT", 0, -cut, "BOTTOMRIGHT", 0, cut, "width" },
  }
  for i, sd in ipairs(sides) do
    local t = Solid(f, layer, { 1, 1, 1 })
    t:SetPoint(sd[1], f, sd[1], sd[2], sd[3])
    t:SetPoint(sd[4], f, sd[4], sd[5], sd[6])
    if sd[7] == "height" then t:SetHeight(width) else t:SetWidth(width) end
    shape.strips[i] = t
  end
  if r > 0 then
    -- the ring image nearest this edge's share of the radius
    local share, best = width / r * 100, nil
    for _, pct in ipairs(RINGS) do
      if not best or math.abs(pct - share) < math.abs(best - share) then best = pct end
    end
    shape.corners = {}
    for i, c in ipairs(CORNERS) do
      local t = f:CreateTexture(nil, layer)
      t:SetTexture(MEDIA .. "ring" .. (best < 10 and "0" or "") .. best)
      t:SetTexCoord(c[4], c[5], c[6], c[7])
      t:SetWidth(r)
      t:SetHeight(r)
      t:SetPoint(c[1], f, c[1], 0, 0)
      shape.corners[i] = t
    end
  end
  return shape
end

-- colors a shape with one color, or shades it from a top color to a bottom one
local function Color(shape, c)
  local top, bottom = c.top or c, c.bottom or c
  for _, t in ipairs(shape.strips or { shape.tall, shape.left, shape.right }) do
    if c.top then
      Shade(t, top, bottom)
    else
      if t.SetGradient then t:SetGradient("VERTICAL", 1, 1, 1, 1, 1, 1) end
      t:SetAlpha(1)   -- a shaded look may have left its own see-through on the texture
      t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
  end
  if shape.corners then
    for i, t in ipairs(shape.corners) do
      local k = i <= 2 and top or bottom
      t:SetVertexColor(k[1], k[2], k[3], k[4] or 1)
    end
  end
end

-- a box with rounded corners and an edge around its background. Paint recolors either part.
local function Box(f, bg, edge, width, radius)
  width, radius = width or 1, radius or 0
  local b = { edge = RoundRing(f, "BACKGROUND", width, radius),
    fill = RoundRect(f, "BORDER", width, math.max(0, radius - width)) }
  b.Paint = function(bgc, edgec)
    if bgc then Color(b.fill, bgc) end
    if edgec then Color(b.edge, edgec) end
  end
  b.Paint(bg, edge)
  return b
end
local SELECTED = { top = UI.selTop, bottom = UI.selBottom }
local PRESSED = { top = UI.pressTop, bottom = UI.pressBottom }

local function Text(parent, size, color, font)
  local s = parent:CreateFontString(nil, "OVERLAY")
  s:SetFont(font or UI_FONT, size, "")
  s:SetShadowColor(0, 0, 0, 1)
  s:SetShadowOffset(1, -1)
  s:SetTextColor(color[1], color[2], color[3])
  return s
end

local cfg = CreateFrame("Frame", "BattleMarksConfig", UIParent)
cfg:SetWidth(W)
cfg:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
cfg:SetFrameStrata("DIALOG")
cfg:SetMovable(true)
cfg:SetClampedToScreen(true)
cfg:EnableMouse(true)
cfg:RegisterForDrag("LeftButton")
cfg:SetScript("OnDragStart", function() this:StartMoving() end)
cfg:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
cfg:SetScale(SCALE)
cfg:Hide()
table.insert(UISpecialFrames, "BattleMarksConfig")   -- Escape closes it
Box(cfg, { top = UI.top, bottom = UI.bottom }, UI.outer, 1, 12)

local title = Text(cfg, 36, UI.title, TITLE_FONT)
title:SetPoint("TOP", cfg, "TOP", 0, -14)
title:SetText("BattleMarks")

local panel = CreateFrame("Frame", nil, cfg)
panel:SetPoint("TOPLEFT", cfg, "TOPLEFT", 26, -69)
panel:SetPoint("BOTTOMRIGHT", cfg, "BOTTOMRIGHT", -26, 72)
Box(panel, { 0, 0, 0, 0.38 }, UI.panelEdge, THICK, 4)

-- the line along the bottom says what the setting under the mouse does
local help = Text(cfg, 13, UI.muted)
help:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -10)
help:SetWidth(W - 160)
help:SetHeight(50)
help:SetJustifyH("LEFT")
help:SetJustifyV("TOP")
local function Help(text) help:SetText(text or "Hover a setting to see what it does.") end

local function Hover(f, desc, onEnter, onLeave)
  f:SetScript("OnEnter", function()
    Help(type(desc) == "function" and desc() or desc)
    if onEnter then onEnter() end
  end)
  f:SetScript("OnLeave", function()
    Help(nil)
    if onLeave then onLeave() end
  end)
end

-- one column down the panel: headings and rows stack downward
local col = { y = -12, width = W - 52 }
local controls, grouped = {}, {}

local function Heading(text)
  if col.y < -12 then col.y = col.y - 8 end
  local h = Text(panel, 16, UI.title, TITLE_FONT)
  h:SetPoint("TOPLEFT", panel, "TOPLEFT", 15, col.y - 4)
  h:SetText(text)
  local line = Solid(panel, "ARTWORK", UI.dim)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", panel, "TOPLEFT", 15, col.y - 24)
  line:SetWidth(col.width - 30)
  col.y = col.y - 30
end

-- one setting: the gold label on the left, its control at CX
local function Row(label, desc, height)
  local row = CreateFrame("Frame", nil, panel)
  row:SetHeight(height or 30)
  row:SetWidth(col.width)
  row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, col.y)
  row:EnableMouse(true)
  col.y = col.y - (height or 30) - 2
  local l = Text(row, 14, UI.gold)
  l:SetPoint("LEFT", row, "LEFT", 15, 0)
  l:SetText(label)
  Hover(row, desc)
  return row
end

-- a checkbox; when, if given, greys the row out while it's false
local function Check(key, label, desc, onChange, when)
  local row = Row(label, desc)
  local b = CreateFrame("Button", "BattleMarksCheck_" .. key, row)
  b:SetWidth(21)
  b:SetHeight(21)
  b:SetPoint("LEFT", row, "LEFT", CX, 0)
  local box = Box(b, UI.well, UI.edge, THICK, 2.5)
  local mark = Solid(b, "ARTWORK", UI.hot)
  mark:SetPoint("TOPLEFT", b, "TOPLEFT", 4.25, -4.25)
  mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4.25, 4.25)
  Hover(b, desc, function() box.Paint(nil, UI.hot) end, function() box.Paint(nil, UI.edge) end)
  b:SetScript("OnClick", function()
    if row.off then return end
    db[key] = not db[key]
    if onChange then onChange() end
    Refresh()
  end)
  b.Refresh = function() if db[key] then mark:Show() else mark:Hide() end end
  table.insert(controls, b)
  if when then
    row.when = when
    table.insert(grouped, row)
  end
end

-- a row of the eight markers, each in a small box; look(i) says whether marker i is chosen and
-- whether it's drawn bright (true), dimmed (false) or darker still, taken elsewhere ("off").
-- when, if given, greys the row out while it's false
local function MarkerRow(label, desc, tip, onClick, look, when, number)
  local row = Row(label, desc, 36)
  if when then
    row.when = when
    table.insert(grouped, row)
  end
  local buttons = {}
  for n = 1, 8 do
    local i = n   -- Lua 5.0 keeps one loop variable for every pass: the closures below need their own
    local b = CreateFrame("Button", nil, row)
    b:SetWidth(32)
    b:SetHeight(32)
    b:SetPoint("LEFT", row, "LEFT", CX + (i - 1) * 37, 0)
    b.box = Box(b, UI.well, UI.dim, 1, 2.5)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
    b.icon:SetTexture(ICONS)
    MarkerCoords(b.icon, i)
    if number then
      -- which hero of the party wears it: 1 is you
      b.number = b:CreateFontString(nil, "OVERLAY")
      b.number:SetFont(UI_FONT, 12, "OUTLINE")
      b.number:SetTextColor(UI.chosen[1], UI.chosen[2], UI.chosen[3])
      b.number:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
    end
    b.index = i
    Hover(b, function() return tip(i) end,
      function() b.hot = true; b.Refresh() end, function() b.hot = nil; b.Refresh() end)
    b:SetScript("OnClick", function()
      if row.off then return end
      onClick(i)
      Refresh()
      Help(tip(i))
    end)
    b.Refresh = function()
      local chosen, bright = look(i)
      b.box.Paint(chosen and SELECTED or UI.well, (chosen or (b.hot and bright ~= "off")) and UI.hot or UI.dim)
      local v = bright == "off" and 0.15 or (bright and 1 or 0.35)
      b.icon:SetVertexColor(v, v, v)
      if b.number then b.number:SetText(number(i) or "") end
    end
    table.insert(controls, b)
    buttons[i] = b
  end
  return row
end

-- a row of buttons, one per choice ({ value, text, description }), the chosen one dark red
local function Choice(key, label, choices, desc, when)
  local row = Row(label, desc)
  if when then
    row.when = when
    table.insert(grouped, row)
  end
  local x = CX
  for _, c in ipairs(choices) do
    local value = c[1]
    local b = CreateFrame("Button", nil, row)
    local t = Text(b, 13, UI.gold)
    t:SetPoint("CENTER", b, "CENTER", 0, 0)
    t:SetText(c[2])
    local w = math.ceil(t:GetStringWidth()) + 18
    b:SetWidth(w)
    b:SetHeight(25)
    b:SetPoint("LEFT", row, "LEFT", x, 0)
    x = x + w + 5.5
    local box = Box(b, UI.well, UI.dim, 1, 2.5)
    Hover(b, c[3] or desc, function() if db[key] ~= value then box.Paint(nil, UI.edge) end end,
      function() if db[key] ~= value then box.Paint(nil, UI.dim) end end)
    b:SetScript("OnClick", function()
      if row.off then return end
      db[key] = value
      Refresh()
    end)
    b.Refresh = function()
      if db[key] == value then
        box.Paint(SELECTED, UI.hot)
        t:SetTextColor(UI.chosen[1], UI.chosen[2], UI.chosen[3])
      else
        box.Paint(UI.well, UI.dim)
        t:SetTextColor(UI.gold[1], UI.gold[2], UI.gold[3])
      end
    end
    table.insert(controls, b)
  end
end

-- a line of text to edit; emptying it gives back the default
local function MessageRow(key, default, label, desc, when)
  local row = Row(label, desc)
  if when then
    row.when = when
    table.insert(grouped, row)
  end
  local holder = CreateFrame("Frame", nil, row)
  holder:SetPoint("LEFT", row, "LEFT", CX, 0)
  holder:SetWidth(col.width - CX - 15)
  holder:SetHeight(25)
  local box = Box(holder, UI.well, UI.edge, 1, 2.5)
  local e = CreateFrame("EditBox", "BattleMarksText_" .. key, holder)
  e:SetPoint("TOPLEFT", holder, "TOPLEFT", 7, 0)
  e:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -7, 0)
  e:SetFont(UI_FONT, 13, "")
  e:SetTextColor(UI.text[1], UI.text[2], UI.text[3])
  e:SetAutoFocus(false)
  e:SetMaxLetters(200)
  local function Save()
    local text = e:GetText() or ""
    if string.gsub(text, "%s", "") == "" then text = default end
    db[key] = text
    e:SetText(text)
  end
  e:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  e:SetScript("OnEscapePressed", function() this:SetText(db[key]); this:ClearFocus() end)
  -- 1.12 edit boxes can't say whether they have the focus, so it's kept here
  e:SetScript("OnEditFocusLost", function()
    e.typing = nil
    Save()
    box.Paint(nil, UI.edge)
  end)
  e:SetScript("OnEditFocusGained", function()
    if row.off then this:ClearFocus(); return end
    e.typing = true
    box.Paint(nil, UI.hot)
  end)
  e:SetScript("OnTextChanged", function() if e.typing then db[key] = this:GetText() end end)
  Hover(e, desc)
  e:SetScript("OnHide", function() this:ClearFocus() end)
  holder.Refresh = function()
    if not e.typing then e:SetText(db[key]) end
  end
  table.insert(controls, holder)
end

-- a red button inside a row, doing one thing
local function RowButton(row, text, x, desc, onClick)
  local b = CreateFrame("Button", nil, row)
  local t = Text(b, 13, UI.gold)
  t:SetPoint("CENTER", b, "CENTER", 0, 0)
  t:SetText(text)
  local w = math.ceil(t:GetStringWidth()) + 18
  b:SetWidth(w)
  b:SetHeight(25)
  b:SetPoint("LEFT", row, "LEFT", x, 0)
  local box = Box(b, SELECTED, UI.edge, 1, 2.5)
  Hover(b, desc, function() box.Paint(nil, UI.hot) end, function() box.Paint(nil, UI.edge) end)
  b:SetScript("OnMouseDown", function() box.Paint(PRESSED) end)
  b:SetScript("OnMouseUp", function() box.Paint(SELECTED) end)
  b:SetScript("OnClick", onClick)
  return x + w + 5.5
end

Heading("General")
Check("enabled", "BattleMarks on", "Marks every hero of a co-op party, you included, when the match loads, and bosses and guardians as set below.", function()
  if not db.enabled then passes = {} end
  ButtonLook()
end)
Check("button", "Minimap button", "Shows the BattleMarks button on the minimap. /bmarks always opens this window.", function()
  ButtonShown()
  if not db.button then Print("minimap button hidden: /bmarks opens the settings.") end
end)
Check("bossesSolo", "Solo", "Marks bosses and guardians when you play alone too, not only in a party.")

-- turning bosses or guardians on takes their markers back from the party
local function FreeMine()
  ClearConflicts()
  users[Me()] = db.mine
  Hello(false)
end
local function AnyBoss() return db.markBosses or db.markGuardians end
local function BothKinds() return db.markBosses and db.markGuardians end

-- One row of the eight markers for numbered slots. A click on a free marker gives it the lowest
-- empty number; a click on a numbered one lets that number go. elsewhere(i) says why marker i
-- can't be picked here, if it can't.
local function SlotRow(label, desc, slots, max, elsewhere, onChange, when)
  local function SlotOf(i)
    for n = 1, max do
      if slots()[n] == i then return n end
    end
  end
  local function Empty()
    for n = 1, max do
      if not slots()[n] then return n end
    end
  end
  MarkerRow(label, desc, function(i)
    local why = elsewhere(i)
    if why then return Title(NAMES[i]) .. ": " .. why end
    local n, free = SlotOf(i), Empty()
    if n then return Title(NAMES[i]) .. ": number " .. n .. ". Click to let it go." end
    if free then return Title(NAMES[i]) .. ": click to make it number " .. free .. "." end
    return Title(NAMES[i]) .. ": all " .. max .. " numbers are taken. Click a numbered marker to free one."
  end, function(i)
    if elsewhere(i) then return end
    local n = SlotOf(i)
    if n then
      slots()[n] = nil
    else
      local free = Empty()
      if not free then return end
      slots()[free] = i
    end
    onChange()
  end, function(i)
    if elsewhere(i) then return false, "off" end
    local n = SlotOf(i)
    return n ~= nil, n ~= nil
  end, when, function(i)
    local n = SlotOf(i)
    return n and tostring(n)
  end)
end

Heading("Bosses / Guardians")
Check("markBosses", "Bosses", "Puts the markers below on bosses: the final boss first, then the others in the order they came. A marker goes up once someone targets or hovers over the boss.", FreeMine)
Check("markGuardians", "Guardians", "Puts the markers below on awake guardians. The game only tells a guardian apart for your own target, so a guardian is marked once you target it.", FreeMine)
Choice("guardiansFirst", "Priority", {
  { false, "Bosses first", "Bosses first: bosses get the markers; guardians only when no boss is up." },
  { true, "Guardians first", "Guardians first: awake guardians get the markers; bosses only when no guardian is awake." },
}, "Which kind gets the markers when bosses and guardians are up at once.", BothKinds)
Check("fillGaps", "Fill empty markers", "With fewer of the first kind up than markers, the markers left over go to the other kind instead of waiting, like a guardian beside a lone boss.", nil, BothKinds)
SlotRow("Markers", "1 goes to the top boss or guardian, 2 to the next, and so on, up to all eight; any more wait unmarked. When one dies, the ones after it move up. Click a marker to number it, click a numbered one to let it go.",
  function() return db.bossMarks end, BOSS_MAX, function(i)
    for n = 1, PARTY_MAX do
      if db.partyMarks[n] == i then return "used by the party. Let it go under Party / Self to use it here." end
    end
  end, function()
    ResetBossMarks()
    FreeMine()
  end, AnyBoss)

Heading("Party / Self")
SlotRow("Markers", "1 is you; 2 to 5 are your teammates, in party order. A number left empty marks no one, so leave 1 empty to go unmarked, or use none to mark bosses only. Click a marker to number it, click a numbered one to let it go.",
  function() return db.partyMarks end, PARTY_MAX, function(i)
    if Reserved(i) then return "used for Bosses / Guardians. Let it go there to use it here." end
  end, function()
    db.mine = db.partyMarks[1]
    users[Me()] = db.mine
    Hello(false)
  end)
Check("selfSolo", "Self when solo", "Puts your marker, number 1, on you when you start a run alone too, not only in a party.")
local partyRow = Row("Markers now", "Sets or clears the heroes' markers by hand. They also go up by themselves when a co-op match loads.")
local x = RowButton(partyRow, "Set markers", CX, "Puts a marker on every hero of your party now.", function()
  if GetNumPartyMembers() == 0 and not db.selfSolo then Print("you're not in a party (turn on Self when solo to mark yourself)."); return end
  users[Me()] = db.mine
  Apply(false)
end)
RowButton(partyRow, "Clear markers", x, "Takes every hero's marker off.", function() Clear() end)
local who = Text(panel, 13, UI.text)
who:SetPoint("TOPLEFT", panel, "TOPLEFT", 15, col.y - 6)
who:SetWidth(col.width - 30)
who:SetJustifyH("LEFT")
col.y = col.y - 34

Heading("Communication")
Check("announce", "Party Markers", "Says in party chat who has which marker when the match starts, and names heroes who join later.")
MessageRow("announceText", SAY_MARKERS, "Message", "What the party is told. {markers} becomes the list, like Eric = Star, Bob = Circle. Empty it to get the default back.",
  function() return db.announce end)
Check("announceBossMarks", "Boss Markers", "Also says which markers the bosses and guardians get, once when the match starts.", nil, AnyBoss)
MessageRow("bossText", SAY_BOSSES, "Message", "What the party is told about the bosses' markers. {first} and {second} become the markers, like Skull and Cross; {kind} becomes boss, guardian or boss or guardian, as set above. Empty it to get the default back.",
  function() return db.announceBossMarks and AnyBoss() end)

-- the panel is as tall as what's in it
cfg:SetHeight(69 + (12 - col.y) + 72)

local function BigButton(text, x, width, onClick)
  local b = CreateFrame("Button", nil, cfg)
  b:SetWidth(width)
  b:SetHeight(34)
  b:SetPoint("BOTTOMRIGHT", cfg, "BOTTOMRIGHT", x, 21)
  local box = Box(b, SELECTED, UI.edge, THICK, 3)
  local t = Text(b, 15, UI.gold)
  t:SetPoint("CENTER", b, "CENTER", 0, 0)
  t:SetText(text)
  b:SetScript("OnEnter", function() box.Paint(nil, UI.hot) end)
  b:SetScript("OnLeave", function() box.Paint(SELECTED, UI.edge) end)
  b:SetScript("OnMouseDown", function() box.Paint(PRESSED) end)
  b:SetScript("OnMouseUp", function() box.Paint(SELECTED) end)
  b:SetScript("OnClick", onClick)
  return b
end
BigButton("Done", -26, 76, function() cfg:Hide() end)

Refresh = function()
  if not db or not cfg:IsShown() then return end
  for i = 1, table.getn(controls) do controls[i].Refresh() end
  for _, row in ipairs(grouped) do
    row.off = not row.when()
    row:SetAlpha(row.off and 0.35 or 1)
  end
  if GetNumPartyMembers() == 0 then
    who:SetText("Not in a party right now. Markers go up when a co-op match loads.")
  else
    local d = Decider()
    who:SetText("In this party the markers are set by " .. (d == Me() and "you" or ("|cffffffff" .. tostring(d) .. "|r"))
      .. (d ~= Me() and d and " (they run BattleMarks too; your chosen marker is honoured)." or "."))
  end
end
cfg:SetScript("OnShow", function()
  Help(nil)
  Refresh()
end)
-- the party can change while the window is open
local cfgTick = 0
cfg:SetScript("OnUpdate", function()
  cfgTick = cfgTick + arg1
  if cfgTick < 1 then return end
  cfgTick = 0
  Refresh()
end)

function ToggleConfig()
  if cfg:IsShown() then cfg:Hide() else cfg:Show() end
end
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
    if GetNumPartyMembers() == 0 and not db.selfSolo then Print("you're not in a party (turn on Self when solo to mark yourself)."); return end
    users[Me()] = db.mine
    local n = Apply(false)
    Print("markers set (" .. n .. " changed).")
  elseif cmd == "clear" then
    Clear()
    Print("markers cleared.")
  elseif cmd == "" then
    ToggleConfig()
  elseif cmd == "status" then
    local kinds = db.markBosses and (db.markGuardians and "bosses and guardians" or "bosses")
      or (db.markGuardians and "guardians" or nil)
    local marks = Compact(db.bossMarks, BOSS_MAX)
    for n = 1, table.getn(marks) do marks[n] = Marker(marks[n]) end
    Print((db.enabled and "on" or "off") .. ", your marker: " .. (db.mine and Marker(db.mine) or "none") .. ", "
      .. (kinds and (kinds .. ": " .. (marks[1] and table.concat(marks, " and ") or "no markers")
        .. (db.bossesSolo and ", solo too" or ", in a party")) or "bosses and guardians: off")
      .. ", party chat: " .. (db.announce and "on" or "off") .. ".")
    if GetNumPartyMembers() > 0 then
      local d = Decider()
      Print("in this party the markers are set by " .. (d == Me() and "you" or tostring(d)) .. ".")
    end
  else
    Print("commands: /bmarks (settings), /bmarks me <marker>, /bmarks on|off, /bmarks now, /bmarks clear, /bmarks status, /bmarks button")
  end
end
