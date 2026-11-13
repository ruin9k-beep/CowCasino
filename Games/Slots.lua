-- CowCasino: Slots
-- Three slot machines, picked in Slots' Options:
--   3x3  three reels, three rows, five lines (the rows and both diagonals)
--   5x4  five reels, four rows, ten lines (the rows plus zigzags)
--   5x5  five reels, five rows, fifteen lines (the rows plus zigzags)
-- A line pays when the same symbol runs from the leftmost reel: three or
-- more (cherries also pay for two).
-- Modern features:
--   Wilds (not on the first reel) stand in for any symbol on a line, and
--     each one lands with a 2x, 3x or 5x multiplier for the lines it's on.
--   Scatters pay anywhere on the reels: three of them pay and start free
--     spins, at the bet that won them. Each winning free spin raises the
--     multiplier on the next one (x1, x2, then x3), and three more scatters
--     add five more spins.
--   Big wins get a count-up and a banner; Auto spins a run of paid spins.
-- Every reel's cells see the same symbol mix whatever the line shape, so
-- every line has the same odds. Each machine returns about 95% over time,
-- free spins included (dev/art-src/slots-math has the working).
-- Symbols are drawn by the selected slot theme (SlotArt.lua); themes change
-- the look only. Wild and scatter look the same in every theme.
-- A spin is saved the moment it starts, and free spins are saved as they're
-- won, so a reload never loses either.

local ns = CowCasino.ns

local AREA_W = 352
local TICK = 0.05                                -- seconds per symbol while spinning
local STOP_TIMES = { 0.6, 0.9, 1.2, 1.5, 1.8 }   -- when each reel stops
local LINE_BETS = { 1, 2, 5, 10, 20 }            -- bet per line

-- Paylines: the row (1 top ... last bottom) used on each reel.
local LINES_3x3 = {
    { 1, 1, 1 },         -- 1-3: straight rows
    { 2, 2, 2 },
    { 3, 3, 3 },
    { 1, 2, 3 },         -- 4-5: diagonals
    { 3, 2, 1 },
}
local LINES_5x4 = {
    { 1, 1, 1, 1, 1 },   -- 1-4: straight rows
    { 2, 2, 2, 2, 2 },
    { 3, 3, 3, 3, 3 },
    { 4, 4, 4, 4, 4 },
    { 1, 2, 3, 2, 1 },   -- 5-8: Vs
    { 4, 3, 2, 3, 4 },
    { 2, 3, 4, 3, 2 },
    { 3, 2, 1, 2, 3 },
    { 2, 1, 1, 1, 2 },   -- 9-10: shallow arches
    { 3, 4, 4, 4, 3 },
}
local LINES_5x5 = {
    { 1, 1, 1, 1, 1 },   -- 1-5: straight rows
    { 2, 2, 2, 2, 2 },
    { 3, 3, 3, 3, 3 },
    { 4, 4, 4, 4, 4 },
    { 5, 5, 5, 5, 5 },
    { 1, 2, 3, 2, 1 },   -- 6-9: Vs
    { 5, 4, 3, 4, 5 },
    { 2, 3, 4, 3, 2 },
    { 4, 3, 2, 3, 4 },
    { 1, 2, 3, 4, 5 },   -- 10-11: diagonals
    { 5, 4, 3, 2, 1 },
    { 2, 1, 1, 1, 2 },   -- 12-15: shallow arches
    { 4, 5, 5, 5, 4 },
    { 3, 2, 2, 2, 3 },
    { 3, 4, 4, 4, 3 },
}

-- Reel strips. Each reel: 1 seven, 2 bars, 3 bells, 4 plums, 5 oranges,
-- 6 lemons and 6 cherries, plus a wild on every reel but the first, and two
-- scatters on the reels that carry them (5 reels: 1, 3 and 5; 3 reels: all).
-- The scatters on a reel sit far enough apart that only one shows at a time.
local STRIPS_5 = {
    {
        "cherry", "seven", "bell", "plum", "cherry", "lemon", "scatter", "orange", "plum", "orange", "cherry",
        "bar", "lemon", "orange", "lemon", "plum", "lemon", "bell", "plum", "lemon", "cherry", "scatter",
        "lemon", "cherry", "orange", "bell", "cherry", "bar", "orange",
    },
    {
        "cherry", "lemon", "bell", "lemon", "plum", "seven", "orange", "bar", "cherry", "bell", "plum",
        "orange", "cherry", "lemon", "plum", "cherry", "wild", "plum", "orange", "lemon", "cherry", "orange",
        "cherry", "lemon", "bar", "lemon", "bell", "orange",
    },
    {
        "cherry", "scatter", "seven", "orange", "cherry", "lemon", "plum", "lemon", "bell", "lemon", "plum",
        "wild", "orange", "lemon", "plum", "cherry", "bar", "bell", "cherry", "bell", "plum", "scatter", "bar",
        "lemon", "orange", "lemon", "cherry", "orange", "cherry", "orange",
    },
    {
        "plum", "cherry", "lemon", "orange", "plum", "cherry", "orange", "seven", "bell", "cherry", "lemon",
        "plum", "cherry", "plum", "bell", "bar", "orange", "cherry", "lemon", "bar", "lemon", "bell", "wild",
        "orange", "lemon", "cherry", "orange", "lemon",
    },
    {
        "seven", "plum", "lemon", "cherry", "lemon", "bar", "orange", "scatter", "lemon", "cherry", "bell",
        "lemon", "orange", "cherry", "lemon", "cherry", "plum", "wild", "bell", "orange", "plum", "cherry",
        "bell", "cherry", "orange", "plum", "lemon", "scatter", "bar", "orange",
    },
}
local STRIPS_3 = {
    {
        "cherry", "seven", "bell", "plum", "cherry", "lemon", "scatter", "orange", "plum", "orange", "cherry",
        "bar", "lemon", "orange", "lemon", "plum", "lemon", "bell", "plum", "lemon", "cherry", "scatter",
        "lemon", "cherry", "orange", "bell", "cherry", "bar", "orange",
    },
    {
        "cherry", "lemon", "bell", "lemon", "plum", "seven", "orange", "wild", "bar", "cherry", "bell", "plum",
        "orange", "cherry", "lemon", "plum", "cherry", "scatter", "plum", "orange", "lemon", "cherry",
        "orange", "cherry", "lemon", "bar", "lemon", "scatter", "bell", "orange",
    },
    {
        "cherry", "scatter", "seven", "orange", "cherry", "lemon", "plum", "lemon", "bell", "lemon", "plum",
        "wild", "orange", "lemon", "plum", "cherry", "bar", "bell", "cherry", "bell", "plum", "scatter", "bar",
        "lemon", "orange", "lemon", "cherry", "orange", "cherry", "orange",
    },
}

