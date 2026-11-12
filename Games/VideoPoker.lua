-- CowCasino: Video Poker (Jacks or Better)
-- The classic 9/6 machine: bet one to five coins, get five cards, click the
-- ones to hold, then draw new cards for the rest. A pair of Jacks or better
-- pays. Five coins make a Royal Flush pay 800 per coin instead of 250.
-- With perfect play this machine returns about 99.5% of what's bet.
-- Cards come from one shuffled deck per hand. A hand that's been dealt but
-- not drawn is saved, so a reload or logout doesn't lose it.

local ns = CowCasino.ns

local AREA_W      = 352
local MAX_COINS   = 5
local COIN_SIZES  = { 1, 5, 10, 25, 50, 100, 250, 500 }
local CARD_W, CARD_H = 62, 86
local CARD_GAP    = 6

-- The pay table, per coin bet. royal5 is the Royal Flush on five coins.
local PAYS = {
    { key = "royal",    name = "Royal Flush",     pay = 250, royal5 = 800 },
    { key = "sflush",   name = "Straight Flush",  pay = 50 },
    { key = "quads",    name = "Four of a Kind",  pay = 25 },
    { key = "full",     name = "Full House",      pay = 9 },
    { key = "flush",    name = "Flush",           pay = 6 },
    { key = "straight", name = "Straight",        pay = 4 },
    { key = "trips",    name = "Three of a Kind", pay = 3 },
    { key = "twopair",  name = "Two Pair",        pay = 2 },
    { key = "jacks",    name = "Jacks or Better", pay = 1 },
}

local DEFAULT_STATS = { hands = 0, wins = 0, royals = 0, biggestWin = 0, wagered = 0, won = 0 }

local VideoPoker = {
    id = "videopoker",
    name = "Video Poker",
    description = "Jacks or Better: hold the cards you like and draw for the rest.",
    icon = "Interface\\AddOns\\CowCasino\\Art\\VideoPokerIcon",   -- painted (dev/art-src/make_game_icons.py)
}

local db
local ui = {}
local last          -- the last hand drawn, for the screen: { cards, row (PAYS index or nil), paid }

local function Fmt(n) return ns:FormatChips(n) end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

---------------------------------------------------------------------------
-- Hands
---------------------------------------------------------------------------
-- Which line of the pay table five cards make (an index into PAYS), or nil.
local function Classify(cards)
    local counts, suits = {}, {}
    local ranks = {}
    for _, c in ipairs(cards) do
        local r = (c.rank == 1) and 14 or c.rank
        counts[r] = (counts[r] or 0) + 1
        suits[c.suit] = true
        table.insert(ranks, r)
    end
    local nSuits = 0
    for _ in pairs(suits) do nSuits = nSuits + 1 end
    local flush = nSuits == 1
    table.sort(ranks)
    local distinct = 0
    for _ in pairs(counts) do distinct = distinct + 1 end
    local straight, royal = false, false
    if distinct == 5 then
        if ranks[5] - ranks[1] == 4 then straight = true end
        if ranks[1] == 2 and ranks[2] == 3 and ranks[3] == 4 and ranks[4] == 5 and ranks[5] == 14 then straight = true end
        royal = straight and ranks[1] == 10
    end
    if straight and flush then return royal and 1 or 2 end
    local four, three, npairs, highPair = false, false, 0, false
    for r, n in pairs(counts) do
        if n == 4 then four = true
        elseif n == 3 then three = true
        elseif n == 2 then
            npairs = npairs + 1
            if r >= 11 then highPair = true end
        end
    end
    if four then return 3 end
    if three and npairs == 1 then return 4 end
    if flush then return 5 end
    if straight then return 6 end
    if three then return 7 end
    if npairs == 2 then return 8 end
    if npairs == 1 and highPair then return 9 end
    return nil
end

-- What a line of the pay table pays, in chips, for this many coins of this size.
local function Payout(row, coins, coin)
    if not row then return 0 end
    local line = PAYS[row]
    local per = (coins == MAX_COINS and line.royal5) or line.pay
    return per * coins * coin
end

local function NewDeck()
    return ns:NewShoe(1)
end
local deck

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
    return string.format("Hands %d  Wins %d  Royals %d  Biggest win %s  Net %s|r",
        s.hands, s.wins, s.royals, Fmt(s.biggestWin), netText)
end

