-- CowCasino: main window
-- One window with two pages: the game list (menu) and the open game.

local ns = CowCasino.ns

local FRAME_W, FRAME_H = 436, 440
local INSET = 42            -- the menu and game pages sit this far in from the sides (clear of the totem poles)
local GAME_INSET = 28       -- a game's area reaches closer, up to the poles' inner edge (380 across)
local GAME_W = 352          -- the width most games are laid out for (centered in the wider area)
local LIST_H = 318          -- room for the game list under the header
local PAGER_H = 24          -- page buttons under the list, when the games need more than one page
-- The game list is a grid of tiles (icon and name), 5 across and 4 down a
-- page; the hovered game's description shows in a line under the grid (and
-- in a tooltip). Multiplayer games have a blue border, the rest gold.
local COLS, GRID_ROWS = 5, 4
local TILE_W, TILE_H, TILE_GAP = 66, 62, 5
local DESC_H = 28            -- the description line under the grid
local SP_BORDER = { 0.8, 0.65, 0.2 }
local MP_BORDER = { 0.35, 0.65, 1 }

local TILE_BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------
-- Saved as the window's top-left corner. (On 1.12, asking a frame that was
-- just dragged for its anchor can return nothing, so we read its edges.)
function ns:SavePosition()
    local left, top = self.frame:GetLeft(), self.frame:GetTop()
    if left and top then
        self.db.point = { "TOPLEFT", "BOTTOMLEFT", left, top }
    end
end

local VALID_POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

function ns:RestorePosition()
    if not self.frame then return end
    local p = self.db.point
    -- Anything unusable (such as an empty position saved by an older
    -- version) puts the window back in the center instead of failing.
    if type(p) ~= "table" or not VALID_POINTS[p[1]] or not VALID_POINTS[p[2]]
        or type(p[3]) ~= "number" or type(p[4]) ~= "number" then
        p = { "CENTER", "CENTER", 0, 0 }
        self.db.point = p
    end
    self.frame:ClearAllPoints()
    self.frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

---------------------------------------------------------------------------
-- Scale
---------------------------------------------------------------------------
ns.MIN_SCALE, ns.MAX_SCALE = 0.75, 2.5

-- Resize the whole window, keeping its top-left corner where it is.
function ns:SetScale(scale)
    scale = math.max(self.MIN_SCALE, math.min(self.MAX_SCALE, math.floor(scale * 100 + 0.5) / 100))
    self.db.scale = scale
    local f = self.frame
    if not f then return end
    local old = f:GetScale() or 1
    local left, top = f:GetLeft(), f:GetTop()
    f:SetScale(scale)
    if left and top then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
        self:SavePosition()
    end
end

---------------------------------------------------------------------------
-- Game order: your saved order, then any games added since (with the
-- multiplayer games first, if that's set in Options).
---------------------------------------------------------------------------
-- A game is multiplayer if it says so (game.multiplayer), or its description
-- does ("Supports Multiplayer", "Party game").
function ns:IsMultiplayer(game)
    if not game then return false end
    if game.multiplayer ~= nil then return game.multiplayer and true or false end
    local d = game.description or ""
    return string.find(d, "Multiplayer", 1, true) ~= nil or string.find(d, "Party game", 1, true) ~= nil
end

function ns:MenuOrder()
    local out, seen = {}, {}
    for _, id in ipairs(self.db.order or {}) do
        if self.games[id] and not seen[id] then
            table.insert(out, id)
            seen[id] = true
        end
    end
    for _, id in ipairs(self.gameOrder) do
        if not seen[id] then table.insert(out, id) end
    end
    if self.db.mpFirst then
        local mp, sp = {}, {}
        for _, id in ipairs(out) do
            if self:IsMultiplayer(self.games[id]) then table.insert(mp, id) else table.insert(sp, id) end
        end
        for _, id in ipairs(sp) do table.insert(mp, id) end
        out = mp
    end
    return out
end

function ns:MoveGame(index, dir)
    local order = self:MenuOrder()
    local j = index + dir
    if j < 1 or j > ns.getn(order) then return end
    order[index], order[j] = order[j], order[index]
    self.db.order = order
    self:LayoutMenu()
end

---------------------------------------------------------------------------
-- Menu tiles
---------------------------------------------------------------------------
local LEGEND = "|cffcca633Gold|r: single player     |cff59a6ffBlue|r: multiplayer     (hover a game for more)"

-- The description, on one line ("Supports Multiplayer" goes: the border says it).
local function ShortDescription(game)
    local d = string.gsub(game.description or "", "\n?|cff%x%x%x%x%x%xSupports Multiplayer|r", "")
    d = string.gsub(d, "\n", "  ")
    return d
end

local function CreateGameTile(parent, game)
    local tile = ns.CreateFrame("Button", nil, parent)
    tile:SetWidth(TILE_W); tile:SetHeight(TILE_H)
    tile:SetBackdrop(TILE_BACKDROP)
    tile:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    local border = ns:IsMultiplayer(game) and MP_BORDER or SP_BORDER
    tile:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    tile.multiplayer, tile.border = ns:IsMultiplayer(game), border

    local hl = tile:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", tile, "TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -3, 3)
    hl:SetTexture(1, 0.82, 0, 0.15)

    local icon = tile:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(34); icon:SetHeight(34)
    icon:SetPoint("TOP", tile, "TOP", 0, -5)
    icon:SetTexture(game.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    tile.icon = icon

    local name = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("TOP", icon, "BOTTOM", 0, -1)
    name:SetWidth(TILE_W - 4)
    name:SetHeight(20)
    name:SetJustifyH("CENTER")
    name:SetJustifyV("TOP")
    name:SetText(game.name or game.id)
    tile.name = name

    -- marks a game that's still holding chips: an orange dot in the corner
    local dot = tile:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\AddOns\\CowCasino\\Art\\Dot")
    dot:SetWidth(10); dot:SetHeight(10)
    dot:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -4, -4)
    dot:SetVertexColor(1, 0.55, 0.1, 1)
    dot:Hide()
    tile.inPlay = dot

    tile:SetScript("OnEnter", function()
        GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
        GameTooltip:SetText(game.name or game.id, 1, 0.82, 0)
        GameTooltip:AddLine(ShortDescription(game), 1, 1, 1, 1)
        if tile.multiplayer then GameTooltip:AddLine("Supports Multiplayer", 0.4, 0.8, 1) else GameTooltip:AddLine("Single player", 0.8, 0.65, 0.2) end
        if tile.inPlay:IsShown() then GameTooltip:AddLine("In progress", 1, 0.6, 0.2) end
        GameTooltip:Show()
        local menu = ns.frame and ns.frame.menu
        if menu and menu.desc then menu.desc:SetText("|cffffd100" .. (game.name or game.id) .. ":|r " .. ShortDescription(game)) end
    end)
    tile:SetScript("OnLeave", function()
        GameTooltip:Hide()
        local menu = ns.frame and ns.frame.menu
        if menu and menu.desc then menu.desc:SetText(LEGEND) end
    end)
    tile:SetScript("OnClick", function()
        GameTooltip:Hide()
        ns:Sound("IG_MAINMENU_OPTION")
        ns:OpenGame(game.id)
    end)

    return tile
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
-- Tiles in menu order, across then down, a page at a time.
function ns:LayoutMenu()
    local menu = self.frame and self.frame.menu
    if not menu or not menu.list then return end
    local order = self:MenuOrder()
    local per = menu.perPage
    local pages = math.ceil(ns.getn(order) / per)
    menu.page = math.max(1, math.min(menu.page or 1, pages))
    local left = math.floor((menu.list:GetWidth() - (COLS * TILE_W + (COLS - 1) * TILE_GAP)) / 2)
    if left < 0 then left = 0 end
    for i, id in ipairs(order) do
        local tile = self.menuRows[id]
        local page = math.floor((i - 1) / per) + 1
        local at = i - 1 - (page - 1) * per
        local x = left + ns.Mod(at, COLS) * (TILE_W + TILE_GAP)
        local y = -math.floor(at / COLS) * (TILE_H + TILE_GAP)
        tile.menuPage = page
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", menu.list, "TOPLEFT", x, y)
        ns.SetShown(tile, page == menu.page)
    end
    if menu.pager then
        ns.SetShown(menu.pager, pages > 1)
        menu.pageText:SetText("Page " .. menu.page .. " of " .. pages)
        ns.SetEnabled(menu.prevPage, menu.page > 1)
        ns.SetEnabled(menu.nextPage, menu.page < pages)
    end
    if self.optionsPage and self.optionsPage:IsShown() then self.optionsPage:Refresh() end
