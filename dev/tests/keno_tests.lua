-- Keno: every pay table returns 90-96% (worked out exactly), picks are 1 to
-- 10 numbers, the draw comes out one number at a time and pays the right
-- amount, Quick pick and Auto work, and a draw cut off by a reload pays out.
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
local PANEL
local function Visible(o)
  local inPanel = PANEL == nil
  while o do if not o.shown then return false end; if o == PANEL then inPanel = true end; o = o.parent end
  return inPanel
end
local function Find(text, prefix)
  for _, o in ipairs(env.all) do
    if o.kind == "Button" and Visible(o) and type(o.text) == "string"
      and (o.text == text or (prefix and string.sub(o.text, 1, string.len(text)) == text)) then return o end
  end
end
local function Press(text, prefix) local b = assert(Find(text, prefix), "no " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end
local function Tick(sec)
  for _ = 1, math.floor(sec * 20 + 0.5) do
    env.CLOCK = env.CLOCK + 0.05
    for _, o in ipairs(env.all) do if o.scripts.OnUpdate and not o.parent and o.shown then env.Fire(o, "OnUpdate", 0.05) end end
  end
end

ns.db.chips = 1000
ns:OpenGame("keno")
local K = ns.games.keno
PANEL = K.panel
local kdb = ns.db.keno
Check("Keno is in the game list", K ~= nil and K.name == "Keno")

-- The return of every pay table, exactly (hypergeometric odds)
local function Choose(n, k)
  if k < 0 or k > n then return 0 end
  local r = 1
  for i = 1, k do r = r * (n - k + i) / i end
  return r
end
local allFair, worst, best = true, 1, 0
for spots = 1, 10 do
  local rtp = 0
  for hits = 0, spots do
    local p = Choose(spots, hits) * Choose(80 - spots, 20 - hits) / Choose(80, 20)
    rtp = rtp + p * ((K.PAYS[spots][hits]) or 0)
  end
  if rtp < 0.9 or rtp > 0.965 then allFair = false end
  if rtp < worst then worst = rtp end
  if rtp > best then best = rtp end
end
Check("every pay table returns 90% to 96.5%", allFair, string.format("%.1f%% to %.1f%%", worst * 100, best * 100))
Check("payouts are whole chips", K.Payout(1, 1, 1) == 3 and K.Payout(1, 1, 10) == 37 and K.Payout(2, 2, 10) == 155)
local d = K.DrawNumbers()
local seen, dup, inRange = {}, false, true
for _, n in ipairs(d) do if seen[n] then dup = true end; seen[n] = true; if n < 1 or n > 80 then inRange = false end end
Check("a draw is twenty different numbers from 1 to 80", table.getn(d) == 20 and not dup and inRange)

-- Picking
Check("Play is off with nothing picked", not Find("Play").enabled)
for n = 1, 11 do env.Fire(K.ui.cells[n], "OnClick", "LeftButton") end
local picked = 0
for _ in pairs(kdb.picks) do picked = picked + 1 end
Check("ten picks at most", picked == 10 and not kdb.picks[11])
env.Fire(K.ui.cells[10], "OnClick", "LeftButton")
Check("clicking a pick again un-picks it", kdb.picks[10] == nil)
Check("the pay table follows the spots picked", K.ui.payTitle.text == "9 spots picked")
Press("Clear")
Check("Clear empties the board", next(kdb.picks) == nil)
Press("Quick pick")
picked = 0
for _ in pairs(kdb.picks) do picked = picked + 1 end
Check("Quick pick with nothing picked picks six", picked == 6)
Press("Clear")

-- A rigged draw: pick 1-4, three of them come up
for n = 1, 4 do env.Fire(K.ui.cells[n], "OnClick", "LeftButton") end
local rig = { 1, 2, 3, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46 }
local realDraw = K.DrawNumbers
K.SetDraw(function() return rig end)
Check("bet starts at 10", kdb.bet == 10)
Press("Play")
Check("Play takes the bet", ns.db.chips == 990)
Check("the draw is running; the board is locked", kdb.game ~= nil and not Find("Clear").enabled)
Tick(0.5)
local shown = K.S.shown
Check("numbers come out one at a time", shown > 0 and shown < 20, shown)
Tick(3)
Check("after the draw: caught 3 of 4 pays 6x (60)", kdb.game == nil and ns.db.chips == 990 + 60, ns.db.chips)
Check("catches show gold, misses red, other picks blue", K.ui.cells[1].bg.color[1] > 0.9 and K.ui.cells[30].bg.color[1] > 0.5
  and K.ui.cells[30].bg.color[3] < 0.2 and K.ui.cells[4].bg.color[3] > 0.8)
Check("stats: one game, one win", kdb.stats.games == 1 and kdb.stats.wins == 1 and kdb.stats.won == 60 and kdb.stats.bestHits == 3)
Check("the picks stay for the next game", kdb.picks[1] and kdb.picks[4])

-- Auto: three games in a row
kdb.autoCount = 5; K:OnShow()
local before = kdb.stats.games
Press("Auto 5")
Check("Auto starts a game", kdb.game ~= nil and Find("Stop (5)", true) ~= nil)
Tick(12)
Check("...and keeps going", kdb.stats.games >= before + 3, kdb.stats.games - before)
Press("Stop", true)
Tick(4)
local stoppedAt = kdb.stats.games
Tick(4)
Check("Stop ends Auto", K.S.autoLeft == 0 and kdb.stats.games == stoppedAt and kdb.game == nil)

-- A draw cut off by a reload is paid out when Keno opens
K.SetDraw(function() return rig end)
Press("Play")
Tick(0.3)
local chips = ns.db.chips
local env2, ns2 = Start(env.CowCasinoDB)
Check("a draw in progress counts as chips in play", ns2:ChipsInPlay())
ns2:OpenGame("keno")
Check("after a reload the cut-off draw pays out (3 of 4: 60)", ns2.db.keno.game == nil and ns2.db.chips == chips + 60, ns2.db.chips - chips)
env, ns, K = env2, ns2, ns2.games.keno
PANEL = K.panel

-- Leaving finishes a draw at once
K.SetDraw(realDraw)
Press("Play")
ns:ShowMenu()
Check("leaving Keno finishes the draw", ns.db.keno.game == nil and not ns:ChipsInPlay())

-- Not enough chips
ns:OpenGame("keno")
ns.db.chips = 5
K:OnShow()
Check("Play is off when the bet is more than your chips", not Find("Play").enabled)

io.write(ok and "KENO PASS\n" or "KENO FAIL\n")
os.exit(ok and 0 or 1)
