-- CowCasino: Texas Hold'em
-- No-limit hold'em against computer players or your party. The blinds are
-- picked in Options (5/10 to start) and buy-ins are 20, 50 or 100 big blinds.
-- A table keeps its blinds while it lasts; a party table uses the host's.
-- Buy in from the chip wallet; your stack goes back to the wallet when you
-- leave the table. Busted opponents are replaced by fresh ones.
-- Cards are drawn by the selected card art (Cards.lua).
-- If a hand is interrupted by a reload or logout, it is canceled and every
-- stack goes back to what it was before that hand.

local ns = CowCasino.ns

local BLIND_LEVELS  = { { 1, 2 }, { 5, 10 }, { 10, 20 }, { 25, 50 }, { 50, 100 }, { 100, 200 } }
local DEFAULT_BLINDS = 2         -- 5/10
local BUY_IN_BB     = { 20, 50, 100 }   -- buy-ins, in big blinds
local SB, BB        = 5, 10      -- the blinds at your table (set when you sit down)
local BOT_STACK_MIN = 600        -- computer players' stacks at 5/10 when there's no buy-in to
local BOT_STACK_MAX = 1400       -- match (normally they start with what you bought in for)
local NUM_SEATS     = 4          -- seat 1 is you, 2-4 go clockwise
local ACT_DELAY     = 0.8        -- seconds before a computer player acts
local STREET_DELAY  = 1.0        -- seconds before the next cards are dealt
local MAX_RAISES    = 4          -- computer players stop re-raising after this many raises in a round

local CARD_W, CARD_H   = 46, 64
local SMALL_W, SMALL_H = 30, 42
local AREA_W           = 352

local BOT_NAMES = { "Grimble", "Tazzik", "Old Hobbs", "Mirela", "Brannock", "Zuzu", "Felwick",
                    "Pip", "Dorna", "Krask", "Velma", "Thistle", "Sorrel", "Bix", "Marnie", "Gorbo" }

local RANK_NAME   = { [2] = "Two", [3] = "Three", [4] = "Four", [5] = "Five", [6] = "Six", [7] = "Seven",
                      [8] = "Eight", [9] = "Nine", [10] = "Ten", [11] = "Jack", [12] = "Queen", [13] = "King", [14] = "Ace" }
local RANK_PLURAL = { [2] = "Twos", [3] = "Threes", [4] = "Fours", [5] = "Fives", [6] = "Sixes", [7] = "Sevens",
                      [8] = "Eights", [9] = "Nines", [10] = "Tens", [11] = "Jacks", [12] = "Queens", [13] = "Kings", [14] = "Aces" }

local DEFAULT_STATS = { hands = 0, won = 0, biggestPot = 0, buyIns = 0 }

local Poker = {
    id = "holdem",
    name = "Texas Hold'em",
    description = "No-limit poker against three computer players.\n|cff66ccffSupports Multiplayer|r",
    icon = "Interface\\AddOns\\CowCasino\\Art\\HoldemIcon",   -- painted (dev/art-src/make_game_icons.py)
    -- the dealer on top of the window (Dealer.lua): the one picked in Options
    dealer = { idle = "Shuffle up and deal." },
}

local db      -- ns.db.holdem
local ui = {}
local shoe
local sims = 150   -- Monte Carlo deals per computer decision

-- Table state. seats[i] = { name, stack, isHuman, style, hole, bet, total,
--   folded, allIn, acted, last, score, won }
local T = {
    seats = {},
    button = 1,
    board = {},
    pot = 0,             -- chips from finished betting rounds
    currentBet = 0,
    lastRaise = BB,      -- size of the last full raise (minimum raise increment)
    raises = 0,
    street = "idle",     -- idle | preflop | flop | turn | river | showdown
    actor = 0,           -- seat whose turn it is (0: nobody)
    hand = 0,            -- bumps every hand so stale timers stop
    reveal = false,
    raiseTo = 0,         -- your chosen raise amount
}

local function Fmt(n) return ns:FormatChips(n) end

-- The blinds picked in Options, for the next table you sit at or host.
local function ChosenBlinds()
    local level = BLIND_LEVELS[db and db.blinds or DEFAULT_BLINDS] or BLIND_LEVELS[DEFAULT_BLINDS]
    return level[1], level[2]
end

-- Hosting: the blinds and buy-in the host typed in (saved), with checks.
local MAX_AMOUNT   = 1000000
local MIN_BUYIN_BB = 10           -- a buy-in is at least 10 big blinds
local function HostSettings()
    local sb, bb = ChosenBlinds()
    local hs = db and db.hostSettings
    sb = (hs and hs.sb) or sb
    bb = (hs and hs.bb) or bb
    return sb, bb, (hs and hs.buyin) or 50 * bb
end
-- nil if they're fine, or what's wrong
local function HostSettingsProblem(sb, bb, buyin)
    if not sb or sb < 1 then return "Enter a small blind of at least 1." end
    if not bb or bb < sb then return "The big blind can't be smaller than the small blind." end
    if bb > MAX_AMOUNT or sb > MAX_AMOUNT then return "Those blinds are too big." end
    if not buyin or buyin < MIN_BUYIN_BB * bb then
        return "The buy-in must be at least " .. MIN_BUYIN_BB .. " big blinds (" .. Fmt(MIN_BUYIN_BB * bb) .. ")."
    end
    if buyin > MAX_AMOUNT then return "That buy-in is too big." end
    return nil
end

-- Buy-in amounts at a table with this big blind.
local function BuyIns(bb)
    local t = {}
    for i, n in ipairs(BUY_IN_BB) do t[i] = n * bb end
    return t
end

local function NextSeat(i) return ns.Mod(i, NUM_SEATS) + 1 end

---------------------------------------------------------------------------
-- Hand evaluation: best five of seven cards
-- A score is { category, tiebreak1, tiebreak2, ... }; higher is better.
-- Categories: 9 straight flush, 8 quads, 7 full house, 6 flush, 5 straight,
-- 4 trips, 3 two pair, 2 pair, 1 high card. Ranks run 2..14 (ace high).
---------------------------------------------------------------------------
local function HighRank(card)
    if card.rank == 1 then return 14 end
    return card.rank
end

-- Highest card of a five-card run in `present` (ace can be low), or nil.
local function TopStraight(present)
    local run = 0
    for r = 14, 1, -1 do
        local has = present[r] or (r == 1 and present[14])
        if has then
            run = run + 1
            if run >= 5 then return r + 4 end
        else
            run = 0
        end
    end
    return nil
end

local function Evaluate(cards)
    local counts, present = {}, {}
    local suits = { {}, {}, {}, {} }
    for _, c in ipairs(cards) do
        local r = HighRank(c)
        counts[r] = (counts[r] or 0) + 1
        present[r] = true
        table.insert(suits[c.suit], r)
    end

    local flush
    for s = 1, 4 do
        if ns.getn(suits[s]) >= 5 then
            local inSuit = {}
            for _, r in ipairs(suits[s]) do inSuit[r] = true end
            local top = TopStraight(inSuit)
            if top then return { 9, top } end
            flush = suits[s]
            table.sort(flush, function(a, b) return a > b end)
        end
    end

    local quads, trips, pairList = {}, {}, {}
    for r = 14, 2, -1 do
        local n = counts[r]
        if n == 4 then table.insert(quads, r)
        elseif n == 3 then table.insert(trips, r)
        elseif n == 2 then table.insert(pairList, r) end
    end

    -- Highest ranks not used by the made hand.
    local function Kickers(used, n)
        local out = {}
        for r = 14, 2, -1 do
            if counts[r] and not used[r] then
                table.insert(out, r)
                if ns.getn(out) == n then return out end
            end
        end
        return out
    end

    if quads[1] then
        local k = Kickers({ [quads[1]] = true }, 1)
        return { 8, quads[1], k[1] or 0 }
    end
    if trips[1] and (trips[2] or pairList[1]) then
        local pairRank = pairList[1] or 0
        if trips[2] and trips[2] > pairRank then pairRank = trips[2] end
        return { 7, trips[1], pairRank }
    end
    if flush then
        return { 6, flush[1], flush[2], flush[3], flush[4], flush[5] }
    end
    local top = TopStraight(present)
    if top then return { 5, top } end
    if trips[1] then
        local k = Kickers({ [trips[1]] = true }, 2)
        return { 4, trips[1], k[1] or 0, k[2] or 0 }
    end
    if pairList[2] then
        local k = Kickers({ [pairList[1]] = true, [pairList[2]] = true }, 1)
        return { 3, pairList[1], pairList[2], k[1] or 0 }
    end
    if pairList[1] then
        local k = Kickers({ [pairList[1]] = true }, 3)
        return { 2, pairList[1], k[1] or 0, k[2] or 0, k[3] or 0 }
    end
    local k = Kickers({}, 5)
    return { 1, k[1] or 0, k[2] or 0, k[3] or 0, k[4] or 0, k[5] or 0 }
end

local function Compare(a, b)
    for i = 1, math.max(ns.getn(a), ns.getn(b)) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then
            if x > y then return 1 end
            return -1
        end
    end
    return 0
end

local function Describe(s)
    local c = s[1]
    if c == 9 then
        if s[2] == 14 then return "Royal Flush" end
        return "Straight Flush, " .. RANK_NAME[s[2]] .. " high"
    elseif c == 8 then return "Four of a Kind, " .. RANK_PLURAL[s[2]]
    elseif c == 7 then return "Full House, " .. RANK_PLURAL[s[2]] .. " full of " .. RANK_PLURAL[s[3]]
    elseif c == 6 then return "Flush, " .. RANK_NAME[s[2]] .. " high"
    elseif c == 5 then return "Straight, " .. RANK_NAME[s[2]] .. " high"
    elseif c == 4 then return "Three of a Kind, " .. RANK_PLURAL[s[2]]
    elseif c == 3 then return "Two Pair, " .. RANK_PLURAL[s[2]] .. " and " .. RANK_PLURAL[s[3]]
    elseif c == 2 then return "Pair of " .. RANK_PLURAL[s[2]]
    end
    return RANK_NAME[s[2]] .. " high"
end

local function Seven(a, b, board)
    local t = { a, b }
    for i = 1, ns.getn(board) do t[i + 2] = board[i] end
    return t
end

-- Chance of winning (ties count as shared) against `opponents` random hands.
local function Equity(hole, board, opponents)
    if opponents < 1 then return 1 end
    local used = {}
    for _, c in ipairs(hole) do used[c.suit * 16 + c.rank] = true end
    for _, c in ipairs(board) do used[c.suit * 16 + c.rank] = true end
    local deck = {}
    for s = 1, 4 do
        for r = 1, 13 do
            if not used[s * 16 + r] then table.insert(deck, { rank = r, suit = s }) end
        end
    end

    local n = ns.getn(deck)
    local needBoard = 5 - ns.getn(board)
    local need = needBoard + 2 * opponents
    local score = 0
    for _ = 1, sims do
        for j = 1, need do
            local k = math.random(j, n)
            deck[j], deck[k] = deck[k], deck[j]
        end
        local full = {}
        for i = 1, ns.getn(board) do full[i] = board[i] end
        for j = 1, needBoard do full[ns.getn(full) + 1] = deck[j] end

        local mine = Evaluate(Seven(hole[1], hole[2], full))
        local ties, lost = 0, false
        local idx = needBoard
        for _ = 1, opponents do
            local c = Compare(mine, Evaluate(Seven(deck[idx + 1], deck[idx + 2], full)))
            idx = idx + 2
            if c < 0 then
                lost = true
                break
            elseif c == 0 then
                ties = ties + 1
            end
        end
        if not lost then score = score + 1 / (ties + 1) end
    end
    return score / sims
