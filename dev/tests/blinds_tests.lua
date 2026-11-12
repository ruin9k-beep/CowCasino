-- Party Hold'em simulation: three isolated 1.12 clients (Host, Bob, Cid)
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
      if string.sub(part, 1, 5) == "HE;K;" then LAST_KICK = part end
      if string.sub(part, 1, 5) == "HE;P;" and name == "Host" then LAST_P = part end
    end
  end
  for _, o in ipairs(env.all) do
    if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end
  end
  local ns = env.CowCasino.ns
  ns.db.chips = 5000
  env.CowCasinoFrame:Show()
  ns:OpenGame("holdem")
  local c = { name = name, env = env, ns = ns, P = ns.games.holdem }
  c.T = c.P.T
  c.updaters = {}
  for _, o in ipairs(env.all) do
    if not o.parent and o.scripts.OnUpdate then table.insert(c.updaters, o) end
  end
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
  for i = 1, 4 do s = s + T.seats[i].stack + T.seats[i].bet end
  return s
end

-- Hold'em blinds, picked in Options.
local function Shown(c, text)
  for _, f in ipairs(c.env.all) do
    if f.kind == "FontString" and InPoker(c, f) and f.text and string.find(f.text, text, 1, true) then return f end
  end
end
local function BlindsButton(c, dir)   -- the < / > beside "Blinds" in Options
  for _, o in ipairs(c.env.all) do
    if o.kind == "Button" and InPoker(c, o) and o.text == dir and o.anchor and (o.anchor[5] == -56 or (o.anchor[2] and o.anchor[2].text and string.find(o.anchor[2].text or "", "/", 1, true))) then return o end
  end
end
local host = NewClient("Host")
local bob = NewClient("Bob")
host.P.SetSims(20); bob.P.SetSims(20)
group = { "Host", "Bob" }
GroupChanged()
Run(1)

Check("lobby starts at 5/10 with buy-ins 200 / 500 / 1,000", Shown(host, "blinds 5/10") ~= nil
  and Find(host, "200") and Find(host, "500") and Find(host, "1,000") and true)
Press(host, "Options")
Check("Options shows the blinds, 5 / 10", Shown(host, "5 / 10") ~= nil and Shown(host, "Buy-ins 200, 500 or 1,000") ~= nil)
host.env.Fire(BlindsButton(host, ">"), "OnClick", "LeftButton")
Check("> raises them to 10 / 20, buy-ins 400 / 1,000 / 2,000", Shown(host, "10 / 20") ~= nil and Shown(host, "Buy-ins 400, 1,000 or 2,000") ~= nil)
for _ = 1, 10 do local b = BlindsButton(host, ">"); if b.enabled then host.env.Fire(b, "OnClick", "LeftButton") end end
Check("the top level is 100 / 200, and > stops there", Shown(host, "100 / 200") ~= nil and not BlindsButton(host, ">").enabled)
for _ = 1, 10 do local b = BlindsButton(host, "<"); if b.enabled then host.env.Fire(b, "OnClick", "LeftButton") end end
Check("the bottom level is 1 / 2, and < stops there", Shown(host, "1 / 2") ~= nil and not BlindsButton(host, "<").enabled)
host.env.Fire(BlindsButton(host, ">"), "OnClick", "LeftButton")
host.env.Fire(BlindsButton(host, ">"), "OnClick", "LeftButton")
Press(host, "Done")
Check("the lobby follows: blinds 10/20, buy-ins 400 / 1,000 / 2,000", Shown(host, "blinds 10/20") ~= nil
  and Find(host, "400") and Find(host, "2,000") and true)

-- Solo table at 10/20
local T = host.T
local before = host.ns.db.chips
Press(host, "400")
Check("buying in takes 400", host.ns.db.chips == before - 400)
Check("the table shows blinds 10/20", Shown(host, "Blinds 10/20") ~= nil)
local posted = {}
for i = 1, 4 do if T.seats[i].bet > 0 then table.insert(posted, T.seats[i].bet) end end
table.sort(posted)
Check("the hand posts 10 and 20", table.concat(posted, ",") == "10,20", table.concat(posted, ","))
local botStacks = {}
for i = 2, 4 do table.insert(botStacks, T.seats[i].stack + T.seats[i].bet) end
Check("computer players start with your buy-in (400 each)", botStacks[1] == 400 and botStacks[2] == 400 and botStacks[3] == 400,
  table.concat(botStacks, ","))
Press(host, "Options")
host.env.Fire(BlindsButton(host, ">"), "OnClick", "LeftButton")
Check("changing them while seated: this table stays, with a note", Shown(host, "This table stays at 10/20") ~= nil
  and Shown(host, "Blinds 10/20") ~= nil)
Press(host, "Done")
-- a reload while seated keeps the table's blinds
local saved = host.ns.db
local c2 = NewClient("Host2")
-- load the same save into a fresh client
local env3 = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
env3.arg = { ADDON }; env3.SELECT_SAVED = select
assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env3))()
env3.CowCasinoDB = saved
for _, o in ipairs(env3.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env3.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
env3.CowCasinoFrame:Show()
env3.CowCasino.ns:OpenGame("holdem")
local T3 = env3.CowCasino.ns.games.holdem.T
local found = false
for _, f in ipairs(env3.all) do if f.kind == "FontString" and f.text == "Blinds 10/20" then found = true end end
Check("after a reload the table is still at 10/20 (not the new 25/50)", found and T3.seats[1] ~= nil)
-- leave: the lobby shows the new level
local guard = 0
while T.street ~= "idle" and guard < 2000 do
  if MyTurn(host) then Press(host, "Fold") end
  Tick(0.5); guard = guard + 1
end
T.hand = T.hand + 1   -- stop the next deal
Press(host, "Leave table", true)
Check("after leaving, the lobby is at the new 25/50", Shown(host, "blinds 25/50") ~= nil and Find(host, "1,000") and Find(host, "5,000") and true)

-- Party: Bob joins Host's 25/50 table and plays the host's blinds
Press(host, "Play with your party")
Check("party panel: your table's blinds and buy-in", Shown(host, "Your table: blinds 25/50, buy-in 2,500") ~= nil)
Press(host, "Host a table")
Run(2)
Press(bob, "Play with your party")
Run(1)
Check("bob sees the host's blinds", Shown(bob, "Host: blinds 25/50") ~= nil)
local bobBefore = bob.ns.db.chips
Press(bob, "Join")
Run(8)
Check("bob buys in for 50 of the host's big blinds (2,500)", bob.T.mode == "client" and bob.ns.db.chips == bobBefore - 2500,
  bobBefore - bob.ns.db.chips)
Check("bob's table shows 25/50 (his own setting is 5/10)", Shown(bob, "Blinds 25/50") ~= nil)
-- play a hand where bob is to act: his raise steps are the host's big blind
local stepOk = nil
for _ = 1, 400 do
  Tick(0.2)
  if MyTurn(bob) and Find(bob, "+") then
    local r0 = bob.T.raiseTo
    Press(bob, "+")
    stepOk = (bob.T.raiseTo - r0 == 50) or (bob.T.raiseTo == bob.T.seats[bob.T.mySeat].stack + bob.T.seats[bob.T.mySeat].bet)
    Press(bob, "Fold")
    break
  end
  if MyTurn(host) then Press(host, Enabled(host, "Check") and "Check" or "Call", true) end
end
Check("bob's raise steps by the table's big blind (50)", stepOk == true)
io.write(ok and "BLINDS PASS\n" or "BLINDS FAIL\n")
os.exit(ok and 0 or 1)
