-- CowCasino: the lobby hub, the same for every multiplayer game.
--   * When someone in your group opens a table or puts up a challenge, a
--     pop-up says so; click it to open that game and join. (Right-click, or
--     the x, puts it away. Options > Games turns these pop-ups off; invites
--     always show.)
--   * While anything is open in your group, the minimap button and that
--     game's tile carry a count.
--   * While you're hosting, an Invite button sits in the window's title row:
--     invite someone by name (anyone not in your group is invited to it
--     first, and gets the table invite once they've joined), your target, or
--     the whole group.
--
-- Each game registers what only it knows:
--   ns.Lobby:Register("chess", {
--       offers  = function() return { { host = "Name", key = "id" }, ... } end,
--                 -- others' tables or challenges you could join now
--       ask     = function() end,         -- ask the group who's hosting
--       join    = function(host) end,     -- the game is on screen: join host's table
--                                         -- (returns a reason when it can't)
--       hosting = function() return true end,   -- you host a table / have a challenge up
--       busy    = function() return true end,   -- you're at a table or in a game of it
--       noun    = "table",                       -- "table", "challenge" or "game"
--   })
-- Message: LB;I;<game id>;<to>, an invite ("*": everyone in the group).

local ns = CowCasino.ns
local Net = ns.Net

local Lobby = { specs = {}, order = {}, seen = {}, invited = {}, queue = {}, pending = {}, intros = {} }
ns.Lobby = Lobby

Lobby.TOAST_TIME  = 20      -- seconds a pop-up stays up
Lobby.JOIN_WAIT   = 12      -- after clicking one: how long to wait to hear the host's table
Lobby.INVITE_WAIT = 120     -- someone invited to the group: how long to wait for them to join it
local POLL = 1

function Lobby:Register(id, spec)
    if not self.specs[id] then table.insert(self.order, id) end
    self.specs[id] = spec
end

local function Lower(s) return string.lower(s or "") end

local function GameName(id)
    local g = ns.games[id]
    return (g and g.name) or id
end

-- Others' open tables in a game (members of the group only).
function Lobby:Offers(id)
    local spec = self.specs[id]
    if not spec or not Net:InGroup() then return {} end
    local out, me = {}, Net:Me()
    for _, o in ipairs(spec.offers() or {}) do
        if o.host and o.host ~= me and Net:IsMember(o.host) then table.insert(out, o) end
    end
    return out
end

function Lobby:Busy(id)
    local spec = self.specs[id]
    return (spec and spec.busy and spec.busy()) and true or false
end

function Lobby:Hosting(id)
    local spec = self.specs[id]
    return (spec and spec.hosting and spec.hosting()) and true or false
end

-- Hosts with something open, by game (games you're busy in left out).
function Lobby:Open()
    local out, total = {}, 0
    for _, id in ipairs(self.order) do
        if not self:Busy(id) then
            local hosts = {}
            for _, o in ipairs(self:Offers(id)) do table.insert(hosts, o.host) end
            if hosts[1] then
                table.sort(hosts)
                out[id] = hosts
                total = total + ns.getn(hosts)
            end
        end
    end
    return out, total
end

---------------------------------------------------------------------------
-- Pop-ups
---------------------------------------------------------------------------
local function ToastText(item)
    local spec = Lobby.specs[item.id] or {}
    local name = "|cffffd100" .. GameName(item.id) .. "|r"
    if item.invite then return item.host .. " invites you to " .. name .. "." end
    if spec.noun == "challenge" then return item.host .. " challenges the group to " .. name .. "." end
    if spec.noun == "game" then return item.host .. " is hosting " .. name .. "." end
    return item.host .. " opened a " .. name .. " table."
end

function Lobby:BuildToast()
    if self.toast then return self.toast end
    local t = ns.CreateFrame("Button", "CowCasinoLobbyToast", UIParent)
    t:SetWidth(300); t:SetHeight(62)
    t:SetPoint("TOP", UIParent, "TOP", 0, -120)
    t:SetFrameStrata("DIALOG")
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    t:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    t:SetBackdropColor(0.04, 0.05, 0.10, 0.94)
    t:SetBackdropBorderColor(0.35, 0.65, 1, 1)
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", t, "TOPLEFT", 4, -4)
    hl:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -4, 4)
    hl:SetTexture(0.35, 0.65, 1, 0.15)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetWidth(36); t.icon:SetHeight(36)
    t.icon:SetPoint("LEFT", t, "LEFT", 9, 0)
    -- (room for two lines of text: a long name wraps it)
    t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t.text:SetPoint("TOPLEFT", t, "TOPLEFT", 53, -9)
    t.text:SetWidth(222)
    t.text:SetJustifyH("LEFT")
    t.hint = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.hint:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 53, 8)
    t.hint:SetText("Click to join.  |cff999999Right-click to close.|r")
    t.close = ns.CreateFrame("Button", nil, t, "UIPanelCloseButton")
    t.close:SetWidth(24); t.close:SetHeight(24)
    t.close:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
    t.close:SetScript("OnClick", function() Lobby:CloseToast() end)
    t:SetScript("OnClick", function()
        if arg1 == "RightButton" then Lobby:CloseToast() else Lobby:Take(Lobby.current) end
    end)
    t:SetScript("OnUpdate", function()
        if Lobby.current and GetTime() >= (Lobby.current.untilT or 0) then Lobby:CloseToast() end
    end)
    t:Hide()
    self.toast = t
    return t
end

-- Show a pop-up (or queue it behind the one showing). item: id, host, invite.
function Lobby:Toast(item)
    local same = function(a) return a and a.id == item.id and a.host == item.host end
    if same(self.current) then
        if item.invite and not self.current.invite then
            self.current.invite = true
            self.toast.text:SetText(ToastText(self.current))
        end
        self.current.untilT = GetTime() + self.TOAST_TIME
        return
    end
    for _, q in ipairs(self.queue) do
        if same(q) then
            if item.invite then q.invite = true end
            return
        end
    end
    table.insert(self.queue, item)
    if not self.current then self:NextToast() end
end

function Lobby:NextToast()
    local t = self:BuildToast()
    local item = table.remove(self.queue, 1)
    self.current = item
    if not item then t:Hide() return end
    item.untilT = GetTime() + self.TOAST_TIME
    local g = ns.games[item.id]
    t.icon:SetTexture((g and g.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
    t.text:SetText(ToastText(item))
    t:Show()
    ns:Sound("IG_PLAYER_INVITE")
end

function Lobby:CloseToast()
    self.current = nil
    self:NextToast()
end

-- A pop-up was clicked: open the game and join (once its host is heard).
function Lobby:Take(item)
    if not item then return end
    self:CloseToast()
    -- the rest of the queue for this game would only repeat this one
    for i = ns.getn(self.queue), 1, -1 do
        if self.queue[i].id == item.id then table.remove(self.queue, i) end
    end
    local f = ns.frame
    if not f then return end
    if not f:IsShown() then ns:Toggle() end
    if ns.currentGame ~= item.id then ns:OpenGame(item.id) end
    if ns.currentGame ~= item.id then return end
    self.want = { id = item.id, host = item.host, untilT = GetTime() + self.JOIN_WAIT }
    if not self:TryJoin() then
        local spec = self.specs[item.id]
        if spec and spec.ask then spec.ask() end
    end
end

-- True when the wanted table was found (and asked to join) or given up on.
function Lobby:TryJoin()
    local w = self.want
    if not w then return true end
    local spec = self.specs[w.id]
    if not spec then self.want = nil return true end
    for _, o in ipairs(self:Offers(w.id)) do
        if o.host == w.host then
            self.want = nil
            local why = spec.join(w.host)
            if why then ns:Print(why) end
            return true
        end
    end
    if GetTime() >= w.untilT then
        self.want = nil
        ns:Print("Couldn't find " .. w.host .. "'s " .. (spec.noun or "table") .. " in " .. GameName(w.id) .. ". It may have closed.")
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Inviting
---------------------------------------------------------------------------
-- The group member called name (any case), or nil.
local function Member(name)
    local want = Lower(name)
    if want == Lower(Net:Me()) then return Net:Me() end
    if ns.NumRaid() > 0 then
        for i = 1, ns.NumRaid() do
            local n = UnitName("raid" .. i)
            if n and Lower(n) == want then return n end
        end
    else
        for i = 1, ns.NumParty() do
            local n = UnitName("party" .. i)
            if n and Lower(n) == want then return n end
        end
    end
end

local function SendInvite(id, to)
    Net:Send("LB;I;" .. id .. ";" .. to)
end

-- Invite someone to your table in game id. Returns what happened, to show.
function Lobby:Invite(id, name)
    name = ns.Trim(name)
    if name == "" then return "Type a name, or use your target." end
    if string.find(name, "[;~]") then return "That isn't a name." end
    if Lower(name) == Lower(Net:Me()) then return "That's you." end
    local member = Member(name)
    if member then
        SendInvite(id, member)
        return "Invited " .. member .. "."
    end
    ns.InviteToGroup(name)
    self.pending[Lower(name)] = { id = id, name = name, untilT = GetTime() + self.INVITE_WAIT }
    return "Invited " .. name .. " to your group. The table invite follows once they join."
end

function Lobby:InviteGroup(id)
    if not Net:InGroup() then return "You're not in a group. Invite someone by name." end
    SendInvite(id, "*")
    return "Invited everyone in your group."
end

-- Anyone invited to the group who has joined it gets their table invite.
function Lobby:CheckPending()
    local now = GetTime()
    for key, p in pairs(self.pending) do
        local member = Member(p.name)
        if member and member ~= Net:Me() then
            self.pending[key] = nil
            if self:Hosting(p.id) then SendInvite(p.id, member) end
        elseif now >= p.untilT then
            self.pending[key] = nil
        end
    end
end

Net.groupHandlers.lobby = function() Lobby:CheckPending() end

Net.handlers.LB = function(sender, f)
    if f[2] ~= "I" then return end
    local id, to = f[3], f[4]
    if not Lobby.specs[id] or not ns.games[id] then return end
    if to ~= "*" and Lower(to) ~= Lower(Net:Me()) then return end
    if Lobby:Busy(id) or Lobby:Hosting(id) then return end
    Lobby.invited[id .. ";" .. sender] = GetTime()
    Lobby:Toast({ id = id, host = sender, invite = true })
end

---------------------------------------------------------------------------
-- The Invite button (title row, while hosting) and its page
---------------------------------------------------------------------------
function Lobby:BuildWindow(frame)
    local b = ns.CreateFrame("Button", ns:NewName(), frame.gamePage, "UIPanelButtonTemplate")
    b:SetWidth(56); b:SetHeight(22)
    b:SetPoint("RIGHT", frame.optionsButton, "LEFT", -4, 0)
    b:SetText("Invite")
    b:SetScript("OnClick", function() Lobby:ToggleInvitePage() end)
    b:Hide()
    frame.inviteButton = b

    local o = ns.CreateFrame("Frame", nil, frame.gamePage)
    o:SetWidth(300); o:SetHeight(176)
    o:SetPoint("TOP", frame.gamePage, "TOP", 0, -44)
    o:SetFrameLevel(frame.gamePage:GetFrameLevel() + 80)
    o:EnableMouse(true)
    o:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    o:SetBackdropColor(0.04, 0.05, 0.10, 0.97)
    o:SetBackdropBorderColor(0.35, 0.65, 1, 1)
    o:Hide()
    o.title = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    o.title:SetPoint("TOP", o, "TOP", 0, -12)
    local label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -42)
    label:SetText("Name")
    local box = ns.CreateFrame("EditBox", nil, o)
    box:SetWidth(150); box:SetHeight(22)
    box:SetPoint("LEFT", label, "RIGHT", 8, 0)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.8)
    box:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    box:SetScript("OnEnterPressed", function() Lobby:InviteTyped() end)
    box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    o.box = box
    local MakeButton = ns.UI.Button
    local send = MakeButton(o, "Invite", 64, function() Lobby:InviteTyped() end)
    send:SetPoint("LEFT", box, "RIGHT", 6, 0)
    local target = MakeButton(o, "Invite my target", 130, function()
        local name = UnitName("target")
        if not name or not UnitIsPlayer("target") then
            Lobby:InviteNote("Target a player first.")
            return
        end
        Lobby:InviteNote(Lobby:Invite(o.id, name))
    end)
    target:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -76)
    local all = MakeButton(o, "Invite the whole group", 130, function() Lobby:InviteNote(Lobby:InviteGroup(o.id)) end)
    all:SetPoint("LEFT", target, "RIGHT", 8, 0)
    o.groupButton = all
    o.note = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.note:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -110)
    o.note:SetWidth(268)
    o.note:SetJustifyH("LEFT")
    local done = MakeButton(o, "Done", 80, function() o:Hide() end)
    done:SetPoint("BOTTOM", o, "BOTTOM", 0, 12)
    frame.invitePage = o
