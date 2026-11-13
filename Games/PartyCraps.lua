-- CowCasino: Party Craps
-- Craps's party mode: Craps shows this in its window when you choose
-- "Party play" (Games\Craps.lua), the way Blackjack does.
-- Up to four players from your party or raid at one craps table. One player
-- hosts: their client rolls the dice and settles every bet, and tells the
-- others what happened. Seats are free: everyone plays with the stack the
-- host picked, and nobody's own chips are touched.
-- The dice pass around the table: the shooter rolls when ready (or the
-- dice roll themselves when the betting time runs out), and hands them on
-- after a seven out. Rules and bets match solo Craps.

local ns = CowCasino.ns

local DEFAULT_STATS = { rolls = 0, net = 0, pointsMade = 0, buyIns = 0 }

local NUM_SEATS     = 4
local BUY_INS       = { 200, 500, 1000, 2500, 5000, 10000 }   -- the host picks everyone's (free) stack
local CHIP_VALUES   = { 5, 25, 100, 500 }
local ODDS_MAX      = 3
local BET_TIME      = 25     -- seconds of betting before the dice roll themselves
local RESULT_TIME   = 3      -- seconds the result stays up before betting opens again
local HEARTBEAT     = 15     -- the host re-sends the table this often
local HOST_TIMEOUT  = 40
local OFFER_TIMEOUT = 60
local GAME_TAG      = "CR"

local AREA_W        = 352
local SEAT_W, SEAT_GAP = 85, 4

local Rules = ns.CrapsRules
local Net = ns.Net

local Game = {
    id = "partycraps",
    name = "Party Craps",
    description = "Craps with your party.",
}

local db          -- ns.db.partycraps
local ui = {}

local T = {
    mode = "lobby",     -- lobby | host | client
    seats = {},
    phase = "waiting",  -- betting | result
    rollNo = 0,
    version = 0,
    shooter = 1,
    point = nil,
    d1 = 0, d2 = 0,
    event = "",
    mySeat = 1,
    offers = {},
    dirtySeats = {},
    partyBuyIn = 500,
    chip = 25,
    round = 0,          -- bumps when the table changes, so stale timers stop
}

local function Fmt(n) return ns:FormatChips(n) end
local function Msg(parts) return GAME_TAG .. ";" .. table.concat(parts, ";") end

local PHASE_CODE = { waiting = "w", betting = "b", result = "r" }
local PHASE_NAME = { w = "waiting", b = "betting", r = "result" }
local EVENT_CODE = { natural = "n", craps = "c", point = "p", made = "m", sevenOut = "s", roll = "r" }
local EVENT_NAME = { n = "natural", c = "craps", p = "point", m = "made", s = "sevenOut", r = "roll" }

local function NewSeat(kind, name, stack)
    return { kind = kind, name = name, stack = stack or 0, bets = {}, results = {}, last = nil }
end

local function MySeat() return T.mySeat or 1 end
local function Me() return T.seats[MySeat()] end
local function IsMine(i) return i == MySeat() end

local function HasRemote()
    for _, p in ipairs(T.seats) do
        if p.kind == "remote" then return true end
    end
    return false
end

local function OpenSeats()
    local n = 0
    for i = 2, NUM_SEATS do
        if T.seats[i] and T.seats[i].kind == "empty" then n = n + 1 end
    end
    return n
end

-- Your chips at the table if it closed now: stack plus bets on the table.
local function SafeStack(p)
    return (p.stack or 0) + Rules.Total(p.bets or {})
end

-- Line bets can't come down while a point is on.
local function LockedBets(p)
    return T.point ~= nil and (((p.bets.pass or 0) > 0) or ((p.bets.dontPass or 0) > 0))
end

---------------------------------------------------------------------------
-- Host: telling the table
---------------------------------------------------------------------------
local Refresh, StartBetting, HostRoll

local function MarkSeat(i) T.dirtySeats[i] = true end
local function MarkAll() for i = 1, NUM_SEATS do T.dirtySeats[i] = true end end

local function Changed()
    T.version = T.version + 1
    T.dirty = true
end

local function ResultsPack(p)
    local out = {}
    for i, s in ipairs(Rules.SPOTS) do
        local r = p.results[s.key]
        out[i] = r and tostring(r) or ""
    end
    return table.concat(out, ",")
end

local function SeatMsg(i)
    local p = T.seats[i]
    local flags = (p.leaving and "l" or "") .. (p.active and "a" or "")
    return Msg({ "Z", T.tid, T.rollNo, i, p.stack or 0, Rules.Pack(p.bets), ResultsPack(p), p.last or "", flags })
end

local function StateMsg()
    local remain = ""
    if T.deadline then remain = math.max(0, math.floor(T.deadline - GetTime() + 0.5)) end
    return Msg({ "P", T.tid, T.version, T.rollNo, PHASE_CODE[T.phase], T.shooter, T.point or 0,
        T.d1 or 0, T.d2 or 0, EVENT_CODE[T.event] or "", remain })
end

local function RosterMsg()
    local parts = { "R", T.tid }
    for i = 1, NUM_SEATS do
        local p = T.seats[i]
        table.insert(parts, p.kind == "empty" and "" or (p.name or "?"))
    end
    return Msg(parts)
end

local function SendRoster()
    if T.mode == "host" and HasRemote() then Net:Send(RosterMsg(), "CR-R") end
