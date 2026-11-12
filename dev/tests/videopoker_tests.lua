-- Video Poker (Jacks or Better 9/6): hands are named and paid right, held
-- cards stay, the rest are drawn, bets and chips add up, and a dealt hand
-- survives a reload.
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
local function C(code)   -- "As", "Th", "7c"...
  local r = string.find("A23456789TJQK", string.sub(code, 1, 1), 1, true)
  local s = string.find("shdc", string.sub(code, 2, 2), 1, true)
  return { rank = r, suit = s }
end
local function Hand(str) local t = {} for code in string.gfind(str, "%S+") do table.insert(t, C(code)) end return t end

ns.db.chips = 1000
ns:OpenGame("videopoker")
local V = ns.games.videopoker
PANEL = V.panel
Check("Video Poker is in the game list", V ~= nil and V.name == "Video Poker")

-- Naming the hands
local cases = {
  { "Ts Js Qs Ks As", "Royal Flush" }, { "9h Th Jh Qh Kh", "Straight Flush" }, { "Ad 2d 3d 4d 5d", "Straight Flush" },
  { "7s 7h 7d 7c 2s", "Four of a Kind" }, { "Ks Kh Kd 4c 4s", "Full House" }, { "2c 8c Tc Jc Ac", "Flush" },
  { "As 2h 3d 4c 5s", "Straight" }, { "Ts Jh Qd Kc As", "Straight" }, { "9s 9h 9d Kc 2s", "Three of a Kind" },
  { "4s 4h 9d 9c Ks", "Two Pair" }, { "Js Jh 3d 7c 9s", "Jacks or Better" }, { "As Ah 3d 7c 9s", "Jacks or Better" },
}
for _, case in ipairs(cases) do
  local row = V.Classify(Hand(case[1]))
  Check("  " .. case[1] .. " is " .. case[2], row and V.PAYS[row].name == case[2], row and V.PAYS[row].name or "nothing")
end
Check("  Ts Th 3d 7c 9s (a low pair) pays nothing", V.Classify(Hand("Ts Th 3d 7c 9s")) == nil)
Check("  Qs Kh Ad 2c 3s (no wraparound straight) pays nothing", V.Classify(Hand("Qs Kh Ad 2c 3s")) == nil)
Check("  As Kh 9d 4c 2s pays nothing", V.Classify(Hand("As Kh 9d 4c 2s")) == nil)

-- The 9/6 pay table, per coin
Check("pays: full house 9, flush 6 (the 9/6 machine)", V.Payout(4, 1, 1) == 9 and V.Payout(5, 1, 1) == 6)
Check("pays: Jacks or Better gives the bet back", V.Payout(9, 3, 5) == 15)
Check("pays: Royal is 250 a coin, 800 a coin on five coins", V.Payout(1, 4, 1) == 1000 and V.Payout(1, 5, 1) == 4000)
Check("pays: coin size multiplies it", V.Payout(2, 5, 25) == 50 * 5 * 25)

-- Stacked decks
local stack
V.SetDeck(function()
  local i = 0
  return { Draw = function() i = i + 1; return stack[i] end }
end)

-- Bet controls
local cdb = ns.db.videopoker
Check("starts at five coins of 5: Deal 25", Find("Deal 25") ~= nil, cdb.coins .. "x" .. cdb.coin)
Press("Bet One")
Check("Bet One past five wraps to one coin", cdb.coins == 1 and Find("Deal 5") ~= nil, cdb.coins)
Press("Bet One"); Press("Bet One")
Check("...and counts up", cdb.coins == 3 and Find("Deal 15") ~= nil)
Press("Bet Max")
Press(">")
Check("Bet Max is five coins; > makes the coin 10: Deal 50", cdb.coins == 5 and cdb.coin == 10 and Find("Deal 50") ~= nil)
Press("<"); Press("<")
Check("< goes back down: coin 1", cdb.coin == 1)
Press(">")

