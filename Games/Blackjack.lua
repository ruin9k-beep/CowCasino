-- CowCasino: Blackjack
-- Pretend chips from the shared casino wallet (Core.lua).
-- Blackjack pays 3:2, insurance pays 2:1, dealer peeks
-- for blackjack. Double down, split (up to 4 hands, split aces get one card
-- each), late surrender. Shoe size and dealer soft-17 rule are options.

local ns = CowCasino.ns

local CARD_W, CARD_H = 46, 64       -- the dealer's cards
local MY_CARD_W, MY_CARD_H = 55, 77 -- your cards, 20% bigger
local CARD_GAP     = 5
local AREA_W       = 352     -- width of the game panel
local PORTRAIT_W   = 46      -- your portrait, left of your hands
local PLAYER_X     = PORTRAIT_W + 6
local PLAYER_W     = AREA_W - PLAYER_X
local CENTER_W     = AREA_W - 2 * PLAYER_X   -- centered under the dealer, clear of the portrait
local HAND_GAP     = 6
local DEALER_DELAY = 0.6     -- seconds between dealer draws
local START_CHIPS  = 1000
local MIN_BET      = 5
local MAX_BET      = 1000
local MAX_HANDS    = 4
local CHIP_VALUES  = { 5, 25, 100, 500 }
local DECK_CHOICES = { 1, 2, 4, 6, 8 }

local DEFAULT_SETTINGS = { decks = 6, hitSoft17 = false, surrender = true, doubleAfterSplit = true }
local DEFAULT_STATS    = { rounds = 0, wins = 0, losses = 0, pushes = 0, blackjacks = 0, net = 0, best = START_CHIPS, rebuys = 0 }

local Blackjack = {
    id = "blackjack",
    name = "Blackjack",
    description = "Beat the dealer to 21. Double, split, insurance.\n|cff66ccffSupports Multiplayer|r",
    icon = "Interface\\AddOns\\CowCasino\\Art\\BlackjackIcon",   -- painted (dev/art-src/make_game_icons.py)
    -- the dealer on top of the window (Dealer.lua)
    -- (the picture and name are the dealer picked in CowCasino Options)
    dealer = { idle = "Place your bet and I'll deal." },
}

-- What the dealer says (only while Blackjack is on screen).
-- The chosen dealer's own line for a moment (DEALERS.md lists them), or the
-- fallback. Quiet ones don't talk over something just said.
local function React(event, vars, seconds, fallback, quiet)
    ns.Dealer:React(Blackjack, event, vars, seconds, fallback, quiet)
end

local db      -- ns.db.blackjack
local shoe
local ui = {}

local S = {
    phase = "betting",   -- betting | insurance | player | dealer
    hands = {},          -- player hands, see NewHand
    active = 0,          -- index of the hand being played
    dealer = {},
    holeHidden = false,
    insurance = 0,
    round = 0,           -- bumps each deal so stale timers stop
}

local function Sound(key) ns:Sound(key) end

local function Fmt(n) return ns:FormatChips(n) end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
local function CardValue(card)
    if card.rank == 1 then return 11 end
    if card.rank >= 10 then return 10 end
    return card.rank
end

-- Total and whether it is soft (an ace still counted as 11).
-- "an Ace", "a 7", "an 8", "a King": how the dealer names a card
local CARD_NAMES = { "an Ace", "a 2", "a 3", "a 4", "a 5", "a 6", "a 7", "an 8", "a 9", "a 10", "a Jack", "a Queen", "a King" }
local function CardName(card) return card and CARD_NAMES[card.rank] or "a card" end

local function HandValue(cards, upto)
    local total, aces = 0, 0
    for i = 1, (upto or ns.getn(cards)) do
        local v = CardValue(cards[i])
        total = total + v
        if v == 11 then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end
    return total, aces > 0
end

local function NewHand(bet)
    return { cards = {}, bet = bet }
end

-- A 21 made on a split hand is not a blackjack.
local function IsBlackjack(hand)
    return ns.getn(hand.cards) == 2 and not hand.fromSplit and HandValue(hand.cards) == 21
end

local function DealerBlackjack()
    return ns.getn(S.dealer) == 2 and HandValue(S.dealer) == 21
end

local function ActiveHand()
    return S.hands[S.active]
end

---------------------------------------------------------------------------
-- What the player may do right now
---------------------------------------------------------------------------
local function CanHit(h)
    return S.phase == "player" and h and not h.done
end

local function CanDouble(h)
    return CanHit(h) and ns.getn(h.cards) == 2 and not h.splitAces and ns.db.chips >= h.bet
        and (not h.fromSplit or db.settings.doubleAfterSplit)
end

