-- CowCasino: Mafia's rules (Games\Mafia.lua runs the game).
--
-- Players sit in seats 1..n. Roles are one letter per seat; the Mafia (and
-- their Godfather) know each other, the Town doesn't. Nights: the Mafia
-- pick someone to kill, the Doctor protects someone, the Detective checks
-- someone, the Bodyguard guards someone (and dies in their place), and the
-- Vigilante may shoot once. Days: everyone votes; a majority lynches at once,
-- otherwise the most votes when time's up (a tie lynches nobody). The Mayor's
-- vote counts twice. The Town wins when the Mafia are gone; the Mafia win when
-- they're as many as everyone else; the Jester wins by being lynched.

local ns = CowCasino.ns

local R = {}
ns.MafiaRules = R

R.ROLES = {
    M = { name = "Mafia", team = "mafia", act = "kill", color = "ff5050",
        desc = "Each night, help the Mafia pick someone to kill. You know your fellow Mafia." },
    G = { name = "Godfather", team = "mafia", act = "kill", color = "ff5050",
        desc = "Mafia. Each night, pick someone to kill (your pick breaks ties). The Detective sees you as innocent." },
    D = { name = "Detective", team = "town", act = "check", color = "66ccff",
        desc = "Each night, check one player to learn whether they're Mafia." },
    H = { name = "Doctor", team = "town", act = "save", color = "40ff40",
        desc = "Each night, protect one player from being killed (not the same one two nights running)." },
    V = { name = "Vigilante", team = "town", act = "shoot", color = "ffaa33",
        desc = "Once a game, shoot someone at night. Choose wisely." },
    B = { name = "Bodyguard", team = "town", act = "guard", color = "aaaaff",
        desc = "Each night, guard another player: if the Mafia attack them, you die in their place." },
    Y = { name = "Mayor", team = "town", color = "ffd100",
        desc = "Your vote counts twice. Keep it quiet, or the Mafia will come for you." },
    T = { name = "Townsfolk", team = "town", color = "ffffff",
        desc = "Find the Mafia and vote them out." },
    J = { name = "Jester", team = "jester", color = "ff66ff",
        desc = "You win if the town votes you out. Act suspicious!" },
}
-- The special roles a host can turn on or off (one of each), in the order
-- they're handed out when seats are short.
R.SPECIALS = { "G", "D", "H", "V", "B", "Y", "J" }
R.MIN_PLAYERS = 5

function R.Role(letter) return R.ROLES[letter or ""] end
function R.Team(letter) local r = R.ROLES[letter or ""] return r and r.team end
function R.IsMafia(letter) return R.Team(letter) == "mafia" end

-- How many Mafia for n players ("auto": a quarter, at least 1), never half or more.
function R.MafiaCount(n, setting)
    local m = tonumber(setting) or math.max(1, math.floor(n / 4))
    return math.max(1, math.min(m, math.floor((n - 1) / 2)))
end

-- The roles for n players, before shuffling. opts.mafia ("auto" or a number),
-- opts.specials: a string of the special letters turned on.
function R.Setup(n, opts)
    local m = R.MafiaCount(n, opts.mafia)
    local on = opts.specials or ""
    local list = {}
    local godfather = string.find(on, "G", 1, true) and m >= 2
    for i = 1, m do table.insert(list, (godfather and i == 1) and "G" or "M") end
    -- the specials, while seats last (leaving at least one Townsfolk once there are 6)
    local keep = n >= 6 and 1 or 0
    for _, k in ipairs(R.SPECIALS) do
        if k ~= "G" and string.find(on, k, 1, true) and ns.getn(list) < n - keep then table.insert(list, k) end
    end
    while ns.getn(list) < n do table.insert(list, "T") end
    return list
end

