-- CowCasino: Mines
-- A 5x5 board hides 1-24 mines. Every safe tile you uncover raises the
-- multiplier; cash out whenever you like, or hit a mine and lose the bet.
-- Multipliers are the fair odds with a 1% house edge, like the websites.
-- An unfinished game is saved, so a reload or logout doesn't lose it.

local ns = CowCasino.ns

local GRID       = 5
local TILES      = GRID * GRID
local TILE       = 46
local TILE_GAP   = 4
local AREA_W     = 352
local HOUSE_EDGE = 0.01
local MIN_BET, MAX_BET = 5, 1000
local CHIP_VALUES = { 5, 25, 100, 500 }

-- Icon choices for gems and mines, picked in Options. Every icon name was
-- checked on warcraft.wiki.gg. Other addons can add more with
-- CowCasino.AddMinesIcon("gem" or "mine", "Name", "Interface\\Icons\\...").
local ICONS = {
    gem = {
        { name = "Azerothian Diamond", path = "Interface\\Icons\\INV_Misc_Gem_Diamond_01" },
        { name = "Star Ruby",          path = "Interface\\Icons\\INV_Misc_Gem_Ruby_02" },
        { name = "Huge Emerald",       path = "Interface\\Icons\\INV_Misc_Gem_Emerald_01" },
        { name = "Blue Sapphire",      path = "Interface\\Icons\\INV_Misc_Gem_Sapphire_02" },
        { name = "Shadowgem",          path = "Interface\\Icons\\INV_Misc_Gem_Amethyst_01" },
        { name = "Arcane Crystal",     path = "Interface\\Icons\\INV_Misc_Gem_Topaz_01" },
        { name = "Large Opal",         path = "Interface\\Icons\\INV_Misc_Gem_Opal_01" },
        { name = "Black Diamond",      path = "Interface\\Icons\\INV_Misc_Gem_01" },
        { name = "Gold Coin",          path = "Interface\\Icons\\INV_Misc_Coin_01" },
    },
    mine = {
        { name = "Self Destruct",      path = "Interface\\Icons\\Spell_Fire_SelfDestruct" },
        { name = "Big Iron Bomb",      path = "Interface\\Icons\\INV_Misc_Bomb_01" },
        { name = "Mithril Frag Bomb",  path = "Interface\\Icons\\INV_Misc_Bomb_02" },
        { name = "The Big One",        path = "Interface\\Icons\\INV_Misc_Bomb_04" },
        { name = "Dark Iron Bomb",     path = "Interface\\Icons\\INV_Misc_Bomb_05" },
        { name = "Dynamite",           path = "Interface\\Icons\\INV_Misc_Bomb_06" },
        { name = "Iron Grenade",       path = "Interface\\Icons\\INV_Misc_Bomb_08" },
    },
}

-- Board colors. Swap these to restyle the game.
local ART = {
    edge         = { 0.35, 0.38, 0.48, 1 },
    tile         = { 0.17, 0.19, 0.25, 1 },
    safe         = { 0.10, 0.30, 0.16, 1 },
    hit          = { 0.55, 0.08, 0.08, 1 },
    hidden       = { 0.11, 0.12, 0.15, 1 },   -- tiles shown after the game ends
    hiddenAlpha  = 0.35,
    felt         = { 0.06, 0.08, 0.13, 0.92 },
}

local DEFAULT_STATS = { games = 0, cashouts = 0, losses = 0, bestMultiplier = 0, biggestWin = 0 }

local Mines = {
    id = "mines",
    name = "Mines",
    description = "Uncover gems, dodge the mines, cash out before it blows.",
    icon = "Interface\\AddOns\\CowCasino\\Art\\MinesIcon",   -- painted (dev/art-src/make_game_icons.py)
}

local db       -- ns.db.mines; db.active holds the game in progress

-- The chosen icon (saved by name, so adding icons never shifts a choice).
local function IconIndex(kind)
    local wanted = db and db.icons and db.icons[kind]
    for i, icon in ipairs(ICONS[kind]) do
        if icon.name == wanted then return i end
    end
    return 1
end
local function Icon(kind) return ICONS[kind][IconIndex(kind)].path end