local function CanSplit(h)
    return CanHit(h) and ns.getn(h.cards) == 2 and ns.getn(S.hands) < MAX_HANDS and ns.db.chips >= h.bet
        and CardValue(h.cards[1]) == CardValue(h.cards[2])
end

local function CanSurrender(h)
    return CanHit(h) and db.settings.surrender and ns.getn(S.hands) == 1 and ns.getn(h.cards) == 2
        and not h.fromSplit
end

---------------------------------------------------------------------------
-- Drawing the table
---------------------------------------------------------------------------
local function LayoutCards(group, cards, hideSecond)
    local width = group.width or AREA_W
    local cw, ch = group.cardW, group.cardH
    local n = ns.getn(cards)
    local step = cw + CARD_GAP
    if n > 1 and cw + (n - 1) * step > width then
        step = (width - cw) / (n - 1)
    end
    local used = (n > 0) and (cw + (n - 1) * step) or 0
    local x0 = (width - used) / 2
    local base = group.row:GetFrameLevel()

    for i = 1, math.max(n, ns.getn(group.cards)) do
        local w = group.cards[i]
        if i <= n then
            if not w then
                w = ns:CreateCardWidget(group.row, cw, ch)
                group.cards[i] = w
            end
            w:ClearAllPoints()
            w:SetPoint("LEFT", group.row, "LEFT", x0 + (i - 1) * step, 0)
            w:SetLevel(base + i * 3)
            w:SetCard(cards[i], not (hideSecond and i == 2))
        elseif w then
            w:Clear()
        end
    end
end

local function TotalText(cards, blackjack)
    if ns.getn(cards) == 0 then return "" end
    if blackjack then return "|cffffd100Blackjack!|r" end
    local total, soft = HandValue(cards)
    if total > 21 then return "|cffff5050Bust (" .. total .. ")|r" end
    if soft and total < 21 then return "Soft " .. total end
    return tostring(total)
end

local function HandInfoText(h)
    if h.result then
        local delta = (h.payout or 0) - h.bet
        local sign = delta > 0 and "+" or (delta < 0 and "-" or "")
        local color = delta > 0 and "|cff40ff40" or (delta < 0 and "|cffff5050" or "|cffcccccc")
        local amount = (delta ~= 0) and (" " .. sign .. Fmt(math.abs(delta))) or ""
        return color .. h.result .. amount .. "|r"
    end
    return "Bet " .. Fmt(h.bet) .. (h.doubled and " (doubled)" or "")
end

local function SetStatus(text, r, g, b)
    ui.status:SetText(text)
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function UpdateStats()
    local s = db.stats
    local net = s.net or 0
    local netText = (net > 0 and ("|cff40ff40+" .. Fmt(net))) or (net < 0 and ("|cffff5050-" .. Fmt(-net))) or "|cffcccccc0"
    ui.stats:SetText(string.format("Rounds %d  Won |cff40ff40%d|r  Lost |cffff5050%d|r  Push |cffcccccc%d|r  Blackjacks |cffffd100%d|r  Net %s|r", s.rounds, s.wins, s.losses, s.pushes, s.blackjacks, netText))
end

local function Refresh()
    ns:UpdateChipsDisplay()

    -- Dealer
    LayoutCards(ui.dealerGroup, S.dealer, S.holeHidden)
    if ns.getn(S.dealer) == 0 then
        ui.dealerLabel:SetText("Dealer")
    elseif S.holeHidden then
        ui.dealerLabel:SetText("Dealer showing " .. HandValue(S.dealer, 1))
    else
        ui.dealerLabel:SetText("Dealer: " .. TotalText(S.dealer, DealerBlackjack()))
    end

    -- Player hands, side by side, centered under the dealer (3-4 split hands
    -- also use the room on the right so the cards stay readable)
    local n = math.max(ns.getn(S.hands), 1)
    local areaW = (n <= 2) and CENTER_W or PLAYER_W
    local w = (areaW - (n - 1) * HAND_GAP) / n
    for i, g in ipairs(ui.hands) do
        local h = S.hands[i]
        if h then
            g.width = w
            g.frame:ClearAllPoints()
            g.frame:SetPoint("TOPLEFT", ui.playerArea, "TOPLEFT", (i - 1) * (w + HAND_GAP), 0)
            g.frame:SetWidth(w)
            LayoutCards(g, h.cards, false)
            g.total:SetText(TotalText(h.cards, IsBlackjack(h)))
            g.info:SetText(HandInfoText(h))
            ns.SetShown(g.glow, S.phase == "player" and i == S.active and ns.getn(S.hands) > 1)
            g.frame:Show()
        else
            g.frame:Hide()
        end
    end

    -- Action buttons
    local h = ActiveHand()
    local insurance = S.phase == "insurance"
    ns.SetShown(ui.actionRow, not insurance)
    ns.SetShown(ui.insuranceRow, insurance)
    ns.SetEnabled(ui.hit, (CanHit(h) and not h.splitAces) and true or false)
    ns.SetEnabled(ui.stand, CanHit(h) and true or false)
    ns.SetEnabled(ui.double, CanDouble(h) and true or false)
    ns.SetEnabled(ui.split, CanSplit(h) and true or false)
    ns.SetEnabled(ui.surrender, CanSurrender(h) and true or false)
    if insurance then
        ui.insYes:SetText("Insure " .. Fmt(ns.InsuranceCost(S.hands[1].bet)))
    end

    -- Betting
    local betting = S.phase == "betting"
    for _, b in ipairs(ui.chipButtons) do ns.SetEnabled(b, betting) end
    ns.SetEnabled(ui.clear, betting and db.bet > 0)
    ui.deal:SetText("Deal " .. Fmt(db.bet))
    ns.SetEnabled(ui.deal, betting and db.bet >= MIN_BET and db.bet <= ns.db.chips)

    if ui.partyButton then ns.SetEnabled(ui.partyButton, betting) end
    if ui.options and ui.options:IsShown() then ui.options:Refresh() end
