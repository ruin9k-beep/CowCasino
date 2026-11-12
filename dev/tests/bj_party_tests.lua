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
      if string.sub(part, 1, 5) == "BJ;K;" then LAST_KICK = part end
      if string.sub(part, 1, 5) == "BJ;P;" and name == "Host" then LAST_P = part end
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
  ns:OpenGame("blackjack")
  -- Party play lives inside Blackjack now: press its "Party play" button.
  for _, o in ipairs(env.all) do
    if o.kind == "Button" and o.text == "Party play" then env.Fire(o, "OnClick", "LeftButton") end
  end
  local c = { name = name, env = env, ns = ns, P = ns.PartyBlackjack }
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


---------------------------------------------------------------------------
-- Party Blackjack tests (body; appended to bj_head.lua)
---------------------------------------------------------------------------
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
local function RunUntil(cond, limit)
  local t = 0
  while not cond() and t < (limit or 120) do Tick(0.1); t = t + 0.1 end
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
local function Find(c, text, prefix)
  for _, o in ipairs(c.env.all) do
    if o.kind == "Button" and InPanel(c, o) then
      if o.text == text or (prefix and string.sub(o.text, 1, string.len(text)) == text) then return o end
    end
  end
end
local function Enabled(c, text, prefix) local b = Find(c, text, prefix); return b ~= nil and b.enabled ~= nil end
local function Press(c, text, prefix)
  local b = Find(c, text, prefix)
  assert(b, c.name .. ": no button " .. text)
  assert(b.enabled, c.name .. ": button disabled: " .. b.text)
  c.env.Fire(b, "OnClick", "LeftButton")
  return b
end

-- Independent rules, written separately from the addon.
local function Val(cards)
  local t, a = 0, 0
  for _, c in ipairs(cards) do
    local v = c.rank == 1 and 11 or (c.rank >= 10 and 10 or c.rank)
    t = t + v
    if v == 11 then a = a + 1 end
  end
  while t > 21 and a > 0 do t = t - 10; a = a - 1 end
  return t
end
local function Codes(cards)
  local s = {}
  for _, c in ipairs(cards) do table.insert(s, c.hidden and "XX" or (c.rank .. "/" .. c.suit)) end
  return table.concat(s, " ")
end
local function C(rank, suit) return { rank = rank, suit = suit or 1 } end

---------------------------------------------------------------------------
-- Clients
---------------------------------------------------------------------------
local RIG = {}
local host = NewClient("Host")
local orig = host.ns.NewShoe
host.ns.NewShoe = function(self, d, p)
  local s = orig(self, d, p)
  local draw = s.Draw
  s.Draw = function(sh)
    if RIG[1] then return table.remove(RIG, 1) end
    return draw(sh)
  end
  return s
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
local function Heard(c, name, from)
  local n = 0
  for k = from or 1, table.getn(c.played) do if c.played[k] == name then n = n + 1 end end
  return n
end

-- The hole card must never travel while players are still deciding.
local holeLeak, lastZ2 = nil, nil
HOOK = function(name, text)
  if name ~= "Host" then return end
  local f = {}
  for part in string.gfind(text .. ";", "([^;]*);") do table.insert(f, part) end
  if f[2] == "Z" and f[5] == "2" then lastZ2 = tonumber(f[6]) end
  if f[2] ~= "P" then return end
  local phase, dealer = f[6], f[10] or ""
  if (phase == "i" or phase == "p") and string.len(dealer) >= 4 and string.sub(dealer, 3, 4) ~= "XX" then
    holeLeak = text
  end
end

Check("dan alone: can't host", not Enabled(dan, "Host a table"))
group = { "Host", "Bob", "Cid" }
GroupChanged()
Run(1)