end

---------------------------------------------------------------------------
-- Party play
-- solo:   you and three computer players (everything runs here)
-- host:   your table; party members take seats, computer players can fill
--         the rest. This client runs the game and tells everyone the result
--         of every action.
-- client: you sit at someone else's table; this client draws what the host
--         sends and sends your moves back.
---------------------------------------------------------------------------
local ACTION_TIME     = 30    -- seconds a player gets to act at a party table
local NEXT_HAND_DELAY = 5     -- seconds between hands at a party table
local HEARTBEAT       = 15    -- the host re-sends the table this often
local HOST_TIMEOUT    = 40    -- a client gives up on a silent host after this long
local OFFER_TIMEOUT   = 60    -- forget a table we haven't heard about for this long
local MAX_TIMEOUTS    = 2     -- missed turns in a row before a player is removed
local GAME_TAG        = "HE"  -- first field of every Hold'em message

T.mode    = "solo"
T.mySeat  = 1
T.version = 0       -- bumps on every change of the game; actions carry it
T.pending = {}      -- host: players waiting for a seat
T.offers  = {}      -- client: tables in the group, by host name
T.fillBots = true

local Net = ns.Net
local Refresh, Continue, EndRound, StartHand, SetStatus, Leave, DealerWatch

local STREET_CODE = { idle = "i", preflop = "p", flop = "f", turn = "t", river = "r", showdown = "s" }
local STREET_NAME = { i = "idle", p = "preflop", f = "flop", t = "turn", r = "river", s = "showdown" }
local RANK_CHARS, SUIT_CHARS = "A23456789TJQK", "shdc"

local function Msg(parts) return GAME_TAG .. ";" .. table.concat(parts, ";") end

local function CardsCode(list)
    local s = ""
    for _, c in ipairs(list) do
        s = s .. string.sub(RANK_CHARS, c.rank, c.rank) .. string.sub(SUIT_CHARS, c.suit, c.suit)
    end
    return s
end

local function DecodeCards(s)
    local out, i = {}, 1
    s = s or ""
    while i < string.len(s) do
        local r = string.find(RANK_CHARS, string.sub(s, i, i), 1, true)
        local u = string.find(SUIT_CHARS, string.sub(s, i + 1, i + 1), 1, true)
        if r and u then table.insert(out, { rank = r, suit = u }) end
        i = i + 2
    end
    return out
end

---------------------------------------------------------------------------
-- Table helpers
---------------------------------------------------------------------------
local function MySeat() return T.mySeat or 1 end
local function Me() return T.seats[MySeat()] end
local function IsMine(p) return p ~= nil and p == T.seats[MySeat()] end

-- Where seat i is drawn: 1 is the bottom (you), then 2-4 clockwise.
local function ViewIndex(i) return ns.Mod(i - MySeat(), NUM_SEATS) + 1 end

local function NewSeat(kind, name, stack)
    return { kind = kind, name = name, stack = stack or 0, hole = {}, bet = 0, total = 0, won = 0 }
end

local function PotTotal()
    local t = T.pot
    for _, p in ipairs(T.seats) do t = t + p.bet end
    return t
end

local function CountWhere(test)
    local n = 0
    for _, p in ipairs(T.seats) do
        if test(p) then n = n + 1 end
    end
    return n
end

local function InHand(p) return not p.folded end
local function CanAct(p) return not p.folded and not p.allIn end

local function NeedsToAct(p)
    return not p.out and not p.folded and not p.allIn and (not p.acted or p.bet < T.currentBet)
end

local function MinRaiseTo()
    if T.currentBet == 0 then return BB end
    return T.currentBet + T.lastRaise
end

-- A legal raise-to amount for p: at least the minimum raise, at most all-in.
local function ClampRaise(p, to)
    local maxTo = p.stack + p.bet
    to = math.floor(to + 0.5)
    local minTo = MinRaiseTo()
    if to < minTo then to = minTo end
    if to > maxTo then to = maxTo end
    return to
end

local function PutIn(p, amount)
    if amount > p.stack then amount = p.stack end
    p.stack = p.stack - amount
    p.bet = p.bet + amount
    p.total = p.total + amount
    if p.stack == 0 then p.allIn = true end
    return amount
end

-- Next seat after i that is playing this hand.
local function NextActive(i)
    local j = i
    for _ = 1, NUM_SEATS do
        j = NextSeat(j)
        if not T.seats[j].out then return j end
    end
    return i
end

local function Who(p)
    if IsMine(p) then return "You" end
    return p.name or "?"
end

local function HasRemote()
    for _, p in ipairs(T.seats) do
        if p.kind == "remote" then return true end
    end
    return false
end

-- Last action, stored as a short code so it fits in a network message.
local LAST_WORD = { F = "Fold", K = "Check", C = "Call", R = "Raise to", B = "Bet", A = "All-in",
                    S = "Small blind", G = "Big blind", W = "Wins" }

local function LastText(code)
    if not code or code == "" then return nil end
    local k = string.sub(code, 1, 1)
    local n = tonumber(string.sub(code, 2))
    local word = LAST_WORD[k]
    if not word then return nil end
    if k == "S" or k == "G" or not n then return word end
    return word .. " " .. Fmt(n)
end

local function SetLast(p, k, n)
    p.lastCode = k .. (n and tostring(n) or "")
    p.last = LastText(p.lastCode)
end

