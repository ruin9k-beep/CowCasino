-- CowCasino: Roulette
-- A single-zero (European) wheel. Pick a chip, then click the layout:
--   on a number ............. straight up (pays 35:1)
--   on the line between two .. split (17:1)
--   where four numbers meet .. corner (8:1)
--   bottom edge of a column .. street, three numbers (11:1)
--   bottom edge between two .. six line (5:1)
--   along the zero ........... 0-1, 0-2, 0-3 splits, the 0-1-2 / 0-2-3 trios,
--                              and 0-1-2-3 at the bottom corner (8:1)
-- Outside bets: dozens and columns pay 2:1; red/black, odd/even, 1-18/19-36 pay 1:1.
-- Every bet pays 36/n - 1 for the n numbers it covers, so the house edge is
-- the same 2.7% everywhere. Right-click a bet to take a chip back.
-- A spin is saved the moment it starts, so a reload mid-spin still pays out.

local ns = CowCasino.ns

local DEFAULT_STATS = { spins = 0, wagered = 0, returned = 0, bestWin = 0 }

local CHIP_VALUES = { 1, 5, 25, 100, 500 }
local MAX_SPOT    = 1000         -- most you can put on one spot
local SPIN_TIME   = 4.2          -- seconds the wheel turns
local TURNS       = 3            -- full turns before it lands

-- The board
local CELL_W, CELL_H = 24, 22
local ZERO_W  = 22
local COL_W   = 26               -- the "2 to 1" column bets
local EDGE    = 5                -- pixels from a line that count as "on the line"
local BOARD_X = 8
local GRID_W, GRID_H = CELL_W * 12, CELL_H * 3

-- The wheel strip
local POCKET_W  = 28
local STRIP_W   = 336
local STRIP_H   = 36

-- Pocket order around a European wheel.
local WHEEL = { 0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
                5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26 }
local POCKETS = ns.getn(WHEEL)

local RED = {}
for _, n in ipairs({ 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36 }) do RED[n] = true end

local COLORS = {
    red   = { 0.70, 0.08, 0.08 },
    black = { 0.10, 0.10, 0.10 },
    green = { 0.05, 0.50, 0.15 },
}
local function ColorOf(n)
    if n == 0 then return "green" end
    return RED[n] and "red" or "black"
end
local COLOR_WORDS = { red = "|cffff4040Red|r", black = "Black", green = "|cff40ff40Green|r" }

local Game = {
    id = "roulette",
    name = "Roulette",
    description = "Single-zero wheel. Straight up pays 35 to 1.",
    icon = "Interface\\AddOns\\CowCasino\\Art\\RouletteIcon",   -- painted (dev/art-src/make_game_icons.py)
}

local db          -- ns.db.roulette
local ui = {}
local S = {
    bets = {},        -- key -> { nums, amount, label, x, y }
    undo = {},        -- list of actions; each a list of { key, delta, spec }
    chip = 5,
    spinning = false,
    pos = 0,          -- wheel strip position, in pockets
}

local function Fmt(n) return ns:FormatChips(n) end

local function SetStatus(text, r, g, b)
    ui.status:SetText(text or "")
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

---------------------------------------------------------------------------
-- Bets
---------------------------------------------------------------------------
local function Pays(nums) return math.floor(36 / ns.getn(nums) + 0.5) - 1 end

local function TotalBet()
    local t = 0
    for _, b in pairs(S.bets) do t = t + b.amount end
    return t
end

local function Covers(nums, n)
    for _, m in ipairs(nums) do
        if m == n then return true end
    end
    return false
end

local function InsideLabel(nums)
    local n, zero = ns.getn(nums), Covers(nums, 0)
    if n == 1 then return "Straight " .. nums[1] end
    local list = table.concat(nums, "-")
    if n == 2 then return "Split " .. list end
    if n == 3 then return (zero and "Trio " or "Street ") .. list end
    if n == 4 then return (zero and "First four " or "Corner ") .. list end
    return "Six line " .. nums[1] .. "-" .. nums[6]
