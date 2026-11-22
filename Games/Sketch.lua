-- CowCasino: Sketch & Guess, a party drawing game (built on the drawing kit,
-- Games\SketchKit.lua, and the word packs, Games\SketchWords.lua).
--
-- One player hosts: their client keeps the players and scores, picks each
-- word and the artist, runs the clock and checks the guesses. Everyone takes
-- a turn drawing, round robin (nobody draws twice before everyone has drawn
-- once), for as many turns each as the host picked. The artist sees the word
-- and draws it; the others race to type it in. The first right guess ends
-- the turn: 2 points to the guesser, 1 to the artist. Letters of the word
-- show as hints as the clock runs down. Free to play: no chips move.
--
-- The host picks the words: any of the built-in packs, their own list, or
-- both. A host who typed their own words knows them, so they draw in turn
-- but don't guess (and the game needs three players).
-- There's also Practice: a canvas to doodle on alone (and check how lines
-- look on this client).
--
-- Messages (tag SK, after it): Q (who's hosting?), O;tid;players;phase;ver
-- (a game you can join), J;tid;ver (join), F;tid;name;why (can't join),
-- L;tid (leaving), X;tid (game closed), R;tid;roster, S;tid;state..., K;tid;
-- turn;word (the word, lightly disguised, for the artist), G;tid;turn;guess
-- (to the host), W;tid;turn;name;text;how (a guess, as the host saw it:
-- x wrong, c close, y right) and the drawing kit's D/E/C/N.

local ns = CowCasino.ns
local Net = ns.Net
local Kit = ns.SketchKit
local Words = ns.SketchWords

local TAG          = "SK"
local MAX_PLAYERS  = 10
local TIMES        = { 30, 45, 60, 80, 100, 120, 150, 180 }
local EACH         = { 1, 2, 3, 4 }
local REVEAL_TIME  = 5       -- seconds the word stays up after a turn
local LOG_LINES    = 10
local ROWS         = 4       -- games listed in the lobby
local GUESS_POINTS, ART_POINTS = 2, 1
local ART = "Interface\\AddOns\\CowCasino\\Art\\"

local DEFAULT_STATS = { games = 0, wins = 0, guessed = 0, drawn = 0, points = 0 }
local DEFAULT_SETTINGS = { time = 80, each = 2, packs = "ecl", custom = false }

local Game = {
    id = "sketch",
    name = "Sketch & Guess",
    description = "Draw the secret word while your group races to guess it.\n|cff66ccffParty game|r",
    icon = ART .. "SketchIcon",   -- painted (dev/art-src/make_game_icons.py)
    wide = true,
}

local db
local ui = {}
local S = {
    -- the room (players, host, joining, offers) is RoomKit's (room, below);
    -- S.mode, S.players and S.host mirror it for the display (Sync)
    mode = "lobby",     -- lobby | host | client | practice
    practice = nil,     -- doodling alone (no room)
    players = {},
    phase = "w",        -- w waiting to start, d drawing, r the word revealed, o game over
    turn = 0,
    log = {},
    set = {},           -- the game's settings (the host's, or as the host sent them)
}
local HS = {}           -- the host's own: word, used, revealed, hints, revealUntil

local room              -- the party room (Games\RoomKit.lua), made below once its hooks are
local function Me() return Net:Me() end
local function Ctx() return (room and room.tid or "") .. "." .. S.turn end
local function Fill(t, d) ns.UI.Fill(t, d) end

local Refresh   -- (below)

-- S's copies of the room, for the display.
local function Sync()
    S.mode = S.practice and "practice" or room.mode
    S.players, S.host = room.players, room.host
end

---------------------------------------------------------------------------
-- Players and settings
---------------------------------------------------------------------------
local function Player(name) return room:Player(name) end
local function HostName() return room:HostName() end

local function NeedPlayers() return Words.NeedPlayers(S.set) end

-- A host who typed their own words knows them: they draw but don't guess.
local function CanGuess(name)
    if S.phase ~= "d" or name == S.drawer or not Player(name) then return false end
    if S.set.custom and name == HostName() then return false end
    return true
end

local function PackNames(packs)
    local t = {}
    for i = 1, string.len(packs or "") do
        local p = Words.Pack(string.sub(packs, i, i))
        if p then table.insert(t, p.name) end
    end
    return t
end

local function SettingsText()
    local names = PackNames(S.set.packs)
    if S.set.custom then table.insert(names, "the host's own words") end
    return "Words: " .. (names[1] and table.concat(names, ", ") or "none yet") .. "\n"
        .. (S.set.time or 80) .. " seconds to draw, " .. (S.set.each or 2) .. " turn" .. ((S.set.each or 2) == 1 and "" or "s")
        .. " each"
end

local function Log(text) ns.UI.AddLog(S.log, text, 40) end

---------------------------------------------------------------------------
-- The drawing (one canvas and its sync, made in Build)
---------------------------------------------------------------------------
local function IDraw() return S.practice or (S.phase == "d" and S.drawer == Me() and room:InRoom()) end

local function NewTurn(turn, drawer)
    S.turn, S.drawer = turn, drawer
    S.log, S.winner, S.myGuess = {}, nil, nil
    if not room:IsHost() then S.word = nil end
    if ui.sync then ui.sync:Begin(Ctx(), { [drawer or ""] = true }) end
    if ui.canvas then ui.canvas:SetDrawing(IDraw()) end
    if drawer == Me() then
        ns:Sound("RAID_WARNING")
    end
end

---------------------------------------------------------------------------
-- Host: telling the group (the room sends the roster and state; the artist
-- also gets the word, disguised, with every one)
---------------------------------------------------------------------------
local function StateParts()
    local left = S.deadline and math.max(0, math.floor(S.deadline - GetTime() + 0.5)) or 0
    local reveal = (S.phase == "r" or S.phase == "o") and (HS.word or "") or ""
    return { S.phase, S.turn, S.drawer or "", left, S.mask or "", S.set.time, S.set.each,
        S.set.packs or "", S.set.custom and "1" or "", reveal, S.winner or "" }
end

local function SendWord()
    if S.phase == "d" and HS.word then room:Send({ "K", room.tid, S.turn, Words.Hide(HS.word, S.drawer .. Ctx()) }, TAG .. "-K") end
end

local function Broadcast() room:Broadcast() end
local function SendOffer() room:Offer() end

---------------------------------------------------------------------------
-- Host: running the game
---------------------------------------------------------------------------
local function HostRoom()
    if S.practice then return end
    if room:Host() then ns:Sound("IG_MAINMENU_OPTION") end
end

-- (the room just opened)
local function OnHost()
    S.phase, S.turn, S.drawer, S.deadline, S.mask, S.winner = "w", 0, nil, nil, nil, nil
    S.set = db.settings
    S.log = {}
    HS.used = {}
end

local function GameOver()
    S.phase, S.deadline, S.drawer = "o", nil, nil
    HS.word = nil
    Broadcast()
    SendOffer()
    Refresh()
end

-- The next artist: whoever has drawn least, going round from the last one.
local function NextArtist()
    local n = ns.getn(room.players)
    local _, last = Player(S.drawer or "")
    last = last or n
    local best
    for step = 1, n do
        local p = room.players[ns.Mod(last - 1 + step, n) + 1]
        if p.drew < (S.set.each or 2) and (not best or p.drew < best.drew) then best = p end
    end
    return best
end

local function PickWord()
    if not HS.pool or ns.getn(HS.pool) == 0 then return nil end
    local fresh = {}
    for _, w in ipairs(HS.pool) do if not HS.used[Words.Norm(w)] then table.insert(fresh, w) end end
    if ns.getn(fresh) == 0 then
        HS.used = {}
        fresh = HS.pool
    end
    local w = fresh[math.random(1, ns.getn(fresh))]
    HS.used[Words.Norm(w)] = true
    return w
end

local function NextTurn()
    if not room:IsHost() then return end
    local artist = ns.getn(room.players) >= NeedPlayers() and NextArtist()
    local word = artist and PickWord()
    if not artist or not word then
        GameOver()
        return
    end
    artist.drew = artist.drew + 1
    HS.word, HS.revealed, HS.hints = word, {}, 0
    S.phase = "d"
    NewTurn(S.turn + 1, artist.name)
    S.mask = Words.Mask(word, HS.revealed)
    S.word = (artist.name == Me()) and word or nil
    S.deadline = GetTime() + (S.set.time or 80)
    HS.started = GetTime()
    Broadcast()
    SendOffer()
    Refresh()
end

local function HostStart()
    if not room:IsHost() or (S.phase ~= "w" and S.phase ~= "o") then return end
    HS.pool = Words.Pool(S.set.packs, S.set.custom and db.custom or nil)
    if ns.getn(HS.pool) == 0 or ns.getn(room.players) < NeedPlayers() then return end
    for _, p in ipairs(room.players) do p.score, p.drew = 0, 0 end
    S.turn, S.drawer = 0, nil
    ns:Sound("IG_MAINMENU_OPTION")
    NextTurn()
end

-- The turn ends: someone guessed it (winner), or time ran out / the artist left.
local function EndTurn(winner, why)
    if S.phase ~= "d" then return end
    S.phase, S.winner = "r", winner
    S.deadline = nil
    if winner then
        local p = Player(winner)
        if p then p.score = p.score + GUESS_POINTS end
        local a = Player(S.drawer or "")
        if a then a.score = a.score + ART_POINTS end
    end
    HS.revealUntil = GetTime() + REVEAL_TIME
    HS.why = why
    Game.CountTurn(HS.word, winner)
    Broadcast()
    Refresh()
end

-- A letter more of the word shows at half and three quarters of the time.
local function Hint()
    local hidden = {}
    for i = 1, string.len(HS.word) do
        if string.find(string.sub(HS.word, i, i), "%w") and not HS.revealed[i] then table.insert(hidden, i) end
    end
    if ns.getn(hidden) < 3 then return end
    HS.revealed[hidden[math.random(1, ns.getn(hidden))]] = true
    S.mask = Words.Mask(HS.word, HS.revealed)
    room:SendState()
    Refresh()
end

local function HostGuess(name, text)
    if not CanGuess(name) or not HS.word then return end
    text = Words.Clean(text)
    if text == "" then return end
    local g, w = Words.Norm(text), Words.Norm(HS.word)
    if g == w then
        room:Send({ "W", room.tid, S.turn, name, "", "y" })
        Game.ShowGuess(name, "", "y")
        EndTurn(name)
    elseif Words.Close(g, w) then
        room:Send({ "W", room.tid, S.turn, name, "", "c" })
        Game.ShowGuess(name, text, "c")
    else
        room:Send({ "W", room.tid, S.turn, name, text, "x" })
        Game.ShowGuess(name, text, "x")
    end
end

-- (someone left; the room has taken them off the roster and tells the group)
local function OnDrop(name)
    if S.phase == "d" and S.drawer == name then EndTurn(nil, name .. " left")
    elseif S.phase == "d" and ns.getn(room.players) < NeedPlayers() then EndTurn(nil) end
end

-- (someone joined partway: they draw as often as everyone else still will)
local function OnJoin(name, p)
    local least
    for _, q in ipairs(room.players) do if q ~= p and (not least or q.drew < least) then least = q.drew end end
    p.drew = (S.phase == "w" or S.phase == "o") and 0 or (least or 0)
    Log(name .. " joined.")
end

local function HostClose(message) room:Close(message) end

local function HostTick(now)
    if S.phase == "d" then
        local total = S.set.time or 80
        local gone = now - (HS.started or now)
        if now >= (S.deadline or now) then
            EndTurn(nil)
        elseif HS.hints == 0 and gone >= total * 0.5 then
            HS.hints = 1
            Hint()
        elseif HS.hints == 1 and gone >= total * 0.75 then
            HS.hints = 2
            Hint()
        end
    elseif S.phase == "r" and now >= (HS.revealUntil or now) then
        NextTurn()
    end
end

---------------------------------------------------------------------------
-- Clients
---------------------------------------------------------------------------
-- (back in the lobby: the room left, closed or lost touch)
local function OnLobby()
    S.phase, S.turn, S.drawer, S.deadline, S.mask, S.word, S.winner = "w", 0, nil, nil, nil, nil, nil
    S.log = {}
    if ui.sync then ui.sync:Begin(nil, {}) end
    if ui.canvas then ui.canvas:SetDrawing(false) end
end

-- To the lobby: out of practice, or out of a room.
function Game.ToLobby(message)
    S.practice = nil
    if room.mode ~= "lobby" then
        room:ToLobby(message)
    else
        OnLobby()
        room.lobbyMsg = message
        Refresh()
    end
end

local function Join(host, tid) room:Join(host, tid) end
local function ClientLeave() room:Leave() end

-- The host's state (S;tid;...: fields from f[4]).
local function ClientState(f)
    if room.fresh then S.phase, S.turn, S.log = "?", 0, {} end    -- (just joined)
    local phase, turn, drawer = f[4] or "w", tonumber(f[5] or "") or 0, f[6] ~= "" and f[6] or nil
    local wasPhase = S.phase
    S.set = { time = tonumber(f[9] or "") or 80, each = tonumber(f[10] or "") or 2, packs = f[11] or "", custom = f[12] == "1" }
    if turn ~= S.turn and phase ~= "w" then
        NewTurn(turn, drawer)
        if phase == "d" and drawer ~= Me() and wasPhase == "?" then ui.sync:Request() end
    end
    S.phase, S.drawer = phase, drawer
    local left = tonumber(f[7] or "") or 0
    S.deadline = (phase == "d") and (GetTime() + left) or nil
    S.mask = f[8] ~= "" and f[8] or nil
    if phase == "r" or phase == "o" then
        if f[13] and f[13] ~= "" then S.word = f[13] end
        local winner = (f[14] and f[14] ~= "") and f[14] or nil
        if phase == "r" and wasPhase == "d" then Game.CountTurn(S.word, winner) end
        S.winner = winner
    end
    if phase == "o" and wasPhase ~= "o" and wasPhase ~= "?" then Game.CountGame() end
    if ui.canvas then ui.canvas:SetDrawing(IDraw()) end
    Refresh()
end

room = ns.RoomKit.New({
    tag = TAG, id = "sketch", max = MAX_PLAYERS, fields = { "score", "drew" },
    phase = function() return S.phase end,
    state = StateParts,
    onBroadcast = SendWord,
    onState = ClientState,
    onHost = OnHost,
    onJoin = OnJoin,
    onDrop = OnDrop,
    onLobby = OnLobby,
    -- a guess, to the host
    onHostMessage = function(sender, f)
        if f[2] == "G" and tonumber(f[4] or "") == S.turn then HostGuess(sender, f[5]) end
    end,
    -- the artist's word (disguised) and the guesses, from the host
    onClientMessage = function(f)
        if f[2] == "K" then
            if tonumber(f[4] or "") == S.turn and S.drawer == Me() then
                S.word = Words.Reveal(f[5], Me() .. Ctx())
                Refresh()
            end
        elseif f[2] == "W" then
            if tonumber(f[4] or "") == S.turn then Game.ShowGuess(f[5], f[6], f[7]) end
        end
    end,
    refresh = function() Refresh() end,
})
-- the drawing kit's strokes first (they carry the same tag), then the room
Net.handlers[TAG] = function(sender, f)
    if ui.sync and ui.sync:Handle(sender, f) then return end
    room:OnMessage(sender, f)
end

-- Guessing: the host checks it (a guess goes nowhere else).
local function Guess(text)
    text = Words.Clean(text)
    if text == "" or not CanGuess(Me()) then return end
    S.myGuess = text
    if room:IsHost() then HostGuess(Me(), text) else room:Send({ "G", room.tid, S.turn, text }) end
    Refresh()
end

-- A guess as the host saw it.
function Game.ShowGuess(name, text, how)
    local mine = name == Me()
    local who = mine and "You" or (name or "?")
    if how == "y" then
        Log("|cff40ff40" .. who .. " guessed it!|r")
        if mine then
            db.stats.guessed = db.stats.guessed + 1
            ns:Sound("LOOT_WINDOW_COIN_SOUND")
        end
    elseif how == "c" then
        Log("|cffffd100" .. who .. (mine and (": " .. (S.myGuess or "") .. " - so close!|r") or " is close!|r"))
    else
        Log((mine and "You" or who) .. ": |cffcccccc" .. (text or "") .. "|r")
    end
    Refresh()
end

-- Stats: once per turn and per game, on every client.
function Game.CountTurn(word, winner)
    if S.drawer == Me() and winner then db.stats.drawn = db.stats.drawn + 1 end
end

function Game.CountGame()
    local s = db.stats
    s.games = s.games + 1
    local me, top = Player(Me()), 0
    for _, p in ipairs(room.players) do if p.score > top then top = p.score end end
    if me then
        s.points = s.points + me.score
        if top > 0 and me.score == top then
            s.wins = s.wins + 1
            ns:Sound("UI_EPICLOOT_TOAST")
        end
    end
end

---------------------------------------------------------------------------
-- The clock: the host's game, clients waiting on the host, sending strokes
---------------------------------------------------------------------------
ns:Every(0, function() if ui.sync then ui.sync:Tick() end end)
ns:Every(0.5, function() if ui.room and ui.room:IsShown() then Game.RefreshClock() end end)
ns:Every(0.2, function(dt, now)
    room:Tick(now)
    if room:IsHost() then
        HostTick(now)
        if S.phase == "o" and S.wasOver ~= true then
            S.wasOver = true
            Game.CountGame()
        elseif S.phase ~= "o" then
            S.wasOver = nil
        end
    end
end)

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function Clock() return ns.UI.Countdown(S.deadline) end

function Game.RefreshClock()
    if ui.timer then ui.timer:SetText(Clock()) end
end

local function RefreshWait()
    local host = S.mode == "host"
    for _, c in ipairs(ui.packChecks) do
        c:SetChecked(string.find(S.set.packs or "", c.key, 1, true) ~= nil)
        ns.SetShown(c, host); ns.SetShown(c.label, host)
    end
    ui.customCheck:SetChecked(S.set.custom and true or nil)
    ns.SetShown(ui.customCheck, host); ns.SetShown(ui.customCheck.label, host)
    ns.SetShown(ui.customBox, host and S.set.custom)
    ui.customCount:SetText((host and S.set.custom) and (ns.getn(Words.ParseCustom(db.custom)) .. " of your own words") or "")
    ns.SetShown(ui.timeStep, host); ns.SetShown(ui.eachStep, host)
    ns.SetShown(ui.timeLabel, host); ns.SetShown(ui.eachLabel, host)
    if host then
        ui.timeStep:Refresh(); ui.eachStep:Refresh()
    end
    ns.SetShown(ui.waitSummary, not host)
    ui.waitSummary:SetText(SettingsText() .. "\n\n|cffffffffWaiting for " .. (S.host or "the host") .. " to start.|r")
    ns.SetShown(ui.start, host)
    local n, need = ns.getn(S.players), NeedPlayers()
    local pool = host and ns.getn(Words.Pool(S.set.packs, S.set.custom and db.custom or nil)) or 1
    ns.SetEnabled(ui.start, host and n >= need and pool > 0)
    local note = ""
    if host then
        if pool == 0 then note = "Pick a word pack, or add your own words."
        elseif n < need then note = "Waiting for players: " .. need .. " needed" .. (S.set.custom and " (you know your own words, so you don't guess)." or ".")
        else note = n .. " players. Start when everyone's in." end
    end
    ui.startNote:SetText(note)
end

local function RefreshSide()
    local practice = S.mode == "practice"
    for i = 1, MAX_PLAYERS do
        local row, p = ui.players[i], (not practice) and S.players[i]
        if p then
            local name = p.name == Me() and (p.name .. " (you)") or p.name
            if p.name == S.drawer and S.phase == "d" then name = "|cffffd100" .. name .. "|r"
            elseif p.name == S.winner and S.phase == "r" then name = "|cff40ff40" .. name .. "|r" end
            row.name:SetText(name)
            row.score:SetText(tostring(p.score))
        else
            row.name:SetText(""); row.score:SetText("")
        end
    end
    ui.logHeader:SetText(practice and "" or "Guesses")
    local n = ns.getn(S.log)
    for i = 1, LOG_LINES do
        local line = (not practice) and S.log[n - LOG_LINES + i]
        ui.log[i]:SetText(line or "")
    end
    ns.SetShown(ui.practiceSide, practice)
    if practice then
        local can = Kit.CanRotate()
        ui.modeButton:SetText(Kit.LineMode() == "lines" and "Lines: smooth" or "Lines: dots")
        ns.SetEnabled(ui.modeButton, can)
    end
end

local function RefreshRoom()
    local practice = S.mode == "practice"
    local waiting = not practice and (S.phase == "w" or S.phase == "?")
    ns.SetShown(ui.wait, waiting)
    ns.SetShown(ui.canvas.frame, not waiting)
    if waiting then RefreshWait() end
    local drawing = IDraw()
    ui.canvas:SetDrawing(drawing)
    ns.SetShown(ui.tools, drawing)
    if drawing then ui.tools:Refresh() end
    local guessing = not practice and S.mode ~= "lobby" and CanGuess(Me())
    ns.SetShown(ui.guess, guessing)
    if not guessing and rawget(ui.guess, "focused") then ui.guess:ClearFocus() end

    -- the word line
    local word, status = "", ""
    if practice then
        word, status = "Practice", "Draw anything. Right-click (or the eraser) rubs a line out."
    elseif waiting then
        word = "Waiting to start"
    elseif S.phase == "d" then
        if S.drawer == Me() then
            word = "Draw: |cffffffff" .. (S.word or "...") .. "|r"
            status = "Your turn to draw! Don't write the word."
        else
            word = "|cffffffff" .. Words.ShowMask(S.mask) .. "|r"
            status = (S.drawer or "?") .. " is drawing." .. (CanGuess(Me()) and "" or
                (S.set.custom and S.mode == "host" and " You know your words, so you're watching this one." or ""))
        end
    elseif S.phase == "r" then
        word = "It was: |cffffffff" .. (S.word or "?") .. "|r"
        status = S.winner and ((S.winner == Me() and "You" or S.winner) .. " guessed it! +" .. GUESS_POINTS .. ", and +"
            .. ART_POINTS .. " for " .. (S.drawer == Me() and "you" or (S.drawer or "the artist")) .. ".")
            or "Nobody got it."
    elseif S.phase == "o" then
        word = "Game over"
    end
    ui.word:SetText(word)
    ui.status:SetText(status)
    Game.RefreshClock()
    local turns = ns.getn(S.players) * (S.set.each or 2)
    ui.info:SetText((not practice and S.turn > 0 and S.phase ~= "o") and ("Turn " .. S.turn .. " of about " .. turns) or "")

    -- the banner over the drawing
    local banner = ""
    if S.phase == "o" and not practice then
        local list = {}
        for _, p in ipairs(S.players) do table.insert(list, p) end
        table.sort(list, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
        local lines = { "|cffffd100Final scores|r" }
        for i, p in ipairs(list) do
            if i > 6 then break end
            table.insert(lines, i .. ". " .. (p.name == Me() and "You" or p.name) .. " - " .. p.score)
        end
        banner = table.concat(lines, "\n")
    end
    ns.SetShown(ui.banner, banner ~= "")
    ui.bannerText:SetText(banner)
    ns.SetShown(ui.again, S.mode == "host" and S.phase == "o")
    if S.mode == "host" and S.phase == "o" then ns.SetEnabled(ui.again, ns.getn(S.players) >= NeedPlayers()) end
    ns.SetShown(ui.testButton, practice)
    ui.leave:SetText(practice and "Done" or (S.mode == "host" and "Close game" or "Leave game"))
    RefreshSide()
end

Refresh = function()
    if not ui.lobby then return end
    Sync()
    local lobby = S.mode == "lobby"
    ns:UpdateIntro(Game)
    ns.SetShown(ui.room, not lobby)
    if lobby then room:RefreshLobby() else RefreshRoom() end
end
Game.Refresh = function() Refresh() end

-- For the core's intro (Intro.lua): a game or practice on is "busy"; in the
-- lobby the intro is all there is.
function Game:IntroState() return (S.practice or room.mode ~= "lobby") and "busy" or "intro" end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local Text = ns.UI.Text

local function Check(parent, x, y, label, onClick)
    local c = ns.UI.CheckBox(parent, label, function() return false end, function() onClick() end, true)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return c
end

local function EditBox(parent, width, maxLetters, hint)
    return ns.UI.EditBox(parent, { width = width, maxLetters = maxLetters, hint = hint })
end

-- The lobby is the game's intro screen (Intro.lua, through the room kit):
-- Practice, Host a game, and the games open in the group.
local function BuildLobby(panel)
    room:BuildLobby(panel, {
        game = Game, felt = { 0.07, 0.06, 0.05, 1 },
        info = "Draw a secret word while the others race to guess it. Free: no chips are wagered.",
        alone = "Join a party or raid to play with friends (or practice on your own).",
        buttons = { { "Practice", function() Game.Practice() end } },
        stats = function()
            local s = db.stats
            return string.format("Games %d   Wins %d   Right guesses %d   Drawings guessed %d",
                s.games, s.wins, s.guessed, s.drawn)
        end,
    })
    ui.intro = room.intro
    ui.lobby = room.lobby
end

local function TogglePack(key)
    local packs = S.set.packs or ""
    local at = string.find(packs, key, 1, true)
    if at then packs = string.sub(packs, 1, at - 1) .. string.sub(packs, at + 1) else packs = packs .. key end
    S.set.packs = packs
end

local function SettingsChanged() room:SettingsChanged() end

local function BuildWait(field)
    local w = ns.CreateFrame("Frame", nil, field)
    w:SetPoint("TOPLEFT", field, "TOPLEFT", 2, -26)
    w:SetWidth(256); w:SetHeight(320)
    local bg = w:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(w)
    bg:SetTexture(0, 0, 0, 0.35)
    ui.wait = w
    local label = Text(w, "GameFontNormal", 6, -6)
    label:SetText("Words")
    ui.packChecks = {}
    for i, p in ipairs(Words.PACKS) do
        local key = p.key
        local c = Check(w, 4 + ns.Mod(i - 1, 2) * 124, -22 - math.floor((i - 1) / 2) * 22, p.name, function()
            TogglePack(key)
            SettingsChanged()
        end)
        c.key = key
        table.insert(ui.packChecks, c)
    end
    local n = ns.getn(Words.PACKS)
    ui.customCheck = Check(w, 4 + ns.Mod(n, 2) * 124, -22 - math.floor(n / 2) * 22, "My own words", function()
        S.set.custom = not S.set.custom
        SettingsChanged()
    end)
    local rowsY = -22 - math.floor(n / 2 + 1) * 22
    ui.customBox = ns.UI.EditBox(w, { width = 246, maxLetters = 2000, hint = "Your words, separated by commas",
        onChange = function(b)
            db.custom = b:GetText() or ""
            Refresh()
        end })
    ui.customBox:SetPoint("TOPLEFT", w, "TOPLEFT", 4, rowsY - 2)
    ui.customBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    ui.customCount = Text(w, "GameFontDisableSmall", 8, rowsY - 26, 240)

    ui.timeLabel = Text(w, "GameFontHighlightSmall", 6, rowsY - 50)
    ui.timeLabel:SetText("Time to draw")
    ui.timeStep = ns.UI.Stepper(w, {
        list = TIMES, width = 70,
        label = function(v) return "|cffffffff" .. v .. " sec|r" end,
        get = function() return S.set.time end,
        set = function(v) S.set.time = v end,
        onChange = function() SettingsChanged() end,
    })
    ui.timeStep:SetPoint("TOPRIGHT", w, "TOPRIGHT", -4, rowsY - 44)
    ui.eachLabel = Text(w, "GameFontHighlightSmall", 6, rowsY - 78)
    ui.eachLabel:SetText("Turns each")
    ui.eachStep = ns.UI.Stepper(w, {
        list = EACH, width = 70,
        label = function(v) return "|cffffffff" .. v .. "|r" end,
        get = function() return S.set.each end,
        set = function(v) S.set.each = v end,
        onChange = function() SettingsChanged() end,
    })
    ui.eachStep:SetPoint("TOPRIGHT", w, "TOPRIGHT", -4, rowsY - 72)

    ui.waitSummary = Text(w, "GameFontHighlight", 8, -14, 240)
    ui.start = ns.UI.Button(w, "Start", 140, function() HostStart() end, 26)
    ui.start:SetPoint("TOP", w, "TOP", 0, rowsY - 112)
    ui.startNote = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.startNote:SetPoint("TOP", ui.start, "BOTTOM", 0, -6)
    ui.startNote:SetWidth(240)
end

local function BuildRoom(panel)
    local field = ns.CreateFrame("Frame", nil, panel)
    field:SetAllPoints(panel)
    ui.room = field
    ui.word = Text(field, "GameFontNormalLarge", 4, -5, 254)
    ui.timer = field:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.timer:SetPoint("TOPRIGHT", field, "TOPRIGHT", -6, -5)

    -- the drawing, and what everyone sees of it
    local canvas = Kit.NewCanvas(field, { size = 256 })
    canvas.frame:SetPoint("TOPLEFT", field, "TOPLEFT", 2, -26)
    ui.canvas = canvas
    ui.sync = Kit.NewSync({ tag = TAG, canvas = canvas })
    canvas.onEvent = (function(chain)
        return function(event, key)
            chain(event, key)
            if ui.tools and ui.tools:IsShown() then ui.tools:Refresh() end
        end
    end)(canvas.onEvent)
    ui.tools = Kit.NewTools(field, canvas)
    ui.tools:SetPoint("TOPLEFT", field, "TOPLEFT", 2, -288)

    ui.banner = ns.CreateFrame("Frame", nil, field)
    ui.banner:SetPoint("TOPLEFT", canvas.frame, "TOPLEFT", 16, -40)
    ui.banner:SetPoint("BOTTOMRIGHT", canvas.frame, "BOTTOMRIGHT", -16, 40)
    ui.banner:SetFrameLevel(canvas.frame:GetFrameLevel() + 5)
    local bbg = ui.banner:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints(ui.banner)
    bbg:SetTexture(0, 0, 0, 0.82)
    ui.bannerText = ui.banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.bannerText:SetPoint("TOP", ui.banner, "TOP", 0, -12)
    ui.bannerText:SetWidth(210)
    ui.again = ns.UI.Button(ui.banner, "Play again", 110, function() HostStart() end, 22)
    ui.again:SetPoint("BOTTOM", ui.banner, "BOTTOM", 0, 10)

    -- guessing
    ui.guess = EditBox(field, 256, 40, "Type your guess and press Enter")
    ui.guess:SetPoint("TOPLEFT", field, "TOPLEFT", 2, -290)
    ui.guess:SetScript("OnEnterPressed", function()
        Guess(this:GetText())
        this:SetText("")
    end)
    ui.status = Text(field, "GameFontHighlightSmall", 4, -342, 256)
    ui.info = Text(field, "GameFontDisableSmall", 4, -362, 180)

    BuildWait(field)

    -- the side: players and guesses (or, practicing, how lines are drawn)
    local x = 266
    ui.players = {}
    for i = 1, MAX_PLAYERS do
        ui.players[i] = {
            name = Text(field, "GameFontHighlightSmall", x, -30 - (i - 1) * 14, 92),
            score = Text(field, "GameFontNormalSmall", x + 92, -30 - (i - 1) * 14, 20, "RIGHT"),
        }
    end
    ui.logHeader = Text(field, "GameFontNormal", x, -176)
    ui.log = {}
    for i = 1, LOG_LINES do ui.log[i] = Text(field, "GameFontHighlightSmall", x, -192 - (i - 1) * 13, 112) end

    local ps = ns.CreateFrame("Frame", nil, field)
    ps:SetPoint("TOPLEFT", field, "TOPLEFT", x, -30)
    ps:SetWidth(112); ps:SetHeight(200)
    ui.practiceSide = ps
    local note = Text(ps, "GameFontHighlightSmall", 0, 0, 112)
    note:SetText("Lines can be drawn smooth, or as dots for a client that can't turn a texture. "
        .. "The test pattern shows how they look here.")
    ui.modeButton = ns.UI.Button(ps, "Lines: smooth", 110, function()
        Kit.SetLineMode(Kit.LineMode() == "lines" and "dots" or "lines")
        ns:Sound("IG_MAINMENU_OPTION")
        Refresh()
    end)
    ui.modeButton:SetPoint("TOPLEFT", ps, "TOPLEFT", 0, -96)
    ui.testButton = ns.UI.Button(ps, "Test pattern", 110, function() canvas:TestPattern() end)
    ui.testButton:SetPoint("TOPLEFT", ps, "TOPLEFT", 0, -122)

    ui.leave = ns.UI.Button(field, "Leave game", 110, function()
        if S.practice then Game.ToLobby(nil)
        elseif room:IsHost() then HostClose()
        else ClientLeave() end
    end)
    ui.leave:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -2, 4)
end

function Game.Practice()
    if S.practice or room.mode ~= "lobby" then return end
    S.practice, S.phase, room.lobbyMsg = true, "w", nil
    ui.sync:Begin(nil, {})
    ui.canvas:SetDrawing(true)
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

local RULES = "One player hosts and picks the words: built-in packs, their own list, or both. Everyone takes a turn "
    .. "drawing (round robin), for as many turns each as the host chose.\n\n"
    .. "The artist sees the word and draws it; everyone else types guesses. The first right guess ends the turn: "
    .. GUESS_POINTS .. " points to the guesser, " .. ART_POINTS .. " to the artist. A letter of the word shows at half "
    .. "time and another at three quarters. Close guesses are flagged, and guesses don't need capitals, spaces or dashes.\n\n"
    .. "A host using their own words knows them, so they draw but don't guess.\n\n"
    .. "Drawing: pick a color and size; right-click or the eraser removes a line; Undo takes back your last one."

function Game:Build(panel)
    db = ns:SetupGame(panel, "sketch", { stats = DEFAULT_STATS, felt = { 0.07, 0.06, 0.05, 1 } })
    db.settings = db.settings or {}
    Fill(db.settings, DEFAULT_SETTINGS)
    db.custom = db.custom or ""
    self.panel = panel
    room:Restore(db)
    BuildLobby(panel)
    BuildRoom(panel)
    ui.customBox:SetText(db.custom)
    S.set = db.settings

    ns:GameOptions(self, panel, {
        settings = true, rules = RULES,
        build = function(o)
            local label = Text(o.settings, "GameFontNormal", 16, -48)
            label:SetText("Lines")
            o.lineStep = ns.UI.Stepper(o.settings, {
                list = { "lines", "dots" }, width = 110,
                label = function(v) return "|cffffffff" .. (v == "lines" and "Smooth lines" or "Dots") .. "|r" end,
                get = function() return Kit.LineMode() end,
                set = function(v) Kit.SetLineMode(v) end,
                locked = function() return not Kit.CanRotate() end,
            })
            o.lineStep:SetPoint("TOPRIGHT", o, "TOPRIGHT", -16, -44)
            local note = Text(o.settings, "GameFontHighlightSmall", 16, -76, 330)
            note:SetText("How drawings are drawn on your screen. Use Dots if smooth lines look wrong on this client "
                .. "(Practice has a test pattern). It doesn't change what others see.")
        end,
        refresh = function(o) if o.lineStep then o.lineStep:Refresh() end end,
    })

    Refresh()
end

function Game:OnShow()
    room:Ask()
    Refresh()
end

function Game:OnHide()
    if ui.guess and rawget(ui.guess, "focused") then ui.guess:ClearFocus() end
end

function Game:IsSeated() return room:InRoom() end
function Game:ChatTable() return room:ChatTable() end

Game.defaultStats = DEFAULT_STATS     -- (ns:ResetStats)
function Game:OnStatsReset(d)
    if ui.lobby then Refresh() end
end

-- Exposed for tests (and for other games that want to look).
Game.S, Game.HS, Game.ui, Game.room = S, HS, ui, room
ns.Sketch = Game

ns:RegisterGame(Game)

-- The lobby hub (Lobby.lua): pop-ups, badges and invites.
room:RegisterLobby("sketch", function()
    if S.practice then Game.ToLobby() end
end)