end

---------------------------------------------------------------------------
-- Settling
---------------------------------------------------------------------------
local function SettleRound()
    local s = db.stats
    S.phase = "betting"
    S.holeHidden = false

    local dealerTotal = HandValue(S.dealer)
    local dBJ = DealerBlackjack()
    local wagered, returned = 0, 0
    local notes = {}

    if S.insurance > 0 then
        wagered = wagered + S.insurance
        if dBJ then
            returned = returned + S.insurance * 3
            notes[ns.getn(notes) + 1] = "Insurance pays."
        end
    end

    for _, h in ipairs(S.hands) do
        local p = HandValue(h.cards)
        local pBJ = IsBlackjack(h)
        local pay, outcome

        if h.surrendered then
            pay, outcome, h.result = ns.SurrenderBack(h.bet), "loss", "Surrendered"
        elseif p > 21 then
            pay, outcome, h.result = 0, "loss", "Bust"
        elseif pBJ and not dBJ then
            pay, outcome, h.result = ns.BlackjackPay(h.bet), "win", "Blackjack"
            s.blackjacks = s.blackjacks + 1
        elseif dBJ and not pBJ then
            pay, outcome, h.result = 0, "loss", "Dealer blackjack"
        elseif pBJ and dBJ then
            pay, outcome, h.result = h.bet, "push", "Push"
        elseif dealerTotal > 21 or p > dealerTotal then
            pay, outcome, h.result = h.bet * 2, "win", "Win"
        elseif p < dealerTotal then
            pay, outcome, h.result = 0, "loss", "Lose"
        else
            pay, outcome, h.result = h.bet, "push", "Push"
        end

        h.payout = pay
        wagered = wagered + h.bet
        returned = returned + pay
        if outcome == "win" then
            s.wins = s.wins + 1
        elseif outcome == "loss" then
            s.losses = s.losses + 1
        else
            s.pushes = s.pushes + 1
        end
    end

    ns:AddChips(returned)
    if ns.db.chips > s.best then s.best = ns.db.chips end

    local net = returned - wagered
    s.net = (s.net or 0) + net
    local head
    if dealerTotal > 21 and not dBJ then table.insert(notes, 1, "Dealer busts.") end
    -- the dealer calls it: a plain call, or the chosen dealer's own line
    local call
    if dBJ then call = "Dealer has blackjack."
    elseif dealerTotal > 21 then call = "I bust with " .. dealerTotal .. "!"
    else call = "Dealer stands on " .. dealerTotal .. "." end
    if net > 0 then call = call .. " Nicely played - you win " .. Fmt(net) .. "."
    elseif net < 0 then call = call .. " The house takes this one."
    else call = call .. " We push." end
    local anyBJ, allBust, surrendered = false, true, false
    for _, h in ipairs(S.hands) do
        if h.result == "Blackjack" then anyBJ = true end
        if h.result ~= "Bust" then allBust = false end
        if h.surrendered then surrendered = true end
    end
    local event
    if net > 0 then
        event = (anyBJ and "playerBlackjack") or (dealerTotal > 21 and "dealerBust") or "win"
    elseif net < 0 then
        event = (dBJ and "dealerBlackjack") or (allBust and "playerBust") or (surrendered and "surrender") or "lose"
    else
        event = "push"
    end
    local first = S.hands[1] and HandValue(S.hands[1].cards)
    React(event, { total = dealerTotal, player = first, win = Fmt(net), loss = Fmt(-net) }, 7, call)
    if net > 0 then
        head = "You win " .. Fmt(net) .. "!"
        SetStatus(head .. " " .. table.concat(notes, " "), 0.25, 1, 0.25)
        ns:PlayGameSound(db, "win")
    elseif net < 0 then
        head = "You lose " .. Fmt(-net) .. "."
        SetStatus(head .. " " .. table.concat(notes, " "), 1, 0.35, 0.35)
        ns:PlayGameSound(db, "lose")
    else
        SetStatus("Even. " .. table.concat(notes, " "), 0.85, 0.85, 0.85)
    end

    -- Keep the last bet for the next round if it is still affordable.
    if db.bet > ns.db.chips then
        db.bet = math.floor(ns.db.chips / MIN_BET) * MIN_BET
    end
    if ns.db.chips < MIN_BET then
        SetStatus(ns:LowChipsText(MIN_BET), 1, 0.35, 0.35)
        if ns.Dealer:Line("broke") then React("broke", nil, 10) end
    end

    Refresh()
    UpdateStats()
