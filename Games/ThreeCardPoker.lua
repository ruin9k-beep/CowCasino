-- CowCasino: Three Card Poker
-- Put up an Ante (and, if you like, a Pair Plus bet) and get three cards.
-- Then Play (bet the Ante again) or Fold. The dealer needs Queen high or
-- better to play:
--   * dealer doesn't qualify: the Ante pays 1 to 1, the Play bet comes back
--   * your hand beats the dealer's: Ante and Play both pay 1 to 1
--   * a tie: both come back; the dealer's better hand takes both
-- The Ante bonus pays on a straight (1 to 1), three of a kind (4 to 1) or a
-- straight flush (5 to 1) whatever the dealer has, once you Play.
-- Pair Plus pays on your three cards alone, even if you fold:
--   pair 1, flush 4, straight 6, three of a kind 30, straight flush 40 (to 1).
-- In three cards a straight beats a flush (it's rarer), and A-2-3 is the
-- lowest straight. A dealt hand is saved, so a reload doesn't lose it.

local ns = CowCasino.ns

local AREA_W     = 352
local CARD_W, CARD_H = 62, 86
local CARD_GAP   = 8
local ANTES      = { 5, 10, 25, 50, 100, 250, 500, 1000 }
local PAIR_PLUS  = { 0, 5, 10, 25, 50, 100, 250, 500, 1000 }

-- Hand categories, best last
local HIGH, PAIR, FLUSH, STRAIGHT, TRIPS, SFLUSH = 1, 2, 3, 4, 5, 6
local CAT_NAME = { "High card", "Pair", "Flush", "Straight", "Three of a Kind", "Straight Flush" }
local PAIR_PLUS_PAY = { [PAIR] = 1, [FLUSH] = 4, [STRAIGHT] = 6, [TRIPS] = 30, [SFLUSH] = 40 }
local ANTE_BONUS    = { [STRAIGHT] = 1, [TRIPS] = 4, [SFLUSH] = 5 }

local DEFAULT_STATS = { hands = 0, wins = 0, folds = 0, pairPlusWins = 0, biggestWin = 0, wagered = 0, won = 0 }

local TCP = {
    id = "threecard",
    name = "Three Card Poker",
    description = "Three cards against the dealer's three. Play or fold, with a Pair Plus side bet.",
    icon = "Interface\\AddOns\\CowCasino\\Art\\ThreeCardIcon",   -- painted (dev/art-src/make_game_icons.py)
    dealer = { idle = "Ante up! I play with Queen high or better." },
}

local db
local ui = {}
local last          -- the last hand, for the screen: { cards, dealer, result text }

local function Fmt(n) return ns:FormatChips(n) end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function Say(event, vars, fallback, quiet)
    if ns.Dealer then ns.Dealer:React(TCP, event, vars, nil, fallback, quiet) end
end

---------------------------------------------------------------------------
-- Hands
---------------------------------------------------------------------------
-- Three cards -> category (HIGH..SFLUSH) and a number that orders hands of
-- the same category (bigger is better).
local function Evaluate(cards)
    local r = {}
    for i = 1, 3 do r[i] = (cards[i].rank == 1) and 14 or cards[i].rank end
    table.sort(r)
    local a, b, c = r[1], r[2], r[3]
    local flush = cards[1].suit == cards[2].suit and cards[2].suit == cards[3].suit
    local straightHigh
    if a ~= b and b ~= c then
        if c - a == 2 then straightHigh = c
        elseif a == 2 and b == 3 and c == 14 then straightHigh = 3 end   -- A-2-3, the lowest
    end
    if straightHigh and flush then return SFLUSH, straightHigh end
    if a == c then return TRIPS, c end
    if straightHigh then return STRAIGHT, straightHigh end
    if flush then return FLUSH, c * 225 + b * 15 + a end
    if a == b then return PAIR, a * 15 + c end
    if b == c then return PAIR, c * 15 + a end
    return HIGH, c * 225 + b * 15 + a
end

-- Does the dealer play? Queen high or better.
local function Qualifies(cards)
    local cat, key = Evaluate(cards)
    if cat > HIGH then return true end
    return math.floor(key / 225) >= 12
end

-- 1 if hand a beats b, -1 if b wins, 0 for a tie.
local function Compare(a, b)
    local ca, ka = Evaluate(a)
    local cb, kb = Evaluate(b)
    if ca ~= cb then return ca > cb and 1 or -1 end
    if ka ~= kb then return ka > kb and 1 or -1 end
    return 0
end

local function HandName(cards)
    local cat, key = Evaluate(cards)
    if cat == HIGH then
        local high = math.floor(key / 225)
        return ns.RANKS[high == 14 and 1 or high].name .. " high"
    elseif cat == PAIR then
        local p = math.floor(key / 15)
        return "Pair of " .. ns.RANKS[p == 14 and 1 or p].name .. (p == 6 and "es" or "s")
    end
    return CAT_NAME[cat]
end

-- What every bet comes to when the hand is played out. play: whether the
-- player played (false = folded). Returns the chips paid back (stakes
-- included) and a table of what happened.
local function Settle(h, play)
    local out = { paid = 0 }
    local cat = Evaluate(h.cards)
    -- Pair Plus: on the player's cards alone, fold or not
    if h.pp > 0 and PAIR_PLUS_PAY[cat] then
        out.pairPlus = h.pp * PAIR_PLUS_PAY[cat]
        out.paid = out.paid + h.pp + out.pairPlus
    end
    if not play then
        out.result = "fold"
        return out
    end
    if ANTE_BONUS[cat] then
        out.bonus = h.ante * ANTE_BONUS[cat]
        out.paid = out.paid + out.bonus
    end
    if not Qualifies(h.dealer) then
        out.result = "noQualify"
        out.paid = out.paid + h.ante * 2 + h.ante        -- ante wins, play pushes
    else
        local cmp = Compare(h.cards, h.dealer)
        if cmp > 0 then
            out.result = "win"
            out.paid = out.paid + h.ante * 4
        elseif cmp == 0 then
            out.result = "push"
            out.paid = out.paid + h.ante * 2
        else
            out.result = "lose"
        end
    end
    return out
end

local function NewDeck() return ns:NewShoe(1) end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function SetStatus(text, r, g, b)
    ui.status:SetText(text or "")
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function StatsText()
    local s = db.stats
    local net = s.won - s.wagered
    local netText = (net > 0 and ("|cff40ff40+" .. Fmt(net))) or (net < 0 and ("|cffff5050-" .. Fmt(-net))) or "|cffcccccc0"
    return string.format("Hands %d  Wins %d  Folds %d  Pair Plus %d  Net %s|r",
        s.hands, s.wins, s.folds, s.pairPlusWins, netText)
end

local function NeedFor(ante, pp) return ante * 2 + pp end

local function Refresh()
    if not ui.cards then return end
    ns:UpdateChipsDisplay()
    local h = db.hand
    local mine = (h and h.cards) or (last and last.cards)
    local theirs = last and last.dealer
    for k = 1, 3 do
        if mine then ui.cards[k]:SetCard(mine[k], true) else ui.cards[k]:SetCard({ rank = 1, suit = 1 }, false) end
        -- the dealer's cards stay face down until the hand is played out
        if theirs and not h then ui.dealerCards[k]:SetCard(theirs[k], true)
        else ui.dealerCards[k]:SetCard({ rank = 1, suit = 1 }, false) end
    end
    ui.myHand:SetText(mine and HandName(mine) or "")
    if theirs and not h then
        ui.dealerHand:SetText(HandName(theirs) .. (Qualifies(theirs) and "" or "  |cffaaaaaa(doesn't qualify)|r"))
    else
        ui.dealerHand:SetText("")
    end

    ui.anteText:SetText("Ante |cffffffff" .. Fmt(db.ante) .. "|r")
    ui.ppText:SetText("Pair Plus " .. (db.pp > 0 and ("|cffffffff" .. Fmt(db.pp) .. "|r") or "|cff999999off|r"))
    local idle = h == nil
    local ai, pi = 1, 1
    for i, v in ipairs(ANTES) do if v == db.ante then ai = i end end
    for i, v in ipairs(PAIR_PLUS) do if v == db.pp then pi = i end end
    ns.SetEnabled(ui.anteDown, idle and ai > 1)
    ns.SetEnabled(ui.anteUp, idle and ai < ns.getn(ANTES))
    ns.SetEnabled(ui.ppDown, idle and pi > 1)
    ns.SetEnabled(ui.ppUp, idle and pi < ns.getn(PAIR_PLUS))
    if idle then
        ui.deal:SetText("Deal " .. Fmt(db.ante + db.pp))
        ns.SetEnabled(ui.deal, ns.db.chips >= NeedFor(db.ante, db.pp))
        ui.deal:Show(); ui.play:Hide(); ui.fold:Hide()
    else
        ui.play:SetText("Play " .. Fmt(h.ante))
        ns.SetEnabled(ui.play, ns.db.chips >= h.ante)
        ui.deal:Hide(); ui.play:Show(); ui.fold:Show()
    end
    ui.stats:SetText(StatsText())
end

---------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------
local function Deal()
    if db.hand then return end
    local bet = db.ante + db.pp
    if ns.db.chips < NeedFor(db.ante, db.pp) or not ns:SpendChips(bet) then
        SetStatus(ns:LowChipsText(NeedFor(ANTES[1], 0)), 1, 0.35, 0.35)
        return
    end
    local deck = NewDeck()
    local cards, dealer = {}, {}
    for k = 1, 3 do cards[k] = deck:Draw() end
    for k = 1, 3 do dealer[k] = deck:Draw() end
    db.hand = { ante = db.ante, pp = db.pp, cards = cards, dealer = dealer }
    last = nil
    db.stats.hands = db.stats.hands + 1
    db.stats.wagered = db.stats.wagered + bet
    SetStatus("You have " .. HandName(cards) .. ". Play for " .. Fmt(db.ante) .. ", or Fold?")
    ns:PlayGameSound(db, "newHand")
    Say("tcpDeal", { hand = HandName(cards) }, nil, true)
    Refresh()
end

local function Finish(play)
    local h = db.hand
    if not h then return end
    if play then
        if not ns:SpendChips(h.ante) then return end
        db.stats.wagered = db.stats.wagered + h.ante
    end
    db.hand = nil
    local out = Settle(h, play)
    local s = db.stats
    last = { cards = h.cards, dealer = h.dealer }
    if out.paid > 0 then
        ns:AddChips(out.paid)
        s.won = s.won + out.paid
    end
    if out.pairPlus then s.pairPlusWins = s.pairPlusWins + 1 end
    local staked = h.ante + h.pp + (play and h.ante or 0)
    local net = out.paid - staked
    if net > s.biggestWin then s.biggestWin = net end

    local extras = {}
    if out.bonus then table.insert(extras, "Ante bonus " .. Fmt(out.bonus)) end
    if out.pairPlus then table.insert(extras, "Pair Plus " .. Fmt(out.pairPlus)) end
    local extra = extras[1] and (" (" .. table.concat(extras, ", ") .. ")") or ""
    local mine, theirs = HandName(h.cards), HandName(h.dealer)
    local vars = { hand = mine, dealer = theirs, amount = Fmt(math.max(net, 0)) }

    if out.result == "fold" then
        s.folds = s.folds + 1
        if out.pairPlus then
            SetStatus("Folded. Pair Plus pays " .. Fmt(out.pairPlus) .. ".", 0.4, 0.8, 1)
        else
            SetStatus("Folded. The dealer had " .. theirs .. ".", 0.85, 0.85, 0.85)
        end
        Say("tcpFold", vars, "Folded. On to the next one.")
        ns:PlayGameSound(db, "lose")
    elseif out.result == "noQualify" then
        s.wins = s.wins + 1
        SetStatus("Dealer has " .. theirs .. " and doesn't qualify. Ante pays" .. extra .. ": +" .. Fmt(net) .. ".", 0.25, 1, 0.25)
        Say("tcpNoQualify", vars, "I don't qualify. Your Ante wins.")
        ns:PlayGameSound(db, "win")
    elseif out.result == "win" then
        s.wins = s.wins + 1
        SetStatus(mine .. " beats " .. theirs .. "!" .. extra .. " +" .. Fmt(net) .. ".", 0.25, 1, 0.25)
        Say("tcpWin", vars, "Your hand wins.")
        ns:PlayGameSound(db, "win")
    elseif out.result == "push" then
        SetStatus("A tie: " .. mine .. " each. Ante and Play come back" .. extra .. ".", 0.85, 0.85, 0.85)
        Say("tcpPush", vars, "A push.")
    else
        SetStatus("Dealer's " .. theirs .. " beats your " .. mine .. "." .. (extra ~= "" and (" " .. extra) or ""), 1, 0.45, 0.45)
        Say("tcpLose", vars, "The dealer's hand wins.")
        ns:PlayGameSound(db, "lose")
    end
    if out.pairPlus and out.pairPlus >= h.pp * 30 then
        ns:Sound("UI_EPICLOOT_TOAST")
        Say("tcpBigPairPlus", vars, "Pair Plus pays big!")
    end
    if ns.db.chips < NeedFor(ANTES[1], 0) then
        SetStatus(ns:LowChipsText(NeedFor(ANTES[1], 0)), 1, 0.35, 0.35)
    end
    -- a smaller bet if the chips no longer cover this one
    while ns.db.chips < NeedFor(db.ante, db.pp) and db.pp > 0 do
        local i = 1
        for k, v in ipairs(PAIR_PLUS) do if v == db.pp then i = k end end
        db.pp = PAIR_PLUS[i - 1] or 0
    end
    while ns.db.chips < NeedFor(db.ante, 0) and db.ante > ANTES[1] do
        local i = 1
        for k, v in ipairs(ANTES) do if v == db.ante then i = k end end
        db.ante = ANTES[i - 1]
    end
    Refresh()
end

local function Step(list, key, dir)
    if db.hand then return end
    local idx = 1
    for i, v in ipairs(list) do if v == db[key] then idx = i end end
    idx = math.max(1, math.min(ns.getn(list), idx + dir))
    db[key] = list[idx]
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
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

local function BuildOptions(panel)
    local o = ns.CreateFrame("Frame", nil, panel)
    o:SetAllPoints(panel)
    o:SetFrameLevel(panel:GetFrameLevel() + 50)
    o:EnableMouse(true)
    o:Hide()
    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0, 0, 0, 0.94)
    local title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", o, "TOP", 0, -10)
    title:SetText("Three Card Poker Options")

    local rules = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rules:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -40)
    rules:SetWidth(AREA_W - 32)
    rules:SetJustifyH("LEFT")
    rules:SetText("How it plays: bet the Ante (and Pair Plus if you like) and Deal. Look at your three cards, then "
        .. "Play (bet the Ante again) or Fold (lose the Ante).\n\n"
        .. "The dealer needs Queen high or better. If not, your Ante pays 1 to 1 and the Play bet comes back. "
        .. "If it does, the better hand wins Ante and Play at 1 to 1; a tie gives both back.\n\n"
        .. "Ante bonus (when you Play, whatever the dealer has): straight 1, three of a kind 4, straight flush 5.\n"
        .. "Pair Plus (on your cards alone, even if you fold): pair 1, flush 4, straight 6, three of a kind 30, "
        .. "straight flush 40.\n\n"
        .. "Hands, best first: straight flush, three of a kind, straight, flush, pair, high card. "
        .. "A-2-3 is the lowest straight. Tip: Play with Queen-6-4 or better, and fold worse.")

    local reset
    reset = MakeButton(o, "Reset stats", 110, function()
        if reset.armed and GetTime() - reset.armed <= 3 then
            reset.armed = nil
            reset:SetText("Reset stats")
            db.stats = {}
            Fill(db.stats, DEFAULT_STATS)
            Refresh()
            return
        end
        reset.armed = GetTime()
        reset:SetText("Sure? Click again")
    end)
    reset:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", 16, 40)
    local sounds = MakeButton(o, "Sounds", 80, function() ui.sounds:Show() end)
    sounds:SetPoint("BOTTOM", o, "BOTTOM", 0, 40)
    local done = MakeButton(o, "Done", 90, function() o:Hide() end)
    done:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -16, 40)
    o:SetScript("OnShow", function()
        reset.armed = nil
        reset:SetText("Reset stats")
    end)
    return o