end

local function SendOffer()
    if T.mode ~= "host" then return end
    Net:Send(Msg({ "O", T.tid, NUM_SEATS - OpenSeats(), OpenSeats(), T.tableBuyIn or T.partyBuyIn }), "CR-O")
end

-- Seat updates first, then the table state, so a client never sees a roll
-- before the bets that go with it.
local function Broadcast()
    T.dirty = false
    if T.mode ~= "host" or not HasRemote() then
        T.dirtySeats = {}
        return
    end
    for i = 1, NUM_SEATS do
        if T.dirtySeats[i] then Net:Send(SeatMsg(i), "CR-Z" .. i) end
    end
    T.dirtySeats = {}
    Net:Send(StateMsg(), "CR-P")
end

local function SaveHost()
    if T.mode == "host" then db.host = { stack = SafeStack(Me()) } end
end

local function SaveSeat()
    if T.mode == "client" then db.seat = { host = T.host, tid = T.tid, stack = SafeStack(Me()) } end
end

---------------------------------------------------------------------------
-- Host: the dice
---------------------------------------------------------------------------
local function StartClock(seconds, onExpire)
    T.deadline = GetTime() + seconds
    T.clock = (T.clock or 0) + 1
    local clock, round = T.clock, T.round
    ns:After(seconds, function()
        if T.mode ~= "host" or T.clock ~= clock or T.round ~= round then return end
        onExpire()
    end)
end

local function StopClock()
    T.deadline = nil
    T.clock = (T.clock or 0) + 1
end

local function AnyBets()
    for _, p in ipairs(T.seats) do
        if p.kind ~= "empty" and Rules.Total(p.bets) > 0 then return true end
    end
    return false
end

-- The next seated player after `from`, going around the table.
local function NextShooter(from)
    for k = 1, NUM_SEATS do
        local i = ns.Mod((from or 0) - 1 + k, NUM_SEATS) + 1
        local p = T.seats[i]
        if p and p.kind ~= "empty" and not p.leaving then return i end
    end
    return 1
end

function StartBetting()
    if T.mode ~= "host" then return end
    T.phase = "betting"
    local p = T.seats[T.shooter]
    if not p or p.kind == "empty" or p.leaving then T.shooter = NextShooter(T.shooter) end
    -- When time's up the dice roll themselves (if anyone has a bet down).
    local function Expire()
        if T.phase ~= "betting" then return end
        if AnyBets() then HostRoll() else StartClock(BET_TIME, Expire) Changed() Refresh() end
    end
    StartClock(BET_TIME, Expire)
    Changed()
    Refresh()
end

local function TidySeats()
    local changed = false
    for i = 2, NUM_SEATS do
        local p = T.seats[i]
        if p.kind == "remote" and p.leaving then
            T.seats[i] = NewSeat("empty")
            MarkSeat(i)
            changed = true
        end
    end
    if changed then
        SendRoster()
        SendOffer()
    end
end

function HostRoll()
    if T.mode ~= "host" or T.phase ~= "betting" or not AnyBets() then return end
    StopClock()
    local d1, d2 = Rules.Roll()
    local oldPoint = T.point
    T.rollNo = T.rollNo + 1
    T.d1, T.d2 = d1, d2
    local newPoint, event
    for i, p in ipairs(T.seats) do
        p.results = {}
        p.last = nil
        p.active = Rules.Total(p.bets) > 0       -- had bets on this roll
        if p.kind ~= "empty" then
            local back
            back, newPoint, event = Rules.Settle(p.bets, oldPoint, d1, d2)
            local net, returned = 0, 0
            for key, amount in pairs(back) do
                p.results[key] = amount - p.bets[key]
                net = net + amount - p.bets[key]
                returned = returned + amount
                p.bets[key] = nil
            end
            p.stack = p.stack + returned
            if next(back) then p.last = net end
            MarkSeat(i)
        end
    end
    T.point, T.event = newPoint, event
    if event == "sevenOut" then T.shooter = NextShooter(T.shooter) end
    T.phase = "result"
    SaveHost()
    Changed()
    if ui.dice then
        ns:PlayGameSound(ns.db.craps, "newHand")
        ui.dice:Tumble(d1, d2, function() Game.CountRoll() Refresh() end)
    end
    Refresh()
    local round = T.round
    ns:After(RESULT_TIME, function()
        if T.mode ~= "host" or T.round ~= round or T.phase ~= "result" then return end
        if T.closeAfterRoll then
            T.closeAfterRoll = nil
            Game.HostLeave()
            return
        end
        TidySeats()
        StartBetting()
    end)
end

local function HostAct(i, code, key, amount)
    local p = T.seats[i]
    if not p or p.kind == "empty" then return end
    amount = tonumber(amount) or 0
    if code == "r" then
        if i == T.shooter then HostRoll() end
        return
    end
    if T.phase ~= "betting" then return end
    local spot
    for _, s in ipairs(Rules.SPOTS) do if s.key == key or s.code == key then spot = s end end
    if code == "c" then
        local back = 0
        for k, v in pairs(p.bets) do
            if Rules.CanRemove(k, T.point) then
                back = back + v
                p.bets[k] = nil
            end
        end
        p.stack = p.stack + back
    elseif spot and code == "b" then
        if not Rules.CanAdd(spot.key, T.point, p.bets) then return end
        local have = p.bets[spot.key] or 0
        local add = math.min(amount, p.stack, Rules.Limit(spot.key, p.bets, ODDS_MAX) - have)
        if add < 1 then return end
        p.bets[spot.key] = have + add
        p.stack = p.stack - add
    elseif spot and code == "t" then
        local have = p.bets[spot.key] or 0
        if have <= 0 or not Rules.CanRemove(spot.key, T.point) then return end
        local back = math.min(have, amount)
        p.bets[spot.key] = (have - back > 0) and (have - back) or nil
        p.stack = p.stack + back
    else
        return
    end
    p.results, p.last, p.active = {}, nil, nil
    MarkSeat(i)
    SaveHost()
    Changed()
    Refresh()
