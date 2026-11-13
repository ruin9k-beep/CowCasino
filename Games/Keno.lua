-- CowCasino: Keno
-- Pick 1 to 10 numbers from 1 to 80 and bet. Twenty numbers are drawn, one
-- at a time; the more of yours come up, the more it pays. The pay table for
-- the number of spots you picked is under the board (each one returns about
-- 91% to 96% of what's bet over time). Ten spots also pay for catching none.
-- Your picks stay for the next game, so Play again repeats them; Quick pick
-- chooses for you and Auto plays several games in a row.

local ns = CowCasino.ns

local AREA_W     = 352
local NUMBERS    = 80
local DRAWN      = 20
local MAX_SPOTS  = 10
local COLS       = 10
local CELL_W, CELL_H, CELL_GAP = 32, 20, 2
local BETS       = { 1, 5, 10, 25, 50, 100, 250, 500, 1000 }
local DRAW_STEP  = 0.12      -- seconds between drawn numbers
local AUTO_COUNTS = { 5, 10, 25 }
local AUTO_PAUSE = 1.2       -- between auto games

-- PAYS[spots][hits] = how many times the bet comes back
local PAYS = {
    { [1] = 3.7 },
    { [2] = 15.5 },
    { [2] = 2, [3] = 47 },
    { [2] = 1, [3] = 6, [4] = 150 },
    { [3] = 3, [4] = 15, [5] = 800 },
    { [3] = 2, [4] = 6, [5] = 95, [6] = 1600 },
    { [3] = 1, [4] = 4, [5] = 23, [6] = 280, [7] = 5000 },
    { [4] = 2, [5] = 12, [6] = 95, [7] = 1500, [8] = 15000 },
    { [4] = 1, [5] = 6, [6] = 45, [7] = 350, [8] = 4000, [9] = 25000 },
    { [0] = 5, [5] = 2, [6] = 20, [7] = 140, [8] = 1000, [9] = 5000, [10] = 30000 },
}

local DEFAULT_STATS = { games = 0, wins = 0, bestHits = 0, biggestWin = 0, wagered = 0, won = 0 }

local Keno = {
    id = "keno",
    name = "Keno",
    description = "Pick up to ten numbers; twenty are drawn. The more you catch, the more it pays.",
    icon = "Interface\\AddOns\\CowCasino\\Art\\KenoIcon",   -- painted (dev/art-src/make_game_icons.py)
}

local db
local ui = {}
local S = {
    drawing = false,    -- the numbers are coming out
    shown = 0,          -- how many of this game's drawn numbers are on the board
    autoLeft = 0,
    t = 0,
}

local function Fmt(n) return ns:FormatChips(n) end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function FmtMult(m)
    if m == math.floor(m) then return Fmt(m) end
    return string.format("%.1f", m)
end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
local function Spots()
    local n = 0
    for _ in pairs(db.picks) do n = n + 1 end
    return n
end

-- What a game pays (stake included) for this many picks and hits.
local function Payout(spots, hits, bet)
    local row = PAYS[spots]
    local m = row and row[hits]
    if not m then return 0 end
    return math.floor(bet * m)
end

-- Twenty different numbers from 1 to 80, in the order they come out.
local function DrawNumbers()
    local pool = {}
    for i = 1, NUMBERS do pool[i] = i end
    local out = {}
    for i = 1, DRAWN do
        local j = math.random(i, NUMBERS)
        pool[i], pool[j] = pool[j], pool[i]
        out[i] = pool[i]
    end
    return out
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
    local net = s.won - s.wagered
    local netText = (net > 0 and ("|cff40ff40+" .. Fmt(net))) or (net < 0 and ("|cffff5050-" .. Fmt(-net))) or "|cffcccccc0"
    return string.format("Games %d  Wins %d  Best catch %d  Biggest win %s  Net %s|r",
        s.games, s.wins, s.bestHits, Fmt(s.biggestWin), netText)
end

-- Which numbers are drawn so far in the game on screen.
local function DrawnSet()
    local set = {}
    local g = db.game or db.last
    if g then
        local n = db.game and S.shown or DRAWN
        for i = 1, math.min(n, DRAWN) do set[g.drawn[i]] = true end
    end
    return set
end

local function Hits()
    local g = db.game or db.last
    if not g then return 0 end
    local set = DrawnSet()
    local n = 0
    for num in pairs(g.picks) do if set[num] then n = n + 1 end end
    return n
end

local function RefreshPays()
    local spots = (db.game and db.game.spots) or Spots()
    local row = PAYS[spots]
    local hitsText, paysText = { "|cffffd100Catch|r" }, { "|cffffd100Pays|r" }
    if row then
        for h = 0, spots do
            if row[h] then
                table.insert(hitsText, tostring(h))
                table.insert(paysText, FmtMult(row[h]) .. "x")
            end
        end
        ui.payTitle:SetText(spots .. (spots == 1 and " spot" or " spots") .. " picked")
    else
        ui.payTitle:SetText("Pick 1 to 10 numbers")
    end
    for i = 1, 8 do
        ui.payHits[i]:SetText(hitsText[i] or "")
        ui.payMults[i]:SetText(paysText[i] or "")
    end
end

local function Refresh()
    if not ui.cells then return end
    ns:UpdateChipsDisplay()
    local drawn = DrawnSet()
    local picks = (db.game and db.game.picks) or db.picks
    for n = 1, NUMBERS do
        local c = ui.cells[n]
        local picked, out = picks[n], drawn[n]
        if picked and out then c.bg:SetTexture(0.95, 0.75, 0.1, 0.95)        -- a catch
        elseif picked then c.bg:SetTexture(0.15, 0.45, 0.9, 0.9)
        elseif out then c.bg:SetTexture(0.55, 0.12, 0.12, 0.9)
        else c.bg:SetTexture(0.1, 0.1, 0.12, 0.85) end
        if picked and out then c.text:SetTextColor(0.1, 0.05, 0) else c.text:SetTextColor(1, 1, 1) end
    end
    RefreshPays()

    local busy = db.game ~= nil or S.autoLeft > 0
    local bi = 1
    for i, v in ipairs(BETS) do if v == db.bet then bi = i end end
    ns.SetEnabled(ui.betDown, not busy and bi > 1)
    ns.SetEnabled(ui.betUp, not busy and bi < ns.getn(BETS))
    ui.betText:SetText("Bet |cffffffff" .. Fmt(db.bet) .. "|r")
    ns.SetEnabled(ui.quick, not busy)
    ns.SetEnabled(ui.clear, not busy and Spots() > 0)
    local spots = Spots()
    ui.play:SetText("Play")
    ns.SetEnabled(ui.play, not busy and spots > 0 and ns.db.chips >= db.bet)
    if S.autoLeft > 0 then
        ui.auto:SetText("Stop (" .. S.autoLeft .. ")")
        ns.SetEnabled(ui.auto, true)
    else
        ui.auto:SetText("Auto " .. db.autoCount)
        ns.SetEnabled(ui.auto, not busy and spots > 0 and ns.db.chips >= db.bet)
    end
    if db.game then
        ui.catch:SetText("Drawn " .. S.shown .. " of " .. DRAWN .. "   Caught " .. Hits())
    elseif db.last then
        ui.catch:SetText("Caught " .. Hits() .. " of " .. db.last.spots)
    else
        ui.catch:SetText("")
    end
    ui.stats:SetText(StatsText())
end

---------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------
local function Finish()
    local g = db.game
    if not g then return end
    S.drawing = false
    S.shown = DRAWN
    local set = {}
    for i = 1, DRAWN do set[g.drawn[i]] = true end
    local hits = 0
    for num in pairs(g.picks) do if set[num] then hits = hits + 1 end end
    local paid = Payout(g.spots, hits, g.bet)
    local s = db.stats
    if hits > s.bestHits then s.bestHits = hits end
    db.last = g
    db.game = nil
    if paid > 0 then
        ns:AddChips(paid)
        s.won = s.won + paid
        if paid > g.bet then s.wins = s.wins + 1 end
        if paid - g.bet > s.biggestWin then s.biggestWin = paid - g.bet end
        local m = PAYS[g.spots][hits]
        SetStatus(string.format("Caught %d of %d! Pays %sx: %s.", hits, g.spots, FmtMult(m), Fmt(paid)), 0.25, 1, 0.25)
        ns:PlayGameSound(db, "win")
        if m >= 100 then ns:Sound("UI_EPICLOOT_TOAST") end
    else
        SetStatus(string.format("Caught %d of %d. No win this time.", hits, g.spots), 0.85, 0.85, 0.85)
        ns:PlayGameSound(db, "lose")
    end
    if S.autoLeft > 0 then
        S.autoLeft = S.autoLeft - 1
        if S.autoLeft > 0 and ns.db.chips < db.bet then
            S.autoLeft = 0
            SetStatus("Auto stopped: not enough chips for the bet.", 1, 0.35, 0.35)
        end
        if S.autoLeft > 0 then S.wait = AUTO_PAUSE end
    end
    if S.autoLeft <= 0 and ns.db.chips < BETS[1] then
        SetStatus(ns:LowChipsText(BETS[1]), 1, 0.35, 0.35)
    end
    while db.bet > BETS[1] and db.bet > ns.db.chips do
        local i = 1
        for k, v in ipairs(BETS) do if v == db.bet then i = k end end
        db.bet = BETS[i - 1]
    end
    Refresh()
end

local function Play(quiet)
    if db.game then return end
    local spots = Spots()
    if spots < 1 then
        SetStatus("Pick some numbers first (1 to 10).")
        return
    end
    if not ns:SpendChips(db.bet) then
        S.autoLeft = 0
        SetStatus(ns:LowChipsText(db.bet), 1, 0.35, 0.35)
        Refresh()
        return
    end
    local picks = {}
    for n in pairs(db.picks) do picks[n] = true end
    db.game = { bet = db.bet, spots = spots, picks = picks, drawn = DrawNumbers() }
    db.stats.games = db.stats.games + 1
    db.stats.wagered = db.stats.wagered + db.bet
    S.drawing, S.shown, S.t = true, 0, 0
    SetStatus("Drawing...")
    if not quiet then ns:PlayGameSound(db, "newHand") end
    Refresh()
end

local function TogglePick(n)
    if db.game or S.autoLeft > 0 then return end
    if db.picks[n] then
        db.picks[n] = nil
    elseif Spots() >= MAX_SPOTS then
        SetStatus("Ten numbers at most. Click one of yours to swap it.")
        return
    else
        db.picks[n] = true
    end
    db.last = nil
    ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    local spots = Spots()
    SetStatus(spots > 0 and (spots .. (spots == 1 and " number" or " numbers") .. " picked. Play when ready.")
        or "Pick 1 to 10 numbers, then Play.")
    Refresh()
end

local function QuickPick()
    if db.game or S.autoLeft > 0 then return end
    local n = Spots()
    if n == 0 then n = db.quickSpots or 6 end
    db.picks = {}
    local pool = {}
    for i = 1, NUMBERS do pool[i] = i end
    for i = 1, n do
        local j = math.random(i, NUMBERS)
        pool[i], pool[j] = pool[j], pool[i]
        db.picks[pool[i]] = true
    end
    db.last = nil
    ns:Sound("IG_MAINMENU_OPTION")
    SetStatus("Quick pick: " .. n .. " numbers. Play when ready.")
    Refresh()
end

local function Clear()
    if db.game or S.autoLeft > 0 then return end
    db.picks = {}
    db.last = nil
    ns:Sound("IG_MAINMENU_OPTION")
    SetStatus("Pick 1 to 10 numbers, then Play.")
    Refresh()
end

local function ToggleAuto()
    if S.autoLeft > 0 then
        S.autoLeft = 0
        S.wait = nil
        SetStatus("Auto stopped.")
        Refresh()
        return
    end
    if db.game or Spots() == 0 then return end
    S.autoLeft = db.autoCount
    Play()
end

local function StepBet(dir)
    if db.game or S.autoLeft > 0 then return end
    local idx = 1
    for i, v in ipairs(BETS) do if v == db.bet then idx = i end end
    idx = math.max(1, math.min(ns.getn(BETS), idx + dir))
    db.bet = BETS[idx]
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

-- The draw, one number at a time; Auto's next game after a pause.
local ticker = ns.CreateFrame("Frame")
ticker:SetScript("OnUpdate", function()
    if not db then return end
    local dt = arg1 or 0
    if S.drawing and db.game then
        S.t = S.t + dt
        local changed = false
        while S.t >= DRAW_STEP and S.shown < DRAWN do
            S.t = S.t - DRAW_STEP
            S.shown = S.shown + 1
            changed = true
            if db.game.picks[db.game.drawn[S.shown]] and ns.currentGame == "keno" then
                ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            end
        end
        if S.shown >= DRAWN then Finish() elseif changed then Refresh() end
    elseif S.wait then
        S.wait = S.wait - dt
        if S.wait <= 0 then
            S.wait = nil
            if S.autoLeft > 0 then Play(true) end
        end
    end
end)

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
    title:SetText("Keno Options")

    local rules = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rules:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -40)
    rules:SetWidth(AREA_W - 32)
    rules:SetJustifyH("LEFT")
    rules:SetText("How it plays: click 1 to 10 numbers on the board (or Quick pick), set your bet and Play. "
        .. "Twenty of the eighty numbers are drawn. Gold squares are your catches. The table under the board "
        .. "shows what each catch pays for the number of spots you picked, as times your bet. Ten spots pay "
        .. "5x for catching none at all.\n\nYour numbers stay picked, so Play again repeats them. Auto plays "
        .. "several games in a row and stops if you run short of chips.")

    local autoLabel = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -170)
    autoLabel:SetText("Auto games")
    local autoBtns = {}
    for i, n in ipairs(AUTO_COUNTS) do
        local n = n
        local b = MakeButton(o, tostring(n), 44, function()
            db.autoCount = n
            ns:Sound("IG_MAINMENU_OPTION")
            o:Refresh()
            Refresh()
        end)
        b:SetPoint("LEFT", autoLabel, "RIGHT", 10 + (i - 1) * 48, 0)
        autoBtns[i] = b
    end
    local quickLabel = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    quickLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -200)
    quickLabel:SetText("Quick pick, with nothing picked:")
    local qDown = MakeButton(o, "<", 24, function()
        db.quickSpots = math.max(1, db.quickSpots - 1); o:Refresh()
    end)
    qDown:SetPoint("LEFT", quickLabel, "RIGHT", 8, 0)
    local qText = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qText:SetPoint("LEFT", qDown, "RIGHT", 4, 0)
    qText:SetWidth(24)
    local qUp = MakeButton(o, ">", 24, function()
        db.quickSpots = math.min(MAX_SPOTS, db.quickSpots + 1); o:Refresh()
    end)
    qUp:SetPoint("LEFT", qText, "RIGHT", 4, 0)

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
        for i, n in ipairs(AUTO_COUNTS) do
            autoBtns[i]:SetText(n == db.autoCount and ("|cffffff00" .. n .. "|r") or tostring(n))
        end
        qText:SetText(tostring(db.quickSpots))
        ns.SetEnabled(qDown, db.quickSpots > 1)
        ns.SetEnabled(qUp, db.quickSpots < MAX_SPOTS)
        if not (reset.armed and GetTime() - reset.armed <= 3) then
            reset.armed = nil
            reset:SetText("Reset stats")
        end
    end
    o:SetScript("OnShow", function() this:Refresh() end)
    return o