Press(host, "Host a table")          -- default 500
Run(1)
Check("host: table open, wallet paid 500", host.T.mode == "host" and host.ns.db.chips == 4500 and host.T.seats[1].stack == 500)
bob.P:OnShow()
Run(1)
Check("bob: sees Host's table", Enabled(bob, "Join"))
Press(bob, ">")                      -- 1,000
Press(bob, "Join")
Run(2)
Check("bob: seated with 1,000", bob.T.mode == "client" and bob.ns.db.chips == 4000 and host.T.seats[2].name == "Bob"
  and host.T.seats[2].stack == 1000)
cid.P:OnShow()
Run(1)
Press(cid, "Join")
Run(2)
Check("cid: seated with 500", cid.T.mode == "client" and cid.ns.db.chips == 4500 and host.T.seats[3].stack == 500)
Check("dan (not in group): no tables listed", Find(dan, "Join") == nil)

-- Portraits: every player at the table gets one, aimed at the right person.
Run(1)
local function SeatFor(c, who)
  for i, st in ipairs(c.P.ui.seats) do
    if st.name:GetText() == who then return st, i end
  end
end
local hb = SeatFor(host, "Bob")
local cy = SeatFor(cid, "You")
local ch = SeatFor(cid, "Host")
Check("portraits: host sees Bob", hb and hb.portrait:IsShown() and hb.portrait.unit == host.ns.Net:UnitFor("Bob") and (hb.portrait.camera == 0 or hb.portrait.zoom == 1),
  hb and tostring(hb.portrait.unit))
Check("portraits: your own seat shows you", cy and cy.portrait.unit == "player")
Check("portraits: Cid sees the host", ch and ch.portrait.unit == cid.ns.Net:UnitFor("Host"))
local empty
for _, st in ipairs(host.P.ui.seats) do if string.find(st.name:GetText(), "Empty") then empty = st end end
Check("portraits: empty seats have none", empty and not empty.portrait:IsShown())
local bobUnit = host.ns.Net:UnitFor("Bob")
host.env.UNIT_VISIBLE[bobUnit] = false
Run(3)
Check("portraits: out of range shows the question mark", hb.portrait.model == host.env.QUESTION_MODEL)
host.env.UNIT_VISIBLE[bobUnit] = nil
Run(3)
Check("portraits: back in range shows Bob", hb.portrait.unit == bobUnit)

---------------------------------------------------------------------------
-- Rigged rounds
---------------------------------------------------------------------------
local function WaitBetting()
  return RunUntil(function() return host.T.phase == "betting" and Enabled(host, "Place bet")
    and Enabled(bob, "Place bet") and Enabled(cid, "Place bet") end, 60)
end
local function BetAll(deal)
  assert(WaitBetting(), "no betting phase")
  for _, c in ipairs({ host, bob, cid }) do
    Press(c, "Clear"); Press(c, "25")
  end
  RIG = deal
  for _, c in ipairs({ host, bob, cid }) do Press(c, "Place bet") end
  Run(1.5)
end
local function JoinFully(c)
  c.P:OnShow()
  if not RunUntil(function() return Enabled(c, "Join") end, 10) then return false end
  Press(c, "Join")
  return RunUntil(function() return c.T.mode == "client" end, 90)
end
local function Stacks() return host.T.seats[1].stack, host.T.seats[2].stack, host.T.seats[3].stack end
local function WaitSettled() return RunUntil(function() return host.T.phase == "settled" end, 60) end

-- A: dealer Ace up with blackjack; insurance for host (blackjack) and Bob.
local h0, b0, c0 = Stacks()
local markH, markB, markC = table.getn(host.played) + 1, table.getn(bob.played) + 1, table.getn(cid.played) + 1
BetAll({ C(1), C(10), C(10), C(1, 2), C(13), C(9), C(7), C(13, 2) })
Check("A: insurance offered to all three", host.T.phase == "insurance" and Find(bob, "Insure", true) ~= nil
  and Find(cid, "No thanks") ~= nil)
Check("A: clients see the hole card face down", bob.T.holeHidden and bob.T.dealer[2] and bob.T.dealer[2].hidden == true
  and cid.T.dealer[2].hidden == true)
