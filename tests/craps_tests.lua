-- Craps (solo): the rules against an independent copy, the table, saving bets.
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
local function Find(text) for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == text and Visible(o) then return o end end end
local function Press(text) local b = Find(text); assert(b, "no button " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end
local function Tick(sec) for _ = 1, math.floor(sec * 10 + 0.5) do env.CLOCK = env.CLOCK + 0.1; for _, o in ipairs(env.all) do if o.scripts.OnUpdate and Visible(o) then env.Fire(o, "OnUpdate", 0.1) end end end end

local Rules = ns.CrapsRules

---------------------------------------------------------------------------
-- Every roll, every point, every bet, against rules written separately
---------------------------------------------------------------------------
local function Expected(point, total)
  local e = {}   -- key -> net, or nil if the bet stays
  if total == 2 then e.field = 20 elseif total == 12 then e.field = 30
  elseif total == 3 or total == 4 or total == 9 or total == 10 or total == 11 then e.field = 10 else e.field = -10 end
  e.any7 = (total == 7) and 40 or -10
  e.anyCraps = (total == 2 or total == 3 or total == 12) and 70 or -10
  local newPoint = point
  if not point then
    if total == 7 or total == 11 then e.pass, e.dontPass = 10, -10
    elseif total == 2 or total == 3 then e.pass, e.dontPass = -10, 10
    elseif total == 12 then e.pass, e.dontPass = -10, 0
    else newPoint = total end
  elseif total == point then
    e.pass, e.dontPass = 10, -10
    e.odds = ({ [4] = 20, [10] = 20, [5] = 15, [9] = 15, [6] = 12, [8] = 12 })[point]
    newPoint = nil
  elseif total == 7 then
    e.pass, e.dontPass, e.odds = -10, 10, -10
    newPoint = nil
  end
  return e, newPoint
end
local bad = {}
for _, point in ipairs({ false, 4, 5, 6, 8, 9, 10 }) do
  for d1 = 1, 6 do for d2 = 1, 6 do
    local bets = { pass = 10, dontPass = 10, field = 10, any7 = 10, anyCraps = 10 }
    if point then bets.odds = 10 end
    local back, newPoint = Rules.Settle(bets, point or nil, d1, d2)
    local want, wantPoint = Expected(point or nil, d1 + d2)
    for key in pairs(bets) do
      local got = back[key] and (back[key] - bets[key]) or nil
      if got ~= want[key] then table.insert(bad, (point or "off") .. " " .. d1 .. "+" .. d2 .. " " .. key .. " got " .. tostring(got) .. " want " .. tostring(want[key])) end
    end
    if newPoint ~= wantPoint then table.insert(bad, (point or "off") .. " " .. d1 .. "+" .. d2 .. " point " .. tostring(newPoint)) end
  end end
end
Check("every roll at every point settles every bet right (252 rolls)", table.getn(bad) == 0, table.concat(bad, "; "))
Check("odds pay in whole chips, rounding up (25 on 6 wins 30, 5 on 5 wins 8)", Rules.OddsWin(6, 25) == 30 and Rules.OddsWin(5, 5) == 8)
Check("line bets go down on the come-out only, odds only behind Pass",
  Rules.CanAdd("pass", nil, {}) and not Rules.CanAdd("pass", 6, {}) and not Rules.CanAdd("odds", 6, {})
  and Rules.CanAdd("odds", 6, { pass = 5 }) and not Rules.CanAdd("odds", nil, { pass = 5 }))
Check("bets pack and unpack for party play", Rules.Pack(Rules.Unpack("25,50,0,5,0,10")) == "25,50,0,5,0,10")

---------------------------------------------------------------------------
-- The table
---------------------------------------------------------------------------
local RIG = {}
Rules.Roll = function() local r = table.remove(RIG, 1); return r[1], r[2] end
ns.db.chips = 1000
ns:OpenGame("craps")
local G = ns.games.craps
local db = ns.db.craps
local function Spot(key) for _, b in ipairs(G.ui.spots) do if b.spot.key == key then return b end end end
local function Click(key, right) env.Fire(Spot(key), "OnClick", right and "RightButton" or "LeftButton") end
local function Roll(d1, d2) table.insert(RIG, { d1, d2 }); Press("Roll"); Tick(1.2) end
local function Status() return G.ui.status.text or "" end

Check("Craps is on the menu", ns.games.craps ~= nil and Find("Roll") ~= nil)
do
  local rel = string.gsub(string.gsub(G.icon, "^Interface\\AddOns\\CowCasino\\", ""), "\\", "/")
  local f = io.open(ADDON .. "/" .. rel .. ".tga", "rb")
  local hdr = f and f:read(18)
  if f then f:close() end
  Check("the menu icon is the painted dice, a 64x64 32-bit TGA", hdr ~= nil and string.byte(hdr, 3) == 2
    and string.byte(hdr, 13) == 64 and string.byte(hdr, 15) == 64 and string.byte(hdr, 17) == 32, G.icon)
end
Check("nothing to roll with no bets down", not Find("Roll").enabled)
Press("25")
Click("pass")
Press("5")
Click("field")
Check("chips go on the spots", db.bets.pass == 25 and db.bets.field == 5 and ns.db.chips == 970, ns.db.chips)
Click("odds")
Check("no odds before there's a point", db.bets.odds == nil and string.find(Status(), "Odds go behind", 1, true) ~= nil)
Roll(3, 3)
Check("a 6 on the come-out sets the point; the Field loses", db.point == 6 and db.bets.pass == 25 and db.bets.field == nil
  and ns.db.chips == 970 and string.find(Status(), "point is 6", 1, true) ~= nil, Status())
Click("pass", true)
Check("Pass can't come down once there's a point", db.bets.pass == 25)
Click("dontPass")
Check("Don't Pass can't go down during a point", db.bets.dontPass == nil)
Press("25")
Click("odds"); Click("odds"); Click("odds"); Click("odds")
Check("odds up to 3x the Pass bet", db.bets.odds == 75 and ns.db.chips == 895, db.bets.odds)
Check("Party play is off while bets are down", not Find("Party play").enabled)
Roll(2, 4)
Check("point made: Pass pays 1:1 and the odds 6:5", ns.db.chips == 895 + 50 + 75 + 90 and db.point == nil
  and next(db.bets) == nil, ns.db.chips)
Check("...and the status says so", string.find(Status(), "Point made", 1, true) ~= nil and string.find(Status(), "win 115", 1, true) ~= nil, Status())
Check("stats: rolls, points made, net", db.stats.rolls == 2 and db.stats.pointsMade == 1 and db.stats.net == ns.db.chips - 1000, db.stats.net)

-- Same bets, a seven out
Check("Same bets is ready after the roll", Find("Same bets").enabled)
Press("Same bets")
Check("...Pass goes back; the odds wait for a point", db.bets.pass == 25 and db.bets.odds == nil and db.bets.field == nil)
Press("5")
Click("field")
Roll(4, 4)
Check("during a point, Same bets puts the Field back after each roll", db.point == 8 and db.bets.field == nil and Find("Same bets").enabled)
local c0 = ns.db.chips
Press("Same bets")
Check("...just the Field: Pass is still up", db.bets.field == 5 and db.bets.pass == 25 and ns.db.chips == c0 - 5)
Check("...and nothing more to put back", not Find("Same bets").enabled)
Press("25")
Click("odds"); Click("odds")
Roll(2, 3)
Press("Same bets")
Check("...odds and Field both come back behind the Pass bet", db.bets.odds == 50 and db.bets.field == 5 and db.bets.pass == 25)
Roll(3, 4)
Check("seven out: Pass loses", db.point == nil and next(db.bets) == nil and db.stats.sevenOuts == 1)

-- Don't Pass and a 12
local before = ns.db.chips
Press("25")
Click("dontPass"); Click("pass")
Press("5")
Click("anyCraps")
Roll(6, 6)
Check("12 on the come-out: Don't Pass pushes, Pass loses, Any Craps pays 7:1", ns.db.chips == before - 25 + 35,
  ns.db.chips - before)

-- Taking bets down
before = ns.db.chips
Press("100")
Click("field"); Click("any7")
Press("Take down")
Check("Take down returns everything that can come down", ns.db.chips == before and next(db.bets) == nil)

---------------------------------------------------------------------------
-- Bets survive a reload
---------------------------------------------------------------------------
Press("25")
Click("pass")
Roll(5, 5)
Click("odds")
local chipsNow = ns.db.chips
Check("chips in play while bets are down", ns:ChipsInPlay() and not ns:IsBroke())
local env2, ns2 = Start(ns.db)
ns2:OpenGame("craps")
local db2 = ns2.db.craps
Check("after a reload the bets and the point are still there", db2.point == 10 and db2.bets.pass == 25 and db2.bets.odds == 25
  and ns2.db.chips == chipsNow)
Check("...and it says so", string.find(ns2.games.craps.ui.status.text or "", "Welcome back", 1, true) ~= nil)

---------------------------------------------------------------------------
-- A fresh stack resets the stats
---------------------------------------------------------------------------
ns:RebuyChips(1000)
Check("a fresh stack starts the craps stats over", db.stats.rolls == 0 and db.stats.net == 0)
Check("stats line shows Net", string.find(G.ui.stats.text or "", "Net", 1, true) ~= nil, G.ui.stats.text)

io.write(ok and "CRAPS PASS\n" or "CRAPS FAIL\n")
os.exit(ok and 0 or 1)
