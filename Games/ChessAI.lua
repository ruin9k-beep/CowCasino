-- CowCasino: the chess computer (Easy, Medium and Hard), for ChessRules.
-- ChessRules stays the referee; this keeps a faster board of its own for
-- searching: moves are made and taken back in place, attacks are found
-- from tables worked out once, and pieces are looked up rather than parsed.
--
-- The search: alpha-beta to a fixed depth, captures first (most valuable
-- victim, least valuable attacker), two "killer" quiet moves per ply, and a
-- capture-only search at the end so it never stops halfway through a trade.
-- A position is judged on material plus the usual square tables (knights
-- in the middle, pawns pushed on, the king tucked away until the endgame).
-- Like the checkers computer, it yields every few hundred positions when
-- run in a coroutine, so the game never stalls while it thinks.
local ns = CowCasino.ns
local R = ns.ChessRules

R.LEVELS = {
    { name = "Easy",   depth = 1, quiet = 2, noise = 90 },
    { name = "Medium", depth = 2, quiet = 4, noise = 18 },
    { name = "Hard",   depth = 3, quiet = 8, noise = 0 },
}

local MATE = 100000
local YIELD_EVERY = 120

---------------------------------------------------------------------------
-- Tables worked out once
---------------------------------------------------------------------------
local SIDE, KIND = {}, {}
for _, side in ipairs({ "w", "b" }) do
    for _, kind in ipairs({ "P", "N", "B", "R", "Q", "K" }) do
        SIDE[side .. kind], KIND[side .. kind] = side, kind
    end
end
local OTHER = { w = "b", b = "w" }
local VALUE = { P = 100, N = 320, B = 330, R = 500, Q = 900, K = 0 }

local function RankFile(s) return math.floor((s - 1) / 8), ns.Mod(s - 1, 8) end
local function Sq(rank, file)
    if rank < 0 or rank > 7 or file < 0 or file > 7 then return nil end
    return rank * 8 + file + 1
end

local KNIGHT, KING, RAYS, PAWN_FROM = {}, {}, {}, { w = {}, b = {} }
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }   -- 1-4 straight, 5-8 diagonal
for s = 1, 64 do
    local rank, file = RankFile(s)
    KNIGHT[s], KING[s], RAYS[s] = {}, {}, {}
    for _, d in ipairs({ { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } }) do
        local t = Sq(rank + d[1], file + d[2])
        if t then table.insert(KNIGHT[s], t) end
    end
    for i, d in ipairs(DIRS) do
        local t = Sq(rank + d[1], file + d[2])
        if t then table.insert(KING[s], t) end
        local ray, r, f = {}, rank + d[1], file + d[2]
        while Sq(r, f) do
            table.insert(ray, Sq(r, f))
            r, f = r + d[1], f + d[2]
        end
        RAYS[s][i] = ray
    end
    -- the squares a pawn of each side would attack s from
    PAWN_FROM.w[s], PAWN_FROM.b[s] = {}, {}
    for _, df in ipairs({ -1, 1 }) do
        local a = Sq(rank - 1, file + df)
        if a then table.insert(PAWN_FROM.w[s], a) end
        local b = Sq(rank + 1, file + df)
        if b then table.insert(PAWN_FROM.b[s], b) end
    end
end

