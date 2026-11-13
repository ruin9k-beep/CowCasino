-- Deathroll: against the dealer (rolls go 1 to the last roll, a 1 loses,
-- the winner takes both stakes, a duel survives a reload) and party duels
-- between isolated clients: a challenge, the first to accept plays, real
-- /rolls read from the system chat (or the backup addon message), forfeits,
-- leaving the group and a reload calling a duel off.
local ADDON = arg[1]
local base = _G
local BLOCKED = { select = true, print = true }
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-66s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end

local CLOCK = 0
local group = {}
local wire, sys = {}, {}
local clients, byName = {}, {}
local ROLLS = {}             -- rigged /roll results, used in order
local hideRollsFrom = {}     -- names whose /roll messages never arrive
local rollsMade = {}

function Copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Copy(v) end
  return out
end

local function InGroup(name)
  for _, n in ipairs(group) do if n == name then return true end end
  return false
end
local function Others(name)
  local out = {}
  for _, n in ipairs(group) do if n ~= name then table.insert(out, n) end end
  return out
end

local function NewClient(name, saved)
  local env = setmetatable({}, { __index = function(t, k) if BLOCKED[k] then return nil end return base[k] end })
  env.arg = { ADDON }
  env.PLAYER_NAME = name
  env.SELECT_SAVED = select
  assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
  env.GetTime = function() return CLOCK end
  env.CowCasinoDB = saved
  env.UnitName = function(u)
    if u == "player" then return name end
    local _, _, n = string.find(u, "^party(%d)$")
    if n and InGroup(name) then return Others(name)[tonumber(n)] end
    return nil
  end
  env.GetNumPartyMembers = function() if InGroup(name) and table.getn(group) > 1 then return table.getn(group) - 1 end return 0 end
  env.GetNumRaidMembers = function() return 0 end
  env.SendAddonMessage = function(prefix, text, chan)
    assert(type(text) == "string" and chan == "PARTY", "bad addon message")
    assert(string.len(prefix) + string.len(text) <= 254, "addon message too long")
    table.insert(wire, { from = name, prefix = prefix, text = text, chan = chan })
  end
  env.RandomRoll = function(lo, hi)
    local v = table.remove(ROLLS, 1) or math.random(lo, hi)
    table.insert(rollsMade, { name = name, lo = lo, hi = hi, v = v })
    if not hideRollsFrom[name] then
      table.insert(sys, { from = name, text = name .. " rolls " .. v .. " (" .. lo .. "-" .. hi .. ")" })
    end
  end
  for _, o in ipairs(env.all) do
    if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end
  end
  local ns = env.CowCasino.ns
  if not saved then ns.db.chips = 1000 end
  env.CowCasinoFrame:Show()
  ns:OpenGame("deathroll")
  local c = { name = name, env = env, ns = ns, G = ns.games.deathroll }
  c.S = c.G.S
  c.updaters = {}
  for _, o in ipairs(env.all) do
    if not o.parent and o.scripts.OnUpdate then table.insert(c.updaters, o) end
  end
  if ns.Dealer.UI() then table.insert(c.updaters, ns.Dealer.UI()) end
  table.insert(clients, c)
  byName[name] = c
  return c
end

local function FireAll(c, ev, a1, a2, a3, a4)
  for _, o in ipairs(c.env.all) do
    if rawget(o, "events") and o.events[ev] then c.env.Fire(o, "OnEvent", a1, ev, a2, a3, a4) end
  end
end

local function Deliver()
  while wire[1] or sys[1] do
    local m = table.remove(wire, 1)
    if m and InGroup(m.from) then
      for _, c in ipairs(clients) do
        if c.name ~= m.from and InGroup(c.name) and c.env.PrefixHeard(m.prefix) then
          FireAll(c, "CHAT_MSG_ADDON", m.prefix, m.text, m.chan, m.from .. c.env.REALM_SUFFIX)
        end
      end
    end
    local r = table.remove(sys, 1)
    if r then
      for _, c in ipairs(clients) do
        if c.name == r.from or (InGroup(c.name) and InGroup(r.from)) then FireAll(c, "CHAT_MSG_SYSTEM", r.text) end
      end
    end
  end
end

local function GroupChanged()
  for _, c in ipairs(clients) do FireAll(c, c.env.ROSTER_EVENT) end
end

