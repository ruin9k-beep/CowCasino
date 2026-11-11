-- Slots: 3x3, 5x4 and 5x5 machines, picked in Slots' own Options.
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
local function Find(text) for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == text and Visible(o) then return o end end end
local function Press(text) local b = assert(Find(text), "no " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end
local function Shown(text) for _, f in ipairs(env.all) do if f.kind == "FontString" and Visible(f) and f.text and string.find(f.text, text, 1, true) then return f end end end
local function Tick(sec)
  for _ = 1, math.floor(sec * 20 + 0.5) do
    env.CLOCK = env.CLOCK + 0.05
    for _, o in ipairs(env.all) do if o.scripts.OnUpdate and (o.shown) then env.Fire(o, "OnUpdate", 0.05) end end
  end
end
local G = ns.games.slots
local function VisibleCells()
  local reels, rows = 0, 0
  for _, r in ipairs(G:Machine().reelFrames) do if Visible(r) then reels = reels + 1; rows = table.getn(r.cells) end end
  return reels, rows
end

-- Exact line and scatter returns, worked out here from the strips and pays
-- (written separately from the game), then checked against the game itself.
local EM = 0
for _, m in ipairs(G.WILD_MULTS) do EM = EM + m end
EM = EM / table.getn(G.WILD_MULTS)
local function Count(strip, sym) local n = 0 for _, s in ipairs(strip) do if s == sym then n = n + 1 end end return n end
local function LineReturn(strips, pays, reels)
  local total = 0
  for sym, byCount in pairs(pays) do
    local prob = Count(strips[1], sym) / table.getn(strips[1])
    for c = 2, reels do
      local st = strips[c]
      prob = prob * (Count(st, sym) + Count(st, "wild") * EM) / table.getn(st)
      local stop = 1
      if c < reels then
        local nx = strips[c + 1]
        stop = 1 - (Count(nx, sym) + Count(nx, "wild")) / table.getn(nx)
      end
      total = total + prob * stop * (byCount[c] or 0)
    end
  end
  return total
end
local r3, r5 = LineReturn(G.STRIPS_3, G.PAYS_3, 3), LineReturn(G.STRIPS_5, G.PAYS, 5)
Check("3-reel lines return about 70% (free spins and scatters add the rest)", math.abs(r3 - 0.700) < 0.002, string.format("%.2f%%", r3 * 100))
Check("5-reel lines return about 52.5%", math.abs(r5 - 0.525) < 0.002, string.format("%.2f%%", r5 * 100))
-- the game's own evaluation over every 3x3 stop combination, with each wild
-- at its average multiplier, gives exactly the same
ns.db.slots = ns.db.slots or {}
ns.db.slots.machine = "3x3"
ns:OpenGame("slots")
local L3 = table.getn(G.STRIPS_3[1]) * table.getn(G.STRIPS_3[2]) * table.getn(G.STRIPS_3[3])
local avg = {}
for r = 1, 3 do avg[r] = {}; for row = 1, 3 do avg[r][row] = EM end end
local sum, n = 0, 0
for a = 1, table.getn(G.STRIPS_3[1]) do for b = 1, table.getn(G.STRIPS_3[2]) do for c = 1, table.getn(G.STRIPS_3[3]) do
  sum = sum + G.EvaluateSpin({ a, b, c }, avg); n = n + 1
end end end
local exact = sum / n / 5
Check("3x3: all " .. L3 .. " spins evaluated by the game agree", n == L3 and math.abs(exact - r3) < 1e-9, string.format("%.4f vs %.4f", exact, r3))
Check("3x3: three reels of three rows on screen", (function() local a, b = VisibleCells(); return a == 3 and b == 3 end)())
Check("3x3: bet is over 5 lines", Shown("x 5 lines") ~= nil)
Check("3x3: top pay names three sevens", Shown("Three ") ~= nil)
Press("Paytable")
Check("3x3 paytable: 2 and 3 in a row only", Shown("3 in a row") and not Shown("4 in a row") and true)
Press("Next >")
Check("3x3 features: 14 free spins, scatters on every reel", Shown("14 free spins") ~= nil and Shown("reels 1, 3 and 5") == nil)
Press("Next >")
local tiles = 0
for _, f in ipairs(env.all) do if f.kind == "FontString" and Visible(f) and f.text and string.find(f.text, "^Line %d") then tiles = tiles + 1 end end
Check("3x3 paytable: the 5 line shapes", tiles == 5, tiles)
Press("Done")
-- a spin that lands three sevens on the middle row pays the jackpot
local seven = {}
for r = 1, 3 do for i, sym in ipairs(G.STRIPS_3[r]) do if sym == "seven" then seven[r] = i end end end
local realRandom = math.random
local k = 0
math.random = function(a, b) if a and not b and a >= 28 then k = k + 1; return seven[k] end return realRandom(a, b) end
local before = ns.db.chips
Press("Spin")
math.random = realRandom
local paid = G.EvaluateSpin(seven, ns.db.slots.pending.wilds)
Tick(5)
Check("3x3: three sevens on the middle row win the jackpot (250x)", Shown("JACKPOT") ~= nil and paid >= 250
  and ns.db.chips == before - 5 + paid, ns.db.chips - before)

-- The CowCasino Options no longer have it
ns:ShowMenu()
Press("Options")
Check("the CowCasino Options don't have the reel picker", Shown("Slot machine reels") == nil and Shown("Reel size") == nil)
Press("Done")
-- Slots' own Options: the picker
ns:OpenGame("slots")
Press("Paytable")
Press("Options")
Check("Slots has an Options button; it closes the paytable", Shown("Slots Options") ~= nil and Shown("Reel size") ~= nil
  and Shown("3 x 3") ~= nil and not Shown("in a row"))
Press(">")
Check("> moves to 5 x 4, and the machine changes at once", Shown("5 x 4") ~= nil and G:GetMachine() == "5x4" and Shown("10 paylines") ~= nil
  and (function() local a, b = VisibleCells(); return a == 5 and b == 4 end)())
Press(">")
Check("> again: 5 x 5", Shown("5 x 5") ~= nil and G:GetMachine() == "5x5" and Shown("15 paylines") ~= nil)
Press("Done")
Check("Done closes Slots Options", Shown("Slots Options") == nil)
Check("5x5: five reels of five rows on screen", (function() local a, b = VisibleCells(); return a == 5 and b == 5 end)())
Check("5x5: bet is over 15 lines", Shown("x 15 lines") ~= nil)
Check("only one machine on screen", (function()
  local n = 0
  for _, m in ipairs(G.MACHINES) do if m.frame and Visible(m.frame) then n = n + 1 end end
  return n == 1 end)())
-- the machine fits: its bottom stays above the bet row
local mf = G:Machine().frame
local bottom = 24 + mf.h
Check("5x5: machine fits above the bet controls (no taller than 5x4)", bottom <= 24 + 4 * 48 + 12, bottom)
Press("Paytable"); Press("Next >")
Check("5x5 features: 5 free spins, scatters on reels 1, 3 and 5", Shown("5 free spins") ~= nil and Shown("reels 1, 3 and 5") ~= nil)
Press("Next >")
Check("5x5 paytable: 15 lines over two pages", Shown("Winning lines (1 of 2)") ~= nil)
Press("Next >")
Check("...the second page shows lines 13-15", Shown("Line 13") and Shown("Line 15") and not Shown("Line 12") and true)
Press("Done")
-- a straight diagonal pays on 5x5 (line 10)
local diag = G:Machine().lines[10]
Check("5x5 has the straight diagonal", table.concat(diag, ",") == "1,2,3,4,5")

-- Can't change during a spin
Press("Spin")
Check("changing the machine is refused during a spin", G:SetMachine("3x3") == false and G:GetMachine() == "5x5")
Press("Options")
local function Arrow() for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == ">" and Visible(o) then return o end end end
Check("Options: picker disabled during a spin, with a note", not Arrow().enabled and Shown("once your spin (and any free spins) finish") ~= nil)
Tick(3)
-- (a spin can win free spins, which play out first)
for _ = 1, 200 do if not G:ChipsInPlay() then break end Tick(1) end
Press("Done"); Press("Options")
Check("...enabled again once it's done", Arrow().enabled)
Press(">")
Check("wraps around to 3 x 3", G:GetMachine() == "3x3" and (function() local a, b = VisibleCells(); return a == 3 and b == 3 end)())
Press("Done")
ns:ShowMenu()
Check("leaving Slots closes its Options", Shown("Slots Options") == nil)

-- Reloads
local env2, ns2 = Start(nil, function(n)
  n.db.slots = { machine = "5x5", betIndex = 1, pending = { v = 2, lineBet = 1, stops = { 1, 2, 3, 4, 5 }, lines = 15, machine = "5x5", wilds = {} } }
end)
local chips = ns2.db.chips
ns2:OpenGame("slots")
Check("reload mid-spin on 5x5: the spin settles on 5x5", ns2.db.slots.pending == nil and ns2.games.slots:Machine().id == "5x5")
local env3, ns3 = Start(nil, function(n)
  n.db.slots = { betIndex = 1, pending = { lineBet = 2, stops = { 1, 2, 3, 4, 5 }, lines = 10 } }
end)
local c3 = ns3.db.chips
ns3:OpenGame("slots")
Check("a spin saved by an older version (other reels) is refunded", ns3.db.slots.pending == nil and ns3.db.slots.machine == "5x4"
  and ns3.db.chips == c3 + 20, ns3.db.chips - c3)
local env4, ns4 = Start(nil, function(n)
  n.db.slots = { machine = "5x4", betIndex = 1, pending = { lineBet = 2, stops = { 1, 2, 3 }, lines = 5, machine = "3x3" } }
end)
local c4 = ns4.db.chips
ns4:OpenGame("slots")
Check("a spin owed from another machine is refunded", ns4.db.chips == c4 + 10 and ns4.db.slots.pending == nil, ns4.db.chips - c4)

io.write(ok and "SLOT MACHINES PASS\n" or "SLOT MACHINES FAIL\n")
os.exit(ok and 0 or 1)