-- Pays per line, as multiples of the line bet, by how many in a row from
-- the left (wilds count as the symbol and multiply the pay).
-- Five reels:
local PAYS_5 = {
    seven  = { [3] = 20, [4] = 80, [5] = 500 },
    bar    = { [3] = 10, [4] = 40, [5] = 150 },
    bell   = { [3] = 8,  [4] = 20, [5] = 80 },
    plum   = { [3] = 4,  [4] = 13, [5] = 40 },
    orange = { [3] = 4,  [4] = 9,  [5] = 25 },
    lemon  = { [3] = 3,  [4] = 6,  [5] = 20 },
    cherry = { [2] = 1,  [3] = 4,  [4] = 10, [5] = 25 },
}

-- Three reels:
local PAYS_3 = {
    seven  = { [3] = 250 },
    bar    = { [3] = 65 },
    bell   = { [3] = 26 },
    plum   = { [3] = 16 },
    orange = { [3] = 8 },
    lemon  = { [3] = 3 },
    cherry = { [2] = 1, [3] = 5 },
}

-- Wild multipliers: each wild that lands picks one (2x most often).
local WILD_MULTS = { 2, 2, 2, 2, 2, 2, 3, 3, 3, 5 }
local FREE_MULT_MAX = 3      -- free spin multiplier: x1, then +1 per winning free spin
local RETRIGGER     = 5      -- free spins added by three scatters during free spins
local MAX_WIN       = 5000   -- most one spin can pay, in total bets
local BIG_WINS = { { 50, "EPIC WIN!" }, { 25, "MEGA WIN!" }, { 10, "BIG WIN!" } }   -- times the total bet
local AUTO_CHOICES = { 10, 25, 50, 100 }

-- scatterPay: line bets paid for three scatters; freeSpins: spins they start.
local MACHINES = {
    { id = "3x3", name = "3 x 3", reels = 3, rows = 3, reelW = 80, rowH = 60, gap = 8, lines = LINES_3x3, pays = PAYS_3,
      strips = STRIPS_3, scatterPay = 25, freeSpins = 14 },
    { id = "5x4", name = "5 x 4", reels = 5, rows = 4, reelW = 60, rowH = 46, gap = 6, lines = LINES_5x4, pays = PAYS_5,
      strips = STRIPS_5, scatterPay = 20, freeSpins = 12 },
    { id = "5x5", name = "5 x 5", reels = 5, rows = 5, reelW = 60, rowH = 37, gap = 6, lines = LINES_5x5, pays = PAYS_5,
      strips = STRIPS_5, scatterPay = 36, freeSpins = 5 },
}
local DEFAULT_MACHINE = "5x4"
local function MachineById(id)
    for _, m in ipairs(MACHINES) do
        if m.id == id then return m end
    end
end

-- The machine in use; set by UseMachine.
local M
local REELS, ROWS, REEL_W, ROW_H, REEL_GAP, LINES, PAYS, STRIPS

local COUNT_WORDS = { "One", "Two", "Three", "Four", "Five" }

local DEFAULT_STATS = { spins = 0, wagered = 0, won = 0, biggestWin = 0, jackpots = 0, freeRounds = 0 }

local Slots = {
    id = "slots",
    name = "Slots",
    description = "Three slot machines: 3x3, 5x4 and 5x5 reels (pick in Options).",
    icon = "Interface\\AddOns\\CowCasino\\Art\\SlotsIcon",   -- painted (dev/art-src/make_game_icons.py)
}

local db      -- ns.db.slots
local ui = {}
local S = {
    spinning = false,
    autoLeft = 0,           -- paid spins Auto still has to go
    waiting = false,        -- an auto or free spin is about to start
    pos = { 1, 1, 1, 1, 1 },   -- strip index showing in row 2 of each reel
    stopped = { true, true, true, true, true },
    t = 0, tick = 0,
    recent = {},            -- net chips of the last spins, newest first
}

local function Sound(key) ns:Sound(key) end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function Fmt(n) return ns:FormatChips(n) end

local function LineBet() return LINE_BETS[db.betIndex] end
local function TotalBet() return LineBet() * ns.getn(LINES) end

local function Wrap(i, n) return ns.Mod(i - 1, n) + 1 end

---------------------------------------------------------------------------
-- Paying out
---------------------------------------------------------------------------
-- The symbol in a given row of a reel stopped at `stop` (row 2 is the stop itself;
-- row 1 is the stop before it, rows 3 and 4 the ones after).
local function SymbolAt(reel, stop, row)
    local strip = STRIPS[reel]
    return strip[Wrap(stop + row - 2, ns.getn(strip))]
end

-- One payline. symbols[r] is the symbol on reel r, wildMults[r] the
-- multiplier of a wild there. Returns the pay (in line bets), the symbol,
-- how many in a row, and the wild multiplier it got.
local function EvaluateLine(symbols, wildMults)
    local first = symbols[1]
    if not PAYS[first] then return 0, first, 0, 1 end   -- a scatter starts no line
    local count, mult = 1, 1
    for r = 2, ns.getn(symbols) do
        local s = symbols[r]
        if s ~= first and s ~= "wild" then break end
        count = count + 1
        if s == "wild" then mult = mult * ((wildMults and wildMults[r]) or 1) end
    end
    local pay = PAYS[first][count]
    if not pay then return 0, first, count, 1 end
    return pay * mult, first, count, mult
end

-- Whole spin: line pays (in line bets), the winning lines, and the scatters
-- in view. wilds[r][row] is the multiplier of each wild showing.
local function EvaluateSpin(stops, wilds)
    local total, wins = 0, {}
    for li, line in ipairs(LINES) do
        local symbols, mults = {}, {}
        for r = 1, REELS do
            symbols[r] = SymbolAt(r, stops[r], line[r])
            mults[r] = wilds and wilds[r] and wilds[r][line[r]] or 2
        end
        local pay, sym, count, wm = EvaluateLine(symbols, mults)
        if pay > 0 then
            total = total + pay
            table.insert(wins, { line = li, mult = pay, symbol = sym, count = count, wild = wm })
        end
    end
    local scatters = {}
    for r = 1, REELS do
        for row = 1, ROWS do
            if SymbolAt(r, stops[r], row) == "scatter" then table.insert(scatters, { r, row }) end
        end
    end
    return total, wins, scatters
end

-- A multiplier for every wild in view (saved with the spin).
local function RollWilds(stops)
    local wilds = {}
    for r = 1, REELS do
        for row = 1, ROWS do
            if SymbolAt(r, stops[r], row) == "wild" then
                wilds[r] = wilds[r] or {}
                wilds[r][row] = WILD_MULTS[math.random(ns.getn(WILD_MULTS))]
            end
        end
    end
    return wilds
end

