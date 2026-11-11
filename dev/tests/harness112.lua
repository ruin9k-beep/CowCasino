dofile((os.getenv("MOCK") or "mock112.lua"))
local ns = CowCasino.ns

-- Timer frame (Core) and helpers
local timerFrame
for _, o in ipairs(all) do if o.scripts.OnUpdate and not o.parent and rawget(o, "file") == "Core.lua" then timerFrame = o; break end end
local function Flush() local g = 0; while timerFrame.shown do CLOCK = CLOCK + 10; Fire(timerFrame, "OnUpdate", 10); g = g + 1; assert(g < 500) end end

-- Stacked shoe support
stacked = nil
local realNewShoe = ns.NewShoe
function ns:NewShoe(decks)
  local s = realNewShoe(self, decks)
  local draw = s.Draw
  s.Draw = function(self) if stacked and #stacked > 0 then return table.remove(stacked, 1) end return draw(self) end
  return s
end

-- ADDON_LOADED
for _, o in ipairs(all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
assert(ns.db and CowCasinoFrame, "addon did not load")
CowCasinoFrame:Show()
ns:OpenGame("blackjack")
local db = ns.db.blackjack

local function visible(o) while o do if not o.shown then return false end; o = o.parent end return true end
local function Find(text)
  for _, o in ipairs(all) do
    if (o.kind == "Button" or o.kind == "CheckButton") and o.text == text and visible(o) then return o end
  end
end
local function FindPrefix(p)
  for _, o in ipairs(all) do
    if o.kind == "Button" and string.sub(o.text, 1, #p) == p and visible(o) then return o end
  end
end
local function Click(text, button)
  local b = Find(text) or FindPrefix(text)
  assert(b, "no button " .. text)
  assert(b.enabled, "button disabled: " .. text)
  Fire(b, "OnClick", button or "LeftButton")
  Flush()
end
local function Enabled(text) local b = Find(text) or FindPrefix(text); return b and b.enabled and true or false end

local R = { A=1, J=11, Q=12, K=13 }
local function C(r, s) return { rank = R[r] or tonumber(r), suit = s or 1 } end
local betDB
local function SetBet(n)
  Click("Clear")
  local left = n
  for _, v in ipairs({ 500, 100, 25, 5 }) do
    while left >= v do Click(tostring(v)); left = left - v end
  end
  local t = betDB or db; assert(t.bet == n, "bet is " .. t.bet)
end
local function Scenario(name, cards, bet, actions, expectNet)
  ns.db.chips = 1000
  stacked = cards
  SetBet(bet)
  local before = ns.db.chips
  Click("Deal")
  for _, a in ipairs(actions) do Click(a) end
  Flush()
  local net = ns.db.chips - before
  local ok = math.abs(net - expectNet) < 1e-9 and Enabled("Deal")
  io.write(string.format("%-34s net %+6.1f  expected %+6.1f  %s\n", name, net, expectNet, ok and "PASS" or "FAIL"))
  stacked = nil
  return ok
end

local allOk = true
local function T(...) allOk = Scenario(...) and allOk end
-- deal order: player, dealer(up), player, dealer(hole), then hits
T("19 v 17 stand, win", { C(10), C(10), C(9), C(7) }, 10, { "Stand" }, 10)
T("player blackjack 3:2", { C("A"), C(9), C("K"), C(7) }, 10, {}, 15)
T("dealer bust after hit", { C(10), C(10), C(2), C(6), C(5), C(10) }, 10, { "Hit", "Stand" }, 10)
T("player bust", { C(10), C(10), C(6), C(7), C(9) }, 10, { "Hit" }, -10)
T("push 18 v 18", { C(10), C(10), C(8), C(8) }, 10, { "Stand" }, 0)
T("double 11 -> 21 v 20", { C(5), C(10), C(6), C(10), C(10) }, 10, { "Double" }, 20)
T("split 8s, double first, dlr bust", { C(8), C(6), C(8), C(10), C(3), C(10), C(10), C(10) }, 10,
  { "Split", "Double", "Stand" }, 30)
T("insured, dealer blackjack", { C(10), C("A"), C(9), C("K") }, 10, { "Insure" }, 0)
T("no insurance, dealer blackjack", { C(10), C("A"), C(9), C("K") }, 10, { "No thanks" }, -10)
T("insurance lost, then win", { C(10), C("A"), C(9), C(6), C(10) }, 10, { "Insure", "Stand" }, 5)
T("even money on blackjack", { C("A"), C("A"), C("K"), C(7) }, 10, { "Insure" }, 10)
T("blackjack v dealer bj = push", { C("A"), C("A"), C("K"), C("Q") }, 10, { "No thanks" }, 0)
T("surrender", { C(10), C(10), C(6), C(9) }, 10, { "Surrender" }, -5)
T("split aces one card each", { C("A"), C(9), C("A"), C(8), C("K"), C("Q") }, 10, { "Split" }, 20)
T("split 10s, one busts", { C(10), C(10), C("K"), C(8), C(6), C(9), C(10), C(9) }, 10, { "Split", "Stand", "Hit" }, -20)
T("dealer stands soft 17 (default)", { C(10), C("A"), C(8), C(6) }, 10, { "No thanks", "Stand" }, 10)
db.settings.hitSoft17 = true
T("dealer hits soft 17 (option on)", { C(10), C("A"), C(8), C(6), C(2) }, 10, { "No thanks", "Stand" }, -10)
db.settings.hitSoft17 = false
db.settings.surrender = false
T("surrender off: button disabled", { C(10), C(10), C(6), C(9) }, 10, { "Stand" }, -10)
db.settings.surrender = true

-- Random play: thousands of rounds clicking any enabled action.
math.randomseed(42)
db.settings.decks = 2
local rounds, errs = 0, 0
for i = 1, 20000 do
  if ns.db.chips < 5 then ns.db.chips = 0; ns:RebuyChips(1000); ns.games.blackjack:OnShow() end
  SetBet(5 * math.random(1, math.min(20, math.floor(ns.db.chips / 5))))
  local okDeal, e = pcall(Click, "Deal")
  if not okDeal then errs = errs + 1; io.write("deal error: ", tostring(e), "\n") break end
  local guard = 0
  while ns.games.blackjack:ChipsInPlay() do
    guard = guard + 1
    assert(guard < 100, "stuck in a round")
    local choices = {}
    for _, t in ipairs({ "Hit", "Stand", "Double", "Split", "Surrender", "Insure", "No thanks" }) do
      if Enabled(t) then choices[#choices + 1] = t end
    end
    assert(#choices > 0, "no action available mid-round")
    Click(choices[math.random(#choices)])
  end
  assert(ns.db.chips >= 0, "negative chips")
  rounds = rounds + 1
end
io.write(string.format("random play: %d rounds, %d errors, chips %.1f, rebuys %d\n", rounds, errs, ns.db.chips, ns.db.rebuys))

-- Card art switching with a second registered pack
CowCasino.RegisterTextureDeck({ id = "testdeck", name = "Test", path = "Interface\\AddOns\\X" })
ns:SetCardArt("testdeck")
ns:SetCardArt("plain")
io.write("art packs: ", table.concat(ns.cardArtOrder, ", "), "\n")
-- Minimap button
local mb = CowCasinoMinimapButton
assert(mb and mb.shown, "minimap button missing")
local wasShown = CowCasinoFrame.shown
Fire(mb, "OnClick"); assert(CowCasinoFrame.shown ~= wasShown, "click did not toggle")
Fire(mb, "OnClick"); assert(CowCasinoFrame.shown == wasShown, "second click did not toggle back")
Fire(mb, "OnEnter")
Fire(mb, "OnDragStart"); Fire(mb, "OnUpdate"); Fire(mb, "OnDragStop")
io.write(string.format("minimap: toggle ok, dragged to angle %.0f\n", ns.db.minimap.angle))
SlashCmdList.COWCASINO("minimap"); assert(not mb.shown and ns.db.minimap.hide)
SlashCmdList.COWCASINO("minimap"); assert(mb.shown and not ns.db.minimap.hide)
io.write("minimap: /casino minimap hide/show ok\n")
-- ---------------- Mines ----------------
ns:OpenGame("mines")
local mdb = ns.db.mines
betDB = mdb
local tiles = {}
for _, o in ipairs(all) do if o.kind == "Button" and o.w == 46 and o.h == 46 and #tiles < 25 then tiles[#tiles + 1] = o end end
assert(#tiles == 25, "expected 25 tiles, got " .. #tiles)
local function SetMines(n) while mdb.mines < n do Click("+") end while mdb.mines > n do Click("-") end end
local function Safe() for i = 1, 25 do if not mdb.active.board[i] and not mdb.active.revealed[i] then return i end end end
local function Mine() for i = 1, 25 do if mdb.active.board[i] then return i end end end
local function Tile(i) local t = tiles[i]; assert(t.enabled, "tile disabled"); Fire(t, "OnClick"); Flush() end
local function MCase(name, mines, bet, fn, expect)
  ns.db.chips = 1000; SetMines(mines); SetBet(bet)
  local before = ns.db.chips
  Click("Bet ")
  local mineCount = 0; for i = 1, 25 do if mdb.active.board[i] then mineCount = mineCount + 1 end end
  assert(mineCount == mines, "board has " .. mineCount .. " mines")
  fn()
  local net = ns.db.chips - before
  local ok = math.abs(net - expect) < 1e-9 and mdb.active == nil
  io.write(string.format("%-34s net %+7.2f  expected %+7.2f  %s\n", name, net, expect, ok and "PASS" or "FAIL"))
  allOk = allOk and ok
end
MCase("mines: 3 mines, 1 gem, cash out", 3, 100, function() Tile(Safe()); Click("Cash out") end, 13)
MCase("mines: 1 mine, 1 gem, cash out", 1, 100, function() Tile(Safe()); Click("Cash out") end, 3)
MCase("mines: hit a mine", 5, 50, function() Tile(Safe()); Tile(Mine()) end, -50)
MCase("mines: 24 mines, auto cash out", 24, 10, function() Tile(Safe()) end, 238)   -- 247.5 back: half a chip rounds up
MCase("mines: 3 mines, 5 gems", 3, 100, function() for _ = 1, 5 do Tile(Safe()) end Click("Cash out") end,
  math.floor(100 * 0.99 * (25*24*23*22*21)/(22*21*20*19*18) + 0.5) - 100)
-- can't cash out before a pick, controls locked mid-game
ns.db.chips = 1000; SetBet(25); Click("Bet ")
assert(not Enabled("Pick a tile"), "cash out enabled before a pick")
assert(not Enabled("+") and not Enabled("Clear"), "controls not locked")
assert(mdb.active and mdb.active.bet == 25, "active game not saved")
Click("Random tile")
if mdb.active then Click("Cash out") end
io.write("mines: locks, random tile and saved game ok\n")

-- RTP check: 3 mines, take 2 gems then cash out, many games
local staked, returned = 0, 0
SetMines(3)
for g = 1, 40000 do
  ns.db.chips = 1000; SetBet(10)
  Click("Bet ")
  staked = staked + 10
  local before = ns.db.chips
  Click("Random tile")
  if mdb.active then Click("Random tile") end
  if mdb.active then Click("Cash out") end
  returned = returned + (ns.db.chips - before)
end
io.write(string.format("mines RTP over 40000 games: %.3f (target ~0.99)\n", returned / staked))
io.write(string.format("wallet: chips %s, best %s, rebuys %d\n", ns:FormatChips(ns.db.chips), ns:FormatChips(ns.db.bestChips), ns.db.rebuys))
-- ---------------- Slots ----------------
-- Slots is tested on its own: slots_machine_tests, slots_lines_tests and
-- slots_features_tests (wilds, scatters, free spins, Auto, payouts).
-- Theme swapping
CowCasino.RegisterSlotIconTheme({ id = "icons", name = "Icons", icons = {
  seven = "a", bar = "b", bell = "c", plum = "d", orange = "e", lemon = "f", cherry = { "sheet", 0, 0.5, 0, 0.5 } } })
ns:SetSlotTheme("icons"); ns:SetSlotTheme("classic"); ns:SetSlotTheme("azeroth")
assert(not pcall(CowCasino.RegisterSlotIconTheme, { id = "broken", icons = { seven = "a" } }))
io.write("slot themes: ", table.concat(ns.slotThemeOrder, ", "), "; incomplete theme rejected\n")
-- Mines icon options
do
  ns:OpenGame("mines")
  local mdb = ns.db.mines
  local mtiles = {}
  for _, o in ipairs(all) do if o.kind == "Button" and o.w == 46 and o.h == 46 and #mtiles < 25 then mtiles[#mtiles + 1] = o end end
  ns.db.chips = 1000
  Click("Bet ")
  local safe; for i = 1, 25 do if not mdb.active.board[i] then safe = i; break end end
  Fire(mtiles[safe], "OnClick")
  assert(string.find(mtiles[safe].icon.tex, "Diamond_01"), "default gem not shown: " .. tostring(mtiles[safe].icon.tex))
  Click("Options")
  Click(">")            -- first picker is the gem
  Click(">")
  assert(mdb.icons.gem == "Huge Emerald", "gem pick is " .. tostring(mdb.icons.gem))
  assert(string.find(mtiles[safe].icon.tex, "Emerald_01"), "board did not update mid-game")
  Click("<"); Click("<"); Click("<")   -- wraps around to the last gem
  assert(mdb.icons.gem == "Gold Coin", "wrap failed: " .. tostring(mdb.icons.gem))
  -- mine picker: find the second ">" in the visible options panel
  local mineNext
  local n = 0
  for _, o in ipairs(all) do if o.kind == "Button" and o.text == ">" and visible(o) then n = n + 1; if n == 2 then mineNext = o end end end
  Fire(mineNext, "OnClick"); Fire(mineNext, "OnClick")
  assert(mdb.icons.mine == "Mithril Frag Bomb", "mine pick is " .. tostring(mdb.icons.mine))
  Click("Done")
  local mine; for i = 1, 25 do if mdb.active.board[i] then mine = i; break end end
  Fire(mtiles[mine], "OnClick")
  assert(string.find(mtiles[mine].icon.tex, "Bomb_02"), "chosen mine icon not shown")
  -- unknown saved name falls back to the first icon; addons can add icons
  mdb.icons.gem = "Not An Icon"
  CowCasino.AddMinesIcon("gem", "Test Gem", "Interface\\Icons\\Test")
  Click("Options"); for _ = 1, 9 do Click(">") end
  assert(mdb.icons.gem == "Test Gem", "added icon not reachable: " .. tostring(mdb.icons.gem))
  Click("Done")
  io.write("mines icons: pickers cycle and wrap, saved by name, board updates mid-game, addon icons appear\n")
end
io.write(allOk and "ALL SCENARIOS PASS\n" or "SOME SCENARIOS FAILED\n")
do
  ns.db.slotTheme = nil
  assert(ns:GetSlotTheme().id == "azeroth", "default theme is " .. ns:GetSlotTheme().id)
  local SL = ns.games.slots
  local _, _, n, c = SL.EvaluateLine({ "seven", "seven", "seven", "seven", "seven" })
  assert(ns:SlotSymbolName("seven", true) == "Diamonds" and ns:SlotSymbolName("cherry", true) == "Apples")
  for _, o in ipairs(all) do
    if o.kind == "Texture" and type(o.tex) == "string" then
      assert(not string.find(o.tex, "Food_10[45]") and not string.find(o.tex, "FelIron") and not string.find(o.tex, "MindBomb"), "post-1.12 icon in use: " .. o.tex)
    end
  end
  io.write("1.12: Azeroth default with vanilla fruit (Diamonds ... Apples); no post-1.12 icons on any texture\n")
end

do
  local run = dofile("poker_tests.lua")
  run({ ns = ns, all = all, Flush = Flush,
        Press = function(b) assert(b, "no such button"); assert(b.enabled, "button disabled: " .. b.text); Fire(b, "OnClick", "LeftButton"); Flush() end,
        FireOnly = function(b) Fire(b, "OnClick", "LeftButton") end,
        SetStacked = function(c) stacked = c end })
end