-- Square tables, from White's side (rank 8 first, as they're usually
-- written); Black reads them upside down.
local PST_SRC = {
    P = { 0, 0, 0, 0, 0, 0, 0, 0,  50, 50, 50, 50, 50, 50, 50, 50,  10, 10, 20, 30, 30, 20, 10, 10,
          5, 5, 10, 25, 25, 10, 5, 5,  0, 0, 0, 20, 20, 0, 0, 0,  5, -5, -10, 0, 0, -10, -5, 5,
          5, 10, 10, -20, -20, 10, 10, 5,  0, 0, 0, 0, 0, 0, 0, 0 },
    N = { -50, -40, -30, -30, -30, -30, -40, -50,  -40, -20, 0, 0, 0, 0, -20, -40,  -30, 0, 10, 15, 15, 10, 0, -30,
          -30, 5, 15, 20, 20, 15, 5, -30,  -30, 0, 15, 20, 20, 15, 0, -30,  -30, 5, 10, 15, 15, 10, 5, -30,
          -40, -20, 0, 5, 5, 0, -20, -40,  -50, -40, -30, -30, -30, -30, -40, -50 },
    B = { -20, -10, -10, -10, -10, -10, -10, -20,  -10, 0, 0, 0, 0, 0, 0, -10,  -10, 0, 5, 10, 10, 5, 0, -10,
          -10, 5, 5, 10, 10, 5, 5, -10,  -10, 0, 10, 10, 10, 10, 0, -10,  -10, 10, 10, 10, 10, 10, 10, -10,
          -10, 5, 0, 0, 0, 0, 5, -10,  -20, -10, -10, -10, -10, -10, -10, -20 },
    R = { 0, 0, 0, 0, 0, 0, 0, 0,  5, 10, 10, 10, 10, 10, 10, 5,  -5, 0, 0, 0, 0, 0, 0, -5,  -5, 0, 0, 0, 0, 0, 0, -5,
          -5, 0, 0, 0, 0, 0, 0, -5,  -5, 0, 0, 0, 0, 0, 0, -5,  -5, 0, 0, 0, 0, 0, 0, -5,  0, 0, 0, 5, 5, 0, 0, 0 },
    Q = { -20, -10, -10, -5, -5, -10, -10, -20,  -10, 0, 0, 0, 0, 0, 0, -10,  -10, 0, 5, 5, 5, 5, 0, -10,
          -5, 0, 5, 5, 5, 5, 0, -5,  0, 0, 5, 5, 5, 5, 0, -5,  -10, 5, 5, 5, 5, 5, 0, -10,
          -10, 0, 5, 0, 0, 0, 0, -10,  -20, -10, -10, -5, -5, -10, -10, -20 },
    K = { -30, -40, -40, -50, -50, -40, -40, -30,  -30, -40, -40, -50, -50, -40, -40, -30,  -30, -40, -40, -50, -50, -40, -40, -30,
          -30, -40, -40, -50, -50, -40, -40, -30,  -20, -30, -30, -40, -40, -30, -30, -20,  -10, -20, -20, -20, -20, -20, -20, -10,
          20, 20, 0, 0, 0, 0, 20, 20,  20, 30, 10, 0, 0, 10, 30, 20 },
    E = { -50, -40, -30, -20, -20, -30, -40, -50,  -30, -20, -10, 0, 0, -10, -20, -30,  -30, -10, 20, 30, 30, 20, -10, -30,
          -30, -10, 30, 40, 40, 30, -10, -30,  -30, -10, 30, 40, 40, 30, -10, -30,  -30, -10, 20, 30, 30, 20, -10, -30,
          -30, -30, 0, 0, 0, 0, -30, -30,  -50, -30, -30, -30, -30, -30, -30, -50 },   -- the king, in the endgame
}
-- PST[side][kind][square], with the material value in
local PST = { w = {}, b = {} }
for kind, src in pairs(PST_SRC) do
    PST.w[kind], PST.b[kind] = {}, {}
    local value = VALUE[kind] or 0
    for s = 1, 64 do
        local rank, file = RankFile(s)
        PST.w[kind][s] = value + src[(7 - rank) * 8 + file + 1]
        PST.b[kind][s] = value + src[rank * 8 + file + 1]
    end
end

---------------------------------------------------------------------------
-- The search board
---------------------------------------------------------------------------
local function NewBoard(pos)
    local B = { sq = {}, turn = pos.turn, castle = pos.castle, ep = pos.ep, king = {} }
    for s = 1, 64 do
        local p = pos.sq[s]
        B.sq[s] = p
        if p and KIND[p] == "K" then B.king[SIDE[p]] = s end
    end
    return B
end

