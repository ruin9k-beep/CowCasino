-- CowCasino: Crash
-- Place a bet and launch: the multiplier climbs from 1.00x, faster and
-- faster, until it crashes at a random point. Cash out before the crash to
-- win your bet times the multiplier; still in when it crashes, you lose it.
-- An auto cash-out can take the win for you at a multiplier you choose.
-- Crash points are fair odds with a 1% house edge, like the websites: a run
-- reaches 2x about half the time, 10x about one time in ten.
-- A run still going when the game reloads is refunded.

local ns = CowCasino.ns

local AREA_W      = 352
local MIN_BET, MAX_BET = 5, 1000
local CHIP_VALUES = { 5, 25, 100, 500 }
local HOUSE_EDGE  = 0.01
local GROWTH      = 0.09          -- the multiplier is e^(GROWTH * seconds)
local MAX_CRASH   = 10000
local AUTO_CHOICES = { 0, 1.1, 1.25, 1.5, 2, 3, 5, 10, 25, 100 }   -- 0 = off
local DOT = "Interface\\AddOns\\CowCasino\\Art\\Dot"
local CURVE_DOTS  = 70

-- Graph area
local GX, GY, GW, GH = 34, -16, 300, 196

local DEFAULT_STATS = { runs = 0, cashouts = 0, busts = 0, bestCashout = 0, biggestWin = 0, net = 0 }

local Crash = {
    id = "crash",
    name = "Crash",
    description = "Watch the multiplier climb. Cash out before it crashes!",
    icon = "Interface\\AddOns\\CowCasino\\Art\\CrashIcon",   -- painted (dev/art-src/make_game_icons.py)
}

local db
local ui = {}
-- The run: { bet, crash, start, auto, cashed = multiplier or nil, over }
local run
local history = {}    -- recent crash points, newest first

local function Fmt(n) return ns:FormatChips(n) end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function FmtMult(m) return string.format("%.2fx", m) end

-- A crash point with P(crash >= x) = (1 - edge) / x, in hundredths.
-- About 1 run in 50 crashes at 1.00x straight away.
function Crash.NewCrashPoint(u)
    u = u or math.random()
    if u >= 1 then u = 0.999999 end
    local x = (1 - HOUSE_EDGE) / (1 - u)
    x = math.floor(x * 100) / 100
    if x < 1 then x = 1 end
    if x > MAX_CRASH then x = MAX_CRASH end
    return x
end

local function MultAt(seconds) return math.exp(GROWTH * seconds) end
local function SecondsFor(mult) return math.log(mult) / GROWTH end

-- Whole chips: half a chip or more rounds up.
local function Pay(bet, mult) return math.floor(bet * mult + 0.5) end

local function SetStatus(text, r, g, b)
    ui.status:SetText(text or "")
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function StatsText()
    local s = db.stats
    local net = s.net
    local netText = (net > 0 and ("|cff40ff40+" .. Fmt(net))) or (net < 0 and ("|cffff5050-" .. Fmt(-net))) or "|cffcccccc0"
    return string.format("Runs %d  Cashed %d  Best %s  Net %s|r", s.runs, s.cashouts, FmtMult(s.bestCashout), netText)
end

local function AutoText()
    if db.auto == 0 then return "Off" end
    return FmtMult(db.auto)
end

-- Where a point (seconds, multiplier) sits on the graph, which stretches to fit.
local function Scale(maxT, maxM)
    local spanT = math.max(8, maxT * 1.15)
    local spanM = math.max(2, 1 + (maxM - 1) * 1.15)
    return spanT, spanM
end

local function DrawGraph(now, mult, crashed)
    local spanT, spanM = Scale(now, mult)
    for k = 1, CURVE_DOTS do
        local d = ui.curve[k]
        local t = now * k / CURVE_DOTS
        if now > 0 then
            local m = MultAt(t)
            local x = GW * t / spanT
            local y = GH * (m - 1) / (spanM - 1)
            d:ClearAllPoints()
            d:SetPoint("CENTER", ui.graph, "BOTTOMLEFT", x, y)
            if crashed then d:SetVertexColor(0.95, 0.25, 0.2) else d:SetVertexColor(1, 0.82, 0.2) end
            d:Show()
        else
            d:Hide()
        end
    end
    -- axis labels: top multiplier and right-hand time
    ui.yTop:SetText(FmtMult(spanM))
    ui.xRight:SetText(math.floor(spanT + 0.5) .. "s")