-- A hand: hold the pair of jacks, draw three, make trips
stack = Hand("Js 4h Jd 9c 2s  Jh 5c 6d")
Press("Deal 25")
Check("Deal takes the bet", ns.db.chips == 975)
Check("five cards dealt, face up", V.ui.cards[1].card and V.ui.cards[1].card.rank == 11 and V.ui.cards[5].card.rank == 2)
Check("the button turns to Draw; bets are locked", Find("Draw") ~= nil and not Find("Bet Max").enabled)
env.Fire(V.ui.holds[1], "OnClick", "LeftButton")
env.Fire(V.ui.holds[3], "OnClick", "LeftButton")
env.Fire(V.ui.holds[5], "OnClick", "LeftButton")
env.Fire(V.ui.holds[5], "OnClick", "LeftButton")   -- changed my mind
Check("clicking a card holds it (and again lets it go)", V.ui.held[1].shown ~= false and V.ui.held[3].shown ~= false
  and V.ui.held[5].shown == false and V.ui.held[2].shown == false)
Press("Draw")
local cards = {}
for k = 1, 5 do cards[k] = V.ui.cards[k].card end
Check("held cards stay; the rest are drawn", cards[1].rank == 11 and cards[3].rank == 11 and cards[2].rank == 11
  and cards[4].rank == 5 and cards[5].rank == 6)
Check("three Jacks pay 3 a coin: 75 for 25", ns.db.chips == 975 + 75, ns.db.chips)
Check("the winning line is lit", V.ui.payRows[7].lit.shown ~= false and V.ui.payRows[9].lit.shown == false)
Check("stats: one hand, one win", cdb.stats.hands == 1 and cdb.stats.wins == 1 and cdb.stats.won == 75 and cdb.stats.wagered == 25)

-- A losing hand
stack = Hand("2s 4h 7d 9c Ks  3c 5d 8h Ts Qd")
Press("Deal 25")
Press("Draw")
Check("nothing held, nothing made: the bet is lost", ns.db.chips == 1050 - 25, ns.db.chips)
Check("...and nothing is lit", V.ui.payRows[9].lit.shown == false)

-- A Royal on five coins
stack = Hand("Ts Js Qs Ks 2h  As")
Press("Deal 25")
for k = 1, 4 do env.Fire(V.ui.holds[k], "OnClick", "LeftButton") end
Press("Draw")
Check("a Royal Flush on five coins of 5 pays 4,000 a coin... 20,000", ns.db.chips == 1025 - 25 + 20000, ns.db.chips)
Check("...and counts as a royal", cdb.stats.royals == 1)

-- A dealt hand survives a reload, and draws without repeating a card in hand
stack = Hand("Qs Qh 3d 8c 5s")
Press("Deal 25")
env.Fire(V.ui.holds[1], "OnClick", "LeftButton")
env.Fire(V.ui.holds[2], "OnClick", "LeftButton")
local chipsDealt = ns.db.chips
Check("a dealt hand counts as chips in play", V:ChipsInPlay())
local env2, ns2 = Start(env.CowCasinoDB)
ns2:OpenGame("videopoker")
env, ns = env2, ns2
V = ns.games.videopoker
PANEL = V.panel
Check("after a reload the hand is still there, holds and all", ns.db.videopoker.hand ~= nil and V.ui.cards[1].card.rank == 12
  and V.ui.held[1].shown ~= false and V.ui.held[3].shown == false and ns.db.chips == chipsDealt)
Press("Draw")
local seen, dup = {}, false
for k = 1, 5 do
  local c = V.ui.cards[k].card
  local key = c.rank .. "/" .. c.suit
  if seen[key] then dup = true end
  seen[key] = true
end
Check("...Draw finishes it, with no card twice", ns.db.videopoker.hand == nil and not dup and V.ui.cards[1].card.rank == 12
  and V.ui.cards[2].card.rank == 12)
Check("...and the pair of Queens at least pays the bet back", ns.db.chips >= chipsDealt + 25, ns.db.chips)

-- Start over gives up a dealt hand
Press("Deal 25")
V:Abandon()
Check("Start over gives up a dealt hand", ns.db.videopoker.hand == nil and not V:ChipsInPlay() and Find("Deal 25") ~= nil)

-- Not enough chips
ns.db.chips = 20
V:OnShow()
Check("Deal is off when the bet is more than your chips", not Find("Deal 25").enabled)

io.write(ok and "VIDEO POKER PASS\n" or "VIDEO POKER FAIL\n")
os.exit(ok and 0 or 1)
