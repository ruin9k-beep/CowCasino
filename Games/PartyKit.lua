-- CowCasino: the pieces every hosted party table shares (Party Blackjack and
-- Party Craps): seats and who's at them, the table offer and joining it, the
-- host's turn clock, sending changes out, free top-ups, leaving and being
-- dropped, and the lobby with its list of tables in your group.
--
-- A game makes one kit from its own table state:
--   local H = {}        -- the game's own pieces the kit calls, filled in later
--   local P = ns.PartyKit({ T = T, ui = ui, game = Game, tag = "BJ", seats = 4,
--       noun = "blackjack", db = function() return db end, hooks = H })
-- and fills in H once its functions exist:
--   H.Refresh, H.SeatMsg, H.StateMsg, H.NewSeat, H.ResetToLobby, H.HostTable,
--   H.LobbyStats() -> the lobby's stats line, H.TopUpLater(p) -> true when a
--   top-up has to wait for the round to end.
-- The kit also runs the table's messages (P.OnMessage), its clock
-- (heartbeat, a silent host, an unanswered join) and the group changing
-- (P.Watch), with these hooks:
--   H.HostAct(i, f)       a seated player's move (A), to the host
--   H.DropPlayer(i)       a player left the table or the group (host)
--   H.ClientSeat(f), H.ClientState(f)   a seat (Z) and the table (P), to a client
--   optional: H.OnJoin(name, buyin) (default: seat them), H.OnSeat(p) (a new
--   player's seat), H.OnSeated() (you just sat down), H.ClientMessage(kind, f, sender)
-- The game's table state T needs: mode ("lobby", "host", "client"), seats,
-- mySeat, tid, host, offers, joining, version, dirty, dirtySeats, round,
-- deadline, clock, tableBuyIn and partyBuyIn.

local ns = CowCasino.ns
local Net = ns.Net

local HEARTBEAT = 15          -- the host re-sends the table this often
local HOST_TIMEOUT = 40       -- a client gives up on a silent host after this long
local JOIN_TIMEOUT = 15       -- no answer to a seat request

function ns.PartyKit(K)
    local T, ui, H, Game = K.T, K.ui, K.hooks, K.game
    local TAG, NUM_SEATS = K.tag, K.seats
    local P = {}
    local sess      -- the session (P.Watch)

    local Fmt = ns.Fmt
    local function Msg(parts) return TAG .. ";" .. table.concat(parts, ";") end
    P.Msg = Msg

    -- Seats --------------------------------------------------------------
    function P.MySeat() return T.mySeat or 1 end
    function P.Me() return T.seats[P.MySeat()] end
    function P.IsMine(i) return i == P.MySeat() end

    function P.HasRemote()
        for _, p in ipairs(T.seats) do
            if p.kind == "remote" then return true end
        end
        return false
    end

    function P.OpenSeats()
        local n = 0
        for i = 2, NUM_SEATS do
            if T.seats[i] and T.seats[i].kind == "empty" then n = n + 1 end
        end
        return n
    end

    function P.SeatName(i)
        local p = T.seats[i]
        if not p or p.kind == "empty" then return "|cff888888Empty seat|r" end
        if P.IsMine(i) then return "You" end
        return p.name or "?"
    end

    -- Host: telling the table ---------------------------------------------
    function P.MarkSeat(i) T.dirtySeats[i] = true end
    function P.MarkAll() for i = 1, NUM_SEATS do T.dirtySeats[i] = true end end
    function P.Changed()
        T.version = T.version + 1
        T.dirty = true
    end

    function P.RosterMsg()
        local parts = { "R", T.tid }
        for i = 1, NUM_SEATS do
            local p = T.seats[i]
            table.insert(parts, p.kind == "empty" and "" or (p.name or "?"))
        end
        return Msg(parts)
    end

    function P.SendRoster()
        if T.mode == "host" and P.HasRemote() then Net:Send(P.RosterMsg(), TAG .. "-R") end
    end

    function P.SendOffer()
        if T.mode ~= "host" then return end
        Net:Send(Msg(Net:Pack("tableOffer", { tid = T.tid, players = NUM_SEATS - P.OpenSeats(), open = P.OpenSeats(),
            buyin = T.tableBuyIn or T.partyBuyIn })), TAG .. "-O")
    end

    -- Seat updates first, then the table state, so a client never sees a turn
    -- (or a roll) before what goes with it.
    function P.Broadcast()
        T.dirty = false
        if T.mode ~= "host" or not P.HasRemote() then
            T.dirtySeats = {}
            return
        end
        for i = 1, NUM_SEATS do
            if T.dirtySeats[i] then Net:Send(H.SeatMsg(i), TAG .. "-Z" .. i) end
        end
        T.dirtySeats = {}
        Net:Send(H.StateMsg(), TAG .. "-P")
    end

    -- Host: the turn clock (a newer clock or round cancels an older one) ---
    function P.StartClock(seconds, onExpire)
        local round = T.round
        ns.TableKit.StartClock(T, seconds, function() return T.mode == "host" and T.round == round end, onExpire)
    end

    function P.StopClock() ns.TableKit.StopClock(T) end

    -- Free top-ups to the table's stack ------------------------------------
    -- Host: top seat i back up (at once, or when the round ends).
    function P.HostTopUp(i)
        local p = T.seats[i]
        if not p or p.kind == "empty" or not T.tableBuyIn or p.stack >= T.tableBuyIn then return end
        if H.TopUpLater and H.TopUpLater(p) then
            p.topUp = true
            return
        end
        p.topUp = nil
        p.stack = T.tableBuyIn
        P.MarkSeat(i)
        P.Changed()
        H.Refresh()
    end

    -- Your Top up button: the host does it, a client asks.
    function P.DoTopUp()
        local me = T.seats[P.MySeat()]
        if T.mode == "lobby" or not me or not T.tableBuyIn or me.stack >= T.tableBuyIn or me.topUp then return end
        if T.mode == "host" then
            P.HostTopUp(P.MySeat())
        else
            me.topUp = true
            Net:Send(Msg({ "U", T.tid }))
        end
        ns:Sound("IG_MAINMENU_OPTION")
        H.Refresh()
    end

    function P.RefreshTopUp(me)
        if not ui.topUp then return end
        if me.topUp and T.tableBuyIn and me.stack >= T.tableBuyIn then me.topUp = nil end   -- (a client's came through)
        ns.SetShown(ui.topUp, T.tableBuyIn ~= nil)
        if not T.tableBuyIn then return end
        ui.topUp:SetText(me.topUp and "Topping up..." or ("Top up to " .. Fmt(T.tableBuyIn)))
        ns.SetEnabled(ui.topUp, me.stack < T.tableBuyIn and not me.topUp)
    end

    -- Clients: joining and leaving ----------------------------------------
    function P.SetLobbyMessage(text) if ui.lobbyMsg then ui.lobbyMsg:SetText(text or "") end end

    -- Back to the lobby. A party seat is free, so its stack stays at the table.
    function P.ClientCashOut(amount, message)
        K.db().seat = nil
        H.ResetToLobby()
        P.SetLobbyMessage(message .. ((amount and amount > 0) and (" You finished with " .. Fmt(amount) .. ".") or ""))
        H.Refresh()
    end

    function P.HostGone(message)
        if T.mode ~= "client" then return end
        local seat = K.db().seat
        P.ClientCashOut(seat and seat.stack or 0, message)
    end

    function P.JoinTable(host, tid)
        local offer = T.offers[host]
        local buyin = (offer and offer.buyin) or T.partyBuyIn     -- the host's stack, free
        if T.mode ~= "lobby" then return end
        T.joining = { host = host, tid = tid, buyin = buyin, at = GetTime() }
        Net:Send(Msg(Net:Pack("tableJoin", { tid = tid, buyin = buyin })))
        P.SetLobbyMessage("Asking " .. host .. " for a seat...")
    end

    -- Hooks the table up to the lobby hub (Lobby.lua: pop-ups, badges and
    -- invites), under the menu game id it's shown in. show(): puts the party
    -- lobby on screen, or returns why it can't.
    function P.RegisterLobby(id, show)
        sess:RegisterLobby(id, {
            noun = "table",
            offers = function()
                local out = {}
                for _, o in ipairs(Net:OpenOffers(T.offers, function(o) return (o.open or 0) > 0 and not Net:VersionProblem(o.ver) end)) do
                    table.insert(out, { host = o.host, key = o.tid,
                        text = string.format("%s: %d seated, %d open", o.host, o.players or 0, o.open or 0) })
                end
                return out
            end,
            join = function(host)
                if T.mode ~= "lobby" then return "You're already at a table." end
                local why = show()
                if why then return why end
                local o = T.offers[host]
                if not o then return host .. "'s table is gone." end
                P.JoinTable(host, o.tid)
            end,
        })
    end

    -- A client: who's sitting where. False if we're no longer at the table.
    function P.ClientRoster(f)
        for i = 1, NUM_SEATS do
            local name = f[3 + i] or ""
            local p = T.seats[i] or H.NewSeat("empty")
            if name == "" then
                p.kind, p.name = "empty", nil
            else
                p.kind, p.name = "human", name
            end
            T.seats[i] = p
        end
        local mine = T.seats[P.MySeat()]
        if mine.kind ~= "human" or mine.name ~= Net:Me() then
            local seat = K.db().seat
            P.ClientCashOut(seat and seat.stack or 0, "You're no longer at " .. (T.host or "the") .. "'s table.")
            return false
        end
        return true
    end

    -- The lobby's messages (asking for tables, offers, a table closing).
    -- True when the message is handled and needs nothing more.
    function P.LobbyMessage(sender, f)
        local kind, tid = f[2], f[3]
        if kind == "X" then
            T.offers[sender] = nil
            if T.joining and T.joining.host == sender then
                T.joining = nil
                P.SetLobbyMessage(sender .. " closed the table.")
                H.Refresh()
            end
        end
        if kind == "Q" then
            if T.mode == "host" then P.SendOffer() end
            return true
        elseif kind == "O" then
            local o = Net:Read("tableOffer", f)
            o.players, o.open, o.heard = o.players or 0, o.open or 0, GetTime()
            T.offers[sender] = o
            if T.mode == "lobby" then H.Refresh() end
            return true
        end
        return false
    end

    -- The lobby -------------------------------------------------------------
    -- spec: title, info, buyIns (the table stacks a host can pick)
    function P.BuildLobby(panel, spec)
        local MakeButton = ns.UI.Button
        local l = ns.CreateFrame("Frame", nil, panel)
        l:SetAllPoints(panel)
        ui.lobby = l

        local title = ns:BigFont(l:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 22)
        title:SetPoint("TOP", l, "TOP", 0, -14)
        title:SetText(spec.title)

        local info = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        info:SetPoint("TOP", title, "BOTTOM", 0, -8)
        info:SetWidth(328)
        info:SetText(spec.info)

        ui.groupInfo = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ui.groupInfo:SetPoint("TOP", l, "TOP", 0, -84)
        ui.groupInfo:SetWidth(328)

        local label = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", l, "TOPLEFT", 16, -112)
        label:SetText("Table stack")
        ui.buyIn = ns.UI.Stepper(l, {
            list = spec.buyIns, width = 80,
            label = function(v) return "|cffffffff" .. Fmt(v) .. "|r" end,
            get = function() return T.partyBuyIn end,
            set = function(v) T.partyBuyIn = v end,
            onChange = function() H.Refresh() end,
        })
        ui.buyIn:SetPoint("TOPRIGHT", l, "TOPRIGHT", -16, -108)

        local back = MakeButton(l, "< Back", 90, function()
            if Game.onBack then Game.onBack() end
        end)
        back:SetPoint("TOPLEFT", l, "TOPLEFT", 0, -2)

        ui.host = MakeButton(l, "Host a table", 140, function() H.HostTable(T.partyBuyIn) end, 24)
        ui.host:SetPoint("TOP", l, "TOP", 0, -138)

        ui.tables = ns.UI.OfferList(l, { y = -178,
            onRefresh = function()
                Net:Send(Msg({ "Q" }))
                H.Refresh()
            end,
            onJoin = function(offer) P.JoinTable(offer.host, offer.tid) end })
        ui.rows = ui.tables.rows

        ui.lobbyMsg = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ui.lobbyMsg:SetPoint("TOP", l, "TOP", 0, -296)
        ui.lobbyMsg:SetWidth(328)

        ui.lobbyStats = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ui.lobbyStats:SetPoint("BOTTOM", l, "BOTTOM", 0, 12)
        ui.lobbyStats:SetWidth(332)
    end

    function P.RefreshLobby()
        local inGroup = Net:InGroup()
        ui.groupInfo:SetText(inGroup and ("You're in a group of " .. Net:GroupSize() .. ". Everyone needs CowCasino to play.")
            or "Join a party or raid to play with friends.")
        ui.buyIn:Refresh()
        ns.SetEnabled(ui.host, inGroup)

        ui.tables:Set(Net:OpenOffers(T.offers),
            function(offer)
                return string.format("%s's table - %d playing, %d open", offer.host, offer.players, offer.open)
                    .. (offer.buyin and ("\n|cffccccccFree " .. Fmt(offer.buyin) .. " stack|r") or "")
            end,
            function(offer) return offer.open > 0 and not T.joining end,
            inGroup and "No tables yet. Ask someone to host, or host one." or nil)
        ui.lobbyStats:SetText(H.LobbyStats())
    end

    -- Host: opening a table, seating and finding players --------------------
    -- The table's common setup (the game adds its own, then offers it and
    -- starts). False if it can't open.
    function P.OpenTable(buyin)
        if T.mode ~= "lobby" or not Net:InGroup() then return false end   -- free: party tables don't use your chips
        local db = K.db()
        db.stats.buyIns = db.stats.buyIns + 1
        T.tableBuyIn = buyin            -- everyone who joins sits down with this
        T.mode, T.mySeat = "host", 1
        T.tid = tostring(math.random(1, 99999))
        T.version, T.pending = 0, {}
        T.seats = { H.NewSeat("you", Net:Me(), buyin) }
        for i = 2, NUM_SEATS do T.seats[i] = H.NewSeat("empty") end
        db.host = { stack = buyin }
        return true
    end

    -- The seat a remote player is in (or nil).
    function P.RemoteSeat(name)
        for i = 2, NUM_SEATS do
            local p = T.seats[i]
            if p.kind == "remote" and p.name == name then return i end
        end
    end

    function P.SeatPlayer(name, buyin)
        for i = 2, NUM_SEATS do
            local p = T.seats[i]
            if p.kind == "remote" and p.name == name then
                if not (p.leaving or p.kicked) then
                    -- asked twice (or back after a reload): their seat, and the whole table again
                    Net:Send(Msg({ "S", T.tid, name, i, p.stack }))
                    P.MarkAll()
                    P.Changed()
                    P.SendRoster()
                    return
                end
                -- a seat they dropped from mid-round: clear it and seat them fresh
                if p.kicked then Net:Send(Msg({ "K", T.tid, p.name, p.stack })) end
                T.seats[i] = H.NewSeat("empty")
                P.MarkSeat(i)
            end
        end
        local free
        for i = 2, NUM_SEATS do
            if not free and T.seats[i].kind == "empty" then free = i end
        end
        if not free then
            Net:Send(Msg({ "N", T.tid, name, "The table is full." }))
            return
        end
        local p = H.NewSeat("remote", name, buyin)
        if H.OnSeat then H.OnSeat(p) end
        T.seats[free] = p
        Net:Send(Msg({ "S", T.tid, name, free, buyin }))
        P.MarkAll()           -- the newcomer needs every seat, not just theirs
        P.Changed()
        P.SendRoster()
        P.SendOffer()
    end

    -- Messages -----------------------------------------------------------------
    local function HostMessage(sender, f)
        local kind = f[2]
        if kind == "J" then
            if Net:VersionProblem(Net:Read("tableJoin", f).ver) then return end   -- another version can't sit here
            local buyin = T.tableBuyIn or 500             -- everyone gets the host's stack
            if H.OnJoin then H.OnJoin(sender, buyin)
            else
                P.SeatPlayer(sender, buyin)
                H.Refresh()
            end
            return
        end
        local i = P.RemoteSeat(sender)
        if not i then return end
        if kind == "A" then H.HostAct(i, f)
        elseif kind == "L" then H.DropPlayer(i)
        elseif kind == "U" then P.HostTopUp(i) end
    end

    -- The host's answer to your seat request.
    local function JoinReply(sender, f)
        local kind, tid = f[2], f[3]
        if kind == "S" and f[4] == Net:Me() then
            local seat, stack = tonumber(f[5]), tonumber(f[6]) or 0
            local rejoin = T.joining.rejoin
            T.joining = nil
            if not seat then
                Net:Send(Msg({ "L", tid }))
                return
            end
            local db = K.db()
            if not rejoin then db.stats.buyIns = db.stats.buyIns + 1 end
            T.mode, T.host, T.tid, T.mySeat = "client", sender, tid, seat
            T.tableBuyIn = stack            -- the host's stack, for topping up
            T.seats = {}
            for i = 1, NUM_SEATS do T.seats[i] = H.NewSeat("empty") end
            T.seats[seat] = H.NewSeat("human", Net:Me(), stack)
            T.phase, T.version, T.lastHeard = "waiting", 0, GetTime()
            db.seat = { host = sender, tid = tid, stack = stack }
            if H.OnSeated then H.OnSeated() end
            H.Refresh()
        elseif kind == "N" and f[4] == Net:Me() then
            if f[5] == "wait" then
                T.joining.waiting = true
                P.SetLobbyMessage(sender .. " will seat you after this round.")
            else
                T.joining = nil
                P.SetLobbyMessage(f[5] or "No seat.")
            end
        end
    end

    function P.OnMessage(sender, f)
        local kind, tid = f[2], f[3]
        if P.LobbyMessage(sender, f) then return end
        if T.mode == "host" and tid == T.tid then return HostMessage(sender, f) end
        if T.joining and sender == T.joining.host and tid == T.joining.tid then return JoinReply(sender, f) end
        if T.mode ~= "client" or sender ~= T.host or tid ~= T.tid then
            if kind == "X" and T.mode == "lobby" then H.Refresh() end    -- (a table gone from the list)
            return
        end
        sess:Heard()
        if kind == "R" then
            if P.ClientRoster(f) then H.Refresh() end
        elseif kind == "Z" then
            H.ClientSeat(f)
            H.Refresh()
        elseif kind == "P" then
            H.ClientState(f)
        elseif kind == "X" then
            P.HostGone(sender .. " closed the table.")
        elseif H.ClientMessage then
            H.ClientMessage(kind, f, sender)
        end
    end

    -- The session (Games\SessionKit.lua): heartbeat, a quiet host, an
    -- unanswered join, the group changing --------------------------------

    -- Hooks the table to the network: its messages, the group, the clock.
    -- id: the key the group handler goes under (the game's id).
    function P.Watch(id)
        sess = ns.SessionKit.New({
            tag = TAG, id = id, state = T, handle = P.OnMessage,
            heartbeat = HEARTBEAT, hostTimeout = HOST_TIMEOUT, joinTimeout = JOIN_TIMEOUT,
            beat = function()
                if P.HasRemote() then
                    P.SendRoster()
                    P.MarkAll()
                    P.Broadcast()
                end
            end,
            hostGone = P.HostGone,
            joinLost = function(message)
                P.SetLobbyMessage(message)
                H.Refresh()
            end,
            hostGroup = function()
                for i = 2, NUM_SEATS do
                    local p = T.seats[i]
                    if p.kind == "remote" and not Net:IsMember(p.name) then H.DropPlayer(i) end
                end
            end,
            changed = function() if T.mode == "lobby" and ui.lobby then H.Refresh() end end,
        })
        P.session = sess
        -- the countdown: a redraw only when the seconds shown change
        ns:Every(0.5, function()
            if T.deadline and ui.table and ui.table:IsVisible() then
                local left = math.ceil(T.deadline - GetTime())
                if left ~= T.shownLeft then
                    T.shownLeft = left
                    H.Refresh()
                end
            end
        end)
    end

    -- Building: saved settings, the felt, the lobby, and a table that didn't
    -- survive a reload. spec: key (ns.db[key]), stats (defaults), noun
    -- ("blackjack"), and the lobby's title, info and buyIns. Returns the db.
    function P.Build(panel, spec)
        ns.db[spec.key] = ns.db[spec.key] or {}
        local db = ns.db[spec.key]
        db.stats = db.stats or {}
        ns.UI.Fill(db.stats, spec.stats)
        Game.panel = panel
        local felt = panel:CreateTexture(nil, "BACKGROUND")
        felt:SetAllPoints(panel)
        felt:SetTexture(0.05, 0.30, 0.12, 1)
        P.BuildLobby(panel, spec)
        return db
    end

    -- After the table's built: a party table can't survive a reload (its
    -- stacks are free, so nothing goes back to your chips).
    function P.Restore(noun)
        P.SetLobbyMessage(sess:Restore(K.db(), { host = "host", seat = "seat", noun = noun .. " table",
            rejoin = function(seat)
                T.joining = { host = seat.host, tid = seat.tid, at = GetTime(), rejoin = true }
                Net:Send(Msg(Net:Pack("tableJoin", { tid = seat.tid, buyin = T.partyBuyIn })))
            end }))
        H.Refresh()
    end

    function Game:OnShow()
        if T.mode == "lobby" and Net:InGroup() then Net:Send(Msg({ "Q" })) end
        if ui.table then H.Refresh() end
    end

    -- The game's hooks into the rest of the casino -------------------------
    function Game:IsSeated() return T.mode ~= "lobby" end

    function Game:ChatTable()
        if (T.mode ~= "host" and T.mode ~= "client") or not T.tid then return nil end
        local host = (T.mode == "host") and Net:Me() or T.host
        local members = { [host] = true }
        for _, p in ipairs(T.seats) do
            if p.kind ~= "empty" and p.kind ~= "bot" and p.name then members[p.name] = true end
        end
        return { game = TAG, host = host, tid = T.tid, members = members }
    end

    -- Party tables are free (everyone plays with the host's stack, not their
    -- chips), but sitting at one still keeps you in the game when you're out.
    function Game:ChipsInPlay() return T.mode ~= "lobby" end

    return P
end