function ns:AddMinesIcon(kind, name, path)
    assert(ICONS[kind], "CowCasino: Mines icon kind must be \"gem\" or \"mine\"")
    assert(type(name) == "string" and type(path) == "string", "CowCasino: Mines icon needs a name and a path")
    for _, icon in ipairs(ICONS[kind]) do
        if icon.name == name then icon.path = path; return end
    end
    table.insert(ICONS[kind], { name = name, path = path })
end
CowCasino = CowCasino or {}
function CowCasino.AddMinesIcon(kind, name, path) return ns:AddMinesIcon(kind, name, path) end
local ui = {}
local last     -- the board that just ended: { board, revealed, hit }

local function Sound(key) ns:Sound(key) end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function Round2(n)
    return math.floor(n * 100 + 0.5) / 100
end

local function Fmt(n) return ns:FormatChips(n) end

local function FmtMult(m)
    return string.format("x%.2f", m)
end

---------------------------------------------------------------------------
-- Odds
---------------------------------------------------------------------------
-- Payout multiplier after `picks` safe tiles with `mines` mines on the board.
local function Multiplier(picks, mines)
    if picks <= 0 then return 1 end
    local m = 1
    for i = 0, picks - 1 do
        m = m * (TILES - i) / (TILES - mines - i)
    end
    return Round2(m * (1 - HOUSE_EDGE))
end

local function Payout(game)
    return Round2(game.bet * Multiplier(game.picks, game.mines))
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function SetStatus(text, r, g, b)
    ui.status:SetText(text)
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function StatsText()
    local s = db.stats
    if s.games == 0 then return "Pick how many mines, place a bet and start." end
    return string.format("Played %d   Cashed out %d   Best %s   Biggest win %s",
        s.games, s.cashouts, FmtMult(math.max(1, s.bestMultiplier)), Fmt(s.biggestWin))
end

local function Color(tex, c) tex:SetTexture(c[1], c[2], c[3], c[4] or 1) end

local function DrawTile(t, state, icon)
    -- state: "closed" | "safe" | "hit" | "hidden"
    Color(t.face, state == "safe" and ART.safe or state == "hit" and ART.hit
        or state == "hidden" and ART.hidden or ART.tile)
    if icon then
        t.icon:SetTexture(icon)
        t.icon:SetAlpha(state == "hidden" and ART.hiddenAlpha or 1)
        t.icon:Show()
    else
        t.icon:Hide()
    end
end

local function Refresh()
    local game = db.active

    for i, t in ipairs(ui.tiles) do
        if game then
            if game.revealed[i] then
                DrawTile(t, "safe", Icon("gem"))
            else
                DrawTile(t, "closed")
            end
            ns.SetEnabled(t, not game.revealed[i])
        elseif last then
            local mine = last.board[i]
            if i == last.hit then
                DrawTile(t, "hit", Icon("mine"))
            elseif last.revealed[i] then
                DrawTile(t, "safe", Icon("gem"))
            else
                DrawTile(t, "hidden", mine and Icon("mine") or Icon("gem"))
            end
            ns.SetEnabled(t, false)
        else
            DrawTile(t, "closed")
            ns.SetEnabled(t, false)
        end
    end

    -- Info line
    local mines = game and game.mines or db.mines
    if game then
        local now = Multiplier(game.picks, game.mines)
        local nextM = Multiplier(game.picks + 1, game.mines)
        local left = TILES - game.mines - game.picks
        ui.info:SetText(string.format("Mines |cffffffff%d|r   Now |cff40ff40%s|r   Next |cffffd100%s|r   Gems left |cffffffff%d|r", game.mines, FmtMult(now), FmtMult(nextM), left))
    else
        ui.info:SetText(string.format("Mines |cffffffff%d|r   First gem pays |cffffd100%s|r   All gems pay |cffffd100%s|r", mines, FmtMult(Multiplier(1, mines)), FmtMult(Multiplier(TILES - mines, mines))))
    end

    -- Controls
    local idle = not game
    for _, b in ipairs(ui.chipButtons) do ns.SetEnabled(b, idle) end
    ns.SetEnabled(ui.clear, idle and db.bet > 0)
    ns.SetEnabled(ui.fewer, idle and db.mines > 1)
    ns.SetEnabled(ui.more, idle and db.mines < TILES - 1)
    ui.mineCount:SetText(db.mines .. (db.mines == 1 and " mine" or " mines"))

    if game then
        if game.picks > 0 then
            ui.main:SetText("Cash out " .. Fmt(Payout(game)))
            ns.SetEnabled(ui.main, true)
        else
            ui.main:SetText("Pick a tile")
            ns.SetEnabled(ui.main, false)
        end
    else
        ui.main:SetText("Bet " .. Fmt(db.bet))
        ns.SetEnabled(ui.main, db.bet >= MIN_BET and db.bet <= ns.db.chips)
    end
    ns.SetEnabled(ui.random, not idle)

    ns:UpdateChipsDisplay()