end

-- The numbers under a point on the number grid (x right, y down, from the
-- grid's top-left corner), and where that bet's chip sits.
-- Columns 1-12 run left to right; the zero is column 0. Rows: 3 is the top
-- row (3, 6, 9 ...), 1 the bottom row (1, 4, 7 ...).
local function Zone(x, y)
    if y >= GRID_H and y < GRID_H + EDGE then y = GRID_H - 1 end   -- just under the bottom row: street line
    if x < 0 or y < 0 or x >= GRID_W or y >= GRID_H then return nil end
    local c = math.floor(x / CELL_W) + 1
    local t = math.floor(y / CELL_H) + 1          -- row from the top
    local ex, ey = x - (c - 1) * CELL_W, y - (t - 1) * CELL_H
    local r = 4 - t
    local cols, rows = { c }, { r }
    local mx, my = (c - 0.5) * CELL_W, (t - 0.5) * CELL_H

    if ex < EDGE then
        cols = { c - 1, c }; mx = (c - 1) * CELL_W
    elseif ex > CELL_W - EDGE and c < 12 then
        cols = { c, c + 1 }; mx = c * CELL_W
    end
    if ey > CELL_H - EDGE and t == 3 then
        rows = { 1, 2, 3 }; my = GRID_H              -- street / six line / first four
    elseif ey < EDGE and t > 1 then
        rows = { r, r + 1 }; my = (t - 1) * CELL_H
    elseif ey > CELL_H - EDGE then
        rows = { r - 1, r }; my = t * CELL_H
    end

    local nums, seen = {}, {}
    for _, col in ipairs(cols) do
        for _, row in ipairs(rows) do
            local n = (col == 0) and 0 or (3 * (col - 1) + row)
            if not seen[n] then
                seen[n] = true
                table.insert(nums, n)
            end
        end
    end
    table.sort(nums)
    return nums, mx, my
end

-- Outside bets
local OUTSIDE = {}
local function Outside(key, label, test)
    local nums = {}
    for n = 1, 36 do
        if test(n) then table.insert(nums, n) end
    end
    OUTSIDE[key] = { nums = nums, label = label }
end
Outside("low", "1 to 18", function(n) return n <= 18 end)
Outside("high", "19 to 36", function(n) return n >= 19 end)
Outside("even", "Even", function(n) return ns.Mod(n, 2) == 0 end)
Outside("odd", "Odd", function(n) return ns.Mod(n, 2) == 1 end)
Outside("red", "Red", function(n) return RED[n] == true end)
Outside("black", "Black", function(n) return not RED[n] end)
Outside("dz1", "1st 12", function(n) return n <= 12 end)
Outside("dz2", "2nd 12", function(n) return n >= 13 and n <= 24 end)
Outside("dz3", "3rd 12", function(n) return n >= 25 end)
Outside("col1", "Column 1-34", function(n) return ns.Mod(n, 3) == 1 end)
Outside("col2", "Column 2-35", function(n) return ns.Mod(n, 3) == 2 end)
Outside("col3", "Column 3-36", function(n) return ns.Mod(n, 3) == 0 end)

-- A bet spot: { key, nums, label, x, y } where x/y place its chip on the board.
local function InsideSpec(nums, mx, my)
    return { key = "n" .. table.concat(nums, "-"), nums = nums, label = InsideLabel(nums),
             x = ZERO_W + mx, y = my }
end

local Refresh, DrawChips

-- Change one or more bets as a single step (for Undo).
local function Apply(changes, record)
    for _, ch in ipairs(changes) do
        local b = S.bets[ch.key]
        if not b then
            b = { nums = ch.spec.nums, label = ch.spec.label, x = ch.spec.x, y = ch.spec.y, amount = 0 }
            S.bets[ch.key] = b
        end
        b.amount = b.amount + ch.delta
        if b.amount <= 0 then S.bets[ch.key] = nil end
    end
    if record then table.insert(S.undo, changes) end
end

local function Place(spec, button)
    if S.spinning then return end
    local b = S.bets[spec.key]
    if button == "RightButton" then
        if not b then return end
        local take = math.min(S.chip, b.amount)
        Apply({ { key = spec.key, delta = -take, spec = spec } }, true)
        ns:Sound("IG_MAINMENU_OPTION")
    else
        local current = b and b.amount or 0
        local add = math.min(S.chip, MAX_SPOT - current, ns.db.chips - TotalBet())
        if add <= 0 then
            if current >= MAX_SPOT then
                SetStatus("That spot is at the " .. Fmt(MAX_SPOT) .. " limit.", 1, 0.35, 0.35)
            else
                SetStatus("Not enough chips for that.", 1, 0.35, 0.35)
            end
            return
        end
        Apply({ { key = spec.key, delta = add, spec = spec } }, true)
        ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        SetStatus(spec.label .. ": " .. Fmt(current + add) .. " (pays " .. Pays(spec.nums) .. " to 1)")
    end
    Refresh()
end

local function Undo()
    local last = table.remove(S.undo)
    if not last then return end
    local back = {}
    for _, ch in ipairs(last) do
        table.insert(back, { key = ch.key, delta = -ch.delta, spec = ch.spec })
    end
    Apply(back, false)
    Refresh()
end

local function ClearBets()
    local changes = {}
    for key, b in pairs(S.bets) do
        table.insert(changes, { key = key, delta = -b.amount, spec = b })
    end
    if ns.getn(changes) == 0 then return end
    Apply(changes, true)
    Refresh()
end

local function DoubleBets()
    local total, changes = TotalBet(), {}
    if total == 0 then return end
    if total * 2 > ns.db.chips then
        SetStatus("Not enough chips to double.", 1, 0.35, 0.35)
        return
    end
    for key, b in pairs(S.bets) do
        if b.amount * 2 > MAX_SPOT then
            SetStatus("Doubling would go over the " .. Fmt(MAX_SPOT) .. " spot limit.", 1, 0.35, 0.35)
            return
        end
        table.insert(changes, { key = key, delta = b.amount, spec = b })
    end
    Apply(changes, true)
    Refresh()
end

local function SpecFromSaved(s)
    return { key = s.key, nums = s.nums, label = s.label, x = s.x, y = s.y }
end

local function Rebet()
    local last = db.lastBets
    if not last or ns.getn(last) == 0 then return end
    local need = 0
    for _, s in ipairs(last) do need = need + s.amount end
    if need > ns.db.chips then
        SetStatus("You need " .. Fmt(need) .. " chips to repeat that.", 1, 0.35, 0.35)
        return
    end
    local changes = {}
    for key, b in pairs(S.bets) do table.insert(changes, { key = key, delta = -b.amount, spec = b }) end
    for _, s in ipairs(last) do table.insert(changes, { key = s.key, delta = s.amount, spec = SpecFromSaved(s) }) end
    Apply(changes, true)
    Refresh()
end

local function SaveBets()
    local list = {}
    for key, b in pairs(S.bets) do
        table.insert(list, { key = key, nums = b.nums, label = b.label, x = b.x, y = b.y, amount = b.amount })
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

---------------------------------------------------------------------------
-- The wheel strip
---------------------------------------------------------------------------
local function DrawStrip()
    local pos = S.pos
    local base = math.floor(pos)
    local frac = pos - base
    for k = -6, 6 do
        local cell = ui.pockets[k + 7]
        local x = (k - frac) * POCKET_W
        local idx = ns.Mod(base + k, POCKETS) + 1
        local n = WHEEL[idx]
        local ax = math.abs(x)
        if ax > STRIP_W / 2 - POCKET_W / 2 then
            cell:Hide()
        else
            cell:ClearAllPoints()
            cell:SetPoint("CENTER", ui.strip, "CENTER", x, 0)
            local col = COLORS[ColorOf(n)]
            cell.bg:SetTexture(col[1], col[2], col[3], 1)
            cell.text:SetText(n)
            local fade = 1
            if ax > STRIP_W / 2 - 2 * POCKET_W then
                fade = math.max(0.15, 1 - (ax - (STRIP_W / 2 - 2 * POCKET_W)) / (1.5 * POCKET_W))
            end
            cell:SetAlpha(fade)
            cell:Show()
        end
    end
end

local function IndexOf(n)
    for i, m in ipairs(WHEEL) do
        if m == n then return i - 1 end
    end
    return 0
end

---------------------------------------------------------------------------
-- Spinning and paying
---------------------------------------------------------------------------
local function StatsText()
    local s = db.stats
    if s.spins == 0 then return "Pick a chip, then click the table to bet." end
    return string.format("Spins %d   Wagered %s   Returned %s   Best win %s",
        s.spins, Fmt(s.wagered), Fmt(s.returned), Fmt(s.bestWin))
end

local function Settle(afterReload)
    local p = db.pending
    if not p then
        S.spinning = false
        S.bets, S.undo = {}, {}   -- they were paid for when the spin started
        Refresh()
        return
    end
    db.pending = nil
    local n = p.result
    local back, staked, winners = 0, 0, {}
    for _, b in ipairs(p.bets) do
        staked = staked + b.amount
        if Covers(b.nums, n) then
            local win = b.amount * (Pays(b.nums) + 1)
            back = back + win
            table.insert(winners, b.label)
        end
    end
    if back > 0 then ns:AddChips(back) end

    local s = db.stats
    s.spins = s.spins + 1
    s.wagered = s.wagered + staked
    s.returned = s.returned + back
    if back - staked > s.bestWin then s.bestWin = back - staked end
    s.counts[n + 1] = (s.counts[n + 1] or 0) + 1

    table.insert(db.history, 1, n)
    while ns.getn(db.history) > 12 do table.remove(db.history) end

    S.pos = IndexOf(n)
    S.result = n
    S.spinning = false
    -- The table is cleared after each spin; Rebet puts the same bets back.
    S.bets, S.undo = {}, {}
    db.lastBets = p.bets

    ui.result:SetText(n .. "  " .. COLOR_WORDS[ColorOf(n)])
    local net = back - staked
    local prefix = afterReload and "The wheel stopped while you were away. " or ""
    if back > 0 then
        local names = table.concat(winners, ", ")
        if string.len(names) > 60 then names = ns.getn(winners) .. " bets" end
        if net > 0 then
            SetStatus(prefix .. "You win " .. Fmt(net) .. "! (" .. names .. ")", 0.25, 1, 0.25)
            ns:Sound(net >= staked * 10 and "UI_EPICLOOT_TOAST" or "LOOT_WINDOW_COIN_SOUND")
        else
            SetStatus(prefix .. names .. " hit - you get " .. Fmt(back) .. " back.", 0.85, 0.85, 0.85)
        end
    else
        SetStatus(prefix .. "No luck - you lose " .. Fmt(staked) .. ".", 1, 0.35, 0.35)
    end
    if ns.db.chips < 1 then SetStatus(ns:LowChipsText(1), 1, 0.35, 0.35) end
    DrawStrip()
    Refresh()
end

local driver = ns.CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
    local t = (GetTime() - S.spinStart) / SPIN_TIME
    if t >= 1 then
        this:Hide()
        Settle(false)
        return
    end
    local eased = 1 - (1 - t) * (1 - t) * (1 - t)
    local before = math.floor(S.pos)
    S.pos = S.spinFrom + S.spinDistance * eased
    if math.floor(S.pos) ~= before and t > 0.6 then ns:Sound("IG_MAINMENU_OPTION") end
    DrawStrip()
end)

