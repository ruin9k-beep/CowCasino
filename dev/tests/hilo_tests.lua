-- Hi-Lo: fair odds less 1% on every guess, stacking multipliers, cash out,
-- bust, skip, and a game that survives a reload.
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
local function Press(text, prefix) local b = assert(Find(text, prefix), "no " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end

ns.db.chips = 1000
ns:OpenGame("hilo")
local H = ns.games.hilo
local db = ns.db.hilo
local ui = H.ui

---------------------------------------------------------------------------
-- The odds, worked out here separately
---------------------------------------------------------------------------
local bad = {}
for rank = 1, 13 do
  local hi, lo = H.Choices(rank)
  for _, c in ipairs({ hi, lo }) do
    local wins = 0
    for r = 1, 13 do if c.wins(r) then wins = wins + 1 end end
    local chance = wins / 13
    if math.abs(chance - c.chance) > 1e-12 then table.insert(bad, rank .. " " .. c.label .. " chance") end
    -- the expected return of a guess: chance x multiplier = 0.99, whatever the card
    if math.abs(chance * H.StepMult(c.chance) - 0.99) > 1e-12 then table.insert(bad, rank .. " " .. c.label .. " return") end
    if wins == 0 or wins == 13 then table.insert(bad, rank .. " " .. c.label .. " can't lose or can't win") end
  end
end
Check("every guess on every card returns exactly 99% (1% house edge)", table.getn(bad) == 0, table.concat(bad, "; "))
local h7, l7 = H.Choices(7)
Check("a 7: higher-or-same and lower-or-same are both 7 in 13", h7.label == "Higher or same" and h7.chance == 7 / 13 and l7.chance == 7 / 13)
local hA, lA = H.Choices(1)
local hK, lK = H.Choices(13)
Check("an ace: Higher (12 in 13) or the same ace (1 in 13)", hA.label == "Higher" and hA.chance == 12 / 13 and lA.chance == 1 / 13)
Check("a king: Lower (12 in 13) or the same king (1 in 13)", lK.label == "Lower" and lK.chance == 12 / 13 and hK.chance == 1 / 13)

---------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------
local DECK = {}
H.SetDraw(function() return table.remove(DECK, 1) end)
local function C(rank, suit) return { rank = rank, suit = suit or 1 } end

Check("guesses are off until a bet", not ui.hi.enabled and not ui.lo.enabled)
db.bet = 0
Press("100")
table.insert(DECK, C(7))
Press("Bet 100")
Check("a bet deals a card", db.active and db.active.card.rank == 7 and ns.db.chips == 900 and ui.big.card.rank == 7 and ui.big.faceUp)
Check("...the buttons show what each guess pays", ui.hi.mult.text == "1.84x" and ui.lo.mult.text == "1.84x" and ui.hi.chance.text == "54% chance",
  ui.hi.mult.text .. " " .. ui.hi.chance.text)
Check("no cashing out before a right guess", Find("Guess first") ~= nil and not Find("Guess first").enabled)
table.insert(DECK, C(10, 2))
env.Fire(ui.hi, "OnClick", "LeftButton")
local m1 = 0.99 * 13 / 7
Check("right: 10 is higher than 7, and the multiplier is 0.99 x 13/7", db.active and math.abs(db.active.mult - m1) < 1e-9 and db.active.card.rank == 10)
table.insert(DECK, C(3))
env.Fire(ui.lo, "OnClick", "LeftButton")
local m2 = m1 * 0.99 * 13 / 10
Check("right again: multipliers stack", db.active and math.abs(db.active.mult - m2) < 1e-9)
local pay = math.floor(100 * m2 + 0.5)
Check("Cash out shows the whole-chip payout", Find("Cash out " .. ns:FormatChips(pay)) ~= nil, pay)
Press("Cash out", true)
Check("cashing out pays it", db.active == nil and ns.db.chips == 900 + pay and db.stats.cashouts == 1, ns.db.chips)
Check("the trail shows the cards", ui.trail[1].card.card.rank == 7 and ui.trail[2].card.card.rank == 10 and ui.trail[3].card.card.rank == 3
  and string.find(ui.trail[3].text.text, "x", 1, true) ~= nil)

-- skip, then a wrong guess
local before = ns.db.chips
table.insert(DECK, C(13))
Press("Bet 100")
Check("a king: Lower or the same king", ui.lo.label.text == "Lower" and ui.hi.label.text == "Same (king)")
table.insert(DECK, C(5))
Press("Skip card")
Check("skip swaps the card and keeps the multiplier", db.active.card.rank == 5 and db.active.mult == 1 and ns.db.chips == before - 100)
table.insert(DECK, C(4))
env.Fire(ui.hi, "OnClick", "LeftButton")
Check("wrong: 4 isn't higher or the same as 5, the bet is lost", db.active == nil and ns.db.chips == before - 100 and db.stats.busts == 1)
Check("...the card shows, marked", ui.big.card.rank == 4 and ui.bust.shown and string.find(ui.status.text, "wrong", 1, true) ~= nil)
Check("stats: net matches the chips", db.stats.net == ns.db.chips - 1000, db.stats.net)
Check("the stats line shows it", string.find(ui.stats.text, "Net", 1, true) ~= nil and string.find(ui.stats.text, "Games 2", 1, true) ~= nil, ui.stats.text)
Check("the last games line: the bust first, then the cash-out", ui.history.text == "|cffff7070-100|r  |cff40ff40+"
  .. ns:FormatChips(pay - 100) .. "|r", ui.history.text)

-- an unfinished game survives a reload
table.insert(DECK, C(2))
Press("Bet 100")
table.insert(DECK, C(9))
env.Fire(ui.hi, "OnClick", "LeftButton")
local chipsNow, multNow = ns.db.chips, db.active.mult
Check("chips in play during a game", ns:ChipsInPlay())
local env2, ns2 = Start(ns.db)
ns2:OpenGame("hilo")
local d2 = ns2.db.hilo
Check("after a reload the game is still going", d2.active and d2.active.card.rank == 9 and d2.active.mult == multNow and ns2.db.chips == chipsNow)
local b2
for _, o in ipairs(env2.all) do if o.kind == "Button" and o.text and string.find(o.text, "^Cash out") then b2 = o end end
env2.Fire(b2, "OnClick", "LeftButton")
Check("...and cashes out", d2.active == nil and ns2.db.chips == chipsNow + math.floor(100 * multNow + 0.5))

-- the long run: one guess then cash out, over many games, comes back near 99%
H.SetDraw(function() return { rank = math.random(1, 13), suit = math.random(1, 4) } end)
math.randomseed(4242)
db.active = nil            -- that game was finished in the reloaded copy
ns.db.chips = 10000000
db.bet = 100
H:OnShow()
local staked, back = 0, 0
for i = 1, 60000 do
  local c0 = ns.db.chips
  Press("Bet 100")
  if math.mod(i, 2) == 0 then env.Fire(ui.hi, "OnClick", "LeftButton") else env.Fire(ui.lo, "OnClick", "LeftButton") end
  if db.active then Press("Cash out", true) end
  staked = staked + 100
  back = back + (ns.db.chips - c0 + 100)
end
Check("60,000 one-guess games return about 99%", math.abs(back / staked - 0.99) < 0.01, string.format("%.2f%%", back / staked * 100))

ns:RebuyChips(1000)
Check("a fresh stack starts the Hi-Lo stats over", db.stats.games == 0 and db.stats.net == 0)
Check("...and clears the last games line", table.getn(ns.games.hilo.recent) == 0)

io.write(ok and "HILO PASS\n" or "HILO FAIL\n")
os.exit(ok and 0 or 1)
