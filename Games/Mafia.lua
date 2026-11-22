-- CowCasino: Mafia, the social deduction party game, for 5 to 30 players
-- (a raid). The rules are in Games\MafiaRules.lua; hosting and joining are
-- the room kit's (Games\RoomKit.lua).
--
-- The host's client deals the roles and runs the nights and days; the host
-- plays too. Talk happens in raid chat (or voice); the addon handles roles,
-- night actions, votes, deaths and who's won. Nothing is secret on the wire:
-- every message goes to the whole raid and each client shows only what its
-- player may see (your own role, your fellow Mafia, the Detective's answers).
-- Dead players see every role.
--
-- Players sit in seats (1..n, the roster's order at the deal; anyone joining
-- later watches until the next game). Messages (tag MF; the room kit's, and):
--   S;tid;phase;day;left;alive;shown;votes;winner;mafia;specials;dayTime;nightTime;secret;seats;shot;saved
--     phase w waiting, n night, d day, o over; alive "1"/"0" a seat; shown a
--     seat's role once it's out ("-" before); votes a seat's vote (see SeatChar,
--     "-" none, "x" voted when votes are secret)
--   K;tid;game;roles   the deal, one letter a seat
--   N;tid;day;seat     a night action (0: no one), to the host
--   V;tid;day;seat     a vote (0: nobody), to the host
--   C;tid;text;who     Mafia talk (a player's goes to the host, who passes it on)
--   P;tid;day;picks    the Mafia's picks so far (a seat char each), for the Mafia
--   I;tid;day;seat;m|t the Detective's answer
--   W;tid;text         a line for everyone's log

local ns = CowCasino.ns
local R = ns.MafiaRules

local TAG = "MF"
local MAX_PLAYERS = 30
local ROWS = 15
local DAY_TIMES = { 60, 90, 120, 180, 240, 300 }
local NIGHT_TIMES = { 20, 30, 45, 60, 90 }
local MAFIA_COUNTS = { "auto", 1, 2, 3, 4, 5, 6, 7, 8 }
local LOG_LINES = 5
local SEATS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local ART = "Interface\\AddOns\\CowCasino\\Art\\"

local DEFAULT_STATS = { games = 0, wins = 0, mafia = 0, town = 0 }
local DEFAULT_SET = { mafia = "auto", specials = "GDHVBY", day = 120, night = 30, secret = false }

local Game = {
    id = "mafia",
    name = "Mafia",
    description = "Secret roles, night kills and day votes, for 5 to 30 players.\n|cff66ccffParty game|r",
    icon = ART .. "MafiaIcon",   -- painted (dev/art-src/make_game_icons.py)
    wide = true,
}

local db
local ui = {}
-- The game as this client knows it.
local G = { phase = "w", day = 0, n = 0, alive = {}, shown = {}, votes = {}, names = {}, log = {}, picks = {} }
local HS = {}   -- the host's own: roles, picks, acts, acted, votes, lastSave, shotUsed, game
local room
local Refresh

local function Me() return ns.Net:Me() end

local function SeatChar(s) return s == 0 and "0" or string.sub(SEATS, s, s) end
local function CharSeat(c)
    if c == "0" then return 0 end
    local i = string.find(SEATS, c or "", 1, true)
    return i
end

local function Name(seat) return G.names[seat] or ("Seat " .. seat) end
local function MySeat()
    local p = room:Player(Me())
    return p and p.seat or 0
end
local function MyRole() return G.roles and R.RoleAt(G.roles, MySeat()) or nil end
local function Alive(seat) return G.alive[seat] == true end

local function Log(text)
    table.insert(G.log, text)
    while ns.getn(G.log) > 60 do table.remove(G.log, 1) end
end

local function Clean(text) return ns.Net.Clean(text, 120) end

---------------------------------------------------------------------------
-- What this client may see
---------------------------------------------------------------------------
-- A seat's role, if this player may know it: their own, the Mafia's to the
-- Mafia, everyone's once it's revealed, to the dead, or when the game's over.
local function KnownRole(seat)
    if not G.roles then return nil end
    local role = R.RoleAt(G.roles, seat)
    if G.shown[seat] then return G.shown[seat] end
    local me = MySeat()
    if G.phase == "o" then return role end
    if me == 0 then return nil end
    if seat == me or not Alive(me) then return role end
    if R.IsMafia(MyRole()) and R.IsMafia(role) then return role end
    return nil
end

local function RoleText(letter)
    local r = R.Role(letter)
    if not r then return "?" end
    return "|cff" .. r.color .. r.name .. "|r"
end

---------------------------------------------------------------------------
-- The host
---------------------------------------------------------------------------
local function Encode(t, n, default)
    local out = {}
    for s = 1, n do table.insert(out, t[s] or default) end
    return table.concat(out)
end

local function State()
    local left = G.deadline and math.max(0, math.floor(G.deadline - GetTime() + 0.5)) or 0
    local alive, shown, votes = {}, {}, {}
    for s = 1, G.n do
        alive[s] = Alive(s) and "1" or "0"
        shown[s] = G.shown[s] or "-"
        local v = HS.votes and HS.votes[s]
        if v == nil then votes[s] = "-"
        elseif G.set.secret and G.phase == "d" then votes[s] = "x"
        else votes[s] = SeatChar(v) end
    end
    return { G.phase, G.day, left, table.concat(alive), table.concat(shown), table.concat(votes), G.winner or "",
        G.set.mafia, G.set.specials, G.set.day, G.set.night, G.set.secret and "1" or "", G.n,
        HS.shotUsed and "1" or "", HS.lastSave and SeatChar(HS.lastSave) or "" }
end

local function SendDeal()
    if HS.roles then room:Send({ "K", room.tid, HS.game or 0, HS.roles }, TAG .. "-K") end
end

local function Say(text)
    Log(text)
    room:Send({ "W", room.tid, text })
end

local function Push()
    -- the host's own screen shows votes as everyone else's does
    G.votes = {}
    for seat, v in pairs(HS.votes or {}) do G.votes[seat] = (G.set.secret and G.phase == "d") and "x" or v end
    G.shotUsed, G.lastSave = HS.shotUsed, HS.lastSave
    room:SendState()
    Refresh()
end

local function AliveSet()
    local t = {}
    for s = 1, G.n do if Alive(s) then t[s] = true end end
    return t
end

local function Reveal(seat)
    G.alive[seat] = false
    G.shown[seat] = R.RoleAt(HS.roles, seat)
end

local function GameOver(winner)
    G.phase, G.winner, G.deadline = "o", winner, nil
    for s = 1, G.n do G.shown[s] = R.RoleAt(HS.roles, s) end
    local text = (winner == "town" and "|cff66ccffThe Town wins!|r All the Mafia are gone.")
        or (winner == "mafia" and "|cffff5050The Mafia win!|r They match the rest of the town.")
        or "|cffff66ffThe Jester wins!|r The town lynched them."
    Say(text)
    room:Broadcast()
    room:Offer()
    Game.CountGame()
    Refresh()
end

local function CheckWin()
    local w = R.Winner(HS.roles, AliveSet())
    if w then GameOver(w) return true end
    return false
end

local function StartNight()
    G.phase = "n"
    G.day = G.day + 1
    G.deadline = GetTime() + (G.set.night or 30)
    HS.picks, HS.acts, HS.acted, HS.votes = {}, {}, {}, {}
    G.picks = {}
    Say("|cff8888ffNight " .. G.day .. " falls.|r")
    Push()
end

local function StartDay()
    G.phase = "d"
    G.deadline = GetTime() + (G.set.day or 120)
    HS.votes = {}
    Push()
end

local function Act(role) local r = R.Role(role) return r and r.act end

-- Everyone with something to do tonight has done it?
local function NightDone()
    for s = 1, G.n do
        local act = Act(R.RoleAt(HS.roles, s))
        if Alive(s) and act and not (act == "shoot" and HS.shotUsed) and not HS.acted[s] then return false end
    end
    return true
end

local function EndNight()
    local a = HS.acts
    a.kill = R.MafiaTarget(HS.picks, HS.roles)
    if a.shoot and a.shoot > 0 then HS.shotUsed = true end
    HS.lastSave = a.save
    local deaths, check = R.Night(HS.roles, AliveSet(), a)
    if check then
        for s = 1, G.n do
            if R.RoleAt(HS.roles, s) == "D" and Alive(s) then
                room:Send({ "I", room.tid, G.day, a.check, check })
                Game.Detective(G.day, a.check, check)
            end
        end
    end
    if ns.getn(deaths) == 0 then
        Say("|cffffd100Morning " .. G.day .. ":|r nobody died in the night.")
    end
    for _, d in ipairs(deaths) do
        Reveal(d.seat)
        local how = (d.how == "guard" and " died protecting someone.") or (d.how == "shot" and " was shot in the night.")
            or " was killed in the night."
        Say("|cffffd100Morning " .. G.day .. ":|r " .. Name(d.seat) .. how .. " They were the " .. RoleText(G.shown[d.seat]) .. ".")
    end
    if not CheckWin() then StartDay() end
end

local function EndDay(target)
    if target == nil then target = R.Lynch(HS.votes, HS.roles, AliveSet()) end
    if target and target > 0 then
        Reveal(target)
        Say("|cffff8800The town lynches " .. Name(target) .. ".|r They were the " .. RoleText(G.shown[target]) .. ".")
        if G.shown[target] == "J" then
            GameOver("jester")
            return
        end
    else
        Say("The town can't agree. Nobody is lynched.")
    end
    if not CheckWin() then StartNight() end
end

local function HostStart()
    if not room:IsHost() or (G.phase ~= "w" and G.phase ~= "o") then return end
    local n = ns.getn(room.players)
    if n < R.MIN_PLAYERS then return end
    G.n, G.names, G.alive, G.shown, G.log, G.winner, G.day = n, {}, {}, {}, {}, nil, 0
    for i, p in ipairs(room.players) do
        p.seat = i
        G.names[i] = p.name
        G.alive[i] = true
    end
    HS.roles = R.Deal(n, G.set)
    HS.game = (HS.game or 0) + 1
    HS.shotUsed, HS.lastSave = nil, nil
    G.roles = HS.roles
    ns:Sound("IG_MAINMENU_OPTION")
    Say("Roles are dealt: " .. R.Describe(R.Setup(n, G.set)) .. ".")
    room:Broadcast()
    SendDeal()
    StartNight()
end

-- A night action from a seat (target 0: no one).
local function HostAction(seat, target)
    if G.phase ~= "n" or not Alive(seat) then return end
    local role = R.RoleAt(HS.roles, seat)
    local act = Act(role)
    if not act then return end
    if target ~= 0 and not Alive(target) then return end
    if act == "kill" then
        if target ~= 0 and R.IsMafia(R.RoleAt(HS.roles, target)) then return end
        HS.picks[seat] = target
        G.picks[seat] = target
        local t = {}
        for s = 1, G.n do t[s] = HS.picks[s] and SeatChar(HS.picks[s]) or "-" end
        room:Send({ "P", room.tid, G.day, table.concat(t) }, TAG .. "-P")
    elseif act == "save" then
        if target ~= 0 and target == HS.lastSave then return end
        HS.acts.save = target ~= 0 and target or nil
    elseif act == "check" then
        if target == seat then return end
        HS.acts.check = target ~= 0 and target or nil
    elseif act == "guard" then
        if target == seat then return end
        HS.acts.guard = target ~= 0 and target or nil
    elseif act == "shoot" then
        if HS.shotUsed or target == seat then return end
        HS.acts.shoot = target ~= 0 and target or nil
    end
    HS.acted[seat] = true
    if NightDone() then EndNight() else Refresh() end
end

local function HostVote(seat, target)
    if G.phase ~= "d" or not Alive(seat) or (target ~= 0 and not Alive(target)) then return end
    HS.votes[seat] = target
    local _, _, majority = R.Tally(HS.votes, HS.roles, AliveSet())
    if majority then
        EndDay(majority)
        return
    end
    local all = true
    for s = 1, G.n do if Alive(s) and HS.votes[s] == nil then all = false end end
    if all then EndDay(nil) else Push() end
end

local function HostTick(now)
    if G.phase == "n" and G.deadline and now >= G.deadline then EndNight()
    elseif G.phase == "d" and G.deadline and now >= G.deadline then EndDay(nil) end
end

---------------------------------------------------------------------------
-- Everyone
---------------------------------------------------------------------------
function Game.Detective(day, seat, answer)
    if MyRole() ~= "D" then return end
    Log("|cff66ccffYour check: " .. Name(seat) .. (answer == "m" and " |cffff5050is Mafia!|r" or " is not Mafia.") .. "|r")
    Refresh()
end

function Game.CountGame()
    local s = db.stats
    local role = MyRole()
    if MySeat() == 0 or not role then return end
    s.games = s.games + 1
    local team = R.Team(role)
    if team == G.winner then
        s.wins = s.wins + 1
        if team == "mafia" then s.mafia = s.mafia + 1 elseif team == "town" then s.town = s.town + 1 end
        ns:Sound("UI_EPICLOOT_TOAST")
    end
end

local function ClientState(f)
    local was = G.phase
    G.phase, G.day = f[4] or "w", tonumber(f[5] or "") or 0
    local left = tonumber(f[6] or "") or 0
    G.deadline = (G.phase == "n" or G.phase == "d") and (GetTime() + left) or nil
    G.n = tonumber(f[16] or "") or 0
    local alive, shown, votes = f[7] or "", f[8] or "", f[9] or ""
    G.alive, G.shown, G.votes = {}, {}, {}
    for s = 1, G.n do
        G.alive[s] = string.sub(alive, s, s) == "1"
        local r = string.sub(shown, s, s)
        if r ~= "-" and r ~= "" then G.shown[s] = r end
        local v = string.sub(votes, s, s)
        if v == "x" then G.votes[s] = "x" elseif v ~= "-" and v ~= "" then G.votes[s] = CharSeat(v) end
    end
    G.winner = (f[10] ~= "") and f[10] or nil
    G.set = { mafia = tonumber(f[11] or "") or "auto", specials = f[12] or "", day = tonumber(f[13] or "") or 120,
        night = tonumber(f[14] or "") or 30, secret = f[15] == "1" }
    G.shotUsed = f[17] == "1"
    G.lastSave = (f[18] and f[18] ~= "") and CharSeat(f[18]) or nil
    if G.phase ~= was then
        G.choice = nil
        if G.phase == "n" then G.picks = {} end
        if G.phase == "o" and not room.fresh then Game.CountGame() end
        if G.phase == "n" or G.phase == "d" then ns:Sound("RAID_WARNING") end
    end
    -- keep names for seats (someone who left keeps their name on the list)
    for _, p in ipairs(room.players) do if p.seat and p.seat > 0 then G.names[p.seat] = p.name end end
    Refresh()
end

-- Clicking a seat: your vote by day, your action by night.
local function Choose(seat)
    local me = MySeat()
    if me == 0 or not Alive(me) then return end
    if G.phase == "d" then
        if seat ~= 0 and not Alive(seat) then return end
        G.choice = seat
        if room:IsHost() then HostVote(me, seat) else room:Send({ "V", room.tid, G.day, seat }) end
    elseif G.phase == "n" then
        local act = Act(MyRole())
        if not act or (seat ~= 0 and not Alive(seat)) then return end
        G.choice = seat
        if R.IsMafia(MyRole()) then G.picks[me] = seat end
        if room:IsHost() then HostAction(me, seat) else room:Send({ "N", room.tid, G.day, seat }) end
    end
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

local function MafiaTalk(text)
    text = Clean(text)
    if text == "" or not R.IsMafia(MyRole()) or not Alive(MySeat()) then return end
    room:Send({ "C", room.tid, text, Me() })
    Log("|cffff5050[Mafia] You:|r " .. text)
    Refresh()
end

local function OnGameMessage(sender, f)
    local kind = f[2]
    if kind == "K" then
        G.roles = f[5]
        for _, p in ipairs(room.players) do if p.seat and p.seat > 0 then G.names[p.seat] = p.name end end
        Refresh()
    elseif kind == "C" then
        -- Mafia talk goes through the host (players only hear the host)
        local who = (f[5] and f[5] ~= "") and f[5] or sender
        if room:IsHost() and sender ~= Me() then room:Send({ "C", room.tid, Clean(f[4]), sender }) end
        if who ~= Me() and (R.IsMafia(MyRole()) or (MySeat() > 0 and not Alive(MySeat()))) then
            Log("|cffff5050[Mafia] " .. who .. ":|r " .. (f[4] or ""))
            Refresh()
        end
    elseif kind == "W" then
        Log(f[4] or "")
        Refresh()
    elseif kind == "P" and tonumber(f[4] or "") == G.day then
        G.picks = {}
        local s = f[5] or ""
        for i = 1, string.len(s) do
            local c = string.sub(s, i, i)
            if c ~= "-" then G.picks[i] = CharSeat(c) end
        end
        Refresh()
    elseif kind == "I" and tonumber(f[4] or "") == G.day then
        Game.Detective(G.day, tonumber(f[5] or "") or 0, f[6])
    end
end

room = ns.RoomKit.New({
    tag = TAG, id = "mafia", max = MAX_PLAYERS, fields = { "seat" },
    phase = function() return (G.phase == "w" or G.phase == "o") and G.phase or "p" end,
    state = State,
    onState = ClientState,
    onHost = function()
        G.set = db.set
        G.phase, G.day, G.n, G.roles, G.winner, G.deadline = "w", 0, 0, nil, nil, nil
        G.log, G.alive, G.shown, G.votes, G.names, G.picks = {}, {}, {}, {}, {}, {}
        HS.roles = nil
    end,
    onJoin = function(name, p)
        p.seat = 0
        if G.phase ~= "w" and G.phase ~= "o" then Say(name .. " is watching (they'll play next game).") end
        SendDeal()
    end,
    onDrop = function(name)
        for s = 1, G.n do
            if G.names[s] == name and Alive(s) and (G.phase == "n" or G.phase == "d") then
                Reveal(s)
                Say(name .. " left the game. They were the " .. RoleText(G.shown[s]) .. ".")
                if not CheckWin() then
                    if G.phase == "n" and NightDone() then EndNight() end
                end
            end
        end
    end,
    onHostMessage = function(sender, f)
        local p = room:Player(sender)
        local seat = p and p.seat or 0
        if f[2] == "C" then
            OnGameMessage(sender, f)
            return
        end
        if seat == 0 or tonumber(f[4] or "") ~= G.day then return end
        local target = tonumber(f[5] or "")
        if not target then return end
        if f[2] == "N" then HostAction(seat, target) elseif f[2] == "V" then HostVote(seat, target) end
    end,
    onClientMessage = function(f) OnGameMessage(room.host, f) end,
    onLobby = function()
        G.phase, G.log, G.roles, G.n = "w", {}, nil, 0
    end,
    refresh = function() Refresh() end,
})

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function Clock()
    if not G.deadline then return "" end
    local left = math.max(0, math.floor(G.deadline - GetTime() + 0.5))
    local text = string.format("%d:%02d", math.floor(left / 60), ns.Mod(left, 60))
    if left <= 10 then return "|cffff5050" .. text .. "|r" end
    return text
end

local PROMPTS = {
    kill = "Pick someone for the Mafia to kill.",
    save = "Pick someone to protect tonight.",
    check = "Pick someone to check.",
    guard = "Pick someone to guard.",
    shoot = "Pick someone to shoot, or no one.",
}

local function Prompt()
    local me = MySeat()
    if G.phase == "o" then
        return (G.winner == "town" and "|cff66ccffThe Town wins!|r") or (G.winner == "mafia" and "|cffff5050The Mafia win!|r")
            or "|cffff66ffThe Jester wins!|r"
    end
    if me == 0 then return "You're watching this game; you'll play the next one." end
    if not Alive(me) then return "You're dead. You can see every role now; please don't give anything away." end
    if G.phase == "n" then
        local act = Act(MyRole())
        if act == "shoot" and G.shotUsed then act = nil end
        if not act then return "Night falls. Wait for morning." end
        if G.choice ~= nil then return "You chose " .. (G.choice == 0 and "no one" or Name(G.choice)) .. ". (Click to change.)" end
        return PROMPTS[act]
    elseif G.phase == "d" then
        local total, voted = 0, 0
        for s = 1, G.n do
            if Alive(s) then
                total = total + 1
                if G.votes[s] ~= nil then voted = voted + 1 end
            end
        end
        local head = (G.choice ~= nil) and ("You voted for " .. (G.choice == 0 and "nobody" or Name(G.choice)) .. ". ") or "Vote: who's Mafia? "
        return head .. voted .. " of " .. total .. " have voted; a majority ends the day."
    end
    return ""
end

-- Can I click this seat now?
local function Clickable(seat)
    local me = MySeat()
    if me == 0 or not Alive(me) or not Alive(seat) then return false end
    if G.phase == "d" then return true end
    if G.phase ~= "n" then return false end
    local role = MyRole()
    local act = Act(role)
    if not act then return false end
    if act == "shoot" and G.shotUsed then return false end
    if act == "kill" then return not R.IsMafia(KnownRole(seat)) end
    if act == "save" then return seat ~= G.lastSave end
    return seat ~= me
end

local function RefreshSeats()
    local counts = {}
    if G.phase == "d" and not G.set.secret then
        for voter, t in pairs(G.votes) do
            if type(t) == "number" and Alive(voter) then
                counts[t] = (counts[t] or 0) + 1   -- (a Mayor's second vote stays secret)
            end
        end
    end
    local mafiaView = R.IsMafia(MyRole())
    for s = 1, MAX_PLAYERS do
        local row = ui.seats[s]
        if s > G.n then
            row:Hide()
        else
            row:Show()
            local known = KnownRole(s)
            local name = Name(s) .. (G.names[s] == Me() and " (you)" or "")
            local right = ""
            if not Alive(s) then
                name = "|cff777777" .. name .. "|r"
                right = "|cff777777dead|r " .. (known and RoleText(known) or "")
            else
                if known then right = RoleText(known) end
                if G.phase == "d" then
                    local v = G.votes[s]
                    if v == "x" then right = right .. " |cffaaaaaa(voted)|r"
                    elseif v ~= nil then right = right .. " |cffaaaaaa> " .. (v == 0 and "nobody" or Name(v)) .. "|r" end
                    if counts[s] then name = name .. " |cffff8800(" .. counts[s] .. ")|r" end
                elseif G.phase == "n" and mafiaView and G.picks[s] ~= nil then
                    right = right .. " |cffff5050> " .. (G.picks[s] == 0 and "no one" or Name(G.picks[s])) .. "|r"
                end
            end
            row.name:SetText(name)
            row.info:SetText(right)
            ns.SetShown(row.mark, G.choice == s and (G.phase == "n" or G.phase == "d"))
            ns.SetEnabled(row, Clickable(s))
        end
    end
end

local function RefreshWait()
    local host = room:IsHost()
    for _, c in ipairs(ui.checks) do
        c:SetChecked(string.find(G.set.specials or "", c.key, 1, true) ~= nil)
        ns.SetEnabled(c, host)
    end
    ui.mafiaStep:Refresh(); ui.dayStep:Refresh(); ui.nightStep:Refresh(); ui.secretStep:Refresh()
    local n = ns.getn(room.players)
    ns.SetShown(ui.start, host)
    ns.SetEnabled(ui.start, host and n >= R.MIN_PLAYERS)
    local setup = n >= R.MIN_PLAYERS and ("With " .. n .. " players: " .. R.Describe(R.Setup(n, G.set)) .. ".")
        or (n .. " player" .. (n == 1 and "" or "s") .. " so far; " .. R.MIN_PLAYERS .. " needed.")
    ui.preview:SetText(setup)
    ui.startNote:SetText(host and "Everyone needs to be in the raid with CowCasino. Talk in raid chat or voice."
        or ("|cffffffffWaiting for " .. (room.host or "the host") .. " to start.|r"))
end

local function RefreshTable()
    local waiting = G.phase == "w"
    ns.SetShown(ui.wait, waiting)
    ns.SetShown(ui.play, not waiting)
    local title = (G.phase == "n" and ("|cff8888ffNight " .. G.day .. "|r")) or (G.phase == "d" and ("|cffffd100Day " .. G.day .. "|r"))
        or (G.phase == "o" and "Game over") or "Waiting to start"
    ui.title:SetText(title)
    ui.clock:SetText(Clock())
    local role = MyRole()
    if waiting then
        ui.role:SetText("")
        RefreshWait()
    else
        if MySeat() > 0 and role then
            local r = R.Role(role)
            local mates = ""
            if R.IsMafia(role) then
                local t = {}
                for s = 1, G.n do
                    if s ~= MySeat() and R.IsMafia(R.RoleAt(G.roles, s)) then table.insert(t, Name(s)) end
                end
                mates = t[1] and (" Your fellow Mafia: " .. table.concat(t, ", ") .. ".") or ""
            end
            ui.role:SetText("You are the " .. RoleText(role) .. ". " .. r.desc .. mates)
        else
            ui.role:SetText(MySeat() == 0 and "You're watching this game." or "")
        end
        RefreshSeats()
        ui.prompt:SetText(Prompt())
        local me = MySeat()
        local canSkip = me > 0 and Alive(me) and ((G.phase == "d") or (G.phase == "n" and Act(role) ~= nil
            and not (Act(role) == "shoot" and G.shotUsed)))
        ns.SetShown(ui.skip, canSkip)
        ui.skip:SetText(G.phase == "d" and "Vote nobody" or "No one")
        local n = ns.getn(G.log)
        for i = 1, LOG_LINES do ui.log[i]:SetText(G.log[n - LOG_LINES + i] or "") end
        local talk = me > 0 and Alive(me) and R.IsMafia(role) and G.phase ~= "o"
        ns.SetShown(ui.talk, talk)
    end
    ui.leave:SetText(room:IsHost() and "Close game" or "Leave game")
    ns.SetShown(ui.again, room:IsHost() and G.phase == "o")
    if room:IsHost() and G.phase == "o" then ns.SetEnabled(ui.again, ns.getn(room.players) >= R.MIN_PLAYERS) end
end

Refresh = function()
    if not ui.table then return end
    local inRoom = room:InRoom()
    ns:UpdateIntro(Game)
    ns.SetShown(ui.table, inRoom)
    if inRoom then RefreshTable() else room:RefreshLobby() end
end

-- For the core's intro (Intro.lua): in a room it's "busy"; otherwise the
-- intro (the lobby) is all there is.
function Game:IntroState() return room:InRoom() and "busy" or "intro" end
Game.Refresh = function() Refresh() end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Text(parent, font, x, y, width, justify)
    local t = parent:CreateFontString(nil, "OVERLAY", font)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then t:SetWidth(width) end
    t:SetJustifyH(justify or "LEFT")
    return t
end

local function Changed()
    ns:Sound("IG_MAINMENU_OPTION")
    if room:IsHost() then room:SendState() end
    Refresh()
end

local function BuildWait(t)
    local w = ns.CreateFrame("Frame", nil, t)
    w:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -30)
    w:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 34)
    ui.wait = w
    Text(w, "GameFontNormal", 10, -2):SetText("Mafia")
    ui.mafiaStep = ns.UI.Stepper(w, {
        list = MAFIA_COUNTS, width = 90,
        label = function(v) return "|cffffffff" .. (v == "auto" and "Auto (1 in 4)" or v) .. "|r" end,
        get = function() return G.set.mafia end,
        set = function(v) G.set.mafia = v end,
        onChange = Changed,
        locked = function() return not room:IsHost() end,
    })
    ui.mafiaStep:SetPoint("TOPLEFT", w, "TOPLEFT", 150, 2)
    Text(w, "GameFontNormal", 10, -28):SetText("Special roles (one of each)")
    ui.checks = {}
    for i, k in ipairs(R.SPECIALS) do
        local key = k
        local c = ns.CreateFrame("CheckButton", ns:NewName(), w, "UICheckButtonTemplate")
        c:SetWidth(22); c:SetHeight(22)
        local x, y = 8 + ns.Mod(i - 1, 3) * 122, -44 - math.floor((i - 1) / 3) * 22
        c:SetPoint("TOPLEFT", w, "TOPLEFT", x, y)
        c.key = key
        c:SetScript("OnClick", function()
            local s = G.set.specials or ""
            local at = string.find(s, key, 1, true)
            if at then s = string.sub(s, 1, at - 1) .. string.sub(s, at + 1) else s = s .. key end
            G.set.specials = s
            Changed()
        end)
        Text(w, "GameFontHighlightSmall", x + 24, y - 5):SetText(R.ROLES[k].name)
        table.insert(ui.checks, c)
    end
    local function Row(y, label, list, key, fmt)
        Text(w, "GameFontHighlightSmall", 10, y - 6):SetText(label)
        local st = ns.UI.Stepper(w, {
            list = list, width = 90,
            label = fmt,
            get = function() return G.set[key] end,
            set = function(v) G.set[key] = v end,
            onChange = Changed,
            locked = function() return not room:IsHost() end,
        })
        st:SetPoint("TOPLEFT", w, "TOPLEFT", 150, y)
        return st
    end
    local function Secs(v) return "|cffffffff" .. (v >= 60 and (math.floor(v / 60) .. ":" .. string.format("%02d", ns.Mod(v, 60))) or (v .. " sec")) .. "|r" end
    ui.dayStep = Row(-118, "Day length", DAY_TIMES, "day", Secs)
    ui.nightStep = Row(-144, "Night length", NIGHT_TIMES, "night", Secs)
    ui.secretStep = Row(-170, "Votes", { false, true }, "secret", function(v) return "|cffffffff" .. (v and "Secret" or "Public") .. "|r" end)
    ui.preview = Text(w, "GameFontHighlight", 10, -202, 360)
    ui.start = ns.UI.Button(w, "Deal the roles", 150, function() HostStart() end, 26)
    ui.start:SetPoint("TOP", w, "TOP", 0, -248)
    ui.startNote = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.startNote:SetPoint("TOP", ui.start, "BOTTOM", 0, -6)
    ui.startNote:SetWidth(350)
end

local function BuildSeat(parent, s)
    local col, row = math.floor((s - 1) / ROWS), ns.Mod(s - 1, ROWS)
    local b = ns.CreateFrame("Button", nil, parent)
    b:SetWidth(184); b:SetHeight(13)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 4 + col * 188, -row * 13)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetTexture(1, 1, 1, 0.12)
    local mark = b:CreateTexture(nil, "BACKGROUND")
    mark:SetAllPoints(b)
    mark:SetTexture(1, 0.82, 0, 0.25)
    b.mark = mark
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("LEFT", b, "LEFT", 2, 0)
    b.name:SetWidth(92)
    b.name:SetJustifyH("LEFT")
    b.info = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.info:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    b.info:SetWidth(90)
    b.info:SetJustifyH("RIGHT")
    b:SetScript("OnClick", function() Choose(s) end)
    return b