end

---------------------------------------------------------------------------
-- Game flow
---------------------------------------------------------------------------
local function EndGame(hit)
    local game = db.active
    last = { board = game.board, revealed = game.revealed, hit = hit }
    db.active = nil
    if db.bet > ns.db.chips then
        db.bet = math.floor(ns.db.chips / MIN_BET) * MIN_BET
    end
end

local function CashOut(auto)
    local game = db.active
    if not game or game.picks == 0 then return end

    local mult = Multiplier(game.picks, game.mines)
    local payout = Payout(game)
    ns:AddChips(payout)

    local s = db.stats
    s.cashouts = s.cashouts + 1
    if mult > s.bestMultiplier then s.bestMultiplier = mult end
    if payout - game.bet > s.biggestWin then s.biggestWin = payout - game.bet end

    EndGame(nil)
    Sound("LOOT_WINDOW_COIN_SOUND")
    local lead = auto and "Every gem found! " or "Cashed out at "
    SetStatus(lead .. FmtMult(mult) .. " - you win " .. Fmt(payout) .. "!", 0.25, 1, 0.25)
    Refresh()
end

local function Reveal(i)
    local game = db.active
    if not game or game.revealed[i] then return end
    game.revealed[i] = true

    if game.board[i] then
        db.stats.losses = db.stats.losses + 1
        EndGame(i)
        Sound("RAID_WARNING")
        SetStatus("Boom! You lose " .. Fmt(game.bet) .. ".", 1, 0.35, 0.35)
        if ns.db.chips < MIN_BET then
            SetStatus("Boom! " .. ns:LowChipsText(MIN_BET), 1, 0.35, 0.35)
        end
        Refresh()
        return
    end

    game.picks = game.picks + 1
    Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    if game.picks == TILES - game.mines then
        CashOut(true)
        return
    end
    SetStatus(string.format("Safe! Cash out %s or keep going for %s.",
        Fmt(Payout(game)), FmtMult(Multiplier(game.picks + 1, game.mines))))
    Refresh()
end

local function RandomPick()
    local game = db.active
    if not game then return end
    local closed = {}
    for i = 1, TILES do
        if not game.revealed[i] then closed[ns.getn(closed) + 1] = i end
    end
    if ns.getn(closed) > 0 then Reveal(closed[math.random(ns.getn(closed))]) end
end

local function StartGame()
    if db.active then return end
    if ns.db.chips < MIN_BET then
        SetStatus(ns:LowChipsText(MIN_BET), 1, 0.35, 0.35)
        return
    end
    if db.bet < MIN_BET or db.bet > ns.db.chips then
        SetStatus("Place a bet of at least " .. MIN_BET .. ".")
        return
    end
    if not ns:SpendChips(db.bet) then return end

    -- Shuffle tile numbers and plant mines in the first `mines` of them.
    local order = {}
    for i = 1, TILES do order[i] = i end
    for i = TILES, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    local board = {}
    for i = 1, db.mines do board[order[i]] = true end

    db.active = { bet = db.bet, mines = db.mines, board = board, revealed = {}, picks = 0 }
    db.stats.games = db.stats.games + 1
    last = nil
    SetStatus("Pick a tile. Any tile.")
    Refresh()
end

local function AddBet(amount)
    if db.active then return end
    db.bet = math.max(0, math.min(db.bet + amount, MAX_BET, ns.db.chips))
    Refresh()