end

function ns:MenuPage(dir)
    local menu = self.frame and self.frame.menu
    if not menu then return end
    menu.page = (menu.page or 1) + dir
    ns:Sound("IG_MAINMENU_OPTION")
    self:LayoutMenu()
end

---------------------------------------------------------------------------
-- CowCasino options, in tabs: Display (window size, card art, the dealer, the window style),
-- Games (their order), Chat (table chat) and Chips (starting over).
---------------------------------------------------------------------------
function ns:BuildOptionsPage(frame)
    local o = ns.CreateFrame("Frame", nil, frame)
    o:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, -36)
    o:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -INSET, 14)
    o:SetFrameLevel(frame:GetFrameLevel() + 60)
    o:EnableMouse(true)
    o:Hide()
    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0, 0, 0, 0.95)

    local head = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOP", o, "TOP", 0, -8)
    head:SetText("CowCasino Options")

    -- Tabs along the bottom; Done sits above them
    local tabs = ns.UI.Tabs(o, { "Display", "Games", "Chat", "Chips" }, 4)
    local disp, games, chat, chips = tabs.frames[1], tabs.frames[2], tabs.frames[3], tabs.frames[4]
    o.tabs = tabs

    -- Window scale, on one line: label, slider, value, 100%
    local scaleLabel = disp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, -42)
    scaleLabel:SetText("Window size")
    local sliderName = ns:NewName() or "CowCasinoScaleSlider"
    local slider = ns.CreateFrame("Slider", sliderName, disp, "OptionsSliderTemplate")
    slider:SetWidth(130); slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", o, "TOPLEFT", 100, -40)
    slider:SetMinMaxValues(ns.MIN_SCALE, ns.MAX_SCALE)
    slider:SetValueStep(0.05)
    local low, high, label = ns.getglobal(sliderName .. "Low"), ns.getglobal(sliderName .. "High"), ns.getglobal(sliderName .. "Text")
    low:SetText("")        -- the value beside it says the size
    high:SetText("")
    label:SetText("")
    local scaleValue = disp:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleValue:SetPoint("LEFT", slider, "RIGHT", 14, 0)
    -- The slider is inside the window it resizes, so resizing while you drag
    -- would move the slider under the mouse. Show the size while dragging and
    -- apply it when the mouse button is let go (or when this screen closes).
    local function ApplyPending()
        if o.pending then
            ns:SetScale(o.pending)
            o.pending = nil
        end
    end
    slider:SetScript("OnValueChanged", function()
        if o.updating then return end
        o.pending = math.floor(this:GetValue() * 100 + 0.5) / 100
        scaleValue:SetText(math.floor(o.pending * 100 + 0.5) .. "%")
    end)
    slider:SetScript("OnMouseUp", ApplyPending)
    o:SetScript("OnHide", ApplyPending)
    local resetScale = ns.CreateFrame("Button", ns:NewName(), disp, "UIPanelButtonTemplate")
    resetScale:SetWidth(50); resetScale:SetHeight(20)
    resetScale:SetPoint("LEFT", scaleValue, "RIGHT", 10, 0)
    resetScale:SetText("100%")
    resetScale:SetScript("OnClick", function()
        o.pending = nil
        ns:SetScale(1)
        o:Refresh()
    end)

    -- Game order
    local orderLabel = games:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local ROWS_Y = -62
    orderLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, -42)
    orderLabel:SetText("Order of the games")
    -- two columns, read down the left one first
    local slots = {}
    local perColumn = math.ceil(ns.getn(ns.gameOrder) / 2)
    for i = 1, ns.getn(ns.gameOrder) do
        local i = i   -- own copy for closures (Lua 5.0)
        local col = (i > perColumn) and 1 or 0
        local x = 8 + col * 166
        local y = ROWS_Y - (i - 1 - col * perColumn) * 21
        local text = games:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", o, "TOPLEFT", x, y - 5)
        text:SetWidth(90)
        text:SetJustifyH("LEFT")
        local up = ns.CreateFrame("Button", ns:NewName(), games, "UIPanelButtonTemplate")
        up:SetWidth(30); up:SetHeight(20)
        up:SetPoint("TOPLEFT", o, "TOPLEFT", x + 92, y)
        up:SetText("Up")
        up:SetScript("OnClick", function() ns:MoveGame(i, -1) end)
        local down = ns.CreateFrame("Button", ns:NewName(), games, "UIPanelButtonTemplate")
        down:SetWidth(40); down:SetHeight(20)
        down:SetPoint("LEFT", up, "RIGHT", 1, 0)
        down:SetText("Down")
        down:SetScript("OnClick", function() ns:MoveGame(i, 1) end)
        slots[i] = { text = text, up = up, down = down }
    end
    local mpFirst = ns.CreateFrame("CheckButton", ns:NewName(), games, "UICheckButtonTemplate")
    mpFirst:SetWidth(24); mpFirst:SetHeight(24)
    mpFirst:SetPoint("TOPLEFT", o, "TOPLEFT", 8, ROWS_Y - perColumn * 21 - 4)
    mpFirst:SetScript("OnClick", function()
        ns.db.mpFirst = this:GetChecked() and true or nil
        ns:Sound("IG_MAINMENU_OPTION")
        ns:LayoutMenu()
    end)
    local mpLabel = games:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mpLabel:SetPoint("LEFT", mpFirst, "RIGHT", 2, 0)
    mpLabel:SetText("Multiplayer games first")
    o.mpFirst = mpFirst

    -- Card art, shared by every card game (Cards.lua), with a small preview
    local artY = -82
    local artLabel = disp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    artLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, artY)
    artLabel:SetText("Card art")
    local artName = disp:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local artBy = disp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local function StepArt(dir)
        local order = ns.cardArtOrder
        local current = ns:GetCardArt()
        local idx = 1
        for i, id in ipairs(order) do
            if current and id == current.id then idx = i end
        end
        ns:SetCardArt(order[ns.Mod(idx - 1 + dir, ns.getn(order)) + 1])
        ns:Sound("IG_MAINMENU_OPTION")
        o:Refresh()
    end
    local artPrev = ns.CreateFrame("Button", ns:NewName(), disp, "UIPanelButtonTemplate")
    artPrev:SetWidth(26); artPrev:SetHeight(22)
    artPrev:SetPoint("TOPLEFT", o, "TOPLEFT", 12, artY - 18)
    artPrev:SetText("<")
    artPrev:SetScript("OnClick", function() StepArt(-1) end)
    artName:SetPoint("LEFT", artPrev, "RIGHT", 4, 0)
    artName:SetWidth(90)
    artName:SetJustifyH("CENTER")
    local artNext = ns.CreateFrame("Button", ns:NewName(), disp, "UIPanelButtonTemplate")
    artNext:SetWidth(26); artNext:SetHeight(22)
    artNext:SetPoint("LEFT", artName, "RIGHT", 4, 0)
    artNext:SetText(">")
    artNext:SetScript("OnClick", function() StepArt(1) end)
    artBy:SetPoint("TOPLEFT", artLabel, "TOPRIGHT", 8, -1)
    -- an ace, a red queen and a back, at the small table size
    local previews = {}
    local cards = { { 1, 1, true }, { 12, 2, true }, { 1, 1, false } }
    for i, c in ipairs(cards) do
        local w = ns:CreateCardWidget(disp, 26, 36)
        w:SetPoint("TOPLEFT", o, "TOPLEFT", 196 + (i - 1) * 32, artY - 2)
        previews[i] = { widget = w, rank = c[1], suit = c[2], up = c[3] }
    end

    -- The dealer on top of the window (Dealer.lua), with its picture
    local dealerY = artY - 48
    local dealerLabel = disp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dealerLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, dealerY)
    dealerLabel:SetText("Dealer")
    local dealerName = disp:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local dealerBy = disp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local function StepDealer(dir)
        local order = ns:DealerChoices()
        local current = ns:GetDealer()
        local idx = 1
        for i, id in ipairs(order) do
            if current and id == current.id then idx = i end
        end
        ns:SetDealer(order[ns.Mod(idx - 1 + dir, ns.getn(order)) + 1])
        ns:Sound("IG_MAINMENU_OPTION")
        o:Refresh()
    end
    local dealerPrev = ns.CreateFrame("Button", ns:NewName(), disp, "UIPanelButtonTemplate")
    dealerPrev:SetWidth(26); dealerPrev:SetHeight(22)
    dealerPrev:SetPoint("TOPLEFT", o, "TOPLEFT", 12, dealerY - 18)
    dealerPrev:SetText("<")
    dealerPrev:SetScript("OnClick", function() StepDealer(-1) end)
    dealerName:SetPoint("LEFT", dealerPrev, "RIGHT", 4, 0)
    dealerName:SetWidth(90)
    dealerName:SetJustifyH("CENTER")
    local dealerNext = ns.CreateFrame("Button", ns:NewName(), disp, "UIPanelButtonTemplate")
    dealerNext:SetWidth(26); dealerNext:SetHeight(22)
    dealerNext:SetPoint("LEFT", dealerName, "RIGHT", 4, 0)
    dealerNext:SetText(">")
    dealerNext:SetScript("OnClick", function() StepDealer(1) end)
    dealerBy:SetPoint("TOPLEFT", dealerLabel, "TOPRIGHT", 8, -1)
    local dealerBox = disp:CreateTexture(nil, "BORDER")
    dealerBox:SetWidth(38); dealerBox:SetHeight(38)
    dealerBox:SetPoint("TOPLEFT", o, "TOPLEFT", 196, dealerY - 1)
    dealerBox:SetTexture(0.8, 0.65, 0.2, 0.6)
    local dealerPic = disp:CreateTexture(nil, "ARTWORK")
    dealerPic:SetWidth(36); dealerPic:SetHeight(36)
    dealerPic:SetPoint("CENTER", dealerBox, "CENTER", 0, 0)
    o.dealerPic = dealerPic

    -- The window's look
    local styleY = dealerY - 58
    local styleLabel = disp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    styleLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, styleY)
    styleLabel:SetText("Window style")
    local styleStep = ns.UI.Stepper(disp, {
        list = ns.FRAME_STYLES, width = 90,
        label = function(v) return "|cffffffff" .. ns.FRAME_STYLE_NAMES[v] .. "|r" end,
        get = function() return ns:FrameStyle() end,
        set = function(v) ns.db.frameStyle = v end,
        onChange = function() ns:ApplyFrameStyle() end,
    })
    styleStep:SetPoint("TOPLEFT", o, "TOPLEFT", 120, styleY + 5)
    o.styleStep = styleStep

    -- Table chat (Chat.lua), for party tables
    local chatY = -42
    local chatLabel = chat:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chatLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, chatY)
    chatLabel:SetText("Table chat at party tables")
    local function Check(text, x, y, onClick)
        local c = ns.CreateFrame("CheckButton", ns:NewName(), chat, "UICheckButtonTemplate")
        c:SetWidth(22); c:SetHeight(22)
        c:SetPoint("TOPLEFT", o, "TOPLEFT", x, y)
        c:SetScript("OnClick", onClick)
        local t = chat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("LEFT", c, "RIGHT", 2, 1)
        t:SetText(text)
        return c
    end
    local chatShow = Check("Show the chat arrow", 14, chatY - 16, function()
        ns.Chat:Settings().enabled = this:GetChecked() and true or false
        ns.Chat:Refresh()
    end)
    local chatAuto = Check("Open it when someone talks", 14, chatY - 36, function()
        ns.Chat:Settings().autoOpen = this:GetChecked() and true or false
    end)
    local sideValue = chat:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local function FlipSide()
        local s = ns.Chat:Settings()
        s.side = (s.side == "left") and "right" or "left"
        ns.Chat:Layout()
        ns:Sound("IG_MAINMENU_OPTION")
        o:Refresh()
    end
    local sidePrev = ns.CreateFrame("Button", ns:NewName(), chat, "UIPanelButtonTemplate")
    sidePrev:SetWidth(26); sidePrev:SetHeight(22)
    sidePrev:SetPoint("TOPLEFT", o, "TOPLEFT", 212, chatY - 20)
    local sideLabel = chat:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sideLabel:SetPoint("BOTTOM", sideValue, "TOP", 0, 5)
    sideLabel:SetText("Chat window on the")
    sidePrev:SetText("<")
    sidePrev:SetScript("OnClick", FlipSide)
    sideValue:SetPoint("LEFT", sidePrev, "RIGHT", 4, 0)
    sideValue:SetWidth(62)
    sideValue:SetJustifyH("CENTER")
    local sideNext = ns.CreateFrame("Button", ns:NewName(), chat, "UIPanelButtonTemplate")
    sideNext:SetWidth(26); sideNext:SetHeight(22)
    sideNext:SetPoint("LEFT", sideValue, "RIGHT", 4, 0)
    sideNext:SetText(">")
    sideNext:SetScript("OnClick", FlipSide)

    local default = ns.CreateFrame("Button", ns:NewName(), games, "UIPanelButtonTemplate")
    default:SetWidth(110); default:SetHeight(22)
    default:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", 6, 34)
    default:SetText("Default order")
    default:SetScript("OnClick", function()
        ns.db.order = nil
        ns:LayoutMenu()
        o:Refresh()
    end)
    local done = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    done:SetWidth(90); done:SetHeight(22)
    done:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -6, 34)
    done:SetText("Done")
    done:SetScript("OnClick", function() o:Hide() end)

    -- Start over: as if you'd run out of chips. A second click within three
    -- seconds confirms, and gives up any game still holding chips (named in
    -- the note above the button). A party table has to be left first.
    local startOver = ns.CreateFrame("Button", ns:NewName(), chips, "UIPanelButtonTemplate")
    startOver:SetWidth(126); startOver:SetHeight(22)
    local startText = chips:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    startText:SetPoint("TOPLEFT", o, "TOPLEFT", 12, -42)
    startText:SetWidth(328)
    startText:SetJustifyH("LEFT")
    startText:SetText("Start over empties your wallet and brings up the new-stack screen, just as running out "
        .. "of chips does. A fresh stack starts the games' stats over. Your settings, art and game order stay.")
    startOver:SetPoint("TOP", o, "TOP", 0, -130)
    startOver:SetText("Start over")
    local armedAt, blockedAt
    local function Restore()
        armedAt, blockedAt = nil, nil
        startOver:SetText("Start over")
    end
    local inPlayNote = chips:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inPlayNote:SetPoint("BOTTOM", startOver, "TOP", 0, 4)
    inPlayNote:SetWidth(330)
    inPlayNote:SetTextColor(1, 0.6, 0.2)
    o.inPlayNote = inPlayNote
    startOver:SetScript("OnClick", function()
        local party = false
        for _, p in ipairs(ns:InPlay()) do if not p.canGiveUp then party = true end end
        if party then
            armedAt = nil
            blockedAt = GetTime()
            startOver:SetText("Leave your table first")
            ns:After(3, function() if blockedAt and GetTime() - blockedAt >= 2.9 then Restore() end end)
            return
        end
        if armedAt and GetTime() - armedAt <= 3 then
            Restore()
            ns:StartOver(true)
            return
        end
        armedAt = GetTime()
        startOver:SetText("Click again to confirm")
        ns:Sound("IG_MAINMENU_OPTION")
        ns:After(3, function() if armedAt and GetTime() - armedAt >= 2.9 then Restore() end end)
    end)
    o.startOver = startOver

    function o:Refresh()
        local names = {}
        local party = false
        for _, p in ipairs(ns:InPlay()) do
            table.insert(names, p.name)
            if not p.canGiveUp then party = true end
        end
        if ns.getn(names) == 0 then
            inPlayNote:SetText("")
        elseif party then
            inPlayNote:SetText("Chips in play at a party table (" .. table.concat(names, ", ") .. "): leave it to start over.")
        else
            inPlayNote:SetText("Chips still in play in " .. table.concat(names, ", ") .. ". Starting over gives them up.")
        end
        local pack = ns:GetCardArt()
        artName:SetText(pack and pack.name or "?")
        artBy:SetText(pack and pack.author and ("by " .. pack.author) or "")
        for _, p in ipairs(previews) do p.widget:SetCard({ rank = p.rank, suit = p.suit }, p.up) end
        local dealer = ns:GetDealer()
        if dealer then
            dealerName:SetText(dealer.name)
            dealerBy:SetText(dealer.author and ("by " .. dealer.author) or "")
            local img = dealer.image
            if type(img) == "table" then
                dealerPic:SetTexture(img[1])
                dealerPic:SetTexCoord(img[2] or 0, img[3] or 1, img[4] or 0, img[5] or 1)
            else
                dealerPic:SetTexture(img)
                dealerPic:SetTexCoord(0, 1, 0, 1)
            end
        end
        if ns.Chat then
            local cs = ns.Chat:Settings()
            chatShow:SetChecked(cs.enabled)
            chatAuto:SetChecked(cs.autoOpen)
            sideValue:SetText(cs.side == "left" and "Left side" or "Right side")
        end
        o.updating = true
        slider:SetValue(ns.db.scale or 1)
        o.updating = nil
        scaleValue:SetText(math.floor((ns.db.scale or 1) * 100 + 0.5) .. "%")
        o.mpFirst:SetChecked(ns.db.mpFirst and true or nil)
        o.styleStep:Refresh()
        local order = ns:MenuOrder()
        local n = ns.getn(order)
        for i, slot in ipairs(slots) do
            local game = ns.games[order[i]]
            slot.text:SetText(game and (i .. ". " .. (game.name or game.id)) or "")
            ns.SetEnabled(slot.up, game ~= nil and i > 1)
            ns.SetEnabled(slot.down, game ~= nil and i < n)
        end
    end
    o:SetScript("OnShow", function() this:Refresh() end)
    return o