end

---------------------------------------------------------------------------
-- Dealer
---------------------------------------------------------------------------
local function DealerStep(round)
    if round ~= S.round or S.phase ~= "dealer" then return end
    local v, soft = HandValue(S.dealer)
    if v < 17 or (v == 17 and soft and db.settings.hitSoft17) then
        S.dealer[ns.getn(S.dealer) + 1] = shoe:Draw()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        Refresh()
        ns:After(DEALER_DELAY, function() DealerStep(round) end)
    else
        SettleRound()
    end
end

local function DealerTurn()
    S.phase = "dealer"
    S.holeHidden = false
    S.active = 0

    -- Nothing left to beat: every hand bust or surrendered.
    local live = false
    for _, h in ipairs(S.hands) do
        if not h.surrendered and HandValue(h.cards) <= 21 then live = true end
    end
    if not live then
        SettleRound()
        return
    end

    SetStatus("Dealer's turn...")
    React("dealerTurn", { up = CardName(S.dealer[1]) }, nil, "My turn.", true)
    Refresh()
    local round = S.round
    ns:After(DEALER_DELAY, function() DealerStep(round) end)
end

---------------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------------
local NextHand

-- Finish the active hand and move to the next one (or the dealer).
function NextHand()
    local h = ActiveHand()
    if h then h.done = true end
    S.active = S.active + 1

    local nh = ActiveHand()
    if not nh then
        DealerTurn()
        return
    end

    -- A split hand gets its second card when it comes into play.
    if ns.getn(nh.cards) < 2 then table.insert(nh.cards, shoe:Draw()) end
    if nh.done or HandValue(nh.cards) == 21 then
        Refresh()
        NextHand()
        return
    end

    SetStatus(string.format("Hand %d of %d - your move.", S.active, ns.getn(S.hands)))
    Refresh()
end

local function Hit()
    local h = ActiveHand()
    if not CanHit(h) or h.splitAces then return end
    local before, soft = HandValue(h.cards)
    table.insert(h.cards, shoe:Draw())
    local v = HandValue(h.cards)
    local vars = { before = before, player = v }
    if v > 21 then React("playerBust", vars, 5)
    elseif v == 21 then React("twentyOne", vars, 5)
    elseif before >= 16 and not soft then React("hitHighSafe", vars, 5) end
    if v >= 21 then
        Refresh()
        NextHand()
    else
        Refresh()
    end
end

local function Stand()
    local h = ActiveHand()
    if not CanHit(h) then return end
    local v = HandValue(h.cards)
    if v <= 12 then React("standLow", { player = v }, 5) end
    NextHand()
end

local function Double()
    local h = ActiveHand()
    if not CanDouble(h) then return end
    ns.db.chips = ns.db.chips - h.bet
    h.bet = h.bet * 2
    h.doubled = true
    table.insert(h.cards, shoe:Draw())
    React("double", { player = HandValue(h.cards), bet = Fmt(h.bet) }, 5)
    Refresh()
    NextHand()
end

local function Split()
    local h = ActiveHand()
    if not CanSplit(h) then return end

    ns.db.chips = ns.db.chips - h.bet
    local nh = NewHand(h.bet)
    -- New card lists for both hands rather than table.remove: in Lua 5.0 a
    -- table that has been through table.remove keeps that size for
    -- table.getn, so cards added afterward wouldn't count (or show).
    -- Cards are always added with table.insert, which keeps the size right.
    nh.cards = { h.cards[2] }
    h.cards = { h.cards[1] }
    h.fromSplit, nh.fromSplit = true, true
    table.insert(S.hands, S.active + 1, nh)
    React("split", nil, 5)

    if h.cards[1].rank == 1 then
        -- Split aces: one card each, then they stand.
        h.splitAces, nh.splitAces = true, true
        table.insert(h.cards, shoe:Draw())
        table.insert(nh.cards, shoe:Draw())
        nh.done = true
        Refresh()
        NextHand()
        return
    end

    table.insert(h.cards, shoe:Draw())
    if HandValue(h.cards) == 21 then
        Refresh()
        NextHand()
        return
    end
    SetStatus(string.format("Hand %d of %d - your move.", S.active, ns.getn(S.hands)))
    Refresh()
