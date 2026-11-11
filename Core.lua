-- CowCasino: core
-- Namespace, 1.12 compatibility helpers, game registry, chip wallet,
-- saved variables and slash commands.
--
-- The 1.12 client runs Lua 5.0 and has no "..." addon namespace, so every
-- file reaches the shared namespace through the CowCasino global.

CowCasino = CowCasino or {}
CowCasino.ns = CowCasino.ns or {}
local ns = CowCasino.ns

local ADDON_NAME = "CowCasino"

ns.games = {}      -- id -> game definition
ns.gameOrder = {}  -- list of ids, in the order they appear on the menu
ns.partyGames = {} -- party modes shown inside a game's window (Party Blackjack, Party Craps)

local PREFIX = "|cffffd100CowCasino|r"

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. ": " .. tostring(msg))
end

---------------------------------------------------------------------------
-- 1.12 compatibility helpers
---------------------------------------------------------------------------
-- Lua 5.0 has no % operator, and math.mod keeps the sign of `a`.
function ns.Mod(a, b)
    local r = ns.mod(a, b)
    if r < 0 then r = r + b end
    return r
end

function ns.SetEnabled(widget, enabled)
    if enabled then widget:Enable() else widget:Disable() end
end

function ns.SetShown(widget, shown)
    if shown then widget:Show() else widget:Hide() end
end

-- 1.12's UIPanelButtonTemplate looks up its textures by the button's global
-- name, so a nameless button errors when clicked. Every templated button
-- gets a unique name from here.
local nameCount = 0
function ns:NewName()
    nameCount = nameCount + 1
    return "CowCasinoButton" .. nameCount
end

function ns.Trim(s)
    return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

-- Fonts bigger than the 1.12 templates offer.
function ns:BigFont(fs, size)
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 20)
    return fs
end

-- Sounds: games use the retail-style keys; these are the 1.12 names.
local SOUNDS = {
    IG_MAINMENU_OPTION              = "igMainMenuOption",
    IG_MAINMENU_OPTION_CHECKBOX_ON  = "igMainMenuOptionCheckBoxOn",
    IG_CHARACTER_INFO_OPEN          = "igCharacterInfoOpen",
    IG_CHARACTER_INFO_CLOSE         = "igCharacterInfoClose",
    LOOT_WINDOW_COIN_SOUND          = "LOOTWINDOWCOINSOUND",
    UI_EPICLOOT_TOAST               = "LEVELUPSOUND",
    RAID_WARNING                    = "RaidWarning",
}

function ns:Sound(key)
    local name = SOUNDS[key]
    if name then ns.PlaySound(name) end
end

-- Timers: ns:After(seconds, func). 1.12 has no C_Timer.
local timers = {}
local timerFrame = ns.CreateFrame("Frame")
timerFrame:Hide()
timerFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    local i = 1
    while i <= ns.getn(timers) do
        local t = timers[i]
        if now >= t.at then
            table.remove(timers, i)
            t.func()
        else
            i = i + 1
        end
    end
    if ns.getn(timers) == 0 then this:Hide() end
end)

function ns:After(delay, func)
    table.insert(timers, { at = GetTime() + delay, func = func })
    timerFrame:Show()
end

---------------------------------------------------------------------------
-- Game registry
-- A game is a table with:
--   id          unique string key
--   name        shown on the menu
--   description one short line under the name
--   icon        texture path for the menu row
--   Build(self, panel)   called once, the first time the game is opened
--   OnShow(self)         optional, every time the game is opened
--   OnHide(self)         optional, every time the player leaves the game
---------------------------------------------------------------------------
function ns:RegisterGame(game)
    assert(type(game) == "table" and game.id, "CowCasino: game needs an id")
    if self.games[game.id] then return end
    self.games[game.id] = game
    table.insert(self.gameOrder, game.id)
end

---------------------------------------------------------------------------
-- Chip wallet, shared by every game. Pretend chips only.
---------------------------------------------------------------------------
ns.START_CHIPS = 1000

-- 1234567 -> "1,234,567"; 12.5 -> "12.5"
function ns:FormatChips(n)
    n = n or 0
    if n == math.floor(n) then
        local s = tostring(math.floor(math.abs(n)))
        local out = ""
        while string.len(s) > 3 do
            out = "," .. string.sub(s, -3) .. out
            s = string.sub(s, 1, string.len(s) - 3)
        end
        return (n < 0 and "-" or "") .. s .. out
    end
    local s = string.format("%.2f", n)
    s = string.gsub(s, "0$", "")
    return s
end

function ns:SpendChips(amount)
    if amount <= 0 or self.db.chips < amount then return false end
    self.db.chips = self.db.chips - amount
    self:UpdateChipsDisplay()
    return true
end

-- Chips are always whole. Blackjack's odd amounts round in the player's
-- favor: a 3:2 blackjack and a surrender's half back round up, and so does
-- insurance (half the bet), so an insured hand still breaks even (or a chip
-- better) against a dealer blackjack.
function ns.BlackjackPay(bet) return bet + math.ceil(bet * 1.5) end   -- bet back plus 3:2
function ns.SurrenderBack(bet) return math.ceil(bet / 2) end
function ns.InsuranceCost(bet) return math.ceil(bet / 2) end

