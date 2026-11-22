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

Check("checkers shows the captured-pieces rows, empty to start", G.ui.taken ~= nil
  and not G.ui.taken[1].icons[1].shown and not G.ui.taken[2].icons[1].shown)
G:DrawTaken({ me = "b", taken = { b = { "rM", "rK", "rM" }, r = { "bM" } } })
local function KIcons(k) local n = 0 for _, t in ipairs(G.ui.taken[k].icons) do if t.shown then n = n + 1 end end return n end
Check("...what you took and what they took, with the lead in pieces", KIcons(2) == 3 and KIcons(1) == 1
  and string.find(G.ui.taken[2].lead.text, "+2", 1, true) ~= nil and G.ui.taken[1].lead.text == "")
Check("...kings first", G.ui.taken[2].icons[1].coords[1] == 0.75 and G.ui.taken[2].icons[1].coords[3] == 0.375
  and G.ui.taken[2].icons[2].coords[3] == 0.375 and G.ui.taken[2].icons[2].coords[1] == 0.5)
G:DrawTaken(nil)
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
-- piece sets (Options > Settings)
local function PieceSquare(pc) for q = 1, 64 do if g.pos.sq[q] == pc then return G.ui.squares[q] end end end
G.ui.options:Show()
H.Press("Settings")
local ps = G.ui.options.pieceStep
Check("Options > Settings: Pieces, Classic to start", ps ~= nil and string.find(ps.text.text, "Classic", 1, true) ~= nil
  and PieceSquare("bM").piece.tex == ns.BoardKit.ATLAS and not PieceSquare("bM").emblem.shown)
env.Fire(ps.up, "OnClick", "LeftButton")
Check("...Horde vs Alliance: its own pieces and squares, saved", G.db.pieceSet == "faction"
  and string.find(PieceSquare("bM").piece.tex, "BoardPiecesFaction", 1, true) ~= nil
  and string.find(ps.text.text, "Horde vs Alliance", 1, true) ~= nil
  and string.find(G.ui.options.pieceNote.text, "Alliance plays Black", 1, true) ~= nil)
Check("...the men wear their faction's emblem", PieceSquare("bM").emblem.shown
  and string.find(PieceSquare("bM").emblem.tex, "UI-PVP-Alliance", 1, true) ~= nil
  and string.find(PieceSquare("rM").emblem.tex, "UI-PVP-Horde", 1, true) ~= nil)
Check("...and the sides take their names", G.ui.against.text and string.find(G.ui.against.text, "You: Alliance", 1, true) ~= nil
  and G:SideName("r") == "Horde", G.ui.against.text)
Check("...the piece set's cells are a quarter of its height (a 4-row atlas)", math.abs(PieceSquare("rM").piece.coords[4]
  - PieceSquare("rM").piece.coords[3] - 0.25) < 0.001)
env.Fire(ps.up, "OnClick", "LeftButton")
Check("...Goblins vs Gnomes: gears and coins, no emblems", G.db.pieceSet == "goblin"
  and string.find(PieceSquare("rM").piece.tex, "BoardPiecesGoblin", 1, true) ~= nil and not PieceSquare("rM").emblem.shown
  and G:SideName("b") == "Gnomes" and not ps.up.enabled)
env.Fire(ps.down, "OnClick", "LeftButton"); env.Fire(ps.down, "OnClick", "LeftButton")
Check("...and back to Classic", G.db.pieceSet == "classic" and PieceSquare("bM").piece.tex == ns.BoardKit.ATLAS
  and G:SideName("b") == "Black")
G.ui.options:Hide()
Check("chess has the same three sets", table.getn(ns.games.chess:PieceSets()) == 3
  and ns.games.chess:PieceSets()[2].names.w == "Alliance" and ns.games.chess:PieceSets()[3].names.b == "Goblins")
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
Check("Resign asks first, and can't be confirmed for 3 seconds", G.S.game ~= nil and H.Find("Resign? 3") ~= nil
  and not H.Find("Resign? 3").enabled)
