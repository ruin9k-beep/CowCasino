-- CowCasino: Party Blackjack
-- Blackjack's party mode: Blackjack shows this in its window when you choose
-- "Play with your party" (Games\Blackjack.lua), the way Hold'em does.
-- Up to four players from your party or raid against a computer dealer.
-- One player hosts: their client shuffles, deals and settles, and tells the
-- others what happened. Everyone buys in from their own chips and gets their
-- stack back when they leave. Rules match solo Blackjack: blackjack pays 3:2,
-- insurance 2:1, the dealer peeks for blackjack and stands on soft 17;
-- double on any first two cards (also after a split), split once, split
-- aces get one card each, late surrender.
-- If the host disappears mid-round, the round is called off and everyone
-- gets back what they had before it.

local ns = CowCasino.ns

local DEFAULT_STATS = { wins = 0, losses = 0, pushes = 0, blackjacks = 0, buyIns = 0 }

local NUM_SEATS    = 4
local BUY_INS      = { 200, 500, 1000 }
local CHIP_VALUES  = { 5, 25, 100, 500 }
local MIN_BET      = 5
local MAX_BET      = 500
local DECKS        = 6
local BET_TIME     = 20     -- seconds to place bets
local INS_TIME     = 15     -- seconds to decide on insurance
local ACTION_TIME  = 30     -- seconds per decision
local DEALER_DELAY = 0.7    -- seconds between dealer cards
local RESULT_DELAY = 6      -- seconds the results stay up before the next round
local MAX_TIMEOUTS = 2      -- missed turns in a row before a player is removed
local MAX_SITOUTS  = 5      -- betting rounds sat out in a row before a player is removed
local HEARTBEAT    = 15     -- the host re-sends the table this often
local HOST_TIMEOUT = 40
local OFFER_TIMEOUT = 60
local GAME_TAG     = "BJ"

local CARD_W, CARD_H   = 46, 64
local SMALL_W, SMALL_H = 26, 36
local AREA_W           = 352
local SEAT_W, SEAT_GAP = 85, 4
local CARD_STEP        = 11
local MAX_SHOWN        = 6

local Game = {
    id = "partybj",
    name = "Party Blackjack",
    description = "Blackjack with your party against a computer dealer.",
    icon = "Interface\\AddOns\\CowCasino\\Art\\BlackjackIcon",   -- painted (dev/art-src/make_game_icons.py)
}

local Net = ns.Net
local db          -- ns.db.partybj
local ui = {}
local shoe

local T = {
    mode = "lobby",     -- lobby | host | client
    seats = {},
    dealer = {},
    holeHidden = false,
    phase = "waiting",  -- waiting | betting | insurance | playing | dealer | settled
    round = 0,
    version = 0,
    actor = 0,
    handIdx = 0,
    mySeat = 1,
    pending = {},
    offers = {},
    dirtySeats = {},
    partyBuyIn = 500,
    myBet = 25,
}

local function Fmt(n) return ns:FormatChips(n) end
local function Sound(key) ns:Sound(key) end
local function Msg(parts) return GAME_TAG .. ";" .. table.concat(parts, ";") end

local PHASE_CODE = { waiting = "w", betting = "b", insurance = "i", playing = "p", dealer = "d", settled = "s" }
local PHASE_NAME = { w = "waiting", b = "betting", i = "insurance", p = "playing", d = "dealer", s = "settled" }

local RANK_CHARS, SUIT_CHARS = "A23456789TJQK", "shdc"

local function CardCode(c)
    return string.sub(RANK_CHARS, c.rank, c.rank) .. string.sub(SUIT_CHARS, c.suit, c.suit)
end

local function CardsCode(list, hideSecond)
    local s = ""
    for i, c in ipairs(list) do
        if hideSecond and i == 2 then s = s .. "XX" else s = s .. CardCode(c) end
    end
    return s
end

local function DecodeCards(s)
    local out, i = {}, 1
    s = s or ""
    while i < string.len(s) do
        local a, b = string.sub(s, i, i), string.sub(s, i + 1, i + 1)
        if a == "X" then
            table.insert(out, { hidden = true })
        else
            local r = string.find(RANK_CHARS, a, 1, true)
            local u = string.find(SUIT_CHARS, b, 1, true)
            if r and u then table.insert(out, { rank = r, suit = u }) end
        end
        i = i + 2
    end
    return out
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
local function CardValue(c)
    if c.rank == 1 then return 11 end
    if c.rank >= 10 then return 10 end
    return c.rank
end

local function HandValue(cards)
    local total, aces = 0, 0
    for _, c in ipairs(cards) do
        if not c.hidden then
            local v = CardValue(c)
            total = total + v
            if v == 11 then aces = aces + 1 end
        end
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end
    return total, aces > 0
end

local function IsBlackjack(h)
    return ns.getn(h.cards) == 2 and not h.fromSplit and HandValue(h.cards) == 21
end

local function DealerBlackjack()
    return ns.getn(T.dealer) == 2 and not T.dealer[2].hidden and HandValue(T.dealer) == 21
end

local function TotalText(h)
    local cards = h.cards
    if ns.getn(cards) == 0 then return "" end
    if IsBlackjack(h) then return "|cffffd100Blackjack|r" end
    local total, soft = HandValue(cards)
    if total > 21 then return "|cffff5050Bust " .. total .. "|r" end
    if soft and total < 21 then return "Soft " .. total end
    return tostring(total)
end

---------------------------------------------------------------------------
-- Seats
---------------------------------------------------------------------------
local function NewSeat(kind, name, stack)
    return { kind = kind, name = name, stack = stack or 0, bet = 0, hands = {}, insurance = 0 }
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

local function CurrentHand()
    local p = T.seats[T.actor]
    return p and p.hands[T.handIdx]
end

-- Chips we'd hand back if this round were called off now.
-- What this round did to your chips: hands plus insurance.
local function RoundNet(p)
    local net = 0
    for _, h in ipairs(p.hands) do net = net + (h.payout or 0) - h.bet end
    if p.insurance and p.insurance > 0 then
        net = net + ((p.insPaid and p.insurance * 3) or 0) - p.insurance
    end
    return net
end

local function PlayResult(p)
    if ns.getn(p.hands) == 0 then return end
    local net = RoundNet(p)
    if net > 0 then ns:PlayGameSound(ns.db.blackjack, "win")
    elseif net < 0 then ns:PlayGameSound(ns.db.blackjack, "lose") end
end