local function WinText(w)
    return string.format("Line %d: %s %s%s", w.line, COUNT_WORDS[w.count], ns:SlotSymbolName(w.symbol, w.count > 1),
        (w.wild and w.wild > 1) and (" (wild x" .. w.wild .. ")") or "")
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function SetStatus(text, r, g, b)
    ui.status:SetText(text)
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

-- What the status line says between spins.
local function StatsText()
    return "Pick a line bet and spin. All " .. ns.getn(LINES) .. " lines pay on every spin."
end

-- The stats line along the bottom, like the other games. Spins counts free
-- spins too; net is everything won (free spins included) less every bet.
local function BottomStats()
    local s = db.stats
    local net = s.won - s.wagered
    local netText = (net > 0 and ("|cff40ff40+" .. Fmt(net))) or (net < 0 and ("|cffff5050-" .. Fmt(-net))) or "|cffcccccc0"
    return string.format("Spins %d  Biggest win %s  Free spin rounds %d  Net %s|r",
        s.spins, Fmt(s.biggestWin), s.freeRounds, netText)
end

local function InFree() return db.free ~= nil and db.free.machine == M.id end

local function DrawReel(r)
    local cells = ui.reels[r].cells
    for row = 1, ROWS do cells[row]:SetSymbol(SymbolAt(r, S.pos[r], row)) end
end

-- Wild multipliers on the wilds showing (none while the reels turn).
local function SetBadges(wilds)
    for r = 1, REELS do
        local reel = ui.reels[r]
        for row = 1, ROWS do
            local m = wilds and wilds[r] and wilds[r][row]
            if m and S.stopped[r] then
                reel.badges[row]:SetText("x" .. m)
                reel.badges[row]:Show()
            else
                reel.badges[row]:Hide()
            end
        end
    end
end

-- Light every cell on a winning line's run, and every scatter that paid.
local function SetLit(wins, scatters)
    for r = 1, REELS do
        for row = 1, ROWS do ui.reels[r].glows[row]:Hide() end
    end
    for _, w in ipairs(wins or {}) do
        local line = LINES[w.line]
        for r = 1, w.count do ui.reels[r].glows[line[r]]:Show() end
    end
    for _, c in ipairs(scatters or {}) do ui.reels[c[1]].glows[c[2]]:Show() end
end

-- The last few spins along a line, newest on the left: what each one won or
-- lost after its bet (a free spin costs nothing, so it shows its whole win).
local RECENT_SHOWN = 6
local function RecentText()
    local parts = {}
    for i = 1, math.min(RECENT_SHOWN, ns.getn(S.recent)) do
        local n = S.recent[i]
        local text = (n > 0 and ("|cff40ff40+" .. Fmt(n))) or (n < 0 and ("|cffff7070-" .. Fmt(-n))) or "|cffaaaaaa0"
        table.insert(parts, text .. "|r")
    end
    return table.concat(parts, "  ")
end

local function Refresh()
    for r = 1, REELS do DrawReel(r) end

    local chips = ns.db.chips
    local free = InFree()
    ui.bet:SetText(string.format("%d x %d lines = |cffffffff%s|r", free and db.free.lineBet or LineBet(), ns.getn(LINES),
        Fmt((free and db.free.lineBet or LineBet()) * ns.getn(LINES))))
    local locked = S.spinning or free or S.autoLeft > 0
    ns.SetEnabled(ui.lower, not locked and db.betIndex > 1)
    ns.SetEnabled(ui.raise, not locked and db.betIndex < ns.getn(LINE_BETS))
    ns.SetEnabled(ui.max, not locked)

    if S.spinning then
        ui.spin:SetText("Stop")
        ns.SetEnabled(ui.spin, true)
    elseif free then
        ui.spin:SetText("Free spin")
        ns.SetEnabled(ui.spin, not S.waiting)
    else
        ui.spin:SetText("Spin")
        ns.SetEnabled(ui.spin, chips >= TotalBet() and not S.waiting)
    end
    if S.autoLeft > 0 then
        ui.auto:SetText("Stop (" .. S.autoLeft .. ")")
        ns.SetEnabled(ui.auto, true)
    else
        ui.auto:SetText("Auto " .. db.autoCount)
        ns.SetEnabled(ui.auto, not S.spinning and not free and chips >= TotalBet())
    end

    if free then
        ui.topPay:SetText(string.format("|cff66ccffFREE SPINS|r  %d left  -  |cffffd100x%d|r on the next win",
            db.free.left, db.free.mult))
        ui.felt:SetTexture(0.18, 0.06, 0.30, 0.94)
    else
        ui.topPay:SetText(COUNT_WORDS[REELS] .. " " .. ns:SlotSymbolName("seven", true) .. " pay |cffffd100"
            .. Fmt(LineBet() * PAYS.seven[REELS]) .. "|r   Wilds 2x-5x")
        ui.felt:SetTexture(0.25, 0.05, 0.08, 0.92)
    end
    ui.stats:SetText(BottomStats())
    ui.history:SetText(RecentText())
    ns:UpdateChipsDisplay()
    if ui.paytable and ui.paytable:IsShown() then ui.paytable:Refresh() end
end

-- The win counts up from zero, with a banner for the big ones.
local function ShowWin(win, label)
    S.count = { target = win, shown = 0, t = 0, label = label }
    ui.counter:Show()
end

---------------------------------------------------------------------------
-- Spinning
---------------------------------------------------------------------------
local Spin
local NEXT_DELAY = 0.7       -- seconds between auto and free spins
local BIG_DELAY  = 2.5       -- ...after a big win or the free spins starting

-- Free spins and Auto keep going on their own, a moment after each spin.
local function Continue(delay)
    if not InFree() and S.autoLeft <= 0 then return end
    S.waiting = true
    S.next = (S.next or 0) + 1
    local token = S.next
    ns:After(delay, function()
        if S.next ~= token then return end
        S.waiting = false
        if S.spinning then return end
        if InFree() then
            Spin()
        elseif S.autoLeft > 0 then
            if ns.db.chips >= TotalBet() then
                Spin()
            else
                S.autoLeft = 0
                SetStatus("Auto stopped: not enough chips for the bet.", 1, 0.35, 0.35)
                Refresh()
            end
        else
            Refresh()
        end
    end)
end

