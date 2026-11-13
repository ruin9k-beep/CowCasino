-- Party Craps simulation: isolated clients (Host, Bob, Cid, Dan)
-- talking over a simulated party channel. Each client loads the real addon
-- into its own environment on top of the strict 1.12 mock.
local ADDON = arg[1]
local base = _G
local BLOCKED = { select = true, print = true }
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-58s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. extra) or ""))
  ok = ok and cond and true or false
end

local CLOCK = 0
local group = {}          -- names in the party, in join order
local wire = {}           -- messages in flight
local stats = { sent = 0, longest = 0, chars = 0 }
local clients, byName = {}, {}

local function InGroup(name)
  for _, n in ipairs(group) do if n == name then return true end end
  return false
end
local function Others(name)
  local out = {}
  for _, n in ipairs(group) do if n ~= name then table.insert(out, n) end end
  return out
end

local function NewClient(name)
  local env = setmetatable({}, { __index = function(t, k) if BLOCKED[k] then return nil end return base[k] end })
  env.arg = { ADDON }
  env.PLAYER_NAME = name
  env.SELECT_SAVED = select
  assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
  env.GetTime = function() return CLOCK end
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
    local len = string.len(prefix) + string.len(text)
    assert(len <= 254, "addon message too long (" .. len .. "): " .. text)
    stats.sent = stats.sent + 1
    stats.chars = stats.chars + len
    if len > stats.longest then stats.longest = len end
    table.insert(wire, { from = name, prefix = prefix, text = text, chan = chan })
    -- messages may be packed together, joined by "~" (chat always goes alone)
    local parts = {}
    if string.sub(text, 1, 3) == "CH;" then parts = { text } else
      local start = 1
      while true do
        local i = string.find(text, "~", start, true)
        if not i then table.insert(parts, string.sub(text, start)) break end
        table.insert(parts, string.sub(text, start, i - 1)); start = i + 1
      end
    end
    stats.parts = (stats.parts or 0) + table.getn(parts)
    for _, part in ipairs(parts) do
                end
    if HOOK then for _, part in ipairs(parts) do HOOK(name, part) end end
  end
  for _, o in ipairs(env.all) do
    if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end
  end
  local ns = env.CowCasino.ns
  ns.db.chips = 5000
  env.CowCasinoFrame:Show()
  if PREP then PREP(ns) end
  ns:OpenGame("craps")
  -- Party play lives inside Craps: press its "Party play" button.
  for _, o in ipairs(env.all) do
    if o.kind == "Button" and o.text == "Party play" then env.Fire(o, "OnClick", "LeftButton") end
  end
  local c = { name = name, env = env, ns = ns, P = ns.PartyCraps }
  c.T = c.P.T
  c.updaters = {}
  for _, o in ipairs(env.all) do
    if not o.parent and o.scripts.OnUpdate then table.insert(c.updaters, o) end
  end
  if ns.Dealer.UI() then table.insert(c.updaters, ns.Dealer.UI()) end   -- the dealer's messages
  table.insert(clients, c)
  byName[name] = c
  return c
end

local function Deliver()
  while wire[1] do
    local m = table.remove(wire, 1)
    if InGroup(m.from) then
      for _, c in ipairs(clients) do
        if InGroup(c.name) and c.env.PrefixHeard(m.prefix) then   -- the modern client only delivers registered prefixes
          for _, o in ipairs(c.env.all) do
            if rawget(o, "events") and o.events.CHAT_MSG_ADDON then
              c.env.Fire(o, "OnEvent", m.prefix, "CHAT_MSG_ADDON", m.text, m.chan, m.from .. c.env.REALM_SUFFIX)
            end
          end
        end
      end
    end
  end
end

local function GroupChanged()
  for _, c in ipairs(clients) do
    for _, o in ipairs(c.env.all) do
      if rawget(o, "events") and o.events[c.env.ROSTER_EVENT] then c.env.Fire(o, "OnEvent", nil, c.env.ROSTER_EVENT) end
    end
  end
end



