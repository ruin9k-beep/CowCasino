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
--     are real /rolls, so the whole group sees them in chat. Party duels are
--     free: the stake is just for bragging rights, and nobody's chips move.
-- A party duel's rolls are read from the game's own roll messages, and each
-- player's addon also sends its roll in case a message is missed. A duel
-- against the dealer is saved, so a reload carries on where it was; a party
-- duel cut off by a reload is called off.

local ns = CowCasino.ns
local Net = ns.Net

local AREA_W       = 352
local STAKES       = { 10, 25, 50, 100, 250, 500, 1000, 5000 }
local STARTS       = { 100, 1000, 10000, 100000 }
local LOG_LINES    = 10      -- (setting up a duel happens on the intro screen, so the rolls get the room)
local PIC          = 70      -- the two portraits at the top, facing each other
local FACE         = 0.6     -- how far each turns toward the other (radians)
local DEALER_PAUSE = 1.1     -- seconds before the dealer rolls back
local ROLL_WAIT    = 3       -- seconds to wait for a /roll to show before rolling here
local QUIET_LIMIT  = 60      -- after this long without the other player's roll, a duel can be called off
local GAME_TAG     = "DT"

local DEFAULT_STATS = { duels = 0, wins = 0, losses = 0, partyDuels = 0, biggestWin = 0, wagered = 0, won = 0 }

local Deathroll = {
    id = "deathroll",
    name = "Deathroll",
    description = "Roll lower and lower. Roll a 1 and you lose.\n|cff66ccffSupports Multiplayer|r",
    icon = "Interface\\AddOns\\CowCasino\\Art\\DeathrollIcon",   -- painted (dev/art-src/make_game_icons.py)
    dealer = { idle = "Roll a 1 and you lose." },
}

local db
local ui = {}
local S = {
    duel = nil,         -- the duel being played (a solo one is also db.duel)
    posted = nil,       -- our open party challenge: { id, stake, start, sentAt }
    offers = {},        -- other players' open challenges: [name] = { id, stake, start, heard }
    accepting = nil,    -- a challenge we asked to take: { host, id }
}
local ch    -- the challenges (Games\ChallengeKit.lua), made below once the duel's own messages are

local Fmt = ns.Fmt
local function Msg(parts) return GAME_TAG .. ";" .. table.concat(parts, ";") end

local Fill = ns.UI.Fill

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
local function SetStatus(text, r, g, b) ns.UI.SetStatus(ui.status, text, r, g, b, Deathroll) end

local function StatsText()
    local s = db.stats
    local net = s.won - s.wagered
    local netText = ns.UI.Net(net)
    return string.format("Duels %d  Won %d  Lost %d  Biggest win %s  Net %s|r",
        s.duels, s.wins, s.losses, Fmt(s.biggestWin), netText)
end

local function OppName(d)
    if d.kind == "solo" then return DealerName() end
    return d.opp or "?"
end