end

local function BuildPlay(t)
    local p = ns.CreateFrame("Frame", nil, t)
    p:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -26)
    p:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 34)
    ui.play = p
    ui.role = Text(p, "GameFontHighlightSmall", 6, 0, 368)
    local grid = ns.CreateFrame("Frame", nil, p)
    grid:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -30)
    grid:SetWidth(380); grid:SetHeight(ROWS * 13)
    ui.seats = {}
    for s = 1, MAX_PLAYERS do ui.seats[s] = BuildSeat(grid, s) end
    ui.prompt = Text(p, "GameFontNormal", 6, -232, 268)
    ui.skip = ns.UI.Button(p, "No one", 96, function() Choose(0) end, 20)
    ui.skip:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -228)
    ui.log = {}
    for i = 1, LOG_LINES do ui.log[i] = Text(p, "GameFontHighlightSmall", 6, -254 - (i - 1) * 12, 368) end
    local box = ns.UI.EditBox(p, { width = 240, height = 20, maxLetters = 120,
        bg = { 0.25, 0, 0, 0.85 }, edge = { 0.7, 0.2, 0.2, 1 },
        hint = "Talk to the Mafia (only they see it)",
        onEnter = function(b)
            MafiaTalk(b:GetText())
            b:SetText("")
        end })
    box:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -318)
    ui.talk = box