local function Settle(quiet)
    local pending = db.pending
    if not pending then return end
    db.pending = nil

    local lineTotal, wins, scatters = EvaluateSpin(pending.stops, pending.wilds)
    local nScatter = ns.getn(scatters)
    local scatterPay = (nScatter >= 3) and M.scatterPay or 0
    local freeMult = pending.freeMult or 1
    local totalBet = pending.lineBet * pending.lines
    local win = math.min(pending.lineBet * (lineTotal + scatterPay) * freeMult, totalBet * MAX_WIN)
    local s = db.stats
    local jackpot = false
    for _, w in ipairs(wins) do
        if w.symbol == "seven" and w.count == REELS then jackpot = true end
    end
    if win > 0 then
        ns:AddChips(win)
        s.won = s.won + win
        if win > s.biggestWin then s.biggestWin = win end
    end
    if jackpot then s.jackpots = s.jackpots + 1 end
    table.insert(S.recent, 1, win - (pending.free and 0 or totalBet))
    if ns.getn(S.recent) > 12 then table.remove(S.recent) end

    -- free spins: count this one, raise the multiplier, add more on scatters
    local started, retriggered, finished
    if pending.free and db.free then
        db.free.won = db.free.won + win
        if win > 0 then db.free.mult = math.min(FREE_MULT_MAX, db.free.mult + 1) end
        if nScatter >= 3 then
            db.free.left = db.free.left + RETRIGGER
            retriggered = true
        end
        if db.free.left <= 0 then
            finished = db.free.won
            db.free = nil
        end
    elseif nScatter >= 3 then
        db.free = { left = M.freeSpins, lineBet = pending.lineBet, mult = 1, won = 0, machine = M.id }
        s.freeRounds = s.freeRounds + 1
        started = true
    end

    SetLit(wins, nScatter >= 3 and scatters or nil)
    SetBadges(pending.wilds)
    S.lastWilds = pending.wilds

    -- what to say
    local label
    for _, b in ipairs(BIG_WINS) do
        if not label and win >= totalBet * b[1] then label = b[2] end
    end
    if jackpot then label = "JACKPOT!" end
    local msg
    if ns.getn(wins) == 1 then
        msg = WinText(wins[1]) .. " pays " .. wins[1].mult .. "x."
    elseif ns.getn(wins) > 1 then
        local parts = {}
        for i = 1, math.min(2, ns.getn(wins)) do parts[i] = WinText(wins[i]) end
        msg = ns.getn(wins) .. " lines win! " .. table.concat(parts, ", ") .. (ns.getn(wins) > 2 and ", ..." or "")
    end
    if nScatter >= 3 then
        msg = (msg and (msg .. " ") or "") .. "Three scatters pay " .. scatterPay .. "x."
    end
    if freeMult > 1 and win > 0 then msg = msg .. " All x" .. freeMult .. "!" end
    if started then
        msg = (msg and (msg .. " ") or "") .. "|cff66ccff" .. M.freeSpins .. " FREE SPINS!|r"
    elseif retriggered then
        msg = msg .. " |cff66ccff+" .. RETRIGGER .. " free spins!|r"
    end
    if finished then
        msg = (msg and (msg .. " ") or "") .. "Free spins over: they paid " .. Fmt(finished) .. "."
    end

    if win > 0 then
        ShowWin(win, label)
        if quiet then msg = "Your last spin landed: " .. msg end
        SetStatus(msg, 0.3, 1, 0.3)
        if not quiet then
            Sound((label or started) and "UI_EPICLOOT_TOAST" or "LOOT_WINDOW_COIN_SOUND")
        end
    else
        ui.win:SetText("")
        ui.banner:SetText("")
        if msg then
            SetStatus(msg, 0.4, 0.8, 1)
        else
            SetStatus(quiet and "Your last spin didn't pay." or "No win. Spin again?", 0.8, 0.8, 0.8)
        end
        if started and not quiet then Sound("UI_EPICLOOT_TOAST") end
    end

    if not db.free then
        while db.betIndex > 1 and TotalBet() > ns.db.chips do db.betIndex = db.betIndex - 1 end
        if ns.db.chips < LINE_BETS[1] * ns.getn(LINES) and S.autoLeft <= 0 then
            SetStatus(ns:LowChipsText(LINE_BETS[1] * ns.getn(LINES)), 1, 0.35, 0.35)
        end
    end
    Refresh()
    if not quiet then Continue((label or started or finished) and BIG_DELAY or NEXT_DELAY) end
end

local function StopAll()
    for r = 1, REELS do
        if not S.stopped[r] then
            S.stopped[r] = true
            S.pos[r] = db.pending.stops[r]
        end
    end
end

local function OnUpdate(driver, elapsed)
    S.t = S.t + elapsed
    S.tick = S.tick + elapsed
    local step = S.tick >= TICK
    if step then S.tick = 0 end

    local stillSpinning = false
    for r = 1, REELS do
        if not S.stopped[r] then
            if S.t >= STOP_TIMES[r] then
                S.stopped[r] = true
                S.pos[r] = db.pending.stops[r]
                Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            else
                if step then S.pos[r] = Wrap(S.pos[r] - 1, ns.getn(STRIPS[r])) end
                stillSpinning = true
            end
        end
    end
    for r = 1, REELS do DrawReel(r) end
    SetBadges(db.pending and db.pending.wilds)

    if not stillSpinning then
        driver:Hide()
        S.spinning = false
        Settle(false)
    end
end

-- Runs even while the casino window is closed, so a spin always finishes.
local driver = ns.CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function() OnUpdate(this, arg1) end)

-- Counts the win up on screen.
local counter = ns.CreateFrame("Frame")
counter:Hide()
counter:SetScript("OnUpdate", function()
    local c = S.count
    if not c or not ui.win then this:Hide() return end
    c.t = c.t + (arg1 or 0)
    local length = c.label and 1.6 or 0.6
    local f = math.min(1, c.t / length)
    local shown = math.floor(c.target * f + 0.5)
    ui.win:SetText((c.label and "" or "WIN ") .. Fmt(shown))
    ui.win:SetTextColor(0.3, 1, 0.3)
    ui.banner:SetText(c.label or "")
    if f >= 1 then
        S.count = nil
        this:Hide()
    end
end)
ui.counter = counter

function Spin()
    if S.spinning then
        StopAll()       -- "Stop": the next frame lands every reel
        return
    end
    S.next = (S.next or 0) + 1      -- a spin by hand replaces any waiting one
    S.waiting = false
    local free = InFree()
    local lineBet = free and db.free.lineBet or LineBet()
    local total = lineBet * ns.getn(LINES)
    if not free then
        if ns.db.chips < LINE_BETS[1] * ns.getn(LINES) then
            SetStatus(ns:LowChipsText(LINE_BETS[1] * ns.getn(LINES)), 1, 0.35, 0.35)
            S.autoLeft = 0
            Refresh()
            return
        end
        if not ns:SpendChips(total) then
            SetStatus("Not enough chips for that bet - lower it.")
            S.autoLeft = 0
            Refresh()
            return
        end
        if S.autoLeft > 0 then S.autoLeft = S.autoLeft - 1 end
    end

    local stops = {}
    for r = 1, REELS do stops[r] = math.random(ns.getn(STRIPS[r])) end
    -- saved now in case of a reload
    db.pending = { v = 2, lineBet = lineBet, stops = stops, lines = ns.getn(LINES), machine = M.id, wilds = RollWilds(stops) }
    if free then
        db.pending.free = true
        db.pending.freeMult = db.free.mult
        db.free.left = db.free.left - 1
    end

    local s = db.stats
    s.spins = s.spins + 1
    if not free then s.wagered = s.wagered + total end

    S.spinning = true
    S.t, S.tick = 0, 0
    for r = 1, REELS do S.stopped[r] = false end
    SetLit(nil)
    SetBadges(nil)
    S.count = nil
    ui.win:SetText("")
    ui.banner:SetText("")
    SetStatus(free and ("Free spin... x" .. db.free.mult .. " on a win") or "Spinning...")
    Sound("IG_MAINMENU_OPTION")
    Refresh()
    driver:Show()
