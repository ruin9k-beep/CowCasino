-- CowCasino: the Dealer
-- A strip on top of the casino window, between the horns, where a game's
-- dealer can talk to you. It shows:
--   * a picture: an image (an icon or any texture) or a player's 3D portrait
--     (a party member dealing, say, or the player with the big blind)
--   * a name line and a message, which can fall back to an idle line after
--     a few seconds
-- and it can play sounds. It's hidden on the menu and for games without one.
--
-- A game turns it on with a `dealer` table in its definition:
--   dealer = { name = "Dealer", image = "Interface\\Icons\\...", idle = "Place your bets." }
-- (image may also be { path, left, right, top, bottom } to crop it).
-- Then, while that game is on screen, it drives the dealer through ns.Dealer:
--   ns.Dealer:Say(game, "Dealer busts!", 4)          -- 4 seconds, then the idle line
--   ns.Dealer:Say(game, "Blackjack!", 4, "UI_EPICLOOT_TOAST")   -- with a sound
--   ns.Dealer:Sound(game, "win", db)                 -- a game sound event (its Sounds menu)
--   ns.Dealer:Sound(game, "RAID_WARNING")            -- or any sound by name
--   ns.Dealer:SetName(game, "Bob - big blind")
--   ns.Dealer:SetPlayer(game, "Bob")                 -- a party member's portrait ("player" = you)
--   ns.Dealer:SetImage(game, "Interface\\Icons\\INV_Misc_Coin_01")   -- back to a picture
--   ns.Dealer:Idle(game)                             -- the idle line again
-- Calls from a game that isn't on screen are ignored, so only the current
-- game controls the dealer. Opening a game resets the dealer to its table.

local ns = CowCasino.ns

local STRIP_H   = 56
local SIDE      = 34      -- clear of the horns at the window's top corners
local PIC       = 44
local BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local DEFAULT_IMAGE = "Interface\\Icons\\INV_Misc_Coin_01"

local Dealer = {}
ns.Dealer = Dealer

local ui            -- built the first time a game with a dealer opens
local owner         -- the game it belongs to right now
local idleText = ""
local revertAt      -- GetTime() when the message goes back to the idle line

local function Owns(game)
    return game ~= nil and game == owner and ns.currentGame ~= nil and ns.games[ns.currentGame] == game
end

local function Build()
    if ui or not ns.frame then return end
    ui = ns.CreateFrame("Frame", nil, ns.frame)
    ui:SetHeight(STRIP_H)
    ui:SetPoint("BOTTOMLEFT", ns.frame, "TOPLEFT", SIDE, 8)
    ui:SetPoint("BOTTOMRIGHT", ns.frame, "TOPRIGHT", -SIDE, 8)
    ui:SetFrameLevel(ns.frame:GetFrameLevel() + 10)
    ui:SetBackdrop(BACKDROP)
    ui:SetBackdropColor(0.08, 0.06, 0.04, 0.95)
    ui:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
    ui:EnableMouse(true)          -- dragging it moves the window, like the window itself
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", function() ns.frame:StartMoving() end)
    ui:SetScript("OnDragStop", function() ns.frame:StopMovingOrSizing(); ns:SavePosition() end)
    ui:Hide()

    -- the picture: an image or a 3D portrait, in a small dark box
    ui.box = ns.CreateFrame("Frame", nil, ui)
    ui.box:SetWidth(PIC); ui.box:SetHeight(PIC)
    ui.box:SetPoint("LEFT", ui, "LEFT", 6, 0)
    local bg = ui.box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(ui.box)
    bg:SetTexture(0, 0, 0, 0.6)
    ui.image = ui.box:CreateTexture(nil, "ARTWORK")
    ui.image:SetPoint("TOPLEFT", ui.box, "TOPLEFT", 1, -1)
    ui.image:SetPoint("BOTTOMRIGHT", ui.box, "BOTTOMRIGHT", -1, 1)
    ui.portrait = ns:CreatePortrait(ui.box, PIC, PIC)
    ui.portrait:SetPoint("CENTER", ui.box, "CENTER", 0, 0)

    ui.name = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ui.name:SetPoint("TOPLEFT", ui.box, "TOPRIGHT", 8, -1)
    ui.name:SetJustifyH("LEFT")
    ui.text = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.text:SetPoint("TOPLEFT", ui.name, "BOTTOMLEFT", 0, -3)
    ui.text:SetPoint("RIGHT", ui, "RIGHT", -8, 0)
    ui.text:SetHeight(28)
    ui.text:SetJustifyH("LEFT")
    ui.text:SetJustifyV("TOP")

    -- a timed message goes back to the idle line
    ui:SetScript("OnUpdate", function()
        if revertAt and GetTime() >= revertAt then
            revertAt = nil
            ui.text:SetText(idleText)
        end
    end)
