-- Chess and Checkers on the board kit: checkers against the computer (the
-- stake, clicking moves and jumps, the computer answering, resigning, a win
-- paying double, a reload carrying on), and party games between isolated
-- clients (a challenge and accept, moves both ways, checkmate, draw offers,
-- resigning, promotion, and a reload catching up on missed moves).
local H = dofile("harness.lua")
local Check = H.Check

local function Copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Copy(v) end
  return out
end

-- Square names: "e2" -> 13 (chess); checkers numbers 1-32 -> squares
local function Sq(name) return (tonumber(string.sub(name, 2)) - 1) * 8 + (string.byte(name, 1) - 97) + 1 end

---------------------------------------------------------------------------
-- Checkers against the computer
---------------------------------------------------------------------------
local env, ns = H.Start(nil)
local K = ns.CheckersRules
local function KSq(n) for s = 1, 64 do if K.Dark(s) and K.Num(s) == n then return s end end end
ns:OpenGame("checkers")
local G = ns.games.checkers
local function Click(s) env.Fire(G.ui.squares[s], "OnClick", "LeftButton") end
local function Dots()
  local n = 0
  for s = 1, 64 do if G.ui.squares[s].dot.shown then n = n + 1 end end
  return n
end

Check("Checkers is on the menu, with its icon", ns.games.checkers.icon ~= nil and ns.games.chess ~= nil)
Check("it opens on Vs the computer, with stake, level and side pickers", G.ui.stake.shown and G.ui.level.shown
  and H.Find("Play for 50") ~= nil)
local before = ns.db.chips
H.Press("Play for 50")
local g = G.S.game
Check("Play takes the 50 stake and starts you as Black", g ~= nil and ns.db.chips == before - 50 and g.me == "b")
Check("...with the board's 24 pieces showing", (function()
  local n = 0
  for s = 1, 64 do if G.ui.squares[s].piece.shown then n = n + 1 end end
  return n == 24
end)())
Click(KSq(11))
Check("clicking a piece selects it and marks where it can go", G.S.sel ~= nil and Dots() == 2, Dots())
Click(KSq(15))
Check("clicking a marked square plays the move", table.getn(g.moves) == 1 and G.S.sel == nil and g.log[1] == "1. 11-15", g.log[1])
H.Tick(0.3)
Check("the computer waits a moment...", table.getn(g.moves) == 1)
H.Tick(3)
Check("...then answers", table.getn(g.moves) == 2 and K.Num ~= nil, table.getn(g.moves))
Click(KSq(1))
Check("a piece that can't move can't be picked", G.S.sel == nil)

-- a reload carries the game on
local saved = Copy(env.CowCasinoDB)
local env2, ns2 = H.Start(saved)
ns2:OpenGame("checkers")
local G2 = ns2.games.checkers
Check("after a reload the game is still on, same moves", G2.S.game ~= nil and table.getn(G2.S.game.moves) == 2
  and G2.S.game.stake == 50 and G2:ChipsInPlay())

H.Press("Resign")
Check("Resign loses the game (and the stake)", G.S.game == nil and G.db.stats.losses == 1 and ns.db.chips == before - 50)
Check("...and the last position stays on the board", G.S.over ~= nil and H.Find("Play for 50") ~= nil)

-- a double jump, clicked square by square, wins the game and pays double
local function Board(list, turn)
  local sq = {}
  for i = 1, 64 do sq[i] = false end
  for n, piece in pairs(list) do sq[KSq(n)] = piece end
  return { sq = sq, turn = turn, quiet = 0 }
end
before = ns.db.chips
H.Press("Play for 50")
g = G.S.game
g.pos = Board({ [14] = "bM", [18] = "rM", [26] = "rM" }, "b")
G:Refresh()
Click(KSq(14))
Click(KSq(23))
Check("the first hop of a double jump waits for the next", table.getn(g.moves) == 0 and G.S.sel ~= nil
  and table.getn(G.S.sel) == 2 and Dots() == 1)
Click(KSq(30))
Check("the second hop finishes it, takes both pieces, and wins", G.S.game == nil and G.db.stats.wins == 1)
Check("a win pays double the stake", ns.db.chips == before + 50, ns.db.chips - before)

-- Hard, Easy: the level picker
G.db.level = 1
G:Refresh()
Check("the level picker shows Easy", string.find(G.ui.level.text.text, "Easy") ~= nil)
G.db.level = 2

