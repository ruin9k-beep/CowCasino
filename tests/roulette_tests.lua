-- Roulette tests on the strict 1.12 mock.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-62s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end

local function Start(saved)
  local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
  env.arg = { ADDON }
  env.SELECT_SAVED = select
  assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
  env.CowCasinoDB = saved
  for _, o in ipairs(env.all) do
    if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end
  end
  local ns = env.CowCasino.ns
  env.CowCasinoFrame:Show()
  return env, ns
end

local env, ns = Start(nil)
ns.db.chips = 10000
ns:OpenGame("roulette")
local G = ns.games.roulette
local S = G.S

local function Under(o, root)
  while o do
    if not o.shown then return false end
    if o == root then return true end
    o = o.parent
  end
  return false
end
local function Find(text)
  for _, o in ipairs(env.all) do
    if o.kind == "Button" and o.text == text and Under(o, G.panel) then return o end
  end
end
local function Press(text, button)
  local b = assert(Find(text), "no button " .. text)
  assert(b.enabled, "disabled: " .. text)
  env.Fire(b, "OnClick", button or "LeftButton")
end
local function Enabled(text) local b = Find(text); return b ~= nil and b.enabled ~= nil end

local driver
for _, o in ipairs(env.all) do
  if rawget(o, "file") == "Games/Roulette.lua" and not o.parent and o.scripts.OnUpdate then driver = o end
end
local function Finish()
  for _ = 1, 60 do
    env.CLOCK = env.CLOCK + 0.1
    if driver.shown then env.Fire(driver, "OnUpdate", 0.1) end
  end
end
local realRandom = math.random
local function SpinTo(n)
  math.random = function(a, b) if a == 37 and not b then return n + 1 end return realRandom(a, b) end
  Press("Spin")
  math.random = realRandom
  Finish()
end

---------------------------------------------------------------------------
-- 1. Click zones, every pixel of the grid
---------------------------------------------------------------------------
local GW, GH = 24 * 12, 22 * 3
local function Adjacent(nums)
  -- every legal inside bet is a rectangle of the layout (zero counts as column 0)
  local n = table.getn(nums)
  local cols, rows = {}, {}
  for _, v in ipairs(nums) do
    if v == 0 then cols[0] = true
    else
      cols[math.floor((v - 1) / 3) + 1] = true
      rows[v - 3 * math.floor((v - 1) / 3)] = true
    end
  end
  local nc, nr, minc, maxc = 0, 0, 99, -1
  for c in pairs(cols) do nc = nc + 1; if c < minc then minc = c end; if c > maxc then maxc = c end end
  for _ in pairs(rows) do nr = nr + 1 end
  if maxc - minc + 1 ~= nc then return false end
  if cols[0] then return n == 1 + nr end
  return n == nc * nr
end
local seen, bad, byCount = {}, nil, { 0, 0, 0, 0, 0, 0 }
for y = 0, GH + 4 do
  for x = 0, GW - 1 do
    local nums = G.Zone(x, y)
    if not nums then bad = bad or ("nil at " .. x .. "," .. y)
    else
      local key = table.concat(nums, "-")
      local n = table.getn(nums)
      if not (n == 1 or n == 2 or n == 3 or n == 4 or n == 6) or not Adjacent(nums) then bad = bad or ("odd bet " .. key) end
      if not seen[key] then
        seen[key] = true
        byCount[n] = byCount[n] + 1
      end
    end
  end
