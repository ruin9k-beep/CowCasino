-- CowCasino: Hi-Lo
-- Bet, and a card is dealt. Guess whether the next card is higher or the
-- same, or lower or the same (on an ace: higher, or the same ace; on a king:
-- lower, or the same king). Every right guess multiplies your winnings by
-- the fair odds less a 1% house edge; cash out whenever you like after one.
-- A wrong guess loses the bet. Skip swaps the card for a new one, free.
-- Aces are low, kings high; suits don't matter. Every card comes from a
-- fresh shuffled deck, so each draw is 1 in 13 for any rank.
-- An unfinished game is saved, so a reload or logout doesn't lose it.

local ns = CowCasino.ns

local AREA_W      = 352
local MIN_BET, MAX_BET = 5, 1000
local CHIP_VALUES = { 5, 25, 100, 500 }
local HOUSE_EDGE  = 0.01
local MAX_MULT    = 10000       -- a game cashes itself out here
local HISTORY     = 9           -- small cards shown along the trail
local BIG_W, BIG_H = 92, 128
local SMALL_W, SMALL_H = 30, 42

local DEFAULT_STATS = { games = 0, cashouts = 0, busts = 0, guesses = 0, bestMultiplier = 0, biggestWin = 0, net = 0 }

local HiLo = {
    id = "hilo",
    name = "Hi-Lo",
    description = "Higher or lower? Each right guess multiplies the win. Cash out any time.",
    icon = "Interface\\AddOns\\CowCasino\\Art\\HiLoIcon",   -- painted (dev/art-src/make_game_icons.py)
}

local db
local ui = {}
local last          -- how the last game ended, for the screen: { bust = true } or { cashed = chips }

local function Fmt(n) return ns:FormatChips(n) end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function FmtMult(m)
    if m >= 1000 then return Fmt(math.floor(m)) .. "x" end
    return string.format("%.2fx", m)
end

-- Whole chips: half a chip or more rounds up.
local function Pay(bet, mult) return math.floor(bet * math.min(mult, MAX_MULT) + 0.5) end

---------------------------------------------------------------------------
-- The two guesses for a card: { key, label, chance, wins(rank) }
---------------------------------------------------------------------------
local function Choices(rank)
    if rank == 1 then
        return { key = "hi", label = "Higher", chance = 12 / 13, wins = function(r) return r > 1 end },
               { key = "lo", label = "Same (ace)", chance = 1 / 13, wins = function(r) return r == 1 end }
    elseif rank == 13 then
        return { key = "hi", label = "Same (king)", chance = 1 / 13, wins = function(r) return r == 13 end },
               { key = "lo", label = "Lower", chance = 12 / 13, wins = function(r) return r < 13 end }
    end
    return { key = "hi", label = "Higher or same", chance = (14 - rank) / 13, wins = function(r) return r >= rank end },
           { key = "lo", label = "Lower or same", chance = rank / 13, wins = function(r) return r <= rank end }
end

local function StepMult(chance) return (1 - HOUSE_EDGE) / chance end

local function Draw()
    return { rank = math.random(1, 13), suit = math.random(1, 4) }
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function SetStatus(text, r, g, b)
    ui.status:SetText(text or "")
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function StatsText()
    local s = db.stats
    local net = s.net
    local netText = (net > 0 and ("|cff40ff40+" .. Fmt(net))) or (net < 0 and ("|cffff5050-" .. Fmt(-net))) or "|cffcccccc0"
    return string.format("Games %d  Cashed %d  Best %s  Biggest win %s  Net %s|r", s.games, s.cashouts,
        FmtMult(s.bestMultiplier), Fmt(s.biggestWin), netText)
end