end

function Lobby:InviteNote(text)
    local o = ns.frame and ns.frame.invitePage
    if o then o.note:SetText(text or "") end
end

function Lobby:InviteTyped()
    local o = ns.frame and ns.frame.invitePage
    if not o then return end
    local text = Lobby:Invite(o.id, o.box:GetText())
    o.box:ClearFocus()
    if string.find(text, "^Invited") then o.box:SetText("") end
    self:InviteNote(text)
end

function Lobby:ToggleInvitePage()
    local o = ns.frame and ns.frame.invitePage
    if not o then return end
    if o:IsShown() then o:Hide() return end
    o.id = ns.currentGame
    o.title:SetText("Invite players to " .. GameName(o.id))
    o.note:SetText("Not in your group? They'll be invited to it first.")
    ns.SetEnabled(o.groupButton, Net:InGroup())
    ns:Sound("IG_MAINMENU_OPTION")
    o:Show()
end

-- The Invite button shows while you host in the game on screen (the game's
-- name moves left to make room).
function Lobby:UpdateWindow()
    local f = ns.frame
    if not f or not f.inviteButton then return end
    local id = ns.currentGame
    local show = id ~= nil and self:Hosting(id)
    if show ~= f.inviteButton:IsShown() then
        ns.SetShown(f.inviteButton, show)
        f.title:ClearAllPoints()
        f.title:SetPoint("TOP", f, "TOP", show and -30 or 0, -17)
    end
    if not show and f.invitePage:IsShown() then f.invitePage:Hide() end
