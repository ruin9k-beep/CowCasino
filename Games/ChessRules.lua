-- CowCasino: Chess rules, for the board kit. The full game: castling, en
-- passant, promotion, check, checkmate and stalemate. Draws: stalemate,
-- the fifty-move rule, the same position three times, and too little
-- material to mate. (The board kit adds draw offers and resigning.)
--
-- Squares are 1..64: (rank * 8 + file + 1), rank 0 is White's back rank,
-- file 0 is the a-file. Pieces: "wK", "wQ", "wR", "wB", "wN", "wP" and the
-- same with "b".
local ns = CowCasino.ns

local R = { first = "w", sides = { "w", "b" }, names = { w = "White", b = "Black" } }
ns.ChessRules = R

local FILES = "abcdefgh"

local function Sq(rank, file) return rank * 8 + file + 1 end
local function RankFile(s) return math.floor((s - 1) / 8), ns.Mod(s - 1, 8) end
local function Other(side) if side == "w" then return "b" end return "w" end
R.Other = Other
local function Name(s)
    local rank, file = RankFile(s)
    return string.sub(FILES, file + 1, file + 1) .. (rank + 1)
end
R.SquareName = Name

local function Copy(pos)
    local sq = {}
    for i = 1, 64 do sq[i] = pos.sq[i] end
    return { sq = sq, turn = pos.turn, castle = pos.castle, ep = pos.ep, half = pos.half, full = pos.full }
end

local BACK = { "R", "N", "B", "Q", "K", "B", "N", "R" }

function R.New()
    local sq = {}
    for i = 1, 64 do sq[i] = false end
    for f = 0, 7 do
        sq[Sq(0, f)] = "w" .. BACK[f + 1]
        sq[Sq(1, f)] = "wP"
        sq[Sq(6, f)] = "bP"
        sq[Sq(7, f)] = "b" .. BACK[f + 1]
    end
    return { sq = sq, turn = "w", castle = "KQkq", ep = nil, half = 0, full = 1 }
end

local KNIGHT = { { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } }
local KING   = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
local ROOK   = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local BISHOP = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function On(rank, file) return rank >= 0 and rank <= 7 and file >= 0 and file <= 7 end

-- Is square s attacked by any piece of side `by`?
local function Attacked(pos, s, by)
    local rank, file = RankFile(s)
    local sq = pos.sq
    -- pawns
    local pr = by == "w" and rank - 1 or rank + 1
    for _, df in ipairs({ -1, 1 }) do
        if On(pr, file + df) and sq[Sq(pr, file + df)] == by .. "P" then return true end
    end
    for _, d in ipairs(KNIGHT) do
        local r, f = rank + d[1], file + d[2]
        if On(r, f) and sq[Sq(r, f)] == by .. "N" then return true end
    end
    for _, d in ipairs(KING) do
        local r, f = rank + d[1], file + d[2]
        if On(r, f) and sq[Sq(r, f)] == by .. "K" then return true end
    end
    for _, set in ipairs({ { ROOK, "R" }, { BISHOP, "B" } }) do
        for _, d in ipairs(set[1]) do
            local r, f = rank + d[1], file + d[2]
            while On(r, f) do
                local p = sq[Sq(r, f)]
                if p then
                    if p == by .. set[2] or p == by .. "Q" then return true end
                    break
                end
                r, f = r + d[1], f + d[2]
            end
        end
    end
    return false
end
R.Attacked = Attacked

local function KingSquare(pos, side)
    for s = 1, 64 do if pos.sq[s] == side .. "K" then return s end end
end

function R.InCheck(pos, side)
    side = side or pos.turn
    local k = KingSquare(pos, side)
    return k ~= nil and Attacked(pos, k, Other(side))
end

