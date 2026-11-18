-- CowCasino: Battleship rules, and the computer that plays it.
--
-- A 10 x 10 sea. Squares are 1..100: (row * 10 + col + 1), row 0 is the top
-- row (A), col 0 the left column (1), so "B7" is row 1, col 6. Each side has
-- the classic fleet: Carrier 5, Battleship 4, Cruiser 3, Submarine 3 and
-- Destroyer 2, placed in straight lines across or down, not overlapping.
-- Players take turns firing one shot; a ship is sunk when every square of it
-- is hit, and the side that sinks the whole enemy fleet wins.
--
-- A fleet is a list (in FLEET order) of { start = square, down = true/false }
-- (start nil while a ship isn't placed yet).
-- An answer to a shot is "m" (miss), "h" (hit), "s<k>:<ship>" (sunk ship k,
-- with where it was) or "w<k>:<ship>" (sunk, and that was the last one).
local ns = CowCasino.ns

local R = { sides = { "a", "b" }, names = { a = "1st shot", b = "2nd shot" }, SIZE = 10 }
ns.BattleshipRules = R

R.FLEET = {
    { name = "Carrier", size = 5 },
    { name = "Battleship", size = 4 },
    { name = "Cruiser", size = 3 },
    { name = "Submarine", size = 3 },
    { name = "Destroyer", size = 2 },
}
local FLEET, SIZE = R.FLEET, R.SIZE
local ROWS = "ABCDEFGHIJ"

function R.Other(side) if side == "a" then return "b" end return "a" end
function R.OfferText(side) return side == "a" and "shoots first" or "shoots second" end

local function RowCol(s) return math.floor((s - 1) / SIZE), ns.Mod(s - 1, SIZE) end
R.RowCol = RowCol

function R.Name(s)
    local row, col = RowCol(s)
    return string.sub(ROWS, row + 1, row + 1) .. (col + 1)
end

-- The squares a ship of `size` covers from `start`, or nil off the edge.
function R.Cells(start, size, down)
    if not start then return nil end
    local row, col = RowCol(start)
    if (down and row + size > SIZE) or (not down and col + size > SIZE) then return nil end
    local out = {}
    for i = 0, size - 1 do
        table.insert(out, down and (start + i * SIZE) or (start + i))
    end
    return out
end

function R.ShipCells(fleet, k)
    local ship = fleet[k]
    return ship and R.Cells(ship.start, FLEET[k].size, ship.down)
end

-- Which ship (if any) is on square s.
function R.ShipAt(fleet, s)
    for k = 1, ns.getn(FLEET) do
        local cells = R.ShipCells(fleet, k)
        if cells then
            for _, c in ipairs(cells) do if c == s then return k end end
        end
    end
end

-- Can ship k go at start (across or down), clear of the others?
function R.Fits(fleet, k, start, down)
    local cells = R.Cells(start, FLEET[k].size, down)
    if not cells then return nil end
    for _, c in ipairs(cells) do
        local other = R.ShipAt(fleet, c)
        if other and other ~= k then return nil end
    end
    return cells
end

function R.Complete(fleet)
    for k = 1, ns.getn(FLEET) do
        if not (fleet[k] and fleet[k].start) then return false end
    end
    return true
end

function R.RandomFleet()
    local fleet = {}
    for k = 1, ns.getn(FLEET) do
        fleet[k] = {}
        repeat
            local start, down = math.random(1, SIZE * SIZE), math.random() < 0.5
            if R.Fits(fleet, k, start, down) then fleet[k].start, fleet[k].down = start, down end
        until fleet[k].start
    end
    return fleet
end

-- "12a,45d,..." (each ship's start square, across or down)
function R.EncodeShip(ship) return ship.start .. (ship.down and "d" or "a") end
function R.EncodeFleet(fleet)
    local t = {}
    for k = 1, ns.getn(FLEET) do table.insert(t, R.EncodeShip(fleet[k])) end
    return table.concat(t, ",")
end

function R.DecodeShip(text)
    local _, _, n, dir = string.find(text or "", "^(%d+)([ad])$")
    if not n then return nil end
    return { start = tonumber(n), down = dir == "d" }
end

-- Returns nil unless it's a whole, legal fleet.
function R.DecodeFleet(text)
    local fleet, k = {}, 0
    for _, part in ipairs(ns.Net.Split(text or "", ",")) do
        k = k + 1
        local ship = R.DecodeShip(part)
        if not ship or not FLEET[k] then return nil end
        fleet[k] = {}
        if not R.Fits(fleet, k, ship.start, ship.down) then return nil end
        fleet[k] = ship
    end
    if k ~= ns.getn(FLEET) then return nil end
    return fleet
end

-- The answer to a shot at s. hits: the squares already hit on this fleet.
function R.Answer(fleet, hits, s)
    local k = R.ShipAt(fleet, s)
    if not k then return "m" end
    local hit = { [s] = true }
    for c in pairs(hits) do hit[c] = true end
    for _, c in ipairs(R.ShipCells(fleet, k)) do
        if not hit[c] then return "h" end
    end
    local all = true
    for j = 1, ns.getn(FLEET) do
        for _, c in ipairs(R.ShipCells(fleet, j)) do
            if not hit[c] then all = false end
        end
    end
    return (all and "w" or "s") .. k .. ":" .. R.EncodeShip(fleet[k])
end

-- What an answer means: kind ("m", "h", "s", "w"), and for a sinking the
-- ship's number and where it was.
function R.Parse(res)
    local kind = string.sub(res or "", 1, 1)
    if kind == "s" or kind == "w" then
        local _, _, k, ship = string.find(res, "^.(%d+):(.+)$")
        return kind, tonumber(k), R.DecodeShip(ship)
    end
    return kind
end

-- A short fingerprint of a fleet (with a secret salt), sent at the start so
-- the fleet can be checked against it at the end. Not cryptography, but
-- enough that answers can't be quietly changed mid-game without it showing.
function R.Hash(text)
    local a, b = 5381, 52711
    for i = 1, string.len(text) do
        local c = string.byte(text, i)
        a = ns.Mod(a * 33 + c, 2147483629)
        b = ns.Mod(b * 31 + c * 7 + i, 2147483587)
    end
    return string.format("%08x%08x", a, b)
end

---------------------------------------------------------------------------
-- The computer
---------------------------------------------------------------------------
-- view: { shots = { [square] = answer }, sunk = { [k] = true } }
-- Returns the square to fire at.
R.LEVELS = { { name = "Easy" }, { name = "Medium" }, { name = "Hard" } }

-- Hits that aren't part of a ship already sunk.
local function OpenHits(view)
    local sunkCells = {}
    for _, res in pairs(view.shots) do
        local kind, k, ship = R.Parse(res)
        if (kind == "s" or kind == "w") and ship then
            for _, c in ipairs(R.Cells(ship.start, FLEET[k].size, ship.down) or {}) do sunkCells[c] = true end
        end
    end
    local open = {}
    for s, res in pairs(view.shots) do
        if res ~= "m" and not sunkCells[s] then table.insert(open, s) end
    end
    table.sort(open)
    return open, sunkCells
end

local function Untried(view)
    local list = {}
    for s = 1, SIZE * SIZE do if not view.shots[s] then table.insert(list, s) end end
    return list
end

local function Pick(list) return list[math.random(1, ns.getn(list))] end

-- Medium: fire around a hit (along the line once two hits line up).
local function Target(view, open)
    local around = {}
    local function Try(r, c)
        if r >= 0 and r < SIZE and c >= 0 and c < SIZE then
            local s = r * SIZE + c + 1
            if not view.shots[s] then around[s] = (around[s] or 0) + 1 end
        end
    end
    local inLine = {}
    for _, s in ipairs(open) do
        local r, c = RowCol(s)
        for _, t in ipairs(open) do
            if t ~= s then
                local r2, c2 = RowCol(t)
                if r2 == r and math.abs(c2 - c) == 1 then Try(r, c + (c - c2)); inLine[r .. "," .. (c + (c - c2))] = true end
                if c2 == c and math.abs(r2 - r) == 1 then Try(r + (r - r2), c); inLine[(r + (r - r2)) .. "," .. c] = true end
            end
        end
    end
    local best = {}
    for s in pairs(around) do
        local r, c = RowCol(s)
        if inLine[r .. "," .. c] then table.insert(best, s) end
    end
    if ns.getn(best) > 0 then return Pick(best) end
    for _, s in ipairs(open) do
        local r, c = RowCol(s)
        Try(r - 1, c); Try(r + 1, c); Try(r, c - 1); Try(r, c + 1)
    end
    for s in pairs(around) do table.insert(best, s) end
    if ns.getn(best) > 0 then return Pick(best) end
end

-- Hard: count every way each ship still afloat could lie, given what's
-- known; squares covered by more of them (and above all, next to open hits)
-- are likelier.
local function Density(view, open, sunkCells)
    local heat = {}
    local openSet = {}
    for _, s in ipairs(open) do openSet[s] = true end
    for k, ship in ipairs(FLEET) do
        if not view.sunk[k] then
            for start = 1, SIZE * SIZE do
                for _, down in ipairs({ false, true }) do
                    local cells = R.Cells(start, ship.size, down)
                    if cells then
                        local ok, covers = true, 0
                        for _, c in ipairs(cells) do
                            if view.shots[c] == "m" or sunkCells[c] then ok = false end
                            if openSet[c] then covers = covers + 1 end
                        end
                        if ok then
                            local w = 1 + covers * 40
                            for _, c in ipairs(cells) do
                                if not view.shots[c] then heat[c] = (heat[c] or 0) + w end
                            end
                        end
                    end
                end
            end
        end
    end
    local best, top = {}, -1
    for s, h in pairs(heat) do
        if h > top then best, top = { s }, h
        elseif h == top then table.insert(best, s) end
    end
    if ns.getn(best) > 0 then return Pick(best) end
end

function R.ChooseShot(view, level)
    local untried = Untried(view)
    if level <= 1 then return Pick(untried) end
    local open, sunkCells = OpenHits(view)
    if level == 2 then
        if ns.getn(open) > 0 then
            local s = Target(view, open)
            if s then return s end
        end
        return Pick(untried)
    end
    return Density(view, open, sunkCells) or Pick(untried)
end

-- The board kit offers a computer opponent when the rules have this.
R.ChooseMove = R.ChooseShot
