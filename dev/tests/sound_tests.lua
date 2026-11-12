-- Game sound effects: solo Blackjack, solo Hold'em, and the Options screens.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-62s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end
local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
env.arg = { ADDON }; env.SELECT_SAVED = select
assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
local played = {}
local realPlay = env.PlaySound
env.PlaySound = function(n) table.insert(played, env.SoundName(n)); realPlay(n) end
for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
local ns = env.CowCasino.ns
env.CowCasinoFrame:Show()
ns.db.chips = 100000
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Find(text, prefix)
  for _, o in ipairs(env.all) do
    if o.kind == "Button" and Visible(o) and (o.text == text or (prefix and string.sub(o.text, 1, string.len(text)) == text)) then return o end
  end
end
local function Press(text, prefix) local b = assert(Find(text, prefix), "no " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end
local function Enabled(text, prefix) local b = Find(text, prefix); return b ~= nil and b.enabled ~= nil end
local function Tick(sec)
  for _ = 1, math.floor(sec * 10 + 0.5) do
    env.CLOCK = env.CLOCK + 0.1
    for _, o in ipairs(env.all) do if o.shown and o.scripts.OnUpdate and not o.parent then env.Fire(o, "OnUpdate", 0.1) end end
  end
end
local function Count(name, from) local n = 0; for k = from or 1, table.getn(played) do if played[k] == name then n = n + 1 end end; return n end
local COINS, DROP, PAGE, FANFARE = "LOOTWINDOWCOINSOUND", "igQuestCancel", "igQuestListOpen", "LEVELUPSOUND"

---------------------------------------------------------------------------
-- Blackjack
---------------------------------------------------------------------------
ns:OpenGame("blackjack")
local bdb = ns.db.blackjack
local bjPortrait = ns.games.blackjack and nil
for _, o in ipairs(env.all) do if o.kind == "PlayerModel" and Visible(o) then bjPortrait = o end end
Check("blackjack: your 3D portrait shows", bjPortrait ~= nil and bjPortrait.unit == "player" and (bjPortrait.camera == 0 or bjPortrait.zoom == 1))
Check("blackjack: default sounds", bdb.sounds.win == "coins" and bdb.sounds.lose == "questDrop" and bdb.sounds.newHand == "pageTurn")
math.randomseed(5)
local rounds, okRounds = 0, 0
local status
for _, o in ipairs(env.all) do if o.kind == "FontString" and rawget(o, "file") == nil then end end
for r = 1, 60 do
  local from = table.getn(played) + 1
  local chips0 = ns.db.chips
  Press("Deal", true)
  local dealt = played[from] == PAGE or Count(PAGE, from) == 1
  for _ = 1, 30 do
    if Find("No thanks") then Press("No thanks")
    elseif Find("Stand") and Enabled("Stand") then
      if math.random() < 0.4 and Enabled("Hit") then Press("Hit") else Press("Stand") end
    end
    Tick(1)
    if Enabled("Deal", true) then break end
  end
  local net = ns.db.chips - chips0
  local wins, loses = Count(COINS, from), Count(DROP, from)
  local right = dealt and ((net > 0 and wins == 1 and loses == 0) or (net < 0 and loses == 1 and wins == 0) or (net == 0 and wins == 0 and loses == 0))
  rounds = rounds + 1
  if right then okRounds = okRounds + 1 elseif not BJBAD then BJBAD = "round " .. r .. " net " .. net .. " sounds " .. table.concat(played, ",", from) end
end
Check("blackjack: new hand / win / lose sounds every round", okRounds == rounds, okRounds .. "/" .. rounds .. " " .. tostring(BJBAD))

-- Options > Sounds
Press("Options")
Press("Sounds")
local function RowValues()
  local vals = {}
  for _, o in ipairs(env.all) do
    if o.kind == "FontString" and Visible(o) and (o.text == "Coins" or o.text == "Quest abandoned" or o.text == "Page turn"
      or o.text == "Level-up fanfare" or o.text == "None" or o.text == "Quest complete") then table.insert(vals, o.text) end
  end
  return table.concat(vals, ",")
end
Check("options: Sounds screen lists the three choices", RowValues() == "Coins,Quest abandoned,Page turn", RowValues())
local overlay = Find("Defaults").parent
local from = table.getn(played) + 1
local nexts = {}
for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == ">" and o.parent == overlay then table.insert(nexts, o) end end
env.Fire(nexts[1], "OnClick", "LeftButton")      -- win: Coins -> Level-up fanfare
Check("options: > picks the next sound and plays it", bdb.sounds.win == "fanfare" and played[from] == FANFARE, tostring(played[from]))
from = table.getn(played) + 1
local plays = {}
for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == "Play" and o.parent == overlay then table.insert(plays, o) end end
env.Fire(plays[3], "OnClick", "LeftButton")
Check("options: Play previews the sound", played[from] == PAGE)
local prevs = {}
for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == "<" and o.parent == overlay then table.insert(prevs, o) end end
-- lose: back to None (Quest abandoned is 5th; None is 1st)
for _ = 1, 4 do env.Fire(prevs[2], "OnClick", "LeftButton") end
Check("options: a sound can be turned off", bdb.sounds.lose == "none" and not (plays[2].enabled), bdb.sounds.lose)
Press("Done")
Press("Done")
-- a losing round is now silent, and a win plays the fanfare
local silentOk, fanfareOk = true, true
for r = 1, 40 do
  local from2 = table.getn(played) + 1
  local chips0 = ns.db.chips
  Press("Deal", true)
  for _ = 1, 30 do
    if Find("No thanks") then Press("No thanks") elseif Find("Stand") and Enabled("Stand") then Press("Stand") end
    Tick(1)
    if Enabled("Deal", true) then break end
  end
  local net = ns.db.chips - chips0
  if net < 0 and (Count(DROP, from2) > 0) then silentOk = false end
  if net > 0 and Count(FANFARE, from2) ~= 1 then fanfareOk = false end
end
Check("blackjack: chosen sounds are used (lose off, win fanfare)", silentOk and fanfareOk)
Press("Options"); Press("Sounds"); Press("Defaults")
Check("options: Defaults restores the defaults", bdb.sounds.win == "coins" and bdb.sounds.lose == "questDrop")
Press("Done"); Press("Done")

---------------------------------------------------------------------------
-- Solo Hold'em
---------------------------------------------------------------------------
ns:ShowMenu()
ns:OpenGame("holdem")
local P = ns.games.holdem
local hdb = ns.db.holdem
Check("hold'em: default sounds", hdb.sounds.win == "coins" and hdb.sounds.newHand == "pageTurn")
local curFrom = table.getn(played)
Press("1,000")
local hands, handsOk, bad = 0, 0, nil
local cur = nil
for _ = 1, 3000 do
  local T = P.T
  if T.street ~= "idle" then cur = T.hand end
  local f = Find("Fold")
  if f and f.enabled then
    local c = Find("Call", true) or Find("Check")
    if math.random() < 0.25 then env.Fire(f, "OnClick", "LeftButton") elseif c and c.enabled then env.Fire(c, "OnClick", "LeftButton") end
  end
  Tick(0.3)
  T = P.T
  if T.street == "idle" and cur == T.hand then
    local me = T.seats[1]
    local w, l, n = Count(COINS, curFrom + 1), Count(DROP, curFrom + 1), Count(PAGE, curFrom + 1)
    local want = (me.won or 0) > 0 and "win" or ((me.total or 0) > 0 and "lose" or "none")
    local right = n == 1 and ((want == "win" and w == 1 and l == 0) or (want == "lose" and l == 1 and w == 0) or (want == "none" and w == 0 and l == 0))
    hands = hands + 1
    if right then handsOk = handsOk + 1 elseif not bad then bad = "hand " .. T.hand .. " want " .. want .. " got " .. table.concat(played, ",", curFrom + 1) end
    cur = nil
    curFrom = table.getn(played)
    if me.stack <= 0 then      -- busted: buy in again and keep going
      ns.db.chips = math.max(ns.db.chips, 1000)
      Press("Leave table"); Press("1,000")
      curFrom = table.getn(played)
    elseif Enabled("Deal") then Press("Deal") end
  elseif T.street == "idle" and Enabled("Deal") then
    Press("Deal")
  end
  if hands >= 40 then break end
end
Check("hold'em: new hand / win / lose sounds every hand", hands >= 20 and handsOk == hands, handsOk .. "/" .. hands .. " " .. tostring(bad))
Press("Options")
Press("Sounds")
Check("hold'em: Options has its own Sounds screen", Find("Defaults") ~= nil)
Press("Done"); Press("Done")

io.write(ok and "SOUNDS PASS\n" or "SOUNDS FAIL\n")
os.exit(ok and 0 or 1)