local function Spin()
    if S.spinning then return end
    if TotalBet() == 0 and ns.db.chips < 1 then
        SetStatus(ns:LowChipsText(1), 1, 0.35, 0.35)
        return
    end
    local total = TotalBet()
    if total == 0 then
        SetStatus("Place a bet first: pick a chip, then click the table.")
        return
    end
    if not ns:SpendChips(total) then
        SetStatus("Not enough chips for those bets.", 1, 0.35, 0.35)
        return
    end
    local result = math.random(POCKETS) - 1
    db.pending = { result = result, bets = SaveBets() }    -- saved now in case of a reload
    S.spinning = true
    S.result = nil
    S.spinFrom = S.pos
    local target = IndexOf(result)
    S.spinDistance = ns.Mod(target - S.pos, POCKETS) + TURNS * POCKETS
    S.spinStart = GetTime()
    ui.result:SetText("")
    SetStatus("No more bets!")
    ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    driver:Show()
    Refresh()
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function ShowHighlight(nums)
    local on = {}
    if nums then
        for _, n in ipairs(nums) do on[n] = true end
    end
    for n = 0, 36 do ns.SetShown(ui.cells[n].hl, on[n] == true) end
end

local function Hover(spec)
    if not spec then
        ShowHighlight(nil)
        ui.hover:SetText("")
        return
    end
    ShowHighlight(spec.nums)
    local b = S.bets[spec.key]
    local text = spec.label .. " - pays " .. Pays(spec.nums) .. " to 1"
    if b then text = text .. "   |cffffffff(bet " .. Fmt(b.amount) .. ")|r" end
    ui.hover:SetText(text)
