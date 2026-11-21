-- Battleship: the rules (fleets, answers, the fingerprint), the computer's
-- three levels, a game against the computer (placing, firing, winning,
-- a reload), and party games between isolated clients (secret fleets, the
-- end-of-game fleet check catching a liar, a reload catching up).
local H = dofile("harness.lua")
local Check = H.Check

local function Copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Copy(v) end
  return out
end

local env, ns = H.Start(nil)
local R = ns.BattleshipRules

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
local good = true
for _ = 1, 60 do
  local f = R.RandomFleet()
  local back = R.DecodeFleet(R.EncodeFleet(f))
  if not (R.Complete(f) and back and R.EncodeFleet(back) == R.EncodeFleet(f)) then good = false end
  local cells = 0
  for s = 1, 100 do if R.ShipAt(f, s) then cells = cells + 1 end end
  if cells ~= 17 then good = false end
end
Check("random fleets: five ships, 17 squares, no overlaps, and they survive encoding", good)
local f = { { start = 1, down = false }, { start = 21, down = false }, { start = 41, down = false },
            { start = 61, down = false }, { start = 81, down = false } }
Check("ships can't hang off the edge or overlap", R.Fits(f, 1, 7, false) == nil and R.Fits(f, 2, 3, true) == nil
  and R.Fits(f, 5, 99, false) ~= nil)
Check("a fleet that overlaps is refused when decoded", R.DecodeFleet("1a,1d,41a,61a,81a") == nil)
local hits = {}
Check("a shot at open water is a miss", R.Answer(f, hits, 100) == "m")
Check("a shot at a ship is a hit", R.Answer(f, hits, 81) == "h")
hits[81] = true
local res = R.Answer(f, hits, 82)
local kind, k, ship = R.Parse(res)
Check("the last square of a ship sinks it, and says which and where", kind == "s" and k == 5 and ship.start == 81, res)
for s = 1, 100 do if R.ShipAt(f, s) and s ~= 3 then hits[s] = true end end
Check("sinking the last ship wins", string.sub(R.Answer(f, hits, 3), 1, 1) == "w")
Check("squares are named A1..J10", R.Name(1) == "A1" and R.Name(100) == "J10" and R.Name(17) == "B7")
local h1, h2 = R.Hash("1a,21a/123"), R.Hash("1a,21a/124")
Check("the fingerprint is the same for the same fleet, different for another", h1 == R.Hash("1a,21a/123") and h1 ~= h2
  and string.len(h1) == 16)

-- the computer
local function Hunt(level, fleet)
  local shots, sunk, hit, n = {}, {}, {}, 0
  while n < 100 do
    local s = R.ChooseShot({ shots = shots, sunk = sunk }, level)
    assert(not shots[s], "fired twice at " .. s)
    local res = R.Answer(fleet, hit, s)
    shots[s] = res; n = n + 1
    if res ~= "m" then hit[s] = true end
    local kd, kk = R.Parse(res)
    if kd == "s" or kd == "w" then sunk[kk] = true end
    if kd == "w" then return n end
  end
  return n
end
math.randomseed(11)
local total = { 0, 0, 0 }
for _ = 1, 12 do
  local fleet = R.RandomFleet()
  for lvl = 1, 3 do total[lvl] = total[lvl] + Hunt(lvl, fleet) end
end
local avg = { total[1] / 12, total[2] / 12, total[3] / 12 }
Check("Easy, Medium and Hard each sink a fleet without firing twice at a square", avg[1] > 0 and avg[3] > 0)
Check("...and each level needs fewer shots than the one below", avg[3] < avg[2] and avg[2] < avg[1],
  string.format("%.0f / %.0f / %.0f shots", avg[1], avg[2], avg[3]))
local view = { shots = { [45] = "h" }, sunk = {} }
local t = R.ChooseShot(view, 2)
Check("after a hit, Medium fires next to it", t == 35 or t == 55 or t == 44 or t == 46, t)
view = { shots = { [45] = "h", [46] = "h", [44] = "m" }, sunk = {} }
t = R.ChooseShot(view, 3)
Check("Hard follows a line of hits", t == 47, t)

---------------------------------------------------------------------------
-- Against the computer
---------------------------------------------------------------------------
ns:OpenGame("battleship")
local G = ns.games.battleship
local function Click(s) env.Fire(G.ui.squares[s], "OnClick", "LeftButton") end
local function Parts()
  local n = 0
  for s = 1, 100 do if G.ui.squares[s].piece.shown then n = n + 1 end end
  return n
end
Check("Battleship is on the menu with a 10 x 10 board", G.icon ~= nil and G.ui.squares[100] ~= nil and G.ui.squares[101] == nil)
local before = ns.db.chips
H.Press("Play for 50")
local g = G.S.game
Check("Play takes the stake and starts with your fleet placed at random", g and g.phase == "place"
  and ns.db.chips == before - 50 and Parts() == 17 and H.Find("Ready") ~= nil and H.Find("Ready").enabled)