end

function Keno:Build(panel)
    ns.db.keno = ns.db.keno or {}
    db = ns.db.keno
    db.bet = db.bet or 10
    db.picks = db.picks or {}
    db.autoCount = db.autoCount or 10
    db.quickSpots = db.quickSpots or 6
    db.stats = db.stats or {}
    Fill(db.stats, DEFAULT_STATS)
    ns:InitSounds(db)

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.12, 0.08, 0.2, 0.94)

    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    -- The board: 80 numbers, ten to a row
    ui.cells = {}
    local x0 = (AREA_W - (COLS * CELL_W + (COLS - 1) * CELL_GAP)) / 2
    for n = 1, NUMBERS do
        local n = n   -- own copy for the closure (Lua 5.0)
        local col = ns.Mod(n - 1, COLS)
        local row = math.floor((n - 1) / COLS)
        local c = ns.CreateFrame("Button", nil, panel)
        c:SetWidth(CELL_W); c:SetHeight(CELL_H)
        c:SetPoint("TOPLEFT", panel, "TOPLEFT", x0 + col * (CELL_W + CELL_GAP), -6 - row * (CELL_H + CELL_GAP))
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints(c)
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        c.text:SetPoint("CENTER", c, "CENTER", 0, 0)
        c.text:SetText(tostring(n))
        c:SetScript("OnClick", function() TogglePick(n) end)
        ui.cells[n] = c
    end
    local boardBottom = -6 - 8 * (CELL_H + CELL_GAP)

    -- The pay table for the spots picked
    ui.payTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ui.payTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, boardBottom - 4)
    ui.catch = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.catch:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, boardBottom - 4)
    ui.payHits, ui.payMults = {}, {}
    for i = 1, 8 do
        local x = 10 + (i - 1) * 42
        local h = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        h:SetPoint("TOPLEFT", panel, "TOPLEFT", x, boardBottom - 20)
        local m = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        m:SetPoint("TOPLEFT", panel, "TOPLEFT", x, boardBottom - 33)
        ui.payHits[i], ui.payMults[i] = h, m
    end

    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", panel, "TOP", 0, boardBottom - 52)
    ui.status:SetWidth(AREA_W - 8)

    -- Bet, Quick pick and Clear
    local row = ns.CreateFrame("Frame", nil, panel)
    row:SetWidth(AREA_W - 8); row:SetHeight(24)
    row:SetPoint("BOTTOM", panel, "BOTTOM", 0, 48)
    ui.betDown = MakeButton(row, "<", 24, function() StepBet(-1) end)
    ui.betDown:SetPoint("LEFT", row, "LEFT", 6, 0)
    ui.betText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.betText:SetPoint("LEFT", ui.betDown, "RIGHT", 2, 0)
    ui.betText:SetWidth(90)
    ui.betUp = MakeButton(row, ">", 24, function() StepBet(1) end)
    ui.betUp:SetPoint("LEFT", ui.betText, "RIGHT", 2, 0)
    ui.clear = MakeButton(row, "Clear", 60, Clear)
    ui.clear:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    ui.quick = MakeButton(row, "Quick pick", 86, QuickPick)
    ui.quick:SetPoint("RIGHT", ui.clear, "LEFT", -4, 0)

    ui.play = MakeButton(panel, "Play", 150, function() Play() end, 28)
    ui.play:SetPoint("BOTTOM", panel, "BOTTOM", 0, 18)
    ui.auto = MakeButton(panel, "Auto", 80, ToggleAuto, 26)
    ui.auto:SetPoint("LEFT", ui.play, "RIGHT", 10, 0)

    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 3)

    ui.options = BuildOptions(panel)
    ui.sounds = ns:CreateSoundOptions(panel, "Keno Options", function() return db end)

    if db.game then
        -- a game cut off by a reload: its numbers were already drawn, so show them
        Finish()
        SetStatus("Welcome back - your last game finished while you were away. " .. (ui.status:GetText() or ""))
    elseif Spots() > 0 then
        SetStatus("Your numbers are still picked. Play when ready.")
    else
        SetStatus("Pick 1 to 10 numbers, then Play.")
    end
    Refresh()