local function Refresh()
    if not ui.cards then return end
    ns:UpdateChipsDisplay()
    local h = db.hand
    local coins, coin = db.coins, db.coin

    -- the pay table: your coins' column lit, the winning line lit
    local winRow = (not h) and last and last.row or nil
    for i, line in ipairs(PAYS) do
        local row = ui.payRows[i]
        for c = 1, MAX_COINS do
            local per = (c == MAX_COINS and line.royal5) or line.pay
            local text = Fmt(per * c)
            if c == coins then text = "|cffffff00" .. text .. "|r" end
            row.cols[c]:SetText(text)
        end
        ns.SetShown(row.lit, winRow == i)
    end
    for c = 1, MAX_COINS do ns.SetShown(ui.colLit[c], c == coins) end

    -- the cards
    local cards = (h and h.cards) or (last and last.cards)
    for k = 1, 5 do
        local w = ui.cards[k]
        if cards and cards[k] then w:SetCard(cards[k], true) else w:SetCard({ rank = 1, suit = 1 }, false) end
        local held = h and h.held[k]
        ns.SetShown(ui.held[k], held and true or false)
        ui.holds[k]:EnableMouse(h ~= nil)
    end

    -- controls
    local bet = coins * coin
    ui.betInfo:SetText(string.format("Coin %s  x  %d  =  Bet %s   |cff999999(pays in coins)|r", Fmt(coin), coins, Fmt(bet)))
    for _, b in ipairs({ ui.betOne, ui.betMax, ui.coinDown, ui.coinUp }) do ns.SetEnabled(b, h == nil) end
    ns.SetEnabled(ui.coinDown, h == nil and coin > COIN_SIZES[1])
    ns.SetEnabled(ui.coinUp, h == nil and coin < COIN_SIZES[ns.getn(COIN_SIZES)])
    if h then
        ui.deal:SetText("Draw")
        ns.SetEnabled(ui.deal, true)
    else
        ui.deal:SetText("Deal " .. Fmt(bet))
        ns.SetEnabled(ui.deal, bet <= ns.db.chips)
    end
    ui.stats:SetText(StatsText())
end

---------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------
local function Deal()
    if db.hand then return end
    local bet = db.coins * db.coin
    if not ns:SpendChips(bet) then
        SetStatus(ns:LowChipsText(bet), 1, 0.35, 0.35)
        return
    end
    deck = NewDeck()
    local cards = {}
    for k = 1, 5 do cards[k] = deck:Draw() end
    db.hand = { coins = db.coins, coin = db.coin, cards = cards, held = {} }
    last = nil
    db.stats.hands = db.stats.hands + 1
    db.stats.wagered = db.stats.wagered + bet
    local row = Classify(cards)
    SetStatus(row and ("Dealt " .. PAYS[row].name .. ". Hold the cards you want, then Draw.")
        or "Click the cards you want to hold, then Draw.")
    ns:PlayGameSound(db, "newHand")
    Refresh()
end

local function Toggle(k)
    local h = db.hand
    if not h then return end
    if h.held[k] then h.held[k] = nil else h.held[k] = true end
    ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    Refresh()
end

local function DrawCards()
    local h = db.hand
    if not h then return end
    -- the deck after a reload: a fresh one without the cards in hand
    if not deck then
        deck = NewDeck()
        h.redeal = true
    end
    for k = 1, 5 do
        if not h.held[k] then
            local c = deck:Draw()
            if h.redeal then
                -- (skip cards that are already in the hand)
                local dup = true
                while dup do
                    dup = false
                    for j = 1, 5 do
                        if h.cards[j].rank == c.rank and h.cards[j].suit == c.suit then dup = true end
                    end
                    if dup then c = deck:Draw() end
                end
            end
            h.cards[k] = c
        end
    end
    db.hand = nil
    deck = nil
    local row = Classify(h.cards)
    local paid = Payout(row, h.coins, h.coin)
    local s = db.stats
    last = { cards = h.cards, row = row, paid = paid }
    if paid > 0 then
        ns:AddChips(paid)
        s.wins = s.wins + 1
        s.won = s.won + paid
        if paid > s.biggestWin then s.biggestWin = paid end
        if row == 1 then s.royals = s.royals + 1 end
        SetStatus(PAYS[row].name .. "! You win " .. Fmt(paid) .. ".", 0.25, 1, 0.25)
        ns:PlayGameSound(db, "win")
        if row <= 3 then ns:Sound("UI_EPICLOOT_TOAST") end
    else
        SetStatus("No win. Deal again?", 0.85, 0.85, 0.85)
        ns:PlayGameSound(db, "lose")
        local bet = db.coins * db.coin
        if bet > ns.db.chips then SetStatus(ns:LowChipsText(bet), 1, 0.35, 0.35) end
    end
    Refresh()
