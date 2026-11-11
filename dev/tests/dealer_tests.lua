-- The Dealer strip: shown for games that have one, controlled only by the
-- game on screen, with messages, pictures, player portraits and sounds.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-66s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end
local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
env.arg = { ADDON }; env.SELECT_SAVED = select
assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
env.CowCasinoFrame:Show()
local ns = env.CowCasino.ns
local D = ns.Dealer
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Find(text) for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == text and Visible(o) then return o end end end
local function Press(text) local b = assert(Find(text), "no " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end
local function Tick(sec) for _ = 1, math.floor(sec * 10 + 0.5) do env.CLOCK = env.CLOCK + 0.1; for _, o in ipairs(env.all) do if o.scripts.OnUpdate and Visible(o) then env.Fire(o, "OnUpdate", 0.1) end end end end
-- tick for sec seconds, calling fn with the dealer's text at every step
local function Watch(sec, fn) for _ = 1, math.floor(sec * 10 + 0.5) do Tick(0.1); fn(D.UI().text.text or "") end end
local heard = {}
local realPlay = env.PlaySound
env.PlaySound = function(n) table.insert(heard, env.SoundName(n)); realPlay(n) end
local function Heard(name) for _, h in ipairs(heard) do if h == name then return true end end return false end

ns:ShowMenu()
Check("no dealer on the menu", not D:IsShown())
ns:OpenGame("blackjack")
local BJ = ns.games.blackjack
local ui = D.UI()
Check("Blackjack has a dealer on top of the window", D:IsShown() and Visible(ui))
-- (the mock keeps the last point set: the right-hand edge)
Check("...anchored to the window's top edge, clear of the horns", ui.anchor and ui.anchor[1] == "BOTTOMRIGHT" and ui.anchor[2] == env.CowCasinoFrame
  and ui.anchor[3] == "TOPRIGHT" and ui.anchor[4] <= -30, ui.anchor and (tostring(ui.anchor[1]) .. " " .. tostring(ui.anchor[4])))
Check("...the goblin by default: its name, picture and idle line", ui.name.text == "Fizzlecog" and ui.image.shown
  and not ui.portrait.shown and string.find(ui.image.tex, "DealerGoblin", 1, true) ~= nil
  and ui.text.text == "Place your bet and I'll deal.", tostring(ui.name.text) .. " " .. tostring(ui.image.tex))

-- a round: the dealer calls the result, then goes back to the idle line
-- (the human dealer has no lines of his own: the plain calls)
ns:SetDealer("human")
ns.db.chips = 1000
local called
for _ = 1, 20 do
  if Find("Deal 25") or Find("Deal") then
    local deal = Find("Deal 25") or Find("Deal")
    if deal.enabled then env.Fire(deal, "OnClick", "LeftButton") end
  end
  if Find("No thanks") then Press("No thanks") end
  for _ = 1, 6 do if Find("Stand") and Find("Stand").enabled then Press("Stand") end end
  Watch(8, function(t)
    if not called and (string.find(t, "stands on", 1, true) or string.find(t, "bust", 1, true) or string.find(t, "blackjack", 1, true)) then called = t end
  end)
  if called then break end
end
Check("the dealer calls the result of the round", called ~= nil, called)
Tick(12)
Check("...then goes back to the idle line", ui.text.text == "Place your bet and I'll deal.", ui.text.text)

-- Fizzlecog has his own lines for Blackjack
ns:SetDealer("goblin")
local G = ns.dealers.goblin.lines
local function Pattern(line)   -- a line with its {names} filled by anything
  local p = string.gsub(line, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  return "^" .. string.gsub(p, "{%w+}", ".-") .. "$"
end
local function FromEvents(text, events)
  for _, e in ipairs(events) do for _, l in ipairs(G[e]) do if string.find(text, Pattern(l)) then return e end end end
end
local SETTLE = { "playerBlackjack", "dealerBlackjack", "dealerBust", "win", "lose", "push", "playerBust", "surrender" }
for _, e in ipairs({ "deal", "insurance", "evenMoney", "hitHighSafe", "twentyOne", "playerBust", "standLow", "double", "split",
                     "dealerTurn", "playerBlackjack", "dealerBlackjack", "dealerBust", "win", "lose", "push", "surrender", "broke" }) do
  Check("Fizzlecog has lines for " .. e, type(G[e]) == "table" and G[e][1] ~= nil)
end
local line = D:Line("deal", { player = 14, up = "an Ace" })
Check("a line fills in its {names}", line and not string.find(line, "{", 1, true) and FromEvents(line, { "deal" }) == "deal", line)
local seen, repeats, prev = {}, 0, nil
for _ = 1, 30 do local l = D:Line("win", { total = 18, win = "25" }); seen[l] = true; if l == prev then repeats = repeats + 1 end; prev = l end
local kinds = 0; for _ in pairs(seen) do kinds = kinds + 1 end
Check("...picked at random, never the same one twice in a row", kinds > 1 and repeats == 0, kinds .. " kinds, " .. repeats .. " repeats")
D:React(BJ, "push", nil, 5, "We push.")
Tick(0.5)
Check("React says the dealer's line", FromEvents(ui.text.text, { "push" }) == "push", ui.text.text)
D:React(BJ, "dealerTurn", nil, nil, "My turn.", true)
Check("...a quiet one doesn't talk over it", D.Pending() == 0 and FromEvents(ui.text.text, { "push" }) == "push", ui.text.text)
Tick(3)
D:React(BJ, "dealerTurn", nil, nil, "My turn.", true)
Tick(0.5)
Check("...but speaks up once it's had its time", FromEvents(ui.text.text, { "dealerTurn" }) == "dealerTurn", ui.text.text)
Tick(3)
D:React(BJ, "noSuchMoment", nil, nil, "Plain words.")
Tick(0.5)
Check("a moment without a line gets the plain words", ui.text.text == "Plain words.")
ns:SetDealer("human")
Tick(3)
D:React(BJ, "push", nil, 5, "We push.")
Tick(0.5)
Check("a dealer without lines gets the plain words", ui.text.text == "We push.")
ns:SetDealer("goblin")
Tick(8)

-- a few rounds with Fizzlecog: he talks through the deal and calls the result in his own words
local dealt, settled, other = nil, nil, nil
for _ = 1, 12 do
  local deal = Find("Deal 25") or Find("Deal")
  if deal and deal.enabled then env.Fire(deal, "OnClick", "LeftButton") end
  if Find("No thanks") then Press("No thanks") end
  for _ = 1, 6 do if Find("Hit") and Find("Hit").enabled then Press("Hit") end end
  Watch(20, function(t)
    if FromEvents(t, { "deal" }) then dealt = dealt or t end
    if FromEvents(t, SETTLE) then settled = settled or t end
  end)
  if dealt and settled then break end
end
Check("Fizzlecog talks when he deals", dealt ~= nil, dealt)
Check("...and calls results in his own words", settled ~= nil and not string.find(settled, "{", 1, true), settled)

-- the API, from the game on screen
Check("(quiet before the API checks)", ui.text.text == "Place your bet and I'll deal." and D.Pending() == 0, ui.text.text)
D:Say(BJ, "Hello there.")
Tick(0.1)
Check("changing the text fades it out first", ui.text.text == "Place your bet and I'll deal." and ui.text.alpha and ui.text.alpha < 1,
  tostring(ui.text.alpha))
Tick(0.2)
Check("...then the message fades in", ui.text.text == "Hello there." and ui.text.alpha < 1, tostring(ui.text.alpha))
Tick(0.2)
Check("...all the way", ui.text.text == "Hello there." and ui.text.alpha == 1, tostring(ui.text.alpha))
D:Say(ns.games.mines, "Not my table.")
Check("a game that isn't on screen can't make it talk", D.Pending() == 0)
-- the queue: one at a time, 3 seconds each at least, in order
D:Say(BJ, "One.")
D:Say(BJ, "Two.", 4)
Check("messages wait their turn", D.Pending() == 2 and ui.text.text == "Hello there.")
local shown = {}
Watch(12, function(t) if shown[table.getn(shown)] ~= t then table.insert(shown, t) end end)
Check("...and show one at a time, in order", shown[1] == "Hello there." and shown[2] == "One." and shown[3] == "Two."
  and shown[4] == "Place your bet and I'll deal.", table.concat(shown, " | "))
D:Say(BJ, "First.", 1)
D:Say(BJ, "Second.", 1)
local firstAt, secondAt
Watch(6, function(t)
  if t == "First." and not firstAt then firstAt = env.CLOCK end
  if t == "Second." and not secondAt then secondAt = env.CLOCK end
end)
Check("each stays up at least 3 seconds", firstAt and secondAt and secondAt - firstAt >= 3, firstAt and secondAt and (secondAt - firstAt))
Tick(4)
Check("a timed message goes back to the idle line (after 3 seconds at least)", ui.text.text == "Place your bet and I'll deal.", ui.text.text)
for i = 1, 8 do D:Say(BJ, "Spam " .. i) end
Check("the queue keeps only the latest few", D.Pending() <= 4, D.Pending())
D:Idle(BJ)
Tick(0.5)
Check("Idle drops what's waiting and goes back to the idle line", D.Pending() == 0 and ui.text.text == "Place your bet and I'll deal.", ui.text.text)
D:SetIdle(BJ, "Bets, please.")
Tick(0.5)
Check("the idle line can change", ui.text.text == "Bets, please.")
D:SetName(BJ, "Bob - big blind")
Check("the name can change", ui.name.text == "Bob - big blind")
D:SetPlayer(BJ, "player")
Check("a player's 3D portrait replaces the picture", ui.portrait.shown and ui.portrait.unit == "player" and not ui.image.shown)
Tick(2)
Check("...framed on the face", ui.portrait.camera == 0 or ui.portrait.zoom == 1)
D:SetPlayer(BJ, "Nobody")
Check("someone not in your group gets the picture instead", ui.image.shown and not ui.portrait.shown)
D:SetImage(BJ, { "Interface\\Icons\\INV_Misc_Coin_01", 0.1, 0.9, 0.1, 0.9 })
Check("any picture, cropped", ui.image.tex == "Interface\\Icons\\INV_Misc_Coin_01" and ui.image.coords[1] == 0.1)
heard = {}
D:Sound(BJ, "win", ns.db.blackjack)
Check("a game sound event plays (from its Sounds menu)", Heard("LOOTWINDOWCOINSOUND"), table.concat(heard, ","))
heard = {}
D:Sound(BJ, "RAID_WARNING")
Check("any sound by name plays", Heard("RaidWarning"), table.concat(heard, ","))
heard = {}
D:Sound(ns.games.mines, "RAID_WARNING")
Check("a game that isn't on screen can't play dealer sounds", not Heard("RaidWarning"))
heard = {}
D:Say(BJ, "Winner!", nil, "UI_EPICLOOT_TOAST")
Check("a message's sound waits for the message", not Heard("LEVELUPSOUND"))
Tick(0.5)
Check("...and plays when it shows", Heard("LEVELUPSOUND") and ui.text.text == "Winner!")

-- other games: no dealer; coming back resets it
ns:OpenGame("mines")
Check("Mines has no dealer: the strip hides", not D:IsShown())
D:Say(BJ, "Psst.")
Check("...and Blackjack, off screen, can't bring it back", not D:IsShown())
ns:OpenGame("blackjack")
Check("back at Blackjack it starts fresh", D:IsShown() and ui.name.text == "Fizzlecog" and ui.image.shown
  and ui.text.text == "Place your bet and I'll deal.")

-- dealer packs: the built-in two, one from another addon, the picker in Options
Check("CowCasino has a goblin and a human dealer", ns.dealers.goblin ~= nil and ns.dealers.human ~= nil
  and ns.dealerOrder[1] == "goblin" and ns:GetDealer().id == "goblin")
env.CowCasino.RegisterDealer({ id = "tester", name = "Test Orc", author = "someone", title = "Grukk",
  image = { "Interface\\Icons\\INV_Misc_Head_Orc_01", 0.08, 0.92, 0.08, 0.92 } })
Check("another addon can add a dealer", ns.dealers.tester ~= nil and ns.dealerOrder[3] == "tester")
local okErr = pcall(env.CowCasino.RegisterDealer, { id = "broken" })
Check("...a dealer without a picture is refused", not okErr and ns.dealers.broken == nil)
ns:SetDealer("tester")
Check("picking a dealer saves it", ns.db.dealer == "tester" and ns:GetDealer().id == "tester")
Check("...and the strip shows it at once (picture, crop and name)", ui.image.tex == "Interface\\Icons\\INV_Misc_Head_Orc_01"
  and ui.image.coords[1] == 0.08 and ui.name.text == "Grukk", tostring(ui.image.tex) .. " " .. tostring(ui.name.text))
D:SetPlayer(BJ, "player")
ns:SetDealer("human")
Check("...but not over a player's portrait", ui.portrait.shown and not ui.image.shown)
D:SetPlayer(BJ, "Nobody")
Check("...which falls back to the chosen dealer", ui.image.shown and string.find(ui.image.tex, "DealerHuman", 1, true) ~= nil)
D:SetName(BJ, "Bob - big blind")
ns:SetDealer("goblin")
Check("a name the game set stays when the dealer changes", ui.name.text == "Bob - big blind")
ns:SetDealer("nobody-here")
Check("an unknown dealer id is ignored", ns.db.dealer == "goblin")
ns.db.dealer = "uninstalled"
Check("a saved dealer whose addon is gone falls back to the goblin", ns:GetDealer().id == "goblin")
ns.db.dealer = "goblin"

-- the Options picker
ns:ShowMenu()
Check("the menu hides it again", not D:IsShown())
local opts = ns.optionsPage or ns:BuildOptionsPage(env.CowCasinoFrame)
opts:Show()
local function DealerNameText() for _, o in ipairs(env.all) do if o.text == "Goblin" or o.text == "Human" or o.text == "Test Orc" then
  if Visible(o) and o.kind ~= "Button" then return o.text end end end end
Check("Options shows the chosen dealer", DealerNameText() == "Goblin" and string.find(opts.dealerPic.tex, "DealerGoblin", 1, true) ~= nil)
-- the dealer row's ">" is the second ">" from the top (card art first)
local nexts = {}
for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == ">" and Visible(o) and o.parent == opts then table.insert(nexts, o) end end
local dealerNext = nexts[2]
env.Fire(dealerNext, "OnClick", "LeftButton")
Check("its > button picks the next dealer", ns.db.dealer == "human" and DealerNameText() == "Human"
  and string.find(opts.dealerPic.tex, "DealerHuman", 1, true) ~= nil, ns.db.dealer)
env.Fire(dealerNext, "OnClick", "LeftButton")
env.Fire(dealerNext, "OnClick", "LeftButton")
Check("...and wraps around", ns.db.dealer == "goblin", ns.db.dealer)
opts:Hide()
env.CowCasinoFrame:Hide()
ns:OpenGame("blackjack")
Check("closing the window takes it along", not Visible(ui))

io.write(ok and "DEALER PASS\n" or "DEALER FAIL\n")
os.exit(ok and 0 or 1)