end

local function ChangeMines(delta)
    if db.active then return end
    if IsShiftKeyDown and IsShiftKeyDown() then delta = delta * 5 end
    db.mines = math.max(1, math.min(TILES - 1, db.mines + delta))
    Refresh()
end

---------------------------------------------------------------------------
-- Build
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

local function MakeTile(parent, index)
    local t = ns.CreateFrame("Button", nil, parent)
    t:SetWidth(TILE); t:SetHeight(TILE)

    t.edge = t:CreateTexture(nil, "BACKGROUND")
    t.edge:SetAllPoints(t)
    Color(t.edge, ART.edge)

    t.face = t:CreateTexture(nil, "BORDER")
    t.face:SetPoint("TOPLEFT", t, "TOPLEFT", 1, -1)
    t.face:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -1, 1)

    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetPoint("TOPLEFT", t, "TOPLEFT", 7, -7)
    t.icon:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -7, 7)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.icon:Hide()

    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", t, "TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -1, 1)
    hl:SetTexture(1, 1, 1, 0.12)

    t:SetScript("OnClick", function() Reveal(index) end)
    return t
end

---------------------------------------------------------------------------
-- Options overlay: pick the gem and mine icons
---------------------------------------------------------------------------
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
    title:SetText("Mines Options")

    local pickers = {}
    local function Picker(kind, label, y)
        local text = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOPLEFT", o, "TOPLEFT", 16, y)
        text:SetText(label)

        -- A preview tile, drawn like the board.
        local tile = MakeTile(o, 0)
        tile:SetPoint("TOPLEFT", tile:GetParent(), "TOPLEFT", 16, y - 20)
        tile:EnableMouse(false)
        tile:SetScript("OnClick", nil)

        local name = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", tile, "RIGHT", 44, 0)
        name:SetWidth(150)
        name:SetJustifyH("CENTER")

        local function Step(dir)
            local list = ICONS[kind]
            local i = ns.Mod(IconIndex(kind) - 1 + dir, ns.getn(list)) + 1
            db.icons[kind] = list[i].name
            o:Refresh()
            Refresh()
        end
        local prev = MakeButton(o, "<", 26, function() Step(-1) end)
        prev:SetPoint("RIGHT", name, "LEFT", -6, 0)
        local nextB = MakeButton(o, ">", 26, function() Step(1) end)
        nextB:SetPoint("LEFT", name, "RIGHT", 6, 0)

        local count = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        count:SetPoint("TOP", name, "BOTTOM", 0, -4)

        pickers[ns.getn(pickers) + 1] = function()
            local i = IconIndex(kind)
            name:SetText(ICONS[kind][i].name)
            count:SetText(i .. " of " .. ns.getn(ICONS[kind]))
            DrawTile(tile, kind == "gem" and "safe" or "hit", Icon(kind))
        end
    end

    Picker("gem", "Gem icon", -48)
    Picker("mine", "Mine icon", -132)

    local hint = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", o, "TOP", 0, -226)
    hint:SetWidth(AREA_W - 32)
    hint:SetText("Changes show on the board straight away, even mid-game. The icons are for looks only.")

    local done = MakeButton(o, "Done", 90, function() o:Hide() end)
    done:SetPoint("BOTTOM", done:GetParent(), "BOTTOM", 0, 12)

    function o:Refresh()
        for _, p in ipairs(pickers) do p() end
    end
    o:SetScript("OnShow", function() local self = this self:Refresh() end)
    return o
end