local function Refresh()
    if not ui.big then return end
    ns:UpdateChipsDisplay()
    local g = db.active

    -- the card in play (or the last one, face up, or a back)
    local card = (g and g.card) or (last and last.card)
    if card then ui.big:SetCard(card, true) else ui.big:SetCard({ rank = 1, suit = 1 }, false) end
    ns.SetShown(ui.bust, last ~= nil and last.bust == true and not g)

    -- the trail of cards so far, oldest on the left
    local trail = (g and g.history) or (last and last.history) or {}
    local n = ns.getn(trail)
    local first = math.max(1, n - HISTORY + 1)
    for k = 1, HISTORY do
        local slot = ui.trail[k]
        local h = trail[first + k - 1]
        if h then
            slot.card:SetCard(h.card, true)
            slot.text:SetText(h.mult and ("|cff40ff40" .. FmtMult(h.mult) .. "|r") or (h.skip and "|cff999999skip|r")
                or (h.bust and "|cffff5050bust|r") or "|cffccccccstart|r")
        else
            slot.card:Clear()
            slot.text:SetText("")
        end
    end

    -- the guesses
    local rank = g and g.card.rank or (card and card.rank) or 7
    local hi, lo = Choices(rank)
    for _, pair in ipairs({ { ui.hi, hi }, { ui.lo, lo } }) do
        local b, c = pair[1], pair[2]
        b.label:SetText(c.label)
        b.mult:SetText(FmtMult(StepMult(c.chance)))
        b.chance:SetText(string.format("%.0f%% chance", c.chance * 100))
        ns.SetEnabled(b, g ~= nil)
        b:SetAlpha(g and 1 or 0.6)
    end
    ns.SetEnabled(ui.skip, g ~= nil)

    if g then
        local pay = Pay(g.bet, g.mult)
        ui.info:SetText(string.format("Bet %s   Multiplier |cffffd100%s|r   Cash out |cff40ff40%s|r", Fmt(g.bet), FmtMult(g.mult), Fmt(pay)))
        ui.main:SetText(g.mult > 1 and ("Cash out " .. Fmt(pay)) or "Guess first")
        ns.SetEnabled(ui.main, g.mult > 1)
    else
        ui.info:SetText("Higher or lower? Place a bet to deal.")
        ui.main:SetText("Bet " .. Fmt(db.bet))
        ns.SetEnabled(ui.main, db.bet >= MIN_BET and db.bet <= ns.db.chips)
    end
    for _, b in ipairs(ui.chipButtons) do ns.SetEnabled(b, g == nil) end
    ns.SetEnabled(ui.clear, g == nil and db.bet > 0)
    ui.stats:SetText(StatsText())
end

---------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------
local function AddBet(amount)
    if db.active then return end
    db.bet = math.max(0, math.min(MAX_BET, db.bet + amount, math.max(0, ns.db.chips)))
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

local function Start()
    if db.active or db.bet < MIN_BET then return end
    if not ns:SpendChips(db.bet) then
        SetStatus("Not enough chips.", 1, 0.35, 0.35)
        return
    end
    local card = Draw()
    db.active = { bet = db.bet, card = card, mult = 1, history = { { card = card } } }
    last = nil
    db.stats.games = db.stats.games + 1
    SetStatus("Higher or lower?")
    ns:PlayGameSound(db, "newHand")
    Refresh()
end

local function CashOut(auto)
    local g = db.active
    if not g or g.mult <= 1 then return end
    local pay = Pay(g.bet, g.mult)
    db.active = nil
    ns:AddChips(pay)
    local s = db.stats
    s.cashouts = s.cashouts + 1
    s.net = s.net + pay - g.bet
    if g.mult > s.bestMultiplier then s.bestMultiplier = g.mult end
    if pay - g.bet > s.biggestWin then s.biggestWin = pay - g.bet end
    last = { card = g.card, history = g.history, cashed = pay }
    SetStatus((auto and ("The multiplier hit its top, " .. FmtMult(MAX_MULT) .. ": cashed out for ") or "Cashed out: ")
        .. Fmt(pay) .. " (+" .. Fmt(pay - g.bet) .. ").", 0.25, 1, 0.25)
    ns:PlayGameSound(db, "win")
    Refresh()
end