Press(host, "Insure", true); Press(bob, "Insure", true); Press(cid, "No thanks")
Run(1.5)
Check("A: settled at once on dealer blackjack", host.T.phase == "settled")
local h1, b1, c1 = Stacks()
Check("A: host BJ push + insurance (13 on 25, pays 26) = +26", h1 - h0 == 26, tostring(h1 - h0))
Check("A: bob lose + insurance (13, pays 26) = +1", b1 - b0 == 1, tostring(b1 - b0))
Check("A: cid loses 25", c1 - c0 == -25, tostring(c1 - c0))
Run(1)
Check("A: clients see the dealer blackjack", Codes(bob.T.dealer) == "1/2 13/2" and Codes(cid.T.dealer) == "1/2 13/2")
Check("sounds: everyone hears the new hand", Heard(host, "MapPing", markH) == 1 and Heard(bob, "MapPing", markB) == 1
  and Heard(cid, "MapPing", markC) == 1)
Check("sounds: host wins (+25) -> coins", Heard(host, "LOOTWINDOWCOINSOUND", markH) == 1 and Heard(host, "igQuestCancel", markH) == 0)
Check("sounds: bob nets +1 (insurance rounded up) -> coins", Heard(bob, "LOOTWINDOWCOINSOUND", markB) == 1 and Heard(bob, "igQuestCancel", markB) == 0)
Check("sounds: cid loses -> lose sound", Heard(cid, "igQuestCancel", markC) == 1 and Heard(cid, "LOOTWINDOWCOINSOUND", markC) == 0)
Check("A: bob's client shows even result", string.find(bob.T.seats[2].hands[1].result or "", "L") ~= nil)

local function StatusText(c) return c.P.ui.status:GetText() end
local function SeatLine(c, i) return c.P.ui.seats[i].bet:GetText() end
Check("A: insurance results reach every screen", host.T.seats[2].insPaid == true and bob.T.seats[2].insPaid == true
  and cid.T.seats[2].insPaid == true)
Check("A: bob's screen shows the result with the insurance", string.find(StatusText(bob), "You win 1! Insurance paid 26.", 1, true) ~= nil, StatusText(bob))
Check("A: seat line shows the insurance win", string.find(SeatLine(cid, 2), "ins +26", 1, true) ~= nil, SeatLine(cid, 2))

-- E: dealer Ace up without blackjack: insurance is lost and shown as lost; the hole card stays face down for everyone.
local hE, bE = host.T.seats[1].stack, host.T.seats[2].stack
BetAll({ C(10), C(10), C(10), C(1, 4), C(9), C(8), C(7), C(7, 4) })
Check("E: insurance phase", host.T.phase == "insurance")
Check("E: hole card face down on the host's screen", host.P.ui.dealerCards[2].faceUp == false and host.P.ui.dealerCards[2].card ~= nil)
Check("E: hole card face down on the clients' screens", bob.P.ui.dealerCards[2].faceUp == false and cid.P.ui.dealerCards[2].faceUp == false)
Check("E: dealer label shows only the ace", host.P.ui.dealerLabel:GetText() == "Dealer shows 11", host.P.ui.dealerLabel:GetText())
Press(host, "No thanks"); Press(bob, "Insure", true); Press(cid, "No thanks")
Run(1.5)
Check("E: no blackjack: play goes on", host.T.phase == "playing")
Check("E: bob's insurance shown as lost everywhere", host.T.seats[2].insPaid == false and bob.T.seats[2].insPaid == false
  and string.find(SeatLine(cid, 2), "ins lost", 1, true) ~= nil, SeatLine(cid, 2))
Check("E: hole card still face down while players decide", host.P.ui.dealerCards[2].faceUp == false and bob.P.ui.dealerCards[2].faceUp == false)
Press(host, "Stand"); Run(1.5)
Press(bob, "Stand"); Run(1.5)
Press(cid, "Stand")
Check("E: settles", WaitSettled())
Run(1)
Check("E: hole card turned up at the end", host.P.ui.dealerCards[2].faceUp == true and bob.P.ui.dealerCards[2].faceUp == true)
Check("E: bob 18 vs 18 push, insurance lost: -13 (half of 25, rounded up)", host.T.seats[2].stack - bE == -13, host.T.seats[2].stack - bE)
Check("E: bob's screen says insurance lost", string.find(StatusText(bob), "Insurance lost.", 1, true) ~= nil, StatusText(bob))

