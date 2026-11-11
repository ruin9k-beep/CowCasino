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
Check("...with its name, picture and idle line", ui.name.text == "Dealer" and ui.image.shown and not ui.portrait.shown
  and string.find(ui.image.tex, "DealerPortrait", 1, true) ~= nil and ui.text.text == "Place your bet and I'll deal.")

-- a round: the dealer calls the result, then goes back to the idle line
ns.db.chips = 1000
local called
for _ = 1, 20 do
  if Find("Deal 25") or Find("Deal") then
    local deal = Find("Deal 25") or Find("Deal")
    if deal.enabled then env.Fire(deal, "OnClick", "LeftButton") end
  end
  if Find("No thanks") then Press("No thanks") end
  for _ = 1, 6 do if Find("Stand") and Find("Stand").enabled then Press("Stand") end end
  Tick(3)
  local t = ui.text.text or ""
  if string.find(t, "stands on", 1, true) or string.find(t, "bust", 1, true) or string.find(t, "blackjack", 1, true) then called = t break end
end
Check("the dealer calls the result of the round", called ~= nil, called)
Tick(7)
Check("...then goes back to the idle line", ui.text.text == "Place your bet and I'll deal.", ui.text.text)

-- the API, from the game on screen
D:Say(BJ, "Hello there.")
Check("Say shows a message", ui.text.text == "Hello there.")
D:Say(ns.games.mines, "Not my table.")
Check("a game that isn't on screen can't make it talk", ui.text.text == "Hello there.")
D:Say(BJ, "Back in a moment.", 2)
Tick(2.5)
Check("a timed message goes back to the idle line", ui.text.text == "Place your bet and I'll deal.")
D:SetIdle(BJ, "Bets, please.")
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
Check("Say can bring a sound along", Heard("LEVELUPSOUND") and ui.text.text == "Winner!")

-- other games: no dealer; coming back resets it
ns:OpenGame("mines")
Check("Mines has no dealer: the strip hides", not D:IsShown())
D:Say(BJ, "Psst.")
Check("...and Blackjack, off screen, can't bring it back", not D:IsShown())
ns:OpenGame("blackjack")
Check("back at Blackjack it starts fresh", D:IsShown() and ui.name.text == "Dealer" and ui.image.shown
  and ui.text.text == "Place your bet and I'll deal.")
ns:ShowMenu()
Check("the menu hides it again", not D:IsShown())
env.CowCasinoFrame:Hide()
ns:OpenGame("blackjack")
Check("closing the window takes it along", not Visible(ui))

io.write(ok and "DEALER PASS\n" or "DEALER FAIL\n")
os.exit(ok and 0 or 1)
