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
  for i = 1, 4 do s = s + T.seats[i].stack + T.seats[i].bet end
  return s
end

---------------------------------------------------------------------------
local host = NewClient("Host")
local bob = NewClient("Bob")
local cid = NewClient("Cid")
for _, c in ipairs({ host, bob, cid }) do
  local c = c
  c.played = {}
  local real = c.env.PlaySound
  c.env.PlaySound = function(n) table.insert(c.played, c.env.SoundName(n)); real(n) end
end
local function Heard(c, name)
  local n = 0
  for _, x in ipairs(c.played) do if x == name then n = n + 1 end end
  return n
end
local dan = NewClient("Dan")      -- not in the party
host.P.SetSims(20)
group = { "Host", "Bob", "Cid" }
GroupChanged()
Run(1)

-- /casino net: a report, and a ping every CowCasino in the group answers
local printed = {}
host.env.DEFAULT_CHAT_FRAME.AddMessage = function(_, m) table.insert(printed, m) end
host.env.SlashCmdList.COWCASINO("net")
Run(3)
local text = table.concat(printed, "\n")
Check("/casino net: reports the channel and the members", string.find(text, "channel PARTY", 1, true) ~= nil
  and string.find(text, "Bob", 1, true) ~= nil and string.find(text, "Cid", 1, true) ~= nil, printed[1])
Check("/casino net: Bob and Cid answer the ping with their version", string.find(text, "Bob answered (CowCasino test)", 1, true) ~= nil
  and string.find(text, "Cid answered (CowCasino test)", 1, true) ~= nil, printed[table.getn(printed)])

-- Host types in the blinds and buy-in, and opens a table (computer players
-- fill the empty seat).
local function Boxes(c)
  local t = {}
  for _, o in ipairs(c.env.all) do if o.kind == "EditBox" and InPoker(c, o) then table.insert(t, o) end end
  return t[1], t[2], t[3]     -- small blind, big blind, buy-in
end
Press(host, "Play with your party")
local sbBox, bbBox, buyBox = Boxes(host)
Check("host: blinds and buy-in boxes, filled from last time (5/10, 500)", sbBox and sbBox.text == "5" and bbBox.text == "10"
  and buyBox.text == "500", sbBox and (sbBox.text .. "/" .. bbBox.text .. " " .. buyBox.text))
host.env.TypeInto(sbBox, "1x5")
Check("host: only digits go in", sbBox.text == "15", sbBox.text)
Check("host: a big blind smaller than the small blind can't host", not Find(host, "Host a table").enabled)
host.env.TypeInto(bbBox, "30")
host.env.TypeInto(buyBox, "200")
Check("host: a buy-in under 10 big blinds can't host", not Find(host, "Host a table").enabled)
host.env.TypeInto(buyBox, "")
Check("host: nor an empty one", not Find(host, "Host a table").enabled)
host.env.TypeInto(sbBox, "5"); host.env.TypeInto(bbBox, "10"); host.env.TypeInto(buyBox, "1000")
Check("host: 5/10 with a 1,000 buy-in is fine", Find(host, "Host a table").enabled and host.ns.db.holdem.hostSettings.buyin == 1000)
Press(host, "Host a table")
Run(1)
Check("host: table open with a free 1,000 stack, wallet untouched", host.T.mode == "host" and host.ns.db.chips == 5000 and host.T.seats[1].stack == 1000)

-- Bob and Cid find it and join.
Press(bob, "Play with your party")
Run(1)
Check("bob: sees Host's table", Find(bob, "Join") ~= nil and Find(bob, "Join").enabled ~= nil)
local listed
for _, o in ipairs(bob.env.all) do if type(o.text) == "string" and string.find(o.text, "Host: blinds 5/10, free 1,000 stack", 1, true) then listed = o.text end end
Check("bob: the table list shows the host's blinds and buy-in", listed ~= nil)
Press(bob, "Join")
Run(2)
Check("bob: seated free with the host's buy-in, 1,000", bob.T.mode == "client" and bob.ns.db.chips == 5000
  and host.T.seats[bob.T.mySeat].name == "Bob" and host.T.seats[bob.T.mySeat].stack == 1000)