end

local function SetCoins(n)
    if db.hand then return end
    db.coins = math.max(1, math.min(MAX_COINS, n))
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

local function StepCoin(dir)
    if db.hand then return end
    local idx = 1
    for i, v in ipairs(COIN_SIZES) do if v == db.coin then idx = i end end
    idx = math.max(1, math.min(ns.getn(COIN_SIZES), idx + dir))
    db.coin = COIN_SIZES[idx]
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
    title:SetText("Video Poker Options")

    local rules = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rules:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -48)
    rules:SetWidth(AREA_W - 32)
    rules:SetJustifyH("LEFT")
    rules:SetText("How it plays: pick a coin size and bet one to five coins, then Deal. Click the cards you want "
        .. "to keep (they show HELD), then Draw to replace the rest. A pair of Jacks or better pays; the pay table "
        .. "shows what every hand pays for your coins. Bet five coins for the big Royal Flush: 800 per coin instead "
        .. "of 250.\n\nThis is the classic 9/6 Jacks or Better machine. Played perfectly it pays back about 99.5% "
        .. "of what's bet. Tips: hold any paying hand, hold four to a flush or straight flush, hold pairs (even "
        .. "low ones) over a single high card, and never hold a kicker with a pair.")

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

    function o:Refresh()
        if not (reset.armed and GetTime() - reset.armed <= 3) then
            reset.armed = nil
            reset:SetText("Reset stats")
        end
    end
    o:SetScript("OnShow", function() this:Refresh() end)
    return o
end