local function SafeStack(p)
    local s = p.stack
    if p.inRound then
        for _, h in ipairs(p.hands) do s = s + h.bet end
        s = s + (p.insurance or 0)
    end
    return s
end

---------------------------------------------------------------------------
-- Host: telling the table
---------------------------------------------------------------------------
local Refresh, StartBetting, Settle, NextTurn, HostLeave

local function MarkSeat(i) T.dirtySeats[i] = true end
local function MarkAll() for i = 1, NUM_SEATS do T.dirtySeats[i] = true end end

local function Changed()
    T.version = T.version + 1
    T.dirty = true
end

local function SeatMsg(i)
    local p = T.seats[i]
    local hands = { "", "" }
    for k = 1, 2 do
        local h = p.hands[k]
        if h then
            local f = (h.doubled and "d" or "") .. (h.fromSplit and "s" or "") .. (h.splitAces and "a" or "")
                .. (h.surrendered and "u" or "") .. (h.done and "x" or "")
            hands[k] = CardsCode(h.cards) .. ":" .. h.bet .. ":" .. f .. ":" .. (h.result or "") .. ":" .. (h.payout or 0)
        end
    end
    local flags = (p.ready and "r" or "") .. (p.inRound and "i" or "") .. (p.leaving and "l" or "")
        .. (p.insDecided and "y" or "") .. ((p.insPaid == true) and "w" or "") .. ((p.insPaid == false) and "o" or "")
    return Msg({ "Z", T.tid, T.round, i, p.stack or 0, p.bet or 0, p.insurance or 0, flags, hands[1], hands[2] })
end

local function StateMsg()
    local remain = ""
    if T.deadline then remain = math.max(0, math.floor(T.deadline - GetTime() + 0.5)) end
    return Msg({ "P", T.tid, T.version, T.round, PHASE_CODE[T.phase], T.actor, T.handIdx, remain,
        CardsCode(T.dealer, T.holeHidden) })
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
    if T.mode == "host" and HasRemote() then Net:Send(RosterMsg(), "BJ-R") end
end

local function SendOffer()
    if T.mode ~= "host" then return end
    Net:Send(Msg({ "O", T.tid, NUM_SEATS - OpenSeats(), OpenSeats() }), "BJ-O")
end

-- Seat updates first, then the table state, so a client never sees a turn
-- before the cards that go with it.
local function Broadcast()
    T.dirty = false
    if T.mode ~= "host" or not HasRemote() then
        T.dirtySeats = {}
        return
    end
    for i = 1, NUM_SEATS do
        if T.dirtySeats[i] then Net:Send(SeatMsg(i), "BJ-Z" .. i) end
    end
    T.dirtySeats = {}
    Net:Send(StateMsg(), "BJ-P")
end

local function SaveHost()
    if T.mode == "host" then db.host = { stack = SafeStack(Me()) } end
end

---------------------------------------------------------------------------
-- Host: the round
---------------------------------------------------------------------------
local function SeatPlayer(name, buyin)
    for i = 2, NUM_SEATS do
        local p = T.seats[i]
        if p.kind == "remote" and p.name == name then
            if not (p.leaving or p.kicked) then
                Net:Send(Msg({ "S", T.tid, name, i, p.stack }))   -- asked twice
                return
            end
            -- a seat they dropped from mid-round: clear it and seat them fresh
            if p.kicked then Net:Send(Msg({ "K", T.tid, p.name, p.stack })) end
            T.seats[i] = NewSeat("empty")
            MarkSeat(i)
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
    local p = NewSeat("remote", name, buyin)
    p.bet = math.min(25, buyin)
    T.seats[free] = p
    Net:Send(Msg({ "S", T.tid, name, free, buyin }))
    MarkAll()           -- the newcomer needs every seat, not just theirs
    Changed()
    SendRoster()
    SendOffer()
end

local function SeatPending()
    local waiting = T.pending
    T.pending = {}
    for _, w in ipairs(waiting) do
        if Net:IsMember(w.name) then SeatPlayer(w.name, w.buyin) end
    end
end

-- Between rounds: drop players who left or were removed, seat new ones.
local function TidySeats()
    local changed = false
    for i = 2, NUM_SEATS do
        local p = T.seats[i]
        if p.kind == "remote" and (p.leaving or p.kicked) then
            if p.kicked then
                Net:Send(Msg({ "K", T.tid, p.name, p.stack }))
                ns:Print(p.name .. " was removed from your blackjack table for not responding.")
            end
            T.seats[i] = NewSeat("empty")
            MarkSeat(i)
            changed = true
        end
    end
    SeatPending()
    if changed then
        SendRoster()
        SendOffer()
    end
end

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

local function SettleInsurance()
    local dbj = DealerBlackjack()
    for i, p in ipairs(T.seats) do
        if p.inRound and p.insurance > 0 then
            if dbj then p.stack = p.stack + p.insurance * 3 end
            p.insPaid = dbj
            MarkSeat(i)
        end
    end
end

local function DealerPlay()
    T.phase = "dealer"
    T.actor, T.handIdx = 0, 0
    StopClock()
    T.holeHidden = false
    Changed()
    Refresh()

    -- If every hand is bust or surrendered there's nothing to beat.
    local live = false
    for _, p in ipairs(T.seats) do
        if p.inRound then
            for _, h in ipairs(p.hands) do
                if not h.surrendered and HandValue(h.cards) <= 21 and not IsBlackjack(h) then live = true end
            end
        end
    end
    local round = T.round
    local function Step()
        if T.mode ~= "host" or T.round ~= round or T.phase ~= "dealer" then return end
        if live and HandValue(T.dealer) < 17 then
            table.insert(T.dealer, shoe:Draw())
            Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            Changed()
            Refresh()
            ns:After(DEALER_DELAY, Step)
        else
            Settle()
        end
    end
    ns:After(DEALER_DELAY, Step)
end

