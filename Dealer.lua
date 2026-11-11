-- CowCasino: the Dealer
-- A strip on top of the casino window, between the horns, where a game's
-- dealer can talk to you. It shows:
--   * a picture: an image (an icon or any texture) or a player's 3D portrait
--     (a party member dealing, say, or the player with the big blind)
--   * a name line and a message, which can fall back to an idle line after
--     a few seconds
-- and it can play sounds. It's hidden on the menu and for games without one.
--
-- The picture is the dealer you picked in CowCasino Options (a goblin unless
-- you change it). Dealers are packs, like card art: CowCasino has a goblin
-- and a human, and other addons can add more with CowCasino.RegisterDealer
-- (see DEALERS.md).
--
-- A game turns the strip on with a `dealer` table in its definition:
--   dealer = { idle = "Place your bets." }
-- It may also give its own name line or picture, instead of the chosen dealer's:
--   dealer = { name = "Croupier", image = "Interface\\Icons\\...", idle = "..." }
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
local ART = "Interface\\AddOns\\CowCasino\\Art\\"
local DEFAULT_DEALER = "goblin"

local Dealer = {}
ns.Dealer = Dealer

---------------------------------------------------------------------------
-- Dealer packs: { id, name (for the picker), title (the strip's name line),
-- author, image = path or { path, left, right, top, bottom } }
---------------------------------------------------------------------------
ns.dealers = {}
ns.dealerOrder = {}

function ns:RegisterDealer(pack)
    assert(type(pack) == "table" and type(pack.id) == "string", "CowCasino: a dealer needs an id")
    assert(type(pack.image) == "string" or type(pack.image) == "table",
        "CowCasino: dealer '" .. pack.id .. "' needs an image")
    pack.name = pack.name or pack.id
    pack.title = pack.title or "Dealer"
    if not self.dealers[pack.id] then table.insert(self.dealerOrder, pack.id) end
    self.dealers[pack.id] = pack
    return pack
end

-- The dealer picked in Options (saved), or the goblin.
function ns:GetDealer()
    local id = self.db and self.db.dealer
    return self.dealers[id] or self.dealers[DEFAULT_DEALER] or self.dealers[self.dealerOrder[1]]
end

function ns:SetDealer(id)
    if not self.dealers[id] or not self.db then return end
    self.db.dealer = id
    Dealer:Repaint()
end

function CowCasino.RegisterDealer(pack) return ns:RegisterDealer(pack) end

local ui            -- built the first time a game with a dealer opens
local owner         -- the game it belongs to right now
local showingPlayer -- a player's portrait is up (not the picture)
local customName    -- the game changed the name line
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

-- The game's own picture, or the dealer picked in Options.
local function DefaultImage()
    local def = owner and owner.dealer
    return (def and def.image) or ns:GetDealer().image
end

local function DefaultName()
    local def = owner and owner.dealer
    return (def and def.name) or ns:GetDealer().title
end

local function ShowImage(image)
    showingPlayer = false
    local path, l, r, t, b = image, 0, 1, 0, 1
    if type(image) == "table" then path, l, r, t, b = image[1], image[2] or 0, image[3] or 1, image[4] or 0, image[5] or 1 end
    ui.portrait:ShowUnit(nil)
    ui.portrait:Hide()
    ui.image:SetTexture(path)
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
    customName = nil
    idleText = def.idle or ""
    ui.name:SetText(DefaultName())
    ui.text:SetText(idleText)
    ShowImage(DefaultImage())
    ui:Show()
end

-- A different dealer picked in Options: show it now, unless the game has a
-- player's portrait or its own picture up.
function Dealer:Repaint()
    if not ui or not owner then return end
    if not showingPlayer then ShowImage(DefaultImage()) end
    if not customName then ui.name:SetText(DefaultName()) end
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
    customName = text
    ui.name:SetText(text or DefaultName())
end

-- A picture: a texture path, or { path, left, right, top, bottom }; nil
-- goes back to the game's picture (or the dealer picked in Options).
function Dealer:SetImage(game, image)
    if not Owns(game) then return end
    ShowImage(image or DefaultImage())
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
        ShowImage(DefaultImage())
        return
    end
    showingPlayer = true
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

---------------------------------------------------------------------------
-- CowCasino's own dealers (pictures made by dev/art-src/make_dealer.py)
---------------------------------------------------------------------------
ns:RegisterDealer({ id = "goblin", name = "Goblin", title = "Fizzlecog, your dealer", author = "ruin9k",
    image = ART .. "DealerGoblin" })
ns:RegisterDealer({ id = "human", name = "Human", title = "Your dealer", author = "ruin9k",
    image = ART .. "DealerHuman" })