-- B: host splits 8s and doubles hand 1; Bob surrenders; Cid hits; dealer busts.
h0, b0, c0 = Stacks()
BetAll({ C(8), C(10), C(10), C(6), C(8, 2), C(6), C(2), C(10, 3),
         C(3), C(10), C(10, 2), C(5), C(10, 4) })
Check("B: host's turn with split allowed", host.T.phase == "playing" and host.T.actor == 1 and Enabled(host, "Split"))
Check("B: others can't act yet", Find(bob, "Hit") == nil and Find(cid, "Hit") == nil)
Press(host, "Split"); Run(0.5)
Check("B: hand 1 has 8,3; double allowed after split", Codes(host.T.seats[1].hands[1].cards) == "8/1 3/1" and Enabled(host, "Double"))
Check("B: surrender not allowed after split", not Enabled(host, "Surrender"))
Press(host, "Double"); Run(0.5)
Check("B: hand 2 dealt its second card on arrival", Codes(host.T.seats[1].hands[2].cards) == "8/2 10/2" and host.T.handIdx == 2)
Press(host, "Stand"); Run(1.5)
Check("B: bob's turn on his client", Find(bob, "Surrender") ~= nil and bob.T.actor == 2)
Press(bob, "Surrender"); Run(1.5)
Press(cid, "Hit"); Run(1.5)
Check("B: cid has 17", Val(host.T.seats[3].hands[1].cards) == 17 and Find(cid, "Stand") ~= nil)
Press(cid, "Stand")
Check("B: settles", WaitSettled())
h1, b1, c1 = Stacks()
Check("B: host +75 (doubled split win + split win)", h1 - h0 == 75, tostring(h1 - h0))
Check("B: bob -12 (surrender gets 13 of 25 back)", b1 - b0 == -12, tostring(b1 - b0))
Check("B: cid +25", c1 - c0 == 25, tostring(c1 - c0))
Check("B: dealer drew to bust", Val(host.T.dealer) == 26)
Run(1)
Check("B: clients agree on the host's split hands", Codes(bob.T.seats[1].hands[1].cards) == "8/1 3/1 10/1"
  and Codes(cid.T.seats[1].hands[2].cards) == "8/2 10/2")

-- C: split aces get one card each, and 21 after a split pays 1:1.
h0, b0, c0 = Stacks()
BetAll({ C(1), C(10), C(9), C(10, 2), C(1, 2), C(10, 3), C(9, 2), C(7), C(13), C(5) })
Press(host, "Split"); Run(1.5)
Check("C: both ace hands done after one card", host.T.actor == 2 and Codes(host.T.seats[1].hands[2].cards) == "1/2 5/1")
Press(bob, "Stand"); Run(1.5)
Check("C: cid can split 9s", Enabled(cid, "Split"))
Press(cid, "Stand")
Check("C: settles", WaitSettled())
h1, b1, c1 = Stacks()
Check("C: host even (21 pays 1:1, 16 loses)", h1 - h0 == 0, tostring(h1 - h0))
Check("C: bob +25, cid +25", b1 - b0 == 25 and c1 - c0 == 25)

-- D: player blackjack pays 3:2, dealer stands on soft 17.
h0, b0, c0 = Stacks()
BetAll({ C(1), C(10), C(10), C(1, 3), C(13), C(7), C(10, 4), C(6) })
Press(host, "No thanks"); Press(bob, "No thanks"); Press(cid, "No thanks")
Run(1.5)
Check("D: host blackjack skips the turn", host.T.phase ~= "playing" or host.T.actor ~= 1)
Press(bob, "Stand"); Run(1.5)
Press(cid, "Stand")
Check("D: settles", WaitSettled())
h1, b1, c1 = Stacks()
Check("D: dealer stood on soft 17", table.getn(host.T.dealer) == 2)
Check("D: host +38 (3:2 on 25, rounded up), bob push, cid +25", h1 - h0 == 38 and b1 - b0 == 0 and c1 - c0 == 25,
  (h1 - h0) .. "," .. (b1 - b0) .. "," .. (c1 - c0))