function Settle()
    local dTotal = HandValue(T.dealer)
    local dbj = DealerBlackjack()
    local me = Me()
    local s = db.stats
    for i, p in ipairs(T.seats) do
        if p.inRound then
            for _, h in ipairs(p.hands) do
                local pv = HandValue(h.cards)
                local pbj = IsBlackjack(h)
                local pay, res
                if h.surrendered then pay, res = ns.SurrenderBack(h.bet), "S"
                elseif pv > 21 then pay, res = 0, "L"
                elseif pbj and not dbj then pay, res = ns.BlackjackPay(h.bet), "B"
                elseif dbj and not pbj then pay, res = 0, "L"
                elseif pbj and dbj then pay, res = h.bet, "P"
                elseif dTotal > 21 or pv > dTotal then pay, res = h.bet * 2, "W"
                elseif pv < dTotal then pay, res = 0, "L"
                else pay, res = h.bet, "P" end
                h.payout, h.result, h.done = pay, res, true
                p.stack = p.stack + pay
                if p == me then
                    if res == "W" or res == "B" then s.wins = s.wins + 1
                    elseif res == "P" then s.pushes = s.pushes + 1
                    else s.losses = s.losses + 1 end
                    if res == "B" then s.blackjacks = s.blackjacks + 1 end
                end
            end
            p.inRound = false
            MarkSeat(i)
        end
    end
    T.phase = "settled"
    T.actor, T.handIdx = 0, 0
    T.holeHidden = false
    StopClock()
    Changed()
    SaveHost()
    PlayResult(Me())
    Refresh()

    if T.closeAfterRound then
        Broadcast()
        HostLeave()
        return
    end
    local round = T.round
    ns:After(RESULT_DELAY, function()
        if T.mode == "host" and T.round == round and T.phase == "settled" then StartBetting() end
    end)
end

-- The next hand that needs a decision, starting from the current one.
function NextTurn()
    local i, k = T.actor, T.handIdx
    if i < 1 then i, k = 1, 1 end
    while i <= NUM_SEATS do
        local p = T.seats[i]
        if p.inRound then
            while k <= ns.getn(p.hands) do
                local h = p.hands[k]
                -- a split hand gets its second card when it comes into play
                if ns.getn(h.cards) < 2 then
                    table.insert(h.cards, shoe:Draw())
                    MarkSeat(i)
                    if h.splitAces then h.done = true end
                end
                if not h.done and HandValue(h.cards) >= 21 then h.done = true end
                if not h.done then
                    T.actor, T.handIdx = i, k
                    Changed()
                    StartClock(ACTION_TIME, function()
                        local q = T.seats[i]
                        q.timeouts = (q.timeouts or 0) + 1
                        if q.kind == "remote" and q.timeouts >= MAX_TIMEOUTS then q.kicked = true end
                        local hh = q.hands[k]
                        if hh then hh.done = true end
                        MarkSeat(i)
                        T.handIdx = k + 1
                        NextTurn()
                    end)
                    Refresh()
                    return
                end
                k = k + 1
            end
        end
        i, k = i + 1, 1
    end
    DealerPlay()
end

local function Peek()
    StopClock()
    if DealerBlackjack() then
        T.holeHidden = false
        SettleInsurance()
        Changed()
        Settle()
        return
    end
    SettleInsurance()
    for i, p in ipairs(T.seats) do
        if p.inRound then
            for _, h in ipairs(p.hands) do
                if IsBlackjack(h) then h.done = true end
            end
            MarkSeat(i)
        end
    end
    T.phase = "playing"
    T.actor, T.handIdx = 1, 1
    NextTurn()
end

local function Deal()
    if shoe.needsShuffle then shoe:Shuffle() end
    local any = false
    for i, p in ipairs(T.seats) do
        p.hands, p.insurance, p.insDecided, p.insPaid = {}, 0, false, nil
        p.inRound = false
        if p.kind == "remote" then
            if p.ready then p.sitOuts = 0 else p.sitOuts = (p.sitOuts or 0) + 1 end
            if p.sitOuts >= MAX_SITOUTS then p.kicked = true end
        end
        if p.kind ~= "empty" and p.ready and p.bet >= MIN_BET and p.bet <= p.stack then
            p.stack = p.stack - p.bet
            p.hands = { { cards = {}, bet = p.bet } }
            p.inRound = true
            p.lastBet = p.bet
            any = true
        end
        p.ready = false
        MarkSeat(i)
    end
    if not any then return false end
    SaveHost()

    T.dealer = {}
    for _ = 1, 2 do
        for _, p in ipairs(T.seats) do
            if p.inRound then table.insert(p.hands[1].cards, shoe:Draw()) end
        end
        table.insert(T.dealer, shoe:Draw())
    end
    T.holeHidden = true
    if Me().inRound then ns:PlayGameSound(ns.db.blackjack, "newHand") end

    if T.dealer[1].rank == 1 then
        T.phase = "insurance"
        for i, p in ipairs(T.seats) do
            -- players who can't afford it, or have blackjack and want even money, still choose
            if p.inRound and p.stack < ns.InsuranceCost(p.hands[1].bet) then p.insDecided = true end
            MarkSeat(i)
        end
        Changed()
        StartClock(INS_TIME, Peek)
        Refresh()
        local all = true
        for _, p in ipairs(T.seats) do
            if p.inRound and not p.insDecided then all = false end
        end
        if all then Peek() end
    else
        Peek()
    end
    return true
end

function StartBetting()
    if T.mode ~= "host" then return end
    TidySeats()
    T.round = T.round + 1
    T.phase = "betting"
    T.dealer, T.holeHidden = {}, false
    T.actor, T.handIdx = 0, 0
    for i, p in ipairs(T.seats) do
        p.hands, p.insurance, p.ready, p.inRound, p.insDecided, p.insPaid = {}, 0, false, false, false, nil
        if p.kind ~= "empty" then
            p.bet = math.min(p.lastBet or p.bet or 25, p.stack)
            if p.bet < MIN_BET then p.bet = 0 end
        end
        MarkSeat(i)
    end
    Changed()
    StartClock(BET_TIME, function()
        if not Deal() then StartBetting() end
    end)
    SaveHost()
    Refresh()
end

-- Everyone who can bet has: deal now.
local function CheckAllReady()
    if T.phase ~= "betting" then return end
    local any, all = false, true
    for _, p in ipairs(T.seats) do
        if p.kind ~= "empty" and p.stack >= MIN_BET then
            if p.ready then any = true else all = false end
        end
    end
    if any and all then
        StopClock()
        Deal()
    end
end

---------------------------------------------------------------------------
-- Host: applying a player's decision (local or from the network)
---------------------------------------------------------------------------
local function CanDouble(p, h)
    return h and ns.getn(h.cards) == 2 and not h.splitAces and p.stack >= h.bet
end

local function CanSplit(p, h)
    return h and ns.getn(h.cards) == 2 and ns.getn(p.hands) == 1 and p.stack >= h.bet
        and CardValue(h.cards[1]) == CardValue(h.cards[2])
end

local function CanSurrender(p, h)
    return h and ns.getn(p.hands) == 1 and ns.getn(h.cards) == 2 and not h.fromSplit
