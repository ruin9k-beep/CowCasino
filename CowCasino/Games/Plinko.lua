-- CowCasino: Plinko
-- Drop a ball through a triangle of pegs. At every row it bounces left or
-- right, and the slot it lands in multiplies the bet. Edge slots pay big
-- and the middle pays least; pick 8, 12 or 16 rows and a risk level.
-- The payout tables match the well-known online game (about a 1% house edge).
-- Each press of Drop sends 1 to 10 balls (picked on the table); rows, risk
-- and ball speed are in Options. A ball still falling when the game reloads
-- is refunded.

local ns = CowCasino.ns

local AREA_W      = 352
local MIN_BET, MAX_BET = 5, 1000
local CHIP_VALUES = { 5, 25, 100, 500 }
local ROW_CHOICES = { 8, 12, 16 }
local RISKS       = { "Low", "Medium", "High" }
local MAX_BALLS   = 20       -- in the air at once
local MAX_PER_DROP = 10      -- balls one press of Drop can send
local DROP_GAP    = 0.12     -- seconds between the balls of one drop
local ROW_TIME    = { normal = 0.11, fast = 0.06 }   -- seconds per row of pegs
local DOT = "Interface\\AddOns\\CowCasino\\Art\\Dot"

-- Board area inside the panel
local BOARD_TOP, BOARD_H, BOARD_W = -14, 216, 330

-- Multipliers per slot, left to right, by rows and risk.
local PAYOUTS = {
    [8] = {
        Low    = { 5.6, 2.1, 1.1, 1, 0.5, 1, 1.1, 2.1, 5.6 },
        Medium = { 13, 3, 1.3, 0.7, 0.4, 0.7, 1.3, 3, 13 },
        High   = { 29, 4, 1.5, 0.3, 0.2, 0.3, 1.5, 4, 29 },
    },
    [12] = {
        Low    = { 10, 3, 1.6, 1.4, 1.1, 1, 0.5, 1, 1.1, 1.4, 1.6, 3, 10 },
        Medium = { 33, 11, 4, 2, 1.1, 0.6, 0.3, 0.6, 1.1, 2, 4, 11, 33 },
        High   = { 170, 24, 8.1, 2, 0.7, 0.2, 0.2, 0.2, 0.7, 2, 8.1, 24, 170 },
    },
    [16] = {
        Low    = { 16, 9, 2, 1.4, 1.4, 1.2, 1.1, 1, 0.5, 1, 1.1, 1.2, 1.4, 1.4, 2, 9, 16 },
        Medium = { 110, 41, 10, 5, 3, 1.5, 1, 0.5, 0.3, 0.5, 1, 1.5, 3, 5, 10, 41, 110 },
        High   = { 1000, 130, 26, 9, 4, 2, 0.2, 0.2, 0.2, 0.2, 0.2, 2, 4, 9, 26, 130, 1000 },
    },
}

local DEFAULT_STATS = { balls = 0, bestMultiplier = 0, biggestWin = 0, net = 0 }

local Plinko = {
    id = "plinko",
    name = "Plinko",
    description = "Drop balls through the pegs. Edge slots pay up to 1000x.",
    icon = "Interface\\AddOns\\CowCasino\\Art\\PlinkoIcon",   -- painted (art-src/make_game_icons.py)
}

local db
local ui = {}
local balls = {}      -- in the air: { bet, rows, risk, path = {0/1...}, slot, t, tex }
local last = {}       -- recent results, newest first: { mult = }

local function Fmt(n) return ns:FormatChips(n) end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function FmtMult(m)
    if m >= 1000 then return math.floor(m / 1000) .. "k" end
    if m >= 100 then return tostring(math.floor(m)) end
    if m == math.floor(m) then return tostring(m) end
    return string.format("%.1f", m)
end

-- Whole chips: half a chip or more rounds up.
local function Pay(bet, mult) return math.floor(bet * mult + 0.5) end

-- Slot colors run from cool (middle) to hot (edges).
local function SlotColor(i, n)
    local mid = (n + 1) / 2
    local f = math.abs(i - mid) / (mid - 1)
    return 0.95, 0.85 - 0.65 * f, 0.15 - 0.1 * f
end

---------------------------------------------------------------------------
-- Board geometry: pegs for the current rows
---------------------------------------------------------------------------
local function Spacing(rows)
    local dx = math.min(32, math.floor(BOARD_W / (rows + 2)))
    local dy = math.floor(BOARD_H / (rows + 1))
    return dx, dy
