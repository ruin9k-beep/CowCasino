-- CowCasino: Blackjack rules, shared by the solo table and party play
local ns = CowCasino.ns

local Rules = {}
ns.BlackjackRules = Rules

-- Aces count 11 until that would bust, faces count 10.
function Rules.CardValue(card)
    if card.rank == 1 then return 11 end
    if card.rank >= 10 then return 10 end
    return card.rank
end
local CardValue = Rules.CardValue

-- Total of the first `upto` cards (all by default), leaving out face-down
-- ones. Returns the total and whether it is soft.
function Rules.HandValue(cards, upto)
    local total, aces = 0, 0
    for i = 1, (upto or ns.getn(cards)) do
        local c = cards[i]
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
local HandValue = Rules.HandValue

-- A two-card 21 that didn't come from a split.
function Rules.IsBlackjack(hand)
    return ns.getn(hand.cards) == 2 and not hand.fromSplit and HandValue(hand.cards) == 21
end
local IsBlackjack = Rules.IsBlackjack

function Rules.DealerBlackjack(cards)
    return ns.getn(cards) == 2 and not cards[2].hidden and HandValue(cards) == 21
end

-- Two cards of the same value can be split.
function Rules.Pair(hand)
    return ns.getn(hand.cards) == 2 and CardValue(hand.cards[1]) == CardValue(hand.cards[2])
end

function Rules.TotalText(cards, blackjack)
    if ns.getn(cards) == 0 then return "" end
    if blackjack then return "|cffffd100Blackjack!|r" end
    local total, soft = HandValue(cards)
    if total > 21 then return "|cffff5050Bust (" .. total .. ")|r" end
    if soft and total < 21 then return "Soft " .. total end
    return tostring(total)
end

-- What one hand gets back against the dealer's cards: the chips returned
-- (stake included) and a result code: B blackjack, W win, P push, L loss,
-- S surrendered.
function Rules.Settle(hand, dealerTotal, dealerBJ)
    local bet = hand.bet
    if hand.surrendered then return ns.SurrenderBack(bet), "S" end
    local p = HandValue(hand.cards)
    if p > 21 then return 0, "L" end
    local bj = IsBlackjack(hand)
    if bj and not dealerBJ then return ns.BlackjackPay(bet), "B" end
    if dealerBJ and not bj then return 0, "L" end
    if bj then return bet, "P" end
    if dealerTotal > 21 or p > dealerTotal then return bet * 2, "W" end
    if p < dealerTotal then return 0, "L" end
    return bet, "P"
end