end

local function BuildTable(panel)
    local t = ns.CreateFrame("Frame", nil, panel)
    t:SetAllPoints(panel)
    ui.table = t
    ui.title = ns:BigFont(t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 16)
    ui.title:SetPoint("TOPLEFT", t, "TOPLEFT", 6, -6)
    ui.clock = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.clock:SetPoint("TOPRIGHT", t, "TOPRIGHT", -6, -6)
    BuildPlay(t)
    BuildWait(t)
    ui.leave = ns.UI.Button(t, "Leave game", 110, function() room:Exit() end, 24)
    ui.leave:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -4, 6)
    ui.again = ns.UI.Button(t, "Deal again", 110, function() HostStart() end, 24)
    ui.again:SetPoint("RIGHT", ui.leave, "LEFT", -8, 0)
end

local RULES = "Some players are secretly the Mafia; everyone else is the Town. Nights: the Mafia pick someone to kill, "
    .. "and the special roles act in secret. Days: everyone talks (in raid chat or voice) and votes; a majority lynches "
    .. "at once, otherwise the most votes when time's up (a tie lynches nobody). Dead players' roles are shown.\n\n"
    .. "The Town wins when the Mafia are gone; the Mafia win when they're as many as everyone else.\n\n"
    .. "Godfather: Mafia, but looks innocent to the Detective. Detective: checks one player a night. Doctor: protects "
    .. "one player a night (not the same twice running). Vigilante: one shot a game. Bodyguard: dies in place of the "
    .. "player they guard. Mayor: their vote counts twice. Jester: wins if lynched.\n\n"
    .. "Everyone needs CowCasino and the same raid. The host plays too. Free: no chips."