end

---------------------------------------------------------------------------
-- Leaving, hosting, joining
---------------------------------------------------------------------------
local function ResetToLobby()
    T.mode, T.mySeat = "lobby", 1
    T.seats = {}
    T.phase, T.point, T.d1, T.d2, T.event = "waiting", nil, 0, 0, ""
    T.round = T.round + 1          -- stops timers from the old table
    T.deadline, T.dirty = nil, false
    T.tid, T.host, T.closeAfterRoll, T.shooter = nil, nil, nil, 1
    T.dirtySeats = {}
    T.seenRoll = nil
    StopClock()
end

local function SetLobbyMessage(text) if ui.lobbyMsg then ui.lobbyMsg:SetText(text or "") end end

-- Closing the table hands everyone their stack and their bets back.
function Game.HostLeave()
    if T.mode ~= "host" then return end
    if T.phase == "result" and ui.dice and ui.dice.rolling then
        T.closeAfterRoll = true
        Refresh()
        return
    end
    local stack = SafeStack(Me())
    Net:Send(Msg({ "X", T.tid }))
    db.host = nil
    ResetToLobby()
    SetLobbyMessage("You closed your table.")
    Refresh()
end

local function HostTable(buyin)
    if T.mode ~= "lobby" or not Net:InGroup() then return end   -- free: party tables don't use your chips
    db.stats.buyIns = db.stats.buyIns + 1
    T.tableBuyIn = buyin            -- everyone who joins sits down with this
    T.mode, T.mySeat = "host", 1
    T.tid = tostring(math.random(1, 99999))
    T.version, T.rollNo, T.shooter = 0, 0, 1
    T.seats = { NewSeat("you", Net:Me(), buyin) }
    for i = 2, NUM_SEATS do T.seats[i] = NewSeat("empty") end
    db.host = { stack = buyin }
    SendOffer()
    StartBetting()
end

local function SeatPlayer(name, buyin)
    for i = 2, NUM_SEATS do
        local p = T.seats[i]
        if p.kind == "remote" and p.name == name then
            if not p.leaving then
                Net:Send(Msg({ "S", T.tid, name, i, p.stack }))   -- asked twice
                return
            end
            T.seats[i] = NewSeat("empty")
        end
    end
    local free
    for i = 2, NUM_SEATS do
        if not free and T.seats[i].kind == "empty" then free = i end
    end
    if not free then
        Net:Send(Msg({ "N", T.tid, name, "The table is full." }))
        return
    end
    T.seats[free] = NewSeat("remote", name, buyin)
    Net:Send(Msg({ "S", T.tid, name, free, buyin }))
    MarkAll()           -- the newcomer needs every seat, not just theirs
    Changed()
    SendRoster()
    SendOffer()
end

-- A player who leaves (or drops from the group) takes their stack and the
-- bets they could take down; line bets riding on a point are left behind.
local function HostDropPlayer(i)
    local p = T.seats[i]
    if not p or p.kind ~= "remote" then return end
    T.seats[i] = NewSeat("empty")
    MarkSeat(i)
    if T.shooter == i then T.shooter = NextShooter(i) end
    Changed()
    SendRoster()
    SendOffer()
    Refresh()
end

-- Client side ---------------------------------------------------------------
local function ClientCashOut(amount, message)
    -- a party seat is free, so its stack stays at the table
    db.seat = nil
    ResetToLobby()
    SetLobbyMessage(message .. ((amount and amount > 0) and (" You finished with " .. Fmt(amount) .. ".") or ""))
    Refresh()
end

local function HostGone(message)
    if T.mode ~= "client" then return end
    ClientCashOut(db.seat and db.seat.stack or 0, message)
end

-- What you take with you: your stack and every bet that can come down.
local function ClientLeave()
    if T.mode ~= "client" then return end
    local me = Me()
    if LockedBets(me) or T.phase ~= "betting" and T.phase ~= "waiting" then return end
    Net:Send(Msg({ "L", T.tid }))
    ClientCashOut(SafeStack(me), "You left " .. (T.host or "the host") .. "'s table.")
end

local function JoinTable(host, tid)
    local offer = T.offers[host]
    local buyin = (offer and offer.buyin) or T.partyBuyIn     -- the host's stack, free
    if T.mode ~= "lobby" then return end
    T.joining = { host = host, tid = tid, buyin = buyin, at = GetTime() }
    Net:Send(Msg({ "J", tid, buyin }))
    SetLobbyMessage("Asking " .. host .. " for a seat...")
end