local function Attacked(B, s, by)
    local sq = B.sq
    local pawn, knight, king = by .. "P", by .. "N", by .. "K"
    local rook, bishop, queen = by .. "R", by .. "B", by .. "Q"
    for _, a in ipairs(PAWN_FROM[by][s]) do if sq[a] == pawn then return true end end
    for _, a in ipairs(KNIGHT[s]) do if sq[a] == knight then return true end end
    for _, a in ipairs(KING[s]) do if sq[a] == king then return true end end
    local rays = RAYS[s]
    for i = 1, 8 do
        local slider = (i <= 4) and rook or bishop
        for _, t in ipairs(rays[i]) do
            local p = sq[t]
            if p then
                if p == slider or p == queen then return true end
                break
            end
        end
    end
    return false
end

local function Add(out, B, f, t, promo, special, capSq)
    local cap = capSq or t
    local victim = B.sq[cap] or nil
    local order = 0
    if victim then order = 10 * VALUE[KIND[victim]] - VALUE[KIND[B.sq[f]]] / 10 + 10000 end
    if promo then order = order + VALUE[promo] + 9000 end
    table.insert(out, { f = f, t = t, promo = promo, special = special, cap = victim and cap or nil, order = order })
end

-- Moves that follow the pieces' rules (the king may be left in check:
-- the search skips those). capturesOnly: captures and promotions.
local function Gen(B, capturesOnly)
    local out, sq, side = {}, B.sq, B.turn
    local opp = OTHER[side]
    for s = 1, 64 do
        local p = sq[s]
        if p and SIDE[p] == side then
            local kind = KIND[p]
            if kind == "P" then
                local rank, file = RankFile(s)
                local dir, start, last = 1, 1, 7
                if side == "b" then dir, start, last = -1, 6, 0 end
                local ahead = Sq(rank + dir, file)
                if ahead and not sq[ahead] then
                    if rank + dir == last then
                        for _, q in ipairs({ "Q", "N", "R", "B" }) do Add(out, B, s, ahead, q) end
                    elseif not capturesOnly then
                        Add(out, B, s, ahead)
                        local two = Sq(rank + 2 * dir, file)
                        if rank == start and not sq[two] then Add(out, B, s, two, nil, "double") end
                    end
                end
                for _, df in ipairs({ -1, 1 }) do
                    local t = Sq(rank + dir, file + df)
                    if t then
                        if sq[t] and SIDE[sq[t]] == opp then
                            if rank + dir == last then
                                for _, q in ipairs({ "Q", "N", "R", "B" }) do Add(out, B, s, t, q) end
                            else
                                Add(out, B, s, t)
                            end
                        elseif t == B.ep then
                            Add(out, B, s, t, nil, "ep", Sq(rank, file + df))
                        end
                    end
                end
            elseif kind == "N" or kind == "K" then
                for _, t in ipairs(kind == "N" and KNIGHT[s] or KING[s]) do
                    local q = sq[t]
                    if q then
                        if SIDE[q] == opp then Add(out, B, s, t) end
                    elseif not capturesOnly then
                        Add(out, B, s, t)
                    end
                end
            else
                local first, last = 1, 8
                if kind == "R" then last = 4 elseif kind == "B" then first = 5 end
                local rays = RAYS[s]
                for i = first, last do
                    for _, t in ipairs(rays[i]) do
                        local q = sq[t]
                        if q then
                            if SIDE[q] == opp then Add(out, B, s, t) end
                            break
                        end
                        if not capturesOnly then Add(out, B, s, t) end
                    end
                end
            end
        end
    end
    if not capturesOnly then
        local home = side == "w" and 0 or 7
        local k = home * 8 + 5
        if B.king[side] == k and not Attacked(B, k, opp) then
            local kr, qr = (side == "w") and "K" or "k", (side == "w") and "Q" or "q"
            if string.find(B.castle, kr, 1, true) and sq[k + 3] == side .. "R" and not sq[k + 1] and not sq[k + 2]
                and not Attacked(B, k + 1, opp) and not Attacked(B, k + 2, opp) then
                Add(out, B, k, k + 2, nil, "short")
            end
            if string.find(B.castle, qr, 1, true) and sq[k - 4] == side .. "R" and not sq[k - 1] and not sq[k - 2]
                and not sq[k - 3] and not Attacked(B, k - 1, opp) and not Attacked(B, k - 2, opp) then
                Add(out, B, k, k - 2, nil, "long")
            end
        end
    end
    return out