local function NewBot()
    local taken = {}
    for _, p in ipairs(T.seats) do
        if p.name then taken[p.name] = true end
    end
    local free = {}
    for _, name in ipairs(BOT_NAMES) do
        if not taken[name] then table.insert(free, name) end
    end
    -- the same stack you bought in with (a random one only if that's unknown)
    local stack = T.botStack
    if not stack or stack <= 0 then
        local steps = (BOT_STACK_MAX - BOT_STACK_MIN) / 50
        stack = (BOT_STACK_MIN + 50 * math.random(0, steps)) * BB / 10
    end
    local bot = NewSeat("bot", free[math.random(ns.getn(free))], stack)
    bot.style = {
        loose = 0.85 + math.random() * 0.4,    -- how wide they play
        aggro = 0.15 + math.random() * 0.3,    -- how often strength turns into a raise
        bluff = 0.02 + math.random() * 0.06,   -- how often they bet with nothing
    }
    return bot
end

-- Saved so a reload never loses chips. Solo: the whole table. Host: your
-- stack at the start of the hand. Clients save their own seat elsewhere.
local function SaveSeat(inHand)
    if T.mode == "host" then
        db.partyHost = { stack = Me().stack }
        return
    end
    if T.mode ~= "solo" then return end
    local seat = { stacks = {}, bots = {}, button = T.button, inHand = inHand, sb = SB, bb = BB, buyin = T.botStack }
    for i, p in ipairs(T.seats) do
        seat.stacks[i] = p.stack
        if p.kind == "bot" then seat.bots[i] = { name = p.name, style = p.style } end
    end
    db.seat = seat
end

---------------------------------------------------------------------------
-- Host: telling the table what happened
---------------------------------------------------------------------------
local function Changed()
    T.version = T.version + 1
    T.dirty = true
end

local function RosterMsg()
    local parts = { "R", T.tid }
    for i = 1, NUM_SEATS do
        local p = T.seats[i]
        local k = "h"
        if p.kind == "bot" then k = "b" elseif p.kind == "empty" then k = "e" end
        table.insert(parts, k .. "," .. (p.name or ""))
    end
    return Msg(parts)
end

local function StateMsg()
    local remain = ""
    if T.deadline then remain = math.max(0, math.floor(T.deadline - GetTime() + 0.5)) end
    local parts = { "P", T.tid, T.version, T.hand, STREET_CODE[T.street] or "i", T.button, T.actor,
                    T.pot, T.currentBet, T.lastRaise, remain, T.reveal and 1 or 0, CardsCode(T.board) }
    for i = 1, NUM_SEATS do
        local p = T.seats[i]
        local flags = (p.folded and "f" or "") .. (p.allIn and "a" or "") .. (p.acted and "c" or "")
            .. (p.out and "o" or "") .. (p.leaving and "l" or "")
        table.insert(parts, p.stack .. "," .. p.bet .. "," .. p.total .. "," .. flags .. ","
            .. (p.won or 0) .. "," .. (p.lastCode or ""))
    end
    return Msg(parts)
end

local function OpenSeats()
    local n = 0
    for i = 2, NUM_SEATS do
        if T.seats[i].kind ~= "remote" then n = n + 1 end
    end
    return n
end

local function SendOffer()
    if T.mode ~= "host" then return end
    local players = NUM_SEATS - OpenSeats()
    Net:Send(Msg({ "O", T.tid, SB, BB, players, OpenSeats(), T.tableBuyIn or 50 * BB }), "HE-O")
end

local function SendRoster()
    if T.mode == "host" then Net:Send(RosterMsg(), "HE-R") end
end

local function Broadcast()
    if T.mode == "host" and HasRemote() then Net:Send(StateMsg(), "HE-P") end
    T.dirty = false
end

-- Everyone still in sees everyone's cards (run-outs and showdowns).
local function SendReveal()
    if T.mode ~= "host" or not HasRemote() then return end
    local list = {}
    for i, p in ipairs(T.seats) do
        if not p.folded and not p.out and p.hole[2] then
            table.insert(list, i .. ":" .. CardsCode(p.hole))
        end
    end
    Net:Send(Msg({ "V", T.tid, T.hand, table.concat(list, ",") }))
end

---------------------------------------------------------------------------
-- Computer players
-- They estimate their chance of winning by dealing out the rest of the hand
-- many times, then weigh it against the price of calling. Each has its own
-- looseness, aggression and bluffing habits.
---------------------------------------------------------------------------
local function BotRaiseSize(p, monster)
    local toCall = T.currentBet - p.bet
    local to
    if T.street == "preflop" and T.currentBet <= BB then
        to = BB * (2.5 + math.random(0, 2))
    else
        local frac = 0.5 + math.random() * 0.4
        if monster and math.random() < 0.3 then frac = 1 end
        to = T.currentBet + (PotTotal() + toCall) * frac
    end
    return ClampRaise(p, to)
end

local function BotDecide(p)
    local toCall = T.currentBet - p.bet
    local opponents = CountWhere(InHand) - 1
    local eq = Equity(p.hole, T.board, opponents)
    local st = p.style
    local fair = 1 / (opponents + 1)
    local strong = eq > fair * 1.6 / st.loose
    local monster = eq > math.max(0.7, fair * 2.4)
    local canRaise = not p.acted and p.stack > toCall and T.raises < MAX_RAISES
    local r = math.random()

    if toCall <= 0 then
        if canRaise and ((strong and r < st.aggro + 0.35) or r < st.bluff) then
            return "raise", BotRaiseSize(p, monster)
        end
        return "check"
    end

    local potOdds = toCall / (PotTotal() + toCall)
    local streetFactor = (T.street == "preflop") and 0.95 or 1.0
    if eq < potOdds * streetFactor / st.loose then
        return "fold"
    end
    if canRaise and (monster or (strong and r < st.aggro)) then
        return "raise", BotRaiseSize(p, monster)
    end
    return "call"
end

-- Tests may replace this to script the computer players.
Poker.Decide = BotDecide

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
function SetStatus(text, r, g, b)
    ui.status:SetText(text)
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function SetLobbyMessage(text)
    ui.lobbyMsg:SetText(text or "")
end

local function StatsText()
    local s = db.stats
    local best = s.bestName and ("Best hand shown: " .. s.bestName) or "Best hand shown: -"
    return string.format("Hands played %d   Won %d   Biggest pot %s\n%s",
        s.hands, s.won, Fmt(s.biggestPot), best)
end

local function RefreshLobby()
    local chips = ns.db.chips
    local sb, bb = ChosenBlinds()
    local buyIns = BuyIns(bb)
    for i, b in ipairs(ui.buyIns) do
        b:SetText(Fmt(buyIns[i]))
        ns.SetEnabled(b, chips >= buyIns[i])
    end
    ui.lobbyInfo:SetText(string.format("No-limit, blinds %s/%s, against three computer players.\n"
        .. "Buy in from your chips. Whatever is in front of you goes back to your chips when you leave the table.", Fmt(sb), Fmt(bb)))
    ui.lobbyStats:SetText(StatsText())
    ns:UpdateChipsDisplay()
end

local function RefreshSeat(i)
    local p = T.seats[i]
    local s = ui.seats[ViewIndex(i)]
    if not p or not s then return end
    local mine = IsMine(p)

    if p.kind == "empty" then
        s.name:SetText("|cff888888Empty seat|r")
        s.stack:SetText("")
        s.action:SetText("")
    else
        local dealer = (i == T.button) and "|cffffd100(D)|r " or ""
        s.name:SetText(dealer .. (mine and "You" or (p.name or "?")))
        s.stack:SetText("Stack " .. Fmt(p.stack))
        local line = p.last or ""
        if p.bet > 0 and not p.folded and line == "" then line = "Bet " .. Fmt(p.bet) end
        if p.out and p.stack <= 0 then line = "Out of chips" elseif p.out then line = "Sitting out" end
        if p.leaving then line = "Leaving" end
        if T.deadline and T.actor == i and T.street ~= "idle" then
            local left = math.max(0, math.ceil(T.deadline - GetTime()))
            line = (line ~= "" and (line .. "  ") or "") .. "|cffffd100" .. left .. "s|r"
        end
        s.action:SetText(line)
    end

    -- Portraits for people (you included), not computer players.
    local unit
    if mine then unit = "player"
    elseif p.kind == "remote" or p.kind == "human" then unit = Net:UnitFor(p.name) end
    s.portrait:ShowUnit(unit)
    if s.cardX then
        local x = unit and s.cardXWithPortrait or s.cardX
        if s.placedX ~= x then
            s.placedX = x
            s.cards[1]:ClearAllPoints()
            s.cards[1]:SetPoint("TOPLEFT", s.frame, "TOPLEFT", x, -18)
            s.cards[2]:ClearAllPoints()
            s.cards[2]:SetPoint("TOPLEFT", s.frame, "TOPLEFT", x + SMALL_W + 4, -18)
        end
    end

    for c = 1, 2 do
        local w, card = s.cards[c], p.hole[c]
        if not card or p.kind == "empty" or p.out or (p.folded and not mine) then
            w:Clear()
        else
            w:SetCard(card, mine or (T.reveal and not p.folded))
        end
    end
    s.frame:SetAlpha((p.folded or p.out or p.kind == "empty") and 0.45 or 1)
    ns.SetShown(s.glow, T.street ~= "idle" and T.actor == i)
    ns.SetShown(s.win, (p.won or 0) > 0 and T.street == "idle")
end

local function MyTurn()
    local me = Me()
    if not me or T.street == "idle" or T.actor ~= MySeat() or not NeedsToAct(me) then return false end
    if T.mode == "client" and T.sent == T.version then return false end
    return true
end

---------------------------------------------------------------------------
-- The dealer talks the table through each hand. It watches the table as it
-- is drawn, so it works the same solo, hosting or at someone else's table.
-- The lines are the chosen dealer's own (DEALERS.md), or nothing.
---------------------------------------------------------------------------
local seen = { hand = nil, street = nil, allIn = {}, start = {}, done = true }

local function Say(event, vars, seconds, quiet)
    ns.Dealer:React(Poker, event, vars, seconds or 6, nil, quiet)
end

function DealerWatch()
    if T.street ~= "idle" and T.hand ~= seen.hand then
        seen.hand, seen.street, seen.allIn, seen.start, seen.done = T.hand, T.street, {}, {}, false
        for i, p in ipairs(T.seats) do
            if p.kind ~= "empty" and not p.out then seen.start[i] = p.stack + (p.total or 0) end
        end
        local b = T.seats[T.button]
        Say("holdemDeal", { button = b and Who(b) or "?", sb = Fmt(SB), bb = Fmt(BB) })
    end
    if seen.done or T.hand ~= seen.hand then return end
    if T.street ~= seen.street and T.street ~= "idle" and T.street ~= "showdown" then
        seen.street = T.street
        if T.street == "flop" or T.street == "turn" or T.street == "river" then
            Say("holdem" .. string.upper(string.sub(T.street, 1, 1)) .. string.sub(T.street, 2), nil, 5, true)
        end
    end
    for i, p in ipairs(T.seats) do
        if p.allIn and not seen.allIn[i] and seen.start[i] then
            seen.allIn[i] = true
            if IsMine(p) then Say("holdemYouAllIn", { amount = Fmt(p.total or 0) })
            else Say("holdemAllIn", { name = Who(p), amount = Fmt(p.total or 0) }) end
        end
    end
    if T.street ~= "idle" then return end

    -- the hand is over: who won, and who's out of chips
    seen.done = true
    local winners, pot, mine = {}, 0, false
    for _, p in ipairs(T.seats) do
        if (p.won or 0) > 0 and p.kind ~= "empty" then
            table.insert(winners, p)
            pot = pot + p.won
            if IsMine(p) then mine = true end
        end
    end
    local w = winners[1]
    if w then
        local vars = { name = Who(w), pot = Fmt(pot), hand = w.score and Describe(w.score) or "the best hand" }
        if ns.getn(winners) > 1 then Say("holdemSplit", vars)
        elseif not T.reveal or not w.score then Say(mine and "holdemYouFoldWin" or "holdemFoldWin", vars)
        else Say(mine and "holdemYouWin" or "holdemWin", vars) end
    end
    for i, p in ipairs(T.seats) do
        if seen.start[i] and seen.start[i] > 0 and p.stack <= 0 and p.kind ~= "empty" then
            if IsMine(p) then Say("holdemYouBust", nil, 8) else Say("holdemKnockout", { name = Who(p) }, 7) end
        end
    end
end

function Refresh()
    if not ui.table then return end
    local seated = T.seats[1] ~= nil
    ns.SetShown(ui.table, seated)
    ns.SetShown(ui.lobby, not seated)
    if not seated then
        RefreshLobby()
        return
    end

    for i = 1, NUM_SEATS do RefreshSeat(i) end
    for i = 1, 5 do
        if T.board[i] then ui.board[i]:SetCard(T.board[i], true) else ui.board[i]:Clear() end
    end
    ui.pot:SetText("Pot: " .. Fmt(PotTotal()))

    local me = Me()
    local playing = T.street ~= "idle"
    local myTurn = MyTurn()
    local toCall = T.currentBet - me.bet
    local canRaise = myTurn and not me.acted and me.stack > toCall

    -- At a party table, once you're out of the hand the leave/close buttons show.
    local sittingOut = playing and T.mode ~= "solo" and (me.out or me.folded)
    ns.SetShown(ui.actionRow, playing and not sittingOut)
    ns.SetShown(ui.raiseRow, playing and not sittingOut)
    ns.SetShown(ui.betweenRow, not playing or sittingOut)

    ns.SetEnabled(ui.fold, myTurn)
    if toCall > 0 then
        local amount = math.min(toCall, me.stack)
        ui.call:SetText((amount >= me.stack and "All-in " or "Call ") .. Fmt(amount))
    else
        ui.call:SetText("Check")
    end
    ns.SetEnabled(ui.call, myTurn)

    if canRaise then
        T.raiseTo = ClampRaise(me, T.raiseTo)
    end
    local maxTo = me.stack + me.bet
    if canRaise and T.raiseTo >= maxTo then
        ui.raise:SetText("All-in " .. Fmt(maxTo))
    elseif T.currentBet == 0 then
        ui.raise:SetText("Bet " .. Fmt(math.max(T.raiseTo, BB)))
    else
        ui.raise:SetText("Raise to " .. Fmt(math.max(T.raiseTo, MinRaiseTo())))
    end
    ns.SetEnabled(ui.raise, canRaise)
    for _, b in ipairs(ui.sizeButtons) do ns.SetEnabled(b, canRaise) end

    if T.mode == "client" then
        ui.deal:SetText("Host deals")
        ns.SetEnabled(ui.deal, false)
        ui.leave:SetText("Leave table")
        ns.SetEnabled(ui.leave, not playing or me.folded or me.out)
        ui.partyLabel:SetText((T.host or "?") .. "'s table")
    else
        ui.deal:SetText("Deal")
        local players = 0
        for _, p in ipairs(T.seats) do
            if p.kind ~= "empty" and p.stack > 0 then players = players + 1 end
        end
        ns.SetEnabled(ui.deal, not playing and players >= 2 and (T.mode == "host" or me.stack > 0))
        if T.mode == "host" then
            if not playing then
                ui.leave:SetText("Close table")
            elseif T.closeAfterHand then
                ui.leave:SetText("Closing...")
            else
                ui.leave:SetText("Close after hand")
            end
            ns.SetEnabled(ui.leave, not playing or not T.closeAfterHand)
        else
            ui.leave:SetText("Leave table")
            ns.SetEnabled(ui.leave, not playing)
        end
        ui.partyLabel:SetText(T.mode == "host" and "Your party table" or "")
    end
    ui.blinds:SetText("Blinds " .. Fmt(SB) .. "/" .. Fmt(BB))
    ns:UpdateChipsDisplay()
    if T.seats[1] then DealerWatch() end

    if T.dirty then Broadcast() end
end

---------------------------------------------------------------------------
-- Hand flow (solo and host)
---------------------------------------------------------------------------
local function ScheduleNextHand()
    if T.mode ~= "host" or not HasRemote() then return end
    local hand = T.hand
    ns:After(NEXT_HAND_DELAY, function()
        if T.mode == "host" and T.street == "idle" and T.hand == hand then StartHand() end
    end)
end

local function FindSeatFor()
    for i = 2, NUM_SEATS do
        if T.seats[i].kind == "empty" then return i end
    end
    for i = 2, NUM_SEATS do
        if T.seats[i].kind == "bot" then return i end
    end
    return nil
end

-- Host: give a waiting player a seat (only between hands).
local function SeatPlayer(name, buyin)
    for i = 2, NUM_SEATS do
        local p = T.seats[i]
        if p.kind == "remote" and p.name == name then
            Net:Send(Msg({ "S", T.tid, name, i, p.stack }))   -- they missed it; say again
            return
        end
    end
    local i = FindSeatFor()
    if not i then
        Net:Send(Msg({ "N", T.tid, name, "The table is full." }))
        return
    end
    local p = NewSeat("remote", name, buyin)
    p.seat, p.out, p.folded = i, true, true
    T.seats[i] = p
    Net:Send(Msg({ "S", T.tid, name, i, buyin }))
    Changed()
    SendRoster()
    SendOffer()
    SetStatus(name .. " sat down with " .. Fmt(buyin) .. ".")
end

local function SeatPending()
    local waiting = T.pending
    T.pending = {}
    for _, w in ipairs(waiting) do
        if Net:IsMember(w.name) then SeatPlayer(w.name, w.buyin) end
    end
end

local function FinishHand()
    T.street = "idle"
    T.actor = 0
    T.deadline = nil
    Changed()
    local me = Me()
    local s = db.stats
    if not me.out and (me.won or 0) > 0 then
        s.won = s.won + 1
        if me.won > s.biggestPot then s.biggestPot = me.won end
    end
    if not me.out then
        if (me.won or 0) > 0 then ns:PlayGameSound(db, "win")
        elseif (me.total or 0) > 0 then ns:PlayGameSound(db, "lose") end
    end

    if T.mode == "host" then
        local changed = false
        for i = 2, NUM_SEATS do
            local p = T.seats[i]
            if p.kind == "remote" and (p.leaving or p.kicked) then
                if p.kicked then
                    Net:Send(Msg({ "K", T.tid, p.name, p.stack }))
                    ns:Print(p.name .. " was removed from your table for not responding.")
                end
                T.seats[i] = NewSeat("empty")
                T.seats[i].seat = i
                changed = true
            end
        end
        SeatPending()
        if changed then
            SendRoster()
            SendOffer()
        end
    end

    SaveSeat(false)
    if me.stack <= 0 then
        if T.mode == "host" then
            SetStatus("You're out of chips; the table plays on. Close it to cash out.", 1, 0.35, 0.35)
        else
            SetStatus("You're out of chips at this table. Leave to buy in again.", 1, 0.35, 0.35)
        end
    end
    if T.mode == "host" and T.closeAfterHand then
        Broadcast()          -- everyone sees how the hand ended before the table closes
        Leave()
        return
    end
    Refresh()
    ScheduleNextHand()
end

local function CollectBets()
    for _, p in ipairs(T.seats) do
        T.pot = T.pot + p.bet
        p.bet = 0
        p.acted = false
        if not p.folded and not p.allIn then
            p.last, p.lastCode = nil, nil
        end
    end
    T.currentBet, T.lastRaise, T.raises = 0, BB, 0
end

local function AwardUncontested()
    CollectBets()
    local winner
    for _, p in ipairs(T.seats) do
        if not p.folded then winner = p end
    end
    winner.stack = winner.stack + T.pot
    winner.won = T.pot
    SetLast(winner, "W", T.pot)
    if IsMine(winner) then
        SetStatus("Everyone folded - you win " .. Fmt(T.pot) .. ".", 0.25, 1, 0.25)
    else
        SetStatus(winner.name .. " wins " .. Fmt(T.pot) .. " uncontested.", 0.85, 0.85, 0.85)
    end
    T.pot = 0
    FinishHand()
end

-- Share `amount` between winners; odd chips go to the first winner left of the button.
local function Split(amount, winners)
    table.sort(winners, function(a, b)
        return ns.Mod(a.seat - T.button - 1, NUM_SEATS) < ns.Mod(b.seat - T.button - 1, NUM_SEATS)
    end)
    local share = math.floor(amount / ns.getn(winners))
    local odd = amount - share * ns.getn(winners)
    for i, p in ipairs(winners) do
        local got = share
        if i <= odd then got = got + 1 end
        p.stack = p.stack + got
        p.won = (p.won or 0) + got
    end
end

local function Showdown()
    T.street = "showdown"
    if not T.reveal then
        T.reveal = true
        SendReveal()
    end
    T.actor = 0

    for _, p in ipairs(T.seats) do
        if not p.folded then
            p.score = Evaluate(Seven(p.hole[1], p.hole[2], T.board))
            p.last = Describe(p.score)
            p.lastCode = ""
        end
    end

    -- Main pot and side pots, one slice per contribution level.
    local levels, seen = {}, {}
    for _, p in ipairs(T.seats) do
        if p.total > 0 and not seen[p.total] then
            seen[p.total] = true
            table.insert(levels, p.total)
        end
    end
    table.sort(levels)

    local prev, carry, lastWinners = 0, 0, nil
    for _, level in ipairs(levels) do
        local amount = carry
        for _, p in ipairs(T.seats) do
            amount = amount + math.min(p.total, level) - math.min(p.total, prev)
        end
        local best, winners = nil, {}
        for _, p in ipairs(T.seats) do
            if not p.folded and p.total >= level then
                local c = best and Compare(p.score, best) or 1
                if c > 0 then
                    best, winners = p.score, { p }
                elseif c == 0 then
                    table.insert(winners, p)
                end
            end
        end
        if ns.getn(winners) == 0 then
            carry = amount
        else
            carry = 0
            Split(amount, winners)
            lastWinners = winners
        end
        prev = level
    end
    if carry > 0 and lastWinners then Split(carry, lastWinners) end
    T.pot = 0

    local me = Me()
    local parts = {}
    for _, p in ipairs(T.seats) do
        if (p.won or 0) > 0 then
            local verb = IsMine(p) and " win " or " wins "
            table.insert(parts, Who(p) .. verb .. Fmt(p.won) .. (p.score and (" with " .. Describe(p.score)) or ""))
        end
    end
    local msg = table.concat(parts, ". ") .. "."
    if (me.won or 0) > 0 then
        SetStatus(msg, 0.25, 1, 0.25)
    else
        SetStatus(msg, 0.85, 0.85, 0.85)
    end

    if not me.folded and not me.out and me.score then
        local s = db.stats
        if not s.best or Compare(me.score, s.best) > 0 then
            s.best = me.score
            s.bestName = Describe(me.score)
        end
    end
    FinishHand()
end

local function DealStreet()
    if T.street == "preflop" then
        for _ = 1, 3 do table.insert(T.board, shoe:Draw()) end
        T.street = "flop"
    elseif T.street == "flop" then
        table.insert(T.board, shoe:Draw())
        T.street = "turn"
    elseif T.street == "turn" then
        table.insert(T.board, shoe:Draw())
        T.street = "river"
    end
    Changed()
    ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
end

local STREET_NAMES = { flop = "The flop", turn = "The turn", river = "The river" }

function EndRound()
    CollectBets()
    Changed()
    if T.street == "river" then
        Showdown()
        return
    end
    -- Nobody left to bet against: show the cards and deal out the rest.
    local runOut = CountWhere(CanAct) <= 1
    if runOut and not T.reveal then
        T.reveal = true
        SendReveal()
    end
    T.actor = 0
    T.deadline = nil
    Refresh()

    local hand = T.hand
    ns:After(STREET_DELAY, function()
        if T.hand ~= hand or T.street == "idle" then return end
        DealStreet()
        if runOut then
            Refresh()
            EndRound()
        else
            SetStatus(STREET_NAMES[T.street] .. ".")
            T.actor = NextSeat(T.button)
            Continue()
        end
    end)
end

local function Act(p, action, to)
    local toCall = T.currentBet - p.bet
    if action == "raise" and (not to or to <= T.currentBet) then action = "call" end
    if action == "check" and toCall > 0 then action = "call" end
    if action == "call" and toCall <= 0 then action = "check" end

    if action == "fold" then
        p.folded = true
        SetLast(p, "F")
    elseif action == "check" then
        SetLast(p, "K")
    elseif action == "call" then
        local paid = PutIn(p, toCall)
        if p.allIn then SetLast(p, "A", p.bet) else SetLast(p, "C", paid) end
    else
        local before = T.currentBet
        PutIn(p, to - p.bet)
        if p.bet > before then
            local raisedBy = p.bet - before
            T.currentBet = p.bet
            T.raises = T.raises + 1
            if raisedBy >= T.lastRaise then
                -- A full raise: everyone else gets to act (and raise) again.
                T.lastRaise = raisedBy
                for _, o in ipairs(T.seats) do
                    if o ~= p then o.acted = false end
                end
            end
        end
        if p.allIn then
            SetLast(p, "A", p.bet)
        elseif before == 0 then
            SetLast(p, "B", p.bet)
        else
            SetLast(p, "R", p.bet)
        end
    end
    p.acted = true
    T.deadline = nil
    T.clock = (T.clock or 0) + 1      -- cancels the clock for this turn
    Changed()
    ns:Sound("IG_MAINMENU_OPTION")

    T.actor = NextSeat(T.actor)
    Continue()
end

-- Party tables: every player gets ACTION_TIME to act, then checks or folds.
local function StartClock(i)
    T.deadline = GetTime() + ACTION_TIME
    T.clock = (T.clock or 0) + 1
    local hand, clock = T.hand, T.clock
    ns:After(ACTION_TIME, function()
        if T.hand ~= hand or T.clock ~= clock or T.actor ~= i or T.street == "idle" then return end
        local p = T.seats[i]
        p.timeouts = (p.timeouts or 0) + 1
        if p.kind == "remote" and p.timeouts >= MAX_TIMEOUTS then p.kicked = true end
        if T.currentBet - p.bet > 0 then Act(p, "fold") else Act(p, "check") end
    end)
end

function Continue()
    if CountWhere(InHand) == 1 then
        AwardUncontested()
        return
    end
    local i = T.actor
    for _ = 1, NUM_SEATS do
        local p = T.seats[i]
        if NeedsToAct(p) then
            T.actor = i
            if p.kind == "bot" then
                Refresh()
                local hand = T.hand
                ns:After(ACT_DELAY, function()
                    if T.hand ~= hand or T.actor ~= i or T.street == "idle" then return end
                    local action, to = Poker.Decide(p)
                    Act(p, action, to)
                end)
            elseif IsMine(p) then
                local toCall = T.currentBet - p.bet
                T.raiseTo = ClampRaise(p, MinRaiseTo())
                if toCall > 0 then
                    SetStatus("Your move - " .. Fmt(math.min(toCall, p.stack)) .. " to call.")
                else
                    SetStatus("Your move.")
                end
                if T.mode == "host" and HasRemote() then StartClock(i) end
                Refresh()
            else
                if p.leaving then
                    Act(p, "fold")
                    return
                end
                SetStatus("Waiting for " .. p.name .. "...")
                StartClock(i)
                Refresh()
            end
            return
        end
        i = NextSeat(i)
    end
    EndRound()
end

function StartHand()
    if T.street ~= "idle" or not T.seats[1] or T.mode == "client" then return end
    local me = Me()
    if T.mode == "solo" and me.stack <= 0 then return end

    if T.mode == "host" then SeatPending() end
    for i = 2, NUM_SEATS do
        local p = T.seats[i]
        if p.kind == "bot" and p.stack <= 0 then
            local old = p.name
            if T.mode == "solo" or T.fillBots then
                T.seats[i] = NewBot()
                if T.mode == "solo" then ns:Print(old .. " is out of chips; " .. T.seats[i].name .. " takes the seat.") end
            else
                T.seats[i] = NewSeat("empty")
            end
        elseif p.kind == "empty" and T.mode == "host" and T.fillBots then
            T.seats[i] = NewBot()
        end
    end

    local players = 0
    for i, p in ipairs(T.seats) do
        p.seat = i
        p.out = (p.kind == "empty") or p.stack <= 0
        if not p.out then players = players + 1 end
    end
    if players < 2 then
        SetStatus("Waiting for more players.")
        Changed()
        Refresh()
        return
    end

    T.button = NextActive(T.button)
    SaveSeat(true)              -- stacks before the blinds, in case of a reload
    T.hand = T.hand + 1
    if not me.out then db.stats.hands = db.stats.hands + 1 end

    shoe = ns:NewShoe(1)
    T.board, T.pot, T.reveal, T.deadline = {}, 0, false, nil
    for _, p in ipairs(T.seats) do
        p.hole, p.bet, p.total = {}, 0, 0
        p.folded, p.allIn, p.acted = p.out, false, false
        p.last, p.lastCode, p.score, p.won = nil, nil, nil, 0
    end

    -- Heads-up, the button posts the small blind.
    local sbSeat = T.button
    if players > 2 then sbSeat = NextActive(T.button) end
    local bbSeat = NextActive(sbSeat)
    PutIn(T.seats[sbSeat], SB)
    SetLast(T.seats[sbSeat], "S", SB)
    PutIn(T.seats[bbSeat], BB)
    SetLast(T.seats[bbSeat], "G", BB)
    T.currentBet = math.max(T.seats[sbSeat].bet, T.seats[bbSeat].bet)
    T.lastRaise, T.raises = BB, 0

    for _ = 1, 2 do
        local i = NextActive(T.button)
        for _ = 1, players do
            table.insert(T.seats[i].hole, shoe:Draw())
            i = NextActive(i)
        end
    end
    if not Me().out then ns:PlayGameSound(db, "newHand") end

    T.street = "preflop"
    Changed()
    if T.mode == "host" then
        SendRoster()
        for i, p in ipairs(T.seats) do
            if p.kind == "remote" and not p.out then
                Net:Send(Msg({ "H", T.tid, T.hand, i, CardsCode(p.hole) }))
            end
        end
    end
    T.actor = NextActive(bbSeat)
    Continue()
end

---------------------------------------------------------------------------
-- Sitting down and leaving (solo and host)
---------------------------------------------------------------------------
local function ResetToLobby()
    SB, BB = ChosenBlinds()
    T.seats = {}
    T.mode, T.mySeat = "solo", 1
    T.hand = T.hand + 1          -- stops any timers from the old table
    T.street, T.actor, T.deadline, T.sent = "idle", 0, nil, nil
    T.botStack, T.tableBuyIn = nil, nil
    T.board, T.pot, T.reveal = {}, 0, false
    T.tid, T.host, T.dirty = nil, nil, false
    T.pending = {}
end

local function SitDown(stacks, bots, button, buyin)
    T.botStack = buyin or stacks[1]      -- new bots start with what you bought in for
    T.seats = { NewSeat("you", "You", stacks[1]) }
    T.seats[1].seat = 1
    for i = 2, NUM_SEATS do
        local b = bots and bots[i]
        local bot = NewBot()
        if b then
            bot.name, bot.style = b.name, b.style
            bot.stack = stacks[i]
        end
        bot.seat = i
        T.seats[i] = bot
    end
    T.mode, T.mySeat = "solo", 1
    T.button = button or math.random(NUM_SEATS)
    T.street, T.actor, T.board, T.pot, T.reveal = "idle", 0, {}, 0, false
end

local function BuyIn(i)
    local sb, bb = ChosenBlinds()
    local amount = BuyIns(bb)[i]
    if T.seats[1] or not amount or not ns:SpendChips(amount) then return end
    db.stats.buyIns = db.stats.buyIns + 1
    SB, BB = sb, bb
    SitDown({ amount })
    SaveSeat(false)
    SetStatus("You sit down with " .. Fmt(amount) .. ". Good luck!")
    Refresh()
    StartHand()
end

function Leave()
    if not T.seats[1] then return end
    if T.mode == "host" and T.street ~= "idle" then
        T.closeAfterHand = true
        SetStatus("The table will close after this hand.")
        Refresh()
        return
    end
    if T.street ~= "idle" then return end
    T.closeAfterHand = nil
    local stack = Me().stack
    if stack > 0 then ns:AddChips(stack) end
    if T.mode == "host" then
        Net:Send(Msg({ "X", T.tid }))
        db.partyHost = nil
    end
    db.seat = nil
    ResetToLobby()
    SetLobbyMessage(stack > 0 and ("You left the table with " .. Fmt(stack) .. " chips.") or "")
    Refresh()
end

local function HostTable()
    local sb, bb, buyin = HostSettings()
    if HostSettingsProblem(sb, bb, buyin) then return end
    if T.seats[1] or not Net:InGroup() or not ns:SpendChips(buyin) then return end
    db.stats.buyIns = db.stats.buyIns + 1
    SB, BB = sb, bb
    T.mode, T.mySeat = "host", 1
    T.tid = tostring(math.random(1, 99999))
    T.version, T.pending = 0, {}
    T.seats = { NewSeat("you", Net:Me(), buyin) }
    T.botStack = buyin                   -- bots start with the host's buy-in
    T.tableBuyIn = buyin                 -- and so does everyone who joins
    for i = 2, NUM_SEATS do
        T.seats[i] = T.fillBots and NewBot() or NewSeat("empty")
    end
    for i, p in ipairs(T.seats) do p.seat = i end
    T.button = math.random(NUM_SEATS)
    T.street, T.actor, T.board, T.pot, T.reveal = "idle", 0, {}, 0, false
    db.partyHost = { stack = buyin }
    SendOffer()
    ui.party:Hide()
    SetStatus("Your table is open. Party members can join from Hold'em > Play with your party.")
    Changed()
    Refresh()
end

-- Host: a player leaves (asked, left the group, or ran out of time).
local function HostDropPlayer(i)
    local p = T.seats[i]
    if not p or p.kind ~= "remote" then return end
    if T.street == "idle" then
        T.seats[i] = NewSeat("empty")
        T.seats[i].seat = i
        SetStatus(p.name .. " left the table.")
        Changed()
        SendRoster()
        SendOffer()
        Refresh()
        return
    end
    p.leaving = true
    if p.folded or p.out then
        Changed()
        Refresh()
        return
    end
    if T.actor == i then
        Act(p, "fold")
        return
    end
    p.folded = true
    SetLast(p, "F")
    Changed()
    if CountWhere(InHand) == 1 then
        AwardUncontested()
    else
        Refresh()
    end
end

---------------------------------------------------------------------------
-- Client: sitting at someone else's table
---------------------------------------------------------------------------
local function ClientCashOut(amount, message)
    if amount and amount > 0 then ns:AddChips(amount) end
    db.party = nil
    ResetToLobby()
    SetLobbyMessage(message .. (amount and amount > 0 and (" You got " .. Fmt(amount) .. " chips back.") or ""))
    Refresh()
end

-- The host went away: everyone gets back what they had before the hand.
local function HostGone(message)
    if T.mode ~= "client" then return end
    ClientCashOut(db.party and db.party.stack or 0, message)
end

local function ClientLeave()
    if T.mode ~= "client" then return end
    local me = Me()
    local playing = T.street ~= "idle"
    if playing and not me.folded and not me.out then return end
    Net:Send(Msg({ "L", T.tid }))
    ClientCashOut(me.stack, "You left " .. (T.host or "the host") .. "'s table.")
end

local function ClientAct(code, amount)
    if not MyTurn() then return end
    T.sent = T.version
    Net:Send(Msg({ "A", T.tid, T.hand, T.version, code, amount or 0 }))
    Refresh()
end

local function ClientStatus()
    local me = Me()
    if not me then return end
    if T.street == "idle" then
        local parts = {}
        for _, p in ipairs(T.seats) do
            if (p.won or 0) > 0 and p.kind ~= "empty" then
                local verb = IsMine(p) and " win " or " wins "
                table.insert(parts, Who(p) .. verb .. Fmt(p.won) .. (p.score and (" with " .. Describe(p.score)) or ""))
            end
        end
        if me.stack <= 0 then
            SetStatus("You're out of chips at this table. Leave to cash out.", 1, 0.35, 0.35)
        elseif ns.getn(parts) > 0 then
            local won = (me.won or 0) > 0
            if won then SetStatus(table.concat(parts, ". ") .. ".", 0.25, 1, 0.25)
            else SetStatus(table.concat(parts, ". ") .. ".", 0.85, 0.85, 0.85) end
        else
            SetStatus("Waiting for the next hand.")
        end
    elseif MyTurn() then
        local toCall = T.currentBet - me.bet
        if toCall > 0 then
            SetStatus("Your move - " .. Fmt(math.min(toCall, me.stack)) .. " to call.")
        else
            SetStatus("Your move.")
        end
    elseif T.actor > 0 and T.seats[T.actor] then
        local who = T.seats[T.actor]
        SetStatus(IsMine(who) and "Sending your move..." or ("Waiting for " .. (who.name or "?") .. "..."))
    end
end

local function ClientRoster(f)
    for i = 1, NUM_SEATS do
        local spec = Net.Split(f[3 + i] or "e,", ",")
        local p = T.seats[i] or NewSeat("empty")
        if spec[1] == "b" then p.kind = "bot"
        elseif spec[1] == "e" then p.kind = "empty"
        else p.kind = "human" end
        p.name = (spec[2] and spec[2] ~= "") and spec[2] or nil
        p.seat = i
        T.seats[i] = p
    end
end

local function ClientState(f)
    local hand = tonumber(f[5]) or 0
    local version = tonumber(f[4]) or 0
    local me = Me()
    if hand ~= T.hand then
        for _, p in ipairs(T.seats) do p.hole, p.score = {}, nil end
        T.hand = hand
    end
    local wasMyTurn = MyTurn()
    T.version = version
    T.street = STREET_NAME[f[6]] or "idle"
    T.button = tonumber(f[7]) or 1
    T.actor = tonumber(f[8]) or 0
    T.pot = tonumber(f[9]) or 0
    T.currentBet = tonumber(f[10]) or 0
    T.lastRaise = tonumber(f[11]) or BB
    T.deadline = (f[12] and f[12] ~= "") and (GetTime() + tonumber(f[12])) or nil
    T.reveal = f[13] == "1"
    T.board = DecodeCards(f[14])
    for i = 1, NUM_SEATS do
        local p = T.seats[i] or NewSeat("empty")
        T.seats[i] = p
        p.seat = i
        local v = Net.Split(f[14 + i] or "0,0,0,,0,", ",")
        p.stack, p.bet, p.total = tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0
        local flags = v[4] or ""
        p.folded = string.find(flags, "f", 1, true) ~= nil
        p.allIn = string.find(flags, "a", 1, true) ~= nil
        p.acted = string.find(flags, "c", 1, true) ~= nil
        p.out = string.find(flags, "o", 1, true) ~= nil
        p.leaving = string.find(flags, "l", 1, true) ~= nil
        p.won = tonumber(v[5]) or 0
        p.lastCode = v[6]
        p.last = LastText(v[6])
    end
    me = Me()
    if T.pendingHole and T.pendingHole.hand == T.hand then me.hole = T.pendingHole.cards end

    -- Showdown: name everyone's hand from the cards we were shown.
    if T.reveal and ns.getn(T.board) == 5 then
        for _, p in ipairs(T.seats) do
            if not p.folded and not p.out and p.hole[2] then
                p.score = Evaluate(Seven(p.hole[1], p.hole[2], T.board))
                if p.lastCode == "" or T.street == "idle" then p.last = Describe(p.score) end
            end
        end
    end

    -- Stats, once per hand.
    if T.street ~= "idle" and T.countedHand ~= T.hand and not me.out then
        T.countedHand = T.hand
        db.stats.hands = db.stats.hands + 1
    end
    if T.street == "idle" and T.wonHand ~= T.hand and (me.won or 0) > 0 then
        T.wonHand = T.hand
        db.stats.won = db.stats.won + 1
        if me.won > db.stats.biggestPot then db.stats.biggestPot = me.won end
        if me.score and (not db.stats.best or Compare(me.score, db.stats.best) > 0) then
            db.stats.best, db.stats.bestName = me.score, Describe(me.score)
        end
        ns:PlayGameSound(db, "win")
    end
    if T.street == "idle" and T.lostHand ~= T.hand and T.wonHand ~= T.hand
        and not me.out and (me.won or 0) == 0 and (me.total or 0) > 0 then
        T.lostHand = T.hand
        ns:PlayGameSound(db, "lose")
    end
    if T.street ~= "idle" and T.dealtHand ~= T.hand and not me.out then
        T.dealtHand = T.hand
        ns:PlayGameSound(db, "newHand")
    end

    -- What we'd get back if the host vanished now: our stack before this hand
    -- (between hands, simply our stack).
    local safe = me.stack
    if T.street ~= "idle" then safe = me.stack + me.total end
    db.party = { host = T.host, tid = T.tid, stack = safe }

    if MyTurn() and not wasMyTurn then
        T.raiseTo = ClampRaise(me, MinRaiseTo())
        ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    end
    ClientStatus()
    Refresh()
end

-- What it costs to sit at a table: the host's buy-in (an older CowCasino's
-- offer doesn't say, so 50 big blinds).
local function OfferBuyIn(offer)
    return offer.buyin or 50 * offer.bb
end

local function JoinTable(host, tid)
    local offer = T.offers[host]
    local sb, bb = (offer and offer.sb) or 5, (offer and offer.bb) or 10
    local buyin = offer and OfferBuyIn(offer) or 50 * bb
    if T.seats[1] then return end
    if ns.db.chips < buyin then
        ui.partyMsg:SetText("You need " .. Fmt(buyin) .. " chips for that buy-in.")
        return
    end
    T.joining = { host = host, tid = tid, buyin = buyin, sb = sb, bb = bb }
    Net:Send(Msg({ "J", tid, buyin }))
    ui.partyMsg:SetText("Asking " .. host .. " for a seat...")
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local function OnMessage(sender, f)
    local kind, tid = f[2], f[3]

    -- Anyone: table discovery.
    if kind == "Q" then
        if T.mode == "host" then SendOffer() end
        return
    elseif kind == "O" then
        T.offers[sender] = { tid = tid, sb = tonumber(f[4]) or 5, bb = tonumber(f[5]) or 10,
            players = tonumber(f[6]) or 0, open = tonumber(f[7]) or 0, buyin = tonumber(f[8]), heard = GetTime() }
        if ui.party and ui.party:IsShown() then ui.party:Refresh() end
        return
    end

    -- Host: requests from players at (or joining) our table.
    if T.mode == "host" and tid == T.tid then
        if kind == "J" then
            local buyin = tonumber(f[4]) or 0
            local valid = buyin == T.tableBuyIn
            for _, b in ipairs(BuyIns(BB)) do       -- (an older CowCasino joining)
                if b == buyin then valid = true end
            end
            if not valid then return end
            if T.street == "idle" then
                SeatPlayer(sender, buyin)
                Refresh()
                ScheduleNextHand()
            else
                for _, w in ipairs(T.pending) do
                    if w.name == sender then return end
                end
                table.insert(T.pending, { name = sender, buyin = buyin })
                Net:Send(Msg({ "N", T.tid, sender, "wait" }))
            end
        elseif kind == "A" then
            local i = T.actor
            local p = T.seats[i]
            if not p or p.kind ~= "remote" or p.name ~= sender then return end
            if tonumber(f[4]) ~= T.hand or tonumber(f[5]) ~= T.version or not NeedsToAct(p) then return end
            p.timeouts = 0
            local code, amount = f[6], tonumber(f[7]) or 0
            if code == "f" then
                Act(p, "fold")
            elseif code == "r" and not p.acted and p.stack > T.currentBet - p.bet then
                Act(p, "raise", ClampRaise(p, amount))
            else
                Act(p, "call")
            end
        elseif kind == "L" then
            for i = 2, NUM_SEATS do
                if T.seats[i].kind == "remote" and T.seats[i].name == sender then HostDropPlayer(i) end
            end
        end
        return
    end

    -- Waiting to join.
    if T.joining and sender == T.joining.host and tid == T.joining.tid then
        if kind == "S" and f[4] == Net:Me() then
            local seat, stack = tonumber(f[5]), tonumber(f[6]) or 0
            local joining = T.joining
            T.joining = nil
            if not seat or not ns:SpendChips(stack) then
                Net:Send(Msg({ "L", tid }))
                return
            end
            db.stats.buyIns = db.stats.buyIns + 1
            T.mode, T.host, T.tid, T.mySeat = "client", sender, tid, seat
            SB, BB = joining.sb or 5, joining.bb or 10
            T.seats = {}
            for i = 1, NUM_SEATS do
                T.seats[i] = NewSeat("empty")
                T.seats[i].seat = i
            end
            T.seats[seat] = NewSeat("human", Net:Me(), stack)
            T.seats[seat].seat = seat
            T.hand, T.version, T.street, T.actor = -1, 0, "idle", 0
            T.lastHeard = GetTime()
            db.party = { host = sender, tid = tid, stack = stack }
            ui.party:Hide()
            SetStatus("You sat down at " .. sender .. "'s table with " .. Fmt(joining.buyin) .. ".")
            Refresh()
        elseif kind == "N" and f[4] == Net:Me() then
            if f[5] == "wait" then
                ui.partyMsg:SetText(sender .. " will seat you after this hand.")
            else
                T.joining = nil
                ui.partyMsg:SetText(f[5] or "No seat.")
            end
        end
        return
    end

    -- Client: our table.
    if T.mode ~= "client" or sender ~= T.host or tid ~= T.tid then
        if kind == "X" then
            T.offers[sender] = nil
            if ui.party and ui.party:IsShown() then ui.party:Refresh() end
        end
        return
    end
    T.lastHeard = GetTime()
    if kind == "R" then
        ClientRoster(f)
        -- Safety net: if the host's list no longer has us in our seat, we've
        -- been removed without hearing about it; take our safe stack home.
        local mine = T.seats[MySeat()]
        if mine.kind ~= "human" or mine.name ~= Net:Me() then
            ClientCashOut(db.party and db.party.stack or 0, "You're no longer at " .. sender .. "'s table.")
            return
        end
        Refresh()
    elseif kind == "P" then
        ClientState(f)
    elseif kind == "H" then
        if tonumber(f[5]) == MySeat() then
            T.pendingHole = { hand = tonumber(f[4]), cards = DecodeCards(f[6]) }
            if T.pendingHole.hand == T.hand then Me().hole = T.pendingHole.cards end
            Refresh()
        end
    elseif kind == "V" then
        if tonumber(f[4]) == T.hand then
            for _, entry in ipairs(Net.Split(f[5] or "", ",")) do
                local sep = string.find(entry, ":", 1, true)
                if sep then
                    local seat = tonumber(string.sub(entry, 1, sep - 1))
                    if seat and T.seats[seat] then T.seats[seat].hole = DecodeCards(string.sub(entry, sep + 1)) end
                end
            end
            Refresh()
        end
    elseif kind == "K" then
        if f[4] == Net:Me() then
            ClientCashOut(tonumber(f[5]) or 0, "You were removed from " .. sender .. "'s table for not responding.")
        end
    elseif kind == "X" then
        HostGone(sender .. " closed the table.")
    end
end

Net.handlers[GAME_TAG] = OnMessage

Net.groupHandlers.holdem = function()
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
    if ui.party and ui.party:IsShown() then ui.party:Refresh() end
end

-- Countdown, host heartbeat, and noticing a host that went quiet.
local ticker = ns.CreateFrame("Frame")
local tickWait, beatWait = 0, 0
ticker:SetScript("OnUpdate", function()
    tickWait = tickWait + (arg1 or 0)
    if tickWait < 0.5 then return end
    beatWait = beatWait + tickWait
    tickWait = 0
    if T.deadline and ui.table and ui.table:IsShown() then Refresh() end
    if T.mode == "host" and beatWait >= HEARTBEAT then
        beatWait = 0
        if HasRemote() then
            SendRoster()
            Broadcast()
        end
    elseif T.mode == "client" and T.lastHeard and GetTime() - T.lastHeard > HOST_TIMEOUT then
        HostGone((T.host or "The host") .. " stopped responding.")
    end
end)

---------------------------------------------------------------------------
-- Your actions
---------------------------------------------------------------------------
local function DoFold()
    if not MyTurn() then return end
    if T.mode == "client" then ClientAct("f") else Me().timeouts = 0; Act(Me(), "fold") end
end

local function DoCall()
    if not MyTurn() then return end
    if T.mode == "client" then ClientAct("c") else Me().timeouts = 0; Act(Me(), "call") end
end

local function DoRaise()
    local me = Me()
    if not MyTurn() or me.acted or me.stack <= T.currentBet - me.bet then return end
    if T.mode == "client" then
        ClientAct("r", ClampRaise(me, T.raiseTo))
    else
        me.timeouts = 0
        Act(me, "raise", ClampRaise(me, T.raiseTo))
    end
end

local function SetRaise(to)
    if not MyTurn() then return end
    T.raiseTo = ClampRaise(Me(), to)
    Refresh()
end

local function PotRaise(frac)
    local me = Me()
    local toCall = T.currentBet - me.bet
    SetRaise(T.currentBet + (PotTotal() + toCall) * frac)
end

local function DoLeave()
    if T.mode == "client" then ClientLeave() else Leave() end
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

local function MakeSeat(parent, width, height, cardW, cardH)
    local s = { cards = {} }
    s.frame = ns.CreateFrame("Frame", nil, parent)
    s.frame:SetWidth(width); s.frame:SetHeight(height)

    local bg = s.frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(s.frame)
    bg:SetTexture(0, 0, 0, 0.25)

    s.glow = s.frame:CreateTexture(nil, "BORDER")
    s.glow:SetAllPoints(s.frame)
    s.glow:SetTexture(1, 0.82, 0, 0.18)
    s.glow:Hide()

    s.name = s.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s.stack = s.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.action = s.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.win = s.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s.win:SetText("WIN")
    s.win:SetTextColor(0.3, 1, 0.3)
    s.win:Hide()

    for c = 1, 2 do
        s.cards[c] = ns:CreateCardWidget(s.frame, cardW, cardH)
        s.cards[c]:SetLevel(s.frame:GetFrameLevel() + 2 + c * 3)
    end
    return s
end

local function BuildLobby(panel)
    local l = ns.CreateFrame("Frame", nil, panel)
    l:SetAllPoints(panel)
    ui.lobby = l

    local title = ns:BigFont(l:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 22)
    title:SetPoint("TOP", l, "TOP", 0, -20)
    title:SetText("Texas Hold'em")

    ui.lobbyInfo = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.lobbyInfo:SetPoint("TOP", title, "BOTTOM", 0, -12)
    ui.lobbyInfo:SetWidth(AREA_W - 30)

    local pick = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pick:SetPoint("TOP", l, "TOP", 0, -130)
    pick:SetText("Buy in for")

    ui.buyIns = {}
    local w, gap = 100, 10
    local x0 = (AREA_W - (ns.getn(BUY_IN_BB) * w + (ns.getn(BUY_IN_BB) - 1) * gap)) / 2
    for i = 1, ns.getn(BUY_IN_BB) do
        local i = i   -- own copy for closures (Lua 5.0)
        local b = MakeButton(l, "", w, function() BuyIn(i) end, 26)
        b:SetPoint("TOPLEFT", l, "TOPLEFT", x0 + (i - 1) * (w + gap), -150)
        ui.buyIns[i] = b
    end

    ui.lobbyMsg = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.lobbyMsg:SetPoint("TOP", l, "TOP", 0, -220)
    ui.lobbyMsg:SetWidth(AREA_W - 20)

    local party = MakeButton(l, "Play with your party", 170, function() ui.party:Show() end, 26)
    party:SetPoint("TOP", l, "TOP", 0, -262)

    ui.lobbyStats = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.lobbyStats:SetPoint("BOTTOM", l, "BOTTOM", 0, 16)
    ui.lobbyStats:SetWidth(AREA_W - 20)
end

local function BuildTable(panel)
    local t = ns.CreateFrame("Frame", nil, panel)
    t:SetAllPoints(panel)
    ui.table = t

    local felt = t:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(t)
    felt:SetTexture(0.05, 0.30, 0.12, 0.90)

    -- Opponents across the top: left, middle, right (clockwise from you).
    ui.seats = {}
    local seatW, seatH, gap = 112, 92, 8
    for v = 2, NUM_SEATS do
        local s = MakeSeat(t, seatW, seatH, SMALL_W, SMALL_H)
        s.frame:SetPoint("TOPLEFT", t, "TOPLEFT", (v - 2) * (seatW + gap), 0)
        s.name:SetPoint("TOP", s.frame, "TOP", 0, -3)
        local cx = (seatW - (2 * SMALL_W + 4)) / 2
        s.cards[1]:SetPoint("TOPLEFT", s.frame, "TOPLEFT", cx, -18)
        s.cards[2]:SetPoint("TOPLEFT", s.frame, "TOPLEFT", cx + SMALL_W + 4, -18)
        s.cardX, s.cardXWithPortrait = cx, seatW - (2 * SMALL_W + 4) - 6
        s.portrait = ns:CreatePortrait(s.frame, SMALL_W, SMALL_H)
        s.portrait:SetPoint("TOPLEFT", s.frame, "TOPLEFT", 4, -18)
        s.stack:SetPoint("TOP", s.frame, "TOP", 0, -63)
        s.action:SetPoint("TOP", s.frame, "TOP", 0, -76)
        s.action:SetWidth(seatW - 4)
        s.win:SetPoint("TOPRIGHT", s.frame, "TOPRIGHT", -3, -20)
        ui.seats[v] = s
    end

    ui.pot = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.pot:SetPoint("TOP", t, "TOP", 0, -98)

    ui.blinds = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.blinds:SetPoint("TOPRIGHT", t, "TOPRIGHT", -4, -100)

    ui.partyLabel = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.partyLabel:SetPoint("TOPLEFT", t, "TOPLEFT", 4, -100)

    ui.board = {}
    local bw = 5 * CARD_W + 4 * 5
    for i = 1, 5 do
        local w = ns:CreateCardWidget(t, CARD_W, CARD_H)
        w:SetPoint("TOPLEFT", t, "TOPLEFT", (AREA_W - bw) / 2 + (i - 1) * (CARD_W + 5), -114)
        ui.board[i] = w
    end

    ui.status = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", t, "TOP", 0, -184)
    ui.status:SetWidth(AREA_W - 8)

    -- You
    local me = MakeSeat(t, AREA_W, CARD_H + 8, CARD_W, CARD_H)
    me.frame:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -208)
    me.cards[1]:SetPoint("TOPLEFT", me.frame, "TOPLEFT", 60, -4)
    me.cards[2]:SetPoint("TOPLEFT", me.frame, "TOPLEFT", 60 + CARD_W + 5, -4)
    me.name:SetPoint("TOPLEFT", me.frame, "TOPLEFT", 172, -10)
    me.stack:SetPoint("TOPLEFT", me.frame, "TOPLEFT", 172, -28)
    me.action:SetPoint("TOPLEFT", me.frame, "TOPLEFT", 172, -44)
    me.action:SetWidth(170)
    me.action:SetJustifyH("LEFT")
    me.win:SetPoint("TOPRIGHT", me.frame, "TOPRIGHT", -10, -10)
    me.portrait = ns:CreatePortrait(me.frame, 50, CARD_H)
    me.portrait:SetPoint("TOPLEFT", me.frame, "TOPLEFT", 5, -4)
    ui.seats[1] = me


    -- Raise sizing
    ui.raiseRow = ns.CreateFrame("Frame", nil, t)
    ui.raiseRow:SetWidth(AREA_W); ui.raiseRow:SetHeight(22)
    ui.raiseRow:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -284)
    local sizes = {
        { "-", 30, function() SetRaise(T.raiseTo - (IsShiftKeyDown() and 5 * BB or BB)) end },
        { "+", 30, function() SetRaise(T.raiseTo + (IsShiftKeyDown() and 5 * BB or BB)) end },
        { "Half pot", 76, function() PotRaise(0.5) end },
        { "Pot", 56, function() PotRaise(1) end },
        { "Max", 56, function() local me2 = Me(); SetRaise(me2.stack + me2.bet) end },
    }
    ui.sizeButtons = {}
    local x = (AREA_W - (30 + 30 + 76 + 56 + 56 + 4 * 4)) / 2
    for i, spec in ipairs(sizes) do
        local b = MakeButton(ui.raiseRow, spec[1], spec[2], spec[3])
        b:SetPoint("LEFT", ui.raiseRow, "LEFT", x, 0)
        x = x + spec[2] + 4
        ui.sizeButtons[i] = b
    end

    -- Actions
    ui.actionRow = ns.CreateFrame("Frame", nil, t)
    ui.actionRow:SetWidth(AREA_W); ui.actionRow:SetHeight(26)
    ui.actionRow:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -312)
    ui.fold = MakeButton(ui.actionRow, "Fold", 80, DoFold, 26)
    ui.fold:SetPoint("LEFT", ui.actionRow, "LEFT", 10, 0)
    ui.call = MakeButton(ui.actionRow, "Check", 110, DoCall, 26)
    ui.call:SetPoint("LEFT", ui.fold, "RIGHT", 6, 0)
    ui.raise = MakeButton(ui.actionRow, "Raise", 130, DoRaise, 26)
    ui.raise:SetPoint("LEFT", ui.call, "RIGHT", 6, 0)

    -- Between hands
    ui.betweenRow = ns.CreateFrame("Frame", nil, t)
    ui.betweenRow:SetWidth(AREA_W); ui.betweenRow:SetHeight(26)
    ui.betweenRow:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -312)
    ui.deal = MakeButton(ui.betweenRow, "Deal", 130, StartHand, 26)
    ui.deal:SetPoint("LEFT", ui.betweenRow, "LEFT", 40, 0)
    ui.leave = MakeButton(ui.betweenRow, "Leave table", 130, DoLeave, 26)
    ui.leave:SetPoint("LEFT", ui.deal, "RIGHT", 12, 0)
