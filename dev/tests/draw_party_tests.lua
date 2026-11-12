-- Party Five-Card Draw: up to five isolated clients talking over a simulated
-- party channel. Hosts set the blinds and buy-in and choose whether computer
-- players fill empty seats.
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
      if string.sub(part, 1, 5) == "DR;P;" and name == "Host" then LAST_P = part end
    end
  end
  for _, o in ipairs(env.all) do
    if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end
  end
  local ns = env.CowCasino.ns
  ns.db.chips = 5000
  env.CowCasinoFrame:Show()
  ns:OpenGame("draw")
  local c = { name = name, env = env, ns = ns, P = ns.games.draw }
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

local onTick
local function Tick(dt)
  dt = dt or 0.1
  CLOCK = CLOCK + dt
  for _, c in ipairs(clients) do
    for _, o in ipairs(c.updaters) do
      if o.shown and o.scripts.OnUpdate then c.env.Fire(o, "OnUpdate", dt) end
    end
  end
  Deliver()
  if onTick then onTick() end
end
local function Run(seconds) for _ = 1, math.floor(seconds * 10 + 0.5) do Tick(0.1) end end

-- Buttons inside a client's poker window
local function InPoker(c, o)
  local root = c.P.panel
  while o do
    if not o.shown then return false end
    if o == root then return true end
    o = o.parent
  end
  return false
end
local function Find(c, text, prefix)
  for _, o in ipairs(c.env.all) do
    if o.kind == "Button" and InPoker(c, o) then
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

local function MyTurn(c)
  local T = c.T
  local me = T.seats[T.mySeat]
  return T.street ~= "idle" and me and T.actor == T.mySeat and not me.folded and not me.allIn and not me.out
    and (not me.acted or me.bet < T.currentBet) and not (T.mode == "client" and T.sent == T.version)
end

local function TableChips(T)
  local s = T.pot
  for i = 1, 5 do s = s + T.seats[i].stack + T.seats[i].bet end
  return s
end


---------------------------------------------------------------------------
math.randomseed(5)
local host = NewClient("Host")
local bob = NewClient("Bob")
local cid = NewClient("Cid")
local dan = NewClient("Dan")
local eve = NewClient("Eve")
for _, c in ipairs(clients) do c.P.SetSims(10) end
group = { "Host", "Bob", "Cid" }
GroupChanged()
Run(1)

local function Boxes(c)
  local t = {}
  for _, o in ipairs(c.env.all) do if o.kind == "EditBox" and InPoker(c, o) then table.insert(t, o) end end
  return t[1], t[2], t[3]
end
local function BotsBox(c)
  for _, o in ipairs(c.env.all) do if o.kind == "CheckButton" and InPoker(c, o) then return o end end
end

-- Everyone plays their own seat: call or check, and draw a few cards at random.
local function AutoPlay(c)
  local T = c.T
  local me = T.seats[T.mySeat]
  if not me or T.street == "idle" or T.actor ~= T.mySeat then return end
  if T.street == "draw" then
    local picks = c.P.ui.seats[1].picks
    if c.pickHand ~= T.hand then c.picked, c.pickHand = nil, T.hand end
    if not c.picked then
      for k = 1, 5 do if math.random() < 0.3 then c.env.Fire(picks[k], "OnClick", "LeftButton") end end
      c.picked = true
    end
    local b = Find(c, "Draw", true)
    if b and b.enabled then c.env.Fire(b, "OnClick", "LeftButton"); c.picked = nil; return end
    for k = 1, 5 do if T.discard[k] then c.env.Fire(picks[k], "OnClick", "LeftButton") end end
    if Enabled(c, "Stand pat") then Press(c, "Stand pat"); c.picked = nil end
  elseif MyTurn(c) then
    if Enabled(c, "Call", true) then Press(c, "Call", true)
    elseif Enabled(c, "All-in", true) then Press(c, "All-in", true)
    elseif Enabled(c, "Check") then Press(c, "Check") end
  end
end
local drewSeen, holesMatch, mismatch = {}, true, nil
onTick = function()
  for _, c in ipairs(clients) do if InGroup(c.name) then AutoPlay(c) end end
  -- what the host knows a remote player drew, that player sees too
  for _, c in ipairs(clients) do
    if c ~= host and c.T.mode == "client" and InGroup(c.name) then
      local me = c.T.seats[c.T.mySeat]
      local hs = host.T.seats[c.T.mySeat]
      if me and hs and hs.kind == "remote" and c.T.hand == host.T.hand and me.hole[5] and hs.hole[5] and c.T.version == host.T.version then
        for k = 1, 5 do
          if me.hole[k].rank ~= hs.hole[k].rank or me.hole[k].suit ~= hs.hole[k].suit then
            if holesMatch and os.getenv("DEBUGDRAW") then
              local function cs(h) local t = {} for q = 1, 5 do t[q] = h[q].rank .. "/" .. h[q].suit end return table.concat(t, " ") end
              io.write("MISMATCH ", c.name, " street ", c.T.street, " ver c/h ", c.T.version, "/", host.T.version, " actor ", c.T.actor,
                " host: ", cs(hs.hole), " client: ", cs(me.hole), " hostlast ", tostring(hs.lastCode), " drew ", tostring(hs.drew), "\n")
            end
            holesMatch = false; mismatch = mismatch or (c.name .. " card " .. k .. " on " .. c.T.street)
          end
        end
      end
      if os.getenv("DEBUGDRAW") and me and c.name == "Bob" and c.T.street == "second" and not SHOWN then SHOWN = true; io.write("BOB second: drew=", tostring(me.drew), " code=", tostring(me.lastCode), " last=", tostring(me.last), "\n") end
      if me and me.drew and me.lastCode and string.sub(me.lastCode, 1, 1) == "D" then drewSeen[c.name] = true end
    end
  end