end

local function HostAct(i, code, amount)
    local p = T.seats[i]
    if not p or p.kind == "empty" then return end

    if code == "B" then
        if T.phase ~= "betting" then return end
        amount = tonumber(amount) or 0
        if amount < MIN_BET or amount > MAX_BET or amount > p.stack then return end
        p.bet, p.ready = amount, true
        MarkSeat(i)
        Changed()
        Refresh()
        CheckAllReady()
        return
    elseif code == "y" or code == "n" then
        if T.phase ~= "insurance" or not p.inRound or p.insDecided then return end
        if code == "y" then
            local cost = ns.InsuranceCost(p.hands[1].bet)
            if p.stack >= cost then
                p.stack = p.stack - cost
                p.insurance = cost
            end
        end
        p.insDecided = true
        MarkSeat(i)
        Changed()
        Refresh()
        for _, q in ipairs(T.seats) do
            if q.inRound and not q.insDecided then return end
        end
        Peek()
        return
    end

    -- Playing decisions: only for the hand whose turn it is.
    if T.phase ~= "playing" or T.actor ~= i then return end
    local h = p.hands[T.handIdx]
    if not h or h.done then return end
    p.timeouts = 0
    if code == "h" then
        table.insert(h.cards, shoe:Draw())
        if HandValue(h.cards) >= 21 then h.done = true end
    elseif code == "s" then
        h.done = true
    elseif code == "d" then
        if not CanDouble(p, h) then return end
        p.stack = p.stack - h.bet
        h.bet = h.bet * 2
        h.doubled = true
        table.insert(h.cards, shoe:Draw())
        h.done = true
    elseif code == "p" then
        if not CanSplit(p, h) then return end
        p.stack = p.stack - h.bet
        local second = { cards = { table.remove(h.cards) }, bet = h.bet, fromSplit = true }
        h.fromSplit = true
        if h.cards[1].rank == 1 then
            h.splitAces, second.splitAces = true, true
        end
        table.insert(p.hands, second)
        table.insert(h.cards, shoe:Draw())
        if h.splitAces then h.done = true end
    elseif code == "u" then
        if not CanSurrender(p, h) then return end
        h.surrendered, h.done = true, true
    else
        return
    end
    Sound("IG_MAINMENU_OPTION")
    MarkSeat(i)
    StopClock()
    Changed()
    if h.done then T.handIdx = T.handIdx + 1 end
    NextTurn()
end

---------------------------------------------------------------------------
-- Leaving, hosting, joining
---------------------------------------------------------------------------
local function ResetToLobby()
    T.mode, T.mySeat = "lobby", 1
    T.seats, T.dealer = {}, {}
    T.phase, T.actor, T.handIdx, T.holeHidden = "waiting", 0, 0, false
    T.round = T.round + 1          -- stops timers from the old table
    T.deadline, T.sent, T.dirty = nil, nil, false
    T.tid, T.host, T.closeAfterRound = nil, nil, nil
    T.pending, T.dirtySeats = {}, {}
    StopClock()
end

local function SetLobbyMessage(text) if ui.lobbyMsg then ui.lobbyMsg:SetText(text or "") end end

function HostLeave()
    if T.mode ~= "host" then return end
    local playing = T.phase == "insurance" or T.phase == "playing" or T.phase == "dealer"
    if playing then
        T.closeAfterRound = true
        Refresh()
        return
    end
    local stack = Me().stack
    Net:Send(Msg({ "X", T.tid }))
    if stack > 0 then ns:AddChips(stack) end
    db.host = nil
    ResetToLobby()
    SetLobbyMessage("You closed your table with " .. Fmt(stack) .. " chips.")
    Refresh()
end

local function HostTable(buyin)
    if T.mode ~= "lobby" or not Net:InGroup() or not ns:SpendChips(buyin) then return end
    db.stats.buyIns = db.stats.buyIns + 1
    T.mode, T.mySeat = "host", 1
    T.tid = tostring(math.random(1, 99999))
    T.version, T.pending = 0, {}
    T.seats = { NewSeat("you", Net:Me(), buyin) }
    for i = 2, NUM_SEATS do T.seats[i] = NewSeat("empty") end
    T.seats[1].bet = math.min(T.myBet, buyin)
    shoe = ns:NewShoe(DECKS)
    db.host = { stack = buyin }
    SendOffer()
    StartBetting()
end

local function HostDropPlayer(i)
    local p = T.seats[i]
    if not p or p.kind ~= "remote" then return end
    p.leaving = true
    p.ready = false
    MarkSeat(i)
    if not p.inRound then
        T.seats[i] = NewSeat("empty")
        MarkSeat(i)
        Changed()
        SendRoster()
        SendOffer()
        Refresh()
        CheckAllReady()
        return
    end
    -- Mid-round: their hands stand as they are (and are settled normally).
    for _, h in ipairs(p.hands) do h.done = true end
    p.insDecided = true
    Changed()
    if T.phase == "insurance" then
        for _, q in ipairs(T.seats) do
            if q.inRound and not q.insDecided then
                Refresh()
                return
            end
        end
        Peek()
    elseif T.phase == "playing" and T.actor == i then
        StopClock()
        T.handIdx = ns.getn(p.hands) + 1
        NextTurn()
    else
        Refresh()
    end
end

-- Client side ---------------------------------------------------------------
local function ClientCashOut(amount, message)
    if amount and amount > 0 then ns:AddChips(amount) end
    db.seat = nil
    ResetToLobby()
    SetLobbyMessage(message .. ((amount and amount > 0) and (" You got " .. Fmt(amount) .. " chips back.") or ""))
    Refresh()
end

local function HostGone(message)
    if T.mode ~= "client" then return end
    ClientCashOut(db.seat and db.seat.stack or 0, message)
end

local function ClientLeave()
    if T.mode ~= "client" then return end
    local me = Me()
    if me.inRound then return end
    Net:Send(Msg({ "L", T.tid }))
    ClientCashOut(me.stack, "You left " .. (T.host or "the host") .. "'s table.")
end

local function JoinTable(host, tid)
    local buyin = T.partyBuyIn
    if T.mode ~= "lobby" then return end
    if ns.db.chips < buyin then
        SetLobbyMessage("You need " .. Fmt(buyin) .. " chips for that buy-in.")
        return
    end
    T.joining = { host = host, tid = tid, buyin = buyin, at = GetTime() }
    Net:Send(Msg({ "J", tid, buyin }))
    SetLobbyMessage("Asking " .. host .. " for a seat...")