end

local function Refresh()
    if not ui.graph then return end
    ns:UpdateChipsDisplay()
    local live = run and not run.over
    if live and not run.cashed then
        ui.main:SetText("Cash out " .. Fmt(Pay(run.bet, MultAt(GetTime() - run.start))))
        ns.SetEnabled(ui.main, true)
    elseif live then
        ui.main:SetText("Cashed out")
        ns.SetEnabled(ui.main, false)
    else
        ui.main:SetText("Bet " .. Fmt(db.bet))
        ns.SetEnabled(ui.main, db.bet >= MIN_BET and db.bet <= ns.db.chips)
    end
    for _, b in ipairs(ui.chipButtons) do ns.SetEnabled(b, not live) end
    ns.SetEnabled(ui.clear, not live and db.bet > 0)
    ns.SetEnabled(ui.autoPrev, not live)
    ns.SetEnabled(ui.autoNext, not live)
    ui.auto:SetText("Auto " .. AutoText())
    local hist = {}
    for i = 1, math.min(8, ns.getn(history)) do
        local m = history[i]
        local color = m >= 2 and "|cff40ff40" or "|cffff7070"
        table.insert(hist, color .. FmtMult(m) .. "|r")
    end
    ui.history:SetText(table.concat(hist, "  "))
    ui.stats:SetText(StatsText())
end

local function AddBet(amount)
    db.bet = math.max(0, math.min(MAX_BET, db.bet + amount, math.max(0, ns.db.chips)))
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

local function StepAuto(dir)
    local idx = 1
    for i, v in ipairs(AUTO_CHOICES) do if v == db.auto then idx = i end end
    idx = math.max(1, math.min(ns.getn(AUTO_CHOICES), idx + dir))
    db.auto = AUTO_CHOICES[idx]
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

local function CashOut(mult)
    if not run or run.over or run.cashed then return end
    local win = Pay(run.bet, mult)
    run.cashed = mult
    db.live = nil
    ns:AddChips(win)
    local s = db.stats
    s.cashouts = s.cashouts + 1
    s.net = s.net + win - run.bet
    if mult > s.bestCashout then s.bestCashout = mult end
    if win - run.bet > s.biggestWin then s.biggestWin = win - run.bet end
    SetStatus("Cashed out at " .. FmtMult(mult) .. ": " .. Fmt(win) .. " (+" .. Fmt(win - run.bet) .. ").", 0.25, 1, 0.25)
    ns:PlayGameSound(db, "win")
    Refresh()
end

local function EndRun()
    run.over = true
    table.insert(history, 1, run.crash)
    if ns.getn(history) > 12 then table.remove(history) end
    local s = db.stats
    s.runs = s.runs + 1
    ui.mult:SetText("Crashed at " .. FmtMult(run.crash))
    ui.mult:SetTextColor(0.95, 0.25, 0.2)
    if not run.cashed then
        db.live = nil
        s.busts = s.busts + 1
        s.net = s.net - run.bet
        SetStatus("Crashed at " .. FmtMult(run.crash) .. ". You lose " .. Fmt(run.bet) .. ".", 1, 0.35, 0.35)
        ns:PlayGameSound(db, "lose")
    else
        SetStatus("Crashed at " .. FmtMult(run.crash) .. " - you were out at " .. FmtMult(run.cashed) .. ".", 0.25, 1, 0.25)
    end
    if ns.db.chips < MIN_BET then SetStatus(ns:LowChipsText(MIN_BET), 1, 0.35, 0.35) end
    if db.bet > ns.db.chips then db.bet = math.floor(ns.db.chips / MIN_BET) * MIN_BET end
    Refresh()
end

