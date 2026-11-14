-- CowCasino: the Dealer
-- A strip on top of the casino window, between the horns, where a game's
-- dealer can talk to you. It shows:
--   * a picture: an image (an icon or any texture) or a player's 3D portrait
--     (a party member dealing, say, or the player with the big blind)
--   * a name line and a message (the last one stays up until the next; a
--     game's idle line shows when it opens)
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
--   ns.Dealer:Say(game, "Dealer busts!")             -- stays up until the next message
--   ns.Dealer:Say(game, "Blackjack!", 4, "UI_EPICLOOT_TOAST")   -- with a sound
--   ns.Dealer:Sound(game, "win", db)                 -- a game sound event (its Sounds menu)
--   ns.Dealer:Sound(game, "RAID_WARNING")            -- or any sound by name
--   ns.Dealer:SetName(game, "Bob - big blind")
--   ns.Dealer:SetPlayer(game, "Bob")                 -- a party member's portrait ("player" = you)
--   ns.Dealer:SetImage(game, "Interface\\Icons\\INV_Misc_Coin_01")   -- back to a picture
--   ns.Dealer:Idle(game)                             -- the idle line again
--   ns.Dealer:React(game, "playerBust", { player = 24 }, 5, "Bust!")
--       -- the chosen dealer's own line for that moment (see DEALERS.md),
--       -- or the fallback text if this dealer has none
-- Calls from a game that isn't on screen are ignored, so only the current
-- game controls the dealer. Opening a game resets the dealer to its table.
--
-- Messages queue up: each one stays up for at least 3 seconds before the
-- next, and the text fades out and back in whenever it changes. The last
-- message stays up; the idle line shows when a game opens or calls Idle.

local ns = CowCasino.ns

local STRIP_H   = 118
local SIDE      = 34      -- clear of the horns at the window's top corners
local PIC       = 108
local BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local DEFAULT_DEALER = "goblin"

local Dealer = {}
ns.Dealer = Dealer

---------------------------------------------------------------------------
-- Dealer packs: { id, name (for the picker), title (the strip's name line),
-- author, image = path or { path, left, right, top, bottom },
-- lines = { [event] = { "a line", "another, with {player}", ... } } }
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
local MIN_SHOW  = 3       -- seconds each message stays up before the next one
local FADE      = 0.2     -- seconds to fade the text out, and again to fade it in
local MAX_QUEUE = 3       -- messages waiting behind the one on screen (four in all); a new one
                          -- pushes out the oldest waiting
local queue = {}    -- messages waiting: { text, seconds, sound }
local current       -- the message on screen (with shownAt), or nil for the idle line
local fade          -- { out = true/false, t0, msg }: the text is changing
local lastLine = {} -- the line last used for each event, so it doesn't repeat

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

    -- The arrow on the window's top edge that shows and hides the strip
    -- (like the table chat's arrow); the choice is saved.
    local toggle = ns.CreateFrame("Button", nil, ns.frame)
    toggle:SetWidth(26); toggle:SetHeight(26)
    toggle:SetPoint("CENTER", ns.frame, "TOP", 0, 3)
    toggle:SetFrameLevel(ns.frame:GetFrameLevel() + 20)
    toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    toggle:SetScript("OnClick", function()
        ns:Sound("IG_MAINMENU_OPTION")
        Dealer:SetOpen(not Dealer:Open())
    end)
    toggle:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText(Dealer:Open() and "Hide the dealer" or "Show the dealer")
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toggle:Hide()
    ui.toggle = toggle

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

    ui.name = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.name:SetPoint("TOPLEFT", ui.box, "TOPRIGHT", 10, -2)
    ui.name:SetJustifyH("LEFT")
    ui.text = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.text:SetPoint("TOPLEFT", ui.name, "BOTTOMLEFT", 0, -5)
    ui.text:SetPoint("RIGHT", ui, "RIGHT", -10, 0)
    ui.text:SetHeight(STRIP_H - 34)
    ui.text:SetJustifyH("LEFT")
    ui.text:SetJustifyV("TOP")

    ui:SetScript("OnUpdate", function() Dealer:Update() end)
end

-- Fade the text out, then in with msg (nil: the idle line).
local function ChangeTo(msg)
    fade = { out = true, t0 = GetTime(), msg = msg }
end

-- Runs every frame while the strip is up: fades, the queue, timed messages.
function Dealer:Update()
    local now = GetTime()
    if fade then
        local k = (now - fade.t0) / FADE
        if fade.out then
            if k < 1 then ui.text:SetAlpha(1 - k) return end
            current = fade.msg
            if current then
                current.shownAt = now
                ui.text:SetText(current.text)
                if current.sound then ns:Sound(current.sound) end
            else
                ui.text:SetText(idleText)
            end
            ui.text:SetAlpha(0)
            fade = { out = false, t0 = now }
        elseif k < 1 then
            ui.text:SetAlpha(k)
        else
            ui.text:SetAlpha(1)
            fade = nil
        end
        return
    end
    -- (the last message stays up until there's another; Idle() clears it)
    if current then
        if queue[1] and now >= current.shownAt + MIN_SHOW then ChangeTo(table.remove(queue, 1)) end
    elseif queue[1] then
        ChangeTo(table.remove(queue, 1))
    end
end

-- Exposed for tests: messages waiting, and the text's fade.
function Dealer.Pending() return ns.getn(queue) end

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

-- Is the strip wanted (the arrow on the window's top edge)? Saved; on unless hidden.
function Dealer:Open()
    return not (ns.db and ns.db.dealerHidden)
end

-- Show the strip if this game has a dealer and it's wanted; the arrow shows
-- whenever the game has a dealer, pointing the way the strip will go.
local ARROW = "Interface\\Buttons\\UI-ScrollBar-Scroll"
local function Place()
    if not ui then return end
    local open = Dealer:Open()
    ns.SetShown(ui, owner ~= nil and open)
    ns.SetShown(ui.toggle, owner ~= nil)
    local dir = open and "Down" or "Up"
    ui.toggle:SetNormalTexture(ARROW .. dir .. "Button-Up")
    ui.toggle:SetPushedTexture(ARROW .. dir .. "Button-Down")
end

function Dealer:SetOpen(open)
    if ns.db then ns.db.dealerHidden = not open or nil end
    Place()
end

-- Called by the menu whenever a game opens (or nil for the menu): show this
-- game's dealer, reset to its table, or hide the strip.
function Dealer:Attach(game)
    owner = nil
    queue, current, fade = {}, nil, nil
    local def = game and game.dealer
    if not def then
        Place()
        return
    end
    Build()
    if not ui then return end
    owner = game
    customName = nil
    idleText = def.idle or ""
    ui.name:SetText(DefaultName())
    ui.text:SetText(idleText)
    ui.text:SetAlpha(1)
    ShowImage(DefaultImage())
    Place()
end

-- A different dealer picked in Options: show it now, unless the game has a
-- player's portrait or its own picture up.
function Dealer:Repaint()
    if not ui or not owner then return end
    if not showingPlayer then ShowImage(DefaultImage()) end
    if not customName then ui.name:SetText(DefaultName()) end
end

function Dealer:IsShown() return ui ~= nil and ui:IsShown() end
-- (the show/hide arrow, for tests)
function Dealer:ArrowShown() return ui ~= nil and ui.toggle:IsShown() end

-- A message, after any already waiting. It stays up until the next one
-- (3 seconds at least), so the last thing said stays on screen. sound
-- (optional) plays when it shows. (seconds is accepted for older callers
-- and ignored.)
function Dealer:Say(game, text, seconds, sound)
    if not Owns(game) then return end
    if ns.getn(queue) >= MAX_QUEUE then table.remove(queue, 1) end
    table.insert(queue, { text = text or "", seconds = seconds, sound = sound })
    if not current and not fade then ChangeTo(table.remove(queue, 1)) end
end

-- Something is being said, or about to be.
local function Busy()
    return queue[1] ~= nil or (fade ~= nil and (not fade.out or fade.msg ~= nil))
        or (current ~= nil and GetTime() - current.shownAt < MIN_SHOW)
end

-- A line from the chosen dealer for a moment in the game (event), with
-- {name} in it filled from vars; or the fallback text when the dealer has
-- no lines for it (nothing is said if there's neither). A quiet reaction is
-- skipped while something else is being said.
function Dealer:Line(event, vars)
    local lines = ns:GetDealer().lines
    lines = lines and lines[event]
    if type(lines) == "string" then lines = { lines } end
    if type(lines) ~= "table" then return nil end
    local n = ns.getn(lines)
    if n == 0 then return nil end
    local pick = math.random(n)
    if n > 1 and lines[pick] == lastLine[event] then pick = ns.Mod(pick, n) + 1 end
    lastLine[event] = lines[pick]
    local text = lines[pick]
    if vars then
        text = string.gsub(text, "{(%w+)}", function(k)
            local v = vars[k]
            if v == nil then return "{" .. k .. "}" end
            return tostring(v)
        end)
    end
    return text
end

function Dealer:React(game, event, vars, seconds, fallback, quiet)
    if not Owns(game) then return end
    if quiet and Busy() then return end
    local text = self:Line(event, vars) or fallback
    if text then self:Say(game, text, seconds) end
end

-- What the dealer says between messages.
function Dealer:SetIdle(game, text)
    if not Owns(game) then return end
    idleText = text or ""
    if current then return end            -- shows after the message
    if not fade then ChangeTo(nil)
    elseif not fade.out then ui.text:SetText(idleText) end   -- already fading in
    -- (fading out: the new idle line is what fades in)
end

-- Back to the idle line now, dropping anything waiting.
function Dealer:Idle(game)
    if not Owns(game) then return end
    queue = {}
    if current or (fade and fade.msg) then ChangeTo(nil) end
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
