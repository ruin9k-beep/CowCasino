-- CowCasino: the intro screen, part of the core: every game has one. It sits
-- over the play field between rounds, so the field needs no setup controls
-- of its own.
--
-- What it holds, top to bottom:
--   the game's name, and a status line (what just happened)
--   Play solo: the game's settings row (soloRow) and a Start button (soloGo)
--   Play with your group: a settings row (partyRow), a Host button (hostGo),
--     a note, and the tables or challenges open in the group, each with Join
--   the game's stats, at the foot
-- A game that doesn't make its own gets a simple one when it's first opened:
-- its name, its description, Play, and its stats (game:IntroStats(), if it
-- has that).
--
-- When it shows: each game says where it stands with game:IntroState():
--   "busy"   a round or game is on: the field shows (this is also the answer,
--            for a game without IntroState, while it has chips in play)
--   "idle"   between rounds: the intro shows when the game is opened, Play
--            goes to the field, and the window's back button (< Setup) comes
--            back to the intro
--   "intro"  nothing to show on the field (no table to sit at): the intro stays
-- A game can also offer to skip its intro: game:SkipIntro() true opens it
-- straight onto the field when it's idle (the back button still goes there).
-- The back button steps back a screen: the field, then the intro, then the
-- game list.
--
-- A game makes its own intro in Build:
--   local intro = ns:AddIntro(game, panel, {
--       solo = "Vs the computer",        -- the solo section's heading (nil: none)
--       party = "Play with your group",  -- the party section's heading (nil: none)
--       rows = 4,                         -- how many open tables to list
--       felt = { r, g, b, a },            -- the background (the game's felt)
--       blurb = "...",                    -- a word on the game, under its name
--       refresh = true,                   -- a Refresh button by the party heading (intro.onRefresh)
--   })
--   intro.soloRow / intro.partyRow   frames 340 x 24 to put steppers in
--   intro.soloGo / intro.hostGo      buttons: set their text and state; clicks
--                                    call intro.onSolo / intro.onHost
--   intro:SetStatus(text), intro:SetNote(text), intro:SetStats(text)
--   intro:SetOffers({ { text = "Ann (plays White)", label = "Accept", enabled = true, click = fn,
--                       host = "Ann" (and anything else the game wants to keep with it) }, ... })
--   intro:WatchLobby(id)             list game id's open tables from the lobby hub
-- and calls ns:UpdateIntro(game) when its state changes (the core also checks
-- a few times a second).

local ns = CowCasino.ns

local Intro = {}
Intro.__index = Intro
ns.Intro = Intro

local W = 340          -- the sections' width
local ROW_H = 26       -- an open table's row

local function Heading(f, text, y)
    local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
    h:SetText(text)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", h, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    line:SetTexture(1, 0.82, 0, 0.35)
    return h
end

local function Row(f, y)
    local r = ns.CreateFrame("Frame", nil, f)
    r:SetWidth(W); r:SetHeight(24)
    r:SetPoint("TOP", f, "TOP", 0, y)
    return r
end

function Intro.New(panel, spec)
    local self = setmetatable({}, Intro)
    local f = ns.CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)
    f:SetFrameLevel(panel:GetFrameLevel() + 20)
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    local felt = spec.felt or { 0.05, 0.16, 0.08, 1 }
    bg:SetTexture(felt[1], felt[2], felt[3], 1)
    local shade = f:CreateTexture(nil, "BORDER")
    shade:SetAllPoints(f)
    shade:SetTexture(0, 0, 0, 0.35)
    self.frame = f

    local title = ns:BigFont(f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 20)
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText(spec.title or "")
    self.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.status:SetPoint("TOP", title, "BOTTOM", 0, -6)
    self.status:SetWidth(W)

    if spec.simple then
        -- just the game: its description and Play
        local blurb = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        blurb:SetPoint("TOP", f, "TOP", 0, -90)
        blurb:SetWidth(W - 20)
        blurb:SetText(spec.blurb or "")
        self.blurb = blurb
        self.soloGo = ns.UI.Button(f, "Play", 200, function() if self.onSolo then self.onSolo() end end, 30)
        self.soloGo:SetPoint("TOP", f, "TOP", 0, -170)
    end

    local y = -58
    if spec.blurb and not spec.simple then
        -- a word on the game, under the title
        local blurb = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        blurb:SetPoint("TOP", f, "TOP", 0, -52)
        blurb:SetWidth(W)
        blurb:SetText(spec.blurb)
        self.blurb = blurb
        y = y - 26
    end
    if spec.solo then
        self.soloHead = Heading(f, spec.solo, y)
        self.soloRow = Row(f, y - 22)
        self.soloGo = ns.UI.Button(f, "Play", 180, function() if self.onSolo then self.onSolo() end end, 26)
        self.soloGo:SetPoint("TOP", f, "TOP", 0, y - 54)
        y = y - 100
    end
    if spec.party then
        self.partyHead = Heading(f, spec.party, y)
        if spec.refresh then
            -- ask the group again who's hosting
            self.refresh = ns.UI.Button(f, "Refresh", 64, function() if self.onRefresh then self.onRefresh() end end, 18)
            self.refresh:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, y + 2)
        end
        self.partyRow = Row(f, y - 22)
        self.hostGo = ns.UI.Button(f, "Host", 180, function() if self.onHost then self.onHost() end end, 26)
        self.hostGo:SetPoint("TOP", f, "TOP", 0, y - 54)
        self.note = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        self.note:SetPoint("TOP", f, "TOP", 0, y - 88)
        self.note:SetWidth(W)
        self.rows = {}
        for i = 1, spec.rows or 4 do
            local i = i
            local r = ns.CreateFrame("Frame", nil, f)
            r:SetWidth(W - 20); r:SetHeight(ROW_H - 2)
            r:SetPoint("TOP", f, "TOP", 0, y - 104 - (i - 1) * ROW_H)
            local rbg = r:CreateTexture(nil, "BORDER")
            rbg:SetAllPoints(r)
            rbg:SetTexture(0, 0, 0, 0.3)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
            r.text:SetWidth(W - 110)
            r.text:SetJustifyH("LEFT")
            r.join = ns.UI.Button(r, "Join", 70, function()
                local o = self.rows[i].offer
                if o and o.click then o.click() end
            end, 20)
            r.join:SetPoint("RIGHT", r, "RIGHT", -2, 0)
            r.watch = ns.UI.Button(r, "Watch", 62, function()
                local o = self.rows[i].offer
                if o and o.watch then o.watch() end
            end, 20)
            r.watch:SetPoint("RIGHT", r.join, "LEFT", -4, 0)
            r.watch:Hide()
            r:Hide()
            self.rows[i] = r
        end
    end

    self.stats = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.stats:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
    self.stats:SetWidth(W)
    f:Hide()
    return self
