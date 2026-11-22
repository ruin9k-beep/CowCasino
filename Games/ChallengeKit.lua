-- CowCasino: one-on-one challenges, shared by the games two people from a
-- group play against each other (Deathroll, and the board games through
-- BoardKit): posting a challenge, sending it again now and then, taking one,
-- the first taker getting it, withdrawing, someone leaving the group, and
-- the lobby hub's pop-ups and badges.
--
--   local ch = ns.ChallengeKit.New({
--       tag = "DT", id = "deathroll", state = S,    -- S.posted, S.accepting, S.offers
--       fields = function(posted) return { posted.stake } end,   -- the offer's own fields
--       read = function(f) return { stake = tonumber(f[4]) }, 1 end,  -- ...read back (and how many)
--       accepted = function(sender, posted) return { extra } end,  -- host: fields for the start message
--       begin = function(sender, posted, extra) ... end,           -- host: the game starts
--       chosen = function(sender, id, offer, f) return started end, -- taker: the host picked you
--       inGame = function() return S.game ~= nil end,
--       onMessage = function(sender, kind, f) ... end,   -- every other message (the game's own)
--       onGroup = function() ... end,                    -- after the group changed
--       status = function(text) ... end, refresh = function() ... end,
--       shown = function() return true end,              -- the game is on screen
--       enter = function() return whyNot end,            -- the lobby hub: bring up party play
--       busyText = "You're already in a duel.",
--   })
--   ch:Post(posted)  ch:Withdraw(quiet)  ch:Accept(offer)  ch:OpenOffers()  ch:Send(parts, key)
--
-- Messages (tag;kind;id;...): Q who's offering, O an offer (id, fields,
-- version), X withdrawn, A I'll take it (id, version), S the host's pick (id,
-- the taker, accepted fields). The game's own messages pass through.

local ns = CowCasino.ns
local Net = ns.Net

local OFFER_EVERY = 20      -- an open challenge is sent again this often
local ACCEPT_WAIT = 15      -- no answer to taking a challenge after this long

local CK = {}
ns.ChallengeKit = CK

local Kit = {}
Kit.__index = Kit

local function Call(f, a, b, c, d) if f then return f(a, b, c, d) end end

function CK.New(spec)
    local ch = setmetatable({ spec = spec, tag = spec.tag, S = spec.state }, Kit)
    local S = ch.S
    S.offers = S.offers or {}
    Net.handlers[spec.tag] = function(sender, f) ch:OnMessage(sender, f) end
    Net.groupHandlers[spec.id] = function() ch:GroupChanged() end
    ns:Every(0.5, function(dt, now) ch:Tick(now) end)
    ch:RegisterLobby()
    return ch
end

function Kit:Msg(parts) return self.tag .. ";" .. table.concat(parts, ";") end
function Kit:Send(parts, key) return Net:Send(self:Msg(parts), key) end
function Kit:Status(text) Call(self.spec.status, text) end
function Kit:Refresh() Call(self.spec.refresh) end
function Kit:RefreshIfShown() if Call(self.spec.shown) then self:Refresh() end end
function Kit:InGame() return Call(self.spec.inGame) and true or false end

function Kit:OpenOffers() return Net:OpenOffers(self.S.offers) end

function Kit:SendOffer()
    local p = self.S.posted
    if not p then return end
    p.sentAt = GetTime()
    local parts = { "O", p.id }
    for _, v in ipairs(Call(self.spec.fields, p) or {}) do table.insert(parts, v) end
    table.insert(parts, Net.PARTY_VERSION)
    self:Send(parts, self.tag .. "-O")
end