-- Moves that obey how the pieces move, before checking the king is safe.
local function Pseudo(pos)
    local out, side, sq = {}, pos.turn, pos.sq
    local function Add(from, to, extra)
        local m = { path = { from, to }, from = from, to = to, piece = sq[from], cap = sq[to] and to or nil }
        if extra then for k, v in pairs(extra) do m[k] = v end end
        table.insert(out, m)
    end
    for s = 1, 64 do
        local p = sq[s]
        if p and string.sub(p, 1, 1) == side then
            local kind = string.sub(p, 2, 2)
            local rank, file = RankFile(s)
            if kind == "P" then
                local dir, start, last = 1, 1, 7
                if side == "b" then dir, start, last = -1, 6, 0 end
                local r = rank + dir
                local function Pawn(to, extra)
                    if r == last then
                        for _, q in ipairs({ "Q", "R", "B", "N" }) do
                            local e = { promo = q }
                            if extra then for k, v in pairs(extra) do e[k] = v end end
                            Add(s, to, e)
                        end
                    else
                        Add(s, to, extra)
                    end
                end
                if On(r, file) and not sq[Sq(r, file)] then
                    Pawn(Sq(r, file))
                    if rank == start and not sq[Sq(r + dir, file)] then Add(s, Sq(r + dir, file), { double = true }) end
                end
                for _, df in ipairs({ -1, 1 }) do
                    if On(r, file + df) then
                        local t = Sq(r, file + df)
                        if sq[t] and string.sub(sq[t], 1, 1) ~= side then
                            Pawn(t)
                        elseif pos.ep == t then
                            Add(s, t, { cap = Sq(rank, file + df), enPassant = true })
                        end
                    end
                end
            elseif kind == "N" or kind == "K" then
                for _, d in ipairs(kind == "N" and KNIGHT or KING) do
                    local r, f = rank + d[1], file + d[2]
                    if On(r, f) then
                        local t = sq[Sq(r, f)]
                        if not t or string.sub(t, 1, 1) ~= side then Add(s, Sq(r, f)) end
                    end
                end
            else
                local dirs = {}
                if kind == "R" or kind == "Q" then for _, d in ipairs(ROOK) do table.insert(dirs, d) end end
                if kind == "B" or kind == "Q" then for _, d in ipairs(BISHOP) do table.insert(dirs, d) end end
                for _, d in ipairs(dirs) do
                    local r, f = rank + d[1], file + d[2]
                    while On(r, f) do
                        local t = sq[Sq(r, f)]
                        if t then
                            if string.sub(t, 1, 1) ~= side then Add(s, Sq(r, f)) end
                            break
                        end
                        Add(s, Sq(r, f))
                        r, f = r + d[1], f + d[2]
                    end
                end
            end
        end
    end
    -- castling: the rights, empty squares between, and the king never in or
    -- passing through check
    local home = side == "w" and 0 or 7
    local k = Sq(home, 4)
    local opp = Other(side)
    if sq[k] == side .. "K" and not Attacked(pos, k, opp) then
        local kRight, qRight = (side == "w") and "K" or "k", (side == "w") and "Q" or "q"
        if string.find(pos.castle, kRight, 1, true) and sq[Sq(home, 7)] == side .. "R"
            and not sq[Sq(home, 5)] and not sq[Sq(home, 6)]
            and not Attacked(pos, Sq(home, 5), opp) and not Attacked(pos, Sq(home, 6), opp) then
            Add(k, Sq(home, 6), { castle = { Sq(home, 7), Sq(home, 5) } })
        end
        if string.find(pos.castle, qRight, 1, true) and sq[Sq(home, 0)] == side .. "R"
            and not sq[Sq(home, 1)] and not sq[Sq(home, 2)] and not sq[Sq(home, 3)]
            and not Attacked(pos, Sq(home, 3), opp) and not Attacked(pos, Sq(home, 2), opp) then
            Add(k, Sq(home, 2), { castle = { Sq(home, 0), Sq(home, 3) } })
        end
    end
    return out
end

local function DropRight(castle, s)
    local lose = ({ [Sq(0, 4)] = "KQ", [Sq(7, 4)] = "kq", [Sq(0, 7)] = "K", [Sq(0, 0)] = "Q", [Sq(7, 7)] = "k", [Sq(7, 0)] = "q" })[s]
    if not lose then return castle end
    for i = 1, string.len(lose) do castle = string.gsub(castle, string.sub(lose, i, i), "") end
    return castle
end

function R.Apply(pos, m)
    local p = Copy(pos)
    local sq = p.sq
    local piece = sq[m.from]
    sq[m.from] = false
    if m.cap then sq[m.cap] = false end
    sq[m.to] = m.promo and (string.sub(piece, 1, 1) .. m.promo) or piece
    if m.castle then
        sq[m.castle[2]] = sq[m.castle[1]]
        sq[m.castle[1]] = false
    end
    p.castle = DropRight(DropRight(pos.castle, m.from), m.to)
    p.ep = nil
    if m.double then p.ep = math.floor((m.from + m.to) / 2) end
    if string.sub(piece, 2, 2) == "P" or m.cap then p.half = 0 else p.half = pos.half + 1 end
    if pos.turn == "b" then p.full = pos.full + 1 end
    p.turn = Other(pos.turn)
    return p