end

function Keno:OnShow()
    if ui.cells then Refresh() end
end

function Keno:OnHide()
    if ui.options then ui.options:Hide() end
    if ui.sounds then ui.sounds:Hide() end
    -- leaving finishes the draw at once (and stops Auto)
    S.autoLeft = 0
    S.wait = nil
    if db and db.game then Finish() end
end

-- A game being drawn (its numbers are already set, so it's never lost).
function Keno:ChipsInPlay()
    local d = ns.db.keno
    return (d ~= nil and d.game ~= nil) or S.autoLeft > 0
end

-- Start over (Options): stop Auto and finish a draw at once.
function Keno:Abandon()
    S.autoLeft = 0
    S.wait = nil
    if db and db.game then
        Finish()
    elseif not db and ns.db.keno and ns.db.keno.game then
        -- never opened since a reload: pay the saved game out without the board
        local g = ns.db.keno.game
        local set, hits = {}, 0
        for i = 1, DRAWN do set[g.drawn[i]] = true end
        for num in pairs(g.picks) do if set[num] then hits = hits + 1 end end
        local paid = Payout(g.spots, hits, g.bet)
        if paid > 0 then ns:AddChips(paid) end
        ns.db.keno.game = nil
    end
end

function Keno:ResetStats()
    local d = ns.db.keno
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    if ui.stats and db then Refresh() end
end

-- Exposed for tests.
Keno.PAYS, Keno.Payout, Keno.DrawNumbers, Keno.S, Keno.ui = PAYS, Payout, DrawNumbers, S, ui
function Keno.SetDraw(fn) DrawNumbers = fn end

ns:RegisterGame(Keno)