Press(cid, "Play with your party")
Run(1)
Press(cid, "Join")
Run(2)
Check("cid: seated with 1,000 too", cid.T.mode == "client" and cid.ns.db.chips == 5000 and host.T.seats[cid.T.mySeat].stack == 1000)

-- Portraits: people get a 3D portrait, computer players don't.
local function SeatUI(c, who)
  for _, st in ipairs(c.P.ui.seats) do
    local n = string.gsub(st.name:GetText(), "^|cffffd100%(D%)|r ", "")
    if n == who then return st end
  end
end
Run(1)
local function UnitOf(c, who) return c.ns.Net:UnitFor(who) end
local hb = SeatUI(host, "Bob")
Check("portrait: host sees Bob's 3D portrait", hb and hb.portrait:IsShown() and hb.portrait.unit == UnitOf(host, "Bob")
  and (hb.portrait.camera == 0 or hb.portrait.zoom == 1), hb and tostring(hb.portrait.unit))
local mine = SeatUI(cid, "You")
Check("portrait: your own seat shows you", mine and mine.portrait:IsShown() and mine.portrait.unit == "player")
local botSeat
for _, st in ipairs(host.P.ui.seats) do
  local n = st.name:GetText()
  if not string.find(n, "Bob") and not string.find(n, "Cid") and not string.find(n, "You") and not string.find(n, "Empty") then botSeat = st end
end
Check("portrait: computer players have none", botSeat == nil or not botSeat.portrait:IsShown())
local bobUnit = UnitOf(host, "Bob")
host.env.UNIT_VISIBLE[bobUnit] = false
Run(3)
Check("portrait: out of range shows the question mark", hb.portrait:IsShown() and hb.portrait.unit == nil
  and hb.portrait.model == host.env.QUESTION_MODEL, tostring(hb.portrait.model))
host.env.UNIT_VISIBLE[bobUnit] = nil
Run(3)
Check("portrait: back in range shows Bob again", hb.portrait.unit == bobUnit and (hb.portrait.camera == 0 or hb.portrait.zoom == 1))
local hm = SeatUI(host, "You")
hm.portrait:Hide(); hm.portrait.unit = nil
hm.portrait:Show()
Check("portrait: re-applied when shown again", hm.portrait.unit == "player")
local kinds = {}
for i = 1, 4 do kinds[i] = host.T.seats[i].kind end
Check("host: 2 remote players + 1 computer player", table.concat(kinds, ",") == "you,remote,remote,bot" or table.concat(kinds, ",") == "you,remote,bot,remote"
  or table.concat(kinds, ",") == "you,bot,remote,remote", table.concat(kinds, ","))

-- Dan isn't in the party: he sees nothing and can't host.
Press(dan, "Play with your party")
Run(1)
Check("dan (not in group): no tables, can't host", Find(dan, "Join") == nil and not Enabled(dan, "Host a table"))
dan.env.Fire(Find(dan, "Close"), "OnClick", "LeftButton")

---------------------------------------------------------------------------
-- Play: everyone acts at random (quickly enough to beat the clock).
math.randomseed(tonumber(arg[2]) or 11)
local problems, handsSeen, consistent, privacyOk, holeOk = {}, 0, 0, true, true
local startSum, startHand = nil, nil
local function Problem(msg) if table.getn(problems) < 8 then table.insert(problems, msg) end end

local function RandomAct(c)
  local r = math.random()
  if r < 0.12 and Enabled(c, "Fold") then Press(c, "Fold")
  elseif r < 0.82 then
    local b = Find(c, "Call", true) or Find(c, "Check") or Find(c, "All-in", true)
    if b and b.enabled then c.env.Fire(b, "OnClick", "LeftButton") end
  else
    local rb = Find(c, "Raise to", true) or Find(c, "Bet", true)
    if rb and rb.enabled then
      if math.random() < 0.3 then Press(c, "Pot") end
      c.env.Fire(Find(c, "Raise to", true) or Find(c, "Bet", true) or Find(c, "All-in", true), "OnClick", "LeftButton")
    else
      local b = Find(c, "Call", true) or Find(c, "Check")
      if b and b.enabled then c.env.Fire(b, "OnClick", "LeftButton") end
    end
  end