end

-- Your decisions, local or sent to the host.
local function Do(code, amount)
    if T.mode == "host" then
        HostAct(MySeat(), code, amount)
    elseif T.mode == "client" then
        local isPlay = code ~= "B" and code ~= "y" and code ~= "n"
        if isPlay and T.sent == T.version then return end
        T.sent = T.version
        Net:Send(Msg({ "A", T.tid, T.version, T.round, code, amount or 0 }))
        Refresh()
    end
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local function ParseHand(s)
    if not s or s == "" then return nil end
    local f = Net.Split(s, ":")
    local flags = f[3] or ""
    return {
        cards = DecodeCards(f[1]),
        bet = tonumber(f[2]) or 0,
        doubled = string.find(flags, "d", 1, true) ~= nil,
        fromSplit = string.find(flags, "s", 1, true) ~= nil,
        splitAces = string.find(flags, "a", 1, true) ~= nil,
        surrendered = string.find(flags, "u", 1, true) ~= nil,
        done = string.find(flags, "x", 1, true) ~= nil,
        result = (f[4] and f[4] ~= "") and f[4] or nil,
        payout = tonumber(f[5]) or 0,
    }
end

local function ClientSeat(f)
    local i = tonumber(f[5])
    local p = i and T.seats[i]
    if not p then return end
    p.stack = tonumber(f[6]) or 0
    p.bet = tonumber(f[7]) or 0
    p.insurance = tonumber(f[8]) or 0
    local flags = f[9] or ""
    p.ready = string.find(flags, "r", 1, true) ~= nil
    p.inRound = string.find(flags, "i", 1, true) ~= nil
    p.leaving = string.find(flags, "l", 1, true) ~= nil
    p.insDecided = string.find(flags, "y", 1, true) ~= nil
    if string.find(flags, "w", 1, true) then p.insPaid = true
    elseif string.find(flags, "o", 1, true) then p.insPaid = false
    else p.insPaid = nil end
    p.hands = {}
    local h1, h2 = ParseHand(f[10]), ParseHand(f[11])
    if h1 then table.insert(p.hands, h1) end
    if h2 then table.insert(p.hands, h2) end
    if IsMine(i) then
        db.seat = { host = T.host, tid = T.tid, stack = SafeStack(p) }
        -- stats, once per settled hand
        if T.statRound ~= tonumber(f[4]) and h1 and h1.result then
            T.statRound = tonumber(f[4])
            local s = db.stats
            for _, h in ipairs(p.hands) do
                if h.result == "W" or h.result == "B" then s.wins = s.wins + 1
                elseif h.result == "P" then s.pushes = s.pushes + 1
                else s.losses = s.losses + 1 end
                if h.result == "B" then s.blackjacks = s.blackjacks + 1 end
            end
        end
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

local function ClientState(f)
    local wasMyTurn = T.phase == "playing" and T.actor == MySeat()
    T.version = tonumber(f[4]) or 0
    T.round = tonumber(f[5]) or 0
    T.phase = PHASE_NAME[f[6]] or "waiting"
    T.actor = tonumber(f[7]) or 0
    T.handIdx = tonumber(f[8]) or 0
    T.deadline = (f[9] and f[9] ~= "") and (GetTime() + tonumber(f[9])) or nil
    T.dealer = DecodeCards(f[10])
    T.holeHidden = T.dealer[2] ~= nil and T.dealer[2].hidden == true
    if T.phase == "playing" and T.actor == MySeat() and not wasMyTurn then
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    end
    if T.phase == "settled" and T.soundRound ~= T.round then
        T.soundRound = T.round
        PlayResult(Me())
    end
    if T.dealtRound ~= T.round and ns.getn(T.dealer) > 0 and Me().inRound then
        T.dealtRound = T.round
        ns:PlayGameSound(ns.db.blackjack, "newHand")
    end
    Refresh()
end

local function OnMessage(sender, f)
    local kind, tid = f[2], f[3]
    if kind == "X" then
        T.offers[sender] = nil
        if T.joining and T.joining.host == sender then
            T.joining = nil
            SetLobbyMessage(sender .. " closed the table.")
            Refresh()
        end
    end
    if kind == "Q" then
        if T.mode == "host" then SendOffer() end
        return
    elseif kind == "O" then
        T.offers[sender] = { tid = tid, players = tonumber(f[4]) or 0, open = tonumber(f[5]) or 0, heard = GetTime() }
        if T.mode == "lobby" then Refresh() end
        return
    end

    if T.mode == "host" and tid == T.tid then
        if kind == "J" then
            local buyin = tonumber(f[4]) or 0
            local valid = false
            for _, b in ipairs(BUY_INS) do
                if b == buyin then valid = true end
            end
            if not valid then return end
            if T.phase == "betting" or T.phase == "settled" or T.phase == "waiting" then
                SeatPlayer(sender, buyin)
                Refresh()
                CheckAllReady()
            else
                for _, w in ipairs(T.pending) do
                    if w.name == sender then return end
                end
                table.insert(T.pending, { name = sender, buyin = buyin })
                Net:Send(Msg({ "N", T.tid, sender, "wait" }))
            end
        elseif kind == "A" then
            local i
            for s = 2, NUM_SEATS do
                if T.seats[s].kind == "remote" and T.seats[s].name == sender then i = s end
            end
            if not i then return end
            local code = f[6]
            local isPlay = code ~= "B" and code ~= "y" and code ~= "n"
            if tonumber(f[5]) ~= T.round then return end
            if isPlay and tonumber(f[4]) ~= T.version then return end
            HostAct(i, code, f[7])
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
            if not seat or not ns:SpendChips(stack) then
                Net:Send(Msg({ "L", tid }))
                return
            end
            db.stats.buyIns = db.stats.buyIns + 1
            T.mode, T.host, T.tid, T.mySeat = "client", sender, tid, seat
            T.seats = {}
            for i = 1, NUM_SEATS do T.seats[i] = NewSeat("empty") end
            T.seats[seat] = NewSeat("human", Net:Me(), stack)
            T.phase, T.version, T.lastHeard = "waiting", 0, GetTime()
            db.seat = { host = sender, tid = tid, stack = stack }
            Refresh()
        elseif kind == "N" and f[4] == Net:Me() then
            if f[5] == "wait" then
                T.joining.waiting = true
                SetLobbyMessage(sender .. " will seat you after this round.")
            else
                T.joining = nil
                SetLobbyMessage(f[5] or "No seat.")
            end
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
        ClientState(f)
    elseif kind == "K" then
        if f[4] == Net:Me() then
            ClientCashOut(tonumber(f[5]) or 0, "You were removed from " .. sender .. "'s table for not responding.")
        end
    elseif kind == "X" then
        HostGone(sender .. " closed the table.")
    end