end

---------------------------------------------------------------------------
-- Overlays: options (card art) and party tables
---------------------------------------------------------------------------
local function Overlay(panel, titleText)
    local o = ns.CreateFrame("Frame", nil, panel)
    o:SetAllPoints(panel)
    o:SetFrameLevel(panel:GetFrameLevel() + 50)
    o:EnableMouse(true)
    o:Hide()
    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0, 0, 0, 0.92)
    local title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", o, "TOP", 0, -10)
    title:SetText(titleText)
    return o
end

local function BuildOptions(panel)
    local o = Overlay(panel, "Hold'em Options")

    local note = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOP", o, "TOP", 0, -32)
    note:SetWidth(AREA_W - 32)
    note:SetText("Card art is in the CowCasino Options, shared by every card game.")

    local done = MakeButton(o, "Done", 90, function() o:Hide() end)
    done:SetPoint("BOTTOM", o, "BOTTOM", 0, 12)

    local sounds = MakeButton(o, "Sounds", 90, function() ui.sounds:Show() end, 24)
    sounds:SetPoint("TOP", o, "TOP", 0, -140)

    -- Blinds for the next table you sit at or host
    local blindsLabel = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    blindsLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -60)
    blindsLabel:SetText("Blinds")
    local blindsValue = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local function StepBlinds(dir)
        db.blinds = math.max(1, math.min(ns.getn(BLIND_LEVELS), (db.blinds or DEFAULT_BLINDS) + dir))
        if not T.seats[1] then SB, BB = ChosenBlinds() end
        Refresh()
        o:Refresh()
    end
    local blindsUp = MakeButton(o, ">", 26, function() StepBlinds(1) end)
    blindsUp:SetPoint("TOPRIGHT", o, "TOPRIGHT", -16, -56)
    blindsValue:SetPoint("RIGHT", blindsUp, "LEFT", -6, 0)
    blindsValue:SetWidth(110)
    blindsValue:SetJustifyH("CENTER")
    local blindsDown = MakeButton(o, "<", 26, function() StepBlinds(-1) end)
    blindsDown:SetPoint("RIGHT", blindsValue, "LEFT", -6, 0)
    local blindsNote = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    blindsNote:SetPoint("TOPLEFT", blindsLabel, "BOTTOMLEFT", 0, -6)
    blindsNote:SetWidth(AREA_W - 32)
    blindsNote:SetJustifyH("LEFT")

    -- Hosts can close their table from here at any time.
    local closeTable = MakeButton(o, "Close table", 140, function()
        Leave()
        o:Refresh()
    end, 24)
    closeTable:SetPoint("BOTTOM", o, "BOTTOM", 0, 48)

    function o:Refresh()
        local sb, bb = ChosenBlinds()
        local level = db.blinds or DEFAULT_BLINDS
        blindsValue:SetText(Fmt(sb) .. " / " .. Fmt(bb))
        ns.SetEnabled(blindsDown, level > 1)
        ns.SetEnabled(blindsUp, level < ns.getn(BLIND_LEVELS))
        local buyIns = BuyIns(bb)
        local text = "Buy-ins " .. Fmt(buyIns[1]) .. ", " .. Fmt(buyIns[2]) .. " or " .. Fmt(buyIns[3]) .. "."
        if T.seats[1] and (SB ~= sb or BB ~= bb) then
            text = text .. " This table stays at " .. Fmt(SB) .. "/" .. Fmt(BB) .. "; these are for your next one."
        elseif T.mode == "client" then
            text = text .. " Party tables use the host's blinds."
        end
        blindsNote:SetText(text)
        if T.mode == "host" and T.seats[1] then
            closeTable:Show()
            if T.street == "idle" then
                closeTable:SetText("Close table")
            elseif T.closeAfterHand then
                closeTable:SetText("Closing...")
            else
                closeTable:SetText("Close after hand")
            end
            ns.SetEnabled(closeTable, T.street == "idle" or not T.closeAfterHand)
        else
            closeTable:Hide()
        end
    end
    o:SetScript("OnShow", function() this:Refresh() end)
    return o