-- Post a challenge (posted: the game's own fields; an id is added).
function Kit:Post(posted)
    local S = self.S
    if self:InGame() or S.posted or not Net:InGroup() then return false end
    posted.id = tostring(math.random(100000, 999999))
    S.posted = posted
    self:SendOffer()
    return true
end

function Kit:Withdraw(quiet)
    local S = self.S
    if not S.posted then return end
    self:Send({ "X", S.posted.id }, self.tag .. "-O")
    S.posted = nil
    if not quiet then self:Status("Challenge withdrawn.") end
    self:Refresh()
end

function Kit:Accept(offer)
    local S = self.S
    if self:InGame() or S.posted or S.accepting or not offer then return end
    S.accepting = { host = offer.host, id = offer.id, at = GetTime() }
    self:Send({ "A", offer.id, Net.PARTY_VERSION })
    self:Status("Taking " .. offer.host .. "'s challenge...")
    self:Refresh()
end

function Kit:OnMessage(sender, f)
    local kind, id = f[2], f[3]
    local S = self.S
    if kind == "Q" then
        self:SendOffer()
    elseif kind == "O" then
        local offer, n = Call(self.spec.read, f)
        offer = offer or {}
        offer.id, offer.ver, offer.heard = id, tonumber(f[4 + (n or 0)]), GetTime()
        S.offers[sender] = offer
        self:RefreshIfShown()
    elseif kind == "X" then
        S.offers[sender] = nil
        if S.accepting and S.accepting.host == sender then
            S.accepting = nil
            self:Status(sender .. " withdrew that challenge.")
        end
        self:RefreshIfShown()
    elseif kind == "A" then
        -- someone takes our challenge: the first one gets it
        local p = S.posted
        if not p or p.id ~= id or self:InGame() or not Net:IsMember(sender) or Net:VersionProblem(f[4]) then return end
        S.posted = nil
        local extra = Call(self.spec.accepted, sender, p) or {}
        local parts = { "S", p.id, sender }
        for _, v in ipairs(extra) do table.insert(parts, v) end
        self:Send(parts, self.tag .. "-O")
        Call(self.spec.begin, sender, p, extra)
    elseif kind == "S" then
        -- the host picked a taker: us, or someone quicker
        local offer = S.offers[sender]
        S.offers[sender] = nil
        local a = S.accepting
        if a and a.host == sender and a.id == id then
            S.accepting = nil
            if f[4] ~= Net:Me() then
                self:Status(f[4] .. " took " .. sender .. "'s challenge first.")
            elseif Call(self.spec.chosen, sender, id, offer, f) then
                return
            end
        end
        self:RefreshIfShown()
    else
        Call(self.spec.onMessage, sender, kind, f)
    end
end

function Kit:GroupChanged()
    local S = self.S
    for name in pairs(S.offers) do
        if not Net:IsMember(name) then S.offers[name] = nil end
    end
    if S.accepting and not Net:IsMember(S.accepting.host) then S.accepting = nil end
    if S.posted and not Net:InGroup() then S.posted = nil end
    Call(self.spec.onGroup)
    self:RefreshIfShown()
end

function Kit:Tick(now)
    local S = self.S
    if S.posted and now - (S.posted.sentAt or 0) >= OFFER_EVERY then self:SendOffer() end
    if S.accepting and now - S.accepting.at > ACCEPT_WAIT then
        S.accepting = nil
        self:Status("No answer to that challenge.")
        self:Refresh()
    end
end

-- Take host's challenge from a pop-up (Lobby.lua).
function Kit:LobbyJoin(host)
    if self:InGame() then return self.spec.busyText or "You're already in a game." end
    local why = Call(self.spec.enter)
    if why then return why end
    for _, o in ipairs(self:OpenOffers()) do
        if o.host == host then
            self:Accept(o)
            return
        end
    end
    return host .. "'s challenge is gone."
end

function Kit:RegisterLobby()
    local ch, S = self, self.S
    ns.Lobby:Register(self.spec.id, {
        noun = "challenge",
        offers = function()
            local out = {}
            for _, o in ipairs(ch:OpenOffers()) do
                if not Net:VersionProblem(o.ver) then table.insert(out, { host = o.host, key = o.id }) end
            end
            return out
        end,
        ask = function() ch:Send({ "Q" }) end,
        join = function(host) return ch:LobbyJoin(host) end,
        hosting = function() return S.posted ~= nil end,
        busy = function() return ch:InGame() or S.posted ~= nil or S.accepting ~= nil end,
    })
end
