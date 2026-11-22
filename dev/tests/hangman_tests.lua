-- Hangman: solo for chips (hits, misses, being hanged, solving, the 3x
-- perfect payout, giving up), and the party game between isolated clients on
-- the room kit (joining, turns, scoring, solving, a hanging, the clock,
-- the host's own words, the end of the game, leaving and closing).
local H = dofile("harness.lua")
local Check = H.Check

local env, ns = H.Start(nil)
ns:OpenGame("hangman")
local G = ns.Hangman
H.panel = G.panel
local db = ns.db.hangman

Check("Hangman is on the menu, with Play solo and Host a game", G.icon ~= nil and H.Find("Play solo") ~= nil
  and H.Find("Host a game") ~= nil and not H.Find("Host a game").enabled)
H.Press("Play solo")
Check("solo: a bet and a Play button", H.Find("Play for 25") ~= nil and H.Visible(G.ui.betStep))

local function Letter(e, g, l)
  for _, b in ipairs(g.ui.letters) do
    if string.lower(string.gsub(b.text or "", "|c%x%x%x%x%x%x%x%x(.-)|r", "%1")) == l then
      assert(b.enabled, "letter disabled: " .. l)
      e.Fire(b, "OnClick", "LeftButton")
      return
    end
  end
  error("no letter " .. l)
end

local function Deal(word)
  H.Press("Play for " .. ns:FormatChips(db.solo.bet))
  db.solo.word = word      -- a known word for the test
  G.Refresh()
end

local chips = ns.db.chips
Deal("kodo")
Check("Play takes the bet and shows blanks", ns.db.chips == chips - 25 and G.ui.word.text == "_ _ _ _" and G:ChipsInPlay())
Letter(env, G, "o")
Check("a hit fills in every copy of the letter", G.ui.word.text == "_ O _ O" and db.solo.misses == 0)
Letter(env, G, "z")
Check("a miss adds to the gallows", db.solo.misses == 1 and table.getn(G.ui.gallows.order) == 6
  and string.find(G.ui.misses.text, "1 of 6"))
Check("a tried letter can't be picked again", not H.Find("|cffff5050Z|r").enabled)
Letter(env, G, "k")
Letter(env, G, "d")
Check("the whole word: paid 2x", ns.db.chips == chips + 25 and db.solo.result == "win" and not G:ChipsInPlay()
  and string.find(G.ui.status.text, "paid 50"))

chips = ns.db.chips
Deal("ogre")
for _, l in ipairs({ "o", "g", "r", "e" }) do Letter(env, G, l) end
Check("no misses at all: paid 3x", ns.db.chips == chips + 50 and db.stats.perfect == 1)

chips = ns.db.chips
Deal("yeti")
for _, l in ipairs({ "a", "b", "c", "d", "f" }) do Letter(env, G, l) end
Check("five misses: still alive", db.solo.active and db.solo.misses == 5)
Letter(env, G, "g")
Check("six: hanged, the bet's gone, the word shows", not db.solo.active and db.solo.result == "lose"
  and ns.db.chips == chips - 25 and G.ui.word.text == "Y E T I" and table.getn(G.ui.gallows.order) == 11)

Deal("night elf")
Check("spaces show in the blanks", G.ui.word.text == "_ _ _ _ _   _ _ _")
env.TypeInto(G.ui.solveBox, "nightelf x")
env.Fire(G.ui.solveBox, "OnEnterPressed")
Check("a wrong solve is a miss", db.solo.misses == 1 and db.solo.active)
chips = ns.db.chips
env.TypeInto(G.ui.solveBox, "Night-Elf")
H.Press("Solve")
Check("solving it (any capitals, spaces or dashes) wins", db.solo.result == "win" and ns.db.chips == chips + 50)

Deal("murloc")
chips = ns.db.chips
H.Press("Give up")
Check("giving up loses the bet", db.solo.result == "lose" and ns.db.chips == chips and not G:ChipsInPlay())
Deal("murloc")
G:Abandon()
Check("abandoning from Options loses it too", db.solo.result == "lose")
H.Tick(0.3)
Check("between words the window's back button says < Setup", ns.frame.back.text == "< Setup")
env.Fire(ns.frame.back, "OnClick", "LeftButton")
Check("the back button goes to the lobby (the intro)", H.Visible(G.room.lobby))
Check("solo stats", db.stats.solo == 6 and db.stats.soloWins == 3)
H.panel = nil

---------------------------------------------------------------------------
-- The party game
---------------------------------------------------------------------------
local party = H.Party({ game = "hangman", object = function(ns) return ns.Hangman end })
local NewClient, GroupChanged, Run = party.NewClient, party.GroupChanged, party.Run
local function InPanel(cl, o)
  local root = cl.P.panel
  while o do
    if not o.shown then return false end
    if o == root then return true end
    o = o.parent
  end
  return false
end
local function FindIn(cl, text)
  for _, o in ipairs(cl.env.all) do
    -- (text ending in * matches the start: "Play again*")
    if o.kind == "Button" and InPanel(cl, o) and (o.text == text or (string.sub(text, -1) == "*"
      and string.find(o.text or "", string.sub(text, 1, -2), 1, true) == 1)) then return o end
  end
end
local function PressIn(cl, text)
  local b = FindIn(cl, text)
  if not b then error(cl.name .. ": no button " .. text) end
  assert(b.enabled, cl.name .. ": button disabled: " .. text)
  cl.env.Fire(b, "OnClick", "LeftButton")
end
local function LetterIn(cl, l)
  Letter(cl.env, cl.P, l)
  Run(0.5)
end
local function SolveIn(cl, text)
  cl.env.TypeInto(cl.P.ui.solveBox, text)
  cl.env.Fire(cl.P.ui.solveBox, "OnEnterPressed")
  Run(0.5)
end

party.group = { "Ann", "Bob", "Cid" }
local ann, bob, cid = NewClient("Ann"), NewClient("Bob"), NewClient("Cid")
GroupChanged()
PressIn(ann, "Host a game")
Run(0.5)
for _, cl in ipairs({ bob, cid }) do
  PressIn(cl, "Refresh")
  Run(0.5)
  PressIn(cl, "Join")
  Run(1)
end
local AG, BG, room = ann.P.G, bob.P.G, ann.P.room
Check("two join: three players, waiting for the host", table.getn(room.players) == 3 and table.getn(bob.P.room.players) == 3
  and bob.P.room.mode == "client" and FindIn(ann, "Start") ~= nil and FindIn(bob, "Start") == nil)
ann.env.Fire(ann.P.ui.wordsStep.down, "OnClick", "LeftButton")
Run(0.5)
Check("the host's settings reach everyone", AG.set.words == 3 and BG.set.words == 3)
PressIn(ann, "Start")
Run(0.5)
local word = ann.P.HS.word
Check("Start: word 1, blanks and a hint for all, someone's turn", AG.phase == "p" and BG.phase == "p" and BG.round == 1
  and BG.mask == (string.gsub(ann.P.HS.word, "%a", "_")) and BG.hint ~= nil and BG.turn == AG.turn)
local byName = party.byName
local function Turn() return byName[AG.turn] end
local function Others(cl)
  local out = {}
  for _, c in ipairs({ ann, bob, cid }) do if c ~= cl then table.insert(out, c) end end
  return out
end
local t1 = Turn()
Check("only the player whose turn it is can pick", not Others(t1)[1].P.ui.letters[1].enabled
  and t1.P.ui.letters[1].enabled and InPanel(t1, t1.P.ui.solveBox) and not InPanel(Others(t1)[1], Others(t1)[1].P.ui.solveBox))

-- a letter that's in the word: points, and go again
local low = string.lower(word)
local hitL
for i = 1, string.len(low) do
  local ch = string.sub(low, i, i)
  if string.find(ch, "%a") then hitL = ch break end
end
local function Count(w, l) local n = 0 for i = 1, string.len(w) do if string.sub(w, i, i) == l then n = n + 1 end end return n end
local function ScoreOf(name) local p = room:Player(name) return p and p.score end
LetterIn(t1, hitL)
Check("a hit scores a point a letter, and it's still your turn", ScoreOf(t1.name) == Count(low, hitL) and AG.turn == t1.name
  and string.find(string.lower(BG.mask), hitL, 1, true) ~= nil)
local missL
for i = 1, 26 do
  local l = string.sub("zqxjvkwyfbgphmucdlrsnitoae", i, i)
  if not string.find(low, l, 1, true) and not string.find(AG.guessed, l, 1, true) then missL = l break end
end
LetterIn(t1, missL)
Check("a miss passes the turn and grows the gallows", AG.misses == 1 and BG.misses == 1 and AG.turn ~= t1.name
  and table.getn(bob.P.ui.gallows.order) == 6)
Check("everyone's log shows the goes", string.find(table.concat(bob.P.G.log, "\n"), string.upper(missL)) ~= nil)

-- the clock passes the turn (no miss)
local t2 = AG.turn
Run(21)
Check("time up: the turn passes, no miss", AG.turn ~= t2 and AG.misses == 1)

-- solving
local t3 = Turn()
local hidden = ns.SketchWords.Hidden(AG.mask)
SolveIn(t3, "definitely not it")
Check("a wrong solve is a miss", AG.misses == 2 and AG.turn ~= t3.name)
local t4 = Turn()
local before = ScoreOf(t4.name)
SolveIn(t4, string.upper(word))
Check("a right solve: 2 a hidden letter, and the word shows for all", ScoreOf(t4.name) == before + math.max(2, 2 * hidden)
  and AG.phase == "r" and BG.phase == "r" and string.lower(BG.mask) == low and BG.solver == t4.name)
Run(5)
Check("the next word, started by the next player", AG.round == 2 and AG.phase == "p" and BG.misses == 0 and BG.guessed == "")

-- a hanging
local guard = 0
while AG.phase == "p" and guard < 30 do
  local cl = Turn()
  local w = string.lower(ann.P.HS.word)
  local l
  for i = 1, 26 do
    local c = string.sub("zqxjvkwyfbgphmucdlrsnitoae", i, i)
    if not string.find(w, c, 1, true) and not string.find(AG.guessed, c, 1, true) then l = c break end
  end
  if not l then break end
  LetterIn(cl, l)
  guard = guard + 1
end
Check("six misses: hanged, nobody gets it, the word shows", AG.phase == "r" and AG.misses == 6 and BG.solver == nil
  and string.lower(BG.mask) == string.lower(ann.P.HS.word))

-- the last word, then game over
Run(5)
Check("word 3 of 3", AG.round == 3 and AG.phase == "p")
SolveIn(Turn(), ann.P.HS.word)
Run(5)
Check("after the last word: game over for all, Play again for the host", AG.phase == "o" and BG.phase == "o"
  and FindIn(ann, "Play again (1/3)") ~= nil and FindIn(bob, "Play again*") == nil and string.find(bob.P.ui.status.text, "Game over"))
Check("every client counted the game", ann.ns.db.hangman.stats.games == 1 and cid.ns.db.hangman.stats.games == 1)
Check("the ready check: the others get Ready", FindIn(bob, "Ready") ~= nil and FindIn(cid, "Ready") ~= nil)
PressIn(bob, "Ready")
Run(0.5)
Check("...the host sees who's ready", FindIn(ann, "Play again (2/3)") ~= nil and FindIn(bob, "Not ready") ~= nil)
PressIn(cid, "Ready")
Run(0.5)
Check("...everyone ready starts the next game: scores back to 0, word 1", AG.round == 1 and BG.round == 1 and ScoreOf("Bob") == 0)

-- someone leaves, a turn player drops out of the group
PressIn(cid, "Leave game")
Run(0.5)
Check("leaving drops off everyone's list", cid.P.room.mode == "lobby" and table.getn(room.players) == 2
  and table.getn(bob.P.room.players) == 2)
party.group = { "Ann", "Cid" }
GroupChanged()
Run(0.5)
Check("down to one guesser: the word ends", AG.phase ~= "p" and table.getn(room.players) == 1)
party.group = { "Ann", "Bob", "Cid" }
GroupChanged()
PressIn(ann, "Close game")
Run(0.5)
Check("closing sends everyone to the lobby", room.mode == "lobby" and bob.P.room.mode == "lobby")

-- the host's own words: the host sits out
ann.P.G.set = ann.ns.db.hangman.party
PressIn(ann, "Host a game")
Run(0.5)
ann.env.Fire(ann.P.ui.picker.own, "OnClick", "LeftButton")
ann.env.TypeInto(ann.P.ui.picker.box, "kodo, ogre, wisp")
for _, c in ipairs(ann.P.ui.picker.checks) do
  if c.checked then ann.env.Fire(c, "OnClick", "LeftButton") end
end
Check("own words: a count, and the packs can be turned off", string.find(ann.P.ui.picker.count.text, "^3 ") ~= nil
  and ann.ns.db.hangman.party.packs == "")
PressIn(bob, "Refresh")
Run(0.5)
PressIn(bob, "Join")
Run(1)
Check("...two players isn't enough", not FindIn(ann, "Start").enabled)
PressIn(cid, "Refresh")
Run(0.5)
PressIn(cid, "Join")
Run(1)
PressIn(ann, "Start")
Run(0.5)
local own = { kodo = true, ogre = true, wisp = true }
Check("three is: only the host's words, and the host never has a turn", AG.phase == "p" and own[ann.P.HS.word]
  and AG.turn ~= "Ann" and BG.hint == "the host's own words")
local turns = {}
for i = 1, 4 do
  turns[AG.turn] = true
  Run(21)
end
Check("...turns go round Bob and Cid only", turns.Bob and turns.Cid and not turns.Ann)

-- a reload mid-game: Bob asks to rejoin, and the host kept his place
local bobScore = room:Player("Bob").score
local savedBob = bob.env.CowCasinoDB
for i, c in ipairs(party.clients) do if c == bob then table.remove(party.clients, i) break end end
local bob2 = NewClient("Bob", savedBob)
Check("after a reload: rejoining", string.find(bob2.P.room.lobbyMsg or "", "Rejoining Ann's game", 1, true) ~= nil, bob2.P.room.lobbyMsg)
Run(2)
Check("...and back in Ann's game, score and all", bob2.P.room.mode == "client" and bob2.P.room.host == "Ann"
  and bob2.P.room:Player("Bob").score == bobScore and ns.getn(room.players) == 3)
Check("...with the game in progress on his screen", bob2.P.G.phase == AG.phase and bob2.P.G.round == AG.round, bob2.P.G.phase)

-- watching: Dan follows the game without a place in it
table.insert(party.group, "Dan")
local dan = NewClient("Dan")
GroupChanged()
PressIn(dan, "Refresh")
Run(0.5)
PressIn(dan, "Watch")
Run(1)
Check("watching: Dan sees the game in progress, without a place in it", dan.P.room.watching and dan.P.room.mode == "client"
  and dan.P.G.phase == AG.phase and dan.P.G.round == AG.round and room:Player("Dan") == nil and ns.getn(room.players) == 3)
local anyLetter = false
for _, b in ipairs(dan.P.ui.letters) do if b.enabled then anyLetter = true end end
Check("...he can't play a letter, and can stop watching", not anyLetter and FindIn(dan, "Stop watching") ~= nil)
PressIn(dan, "Stop watching")
Run(0.5)
Check("...which takes him back to the lobby, the game going on", dan.P.room.mode == "lobby" and ns.getn(room.players) == 3)

Check("no addon message ran long", party.stats.longest <= 254, party.stats.longest)
H.Done("HANGMAN")