end

local actingClients = { host, bob, cid }
onTick = function()
  local H = host.T
  -- chip conservation per hand, on the host
  if H.street ~= "idle" and H.hand ~= startHand then
    startHand, startSum = H.hand, TableChips(H)
    handsSeen = handsSeen + 1
  elseif H.street == "idle" and startHand == H.hand and startSum then
    if TableChips(H) ~= startSum then Problem("hand " .. H.hand .. ": chips " .. startSum .. " -> " .. TableChips(H)) end
    startSum = nil
  end
  -- clients agree with the host once everything has arrived
  if host.ns.Net:Queued() == 0 and table.getn(wire) == 0 then
    for _, c in ipairs({ bob, cid }) do
      if c.T.mode == "client" and c.T.version == H.version then
        consistent = consistent + 1
        for i = 1, 4 do
          local a, b = H.seats[i], c.T.seats[i]
          if a.stack ~= b.stack or a.bet ~= b.bet or (a.folded and true or false) ~= (b.folded and true or false) then
            Problem(c.name .. " disagrees on seat " .. i .. " stack " .. a.stack .. "/" .. b.stack)
          end
        end
        if H.pot ~= c.T.pot or H.street ~= c.T.street or table.getn(H.board) ~= table.getn(c.T.board) then
          Problem(c.name .. " disagrees on pot/street/board")
        end
        -- your own cards match; nobody else's are known before the reveal
        local mine = c.T.seats[c.T.mySeat]
        local real = H.seats[c.T.mySeat]
        if H.street ~= "idle" and not real.out and real.hole[2] then
          if not mine.hole[2] or mine.hole[1].rank ~= real.hole[1].rank or mine.hole[2].suit ~= real.hole[2].suit then holeOk = false end
        end
        if not c.T.reveal then
          for i = 1, 4 do
            if i ~= c.T.mySeat and c.T.seats[i].hole[1] then privacyOk = false end
          end
        end
      end
    end
  end
  -- players act
  for _, c in ipairs(actingClients) do
    if MyTurn(c) and math.random() < 0.15 then RandomAct(c) end
  end
end

-- what the dealer says at each seat
local dealerSaid = { Host = {}, Bob = {} }
local prevTick = onTick
onTick = function()
  prevTick()
  for who, set in pairs(dealerSaid) do
    local u = byName[who].ns.Dealer.UI()
    if u and u.text.text then set[u.text.text] = true end
  end
end
-- hands deal themselves once party members are seated
Check("first hand deals itself", host.T.street ~= "idle" or host.T.hand > 0, "hand " .. host.T.hand)
Run(900)
local withChips = 0
for i = 1, 4 do local p = host.T.seats[i]; if p.kind ~= "empty" and p.stack > 0 then withChips = withChips + 1 end end
if os.getenv("DEBUG") then
  for i = 1, 4 do local p = host.T.seats[i]; io.write(string.format("  dbg end seat %d %s %s stack=%d\n", i, p.kind, tostring(p.name), p.stack)) end
  io.write("  dbg street=", host.T.street, " hand=", host.T.hand, "\n")
end
Check("15 minutes of play: hands kept coming while 2+ players had chips", handsSeen >= 25 or withChips < 2,
  handsSeen .. " hands, " .. withChips .. " seats with chips at the end")