H.Tick(1.5)
Check("...it counts down", H.Find("Resign? 2") ~= nil and H.Find("Confirm") == nil)
H.Tick(1.6)
Check("...then Confirm", H.Find("Confirm") ~= nil and H.Find("Confirm").enabled and G.S.game ~= nil)
Check("the Resign button has a red wash the Play button doesn't", G.ui.resign.wash ~= nil and G.ui.resign.wash.shown
  and rawget(G.ui.go, "wash") == nil)
H.Tick(6)
Check("left alone, it goes back to Resign", H.Find("Resign") ~= nil and G.S.game ~= nil)
-- the wait is set in Options > Settings
G.ui.options:Show()
H.Press("Settings")
local rs = G.ui.options.resignStep
Check("Options > Settings: Resign's wait, 3 seconds to start", rs ~= nil and rs.text.text == "3 seconds")
env.Fire(rs.down, "OnClick", "LeftButton"); env.Fire(rs.down, "OnClick", "LeftButton")
Check("...step it down to 1 second (saved)", rs.text.text == "1 second" and G.db.resignDelay == 1)
env.Fire(rs.down, "OnClick", "LeftButton")
Check("...or no wait at all, and no lower", rs.text.text == "No wait" and G.db.resignDelay == 0 and not rs.down.enabled)
env.Fire(rs.up, "OnClick", "LeftButton")
G.ui.options:Hide()
H.Press("Resign")
Check("with 1 second, it asks with a 1", H.Find("Resign? 1") ~= nil)
H.Tick(1.1)
Check("...and Confirm works after a second", H.Find("Confirm") ~= nil and H.Find("Confirm").enabled)
H.Tick(6)
G.db.resignDelay = 0
H.Press("Resign")
Check("with no wait, Confirm works at once", H.Find("Confirm") ~= nil and H.Find("Confirm").enabled and G.S.game ~= nil)
H.Tick(6)
G.db.resignDelay = nil
H.Press("Resign")
H.Tick(3.1)
H.Press("Confirm")
Check("Resign loses the game (and the stake)", G.S.game == nil and G.db.stats.losses == 1 and ns.db.chips == before - 50)
Check("...and the last position stays on the board, with Play again and Setup", G.S.over ~= nil
  and not G.ui.intro:IsShown() and H.Find("Play again for 50") ~= nil and H.Find("< Setup") ~= nil)
H.Press("< Setup")
Check("Setup goes back to the intro: stake, level, side and Play", G.ui.intro:IsShown()
  and H.Find("Play for 50") ~= nil and G.ui.stake.shown and H.Find("Challenge the group") ~= nil)
H.Press("Play for 50")
H.Press("Resign"); H.Tick(3.1); H.Press("Confirm")
before = ns.db.chips + 0

-- a double jump, clicked square by square, wins the game and pays double
local function Board(list, turn)
  local sq = {}
  for i = 1, 64 do sq[i] = false end
  for n, piece in pairs(list) do sq[KSq(n)] = piece end
  return { sq = sq, turn = turn, quiet = 0 }
end
before = ns.db.chips
H.Press("Play again for 50")
Check("Play again starts the next game straight from the field", G.S.game ~= nil and not G.ui.intro:IsShown())
g = G.S.game
g.pos = Board({ [14] = "bM", [18] = "rM", [26] = "rM" }, "b")
G:Refresh()
local function Shown(list) local n = 0 for _, t in ipairs(list) do if t.shown then n = n + 1 end end return n end
Check("on your turn, a piece that can capture is marked", G.ui.squares[KSq(14)].can.shown
  and not G.ui.squares[KSq(18)].can.shown)
Click(KSq(14))
Check("picking it draws the capture as a dashed path...", Shown(G.ui.dots) > 20, Shown(G.ui.dots))
Check("...and marks both pieces it would take", G.ui.squares[KSq(18)].threat.shown and G.ui.squares[KSq(26)].threat.shown
  and not G.ui.squares[KSq(14)].threat.shown)
Click(KSq(23))
Check("the first hop of a double jump waits for the next", table.getn(g.moves) == 0 and G.S.sel ~= nil
  and table.getn(G.S.sel) == 2 and Dots() == 1)
