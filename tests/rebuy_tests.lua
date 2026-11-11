-- Out of chips: back to the menu to pick 1,000 / 10,000 / 50,000, in every game.
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
  env.GetNumPartyMembers = function() return 1 end
  env.UnitName = function(u) if u == "player" then return "Host" elseif u == "party1" then return "Bob" end end
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
local function Tick(sec)
  for _ = 1, math.floor(sec * 10 + 0.5) do
    env.CLOCK = env.CLOCK + 0.1
    for _, o in ipairs(env.all) do if o.scripts.OnUpdate and Visible(o) then env.Fire(o, "OnUpdate", 0.1) end end
  end
end
local page = ns.rebuyPage
local function InGame(id) return ns.currentGame == id and not page:IsShown() end
local function Kicked() return ns.currentGame == nil and page:IsVisible() end

Check("new players start with 1,000", ns.db.chips == 1000)
Check("no rebuy screen while you have chips", (Tick(3) or true) and not page:IsShown())

-- On the menu with nothing left: the screen comes up at once
ns.db.chips = 0
Tick(0.5)
Check("out of chips on the menu: rebuy screen shows", Kicked())
Check("it offers 1,000, 10,000 and 50,000", Find("1,000 chips") and Find("10,000 chips") and Find("50,000 chips") and true)
ns:OpenGame("slots")
Check("can't open a game while out of chips", ns.currentGame == nil and page:IsShown())
local rebuys = ns.db.rebuys
Press("10,000 chips")
Check("picking 10,000 gives 10,000 and closes the screen", ns.db.chips == 10000 and not page:IsShown() and ns.db.rebuys == rebuys + 1)
Check("best chips counts the fresh stack", ns.db.bestChips >= 10000)

-- Each solo game, once its chips are gone: a short pause, then the menu
for _, id in ipairs({ "blackjack", "mines", "slots", "roulette", "holdem" }) do
  ns:OpenGame(id)
  ns.db.chips = 0
  Tick(1)
  local stayed = InGame(id)
  Tick(2)
  Check(id .. ": out of chips -> a moment to see it, then the menu", stayed and Kicked())
  Press("1,000 chips")
end
Check("each pick is the amount picked", ns.db.chips == 1000)

ns:OpenGame("blackjack")
Check("Blackjack after a fresh stack: Deal is ready with a bet", Find("Deal 25") ~= nil and Find("Deal 25").enabled)
Check("no Rebuy buttons anywhere", Find("Rebuy") == nil and Find("Rebuy chips") == nil)

-- Chips still in play: no kick
ns:OpenGame("mines")
Press("Bet 25")
local before = ns.db.chips
ns.db.chips = 0
Tick(5)
Check("mines: a board in progress keeps you in the game", InGame("mines"))
ns.db.mines.active = nil
Tick(3)
Check("...and once it's over with nothing left, the menu", Kicked())
Press("50,000 chips")
Check("50,000 works too", ns.db.chips == 50000)

ns.db.chips = 1000
ns:OpenGame("holdem")
Press("1,000")
Check("hold'em: bought in with everything", ns.db.chips == 0)
Tick(5)
Check("hold'em: seated at a table keeps you in the game", InGame("holdem"))
ns.db.chips = 0.5
Check("half a chip and nothing in play counts as out", (function()
  local g = ns.games.holdem; local saved = g.ChipsInPlay
  g.ChipsInPlay = function() return false end
  local r = ns:IsBroke(); g.ChipsInPlay = saved; return r end)())

-- Party Blackjack: seated at your party table
local env2, ns2 = Start(nil)
env, ns = env2, ns2
page = ns.rebuyPage
ns:OpenGame("blackjack")
Press("Party play")
Press("Host a table")
ns.db.chips = 0
Tick(5)
Check("party blackjack: hosting a table keeps you in the game", InGame("blackjack") and ns.PartyBlackjack.T.mode == "host")

-- A reload with a spin still owed: not out until it pays
local env3, ns3 = Start(nil, function(n)
  n.db.chips = 0
  n.db.slots = { pending = { lineBet = 1, stops = { 1, 1, 1, 1, 1 }, lines = 10 } }
end)
Check("reload with a slots spin owed: not out of chips", not ns3:IsBroke())

-- Pachinko is gone: balls left in a save are cashed in
local env4, ns4 = Start(nil, function(n) end)
local base4 = ns4.db.chips
local env5, ns5 = Start({ chips = 300, pachinko = { tray = 40, inFlight = 2, held = 3 }, order = { "pachinko", "slots" } })
Check("an old save's pachinko balls (40 + 2 in flight) become 42 chips", ns5.db.chips == 342 and ns5.db.pachinko == nil, ns5.db.chips)
Check("an old saved order naming pachinko still works", ns5:MenuOrder()[1] == "slots" and ns5.games.pachinko == nil)


-- A fresh stack resets every game's stats
local env6, ns6 = Start({ chips = 0, bestChips = 25000, rebuys = 2,
  blackjack = { stats = { rounds = 40, wins = 20, losses = 18, pushes = 2, blackjacks = 3, best = 25000, rebuys = 1 } },
  mines = { stats = { games = 30, cashouts = 12, losses = 18, bestMultiplier = 7.5, biggestWin = 900 } },
  slots = { stats = { spins = 300, wagered = 3000, won = 2800, biggestWin = 500, jackpots = 1 } },
  roulette = { stats = { spins = 50, wagered = 900, returned = 800, bestWin = 350, counts = { [17] = 4 } }, history = { 17, 3, 0 } },
  holdem = { stats = { hands = 120, won = 40, biggestPot = 2200, buyIns = 6 } },
  partybj = { stats = { wins = 9, losses = 7, pushes = 1, blackjacks = 2, buyIns = 3 } } })
