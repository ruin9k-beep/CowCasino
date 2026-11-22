-- CowCasino: the intro screen, the same for every game that has one. It sits
-- over the play field between games, so the field itself can use the whole
-- game area. Top to bottom:
--   the game's name, and a status line (what just happened)
--   Play solo: the game's own settings row (soloRow) and a Start button (soloGo)
--   Play with your group: a settings row (partyRow), a Host button (hostGo),
--     a note, and the tables or challenges open in the group, each with Join
--   the game's stats, at the foot
--
--   local intro = ns.Intro.New(panel, {
--       title = "Chess",
--       felt = { r, g, b, a },          -- the background (the game's felt)
--       solo = "Vs the computer",       -- the solo section's heading (nil: none)
--       party = "Play with your group", -- the party section's heading (nil: none)
--       rows = 4,                        -- how many open tables to list
--   })
--   intro.soloRow / intro.partyRow   frames 340 x 24 to put steppers in
--   intro.soloGo / intro.hostGo      buttons: set their text and state; clicks
--                                    call intro.onSolo / intro.onHost
--   intro:SetStatus(text), intro:SetNote(text), intro:SetStats(text)
--   intro:SetOffers({ { text = "Ann (plays White)", label = "Accept", enabled = true, click = fn,
--                       host = "Ann" (and anything else the game wants to keep with it) }, ... })
--   intro:Show(), intro:Hide(), intro:IsShown()

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

    local y = -58
    if spec.solo then
        self.soloHead = Heading(f, spec.solo, y)
        self.soloRow = Row(f, y - 22)
        self.soloGo = ns.UI.Button(f, "Play", 180, function() if self.onSolo then self.onSolo() end end, 26)
        self.soloGo:SetPoint("TOP", f, "TOP", 0, y - 54)
        y = y - 100
    end
    if spec.party then
        self.partyHead = Heading(f, spec.party, y)
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
            r:Hide()
            self.rows[i] = r
        end
    end

    self.stats = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.stats:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
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
            r:Show()
        else
            r:Hide()
        end
    end
end