end

Net.handlers[GAME_TAG] = OnMessage

Net.groupHandlers.partybj = function()
    if T.mode == "host" then
        for i = 2, NUM_SEATS do
            local p = T.seats[i]
            if p.kind == "remote" and not Net:IsMember(p.name) then HostDropPlayer(i) end
        end
        local still = {}
        for _, w in ipairs(T.pending) do
            if Net:IsMember(w.name) then table.insert(still, w) end
        end
        T.pending = still
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
    if T.joining and not T.joining.waiting and GetTime() - T.joining.at > 15 then
        SetLobbyMessage("No answer from " .. T.joining.host .. ".")
        T.joining = nil
        Refresh()
    end
end)

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local RESULT_TEXT = { W = "|cff40ff40Win|r", B = "|cffffd100Blackjack!|r", P = "|cffccccccPush|r",
                      L = "|cffff5050Lose|r", S = "|cffccccccSurrender|r" }

local function SetStatus(text, r, g, b)
    ui.status:SetText(text or "")
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function SeatName(i)
    local p = T.seats[i]
    if p.kind == "empty" then return "|cff888888Empty seat|r" end
    if IsMine(i) then return "You" end
    return p.name or "?"
end

local function RefreshLobby()
    local inGroup = Net:InGroup()
    ui.groupInfo:SetText(inGroup and ("You're in a group of " .. Net:GroupSize() .. ". Everyone needs CowCasino to play.")
        or "Join a party or raid to play with friends.")
    ui.buyIn:SetText(Fmt(T.partyBuyIn))
    ns.SetEnabled(ui.host, inGroup and ns.db.chips >= T.partyBuyIn)

    local list = {}
    for name, offer in pairs(T.offers) do
        if GetTime() - offer.heard < OFFER_TIMEOUT and Net:IsMember(name) then
            table.insert(list, { host = name, tid = offer.tid, players = offer.players, open = offer.open })
        end
    end
    table.sort(list, function(a, b) return a.host < b.host end)
    for r = 1, 3 do
        local row, offer = ui.rows[r], list[r]
        row.offer = offer
        if offer then
            row.text:SetText(string.format("%s's table - %d playing, %d open", offer.host, offer.players, offer.open))
            row.join:Show()
            ns.SetEnabled(row.join, offer.open > 0 and ns.db.chips >= T.partyBuyIn and not T.joining)
        else
            row.text:SetText((r == 1 and inGroup) and "|cff888888No tables yet. Ask someone to host, or host one.|r" or "")
            row.join:Hide()
        end
    end
    local s = db.stats
    ui.lobbyStats:SetText(string.format("Hands won %d   Lost %d   Pushes %d   Blackjacks %d",
        s.wins, s.losses, s.pushes, s.blackjacks))
end

local function LayoutCards(widgets, cards, x0, y0, parent, w, h, step)
    for c = 1, ns.getn(widgets) do
        local wd, card = widgets[c], cards[c]
        if card then
            wd:ClearAllPoints()
            wd:SetPoint("TOPLEFT", parent, "TOPLEFT", x0 + (c - 1) * step, y0)
            wd:SetCard(card.hidden and { rank = 1, suit = 1 } or card, not card.hidden)
        else
            wd:Clear()
        end
    end
end