---------------------------------------------------------------------------
-- Chess against the computer
---------------------------------------------------------------------------
ns:OpenGame("chess")
local CH = ns.games.chess
Check("Chess opens on Vs the computer too, with Easy, Medium and Hard", CH.ui.stake.shown
  and string.find(CH.ui.level.text.text, "Medium", 1, true) ~= nil and H.Find("Play for 50") ~= nil)
CH.db.level = 3
CH.db.side = "b"
CH:Refresh()
before = ns.db.chips
H.Press("Play for 50")
local cg = CH.S.game
Check("playing Black: the stake is paid and the computer moves first", cg ~= nil and cg.me == "b"
  and ns.db.chips == before - 50 and string.find(CH.ui.files[1].text, "h", 1, true) ~= nil)
H.Tick(5)
Check("Hard answers within a few seconds of game time", table.getn(cg.moves) == 1, table.getn(cg.moves))
env.Fire(CH.ui.squares[Sq("e7")], "OnClick", "LeftButton")
env.Fire(CH.ui.squares[Sq("e5")], "OnClick", "LeftButton")
H.Tick(5)
Check("your move, then the computer's", table.getn(cg.moves) == 3, table.getn(cg.moves))
H.Press("Resign")
Check("Resign ends it as a loss", CH.S.game == nil and CH.db.stats.losses == 1 and ns.db.chips == before - 50)

---------------------------------------------------------------------------
-- Party chess
---------------------------------------------------------------------------
local party = H.Party({ game = "chess", object = function(ns) return ns.games.chess end, button = "Party game" })
local clients, byName = party.clients, party.byName
local NewClient, GroupChanged, Tick, Run = party.NewClient, party.GroupChanged, party.Tick, party.Run

local function InPanel(c, o)
  local root = c.P.panel
  while o do
    if not o.shown then return false end
    if o == root then return true end
    o = o.parent
  end
  return false
end
local function FindIn(c, text)
  for _, o in ipairs(c.env.all) do
    if o.kind == "Button" and InPanel(c, o) and o.text == text then return o end
  end
end
local function PressIn(c, text)
  local b = FindIn(c, text)
  assert(b, c.name .. ": no button " .. text)
  assert(b.enabled, c.name .. ": button disabled: " .. text)
  c.env.Fire(b, "OnClick", "LeftButton")
end
local function Move(c, from, to)
  c.env.Fire(c.P.ui.squares[Sq(from)], "OnClick", "LeftButton")
  c.env.Fire(c.P.ui.squares[Sq(to)], "OnClick", "LeftButton")
  Run(1)
end

party.group = { "Host", "Guest" }
local host = NewClient("Host")
local guest = NewClient("Guest")
GroupChanged()
Check("Chess's Party game tab shows the lobby (no stake or level)", host.P.ui.lobby.shown
  and FindIn(host, "Challenge the group") ~= nil and not host.P.ui.stake.shown)
local hostChips = host.ns.db.chips
PressIn(host, "Challenge the group")
Run(1)
Check("a challenge shows in the other player's lobby", guest.P.ui.rows[1].shown
  and string.find(guest.P.ui.rows[1].text.text, "Host (plays White)", 1, true) ~= nil, guest.P.ui.rows[1].text.text)
PressIn(guest, "Accept")
Run(1)
local hg, gg = host.P.S.game, guest.P.S.game
Check("Accept starts the game on both sides: Host White, Guest Black", hg and gg and hg.me == "w" and gg.me == "b"
  and hg.opp == "Guest" and gg.opp == "Host")
Check("...the Black player's board is turned round", guest.P.ui.files[1].text == "h" and host.P.ui.files[1].text == "a")
Move(guest, "e7", "e5")
Check("you can't move on the other player's turn", table.getn(gg.moves) == 0)
Move(host, "f2", "f3")
Check("a move shows on both boards", table.getn(gg.moves) == 1 and gg.pos.sq[Sq("f3")] == "wP")
Move(guest, "e7", "e5")
Move(host, "g2", "g4")
Move(guest, "d8", "h4")
Check("fool's mate: Black wins on both sides", host.P.S.game == nil and guest.P.S.game == nil
  and host.P.db.stats.losses == 1 and guest.P.db.stats.wins == 1)
Check("...and party games are free: no chips move", host.ns.db.chips == hostChips)
Check("...the move list ends in Qh4#", string.find(guest.P.S.over.log[2], "Qh4#", 1, true) ~= nil, guest.P.S.over.log[2])