---------------------------------------------------------------------------
-- Party Craps tests (body; appended to party_craps_head.lua)
---------------------------------------------------------------------------
local function Tick(dt)
  dt = dt or 0.1
  CLOCK = CLOCK + dt
  for _, c in ipairs(clients) do
    for _, o in ipairs(c.updaters) do
      if o.shown and o.scripts.OnUpdate then c.env.Fire(o, "OnUpdate", dt) end
    end
  end
  Deliver()
  for _, c in ipairs(clients) do
    local u = c.ns.Dealer.UI()
    if u and u.text.text then c.dealerSaid = c.dealerSaid or {}; c.dealerSaid[u.text.text] = true end
  end
end
local function Run(seconds) for _ = 1, math.floor(seconds * 10 + 0.5) do Tick(0.1) end end
local function RunUntil(cond, limit)
  local t = 0
  while not cond() and t < (limit or 60) do Tick(0.1); t = t + 0.1 end
  return cond()
end
local function InPanel(c, o)
  local root = c.P.panel
  while o do
    if not o.shown then return false end
    if o == root then return true end
    o = o.parent
  end
  return false
end
local function Find(c, text)
  for _, o in ipairs(c.env.all) do
    if o.kind == "Button" and InPanel(c, o) and o.text == text then return o end
  end
end
local function Press(c, text)
  local b = Find(c, text)
  assert(b, c.name .. ": no button " .. text)
  assert(b.enabled, c.name .. ": button disabled: " .. b.text)
  c.env.Fire(b, "OnClick", "LeftButton")
end
local function Spot(c, key) for _, b in ipairs(c.P.ui.spots) do if b.spot.key == key then return b end end end
local function Bet(c, key, chip)
  Press(c, tostring(chip))
  c.env.Fire(Spot(c, key), "OnClick", "LeftButton")
end
local function Take(c, key) c.env.Fire(Spot(c, key), "OnClick", "RightButton") end

local RIG = {}
local host = NewClient("Host")
host.ns.CrapsRules.Roll = function()
  local r = table.remove(RIG, 1)
  if r then return r[1], r[2] end
  return math.random(1, 6), math.random(1, 6)
end
local bob = NewClient("Bob")
local cid = NewClient("Cid")
local dan = NewClient("Dan")      -- not in the party
for _, c in ipairs({ host, bob, cid }) do
  local c = c
  c.played = {}
  local real = c.env.PlaySound
  c.env.PlaySound = function(n) table.insert(c.played, c.env.SoundName(n)); real(n) end
end

-- every chip, everywhere: wallets, stacks at the table, bets on the table
-- what a player has at the table: stack plus bets (party seats are free, so
-- the wallet never moves)
local function Wealth(c)
  local total = 0
  if c.T.mode ~= "lobby" then
    local me = c.T.seats[c.T.mySeat]
    total = total + me.stack
    for _, v in pairs(me.bets) do total = total + v end
  end
  return total
end

table.insert(group, "Host"); table.insert(group, "Bob"); table.insert(group, "Cid")
GroupChanged()
Check("lobby: hosting needs a group", Find(dan, "Host a table") ~= nil and not Find(dan, "Host a table").enabled)
Press(host, "Host a table")
Check("host sits down free with a 500 stack", host.T.mode == "host" and host.ns.db.chips == 5000 and host.T.seats[1].stack == 500)
Run(1)
Press(bob, "Refresh")
Run(1)
Check("Bob sees the table", bob.P.T.offers.Host ~= nil)
Check("Dan, outside the group, doesn't", dan.P.T.offers.Host == nil)
local function JoinButton(c) for _, o in ipairs(c.env.all) do if o.kind == "Button" and o.text == "Join" and InPanel(c, o) and o.enabled then return o end end end
c_join = JoinButton(bob)
bob.env.Fire(c_join, "OnClick", "LeftButton")
Press(cid, "Refresh"); Run(1)
cid.env.Fire(JoinButton(cid), "OnClick", "LeftButton")
Run(2)
Check("Bob and Cid are seated", bob.T.mode == "client" and cid.T.mode == "client" and host.T.seats[2].name == "Bob"
  and host.T.seats[3].name == "Cid")