-- Your bets and roll, local or sent to the host.
local function Do(code, key, amount)
    if T.mode == "host" then
        HostAct(MySeat(), code, key, amount)
    elseif T.mode == "client" then
        local spot
        for _, s in ipairs(Rules.SPOTS) do if s.key == key then spot = s end end
        Net:Send(Msg({ "A", T.tid, T.rollNo, code, spot and spot.code or "", amount or 0 }))
        T.asked = GetTime()
        Refresh()
    end
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local function UnpackResults(text)
    local out, i = {}, 1
    local parts = Net.Split(text or "", ",")
    for _, s in ipairs(Rules.SPOTS) do
        local n = tonumber(parts[i] or "")
        if n then out[s.key] = n end
        i = i + 1
    end
    return out
end

local function ClientSeat(f)
    local i = tonumber(f[5])
    local p = i and T.seats[i]
    if not p then return end
    p.stack = tonumber(f[6]) or 0
    p.bets = Rules.Unpack(f[7])
    p.results = UnpackResults(f[8])
    p.last = tonumber(f[9] or "")
    p.leaving = string.find(f[10] or "", "l", 1, true) ~= nil
    p.active = string.find(f[10] or "", "a", 1, true) ~= nil
    if IsMine(i) then
        T.asked = nil
        SaveSeat()
    end
end

local function ClientRoster(f)
    for i = 1, NUM_SEATS do
        local name = f[3 + i] or ""
        local p = T.seats[i] or NewSeat("empty")
        if name == "" then
            p.kind, p.name = "empty", nil
        else
            p.kind, p.name = "human", name
        end
        T.seats[i] = p
    end
    local mine = T.seats[MySeat()]
    if mine.kind ~= "human" or mine.name ~= Net:Me() then
        ClientCashOut(db.seat and db.seat.stack or 0, "You're no longer at " .. (T.host or "the") .. "'s table.")
        return false
    end
    return true
end

-- Your stats and sounds, once per roll.
local function CountRoll()
    if T.seenRoll == T.rollNo or T.rollNo == 0 then return end
    T.seenRoll = T.rollNo
    local me = Me()
    -- the dealer calls it for everyone at the table, then says who has the dice
    if ns.CrapsDealerCall then
        local net = (me and me.active) and (me.last or 0) or 0
        ns:CrapsDealerCall(T.d1, T.d2, T.event, T.point, T.point, net)
        if T.event == "sevenOut" then
            local p = T.seats[T.shooter]
            if IsMine(T.shooter) then ns:CrapsDealerSay("crapsYourDice")
            elseif p and p.kind ~= "empty" and p.name then ns:CrapsDealerSay("crapsNewShooter", { name = p.name }) end
        end
    end
    if not me or not me.active then return end   -- no bets on this roll
    local s = db.stats
    s.rolls = s.rolls + 1
    s.net = s.net + (me.last or 0)
    if T.event == "made" then s.pointsMade = s.pointsMade + 1 end
    if (me.last or 0) > 0 then ns:PlayGameSound(ns.db.craps, "win")
    elseif (me.last or 0) < 0 then ns:PlayGameSound(ns.db.craps, "lose") end
end

Game.CountRoll = CountRoll

local function ClientState(f)
    local oldRoll = T.rollNo
    T.version = tonumber(f[4]) or 0
    T.rollNo = tonumber(f[5]) or 0
    T.phase = PHASE_NAME[f[6]] or "waiting"
    T.shooter = tonumber(f[7]) or 1
    local point = tonumber(f[8]) or 0
    T.point = point > 0 and point or nil
    T.d1, T.d2 = tonumber(f[9]) or 0, tonumber(f[10]) or 0
    T.event = EVENT_NAME[f[11] or ""] or ""
    T.deadline = (f[12] and f[12] ~= "") and (GetTime() + tonumber(f[12])) or nil
    if T.phase == "result" and T.rollNo ~= oldRoll and T.rollNo > 0 then
        if ui.dice then
            ns:PlayGameSound(ns.db.craps, "newHand")
            ui.dice:Tumble(T.d1, T.d2, function() CountRoll() Refresh() end)
        else
            CountRoll()
        end
    end
    Refresh()
end