local function RefreshSeat(i)
    local p, s = T.seats[i], ui.seats[i]
    s.name:SetText(SeatName(i))
    if p.kind == "empty" then s.portrait:ShowUnit(nil)
    elseif IsMine(i) then s.portrait:ShowUnit("player")
    else s.portrait:ShowUnit(Net:UnitFor(p.name)) end
    if p.kind == "empty" then
        s.stack:SetText("")
        s.bet:SetText("")
    else
        s.stack:SetText(Fmt(p.stack))
        local line = ""
        if T.phase == "betting" then
            if p.ready then line = "|cff40ff40Bet " .. Fmt(p.bet) .. "|r"
            elseif p.stack < MIN_BET then line = "Out of chips"
            else line = "Betting..." end
        elseif p.inRound or ns.getn(p.hands) > 0 then
            local total = 0
            for _, h in ipairs(p.hands) do total = total + h.bet end
            line = "Bet " .. Fmt(total)
            if p.insurance and p.insurance > 0 then
                if p.insPaid == true then line = line .. " |cff40ff40ins +" .. Fmt(p.insurance * 2) .. "|r"
                elseif p.insPaid == false then line = line .. " |cffff5050ins lost|r"
                else line = line .. " +ins" end
            end
        end
        if p.leaving then line = "Leaving" end
        s.bet:SetText(line)
    end
    for k = 1, 2 do
        local row, h = s.hands[k], p.hands[k]
        if h then
            LayoutCards(row.cards, h.cards, 2, row.y, s.frame, SMALL_W, SMALL_H, CARD_STEP)
            local text = TotalText(h)
            if h.result then
                text = RESULT_TEXT[h.result] or ""
                local net = (h.payout or 0) - h.bet
                if net ~= 0 then text = text .. (net > 0 and " +" or " -") .. Fmt(math.abs(net)) end
            elseif h.doubled then
                text = text .. " (x2)"
            end
            if T.phase == "playing" and T.actor == i and T.handIdx == k then text = "> " .. text end
            row.total:SetText(text)
        else
            for _, wd in ipairs(row.cards) do wd:Clear() end
            row.total:SetText("")
        end
    end
    local acting = (T.phase == "playing" and T.actor == i)
        or (T.phase == "insurance" and p.inRound and not p.insDecided)
        or (T.phase == "betting" and p.kind ~= "empty" and not p.ready and p.stack >= MIN_BET)
    ns.SetShown(s.glow, acting)
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

    -- Dealer
    local shown = T.dealer
    if T.holeHidden and T.dealer[2] then
        shown = { T.dealer[1], { hidden = true } }     -- face down on every screen, the host's too
        for k = 3, ns.getn(T.dealer) do shown[k] = T.dealer[k] end
    end
    LayoutCards(ui.dealerCards, shown, (AREA_W - (CARD_W + 4 * 20)) / 2, -18, ui.table, CARD_W, CARD_H, 20)
    if ns.getn(T.dealer) == 0 then
        ui.dealerLabel:SetText("Dealer")
    elseif T.holeHidden then
        ui.dealerLabel:SetText("Dealer shows " .. HandValue({ T.dealer[1] }))
    else
        ui.dealerLabel:SetText("Dealer: " .. TotalText({ cards = T.dealer }))
    end

    for i = 1, NUM_SEATS do RefreshSeat(i) end

    local me = Me()
    local left = T.deadline and math.max(0, math.ceil(T.deadline - GetTime())) or nil
    local function Clock(text) return left and (text .. " (" .. left .. "s)") or text end

    -- What's happening, from your seat.
    local myHand = (T.phase == "playing" and T.actor == MySeat()) and me.hands[T.handIdx] or nil
    local sent = T.mode == "client" and T.sent == T.version
    if T.phase == "betting" then
        if me.ready then SetStatus(Clock("Your bet is in. Waiting for the others"))
        elseif me.stack < MIN_BET then SetStatus("You're out of chips at this table. Leave to cash out.", 1, 0.35, 0.35)
        else SetStatus(Clock("Place your bet")) end
    elseif T.phase == "insurance" then
        if me.inRound and not me.insDecided then SetStatus(Clock("Dealer shows an Ace. Insurance?"))
        else SetStatus(Clock("Waiting for insurance decisions")) end
    elseif T.phase == "playing" then
        if myHand and not sent then
            SetStatus(Clock(ns.getn(me.hands) > 1 and ("Your move - hand " .. T.handIdx) or "Your move"))
        elseif T.actor > 0 then
            SetStatus(Clock("Waiting for " .. SeatName(T.actor)))
        end
    elseif T.phase == "dealer" then
        SetStatus("Dealer's turn...")
    elseif T.phase == "settled" then
        local net = RoundNet(me)
        local ins = ""
        if me.insurance and me.insurance > 0 then
            ins = me.insPaid and (" Insurance paid " .. Fmt(me.insurance * 2) .. ".") or " Insurance lost."
        end
        if ns.getn(me.hands) == 0 then SetStatus("Next round soon.")
        elseif net > 0 then SetStatus("You win " .. Fmt(net) .. "!" .. ins, 0.25, 1, 0.25)
        elseif net < 0 then SetStatus("You lose " .. Fmt(-net) .. "." .. ins, 1, 0.35, 0.35)
        else SetStatus("Even." .. ins, 0.85, 0.85, 0.85) end
    else
        SetStatus("Waiting for players.")
    end
    if T.closeAfterRound then ui.partyLabel:SetText("Closing after this round")
    elseif T.mode == "host" then ui.partyLabel:SetText("Your table")
    else ui.partyLabel:SetText((T.host or "?") .. "'s table") end

    -- Controls
    local betting = T.phase == "betting" and not me.ready and me.stack >= MIN_BET
    local insuring = T.phase == "insurance" and me.inRound and not me.insDecided
    local playing = myHand ~= nil and not sent
    ns.SetShown(ui.betRow, betting)
    ns.SetShown(ui.insRow, insuring)
    ns.SetShown(ui.playRow, playing)
    if betting then
        T.myBet = math.max(0, math.min(T.myBet, MAX_BET, me.stack))
        ui.betAmount:SetText("Bet " .. Fmt(T.myBet))
        ns.SetEnabled(ui.placeBet, T.myBet >= MIN_BET)
    end
    if insuring then
        ui.insure:SetText("Insure " .. Fmt(ns.InsuranceCost(me.hands[1].bet)))
        ns.SetEnabled(ui.insure, me.stack >= ns.InsuranceCost(me.hands[1].bet))
    end
    if playing then
        ns.SetEnabled(ui.hit, not myHand.splitAces)
        ns.SetEnabled(ui.double, CanDouble(me, myHand))
        ns.SetEnabled(ui.split, CanSplit(me, myHand))
        ns.SetEnabled(ui.surrender, CanSurrender(me, myHand))
    end

    if T.mode == "host" then
        local mid = T.phase == "insurance" or T.phase == "playing" or T.phase == "dealer"
        if T.closeAfterRound then ui.leave:SetText("Closing...")
        elseif mid then ui.leave:SetText("Close after round")
        else ui.leave:SetText("Close table") end
        ns.SetEnabled(ui.leave, not T.closeAfterRound)
    else
        ui.leave:SetText("Leave table")
        ns.SetEnabled(ui.leave, not me.inRound)
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
    b:SetScript("OnClick", function() local self, button = this, arg1 onClick(self, button) end)
    return b
end