end

local function Surrender()
    local h = ActiveHand()
    if not CanSurrender(h) then return end
    h.surrendered = true
    NextHand()
end

---------------------------------------------------------------------------
-- Dealing, insurance and the dealer's peek
---------------------------------------------------------------------------
local function AfterInsurance()
    if DealerBlackjack() then
        S.holeHidden = false
        SettleRound()
        return
    end

    -- Insurance is a side bet: a lost one stays in S.insurance and is
    -- counted as money wagered when the round settles.
    local lostInsurance = S.insurance > 0

    local h = S.hands[1]
    if IsBlackjack(h) then
        S.holeHidden = false
        SettleRound()
        return
    end

    S.phase = "player"
    if lostInsurance then
        SetStatus("No dealer blackjack - insurance lost. Your move.")
    else
        SetStatus("Your move.")
    end
    Refresh()
end

local function TakeInsurance(yes)
    if S.phase ~= "insurance" then return end
    if yes then
        local amount = ns.InsuranceCost(S.hands[1].bet)
        ns.db.chips = ns.db.chips - amount
        S.insurance = amount
    end
    AfterInsurance()
end

local function Deal()
    if S.phase ~= "betting" then return end
    if ns.db.chips < MIN_BET then
        SetStatus(ns:LowChipsText(MIN_BET), 1, 0.35, 0.35)
        return
    end
    if db.bet < MIN_BET or db.bet > ns.db.chips then
        SetStatus("Place a bet of at least " .. MIN_BET .. ".")
        return
    end

    if shoe.decks ~= db.settings.decks then
        shoe = ns:NewShoe(db.settings.decks)
    elseif shoe.needsShuffle then
        shoe:Shuffle()
    end

    S.round = S.round + 1
    db.stats.rounds = db.stats.rounds + 1
    ns.db.chips = ns.db.chips - db.bet

    local h = NewHand(db.bet)
    S.hands = { h }
    S.active = 1
    S.dealer = {}
    S.insurance = 0
    S.holeHidden = true

    h.cards[1]  = shoe:Draw()
    S.dealer[1] = shoe:Draw()
    h.cards[2]  = shoe:Draw()
    S.dealer[2] = shoe:Draw()
    ns:PlayGameSound(db, "newHand")
    React("deal", { player = HandValue(h.cards), up = CardName(S.dealer[1]) }, 6)

    if S.dealer[1].rank == 1 and ns.db.chips >= ns.InsuranceCost(h.bet) then
        S.phase = "insurance"
        if IsBlackjack(h) then
            SetStatus("Blackjack! Dealer shows an Ace - take even money?")
            React("evenMoney", nil, nil, "Blackjack! But I'm showing an Ace - even money?")
        else
            SetStatus("Dealer shows an Ace. Insurance?")
            React("insurance", nil, nil, "I'm showing an Ace. Insurance, anyone?")
        end
        Refresh()
        return
    end

    AfterInsurance()
end

local function AddBet(amount)
    if S.phase ~= "betting" then return end
    local limit = math.min(MAX_BET, ns.db.chips)
    db.bet = math.max(0, math.min(db.bet + amount, limit))
    Refresh()
end

local function ResetAll()
    db.stats = {}
    Fill(db.stats, DEFAULT_STATS)
    S.hands, S.dealer, S.active = {}, {}, 0
    shoe = ns:NewShoe(db.settings.decks)
    SetStatus("Blackjack stats reset.")
    Refresh()
    UpdateStats()
end