local first = g.fleet[1].start
Click(first)
Check("clicking a ship picks it up (Ready waits until it's back)", G.S.pick == 1 and Parts() == 12
  and not H.Find("Ready").enabled and H.Find("Turn").enabled)
local blocked = g.fleet[2].start
Click(blocked)
Check("it won't go down on top of another ship", G.S.pick == 1)
H.Press("Turn")
local spot
for s = 1, 100 do
  if R.Fits(g.fleet, 1, s, G.S.down) then spot = s break end
end
G:Hover(spot)
Check("hovering shows where it would go, in green", G.ui.squares[spot].mark.shown)
Click(spot)
Check("...and a click puts it there", G.S.pick == nil and g.fleet[1].start == spot and Parts() == 17)
H.Press("Shuffle")
Check("Shuffle deals a new fleet", R.Complete(g.fleet) and Parts() == 17)
H.Press("Ready")
Check("Ready: the battle starts, the computer's fleet hidden", g.phase == "play" and g.cfleet ~= nil and Parts() == 0)

-- a shot each way (you fire first: the default)
local target
for s = 1, 100 do if not R.ShipAt(g.cfleet, s) then target = s break end end
Click(target)
Check("firing marks the square while the answer comes", g.pending ~= nil and G.ui.squares[target].mark.shown)
H.Tick(0.5)
Check("...a miss shows a splash", g.events[1] and g.events[1].res == "m" and G.ui.squares[target].top.shown)
H.Tick(1.5)
Check("then the computer fires back, onto your small board", table.getn(g.events) == 2 and g.events[2].by == "b")
Click(target)
Check("you can't fire at the same square twice", g.pending == nil)

-- board colors: your ships green by default, set in Options > Settings
local mine
for sq = 1, 100 do if R.ShipAt(g.fleet, sq) and sq ~= g.events[2].sq then mine = sq break end end
local function Near(c, r, gr, b) return c and math.abs(c[1] - r) < 0.01 and math.abs(c[2] - gr) < 0.01 and math.abs(c[3] - b) < 0.01 end
local shotAt = G.ui.mini[g.events[2].sq].color
Check("your ships are green on the small board; their shots red or pale blue", Near(G.ui.mini[mine].color, 0.25, 0.78, 0.30)
  and (Near(shotAt, 0.95, 0.20, 0.10) or Near(shotAt, 0.85, 0.92, 1.00)))
H.Press("Options")
H.Press("Settings")
local steps = G.ui.options.colorSteps
Check("Options > Settings: a color for water, your ships, their hits and their misses", steps and table.getn(steps) == 4
  and steps[2].part == "ships" and H.Visible(steps[2]))
env.Fire(steps[2].up, "OnClick", "LeftButton")
Check("changing your ships' color repaints the small board", ns.db.battleship.colors.ships == "lime"
  and Near(G.ui.mini[mine].color, 0.62, 0.95, 0.20))
env.Fire(steps[1].up, "OnClick", "LeftButton")
Check("...navy water on the big board", ns.db.battleship.colors.water == "navy" and Near(G.ui.squares[1].bg.color, 0.06, 0.13, 0.32))
H.Press("Default colors")
Check("Default colors puts them back", ns.db.battleship.colors == nil and Near(G.ui.mini[mine].color, 0.25, 0.78, 0.30))
Check("...and the Resign wait is on the same tab, under the colors", G.ui.options.resignStep ~= nil
  and G.ui.options.resignStep.text.text == "3 seconds")
H.Press("Options")

-- a reload carries the game on
local saved = Copy(env.CowCasinoDB)
local env2, ns2 = H.Start(saved)
ns2:OpenGame("battleship")
local g2 = ns2.games.battleship.S.game
Check("after a reload the battle is still on, fleets and shots intact", g2 and g2.phase == "play"
  and table.getn(g2.events) == 2 and ns2.R == nil and R.EncodeFleet(g2.cfleet) == R.EncodeFleet(g.cfleet))

-- sink them all
before = ns.db.chips
for s = 1, 100 do
  if G.S.game and R.ShipAt(g.cfleet, s) then
    Click(s)
    H.Tick(0.5)
    H.Tick(1.5)
  end
end
Check("sinking the whole fleet wins and pays double", G.S.game == nil and G.db.stats.wins == 1
  and ns.db.chips == before + 100, ns.db.chips - before)
Check("...and the computer's fleet is shown", G.S.over.theirFleet ~= nil and Parts() == 17)

H.Press("Play for 50")
H.Press("Resign"); H.Tick(3.1); H.Press("Confirm")
Check("Resign (even while placing) loses the stake", G.S.game == nil and G.db.stats.losses == 1)

---------------------------------------------------------------------------
-- Party games
---------------------------------------------------------------------------
local party = H.Party({ game = "battleship", object = function(ns) return ns.games.battleship end, button = "Party game" })
local clients = party.clients
local NewClient, GroupChanged, Run = party.NewClient, party.GroupChanged, party.Run

