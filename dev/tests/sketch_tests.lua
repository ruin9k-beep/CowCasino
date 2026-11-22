-- Sketch & Guess and the drawing kit: words (matching, close guesses, masks,
-- the artist's disguised word), packing points, drawing (rotated lines and
-- dots, erasing, undo), Practice, and party games between isolated clients
-- (joining, a drawing kept in step, guessing, hints, scoring, a latecomer
-- catching up, the host's own words, leaving and closing).
local H = dofile("harness.lua")
local Check = H.Check

local env, ns = H.Start(nil)
local W, Kit = ns.SketchWords, ns.SketchKit

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
Check("guesses match without capitals, spaces or dashes", W.Norm("Night-Elf") == W.Norm("night elf") and W.Norm("NIGHTELF") == "nightelf")
Check("one letter off is close; two isn't; short words never are", W.Close("dragn", "dragon") and W.Close("dragoon", "dragon")
  and W.Close("dragan", "dragon") and not W.Close("drgn", "dragon") and not W.Close("cat", "car"))
Check("a mask hides letters and keeps spaces", W.Mask("night elf") == "_____ ___" and W.Mask("Un'Goro", { [1] = true }) == "U_'____")
Check("a mask is shown spaced", W.ShowMask("__ _") == "_ _   _")
local hid = W.Hide("thunder bluff", "Ann7.3")
Check("the artist's word comes back with the right key, not in plain text", W.Reveal(hid, "Ann7.3") == "thunder bluff"
  and W.Reveal(hid, "Bob7.3") ~= "thunder bluff" and not string.find(hid, "thunder"))
local custom = W.ParseCustom("apple, Banana;; banana , cow|x ,\nkodo")
Check("your own words: split, tidied and without repeats", table.getn(custom) == 4 and custom[2] == "Banana" and custom[3] == "cow x")
Check("a pool holds the chosen packs (and your words)", table.getn(W.Pool("e", nil)) == table.getn(W.Pack("e").words)
  and table.getn(W.Pool("ec", "a,b")) == table.getn(W.Pack("e").words) + table.getn(W.Pack("c").words) + 2)
local clean = true
for _, p in ipairs(W.PACKS) do for _, w in ipairs(p.words) do if W.Clean(w) ~= w or W.Norm(w) == "" then clean = false end end end
Check("every built-in word travels as is", clean)

---------------------------------------------------------------------------
-- The kit
---------------------------------------------------------------------------
local pts = { 0, 0, 255, 255, 17, 200, 128, 3 }
local back = Kit.DecodePoints(Kit.EncodePoints(pts, 1, 4))
local same = table.getn(back) == 8
for i = 1, 8 do if back[i] ~= pts[i] then same = false end end
Check("points pack into 3 characters each and come back", same and string.len(Kit.EncodePoints(pts, 1, 4)) == 12)
local c, s = Kit.ParseStyle(Kit.StyleChar(9, 4))
Check("a stroke's color and size pack into one character", c == 9 and s == 4)

local holder = env.CreateFrame("Frame", nil, env.UIParent)
local C = Kit.NewCanvas(holder, { size = 256, owner = "Me" })
ns.db.sketchLines = "lines"
C:AddPoints("Me:1", Kit.StyleChar(1, 2), 1, { 10, 10, 50, 10 })
local st = C:Stroke("Me:1")
local seg
for _, t in ipairs(st.tex) do if table.getn(t.coords) == 8 then seg = t end end
Check("a straight line: two dots and one turned bar", table.getn(st.tex) == 3 and seg ~= nil)
local k = seg and seg.coords
Check("...a level bar's corners show the whole texture, the right way up", k and math.abs(k[1]) < 1e-6 and math.abs(k[2]) < 1e-6
  and math.abs(k[4] - 1) < 1e-6 and math.abs(k[5] - 1) < 1e-6 and math.abs(k[8] - 1) < 1e-6)
C:AddPoints("Me:2", Kit.StyleChar(2, 3), 1, { 20, 200, 120, 120 })
local d
for _, t in ipairs(C:Stroke("Me:2").tex) do if table.getn(t.coords) == 8 then d = t.coords end end
-- an affine map: opposite corners sum the same, and the box's middle is the texture's
local par = d and math.abs((d[1] + d[7]) - (d[3] + d[5])) < 1e-6 and math.abs((d[1] + d[7]) / 2 - 0.5) < 1e-6
  and math.abs((d[2] + d[8]) / 2 - 0.5) < 1e-6
Check("a slanted bar maps the texture evenly onto its box, centered", par)
-- the stroke's ends land at the bar's ends: walk from the middle by half the length
local function UV(cs, fx, fy)  -- bilinear over the box (fx right, fy down)
  local u = cs[1] * (1 - fx) * (1 - fy) + cs[5] * fx * (1 - fy) + cs[3] * (1 - fx) * fy + cs[7] * fx * fy
  local v = cs[2] * (1 - fx) * (1 - fy) + cs[6] * fx * (1 - fy) + cs[4] * (1 - fx) * fy + cs[8] * fx * fy
  return u, v
end
local t2
for _, t in ipairs(C:Stroke("Me:2").tex) do if table.getn(t.coords) == 8 then t2 = t end end
local bw, bh = t2.w or t2.width, t2.h or t2.height
local ok = false
if bw and bh then
  -- end (120, 120) relative to the box's top-left at (70 - bw/2, 160 - bh/2)
  local u, v = UV(d, (120 - (70 - bw / 2)) / bw, (120 - (160 - bh / 2)) / bh)
  ok = math.abs(u - (1 - 2 / 32)) < 1e-6 and math.abs(v - 0.5) < 1e-6
end
Check("...and the stroke's end lands on the bar's end", ok)
local before = C.used
C:AddPoints("Me:2", Kit.StyleChar(2, 3), 1, { 20, 200, 120, 120 })
Check("points sent again draw nothing new", C.used == before)
C:AddPoints("Me:2", Kit.StyleChar(2, 3), 3, { 150, 120 })
Check("the next points carry the stroke on", C:Stroke("Me:2").n == 3 and C.used == before + 2)
Kit.SetLineMode("dots")
Check("dots: the same strokes, drawn as dot chains", C.mode == "dots" and table.getn(C:Stroke("Me:1").tex) > 3)
Kit.SetLineMode("lines")
Check("...and back to lines", table.getn(C:Stroke("Me:1").tex) == 3)
local n = C.used
C:Undo()
Check("Undo takes your newest stroke, and its textures go back to the pool", C:Stroke("Me:2") == nil and C.used < n
  and table.getn(C.pool) > 0)
local hit = C:StrokeAt(30, 11, 3)
Check("a stroke can be found under the eraser", hit and hit.key == "Me:1" and C:StrokeAt(200, 200, 3) == nil)
C:Clear()
Check("Clear empties the canvas", C.used == 0 and table.getn(C.order) == 0)
Check("the test pattern draws every color", C:TestPattern() == table.getn(Kit.COLORS) + 3 and C.used > 50)
C:Clear()

---------------------------------------------------------------------------
-- Practice, with the mouse
---------------------------------------------------------------------------
ns:OpenGame("sketch")
local G = ns.Sketch
H.panel = G.panel
Check("Sketch & Guess is on the menu: lobby with Host and Practice", G.icon ~= nil and H.Find("Practice") ~= nil
  and H.Find("Host a game") ~= nil and not H.Find("Host a game").enabled)
H.Press("Practice")
local canvas = G.ui.canvas
local function MouseAt(e, x, y) e.GetCursorPosition = function() return 412.5 + x, 655 - y end end
MouseAt(env, 40, 40)
env.Fire(canvas.frame, "OnMouseDown", "LeftButton")
for i = 1, 10 do
  MouseAt(env, 40 + i * 8, 40 + i * 4)
  env.Fire(canvas.frame, "OnUpdate", 0.02)
end
env.Fire(canvas.frame, "OnMouseUp", "LeftButton")
local mine = canvas:Owned(canvas.owner)
Check("practice: dragging the mouse draws a stroke", table.getn(mine) == 1 and mine[1].n == 11 and mine[1].pts[1] == 40)
H.Press("Test pattern")
Check("the test pattern is a button away", table.getn(canvas.order) > 5)
H.Press("Done")
Check("Done goes back to the lobby", G.S.mode == "lobby")
H.panel = nil

---------------------------------------------------------------------------
-- A party game
---------------------------------------------------------------------------
local party = H.Party({ game = "sketch", object = function(ns) return ns.Sketch end })
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
local function GuessIn(cl, text)
  local box = cl.P.ui.guess
  assert(InPanel(cl, box), cl.name .. " can't guess now")
  cl.env.TypeInto(box, text)
  cl.env.Fire(box, "OnEnterPressed")
  Run(0.5)
end
local function Draw(cl, from, to)
  local cv = cl.P.ui.canvas
  MouseAt(cl.env, from[1], from[2])
  cl.env.Fire(cv.frame, "OnMouseDown", "LeftButton")
  for i = 1, 8 do
    MouseAt(cl.env, from[1] + (to[1] - from[1]) * i / 8, from[2] + (to[2] - from[2]) * i / 8)
    cl.env.Fire(cv.frame, "OnUpdate", 0.02)
  end
  cl.env.Fire(cv.frame, "OnMouseUp", "LeftButton")
end
local function Sum(cl)   -- every stroke's points, as one string
  local out = {}
  for _, s in ipairs(cl.P.ui.canvas.order) do table.insert(out, s.key .. "=" .. table.concat(s.pts, ",")) end
  return table.concat(out, "|")
end

party.group = { "Ann", "Bob", "Cid" }
local ann, bob, cid = NewClient("Ann"), NewClient("Bob"), NewClient("Cid")
GroupChanged()
PressIn(ann, "Host a game")
Run(0.5)
PressIn(bob, "Refresh")
Run(0.5)
Check("a hosted game shows in the others' lobbies", bob.P.ui.intro.rows[1].offer ~= nil and bob.P.ui.intro.rows[1].offer.host == "Ann")
PressIn(bob, "Join")
PressIn(cid, "Refresh")
Run(0.5)
PressIn(cid, "Join")
Run(1)
local AS, BS, CS = ann.P.S, bob.P.S, cid.P.S
Check("both join: three players on every screen, waiting to start", table.getn(AS.players) == 3 and table.getn(BS.players) == 3
  and BS.mode == "client" and CS.mode == "client" and BS.phase == "w" and FindIn(bob, "Start") == nil)
Check("the host sees the settings and Start; the others see a summary", FindIn(ann, "Start") ~= nil
  and InPanel(bob, bob.P.ui.waitSummary) and string.find(bob.P.ui.waitSummary.text or "", "80 seconds"))

-- the host turns the time down: everyone hears
ann.env.Fire(ann.P.ui.timeStep.down, "OnClick", "LeftButton")
Run(0.5)
Check("a settings change reaches everyone", AS.set.time == 60 and BS.set.time == 60)

PressIn(ann, "Start")
Run(0.5)
local function ByName(name) return party.byName[name] end
local drawer = ByName(AS.drawer)
Check("Start: turn 1, the first artist round robin, the clock running", AS.phase == "d" and AS.turn == 1 and BS.turn == 1
  and AS.drawer == BS.drawer and AS.drawer == CS.drawer and BS.deadline ~= nil)
local word = ann.P.HS.word
Check("the artist (only) sees the word; the others see blanks", drawer.P.S.word == word
  and ((drawer == bob) or BS.word == nil) and ((drawer == cid) or CS.word == nil)
  and string.find(bob.P.ui.word.text, "_") ~= nil or drawer == bob)
local guessers = {}
for _, cl in ipairs({ ann, bob, cid }) do if cl ~= drawer then table.insert(guessers, cl) end end
Check("the artist gets the tools, the guessers a guess box", InPanel(drawer, drawer.P.ui.tools.colors[1])
  and not InPanel(drawer, drawer.P.ui.guess) and InPanel(guessers[1], guessers[1].P.ui.guess))

Draw(drawer, { 30, 30 }, { 200, 120 })
drawer.env.Fire(drawer.P.ui.tools.colors[4], "OnClick", "LeftButton")
drawer.env.Fire(drawer.P.ui.tools.sizes[4], "OnClick", "LeftButton")
Draw(drawer, { 50, 220 }, { 220, 60 })
Run(1)
Check("the drawing reaches everyone, point for point", Sum(guessers[1]) == Sum(drawer) and Sum(guessers[2]) == Sum(drawer)
  and table.getn(drawer.P.ui.canvas.order) == 2)
Check("...color and size too", guessers[1].P.ui.canvas.order[2].color == 4 and guessers[1].P.ui.canvas.order[2].size == 4)
drawer.env.Fire(drawer.P.ui.tools.undo, "OnClick", "LeftButton")
Run(0.5)
Check("Undo takes it off everyone's canvas", table.getn(guessers[1].P.ui.canvas.order) == 1 and Sum(guessers[2]) == Sum(drawer))
-- a guesser can't draw on it
local g1 = guessers[1]
Draw(g1, { 10, 10 }, { 100, 100 })
Check("guessers can't draw", table.getn(g1.P.ui.canvas.order) == 1)

-- a latecomer
party.group = { "Ann", "Bob", "Cid", "Dee" }
local dee = NewClient("Dee")
GroupChanged()
PressIn(dee, "Refresh")
Run(0.5)
PressIn(dee, "Join")
Run(4)
Check("someone joining partway gets the drawing so far", dee.P.S.mode == "client" and dee.P.S.phase == "d"
  and Sum(dee) == Sum(drawer) and table.getn(dee.P.ui.canvas.order) == 1)
table.insert(guessers, dee)

-- guessing
GuessIn(g1, "potato")
local log = table.concat(drawer.P.S.log, "\n")
Check("a wrong guess shows for everyone", string.find(log, "potato") ~= nil and AS.phase == "d")
local near = string.sub(word, 1, string.len(word) - 1) .. (string.sub(word, -1) == "z" and "y" or "z")
if string.len(W.Norm(word)) >= 4 then
  GuessIn(g1, near)
  local l2 = table.concat(drawer.P.S.log, "\n")
  Check("a close guess is flagged, without giving it away", string.find(l2, "is close") ~= nil and not string.find(l2, near, 1, true))
end
local g2 = guessers[2]
GuessIn(g2, string.upper(word))
Check("the right guess ends the turn: the word shows for everyone", AS.phase == "r" and BS.phase == "r" and dee.P.S.phase == "r"
  and BS.word == word and BS.winner == g2.name)
local function Score(name) for _, p in ipairs(AS.players) do if p.name == name then return p.score end end end
Check("2 points to the guesser, 1 to the artist", Score(g2.name) == 2 and Score(drawer.name) == 1 and Score(g1.name) == 0)
Check("stats: a right guess and a drawing guessed", g2.P.S and ns ~= nil and drawer.ns.db.sketch.stats.drawn == 1
  and g2.ns.db.sketch.stats.guessed == 1)
Check("nobody can guess once it's over", not InPanel(g1, g1.P.ui.guess))

Run(6)
Check("after the reveal, the next turn: a new artist and a clean canvas", AS.phase == "d" and AS.turn == 2
  and AS.drawer ~= drawer.name and table.getn(BS.players) == 4 and table.getn(bob.P.ui.canvas.order) == 0)

-- hints and running out of time
local w2 = ann.P.HS.word
Run(31)
local hidden = W.Hidden(CS.mask)
Check("at half time a letter shows", string.len(W.Norm(w2)) < 4 or hidden == string.len(W.Norm(w2)) - 1)
Run(30)
Check("time up: nobody got it, the word shows anyway", AS.phase == "r" and CS.word == w2 and CS.winner == nil)

-- play to the end (one turn each would have ended it: the game's at two)
local guard = 0
while AS.phase ~= "o" and guard < 150 do Run(5) guard = guard + 1 end
Check("everyone draws twice, round robin, then the game's over", AS.phase == "o" and BS.phase == "o"
  and (function() for _, p in ipairs(AS.players) do if p.drew ~= 2 then return false end end return true end)())
Check("final scores for all, Play again for the host", InPanel(bob, bob.P.ui.banner) and string.find(bob.P.ui.bannerText.text, "Final")
  and FindIn(ann, "Play again*") ~= nil and FindIn(bob, "Play again*") == nil)
Check("every client counted the game", ann.ns.db.sketch.stats.games == 1 and bob.ns.db.sketch.stats.games == 1
  and dee.ns.db.sketch.stats.games == 1)
PressIn(ann, "Play again*")
Run(0.5)
Check("Play again: scores back to 0, turn 1", AS.phase == "d" and AS.turn == 1 and BS.turn == 1 and Score("Bob") == 0)

-- leaving and closing
PressIn(dee, "Leave game")
Run(0.5)
Check("a player leaving drops off everyone's list", dee.P.S.mode == "lobby" and table.getn(AS.players) == 3 and table.getn(BS.players) == 3)
local guard3 = 0
while (AS.drawer == "Ann" or AS.phase ~= "d") and guard3 < 10 do Run(33) guard3 = guard3 + 1 end
local artist = AS.drawer
do
  party.group = { "Ann", artist == "Bob" and "Cid" or "Bob" }
  GroupChanged()
  Run(0.5)
  Check("the artist leaving the group ends their turn", AS.phase == "r" and table.getn(AS.players) == 2)
  party.group = { "Ann", "Bob", "Cid" }
  GroupChanged()
end
PressIn(ann, "Close game")
Run(0.5)
Check("the host closing sends everyone back to the lobby", AS.mode == "lobby" and BS.mode == "lobby" and CS.mode == "lobby")

-- the host's own words
ann.P.S.set = ann.ns.db.sketch.settings
ann.ns.db.sketch.settings.packs = ""
ann.ns.db.sketch.settings.custom = true
ann.ns.db.sketch.settings.each = 1
PressIn(ann, "Host a game")
Run(0.5)
Check("own words: a box to type them in", InPanel(ann, ann.P.ui.customBox))
ann.env.TypeInto(ann.P.ui.customBox, "kodo, murloc")
Check("...and a count of them", string.find(ann.P.ui.customCount.text, "^2 ") ~= nil)
PressIn(bob, "Refresh")
Run(0.5)
PressIn(bob, "Join")
Run(1)
Check("own words: two players isn't enough (the host doesn't guess)", not FindIn(ann, "Start").enabled)
PressIn(cid, "Refresh")
Run(0.5)
PressIn(cid, "Join")
Run(1)
PressIn(ann, "Start")
Run(0.5)
Check("...three is: the game uses only the host's words", AS.phase == "d" and (ann.P.HS.word == "kodo" or ann.P.HS.word == "murloc"))
local guard2 = 0
while AS.drawer ~= "Bob" and guard2 < 10 do Run(66) guard2 = guard2 + 1 end
Check("when someone else draws, the host can't guess", AS.drawer == "Bob" and not InPanel(ann, ann.P.ui.guess)
  and InPanel(cid, cid.P.ui.guess))

-- what went over the wire
Check("no addon message ran long", party.stats.longest <= 254, party.stats.longest)

H.Done("SKETCH")