Check("chips conserved every hand", table.getn(problems) == 0, problems[1])
do
  local G = host.ns.dealers.goblin.lines
  local function Pattern(line)
    local q = string.gsub(line, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return "^" .. string.gsub(q, "{%w+}", ".-") .. "$"
  end
  for _, who in ipairs({ "Host", "Bob" }) do
    local kinds = {}
    for text in pairs(dealerSaid[who]) do
      for e, lines in pairs(G) do
        if string.sub(e, 1, 6) == "holdem" then
          for _, l in ipairs(lines) do if string.find(text, Pattern(l)) then kinds[e] = true end end
        end
      end
    end
    local n, list = 0, {}
    for e in pairs(kinds) do n = n + 1; table.insert(list, e) end
    table.sort(list)
    Check("Fizzlecog talks " .. who .. "'s table through the hands", kinds.holdemDeal and (kinds.holdemWin or kinds.holdemYouWin
      or kinds.holdemFoldWin or kinds.holdemYouFoldWin or kinds.holdemSplit) and n >= 5, table.concat(list, ","))
  end
end
for _, c in ipairs({ bob, cid }) do
  local st = c.ns.db.holdem.stats
  Check("sounds: " .. c.name .. " hears one new-hand sound per hand dealt", Heard(c, "MapPing") == st.hands,
    Heard(c, "MapPing") .. " sounds, " .. st.hands .. " hands")
  Check("sounds: " .. c.name .. " hears one win sound per hand won", Heard(c, "LOOTWINDOWCOINSOUND") == st.won,
    Heard(c, "LOOTWINDOWCOINSOUND") .. " sounds, " .. st.won .. " won")
  Check("sounds: " .. c.name .. " hears lose sounds, never more than hands lost", Heard(c, "igQuestCancel") > 0
    and Heard(c, "igQuestCancel") <= st.hands - st.won, Heard(c, "igQuestCancel") .. " lose sounds")
end
Check("clients always match the host's table", consistent > 100 and table.getn(problems) == 0, consistent .. " checks")
Check("your own hole cards arrive correctly", holeOk)
Check("nobody sees other players' cards before the reveal", privacyOk)
Check("every message fits the 1.12 limit (254)", stats.longest <= 254, "longest " .. stats.longest .. ", " .. stats.sent .. " sent")
Check("traffic stays low", stats.chars / CLOCK < 300, string.format("%.0f chars/s average", stats.chars / CLOCK))

-- Finish the current hand with everyone acting, then stop Bob from acting.
local function UntilIdle(maxSeconds)
  local t = 0
  while host.T.street ~= "idle" and t < maxSeconds do Tick(0.1); t = t + 0.1 end
end
UntilIdle(120)

-- Make sure a player is seated with chips (busted players sit out).
local function EnsureSeated(c)
  if c.T.mode == "client" and c.T.seats[c.T.mySeat].stack > 0 then return end
  local t = 0
  if c.T.mode == "client" then
    while not Enabled(c, "Leave table") and t < 900 do Tick(0.1); t = t + 0.1 end
    Press(c, "Leave table")
    Run(1)
  end
  Press(c, "Play with your party")
  Run(1)
  if not Find(c, "Join") then
    io.write("  dbg ", c.name, " can't see a table: host mode=", host.T.mode, " queued=", host.ns.Net:Queued(), " offers:")
    for n, o in pairs(c.T.offers) do io.write(" ", n, "@", string.format("%.0f", CLOCK - o.heard), "s open=", o.open) end
    io.write(" joining=", tostring(c.T.joining and c.T.joining.host), " mode=", c.T.mode, "\n")
    for i = 1, 4 do local p = host.T.seats[i]; io.write(string.format("  dbg host seat %d %s %s stack=%d leaving=%s\n", i, p.kind, tostring(p.name), p.stack, tostring(p.leaving))) end
  end
  Press(c, "Join")
  t = 0
  while c.T.mode ~= "client" and t < 900 do Tick(0.1); t = t + 0.1 end
  assert(c.T.mode == "client", c.name .. " was never seated")
  Run(1)
end

-- Bob goes silent: after two missed turns he's removed and refunded.
actingClients = {}
for _ = 1, 4 do
  UntilIdle(300)
  EnsureSeated(bob)
  EnsureSeated(cid)
  Run(3)
  if bob.T.mode == "client" and cid.T.mode == "client" then break end
end
actingClients = { host, cid }
local bobWalletBefore = bob.ns.db.chips
local bobSeat = bob.T.mySeat
local waited, lastStack = 0, nil
while bob.T.mode == "client" and waited < 600 do
  Tick(0.1); waited = waited + 0.1
  if host.T.seats[bobSeat].name == "Bob" then lastStack = host.T.seats[bobSeat].stack end
end
if os.getenv("DEBUG") or bob.T.mode == "client" then
  local hs = host.T.seats[bobSeat]
  io.write("  dbg bobSeat=", bobSeat, " bob.mySeat=", tostring(bob.T.mySeat), " bob stack(client)=", tostring(bob.T.seats[bob.T.mySeat] and bob.T.seats[bob.T.mySeat].stack), "\n")
  for i = 1, 4 do local p = host.T.seats[i]; io.write(string.format("  dbg host seat %d %s %s stack=%d out=%s\n", i, p.kind, tostring(p.name), p.stack, tostring(p.out))) end
  io.write("  dbg bob mode=", bob.T.mode, " lobbyMsg=", tostring(bob.P and bob.env.all and (function() for _, o in ipairs(bob.env.all) do if o.kind == "FontString" and o.text and string.find(o.text, "chips back", 1, true) then return o.text end end end)()), "\n")
  io.write("  dbg host seat: name=", tostring(hs.name), " kind=", hs.kind, " stack=", hs.stack, " out=", tostring(hs.out), " timeouts=", tostring(hs.timeouts), " kicked=", tostring(hs.kicked), " street=", host.T.street, " actor=", host.T.actor, "\n")
end
Check("silent player removed after two missed turns", bob.T.mode == "solo" and host.T.seats[bobSeat].name ~= "Bob",
  string.format("%.0fs", waited))
local kicked = LAST_KICK and tonumber(string.sub(LAST_KICK, (string.find(LAST_KICK, ";Bob;", 1, true) or 0) + 5))
Check("a removed player's wallet is untouched (the stack was free)", kicked and bob.ns.db.chips == bobWalletBefore,
  bobWalletBefore .. " + " .. tostring(kicked) .. " = " .. bob.ns.db.chips)

-- Cid leaves between hands.
EnsureSeated(cid)
UntilIdle(120)
actingClients = { host }
local cidStack = cid.T.mode == "client" and cid.T.seats[cid.T.mySeat].stack or 0
local cidWallet = cid.ns.db.chips
local cidSeat = cid.T.mySeat
if cid.T.mode == "client" then
  -- leave as soon as the table is between hands
  local t = 0
  while not Enabled(cid, "Leave table") and t < 120 do Tick(0.1); t = t + 0.1 end
  cidStack = cid.T.seats[cid.T.mySeat].stack
  Press(cid, "Leave table")
  Run(2)
end
Check("leaving leaves your wallet as it was (party stacks are free)", cid.ns.db.chips == cidWallet and cid.T.mode == "solo",
  cidWallet .. " + " .. cidStack .. " = " .. cid.ns.db.chips)
Check("host frees the seat", host.T.seats[cidSeat].kind ~= "remote" or host.T.seats[cidSeat].name ~= "Cid")

-- Bob rejoins; then the host disappears mid-hand.
Press(bob, "Play with your party")
Run(1)
Press(bob, "Join")
UntilIdle(120)
Run(3)
Check("bob rejoins", bob.T.mode == "client")
actingClients = { host, bob }
local t = 0
while not (host.T.street ~= "idle" and host.T.pot + host.T.seats[bob.T.mySeat].bet > 0 and host.T.seats[bob.T.mySeat].total > 0) and t < 120 do Tick(0.1); t = t + 0.1 end
local bobSeatNow = bob.T.mySeat
local bobStart = bob.T.seats[bob.T.mySeat].stack + bob.T.seats[bob.T.mySeat].total
local bobWallet = bob.ns.db.chips
group = { "Bob", "Cid" }     -- the host leaves the party
GroupChanged()
Run(1)
Check("host leaves mid-hand: clients back in the lobby, wallets untouched", bob.T.mode == "solo" and bob.ns.db.chips == bobWallet,
  bobWallet .. " + " .. bobStart .. " = " .. bob.ns.db.chips)
local hs = host.T.seats[bobSeatNow]
Check("host's table folds and drops the missing player", hs.kind ~= "remote" or (hs.leaving and hs.folded))
UntilIdle(120)
Check("...and frees the seat after the hand", host.T.seats[bobSeatNow].kind ~= "remote")

-- Host comes back and closes; a joined player is paid out.
group = { "Host", "Bob", "Cid" }
GroupChanged()
UntilIdle(120)
actingClients = { host }
Press(bob, "Play with your party")
Run(1)
Press(bob, "Join")
UntilIdle(120)
Run(2)
local hostClose = nil
local t2 = 0
-- wait for an idle moment, then close
host.T.mode = host.T.mode
while not Enabled(host, "Close table") and t2 < 120 do Tick(0.1); t2 = t2 + 0.1 end
local bStack = bob.T.mode == "client" and bob.T.seats[bob.T.mySeat].stack or -1
local bWallet = bob.ns.db.chips
local hStack = host.T.seats[1].stack
local hWallet = host.ns.db.chips
Press(host, "Close table")
Run(2)
Check("host closes: everyone back in the lobby, wallets untouched", host.T.mode == "solo" and host.ns.db.chips == hWallet
  and bob.T.mode == "solo" and bob.ns.db.chips == bWallet, string.format("host +%d, bob +%d", hStack, bStack))

-- The host can close mid-hand: it shuts after the hand, everyone paid.
Press(host, "Play with your party")
Press(host, "Host a table")
Press(bob, "Play with your party")
Run(1)
Press(bob, "Join")
actingClients = { host, bob }
local t4 = 0
while host.T.street == "idle" and t4 < 30 do Tick(0.1); t4 = t4 + 0.1 end
Press(host, "Options")
Press(host, "Close after hand")
Press(host, "Done")
Check("host: close during a hand waits for the hand", host.T.mode == "host" and host.T.closeAfterHand)
local bobW, t5 = bob.ns.db.chips, 0
local bobCloseSeat = bob.T.mySeat
local lastBob
while host.T.mode == "host" and t5 < 300 do
  Tick(0.1); t5 = t5 + 0.1
  if bob.T.mode == "client" then lastBob = bob.T.seats[bob.T.mySeat].stack end
end
Run(2)
-- Bob's final stack, from the host's last table message (seat s is field 14 + s)
local fields, start = {}, 1
while true do
  local i = string.find(LAST_P, ";", start, true)
  if not i then table.insert(fields, string.sub(LAST_P, start)) break end
  table.insert(fields, string.sub(LAST_P, start, i - 1)); start = i + 1
end
local seatField = fields[14 + bobCloseSeat]
local finalBob = tonumber(string.sub(seatField, 1, (string.find(seatField, ",", 1, true) or 0) - 1))
local idleFinal = fields[6] == "i"
Check("...then closes after the hand, wallets untouched", host.T.mode == "solo" and bob.T.mode == "solo" and idleFinal
  and finalBob and bob.ns.db.chips == bobW, bobW .. " + " .. tostring(finalBob) .. " = " .. bob.ns.db.chips)

-- A client reloading mid-hand gets their start-of-hand stack and frees the seat.
Press(host, "Play with your party")
Press(host, "Host a table")
Press(cid, "Play with your party")
Run(1)
Press(cid, "Join")
Run(2)
actingClients = { host }
local t3 = 0
while not (host.T.street ~= "idle") and t3 < 30 do Tick(0.1); t3 = t3 + 0.1 end
Run(0.5)
local cidStart = cid.T.seats[cid.T.mySeat].stack + cid.T.seats[cid.T.mySeat].total
local cidW = cid.ns.db.chips
local cSeat = cid.T.mySeat
cid.P:Build(cid.env.CreateFrame("Frame", nil, cid.env.UIParent))   -- the reload
Run(2)
Check("client reload mid-hand: back in the lobby, wallet untouched", cid.ns.db.chips == cidW and cid.T.mode == "solo",
  cidW .. " + " .. cidStart .. " = " .. cid.ns.db.chips)
Check("host marks the reloaded player as gone", host.T.seats[cSeat].leaving or host.T.seats[cSeat].kind ~= "remote")
UntilIdle(120)
Run(6)
Check("table carries on without them", host.T.seats[cSeat].kind ~= "remote")

io.write(ok and "PARTY PASS\n" or "PARTY FAIL\n")