Check("hole card never sent during decisions (rigged)", holeLeak == nil, holeLeak)

---------------------------------------------------------------------------
-- Random play
---------------------------------------------------------------------------
math.randomseed(tonumber(arg[2]) or 7)
RIG = {}
local problems, rounds, consistent, pendingCheck = {}, 0, 0, nil
local function Problem(msg) if table.getn(problems) < 8 then table.insert(problems, msg) end end
local netTotal = 0
local preStack, lastPhase, lastRound = {}, nil, nil
local actors = { host, bob, cid }
local nextAct = {}
local idle = {}       -- name -> "all" (never acts) or "play" (bets, never plays)

local function RandomAct(c)
  if idle[c.name] == "all" then return end
  if CLOCK < (nextAct[c.name] or 0) then return end
  local acted = false
  if Find(c, "Place bet") then
    Press(c, "Clear")
    if not Find(c, "Place bet") then return end   -- the redraw showed we're already in
    for _ = 1, math.random(1, 2) do
      local chips = { "5", "5", "25" }
      Press(c, chips[math.random(1, 3)])
    end
    if Enabled(c, "Place bet") then Press(c, "Place bet") end
    acted = true
  elseif idle[c.name] == "play" then
    return
  elseif Find(c, "No thanks") then
    if math.random() < 0.3 and Enabled(c, "Insure", true) then Press(c, "Insure", true) else Press(c, "No thanks") end
    acted = true
  elseif Find(c, "Hit") then
    local opts = {}
    for _, n in ipairs({ "Hit", "Stand", "Double", "Split", "Surrender" }) do
      if Enabled(c, n) then table.insert(opts, n) end
    end
    local hv = Val(c.T.seats[c.T.mySeat].hands[c.T.handIdx].cards)
    local pick
    if Enabled(c, "Split") and math.random() < 0.6 then pick = "Split"
    elseif Enabled(c, "Double") and math.random() < 0.2 then pick = "Double"
    elseif Enabled(c, "Surrender") and math.random() < 0.05 then pick = "Surrender"
    elseif hv < 17 and Enabled(c, "Hit") then pick = "Hit"
    else pick = opts[math.random(1, table.getn(opts))] end
    Press(c, pick)
    acted = true
  end
  if acted then nextAct[c.name] = CLOCK + 0.2 + math.random() * 3 end
end