end

-- Where a ball is after `rights` bounces right in `row` rows (row 0 = top).
local function BallPos(rows, row, rights)
    local dx, dy = Spacing(rows)
    return (rights - row / 2) * dx, BOARD_TOP - 8 - row * dy
end

local function SetStatus(text, r, g, b)
    ui.status:SetText(text or "")
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function StatsText()
    local s = db.stats
    local net = s.net
    local netText = (net > 0 and ("|cff40ff40+" .. Fmt(net))) or (net < 0 and ("|cffff5050-" .. Fmt(-net))) or "|cffcccccc0"
    return string.format("Balls %d  Best %sx  Biggest win %s  Net %s|r", s.balls, FmtMult(s.bestMultiplier),
        Fmt(s.biggestWin), netText)
end

local function InFlight() return ns.getn(balls) end

local function DrawBoard()
    local rows = db.rows
    local dx, dy = Spacing(rows)
    local n = 0
    for r = 1, rows do
        for k = 0, r + 1 do
            n = n + 1
            local peg = ui.pegs[n]
            peg:ClearAllPoints()
            peg:SetPoint("CENTER", ui.board, "TOP", (k - (r + 1) / 2) * dx, BOARD_TOP - 8 - r * dy + dy * 0.5)
            peg:Show()
        end
    end
    for k = n + 1, ns.getn(ui.pegs) do ui.pegs[k]:Hide() end
    local mults = PAYOUTS[rows][db.risk]
    local slots = rows + 1
    for i = 1, ns.getn(ui.slots) do
        local s = ui.slots[i]
        if i <= slots then
            s:ClearAllPoints()
            s:SetWidth(dx - 2)
            s:SetPoint("TOP", ui.board, "TOP", (i - 1 - rows / 2) * dx, BOARD_TOP - 8 - (rows + 1) * dy + 6)
            s.text:SetText(FmtMult(mults[i]))
            s.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", rows >= 16 and 7 or (rows >= 12 and 8 or 10))
            local r, g, b = SlotColor(i, slots)
            s.fill:SetTexture(r * 0.6, g * 0.6, b * 0.6, 1)
            s.color = { r, g, b }
            s:Show()
        else
            s:Hide()
        end
    end
    ui.drawnRows, ui.drawnRisk = rows, db.risk
end

local function Refresh()
    if not ui.board then return end
    ns:UpdateChipsDisplay()
    if ui.drawnRows ~= db.rows or ui.drawnRisk ~= db.risk then DrawBoard() end
    local n = db.count
    ui.setup:SetText(db.rows .. " rows, " .. db.risk .. " risk")
    ui.count:SetText(n == 1 and "1 ball" or (n .. " balls"))
    ns.SetEnabled(ui.countPrev, n > 1)
    ns.SetEnabled(ui.countNext, n < MAX_PER_DROP)
    ui.drop:SetText(n == 1 and ("Drop " .. Fmt(db.bet)) or ("Drop " .. n .. " x " .. Fmt(db.bet)))
    ns.SetEnabled(ui.drop, db.bet >= MIN_BET and db.bet * n <= ns.db.chips and InFlight() + n <= MAX_BALLS)
    if ui.options and ui.options:IsShown() then ui.options:Refresh() end
    ns.SetEnabled(ui.clear, db.bet > 0)
    local hist = {}
    for i = 1, math.min(6, ns.getn(last)) do
        local m = last[i].mult
        local color = m >= 2 and "|cff40ff40" or (m >= 1 and "|cffffffff" or "|cffff7070")
        table.insert(hist, color .. FmtMult(m) .. "x|r")
    end
    ui.history:SetText(table.concat(hist, "  "))
    ui.stats:SetText(StatsText())
end

local function AddBet(amount)
    db.bet = math.max(0, math.min(MAX_BET, db.bet + amount, math.max(0, ns.db.chips)))
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

local function Step(list, current, dir)
    local idx = 1
    for i, v in ipairs(list) do if v == current then idx = i end end
    idx = math.max(1, math.min(ns.getn(list), idx + dir))
    return list[idx]
end

local function SaveFlight()
    local total = 0
    for _, b in ipairs(balls) do total = total + b.bet end
    db.inFlight = (total > 0) and total or nil
end