end

local function ToggleAuto()
    if S.autoLeft > 0 then
        S.autoLeft = 0
        S.next = (S.next or 0) + 1
        S.waiting = false
        SetStatus("Auto stopped.")
        Refresh()
        return
    end
    if S.spinning or InFree() then return end
    S.autoLeft = db.autoCount
    Spin()
end

local function ChangeBet(delta)
    if S.spinning or InFree() then return end
    db.betIndex = math.max(1, math.min(ns.getn(LINE_BETS), db.betIndex + delta))
    Refresh()
end

local function MaxBet()
    if S.spinning or InFree() then return end
    db.betIndex = 1
    for i, v in ipairs(LINE_BETS) do
        if v * ns.getn(LINES) <= ns.db.chips then db.betIndex = i end
    end
    Refresh()
end

---------------------------------------------------------------------------
-- Build helpers
---------------------------------------------------------------------------
local function MakeButton(parent, text, width, onClick, height)
    local b = ns.CreateFrame("Button", ns:NewName(), parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(height or 24)
    b:SetText(text)
    b:SetScript("OnClick", function() local self, button = this, arg1 onClick(self, button) end)
    return b
end

local function BuildReel(machine, r)
    local reel = ns.CreateFrame("Frame", nil, machine)
    reel:SetWidth(REEL_W); reel:SetHeight(ROW_H * ROWS)
    reel:SetPoint("TOPLEFT", reel:GetParent(), "TOPLEFT", (r - 1) * (REEL_W + REEL_GAP), 0)

    local bg = reel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(reel)
    bg:SetTexture(0.93, 0.92, 0.88, 1)

    reel.cells = {}
    for row = 1, ROWS do
        local w = ns:CreateSymbolWidget(reel, REEL_W, ROW_H)
        w:SetPoint("TOPLEFT", w:GetParent(), "TOPLEFT", 0, -(row - 1) * ROW_H)
        w:SetLevel(reel:GetFrameLevel() + 1)
        reel.cells[row] = w
    end

    -- Win glows sit over the symbols.
    local over = ns.CreateFrame("Frame", nil, reel)
    over:SetAllPoints(over:GetParent())
    over:SetFrameLevel(reel:GetFrameLevel() + 10)
    reel.glows = {}
    for row = 1, ROWS do
        local g = over:CreateTexture(nil, "OVERLAY")
        g:SetPoint("TOPLEFT", over, "TOPLEFT", 0, -(row - 1) * ROW_H)
        g:SetWidth(REEL_W); g:SetHeight(ROW_H)
        g:SetTexture(1, 0.85, 0.1, 0.32)
        g:Hide()
        reel.glows[row] = g
    end
    -- a wild's multiplier, in its corner
    reel.badges = {}
    for row = 1, ROWS do
        local b = over:CreateFontString(nil, "OVERLAY")
        b:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.max(9, math.floor(ROW_H * 0.3)), "OUTLINE")
        b:SetTextColor(1, 0.9, 0.2)
        b:SetPoint("BOTTOMRIGHT", over, "TOPRIGHT", -2, -row * ROW_H + 2)
        b:Hide()
        reel.badges[row] = b
    end
    return reel
end

local function IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
    return 1
end

-- One payline drawn as a small reels-by-rows grid, its path lit.
local LINE_CELL_W, LINE_CELL_H, LINE_CELL_GAP = 12, 9, 2
local function LineTileW() return REELS * LINE_CELL_W + (REELS - 1) * LINE_CELL_GAP end
local function LineTileH() return ROWS * LINE_CELL_H + (ROWS - 1) * LINE_CELL_GAP end

local function BuildLineTile(parent, index)
    local LINE_TILE_W, LINE_TILE_H = LineTileW(), LineTileH()
    local tile = ns.CreateFrame("Frame", nil, parent)
    tile:SetWidth(LINE_TILE_W); tile:SetHeight(LINE_TILE_H + 16)
    local label = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", tile, "TOP", 0, 0)
    label:SetText("Line " .. index)
    local line = LINES[index]
    tile.lit = {}
    for r = 1, REELS do
        for row = 1, ROWS do
            local cell = tile:CreateTexture(nil, "ARTWORK")
            cell:SetWidth(LINE_CELL_W); cell:SetHeight(LINE_CELL_H)
            cell:SetPoint("TOPLEFT", tile, "TOPLEFT", (r - 1) * (LINE_CELL_W + LINE_CELL_GAP),
                -16 - (row - 1) * (LINE_CELL_H + LINE_CELL_GAP))
            if line[r] == row then
                cell:SetTexture(0.95, 0.75, 0.2, 1)
                tile.lit[r] = row
            else
                cell:SetTexture(0.22, 0.2, 0.2, 1)
            end
        end
    end
    return tile
end

-- Paytable pages: the pays first, then the winning line shapes, as many
-- pages of them as it takes.
local LINES_COLS, LINES_ROWS = 4, 3
local LINES_PER_PAGE = LINES_COLS * LINES_ROWS