local function VerifySettle()
  local T = host.T
  local dbj = table.getn(T.dealer) == 2 and Val(T.dealer) == 21
  local live = false
  for i = 1, 4 do
    local p = T.seats[i]
    if table.getn(p.hands) > 0 and preStack[i] then
      local expect = preStack[i] - (p.insurance or 0) + ((dbj and (p.insurance or 0) * 3) or 0)
      for _, h in ipairs(p.hands) do
        local pv = Val(h.cards)
        local pbj = table.getn(h.cards) == 2 and pv == 21 and table.getn(p.hands) == 1
        local pay
        if h.surrendered then pay = math.ceil(h.bet / 2)
        elseif pv > 21 then pay = 0
        elseif pbj and not dbj then pay = h.bet + math.ceil(h.bet * 1.5)
        elseif dbj and not pbj then pay = 0
        elseif pbj and dbj then pay = h.bet
        elseif Val(T.dealer) > 21 or pv > Val(T.dealer) then pay = h.bet * 2
        elseif pv < Val(T.dealer) then pay = 0
        else pay = h.bet end
        if pay ~= h.payout then Problem("round " .. T.round .. " seat " .. i .. ": payout " .. tostring(h.payout) .. " expected " .. pay) end
        expect = expect - h.bet + pay
        if not h.surrendered and pv <= 21 and not pbj then live = true end
        if h.splitAces and table.getn(h.cards) ~= 2 then Problem("split ace hand with " .. table.getn(h.cards) .. " cards") end
        if h.doubled and table.getn(h.cards) ~= 3 then Problem("doubled hand with " .. table.getn(h.cards) .. " cards") end
      end
      if p.stack ~= math.floor(p.stack) then Problem("round " .. T.round .. " seat " .. i .. ": half chips in stack " .. p.stack) end
      if (p.insurance or 0) ~= math.floor(p.insurance or 0) then Problem("round " .. T.round .. " seat " .. i .. ": half-chip insurance") end
      if math.abs(expect - p.stack) > 0.001 then
        Problem("round " .. T.round .. " seat " .. i .. ": stack " .. p.stack .. " expected " .. expect)
      end
      netTotal = netTotal + (p.stack - preStack[i])
    end
  end
  local n = table.getn(T.dealer)
  if dbj then
    if n ~= 2 then Problem("dealer blackjack with extra cards") end
  elseif live then
    if Val(T.dealer) < 17 then Problem("dealer stopped at " .. Val(T.dealer)) end
    if n > 2 then
      local before = {}
      for k = 1, n - 1 do before[k] = T.dealer[k] end
      if Val(before) >= 17 then Problem("dealer hit on " .. Val(before)) end
    end
  elseif n ~= 2 then
    Problem("dealer drew with no live hands")
  end
end

local function VerifyMirror()
  local T = host.T
  local ok = true
  for _, c in ipairs({ bob, cid }) do
    if c.T.mode == "client" then
      if c.T.round ~= T.round or c.T.phase ~= "settled" then ok = false; Problem(c.name .. ": phase " .. c.T.phase .. " round " .. c.T.round .. " vs " .. T.round) end
      if Codes(c.T.dealer) ~= Codes(T.dealer) then ok = false; Problem(c.name .. ": dealer " .. Codes(c.T.dealer) .. " vs " .. Codes(T.dealer)) end
      for i = 1, 4 do
        local a, b = c.T.seats[i], T.seats[i]
        if (b.kind == "empty") ~= (a.kind == "empty") then ok = false; Problem(c.name .. ": seat " .. i .. " kind") end
        if b.kind ~= "empty" then
          if math.abs((a.stack or 0) - b.stack) > 0.001 then ok = false; Problem(c.name .. ": seat " .. i .. " stack " .. tostring(a.stack) .. " vs " .. b.stack) end
          if table.getn(a.hands) ~= table.getn(b.hands) then ok = false; Problem(c.name .. ": seat " .. i .. " hand count") end
          for k, h in ipairs(b.hands) do
            local ah = a.hands[k]
            if not ah or Codes(ah.cards) ~= Codes(h.cards) or ah.result ~= h.result or ah.bet ~= h.bet then
              ok = false; Problem(c.name .. ": seat " .. i .. " hand " .. k .. " differs")
            end
          end
        end
      end
    end
  end
  if ok then consistent = consistent + 1 end
end

local hiddenOk = true
onTick = function()
  local T = host.T
  if T.mode ~= "host" then return end
  if T.phase == "betting" then
    for i = 1, 4 do preStack[i] = T.seats[i].kind ~= "empty" and T.seats[i].stack or nil end
  end
  if T.phase == "settled" and (lastPhase ~= "settled" or lastRound ~= T.round) then
    rounds = rounds + 1
    VerifySettle()
    pendingCheck = { at = CLOCK + 1.5, round = T.round }
  end
  if pendingCheck and CLOCK >= pendingCheck.at then
    if T.phase == "settled" and T.round == pendingCheck.round then VerifyMirror() end
    pendingCheck = nil
  end
  for _, c in ipairs({ bob, cid }) do
    if c.T.mode == "client" and (c.T.phase == "insurance" or c.T.phase == "playing") and c.T.dealer[2]
      and not c.T.dealer[2].hidden then hiddenOk = false end
  end
  lastPhase, lastRound = T.phase, T.round
  for _, c in ipairs(actors) do RandomAct(c) end