local function Land(ball)
    local mults = PAYOUTS[ball.rows][ball.risk]
    local mult = mults[ball.slot]
    local win = Pay(ball.bet, mult)
    if win > 0 then ns:AddChips(win) end
    local s = db.stats
    s.balls = s.balls + 1
    s.net = s.net + win - ball.bet
    if mult > s.bestMultiplier then s.bestMultiplier = mult end
    if win - ball.bet > s.biggestWin then s.biggestWin = win - ball.bet end
    table.insert(last, 1, { mult = mult })
    if ns.getn(last) > 12 then table.remove(last) end
    if ball.rows == db.rows and ball.risk == db.risk and ui.slots[ball.slot] then
        ui.slots[ball.slot].flash = 0.4
    end
    -- several balls from one drop: one line and one sound when the last lands
    local batch = ball.batch
    if batch.n > 1 then
        batch.left = batch.left - 1
        batch.back = batch.back + win
        if batch.left > 0 then return end
        local spent = batch.n * ball.bet
        local net = batch.back - spent
        local text = batch.n .. " balls: " .. Fmt(batch.back) .. " back from " .. Fmt(spent)
        if net > 0 then
            SetStatus(text .. " (+" .. Fmt(net) .. ").", 0.25, 1, 0.25)
            ns:PlayGameSound(db, "win")
        elseif net < 0 then
            SetStatus(text .. " (-" .. Fmt(-net) .. ").", 1, 0.45, 0.45)
            ns:PlayGameSound(db, "lose")
        else
            SetStatus(text .. ".", 0.9, 0.9, 0.9)
        end
        return
    end
    if win > ball.bet then
        SetStatus(FmtMult(mult) .. "x! You win " .. Fmt(win) .. " (+" .. Fmt(win - ball.bet) .. ").", 0.25, 1, 0.25)
        ns:PlayGameSound(db, "win")
    elseif win < ball.bet then
        SetStatus(FmtMult(mult) .. "x: " .. Fmt(win) .. " back from " .. Fmt(ball.bet) .. ".", 1, 0.45, 0.45)
        ns:PlayGameSound(db, "lose")
    else
        SetStatus(FmtMult(mult) .. "x: your " .. Fmt(win) .. " back.", 0.9, 0.9, 0.9)
    end
end

-- Keeps balls falling while the window is hidden, and lands them on time.
local driver = ns.CreateFrame("Frame")
driver:Hide()

-- Sends db.count balls, one just after another, each a bet of db.bet.
local function Drop()
    local n = db.count
    if db.bet < MIN_BET or InFlight() + n > MAX_BALLS then return end
    if not ns:SpendChips(db.bet * n) then
        SetStatus("Not enough chips for " .. n .. " balls.", 1, 0.35, 0.35)
        return
    end
    local batch = { n = n, left = n, back = 0 }
    for k = 1, n do
        local ball = { bet = db.bet, rows = db.rows, risk = db.risk, path = {}, batch = batch,
            t = -(k - 1) * DROP_GAP, speed = ROW_TIME[db.speed] or ROW_TIME.normal }
        local rights = 0
        for r = 1, ball.rows do
            local step = math.random(0, 1)
            ball.path[r] = step
            rights = rights + step
        end
        ball.slot = rights + 1
        -- a free ball texture
        for _, tex in ipairs(ui.ballTex) do
            if not tex.used and not ball.tex then
                tex.used = true
                ball.tex = tex
            end
        end
        table.insert(balls, ball)
    end
    SaveFlight()
    ns:PlayGameSound(db, "newHand")
    driver:Show()
    Refresh()
end