local function InPanel(c, o)
  local root = c.P.panel
  while o do
    if not o.shown then return false end
    if o == root then return true end
    o = o.parent
  end
  return false
end
local function PressIn(c, text)
  for _, o in ipairs(c.env.all) do
    if o.kind == "Button" and InPanel(c, o) and o.text == text then
      assert(o.enabled, c.name .. ": button disabled: " .. text)
      c.env.Fire(o, "OnClick", "LeftButton")
      return
    end
  end
  error(c.name .. ": no button " .. text)
end
local function Shoot(c, s) c.env.Fire(c.P.ui.squares[s], "OnClick", "LeftButton"); Run(1) end
local function Drop(c) for i, x in ipairs(clients) do if x == c then table.remove(clients, i) end end end

party.group = { "Host", "Guest" }
local host = NewClient("Host")
local guest = NewClient("Guest")
GroupChanged()
local function NewGame()
  PressIn(host, "Challenge the group")
  Run(1)
  PressIn(guest, "Accept")
  Run(1)
  return host.P.S.game, guest.P.S.game
end
local hg, gg = NewGame()
Check("a challenge taken: both sides start placing (Host fires first)", hg and gg and hg.phase == "place"
  and gg.phase == "place" and hg.me == "a" and gg.me == "b")
PressIn(host, "Ready")
Run(1)
Check("one side Ready waits for the other", hg.phase == "place" and hg.ready and gg.theirCommit ~= nil)
PressIn(guest, "Ready")
Run(1)
Check("both Ready: the battle starts on both sides", hg.phase == "play" and gg.phase == "play")
Check("each side only ever got the other's fingerprint, not its fleet", hg.theirFleet == nil and gg.theirFleet == nil
  and string.len(hg.theirCommit) == 16)

-- play it out: Host aims at Guest's ships, Guest fires at the corners of nowhere
local gShips, gMiss = {}, {}
for s = 1, 100 do
  if R.ShipAt(gg.fleet, s) then table.insert(gShips, s) end
  if not R.ShipAt(hg.fleet, s) then table.insert(gMiss, s) end
end
local i = 0
while host.P.S.game and i < 40 do
  i = i + 1
  Shoot(host, gShips[i])
  if guest.P.S.game then Shoot(guest, gMiss[i]) end
end
Check("shots and answers go both ways until Host sinks the lot", host.P.S.game == nil and guest.P.S.game == nil
  and host.P.db.stats.wins == 1 and guest.P.db.stats.losses == 1)
Check("party games are free", host.ns.db.chips == 5000 and guest.ns.db.chips == 5000)
Run(1)
Check("at the end each side sees the other's fleet...", host.P.S.over.theirFleet ~= nil and guest.P.S.over.theirFleet ~= nil)
Check("...and the fleet check passes both ways", string.find(host.P.ui.status.text, "match every answer", 1, true) ~= nil
  and string.find(guest.P.ui.status.text, "match every answer", 1, true) ~= nil, host.P.ui.status.text)

-- a liar: Guest's client answers "miss" to everything
hg, gg = NewGame()
PressIn(host, "Ready"); Run(1)
PressIn(guest, "Ready"); Run(1)
local realAnswer = guest.ns.BattleshipRules.Answer
guest.ns.BattleshipRules.Answer = function(fleet, hits, s) return "m" end
gShips = {}
for s = 1, 100 do if R.ShipAt(gg.fleet, s) then table.insert(gShips, s) end end
Shoot(host, gShips[1])
Check("(the lie goes unnoticed while the game's on)", hg.events[1].res == "m")
Shoot(guest, gMiss[1])
PressIn(guest, "Resign"); Run(3.1); PressIn(guest, "Confirm"); Run(1)
guest.ns.BattleshipRules.Answer = realAnswer
Check("but at the end the fleet check catches it", host.P.S.game == nil
  and string.find(host.P.ui.status.text, "Fleet check failed", 1, true) ~= nil, host.P.ui.status.text)

-- a reload in the middle: a shot fired while one side was away gets answered
hg, gg = NewGame()
PressIn(host, "Ready"); Run(1)
PressIn(guest, "Ready"); Run(1)
Shoot(host, 1)
Shoot(guest, 1)
local gsaved = Copy(guest.env.CowCasinoDB)
Drop(guest)
Shoot(host, 2)                       -- the guest is away: no answer yet
Check("(a shot at someone away waits for its answer)", hg.pending ~= nil)
guest = NewClient("Guest", gsaved)
Run(2)
gg = guest.P.S.game
Check("after the reload the game is still on, and the waiting shot is answered", gg and hg.pending == nil
  and table.getn(hg.events) == 3 and table.getn(gg.events) == 3, table.getn(gg and gg.events or {}))
Shoot(guest, 2)
Check("...and play goes on", table.getn(hg.events) == 4)
PressIn(host, "Resign"); Run(3.1); PressIn(host, "Confirm"); Run(1)

H.Done("BATTLESHIP")