local function Guess(key)
    local g = db.active
    if not g then return end
    local hi, lo = Choices(g.card.rank)
    local c = (key == "hi") and hi or lo
    local nextCard = Draw()
    db.stats.guesses = db.stats.guesses + 1
    if c.wins(nextCard.rank) then
        g.mult = g.mult * StepMult(c.chance)
        g.card = nextCard
        table.insert(g.history, { card = nextCard, mult = g.mult })
        if ns.getn(g.history) > 60 then table.remove(g.history, 1) end
        ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if g.mult >= MAX_MULT then
            CashOut(true)
            return
        end
        SetStatus(string.format("%s - right! %s. Cash out for %s, or keep going.", ns.RANKS[nextCard.rank].name,
            FmtMult(g.mult), Fmt(Pay(g.bet, g.mult))), 0.25, 1, 0.25)
    else
        db.active = nil
        table.insert(g.history, { card = nextCard, bust = true })
        local s = db.stats
        s.busts = s.busts + 1
        s.net = s.net - g.bet
        last = { card = nextCard, history = g.history, bust = true }
        SetStatus(ns.RANKS[nextCard.rank].name .. " - wrong guess. You lose " .. Fmt(g.bet) .. ".", 1, 0.35, 0.35)
        ns:PlayGameSound(db, "lose")
        if ns.db.chips < MIN_BET then SetStatus(ns:LowChipsText(MIN_BET), 1, 0.35, 0.35) end
        if db.bet > ns.db.chips then db.bet = math.floor(ns.db.chips / MIN_BET) * MIN_BET end
    end
    Refresh()
end

local function Skip()
    local g = db.active
    if not g then return end
    local card = Draw()
    g.card = card
    table.insert(g.history, { card = card, skip = true })
    if ns.getn(g.history) > 60 then table.remove(g.history, 1) end
    ns:Sound("IG_MAINMENU_OPTION")
    SetStatus("Skipped to a " .. ns.RANKS[card.rank].name .. ".")
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

-- A guess button: what it is, what it pays and the chance, on three lines.
local function GuessButton(parent, key)
    local b = ns.CreateFrame("Button", nil, parent)
    b:SetWidth(112); b:SetHeight(58)
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(b)
    edge:SetTexture(0.85, 0.7, 0.3, 0.9)
    local fill = b:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    if key == "hi" then fill:SetTexture(0.08, 0.30, 0.14, 1) else fill:SetTexture(0.32, 0.08, 0.08, 1) end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetTexture(1, 1, 1, 0.12)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("TOP", b, "TOP", 0, -6)
    b.mult = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    b.mult:SetPoint("CENTER", b, "CENTER", 0, -2)
    b.chance = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.chance:SetPoint("BOTTOM", b, "BOTTOM", 0, 5)
    b:SetScript("OnClick", function() Guess(key) end)
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
    title:SetText("Hi-Lo Options")

    local rules = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rules:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -48)
    rules:SetWidth(AREA_W - 32)
    rules:SetJustifyH("LEFT")
    rules:SetText("How it plays: bet, and a card is dealt. Guess whether the next card is higher or the same, "
        .. "or lower or the same. Aces are low and kings high; suits don't matter. Each guess pays its fair odds "
        .. "less 1%, so the less likely guess pays more, and the multipliers stack from guess to guess. "
        .. "Cash out any time after a right guess; a wrong one loses the bet. Skip swaps the card for free.")

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

