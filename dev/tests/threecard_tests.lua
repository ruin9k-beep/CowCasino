-- Three Card Poker: hands are ranked right (a straight beats a flush), the
-- dealer qualifies on Queen high, every bet settles right (Ante, Play, the
-- Ante bonus and Pair Plus, which pays even on a fold), and a dealt hand
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
ns:OpenGame("threecard")
local G = ns.games.threecard
PANEL = G.panel
local CAT = G.CAT
Check("Three Card Poker is in the game list", G ~= nil and G.name == "Three Card Poker")

-- Ranking three cards
local cases = {
  { "Qs Ks As", CAT.SFLUSH }, { "As 2s 3s", CAT.SFLUSH }, { "7h 7d 7c", CAT.TRIPS },
  { "9s Th Jd", CAT.STRAIGHT }, { "Ac 2d 3h", CAT.STRAIGHT }, { "2c 8c Jc", CAT.FLUSH },
  { "4s 4h Kd", CAT.PAIR }, { "As Kh 9d", CAT.HIGH }, { "Qs Ks Ad", CAT.STRAIGHT },
}
for _, case in ipairs(cases) do
  local cat = G.Evaluate(Hand(case[1]))
  Check("  " .. case[1] .. " is " .. G.HandName(Hand(case[1])), cat == case[2], cat)
end
Check("  Ks As 2d is no straight (no wrapping round)", G.Evaluate(Hand("Ks As 2d")) == CAT.HIGH)
Check("a straight beats a flush in three cards", G.Compare(Hand("4s 5h 6d"), Hand("2c 8c Ac")) == 1)
Check("A-2-3 is the lowest straight", G.Compare(Hand("As 2h 3d"), Hand("2s 3h 4d")) == -1
  and G.Compare(Hand("Qs Kh Ad"), Hand("Js Qh Kd")) == 1)
Check("a pair is compared on the pair first, then the kicker", G.Compare(Hand("9s 9h 2d"), Hand("8s 8h Ad")) == 1
  and G.Compare(Hand("9s 9h 5d"), Hand("9d 9c 4s")) == 1)
Check("high cards compare top down", G.Compare(Hand("Ks 7h 2d"), Hand("Ks 6h 5d")) == 1)
Check("a dead tie", G.Compare(Hand("Ks 7h 2d"), Hand("Kd 7c 2s")) == 0)
Check("the dealer qualifies on Queen high", G.Qualifies(Hand("Qs 4h 2d")) and not G.Qualifies(Hand("Js Th 8d"))
  and G.Qualifies(Hand("2s 2h 3d")))
Check("hand names", G.HandName(Hand("6s 6h 2d")) == "Pair of Sixes" and G.HandName(Hand("As Th 2d")) == "Ace high")

-- Settling, ante 10 and Pair Plus 5
local function S(mine, dealer, play, pp)
  return G.Settle({ ante = 10, pp = pp or 0, cards = Hand(mine), dealer = Hand(dealer) }, play)
end
Check("win: Ante and Play pay 1 to 1 (40 back on 20)", S("Ks Kh 2d", "Qs 4h 2c", true).paid == 40)
Check("dealer doesn't qualify: Ante pays, Play pushes (30 back)", S("4s 5h 9d", "Js 8h 2c", true).paid == 30)
Check("dealer wins: nothing back", S("4s 5h 9d", "Qs 8h 2c", true).paid == 0)
Check("a tie: both bets back", S("Ks 7h 2d", "Kd 7c 2s", true).paid == 20)
local sf = S("9h Th Jh", "As Ad Kc", true, 5)
Check("a straight flush: Ante bonus 5x even on a win, Pair Plus 40x", sf.bonus == 50 and sf.pairPlus == 200
  and sf.paid == 40 + 50 + 205, sf.paid)
local trips = S("7s 7h 7d", "Ah Ad Ac", true)
Check("trips lose to better trips but still get the Ante bonus (4x)", trips.result == "lose" and trips.paid == 40)
local fold = S("4s 4h 9d", "Ah Kd Kc", false, 5)
Check("Pair Plus pays on a fold; the Ante is lost", fold.result == "fold" and fold.paid == 10, fold.paid)
Check("Pair Plus pays: flush 4, straight 6", S("2c 8c Jc", "2s 3s 5d", false, 5).pairPlus == 20
  and S("4s 5h 6d", "2s 3s 5d", false, 5).pairPlus == 30)