end
Check("zones: every pixel maps to a legal bet", bad == nil, bad)
Check("zones: all 36 straights (zero has its own spot)", byCount[1] == 36, byCount[1])
Check("zones: all 60 splits (33 across, 24 up, 3 with zero)", byCount[2] == 60, byCount[2])
Check("zones: 12 streets + 2 zero trios", byCount[3] == 14, byCount[3])
Check("zones: 22 corners + first four", byCount[4] == 23, byCount[4])
Check("zones: 11 six lines", byCount[6] == 11, byCount[6])
local function Z(x, y) return table.concat((G.Zone(x, y)), "-") end
Check("zone: middle of 17", Z(5 * 24 + 12, 33) == "17")
Check("zone: 17|20 split", Z(6 * 24 - 1, 33) == "17-20")
Check("zone: 17/18 split", Z(5 * 24 + 12, 23) == "17-18")
Check("zone: corner 17-18-20-21", Z(6 * 24 - 1, 23) == "17-18-20-21")
Check("zone: street 16-17-18", Z(5 * 24 + 12, GH - 1) == "16-17-18")
Check("zone: six line 13-18", Z(5 * 24 + 1, GH - 1) == "13-14-15-16-17-18")
Check("zone: 0-2 split, 0-2-3 trio, first four", Z(1, 33) == "0-2" and Z(1, 23) == "0-2-3" and Z(1, GH - 1) == "0-1-2-3")
Check("zone: right edge of 36 is still 36", Z(GW - 1, 11) == "36")

---------------------------------------------------------------------------
-- 2. Clicking the layout
---------------------------------------------------------------------------
local grid = G.ui.grid
local function ClickGrid(x, y, button)
  env.GetCursorPosition = function() return 412.5 + x, 655 - y end
  env.Fire(grid, "OnClick", button or "LeftButton")
end
local function Bet(key) return S.bets[key] and S.bets[key].amount or 0 end

Press("5")
ClickGrid(5 * 24 + 12, 33)                        -- 17 straight: 5
Press("25")
ClickGrid(6 * 24 - 1, 33)                         -- 17-20 split: 25
Check("click: straight 17 and split 17-20 placed", Bet("n17") == 5 and Bet("n17-20") == 25)
env.Fire(grid, "OnEnter")
env.Fire(grid, "OnUpdate")
Check("hover: shows what the spot pays", string.find(G.panel and (function()
  for _, o in ipairs(env.all) do if o.kind == "FontString" and string.find(o.text, "Split 17-20 - pays 17 to 1", 1, true) then return o.text end end
  return "" end)(), "pays 17", 1, true) ~= nil)
env.Fire(grid, "OnLeave")
ClickGrid(6 * 24 - 1, 33, "RightButton")          -- take 25 back
Check("right-click takes a chip back", Bet("n17-20") == 0)
Press("Undo")
Check("undo puts it back", Bet("n17-20") == 25)

local function Spot(label)
  for _, o in ipairs(env.all) do
    if o.kind == "Button" and Under(o, G.panel) and o.scripts.OnClick and o ~= grid then
      for _, f in ipairs(env.all) do
        if f.kind == "FontString" and f.parent == o and f.text == label then return o end
      end
    end
  end
end
local function ClickSpot(label, chip)
  Press(tostring(chip))
  env.Fire(assert(Spot(label), "no spot " .. label), "OnClick", "LeftButton")
end
ClickSpot("Red", 100)
ClickSpot("2nd 12", 5)
ClickSpot("1-18", 5)
ClickSpot("Odd", 5)
-- column 2-35 is the middle "2:1"
local cols = {}
for _, o in ipairs(env.all) do
  if o.kind == "Button" and Under(o, G.panel) and o ~= grid then
    for _, f in ipairs(env.all) do if f.kind == "FontString" and f.parent == o and f.text == "2:1" then table.insert(cols, o) end end
  end
end
Press("5")
env.Fire(cols[2], "OnClick", "LeftButton")
Check("outside bets placed", Bet("red") == 100 and Bet("dz2") == 5 and Bet("low") == 5 and Bet("odd") == 5 and Bet("col2") == 5)

local before = ns.db.chips
SpinTo(17)
Check("17 black: wins straight, split, dozen, column, low, odd; red loses",
  ns.db.chips - before == 530, ns.db.chips - before)