function HiLo:Build(panel)
    ns.db.hilo = ns.db.hilo or {}
    db = ns.db.hilo
    if db.bet == nil then db.bet = 25 end
    db.stats = db.stats or {}
    Fill(db.stats, DEFAULT_STATS)
    ns:InitSounds(db)

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.06, 0.20, 0.26, 0.92)

    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    ui.info = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.info:SetPoint("TOP", panel, "TOP", 0, -6)

    -- the card in play, with a guess on each side
    ui.big = ns:CreateCardWidget(panel, BIG_W, BIG_H)
    ui.big:SetPoint("TOP", panel, "TOP", 0, -26)
    ui.big:SetLevel(panel:GetFrameLevel() + 5)
    ui.bust = panel:CreateTexture(nil, "OVERLAY")
    ui.bust:SetPoint("TOPLEFT", ui.big, "TOPLEFT", 0, 0)
    ui.bust:SetPoint("BOTTOMRIGHT", ui.big, "BOTTOMRIGHT", 0, 0)
    ui.bust:SetTexture(0.8, 0.05, 0.05, 0.35)
    ui.bust:Hide()
    ui.hi = GuessButton(panel, "hi")
    ui.hi:SetPoint("RIGHT", ui.big, "LEFT", -12, 0)
    ui.lo = GuessButton(panel, "lo")
    ui.lo:SetPoint("LEFT", ui.big, "RIGHT", 12, 0)

    -- the trail of cards
    ui.trail = {}
    local step = SMALL_W + 7
    local x0 = (AREA_W - (HISTORY * step - 7)) / 2
    for k = 1, HISTORY do
        local slot = {}
        slot.card = ns:CreateCardWidget(panel, SMALL_W, SMALL_H)
        slot.card:SetPoint("TOPLEFT", panel, "TOPLEFT", x0 + (k - 1) * step, -164)
        slot.card:SetLevel(panel:GetFrameLevel() + 5)
        slot.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slot.text:SetPoint("TOP", slot.card, "BOTTOM", 0, -2)
        ui.trail[k] = slot
    end

    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", panel, "TOP", 0, -232)
    ui.status:SetWidth(AREA_W - 8)

    -- Row 1: bet chips, and skip
    local row1 = ns.CreateFrame("Frame", nil, panel)
    row1:SetWidth(AREA_W - 8); row1:SetHeight(24)
    row1:SetPoint("BOTTOM", panel, "BOTTOM", 0, 54)
    ui.chipButtons = {}
    local x = 0
    for i, v in ipairs(CHIP_VALUES) do
        local v = v   -- own copy for closures (Lua 5.0)
        local b = MakeButton(row1, tostring(v), 38, function(_, button)
            AddBet(button == "RightButton" and -v or v)
        end)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetPoint("LEFT", row1, "LEFT", x, 0)
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText("Chip " .. v)
            GameTooltip:AddLine("Left-click to add, right-click to take back.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ui.chipButtons[i] = b
        x = x + 41
    end
    ui.clear = MakeButton(row1, "Clear", 46, function() db.bet = 0; Refresh() end)
    ui.clear:SetPoint("LEFT", row1, "LEFT", x, 0)
    ui.skip = MakeButton(row1, "Skip card", 90, Skip)
    ui.skip:SetPoint("RIGHT", row1, "RIGHT", 0, 0)
    ui.skip:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("Skip card")
        GameTooltip:AddLine("Swap this card for a new one. Free, and the multiplier stays.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ui.skip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Row 2: bet / cash out
    ui.main = MakeButton(panel, "Bet", 200, function()
        if db.active then CashOut(false) else Start() end
    end, 28)
    ui.main:SetPoint("BOTTOM", panel, "BOTTOM", 0, 20)

    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 5)

    ui.options = BuildOptions(panel)
    ui.sounds = ns:CreateSoundOptions(panel, "Hi-Lo Options", function() return db end)

    if db.active then
        SetStatus("Welcome back - your game is still going.")
    else
        SetStatus("Set your bet and press Bet to deal a card.")
    end
    Refresh()
end

function HiLo:OnShow()
    if db and not db.active and (db.bet < MIN_BET or db.bet > ns.db.chips) then
        db.bet = math.min(25, math.floor(ns.db.chips / MIN_BET) * MIN_BET)
    end
    if ui.big then Refresh() end
end

function HiLo:OnHide()
    if ui.options then ui.options:Hide() end
    if ui.sounds then ui.sounds:Hide() end
end

-- For the out-of-chips check: a game in progress (saved across reloads).
function HiLo:ChipsInPlay()
    local d = ns.db.hilo
    return d ~= nil and d.active ~= nil
end

-- Start over (Options) gives up a game in progress.
function HiLo:Abandon()
    if ns.db.hilo then ns.db.hilo.active = nil end
    last = nil
    if ui.big then Refresh() end
end

function HiLo:ResetStats()
    local d = ns.db.hilo
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    if ui.stats and db then Refresh() end
end

-- Exposed for tests.
HiLo.Choices, HiLo.StepMult, HiLo.Pay, HiLo.ui = Choices, StepMult, Pay, ui
function HiLo.SetDraw(fn) Draw = fn end

ns:RegisterGame(HiLo)
