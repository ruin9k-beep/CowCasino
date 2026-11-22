-- CowCasino: a hosted session, the part every hosted party game shares
-- however it plays: the room games (RoomKit), the party tables (PartyKit)
-- and poker (PokerTable). It keeps:
--   * the session's state: mode ("lobby", "host", "client"), tid, host,
--     offers (the games open in the group), joining, lastHeard
--   * the clock: the host's heartbeat, a host gone quiet, a join nobody
--     answered
--   * the group changing: offers and the joining host gone, a client's host
--     gone, the host's players gone (the game's hook)
--   * a session a reload ended (Restore), and the lobby hub (pop-ups, badges)
--
--   local sess = ns.SessionKit.New({
--       tag = "BJ", id = "partybj", state = T, handle = OnMessage,
--       heartbeat = 15, hostTimeout = 40, joinTimeout = 15,   -- seconds (joinTimeout: nil for none)
--       beat = function() end,              -- host: the heartbeat (send the table again)
--       hostGone = function(message) end,   -- client: the host left or went quiet
--       joinLost = function(message) end,   -- asking to join: the host left or never answered
--       hostGroup = function() end,         -- host: the group changed (drop who's gone)
--       changed = function() end,           -- after the group changed
--   })
--   sess:Heard()                        a client heard from its host
--   sess:Send(parts, key)               tag;parts...
--   sess:Restore(db, spec) -> message   a session a reload ended (spec: host, seat
--                                       = db keys; noun = "blackjack table")
--   sess:RegisterLobby(id, spec)        the lobby hub (spec: offers, join, noun, ...)

local ns = CowCasino.ns
local Net = ns.Net

local SK = {}
ns.SessionKit = SK

local Session = {}
Session.__index = Session

local function Call(f, a, b) if f then return f(a, b) end end

function SK.New(spec)
    local s = setmetatable({ spec = spec, tag = spec.tag, T = spec.state }, Session)
    local T = s.T
    T.mode = T.mode or "lobby"
    T.offers = T.offers or {}
    if spec.handle then Net.handlers[spec.tag] = spec.handle end
    Net.groupHandlers[spec.id] = function() s:GroupChanged() end
    ns:Every(0.5, function(dt, now) s:Tick(now) end)
    return s
end

function Session:Msg(parts) return self.tag .. ";" .. table.concat(parts, ";") end
function Session:Send(parts, key) return Net:Send(self:Msg(parts), key) end
function Session:Heard() self.T.lastHeard = GetTime() end

-- The host's next heartbeat is a full interval away (it just sent everything).
function Session:BeatSent() self.nextBeat = GetTime() + (self.spec.heartbeat or 15) end

function Session:Tick(now)
    local T, spec = self.T, self.spec
    if T.mode == "host" then
        if now >= (self.nextBeat or 0) then
            self:BeatSent()
            Call(spec.beat)
        end
    elseif T.mode == "client" then
        if T.lastHeard and now - T.lastHeard > (spec.hostTimeout or 40) then
            T.lastHeard = nil
            Call(spec.hostGone, (T.host or "The host") .. " stopped responding.")
        end
    end
    local j = T.joining
    if j and spec.joinTimeout and not j.waiting and now - (j.at or now) > spec.joinTimeout then
        T.joining = nil
        Call(spec.joinLost, "No answer from " .. (j.host or "the host") .. ".")
    end
end

function Session:GroupChanged()
    local T, spec = self.T, self.spec
    if T.mode == "host" then
        Call(spec.hostGroup)
        if T.pending then T.pending = Net:StillHere(T.pending) end
    elseif T.mode == "client" and not Net:IsMember(T.host) then
        Call(spec.hostGone, (T.host or "The host") .. " left the group.")
    end
    for name in pairs(T.offers) do
        if not Net:IsMember(name) then T.offers[name] = nil end
    end
    if T.joining and not Net:IsMember(T.joining.host) then
        T.joining = nil
        Call(spec.joinLost, "The host left the group.")
    end
    Call(spec.changed)
end

-- In Build, after a reload. A game you hosted is gone (db[spec.host] is
-- cleared). A game you were in (db[spec.seat] = { host, tid }): with
-- spec.rejoin(seat), and its host still in the group, you ask to join again
-- (the host kept your place); otherwise the host is told you've gone.
-- Returns the line to show, if any.
function Session:Restore(db, spec)
    local noun = spec.noun or "game"
    local message
    if db[spec.host] then
        db[spec.host] = nil
        message = "Your " .. noun .. " closed when the game reloaded."
    end
    local seat = db[spec.seat]
    if seat then
        db[spec.seat] = nil
        local here = seat.host and Net:IsMember(seat.host)
        if here and spec.rejoin then
            spec.rejoin(seat)
            return "Rejoining " .. seat.host .. "'s " .. noun .. " after the reload..."
        end
        if here then self:Send({ "L", seat.tid }) end
        message = "You left " .. (seat.host or "the") .. "'s " .. noun .. " when the game reloaded."
    end
    return message
end

-- The lobby hub (Lobby.lua). spec: noun, offers() -> { { host, key, text } },
-- join(host) -> why not, and optionally hosting(), busy().
function Session:RegisterLobby(id, spec)
    local s, T = self, self.T
    ns.Lobby:Register(id, {
        noun = spec.noun or "game",
        offers = spec.offers,
        ask = function() s:Send({ "Q" }) end,
        join = spec.join,
        hosting = spec.hosting or function() return T.mode == "host" end,
        busy = spec.busy or function() return T.mode ~= "lobby" or T.joining ~= nil end,
    })
end