local function OpenOffers() return ch:OpenOffers() end      -- (a rematch for someone else isn't open to us)

-- what's riding on a duel: chips against the dealer, bragging rights in a party
local function StakeText(d)
    if d.kind == "party" then return "for " .. Fmt(d.stake) .. " (free)" end
    return Fmt(d.stake) .. " each"
end

local function Quiet(d)
    return d and d.kind == "party" and d.turn == "them" and GetTime() - (d.heard or 0) > QUIET_LIMIT
end

-- The intro screen (Intro.lua), up between duels: Vs the dealer (stake,
-- starting number, Duel) and the group (the same two, Challenge, and the open
-- challenges to accept).
local function RefreshIntro()
    local intro = ui.intro
    ns:UpdateIntro(Deathroll)
    for _, p in ipairs(ui.pickers) do p:Refresh() end
    intro.soloGo:SetText("Duel " .. DealerName() .. " for " .. Fmt(db.stake))
    ns.SetEnabled(intro.soloGo, ns.db.chips >= db.stake and not S.posted and not S.accepting)
    if S.posted then
        intro.hostGo:SetText("Withdraw challenge")
        ns.SetEnabled(intro.hostGo, true)
    else
        intro.hostGo:SetText("Challenge the group")
        ns.SetEnabled(intro.hostGo, Net:InGroup() and not S.accepting)
    end
    local list, rows = OpenOffers(), {}
    for _, offer in ipairs(list) do
        local o = offer
        table.insert(rows, {
            text = string.format("%s: for %s, from %s (free)", o.host, Fmt(o.stake), Fmt(o.start)) .. Net:VersionNote(o.ver),
            label = "Accept", host = o.host, stake = o.stake,
            enabled = not S.accepting and not S.posted and not Net:VersionProblem(o.ver),
            click = function() ui.onAccept(o) end,
        })
    end
    intro:SetOffers(rows)
    intro:SetNote(S.posted and "Your challenge is open. Waiting for someone to accept..."
        or (list[1] and "Open challenges in your group:")
        or (Net:InGroup() and "No open challenges in your group yet." or "Join a party or raid to duel your friends."))
    intro:SetStats(StatsText())
end

local function Refresh()
    if not ui.range then return end
    ns:UpdateChipsDisplay()
    local d = S.duel
    RefreshIntro()

    -- the range and whose roll it is
    if d then
        ui.range:SetText("1 - " .. Fmt(d.max))
        if d.turn == "me" then
            ui.whose:SetText("|cff66ff66Your roll|r against " .. OppName(d) .. "  -  " .. StakeText(d))
        else
            ui.whose:SetText(OppName(d) .. "'s roll  -  " .. StakeText(d))
        end
    elseif db.lastLog then
        ui.range:SetText(db.lastRange or "")
        ui.whose:SetText("")
    else
        ui.range:SetText("1 - " .. Fmt(db.start))
        ui.whose:SetText("")
    end

    -- the two of you (the last duel's opponent after it)
    local opp = d and { kind = d.kind, name = d.opp } or db.lastOpp
    ui.youPic:ShowUnit("player")
    ui.youName:SetText("You")
    if not opp then
        ui.oppPic:ShowUnit(nil)
        ui.oppImage:Hide()
        ui.oppName:SetText("")
    elseif opp.kind == "solo" then
        -- the dealer: their 3D model facing you where the client can show it
        -- (Portraits.lua), their picture until then (or instead)
        local pack = ns:GetDealer()
        local image = pack.image
        if type(image) == "table" then
            ui.oppImage:SetTexture(image[1])
            ui.oppImage:SetTexCoord(image[2] or 0, image[3] or 1, image[4] or 0, image[5] or 1)
        else
            ui.oppImage:SetTexture(image)
            ui.oppImage:SetTexCoord(0, 1, 0, 1)
        end
        ui.oppPic:ShowCreature(pack.model or pack.portrait)
        ns.SetShown(ui.oppImage, ui.oppPic.cstate ~= "shown")
        ui.oppName:SetText(DealerName())
    else
        ui.oppImage:Hide()
        ui.oppPic:ShowUnit(Net:UnitFor(opp.name))
        ui.oppName:SetText(opp.name or "?")
    end
    -- whose roll it is: their name lit up
    local mine, theirs = d and d.turn == "me", d and d.turn ~= "me"
    ui.youName:SetTextColor(mine and 0.4 or 1, mine and 1 or 0.82, mine and 0.4 or 0)
    ui.oppName:SetTextColor(theirs and 0.4 or 1, theirs and 1 or 0.82, theirs and 0.4 or 0)

    -- the rolls so far
    local log = (d and d.log) or db.lastLog or {}
    local n = ns.getn(log)
    for i = 1, LOG_LINES do ui.log[i]:SetText(log[n - LOG_LINES + i] or "") end

    -- the field's buttons: Roll in a duel; Play again and Setup after one
    ui.forfeit:Hide()
    ns.SetShown(ui.go, d ~= nil)
    -- (after a party duel: a rematch with the same player)
    local over = d == nil and S.over
    ns.SetShown(ui.again, over and true or false)
    if over and over.kind == "party" then
        local state = ch:RematchState(over.opp)
        ui.again:SetText(state == "accept" and "Accept rematch" or state == "sent" and "Cancel rematch" or "Rematch")
        ns.SetEnabled(ui.again, state ~= "gone" and not S.accepting and (state ~= "offer" or not S.posted))
    elseif over then
        ui.again:SetText("Again for " .. Fmt(db.stake))
        ns.SetEnabled(ui.again, ns.db.chips >= db.stake)
    end
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
    end
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
    db.lastOpp = { kind = kind, name = opp }     -- (who the portraits show after the duel)
    if kind == "solo" then db.duel = d else db.partyDuel = { id = id, stake = stake, opp = opp } end
    db.stats.duels = db.stats.duels + 1
    if kind == "party" then db.stats.partyDuels = db.stats.partyDuels + 1 end
    if kind == "solo" then db.stats.wagered = db.stats.wagered + stake end   -- party duels are free
    AddLog(d, string.format(kind == "solo" and "|cffffd100Deathroll from %s, %s each.|r"
        or "|cffffd100Deathroll from %s, for %s (free).|r", Fmt(start), Fmt(stake)))
    ns:PlayGameSound(db, "newHand")
    local who = first == "me" and "You roll" or (OppName(d) .. " rolls")
    SetStatus(who .. " first. Roll a 1 and you lose.")
    if kind == "solo" then
        Say("deathrollStart", { stake = Fmt(stake), start = Fmt(start) }, "You roll first.")
    else
        Say("deathrollParty", { name = OppName(d), stake = Fmt(stake), start = Fmt(start) }, "Roll a 1 and you lose.")
        if ns.Dealer then ns.Dealer:SetPlayer(Deathroll, opp) end
    end
    Refresh()
end

-- The duel is over: loser is "me" or "them" (nil when it's called off).
local function EndDuel(loser, how)
    local d = S.duel
    if not d then return end
    S.duel = nil
    S.over = { kind = d.kind, opp = d.opp, stake = d.stake, start = d.start }
    db.duel, db.partyDuel = nil, nil
    local s = db.stats
    local opp = OppName(d)
    local party = d.kind == "party"
    if loser == "them" then
        local paid = d.stake * 2
        s.wins = s.wins + 1
        if party then
            SetStatus((how or (opp .. " rolled a 1!")) .. " You win the duel!", 0.25, 1, 0.25)
        else
            ns:AddChips(paid)
            s.won = s.won + paid
            if d.stake > s.biggestWin then s.biggestWin = d.stake end
            SetStatus((how or (opp .. " rolled a 1!")) .. " You win " .. Fmt(paid) .. ".", 0.25, 1, 0.25)
        end
        ns:PlayGameSound(db, "win")
        Say("deathrollWin", { name = opp, amount = Fmt(d.stake) }, "You win the duel!")
    elseif loser == "me" then
        s.losses = s.losses + 1
        SetStatus((how or "You rolled a 1!") .. " " .. opp .. (party and " wins the duel." or (" takes the " .. Fmt(d.stake * 2) .. ".")), 1, 0.4, 0.4)
        ns:PlayGameSound(db, "lose")
        Say("deathrollLose", { name = opp, amount = Fmt(d.stake) }, "A 1. That's the duel.")
    else
        s.duels = s.duels - 1
        if party then
            s.partyDuels = s.partyDuels - 1
            SetStatus(how or "The duel is called off.", 0.85, 0.85, 0.85)
        else
            ns:AddChips(d.stake)
            s.wagered = s.wagered - d.stake
            SetStatus((how or "The duel is called off.") .. " Your " .. Fmt(d.stake) .. " is back.", 0.85, 0.85, 0.85)
        end
    end
    if ns.Dealer and d.kind == "party" then ns.Dealer:SetImage(Deathroll, nil) end
    db.lastLog = d.log
    db.lastRange = "1 - " .. Fmt(d.max)
    db.stake = ns:FitList(STAKES, db.stake)
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
-- The challenges (Games\ChallengeKit.lua): posting, taking, withdrawing.

local function PostChallenge()
    if S.duel or not ch:Post({ stake = db.stake, start = db.start }) then return end
    SetStatus("Challenge sent: for " .. Fmt(db.stake) .. ", from " .. Fmt(db.start) .. " (free). Waiting for someone to take it...")
    Refresh()
end

local function Withdraw(quiet) ch:Withdraw(quiet) end
local function Accept(offer) ch:Accept(offer) end

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

-- The duel's own messages (R a roll, F forfeit, C called off).
local function DuelMessage(sender, kind, f)
    local id = f[3]
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

-- (the group changed: a party duel with someone who left is off)
local GroupChanged

ch = ns.ChallengeKit.New({
    tag = GAME_TAG, id = "deathroll", state = S, busyText = "You're already in a duel.",
    fields = function(p) return { p.stake, p.start } end,
    read = function(f) return { stake = tonumber(f[4]) or 0, start = tonumber(f[5]) or 0 }, 2 end,
    begin = function(sender, p) StartDuel("party", p.stake, p.start, "me", sender, p.id) end,
    chosen = function(sender, id, offer)
        if not offer then
            Net:Send(Msg({ "C", id }))
            return false
        end
        StartDuel("party", offer.stake, offer.start, "them", sender, id)
        return true
    end,
    inGame = function() return S.duel ~= nil end,
    onMessage = DuelMessage,
    onGroup = function() GroupChanged() end,
    status = function(text) if ui.range then SetStatus(text) end end,
    refresh = function() if ui.range then Refresh() end end,
    shown = function() return ns.currentGame == "deathroll" end,
    enter = function() if db and db.mode ~= "party" then Deathroll.SetMode("party") end end,
})

GroupChanged = function()
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
ns:Every(0.1, function()
    if not db then return end
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
end)

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local MakeButton = ns.UI.Button

-- A "< amount >" picker (locked during a duel or an open challenge).
local function Picker(parent, list, key, word)
    return ns.UI.Stepper(parent, {
        list = list, width = 104,
        label = function(v) return word .. " |cffffffff" .. Fmt(v) .. "|r" end,
        get = function() return db[key] end,
        set = function(v) db[key] = v end,
        locked = function() return S.duel ~= nil or S.posted ~= nil end,
        onChange = function() Refresh() end,
    })
end

local function SetMode(mode)
    if S.duel or S.posted or db.mode == mode then return end
    db.mode = mode
    if mode == "party" then Net:Send(Msg({ "Q" })) end
    Refresh()
end

local function BuildOptions(panel)
    return ns:GameOptions(Deathroll, panel, {
        rules = "How it plays: both players put up the stake. The first roll is 1 to the starting number; "
            .. "each roll after that is 1 to the last roll. Whoever rolls a 1 loses, and the other takes both "
            .. "stakes. It's an even game: neither side has the edge.\n\n"
            .. "Vs the dealer: you roll first and the dealer answers.\n\n"
            .. "Party duel: free (your chips are never touched). Challenge the "
            .. "group, and the first player with CowCasino to accept is your opponent. The challenger rolls first. "
            .. "Party rolls are real /rolls everyone can see. Forfeit gives up the duel; if the other player goes "
            .. "quiet for a minute you can call it off instead. A reload calls a party duel off too.",
        onReset = function()
            db.stats = {}
            Fill(db.stats, DEFAULT_STATS)
            Refresh()
        end,
        db = function() return db end,
    })
end

function Deathroll:Build(panel)
    db = ns:SetupGame(panel, "deathroll", {
        defaults = { mode = "solo", stake = 100, start = 1000 },
        stats = DEFAULT_STATS,
        sounds = true,
        felt = { 0.18, 0.04, 0.04, 0.94 },
    })


    -- the intro screen: setting up a duel (Intro.lua)
    local intro = ns:AddIntro(Deathroll, panel, {
        felt = { 0.18, 0.04, 0.04, 0.94 },
        solo = "Vs the dealer", party = "Duel your group",
    })
    ui.intro = intro
    intro.onSolo = function()
        SetMode("solo")
        DuelDealer()
    end
    intro.onHost = function()
        SetMode("party")
        if S.posted then Withdraw() else PostChallenge() end
    end
    ui.onAccept = function(o)
        SetMode("party")
        Accept(o)
    end
    ui.pickers = {}
    for _, row in ipairs({ intro.soloRow, intro.partyRow }) do
        local stake = Picker(row, STAKES, "stake", "Stake")
        stake:SetPoint("LEFT", row, "LEFT", 6, 0)
        local start = Picker(row, STARTS, "start", "From")
        start:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        table.insert(ui.pickers, stake)
        table.insert(ui.pickers, start)
        ui.stake, ui.start = ui.stake or stake, ui.start or start
    end
    ui.stats = intro.stats

    -- the two of you at the top, facing each other across the range: your
    -- portrait on the left, theirs on the right (the dealer's picture in a
    -- duel with the dealer)
    local function Frame(point, x)
        local f = panel:CreateTexture(nil, "BORDER")
        f:SetWidth(PIC + 4); f:SetHeight(PIC + 4)
        f:SetPoint(point, panel, point, x, -8)
        f:SetTexture(0, 0, 0, 0.45)
        return f
    end
    local youBox, oppBox = Frame("TOPLEFT", 8), Frame("TOPRIGHT", -8)
    ui.youPic = ns:CreatePortrait(panel, PIC, PIC, FACE)
    ui.youPic:SetPoint("CENTER", youBox, "CENTER", 0, 0)
    ui.oppPic = ns:CreatePortrait(panel, PIC, PIC, -FACE)
    ui.oppPic.onCreature = function(up) ns.SetShown(ui.oppImage, not up) end
    ui.oppPic:SetPoint("CENTER", oppBox, "CENTER", 0, 0)
    ui.oppImage = panel:CreateTexture(nil, "ARTWORK")
    ui.oppImage:SetWidth(PIC); ui.oppImage:SetHeight(PIC)
    ui.oppImage:SetPoint("CENTER", oppBox, "CENTER", 0, 0)
    ui.oppImage:Hide()
    ui.youName = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ui.youName:SetPoint("TOP", youBox, "BOTTOM", 0, -3)
    ui.youName:SetWidth(PIC + 16)
    ui.oppName = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ui.oppName:SetPoint("TOP", oppBox, "BOTTOM", 0, -3)
    ui.oppName:SetWidth(PIC + 16)

    ui.range = ns:BigFont(panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 28)
    ui.range:SetPoint("TOP", panel, "TOP", 0, -16)
    ui.range:SetTextColor(1, 0.85, 0.1)
    ui.whose = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.whose:SetPoint("TOP", panel, "TOP", 0, -52)
    ui.whose:SetWidth(AREA_W - 2 * (PIC + 20))

    -- the rolls so far
    local LOG_Y = -104
    local logBg = panel:CreateTexture(nil, "BORDER")
    logBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, LOG_Y)
    logBg:SetWidth(AREA_W - 40); logBg:SetHeight(LOG_LINES * 14 + 8)
    logBg:SetTexture(0, 0, 0, 0.4)
    ui.log = {}
    for i = 1, LOG_LINES do
        local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("TOP", panel, "TOP", 0, LOG_Y - 4 - (i - 1) * 14)
        ui.log[i] = t
    end

    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", panel, "TOP", 0, LOG_Y - LOG_LINES * 14 - 18)
    ui.status:SetWidth(AREA_W - 8)

    -- the field's buttons: Roll (and Forfeit) in a duel; Play again and Setup after one
    ui.go = MakeButton(panel, "Roll", 170, function() if S.duel then Roll() end end, 28)
    ui.go:SetPoint("BOTTOM", panel, "BOTTOM", 0, 18)
    ui.forfeit = MakeButton(panel, "Forfeit", 72, Forfeit, 24)
    ui.forfeit:SetPoint("LEFT", ui.go, "RIGHT", 6, 0)
    ui.forfeit:Hide()
    ui.again = MakeButton(panel, "Again", 150, function()
        local over = S.over
        if over and over.kind == "party" then
            local state, offer = ch:RematchState(over.opp)
            if state == "accept" then
                Accept(offer)
            elseif state == "sent" then
                Withdraw()
            elseif state == "offer" and ch:Rematch(over.opp, { stake = over.stake, start = over.start }) then
                SetStatus("Rematch offered to " .. over.opp .. ": for " .. Fmt(over.stake) .. ", from " .. Fmt(over.start) .. ".")
            end
            Refresh()
            return
        end
        S.over = nil
        SetMode("solo")
        DuelDealer()
        Refresh()
    end, 26)
    ui.again:SetPoint("BOTTOM", panel, "BOTTOM", 0, 19)
    ui.again:Hide()

    ui.options = BuildOptions(panel)

    if db.partyDuel then
        -- a party duel cut off by a reload: call it off, both stakes go back
        local p = db.partyDuel
        db.partyDuel = nil
        Net:Send(Msg({ "C", p.id }))
        SetStatus("Your party duel with " .. tostring(p.opp) .. " was called off by the reload.")
    elseif db.duel then
        S.duel = db.duel
        S.duel.pending = nil
        SetStatus("Your duel with " .. DealerName() .. " is still on.")
    else
        Net:Send(Msg({ "Q" }))
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
end

function Deathroll:ChipsInPlay()
    local d = ns.db.deathroll
    -- only a duel against the dealer holds chips (party duels are free)
    return (S.duel ~= nil and S.duel.kind == "solo") or (d ~= nil and d.duel ~= nil)
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

Deathroll.defaultStats = DEFAULT_STATS     -- (ns:ResetStats)
function Deathroll:OnStatsReset(d)
    if ui.stats and db then Refresh() end
end

-- For the core's intro (Intro.lua): a duel on is "busy".
function Deathroll:IntroState() return S.duel ~= nil and "busy" or "idle" end

-- Exposed for tests.
Deathroll.S, Deathroll.ui, Deathroll.ParseRoll = S, ui, ParseRoll
Deathroll.SetMode = SetMode

ns:RegisterGame(Deathroll)

-- (the lobby hub's pop-ups and badges come with the challenges, above)