end

-- 1) Host: 10/20 blinds, 2,000 buy-in, computer players fill the empty seats.
Press(host, "Play with your party")
local sbBox, bbBox, buyBox = Boxes(host)
host.env.TypeInto(sbBox, "10"); host.env.TypeInto(bbBox, "20"); host.env.TypeInto(buyBox, "2000")
Check("host: the bots box is there and on", BotsBox(host) ~= nil and BotsBox(host).checked ~= nil)
Press(host, "Host a table")
Run(1)
Check("host: table open at 10/20 with 2,000", host.T.mode == "host" and host.T.seats[1].stack == 2000)
for _, c in ipairs({ bob, cid }) do
  Press(c, "Play with your party")
  Run(1)
  Press(c, "Join")
  Run(2)
end
Check("Bob and Cid sit down with the host's buy-in", bob.T.mode == "client" and cid.T.mode == "client"
  and bob.ns.db.chips == 3000 and cid.ns.db.chips == 3000)
local kinds = {}
for i = 1, 5 do kinds[i] = host.T.seats[i].kind end
local bots, people = 0, 0
for i = 1, 5 do if kinds[i] == "bot" then bots = bots + 1 elseif kinds[i] == "remote" or kinds[i] == "you" then people = people + 1 end end
Check("five seats: three people and two computer players", people == 3 and bots == 2, table.concat(kinds, ","))

Run(400)
Check("hands deal themselves and play through the draw", host.T.hand >= 4, host.T.hand)
Check("players at the host's table drew cards", drewSeen.Bob and drewSeen.Cid, tostring(drewSeen.Bob) .. "/" .. tostring(drewSeen.Cid) .. " hands " .. bob.T.hand)
Check("...and saw the same cards the host dealt them", holesMatch, mismatch)
Check("every table message fits in one addon message", stats.longest <= 254, stats.longest)

-- Close the table between hands; everyone cashes out.
local guard = 0
while host.T.street == "idle" and guard < 3000 do Tick(0.1); guard = guard + 1 end
while host.T.street ~= "idle" and guard < 6000 do Tick(0.1); guard = guard + 1 end
Press(host, "Close table")
Run(3)
Check("closing the table sends everyone home", host.T.mode == "solo" and not host.T.seats[1] and bob.T.mode == "solo" and cid.T.mode == "solo")

-- 2) Five people, no computer players, big numbers.
group = { "Host", "Bob", "Cid", "Dan", "Eve" }
GroupChanged()
Run(1)
for _, c in ipairs(clients) do c.ns.db.chips = 3000000 end
local wallets = 0
for _, c in ipairs(clients) do wallets = wallets + c.ns.db.chips end
Press(host, "Play with your party")
sbBox, bbBox, buyBox = Boxes(host)
host.env.TypeInto(sbBox, "5000"); host.env.TypeInto(bbBox, "10000"); host.env.TypeInto(buyBox, "1000000")
BotsBox(host).checked = nil           -- (the mock doesn't toggle a check box by itself)
host.env.Fire(BotsBox(host), "OnClick", "LeftButton")
Check("host: computer players turned off", not host.T.fillBots)
Press(host, "Host a table")
Run(1)
local empty = 0
for i = 2, 5 do if host.T.seats[i].kind == "empty" then empty = empty + 1 end end
Check("without computer players the other seats wait empty", empty == 4)
for _, c in ipairs({ bob, cid, dan, eve }) do
  Press(c, "Play with your party")
  Run(1)
  Press(c, "Join")
  Run(2)
end
people, bots = 0, 0
for i = 1, 5 do
  local k = host.T.seats[i].kind
  if k == "bot" then bots = bots + 1 elseif k == "remote" or k == "you" then people = people + 1 end
end
Check("five people at one table, no computer players", people == 5 and bots == 0)
drewSeen, holesMatch, mismatch = {}, true, nil
stats.longest = 0
Run(500)
Check("five-player hands play through", host.T.hand >= 3, host.T.hand)
Check("...everyone sees their own draws", drewSeen.Bob and drewSeen.Cid and drewSeen.Dan and drewSeen.Eve)
Check("...the same cards the host dealt", holesMatch, mismatch)
Check("million-chip stacks still fit in one addon message", stats.longest <= 254, stats.longest)
-- wait for a hand to end (a fresh one, so the next deal is 5 seconds away)
guard = 0
while host.T.street == "idle" and guard < 3000 do Tick(0.1); guard = guard + 1 end
while host.T.street ~= "idle" and guard < 6000 do Tick(0.1); guard = guard + 1 end
Run(1)          -- (everyone hears how the hand ended; the next one deals in 5)
local onTable = TableChips(host.T)
local inWallets = 0
for _, c in ipairs(clients) do inWallets = inWallets + c.ns.db.chips end
Check("chips are never made or lost (wallets + table)", inWallets + onTable == wallets, (inWallets + onTable) .. " vs " .. wallets)
for i = 2, 5 do
  local seat = host.T.seats[i]
  local c = byName[seat.name]
  if c then
    local mine = c.T.seats[c.T.mySeat]
    if mine.stack ~= seat.stack then Check("client stack matches the host's: " .. seat.name, false, mine.stack .. " vs " .. seat.stack) end
  end
end
Press(host, "Close table")
Run(3)
inWallets = 0
for _, c in ipairs(clients) do inWallets = inWallets + c.ns.db.chips end
Check("after closing, every chip is back in a wallet", inWallets == wallets, inWallets .. " vs " .. wallets)

io.write(ok and "DRAW PARTY PASS\n" or "DRAW PARTY FAIL\n")
os.exit(ok and 0 or 1)