-- Runs the round even while the window is hidden.
local driver = ns.CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
    if not run or run.over then this:Hide() return end
    local now = GetTime() - run.start
    local mult = MultAt(now)
    local crashAt = SecondsFor(run.crash)
    -- the auto cash-out fires first if its target comes before the crash
    if run.auto > 0 and not run.cashed and run.auto <= run.crash and now >= SecondsFor(run.auto) then
        CashOut(run.auto)
    end
    if now >= crashAt then
        if ui.graph and ui.graph:IsVisible() then DrawGraph(crashAt, run.crash, true) end
        EndRun()
        this:Hide()
        return
    end
    if ui.graph and ui.graph:IsVisible() then
        DrawGraph(now, mult, false)
        ui.mult:SetText(FmtMult(math.floor(mult * 100) / 100))
        ui.mult:SetTextColor(run.cashed and 0.25 or 1, run.cashed and 1 or 1, run.cashed and 0.25 or 1)
        if not run.cashed then ui.main:SetText("Cash out " .. Fmt(Pay(run.bet, mult))) end
    end
end)

local function Launch()
    if run and not run.over then return end
    if db.bet < MIN_BET then return end
    if not ns:SpendChips(db.bet) then
        SetStatus("Not enough chips.", 1, 0.35, 0.35)
        return
    end
    run = { bet = db.bet, crash = Crash.NewCrashPoint(), start = GetTime(), auto = db.auto or 0 }
    db.live = run.bet
    SetStatus("Climbing... cash out before it crashes!")
    ui.mult:SetTextColor(1, 1, 1)
    ns:PlayGameSound(db, "newHand")
    driver:Show()
    Refresh()
end

local function Main()
    if run and not run.over then
        -- too late once the crash time has come, even before the next frame shows it
        local now = GetTime() - run.start
        if not run.cashed and now < SecondsFor(run.crash) then
            local m = math.floor(MultAt(now) * 100) / 100
            if m > run.crash then m = run.crash end
            CashOut(m)
        end
    else
        Launch()
    end
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
    title:SetText("Crash Options")

    local rules = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rules:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -50)
    rules:SetWidth(AREA_W - 32)
    rules:SetJustifyH("LEFT")
    rules:SetText("How it plays: press Bet and the multiplier starts climbing from 1.00x. Press Cash out "
        .. "before it crashes to win your bet times the multiplier; if it crashes first, the bet is lost. "
        .. "A run reaches 2x about half the time and 10x about one time in ten. Set an auto cash-out on the "
        .. "table to take the win at your target automatically.")

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