end

local function ChipLabel(n)
    if n >= 1000 and ns.Mod(n, 1000) == 0 then return (n / 1000) .. "k" end
    return Fmt(n)
end

function DrawChips()
    local i = 0
    for _, b in pairs(S.bets) do
        i = i + 1
        local m = ui.markers[i]
        if not m then
            m = ns.CreateFrame("Frame", nil, ui.board)
            m:SetWidth(18); m:SetHeight(18)
            m:SetFrameLevel(ui.board:GetFrameLevel() + 10)
            local tex = m:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(m)
            tex:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            m.text = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            m.text:SetPoint("CENTER", m, "CENTER", 0, 0)
            ui.markers[i] = m
        end
        m:ClearAllPoints()
        m:SetPoint("CENTER", ui.board, "TOPLEFT", b.x, -b.y)
        m.text:SetText(ChipLabel(b.amount))
        m:Show()
    end
    for k = i + 1, ns.getn(ui.markers) do ui.markers[k]:Hide() end
end

function Refresh()
    if not ui.status then return end
    ns:UpdateChipsDisplay()
    local total = TotalBet()
    ui.total:SetText("Bet " .. Fmt(total))
    for _, b in ipairs(ui.chipButtons) do
        ns.SetShown(b.selected, b.value == S.chip)
        ns.SetEnabled(b, not S.spinning)
    end
    local idle = not S.spinning
    ns.SetEnabled(ui.spin, idle)
    ns.SetEnabled(ui.undo, idle and ns.getn(S.undo) > 0)
    ns.SetEnabled(ui.clear, idle and total > 0)
    ns.SetEnabled(ui.double, idle and total > 0 and total * 2 <= ns.db.chips)
    ns.SetEnabled(ui.rebet, idle and db.lastBets ~= nil and ns.getn(db.lastBets) > 0)
    DrawChips()

    for i = 1, 12 do
        local cell, n = ui.history[i], db.history[i]
        if n then
            local col = COLORS[ColorOf(n)]
            cell.bg:SetTexture(col[1], col[2], col[3], 1)
            cell.text:SetText(n)
            cell:Show()
        else
            cell:Hide()
        end
    end
    ui.stats:SetText(StatsText())
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

