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
-- The game's table state T needs: mode ("lobby", "host", "client"), seats,
-- mySeat, tid, host, offers, joining, version, dirty, dirtySeats, round,
-- deadline, clock, tableBuyIn and partyBuyIn.

local ns = CowCasino.ns
local Net = ns.Net

local OFFER_TIMEOUT = 60      -- an offer not heard again for this long is dropped from the list
local ROWS = 3                -- tables listed in the lobby

function ns.PartyKit(K)
    local T, ui, H, Game = K.T, K.ui, K.hooks, K.game
    local TAG, NUM_SEATS = K.tag, K.seats
    local P = {}

    local function Fmt(n) return ns:FormatChips(n) end
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
        Net:Send(Msg({ "O", T.tid, NUM_SEATS - P.OpenSeats(), P.OpenSeats(), T.tableBuyIn or T.partyBuyIn,
            Net.PARTY_VERSION }), TAG .. "-O")
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
        T.deadline = GetTime() + seconds
        T.clock = (T.clock or 0) + 1
        local clock, round = T.clock, T.round
        ns:After(seconds, function()
            if T.mode ~= "host" or T.clock ~= clock or T.round ~= round then return end
            onExpire()
        end)
    end

    function P.StopClock()
        T.deadline = nil
        T.clock = (T.clock or 0) + 1
    end

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
        Net:Send(Msg({ "J", tid, buyin, Net.PARTY_VERSION }))
        P.SetLobbyMessage("Asking " .. host .. " for a seat...")
    end

    -- Hooks the table up to the lobby hub (Lobby.lua: pop-ups, badges and
    -- invites), under the menu game id it's shown in. show(): puts the party
    -- lobby on screen, or returns why it can't.
    function P.RegisterLobby(id, show)
        ns.Lobby:Register(id, {
            noun = "table",
            offers = function()
                local out = {}
                for name, o in pairs(T.offers) do
                    if GetTime() - o.heard < OFFER_TIMEOUT and (o.open or 0) > 0 and not Net:VersionProblem(o.ver) then
                        table.insert(out, { host = name, key = o.tid })
                    end
                end
                return out
            end,
            ask = function() Net:Send(Msg({ "Q" })) end,
            join = function(host)
                if T.mode ~= "lobby" then return "You're already at a table." end
                local why = show()
                if why then return why end
                local o = T.offers[host]
                if not o then return host .. "'s table is gone." end
                P.JoinTable(host, o.tid)
            end,
            hosting = function() return T.mode == "host" end,
            busy = function() return T.mode ~= "lobby" or T.joining ~= nil end,
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
            T.offers[sender] = { tid = tid, players = tonumber(f[4]) or 0, open = tonumber(f[5]) or 0,
                buyin = tonumber(f[6]), ver = tonumber(f[7]), heard = GetTime() }
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

        local back = MakeButton(l, "< Solo table", 90, function()
            if Game.onBack then Game.onBack() end
        end)
        back:SetPoint("TOPLEFT", l, "TOPLEFT", 0, -2)

        ui.host = MakeButton(l, "Host a table", 140, function() H.HostTable(T.partyBuyIn) end, 24)
        ui.host:SetPoint("TOP", l, "TOP", 0, -138)

        local header = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", l, "TOPLEFT", 16, -178)
        header:SetText("Tables in your group")
        local refresh = MakeButton(l, "Refresh", 70, function()
            Net:Send(Msg({ "Q" }))
            H.Refresh()
        end)
        refresh:SetPoint("TOPRIGHT", l, "TOPRIGHT", -16, -174)

        ui.rows = {}
        for r = 1, ROWS do
            local r = r   -- own copy for closures (Lua 5.0)
            local row = {}
            row.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("TOPLEFT", l, "TOPLEFT", 18, -206 - (r - 1) * 28)
            row.text:SetWidth(250)
            row.text:SetJustifyH("LEFT")
            row.join = MakeButton(l, "Join", 60, function()
                local offer = ui.rows[r].offer
                if offer then P.JoinTable(offer.host, offer.tid) end
            end)
            row.join:SetPoint("TOPRIGHT", l, "TOPRIGHT", -16, -200 - (r - 1) * 28)
            ui.rows[r] = row
        end

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

        local list = {}
        for name, offer in pairs(T.offers) do
            if GetTime() - offer.heard < OFFER_TIMEOUT and Net:IsMember(name) then
                table.insert(list, { host = name, tid = offer.tid, players = offer.players, open = offer.open,
                    buyin = offer.buyin, ver = offer.ver })
            end
        end
        table.sort(list, function(a, b) return a.host < b.host end)
        for r = 1, ROWS do
            local row, offer = ui.rows[r], list[r]
            row.offer = offer
            if offer then
                row.text:SetText(string.format("%s's table - %d playing, %d open", offer.host, offer.players, offer.open)
                    .. (offer.buyin and ("\n|cffccccccFree " .. Fmt(offer.buyin) .. " stack|r") or "")
                    .. Net:VersionNote(offer.ver))
                row.join:Show()
                ns.SetEnabled(row.join, offer.open > 0 and not T.joining and not Net:VersionProblem(offer.ver))
            else
                row.text:SetText((r == 1 and inGroup) and "|cff888888No tables yet. Ask someone to host, or host one.|r" or "")
                row.join:Hide()
            end
        end
        ui.lobbyStats:SetText(H.LobbyStats())
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