end

local function BuildParty(panel)
    local o = Overlay(panel, "Play with your party")

    local group = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    group:SetPoint("TOP", o, "TOP", 0, -36)
    group:SetWidth(AREA_W - 24)

    -- Hosting: type in the blinds and the buy-in (saved for next time).
    -- Everyone who joins uses them.
    local inputs = {}
    local function Amount(key, labelText, x, width)
        local label = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", o, "TOPLEFT", x, -62)
        label:SetText(labelText)
        local box = ns.CreateFrame("EditBox", nil, o)
        box:SetWidth(width); box:SetHeight(20)
        box:SetPoint("LEFT", label, "RIGHT", 4, 0)
        box:SetFontObject(GameFontHighlightSmall)
        box:SetTextInsets(5, 5, 0, 0)
        box:SetAutoFocus(false)
        box:SetMaxLetters(7)
        box:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        box:SetBackdropColor(0, 0, 0, 0.8)
        box:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
        box:SetScript("OnTextChanged", function()
            if o.filling then return end
            local text = this:GetText() or ""
            local digits = string.gsub(text, "[^0-9]", "")
            if digits ~= text then this:SetText(digits) end
            db.hostSettings = db.hostSettings or {}
            local sb, bb, buyin = HostSettings()
            db.hostSettings.sb, db.hostSettings.bb, db.hostSettings.buyin = sb, bb, buyin
            db.hostSettings[key] = tonumber(digits) or 0      -- (empty: 0, which won't do)
            o:Refresh()
        end)
        box:SetScript("OnEnterPressed", function() this:ClearFocus() end)
        box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
        box:SetScript("OnTabPressed", function()
            local order = { "sb", "bb", "buyin" }
            for n, k in ipairs(order) do
                if k == key then inputs[order[ns.Mod(n, 3) + 1]]:SetFocus() end
            end
        end)
        inputs[key] = box
    end
    Amount("sb", "Small blind", 16, 54)
    Amount("bb", "Big blind", 132, 54)
    Amount("buyin", "Buy-in", 236, 66)

    local hostInfo = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hostInfo:SetPoint("TOP", o, "TOP", 0, -146)
    hostInfo:SetWidth(AREA_W - 24)

    local bots = ns.CreateFrame("CheckButton", ns:NewName(), o, "UICheckButtonTemplate")
    bots:SetWidth(24); bots:SetHeight(24)
    bots:SetPoint("TOPLEFT", o, "TOPLEFT", 12, -88)
    bots:SetScript("OnClick", function() T.fillBots = this:GetChecked() and true or false end)
    local botsText = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    botsText:SetPoint("LEFT", bots, "RIGHT", 2, 0)
    botsText:SetText("When hosting, computer players fill empty seats")

    local host = MakeButton(o, "Host a table", 140, function() HostTable() end, 24)
    host:SetPoint("TOP", o, "TOP", 0, -118)
    -- If you're sitting at a solo table, this takes its place: party play needs you up from it.
    local leaveSolo = MakeButton(o, "Leave your solo table", 170, function()
        Leave()
        o:Refresh()
    end, 24)
    leaveSolo:SetPoint("TOP", o, "TOP", 0, -118)

    local header = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -168)
    header:SetText("Tables in your group")
    local refresh = MakeButton(o, "Refresh", 70, function()
        Net:Send(Msg({ "Q" }))
        o:Refresh()
    end)
    refresh:SetPoint("TOPRIGHT", o, "TOPRIGHT", -16, -164)

    local rows = {}
    for r = 1, 3 do
        local r = r   -- own copy for closures (Lua 5.0)
        local row = {}
        row.text = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("TOPLEFT", o, "TOPLEFT", 18, -196 - (r - 1) * 28)
        row.text:SetWidth(250)
        row.text:SetJustifyH("LEFT")
        row.join = MakeButton(o, "Join", 60, function()
            local offer = rows[r].offer
            if offer then JoinTable(offer.host, offer.tid) end
        end)
        row.join:SetPoint("TOPRIGHT", o, "TOPRIGHT", -16, -190 - (r - 1) * 28)
        rows[r] = row
    end

    ui.partyMsg = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.partyMsg:SetPoint("TOP", o, "TOP", 0, -284)
    ui.partyMsg:SetWidth(AREA_W - 24)

    local close = MakeButton(o, "Close", 90, function() o:Hide() end)
    close:SetPoint("BOTTOM", o, "BOTTOM", 0, 12)

    function o:Refresh()
        local inGroup = Net:InGroup()
        if inGroup then
            group:SetText("You're in a group of " .. Net:GroupSize() .. ". Everyone needs CowCasino to play.")
        else
            group:SetText("Join a party or raid to play with friends.")
        end
        local sb, bb, myBuyIn = HostSettings()
        local problem = HostSettingsProblem(sb, bb, myBuyIn)
        o.filling = true
        for key, box in pairs(inputs) do
            local v = ((key == "sb" and sb) or (key == "bb" and bb) or myBuyIn) or 0
            -- (leave what's typed alone if it says the same, "" for 0 included)
            if (tonumber(box:GetText() or "") or 0) ~= v then box:SetText(v > 0 and tostring(v) or "") end
        end
        o.filling = nil
        if problem then
            hostInfo:SetText("|cffff6060" .. problem .. "|r")
        else
            hostInfo:SetText("Your table: blinds " .. Fmt(sb) .. "/" .. Fmt(bb) .. ", buy-in " .. Fmt(myBuyIn)
                .. " (" .. math.floor(myBuyIn / bb) .. " big blinds). Players who join buy in for the same.")
        end
        bots:SetChecked(T.fillBots)
        local solo = T.mode == "solo" and T.seats[1] ~= nil
        ns.SetShown(host, not solo)
        ns.SetShown(leaveSolo, solo)
        if solo then
            ns.SetEnabled(leaveSolo, T.street == "idle")
            ui.partyMsg:SetText(T.street == "idle"
                and ("You're at a solo table with " .. Fmt(Me().stack) .. ". Leave it (your stack goes back to your chips) to host or join.")
                or "You're in the middle of a solo hand. Finish it, then leave the solo table to play with your party.")
        end
        ns.SetEnabled(host, inGroup and not problem and ns.db.chips >= (myBuyIn or 0) and not T.seats[1])

        local list = {}
        for name, offer in pairs(T.offers) do
            if GetTime() - offer.heard < OFFER_TIMEOUT and Net:IsMember(name) then
                table.insert(list, { host = name, tid = offer.tid, players = offer.players, open = offer.open,
                    sb = offer.sb, bb = offer.bb, buyin = offer.buyin })
            end
        end
        table.sort(list, function(a, b) return a.host < b.host end)
        for r = 1, 3 do
            local offer = list[r]
            rows[r].offer = offer
            if offer then
                local need = OfferBuyIn(offer)
                rows[r].text:SetText(string.format("%s: blinds %s/%s, buy-in %s\n%d seated, %d open",
                    offer.host, Fmt(offer.sb), Fmt(offer.bb), Fmt(need), offer.players, offer.open))
                rows[r].join:Show()
                ns.SetEnabled(rows[r].join, offer.open > 0 and ns.db.chips >= need and not T.joining and not T.seats[1])
            else
                rows[r].text:SetText(r == 1 and (inGroup and "|cff888888No tables yet. Ask someone to host, or host one.|r" or "") or "")
                rows[r].join:Hide()
            end
        end
    end
    o:SetScript("OnShow", function()
        if Net:InGroup() then Net:Send(Msg({ "Q" })) end
        ui.partyMsg:SetText("")
        this:Refresh()
    end)
    return o
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Poker:Build(panel)
    ns.db.holdem = ns.db.holdem or {}
    db = ns.db.holdem
    db.stats = db.stats or {}
    ns:InitSounds(db)
    for k, v in pairs(DEFAULT_STATS) do
        if db.stats[k] == nil then db.stats[k] = v end
    end

    BuildLobby(panel)
    BuildTable(panel)

    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)
    ui.options = BuildOptions(panel)
    ui.sounds = ns:CreateSoundOptions(panel, "Texas Hold'em Options", function() return db end)
    ui.party = BuildParty(panel)

    ResetToLobby()
    local message
    -- A party table can't survive a reload: pay back what was safe.
    if db.partyHost then
        local stack = db.partyHost.stack or 0
        if stack > 0 then ns:AddChips(stack) end
        db.partyHost = nil
        message = "Your party table closed when the game reloaded; " .. Fmt(stack) .. " chips went back to you."
    end
    if db.party then
        local stack = db.party.stack or 0
        if db.party.host and Net:IsMember(db.party.host) then
            Net:Send(Msg({ "L", db.party.tid }))
        end
        if stack > 0 then ns:AddChips(stack) end
        message = "You left " .. (db.party.host or "the") .. "'s table when the game reloaded; "
            .. Fmt(stack) .. " chips went back to you."
        db.party = nil
    end

    if db.seat then
        local interrupted = db.seat.inHand
        SB, BB = db.seat.sb or 5, db.seat.bb or 10   -- the table's own blinds (older saves: 5/10)
        SitDown(db.seat.stacks, db.seat.bots, db.seat.button, db.seat.buyin)
        SaveSeat(false)
        if interrupted then
            SetStatus("Your last hand was interrupted, so it was canceled and everyone has their chips back.")
        else
            SetStatus("Welcome back. Press Deal for the next hand.")
        end
    else
        SetStatus("")
    end
    SetLobbyMessage(message)
    Refresh()