end

function Intro:Show() self.frame:Show() end
function Intro:Hide() self.frame:Hide() end
function Intro:IsShown() return self.frame:IsShown() end
function Intro:SetShown(on) ns.SetShown(self.frame, on) end
function Intro:SetStatus(text) self.status:SetText(text or "") end
function Intro:SetNote(text) if self.note then self.note:SetText(text or "") end end
function Intro:SetStats(text) self.stats:SetText(text or "") end

-- The open tables in game id, from the lobby hub (Lobby.lua), each with
-- Join; refreshed every second while the intro is up.
function Intro:WatchLobby(id)
    self.lobbyId = id
    table.insert(ns.Lobby.intros, self)
    self:ShowLobby()
end

function Intro:ShowLobby()
    local id = self.lobbyId
    local spec = id and ns.Lobby.specs[id]
    if not spec then return end
    local rows = {}
    for _, o in ipairs(ns.Lobby:Offers(id)) do
        local host = o.host
        table.insert(rows, { host = host, text = o.text or (host .. "'s table"),
            click = function()
                local why = spec.join(host)
                if why then ns:Print(why) end
            end })
    end
    table.sort(rows, function(a, b) return a.host < b.host end)
    self:SetOffers(rows)
    self:SetNote(rows[1] and "Tables open in your group:"
        or (ns.Net:InGroup() and "No tables open in your group yet." or "Join a party or raid to play your friends."))
