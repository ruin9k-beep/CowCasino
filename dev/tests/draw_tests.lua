-- Five-Card Draw (solo): five seats, five cards, a first betting round, the
-- draw (up to three cards, four with an Ace), a second round and a showdown;
-- chips are never made or lost, and a seat survives a reload.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-66s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end
local function Start(saved)
  local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
  env.arg = { ADDON }; env.SELECT_SAVED = select
  assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
  env.CowCasinoDB = saved
  for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
  env.CowCasinoFrame:Show()
  return env, env.CowCasino.ns
end
math.randomseed(11)
local env, ns = Start(nil)
local PANEL
local function Visible(o)
  local inPanel = PANEL == nil
  while o do if not o.shown then return false end; if o == PANEL then inPanel = true end; o = o.parent end
  return inPanel
end
local function Find(text, prefix)
  for _, o in ipairs(env.all) do
    if o.kind == "Button" and Visible(o) and type(o.text) == "string"
      and (o.text == text or (prefix and string.sub(o.text, 1, string.len(text)) == text)) then return o end
  end
end
local function Enabled(text, prefix) local b = Find(text, prefix); return b ~= nil and b.enabled ~= nil end
local function Press(text, prefix) local b = assert(Find(text, prefix), "no " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end
local function Tick(sec) for _ = 1, math.floor(sec * 10 + 0.5) do env.CLOCK = env.CLOCK + 0.1; for _, o in ipairs(env.all) do if o.scripts.OnUpdate and not o.parent and o.shown then env.Fire(o, "OnUpdate", 0.1) end end end end
local function C(rank, suit) return { rank = rank, suit = suit or 1 } end

ns.db.chips = 5000
ns:OpenGame("draw")
local P = ns.games.draw
local T = P.T
PANEL = P.panel
P.SetSims(30)
Check("Five-Card Draw is in the game list", P ~= nil and P.name == "Five-Card Draw")

-- The computer players' draw
local function Set(t) local s = {} for _, i in ipairs(t) do s[i] = true end return s end
local function Same(a, b) for i = 1, 5 do if (a[i] or false) ~= (b[i] or false) then return false end end return true end
local function Show(s) local t = {} for i = 1, 5 do if s[i] then table.insert(t, i) end end return table.concat(t, ",") end
local D = P.Discards
local d = D({ C(1, 1), C(5, 2), C(9, 3), C(9, 4), C(13, 1) })
Check("bots keep a pair and swap three", Same(d, Set({ 1, 2, 5 })), Show(d))
d = D({ C(4, 1), C(4, 2), C(4, 3), C(9, 4), C(13, 1) })
Check("...keep trips and swap two", Same(d, Set({ 4, 5 })), Show(d))
d = D({ C(4, 1), C(4, 2), C(9, 3), C(9, 4), C(13, 1) })
Check("...keep two pair and swap the kicker", Same(d, Set({ 5 })), Show(d))
d = D({ C(2, 3), C(7, 3), C(9, 3), C(12, 3), C(13, 1) })
Check("...draw one to a flush", Same(d, Set({ 5 })), Show(d))
d = D({ C(5, 1), C(6, 2), C(7, 3), C(8, 4), C(13, 1) })
Check("...draw one to an open straight", Same(d, Set({ 5 })), Show(d))
d = D({ C(5, 1), C(6, 2), C(7, 3), C(8, 4), C(9, 1) })
Check("...stand pat on a straight", Same(d, {}), Show(d))
d = D({ C(1, 1), C(4, 2), C(7, 3), C(9, 4), C(13, 2) })
Check("...with nothing, keep an Ace and draw four", Same(d, Set({ 2, 3, 4, 5 })), Show(d))
d = D({ C(2, 1), C(4, 2), C(7, 3), C(9, 4), C(13, 2) })
Check("...or keep the two highest and draw three", Same(d, Set({ 1, 2, 3 })), Show(d))

-- Sit down: you and four computer players, five cards each
local lobbyBuy
for _, o in ipairs(env.all) do if o.kind == "Button" and Visible(o) and o.text == "500" then lobbyBuy = o end end
Check("buy-ins scale with the blinds (5/10: 200, 500, 1,000)", Find("200") ~= nil and lobbyBuy ~= nil and Find("1,000") ~= nil)
Press("1,000")
Tick(0.1)
local seated = 0
for _, p in ipairs(T.seats) do if p.kind ~= "empty" then seated = seated + 1 end end
Check("five seats: you and four computer players", table.getn(T.seats) == 5 and seated == 5 and T.seats[2].kind == "bot")
local bots1000 = true
for i = 2, 5 do if T.seats[i].stack + T.seats[i].total ~= 1000 then bots1000 = false end end
Check("...each starting with your buy-in", bots1000)
Check("everyone has five cards", table.getn(T.seats[1].hole) == 5 and table.getn(T.seats[3].hole) == 5)
Check("the first betting round is on", T.street == "first", T.street)
local myCards = 0
for _, w in ipairs(P.ui.seats[1].cards) do if w.shown ~= false then myCards = myCards + 1 end end

-- Play the first round by calling until the draw comes round to you.
local function TOTAL()
  local t = T.pot
  for _, p in ipairs(T.seats) do t = t + p.stack + p.bet end
  return t
end
local startTotal = TOTAL()
local guard = 0
while T.street ~= "draw" and T.street ~= "idle" and guard < 400 do
  guard = guard + 1
  if Enabled("Call", true) then Press("Call", true) elseif Enabled("Check") then Press("Check") end
  Tick(0.5)
end
Check("after the first round: the draw", T.street == "draw", T.street)
guard = 0
while T.street == "draw" and T.actor ~= 1 and guard < 100 do guard = guard + 1; Tick(0.5) end
local me = T.seats[1]
if T.street == "draw" and not me.folded then
  Check("your turn to draw: Stand pat until you pick cards", Enabled("Stand pat"))
  -- picking four without an Ace isn't allowed; three is
  local picks = P.ui.seats[1].picks
  local hasAce = false
  for _, c in ipairs(me.hole) do if c.rank == 1 then hasAce = true end end
  for c = 1, 4 do env.Fire(picks[c], "OnClick", "LeftButton") end
  local fourOk = Enabled("Draw 4")
  local keepsAce = me.hole[5].rank == 1
  Check("four cards only when the one kept is an Ace", fourOk == keepsAce, tostring(fourOk))
  Check("...the picked cards are marked", picks[1].mark.shown ~= false and picks[4].mark.shown ~= false)
  env.Fire(picks[4], "OnClick", "LeftButton")      -- unpick: three
  Check("three picked: Draw 3", Enabled("Draw 3"))
  local before = { me.hole[1], me.hole[2], me.hole[3], me.hole[4], me.hole[5] }
  Press("Draw 3")
  local changed = 0
  for c = 1, 3 do if me.hole[c] ~= before[c] then changed = changed + 1 end end
  Check("the three picked cards are swapped, the rest kept", changed == 3 and me.hole[4] == before[4] and me.hole[5] == before[5])
  Check("...and the table sees 'Draws 3'", me.last == "Draws 3", me.last)
  Check("five cards still", table.getn(me.hole) == 5)
else
  Check("(you were still in at the draw)", false, T.street)
end
guard = 0
while T.street == "draw" and guard < 100 do guard = guard + 1; Tick(0.5) end
local botsDrew = true
for i = 2, 5 do local p = T.seats[i]; if not p.folded and not p.out and not p.drew then botsDrew = false end end
Check("every player still in drew (or stood pat)", botsDrew)
Check("then the second round of betting (or the showdown)", T.street == "second" or T.street == "idle", T.street)
guard = 0
while T.street ~= "idle" and guard < 400 do
  guard = guard + 1
  if Enabled("Call", true) then Press("Call", true) elseif Enabled("Check") then Press("Check") end
  Tick(0.5)
end
Check("the hand ends", T.street == "idle")
local winners = 0
for _, p in ipairs(T.seats) do if (p.won or 0) > 0 then winners = winners + 1 end end
Check("somebody won it", winners >= 1)
Check("no chips made or lost", TOTAL() == startTotal, TOTAL() .. " vs " .. startTotal)

-- Many hands, every action at random: chips are kept, nothing gets stuck
-- (each hand is measured from its deal, after busted bots are replaced)
local hands, stuck, leak = 0, false, nil
local dealt = nil
for _ = 1, 3000 do
  if T.street == "idle" then
    if dealt and leak == nil and TOTAL() ~= dealt then leak = "hand " .. hands .. ": " .. TOTAL() .. " vs " .. dealt end
    dealt = nil
    if T.seats[1].stack <= 0 then
      ns.db.chips = math.max(ns.db.chips, 1000)
      Press("Leave table"); Press("1,000")
    else
      Press("Deal")
    end
    hands = hands + 1
    dealt = TOTAL()
  end
  if T.street == "draw" and T.actor == 1 then
    local picks = P.ui.seats[1].picks
    for c = 1, 5 do if math.random() < 0.4 then env.Fire(picks[c], "OnClick", "LeftButton") end end
    local b = Find("Draw", true) or Find("Stand pat")
    if b and b.enabled then env.Fire(b, "OnClick", "LeftButton")
    else for c = 1, 5 do if T.discard[c] then env.Fire(picks[c], "OnClick", "LeftButton") end end; Press("Stand pat") end
  elseif Enabled("Fold") then
    local r = math.random()
    if r < 0.15 then Press("Fold")
    elseif r < 0.3 and Enabled("Raise", true) then Press("Raise", true)
    elseif r < 0.3 and Enabled("Bet", true) then Press("Bet", true)
    elseif Enabled("Call", true) then Press("Call", true) elseif Enabled("All-in", true) then Press("All-in", true)
    elseif Enabled("Check") then Press("Check") end
  end
  Tick(0.5)
  if hands >= 40 then break end
end
Check("40 hands at random play out", hands >= 40, hands)
Check("...without making or losing chips", leak == nil, leak)

-- Reload mid-hand: canceled, everyone's chips back
while T.street ~= "idle" do Tick(0.5); if Enabled("Check") then Press("Check") elseif Enabled("Call", true) then Press("Call", true) end
  if T.street == "draw" and T.actor == 1 and Enabled("Stand pat") then Press("Stand pat") end end
if T.seats[1].stack <= 0 then ns.db.chips = math.max(ns.db.chips, 1000); Press("Leave table"); Press("1,000") else Press("Deal") end
local stacksBefore = {}
for i, p in ipairs(T.seats) do stacksBefore[i] = p.stack + p.total end
local saved = env.CowCasinoDB
local env2, ns2 = Start(saved)
ns2:OpenGame("draw")
local T2 = ns2.games.draw.T
local same = table.getn(T2.seats) == 5
for i = 1, 5 do if not T2.seats[i] or T2.seats[i].stack ~= stacksBefore[i] then same = false end end
Check("a reload mid-hand cancels it: same five seats, stacks as before the hand", same and T2.street == "idle")

io.write(ok and "DRAW PASS\n" or "DRAW FAIL\n")
os.exit(ok and 0 or 1)