end

-- The window's Tauren look: a wooden rim and a Thunder Bluff-style painted
-- band with rawhide lacing along the top and bottom, a carved totem pole
-- down each side (a kodo head on top, then a thunderbird, a bear and a
-- tauren) and horns rising from the kodo heads. Painted by
-- dev/art-src/make_tauren_window.py. All of it is drawn around the window's
-- edge, so nothing inside moves.
local ART = "Interface\\AddOns\\CowCasino\\Art\\"
local SKIN_PAD = 10                -- the art reaches this far outside the window
local HORN = 96                    -- shown size of each horn
local TOTEM_W, TOTEM_H = 64, 512   -- each totem pole's texture (the pole is 480 tall in it)
local TOTEM_X = -8                 -- the pole's middle, from the window's side edge (outward)
local TOTEM_TOP = 18               -- the pole's top, above the window's top edge
local EMBLEM = 28                  -- the faction emblems at the ends of the title band

function ns:SkinFrame(frame)
    local skin = frame:CreateTexture(nil, "BORDER")   -- over the horns
    skin:SetTexture(ART .. "TaurenFrame")
    skin:SetPoint("TOPLEFT", frame, "TOPLEFT", -SKIN_PAD, SKIN_PAD)
    skin:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", SKIN_PAD, -SKIN_PAD)
    -- the art is 456 x 460 in the top-left of a 512 x 512 file
    skin:SetTexCoord(0, (FRAME_W + 2 * SKIN_PAD) / 512, 0, (FRAME_H + 2 * SKIN_PAD) / 512)

    -- horn bases sit on the top corner conchos
    local left = frame:CreateTexture(nil, "BACKGROUND")
    left:SetTexture(ART .. "TaurenHorn")
    left:SetWidth(HORN); left:SetHeight(HORN)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", -74, 85)
    local right = frame:CreateTexture(nil, "BACKGROUND")
    right:SetTexture(ART .. "TaurenHorn")
    right:SetTexCoord(1, 0, 0, 1)    -- mirrored
    right:SetWidth(HORN); right:SetHeight(HORN)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 74, 85)
    -- the totem poles, over the ring's sides (the window's contents draw over them)
    local totemL = frame:CreateTexture(nil, "ARTWORK")
    totemL:SetTexture(ART .. "TaurenTotemL")
    totemL:SetWidth(TOTEM_W); totemL:SetHeight(TOTEM_H)
    totemL:SetPoint("TOPLEFT", frame, "TOPLEFT", TOTEM_X - TOTEM_W / 2, TOTEM_TOP)
    local totemR = frame:CreateTexture(nil, "ARTWORK")
    totemR:SetTexture(ART .. "TaurenTotemR")
    totemR:SetWidth(TOTEM_W); totemR:SetHeight(TOTEM_H)
    totemR:SetPoint("TOPLEFT", frame, "TOPRIGHT", -TOTEM_X - TOTEM_W / 2, TOTEM_TOP)
    frame.skin, frame.hornL, frame.hornR, frame.totemL, frame.totemR = skin, left, right, totemL, totemR

    -- The other looks are one painting each, the same size as the Tauren art:
    -- Modern (dev/art-src/make_modern_window.py), Horde and Alliance
    -- (dev/art-src/make_faction_windows.py).
    frame.styleArt = {}
    for _, style in ipairs(ns.FRAME_STYLES) do
        local file = ns.FRAME_STYLE_ART[style]
        if file then
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetTexture(ART .. file)
            t:SetPoint("TOPLEFT", frame, "TOPLEFT", -SKIN_PAD, SKIN_PAD)
            t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", SKIN_PAD, -SKIN_PAD)
            t:SetTexCoord(0, (FRAME_W + 2 * SKIN_PAD) / 512, 0, (FRAME_H + 2 * SKIN_PAD) / 512)
            frame.styleArt[style] = t
        end
    end
    frame.modern = frame.styleArt.modern
    -- the faction's own emblem (the game's PvP icon, already in every client)
    -- at both ends of the title band, for the Horde and Alliance looks
    frame.emblems = {}
    for style, file in pairs(ns.FRAME_STYLE_EMBLEM) do
        local pair = {}
        for side = 1, 2 do
            local e = frame:CreateTexture(nil, "ARTWORK")
            e:SetTexture(file)
            e:SetTexCoord(0, 0.625, 0, 0.625)   -- the emblem sits in the icon's top-left 40 x 40
            e:SetWidth(EMBLEM); e:SetHeight(EMBLEM)
            if side == 1 then e:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -3)
            else e:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -3) end
            pair[side] = e
        end
        frame.emblems[style] = pair
    end
    self:ApplyFrameStyle(frame)