---------------------------------------------------------------------------
-- Build helpers
---------------------------------------------------------------------------
local function MakeButton(parent, text, width, onClick)
    local b = ns.CreateFrame("Button", ns:NewName(), parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(24)
    b:SetText(text)
    b:SetScript("OnClick", function() local self, button = this, arg1
        Sound("IG_MAINMENU_OPTION")
        onClick(self, button)
    end)
    return b
end

local function MakeButtonRow(parent, specs, gap)
    local row = ns.CreateFrame("Frame", nil, parent)
    local total = 0
    for i, spec in ipairs(specs) do
        total = total + spec.width + (i > 1 and gap or 0)
    end
    row:SetWidth(total); row:SetHeight(24)

    local x = 0
    for _, spec in ipairs(specs) do
        local b = MakeButton(row, spec.text, spec.width, spec.onClick)
        b:SetPoint("LEFT", row, "LEFT", x, 0)
        x = x + spec.width + gap
        spec.button = b
    end
    return row
end

local function MakeGroup(parent, width, cardW, cardH)
    local g = { cards = {}, width = width, cardW = cardW or CARD_W, cardH = cardH or CARD_H }
    g.frame = ns.CreateFrame("Frame", nil, parent)
    g.frame:SetWidth(width); g.frame:SetHeight(g.cardH + 32)

    g.glow = g.frame:CreateTexture(nil, "BACKGROUND")
    g.glow:SetPoint("TOPLEFT", g.frame, "TOPLEFT", -2, 3)
    g.glow:SetPoint("BOTTOMRIGHT", g.frame, "BOTTOMRIGHT", 2, -1)
    g.glow:SetTexture(1, 0.82, 0, 0.18)
    g.glow:Hide()

    g.row = ns.CreateFrame("Frame", nil, g.frame)
    g.row:SetPoint("TOPLEFT", g.row:GetParent(), "TOPLEFT", 0, 0)
    g.row:SetPoint("TOPRIGHT", g.row:GetParent(), "TOPRIGHT", 0, 0)
    g.row:SetHeight(g.cardH)

    g.total = g.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    g.total:SetPoint("TOP", g.row, "BOTTOM", 0, -3)

    g.info = g.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g.info:SetPoint("TOP", g.total, "BOTTOM", 0, -2)
    return g
end

---------------------------------------------------------------------------
-- Options overlay
---------------------------------------------------------------------------
local function MakeCycler(parent, y, label, getText, step)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    text:SetText(label)

    local nextB = MakeButton(parent, ">", 26, function() step(1) end)
    nextB:SetPoint("TOPRIGHT", nextB:GetParent(), "TOPRIGHT", -16, y + 4)

    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    value:SetWidth(110)
    value:SetJustifyH("CENTER")

    local prevB = MakeButton(parent, "<", 26, function() step(-1) end)
    prevB:SetPoint("RIGHT", value, "LEFT", -6, 0)

    return function() value:SetText(getText()) end
end

local function MakeCheck(parent, y, label, key)
    local cb = ns.CreateFrame("CheckButton", ns:NewName(), parent, "UICheckButtonTemplate")
    cb:SetWidth(24); cb:SetHeight(24)
    cb:SetPoint("TOPLEFT", cb:GetParent(), "TOPLEFT", 12, y + 4)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    cb:SetScript("OnClick", function() local self = this
        db.settings[key] = self:GetChecked() and true or false
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        Refresh()
    end)
    return function() cb:SetChecked(db.settings[key]) end
end

local function IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
    return 1
end

local function BuildOptions(panel)
    local o = ns.CreateFrame("Frame", nil, panel)
    o:SetAllPoints(o:GetParent())
    o:SetFrameLevel(panel:GetFrameLevel() + 50)
    o:EnableMouse(true)
    o:Hide()

    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0, 0, 0, 0.92)

    local title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", o, "TOP", 0, -10)
    title:SetText("Blackjack Options")
    local shared = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    shared:SetPoint("TOP", title, "BOTTOM", 0, -2)
    shared:SetText("Sounds apply to solo and party play. Card art is in the CowCasino Options.")

    local refreshers = {}

    -- Shoe size (applies from the next deal)
    refreshers[ns.getn(refreshers) + 1] = MakeCycler(o, -48, "Decks in the shoe",
        function()
            local d = db.settings.decks
            return d .. (d == 1 and " deck" or " decks")
        end,
        function(dir)
            local i = IndexOf(DECK_CHOICES, db.settings.decks)
            i = math.max(1, math.min(ns.getn(DECK_CHOICES), i + dir))
            db.settings.decks = DECK_CHOICES[i]
            o:Refresh()
        end)

    refreshers[ns.getn(refreshers) + 1] = MakeCheck(o, -84, "Dealer hits soft 17", "hitSoft17")
    refreshers[ns.getn(refreshers) + 1] = MakeCheck(o, -110, "Allow surrender", "surrender")
    refreshers[ns.getn(refreshers) + 1] = MakeCheck(o, -136, "Allow double after split", "doubleAfterSplit")

    -- Reset needs a second click within 3 seconds.
    local reset
    reset = MakeButton(o, "Reset stats", 150, function()
        if reset.armed then
            reset.armed = nil
            ResetAll()
            o:Refresh()
        else
            reset.armed = true
            reset:SetText("Click again to reset")
            ns:After(3, function()
                if reset.armed then
                    reset.armed = nil
                    reset:SetText("Reset stats")
                end
            end)
        end
    end)
    reset:SetPoint("BOTTOMLEFT", reset:GetParent(), "BOTTOMLEFT", 16, 40)

    local done = MakeButton(o, "Done", 90, function() o:Hide() end)
    done:SetPoint("BOTTOMRIGHT", done:GetParent(), "BOTTOMRIGHT", -16, 40)

    local sounds = MakeButton(o, "Sounds", 72, function() ui.sounds:Show() end)
    sounds:SetPoint("BOTTOM", sounds:GetParent(), "BOTTOM", 30, 40)

    local rules = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rules:SetPoint("BOTTOM", o, "BOTTOM", 0, 14)
    rules:SetText("Rules above are for your solo table; party tables use the standard rules.")

    function o:Refresh()
        for _, r in ipairs(refreshers) do r() end
        ns.SetEnabled(reset, S.phase == "betting")
        if not reset.armed then reset:SetText("Reset stats") end
    end

    o:SetScript("OnShow", function() local self = this self:Refresh() end)
    return o