-- open two of the games first; the rest are reset without ever being opened
ns6:SetCardArt("plain")
local function Vis6(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Tick6(sec) for _ = 1, math.floor(sec * 10 + 0.5) do env6.CLOCK = env6.CLOCK + 0.1; for _, o in ipairs(env6.all) do if o.scripts.OnUpdate and Vis6(o) then env6.Fire(o, "OnUpdate", 0.1) end end end end
Tick6(1)
local function Press6(text) for _, o in ipairs(env6.all) do if o.kind == "Button" and o.text == text and Vis6(o) then env6.Fire(o, "OnClick", "LeftButton") return true end end end
Check("an old save with no chips: the rebuy screen", ns6.rebuyPage:IsShown())
Press6("10,000 chips")
local db6 = ns6.db
local function AllZero(t, skip)
  for k, v in pairs(t) do if not (skip and skip[k]) and type(v) == "number" and v ~= 0 then return false, k .. "=" .. v end end
  return true
end
Check("rebuy: best chips start again from the new stack", db6.bestChips == 10000, db6.bestChips)
local z, why = AllZero(db6.blackjack.stats, { best = true })
Check("rebuy: Blackjack stats start over (best = the new stack)", z and db6.blackjack.stats.best == 10000 and db6.blackjack.stats.rounds == 0, why)
z, why = AllZero(db6.mines.stats); Check("rebuy: Mines stats start over", z and db6.mines.stats.games == 0, why)
z, why = AllZero(db6.slots.stats); Check("rebuy: Slots stats start over", z and db6.slots.stats.spins == 0, why)
z, why = AllZero(db6.roulette.stats)
Check("rebuy: Roulette stats start over, its recent numbers stay", z and db6.roulette.stats.spins == 0 and next(db6.roulette.stats.counts) == nil
  and table.getn(db6.roulette.history) == 3, why)
z, why = AllZero(db6.holdem.stats); Check("rebuy: Hold'em stats start over", z and db6.holdem.stats.hands == 0, why)
z, why = AllZero(db6.partybj.stats); Check("rebuy: party Blackjack stats start over", z and db6.partybj.stats.wins == 0, why)
-- games opened after the reset show their fresh stats, and keep counting
ns6:OpenGame("slots")
local fresh = false
for _, f in ipairs(env6.all) do if f.kind == "FontString" and Vis6(f) and f.text and string.find(f.text, "Pick a line bet and spin", 1, true) then fresh = true end end
Check("Slots opened after: shows a fresh start", fresh)
Press6("Spin"); Tick6(3)
Check("...and counts the new spin", db6.slots.stats.spins == 1)
ns6:OpenGame("blackjack")
Press6("Deal 25"); for _ = 1, 10 do Press6("No thanks"); Press6("Stand"); Tick6(1) end
Check("Blackjack opened after: counts from zero", db6.blackjack.stats.rounds >= 1 and db6.blackjack.stats.rounds <= 3, db6.blackjack.stats.rounds)

-- Start over, from the CowCasino Options
local env7, ns7 = Start({ chips = 4321, bestChips = 9000, slots = { stats = { spins = 12, wagered = 120, won = 90, biggestWin = 40, jackpots = 0 } } })
local function Vis7(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Tick7(sec) for _ = 1, math.floor(sec * 10 + 0.5) do env7.CLOCK = env7.CLOCK + 0.1; for _, o in ipairs(env7.all) do if o.scripts.OnUpdate and Vis7(o) then env7.Fire(o, "OnUpdate", 0.1) end end end end
local function Btn7(text) for _, o in ipairs(env7.all) do if o.kind == "Button" and o.text == text and Vis7(o) then return o end end end
local function Click7(b) env7.Fire(b, "OnClick", "LeftButton") end
Tick7(1)
Click7(Btn7("Options"))
local so = ns7.optionsPage.startOver
Check("Options has a Start over button", so and Vis7(so) and so.text == "Start over")
Click7(so)
Check("one click asks to confirm, nothing changes yet", so.text == "Click again to confirm" and ns7.db.chips == 4321)
Tick7(4)
Check("...and lets go after 3 seconds", so.text == "Start over" and ns7.db.chips == 4321)
Click7(so); Tick7(4); Click7(so)
Check("a second click after the 3 seconds only asks again", so.text == "Click again to confirm" and ns7.db.chips == 4321)
Click7(so)
Check("two clicks: chips gone, Options closed, the rebuy screen up", ns7.db.chips == 0 and not ns7.optionsPage:IsShown()
  and ns7.rebuyPage:IsVisible() and ns7.currentGame == nil)
Click7(Btn7("50,000 chips"))
Check("picking a stack: 50,000 and fresh stats, like running out", ns7.db.chips == 50000 and ns7.db.slots.stats.spins == 0
  and ns7.db.bestChips == 50000 and not ns7.rebuyPage:IsShown())
-- not while chips are in play
ns7:OpenGame("mines")
Click7(Btn7("Bet 25"))
local before7 = ns7.db.chips
ns7:ShowMenu()
Click7(Btn7("Options"))
Click7(so)
Check("with a Mines board in progress: 'Finish your game first'", so.text == "Finish your game first" and ns7.db.chips == before7)
Click7(so)
Check("...and clicking again still does nothing", ns7.db.chips == before7 and not ns7.rebuyPage:IsShown())
Tick7(4)
Check("...the button comes back afterward", so.text == "Start over")
Check("StartOver itself refuses while chips are in play", ns7:StartOver() == false and ns7.db.chips == before7)

io.write(ok and "REBUY PASS\n" or "REBUY FAIL\n")
os.exit(ok and 0 or 1)
