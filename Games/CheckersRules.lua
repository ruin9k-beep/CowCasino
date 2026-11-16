-- CowCasino: Checkers rules (American checkers / English draughts), for
-- the board kit. Black moves first. Men move one square diagonally forward;
-- kings move one square any diagonal way. Jumps are compulsory and a jump
-- keeps going while it can, but men only jump forward. A man that reaches
-- the far row is crowned, and that ends its move. You lose when you can't
-- move (no pieces left, or all blocked). Forty moves each with no capture
-- and no man moved is a draw.
--
-- Squares are 1..64: (row * 8 + col + 1), row 0 is Black's back row, col 0
-- is the a-file. Pieces: "bM", "bK", "rM", "rK".
local ns = CowCasino.ns

local R = { first = "b", sides = { "b", "r" }, names = { b = "Black", r = "Red" } }
ns.CheckersRules = R

local QUIET_DRAW = 80          -- plies with no capture or man move

local function Sq(row, col) return row * 8 + col + 1 end
local function RowCol(s) return math.floor((s - 1) / 8), ns.Mod(s - 1, 8) end
local function Other(side) if side == "b" then return "r" end return "b" end
R.Other = Other

local function Copy(pos)
    local sq = {}
    for i = 1, 64 do sq[i] = pos.sq[i] end
    return { sq = sq, turn = pos.turn, quiet = pos.quiet }
end

function R.New()
    local sq = {}
    for i = 1, 64 do sq[i] = false end
    for row = 0, 7 do
        for col = 0, 7 do
            if ns.Mod(row + col, 2) == 0 then
                if row <= 2 then sq[Sq(row, col)] = "bM" elseif row >= 5 then sq[Sq(row, col)] = "rM" end
            end
        end
    end
    return { sq = sq, turn = "b", quiet = 0 }
end

-- The diagonal directions a piece may go: {drow, dcol}
local UP   = { { 1, -1 }, { 1, 1 } }
local DOWN = { { -1, -1 }, { -1, 1 } }
local ALL  = { { 1, -1 }, { 1, 1 }, { -1, -1 }, { -1, 1 } }
local function Dirs(piece)
    if string.sub(piece, 2, 2) == "K" then return ALL end
    if string.sub(piece, 1, 1) == "b" then return UP end
    return DOWN
end
local function CrownRow(side) if side == "b" then return 7 end return 0 end