-- A colored box with a label: board cells, pockets, history.
local function MakeBox(parent, w, h, font)
    local f = ns.CreateFrame("Frame", nil, parent)
    f:SetWidth(w); f:SetHeight(h)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.text = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    return f
end

-- A clickable outside spot (or the zero).
local function MakeSpot(x, y, w, h, label, color, spec)
    local b = ns.CreateFrame("Button", nil, ui.board)
    b:SetWidth(w); b:SetHeight(h)
    b:SetPoint("TOPLEFT", ui.board, "TOPLEFT", x, -y)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    bg:SetTexture(color[1], color[2], color[3], 1)
    local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", b, "CENTER", 0, 0)
    text:SetText(label)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetTexture(1, 1, 1, 0.15)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    spec.x, spec.y = x + w / 2, y + h / 2
    b:SetScript("OnClick", function() Place(spec, arg1) end)
    b:SetScript("OnEnter", function() Hover(spec) end)
    b:SetScript("OnLeave", function() Hover(nil) end)
    return b, bg
end

-- Where the cursor is on the number grid, in grid pixels (x right, y down).
local function CursorOnGrid()
    local g = ui.grid
    local scale = g:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local left, top = g:GetLeft(), g:GetTop()
    if not left or not top then return nil end
    return cx / scale - left, top - cy / scale