end

function Intro:SetOffers(list)
    if not self.rows then return end
    for i, r in ipairs(self.rows) do
        local o = list and list[i]
        r.offer = o
        if o then
            r.text:SetText(o.text or "")
            r.join:SetText(o.label or "Join")
            ns.SetEnabled(r.join, o.enabled ~= false)
            ns.SetShown(r.watch, o.watch ~= nil)
            r.text:SetWidth(W - (o.watch and 176 or 110))
            r:Show()
        else
            r:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- The core's part: every game's intro, when it shows, and the back button
---------------------------------------------------------------------------
function ns:AddIntro(game, panel, spec)
    spec.title = spec.title or game.name
    local intro = Intro.New(panel, spec)
    game.intro = intro
    game.introUp = true
    return intro
end

-- A game that didn't make its own: its name, description, Play and stats.
function ns:DefaultIntro(game)
    local intro = self:AddIntro(game, game.panel, { simple = true, blurb = game.description, felt = game.introFelt })
    intro.onSolo = function()
        game.introUp = false
        ns:Sound("IG_MAINMENU_OPTION")
        ns:UpdateIntro(game)
    end
    return intro
end

function ns:IntroState(game)
    if game.IntroState then return game:IntroState() end
    if game.ChipsInPlay and game:ChipsInPlay() then return "busy" end
    return "idle"
end

-- Show or hide the game's intro, as its state says; and the back button.
function ns:UpdateIntro(game)
    local intro = game and game.intro
    if not intro then return end
    local state = self:IntroState(game)
    if state == "busy" then game.introUp = false
    elseif state == "intro" then game.introUp = true end
    intro:SetShown(game.introUp and state ~= "busy")
    if self.currentGame == game.id and self.frame and self.frame.back then
        self.frame.back:SetText((not intro:IsShown() and state == "idle") and "< Setup" or "< Games")
    end
end

function ns:ShowIntro(game)
    if not (game and game.intro) then return end
    game.introUp = true
    self:UpdateIntro(game)
end

-- The game was opened: between rounds, it starts on its intro.
function ns:OpenIntro(game)
    if not game.intro and game.panel and not game.noIntro then self:DefaultIntro(game) end
    if not game.intro then return end
    if game.IntroStats and game.intro.stats then game.intro:SetStats(game:IntroStats()) end
    local state = self:IntroState(game)
    if state ~= "busy" then game.introUp = true end
    -- (a player who'd rather go straight to the field: game:SkipIntro())
    if state == "idle" and game.SkipIntro and game:SkipIntro() then game.introUp = false end
    self:UpdateIntro(game)
end

-- The window's back button: from the field to the intro, else to the games.
function ns:Back()
    local game = self.currentGame and self.games[self.currentGame]
    if game and game.intro and not game.intro:IsShown() and self:IntroState(game) == "idle" then
        ns:Sound("IG_MAINMENU_OPTION")
        self:ShowIntro(game)
        return
    end
    ns:Sound("IG_MAINMENU_OPTION")
    self:ShowMenu()
end

-- a few times a second: the game on screen, in case its state moved on
ns:Every(0.25, function()
    local id = ns.currentGame
    local game = id and ns.games[id]
    if game and game.intro then
        ns:UpdateIntro(game)
        if game.IntroStats and game.intro:IsShown() then game.intro:SetStats(game:IntroStats()) end
    end
end)