driver:SetScript("OnUpdate", function()
    local dt = arg1 or 0
    local i = 1
    local landed = false
    while i <= ns.getn(balls) do
        local b = balls[i]
        b.t = b.t + dt
        local pos = b.t / b.speed               -- rows fallen, fractional
        if pos >= b.rows + 1 then
            table.remove(balls, i)
            if b.tex then b.tex.used = nil; b.tex:Hide() end
            Land(b)
            landed = true
        else
            if b.tex and b.t < 0 then
                b.tex:Hide()
            elseif b.tex and ui.board:IsVisible() then
                -- rights so far, and an easing between rows with a little hop
                local row = math.floor(pos)
                local frac = pos - row
                local r0 = 0
                for k = 1, math.min(row, b.rows) do r0 = r0 + b.path[k] end
                local r1 = r0 + ((row < b.rows) and b.path[row + 1] or 0)
                local x0, y0 = BallPos(b.rows, row, r0)
                local x1, y1 = BallPos(b.rows, row + 1, r1)
                if row >= b.rows then x1 = x0 end
                local x = x0 + (x1 - x0) * frac
                local y = y0 + (y1 - y0) * frac + math.sin(frac * 3.14159) * 5
                b.tex:ClearAllPoints()
                b.tex:SetPoint("CENTER", ui.board, "TOP", x, y)
                b.tex:Show()
            end
            i = i + 1
        end
    end
    -- landing flashes
    if ui.slots then
        for _, s in ipairs(ui.slots) do
            if s.flash and s.color then
                s.flash = s.flash - dt
                local c = s.color
                if s.flash <= 0 then
                    s.flash = nil
                    s.fill:SetTexture(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
                else
                    s.fill:SetTexture(c[1], c[2], c[3], 1)
                end
            end
        end
    end
    if landed then
        SaveFlight()
        Refresh()
    end
    local flashing = false
    if ui.slots then for _, s in ipairs(ui.slots) do if s.flash then flashing = true end end end
    if ns.getn(balls) == 0 and not flashing then this:Hide() end
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
    title:SetText("Plinko Options")

    -- label, < value >
    local function Selector(text, y, onStep)
        local label = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", o, "TOPLEFT", 16, y)
        label:SetText(text)
        local value = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        local function Go(dir)
            onStep(dir)
            ns:Sound("IG_MAINMENU_OPTION")
            Refresh()
            o:Refresh()
        end
        local nextB = MakeButton(o, ">", 26, function() Go(1) end)
        nextB:SetPoint("TOPRIGHT", o, "TOPRIGHT", -16, y + 4)
        value:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
        value:SetWidth(70)
        value:SetJustifyH("CENTER")
        local prevB = MakeButton(o, "<", 26, function() Go(-1) end)
        prevB:SetPoint("RIGHT", value, "LEFT", -6, 0)
        return { value = value, prev = prevB, next = nextB }
    end
    local risk = Selector("Risk", -46, function(dir) db.risk = Step(RISKS, db.risk, dir) end)
    local rows = Selector("Rows of pegs", -76, function(dir) db.rows = Step(ROW_CHOICES, db.rows, dir) end)
    local speed = Selector("Ball speed", -106, function()
        db.speed = (db.speed == "fast") and "normal" or "fast"
    end)
    o.risk, o.rows, o.speed = risk, rows, speed
    local busy = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    busy:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -132)
    busy:SetText("Risk and rows change once the balls in the air have landed.")

    local rules = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rules:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -152)
    rules:SetWidth(AREA_W - 32)
    rules:SetJustifyH("LEFT")
    rules:SetText("How it plays: each ball bounces left or right at every row of pegs, so it usually lands near "
        .. "the middle and only rarely at the edges. The slot's number multiplies your bet. More rows and higher "
        .. "risk make the edges pay more and the middle less.")

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
        local flying = InFlight() > 0
        risk.value:SetText(db.risk)
        rows.value:SetText(tostring(db.rows))
        speed.value:SetText(db.speed == "fast" and "Fast" or "Normal")
        for _, sel in ipairs({ risk, rows }) do
            ns.SetEnabled(sel.prev, not flying)
            ns.SetEnabled(sel.next, not flying)
        end
        ns.SetShown(busy, flying)
        if not (reset.armed and GetTime() - reset.armed <= 3) then
            reset.armed = nil
            reset:SetText("Reset stats")
        end
    end
    o:SetScript("OnShow", function() this:Refresh() end)
    return o
end