end

local function GridSpec()
    local x, y = CursorOnGrid()
    if not x then return nil end
    local nums, mx, my = Zone(x, y)
    if not nums then return nil end
    return InsideSpec(nums, mx, my)
end

local function BuildBoard(panel)
    local board = ns.CreateFrame("Frame", nil, panel)
    board:SetWidth(ZERO_W + GRID_W + COL_W); board:SetHeight(GRID_H + 2 * CELL_H)
    board:SetPoint("TOPLEFT", panel, "TOPLEFT", BOARD_X, -80)
    ui.board = board
    ui.markers = {}
    local lines = board:CreateTexture(nil, "BACKGROUND")
    lines:SetAllPoints(board)
    lines:SetTexture(0.85, 0.75, 0.45, 0.9)

    -- Numbers (drawn) with a highlight each
    ui.cells = {}
    for n = 1, 36 do
        local c = math.floor((n - 1) / 3) + 1
        local r = n - 3 * (c - 1)
        local cell = MakeBox(board, CELL_W, CELL_H)
        cell:SetPoint("TOPLEFT", board, "TOPLEFT", ZERO_W + (c - 1) * CELL_W, -(3 - r) * CELL_H)
        local col = COLORS[ColorOf(n)]
        cell.bg:SetTexture(col[1], col[2], col[3], 1)
        cell.text:SetText(n)
        ui.cells[n] = cell
    end
    -- The zero is its own button (straight up); the line along it belongs to the grid.
    local zeroSpec = { key = "n0", nums = { 0 }, label = "Straight 0" }
    local zero = MakeSpot(0, 0, ZERO_W, GRID_H, "0", COLORS.green, zeroSpec)
    ui.cells[0] = { frame = zero }
    for n = 0, 36 do
        local holder = ui.cells[n].frame or ui.cells[n]
        local hl = holder:CreateTexture(nil, "OVERLAY")
        hl:SetAllPoints(holder)
        hl:SetTexture(1, 1, 1, 0.35)
        hl:Hide()
        ui.cells[n].hl = hl
    end

    -- One invisible button over the numbers works out which bet you mean.
    local grid = ns.CreateFrame("Button", nil, board)
    grid:SetWidth(GRID_W); grid:SetHeight(GRID_H + EDGE)
    grid:SetPoint("TOPLEFT", board, "TOPLEFT", ZERO_W, 0)
    grid:SetFrameLevel(board:GetFrameLevel() + 5)
    grid:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ui.grid = grid
    grid:SetScript("OnClick", function()
        local spec = GridSpec()
        if spec then Place(spec, arg1) end
        Hover(GridSpec())
    end)
    grid:SetScript("OnEnter", function() this.hovering = true end)
    grid:SetScript("OnLeave", function()
        this.hovering = false
        ui.lastHover = nil
        Hover(nil)
    end)
    grid:SetScript("OnUpdate", function()
        if not this.hovering then return end
        local spec = GridSpec()
        local key = spec and spec.key
        if key ~= ui.lastHover then
            ui.lastHover = key
            Hover(spec)
        end
    end)

    -- Columns (2 to 1), right of each row
    local colKeys = { "col3", "col2", "col1" }
    for t = 1, 3 do
        local key = colKeys[t]
        local o = OUTSIDE[key]
        MakeSpot(ZERO_W + GRID_W, (t - 1) * CELL_H, COL_W, CELL_H, "2:1", COLORS.green,
            { key = key, nums = o.nums, label = o.label })
    end
    -- Dozens
    for d = 1, 3 do
        local key = "dz" .. d
        local o = OUTSIDE[key]
        MakeSpot(ZERO_W + (d - 1) * 4 * CELL_W, GRID_H, 4 * CELL_W, CELL_H, o.label, COLORS.green,
            { key = key, nums = o.nums, label = o.label })
    end
    -- Even-money bets
    local evens = { { "low", "1-18" }, { "even", "Even" }, { "red", "Red" }, { "black", "Black" },
                    { "odd", "Odd" }, { "high", "19-36" } }
    for i, e in ipairs(evens) do
        local o = OUTSIDE[e[1]]
        local color = COLORS.green
        if e[1] == "red" then color = COLORS.red elseif e[1] == "black" then color = COLORS.black end
        MakeSpot(ZERO_W + (i - 1) * 2 * CELL_W, GRID_H + CELL_H, 2 * CELL_W, CELL_H, e[2], color,
            { key = e[1], nums = o.nums, label = o.label })
    end