-- Shuffled into seats: a string, one letter a seat.
function R.Deal(n, opts)
    local list = R.Setup(n, opts)
    for i = ns.getn(list), 2, -1 do
        local j = math.random(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return table.concat(list)
end

function R.RoleAt(roles, seat) return string.sub(roles or "", seat, seat) end

-- A plain description of a setup: "4 Mafia (one the Godfather), Detective, ..., 9 Townsfolk".
function R.Describe(list)
    local count, order = {}, {}
    for _, k in ipairs(list) do
        if not count[k] then table.insert(order, k) end
        count[k] = (count[k] or 0) + 1
    end
    local out = {}
    local mafia = (count.M or 0) + (count.G or 0)
    if mafia > 0 then table.insert(out, mafia .. " Mafia" .. (count.G and " (one the Godfather)" or "")) end
    for _, k in ipairs(order) do
        if k ~= "M" and k ~= "G" and k ~= "T" then table.insert(out, R.ROLES[k].name) end
    end
    if count.T then table.insert(out, count.T .. " Townsfolk") end
    return table.concat(out, ", ")
end

---------------------------------------------------------------------------
-- Nights
---------------------------------------------------------------------------
-- The Mafia's target from their picks ({ [seat] = target }): the most
-- picked; a tie goes the Godfather's way if he's in it, else the earliest seat.
function R.MafiaTarget(picks, roles)
    local count, top = {}, 0
    for _, t in pairs(picks) do
        if t and t > 0 then
            count[t] = (count[t] or 0) + 1
            if count[t] > top then top = count[t] end
        end
    end
    if top == 0 then return nil end
    for seat, t in pairs(picks) do
        if R.RoleAt(roles, seat) == "G" and count[t] == top then return t end
    end
    local best
    for t, c in pairs(count) do
        if c == top and (not best or t < best) then best = t end
    end
    return best
end

-- What a night comes to. alive: { [seat] = true }; a: { kill, save, guard,
-- shoot, check } (seats, or nil). Returns deaths ({ seat = , how = }, in
-- order), and the Detective's answer ("m" Mafia, "t" not) if they checked.
function R.Night(roles, alive, a)
    local deaths, dead = {}, {}
    local function Die(seat, how)
        if seat and alive[seat] and not dead[seat] then
            dead[seat] = true
            table.insert(deaths, { seat = seat, how = how })
        end
    end
    local guardSeat
    for s = 1, string.len(roles) do
        if R.RoleAt(roles, s) == "B" and alive[s] then guardSeat = s end
    end
    local t = a.kill
    if t and alive[t] then
        if t == a.save then
            -- saved
        elseif a.guard == t and guardSeat and guardSeat ~= t then
            Die(guardSeat, "guard")
        else
            Die(t, "mafia")
        end
    end
    if a.shoot and alive[a.shoot] and a.shoot ~= a.save then Die(a.shoot, "shot") end
    local check
    if a.check and alive[a.check] then
        check = (R.RoleAt(roles, a.check) == "M") and "m" or "t"
    end
    return deaths, check
end

---------------------------------------------------------------------------
-- Days
---------------------------------------------------------------------------
function R.Weight(roles, seat) return R.RoleAt(roles, seat) == "Y" and 2 or 1 end

-- votes: { [voter] = target (0 for nobody) }. Returns counts ({ [target] =
-- weight }), the total weight of the living, and a target with a majority of
-- it (or nil). A majority for "nobody" (0) ends the day with no lynch.
function R.Tally(votes, roles, alive)
    local counts, total = {}, 0
    for s in pairs(alive) do total = total + R.Weight(roles, s) end
    for voter, target in pairs(votes) do
        if alive[voter] and target and (target == 0 or alive[target]) then
            counts[target] = (counts[target] or 0) + R.Weight(roles, voter)
        end
    end
    local majority
    for target, c in pairs(counts) do
        if c * 2 > total then majority = target end
    end
    return counts, total, majority
end

-- When the day's time is up: the most votes, if just one has it (nil
-- otherwise, or if it's "nobody").
function R.Lynch(votes, roles, alive)
    local counts = R.Tally(votes, roles, alive)
    local best, top, tied = nil, 0, false
    for target, c in pairs(counts) do
        if c > top then best, top, tied = target, c, false
        elseif c == top then tied = true end
    end
    if not best or tied or best == 0 then return nil end
    return best
end

-- Who's won: "town", "mafia", or nil (the Jester's win is checked at a lynch).
function R.Winner(roles, alive)
    local mafia, others = 0, 0
    for s in pairs(alive) do
        if R.IsMafia(R.RoleAt(roles, s)) then mafia = mafia + 1 else others = others + 1 end
    end
    if mafia == 0 then return "town" end
    if mafia >= others then return "mafia" end
    return nil
end