end

local RIGHTS = { [5] = "KQ", [61] = "kq", [8] = "K", [1] = "Q", [64] = "k", [57] = "q" }
local function DropRights(castle, s)
    local lose = RIGHTS[s]
    if not lose or castle == "" then return castle end
    for i = 1, string.len(lose) do castle = string.gsub(castle, string.sub(lose, i, i), "") end
    return castle
end

-- Makes a move in place; returns what Unmake needs.
local function Make(B, m)
    local sq = B.sq
    local piece = sq[m.f]
    local side = B.turn
    local undo = { piece = piece, victim = m.cap and sq[m.cap] or false, castle = B.castle, ep = B.ep }
    if m.cap then sq[m.cap] = false end
    sq[m.f] = false
    sq[m.t] = m.promo and (side .. m.promo) or piece
    if m.special == "short" then sq[m.t + 1], sq[m.t - 1] = false, side .. "R"
    elseif m.special == "long" then sq[m.t - 2], sq[m.t + 1] = false, side .. "R" end
    if KIND[piece] == "K" then B.king[side] = m.t end
    B.castle = DropRights(DropRights(B.castle, m.f), m.t)
    B.ep = nil
    if m.special == "double" then B.ep = (m.f + m.t) / 2 end
    B.turn = OTHER[side]
    return undo
end

local function Unmake(B, m, undo)
    local sq = B.sq
    B.turn = OTHER[B.turn]
    local side = B.turn
    sq[m.f] = undo.piece
    sq[m.t] = false
    if m.cap then sq[m.cap] = undo.victim end
    if m.special == "short" then sq[m.t + 1], sq[m.t - 1] = side .. "R", false
    elseif m.special == "long" then sq[m.t - 2], sq[m.t + 1] = side .. "R", false end
    if KIND[undo.piece] == "K" then B.king[side] = m.f end
    B.castle, B.ep = undo.castle, undo.ep
end

-- From the side to move's point of view.
local function Evaluate(B)
    local sq = B.sq
    local score, heavy = 0, 0
    for s = 1, 64 do
        local p = sq[s]
        if p then
            local k = KIND[p]
            if k == "Q" then heavy = heavy + 2 elseif k == "R" or k == "B" or k == "N" then heavy = heavy + 1 end
        end
    end
    local endgame = heavy <= 4                      -- queens off, few pieces left
    for s = 1, 64 do
        local p = sq[s]
        if p then
            local side, k = SIDE[p], KIND[p]
            if k == "K" and endgame then k = "E" end
            local v = PST[side][k][s]
            if side == B.turn then score = score + v else score = score - v end
        end
    end
    return score
end

local function ByOrder(a, b) return a.order > b.order end

-- Captures only, until the position is quiet. In check, every move counts
-- (so a mate at the end of a line is seen).
local function Quiesce(B, alpha, beta, ctx, depth, ply)
    ctx.nodes = ctx.nodes + 1
    if ctx.yield and ns.Mod(ctx.nodes, YIELD_EVERY) == 0 then coroutine.yield() end
    local side = B.turn
    local inCheck = Attacked(B, B.king[side], OTHER[side])
    if not inCheck then
        local stand = Evaluate(B)
        if stand >= beta then return beta end
        if stand > alpha then alpha = stand end
        if depth <= 0 then return alpha end
    end
    local moves = Gen(B, not inCheck)
    table.sort(moves, ByOrder)
    local legal = 0
    for _, m in ipairs(moves) do
        local undo = Make(B, m)
        if not Attacked(B, B.king[side], B.turn) then
            legal = legal + 1
            local v = -Quiesce(B, -beta, -alpha, ctx, depth - 1, ply + 1)
            Unmake(B, m, undo)
            if v >= beta then return beta end
            if v > alpha then alpha = v end
        else
            Unmake(B, m, undo)
        end
    end
    if inCheck and legal == 0 then return -MATE + ply end
    return alpha
