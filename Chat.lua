-- CowCasino: table chat
-- A chat panel that flies out from the left or right side of the window,
-- for the players at your party table (Hold'em or Blackjack party play).
-- It has its own box to type in and its own hidden addon messages: it never
-- reads or sends party, raid or say chat. Each message shows the sender's 3D
-- portrait when the game has one for them (they're nearby).
-- An arrow on the window's edge opens and closes it; it's only there while
-- you're at a party table. Its settings are in the CowCasino Options.
--
-- Games report the table you're at with game:ChatTable(), returning
--   { game = "HE", host = "Name", tid = "123", members = { Name = true, ... } }
-- or nil when you're not at a party table.

local ns = CowCasino.ns
local Net = ns.Net

local TAG        = "CH"
local MAX_LEN    = 200     -- letters per message
local HISTORY    = 80      -- rows kept
local FLY_W      = 230
local ROW_H      = 46
local PORTRAIT   = 38
local ROW_CHARS  = 90      -- about three lines of small text beside a portrait
local EDGE       = 30      -- the totem poles reach this far past the window's side edge

local Chat = { rows = {}, scroll = 0, unread = 0 }
ns.Chat = Chat

local DEFAULTS = { enabled = true, side = "right", autoOpen = true, open = false }

function Chat:Settings()
    ns.db.chat = ns.db.chat or {}
    local s = ns.db.chat
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    return s
end

-- The party table you're at, from whichever game has one.
function ns:ChatTable()
    for _, game in pairs(self.games) do
        if game.ChatTable then
            local t = game:ChatTable()
            if t then return t end
        end
    end
    for _, party in ipairs(self.partyGames) do   -- part of a game's window, not menu games
        if party.ChatTable then
            local t = party:ChatTable()
            if t then return t end
        end
    end
    return nil
end

local function TableKey(t)
    return t and (t.game .. ";" .. t.host .. ";" .. t.tid) or nil
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
-- No color codes or links from other players: show a "|" as typed.
local function Clean(text)
    text = string.gsub(text or "", "[\r\n\t]", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if string.len(text) > MAX_LEN then text = string.sub(text, 1, MAX_LEN) end
    return text
end

local function Shown(text)
    return (string.gsub(text, "|", "||"))
end

-- Break a message into rows, at spaces where possible.
local function Chunks(text)
    local out = {}
    while string.len(text) > ROW_CHARS do
        local cut = ROW_CHARS
        for i = ROW_CHARS, math.floor(ROW_CHARS / 2), -1 do
            if string.sub(text, i, i) == " " then cut = i break end
        end
        table.insert(out, string.sub(text, 1, cut))
        text = string.gsub(string.sub(text, cut + 1), "^%s+", "")
    end
    table.insert(out, text)
    return out
end

function Chat:AddLine(name, text, system)
    local added = 0
    for i, chunk in ipairs(Chunks(text)) do
        table.insert(self.rows, { name = name, text = chunk, first = (i == 1), system = system })
        added = added + 1
    end
    while ns.getn(self.rows) > HISTORY do table.remove(self.rows, 1) end
    if self.scroll > 0 then
        self.scroll = math.min(self.scroll + added, math.max(0, ns.getn(self.rows) - 1))
    end
    if not system and name ~= Net:Me() and self.ui then
        local s = self:Settings()
        if not s.open then
            if s.autoOpen then
                self:SetOpen(true)
            else
                self.unread = self.unread + 1
            end
        end
    end
    self:Refresh()
end

function Chat:Send(text)
    text = Clean(text)
    if text == "" then return false end
    local t = ns:ChatTable()
    if not t then return false end
    Net:Send(TAG .. ";" .. t.game .. ";" .. t.host .. ";" .. t.tid .. ";" .. text)
    self:AddLine(Net:Me(), text)
    return true
end

-- From the group: kept only if it's for your table and from a player at it.
Net.handlers[TAG] = function(sender, f)
    local t = ns:ChatTable()
    if not t or f[2] ~= t.game or f[3] ~= t.host or f[4] ~= t.tid then return end
    if not t.members[sender] then return end
    local parts = {}
    for i = 5, ns.getn(f) do table.insert(parts, f[i]) end
    local text = Clean(table.concat(parts, ";"))
    if text == "" then return end
    Chat:Check()          -- a new table starts a fresh history before this line goes in
    Chat:AddLine(sender, text)
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local ARROW_RIGHT = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
local ARROW_LEFT  = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-"

local function SetArrow(b, base)
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
end

function Chat:Build(frame)
    local ui = {}
    self.ui = ui

    -- The arrow on the window's edge
    local toggle = ns.CreateFrame("Button", nil, frame)
    toggle:SetWidth(28); toggle:SetHeight(28)
    toggle:SetFrameLevel(frame:GetFrameLevel() + 20)
    toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    toggle:SetScript("OnClick", function()
        ns:Sound("IG_MAINMENU_OPTION")
        Chat:SetOpen(not Chat:Settings().open)
    end)
    toggle:Hide()
    ui.toggle = toggle
    local badge = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetPoint("BOTTOM", toggle, "TOP", 0, -2)
    ui.badge = badge

    -- The flyout
    local fly = ns.CreateFrame("Frame", nil, frame)
    fly:SetWidth(FLY_W)
    fly:SetFrameLevel(frame:GetFrameLevel() + 5)
    fly:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    fly:SetBackdropColor(0.16, 0.10, 0.06, 0.96)
    fly:SetBackdropBorderColor(0.75, 0.58, 0.15, 1)
    fly:EnableMouse(true)
    fly:Hide()
    ui.fly = fly

    local title = fly:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", fly, "TOPLEFT", 10, -9)
    title:SetText("Table chat")
    ui.where = fly:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.where:SetPoint("TOPRIGHT", fly, "TOPRIGHT", -10, -11)
    ui.where:SetWidth(FLY_W - 100)
    ui.where:SetJustifyH("RIGHT")

    -- Message rows, newest at the bottom
    local height = frame:GetHeight() - 2 * 12
    local count = math.floor((height - 30 - 36) / ROW_H)
    ui.rows = {}
    for i = 1, count do
        local r = {}
        local y = -30 - (i - 1) * ROW_H
        r.portrait = ns:CreatePortrait(fly, PORTRAIT, PORTRAIT)
        r.portrait:SetPoint("TOPLEFT", fly, "TOPLEFT", 8, y - 2)
        r.blank = fly:CreateTexture(nil, "ARTWORK")
        r.blank:SetPoint("TOPLEFT", fly, "TOPLEFT", 8, y - 2)
        r.blank:SetWidth(PORTRAIT); r.blank:SetHeight(PORTRAIT)
        r.blank:SetTexture(0, 0, 0, 0.35)
        r.name = fly:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.name:SetPoint("TOPLEFT", fly, "TOPLEFT", 52, y)
        r.name:SetWidth(FLY_W - 62)
        r.name:SetJustifyH("LEFT")
        r.text = fly:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetWidth(FLY_W - 62)
        r.text:SetJustifyH("LEFT")
        r.text:SetJustifyV("TOP")
        r.y = y
        ui.rows[i] = r
    end
    fly:EnableMouseWheel(true)
    fly:SetScript("OnMouseWheel", function()
        local n = ns.getn(Chat.rows)
        Chat.scroll = math.max(0, math.min(Chat.scroll + (arg1 > 0 and 1 or -1), math.max(0, n - count)))
        Chat:Refresh()
    end)

    -- Where you type: its own box, never the game's chat
    local box = ns.CreateFrame("EditBox", nil, fly)
    box:SetHeight(22)
    box:SetPoint("BOTTOMLEFT", fly, "BOTTOMLEFT", 8, 8)
    box:SetPoint("BOTTOMRIGHT", fly, "BOTTOMRIGHT", -8, 8)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(MAX_LEN)
    box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.8)
    box:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", box, "LEFT", 7, 0)
    hint:SetText("Say something to the table...")
    local function UpdateHint() ns.SetShown(hint, (box:GetText() or "") == "" and not box.focused) end
    box:SetScript("OnEditFocusGained", function() box.focused = true UpdateHint() end)
    box:SetScript("OnEditFocusLost", function() box.focused = nil UpdateHint() end)
    box:SetScript("OnTextChanged", UpdateHint)
    box:SetScript("OnEnterPressed", function()
        Chat:Send(this:GetText())
        this:SetText("")
        this:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function()
        this:SetText("")
        this:ClearFocus()
    end)
    ui.box = box

    -- Notices joining and leaving tables, and portraits coming into range.
    -- (Not inside the window, so it keeps up while the window is closed.)
    local watch = ns.CreateFrame("Frame")
    local wait = 0
    watch:SetScript("OnUpdate", function()
        wait = wait + arg1
        if wait < 0.5 then return end
        wait = 0
        Chat:Check()
    end)

    self:Layout()
    self:Check()
end

-- Put the arrow and the flyout on the chosen side.
function Chat:Layout()
    local ui = self.ui
    if not ui then return end
    local frame = ns.frame
    local right = self:Settings().side ~= "left"
    ui.toggle:ClearAllPoints()
    ui.fly:ClearAllPoints()
    if right then
        ui.toggle:SetPoint("CENTER", frame, "RIGHT", EDGE, 0)
        ui.fly:SetPoint("TOPLEFT", frame, "TOPRIGHT", EDGE + 6, -12)
        ui.fly:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", EDGE + 6, 12)
    else
        ui.toggle:SetPoint("CENTER", frame, "LEFT", -EDGE, 0)
        ui.fly:SetPoint("TOPRIGHT", frame, "TOPLEFT", -EDGE - 6, -12)
        ui.fly:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -EDGE - 6, 12)
    end
    self:Refresh()
end

function Chat:SetOpen(open)
    local s = self:Settings()
    s.open = open and true or false
    if s.open then self.unread = 0 end
    if not s.open and self.ui then self.ui.box:ClearFocus() end
    self:Refresh()
end

-- Keep up with the table you're at: a new table starts a fresh chat.
function Chat:Check()
    local t = ns:ChatTable()
    local key = TableKey(t)
    if key ~= self.key then
        self.key = key
        self.rows, self.scroll, self.unread = {}, 0, 0
        if t then
            local whose = (t.host == Net:Me()) and "your" or (t.host .. "'s")
            self.where = "at " .. whose .. " table"
            self:AddLine(nil, "Only the players at " .. whose .. " table see this chat.", true)
        end
    end
    self:Refresh()
end

function Chat:Refresh()
    local ui = self.ui
    if not ui then return end
    local s = self:Settings()
    local available = s.enabled and self.key ~= nil
    ns.SetShown(ui.toggle, available)
    ns.SetShown(ui.fly, available and s.open)
    if not available then
        ui.box:ClearFocus()
        return
    end
    local right = s.side ~= "left"
    -- the arrow points the way the panel will move
    if s.open == right then SetArrow(ui.toggle, ARROW_LEFT) else SetArrow(ui.toggle, ARROW_RIGHT) end
    ui.badge:SetText(self.unread > 0 and ("|cff40ff40" .. self.unread .. "|r") or "")
    ui.where:SetText(self.where or "")
    if not s.open then return end

    local n, count = ns.getn(self.rows), ns.getn(ui.rows)
    local last = n - self.scroll
    for i = 1, count do
        local r = ui.rows[i]
        local row = self.rows[last - count + i]
        r.text:ClearAllPoints()
        if not row then
            r.portrait:ShowUnit(nil); r.blank:Hide(); r.name:SetText(""); r.text:SetText("")
        elseif row.system then
            r.portrait:ShowUnit(nil); r.blank:Hide(); r.name:SetText("")
            r.text:SetPoint("TOPLEFT", ui.fly, "TOPLEFT", 10, r.y - 4)
            r.text:SetWidth(FLY_W - 20); r.text:SetHeight(ROW_H - 6)
            r.text:SetText("|cff9d9d9d" .. Shown(row.text) .. "|r")
        else
            r.text:SetWidth(FLY_W - 62)
            if row.first then
                local unit = Net:UnitFor(row.name)
                if unit and UnitIsVisible(unit) then
                    r.portrait:ShowUnit(unit); r.blank:Hide()
                else
                    r.portrait:ShowUnit(nil); r.blank:Show()   -- no model for them right now
                end
                local color = (row.name == Net:Me()) and "|cff40ff40" or "|cffffd100"
                r.name:SetText(color .. row.name .. "|r")
                r.text:SetPoint("TOPLEFT", ui.fly, "TOPLEFT", 52, r.y - 12)
                r.text:SetHeight(ROW_H - 12)
            else
                r.portrait:ShowUnit(nil); r.blank:Hide(); r.name:SetText("")
                r.text:SetPoint("TOPLEFT", ui.fly, "TOPLEFT", 52, r.y)
                r.text:SetHeight(ROW_H)
            end
            r.text:SetText(Shown(row.text))
        end
    end
end
