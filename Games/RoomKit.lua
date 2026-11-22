-- CowCasino: the party room kit. One player hosts a game for the group:
-- their client keeps the players, runs the game and tells everyone how it
-- stands; the others join from a list of games in the group. This kit is the
-- part every such game shares: offers and joining, the roster, heartbeats,
-- someone leaving (or the host going quiet), a reload closing the game, the
-- lobby page and table chat. The game brings its own state and rules.
--
--   local room = ns.RoomKit.New({
--       tag = "HM", id = "hangman", max = 8,
--       phase    = function() return "w" end,            -- for the lobby list (w waiting, o between games, else playing)
--       state    = function() return { ... } end,         -- host: the game's state, sent as S;tid;...
--       onState  = function(f) end,                       -- clients: an S message (fields from f[4])
--       onHost   = function() end,                        -- host: the room just opened
--       onJoin   = function(name, player) end,            -- host: someone joined (player is their roster row)
--       onDrop   = function(name) end,                    -- host: someone left
--       onHostMessage   = function(sender, f) end,        -- host: another kind from a player
--       onClientMessage = function(f) end,                -- clients: another kind from the host
--       onLobby  = function() end,                        -- back in the lobby (left, closed, lost touch)
--       refresh  = function() end,                        -- redraw
--       fields   = { "score" },                           -- numbers each roster row carries (default score)
--   })
--   room:Restore(db)        (in Build: remembers db, and cleans up a game a reload ended)
--   (heartbeats and timeouts run on their own: Games\SessionKit.lua)
--   room:BuildLobby(panel, opts)  /  room:RefreshLobby()   (the lobby is the game's intro: Intro.lua)
--
-- Messages (tag, then): Q (who's hosting?), O;tid;players;phase;ver, J;tid;ver,
-- F;tid;name;why (can't join), L;tid (leaving), X;tid (closed),
-- R;tid;version;part;parts;rows (the roster, split so a big raid fits: rows
-- are name:field:..., joined by commas), S;tid;<the game's state>. Any other
-- kind goes to the game's hooks.

local ns = CowCasino.ns
local Net = ns.Net

local RK = { HEARTBEAT = 8, HOST_TIMEOUT = 35, JOIN_TIMEOUT = 15 }   -- (offers time out in Net:OpenOffers)
ns.RoomKit = RK

local Room = {}
Room.__index = Room
RK.Room = Room

local function Call(f, a, b) if f then return f(a, b) end end

function RK.New(spec)
    local r = setmetatable({ spec = spec, tag = spec.tag, max = spec.max or 10, fields = spec.fields or { "score" },
        mode = "lobby", players = {}, offers = {} }, Room)
    -- the session (Games\SessionKit.lua): heartbeat, a quiet host, an
    -- unanswered join, the group changing
    r.sess = ns.SessionKit.New({
        tag = spec.tag, id = spec.id, state = r, handle = function(sender, f) r:OnMessage(sender, f) end,
        heartbeat = RK.HEARTBEAT, hostTimeout = RK.HOST_TIMEOUT, joinTimeout = RK.JOIN_TIMEOUT,
        beat = function()
            r:Broadcast()
            r:Offer()
        end,
        hostGone = function(message) r:ToLobby(message) end,
        joinLost = function(message)
            r.lobbyMsg = message
            r:Refresh()
        end,
        hostGroup = function()
            local gone = {}
            for _, p in ipairs(r.players) do if not Net:IsMember(p.name) then table.insert(gone, p.name) end end
            for _, name in ipairs(gone) do r:Drop(name) end
            if not Net:InGroup() then r:Close("You left the group, so your game closed.") end
        end,
        changed = function() if r.mode == "lobby" then r:Refresh() end end,
    })
    return r
end

function Room:Me() return Net:Me() end
function Room:IsHost() return self.mode == "host" end
function Room:InRoom() return self.mode == "host" or self.mode == "client" end
function Room:HostName() return self.mode == "host" and Net:Me() or self.host end

function Room:Send(parts, key)
    Net:Send(self.tag .. ";" .. table.concat(parts, ";"), key)
end

function Room:Player(name)
    for i, p in ipairs(self.players) do if p.name == name then return p, i end end
end

function Room:NewPlayer(name)
    local p = { name = name }
    for _, k in ipairs(self.fields) do p[k] = 0 end
    return p
end

function Room:RosterText()
    local t = {}
    for _, p in ipairs(self.players) do
        local row = { p.name }
        for _, k in ipairs(self.fields) do table.insert(row, p[k] or 0) end
        table.insert(t, table.concat(row, ":"))
    end
    return table.concat(t, ",")
end

function Room:ParseRoster(text)
    local out = {}
    for _, part in ipairs(Net.Split(text or "", ",")) do
        local bits = Net.Split(part, ":")
        if bits[1] and bits[1] ~= "" then
            local p = { name = bits[1] }
            for i, k in ipairs(self.fields) do p[k] = tonumber(bits[i + 1] or "") or 0 end
            table.insert(out, p)
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The host
---------------------------------------------------------------------------
function Room:Refresh() Call(self.spec.refresh) end

-- The host changed a setting: a click, everyone told, the screen redrawn.
function Room:SettingsChanged()
    ns:Sound("IG_MAINMENU_OPTION")
    if self:IsHost() then self:SendState() end
    self:Refresh()
end

function Room:Phase() return Call(self.spec.phase) or "w" end

function Room:Offer()
    if self.mode ~= "host" then return end
    self:Send(Net:Pack("roomOffer", { tid = self.tid, players = ns.getn(self.players), phase = self:Phase() }), self.tag .. "-O")
end

function Room:SendState()
    if self.mode ~= "host" then return end
    if self:Phase() ~= "o" then self.ready = nil end      -- a new game: the ready check starts over
    local parts = { "S", self.tid }
    for _, v in ipairs(Call(self.spec.state) or {}) do table.insert(parts, v) end
    self:Send(parts, self.tag .. "-S")
end

-- The roster, in as many parts as it takes (each a message of its own).
local ROSTER_PART = 170
function Room:SendRoster()
    local parts, cur = {}, ""
    for _, row in ipairs(Net.Split(self:RosterText(), ",")) do
        if cur ~= "" and string.len(cur) + 1 + string.len(row) > ROSTER_PART then
            table.insert(parts, cur)
            cur = row
        else
            cur = (cur == "") and row or (cur .. "," .. row)
        end
    end
    table.insert(parts, cur)
    self.rosterVersion = ns.Mod((self.rosterVersion or 0) + 1, 1000)
    local n = ns.getn(parts)
    for k, text in ipairs(parts) do
        self:Send({ "R", self.tid, self.rosterVersion, k, n, text }, self.tag .. "-R" .. k)
    end
end

-- A roster part arrived: the whole roster once every part of it is in.
function Room:RosterPart(f)
    local v, k, n = f[4], tonumber(f[5] or ""), tonumber(f[6] or "")
    if not k or not n or k < 1 or k > n then return nil end
    local got = self.rosterParts
    if not got or got.v ~= v or got.tid ~= f[3] then
        got = { v = v, tid = f[3], n = n, parts = {}, count = 0 }
        self.rosterParts = got
    end
    if not got.parts[k] then
        got.parts[k] = f[7] or ""
        got.count = got.count + 1
    end
    if got.count < got.n then return nil end
    self.rosterParts = nil
    local rows = {}
    for i = 1, got.n do if got.parts[i] ~= "" then table.insert(rows, got.parts[i]) end end
    return self:ParseRoster(table.concat(rows, ","))
end

-- The roster and the state (and, by heartbeat, the offer).
function Room:Broadcast()
    if self.mode ~= "host" then return end
    self.sess:BeatSent()
    self:SendRoster()
    self:SendState()
    Call(self.spec.onBroadcast)
end

function Room:Host()
    if self.mode ~= "lobby" or not Net:InGroup() then return false end
    self.mode, self.host, self.lobbyMsg = "host", nil, nil
    self.tid = tostring(math.random(10000, 99999))
    self.players = { self:NewPlayer(Net:Me()) }
    if self.db then self.db.hosting = true end
    Call(self.spec.onHost)
    self:Broadcast()
    self:Offer()
    self:Refresh()
    return true
end

function Room:Close(message)
    if self.mode ~= "host" then return end
    self:Send({ "X", self.tid })
    self:ToLobby(message or "You closed your game.")
end

function Room:HostJoin(name, ver)
    if Net:VersionProblem(ver) then return end
    if not self:Player(name) then
        if ns.getn(self.players) >= self.max then
            self:Send({ "F", self.tid, name, "The game is full." })
            return
        end
        local p = self:NewPlayer(name)
        table.insert(self.players, p)
        Call(self.spec.onJoin, name, p)
    end
    self:Broadcast()
    self:Offer()
    self:Refresh()
end

function Room:Drop(name)
    local _, i = self:Player(name)
    if not i or name == Net:Me() then return end
    table.remove(self.players, i)
    Call(self.spec.onDrop, name)
    self:Broadcast()
    self:Offer()
    self:Refresh()
end

---------------------------------------------------------------------------
-- Joining and leaving
---------------------------------------------------------------------------
function Room:ToLobby(message)
    self.mode, self.tid, self.host, self.joining, self.watching = "lobby", nil, nil, nil, nil
    self.players = {}
    self.lobbyMsg = message
    if self.db then self.db.hosting, self.db.joined = nil, nil end
    Call(self.spec.onLobby)
    self:Refresh()
end

function Room:Join(host, tid)
    if self.mode ~= "lobby" then return end
    self.joining = { host = host, tid = tid, at = GetTime() }
    self.lobbyMsg = "Asking " .. host .. " to join..."
    self:Send({ "J", tid, Net.PARTY_VERSION })
    self:Refresh()
end

-- Hooks the room up to the lobby hub (Lobby.lua: pop-ups, badges, invites).
-- enter(): brings the game's lobby page up (from a solo screen, say), or
-- returns why it can't.
function Room:RegisterLobby(id, enter)
    local room = self
    self.sess:RegisterLobby(id, {
        noun = "game",
        offers = function()
            local out = {}
            for _, o in ipairs(Net:OpenOffers(room.offers, function(o) return o.players < room.max and not Net:VersionProblem(o.ver) end)) do
                table.insert(out, { host = o.host, key = o.tid })
            end
            return out
        end,
        join = function(host)
            if room.mode ~= "lobby" then return "You're already in a game." end
            local why = enter and enter()
            if why then return why end
            local o = room.offers[host]
            if not o then return host .. "'s game is gone." end
            room:Join(host, o.tid)
        end,
    })
end

-- Watching a game (spec.watch): following it without a place in it. The
-- room's messages go to the whole group anyway; the host sends the game so
-- far (W). A watcher is a client that isn't on the roster (room.watching).
function Room:Watch(host, tid)
    if self.mode ~= "lobby" or not self.spec.watch then return end
    self.mode, self.host, self.tid, self.watching = "client", host, tid, true
    self.players, self.fresh, self.lobbyMsg = {}, true, nil
    self.sess:Heard()
    self:Send({ "W", tid })
    ns:Sound("IG_MAINMENU_OPTION")
    self:Refresh()
end

-- The ready check, once a game is over (phase "o"): each player says
-- they're ready for another (Y); the host's button shows how many are, and
-- when everyone is the next game starts (spec.onAllReady).
function Room:HostReady(name, on)
    if not self:Player(name) or self:Phase() ~= "o" then return end
    self.ready = self.ready or {}
    self.ready[name] = on or nil
    self:Refresh()
    local ready, total = self:ReadyCount()
    if ready == total and total > 1 then Call(self.spec.onAllReady) end
end

-- Players ready (the host always is) and players in all.
function Room:ReadyCount()
    local ready, total = 0, 0
    for _, p in ipairs(self.players) do
        total = total + 1
        if p.name == self:HostName() or (self.ready and self.ready[p.name]) then ready = ready + 1 end
    end
    return ready, total
end

-- A player's Ready button (between games).
function Room:ToggleReady()
    if self.mode ~= "client" or self.watching then return end
    self.myReady = not self.myReady
    self:Send({ "Y", self.tid, self.myReady and "1" or "0" })
    ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    self:Refresh()
end

-- The game-over button: the host's (hostText, with the count) or a
-- player's Ready. Returns shown, text.
function Room:AgainButton(hostText)
    if self:Phase() ~= "o" then
        self.myReady = nil
        return false
    end
    if self:IsHost() then
        local ready, total = self:ReadyCount()
        return true, hostText .. (total > 1 and (" (" .. ready .. "/" .. total .. ")") or "")
    end
    if self.mode == "client" and not self.watching then
        return true, self.myReady and "Not ready" or "Ready"
    end
    return false
end

-- Every game's game-over button: shows, says and does the right thing.
-- canStart(): enough players for the host to start again.
function Room:RefreshAgain(button, hostText, canStart)
    local shown, text = self:AgainButton(hostText)
    ns.SetShown(button, shown)
    if not shown then return end
    button:SetText(text)
    ns.SetEnabled(button, not self:IsHost() or canStart())
end

-- What the leave button says: Close game, Stop watching or Leave game.
function Room:LeaveLabel()
    if self:IsHost() then return "Close game" end
    return self.watching and "Stop watching" or "Leave game"
end

function Room:Leave()
    if self.mode ~= "client" then return end
    self:Send({ "L", self.tid })
    self:ToLobby((self.watching and "You stopped watching " or "You left ") .. (self.host or "the") .. "'s game.")
end

-- Leave a room either way (host closes it, a player leaves).
function Room:Exit()
    if self.mode == "host" then self:Close() elseif self.mode == "client" then self:Leave() end
end

function Room:OnMessage(sender, f)
    local kind, tid = f[2], f[3]
    if kind == "Q" then
        if self.mode == "host" then self:Offer() end
        return
    elseif kind == "O" then
        local o = Net:Read("roomOffer", f)
        o.players, o.heard = o.players or 0, GetTime()
        self.offers[sender] = o
        if self.mode == "lobby" then self:Refresh() end
        return
    end

    if self.mode == "host" then
        if tid ~= self.tid then return end
        if kind == "J" then self:HostJoin(sender, f[4])
        elseif kind == "W" then self:Broadcast()      -- someone started watching: the game so far
        elseif kind == "Y" then self:HostReady(sender, f[4] == "1")
        elseif kind == "L" then self:Drop(sender)
        elseif self:Player(sender) then Call(self.spec.onHostMessage, sender, f) end
        return
    end

    if kind == "X" then
        self.offers[sender] = nil
        if self.joining and self.joining.host == sender then
            self.joining = nil
            self.lobbyMsg = sender .. " closed the game."
        elseif self.mode == "client" and sender == self.host and tid == self.tid then
            self:ToLobby(sender .. " closed the game.")
            return
        end
        self:Refresh()
        return
    end

    if self.joining and sender == self.joining.host and tid == self.joining.tid then
        if kind == "F" and f[4] == Net:Me() then
            self.joining = nil
            self.lobbyMsg = f[5] or "Couldn't join."
            self:Refresh()
            return
        elseif kind == "R" then
            local roster = self:RosterPart(f)
            if not roster then return end
            local mine = false
            for _, p in ipairs(roster) do if p.name == Net:Me() then mine = true end end
            if not mine then return end
            self.mode, self.host, self.tid, self.joining, self.lobbyMsg = "client", sender, tid, nil, nil
            self.players, self.fresh = roster, true
            self.sess:Heard()
            if self.db then self.db.joined = { host = sender, tid = tid } end
            ns:Sound("IG_MAINMENU_OPTION")
            self:Refresh()
            return
        end
    end

    if self.mode ~= "client" or sender ~= self.host or tid ~= self.tid then return end
    self.sess:Heard()
    if kind == "R" then
        local roster = self:RosterPart(f)
        if not roster then return end
        self.players = roster
        if not self.watching and not self:Player(Net:Me()) then
            self:ToLobby("You're no longer in " .. sender .. "'s game.")
            return
        end
        self:Refresh()
    elseif kind == "S" then
        Call(self.spec.onState, f)
        self.fresh = nil
    else
        Call(self.spec.onClientMessage, f)
    end
end

function Room:GroupChanged() self.sess:GroupChanged() end

-- (the session keeps time itself; kept for the games that still call it)
function Room:Tick(now) end

-- In Build: a game can't survive a reload.
function Room:Restore(db)
    self.db = db
    local room = self
    self.lobbyMsg = self.sess:Restore(db, { host = "hosting", seat = "joined", noun = "game",
        rejoin = function(seat) room:Join(seat.host, seat.tid) end })
end

-- Ask who's hosting (opening the lobby).
function Room:Ask()
    if self.mode == "lobby" and Net:InGroup() then self:Send({ "Q" }) end
end

function Room:ChatTable()
    if not self:InRoom() then return nil end
    local members = {}
    for _, p in ipairs(self.players) do members[p.name] = true end
    members[self:HostName()] = true
    return { game = self.tag, host = self:HostName(), tid = self.tid, members = members }
end

---------------------------------------------------------------------------
-- The lobby page: what the game is, Host (plus the game's own buttons), the
-- games in the group with Join, a message line and a stats line.
--   opts: title, info, buttons = { { text, onClick, width } }, stats = function() return text end
---------------------------------------------------------------------------
local ROWS = 4

-- The lobby is the game's intro screen (Intro.lua): its solo button (the
-- first of opts.buttons), Host a game, and the games open in the group.
-- opts: game, title (unused: the game's name), info, alone, buttons, stats, felt.
function Room:BuildLobby(panel, opts)
    local r = self
    local solo = opts.buttons and opts.buttons[1]
    local intro = ns:AddIntro(opts.game, panel, { felt = opts.felt, blurb = opts.info,
        solo = solo and "Play solo" or nil, party = "Play with your group", rows = solo and 3 or ROWS, refresh = true })
    self.intro = intro
    self.lobby = intro.frame
    if solo then
        intro.soloGo:SetText(solo[1])
        intro.onSolo = solo[2]
    end
    intro.hostGo:SetText("Host a game")
    intro.onHost = function() r:Host() end
    intro.onRefresh = function()
        r:Send({ "Q" })
        r:Refresh()
    end
    self.lobbyOpts = opts
    return intro.frame
end

function Room:RefreshLobby()
    local intro = self.intro
    if not intro then return end
    local inGroup = Net:InGroup()
    ns.SetEnabled(intro.hostGo, inGroup)
    local r, list = self, Net:OpenOffers(self.offers)
    local rows = {}
    for _, o in ipairs(list) do
        local offer = o
        local doing = (o.phase == "w" and "waiting to start") or (o.phase == "o" and "between games") or "playing"
        table.insert(rows, {
            host = o.host, tid = o.tid,
            text = string.format("%s's game - %d player%s, %s", o.host, o.players, o.players == 1 and "" or "s", doing)
                .. Net:VersionNote(o.ver),
            enabled = o.players < self.max and not self.joining and not Net:VersionProblem(o.ver),
            click = function() r:Join(offer.host, offer.tid) end,
            watch = self.spec.watch and not self.joining and function() r:Watch(offer.host, offer.tid) end or nil,
        })
    end
    intro:SetOffers(rows)
    intro:SetNote((rows[1] and "Games in your group:")
        or (inGroup and ("You're in a group of " .. Net:GroupSize() .. ". No games yet: host one, or ask someone to.")
        or (self.lobbyOpts.alone or "Join a party or raid to play with friends.")))
    intro:SetStatus(self.lobbyMsg or "")
    intro:SetStats(Call(self.lobbyOpts.stats) or "")
end