end

---------------------------------------------------------------------------
-- Badges: the minimap button and the game tiles
---------------------------------------------------------------------------
local function Badge(parent, size)
    local b = ns.CreateFrame("Frame", nil, parent)
    b:SetWidth(size); b:SetHeight(size)
    b:SetFrameLevel(parent:GetFrameLevel() + 5)
    local dot = b:CreateTexture(nil, "ARTWORK")
    dot:SetAllPoints(b)
    dot:SetTexture("Interface\\AddOns\\CowCasino\\Art\\Dot")
    dot:SetVertexColor(0.2, 0.55, 1, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b:Hide()
    return b
end

local function SetBadge(b, n)
    if n > 0 then
        b.text:SetText(n > 9 and "9+" or tostring(n))
        b:Show()
    else
        b:Hide()
    end
end

function Lobby:UpdateBadges(open, total)
    local mb = ns.minimapButton
    if mb then
        mb.lobbyBadge = mb.lobbyBadge or Badge(mb, 16)
        mb.lobbyBadge:SetPoint("TOPRIGHT", mb, "TOPRIGHT", 2, 2)
        SetBadge(mb.lobbyBadge, total)
    end
    for id, tile in pairs(ns.menuRows or {}) do
        if self.specs[id] then
            tile.lobbyBadge = tile.lobbyBadge or Badge(tile, 16)
            tile.lobbyBadge:SetPoint("TOPLEFT", tile, "TOPLEFT", 3, -3)
            SetBadge(tile.lobbyBadge, open[id] and ns.getn(open[id]) or 0)
        end
    end
end

-- Tooltip lines for a tile (a game id) or the minimap button (nil).
function Lobby:AddTooltipLines(id)
    local open = self:Open()
    if id then
        if open[id] then GameTooltip:AddLine("Open now: " .. table.concat(open[id], ", ") .. " (click to see)", 0.4, 0.8, 1, 1) end
        return
    end
    for _, gid in ipairs(self.order) do
        if open[gid] then GameTooltip:AddLine(GameName(gid) .. ": " .. table.concat(open[gid], ", "), 0.4, 0.8, 1) end
    end
end

---------------------------------------------------------------------------
-- Every second: new tables (pop-ups), joining after a click, badges
---------------------------------------------------------------------------
function Lobby:Poll()
    local now = GetTime()
    local current = {}
    for _, id in ipairs(self.order) do
        local busy = self:Busy(id)
        for _, o in ipairs(self:Offers(id)) do
            local key = id .. ";" .. o.host .. ";" .. tostring(o.key or "")
            current[key] = true
            if not self.seen[key] then
                self.seen[key] = now
                local invitedAt = self.invited[id .. ";" .. o.host]
                local onScreen = ns.frame and ns.frame:IsShown() and ns.currentGame == id
                if not busy and not onScreen and not (ns.db and ns.db.lobbyQuiet)
                    and not (invitedAt and now - invitedAt < 60) then
                    self:Toast({ id = id, host = o.host })
                end
            end
        end
    end
    for key in pairs(self.seen) do
        if not current[key] then self.seen[key] = nil end
    end
    -- a pop-up for a table that's gone (or a game you're now in) goes too
    local c = self.current
    if c and now >= (c.untilT or 0) then
        self:CloseToast()
    elseif c and not c.invite then
        local still = false
        for _, o in ipairs(self:Offers(c.id)) do if o.host == c.host then still = true end end
        if not still or self:Busy(c.id) then self:CloseToast() end
    end
    self:TryJoin()
    self:CheckPending()
    for _, intro in ipairs(self.intros) do
        if intro:IsShown() then intro:ShowLobby() end
    end
    local open, total = self:Open()
    self:UpdateBadges(open, total)
    self:UpdateWindow()
end

local ticker = ns.CreateFrame("Frame")
local wait = 0
ticker:SetScript("OnUpdate", function()
    wait = wait + (arg1 or 0)
    if wait < POLL or not ns.db then return end
    wait = 0
    Lobby:Poll()
end)