end

local function CardRow(panel, top)
    local row = {}
    local x0 = (AREA_W - (3 * CARD_W + 2 * CARD_GAP)) / 2
    for k = 1, 3 do
        local w = ns:CreateCardWidget(panel, CARD_W, CARD_H)
        w:SetPoint("TOPLEFT", panel, "TOPLEFT", x0 + (k - 1) * (CARD_W + CARD_GAP), top)
        w:SetLevel(panel:GetFrameLevel() + 5)
        row[k] = w
    end
    return row
end

function TCP:Build(panel)
    ns.db.threecard = ns.db.threecard or {}
    db = ns.db.threecard
    db.ante = db.ante or 25
    db.pp = db.pp or 0
    db.stats = db.stats or {}
    Fill(db.stats, DEFAULT_STATS)
    ns:InitSounds(db)

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.05, 0.25, 0.12, 0.94)

    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    -- the dealer's cards on top, yours below
    local dealerLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dealerLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
    dealerLabel:SetText("Dealer")
    local qual = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    qual:SetPoint("TOPLEFT", dealerLabel, "BOTTOMLEFT", 0, -2)
    qual:SetWidth(70); qual:SetJustifyH("LEFT")
    qual:SetText("Plays with Queen high")
    ui.dealerCards = CardRow(panel, -8)
    ui.dealerHand = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.dealerHand:SetPoint("TOP", panel, "TOP", 0, -98)

    local youLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    youLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -122)
    youLabel:SetText("You")
    ui.cards = CardRow(panel, -120)
    ui.myHand = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.myHand:SetPoint("TOP", panel, "TOP", 0, -210)

    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", panel, "TOP", 0, -232)
    ui.status:SetWidth(AREA_W - 8)

    local pays = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pays:SetPoint("BOTTOM", panel, "BOTTOM", 0, 78)
    pays:SetText("Pair Plus: Pair 1  Flush 4  Straight 6  Trips 30  Str. Flush 40")

    -- bets: Ante and Pair Plus
    local row = ns.CreateFrame("Frame", nil, panel)
    row:SetWidth(AREA_W - 8); row:SetHeight(24)
    row:SetPoint("BOTTOM", panel, "BOTTOM", 0, 48)
    ui.anteDown = MakeButton(row, "<", 24, function() Step(ANTES, "ante", -1) end)
    ui.anteDown:SetPoint("LEFT", row, "LEFT", 6, 0)
    ui.anteText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.anteText:SetPoint("LEFT", ui.anteDown, "RIGHT", 2, 0)
    ui.anteText:SetWidth(96)
    ui.anteUp = MakeButton(row, ">", 24, function() Step(ANTES, "ante", 1) end)
    ui.anteUp:SetPoint("LEFT", ui.anteText, "RIGHT", 2, 0)
    ui.ppUp = MakeButton(row, ">", 24, function() Step(PAIR_PLUS, "pp", 1) end)
    ui.ppUp:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    ui.ppText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.ppText:SetPoint("RIGHT", ui.ppUp, "LEFT", -2, 0)
    ui.ppText:SetWidth(116)
    ui.ppDown = MakeButton(row, "<", 24, function() Step(PAIR_PLUS, "pp", -1) end)
    ui.ppDown:SetPoint("RIGHT", ui.ppText, "LEFT", -2, 0)

    ui.deal = MakeButton(panel, "Deal", 180, function() Deal() end, 28)
    ui.deal:SetPoint("BOTTOM", panel, "BOTTOM", 0, 18)
    ui.play = MakeButton(panel, "Play", 130, function() Finish(true) end, 28)
    ui.play:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -6, 18)
    ui.fold = MakeButton(panel, "Fold", 130, function() Finish(false) end, 28)
    ui.fold:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 6, 18)

    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 3)

    ui.options = BuildOptions(panel)
    ui.sounds = ns:CreateSoundOptions(panel, "Three Card Poker Options", function() return db end)

    if db.hand then
        SetStatus("Welcome back - your hand is still dealt. Play or Fold?")
    else
        SetStatus("Set your Ante (and Pair Plus, if you like) and Deal.")
    end
    Refresh()
end

function TCP:OnShow()
    if ui.cards then Refresh() end
end

function TCP:OnHide()
    if ui.options then ui.options:Hide() end
    if ui.sounds then ui.sounds:Hide() end
end

-- A dealt hand waiting for Play or Fold (saved across reloads).
function TCP:ChipsInPlay()
    local d = ns.db.threecard
    return d ~= nil and d.hand ~= nil
end

-- Start over (Options) gives up a hand in progress.
function TCP:Abandon()
    if ns.db.threecard then ns.db.threecard.hand = nil end
    last = nil
    if ui.cards then Refresh() end
end

function TCP:ResetStats()
    local d = ns.db.threecard
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    if ui.stats and db then Refresh() end
end

-- Exposed for tests.
TCP.Evaluate, TCP.Qualifies, TCP.Compare, TCP.Settle, TCP.HandName, TCP.ui = Evaluate, Qualifies, Compare, Settle, HandName, ui
TCP.CAT = { HIGH = HIGH, PAIR = PAIR, FLUSH = FLUSH, STRAIGHT = STRAIGHT, TRIPS = TRIPS, SFLUSH = SFLUSH }
function TCP.SetDeck(fn) NewDeck = fn end

ns:RegisterGame(TCP)