Click(KSq(30))
Check("the second hop finishes it, takes both pieces, and wins", G.S.game == nil and G.db.stats.wins == 1)
Check("the capture just made stays as a dotted path, with a dot on each of its three squares",
  Shown(G.ui.dots) > 12 and not G.ui.squares[KSq(18)].threat.shown, Shown(G.ui.dots))
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
H.Tick(3.1)
H.Press("Confirm")
Check("Resign ends it as a loss", CH.S.game == nil and CH.db.stats.losses == 1 and ns.db.chips == before - 50)

---------------------------------------------------------------------------
-- Party chess
---------------------------------------------------------------------------
local party = H.Party({ game = "chess", object = function(ns) return ns.games.chess end })
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
Check("Chess opens on the intro: Vs the computer, and Challenge the group", host.P.ui.intro:IsShown()
  and FindIn(host, "Challenge the group") ~= nil and FindIn(host, "Play for 50") ~= nil)
local hostChips = host.ns.db.chips
PressIn(host, "Challenge the group")
Run(1)
local grow = guest.P.ui.intro.rows[1]
Check("a challenge shows on the other player's intro", grow.shown
  and string.find(grow.text.text, "Host (plays White)", 1, true) ~= nil, grow.text.text)
Check("...while it's open, the host can't start a solo game", not FindIn(host, "Play for 50").enabled
  and FindIn(host, "Withdraw challenge") ~= nil)
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

-- capture paths in chess
local function NewGame()
  for _, c in ipairs({ host, guest }) do if not c.P.ui.intro:IsShown() then c.ns:Back() end end
  PressIn(host, "Challenge the group")
  Run(1)
  PressIn(guest, "Accept")
  Run(1)
  return host.P.S.game, guest.P.S.game
end
local function DotsShown(c) local n = 0 for _, t in ipairs(c.P.ui.dots) do if t.shown then n = n + 1 end end return n end
hg, gg = NewGame()
Move(host, "e2", "e4")
Check("a plain move gets a dot where it started and where it ended (no line)", DotsShown(host) == 4 and DotsShown(guest) == 4,
  DotsShown(guest))
Move(guest, "d7", "d5")
Check("chess: the pawn that can take is marked", host.P.ui.squares[Sq("e4")].can.shown
  and not host.P.ui.squares[Sq("d2")].can.shown)
host.env.Fire(host.P.ui.squares[Sq("e4")], "OnClick", "LeftButton")
Check("picking it shows a dashed path to the pawn it can take", DotsShown(host) > 0
  and host.P.ui.squares[Sq("d5")].threat.shown, DotsShown(host))
host.env.Fire(host.P.ui.squares[Sq("d5")], "OnClick", "LeftButton")
Run(1)
Check("after exd5, both boards show the capture as a dotted path", DotsShown(host) > 0 and DotsShown(guest) > 0
  and not host.P.ui.squares[Sq("d5")].threat.shown)
local function Icons(c, k) local n = 0 for _, t in ipairs(c.P.ui.taken[k].icons) do if t.shown then n = n + 1 end end return n end
Check("captured pieces: the pawn shows under what the taker took, with +1", Icons(host, 2) == 1 and Icons(host, 1) == 0
  and string.find(host.P.ui.taken[2].lead.text, "+1", 1, true) ~= nil)
Check("...and on the other board, as taken from them", Icons(guest, 1) == 1 and Icons(guest, 2) == 0
  and string.find(guest.P.ui.taken[1].lead.text, "+1", 1, true) ~= nil)
Move(guest, "d8", "d5")
Check("taking back evens it: a pawn each, no lead", Icons(host, 1) == 1 and Icons(host, 2) == 1
  and host.P.ui.taken[1].lead.text == "" and host.P.ui.taken[2].lead.text == "")
host.env.Fire(host.P.ui.squares[Sq("b1")], "OnClick", "LeftButton")
Check("a piece with no capture shows no path", DotsShown(host) == 0 and not host.P.ui.squares[Sq("c3")].threat.shown)
PressIn(host, "Resign")
Run(3.1)
PressIn(host, "Confirm")
Run(1)

-- a draw offer
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
Run(3.1)
PressIn(guest, "Confirm")
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
Run(3.1)
PressIn(host, "Confirm")
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
Run(3.1)
PressIn(host, "Confirm")
Check("...which ends the game without a result (not counted)", host.P.S.game == nil and host.P.db.stats.games == 5,
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