Check("the wheel strip stops on 17", (function()
  for _, o in ipairs(env.all) do
    if o.kind == "FontString" and o.text == "17" and o.parent and o.parent.parent and rawget(o.parent.parent, "w") == 336 then
      return o.parent.shown
    end
  end end)() == true)
Check("table cleared after the spin, Rebet ready", next(S.bets) == nil and Enabled("Rebet"))
Press("Rebet")
Check("rebet restores all 7 bets", Bet("n17") == 5 and Bet("n17-20") == 25 and Bet("red") == 100 and Bet("col2") == 5)
Press("Double")
Check("double doubles every bet", Bet("n17") == 10 and Bet("red") == 200)
Press("Undo")
Check("undo the double", Bet("n17") == 5 and Bet("red") == 100)
before = ns.db.chips
SpinTo(0)
Check("zero: everything loses (150)", ns.db.chips - before == -150, ns.db.chips - before)
Check("history keeps the newest first", ns.db.roulette.history[1] == 0 and ns.db.roulette.history[2] == 17)

-- Limits
if Enabled("Clear") then Press("Clear") end
Press("500")
for _ = 1, 3 do ClickGrid(5 * 24 + 12, 33) end
Check("one spot is capped at 1,000", Bet("n17") == 1000)
if Enabled("Clear") then Press("Clear") end
ns.db.chips = 30
Press("25"); ClickGrid(12, 11); ClickGrid(12, 11)
Check("can't bet more than you have", Bet("n3") == 30)
if Enabled("Clear") then Press("Clear") end
ns.db.chips = 10000

---------------------------------------------------------------------------
-- 3. House edge: every kind of bet returns 36/37 over all 37 numbers
---------------------------------------------------------------------------
local specs = {}
for key in pairs(seen) do
  local nums = {}
  for v in string.gfind(key, "%d+") do table.insert(nums, tonumber(v)) end
  table.insert(specs, G.InsideSpec(nums, 0, 0))
end
table.insert(specs, { key = "n0", nums = { 0 }, label = "Straight 0", x = 0, y = 0 })
for key, o in pairs(G.OUTSIDE) do table.insert(specs, { key = key, nums = o.nums, label = o.label, x = 0, y = 0 }) end
Check("bet spots: 144 inside + zero + 12 outside", table.getn(specs) == 144 + 1 + 12, table.getn(specs))
local staked, returned = 0, 0
Press("1")
for n = 0, 36 do
  for _, spec in ipairs(specs) do G.Place(spec, "LeftButton") end
  local stake = 0
  for _, b in pairs(S.bets) do stake = stake + b.amount end
  local c0 = ns.db.chips
  SpinTo(n)
  staked = staked + stake
  returned = returned + (ns.db.chips - c0) + stake
end
Check("all bets together return exactly 36/37", returned * 37 == staked * 36, returned .. " / " .. staked)

---------------------------------------------------------------------------
-- 4. Reload while the wheel turns; rebuy
---------------------------------------------------------------------------
if Enabled("Clear") then Press("Clear") end
Press("100")
ClickGrid(5 * 24 + 12, 33)
math.random = function(a, b) if a == 37 and not b then return 18 end return realRandom(a, b) end
Press("Spin")
math.random = realRandom
local saved = ns.db
local chipsMid = saved.chips
local env2, ns2 = Start(saved)
ns2:OpenGame("roulette")
Check("reload mid-spin: the spin still pays (17 straight)", ns2.db.chips == chipsMid + 3600 and ns2.db.roulette.pending == nil,
  ns2.db.chips - chipsMid)

Finish()
ns.db.chips = 0
G:OnShow()
Check("broke: no Rebuy button in the game", Find("Rebuy") == nil and Find("Spin") ~= nil)
Check("broke: the game says you're out of chips", ns:IsBroke())

io.write(ok and "ROULETTE PASS\n" or "ROULETTE FAIL\n")
os.exit(ok and 0 or 1)