function Mines:Build(panel)
    ns.db.mines = ns.db.mines or {}
    db = ns.db.mines
    if db.bet == nil then db.bet = 25 end
    if db.mines == nil then db.mines = 3 end
    db.stats = db.stats or {}
    Fill(db.stats, DEFAULT_STATS)
    db.icons = db.icons or {}

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    Color(felt, ART.felt)

    -- Options sits in the top bar, opposite the "< Games" button.
    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetHeight(22)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    ui.info = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.info:SetPoint("TOP", panel, "TOP", 0, -6)

    -- Board
    local gridW = GRID * TILE + (GRID - 1) * TILE_GAP
    local grid = ns.CreateFrame("Frame", nil, panel)
    grid:SetWidth(gridW); grid:SetHeight(gridW)
    grid:SetPoint("TOP", grid:GetParent(), "TOP", 0, -24)
    ui.tiles = {}
    for i = 1, TILES do
        local t = MakeTile(grid, i)
        local col = ns.Mod(i - 1, GRID)
        local row = math.floor((i - 1) / GRID)
        t:SetPoint("TOPLEFT", t:GetParent(), "TOPLEFT", col * (TILE + TILE_GAP), -row * (TILE + TILE_GAP))
        ui.tiles[i] = t
    end

    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", grid, "BOTTOM", 0, -6)
    ui.status:SetWidth(AREA_W - 8)

    -- Row 1: bet chips and mine count
    local row1 = ns.CreateFrame("Frame", nil, panel)
    row1:SetWidth(AREA_W); row1:SetHeight(24)
    row1:SetPoint("BOTTOM", row1:GetParent(), "BOTTOM", 0, 40)

    ui.chipButtons = {}
    local x = 0
    for i, v in ipairs(CHIP_VALUES) do
        local i, v = i, v   -- own copy for closures (Lua 5.0)
        local b = MakeButton(row1, tostring(v), 38, function(_, button)
            AddBet(button == "RightButton" and -v or v)
        end)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetPoint("LEFT", b:GetParent(), "LEFT", x, 0)
        b:SetScript("OnEnter", function() local self = this
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Chip " .. v)
            GameTooltip:AddLine("Left-click to add, right-click to take back.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ui.chipButtons[i] = b
        x = x + 38 + 3
    end
    ui.clear = MakeButton(row1, "Clear", 46, function() AddBet(-db.bet) end)
    ui.clear:SetPoint("LEFT", ui.clear:GetParent(), "LEFT", x, 0)

    ui.more = MakeButton(row1, "+", 24, function() ChangeMines(1) end)
    ui.more:SetPoint("RIGHT", ui.more:GetParent(), "RIGHT", 0, 0)
    ui.mineCount = row1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.mineCount:SetPoint("RIGHT", ui.more, "LEFT", -4, 0)
    ui.mineCount:SetWidth(60)
    ui.fewer = MakeButton(row1, "-", 24, function() ChangeMines(-1) end)
    ui.fewer:SetPoint("RIGHT", ui.mineCount, "LEFT", -4, 0)
    for _, b in ipairs({ ui.fewer, ui.more }) do
        local b = b   -- own copy for closures (Lua 5.0)
        b:SetScript("OnEnter", function() local self = this
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Mines on the board")
            GameTooltip:AddLine("More mines, bigger multipliers. Shift-click to change by 5.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Row 2: bet / cash out and random pick
    ui.main = MakeButton(panel, "Bet", 180, function()
        if db.active then CashOut(false) else StartGame() end
    end)
    ui.main:SetPoint("BOTTOMLEFT", ui.main:GetParent(), "BOTTOMLEFT", 32, 10)
    ui.random = MakeButton(panel, "Random tile", 100, RandomPick)
    ui.random:SetPoint("LEFT", ui.main, "RIGHT", 8, 0)

    ui.options = BuildOptions(panel)

    if db.active then
        SetStatus("Welcome back - your game is still going.")
    else
        SetStatus(StatsText())
    end
    Refresh()
end

function Mines:OnHide()
    if ui.options then ui.options:Hide() end
end

function Mines:OnShow()
    -- after a fresh stack the last bet may be 0: start again from 25
    if db and not db.active and (db.bet < MIN_BET or db.bet > ns.db.chips) then
        db.bet = math.min(25, math.floor(ns.db.chips / MIN_BET) * MIN_BET)
    end
    if ui.status then
        if not db.active and not last then SetStatus(StatsText()) end
        Refresh()
    end
end

-- For the out-of-chips check: a board is in progress (saved across reloads).
function Mines:ChipsInPlay()
    local d = ns.db.mines
    return d ~= nil and d.active ~= nil
end

-- A fresh stack after running out (Core.lua): stats start over.
function Mines:ResetStats()
    local d = ns.db.mines
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
end

ns:RegisterGame(Mines)
