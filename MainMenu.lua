-- CowCasino: main window
-- One window with two pages: the game list (menu) and the open game.

local ns = CowCasino.ns

local FRAME_W, FRAME_H = 436, 440
local INSET = 42            -- the menu and game pages sit this far in from the sides (clear of the totem poles)
local ROW_H, ROW_GAP = 56, 6
local LIST_H = 318          -- room for the game list under the header
local PAGER_H = 24          -- page buttons under the list, when the games need more than one page

local ROW_BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
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
-- Game order: your saved order, then any games added since.
---------------------------------------------------------------------------
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
-- Menu rows
---------------------------------------------------------------------------
local function CreateGameRow(parent, game, rowH)
    local row = ns.CreateFrame("Button", nil, parent)
    row:SetHeight(rowH)
    row:SetBackdrop(ROW_BACKDROP)
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    row:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 4)
    hl:SetTexture(1, 0.82, 0, 0.12)

    local icon = row:CreateTexture(nil, "ARTWORK")
    local iconSize = math.min(40, rowH - 10)
    icon:SetWidth(iconSize); icon:SetHeight(iconSize)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:SetTexture(game.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", iconSize + 18, -7)
    name:SetText(game.name or game.id)

    -- the description gets two lines
    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    desc:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    desc:SetHeight(24)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetText(game.description or "")
    row.desc = desc

    -- marks a game that's still holding chips
    row.inPlay = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.inPlay:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -8)
    row.inPlay:SetTextColor(1, 0.6, 0.2)
    row.inPlay:SetText("In progress")
    row.inPlay:Hide()

    row:SetScript("OnClick", function()
        ns:Sound("IG_MAINMENU_OPTION")
        ns:OpenGame(game.id)
    end)

    return row
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
-- Rows in menu order, a page at a time.
function ns:LayoutMenu()
    local menu = self.frame and self.frame.menu
    if not menu or not menu.list then return end
    local order = self:MenuOrder()
    local per = menu.perPage
    local pages = math.ceil(ns.getn(order) / per)
    menu.page = math.max(1, math.min(menu.page or 1, pages))
    for i, id in ipairs(order) do
        local row = self.menuRows[id]
        local page = math.floor((i - 1) / per) + 1
        local y = -(i - 1 - (page - 1) * per) * (ROW_H + ROW_GAP)
        row.menuPage = page
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu.list, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", menu.list, "TOPRIGHT", 0, y)
        ns.SetShown(row, page == menu.page)
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
-- CowCasino options: window scale, the order of the games, card art, the
-- dealer, table chat and starting over.
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

    -- Window scale, on one line: label, slider, value, 100%
    local scaleLabel = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, -42)
    scaleLabel:SetText("Window size")
    local sliderName = ns:NewName() or "CowCasinoScaleSlider"
    local slider = ns.CreateFrame("Slider", sliderName, o, "OptionsSliderTemplate")
    slider:SetWidth(130); slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", o, "TOPLEFT", 100, -40)
    slider:SetMinMaxValues(ns.MIN_SCALE, ns.MAX_SCALE)
    slider:SetValueStep(0.05)
    local low, high, label = ns.getglobal(sliderName .. "Low"), ns.getglobal(sliderName .. "High"), ns.getglobal(sliderName .. "Text")
    low:SetText("")        -- the value beside it says the size
    high:SetText("")
    label:SetText("")
    local scaleValue = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
    local resetScale = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    resetScale:SetWidth(50); resetScale:SetHeight(20)
    resetScale:SetPoint("LEFT", scaleValue, "RIGHT", 10, 0)
    resetScale:SetText("100%")
    resetScale:SetScript("OnClick", function()
        o.pending = nil
        ns:SetScale(1)
        o:Refresh()
    end)

    -- Game order
    local orderLabel = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local ROWS_Y = -88
    orderLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, -68)
    orderLabel:SetText("Order of the games")
    -- two columns, read down the left one first
    local slots = {}
    local perColumn = math.ceil(ns.getn(ns.gameOrder) / 2)
    for i = 1, ns.getn(ns.gameOrder) do
        local i = i   -- own copy for closures (Lua 5.0)
        local col = (i > perColumn) and 1 or 0
        local x = 8 + col * 166
        local y = ROWS_Y - (i - 1 - col * perColumn) * 21
        local text = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", o, "TOPLEFT", x, y - 5)
        text:SetWidth(90)
        text:SetJustifyH("LEFT")
        local up = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
        up:SetWidth(30); up:SetHeight(20)
        up:SetPoint("TOPLEFT", o, "TOPLEFT", x + 92, y)
        up:SetText("Up")
        up:SetScript("OnClick", function() ns:MoveGame(i, -1) end)
        local down = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
        down:SetWidth(40); down:SetHeight(20)
        down:SetPoint("LEFT", up, "RIGHT", 1, 0)
        down:SetText("Down")
        down:SetScript("OnClick", function() ns:MoveGame(i, 1) end)
        slots[i] = { text = text, up = up, down = down }
    end

    -- Card art, shared by every card game (Cards.lua), with a small preview
    local artY = ROWS_Y - perColumn * 21 - 4
    local artLabel = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    artLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, artY)
    artLabel:SetText("Card art")
    local artName = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local artBy = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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
    local artPrev = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    artPrev:SetWidth(26); artPrev:SetHeight(22)
    artPrev:SetPoint("TOPLEFT", o, "TOPLEFT", 12, artY - 18)
    artPrev:SetText("<")
    artPrev:SetScript("OnClick", function() StepArt(-1) end)
    artName:SetPoint("LEFT", artPrev, "RIGHT", 4, 0)
    artName:SetWidth(90)
    artName:SetJustifyH("CENTER")
    local artNext = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    artNext:SetWidth(26); artNext:SetHeight(22)
    artNext:SetPoint("LEFT", artName, "RIGHT", 4, 0)
    artNext:SetText(">")
    artNext:SetScript("OnClick", function() StepArt(1) end)
    artBy:SetPoint("TOPLEFT", artLabel, "TOPRIGHT", 8, -1)
    -- an ace, a red queen and a back, at the small table size
    local previews = {}
    local cards = { { 1, 1, true }, { 12, 2, true }, { 1, 1, false } }
    for i, c in ipairs(cards) do
        local w = ns:CreateCardWidget(o, 26, 36)
        w:SetPoint("TOPLEFT", o, "TOPLEFT", 196 + (i - 1) * 32, artY - 2)
        previews[i] = { widget = w, rank = c[1], suit = c[2], up = c[3] }
    end

    -- The dealer on top of the window (Dealer.lua), with its picture
    local dealerY = artY - 48
    local dealerLabel = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dealerLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, dealerY)
    dealerLabel:SetText("Dealer")
    local dealerName = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local dealerBy = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local function StepDealer(dir)
        local order = ns.dealerOrder
        local current = ns:GetDealer()
        local idx = 1
        for i, id in ipairs(order) do
            if current and id == current.id then idx = i end
        end
        ns:SetDealer(order[ns.Mod(idx - 1 + dir, ns.getn(order)) + 1])
        ns:Sound("IG_MAINMENU_OPTION")
        o:Refresh()
    end
    local dealerPrev = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    dealerPrev:SetWidth(26); dealerPrev:SetHeight(22)
    dealerPrev:SetPoint("TOPLEFT", o, "TOPLEFT", 12, dealerY - 18)
    dealerPrev:SetText("<")
    dealerPrev:SetScript("OnClick", function() StepDealer(-1) end)
    dealerName:SetPoint("LEFT", dealerPrev, "RIGHT", 4, 0)
    dealerName:SetWidth(90)
    dealerName:SetJustifyH("CENTER")
    local dealerNext = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    dealerNext:SetWidth(26); dealerNext:SetHeight(22)
    dealerNext:SetPoint("LEFT", dealerName, "RIGHT", 4, 0)
    dealerNext:SetText(">")
    dealerNext:SetScript("OnClick", function() StepDealer(1) end)
    dealerBy:SetPoint("TOPLEFT", dealerLabel, "TOPRIGHT", 8, -1)
    local dealerBox = o:CreateTexture(nil, "BORDER")
    dealerBox:SetWidth(38); dealerBox:SetHeight(38)
    dealerBox:SetPoint("TOPLEFT", o, "TOPLEFT", 196, dealerY - 1)
    dealerBox:SetTexture(0.8, 0.65, 0.2, 0.6)
    local dealerPic = o:CreateTexture(nil, "ARTWORK")
    dealerPic:SetWidth(36); dealerPic:SetHeight(36)
    dealerPic:SetPoint("CENTER", dealerBox, "CENTER", 0, 0)
    o.dealerPic = dealerPic

    -- Table chat (Chat.lua), for party tables
    local chatY = dealerY - 42
    local chatLabel = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chatLabel:SetPoint("TOPLEFT", o, "TOPLEFT", 12, chatY)
    chatLabel:SetText("Table chat at party tables")
    local function Check(text, x, y, onClick)
        local c = ns.CreateFrame("CheckButton", ns:NewName(), o, "UICheckButtonTemplate")
        c:SetWidth(22); c:SetHeight(22)
        c:SetPoint("TOPLEFT", o, "TOPLEFT", x, y)
        c:SetScript("OnClick", onClick)
        local t = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    local sideValue = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local function FlipSide()
        local s = ns.Chat:Settings()
        s.side = (s.side == "left") and "right" or "left"
        ns.Chat:Layout()
        ns:Sound("IG_MAINMENU_OPTION")
        o:Refresh()
    end
    local sidePrev = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    sidePrev:SetWidth(26); sidePrev:SetHeight(22)
    sidePrev:SetPoint("TOPLEFT", o, "TOPLEFT", 212, chatY - 20)
    local sideLabel = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sideLabel:SetPoint("BOTTOM", sideValue, "TOP", 0, 5)
    sideLabel:SetText("Chat window on the")
    sidePrev:SetText("<")
    sidePrev:SetScript("OnClick", FlipSide)
    sideValue:SetPoint("LEFT", sidePrev, "RIGHT", 4, 0)
    sideValue:SetWidth(62)
    sideValue:SetJustifyH("CENTER")
    local sideNext = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    sideNext:SetWidth(26); sideNext:SetHeight(22)
    sideNext:SetPoint("LEFT", sideValue, "RIGHT", 4, 0)
    sideNext:SetText(">")
    sideNext:SetScript("OnClick", FlipSide)

    local default = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    default:SetWidth(110); default:SetHeight(22)
    default:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", 6, 4)
    default:SetText("Default order")
    default:SetScript("OnClick", function()
        ns.db.order = nil
        ns:LayoutMenu()
        o:Refresh()
    end)
    local done = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    done:SetWidth(90); done:SetHeight(22)
    done:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -6, 4)
    done:SetText("Done")
    done:SetScript("OnClick", function() o:Hide() end)

    -- Start over: as if you'd run out of chips. A second click within three
    -- seconds confirms, and gives up any game still holding chips (named in
    -- the note above the button). A party table has to be left first.
    local startOver = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    startOver:SetWidth(126); startOver:SetHeight(22)
    startOver:SetPoint("BOTTOM", o, "BOTTOM", 2, 4)
    startOver:SetText("Start over")
    local armedAt, blockedAt
    local function Restore()
        armedAt, blockedAt = nil, nil
        startOver:SetText("Start over")
    end
    local inPlayNote = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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

    local sub = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOP", header, "BOTTOM", 0, -4)
    sub:SetText("Just for fun - no real gold is ever wagered.")

    menu.chips = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    menu.chips:SetPoint("TOP", sub, "BOTTOM", 0, -8)

    local list = ns.CreateFrame("Frame", nil, menu)
    list:SetPoint("TOPLEFT", list:GetParent(), "TOPLEFT", 0, -72)
    list:SetPoint("BOTTOMRIGHT", list:GetParent(), "BOTTOMRIGHT", 0, 0)

    -- Every row is full height (room for two lines about the game). When the
    -- games don't all fit, the list turns into pages.
    local count = ns.getn(self.gameOrder)
    local perPage = math.floor((LIST_H + ROW_GAP) / (ROW_H + ROW_GAP))
    if count > perPage then perPage = math.floor((LIST_H - PAGER_H + ROW_GAP) / (ROW_H + ROW_GAP)) end
    self.menuRows = {}
    for _, id in ipairs(self.gameOrder) do
        self.menuRows[id] = CreateGameRow(list, self.games[id], ROW_H)
    end
    menu.list, menu.perPage, menu.page = list, perPage, 1

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

    local optionsButton = ns.CreateFrame("Button", ns:NewName(), menu, "UIPanelButtonTemplate")
    optionsButton:SetWidth(70); optionsButton:SetHeight(22)
    optionsButton:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -2)
    optionsButton:SetText("Options")
    optionsButton:SetScript("OnClick", function()
        ns:Sound("IG_MAINMENU_OPTION")
        ns.SetShown(ns.optionsPage, not ns.optionsPage:IsShown())
    end)
    self.optionsPage = self:BuildOptionsPage(frame)

    -- Page 2: open game ----------------------------------------------------
    local gamePage = ns.CreateFrame("Frame", nil, frame)
    gamePage:SetPoint("TOPLEFT", gamePage:GetParent(), "TOPLEFT", INSET, -36)
    gamePage:SetPoint("BOTTOMRIGHT", gamePage:GetParent(), "BOTTOMRIGHT", -INSET, 14)
    gamePage:Hide()
    frame.gamePage = gamePage

    local back = ns.CreateFrame("Button", ns:NewName(), gamePage, "UIPanelButtonTemplate")
    back:SetWidth(80); back:SetHeight(22)
    back:SetPoint("TOPLEFT", back:GetParent(), "TOPLEFT", 0, -2)
    back:SetText("< Games")
    back:SetScript("OnClick", function()
        ns:Sound("IG_MAINMENU_OPTION")
        ns:ShowMenu()
    end)

    gamePage.chips = gamePage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gamePage.chips:SetPoint("TOP", gamePage, "TOP", 0, -6)

    local container = ns.CreateFrame("Frame", nil, gamePage)
    container:SetPoint("TOPLEFT", container:GetParent(), "TOPLEFT", 0, -30)
    container:SetPoint("BOTTOMRIGHT", container:GetParent(), "BOTTOMRIGHT", 0, 0)
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
    note:SetText("Your game stats start over with it. Just for fun - no real gold is ever wagered.")
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
            ns:Print("a fresh stack of " .. ns:FormatChips(amount) .. " chips. Good luck!")
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
function ns:ShowMenu()
    local game = self.currentGame and self.games[self.currentGame]
    if game then
        if game.panel then game.panel:Hide() end
        if game.OnHide then game:OnHide() end
    end
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
        game.panel = ns.CreateFrame("Frame", nil, self.frame.container)
        game.panel:SetAllPoints(self.frame.container)
        if game.Build then game:Build(game.panel) end
    end

    self.currentGame = id
    self.frame.menu:Hide()
    if self.optionsPage then self.optionsPage:Hide() end
    self.frame.gamePage:Show()
    game.panel:Show()
    self.frame.title:SetText("CowCasino - " .. (game.name or id))
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
