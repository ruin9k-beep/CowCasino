-- CowCasino: Deathroll
-- The old gold duel. Both players put up the same stake, then take turns
-- rolling: the first roll is 1 to the starting number, and every roll after
-- is 1 to whatever the last one came up. Whoever rolls a 1 loses, and the
-- other player takes both stakes.
--
-- Two ways to play:
--   * against the dealer: you roll first, the dealer answers on its own
--   * a party duel: put up a challenge and anyone in your party or raid
--     with CowCasino can take it. The challenger rolls first. Party rolls
--     are real /rolls, so the whole group sees them in chat.
-- A party duel's rolls are read from the game's own roll messages, and each
-- player's addon also sends its roll in case a message is missed. A duel
-- against the dealer is saved, so a reload carries on where it was; a party
-- duel cut off by a reload is called off and both stakes go back.

local ns = CowCasino.ns
local Net = ns.Net

local AREA_W       = 352
local STAKES       = { 10, 25, 50, 100, 250, 500, 1000, 5000 }
local STARTS       = { 100, 1000, 10000, 100000 }
local LOG_LINES    = 8
local DEALER_PAUSE = 1.1     -- seconds before the dealer rolls back
local ROLL_WAIT    = 3       -- seconds to wait for a /roll to show before rolling here
local OFFER_EVERY  = 20      -- an open challenge is sent again this often
local OFFER_TIMEOUT = 60
local QUIET_LIMIT  = 60      -- after this long without the other player's roll, a duel can be called off
local GAME_TAG     = "DT"

local DEFAULT_STATS = { duels = 0, wins = 0, losses = 0, partyDuels = 0, biggestWin = 0, wagered = 0, won = 0 }

local Deathroll = {
    id = "deathroll",
    name = "Deathroll",
    description = "Take turns rolling lower and lower. Roll a 1 and you lose. Duel the dealer or your party.",
    icon = "Interface\\AddOns\\CowCasino\\Art\\DeathrollIcon",   -- painted (dev/art-src/make_game_icons.py)
    dealer = { idle = "Fancy a deathroll? Roll a 1 and you lose." },
}

local db
local ui = {}
local S = {
    duel = nil,         -- the duel being played (a solo one is also db.duel)
    posted = nil,       -- our open party challenge: { id, stake, start, sentAt }
    offers = {},        -- other players' open challenges: [name] = { id, stake, start, heard }
    accepting = nil,    -- a challenge we asked to take: { host, id }
}

local function Fmt(n) return ns:FormatChips(n) end
local function Msg(parts) return GAME_TAG .. ";" .. table.concat(parts, ";") end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function DealerName()
    local d = ns:GetDealer()
    return (d and d.title) or "The dealer"
end

local function Say(event, vars, fallback, quiet)
    if ns.Dealer then ns.Dealer:React(Deathroll, event, vars, nil, fallback, quiet) end
end

local function NewId() return tostring(math.random(100000, 999999)) end

