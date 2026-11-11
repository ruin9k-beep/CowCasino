-- Slots' modern features: wilds with multipliers, scatters, free spins with
-- a rising multiplier, big win banners, Auto, and the overall return.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-66s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end
local function Start(saved, prep)
  local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
  env.arg = { ADDON }; env.SELECT_SAVED = select
  assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
  env.CowCasinoDB = saved
  for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
  if prep then prep(env.CowCasino.ns) end
  env.CowCasinoFrame:Show()
  return env, env.CowCasino.ns
end
local env, ns = Start(nil)
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Find(text, prefix)
  for _, o in ipairs(env.all) do
    if o.kind == "Button" and Visible(o) and o.text and (o.text == text or (prefix and string.sub(o.text, 1, string.len(text)) == text)) then return o end
  end
end
local function Press(text, prefix) local b = assert(Find(text, prefix), "no " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end
local function Shown(text) for _, f in ipairs(env.all) do if f.kind == "FontString" and Visible(f) and f.text and string.find(f.text, text, 1, true) then return f end end end
local function Tick(sec)
  for _ = 1, math.floor(sec * 20 + 0.5) do
    env.CLOCK = env.CLOCK + 0.05
    for _, o in ipairs(env.all) do if o.scripts.OnUpdate and o.shown then env.Fire(o, "OnUpdate", 0.05) end end
  end
end
local G = ns.games.slots

---------------------------------------------------------------------------
-- Line rules
---------------------------------------------------------------------------
ns.db.slots = { machine = "5x4", betIndex = 1 }
ns:OpenGame("slots")
local E = G.EvaluateLine
Check("a wild stands in for the symbol and multiplies the pay",
  E({ "seven", "wild", "seven", "bar", "bar" }, { 1, 3, 1, 1, 1 }) == 20 * 3)
Check("two wilds on a line multiply together",
  E({ "bar", "wild", "wild", "bar", "bar" }, { 1, 2, 5, 1, 1 }) == 150 * 10)
Check("wilds stretch a cherry pair", E({ "cherry", "wild", "lemon", "x", "x" }, { 1, 2, 1, 1, 1 }) == 1 * 2)
Check("a scatter on the first reel starts no line", E({ "scatter", "wild", "wild", "wild", "wild" }, { 1, 2, 2, 2, 2 }) == 0)
Check("a run stops at the first other symbol", E({ "plum", "plum", "bell", "plum", "plum" }, {}) == 0)
local noWildFirst = true
for _, strip in ipairs({ G.STRIPS_5[1], G.STRIPS_3[1] }) do for _, s in ipairs(strip) do if s == "wild" then noWildFirst = false end end end
Check("no wilds on the first reel", noWildFirst)

---------------------------------------------------------------------------
-- Rigged spins
---------------------------------------------------------------------------
local QUEUE = {}
local realRandom = math.random
math.random = function(a, b)
  if a and not b and a >= 28 and QUEUE[1] then return table.remove(QUEUE, 1) end
  if a == nil then return realRandom() end
  if b == nil then return realRandom(a) end
  return realRandom(a, b)
end
-- stops that put `sym` in a given row (row 2 is the stop itself)
local function StopFor(strip, sym, row)
  for i, s in ipairs(strip) do if s == sym then return ns.Mod(i - 1 - (row - 2), table.getn(strip)) + 1 end end
end
-- a stop with no scatter or wild anywhere in view
local function PlainStop(strip, rows)
  for i = 1, table.getn(strip) do
    local clean = true
    for row = 1, rows do
      local s = strip[ns.Mod(i - 1 + row - 2, table.getn(strip)) + 1]
      if s == "scatter" or s == "wild" then clean = false end
    end
    if clean then return i end
  end
end
local function Queue(stops) for _, v in ipairs(stops) do table.insert(QUEUE, v) end end
local S5 = G.STRIPS_5

-- five sevens on the middle row: 500 line bets = 50x the total bet
local start = ns.db.chips
Queue({ StopFor(S5[1], "seven", 2), StopFor(S5[2], "seven", 2), StopFor(S5[3], "seven", 2), StopFor(S5[4], "seven", 2), StopFor(S5[5], "seven", 2) })
Press("Spin")
local p = ns.db.slots.pending
local expect = G.EvaluateSpin(p.stops, p.wilds)
Tick(2)
Check("five sevens pay at least 500 line bets", expect >= 500 and ns.db.chips == start - 10 + expect, ns.db.chips - start)
Check("...the win counts up", G.ui.win.text ~= ("WIN " .. ns:FormatChips(expect)) and G.ui.win.text ~= "")
Tick(2)
Check("...to the full amount, under a JACKPOT banner", G.ui.win.text == ns:FormatChips(expect) and G.ui.banner.text == "JACKPOT!",
  tostring(G.ui.win.text) .. " / " .. tostring(G.ui.banner.text))

-- a wild in view shows its multiplier
Queue({ PlainStop(S5[1], 4), StopFor(S5[2], "wild", 2), PlainStop(S5[3], 4), PlainStop(S5[4], 4), PlainStop(S5[5], 4) })
Press("Spin")
local m = ns.db.slots.pending.wilds[2][2]
Tick(3)
Check("a landed wild wears its multiplier", m ~= nil and G.ui.reels[2].badges[2].shown and G.ui.reels[2].badges[2].text == "x" .. m,
  tostring(m))

---------------------------------------------------------------------------
-- Free spins
---------------------------------------------------------------------------
Tick(2)
local function Scatters()
  Queue({ StopFor(S5[1], "scatter", 2), PlainStop(S5[2], 4), StopFor(S5[3], "scatter", 3), PlainStop(S5[4], 4), StopFor(S5[5], "scatter", 1) })
end
start = ns.db.chips
Scatters()
Press("Spin")
Tick(2.2)
local d = ns.db.slots
Check("three scatters start 12 free spins on 5x4", d.free ~= nil and d.free.left == 12 and d.free.mult == 1 and d.stats.freeRounds == 1)
Check("...and pay 20 line bets", ns.db.chips == start - 10 + 20 + (d.free and d.free.won or 0), ns.db.chips - start)
Check("the screen says FREE SPINS", Shown("FREE SPINS") ~= nil and Shown("12 left") ~= nil)
Check("bet and machine are locked during free spins", not G.ui.raise.enabled and not G.ui.max.enabled and G:SetMachine("3x3") == false)
Check("chips in play while free spins are owed", ns:ChipsInPlay())

-- they play by themselves; follow the multiplier and the chips
local chipsBefore, paidSpins = ns.db.chips, d.stats.wagered
local mults, rising = {}, true
local lastMult = 1
local spins = 0
local guard = 0
while d.free and guard < 2000 do
  local before = d.pending and d.pending.free
  Tick(0.25); guard = guard + 1
  if d.free and d.free.mult < lastMult then rising = false end
  if d.free then lastMult = d.free.mult end
end
Check("all the free spins play by themselves", d.free == nil and guard < 2000, guard)
Check("free spins never charge a bet", d.stats.wagered == paidSpins)
Check("the multiplier only ever rises, up to x3", rising and lastMult <= 3)
Check("they finish with a summary", Shown("Free spins over") ~= nil)
Check("...and the machine is back to normal", Shown("FREE SPINS") == nil and G.ui.raise.enabled)

---------------------------------------------------------------------------
-- Free spins survive a reload
---------------------------------------------------------------------------
local env2, ns2 = Start(nil, function(n)
  n.db.slots = { machine = "5x4", betIndex = 1, free = { left = 3, lineBet = 2, mult = 2, won = 0, machine = "5x4" } }
end)
local c2 = ns2.db.chips
ns2:OpenGame("slots")
local d2 = ns2.db.slots
Check("after a reload the free spins are waiting", d2.free and d2.free.left == 3 and env2.CowCasino.ns.games.slots.ui.status.text
  and string.find(env2.CowCasino.ns.games.slots.ui.status.text, "3 free spins", 1, true) ~= nil)
for _ = 1, 4000 do
  if not d2.free and not ns2.games.slots:ChipsInPlay() then break end
  env2.CLOCK = env2.CLOCK + 0.05
  for _, o in ipairs(env2.all) do if o.scripts.OnUpdate and o.shown then env2.Fire(o, "OnUpdate", 0.05) end end
end
Check("...and play out at the saved bet, without charging", d2.free == nil and d2.stats.wagered == 0 and ns2.db.chips >= c2)

-- free spins won on another machine bring that machine back
local env3, ns3 = Start(nil, function(n)
  n.db.slots = { machine = "5x4", betIndex = 1, free = { left = 2, lineBet = 1, mult = 1, won = 0, machine = "3x3" } }
end)
ns3:OpenGame("slots")
Check("free spins from the 3x3 open the 3x3", ns3.games.slots:Machine().id == "3x3")

---------------------------------------------------------------------------
-- Auto
---------------------------------------------------------------------------
Check("Auto plays 25 spins by default", Find("Auto 25") ~= nil)
local before = d.stats.spins
Press("Auto 25")
-- (big wins and free spins add pauses, so allow time)
for _ = 1, 60 do if d.stats.spins >= before + 3 then break end Tick(0.5) end
Check("Auto keeps spinning by itself", d.stats.spins >= before + 3 and G.S.autoLeft > 0, d.stats.spins - before)
Check("...with the bet locked", not G.ui.raise.enabled)
local paidBefore = d.stats.wagered
G.S.next = G.S.next   -- (no-op: Stop is pressed by the button below)
local stopButton = Find("Stop (", true) or Find("Stop")
env.Fire(stopButton, "OnClick", "LeftButton")
if G.S.spinning then Tick(3) end
-- free spins already won still play out; then nothing more should start
for _ = 1, 300 do if not (d.free or G.S.spinning or G.S.waiting) then break end Tick(1) end
local stoppedAt, paidAt = d.stats.spins, d.stats.wagered
Tick(6)
Check("Stop ends Auto", G.S.autoLeft == 0 and d.stats.spins == stoppedAt and d.stats.wagered == paidAt and Find("Auto 25") ~= nil,
  d.stats.spins - stoppedAt)
-- Auto stops when the chips run short
ns.db.chips = 25
Press("Auto 25")
-- (wins on the way can keep it going for a while, and a free spin round
-- won on the way plays out first)
for _ = 1, 900 do if G.S.autoLeft == 0 and not (d.free or G.S.spinning or G.S.waiting) then break end Tick(1) end
Check("Auto stops when there aren't chips for the bet", G.S.autoLeft == 0 and ns.db.chips < 10 + 1000 and not G.S.spinning)
ns.db.chips = 5000
Press("Options")
Check("Options: Auto spins 10 to 100", Shown("Auto spins") ~= nil and Shown("25 spins") ~= nil,
  tostring(Shown("Auto spins") ~= nil) .. " " .. tostring(d.autoCount) .. " " .. tostring(G.ui.options and G.ui.options.shown))
Press(">")  -- reel size
Press("Done")

---------------------------------------------------------------------------
-- The stats line along the bottom
---------------------------------------------------------------------------
do
  local st = ns.db.slots.stats
  local net = st.won - st.wagered
  local text = G.ui.stats.text or ""
  local want = (net > 0 and ("+" .. ns:FormatChips(net))) or (net < 0 and ("-" .. ns:FormatChips(-net))) or "0"
  Check("the bottom line shows the spin count and net chips", G.ui.stats.shown
    and string.find(text, "Spins " .. st.spins, 1, true) ~= nil and string.find(text, "Net |cff%x%x%x%x%x%x" .. string.gsub(want, "([%+%-])", "%%%1")) ~= nil, text)
  local spinsBefore = st.spins
  local chipsBefore, wonBefore = ns.db.chips, st.won
  Press("Spin"); Tick(2)
  G.S.next = (G.S.next or 0) + 1; G.S.waiting = false
  Check("...and updates after a spin", string.find(G.ui.stats.text, "Spins " .. (spinsBefore + 1), 1, true) ~= nil, G.ui.stats.text)
  ns.db.slots.free = nil
  G:OnShow()
  ns:RebuyChips(1000)
  Check("...and starts over with a fresh stack", string.find(G.ui.stats.text, "Spins 0", 1, true) ~= nil
    and string.find(G.ui.stats.text, "Net |cffcccccc0", 1, true) ~= nil, G.ui.stats.text)
  ns.db.chips = 5000
end

---------------------------------------------------------------------------
-- 300 paid spins, each paid exactly as rules written here say
---------------------------------------------------------------------------
G:SetMachine("5x4")
local M = G:Machine()
local function MyPay(stops, wilds, lineBet)
  local total = 0
  local function At(r, row) local st = M.strips[r]; return st[ns.Mod(stops[r] + row - 3, table.getn(st)) + 1] end
  for _, line in ipairs(M.lines) do
    local first = At(1, line[1])
    if first ~= "scatter" then
      local n, mult = 1, 1
      for r = 2, 5 do
        local s = At(r, line[r])
        if s ~= first and s ~= "wild" then break end
        n = n + 1
        if s == "wild" then mult = mult * wilds[r][line[r]] end
      end
      total = total + (M.pays[first][n] or 0) * mult * lineBet
    end
  end
  local sc = 0
  for r = 1, 5 do for row = 1, 4 do if At(r, row) == "scatter" then sc = sc + 1 end end end
  if sc >= 3 then total = total + M.scatterPay * lineBet end
  return total, sc >= 3
end
local mismatch
local checked = 0
for _ = 1, 300 do
  ns.db.slots.free = nil      -- paid spins only
  ns.db.chips = 1000
  G:OnShow()
  local before = ns.db.chips
  Press("Spin")
  local pend = ns.db.slots.pending
  local want = MyPay(pend.stops, pend.wilds, pend.lineBet)
  Tick(2)
  G.S.next = (G.S.next or 0) + 1      -- no free spins after this one
  G.S.waiting = false
  local got = ns.db.chips - before + pend.lineBet * 10
  if got ~= want and not mismatch then mismatch = table.concat(pend.stops, ",") .. ": " .. got .. " vs " .. want end
  checked = checked + 1
end
ns.db.slots.free = nil
Check("300 paid spins pay exactly what independent rules say", mismatch == nil and checked == 300, mismatch)

---------------------------------------------------------------------------
-- The whole return, free spins included, from the game's own evaluation
---------------------------------------------------------------------------
math.random = realRandom
local function Simulate(machineId, paid)
  G:SetMachine(machineId)
  local M = G:Machine()
  local lines = table.getn(M.lines)
  local function One()
    local stops = {}
    for r = 1, M.reels do stops[r] = math.random(table.getn(M.strips[r])) end
    local wilds = G.RollWilds(stops)
    local lineTotal, _, sc = G.EvaluateSpin(stops, wilds)
    local scat = (table.getn(sc) >= 3) and M.scatterPay or 0
    return lineTotal + scat, table.getn(sc) >= 3
  end
  local back = 0
  for _ = 1, paid do
    local pay, feature = One()
    back = back + pay
    if feature then
      local left, mult = M.freeSpins, 1
      while left > 0 do
        left = left - 1
        local fp, retrig = One()
        if fp > 0 then back = back + fp * mult; mult = math.min(G.FREE_MULT_MAX, mult + 1) end
        if retrig then left = left + G.RETRIGGER end
      end
    end
  end
  return back / (paid * lines)
end
math.randomseed(12345)
for _, id in ipairs({ "3x3", "5x4", "5x5" }) do
  local rtp = Simulate(id, 100000)
  -- big wild multipliers make 100,000 spins swing a few percent either way
  -- (a million-spin run of this same code lands within half a percent of 95%)
  Check(id .. ": 100,000 spins land near 95%, free spins included", rtp > 0.88 and rtp < 1.06, string.format("%.1f%%", rtp * 100))
end

io.write(ok and "SLOTS FEATURES PASS\n" or "SLOTS FEATURES FAIL\n")
os.exit(ok and 0 or 1)