-- Every jump sequence from `from` (captured squares stay on the board until
-- the move is done, so they can't be jumped twice or landed on).
local function Jumps(pos, from, piece, path, caps, out)
    local side = string.sub(piece, 1, 1)
    local row, col = RowCol(path[ns.getn(path)])
    local found = false
    for _, d in ipairs(Dirs(piece)) do
        local mr, mc, lr, lc = row + d[1], col + d[2], row + 2 * d[1], col + 2 * d[2]
        if lr >= 0 and lr <= 7 and lc >= 0 and lc <= 7 then
            local mid, land = Sq(mr, mc), Sq(lr, lc)
            local victim = pos.sq[mid]
            local taken = false
            for _, c in ipairs(caps) do if c == mid then taken = true end end
            if victim and string.sub(victim, 1, 1) ~= side and not taken
                and (not pos.sq[land] or land == from) then
                found = true
                local p2, c2 = {}, {}
                for i, v in ipairs(path) do p2[i] = v end
                for i, v in ipairs(caps) do c2[i] = v end
                table.insert(p2, land); table.insert(c2, mid)
                if string.sub(piece, 2, 2) == "M" and lr == CrownRow(side) then
                    table.insert(out, { path = p2, caps = c2 })         -- crowned: the move ends
                else
                    Jumps(pos, from, piece, p2, c2, out)
                end
            end
        end
    end
    if not found and ns.getn(caps) > 0 then table.insert(out, { path = path, caps = caps }) end
end

-- The legal moves for the side to move: { path = {from, ...}, caps = {...} }.
-- Jumps first: when there is one, only jumps are legal.
function R.Moves(pos)
    local side, jumps, steps = pos.turn, {}, {}
    for s = 1, 64 do
        local piece = pos.sq[s]
        if piece and string.sub(piece, 1, 1) == side then
            local n = ns.getn(jumps)
            Jumps(pos, s, piece, { s }, {}, jumps)
            if ns.getn(jumps) == n and ns.getn(jumps) == 0 then
                local row, col = RowCol(s)
                for _, d in ipairs(Dirs(piece)) do
                    local r2, c2 = row + d[1], col + d[2]
                    if r2 >= 0 and r2 <= 7 and c2 >= 0 and c2 <= 7 and not pos.sq[Sq(r2, c2)] then
                        table.insert(steps, { path = { s, Sq(r2, c2) }, caps = {} })
                    end
                end
            end
        end
    end
    if ns.getn(jumps) > 0 then return jumps end
    return steps
end

function R.Apply(pos, m)
    local p = Copy(pos)
    local from, to = m.path[1], m.path[ns.getn(m.path)]
    local piece = p.sq[from]
    p.sq[from] = false
    for _, c in ipairs(m.caps) do p.sq[c] = false end
    local side = string.sub(piece, 1, 1)
    local row = RowCol(to)
    if string.sub(piece, 2, 2) == "M" and row == CrownRow(side) then piece = side .. "K" end
    p.sq[to] = piece
    if ns.getn(m.caps) > 0 or string.sub(pos.sq[from], 2, 2) == "M" then p.quiet = 0 else p.quiet = pos.quiet + 1 end
    p.turn = Other(pos.turn)
    return p
end

-- nil while the game goes on, or winner ("b", "r" or "draw") and why.
function R.Result(pos, moves)
    moves = moves or R.Moves(pos)
    if ns.getn(moves) == 0 then
        local any = false
        for s = 1, 64 do
            if pos.sq[s] and string.sub(pos.sq[s], 1, 1) == pos.turn then any = true end
        end
        return Other(pos.turn), any and "no moves left" or "no pieces left"
    end
    if pos.quiet >= QUIET_DRAW then return "draw", "forty moves without a capture" end
    return nil
end

-- The standard 1-32 numbering: 1-4 on Black's back row.
local function Num(s)
    local row, col = RowCol(s)
    return row * 4 + math.floor((7 - col) / 2) + 1
end
R.Num = Num

function R.MoveText(pos, m)
    local parts = {}
    for _, s in ipairs(m.path) do table.insert(parts, Num(s)) end
    return table.concat(parts, ns.getn(m.caps) > 0 and "x" or "-")
end

-- Over the wire: the path as two-digit squares ("1120").
function R.Encode(m)
    local t = {}
    for _, s in ipairs(m.path) do table.insert(t, string.format("%02d", s)) end
    return table.concat(t)
end

function R.Same(a, b)
    if ns.getn(a.path) ~= ns.getn(b.path) then return false end
    for i, s in ipairs(a.path) do if b.path[i] ~= s then return false end end
    return true
end

function R.PieceAt(pos, s) return pos.sq[s] or nil end
function R.SideOf(piece) return string.sub(piece, 1, 1) end
function R.Dark(s) local row, col = RowCol(s) return ns.Mod(row + col, 2) == 0 end

---------------------------------------------------------------------------
-- The computer: alpha-beta search, run a few hundred positions at a time
-- (a coroutine) so the game never stalls.
---------------------------------------------------------------------------
local VALUE = { M = 100, K = 165 }

-- From the side to move's point of view.
function R.Evaluate(pos)
    local score = 0
    for s = 1, 64 do
        local piece = pos.sq[s]
        if piece then
            local side, kind = string.sub(piece, 1, 1), string.sub(piece, 2, 2)
            local row, col = RowCol(s)
            local v = VALUE[kind]
            if kind == "M" then
                local adv = side == "b" and row or (7 - row)
                v = v + adv * 3
                if adv == 0 then v = v + 6 end                         -- guarding the back row
            elseif col >= 2 and col <= 5 and row >= 2 and row <= 5 then
                v = v + 8                                               -- kings like the middle
            end
            if col == 0 or col == 7 then v = v - 3 end
            if side == pos.turn then score = score + v else score = score - v end
        end
    end
    return score
end

local WIN = 100000

-- Negamax with alpha-beta. Jumps at the horizon are played out (up to
-- `extra` more plies) so the search doesn't stop halfway through a trade.
local function Search(pos, depth, alpha, beta, ctx, extra)
    ctx.nodes = ctx.nodes + 1
    if ctx.yield and ns.Mod(ctx.nodes, ctx.every) == 0 then coroutine.yield() end
    local moves = R.Moves(pos)
    if ns.getn(moves) == 0 then return -WIN + ctx.ply end
    if pos.quiet >= QUIET_DRAW then return 0 end
    local forced = ns.getn(moves[1].caps) > 0
    if depth <= 0 and not (forced and extra > 0) then return R.Evaluate(pos) end
    if depth <= 0 then extra = extra - 1 end
    for _, m in ipairs(moves) do
        ctx.ply = ctx.ply + 1
        local v = -Search(R.Apply(pos, m), depth - 1, -beta, -alpha, ctx, extra)
        ctx.ply = ctx.ply - 1
        if v > alpha then alpha = v end
        if alpha >= beta then break end
    end
    return alpha
end

-- The computer's move. level: 1 easy, 2 normal, 3 hard. With yield set,
-- call it from a coroutine: it yields every few hundred positions.
R.LEVELS = { { name = "Easy", depth = 1, slip = 0.35 }, { name = "Medium", depth = 4, slip = 0.05 }, { name = "Hard", depth = 6, slip = 0 } }

function R.ChooseMove(pos, level, yield)
    local L = R.LEVELS[level] or R.LEVELS[2]
    local moves = R.Moves(pos)
    if ns.getn(moves) <= 1 then return moves[1] end
    if math.random() < L.slip then return moves[math.random(1, ns.getn(moves))] end
    local ctx = { nodes = 0, ply = 1, yield = yield, every = 250 }
    local best, bestV = {}, -WIN * 2
    for _, m in ipairs(moves) do
        local v = -Search(R.Apply(pos, m), L.depth - 1, -WIN * 2, -bestV + 1, ctx, 6)
        if v > bestV then best, bestV = { m }, v
        elseif v == bestV then table.insert(best, m) end
    end
    return best[math.random(1, ns.getn(best))]
end