Check("joining is free: their chips are untouched", bob.ns.db.chips == 5000 and cid.ns.db.chips == 5000)
-- each player's chips are their 5000 plus what the table says they won or lost
local function Square()
  local bad = {}
  for _, c in ipairs({ host, bob, cid }) do
    if c.T.mode ~= "lobby" and (Wealth(c) ~= 500 + c.ns.db.partycraps.stats.net or c.ns.db.chips ~= 5000) then
      table.insert(bad, c.name .. " " .. Wealth(c) .. " vs " .. (500 + c.ns.db.partycraps.stats.net) .. ", wallet " .. c.ns.db.chips)
    end
  end
  return table.getn(bad) == 0, table.concat(bad, "; ")
end
Check("the host has the dice first", host.T.shooter == 1 and bob.T.shooter == 1 and Find(host, "Roll") ~= nil and Find(bob, "Roll") == nil)

-- bets from everyone
Bet(host, "pass", 25)
Bet(bob, "pass", 25); Bet(bob, "field", 5)
Bet(cid, "dontPass", 100)
Run(1)
Check("bets reach the host", host.T.seats[2].bets.pass == 25 and host.T.seats[2].bets.field == 5 and host.T.seats[3].bets.dontPass == 100)
Check("...and come back to every table", bob.T.seats[3].bets.dontPass == 100 and cid.T.seats[2].bets.pass == 25 and bob.T.seats[2].stack == 470)
Bet(bob, "odds", 25)
Run(1)
Check("no odds without a point", host.T.seats[2].bets.odds == nil)
Check("only the shooter can roll", not pcall(function() Press(bob, "Roll") end))

-- come-out 8: the point
table.insert(RIG, { 4, 4 })
Press(host, "Roll")
Run(2)
Check("a come-out 8 sets the point on every table", host.T.point == 8 and bob.T.point == 8 and cid.T.point == 8)
Check("Bob's Field lost", host.T.seats[2].bets.field == nil and bob.T.seats[2].last == -5)
Check("the dice show 4 and 4 for everyone", bob.P.ui.dice.a.value == 4 and cid.P.ui.dice.b.value == 4)
Run(2)
Check("betting opens again after the result", host.T.phase == "betting" and bob.T.phase == "betting")
Bet(bob, "odds", 25); Bet(bob, "odds", 25)
Take(cid, "dontPass")
Run(1)
Check("odds behind Pass now; Don't Pass can't come down", host.T.seats[2].bets.odds == 50 and host.T.seats[3].bets.dontPass == 100)
Check("Bob can't leave with a Pass bet on a point", not Find(bob, "Leave table").enabled)

-- 6: nothing happens to the line bets
table.insert(RIG, { 2, 4 })
Press(host, "Roll")
Run(4)
Check("a 6 changes nothing", host.T.point == 8 and host.T.seats[2].bets.pass == 25 and host.T.seats[2].bets.odds == 50)

-- 8 again: point made
table.insert(RIG, { 5, 3 })
Press(host, "Roll")
Run(2)
Check("point made: Pass and odds pay, Don't Pass loses", host.T.point == nil
  and host.T.seats[1].stack == 500 + 25
  and host.T.seats[2].stack == 500 - 5 + 25 + 60
  and host.T.seats[3].stack == 400, host.T.seats[1].stack .. " " .. host.T.seats[2].stack .. " " .. host.T.seats[3].stack)
Check("every table shows the same stacks", bob.T.seats[2].stack == 580 and cid.T.seats[2].stack == 580 and cid.T.seats[3].stack == 400)
Check("Bob's stats count the rolls he had bets on", bob.ns.db.partycraps.stats.rolls == 3 and bob.ns.db.partycraps.stats.net == 80
  and bob.ns.db.partycraps.stats.pointsMade == 1, bob.ns.db.partycraps.stats.net)
Check("sounds: Bob hears a win", bob.played[table.getn(bob.played)] == "LOOTWINDOWCOINSOUND", bob.played[table.getn(bob.played)])
local sq, why = Square()
Check("every player's chips match their wins and losses", sq, why)

-- seven out passes the dice
Run(2)
Bet(host, "pass", 25)
table.insert(RIG, { 5, 5 }); Press(host, "Roll"); Run(4)
table.insert(RIG, { 3, 4 }); Press(host, "Roll"); Run(2)
Check("seven out: the dice pass to Bob", host.T.shooter == 2 and bob.T.shooter == 2 and cid.T.shooter == 2)
Run(2)
Check("Bob gets the Roll button", Find(bob, "Roll") ~= nil and Find(host, "Roll") == nil)