local function OnMessage(sender, f)
    local kind, tid = f[2], f[3]
    if kind == "Q" then
        if T.mode == "host" then SendOffer() end
        return
    elseif kind == "O" then
        T.offers[sender] = { tid = tid, players = tonumber(f[4]) or 0, open = tonumber(f[5]) or 0,
            buyin = tonumber(f[6]), heard = GetTime() }
        if T.mode == "lobby" then Refresh() end
        return
    end

    if T.mode == "host" and tid == T.tid then
        if kind == "J" then
            SeatPlayer(sender, T.tableBuyIn or 500)    -- everyone gets the host's stack
            Refresh()
        elseif kind == "A" then
            local i
            for s = 2, NUM_SEATS do
                if T.seats[s].kind == "remote" and T.seats[s].name == sender then i = s end
            end
            if not i or tonumber(f[4]) ~= T.rollNo then return end
            HostAct(i, f[5], f[6], f[7])
        elseif kind == "L" then
            for i = 2, NUM_SEATS do
                if T.seats[i].kind == "remote" and T.seats[i].name == sender then HostDropPlayer(i) end
            end
        end
        return
    end

    if T.joining and sender == T.joining.host and tid == T.joining.tid then
        if kind == "S" and f[4] == Net:Me() then
            local seat, stack = tonumber(f[5]), tonumber(f[6]) or 0
            T.joining = nil
            if not seat then
                Net:Send(Msg({ "L", tid }))
                return
            end
            db.stats.buyIns = db.stats.buyIns + 1
            T.mode, T.host, T.tid, T.mySeat = "client", sender, tid, seat
            T.seats = {}
            for i = 1, NUM_SEATS do T.seats[i] = NewSeat("empty") end
            T.seats[seat] = NewSeat("human", Net:Me(), stack)
            T.phase, T.version, T.lastHeard = "waiting", 0, GetTime()
            T.seenRoll = nil
            db.seat = { host = sender, tid = tid, stack = stack }
            Refresh()
        elseif kind == "N" and f[4] == Net:Me() then
            T.joining = nil
            SetLobbyMessage(f[5] or "No seat.")
        elseif kind == "X" then
            T.joining = nil
            SetLobbyMessage(sender .. " closed the table.")
            Refresh()
        end
        return
    end

    if T.mode ~= "client" or sender ~= T.host or tid ~= T.tid then
        if kind == "X" then
            T.offers[sender] = nil
            if T.mode == "lobby" then Refresh() end
        end
        return
    end
    T.lastHeard = GetTime()
    if kind == "R" then
        if ClientRoster(f) then Refresh() end
    elseif kind == "Z" then
        ClientSeat(f)
        Refresh()
    elseif kind == "P" then
        -- the first table state after rolls you sat through: don't count those
        if T.seenRoll == nil then T.seenRoll = tonumber(f[5]) or 0 end
        ClientState(f)
    elseif kind == "X" then
        HostGone(sender .. " closed the table.")
    end
end

Net.handlers[GAME_TAG] = OnMessage

Net.groupHandlers.partycraps = function()
    if T.mode == "host" then
        for i = 2, NUM_SEATS do
            local p = T.seats[i]
            if p.kind == "remote" and not Net:IsMember(p.name) then HostDropPlayer(i) end
        end
    elseif T.mode == "client" and not Net:IsMember(T.host) then
        HostGone((T.host or "The host") .. " left the group.")
    end
    for name in pairs(T.offers) do
        if not Net:IsMember(name) then T.offers[name] = nil end
    end
    if T.joining and not Net:IsMember(T.joining.host) then
        T.joining = nil
        SetLobbyMessage("The host left the group.")
    end
    if T.mode == "lobby" and ui.lobby then Refresh() end
end

local ticker = ns.CreateFrame("Frame")
local tickWait, beatWait = 0, 0
ticker:SetScript("OnUpdate", function()
    tickWait = tickWait + (arg1 or 0)
    if tickWait < 0.5 then return end
    beatWait = beatWait + tickWait
    tickWait = 0
    if T.deadline and ui.table and ui.table:IsVisible() then Refresh() end
    if T.mode == "host" and beatWait >= HEARTBEAT then
        beatWait = 0
        if HasRemote() then
            SendRoster()
            MarkAll()
            Broadcast()
        end
    elseif T.mode == "client" and T.lastHeard and GetTime() - T.lastHeard > HOST_TIMEOUT then
        HostGone((T.host or "The host") .. " stopped responding.")
    end
    if T.joining and GetTime() - T.joining.at > 15 then
        SetLobbyMessage("No answer from " .. T.joining.host .. ".")
        T.joining = nil
        Refresh()
    end
end)

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function SetStatus(text, r, g, b)
    ui.status:SetText(text or "")
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function SeatName(i)
    local p = T.seats[i]
    if not p or p.kind == "empty" then return "|cff888888Empty seat|r" end
    if IsMine(i) then return "You" end
    return p.name or "?"
end

local function NetText(n)
    if n == nil then return "" end
    if n > 0 then return "|cff40ff40+" .. Fmt(n) .. "|r" end
    if n < 0 then return "|cffff5050-" .. Fmt(-n) .. "|r" end
    return "|cffcccccceven|r"
end

local function RefreshLobby()
    local inGroup = Net:InGroup()
    ui.groupInfo:SetText(inGroup and ("You're in a group of " .. Net:GroupSize() .. ". Everyone needs CowCasino to play.")
        or "Join a party or raid to play with friends.")
    ui.buyIn:SetText(Fmt(T.partyBuyIn))
    ns.SetEnabled(ui.host, inGroup)

    local list = {}
    for name, offer in pairs(T.offers) do
        if GetTime() - offer.heard < OFFER_TIMEOUT and Net:IsMember(name) then
            table.insert(list, { host = name, tid = offer.tid, players = offer.players, open = offer.open, buyin = offer.buyin })
        end
    end
    table.sort(list, function(a, b) return a.host < b.host end)
    for r = 1, 3 do
        local row, offer = ui.rows[r], list[r]
        row.offer = offer
        if offer then
            row.text:SetText(string.format("%s's table - %d playing, %d open", offer.host, offer.players, offer.open)
                .. (offer.buyin and ("\n|cffccccccFree " .. Fmt(offer.buyin) .. " stack|r") or ""))
            row.join:Show()
            ns.SetEnabled(row.join, offer.open > 0 and not T.joining)
        else
            row.text:SetText((r == 1 and inGroup) and "|cff888888No tables yet. Ask someone to host, or host one.|r" or "")
            row.join:Hide()
        end
    end
    local s = db.stats
    local net = s.net
    ui.lobbyStats:SetText(string.format("Rolls %d   Points made %d   Net %s", s.rolls, s.pointsMade,
        net == 0 and "0" or NetText(net)))