local function Tick(dt)
  dt = dt or 0.1
  CLOCK = CLOCK + dt
  for _, c in ipairs(clients) do
    for _, o in ipairs(c.updaters) do
      if o.shown and o.scripts.OnUpdate then c.env.Fire(o, "OnUpdate", dt) end
    end
  end
  Deliver()
end
local function Run(seconds) for _ = 1, math.floor(seconds * 10 + 0.5) do Tick(0.1) end end

local function InGame(c, o)
  local root = c.G.panel
  while o do
    if not o.shown then return false end
    if o == root then return true end
    o = o.parent
  end
  return false
end
local function Find(c, text, prefix)
  for _, o in ipairs(c.env.all) do
    if o.kind == "Button" and InGame(c, o) and type(o.text) == "string" then
      if o.text == text or (prefix and string.sub(o.text, 1, string.len(text)) == text) then return o end
    end
  end
end
local function Press(c, text, prefix)
  local b = Find(c, text, prefix)
  assert(b, c.name .. ": no button " .. text)
  assert(b.enabled, c.name .. ": button disabled: " .. b.text)
  c.env.Fire(b, "OnClick", "LeftButton")
  return b
end
local function Enabled(c, text, prefix) local b = Find(c, text, prefix); return b ~= nil and b.enabled ~= nil end

---------------------------------------------------------------------------
-- Reading roll messages
---------------------------------------------------------------------------
math.randomseed(7)
local host = NewClient("Host")
local P = host.G.ParseRoll
local n, v, lo, hi = P("Bob rolls 57 (1-1000)")
Check("a roll message is read", n == "Bob" and v == 57 and lo == 1 and hi == 1000)
n = P("Bob-Nordanaar rolls 3 (1-12)")
Check("...a player from another realm is known by name", n == "Bob")
Check("...and other system messages are not rolls", P("Bob has joined the party.") == nil and P(nil) == nil)

---------------------------------------------------------------------------
-- Against the dealer
---------------------------------------------------------------------------
local D = host.ns.db.deathroll
Check("the dealer duel is the default", D.mode == "solo" and Find(host, "Duel", true) ~= nil)
-- rig the duel: you roll 400, dealer 120, you 50, dealer 1
local realRandom = math.random
local rig = { 400, 120, 50, 1 }
math.random = function(a, b) if b and rig[1] then return table.remove(rig, 1) end if b then return realRandom(a, b) elseif a then return realRandom(a) end return realRandom() end
Press(host, "Duel", true)
Check("the duel takes the stake (100)", host.ns.db.chips == 900, host.ns.db.chips)
Check("you roll first: Roll 1-1,000", Enabled(host, "Roll 1-1,000"))
Press(host, "Roll 1-1,000")
Check("your roll sets the dealer's range", host.S.duel.max == 400 and host.S.duel.turn == "them")
Check("you can't roll on the dealer's turn", not Enabled(host, "Waiting", true))
Run(1.5)
Check("the dealer rolls back on its own", host.S.duel.max == 120 and host.S.duel.turn == "me")
Press(host, "Roll 1-120")
-- a reload mid-duel keeps it
local env1 = host.env
local saved = env1.CowCasinoDB
local host2 = NewClient("Host2", Copy(saved))
Check("a duel against the dealer survives a reload", host2.S.duel ~= nil and host2.S.duel.max == 50
  and host2.S.duel.turn == "them" and host2.ns.db.chips == 900)
table.remove(clients)   -- (just checking; play on in the first one)
Run(1.5)
Check("the dealer rolls a 1: you win both stakes (200)", host.S.duel == nil and host.ns.db.chips == 1100, host.ns.db.chips)
Check("stats: a duel won", D.stats.duels == 1 and D.stats.wins == 1 and D.stats.won == 200 and D.stats.wagered == 100)
local logText = table.concat(D.lastLog, " / ")
Check("the log shows every roll", string.find(logText, "400", 1, true) and string.find(logText, "120", 1, true)
  and string.find(logText, "rolls |cffff40401", 1, true), logText)
rig = { 1 }
Press(host, "Duel", true)
Press(host, "Roll", true)
Check("rolling a 1 yourself loses the stake", host.S.duel == nil and host.ns.db.chips == 1000 and D.stats.losses == 1)
math.random = realRandom

-- many duels at random: chips only ever move by the stake
local fine = true
for _ = 1, 30 do
  local before = host.ns.db.chips
  Press(host, "Duel", true)
  local guard = 0
  while host.S.duel and guard < 400 do
    guard = guard + 1
    if Enabled(host, "Roll", true) then Press(host, "Roll", true) end
    Run(0.6)
  end
  local diff = host.ns.db.chips - before
  if host.S.duel or (diff ~= 100 and diff ~= -100) then fine = false end