end

-- The window's look (Options > Display): Modern (the default), Horde,
-- Alliance or Tauren.
ns.FRAME_STYLES = { "modern", "horde", "alliance", "tauren" }
ns.FRAME_STYLE_NAMES = { modern = "Modern", horde = "Horde", alliance = "Alliance", tauren = "Tauren" }
ns.FRAME_STYLE_ART = { modern = "ModernFrame", horde = "HordeFrame", alliance = "AllianceFrame" }
ns.FRAME_STYLE_EMBLEM = {
    horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
    alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
}
function ns:FrameStyle()
    local s = self.db and self.db.frameStyle
    if not ns.FRAME_STYLE_NAMES[s or ""] then s = "modern" end
    return s
end

function ns:ApplyFrameStyle(frame)
    frame = frame or self.frame
    if not frame or not frame.styleArt then return end
    local style = self:FrameStyle()
    local tauren = style == "tauren"
    for _, t in ipairs({ frame.skin, frame.hornL, frame.hornR, frame.totemL, frame.totemR }) do ns.SetShown(t, tauren) end
    for key, t in pairs(frame.styleArt) do ns.SetShown(t, key == style) end
    for key, pair in pairs(frame.emblems or {}) do
        for _, e in ipairs(pair) do ns.SetShown(e, key == style) end
    end