end

local function Search(B, depth, alpha, beta, ctx, ply)
    if depth <= 0 then return Quiesce(B, alpha, beta, ctx, ctx.quiet, ply) end
    ctx.nodes = ctx.nodes + 1
    if ctx.yield and ns.Mod(ctx.nodes, YIELD_EVERY) == 0 then coroutine.yield() end
    local moves = Gen(B, false)
    local killers = ctx.killers[ply]
    if killers then
        for _, m in ipairs(moves) do
            if m.order == 0 then
                for i, k in ipairs(killers) do
                    if k.f == m.f and k.t == m.t then m.order = 5000 - i end
                end
            end
        end
    end
    table.sort(moves, ByOrder)
    local side, legal = B.turn, 0
    for _, m in ipairs(moves) do
        local undo = Make(B, m)
        if not Attacked(B, B.king[side], B.turn) then
            legal = legal + 1
            local v = -Search(B, depth - 1, -beta, -alpha, ctx, ply + 1)
            Unmake(B, m, undo)
            if v >= beta then
                if not m.cap then
                    ctx.killers[ply] = { m, killers and killers[1] }
                end
                return beta
            end
            if v > alpha then alpha = v end
        else
            Unmake(B, m, undo)
        end
    end
    if legal == 0 then
        if Attacked(B, B.king[side], OTHER[side]) then return -MATE + ply end
        return 0
    end
    return alpha
end

-- The computer's move (one of R.Moves(pos)). level: 1 Easy, 2 Medium,
-- 3 Hard. With yield set, call it from a coroutine.
function R.ChooseMove(pos, level, yield)
    local L = R.LEVELS[level] or R.LEVELS[2]
    local legal = R.Moves(pos)
    if ns.getn(legal) <= 1 then return legal[1] end
    local B = NewBoard(pos)
    local ctx = { nodes = 0, yield = yield, quiet = L.quiet, killers = {} }
    local moves = Gen(B, false)
    table.sort(moves, ByOrder)
    local side = B.turn
    local best, bestV = {}, -MATE * 2
    for _, m in ipairs(moves) do
        local undo = Make(B, m)
        if not Attacked(B, B.king[side], B.turn) then
            -- with no noise, only a move at least as good as the best so far matters
            local floor = (L.noise > 0 or bestV <= -MATE) and -MATE * 2 or bestV - 1
            local v = -Search(B, L.depth - 1, -MATE * 2, -floor, ctx, 1)
            if L.noise > 0 then v = v + math.random(-L.noise, L.noise) end
            if v > bestV then best, bestV = { m }, v
            elseif v == bestV then table.insert(best, m) end
        end
        Unmake(B, m, undo)
    end
    local pick = best[math.random(1, ns.getn(best))]
    -- hand back the referee's own move
    for _, m in ipairs(legal) do
        if m.from == pick.f and m.to == pick.t and m.promo == pick.promo then return m end
    end
    return legal[1]
end

R.Evaluate = function(pos) return Evaluate(NewBoard(pos)) end

-- For tests: counts the search board's legal move sequences (should match
-- the referee's).
function R.SearchPerft(pos, depth)
    local B = NewBoard(pos)
    local function Count(d)
        if d == 0 then return 1 end
        local n, side = 0, B.turn
        for _, m in ipairs(Gen(B, false)) do
            local undo = Make(B, m)
            if not Attacked(B, B.king[side], B.turn) then n = n + Count(d - 1) end
            Unmake(B, m, undo)
        end
        return n
    end
    return Count(depth)
end