end

-- Party play: the party lobby and table (Games\\PartyBlackjack.lua) take
-- over this window, the way Hold'em's party tables do.
local function BuildParty(panel)
    local party = ns.PartyBlackjack
    local partyFrame = ns.CreateFrame("Frame", nil, panel)
    partyFrame:SetAllPoints(panel)
    partyFrame:SetFrameLevel(panel:GetFrameLevel() + 20)
    partyFrame:EnableMouse(true)
    partyFrame:Hide()
    ui.partyFrame = partyFrame
    party:Build(partyFrame)
    party.onBack = function()
        partyFrame:Hide()
        Refresh()
    end
    -- The solo table steps aside completely while party play is up.
    local solo = { ui.dealerGroup.frame, ui.playerArea, ui.betRow, ui.actionRow, ui.insuranceRow, ui.portrait }
    partyFrame:SetScript("OnShow", function()
        for _, f in ipairs(solo) do f:Hide() end
        ui.partyButton:Hide()
    end)
    partyFrame:SetScript("OnHide", function()
        ui.dealerGroup.frame:Show()
        ui.playerArea:Show()
        ui.betRow:Show()
        ui.portrait:Show()
        ui.partyButton:Show()
        Refresh()
    end)
    ui.partyButton = MakeButton(panel, "Party play", 80, function()
        if S.phase ~= "betting" then return end
        partyFrame:Show()
        party:OnShow()
    end)
    ui.partyButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -2)
    ui.partyButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Party play")
        GameTooltip:AddLine("Host or join a blackjack table with your party or raid.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ui.partyButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Options, sounds and party play: the screens that open over the table.
local function BuildOverlays(panel)
    ui.options = BuildOptions(panel)
    ui.sounds = ns:CreateSoundOptions(panel, "Blackjack Options", function() return db end)
    BuildParty(panel)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Blackjack:Build(panel)
    ns.db.blackjack = ns.db.blackjack or {}
    db = ns.db.blackjack

    -- Move stats saved by the earlier test version.
    if db.wins and not db.stats then
        db.stats = { wins = db.wins, losses = db.losses or 0, pushes = db.pushes or 0,
                     blackjacks = db.blackjacks or 0 }
        db.wins, db.losses, db.pushes, db.blackjacks = nil, nil, nil, nil
    end

    if db.bet == nil then db.bet = 25 end
    db.settings = db.settings or {}
    db.stats = db.stats or {}
    Fill(db.settings, DEFAULT_SETTINGS)
    Fill(db.stats, DEFAULT_STATS)
    ns:InitSounds(db)

    shoe = ns:NewShoe(db.settings.decks)

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.05, 0.30, 0.12, 0.90)

    -- Options sits in the top bar, opposite the "< Games" button.
    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    -- Dealer
    ui.dealerLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.dealerLabel:SetPoint("TOP", panel, "TOP", 0, -6)

    ui.dealerGroup = MakeGroup(panel, AREA_W)
    ui.dealerGroup.frame:SetPoint("TOPLEFT", ui.dealerGroup.frame:GetParent(), "TOPLEFT", 0, -24)
    ui.dealerGroup.frame:SetHeight(CARD_H)

    -- Status line
    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", panel, "TOP", 0, -100)
    ui.status:SetWidth(AREA_W - 8)

    -- Player hands
    ui.playerArea = ns.CreateFrame("Frame", nil, panel)
    ui.playerArea:SetPoint("TOPLEFT", ui.playerArea:GetParent(), "TOPLEFT", PLAYER_X, -124)
    ui.playerArea:SetWidth(PLAYER_W); ui.playerArea:SetHeight(MY_CARD_H + 32)
    ui.portrait = ns:CreatePortrait(panel, PORTRAIT_W, CARD_H)
    ui.portrait:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -124)
    ui.portrait:ShowUnit("player")
    ui.hands = {}
    for i = 1, MAX_HANDS do
        ui.hands[i] = MakeGroup(ui.playerArea, PLAYER_W, MY_CARD_W, MY_CARD_H)
        ui.hands[i].frame:Hide()
    end

    -- Action buttons
    local actions = {
        { text = "Hit",       width = 64, onClick = Hit },
        { text = "Stand",     width = 64, onClick = Stand },
        { text = "Double",    width = 64, onClick = Double },
        { text = "Split",     width = 64, onClick = Split },
        { text = "Surrender", width = 72, onClick = Surrender },
    }
    ui.actionRow = MakeButtonRow(panel, actions, 4)
    ui.actionRow:SetPoint("BOTTOM", ui.actionRow:GetParent(), "BOTTOM", 0, 70)
    ui.hit, ui.stand, ui.double, ui.split, ui.surrender =
        actions[1].button, actions[2].button, actions[3].button, actions[4].button, actions[5].button

    local insurance = {
        { text = "Insure",    width = 110, onClick = function() TakeInsurance(true) end },
        { text = "No thanks", width = 110, onClick = function() TakeInsurance(false) end },
    }
    ui.insuranceRow = MakeButtonRow(panel, insurance, 8)
    ui.insuranceRow:SetPoint("BOTTOM", ui.insuranceRow:GetParent(), "BOTTOM", 0, 70)
    ui.insYes = insurance[1].button
    ui.insuranceRow:Hide()

    -- Betting: left-click a chip to add it, right-click to take it back
    local betSpecs = {}
    for _, v in ipairs(CHIP_VALUES) do
        local v = v   -- own copy for closures (Lua 5.0)
        betSpecs[ns.getn(betSpecs) + 1] = {
            text = tostring(v), width = 42,
            onClick = function(_, button) AddBet(button == "RightButton" and -v or v) end,
        }
    end
    betSpecs[ns.getn(betSpecs) + 1] = { text = "Clear", width = 52, onClick = function() AddBet(-db.bet) end }
    betSpecs[ns.getn(betSpecs) + 1] = { text = "Deal", width = 100, onClick = Deal }
    ui.betRow = MakeButtonRow(panel, betSpecs, 4)
    ui.betRow:SetPoint("BOTTOM", ui.betRow:GetParent(), "BOTTOM", 0, 38)

    ui.chipButtons = {}
    for i = 1, ns.getn(CHIP_VALUES) do
        local i = i   -- own copy for closures (Lua 5.0)
        local b = betSpecs[i].button
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnEnter", function() local self = this
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Chip " .. CHIP_VALUES[i])
            GameTooltip:AddLine("Left-click to add, right-click to take back.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ui.chipButtons[i] = b
    end
    ui.clear = betSpecs[ns.getn(CHIP_VALUES) + 1].button
    ui.deal = betSpecs[ns.getn(CHIP_VALUES) + 2].button

    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 12)

    BuildOverlays(panel)

    SetStatus("Place your bet and press Deal.")
    Refresh()
    UpdateStats()