end

function ns:BuildMainFrame()
    if self.frame then return end

    -- 1.12 has no window templates: Tauren-themed art plus a close button.
    local frame = ns.CreateFrame("Frame", "CowCasinoFrame", UIParent)
    frame:SetWidth(FRAME_W); frame:SetHeight(FRAME_H)
    self:SkinFrame(frame)
    frame:SetFrameStrata("DIALOG")
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() local f = this
        f:StopMovingOrSizing()
        ns:SavePosition()
    end)
    frame:Hide()
    frame:SetScript("OnHide", function() ns:Sound("IG_CHARACTER_INFO_CLOSE") end)
    tinsert(UISpecialFrames, "CowCasinoFrame") -- Escape closes it
    self.frame = frame
    frame:SetScale(self.db.scale or 1)
    self:RestorePosition()

    local close = ns.CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -INSET + 8, -6)   -- clear of the right totem's head

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -17)
    frame.title = title

    -- Page 1: game list ----------------------------------------------------
    local menu = ns.CreateFrame("Frame", nil, frame)
    menu:SetPoint("TOPLEFT", menu:GetParent(), "TOPLEFT", INSET, -36)
    menu:SetPoint("BOTTOMRIGHT", menu:GetParent(), "BOTTOMRIGHT", -INSET, 14)
    frame.menu = menu

    local header = ns:BigFont(menu:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 22)
    header:SetPoint("TOP", menu, "TOP", 0, -6)
    header:SetText("Pick a game")

    menu.chips = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    menu.chips:SetPoint("TOP", header, "BOTTOM", 0, -10)

    local list = ns.CreateFrame("Frame", nil, menu)
    list:SetPoint("TOPLEFT", list:GetParent(), "TOPLEFT", 0, -72)
    list:SetPoint("BOTTOMRIGHT", list:GetParent(), "BOTTOMRIGHT", 0, 0)

    -- A grid of tiles (5 x 4 a page), the hovered game's description under
    -- it, and page buttons below when the games don't all fit.
    list:SetWidth(FRAME_W - 2 * INSET)
    self.menuRows = {}
    for _, id in ipairs(self.gameOrder) do
        self.menuRows[id] = CreateGameTile(list, self.games[id])
    end
    menu.list, menu.perPage, menu.page = list, COLS * GRID_ROWS, 1
    menu.desc = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    menu.desc:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -(GRID_ROWS * (TILE_H + TILE_GAP)) - 2)
    menu.desc:SetWidth(FRAME_W - 2 * INSET - 8)
    menu.desc:SetHeight(DESC_H)
    menu.desc:SetJustifyH("CENTER")
    menu.desc:SetJustifyV("TOP")
    menu.desc:SetText(LEGEND)

    local pager = ns.CreateFrame("Frame", nil, menu)
    pager:SetHeight(PAGER_H)
    pager:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", 0, 0)
    pager:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0)
    menu.pager = pager
    menu.pageText = pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    menu.pageText:SetPoint("CENTER", pager, "CENTER", 0, 0)
    menu.prevPage = ns.CreateFrame("Button", ns:NewName(), pager, "UIPanelButtonTemplate")
    menu.prevPage:SetWidth(70); menu.prevPage:SetHeight(20)
    menu.prevPage:SetPoint("RIGHT", menu.pageText, "LEFT", -12, 0)
    menu.prevPage:SetText("< Prev")
    menu.prevPage:SetScript("OnClick", function() ns:MenuPage(-1) end)
    menu.nextPage = ns.CreateFrame("Button", ns:NewName(), pager, "UIPanelButtonTemplate")
    menu.nextPage:SetWidth(70); menu.nextPage:SetHeight(20)
    menu.nextPage:SetPoint("LEFT", menu.pageText, "RIGHT", 12, 0)
    menu.nextPage:SetText("Next >")
    menu.nextPage:SetScript("OnClick", function() ns:MenuPage(1) end)
    -- the mouse wheel turns pages too
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function()
        local dir = (arg1 or 0) > 0 and -1 or 1
        local pages = math.ceil(ns.getn(ns.gameOrder) / menu.perPage)
        if menu.page + dir >= 1 and menu.page + dir <= pages then ns:MenuPage(dir) end
    end)
    self:LayoutMenu()

    -- The window's one Options button, in the title row (left of the close button).
    -- On the game list it opens the CowCasino options; in a game, that game's
    -- own page (each game fills it in with ns:GameOptions). It moves onto
    -- whichever page is showing so it draws over it.
    local optionsButton = ns.CreateFrame("Button", ns:NewName(), menu, "UIPanelButtonTemplate")
    optionsButton:SetWidth(70); optionsButton:SetHeight(22)
    optionsButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -INSET - 28, -9)    -- the title row, left of the close button
    optionsButton:SetText("Options")
    optionsButton:SetScript("OnClick", function() ns:ToggleOptions() end)
    frame.optionsButton = optionsButton
    self.optionsPage = self:BuildOptionsPage(frame)

    -- Page 2: open game ----------------------------------------------------
    -- The title row holds < Games, the game's name and Options; the chips sit
    -- just under the name, and the game gets everything below (380 x 380).
    local gamePage = ns.CreateFrame("Frame", nil, frame)
    gamePage:SetPoint("TOPLEFT", gamePage:GetParent(), "TOPLEFT", GAME_INSET, -8)
    gamePage:SetPoint("BOTTOMRIGHT", gamePage:GetParent(), "BOTTOMRIGHT", -GAME_INSET, 14)
    gamePage:Hide()
    frame.gamePage = gamePage

    local back = ns.CreateFrame("Button", ns:NewName(), gamePage, "UIPanelButtonTemplate")
    back:SetWidth(80); back:SetHeight(22)
    back:SetPoint("TOPLEFT", back:GetParent(), "TOPLEFT", INSET - GAME_INSET, -1)   -- level with the close button
    back:SetText("< Games")
    back:SetScript("OnClick", function()
        ns:Sound("IG_MAINMENU_OPTION")
        ns:ShowMenu()
    end)

    gamePage.chips = gamePage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gamePage.chips:SetPoint("TOP", frame, "TOP", 0, -31)

    local container = ns.CreateFrame("Frame", nil, gamePage)
    container:SetPoint("TOPLEFT", container:GetParent(), "TOPLEFT", 0, -38)
    container:SetPoint("BOTTOMRIGHT", container:GetParent(), "BOTTOMRIGHT", 0, 0)
    -- a dark ground; games laid out for 352 sit centered on it
    local ground = container:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints(container)
    ground:SetTexture(0.05, 0.04, 0.03, 0.85)
    frame.container = container

    self.rebuyPage = self:BuildRebuyPage(frame)
    if self.Chat then self.Chat:Build(frame) end

    self:ShowMenu()