local function BuildLobby(panel)
    local l = ns.CreateFrame("Frame", nil, panel)
    l:SetAllPoints(panel)
    ui.lobby = l

    local title = ns:BigFont(l:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 22)
    title:SetPoint("TOP", l, "TOP", 0, -14)
    title:SetText("Party Blackjack")

    local info = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOP", title, "BOTTOM", 0, -8)
    info:SetWidth(AREA_W - 24)
    info:SetText("Up to four players from your group against a computer dealer. Buy in from your chips; "
        .. "your stack goes back to your chips when you leave.")

    ui.groupInfo = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.groupInfo:SetPoint("TOP", l, "TOP", 0, -84)
    ui.groupInfo:SetWidth(AREA_W - 24)

    local label = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", l, "TOPLEFT", 16, -112)
    label:SetText("Buy-in")
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

    ui.dealerLabel = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.dealerLabel:SetPoint("TOP", t, "TOP", 0, -2)
    ui.dealerCards = {}
    for c = 1, 8 do
        local w = ns:CreateCardWidget(t, CARD_W, CARD_H)
        w:SetLevel(t:GetFrameLevel() + 2 + c * 3)
        ui.dealerCards[c] = w
    end

    ui.partyLabel = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.partyLabel:SetPoint("TOPLEFT", t, "TOPLEFT", 4, -4)

    ui.status = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", t, "TOP", 0, -90)
    ui.status:SetWidth(AREA_W - 8)

    ui.seats = {}
    for i = 1, NUM_SEATS do
        local s = { hands = {} }
        s.frame = ns.CreateFrame("Frame", nil, t)
        s.frame:SetWidth(SEAT_W); s.frame:SetHeight(176)
        s.frame:SetPoint("TOPLEFT", t, "TOPLEFT", (i - 1) * (SEAT_W + SEAT_GAP), -108)
        local bg = s.frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(s.frame)
        bg:SetTexture(0, 0, 0, 0.25)
        s.glow = s.frame:CreateTexture(nil, "BORDER")
        s.glow:SetAllPoints(s.frame)
        s.glow:SetTexture(1, 0.82, 0, 0.16)
        s.glow:Hide()
        -- portrait in the corner, name / stack / bet beside it
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
        for k = 1, 2 do
            local row = { cards = {}, y = -46 - (k - 1) * 64 }
            for c = 1, MAX_SHOWN do
                local w = ns:CreateCardWidget(s.frame, SMALL_W, SMALL_H)
                w:SetLevel(s.frame:GetFrameLevel() + 2 + c * 3)
                row.cards[c] = w
            end
            row.total = s.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.total:SetPoint("TOPLEFT", s.frame, "TOPLEFT", 3, row.y - SMALL_H - 3)
            row.total:SetWidth(SEAT_W - 6)
            row.total:SetJustifyH("LEFT")
            s.hands[k] = row
        end
        ui.seats[i] = s
    end

    -- Betting
    ui.betRow = ns.CreateFrame("Frame", nil, t)
    ui.betRow:SetWidth(AREA_W); ui.betRow:SetHeight(52)
    ui.betRow:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -290)
    local x = 6
    for _, v in ipairs(CHIP_VALUES) do
        local v = v   -- own copy for closures (Lua 5.0)
        local b = MakeButton(ui.betRow, tostring(v), 44, function(_, button)
            if button == "RightButton" then T.myBet = T.myBet - v else T.myBet = T.myBet + v end
            Refresh()
        end)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetPoint("TOPLEFT", ui.betRow, "TOPLEFT", x, 0)
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText("Chip " .. v)
            GameTooltip:AddLine("Left-click to add, right-click to take back.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        x = x + 48
    end
    local clear = MakeButton(ui.betRow, "Clear", 50, function() T.myBet = 0; Refresh() end)
    clear:SetPoint("TOPLEFT", ui.betRow, "TOPLEFT", x, 0)
    ui.betAmount = ui.betRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.betAmount:SetPoint("TOPLEFT", ui.betRow, "TOPLEFT", 10, -32)
    ui.placeBet = MakeButton(ui.betRow, "Place bet", 110, function() Do("B", T.myBet) end, 24)
    ui.placeBet:SetPoint("TOPLEFT", ui.betRow, "TOPLEFT", 130, -26)

    -- Insurance
    ui.insRow = ns.CreateFrame("Frame", nil, t)
    ui.insRow:SetWidth(AREA_W); ui.insRow:SetHeight(26)
    ui.insRow:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -300)
    ui.insure = MakeButton(ui.insRow, "Insure", 120, function() Do("y") end, 26)
    ui.insure:SetPoint("LEFT", ui.insRow, "LEFT", 50, 0)
    local noIns = MakeButton(ui.insRow, "No thanks", 120, function() Do("n") end, 26)
    noIns:SetPoint("LEFT", ui.insure, "RIGHT", 10, 0)

    -- Playing
    ui.playRow = ns.CreateFrame("Frame", nil, t)
    ui.playRow:SetWidth(AREA_W); ui.playRow:SetHeight(26)
    ui.playRow:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -300)
    local specs = {
        { "Hit", 62, "h", "hit" }, { "Stand", 62, "s", "stand" }, { "Double", 62, "d", "double" },
        { "Split", 58, "p", "split" }, { "Surrender", 74, "u", "surrender" },
    }
    x = 6
    for _, spec in ipairs(specs) do
        local spec = spec   -- own copy for closures (Lua 5.0)
        local code = spec[3]
        local b = MakeButton(ui.playRow, spec[1], spec[2], function() Do(code) end, 26)
        b:SetPoint("LEFT", ui.playRow, "LEFT", x, 0)
        x = x + spec[2] + 4
        ui[spec[4]] = b
    end

    ui.leave = MakeButton(t, "Leave table", 120, function()
        if T.mode == "host" then HostLeave() else ClientLeave() end
    end, 22)
    ui.leave:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -4, 2)
end

function Game:Build(panel)
    ns.db.partybj = ns.db.partybj or {}
    db = ns.db.partybj
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

    -- A party table can't survive a reload: pay back what was safe.
    local message
    if db.host then
        local stack = db.host.stack or 0
        if stack > 0 then ns:AddChips(stack) end
        db.host = nil
        message = "Your blackjack table closed when the game reloaded; " .. Fmt(stack) .. " chips went back to you."
    end
    if db.seat then
        local stack = db.seat.stack or 0
        if db.seat.host and Net:IsMember(db.seat.host) then Net:Send(Msg({ "L", db.seat.tid })) end
        if stack > 0 then ns:AddChips(stack) end
        message = "You left " .. (db.seat.host or "the") .. "'s blackjack table when the game reloaded; "
            .. Fmt(stack) .. " chips went back to you."
        db.seat = nil
    end
    SetLobbyMessage(message)
    Refresh()
end

-- At a party table (hosting or seated)?
function Game:IsSeated()
    return T.mode ~= "lobby"
end

function Game:OnShow()
    if T.mode == "lobby" and Net:InGroup() then Net:Send(Msg({ "Q" })) end
    if ui.table then Refresh() end
end

-- Exposed for tests.
Game.T, Game.ui = T, ui
Game.HandValue, Game.IsBlackjack = HandValue, IsBlackjack

-- For table chat (Chat.lua): the party table you're at and who's at it.
function Game:ChatTable()
    if (T.mode ~= "host" and T.mode ~= "client") or not T.tid then return nil end
    local host = (T.mode == "host") and Net:Me() or T.host
    local members = { [host] = true }
    for _, p in ipairs(T.seats) do
        if p.kind ~= "empty" and p.kind ~= "bot" and p.name then members[p.name] = true end
    end
    return { game = "BJ", host = host, tid = T.tid, members = members }
end

-- For the out-of-chips check: seated at a party table, or a seat saved from a reload.
function Game:ChipsInPlay()
    local d = ns.db.partybj
    if T.mode ~= "lobby" then return true end
    return d ~= nil and (d.seat ~= nil or d.host ~= nil)
end

-- A fresh stack after running out (Core.lua): stats start over.
function Game:ResetStats()
    local d = ns.db.partybj
    if not d then return end
    d.stats = {}
    for k, v in pairs(DEFAULT_STATS) do d.stats[k] = v end
end

Game.parent = "blackjack"   -- shown inside Blackjack
ns.PartyBlackjack = Game
table.insert(ns.partyGames, Game)