function Game:Build(panel)
    db = ns:SetupGame(panel, "mafia", { stats = DEFAULT_STATS, felt = { 0.06, 0.05, 0.06, 1 } })
    db.set = db.set or {}
    ns.UI.Fill(db.set, DEFAULT_SET)
    G.set = db.set
    self.panel = panel
    room:Restore(db)
    room:BuildLobby(panel, {
        game = Game, felt = { 0.06, 0.05, 0.06, 1 },
        info = "The Mafia kill by night; everyone votes by day. 5 to 30 players, free.",
        alone = "Join a raid (or party) to play. Everyone needs CowCasino.",
        stats = function()
            local s = db.stats
            return string.format("Games %d   Wins %d (as Town %d, as Mafia %d)", s.games, s.wins, s.town, s.mafia)
        end,
    })
    BuildTable(panel)
    ns:GameOptions(self, panel, { rules = RULES })
    Refresh()
end

function Game:OnShow()
    room:Ask()
    Refresh()
end

function Game:IsSeated() return room:InRoom() end
function Game:ChatTable() return room:ChatTable() end

function Game:ResetStats()
    local d = ns.db.mafia
    if not d then return end
    d.stats = {}
    ns.UI.Fill(d.stats, DEFAULT_STATS)
    if ui.table then Refresh() end
end

local ticker = ns.CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function()
    acc = acc + (arg1 or 0)
    if acc < 0.25 then return end
    acc = 0
    local now = GetTime()
    room:Tick(now)
    if room:IsHost() then
        HostTick(now)
        -- the deal again with each heartbeat, for anyone who missed it
        if (G.phase == "n" or G.phase == "d") and now >= (HS.nextDeal or 0) then
            HS.nextDeal = now + 8
            SendDeal()
        end
    end
    if ui.clock and ui.table and ui.table:IsShown() then ui.clock:SetText(Clock()) end
end)

Game.G, Game.HS, Game.ui, Game.room = G, HS, ui, room
ns.Mafia = Game
ns:RegisterGame(Game)
room:RegisterLobby("mafia")
