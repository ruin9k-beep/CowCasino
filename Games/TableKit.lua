-- CowCasino: pieces every seated party table shares (poker, and the party
-- tables through PartyKit): the turn clock, missed turns, and clearing the
-- seats of players who left or were removed.
--   TK.StartClock(T, seconds, valid, onExpire)   T.deadline for the countdown;
--       onExpire runs after seconds unless a newer clock started (or valid()
--       says the moment has passed)
--   TK.StopClock(T)
--   TK.Missed(p, max)      a turn timed out: after max in a row a remote
--                          player is marked to be removed (p.kicked)
--   TK.Acted(p)            they acted: the count starts over
--   TK.ClearLeavers(T, from, to, spec)   seats from..to whose player left or
--       was removed are emptied; a removed player is told (K) and it's noted
--       in chat. spec: send(parts), newSeat(i), noun ("blackjack table"),
--       mark(i). True when any seat changed.

local ns = CowCasino.ns

local TK = {}
ns.TableKit = TK

TK.MAX_MISSED = 2       -- missed turns in a row before a player is removed

function TK.StartClock(T, seconds, valid, onExpire)
    T.deadline = GetTime() + seconds
    T.clock = (T.clock or 0) + 1
    local clock = T.clock
    ns:After(seconds, function()
        if T.clock ~= clock or (valid and not valid()) then return end
        onExpire()
    end)
end

function TK.StopClock(T)
    T.deadline = nil
    T.clock = (T.clock or 0) + 1
end

function TK.Missed(p, max)
    p.timeouts = (p.timeouts or 0) + 1
    if p.kind == "remote" and p.timeouts >= (max or TK.MAX_MISSED) then p.kicked = true end
end

function TK.Acted(p) if p then p.timeouts = 0 end end

function TK.ClearLeavers(T, from, to, spec)
    local changed = false
    for i = from, to do
        local p = T.seats[i]
        if p and p.kind == "remote" and (p.leaving or p.kicked) then
            if p.kicked then
                spec.send({ "K", T.tid, p.name, p.stack })
                ns:Print(p.name .. " was removed from your " .. (spec.noun or "table") .. " for not responding.")
            end
            T.seats[i] = spec.newSeat(i)
            if spec.mark then spec.mark(i) end
            changed = true
        end
    end
    return changed
end