local function Whole(n) return math.floor((n or 0) + 0.5) end

function ns:AddChips(amount)
    self.db.chips = self.db.chips + Whole(amount)
    if self.db.chips > self.db.bestChips then self.db.bestChips = self.db.chips end
    self:UpdateChipsDisplay()
end

-- Out of chips: under 1 chip (the smallest bet any game takes) with nothing
-- still in play anywhere - no bet out, no spin turning, no seat at a table.
-- Each game reports its own chips in play with game:ChipsInPlay().
-- MainMenu.lua then sends you to the menu to pick a fresh stack.
ns.REBUY_AMOUNTS = { 1000, 10000, 50000 }

function ns:ChipsInPlay()
    for _, game in pairs(self.games) do
        if game.ChipsInPlay and game:ChipsInPlay() then return true end
    end
    for _, party in ipairs(self.partyGames) do   -- part of a game's window, not menu games
        if party.ChipsInPlay and party:ChipsInPlay() then return true end
    end
    return false
end

function ns:IsBroke()
    return self.db.chips < 1 and not self:ChipsInPlay()
end

-- Status text for a game whose smallest bet you can't cover.
function ns:LowChipsText(minBet)
    if self.db.chips < 1 then return "Out of chips! Back to the menu for a fresh stack..." end
    return "Not enough chips for the smallest bet here (" .. self:FormatChips(minBet) .. "). Try another game."
end

-- A fresh stack is a fresh start: every game's stats begin again, and so
-- does your best chip count. (Each game resets its own with ResetStats.)
function ns:RebuyChips(amount)
    self.db.chips = amount or self.START_CHIPS
    self.db.rebuys = self.db.rebuys + 1
    self.db.bestChips = self.db.chips
    for _, game in pairs(self.games) do
        if game.ResetStats then game:ResetStats() end
    end
    for _, party in ipairs(self.partyGames) do   -- part of a game's window, not menu games
        if party.ResetStats then party:ResetStats() end
    end
    self:UpdateChipsDisplay()
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local defaults = {
    point = { "CENTER", "CENTER", 0, 0 },
    cardArt = "plain",   -- id of the selected card art pack (Cards.lua)
    minimap = { angle = 225, hide = false },
}

local loader = ns.CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function()
    if arg1 ~= ADDON_NAME then return end
    this:UnregisterEvent("ADDON_LOADED")

    CowCasinoDB = CowCasinoDB or {}
    for k, v in pairs(defaults) do
        if CowCasinoDB[k] == nil then CowCasinoDB[k] = v end
    end
    ns.db = CowCasinoDB

    local db = CowCasinoDB
    if db.chips == nil then db.chips = ns.START_CHIPS end
    db.bestChips = db.bestChips or db.chips
    db.rebuys = db.rebuys or 0

    -- Older versions could leave half chips (Blackjack 3:2 and insurance):
    -- round them, rounding a half up.
    db.chips = Whole(db.chips)
    db.bestChips = Whole(db.bestChips)
    if db.partybj and db.partybj.seat and db.partybj.seat.stack then
        db.partybj.seat.stack = Whole(db.partybj.seat.stack)
    end
    if db.holdem and db.holdem.seat and db.holdem.seat.stacks then
        for i, n in pairs(db.holdem.seat.stacks) do db.holdem.seat.stacks[i] = Whole(n) end
    end

    -- Pachinko was removed in 0.23: balls left in its tray (or in flight at
    -- logout) are cashed in at the 1 chip each they cost.
    local refund
    if db.pachinko then
        refund = (db.pachinko.tray or 0) + (db.pachinko.inFlight or 0)
        if refund > 0 then db.chips = db.chips + refund end
        db.pachinko = nil
    end

    ns:BuildMainFrame()
    ns:BuildMinimapButton()
    ns:Print("loaded. Type /casino to open.")
    if refund and refund > 0 then
        ns:Print("Pachinko has closed: your " .. refund .. " balls were cashed in for " .. ns:FormatChips(refund) .. " chips.")
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_COWCASINO1 = "/casino"
SlashCmdList["COWCASINO"] = function(msg)
    msg = strlower(ns.Trim(msg))
    if msg == "reset" then
        ns:SetScale(1)
        ns.db.point = { "CENTER", "CENTER", 0, 0 }
        ns:RestorePosition()
        ns:Print("window position and size reset.")
    elseif msg == "minimap" then
        ns:SetMinimapButtonShown(ns.db.minimap.hide)
        ns:Print(ns.db.minimap.hide and "minimap button hidden. Type /casino minimap to bring it back."
            or "minimap button shown.")
    elseif msg == "help" then
        ns:Print("/casino - open or close the casino")
        ns:Print("/casino reset - move the window back to the center, at normal size")
        ns:Print("/casino minimap - show or hide the minimap button")
    else
        ns:Toggle()
    end
end