end
Check("30 random duels each end, winning or losing exactly the stake", fine)

---------------------------------------------------------------------------
-- Party duels
---------------------------------------------------------------------------
local bob = NewClient("Bob")
local cid = NewClient("Cid")
group = { "Host", "Bob", "Cid" }
GroupChanged()
Run(0.5)
for _, c in ipairs({ host, bob, cid }) do
  c.ns.db.chips = 1000
  Press(c, "Party duel")
end
Run(1)
Check("party mode: Challenge the group", Enabled(host, "Challenge the group"))
Check("...and the dealer tab switches back", Enabled(host, "Vs", true))
Press(host, "Challenge the group")
Run(1)
Check("the challenge shows for the others", bob.G.ui.rows[1].shown ~= false and bob.G.ui.rows[1].offer
  and bob.G.ui.rows[1].offer.host == "Host" and bob.G.ui.rows[1].offer.stake == 100)
Check("...and the challenger can withdraw it", Enabled(host, "Withdraw challenge"))
-- Bob and Cid both accept; Bob is first
bob.env.Fire(bob.G.ui.rows[1].accept, "OnClick", "LeftButton")
cid.env.Fire(cid.G.ui.rows[1].accept, "OnClick", "LeftButton")
Run(1)
Check("the first to accept gets the duel", host.S.duel and host.S.duel.opp == "Bob" and bob.S.duel and bob.S.duel.opp == "Host")
Check("...the other is told someone was quicker", cid.S.duel == nil and cid.S.accepting == nil
  and string.find(cid.G.ui.status.text or "", "Bob took", 1, true) ~= nil, cid.G.ui.status.text)
Check("party duels are free: no chips taken", host.ns.db.chips == 1000 and bob.ns.db.chips == 1000 and cid.ns.db.chips == 1000)
Check("the challenger rolls first", Enabled(host, "Roll 1-1,000") and not Enabled(bob, "Roll", true))

ROLLS = { 640 }
Press(host, "Roll 1-1,000")
Check("a party roll is a real /roll", rollsMade[table.getn(rollsMade)].name == "Host" and rollsMade[table.getn(rollsMade)].hi == 1000)
Run(0.5)
Check("both see it: Bob's turn, 1-640", host.S.duel.max == 640 and bob.S.duel.max == 640 and bob.S.duel.turn == "me"
  and Enabled(bob, "Roll 1-640"))
-- Bob's roll message never arrives anywhere: the addon message carries it
hideRollsFrom.Bob = true
ROLLS = { 77 }
Press(bob, "Roll 1-640")
Run(0.5)
Check("a /roll that never shows is rolled here after a moment", bob.S.duel.turn == "me" or bob.S.duel.max ~= 640)
Run(4)
Check("...and the other player gets it by addon message", host.S.duel.max == bob.S.duel.max and host.S.duel.turn == "me"
  and bob.S.duel.turn == "them", host.S.duel.max .. "/" .. bob.S.duel.max)
hideRollsFrom.Bob = nil
-- someone else's /roll in between changes nothing
table.insert(sys, { from = "Cid", text = "Cid rolls 1 (1-" .. host.S.duel.max .. ")" })
Run(0.3)
Check("someone else's /roll doesn't count", host.S.duel.turn == "me" and bob.S.duel.turn == "them")
-- play it out
local guard = 0
while host.S.duel and guard < 200 do
  guard = guard + 1
  for _, c in ipairs({ host, bob }) do if Enabled(c, "Roll", true) then Press(c, "Roll", true) end end
  Run(0.6)
end
local hw, bw = host.ns.db.chips, bob.ns.db.chips
Check("the duel ends for both", host.S.duel == nil and bob.S.duel == nil)
Check("...and nobody's chips move", hw == 1000 and bw == 1000, hw .. "/" .. bw)
local hs, bs = host.ns.db.deathroll.stats, bob.ns.db.deathroll.stats
Check("...but the win and the loss are counted", hs.wins + bs.wins >= 1 and hs.losses + bs.losses >= 1
, hs.wins .. "/" .. bs.wins)
local function Rolls(log)
  local t = {}
  for _, line in ipairs(log) do
    local _, _, v = string.find(line, "|c%x%x%x%x%x%x%x%x([%d,]+)|r")
    if v then table.insert(t, v) end
  end
  return table.concat(t, " ")