end

function Poker:OnShow()
    if ui.table then Refresh() end
end

function Poker:OnHide()
    if ui.options then ui.options:Hide() end
    if ui.sounds then ui.sounds:Hide() end
    if ui.party then ui.party:Hide() end
end

-- Exposed for tests.
Poker.T, Poker.ui = T, ui
Poker.Evaluate, Poker.Compare, Poker.Describe, Poker.Equity = Evaluate, Compare, Describe, Equity
function Poker.SetSims(n) sims = n end
Poker.Constants = { ACTION_TIME = ACTION_TIME, NEXT_HAND_DELAY = NEXT_HAND_DELAY, HOST_TIMEOUT = HOST_TIMEOUT }

-- For table chat (Chat.lua): the party table you're at and who's at it.
function Poker:ChatTable()
    if (T.mode ~= "host" and T.mode ~= "client") or not T.tid then return nil end
    local host = (T.mode == "host") and Net:Me() or T.host
    local members = { [host] = true }
    for _, p in ipairs(T.seats) do
        if (p.kind == "you" or p.kind == "remote" or p.kind == "human") and p.name then members[p.name] = true end
    end
    return { game = "HE", host = host, tid = T.tid, members = members }
end

-- For the out-of-chips check: seated at a table, or a seat saved from a reload.
-- Start over (Options) can give up a seat at a computer table; a party
-- table has to be left the usual way.
function Poker:CanAbandon()
    local d = ns.db.holdem
    return T.mode == "solo" and not (d and (d.party or d.partyHost))
end
function Poker:Abandon()
    if not self:CanAbandon() then return end
    if ns.db.holdem then ns.db.holdem.seat = nil end
    ResetToLobby()
    Refresh()
end

function Poker:ChipsInPlay()
    local d = ns.db.holdem
    -- seated: chips in play unless your stack is empty between hands
    if T.seats[1] then return (Me() and (Me().stack or 0) > 0) or T.street ~= "idle" end
    return d ~= nil and (d.seat ~= nil or d.party ~= nil or d.partyHost ~= nil)
end

-- A fresh stack after running out (Core.lua): stats start over.
function Poker:ResetStats()
    local d = ns.db.holdem
    if not d then return end
    d.stats = {}
    for k, v in pairs(DEFAULT_STATS) do d.stats[k] = v end
end

ns:RegisterGame(Poker)