function VideoPoker:Build(panel)
    ns.db.videopoker = ns.db.videopoker or {}
    db = ns.db.videopoker
    db.coins = db.coins or MAX_COINS
    db.coin = db.coin or 5
    db.stats = db.stats or {}
    Fill(db.stats, DEFAULT_STATS)
    ns:InitSounds(db)

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.04, 0.06, 0.22, 0.94)

    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    -- The pay table: hand names, then a column per number of coins
    local TOP, ROW_H = -4, 13
    local NAME_W, COL_W = 112, 46
    local tableBg = panel:CreateTexture(nil, "BORDER")
    tableBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, TOP)
    tableBg:SetWidth(AREA_W - 8); tableBg:SetHeight(ns.getn(PAYS) * ROW_H + 6)
    tableBg:SetTexture(0, 0, 0, 0.45)
    ui.colLit = {}
    for c = 1, MAX_COINS do
        local lit = panel:CreateTexture(nil, "ARTWORK")
        lit:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + NAME_W + (c - 1) * COL_W, TOP)
        lit:SetWidth(COL_W); lit:SetHeight(ns.getn(PAYS) * ROW_H + 6)
        lit:SetTexture(0.75, 0.1, 0.1, 0.35)
        lit:Hide()
        ui.colLit[c] = lit
    end
    ui.payRows = {}
    for i, line in ipairs(PAYS) do
        local y = TOP - 3 - (i - 1) * ROW_H
        local row = { cols = {} }
        row.lit = panel:CreateTexture(nil, "ARTWORK")
        row.lit:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, y)
        row.lit:SetWidth(AREA_W - 8); row.lit:SetHeight(ROW_H)
        row.lit:SetTexture(1, 0.85, 0.1, 0.35)
        row.lit:Hide()
        row.name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y - 1)
        row.name:SetText(line.name)
        for c = 1, MAX_COINS do
            local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            t:SetPoint("TOPRIGHT", panel, "TOPLEFT", 8 + NAME_W + c * COL_W - 6, y - 1)
            t:SetJustifyH("RIGHT")
            row.cols[c] = t
        end
        ui.payRows[i] = row
    end

    -- The five cards, each with a HELD label; click a card to hold it
    ui.cards, ui.held, ui.holds = {}, {}, {}
    local x0 = (AREA_W - (5 * CARD_W + 4 * CARD_GAP)) / 2
    local cardTop = TOP - ns.getn(PAYS) * ROW_H - 16
    for k = 1, 5 do
        local k = k   -- own copy for closures (Lua 5.0)
        local x = x0 + (k - 1) * (CARD_W + CARD_GAP)
        local w = ns:CreateCardWidget(panel, CARD_W, CARD_H)
        w:SetPoint("TOPLEFT", panel, "TOPLEFT", x, cardTop)
        w:SetLevel(panel:GetFrameLevel() + 5)
        ui.cards[k] = w
        local hold = ns.CreateFrame("Button", nil, panel)
        hold:SetWidth(CARD_W); hold:SetHeight(CARD_H + 18)
        hold:SetPoint("TOPLEFT", panel, "TOPLEFT", x, cardTop)
        hold:SetFrameLevel(panel:GetFrameLevel() + 20)
        hold:SetScript("OnClick", function() Toggle(k) end)
        hold:EnableMouse(false)
        ui.holds[k] = hold
        local held = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        held:SetPoint("TOP", panel, "TOPLEFT", x + CARD_W / 2, cardTop - CARD_H - 3)
        held:SetText("HELD")
        held:SetTextColor(1, 0.85, 0.1)
        held:Hide()
        ui.held[k] = held
    end

    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", panel, "TOP", 0, cardTop - CARD_H - 24)
    ui.status:SetWidth(AREA_W - 8)

    -- Bet: coin size and number of coins
    ui.betInfo = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.betInfo:SetPoint("BOTTOM", panel, "BOTTOM", 0, 82)
    local row = ns.CreateFrame("Frame", nil, panel)
    row:SetWidth(AREA_W - 8); row:SetHeight(24)
    row:SetPoint("BOTTOM", panel, "BOTTOM", 0, 52)
    local coinLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    coinLabel:SetPoint("LEFT", row, "LEFT", 0, 0)
    coinLabel:SetText("Coin")
    ui.coinDown = MakeButton(row, "<", 24, function() StepCoin(-1) end)
    ui.coinDown:SetPoint("LEFT", coinLabel, "RIGHT", 4, 0)
    ui.coinUp = MakeButton(row, ">", 24, function() StepCoin(1) end)
    ui.coinUp:SetPoint("LEFT", ui.coinDown, "RIGHT", 2, 0)
    ui.betOne = MakeButton(row, "Bet One", 80, function()
        SetCoins(db.coins >= MAX_COINS and 1 or db.coins + 1)
    end)
    ui.betOne:SetPoint("LEFT", ui.coinUp, "RIGHT", 10, 0)
    ui.betMax = MakeButton(row, "Bet Max", 80, function() SetCoins(MAX_COINS) end)
    ui.betMax:SetPoint("LEFT", ui.betOne, "RIGHT", 4, 0)

    -- Deal / Draw
    ui.deal = MakeButton(panel, "Deal", 200, function()
        if db.hand then DrawCards() else Deal() end
    end, 28)
    ui.deal:SetPoint("BOTTOM", panel, "BOTTOM", 0, 20)

    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 5)

    ui.options = BuildOptions(panel)
    ui.sounds = ns:CreateSoundOptions(panel, "Video Poker Options", function() return db end)

    if db.hand then
        SetStatus("Welcome back - your hand is still dealt. Hold and Draw.")
    else
        SetStatus("Pick your bet and press Deal.")
    end
    Refresh()
end

function VideoPoker:OnShow()
    if ui.cards then Refresh() end
end

function VideoPoker:OnHide()
    if ui.options then ui.options:Hide() end
    if ui.sounds then ui.sounds:Hide() end
end

-- For the out-of-chips check: a dealt hand waiting for its draw (saved across reloads).
function VideoPoker:ChipsInPlay()
    local d = ns.db.videopoker
    return d ~= nil and d.hand ~= nil
end

-- Start over (Options) gives up a hand in progress.
function VideoPoker:Abandon()
    if ns.db.videopoker then ns.db.videopoker.hand = nil end
    deck, last = nil, nil
    if ui.cards then Refresh() end
end

function VideoPoker:ResetStats()
    local d = ns.db.videopoker
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    if ui.stats and db then Refresh() end
end

-- Exposed for tests.
VideoPoker.Classify, VideoPoker.Payout, VideoPoker.PAYS, VideoPoker.ui = Classify, Payout, PAYS, ui
function VideoPoker.SetDeck(fn) NewDeck = fn end

ns:RegisterGame(VideoPoker)