end

-- The legal moves for the side to move.
function R.Moves(pos)
    local out = {}
    for _, m in ipairs(Pseudo(pos)) do
        if not R.InCheck(R.Apply(pos, m), pos.turn) then table.insert(out, m) end
    end
    return out
end

-- A position's key for spotting repeats (the en passant square only counts
-- when a capture there is possible, as the rules say).
function R.Key(pos)
    local t = {}
    for s = 1, 64 do t[s] = pos.sq[s] or "." end
    local ep = "-"
    if pos.ep then
        for _, m in ipairs(R.Moves(pos)) do if m.enPassant then ep = tostring(pos.ep) end end
    end
    return table.concat(t) .. pos.turn .. pos.castle .. ep
end

local function NotEnough(pos)
    local minors, bishops = {}, {}
    for s = 1, 64 do
        local p = pos.sq[s]
        if p then
            local kind = string.sub(p, 2, 2)
            if kind == "P" or kind == "R" or kind == "Q" then return false end
            if kind == "B" or kind == "N" then
                table.insert(minors, p)
                if kind == "B" then
                    local rank, file = RankFile(s)
                    table.insert(bishops, ns.Mod(rank + file, 2))
                end
            end
        end
    end
    local n = ns.getn(minors)
    if n <= 1 then return true end
    -- only bishops, all on the same color of square
    if ns.getn(bishops) == n then
        for i = 2, n do if bishops[i] ~= bishops[1] then return false end end
        return true
    end
    return false
end

-- nil while the game goes on, or winner ("w", "b" or "draw") and why.
-- keys: how many times each position key has been seen (for repeats).
function R.Result(pos, moves, keys)
    moves = moves or R.Moves(pos)
    if ns.getn(moves) == 0 then
        if R.InCheck(pos) then return Other(pos.turn), "checkmate" end
        return "draw", "stalemate"
    end
    if pos.half >= 100 then return "draw", "the fifty-move rule" end
    if keys and (keys[R.Key(pos)] or 0) >= 3 then return "draw", "the same position three times" end
    if NotEnough(pos) then return "draw", "not enough pieces left to checkmate" end
    return nil
end

-- Standard algebraic notation: Nf3, exd5, O-O, e8=Q+, Qxf7#.
function R.MoveText(pos, m)
    local text
    local kind = string.sub(m.piece, 2, 2)
    if m.castle then
        text = (m.to > m.from) and "O-O" or "O-O-O"
    elseif kind == "P" then
        text = m.cap and (string.sub(Name(m.from), 1, 1) .. "x" .. Name(m.to)) or Name(m.to)
        if m.promo then text = text .. "=" .. m.promo end
    else
        -- tell apart two pieces of the same kind that could both go there
        local sameFile, sameRank, other = false, false, false
        for _, o in ipairs(R.Moves(pos)) do
            if o.to == m.to and o.from ~= m.from and o.piece == m.piece then
                other = true
                local r1, f1 = RankFile(o.from)
                local r2, f2 = RankFile(m.from)
                if f1 == f2 then sameFile = true end
                if r1 == r2 then sameRank = true end
            end
        end
        local dis = ""
        if other then
            local name = Name(m.from)
            if not sameFile then dis = string.sub(name, 1, 1)
            elseif not sameRank then dis = string.sub(name, 2, 2)
            else dis = name end
        end
        text = kind .. dis .. (m.cap and "x" or "") .. Name(m.to)
    end
    local after = R.Apply(pos, m)
    if R.InCheck(after) then
        text = text .. ((ns.getn(R.Moves(after)) == 0) and "#" or "+")
    end
    return text
end

-- Over the wire: "e2e4", "e7e8q".
function R.Encode(m)
    return Name(m.from) .. Name(m.to) .. (m.promo and string.lower(m.promo) or "")
end

function R.Same(a, b)
    return a.from == b.from and a.to == b.to and a.promo == b.promo
end

-- Several moves on the same squares (a promotion): what each one is.
function R.ChoiceLabel(m)
    return ({ Q = "Queen", R = "Rook", B = "Bishop", N = "Knight" })[m.promo or ""] or "?"
end

function R.PieceAt(pos, s) return pos.sq[s] or nil end
function R.SideOf(piece) return string.sub(piece, 1, 1) end
function R.Dark(s) local rank, file = RankFile(s) return ns.Mod(rank + file, 2) == 0 end
function R.CheckSquare(pos)
    if R.InCheck(pos) then return KingSquare(pos, pos.turn) end
end