end

local function RefreshSeat(i)
    local p, s = T.seats[i], ui.seats[i]
    s.name:SetText(SeatName(i) .. ((T.shooter == i and p.kind ~= "empty") and " |cffffd100(dice)|r" or ""))
    if p.kind == "empty" then s.portrait:ShowUnit(nil)
    elseif IsMine(i) then s.portrait:ShowUnit("player")
    else s.portrait:ShowUnit(Net:UnitFor(p.name)) end
    if p.kind == "empty" then
        s.stack:SetText("")
        s.bet:SetText("")
        s.result:SetText("")
    else
        s.stack:SetText(Fmt(p.stack))
        local on = Rules.Total(p.bets)
        s.bet:SetText(on > 0 and ("Bets " .. Fmt(on)) or "|cff888888No bets|r")
        local diceDone = not (ui.dice and ui.dice.rolling)
        s.result:SetText((T.phase == "result" and diceDone) and NetText(p.last) or "")
    end
    ns.SetShown(s.glow, T.shooter == i and p.kind ~= "empty")
    s.frame:SetAlpha((p.kind == "empty") and 0.45 or 1)
end

function Refresh()
    if not ui.table then return end
    local seated = T.mode ~= "lobby"
    ns.SetShown(ui.table, seated)
    ns.SetShown(ui.lobby, not seated)
    ns:UpdateChipsDisplay()
    if not seated then
        RefreshLobby()
        if T.dirty then Broadcast() end
        return
    end

    local me = Me()
    local rolling = ui.dice.rolling ~= nil
    if not rolling then
        if T.d1 and T.d1 > 0 then ui.dice:Set(T.d1, T.d2) else ui.dice:Blank() end
    end
    if T.point then
        ui.point:SetText("Point " .. T.point)
        ui.point:SetTextColor(1, 0.82, 0)
    else
        ui.point:SetText("Come-out")
        ui.point:SetTextColor(0.7, 0.7, 0.7)
    end
    for i = 1, NUM_SEATS do RefreshSeat(i) end

    -- your bets on the board
    local betting = T.phase == "betting"
    for _, b in ipairs(ui.spots) do
        local key = b.spot.key
        local open = betting and (Rules.CanAdd(key, T.point, me.bets) or ((me.bets[key] or 0) > 0 and Rules.CanRemove(key, T.point)))
        local res = (T.phase == "result" and not rolling) and me.results[key] or nil
        b:Draw(me.bets[key], open, res)
    end
    for i, b in ipairs(ui.chipButtons) do
        ns.SetShown(b.chosen, CHIP_VALUES[i] == T.chip)
    end

    local left = T.deadline and math.max(0, math.ceil(T.deadline - GetTime())) or nil
    local function Clock(text) return left and (text .. " (" .. left .. "s)") or text end
    local shooterName = (T.shooter == MySeat()) and "you" or (T.seats[T.shooter] and T.seats[T.shooter].name or "?")
    if T.phase == "betting" then
        if T.shooter == MySeat() then SetStatus(Clock("Place your bets and roll when ready"))
        else SetStatus(Clock("Place your bets - " .. shooterName .. " has the dice")) end
    elseif T.phase == "result" then
        if rolling then
            SetStatus("The dice are rolling...")
        else
            local line = Rules.Describe(T.d1, T.d2, T.event, T.point, nil)
            if T.event == "roll" then line = T.d1 .. " + " .. T.d2 .. " = " .. (T.d1 + T.d2) .. "." end
            local net = me.last
            if net and net > 0 then SetStatus(line .. " You win " .. Fmt(net) .. ".", 0.25, 1, 0.25)
            elseif net and net < 0 then SetStatus(line .. " You lose " .. Fmt(-net) .. ".", 1, 0.35, 0.35)
            else SetStatus(line, 0.9, 0.9, 0.9) end
        end
    else
        SetStatus("Waiting for the table...")
    end
    if T.closeAfterRoll then ui.partyLabel:SetText("Closing after this roll")
    elseif T.mode == "host" then ui.partyLabel:SetText("Your table")
    else ui.partyLabel:SetText((T.host or "?") .. "'s table") end

    ns.SetShown(ui.roll, T.shooter == MySeat())
    ns.SetEnabled(ui.roll, betting and T.shooter == MySeat() and AnyBets() and not rolling)
    ns.SetEnabled(ui.takeDown, betting and Rules.Total(me.bets) > 0)
    ui.onTable:SetText("Your bets: " .. Fmt(Rules.Total(me.bets)))

    if T.mode == "host" then
        ui.leave:SetText(T.closeAfterRoll and "Closing..." or "Close table")
        ns.SetEnabled(ui.leave, not T.closeAfterRoll)
    else
        ui.leave:SetText("Leave table")
        ns.SetEnabled(ui.leave, not LockedBets(me) and T.phase ~= "result")
    end

    if T.dirty then Broadcast() end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function MakeButton(parent, text, width, onClick, height)
    local b = ns.CreateFrame("Button", ns:NewName(), parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(height or 22)
    b:SetText(text)
    b:SetScript("OnClick", function() onClick(this, arg1) end)
    return b
end

local function BuildLobby(panel)
    local l = ns.CreateFrame("Frame", nil, panel)
    l:SetAllPoints(panel)
    ui.lobby = l

    local title = ns:BigFont(l:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 22)
    title:SetPoint("TOP", l, "TOP", 0, -14)
    title:SetText("Party Craps")

    local info = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOP", title, "BOTTOM", 0, -8)
    info:SetWidth(AREA_W - 24)
    info:SetText("Up to four players from your group at one table, passing the dice. Free to join: everyone "
        .. "plays with the stack the host picks, and your own chips are never touched.")

    ui.groupInfo = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.groupInfo:SetPoint("TOP", l, "TOP", 0, -84)
    ui.groupInfo:SetWidth(AREA_W - 24)

    local label = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", l, "TOPLEFT", 16, -112)
    label:SetText("Table stack")
    ui.buyIn = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local function StepBuyIn(dir)
        local idx = 1
        for i, b in ipairs(BUY_INS) do
            if b == T.partyBuyIn then idx = i end
        end
        idx = math.max(1, math.min(ns.getn(BUY_INS), idx + dir))
        T.partyBuyIn = BUY_INS[idx]
        Refresh()
    end
    local nextB = MakeButton(l, ">", 26, function() StepBuyIn(1) end)
    nextB:SetPoint("TOPRIGHT", l, "TOPRIGHT", -16, -108)
    ui.buyIn:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    ui.buyIn:SetWidth(80)
    ui.buyIn:SetJustifyH("CENTER")
    local prevB = MakeButton(l, "<", 26, function() StepBuyIn(-1) end)
    prevB:SetPoint("RIGHT", ui.buyIn, "LEFT", -6, 0)

    local back = MakeButton(l, "< Solo table", 90, function()
        if Game.onBack then Game.onBack() end
    end)
    back:SetPoint("TOPLEFT", l, "TOPLEFT", 0, -2)

    ui.host = MakeButton(l, "Host a table", 140, function() HostTable(T.partyBuyIn) end, 24)
    ui.host:SetPoint("TOP", l, "TOP", 0, -138)

    local header = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", l, "TOPLEFT", 16, -178)
    header:SetText("Tables in your group")
    local refresh = MakeButton(l, "Refresh", 70, function()
        Net:Send(Msg({ "Q" }))
        Refresh()
    end)
    refresh:SetPoint("TOPRIGHT", l, "TOPRIGHT", -16, -174)

    ui.rows = {}
    for r = 1, 3 do
        local r = r   -- own copy for closures (Lua 5.0)
        local row = {}
        row.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("TOPLEFT", l, "TOPLEFT", 18, -206 - (r - 1) * 28)
        row.text:SetWidth(250)
        row.text:SetJustifyH("LEFT")
        row.join = MakeButton(l, "Join", 60, function()
            local offer = ui.rows[r].offer
            if offer then JoinTable(offer.host, offer.tid) end
        end)
        row.join:SetPoint("TOPRIGHT", l, "TOPRIGHT", -16, -200 - (r - 1) * 28)
        ui.rows[r] = row
    end

    ui.lobbyMsg = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.lobbyMsg:SetPoint("TOP", l, "TOP", 0, -296)
    ui.lobbyMsg:SetWidth(AREA_W - 24)

    ui.lobbyStats = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.lobbyStats:SetPoint("BOTTOM", l, "BOTTOM", 0, 12)
    ui.lobbyStats:SetWidth(AREA_W - 20)
end

local function BuildTable(panel)
    local t = ns.CreateFrame("Frame", nil, panel)
    t:SetAllPoints(panel)
    ui.table = t

    local felt = t:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(t)
    felt:SetTexture(0.05, 0.30, 0.12, 0.90)

    ui.partyLabel = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.partyLabel:SetPoint("TOPLEFT", t, "TOPLEFT", 4, -4)

    ui.dice = ns:CreateDice(t, 34)
    ui.dice:SetPoint("TOP", t, "TOP", 0, -4)
    ui.point = ns:BigFont(t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 15)
    ui.point:SetPoint("TOPRIGHT", t, "TOPRIGHT", -8, -14)

    ui.status = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", t, "TOP", 0, -44)
    ui.status:SetWidth(AREA_W - 8)

    -- your bets: the same board as the solo table, smaller
    ui.spots = {}
    local W, H, GAP = 170, 34, 4
    for i, spot in ipairs(Rules.SPOTS) do
        local b = ns:CreateCrapsSpot(t, spot, W, H, function(key, remove)
            if remove then Do("t", key, T.chip) else Do("b", key, T.chip) end
            ns:Sound("IG_MAINMENU_OPTION")
        end)
        local col, row = ns.Mod(i - 1, 2), math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", t, "TOPLEFT", 4 + col * (W + GAP), -76 - row * (H + GAP))
        ui.spots[i] = b
    end

    -- the players
    ui.seats = {}
    for i = 1, NUM_SEATS do
        local s = {}
        s.frame = ns.CreateFrame("Frame", nil, t)
        s.frame:SetWidth(SEAT_W); s.frame:SetHeight(64)
        s.frame:SetPoint("TOPLEFT", t, "TOPLEFT", (i - 1) * (SEAT_W + SEAT_GAP), -196)
        local bg = s.frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(s.frame)
        bg:SetTexture(0, 0, 0, 0.25)
        s.glow = s.frame:CreateTexture(nil, "BORDER")
        s.glow:SetAllPoints(s.frame)
        s.glow:SetTexture(1, 0.82, 0, 0.16)
        s.glow:Hide()
        s.portrait = ns:CreatePortrait(s.frame, 28, 40)
        s.portrait:SetPoint("TOPLEFT", s.frame, "TOPLEFT", 2, -2)
        s.name = s.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s.name:SetPoint("TOPLEFT", s.frame, "TOPLEFT", 32, -3)
        s.name:SetWidth(SEAT_W - 34)
        s.name:SetJustifyH("LEFT")
        s.stack = s.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.stack:SetPoint("TOPLEFT", s.frame, "TOPLEFT", 32, -17)
        s.stack:SetWidth(SEAT_W - 34)
        s.stack:SetJustifyH("LEFT")
        s.bet = s.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.bet:SetPoint("TOPLEFT", s.frame, "TOPLEFT", 32, -30)
        s.bet:SetWidth(SEAT_W - 34)
        s.bet:SetJustifyH("LEFT")
        s.result = s.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.result:SetPoint("BOTTOMLEFT", s.frame, "BOTTOMLEFT", 4, 5)
        s.result:SetWidth(SEAT_W - 8)
        s.result:SetJustifyH("LEFT")
        ui.seats[i] = s
    end

    -- chip choice, roll, take down, leave
    local chipLabel = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chipLabel:SetPoint("TOPLEFT", t, "TOPLEFT", 6, -272)
    chipLabel:SetText("Chip")
    ui.chipButtons = {}
    for i, v in ipairs(CHIP_VALUES) do
        local v = v   -- own copy for closures (Lua 5.0)
        local b = MakeButton(t, tostring(v), 44, function()
            T.chip = v
            ns:Sound("IG_MAINMENU_OPTION")
            Refresh()
        end)
        b:SetPoint("TOPLEFT", t, "TOPLEFT", 34 + (i - 1) * 48, -268)
        b.chosen = b:CreateTexture(nil, "OVERLAY")    -- marks the chip you bet with
        b.chosen:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
        b.chosen:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
        b.chosen:SetTexture(1, 0.82, 0, 0.35)
        b.chosen:Hide()
        ui.chipButtons[i] = b
    end
    ui.takeDown = MakeButton(t, "Take down", 80, function() Do("c", nil, 0) end)
    ui.takeDown:SetPoint("TOPRIGHT", t, "TOPRIGHT", -6, -268)
    ui.onTable = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.onTable:SetPoint("TOPLEFT", t, "TOPLEFT", 8, -298)

    ui.roll = MakeButton(t, "Roll", 140, function() Do("r", nil, 0) end, 26)
    ui.roll:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 8, 4)
    ui.leave = MakeButton(t, "Leave table", 120, function()
        if T.mode == "host" then Game.HostLeave() else ClientLeave() end
    end, 22)
    ui.leave:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -4, 4)