end

local function ShowImage(image)
    local path, l, r, t, b = image, 0, 1, 0, 1
    if type(image) == "table" then path, l, r, t, b = image[1], image[2] or 0, image[3] or 1, image[4] or 0, image[5] or 1 end
    ui.portrait:ShowUnit(nil)
    ui.portrait:Hide()
    ui.image:SetTexture(path or DEFAULT_IMAGE)
    ui.image:SetTexCoord(l, r, t, b)
    ui.image:Show()
end

-- Called by the menu whenever a game opens (or nil for the menu): show this
-- game's dealer, reset to its table, or hide the strip.
function Dealer:Attach(game)
    owner = nil
    revertAt = nil
    local def = game and game.dealer
    if not def then
        if ui then ui:Hide() end
        return
    end
    Build()
    if not ui then return end
    owner = game
    idleText = def.idle or ""
    ui.name:SetText(def.name or "Dealer")
    ui.text:SetText(idleText)
    ShowImage(def.image)
    ui:Show()
end

function Dealer:IsShown() return ui ~= nil and ui:IsShown() end

-- A message; seconds (optional) brings back the idle line after that long;
-- sound (optional) plays with it.
function Dealer:Say(game, text, seconds, sound)
    if not Owns(game) then return end
    ui.text:SetText(text or "")
    revertAt = seconds and (GetTime() + seconds) or nil
    if sound then ns:Sound(sound) end
end

-- What the dealer says between messages.
function Dealer:SetIdle(game, text)
    if not Owns(game) then return end
    idleText = text or ""
    if not revertAt then ui.text:SetText(idleText) end
end

function Dealer:Idle(game)
    if not Owns(game) then return end
    revertAt = nil
    ui.text:SetText(idleText)
end

function Dealer:SetName(game, text)
    if not Owns(game) then return end
    ui.name:SetText(text or "")
end

-- A picture: a texture path, or { path, left, right, top, bottom }.
function Dealer:SetImage(game, image)
    if not Owns(game) then return end
    ShowImage(image)
end

-- A player's 3D portrait: "player" for you, or a party or raid member's
-- name (or unit). Someone who can't be shown (not in your group, or out of
-- range) gets the game's picture instead.
function Dealer:SetPlayer(game, who)
    if not Owns(game) then return end
    local unit = who
    if who and who ~= "player" and not string.find(who, "^party") and not string.find(who, "^raid") then
        unit = ns.Net and ns.Net:UnitFor(who)
    end
    if not unit then
        ShowImage(owner.dealer and owner.dealer.image)
        return
    end
    ui.image:Hide()
    ui.portrait:Show()
    ui.portrait:ShowUnit(unit)
end

-- A sound: a game sound event from that game's Sounds menu (with its saved
-- table), or any sound by name (ns:Sound).
function Dealer:Sound(game, key, db)
    if not Owns(game) then return end
    if db then ns:PlayGameSound(db, key) else ns:Sound(key) end
end

-- Exposed for tests.
function Dealer.UI() return ui end