end

---------------------------------------------------------------------------
-- Out of chips: back to the menu to pick a fresh stack
---------------------------------------------------------------------------
local KICK_DELAY = 2.5   -- seconds to see the losing result before leaving the game

function ns:BuildRebuyPage(frame)
    local o = ns.CreateFrame("Frame", nil, frame)
    o:SetAllPoints(frame.menu)
    o:SetFrameLevel(frame.menu:GetFrameLevel() + 60)
    o:EnableMouse(true)
    o:Hide()
    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0.06, 0.04, 0.03, 0.97)

    local head = ns:BigFont(o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 22)
    head:SetPoint("TOP", o, "TOP", 0, -60)
    head:SetText("Out of chips!")
    local sub = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOP", head, "BOTTOM", 0, -12)
    sub:SetWidth(300)
    sub:SetText("Pick a fresh stack to start again.")
    local note = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOP", sub, "BOTTOM", 0, -6)
    note:SetText("Your game stats start over with it.")
    note:SetWidth(300)

    o.buttons = {}
    for i, amount in ipairs(ns.REBUY_AMOUNTS) do
        local amount = amount   -- own copy for the closure (Lua 5.0)
        local b = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
        b:SetWidth(160); b:SetHeight(28)
        b:SetPoint("TOP", o, "TOP", 0, -150 - (i - 1) * 38)
        b:SetText(ns:FormatChips(amount) .. " chips")
        b:SetScript("OnClick", function()
            ns:Sound("IG_MAINMENU_OPTION")
            ns:RebuyChips(amount)
            o:Hide()
            ns:Print("a fresh stack of " .. ns:FormatChips(amount) .. " chips.")
        end)
        o.buttons[i] = b
    end

    -- Watches for running out while the window is open.
    local watch = ns.CreateFrame("Frame", nil, frame)
    local since, wait = 0, 0
    watch:SetScript("OnUpdate", function()
        wait = wait + arg1
        if wait < 0.25 then return end
        local dt = wait
        wait = 0
        if o:IsShown() or not ns:IsBroke() then since = 0 return end
        since = since + dt
        if not ns.currentGame or since >= KICK_DELAY then
            since = 0
            ns:OutOfChips()
        end
    end)
    return o