end

function Game:Build(panel)
    ns.db.partycraps = ns.db.partycraps or {}
    db = ns.db.partycraps
    db.stats = db.stats or {}
    for k, v in pairs(DEFAULT_STATS) do
        if db.stats[k] == nil then db.stats[k] = v end
    end

    self.panel = panel
    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.05, 0.30, 0.12, 1)
    BuildLobby(panel)
    BuildTable(panel)
    ResetToLobby()

    -- A party table can't survive a reload (its stacks are free, so nothing
    -- goes back to your chips).
    local message
    if db.host then
        db.host = nil
        message = "Your craps table closed when the game reloaded."
    end
    if db.seat then
        if db.seat.host and Net:IsMember(db.seat.host) then Net:Send(Msg({ "L", db.seat.tid })) end
        message = "You left " .. (db.seat.host or "the") .. "'s craps table when the game reloaded."
        db.seat = nil
    end
    SetLobbyMessage(message)
    Refresh()
end

function Game:IsSeated()
    return T.mode ~= "lobby"
end

function Game:OnShow()
    if T.mode == "lobby" and Net:InGroup() then Net:Send(Msg({ "Q" })) end
    if ui.table then Refresh() end
end

-- For table chat (Chat.lua): the party table you're at and who's at it.
function Game:ChatTable()
    if (T.mode ~= "host" and T.mode ~= "client") or not T.tid then return nil end
    local host = (T.mode == "host") and Net:Me() or T.host
    local members = { [host] = true }
    for _, p in ipairs(T.seats) do
        if p.kind ~= "empty" and p.name then members[p.name] = true end
    end
    return { game = "CR", host = host, tid = T.tid, members = members }
end

-- For the out-of-chips check: at a party table (its stack is free, but you stay in the game).
function Game:ChipsInPlay()
    -- Party tables are free (everyone plays with the host's stack, not their
    -- chips), but sitting at one still keeps you in the game when you're out.
    return T.mode ~= "lobby"
end

-- A fresh stack after running out (Core.lua): stats start over.
function Game:ResetStats()
    local d = ns.db.partycraps
    if not d then return end
    d.stats = {}
    for k, v in pairs(DEFAULT_STATS) do d.stats[k] = v end
end

-- Exposed for tests.
Game.T, Game.ui = T, ui

Game.parent = "craps"       -- shown inside Craps
ns.PartyCraps = Game
table.insert(ns.partyGames, Game)
