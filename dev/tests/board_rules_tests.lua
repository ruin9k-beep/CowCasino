-- Chess and Checkers rules: chess move counts against the standard perft
-- positions, notation, every way a game ends, and the checkers rules
-- (compulsory and multiple jumps, crowning, the computer's moves).
local H = dofile("harness.lua")
local Check, Start = H.Check, H.Start
local env, ns = Start(nil)
local C, K = ns.ChessRules, ns.CheckersRules

-- A chess position from FEN (board, side, castling, en passant).
local function FEN(f)
  local _, _, board, turn, castle, ep = string.find(f, "(%S+) (%S+) (%S+) (%S+)")
  local sq = {}
  for i = 1, 64 do sq[i] = false end
  local rank = 7
  for _, row in ipairs(ns.Net.Split(board, "/")) do
    local file = 0
    for i = 1, string.len(row) do
      local ch = string.sub(row, i, i)
      if string.find(ch, "%d") then file = file + tonumber(ch)
      else
        sq[rank * 8 + file + 1] = (string.find(ch, "%u") and "w" or "b") .. string.upper(ch)
        file = file + 1
      end
    end
    rank = rank - 1
  end
  local e = nil
  if ep ~= "-" then e = (tonumber(string.sub(ep, 2)) - 1) * 8 + (string.byte(ep, 1) - 97) + 1 end
  return { sq = sq, turn = turn, castle = castle == "-" and "" or castle, ep = e, half = 0, full = 1 }
end

local function Perft(R, pos, d)
  if d == 0 then return 1 end
  local n = 0
  for _, m in ipairs(R.Moves(pos)) do n = n + Perft(R, R.Apply(pos, m), d - 1) end
  return n
end

-- Plays moves given as "e2e4" (or checkers paths "0918"); returns the
-- position, the notation of each move, and the repeat counts.
local function Play(R, pos, list)
  local texts, keys = {}, {}
  if R.Key then keys[R.Key(pos)] = 1 end
  for _, text in ipairs(list) do
    local found
    for _, m in ipairs(R.Moves(pos)) do if R.Encode(m) == text then found = m end end
    assert(found, "not a legal move: " .. text)
    table.insert(texts, R.MoveText(pos, found))
    pos = R.Apply(pos, found)
    if R.Key then keys[R.Key(pos)] = (keys[R.Key(pos)] or 0) + 1 end
  end
  return pos, texts, keys
end

-- Chess: move generation ---------------------------------------------------
Check("chess: 20 moves at the start, 400 after one each, 8,902 after two",
  Perft(C, C.New(), 1) == 20 and Perft(C, C.New(), 2) == 400 and Perft(C, C.New(), 3) == 8902)
local kiwi = FEN("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -")
local n1, n2 = Perft(C, kiwi, 1), Perft(C, kiwi, 2)
Check("chess: the 'Kiwipete' test position (castling, pins, en passant)", n1 == 48 and n2 == 2039, n1 .. ", " .. n2)
local p3 = FEN("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -")
local n3 = Perft(C, p3, 3)
Check("chess: an endgame test position, three moves deep", n3 == 2812, n3)
local p5 = FEN("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ -")
local n5 = Perft(C, p5, 2)
Check("chess: a promotion test position", n5 == 1486, n5)

-- Chess: notation and endings ----------------------------------------------
local pos, texts = Play(C, C.New(), { "f2f3", "e7e5", "g2g4", "d8h4" })
local w, why = C.Result(pos)
Check("fool's mate: Qh4# is checkmate, Black wins", w == "b" and why == "checkmate" and texts[4] == "Qh4#", texts[4])
pos, texts = Play(C, C.New(), { "e2e4", "d7d5", "e4d5", "g8f6", "g1f3", "f6d5", "f1c4", "c8g4", "e1g1" })
Check("notation: e4, exd5, Nf6, Nxd5, Bc4, O-O", texts[1] == "e4" and texts[3] == "exd5" and texts[4] == "Nf6"
  and texts[6] == "Nxd5" and texts[7] == "Bc4" and texts[9] == "O-O", table.concat(texts, " "))
pos, texts = Play(C, FEN("4k3/8/8/8/8/8/8/R3K2R w KQ -"), { "e1c1" })
Check("queenside castling is O-O-O and moves the rook", texts[1] == "O-O-O" and pos.sq[4] == "wR" and pos.sq[3] == "wK")
pos, texts = Play(C, FEN("4k3/8/8/8/8/8/8/R5RK w - -"), { "a1d1" })
Check("two rooks that could go: Rad1", texts[1] == "Rad1", texts[1])
pos, texts = Play(C, FEN("k7/4P3/8/8/8/8/8/4K3 w - -"), { "e7e8q" })
Check("promotion: e8=Q+ makes a queen", texts[1] == "e8=Q+" and pos.sq[61] == "wQ", texts[1])
local promos = 0
for _, m in ipairs(C.Moves(FEN("k7/4P3/8/8/8/8/8/4K3 w - -"))) do if m.promo then promos = promos + 1 end end
Check("...with all four pieces to pick from", promos == 4, promos)
pos, texts = Play(C, FEN("4k3/8/8/3pP3/8/8/8/4K3 w - d6"), { "e5d6" })
Check("en passant: exd6 takes the pawn beside it", texts[1] == "exd6" and pos.sq[36] == false and pos.sq[44] == "wP")
pos = FEN("k7/8/1Q6/8/8/8/8/K7 b - -")
w, why = C.Result(pos)
Check("stalemate is a draw", w == "draw" and why == "stalemate", tostring(why))
w, why = C.Result(FEN("k7/8/8/8/8/8/8/K5B1 w - -"))
Check("king and bishop against king is a draw", w == "draw" and string.find(why, "not enough") ~= nil)
w = C.Result(FEN("k7/8/8/8/8/8/8/K5R1 w - -"))
Check("...king and rook is not", w == nil)
pos, texts, keys = Play(C, C.New(), { "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8" })
w, why = C.Result(pos, nil, keys)
Check("the same position three times is a draw", w == "draw" and string.find(why, "three times") ~= nil, tostring(why))
local castleThrough = FEN("4k3/8/8/8/8/8/5r2/R3K2R w KQ -")
local ok = true
for _, m in ipairs(C.Moves(castleThrough)) do if m.castle and m.to == 7 then ok = false end end
Check("no castling through an attacked square", ok)

-- Checkers ------------------------------------------------------------------
local kpos = K.New()
Check("checkers: Black moves first, with 7 moves", kpos.turn == "b" and table.getn(K.Moves(kpos)) == 7)
local function KSq(n)      -- standard 1-32 number to a square
  for s = 1, 64 do if K.Dark(s) and K.Num(s) == n then return s end end
end
-- a forced jump: after 11-15 23-19, Black must... (play on to a jump)
local function KMove(list)
  local t = {}
  for _, n in ipairs(list) do table.insert(t, string.format("%02d", KSq(n))) end
  return table.concat(t)
end
kpos, texts = Play(K, K.New(), { KMove({ 11, 15 }), KMove({ 22, 18 }) })
local moves = K.Moves(kpos)
Check("a jump is compulsory: Black's only move is 15x22", table.getn(moves) == 1 and K.MoveText(kpos, moves[1]) == "15x22",
  K.MoveText(kpos, moves[1]))

-- a double jump, and crowning ends a jump
local function Board(list, turn)
  local sq = {}
  for i = 1, 64 do sq[i] = false end
  for n, piece in pairs(list) do sq[KSq(n)] = piece end
  return { sq = sq, turn = turn, quiet = 0 }
end
local b = Board({ [14] = "bM", [18] = "rM", [26] = "rM" }, "b")
moves = K.Moves(b)
Check("a double jump is one move: 14x23x30", table.getn(moves) == 1 and K.MoveText(b, moves[1]) == "14x23x30"
  and table.getn(moves[1].caps) == 2, moves[1] and K.MoveText(b, moves[1]))
local after = K.Apply(b, moves[1])
Check("...takes both pieces", after.sq[KSq(18)] == false and after.sq[KSq(26)] == false)
w, why = K.Result(after)
Check("...and with no Red pieces left, Black wins", w == "b" and why == "no pieces left", tostring(why))
b = Board({ [22] = "bM", [26] = "rM", [9] = "rM" }, "b")
moves = K.Moves(b)
after = K.Apply(b, moves[1])
Check("a man jumping onto the far row is crowned there, and stops", table.getn(moves) == 1
  and K.MoveText(b, moves[1]) == "22x31" and after.sq[KSq(31)] == "bK" and after.turn == "r",
  moves[1] and K.MoveText(b, moves[1]))
b = Board({ [18] = "bM", [14] = "rM" }, "b")
local back = false
for _, m in ipairs(K.Moves(b)) do if table.getn(m.caps) > 0 then back = true end end
Check("men don't jump backward", not back)
b = Board({ [18] = "bK", [14] = "rM" }, "b")
moves = K.Moves(b)
Check("kings do", table.getn(moves) == 1 and table.getn(moves[1].caps) == 1)
b = Board({ [1] = "rM", [5] = "bM", [6] = "bM", [9] = "bM", [10] = "bM" }, "r")
w, why = K.Result(b)
Check("a side with pieces but no moves loses", w == "b" and why == "no moves left", tostring(why))

-- the computer
b = Board({ [14] = "bM", [18] = "rM", [26] = "rM", [3] = "bM" }, "b")
local m = K.ChooseMove(b, 2, false)
Check("the computer takes a double jump when it can", m and table.getn(m.caps) == 2)
b = Board({ [10] = "bM", [3] = "bM", [19] = "rM", [21] = "rM", [22] = "rM" }, "b")
local safe = true
for _ = 1, 5 do
  m = K.ChooseMove(b, 3, false)
  local a2 = K.Apply(b, m)
  for _, r in ipairs(K.Moves(a2)) do if table.getn(r.caps) > 0 then safe = false end end
end
Check("Hard doesn't hang a piece when a safe move exists", safe)
local co = coroutine.create(function() return K.ChooseMove(K.New(), 3, true) end)
local yields = 0
while true do
  local _, mv = coroutine.resume(co)
  if coroutine.status(co) == "dead" then m = mv break end
  yields = yields + 1
end
Check("the computer thinks in slices (a coroutine) and still answers", m ~= nil and yields > 0, yields .. " slices")

H.Done("BOARD RULES")