local function BuildPaytable(panel)
    local o = ns.CreateFrame("Frame", nil, panel)
    o:SetAllPoints(o:GetParent())
    o:SetFrameLevel(panel:GetFrameLevel() + 50)
    o:EnableMouse(true)
    o:Hide()

    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0, 0, 0, 0.92)

    local title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", o, "TOP", 0, -8)

    o.pages = {}
    local function NewPage(name)
        local page = ns.CreateFrame("Frame", nil, o)
        page:SetAllPoints(o)
        page:Hide()
        page.title = name
        o.pages[ns.getn(o.pages) + 1] = page
        return page
    end

    -- Page 1: the pays
    local pays = NewPage("Paytable")

    -- Theme picker
    local label = pays:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", pays, "TOPLEFT", 12, -36)
    label:SetText("Symbol theme")
    local nextB = MakeButton(pays, ">", 26, function() o:Cycle(1) end)
    nextB:SetPoint("TOPRIGHT", nextB:GetParent(), "TOPRIGHT", -12, -32)
    local themeName = pays:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    themeName:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    themeName:SetWidth(110)
    themeName:SetJustifyH("CENTER")
    local prevB = MakeButton(pays, "<", 26, function() o:Cycle(-1) end)
    prevB:SetPoint("RIGHT", themeName, "LEFT", -6, 0)

    function o:Cycle(dir)
        local order = ns.slotThemeOrder
        local current = ns:GetSlotTheme()
        local i = IndexOf(order, current and current.id)
        ns:SetSlotTheme(order[ns.Mod(i - 1 + dir, ns.getn(order)) + 1])
        self:Refresh()
    end

    -- Column headings, then one row per symbol: pays for 2/3/4/5 in a row.
    local COLS, COL_X = { 2, 3, 4, 5 }, { 70, 135, 200, 275 }
    if REELS == 3 then COLS, COL_X = { 2, 3 }, { 140, 250 } end
    for i, n in ipairs(COLS) do
        local h = pays:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOP", pays, "TOPLEFT", COL_X[i], -62)
        h:SetText(n .. " in a row")
    end

    local cells = {}
    for i, sym in ipairs(ns.SLOT_SYMBOLS) do
        local y = -76 - (i - 1) * 30
        local w = ns:CreateSymbolWidget(pays, 40, 28)
        w:SetPoint("TOPLEFT", w:GetParent(), "TOPLEFT", 12, y)
        w:SetSymbol(sym.id)
        for c, n in ipairs(COLS) do
            local fs = pays:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetPoint("TOP", pays, "TOPLEFT", COL_X[c], y - 7)
            cells[ns.getn(cells) + 1] = { fs = fs, mult = PAYS[sym.id][n] }
        end
    end

    local note = pays:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOM", pays, "BOTTOM", 0, 42)
    note:SetWidth(AREA_W - 20)

    -- Page 2: wilds, scatters and free spins
    local feat = NewPage("Wilds and free spins")
    local function Feature(y, symbol, text)
        local w = ns:CreateSymbolWidget(feat, 48, 48)
        w:SetPoint("TOPLEFT", feat, "TOPLEFT", 12, y)
        w:SetSymbol(symbol)
        local t = feat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", feat, "TOPLEFT", 70, y)
        t:SetWidth(AREA_W - 84)
        t:SetJustifyH("LEFT")
        t:SetText(text)
        return t
    end
    Feature(-40, "wild", "|cffffd100Wild|r - on every reel but the first. It stands in for any symbol on a line, "
        .. "and lands with a 2x, 3x or 5x multiplier for the lines it's on. Two wilds on one line multiply together.")
    local scatterText = Feature(-112, "scatter", "")
    local freeText = feat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    freeText:SetPoint("TOPLEFT", feat, "TOPLEFT", 12, -190)
    freeText:SetWidth(AREA_W - 24)
    freeText:SetJustifyH("LEFT")

    -- Then the winning lines
    local numLines = ns.getn(LINES)
    local linePages = math.ceil(numLines / LINES_PER_PAGE)
    local LINE_TILE_W, LINE_TILE_H = LineTileW(), LineTileH()
    local stepX = (AREA_W - 24 - LINE_TILE_W) / (LINES_COLS - 1)
    o.lineTiles = {}
    for p = 1, linePages do
        local name = "Winning lines"
        if linePages > 1 then name = name .. " (" .. p .. " of " .. linePages .. ")" end
        local page = NewPage(name)
        local intro = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        intro:SetPoint("TOP", page, "TOP", 0, -34)
        intro:SetWidth(AREA_W - 20)
        intro:SetText("A line pays when the same symbol runs along its path from the left reel. "
            .. "Only these shapes count.")
        for k = 1, LINES_PER_PAGE do
            local index = (p - 1) * LINES_PER_PAGE + k
            if index > numLines then break end
            local col = ns.Mod(k - 1, LINES_COLS)
            local row = math.floor((k - 1) / LINES_COLS)
            local tile = BuildLineTile(page, index)
            tile:SetPoint("TOPLEFT", page, "TOPLEFT", 12 + col * stepX, -70 - row * (LINE_TILE_H + 34))
            o.lineTiles[index] = tile
        end
    end

    -- Page buttons
    local prevPage = MakeButton(o, "< Prev", 70, function() o:ShowPage(o.page - 1) end)
    prevPage:SetPoint("BOTTOMLEFT", prevPage:GetParent(), "BOTTOMLEFT", 12, 10)
    local nextPage = MakeButton(o, "Next >", 70, function() o:ShowPage(o.page + 1) end)
    nextPage:SetPoint("BOTTOMRIGHT", nextPage:GetParent(), "BOTTOMRIGHT", -12, 10)
    local done = MakeButton(o, "Done", 90, function() o:Hide() end)
    done:SetPoint("BOTTOM", done:GetParent(), "BOTTOM", 0, 10)

    function o:ShowPage(n)
        local count = ns.getn(self.pages)
        if n < 1 then n = 1 elseif n > count then n = count end
        self.page = n
        for i, page in ipairs(self.pages) do ns.SetShown(page, i == n) end
        title:SetText(self.pages[n].title)
        ns.SetEnabled(prevPage, n > 1)
        ns.SetEnabled(nextPage, n < count)
    end

    function o:Refresh()
        local theme = ns:GetSlotTheme()
        themeName:SetText(theme and theme.name or "?")
        for _, c in ipairs(cells) do
            c.fs:SetText(c.mult and Fmt(c.mult * LineBet()) or "|cff666666-|r")
        end
        note:SetText(string.format("Wins for a line bet of %d, on each of %d lines. "
            .. "Symbols must run from the left reel; the next pages show the wilds, free spins and line shapes. "
            .. "Returns about 95%% over time.", LineBet(), numLines))
        scatterText:SetText(string.format("|cffffd100Scatter|r - pays anywhere on the reels%s. Three of them pay %s "
            .. "(%dx the line bet) and start %d free spins.", REELS == 5 and " (it's on reels 1, 3 and 5)" or "",
            Fmt(M.scatterPay * LineBet()), M.scatterPay, M.freeSpins))
        freeText:SetText(string.format("|cff66ccffFree spins|r play by themselves at the bet that won them. "
            .. "The first win pays x1, and every win after raises the multiplier for the next one, up to x%d. "
            .. "Three scatters during free spins add %d more. "
            .. "A spin can pay up to %s times the total bet.", FREE_MULT_MAX, RETRIGGER, Fmt(MAX_WIN)))
    end
    o:SetScript("OnShow", function() local self = this self:Refresh() self:ShowPage(1) end)
    return o
end

---------------------------------------------------------------------------
-- Machines
---------------------------------------------------------------------------
-- Point the game at a machine's reels, lines and pays.
local function UseMachine(id)
    M = MachineById(id) or MachineById(DEFAULT_MACHINE)
    REELS, ROWS, REEL_W, ROW_H, REEL_GAP = M.reels, M.rows, M.reelW, M.rowH, M.gap
    LINES, PAYS, STRIPS = M.lines, M.pays, M.strips