---------------------------------------------------------------------------
-- The game's own roll message ("Bob rolls 57 (1-100)") as a pattern
---------------------------------------------------------------------------
local rollPattern
local function RollPattern()
    if rollPattern then return rollPattern end
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    -- escape everything magic, then turn %s and %d into captures
    local p = string.gsub(fmt, "([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
    p = string.gsub(p, "%%s", "(.+)")
    p = string.gsub(p, "%%d", "(%%d+)")
    rollPattern = "^" .. p .. "$"
    return rollPattern
end

-- name, value, low, high from a roll message, or nil.
local function ParseRoll(text)
    if type(text) ~= "string" then return nil end
    local _, _, name, v, lo, hi = string.find(text, RollPattern())
    if not name then return nil end
    -- a player from another realm can show as "Name-Realm"
    local _, _, short = string.find(name, "^([^%-%s]+)")
    return short or name, tonumber(v), tonumber(lo), tonumber(hi)
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function SetStatus(text, r, g, b)
    ui.status:SetText(text or "")
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function StatsText()
    local s = db.stats
    local net = s.won - s.wagered
    local netText = (net > 0 and ("|cff40ff40+" .. Fmt(net))) or (net < 0 and ("|cffff5050-" .. Fmt(-net))) or "|cffcccccc0"
    return string.format("Duels %d  Won %d  Lost %d  Biggest win %s  Net %s|r",
        s.duels, s.wins, s.losses, Fmt(s.biggestWin), netText)
end

local function OppName(d)
    if d.kind == "solo" then return DealerName() end
    return d.opp or "?"
end

local function OpenOffers()
    local list = {}
    for name, o in pairs(S.offers) do
        if GetTime() - o.heard < OFFER_TIMEOUT and Net:IsMember(name) then
            table.insert(list, { host = name, id = o.id, stake = o.stake, start = o.start })
        end
    end
    table.sort(list, function(a, b) return a.host < b.host end)
    return list
end

local function Quiet(d)
    return d and d.kind == "party" and d.turn == "them" and GetTime() - (d.heard or 0) > QUIET_LIMIT
end

local function Refresh()
    if not ui.range then return end
    ns:UpdateChipsDisplay()
    local d = S.duel
    local party = db.mode == "party"
    ns.SetEnabled(ui.soloTab, d == nil and not S.posted and party)
    ns.SetEnabled(ui.partyTab, d == nil and not party)
    ui.soloTab:SetText((not party and "|cffffff00" or "") .. "Vs " .. DealerName())
    ui.partyTab:SetText((party and "|cffffff00" or "") .. "Party duel")

    -- the range and whose roll it is
    if d then
        ui.range:SetText("1 - " .. Fmt(d.max))
        if d.turn == "me" then
            ui.whose:SetText("|cff66ff66Your roll|r against " .. OppName(d) .. "  -  " .. Fmt(d.stake) .. " each")
        else
            ui.whose:SetText(OppName(d) .. "'s roll  -  " .. Fmt(d.stake) .. " each")
        end
    elseif db.lastLog then
        ui.range:SetText(db.lastRange or "")
        ui.whose:SetText("")
    else
        ui.range:SetText("1 - " .. Fmt(db.start))
        ui.whose:SetText("")
    end

    -- the rolls so far, or the open challenges in the party lobby
    local showLobby = party and not d
    local log = (d and d.log) or db.lastLog or {}
    for i = 1, LOG_LINES do ui.log[i]:SetText("") end
    if not showLobby then
        local n = ns.getn(log)
        for i = 1, LOG_LINES do
            local line = log[n - LOG_LINES + i]
            ui.log[i]:SetText(line or "")
        end
    end
    local list = showLobby and OpenOffers() or {}
    for r = 1, 3 do
        local row, offer = ui.rows[r], list[r]
        row.offer = offer
        if offer then
            row.text:SetText(string.format("%s: %s each, from %s", offer.host, Fmt(offer.stake), Fmt(offer.start)))
            row:Show()
            ns.SetEnabled(row.accept, ns.db.chips >= offer.stake and not S.accepting and not S.posted)
        else
            row:Hide()
        end
    end
    ns.SetShown(ui.lobbyTitle, showLobby)
    if showLobby then
        ui.lobbyTitle:SetText(list[1] and "Open challenges in your group:" or
            (Net:InGroup() and "No open challenges in your group yet." or "Join a party or raid to duel your friends."))
    end

    -- stake and starting number
    local idle = d == nil and not S.posted
    local si, ti = 1, 1
    for i, v in ipairs(STAKES) do if v == db.stake then si = i end end
    for i, v in ipairs(STARTS) do if v == db.start then ti = i end end
    ns.SetEnabled(ui.stakeDown, idle and si > 1)
    ns.SetEnabled(ui.stakeUp, idle and si < ns.getn(STAKES))
    ns.SetEnabled(ui.startDown, idle and ti > 1)
    ns.SetEnabled(ui.startUp, idle and ti < ns.getn(STARTS))
    ui.stakeText:SetText("Stake |cffffffff" .. Fmt(db.stake) .. "|r")
    ui.startText:SetText("From |cffffffff" .. Fmt(db.start) .. "|r")

    -- the main button
    ui.forfeit:Hide()
    if d then
        if d.turn == "me" then
            ui.go:SetText(d.pending and "Rolling..." or ("Roll 1-" .. Fmt(d.max)))
            ns.SetEnabled(ui.go, not d.pending)
        else
            ui.go:SetText("Waiting for " .. OppName(d))
            ns.SetEnabled(ui.go, false)
        end
        if d.kind == "party" then
            ui.forfeit:SetText(Quiet(d) and "Call it off" or "Forfeit")
            ui.forfeit:Show()
        end
    elseif party then
        if S.posted then
            ui.go:SetText("Withdraw challenge")
            ns.SetEnabled(ui.go, true)
        else
            ui.go:SetText("Challenge the group")
            ns.SetEnabled(ui.go, Net:InGroup() and ns.db.chips >= db.stake and not S.accepting)
        end
    else
        ui.go:SetText("Duel " .. DealerName() .. " for " .. Fmt(db.stake))
        ns.SetEnabled(ui.go, ns.db.chips >= db.stake)
    end
    ui.stats:SetText(StatsText())
end

---------------------------------------------------------------------------
-- A duel
---------------------------------------------------------------------------
local function AddLog(d, text)
    table.insert(d.log, text)
    while ns.getn(d.log) > 20 do table.remove(d.log, 1) end
end

-- Start a duel (the stake is already paid). first: "me" or "them".
local function StartDuel(kind, stake, start, first, opp, id)
    local d = { kind = kind, stake = stake, start = start, max = start, turn = first, opp = opp, id = id,
        turnNo = 1, log = {}, heard = GetTime() }
    S.duel = d
    if kind == "solo" then db.duel = d else db.partyDuel = { id = id, stake = stake, opp = opp } end
    db.stats.duels = db.stats.duels + 1
    if kind == "party" then db.stats.partyDuels = db.stats.partyDuels + 1 end
    db.stats.wagered = db.stats.wagered + stake
    AddLog(d, string.format("|cffffd100Deathroll from %s, %s each.|r", Fmt(start), Fmt(stake)))
    ns:PlayGameSound(db, "newHand")
    local who = first == "me" and "You roll" or (OppName(d) .. " rolls")
    SetStatus(who .. " first. Roll a 1 and you lose!")
    if kind == "solo" then
        Say("deathrollStart", { stake = Fmt(stake), start = Fmt(start) }, "Deathroll! You roll first.")
    else
        Say("deathrollParty", { name = OppName(d), stake = Fmt(stake), start = Fmt(start) }, "A deathroll duel! Roll a 1 and you lose.")
        if ns.Dealer then ns.Dealer:SetPlayer(Deathroll, opp) end
    end
    Refresh()
end

-- The duel is over: loser is "me" or "them" (nil when it's called off).
local function EndDuel(loser, how)
    local d = S.duel
    if not d then return end
    S.duel = nil
    db.duel, db.partyDuel = nil, nil
    local s = db.stats
    local opp = OppName(d)
    if loser == "them" then
        local paid = d.stake * 2
        ns:AddChips(paid)
        s.wins = s.wins + 1
        s.won = s.won + paid
        if d.stake > s.biggestWin then s.biggestWin = d.stake end
        SetStatus((how or (opp .. " rolled a 1!")) .. " You win " .. Fmt(paid) .. ".", 0.25, 1, 0.25)
        ns:PlayGameSound(db, "win")
        Say("deathrollWin", { name = opp, amount = Fmt(d.stake) }, "You win the duel!")
    elseif loser == "me" then
        s.losses = s.losses + 1
        SetStatus((how or "You rolled a 1!") .. " " .. opp .. " takes the " .. Fmt(d.stake * 2) .. ".", 1, 0.4, 0.4)
        ns:PlayGameSound(db, "lose")
        Say("deathrollLose", { name = opp, amount = Fmt(d.stake) }, "A 1. That's the duel.")
    else
        ns:AddChips(d.stake)
        s.wagered = s.wagered - d.stake
        s.duels = s.duels - 1
        if d.kind == "party" then s.partyDuels = s.partyDuels - 1 end
        SetStatus((how or "The duel is called off.") .. " Your " .. Fmt(d.stake) .. " is back.", 0.85, 0.85, 0.85)
    end
    if ns.Dealer and d.kind == "party" then ns.Dealer:SetImage(Deathroll, nil) end
    db.lastLog = d.log
    db.lastRange = "1 - " .. Fmt(d.max)
    while db.stake > STAKES[1] and db.stake > ns.db.chips do
        local i = 1
        for k, v in ipairs(STAKES) do if v == db.stake then i = k end end
        db.stake = STAKES[i - 1]
    end
    if ns.db.chips < STAKES[1] and not S.duel then SetStatus(ns:LowChipsText(STAKES[1]), 1, 0.35, 0.35) end
    Refresh()
end

-- A roll is in: who is "me" or "them".
local function ApplyRoll(who, value)
    local d = S.duel
    if not d or d.turn ~= who then return end
    local from = d.max
    d.max = value
    d.pending = nil
    d.turnNo = d.turnNo + 1
    d.heard = GetTime()
    local name = who == "me" and "You" or OppName(d)
    local color = value == 1 and "|cffff4040" or (value <= 10 and "|cffffa040" or "|cffffffff")
    AddLog(d, string.format("%s %s %s%s|r (1-%s)", name, who == "me" and "roll" or "rolls", color, Fmt(value), Fmt(from)))
    if value == 1 then
        EndDuel(who == "me" and "me" or "them")
        return
    end
    d.turn = (who == "me") and "them" or "me"
    if d.kind == "solo" and d.turn == "them" then d.dealerAt = GetTime() + DEALER_PAUSE end
    if value <= 10 and from > 10 then
        Say("deathrollClose", { name = who == "me" and "you" or name, value = value }, nil, true)
    end
    if d.kind == "party" and d.turn == "me" then ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON") end
    SetStatus(d.turn == "me" and ("Your roll: 1 to " .. Fmt(value) .. ".") or (OppName(d) .. " rolls next: 1 to " .. Fmt(value) .. "."))
    Refresh()
end

-- Our roll in a party duel: the value is in, so tell the other player and apply it.
local function MyPartyRoll(value)
    local d = S.duel
    if not d or d.kind ~= "party" or d.turn ~= "me" then return end
    Net:Send(Msg({ "R", d.id, d.turnNo, value }))
    ApplyRoll("me", value)
end

local function Roll()
    local d = S.duel
    if not d or d.turn ~= "me" or d.pending then return end
    if d.kind == "solo" then
        ApplyRoll("me", math.random(1, d.max))
        return
    end
    -- a real /roll, so the group sees it; its message comes back to us
    d.pending = GetTime()
    if RandomRoll then RandomRoll(1, d.max) end
    Refresh()
end

---------------------------------------------------------------------------
-- Against the dealer
---------------------------------------------------------------------------
local function DuelDealer()
    if S.duel then return end
    if not ns:SpendChips(db.stake) then
        SetStatus(ns:LowChipsText(db.stake), 1, 0.35, 0.35)
        return
    end
    StartDuel("solo", db.stake, db.start, "me")
end

---------------------------------------------------------------------------
-- Party duels
---------------------------------------------------------------------------
local function SendOffer()
    local p = S.posted
    if not p then return end
    p.sentAt = GetTime()
    Net:Send(Msg({ "O", p.id, p.stake, p.start }), "DT-O")
end

local function PostChallenge()
    if S.duel or S.posted or not Net:InGroup() then return end
    if ns.db.chips < db.stake then
        SetStatus(ns:LowChipsText(db.stake), 1, 0.35, 0.35)
        return
    end
    S.posted = { id = NewId(), stake = db.stake, start = db.start }
    SendOffer()
    SetStatus("Challenge sent: " .. Fmt(db.stake) .. " each, from " .. Fmt(db.start) .. ". Waiting for someone to take it...")
    Refresh()
end

local function Withdraw(quiet)
    if not S.posted then return end
    Net:Send(Msg({ "X", S.posted.id }), "DT-O")
    S.posted = nil
    if not quiet then SetStatus("Challenge withdrawn.") end
    Refresh()
end

local function Accept(offer)
    if S.duel or S.posted or S.accepting or not offer then return end
    if ns.db.chips < offer.stake then
        SetStatus(ns:LowChipsText(offer.stake), 1, 0.35, 0.35)
        return
    end
    S.accepting = { host = offer.host, id = offer.id, at = GetTime() }
    Net:Send(Msg({ "A", offer.id }))
    SetStatus("Taking " .. offer.host .. "'s challenge...")
    Refresh()
end

local function Forfeit()
    local d = S.duel
    if not d then return end
    if d.kind == "party" then
        if Quiet(d) then
            Net:Send(Msg({ "C", d.id }))
            EndDuel(nil, OppName(d) .. " has gone quiet, so the duel is called off.")
            return
        end
        Net:Send(Msg({ "F", d.id }))
    end
    EndDuel("me", "You forfeit.")
end

local function OnMessage(sender, f)
    local kind, id = f[2], f[3]
    if kind == "Q" then
        SendOffer()
        return
    elseif kind == "O" then
        S.offers[sender] = { id = id, stake = tonumber(f[4]) or 0, start = tonumber(f[5]) or 0, heard = GetTime() }
        if ns.currentGame == "deathroll" then Refresh() end
        return
    elseif kind == "X" then
        S.offers[sender] = nil
        if S.accepting and S.accepting.host == sender then
            S.accepting = nil
            SetStatus(sender .. " withdrew that challenge.")
        end
        if ns.currentGame == "deathroll" then Refresh() end
        return
    end

    -- someone takes our challenge: the first one gets it
    if kind == "A" then
        local p = S.posted
        if not p or p.id ~= id or S.duel or not Net:IsMember(sender) then return end
        S.posted = nil
        if not ns:SpendChips(p.stake) then
            Net:Send(Msg({ "X", p.id }), "DT-O")
            SetStatus(ns:LowChipsText(p.stake), 1, 0.35, 0.35)
            Refresh()
            return
        end
        Net:Send(Msg({ "S", p.id, sender }), "DT-O")
        StartDuel("party", p.stake, p.start, "me", sender, p.id)
        return
    end

    -- the challenger starts the duel (with us, or with someone quicker)
    if kind == "S" then
        local offer = S.offers[sender]
        S.offers[sender] = nil
        local a = S.accepting
        if a and a.host == sender and a.id == id then
            S.accepting = nil
            if f[4] ~= Net:Me() then
                SetStatus(f[4] .. " took " .. sender .. "'s challenge first.")
            elseif not offer or not ns:SpendChips(offer.stake) then
                Net:Send(Msg({ "C", id }))
                SetStatus("Not enough chips for that duel any more.", 1, 0.35, 0.35)
            else
                StartDuel("party", offer.stake, offer.start, "them", sender, id)
                return
            end
        end
        if ns.currentGame == "deathroll" then Refresh() end
        return
    end

    local d = S.duel
    if not d or d.kind ~= "party" or d.id ~= id or sender ~= d.opp then return end
    d.heard = GetTime()
    if kind == "R" then
        local turnNo, value = tonumber(f[4]), tonumber(f[5])
        if d.turn == "them" and turnNo == d.turnNo and value and value >= 1 and value <= d.max then
            ApplyRoll("them", value)
        end
    elseif kind == "F" then
        EndDuel("them", sender .. " forfeits!")
    elseif kind == "C" then
        EndDuel(nil, sender .. " called the duel off.")
    end
end

Net.handlers[GAME_TAG] = OnMessage

Net.groupHandlers.deathroll = function()
    for name in pairs(S.offers) do
        if not Net:IsMember(name) then S.offers[name] = nil end
    end
    if S.accepting and not Net:IsMember(S.accepting.host) then S.accepting = nil end
    if S.posted and not Net:InGroup() then S.posted = nil end
    local d = S.duel
    if d and d.kind == "party" and not Net:IsMember(d.opp) then
        EndDuel(nil, d.opp .. " left the group, so the duel is called off.")
    end
    if ns.currentGame == "deathroll" and ui.range then Refresh() end
end

-- Roll messages: ours and the other player's, read from the system chat.
local listener = ns.CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_SYSTEM")
listener:SetScript("OnEvent", function()
    local d = S.duel
    if not d or d.kind ~= "party" then return end
    local name, value, lo, hi = ParseRoll(arg1)
    if not name or lo ~= 1 or hi ~= d.max or not value then return end
    if name == Net:Me() and d.turn == "me" and d.pending then
        MyPartyRoll(value)
    elseif name == d.opp and d.turn == "them" then
        ApplyRoll("them", value)
    end
end)

-- The dealer's answer, /rolls that never showed, and open challenges.
local ticker = ns.CreateFrame("Frame")
local tickWait = 0
ticker:SetScript("OnUpdate", function()
    if not db then return end
    tickWait = tickWait + (arg1 or 0)
    if tickWait < 0.1 then return end
    tickWait = 0
    local d = S.duel
    local now = GetTime()
    if d and d.kind == "solo" and d.turn == "them" then
        d.dealerAt = d.dealerAt or (now + DEALER_PAUSE)
        if now >= d.dealerAt then
            d.dealerAt = nil
            ApplyRoll("them", math.random(1, d.max))
        end
    elseif d and d.kind == "party" and d.turn == "me" and d.pending and now - d.pending > ROLL_WAIT then
        -- the /roll didn't come back (or this client can't /roll): roll here
        MyPartyRoll(math.random(1, d.max))
    elseif d and d.kind == "party" and Quiet(d) and not d.quietShown then
        d.quietShown = true
        if ns.currentGame == "deathroll" then Refresh() end
    end
    if S.posted and now - (S.posted.sentAt or 0) >= OFFER_EVERY then SendOffer() end
    if S.accepting and now - S.accepting.at > 15 then
        S.accepting = nil
        if ui.range then
            SetStatus("No answer to that challenge.")
            Refresh()
        end
    end
end)

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function MakeButton(parent, text, width, onClick, height)
    local b = ns.CreateFrame("Button", ns:NewName(), parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(height or 22)
    b:SetText(text)
    b:SetScript("OnClick", function() onClick(this, arg1) end)
    return b
end

local function Step(list, key, dir)
    if S.duel or S.posted then return end
    local idx = 1
    for i, v in ipairs(list) do if v == db[key] then idx = i end end
    idx = math.max(1, math.min(ns.getn(list), idx + dir))
    db[key] = list[idx]
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

local function SetMode(mode)
    if S.duel or S.posted or db.mode == mode then return end
    db.mode = mode
    ns:Sound("IG_MAINMENU_OPTION")
    if mode == "party" then
        Net:Send(Msg({ "Q" }))
        SetStatus(Net:InGroup() and "Challenge your group, or take a challenge below."
            or "Join a party or raid to duel your friends.")
    else
        SetStatus("Pick a stake and a starting number, then duel " .. DealerName() .. ".")
    end
    Refresh()
end

local function BuildOptions(panel)
    local o = ns.CreateFrame("Frame", nil, panel)
    o:SetAllPoints(panel)
    o:SetFrameLevel(panel:GetFrameLevel() + 50)
    o:EnableMouse(true)
    o:Hide()
    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0, 0, 0, 0.94)
    local title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", o, "TOP", 0, -10)
    title:SetText("Deathroll Options")

    local rules = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rules:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -40)
    rules:SetWidth(AREA_W - 32)
    rules:SetJustifyH("LEFT")
    rules:SetText("How it plays: both players put up the stake. The first roll is 1 to the starting number; "
        .. "each roll after that is 1 to the last roll. Whoever rolls a 1 loses, and the other takes both "
        .. "stakes. It's an even game: neither side has the edge.\n\n"
        .. "Vs the dealer: you roll first and the dealer answers.\n\n"
        .. "Party duel: Challenge the group, and the first player with CowCasino to accept is your opponent. "
        .. "The challenger rolls first. Party rolls are real /rolls everyone can see. Forfeit gives up the "
        .. "duel; if the other player goes quiet for a minute you can call it off instead, and both stakes "
        .. "go back. A reload calls a party duel off too.")

    local reset
    reset = MakeButton(o, "Reset stats", 110, function()
        if reset.armed and GetTime() - reset.armed <= 3 then
            reset.armed = nil
            reset:SetText("Reset stats")
            db.stats = {}
            Fill(db.stats, DEFAULT_STATS)
            Refresh()
            return
        end
        reset.armed = GetTime()
        reset:SetText("Sure? Click again")
    end)
    reset:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", 16, 40)
    local sounds = MakeButton(o, "Sounds", 80, function() ui.sounds:Show() end)
    sounds:SetPoint("BOTTOM", o, "BOTTOM", 0, 40)
    local done = MakeButton(o, "Done", 90, function() o:Hide() end)
    done:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -16, 40)
    o:SetScript("OnShow", function()
        reset.armed = nil
        reset:SetText("Reset stats")
    end)
    return o