end

function Game:Build(panel)
    ns.db.roulette = ns.db.roulette or {}
    db = ns.db.roulette
    db.stats = db.stats or {}
    for k, v in pairs(DEFAULT_STATS) do
        if db.stats[k] == nil then db.stats[k] = v end
    end
    db.stats.counts = db.stats.counts or {}
    db.history = db.history or {}
    if db.chip then S.chip = db.chip end

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.05, 0.30, 0.12, 0.90)

    -- Wheel strip
    local strip = ns.CreateFrame("Frame", nil, panel)
    strip:SetWidth(STRIP_W); strip:SetHeight(STRIP_H)
    strip:SetPoint("TOP", panel, "TOP", 0, -6)
    local stripBg = strip:CreateTexture(nil, "BACKGROUND")
    stripBg:SetAllPoints(strip)
    stripBg:SetTexture(0.25, 0.15, 0.05, 1)
    ui.strip = strip
    ui.pockets = {}
    for k = 1, 13 do
        local cell = MakeBox(strip, POCKET_W, STRIP_H - 6, "GameFontNormal")
        cell.text:SetTextColor(1, 1, 1)
        ui.pockets[k] = cell
    end
    local pointer = ns.CreateFrame("Frame", nil, strip)
    pointer:SetWidth(POCKET_W + 4); pointer:SetHeight(STRIP_H + 4)
    pointer:SetPoint("CENTER", strip, "CENTER", 0, 0)
    pointer:SetFrameLevel(strip:GetFrameLevel() + 5)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 2 },
                            { "TOPLEFT", "BOTTOMLEFT", 2, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 2, 0 } }) do
        local edge = pointer:CreateTexture(nil, "OVERLAY")
        edge:SetPoint(side[1], pointer, side[1], 0, 0)
        edge:SetPoint(side[2], pointer, side[2], 0, 0)
        if side[3] > 0 then edge:SetWidth(side[3]) else edge:SetHeight(side[4]) end
        edge:SetTexture(1, 0.82, 0, 1)
    end

    ui.result = ns:BigFont(panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 18)
    ui.result:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -46)
    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -48)
    ui.status:SetWidth(250)
    ui.status:SetJustifyH("RIGHT")

    BuildBoard(panel)

    -- Chips
    ui.chipButtons = {}
    local x = BOARD_X
    for _, v in ipairs(CHIP_VALUES) do
        local v = v   -- own copy for closures (Lua 5.0)
        local b = MakeButton(panel, tostring(v), 42, function()
            S.chip = v
            db.chip = v
            Refresh()
        end, 24)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -198)
        b.value = v
        b.selected = b:CreateTexture(nil, "OVERLAY")
        b.selected:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 4, 1)
        b.selected:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -4, 1)
        b.selected:SetHeight(3)
        b.selected:SetTexture(1, 0.82, 0, 1)
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText("Chip " .. v)
            GameTooltip:AddLine("Click the table to bet it. Right-click a bet to take a chip back.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(ui.chipButtons, b)
        x = x + 46
    end
    ui.total = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.total:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -203)

    -- Actions
    ui.spin = MakeButton(panel, "Spin", 96, Spin, 28)
    ui.spin:SetPoint("TOPLEFT", panel, "TOPLEFT", BOARD_X, -232)
    ui.rebet = MakeButton(panel, "Rebet", 60, Rebet, 24)
    ui.rebet:SetPoint("LEFT", ui.spin, "RIGHT", 6, 0)
    ui.double = MakeButton(panel, "Double", 60, DoubleBets, 24)
    ui.double:SetPoint("LEFT", ui.rebet, "RIGHT", 4, 0)
    ui.undo = MakeButton(panel, "Undo", 54, Undo, 24)
    ui.undo:SetPoint("LEFT", ui.double, "RIGHT", 4, 0)
    ui.clear = MakeButton(panel, "Clear", 54, ClearBets, 24)
    ui.clear:SetPoint("LEFT", ui.undo, "RIGHT", 4, 0)

    ui.hover = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.hover:SetPoint("TOPLEFT", panel, "TOPLEFT", BOARD_X, -266)
    ui.hover:SetWidth(336)
    ui.hover:SetJustifyH("LEFT")

    -- Recent numbers
    local recent = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recent:SetPoint("TOPLEFT", panel, "TOPLEFT", BOARD_X, -292)
    recent:SetText("Recent")
    ui.history = {}
    for i = 1, 12 do
        local cell = MakeBox(panel, 22, 18)
        cell:SetPoint("TOPLEFT", panel, "TOPLEFT", BOARD_X + 46 + (i - 1) * 24, -288)
        cell:Hide()
        ui.history[i] = cell
    end

    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 8)
    ui.stats:SetWidth(340)

    S.pos = db.history[1] and IndexOf(db.history[1]) or math.random(POCKETS) - 1
    DrawStrip()

    local p = db.pending
    if p and (type(p.result) ~= "number" or type(p.bets) ~= "table") then
        db.pending = nil
    elseif p then
        Settle(true)      -- the wheel was turning when the game reloaded
        return
    end
    SetStatus(ns.db.chips >= 1 and "Place your bets." or ns:LowChipsText(1))
    Refresh()
end

function Game:OnShow()
    if ui.status then Refresh() end
end

function Game:OnHide()
    if ui.grid then
        ui.grid.hovering = false
        Hover(nil)
    end
end

-- Exposed for tests.
Game.S, Game.WHEEL, Game.OUTSIDE, Game.ui = S, WHEEL, OUTSIDE, ui
Game.Zone, Game.Pays, Game.ColorOf, Game.InsideSpec, Game.Place = Zone, Pays, ColorOf, InsideSpec, Place

-- For the out-of-chips check: the wheel is turning or waiting to pay (reloads).
function Game:ChipsInPlay()
    local d = ns.db.roulette
    return S.spinning or (d ~= nil and d.pending ~= nil)
end

-- A fresh stack after running out (Core.lua): stats start over. (The strip
-- of recent numbers is the wheel's, not yours, so it stays.)
function Game:ResetStats()
    local d = ns.db.roulette
    if not d then return end
    d.stats = { counts = {} }
    for k, v in pairs(DEFAULT_STATS) do d.stats[k] = v end
end

ns:RegisterGame(Game)