end

local function TableAndWallets()
  local s = 0
  for _, c in ipairs({ host, bob, cid }) do s = s + c.ns.db.chips end
  for i = 1, 4 do if host.T.seats[i] and host.T.seats[i].kind ~= "empty" then s = s + host.T.seats[i].stack end end
  return s
end
-- Count from a betting phase so the books are clean.
RunUntil(function() return host.T.phase == "betting" end, 60)
local startSum = TableAndWallets()
netTotal = 0
Run(900)
RunUntil(function() return host.T.phase == "betting" end, 60)
Check("random: rounds played", rounds >= 40, tostring(rounds))
Check("random: payouts and stacks match independent rules", table.getn(problems) == 0, problems[1])
Check("random: clients mirror the host after every round", consistent >= rounds - 2, consistent .. "/" .. rounds)
Check("random: hole card hidden on clients during play", hiddenOk)
Check("random: hole card never sent during decisions", holeLeak == nil, holeLeak)
Check("random: chips accounted for", math.abs(TableAndWallets() - (startSum + netTotal)) < 0.001,
  TableAndWallets() .. " vs " .. (startSum + netTotal))
Check("random: messages within 254 chars", stats.longest <= 254, "longest " .. stats.longest)

---------------------------------------------------------------------------
-- Not responding: Cid bets but never plays -> removed after 2 missed turns
---------------------------------------------------------------------------
problems = {}
idle.Cid = "play"
local cidWallet = cid.ns.db.chips
-- make sure Cid has chips to lose (random play may have emptied his stack)
if cid.T.mode ~= "client" or host.T.seats[cid.T.mySeat].stack < 100 then
  idle.Cid = "all"
  if cid.T.mode == "client" then
    RunUntil(function() return Enabled(cid, "Leave table") end, 120)
    Press(cid, "Leave table"); Run(2)
  end
  JoinFully(cid)
  idle.Cid = "play"
  cidWallet = cid.ns.db.chips
end
Check("timeout: cid seated with chips", cid.T.mode == "client" and host.T.seats[cid.T.mySeat].stack >= 100)
local kicked = RunUntil(function() return cid.T.mode == "lobby" end, 400)
Check("timeout: cid removed after missed turns", kicked and host.T.seats[3].kind == "empty")
local kickedStack = LAST_KICK and tonumber(string.sub(LAST_KICK, string.find(LAST_KICK, "[%d%.]+$")))
Check("timeout: cid got his stack back", kickedStack ~= nil and math.abs(cid.ns.db.chips - (cidWallet + kickedStack)) < 0.001,
  tostring(kickedStack))
Check("timeout: no payout problems", table.getn(problems) == 0, problems[1])
idle.Cid = "all"

-- Bob leaves between rounds.
if bob.T.mode ~= "client" or host.T.seats[bob.T.mySeat].stack < 5 then
  if bob.T.mode == "client" then
    RunUntil(function() return Enabled(bob, "Leave table") end, 120)
    Press(bob, "Leave table"); Run(2)
  end
  JoinFully(bob)
end
idle.Bob = "all"
RunUntil(function() return Enabled(bob, "Leave table") end, 120)
local bobStack, bobWallet = host.T.seats[2].stack, bob.ns.db.chips
Press(bob, "Leave table")
Run(2)
-- if a round had just started, the host frees the seat when it ends
RunUntil(function() return host.T.seats[2].kind == "empty" end, 120)
Check("leave: bob back in the lobby with his stack", bob.T.mode == "lobby" and math.abs(bob.ns.db.chips - (bobWallet + bobStack)) < 0.001
  and host.T.seats[2].kind == "empty")