end

-- Start over from the Options: give up your chips and pick a fresh stack,
-- exactly as if you'd run out (stats start over too). With chips still in
-- play it's refused, unless giveUp: then those games are given up first
-- (party tables can't be, so it's still refused while you sit at one).
function ns:StartOver(giveUp)
    if self:ChipsInPlay() then
        if not giveUp or not self:GiveUpAll() then return false end
    end
    self.db.chips = 0
    self:UpdateChipsDisplay()
    if self.optionsPage then self.optionsPage:Hide() end
    self:OutOfChips()
    return true
end

function ns:OutOfChips()
    if not self:IsBroke() then return end
    if self.currentGame then self:ShowMenu() end
    self.rebuyPage:Show()
end

---------------------------------------------------------------------------
-- Chip balance, shown on both pages
---------------------------------------------------------------------------
function ns:UpdateChipsDisplay()
    if not self.frame then return end
    local text = "Chips: |cffffffff" .. self:FormatChips(self.db.chips) .. "|r"
    self.frame.gamePage.chips:SetText(text)
    -- on the menu, mark games still holding chips, and say so if you're out
    local held = {}
    for _, p in ipairs(self:InPlay()) do if p.menuId then held[p.menuId] = true end end
    for id, row in pairs(self.menuRows or {}) do ns.SetShown(row.inPlay, held[id] == true) end
    if self.db.chips < 1 and next(held) then
        text = text .. "  |cffff9933(more in play: see In progress)|r"
    end
    self.frame.menu.chips:SetText(text)
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
-- Options for what's showing: the CowCasino options on the game list, the
-- game's own page in a game.
function ns:ToggleOptions()
    ns:Sound("IG_MAINMENU_OPTION")
    local game = self.currentGame and self.games[self.currentGame]
    if not game then
        ns.SetShown(self.optionsPage, not self.optionsPage:IsShown())
        return
    end
    local o = game.options
    if not o then return end
    if o:IsShown() then
        o:Hide()
    else
        o:Show()
    end