-- Stacked decks: your three, then the dealer's three
local stack
G.SetDeck(function()
  local i = 0
  return { Draw = function() i = i + 1; return stack[i] end }
end)

-- Bet controls
local cdb = ns.db.threecard
Check("starts at Ante 25, no Pair Plus: Deal 25", Find("Deal 25") ~= nil, cdb.ante .. "/" .. cdb.pp)
Press(">")                                   -- the first > is the Ante's
local ppUp
for _, o in ipairs(env.all) do if o.kind == "Button" and Visible(o) and o.text == ">" and o ~= Find(">") then ppUp = o end end
env.Fire(ppUp, "OnClick", "LeftButton"); env.Fire(ppUp, "OnClick", "LeftButton")
Check("Ante up to 50, Pair Plus up to 10: Deal 60", cdb.ante == 50 and cdb.pp == 10 and Find("Deal 60") ~= nil)

-- A winning hand
stack = Hand("Ks Kh 2d  Qs 4h 2c")
Press("Deal 60")
Check("Deal takes the Ante and Pair Plus", ns.db.chips == 940)
Check("your cards are face up, the dealer's face down", G.ui.cards[1].card and G.ui.cards[1].card.rank == 13
  and G.ui.dealerCards[1].faceUp == false, tostring(G.ui.dealerCards[1].faceUp))
Check("Play and Fold show; bets are locked", Find("Play 50") ~= nil and Find("Fold") ~= nil and not Find(">").enabled)
Press("Play 50")
-- 940 - 50 (play) + 200 (ante+play) + 20 (pair plus 1:1 on 10, with the bet back)
Check("Play: Ante and Play win, the pair pays Pair Plus (+170)", ns.db.chips == 1110, ns.db.chips)
Check("the dealer's cards turn over", G.ui.dealerCards[1].faceUp == true)
Check("stats: one hand, one win, one Pair Plus", cdb.stats.hands == 1 and cdb.stats.wins == 1 and cdb.stats.pairPlusWins == 1
  and cdb.stats.wagered == 110 and cdb.stats.won == 220)

-- A fold
stack = Hand("4s 7h 9d  As Kh Qc")
Press("Deal 60")
Press("Fold")
Check("a fold loses the Ante and the Pair Plus", ns.db.chips == 1050, ns.db.chips)
Check("...and counts as a fold", cdb.stats.folds == 1)

-- A dealt hand survives a reload
stack = Hand("Qs Qh 3d  2c 5d 8h")
Press("Deal 60")
local chipsDealt = ns.db.chips
Check("a dealt hand counts as chips in play", G:ChipsInPlay())
local env2, ns2 = Start(env.CowCasinoDB)
ns2:OpenGame("threecard")
env, ns = env2, ns2
G = ns.games.threecard
PANEL = G.panel
Check("after a reload the hand is still there", ns.db.threecard.hand ~= nil and G.ui.cards[1].card.rank == 12
  and ns.db.chips == chipsDealt and Find("Play 50") ~= nil)
Press("Play 50")
-- dealer 8 high doesn't qualify: ante 2x + play back; pair of queens: pair plus 10 + 10
Check("...and plays out: dealer doesn't qualify, Ante wins", ns.db.chips == chipsDealt - 50 + 150 + 20, ns.db.chips)

-- Start over gives up a dealt hand
G.SetDeck(function() return ns:NewShoe(1) end)
Press("Deal 60")
G:Abandon()
Check("Start over gives up a dealt hand", ns.db.threecard.hand == nil and not G:ChipsInPlay() and Find("Deal 60") ~= nil)

-- Not enough chips for the Play bet as well
ns.db.chips = 100
G:OnShow()
Check("Deal is off unless your chips cover Ante, Play and Pair Plus", not Find("Deal 60").enabled)

-- Every hand settles to whole chips and never pays from nothing
local whole = true
for _ = 1, 2000 do
  local deck = ns:NewShoe(1)
  local h = { ante = 25, pp = 10, cards = { deck:Draw(), deck:Draw(), deck:Draw() }, dealer = { deck:Draw(), deck:Draw(), deck:Draw() } }
  for _, play in ipairs({ true, false }) do
    local out = G.Settle(h, play)
    if out.paid ~= math.floor(out.paid) or out.paid < 0 then whole = false end
  end
end
Check("2,000 random hands settle to whole chips", whole)

io.write(ok and "THREE CARD PASS\n" or "THREE CARD FAIL\n")
os.exit(ok and 0 or 1)