end
UseMachine(DEFAULT_MACHINE)

-- The machine: a gold frame around the reels. Built the first time it's used.
local function BuildMachine(panel)
    local machineW = REELS * REEL_W + (REELS - 1) * REEL_GAP
    local machineH = ROWS * ROW_H
    local frame = ns.CreateFrame("Frame", nil, panel)
    frame:SetWidth(machineW + 12); frame:SetHeight(machineH + 12)
    frame:SetPoint("TOP", frame:GetParent(), "TOP", 0, -24)
    local gold = frame:CreateTexture(nil, "BACKGROUND")
    gold:SetAllPoints(frame)
    gold:SetTexture(0.75, 0.58, 0.15, 1)
    local inner = frame:CreateTexture(nil, "BORDER")
    inner:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    inner:SetTexture(0.08, 0.06, 0.06, 1)

    local machine = ns.CreateFrame("Frame", nil, frame)
    machine:SetWidth(machineW); machine:SetHeight(machineH)
    machine:SetPoint("CENTER", machine:GetParent(), "CENTER", 0, 0)
    local reels = {}
    for r = 1, REELS do reels[r] = BuildReel(machine, r) end
    return frame, reels
end

-- Show the machine in use (db.machine), building it if needed.
local function ShowMachine()
    UseMachine(db.machine)
    db.machine = M.id
    for _, m in ipairs(MACHINES) do
        if m.frame and m ~= M then m.frame:Hide() end
        if m.paytable and m ~= M then m.paytable:Hide() end
    end
    if not M.frame then
        M.frame, M.reelFrames = BuildMachine(ui.panel)
        M.paytable = BuildPaytable(ui.panel)
    end
    M.frame:Show()
    ui.reels, ui.paytable = M.reelFrames, M.paytable
    ui.win:ClearAllPoints()
    ui.win:SetPoint("TOP", M.frame, "BOTTOM", 0, -4)
    ui.status:ClearAllPoints()
    ui.status:SetPoint("TOP", M.frame, "BOTTOM", 0, -26)
    ui.banner:ClearAllPoints()
    ui.banner:SetPoint("CENTER", M.frame, "CENTER", 0, 0)
    ui.banner:SetText("")
    -- a random resting position for the reels
    for r = 1, REELS do S.pos[r] = math.random(ns.getn(STRIPS[r])) end
    SetLit(nil)
end