end
Check("...and both saw the same rolls", Rolls(host.ns.db.deathroll.lastLog) == Rolls(bob.ns.db.deathroll.lastLog),
  Rolls(host.ns.db.deathroll.lastLog))

-- A forfeit
for _, c in ipairs({ host, bob, cid }) do c.ns.db.chips = 1000 end
Press(cid, "Challenge the group")
Run(1)
host.env.Fire(host.G.ui.rows[1].accept, "OnClick", "LeftButton")
Run(1)
Check("Host takes Cid's challenge", host.S.duel and host.S.duel.opp == "Cid" and cid.S.duel and cid.S.duel.opp == "Host")
Check("...Bob can't take it any more", bob.G.ui.rows[1].offer == nil or bob.G.ui.rows[1].shown == false)
Press(host, "Forfeit")
Run(1)
Check("a forfeit gives Cid the win, and no chips move", host.S.duel == nil and cid.S.duel == nil and host.ns.db.chips == 1000
  and cid.ns.db.chips == 1000 and string.find(cid.G.ui.status.text or "", "forfeits", 1, true) ~= nil,
  host.ns.db.chips .. "/" .. cid.ns.db.chips)

-- Withdrawing a challenge
Press(bob, "Challenge the group")
Run(1)
Check("Bob's challenge is up", host.G.ui.rows[1].offer and host.G.ui.rows[1].offer.host == "Bob")
Press(bob, "Withdraw challenge")
Run(1)
Check("...and gone when withdrawn", not (host.G.ui.rows[1].offer) and bob.S.posted == nil)

-- Leaving the group calls a duel off
for _, c in ipairs({ host, bob, cid }) do c.ns.db.chips = 1000 end
Press(bob, "Challenge the group")
Run(1)
cid.env.Fire(cid.G.ui.rows[1].accept, "OnClick", "LeftButton")
Run(1)
Check("Bob and Cid are dueling", bob.S.duel and cid.S.duel and bob.ns.db.chips == 1000)
Check("a free party duel holds no chips", not bob.ns:ChipsInPlay() and not cid.ns:ChipsInPlay())
group = { "Host", "Bob" }
GroupChanged()
Run(0.5)
Check("Cid leaves: called off", bob.S.duel == nil and bob.ns.db.chips == 1000
  and cid.S.duel == nil and cid.ns.db.chips == 1000, bob.ns.db.chips .. "/" .. cid.ns.db.chips)

-- A reload calls a duel off; the other player gets their stake back too
group = { "Host", "Bob", "Cid" }
GroupChanged()
Run(0.5)
for _, c in ipairs({ host, bob, cid }) do c.ns.db.chips = 1000 end
Press(host, "Challenge the group")
Run(1)
bob.env.Fire(bob.G.ui.rows[1].accept, "OnClick", "LeftButton")
Run(1)
ROLLS = { 500 }
Press(host, "Roll 1-1,000")
Run(0.5)
local bobSaved = bob.env.CowCasinoDB
for i, c in ipairs(clients) do if c == bob then table.remove(clients, i) end end
local bob2 = NewClient("Bob", Copy(bobSaved))
Run(1)
Check("after Bob's reload the duel is gone, chips untouched", bob2.S.duel == nil and bob2.ns.db.chips == 1000, bob2.ns.db.chips)
Check("...and Host's duel is called off", host.S.duel == nil and host.ns.db.chips == 1000, host.ns.db.chips)

-- Going quiet: after a minute without a roll, the duel can be called off
for _, c in ipairs(clients) do c.ns.db.chips = 1000 end
Press(host, "Challenge the group")
Run(1)
cid.env.Fire(cid.G.ui.rows[1].accept, "OnClick", "LeftButton")
Run(1)
ROLLS = { 300 }
Press(host, "Roll 1-1,000")
Run(1)
Check("waiting on Cid: the button says Forfeit", Find(host, "Forfeit") ~= nil)
Run(61)
Check("a minute of quiet: Call it off", Find(host, "Call it off") ~= nil)
Press(host, "Call it off")
Run(1)
Check("calling it off ends it for both, chips untouched", host.S.duel == nil and cid.S.duel == nil and host.ns.db.chips == 1000
  and cid.ns.db.chips == 1000)

io.write(ok and "DEATHROLL PASS\n" or "DEATHROLL FAIL\n")
os.exit(ok and 0 or 1)