-- Bob rejoins; the host disappears mid-round: Bob gets back his stack from before the round.
idle.Bob = nil
JoinFully(bob)
Check("rejoin: bob seated", bob.T.mode == "client")
local before
RunUntil(function() return host.T.phase == "betting" end, 60)
RunUntil(function()
  if host.T.phase == "betting" and bob.T.mode == "client" then before = host.T.seats[bob.T.mySeat].stack end
  return host.T.phase == "playing" and host.T.seats[bob.T.mySeat].inRound
end, 200)
bobWallet = bob.ns.db.chips
local savedHostActors = actors
actors = {}
group = { "Bob", "Cid" }
GroupChanged()
Run(1)
Check("host gone: bob refunded his pre-round stack", bob.T.mode == "lobby" and before ~= nil
  and math.abs(bob.ns.db.chips - (bobWallet + before)) < 0.001, tostring(before))
-- the host's own table: close it when the host is solo, then re-form the group
group = { "Host", "Bob", "Cid" }
GroupChanged()
actors = savedHostActors

-- Close after round: host asks mid-round; Bob ends up with his settled stack.
Check("close: bob rejoins after the host returns", JoinFully(bob))
local tid = host.T.tid
RunUntil(function() return host.T.phase == "playing" and host.T.seats[2] and host.T.seats[2].inRound end, 200)
Check("close: button reads Close after round", Enabled(host, "Close after round"))
bobWallet = bob.ns.db.chips
Press(host, "Close after round")
RunUntil(function() return host.T.mode == "lobby" end, 200)
Run(3)
local finalBob = lastZ2
Check("close: host back in lobby", host.T.mode == "lobby" and host.ns.db.partybj.host == nil)
Check("close: bob cashed out with his settled stack", bob.T.mode == "lobby" and finalBob ~= nil
  and math.abs(bob.ns.db.chips - (bobWallet + finalBob)) < 0.001, tostring(finalBob))
Check("close: offer gone from bob's lobby", Find(bob, "Join") == nil)

---------------------------------------------------------------------------
-- Waiting to join when the table closes; asking a host who never answers
---------------------------------------------------------------------------
idle.Bob = "all"
idle.Host = "all"
Press(host, "Host a table")
RunUntil(function() return host.T.phase == "betting" end, 10)
RIG = { C(10), C(9), C(10, 2), C(7) }
Press(host, "Place bet")
RunUntil(function() return host.T.phase == "playing" end, 30)
bob.P:OnShow(); Run(1)
Press(bob, "Join"); Run(2)
Check("join mid-round: told to wait", bob.T.joining ~= nil and bob.T.joining.waiting == true)
Press(host, "Close after round")
RunUntil(function() return host.T.mode == "lobby" end, 120)
Run(3)
Check("join mid-round: table closed, request cleared", bob.T.joining == nil and bob.T.mode == "lobby")
idle.Host = nil
bob.T.offers.Cid = { tid = "999", players = 1, open = 3, heard = CLOCK }
bob.P:OnShow(); Run(0.5)
bob.T.offers.Cid = { tid = "999", players = 1, open = 3, heard = CLOCK }
Press(bob, "Join"); Run(1)
Check("no answer: request pending", bob.T.joining ~= nil)
Run(16)
Check("no answer: request dropped after 15s, Join usable again", bob.T.joining == nil)

---------------------------------------------------------------------------
-- Reload safety: saved seat / hosted table are paid back on load
---------------------------------------------------------------------------
PREP = function(ns)
  ns.db.chips = 1000
  ns.db.partybj = { seat = { host = "Nobody", tid = "1", stack = 300 } }
end
local eve = NewClient("Eve")
PREP = nil
Check("reload: seat refunded once", eve.ns.db.chips == 1300 and eve.ns.db.partybj.seat == nil)
PREP = function(ns)
  ns.db.chips = 1000
  ns.db.partybj = { host = { stack = 450 } }
end
local fay = NewClient("Fay")
PREP = nil
Check("reload: hosted table refunded once", fay.ns.db.chips == 1450 and fay.ns.db.partybj.host == nil)

io.write(string.format("messages sent %d, longest %d\n", stats.sent, stats.longest))
io.write(ok and "ALL PASS\n" or "SOME FAILED\n")
os.exit(ok and 0 or 1)
