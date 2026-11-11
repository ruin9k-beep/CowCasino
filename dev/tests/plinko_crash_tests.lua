-- Plinko and Crash: fair payout tables, every chip accounted for, refunds after a reload.
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
local env, ns = Start(nil)
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Find(text, prefix)
  for _, o in ipairs(env.all) do
    if o.kind == "Button" and Visible(o) and o.text and (o.text == text or (prefix and string.sub(o.text, 1, string.len(text)) == text)) then return o end
  end
end
local function Press(text, prefix) local b = Find(text, prefix); assert(b, "no button " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end
local function Tick(sec) for _ = 1, math.floor(sec * 10 + 0.5) do env.CLOCK = env.CLOCK + 0.1; for _, o in ipairs(env.all) do if o.scripts.OnUpdate and Visible(o) then env.Fire(o, "OnUpdate", 0.1) end end end end
local function Pay(bet, m) return math.floor(bet * m + 0.5) end

---------------------------------------------------------------------------
-- Plinko
---------------------------------------------------------------------------
ns.db.chips = 10000
ns:OpenGame("plinko")
local P = ns.games.plinko
local pdb = ns.db.plinko

local function Choose(n, k)
  local r = 1
  for i = 1, k do r = r * (n - k + i) / i end
  return r
end
local rtpBad, shapeBad = {}, {}
for rows, byRisk in pairs(P.PAYOUTS) do
  for risk, mults in pairs(byRisk) do
    local rtp = 0
    for k = 0, rows do rtp = rtp + Choose(rows, k) / 2 ^ rows * mults[k + 1] end
    if rtp < 0.98 or rtp > 1.0 then table.insert(rtpBad, rows .. " " .. risk .. " " .. string.format("%.4f", rtp)) end
    if table.getn(mults) ~= rows + 1 then table.insert(shapeBad, rows .. " " .. risk .. " slots") end
    for i = 1, rows + 1 do if mults[i] ~= mults[rows + 2 - i] then table.insert(shapeBad, rows .. " " .. risk .. " not mirrored") end end
  end
end
Check("every Plinko table returns 98-100% (a house edge of 2% at most)", table.getn(rtpBad) == 0, table.concat(rtpBad, ", "))
Check("...one slot more than rows, mirrored left to right", table.getn(shapeBad) == 0, table.concat(shapeBad, ", "))

-- drop balls and follow every chip
pdb.bet = 0
Press("25"); Press("25")
Check("bet set with the chips", pdb.bet == 50)
local start = ns.db.chips
local expect = start
local function Expect(fromIndex)
  for k = fromIndex, table.getn(P.balls) do
    local b = P.balls[k]
    expect = expect - b.bet + Pay(b.bet, P.PAYOUTS[b.rows][b.risk][b.slot])
  end
end
Check("one ball per drop to start", pdb.count == 1 and Find("Drop 50") ~= nil)
for _ = 1, 12 do env.Fire(P.ui.countNext, "OnClick", "LeftButton") end
Check("up to 10 balls per drop", pdb.count == 10 and not P.ui.countNext.enabled and Find("Drop 10 x 50") ~= nil, pdb.count)
Press("Drop", true)
Check("one press sends 10 balls and takes 10 bets", table.getn(P.balls) == 10 and ns.db.chips == start - 500, table.getn(P.balls))
Expect(1)
Press("Drop", true)
Expect(11)
Check("20 balls in the air at most", table.getn(P.balls) == 20 and not Find("Drop", true).enabled)
Tick(0.1)
local hidden = 0
for k = 2, 10 do if not P.balls[k].tex.shown then hidden = hidden + 1 end end
Check("the balls of a drop follow one another", hidden >= 8, hidden)

-- rows and risk live in Options, and wait while balls fall
Check("rows and risk aren't on the table any more", P.ui.rowsPrev == nil and P.ui.riskPrev == nil)
Press("Options")
local o = P.ui.options
Check("Options has risk, rows and ball speed", o:IsShown() and o.risk.value.text == "Medium" and o.rows.value.text == "16"
  and o.speed.value.text == "Normal")
Check("...risk and rows are off while balls fall", not o.rows.prev.enabled and not o.risk.next.enabled and o.speed.next.enabled)
Check("chips in play while balls fall", ns:ChipsInPlay())
Tick(4)
Check("every ball lands and pays its slot", table.getn(P.balls) == 0 and ns.db.chips == expect, ns.db.chips .. " vs " .. expect)
Check("one line for the whole drop", string.find(P.ui.status.text or "", "10 balls:", 1, true) ~= nil, P.ui.status.text)
Check("stats: balls and net", pdb.stats.balls == 20 and pdb.stats.net == ns.db.chips - start, pdb.stats.net)
Check("no chips in play once they land", not ns:ChipsInPlay())
Check("...and risk and rows can change again", o.rows.prev.enabled and o.risk.next.enabled)

-- 8 rows, high risk: a different board
env.Fire(o.rows.prev, "OnClick", "LeftButton"); env.Fire(o.rows.prev, "OnClick", "LeftButton")
env.Fire(o.risk.next, "OnClick", "LeftButton")
Check("8 rows, high risk", pdb.rows == 8 and pdb.risk == "High" and o.rows.value.text == "8", pdb.rows .. " " .. pdb.risk)
Press("Done")
local shownSlots, edge = 0, nil
for i, s in ipairs(P.ui.slots) do if s.shown then shownSlots = shownSlots + 1; if i == 1 then edge = s.text.text end end end
Check("the board shows 9 slots with 29x at the edge", shownSlots == 9 and edge == "29", tostring(shownSlots) .. " " .. tostring(edge))
Check("the table shows the setup", P.ui.setup.text == "8 rows, High risk", P.ui.setup.text)
for _ = 1, 9 do env.Fire(P.ui.countPrev, "OnClick", "LeftButton") end
local before = ns.db.chips
Press("Drop", true)
local b = P.balls[1]
Tick(2)
Check("one 8-row ball pays from the 8-row table", ns.db.chips == before - 50 + Pay(50, P.PAYOUTS[8].High[b.slot]))

-- not enough chips for every ball of a drop
local keep = ns.db.chips
ns.db.chips = 120
for _ = 1, 2 do env.Fire(P.ui.countNext, "OnClick", "LeftButton") end
Check("3 balls of 50 need 150 chips: Drop waits", pdb.count == 3 and not Find("Drop", true).enabled)
env.Fire(P.ui.countPrev, "OnClick", "LeftButton")
Check("2 balls of 50 fit", Find("Drop 2 x 50") ~= nil and Find("Drop", true).enabled)
ns.db.chips = keep
env.Fire(P.ui.countPrev, "OnClick", "LeftButton")

-- a ball in the air at a reload is refunded
before = ns.db.chips
Press("Drop", true)
local envR, nsR = Start(ns.db)
nsR:OpenGame("plinko")
Check("a ball still falling at a reload is refunded", nsR.db.chips == before and nsR.db.plinko.inFlight == nil, nsR.db.chips .. " vs " .. before)
Tick(2)    -- let the original land (its own copy of the game)

---------------------------------------------------------------------------
-- Crash
---------------------------------------------------------------------------
ns:OpenGame("crash")
local C = ns.games.crash
local cdb = ns.db.crash

Check("crash point 1.00x when the draw is lowest", C.NewCrashPoint(0) == 1)
Check("crash point 1.98x at the middle draw (1% edge)", C.NewCrashPoint(0.5) == 1.98)
local n, at2, at10, instant = 200000, 0, 0, 0
for _ = 1, n do
  local x = C.NewCrashPoint()
  if x >= 2 then at2 = at2 + 1 end
  if x >= 10 then at10 = at10 + 1 end
  if x == 1 then instant = instant + 1 end
end
Check("reaches 2x about 49.5% of the time", math.abs(at2 / n - 0.495) < 0.006, string.format("%.4f", at2 / n))
Check("reaches 10x about 9.9% of the time", math.abs(at10 / n - 0.099) < 0.004, string.format("%.4f", at10 / n))
-- 1.00x: everything under 1.01x, so 1 - 0.99 / 1.01 = 1.98%
Check("about 2% crash at 1.00x straight away", math.abs(instant / n - 0.0198) < 0.0015, string.format("%.4f", instant / n))

local CRASH = {}
C.NewCrashPoint = function() return table.remove(CRASH, 1) end
cdb.bet = 0
Press("100")
start = ns.db.chips

-- cash out by hand at about 2x
table.insert(CRASH, 3.00)
Press("Bet", true)
Check("the bet goes in when the run starts", ns.db.chips == start - 100 and ns:ChipsInPlay())
Tick(C.SecondsFor(2) + 0.05)
local m = math.floor(C.MultAt(env.CLOCK - C.Run().start) * 100) / 100
Press("Cash out", true)
Check("cash out pays the bet times the multiplier", ns.db.chips == start - 100 + Pay(100, m) and C.Run().cashed == m,
  (ns.db.chips - start) .. " at " .. m)
Check("no chips in play after cashing out", not ns:ChipsInPlay())
Tick(C.SecondsFor(3) - C.SecondsFor(2) + 0.5)
Check("the run carries on to its crash point", C.Run().over and C.history[1] == 3)
Check("stats: one run, one cash-out", cdb.stats.runs == 1 and cdb.stats.cashouts == 1)

-- crash before cashing out
before = ns.db.chips
table.insert(CRASH, 1.50)
Press("Bet", true)
Tick(C.SecondsFor(1.5) + 0.3)
Check("a crash before cashing out loses the bet", ns.db.chips == before - 100 and C.Run().over and not C.Run().cashed)

-- auto cash-out
for _ = 1, 4 do env.Fire(C.ui.autoNext, "OnClick", "LeftButton") end
Check("auto cash-out set to 2x", cdb.auto == 2, cdb.auto)
before = ns.db.chips
table.insert(CRASH, 5)
Press("Bet", true)
Tick(C.SecondsFor(5) + 0.3)
Check("auto cash-out takes exactly 2x", ns.db.chips == before + 100)
before = ns.db.chips
table.insert(CRASH, 1.90)
Press("Bet", true)
Tick(C.SecondsFor(1.9) + 0.3)
Check("...but not if it crashes first", ns.db.chips == before - 100)
for _ = 1, 4 do env.Fire(C.ui.autoPrev, "OnClick", "LeftButton") end

-- too late: the crash time has passed even if no frame has shown it yet
before = ns.db.chips
table.insert(CRASH, 1.20)
Press("Bet", true)
env.CLOCK = env.CLOCK + C.SecondsFor(1.2) + 0.5
Press("Cash out", true)
Check("cashing out after the crash time pays nothing", ns.db.chips == before - 100 and not C.Run().cashed)
Tick(0.2)
Check("...and the run ends as a crash", C.Run().over)

-- instant crash
before = ns.db.chips
table.insert(CRASH, 1.00)
Press("Bet", true)
Tick(0.2)
Check("a 1.00x crash ends the run at once", C.Run().over and ns.db.chips == before - 100)
Check("stats net matches the chips", cdb.stats.net == ns.db.chips - start, cdb.stats.net .. " vs " .. (ns.db.chips - start))

-- a run going at a reload is refunded
before = ns.db.chips
table.insert(CRASH, 50)
Press("Bet", true)
local env3, ns3 = Start(ns.db)
ns3:OpenGame("crash")
Check("a run still going at a reload is refunded", ns3.db.chips == before and ns3.db.crash.live == nil, ns3.db.chips .. " vs " .. before)

ns:RebuyChips(1000)
Check("a fresh stack starts Plinko and Crash stats over", pdb.stats.balls == 0 and cdb.stats.runs == 0)

io.write(ok and "PLINKO CRASH PASS\n" or "PLINKO CRASH FAIL\n")
os.exit(ok and 0 or 1)