end

function Blackjack:OnShow()
    -- after a fresh stack the last bet may be 0: start again from 25
    if db and S.phase == "betting" and (db.bet < MIN_BET or db.bet > ns.db.chips) then
        db.bet = math.min(25, math.floor(ns.db.chips / MIN_BET) * MIN_BET)
    end
    if ui.status then Refresh() end
    -- Back at your party table, if you're at one.
    local party = ns.PartyBlackjack
    if ui.partyFrame and (party:IsSeated() or ui.partyFrame:IsShown()) then
        ui.partyFrame:Show()
        party:OnShow()
    end
end

function Blackjack:OnHide()
    if ui.options then ui.options:Hide() end
    if ui.sounds then ui.sounds:Hide() end
end

-- For the out-of-chips check: a round is in progress.
function Blackjack:ChipsInPlay()
    return S.phase ~= "betting"
end

-- Start over (Options) gives up a hand in progress.
function Blackjack:Abandon()
    S.round = S.round + 1          -- stops the dealer's timers
    S.phase, S.hands, S.dealer, S.active = "betting", {}, {}, 0
    S.holeHidden, S.insurance = false, 0
    if ui.status then Refresh() end
end

-- A fresh stack after running out (Core.lua): stats start over.
function Blackjack:ResetStats()
    local d = ns.db.blackjack
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    d.stats.best = ns.db.chips
    if ui.status then UpdateStats() end
end

ns:RegisterGame(Blackjack)