-- a draw offer
local function NewGame()
  PressIn(host, "Challenge the group")
  Run(1)
  PressIn(guest, "Accept")
  Run(1)
  return host.P.S.game, guest.P.S.game
end
hg, gg = NewGame()
PressIn(host, "Offer draw")
Run(1)
Check("a draw offer shows as Accept draw for the other player", FindIn(guest, "Accept draw") ~= nil
  and FindIn(host, "Draw offered") ~= nil)
PressIn(guest, "Accept draw")
Run(1)
Check("taking it ends the game as a draw for both", host.P.S.game == nil and guest.P.S.game == nil
  and host.P.db.stats.draws == 1 and guest.P.db.stats.draws == 1)

hg, gg = NewGame()
Move(host, "e2", "e4")
PressIn(host, "Offer draw")
Run(1)
Move(guest, "e7", "e5")
Check("a move instead turns the offer down", FindIn(host, "Offer draw") ~= nil and FindIn(guest, "Accept draw") == nil)
PressIn(guest, "Resign")
Run(1)
Check("Resign: the other player wins", host.P.S.game == nil and host.P.db.stats.wins == 1 and guest.P.db.stats.losses == 1)

-- promotion: pick the piece
hg, gg = NewGame()
local function Promo(c)
  local g = c.P.S.game
  local sq = {}
  for i = 1, 64 do sq[i] = false end
  sq[Sq("e7")], sq[Sq("e1")], sq[Sq("a8")], sq[Sq("h5")] = "wP", "wK", "bK", "bR"
  g.pos = { sq = sq, turn = "w", castle = "", half = 0, full = 30 }
  c.P:Refresh()
end
Promo(host); Promo(guest)
host.env.Fire(host.P.ui.squares[Sq("e7")], "OnClick", "LeftButton")
host.env.Fire(host.P.ui.squares[Sq("e8")], "OnClick", "LeftButton")
Check("a pawn reaching the end asks what to promote to", host.P.ui.choiceBox.shown and FindIn(host, "Knight") ~= nil)
PressIn(host, "Knight")
Run(1)
Check("...and the other board gets the same piece", gg.pos.sq[Sq("e8")] == "wN" and hg.pos.sq[Sq("e8")] == "wN")
PressIn(host, "Resign")
Run(1)

-- a reload: the game carries on, and missed moves catch up
local function Drop(c) for i, x in ipairs(clients) do if x == c then table.remove(clients, i) end end end
hg, gg = NewGame()
Move(host, "c2", "c4")
local gsaved = Copy(guest.env.CowCasinoDB)
Drop(guest)
guest = NewClient("Guest", gsaved)
Run(2)
gg = guest.P.S.game
Check("after a reload the game is still on", gg ~= nil and table.getn(gg.moves) == 1 and gg.me == "b"
  and string.find(guest.P.ui.status.text, "still on", 1, true) ~= nil)
Move(guest, "c7", "c5")
Move(host, "b1", "c3")
Check("moves go on both ways after it", table.getn(host.P.S.game.moves) == 3 and table.getn(gg.moves) == 3)
Move(guest, "b8", "c6")
gsaved = Copy(guest.env.CowCasinoDB)
Drop(guest)
Move(host, "g1", "f3")                   -- the guest is away and misses this one
guest = NewClient("Guest", gsaved)
Run(2)
gg = guest.P.S.game
Check("a client that missed a move gets it again after a reload", table.getn(gg.moves) == 5
  and gg.pos.sq[Sq("f3")] == "wN", table.getn(gg.moves))
Move(guest, "g8", "f6")
Check("...and play goes on", table.getn(host.P.S.game.moves) == 6)

-- the other player goes quiet: the game can be called off
Drop(guest)
Run(95)
Check("after a long silence, Resign becomes Call it off", FindIn(host, "Call it off") ~= nil)
PressIn(host, "Call it off")
Check("...which ends the game without a result (not counted)", host.P.S.game == nil and host.P.db.stats.games == 4,
  host.P.db.stats.games)

-- leaving the group calls a game off
guest = NewClient("Guest")
GroupChanged()
hg, gg = NewGame()
party.group = { "Host" }
GroupChanged()
Check("the other player leaving the group calls the game off", host.P.S.game == nil
  and string.find(host.P.ui.status.text, "left the group", 1, true) ~= nil)

H.Done("BOARD")
