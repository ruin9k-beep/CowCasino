-- Blackjack and Party Blackjack as one game.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-62s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
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
local played = {}
local real = env.PlaySound
env.PlaySound = function(n) table.insert(played, env.SoundName(n)); real(n) end
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Find(text) for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == text and Visible(o) then return o end end end
local function Press(text) local b = assert(Find(text), "no " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end
local function Tick(sec) for _ = 1, math.floor(sec * 10 + 0.5) do env.CLOCK = env.CLOCK + 0.1; for _, o in ipairs(env.all) do if o.shown and o.scripts.OnUpdate and not o.parent then env.Fire(o, "OnUpdate", 0.1) end end end end

local names = {}
for _, id in ipairs(ns:MenuOrder()) do table.insert(names, ns.games[id].name) end
local list = table.concat(names, ", ")
Check("one Blackjack in the menu, no separate Party Blackjack", not string.find(list, "Party Blackjack", 1, true)
  and string.find(list, "Blackjack", 1, true) ~= nil, list)
ns.db.order = { "partybj", "roulette" }
Check("an old saved order naming Party Blackjack still works", ns:MenuOrder()[1] == "roulette")
ns.db.order = nil

ns:OpenGame("blackjack")
local party = ns.PartyBlackjack
Check("Blackjack opens at your solo table", Find("Deal 25") ~= nil and not party.panel:IsShown())
Check("Party play button, enabled between rounds", Find("Party play") ~= nil and Find("Party play").enabled)
-- deal until a round is actually in progress (a dealt blackjack ends it at once)
local inRound = false
for _ = 1, 20 do
  Press("Deal 25")
  inRound = (Find("Stand") ~= nil and Find("Stand").enabled ~= nil) or Find("No thanks") ~= nil
  if inRound then break end
end
Check("...and disabled during a round", inRound and not Find("Party play").enabled)
for _ = 1, 20 do
  if Find("No thanks") then Press("No thanks") elseif Find("Stand") and Find("Stand").enabled then Press("Stand") end
  Tick(1)
  if Find("Deal 25") and Find("Deal 25").enabled then break end
end
Press("Party play")
Check("Party play shows the party lobby in the Blackjack window", party.panel:IsVisible() and Find("Host a table") ~= nil
  and ns.currentGame == "blackjack")
local soloShown = false
for _, o in ipairs(env.all) do
  if (o.kind == "Button" and (o.text == "Deal 25" or o.text == "Hit" or o.text == "Party play")) or o.kind == "PlayerModel" then
    if Visible(o) and o.parent ~= party.panel then soloShown = soloShown or o.text or o.kind end
  end
end
Check("the solo table is hidden while party play is up", not soloShown, soloShown)
Press("Options")
local opts = Find("Sounds")
Check("Blackjack's Options open over the party screen", opts ~= nil)
Press("Done")
Press("< Solo table")
local bjPortrait
for _, o in ipairs(env.all) do if o.kind == "PlayerModel" and o.unit == "player" and Visible(o) then bjPortrait = o end end
Check("< Solo table goes back to your solo table", not party.panel:IsShown() and Find("Deal 25") ~= nil
  and Find("Party play") ~= nil and bjPortrait ~= nil)

-- Host, leave the window, come back: straight to the party table.
Press("Party play")
ns.db.blackjack.sounds.newHand = "raidWarn"
Press("Host a table")
Check("hosting from inside Blackjack", party.T.mode == "host")
local mark = table.getn(played)
Press("Place bet")
Tick(1)
local heard = false
for k = mark + 1, table.getn(played) do if played[k] == "RaidWarning" then heard = true end end
Check("party play uses Blackjack's sound settings", heard)
ns:ShowMenu()
ns:OpenGame("blackjack")
Check("reopening Blackjack goes straight to your party table", party.panel:IsVisible() and party.ui.table:IsVisible())
for _ = 1, 30 do
  if Find("No thanks") then Press("No thanks") elseif Find("Stand") and Find("Stand").enabled then Press("Stand") end
  Tick(1)
  if party.T.phase == "settled" or party.T.phase == "betting" then break end
end
local leave = Find("Close table") or Find("Close after round")
Press(leave.text)
Tick(10)
Check("closing the table goes back to the party lobby", party.T.mode == "lobby" and Find("< Solo table") ~= nil)

-- A reload while seated still pays back, now when Blackjack opens.
local env2, ns2 = Start(nil, function(n)
  n.db.chips = 1000
  n.db.partybj = { seat = { host = "Nobody", tid = "1", stack = 300 } }
end)
ns2:OpenGame("blackjack")
Check("reload while seated: chips come back when Blackjack opens", ns2.db.chips == 1300 and ns2.db.partybj.seat == nil, ns2.db.chips)

io.write(ok and "MERGE PASS\n" or "MERGE FAIL\n")
os.exit(ok and 0 or 1)