function Crash:Build(panel)
    ns.db.crash = ns.db.crash or {}
    db = ns.db.crash
    if db.bet == nil then db.bet = 25 end
    db.auto = db.auto or 0
    db.stats = db.stats or {}
    Fill(db.stats, DEFAULT_STATS)
    ns:InitSounds(db)

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.05, 0.07, 0.12, 0.94)

    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    -- the graph: axes, a curve of dots and the multiplier
    ui.graph = ns.CreateFrame("Frame", nil, panel)
    ui.graph:SetWidth(GW); ui.graph:SetHeight(GH)
    ui.graph:SetPoint("TOPLEFT", panel, "TOPLEFT", GX, GY)
    local back = ui.graph:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(ui.graph)
    back:SetTexture(0, 0, 0, 0.35)
    local xAxis = ui.graph:CreateTexture(nil, "BORDER")
    xAxis:SetTexture(0.6, 0.6, 0.7, 0.8)
    xAxis:SetHeight(1)
    xAxis:SetPoint("BOTTOMLEFT", ui.graph, "BOTTOMLEFT", 0, 0)
    xAxis:SetPoint("BOTTOMRIGHT", ui.graph, "BOTTOMRIGHT", 0, 0)
    local yAxis = ui.graph:CreateTexture(nil, "BORDER")
    yAxis:SetTexture(0.6, 0.6, 0.7, 0.8)
    yAxis:SetWidth(1)
    yAxis:SetPoint("BOTTOMLEFT", ui.graph, "BOTTOMLEFT", 0, 0)
    yAxis:SetPoint("TOPLEFT", ui.graph, "TOPLEFT", 0, 0)
    local yBottom = ui.graph:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    yBottom:SetPoint("RIGHT", ui.graph, "BOTTOMLEFT", -3, 0)
    yBottom:SetText("1x")
    ui.yTop = ui.graph:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.yTop:SetPoint("RIGHT", ui.graph, "TOPLEFT", -3, -4)
    ui.xRight = ui.graph:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.xRight:SetPoint("TOPRIGHT", ui.graph, "BOTTOMRIGHT", 0, -2)
    ui.curve = {}
    for k = 1, CURVE_DOTS do
        local d = ui.graph:CreateTexture(nil, "ARTWORK")
        d:SetTexture(DOT)
        d:SetWidth(5); d:SetHeight(5)
        d:Hide()
        ui.curve[k] = d
    end
    ui.mult = ns:BigFont(ui.graph:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 30)
    ui.mult:SetPoint("CENTER", ui.graph, "CENTER", 0, 20)
    ui.mult:SetText(FmtMult(1))

    ui.history = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.history:SetPoint("TOP", panel, "TOP", 0, -234)
    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", panel, "TOP", 0, -252)
    ui.status:SetWidth(AREA_W - 8)

    -- Row 1: bet chips and the auto cash-out
    local row1 = ns.CreateFrame("Frame", nil, panel)
    row1:SetWidth(AREA_W - 8); row1:SetHeight(24)
    row1:SetPoint("BOTTOM", panel, "BOTTOM", 0, 52)
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
    ui.autoNext = MakeButton(row1, ">", 24, function() StepAuto(1) end)
    ui.autoNext:SetPoint("RIGHT", row1, "RIGHT", 0, 0)
    ui.auto = row1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.auto:SetPoint("RIGHT", ui.autoNext, "LEFT", -4, 0)
    ui.auto:SetWidth(76)
    ui.autoPrev = MakeButton(row1, "<", 24, function() StepAuto(-1) end)
    ui.autoPrev:SetPoint("RIGHT", ui.auto, "LEFT", -4, 0)
    for _, b in ipairs({ ui.autoPrev, ui.autoNext }) do
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText("Auto cash-out")
            GameTooltip:AddLine("Take the win automatically when the multiplier reaches this. You can still cash out sooner.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Row 2: the big button
    ui.main = MakeButton(panel, "Bet", 220, Main, 28)
    ui.main:SetPoint("BOTTOM", panel, "BOTTOM", 0, 20)

    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 6)

    ui.options = BuildOptions(panel)
    ui.sounds = ns:CreateSoundOptions(panel, "Crash Options", function() return db end)

    if db.live and db.live > 0 then
        ns:AddChips(db.live)
        SetStatus("Refunded " .. Fmt(db.live) .. " chips for a run still going.")
        db.live = nil
    else
        SetStatus("Set your bet and press Bet to launch.")
    end
    DrawGraph(0, 1, false)
    Refresh()
end

function Crash:OnShow()
    if db and not (run and not run.over) and (db.bet < MIN_BET or db.bet > ns.db.chips) then
        db.bet = math.min(25, math.floor(ns.db.chips / MIN_BET) * MIN_BET)
    end
    if ui.graph then Refresh() end
end

function Crash:OnHide()
    if ui.options then ui.options:Hide() end
    if ui.sounds then ui.sounds:Hide() end
end

-- For the out-of-chips check: a run with your bet still in it.
function Crash:ChipsInPlay()
    return run ~= nil and not run.over and not run.cashed
end

-- Start over (Options) gives up a run in progress.
function Crash:Abandon()
    if run then run.over = true end
    if ns.db.crash then ns.db.crash.live = nil end
    if ui.graph then Refresh() end
end

function Crash:ResetStats()
    local d = ns.db.crash
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    if ui.stats and db then Refresh() end
end

-- Exposed for tests.
function Crash.Run() return run end
Crash.ui, Crash.history = ui, history
Crash.MultAt, Crash.SecondsFor = MultAt, SecondsFor

ns:RegisterGame(Crash)