end

-- Put the Options button on the page that's showing (so it draws over it).
local function PlaceOptionsButton(parent, shown)
    local b = ns.frame and ns.frame.optionsButton
    if not b then return end
    b:SetParent(parent)
    b:SetFrameLevel(parent:GetFrameLevel() + 60)
    ns.SetShown(b, shown)
end

function ns:ShowMenu()
    local game = self.currentGame and self.games[self.currentGame]
    if game then
        if game.options then game.options:Hide() end
        if game.panel then game.panel:Hide() end
        if game.OnHide then game:OnHide() end
    end
    PlaceOptionsButton(self.frame.menu, true)
    self.currentGame = nil
    if ns.Dealer then ns.Dealer:Attach(nil) end

    self.frame.gamePage:Hide()
    self.frame.menu:Show()
    if self.optionsPage then self.optionsPage:Hide() end
    self.frame.title:SetText("CowCasino")
    self:UpdateChipsDisplay()
end

function ns:OpenGame(id)
    local game = self.games[id]
    if not game then return end
    if self:IsBroke() then
        self:OutOfChips()
        return
    end

    if self.currentGame and self.currentGame ~= id then self:ShowMenu() end

    if not game.panel then
        local container = self.frame.container
        game.panel = ns.CreateFrame("Frame", nil, container)
        if game.wide then
            game.panel:SetAllPoints(container)          -- a game that uses the whole area
        else
            game.panel:SetPoint("TOP", container, "TOP", 0, 0)
            game.panel:SetPoint("BOTTOM", container, "BOTTOM", 0, 0)
            game.panel:SetWidth(GAME_W)
        end
        if game.Build then game:Build(game.panel) end
        -- every game has an Options page; a plain one if it didn't make its own
        if not game.options then ns:GameOptions(game, game.panel, {}) end
    end
    PlaceOptionsButton(game.panel, true)

    self.currentGame = id
    self.frame.menu:Hide()
    if self.optionsPage then self.optionsPage:Hide() end
    self.frame.gamePage:Show()
    game.panel:Show()
    self.frame.title:SetText(game.name or id)   -- (short: it shares its row with < Games and Options)
    if ns.Dealer then ns.Dealer:Attach(game) end      -- before OnShow, so it can talk straight away
    if game.OnShow then game:OnShow() end
end

function ns:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        ns:Sound("IG_CHARACTER_INFO_OPEN")
        self.frame:Show()
    end
end