---------------------------------------------------------------------------
-- Options: which machine
---------------------------------------------------------------------------
local function BuildOptions(panel)
    local o = ns.CreateFrame("Frame", nil, panel)
    o:SetAllPoints(o:GetParent())
    o:SetFrameLevel(panel:GetFrameLevel() + 60)
    o:EnableMouse(true)
    o:Hide()
    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0, 0, 0, 0.92)

    local title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", o, "TOP", 0, -10)
    title:SetText("Slots Options")

    local label = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -52)
    label:SetText("Reel size")
    local function Step(dir)
        local i = 1
        for k, m in ipairs(MACHINES) do if m.id == Slots:GetMachine() then i = k end end
        i = ns.Mod(i - 1 + dir, ns.getn(MACHINES)) + 1
        Slots:SetMachine(MACHINES[i].id)
        ns:Sound("IG_MAINMENU_OPTION")
        o:Refresh()
    end
    local nextB = MakeButton(o, ">", 26, function() Step(1) end)
    nextB:SetPoint("TOPRIGHT", nextB:GetParent(), "TOPRIGHT", -16, -48)
    local value = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    value:SetWidth(90)
    value:SetJustifyH("CENTER")
    local prevB = MakeButton(o, "<", 26, function() Step(-1) end)
    prevB:SetPoint("RIGHT", value, "LEFT", -6, 0)
    local note = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -10)
    note:SetWidth(AREA_W - 32)
    note:SetJustifyH("LEFT")

    -- How many paid spins Auto plays
    local autoLabel = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -122)
    autoLabel:SetText("Auto spins")
    local function StepAuto(dir)
        local i = IndexOf(AUTO_CHOICES, db.autoCount)
        db.autoCount = AUTO_CHOICES[math.max(1, math.min(ns.getn(AUTO_CHOICES), i + dir))]
        ns:Sound("IG_MAINMENU_OPTION")
        o:Refresh()
        Refresh()
    end
    local autoNext = MakeButton(o, ">", 26, function() StepAuto(1) end)
    autoNext:SetPoint("TOPRIGHT", o, "TOPRIGHT", -16, -118)
    local autoValue = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoValue:SetPoint("RIGHT", autoNext, "LEFT", -6, 0)
    autoValue:SetWidth(90)
    autoValue:SetJustifyH("CENTER")
    local autoPrev = MakeButton(o, "<", 26, function() StepAuto(-1) end)
    autoPrev:SetPoint("RIGHT", autoValue, "LEFT", -6, 0)
    local autoNote = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    autoNote:SetPoint("TOPLEFT", autoLabel, "BOTTOMLEFT", 0, -10)
    autoNote:SetWidth(AREA_W - 32)
    autoNote:SetJustifyH("LEFT")
    autoNote:SetText("Auto plays this many paid spins at your bet, plus any free spins they win. "
        .. "It stops when you press Stop, run short of chips or leave Slots.")

    local done = MakeButton(o, "Done", 90, function() o:Hide() end)
    done:SetPoint("BOTTOM", done:GetParent(), "BOTTOM", 0, 10)

    function o:Refresh()
        local id, name, lines = Slots:GetMachine(), "?", 0
        for _, m in ipairs(MACHINES) do
            if m.id == id then name, lines = m.name, ns.getn(m.lines) end
        end
        value:SetText(name)
        local busy = Slots:ChipsInPlay()
        ns.SetEnabled(prevB, not busy)
        ns.SetEnabled(nextB, not busy)
        note:SetText(busy and "Can be changed once your spin (and any free spins) finish."
            or (lines .. " paylines. Every machine returns about 95% over time, free spins included."))
        autoValue:SetText(db.autoCount .. " spins")
    end
    o:SetScript("OnShow", function() this:Refresh() end)
    return o
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Slots:Build(panel)
    ns.db.slots = ns.db.slots or {}
    db = ns.db.slots
    if db.betIndex == nil or db.betIndex > ns.getn(LINE_BETS) then db.betIndex = 1 end
    db.stats = db.stats or {}
    Fill(db.stats, DEFAULT_STATS)
    db.autoCount = db.autoCount or 25
    -- free spins belong to the machine that won them
    if db.free and MachineById(db.free.machine) then db.machine = db.free.machine end

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.25, 0.05, 0.08, 0.92)
    ui.felt = felt

    -- Options sits in the top bar where the other games have theirs; the
    -- Paytable button is down by Spin (on its left, mirroring Auto).
    ui.options = BuildOptions(panel)
    local optionsButton = MakeButton(panel, "Options", 70, function()
        if ui.paytable then ui.paytable:Hide() end
        ns.SetShown(ui.options, not ui.options:IsShown())
    end, 22)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    ui.topPay = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.topPay:SetPoint("TOP", panel, "TOP", 0, -8)

    ui.win = ns:BigFont(panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 22)
    -- BIG WIN and the like, across the middle of the reels
    ui.banner = ns:BigFont(panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 30)
    ui.banner:SetTextColor(1, 0.85, 0.1)
    ui.banner:SetShadowOffset(2, -2)
    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetWidth(AREA_W - 8)

    -- Bet controls
    local betRow = ns.CreateFrame("Frame", nil, panel)
    betRow:SetWidth(300); betRow:SetHeight(24)
    betRow:SetPoint("BOTTOM", betRow:GetParent(), "BOTTOM", 0, 48)
    ui.lower = MakeButton(betRow, "-", 26, function() ChangeBet(-1) end)
    ui.lower:SetPoint("LEFT", ui.lower:GetParent(), "LEFT", 0, 0)
    ui.bet = betRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.bet:SetPoint("LEFT", ui.lower, "RIGHT", 6, 0)
    ui.bet:SetWidth(150)
    ui.raise = MakeButton(betRow, "+", 26, function() ChangeBet(1) end)
    ui.raise:SetPoint("LEFT", ui.bet, "RIGHT", 6, 0)
    ui.max = MakeButton(betRow, "Max bet", 70, MaxBet)
    ui.max:SetPoint("LEFT", ui.raise, "RIGHT", 10, 0)

    ui.spin = MakeButton(panel, "Spin", 150, function() Spin() end, 28)
    ui.spin:SetPoint("BOTTOM", ui.spin:GetParent(), "BOTTOM", 0, 18)
    ui.auto = MakeButton(panel, "Auto", 80, ToggleAuto, 26)
    ui.auto:SetPoint("LEFT", ui.spin, "RIGHT", 10, 0)
    local paytableButton = MakeButton(panel, "Paytable", 80, function()
        ui.options:Hide()
        ns.SetShown(ui.paytable, not ui.paytable:IsShown())
    end, 26)
    paytableButton:SetPoint("RIGHT", ui.spin, "LEFT", -10, 0)

    -- the last few spins, just above the bet
    ui.history = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.history:SetPoint("BOTTOM", panel, "BOTTOM", 0, 76)

    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 3)

    ui.panel = panel
    ShowMachine()

    local p = db.pending
    if p and not (p.v == 2 and p.stops and ns.getn(p.stops) == REELS and p.lineBet and p.lines == ns.getn(LINES)
            and (p.machine or DEFAULT_MACHINE) == M.id) then
        -- A spin left over from an older machine layout: give the bet back
        -- (a free spin cost nothing, so there's nothing to give back).
        local refund = p.free and 0 or (p.bet or (p.lineBet and p.lineBet * (p.lines or 5)) or 0)
        if refund > 0 then ns:AddChips(refund) end
        db.pending = nil
        ui.win:SetText("")
        SetStatus("The machine has changed since your last spin - that bet was returned.")
    elseif db.pending then
        -- The last spin started but the game reloaded before it stopped.
        for r = 1, REELS do S.pos[r] = db.pending.stops[r] end
        Settle(true)
        if InFree() then Continue(BIG_DELAY) end
    elseif InFree() then
        ui.win:SetText("")
        SetStatus("Welcome back - you have " .. db.free.left .. " free spins to play.", 0.4, 0.8, 1)
        Continue(BIG_DELAY)
    else
        ui.win:SetText("")
        SetStatus(StatsText())
    end
    Refresh()
end

function Slots:OnShow()
    if ui.status and M.id ~= (db.machine or DEFAULT_MACHINE) and not self:ChipsInPlay() then
        ShowMachine()
        ui.win:SetText("")
        SetStatus(StatsText())
    end
    if ui.status then
        if not S.spinning and not InFree() and (ui.win:GetText() or "") == "" then SetStatus(StatsText()) end
        Refresh()
    end
end

function Slots:OnHide()
    if ui.paytable then ui.paytable:Hide() end
    if ui.options then ui.options:Hide() end
    -- Auto stops when you leave; owed free spins carry on
    if S.autoLeft > 0 then
        S.autoLeft = 0
        if not InFree() then S.next = (S.next or 0) + 1; S.waiting = false end
    end
end

-- A fresh stack after running out (Core.lua): stats start over.
function Slots:ResetStats()
    local d = ns.db.slots
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    for i = ns.getn(S.recent), 1, -1 do table.remove(S.recent, i) end
    if ui.stats and db then Refresh() end
end

-- Machine choice, shown in Slots' Options. It can't change while a spin is
-- turning or owed.
Slots.MACHINES = MACHINES
function Slots:GetMachine()
    local d = ns.db.slots
    return (d and MachineById(d.machine) and d.machine) or DEFAULT_MACHINE
end
function Slots:SetMachine(id)
    if not MachineById(id) or self:ChipsInPlay() then return false end
    ns.db.slots = ns.db.slots or {}
    ns.db.slots.machine = id
    if ui.status and ns.currentGame == "slots" then self:OnShow() end
    return true
end

-- Exposed for testing and for anyone curious about the odds.
Slots.STRIPS_5, Slots.STRIPS_3, Slots.PAYS, Slots.LINES = STRIPS_5, STRIPS_3, PAYS_5, LINES_5x4
Slots.PAYS_3, Slots.LINES_3x3, Slots.LINES_5x5 = PAYS_3, LINES_3x3, LINES_5x5
Slots.WILD_MULTS, Slots.FREE_MULT_MAX, Slots.RETRIGGER = WILD_MULTS, FREE_MULT_MAX, RETRIGGER
Slots.S, Slots.ui = S, ui
function Slots:Machine() return M end
Slots.EvaluateLine, Slots.EvaluateSpin, Slots.SymbolAt, Slots.RollWilds = EvaluateLine, EvaluateSpin, SymbolAt, RollWilds

-- Start over (Options) gives up a spin in progress and any free spins owed.
function Slots:Abandon()
    driver:Hide()
    S.spinning, S.autoLeft, S.waiting = false, 0, false
    S.next = (S.next or 0) + 1
    for r = 1, 5 do S.stopped[r] = true end
    local d = ns.db.slots
    if d then d.pending, d.free = nil, nil end
    if ui.status and ui.reels then Refresh() end
end

-- For the out-of-chips check: a spin is turning or waiting to pay (reloads).
function Slots:ChipsInPlay()
    local d = ns.db.slots
    return S.spinning or (d ~= nil and (d.pending ~= nil or d.free ~= nil))
end

ns:RegisterGame(Slots)