function Plinko:Build(panel)
    ns.db.plinko = ns.db.plinko or {}
    db = ns.db.plinko
    if db.bet == nil then db.bet = 25 end
    db.rows = db.rows or 16
    if not PAYOUTS[db.rows] then db.rows = 16 end
    db.risk = db.risk or "Medium"
    if not PAYOUTS[db.rows][db.risk] then db.risk = "Medium" end
    db.speed = db.speed or "normal"
    db.count = math.max(1, math.min(MAX_PER_DROP, db.count or 1))
    db.stats = db.stats or {}
    Fill(db.stats, DEFAULT_STATS)
    ns:InitSounds(db)

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.07, 0.06, 0.16, 0.94)

    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    ui.board = ns.CreateFrame("Frame", nil, panel)
    ui.board:SetWidth(BOARD_W); ui.board:SetHeight(BOARD_H + 40)
    ui.board:SetPoint("TOP", panel, "TOP", 0, 0)

    ui.pegs = {}
    local most = ROW_CHOICES[ns.getn(ROW_CHOICES)]
    for k = 1, most * (most + 5) / 2 do      -- row r has r + 2 pegs
        local p = ui.board:CreateTexture(nil, "ARTWORK")
        p:SetTexture(DOT)
        p:SetVertexColor(0.85, 0.85, 0.95)
        p:SetWidth(5); p:SetHeight(5)
        p:Hide()
        ui.pegs[k] = p
    end
    ui.slots = {}
    for i = 1, most + 1 do
        local s = ns.CreateFrame("Frame", nil, ui.board)
        s:SetHeight(16)
        s.fill = s:CreateTexture(nil, "BACKGROUND")
        s.fill:SetAllPoints(s)
        s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.text:SetPoint("CENTER", s, "CENTER", 0, 0)
        ui.slots[i] = s
    end
    ui.ballTex = {}
    for k = 1, MAX_BALLS do
        local t = ui.board:CreateTexture(nil, "OVERLAY")
        t:SetTexture(DOT)
        t:SetVertexColor(1, 0.35, 0.55)
        t:SetWidth(9); t:SetHeight(9)
        t:Hide()
        ui.ballTex[k] = t
    end

    ui.history = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.history:SetPoint("TOP", panel, "TOP", 0, -251)
    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", panel, "TOP", 0, -266)
    ui.status:SetWidth(AREA_W - 8)

    ui.setup = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.setup:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -4)

    -- Row 1: bet chips, and how many balls a drop sends
    local row1 = ns.CreateFrame("Frame", nil, panel)
    row1:SetWidth(AREA_W - 8); row1:SetHeight(24)
    row1:SetPoint("BOTTOM", panel, "BOTTOM", 0, 52)
    local x = 0
    for _, v in ipairs(CHIP_VALUES) do
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
        x = x + 41
    end
    ui.clear = MakeButton(row1, "Clear", 46, function() db.bet = 0; Refresh() end)
    ui.clear:SetPoint("LEFT", row1, "LEFT", x, 0)
    local function StepCount(dir)
        db.count = math.max(1, math.min(MAX_PER_DROP, db.count + dir))
        ns:Sound("IG_MAINMENU_OPTION")
        Refresh()
    end
    ui.countNext = MakeButton(row1, ">", 24, function() StepCount(1) end)
    ui.countNext:SetPoint("RIGHT", row1, "RIGHT", 0, 0)
    ui.count = row1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.count:SetPoint("RIGHT", ui.countNext, "LEFT", -4, 0)
    ui.count:SetWidth(54)
    ui.countPrev = MakeButton(row1, "<", 24, function() StepCount(-1) end)
    ui.countPrev:SetPoint("RIGHT", ui.count, "LEFT", -4, 0)
    for _, b in ipairs({ ui.countPrev, ui.countNext }) do
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText("Balls per drop")
            GameTooltip:AddLine("Drop sends this many balls, each one a bet.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Row 2: drop
    ui.drop = MakeButton(panel, "Drop", 200, Drop, 26)
    ui.drop:SetPoint("BOTTOM", panel, "BOTTOM", 0, 22)

    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 6)

    ui.options = BuildOptions(panel)
    ui.sounds = ns:CreateSoundOptions(panel, "Plinko Options", function() return db end)

    -- Balls that were falling when the game closed are refunded.
    if db.inFlight and db.inFlight > 0 then
        ns:AddChips(db.inFlight)
        SetStatus("Refunded " .. Fmt(db.inFlight) .. " chips for balls still falling.")
        db.inFlight = nil
    else
        SetStatus("Set your bet and drop a ball.")
    end
    DrawBoard()
    Refresh()
end

function Plinko:OnShow()
    if db and InFlight() == 0 and (db.bet < MIN_BET or db.bet > ns.db.chips) then
        db.bet = math.min(25, math.floor(ns.db.chips / MIN_BET) * MIN_BET)
    end
    if ui.board then Refresh() end
end

function Plinko:OnHide()
    if ui.options then ui.options:Hide() end
    if ui.sounds then ui.sounds:Hide() end
end

-- For the out-of-chips check: balls still falling.
function Plinko:ChipsInPlay()
    return InFlight() > 0
end

function Plinko:ResetStats()
    local d = ns.db.plinko
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    if ui.stats and db then Refresh() end
end

-- Exposed for tests.
Plinko.PAYOUTS, Plinko.balls, Plinko.ui, Plinko.last = PAYOUTS, balls, ui, last

ns:RegisterGame(Plinko)