-- the dice roll themselves when the betting time runs out
Bet(cid, "field", 5)
Run(1)
local rolls = host.T.rollNo
table.insert(RIG, { 1, 1 })      -- craps: no point
Run(26)
Check("the dice roll themselves after the betting time", host.T.rollNo == rolls + 1)
Run(3)
table.insert(RIG, { 5, 6 })      -- 11: no point
Check("Bob, the shooter, rolls when he likes", pcall(function() Bet(bob, "any7", 5); Run(1); Press(bob, "Roll") end))
Run(4)
sq, why = Square()
Check("every player's chips still match their wins and losses", sq, why)

-- table chat knows the craps table
Check("table chat: everyone's at the same craps table", host.ns:ChatTable() and bob.ns:ChatTable()
  and host.ns:ChatTable().game == "CR" and bob.ns:ChatTable().tid == host.ns:ChatTable().tid
  and bob.ns:ChatTable().members.Cid == true)
Check("a party seat keeps you in the game", bob.ns:ChipsInPlay())

-- Cid leaves with his stack and bets
local cidBefore = cid.ns.db.chips
Bet(cid, "field", 5); Run(1)
Check("no point is on", host.T.point == nil)
Press(cid, "Leave table")
Run(1)
Check("Cid leaves; his wallet is untouched", cid.T.mode == "lobby" and cid.ns.db.chips == cidBefore and host.T.seats[3].kind == "empty")

-- Bob drops from the group: he gets his chips back, the host frees the seat
local bobBefore = bob.ns.db.chips
do
  local G = host.ns.dealers.goblin.lines
  local function Pattern(line)
    local q = string.gsub(line, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return "^" .. string.gsub(q, "{%w+}", ".-") .. "$"
  end
  for _, c in ipairs({ host, bob }) do
    local kinds, list = {}, {}
    for text in pairs(c.dealerSaid or {}) do
      for e, lines in pairs(G) do
        if string.sub(e, 1, 5) == "craps" then
          for _, l in ipairs(lines) do if string.find(text, Pattern(l)) then kinds[e] = true end end
        end
      end
    end
    for e in pairs(kinds) do table.insert(list, e) end
    table.sort(list)
    Check("Fizzlecog calls the rolls at " .. c.name .. "'s seat", table.getn(list) >= 2, table.concat(list, ","))
  end
end
table.remove(group, 2)
GroupChanged()
Run(1)
Check("Bob left the group: back in the lobby, wallet untouched, seat freed", bob.T.mode == "lobby" and bob.ns.db.chips == bobBefore and host.T.seats[2].kind == "empty")
Check("the dice move on if the shooter leaves", host.T.shooter == 1, host.T.shooter)

-- the host closes the table
local hostBefore = host.ns.db.chips
Press(host, "Close table")
Check("closing the table leaves the host's wallet untouched", host.T.mode == "lobby" and host.ns.db.chips == hostBefore)

-- a reload while seated pays back the safe stack
table.insert(group, "Bob"); GroupChanged()
Press(host, "Host a table"); Run(1)
Press(bob, "Refresh"); Run(1)
bob.env.Fire(JoinButton(bob), "OnClick", "LeftButton"); Run(2)
Bet(bob, "pass", 100); Run(1)
local saved = bob.ns.db
local bobWealth = bob.ns.db.chips
local env2 = setmetatable({}, { __index = function(t, k) if BLOCKED[k] then return nil end return base[k] end })
env2.arg = { ADDON }; env2.PLAYER_NAME = "Bob"; env2.SELECT_SAVED = select
assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env2))()
env2.CowCasinoDB = saved
for _, o in ipairs(env2.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env2.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
env2.CowCasino.ns:OpenGame("craps")
Check("a reload at a craps table leaves the wallet untouched", env2.CowCasino.ns.db.chips == bobWealth, env2.CowCasino.ns.db.chips .. " vs " .. bobWealth)

io.write(string.format("addon messages: %d sent, %d parts, longest %d\n", stats.sent, stats.parts or 0, stats.longest))
io.write(ok and "PARTY CRAPS PASS\n" or "PARTY CRAPS FAIL\n")
os.exit(ok and 0 or 1)