end

function Deathroll:Build(panel)
    ns.db.deathroll = ns.db.deathroll or {}
    db = ns.db.deathroll
    db.mode = db.mode or "solo"
    db.stake = db.stake or 100
    db.start = db.start or 1000
    db.stats = db.stats or {}
    Fill(db.stats, DEFAULT_STATS)
    ns:InitSounds(db)

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.18, 0.04, 0.04, 0.94)

    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    ui.soloTab = MakeButton(panel, "Vs the dealer", 150, function() SetMode("solo") end)
    ui.soloTab:SetPoint("TOPRIGHT", panel, "TOP", -4, -6)
    ui.partyTab = MakeButton(panel, "Party duel", 150, function() SetMode("party") end)
    ui.partyTab:SetPoint("TOPLEFT", panel, "TOP", 4, -6)

    ui.range = ns:BigFont(panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 30)
    ui.range:SetPoint("TOP", panel, "TOP", 0, -40)
    ui.range:SetTextColor(1, 0.85, 0.1)
    ui.whose = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.whose:SetPoint("TOP", panel, "TOP", 0, -78)

    -- the rolls so far
    local logBg = panel:CreateTexture(nil, "BORDER")
    logBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -98)
    logBg:SetWidth(AREA_W - 40); logBg:SetHeight(LOG_LINES * 14 + 8)
    logBg:SetTexture(0, 0, 0, 0.4)
    ui.log = {}
    for i = 1, LOG_LINES do
        local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("TOP", panel, "TOP", 0, -102 - (i - 1) * 14)
        ui.log[i] = t
    end

    -- open challenges (party mode, between duels), over the log
    ui.lobbyTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ui.lobbyTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 28, -104)
    ui.rows = {}
    for r = 1, 3 do
        local r = r
        local row = ns.CreateFrame("Frame", nil, panel)
        row:SetWidth(AREA_W - 56); row:SetHeight(24)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 28, -122 - (r - 1) * 28)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.accept = MakeButton(row, "Accept", 70, function() Accept(ui.rows[r].offer) end)
        row.accept:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row:Hide()
        ui.rows[r] = row
    end

    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", panel, "TOP", 0, -98 - LOG_LINES * 14 - 16)
    ui.status:SetWidth(AREA_W - 8)

    -- stake and starting number
    local row = ns.CreateFrame("Frame", nil, panel)
    row:SetWidth(AREA_W - 8); row:SetHeight(24)
    row:SetPoint("BOTTOM", panel, "BOTTOM", 0, 52)
    ui.stakeDown = MakeButton(row, "<", 24, function() Step(STAKES, "stake", -1) end)
    ui.stakeDown:SetPoint("LEFT", row, "LEFT", 6, 0)
    ui.stakeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.stakeText:SetPoint("LEFT", ui.stakeDown, "RIGHT", 2, 0)
    ui.stakeText:SetWidth(104)
    ui.stakeUp = MakeButton(row, ">", 24, function() Step(STAKES, "stake", 1) end)
    ui.stakeUp:SetPoint("LEFT", ui.stakeText, "RIGHT", 2, 0)
    ui.startUp = MakeButton(row, ">", 24, function() Step(STARTS, "start", 1) end)
    ui.startUp:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    ui.startText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.startText:SetPoint("RIGHT", ui.startUp, "LEFT", -2, 0)
    ui.startText:SetWidth(104)
    ui.startDown = MakeButton(row, "<", 24, function() Step(STARTS, "start", -1) end)
    ui.startDown:SetPoint("RIGHT", ui.startText, "LEFT", -2, 0)

    ui.go = MakeButton(panel, "Duel", 170, function()
        if S.duel then Roll()
        elseif db.mode == "party" then
            if S.posted then Withdraw() else PostChallenge() end
        else DuelDealer() end
    end, 28)
    ui.go:SetPoint("BOTTOM", panel, "BOTTOM", 0, 18)
    ui.forfeit = MakeButton(panel, "Forfeit", 72, Forfeit, 24)
    ui.forfeit:SetPoint("LEFT", ui.go, "RIGHT", 6, 0)
    ui.forfeit:Hide()

    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 3)

    ui.options = BuildOptions(panel)
    ui.sounds = ns:CreateSoundOptions(panel, "Deathroll Options", function() return db end)

    if db.partyDuel then
        -- a party duel cut off by a reload: call it off, both stakes go back
        local p = db.partyDuel
        db.partyDuel = nil
        ns:AddChips(p.stake)
        db.stats.wagered = db.stats.wagered - p.stake
        Net:Send(Msg({ "C", p.id }))
        SetStatus("Your party duel with " .. tostring(p.opp) .. " was called off by the reload. Your "
            .. Fmt(p.stake) .. " is back.")
    elseif db.duel then
        S.duel = db.duel
        S.duel.pending = nil
        SetStatus("Welcome back - your duel with " .. DealerName() .. " is still on.")
    elseif db.mode == "party" then
        Net:Send(Msg({ "Q" }))
        SetStatus(Net:InGroup() and "Challenge your group, or take a challenge below."
            or "Join a party or raid to duel your friends.")
    else
        SetStatus("Pick a stake and a starting number, then duel " .. DealerName() .. ".")
    end
    Refresh()
end

function Deathroll:OnShow()
    if ui.range then
        if db.mode == "party" and not S.duel then Net:Send(Msg({ "Q" })) end
        Refresh()
    end
end

function Deathroll:OnHide()
    if ui.options then ui.options:Hide() end
    if ui.sounds then ui.sounds:Hide() end
end

function Deathroll:ChipsInPlay()
    local d = ns.db.deathroll
    return S.duel ~= nil or (d ~= nil and (d.duel ~= nil or d.partyDuel ~= nil))
end

-- Start over (Options): a duel in progress is forfeited.
function Deathroll:Abandon()
    if S.posted then Withdraw(true) end
    if S.duel then
        if S.duel.kind == "party" then Net:Send(Msg({ "F", S.duel.id })) end
        EndDuel("me", "You forfeit.")
    else
        local d = ns.db.deathroll
        if d then d.duel, d.partyDuel = nil, nil end
    end
end

function Deathroll:ResetStats()
    local d = ns.db.deathroll
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    if ui.stats and db then Refresh() end
end

-- Exposed for tests.
Deathroll.S, Deathroll.ui, Deathroll.ParseRoll = S, ui, ParseRoll

ns:RegisterGame(Deathroll)
