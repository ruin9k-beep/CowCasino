-- CowCasino: Hangman. Guess the word a letter at a time before the gallows
-- is finished (six misses: head, body, two arms, two legs).
--
-- Solo: against the computer, for a bet. Win and you're paid 2x your bet,
-- 3x with no misses at all; hang and the bet's gone. The words come from the
-- packs picked in Options (the drawing games' packs, Games\SketchWords.lua).
--
-- Party (free, on the room kit, Games\RoomKit.lua): the host picks the word
-- packs (or types their own words, and then sits out guessing), the time for
-- a turn and how many words. Players take turns: call a letter and score a
-- point for each time it's in the word, and go again; a miss adds to the
-- gallows and passes the turn. On your turn you can solve instead: right
-- scores 2 a hidden letter (2 at least) and ends the word, wrong is a miss.
-- Six misses and the word's lost. Highest score after the last word wins.
--
-- Messages (tag HM; the room kit's, and): S (state, below), P;tid;round;letter
-- and V;tid;round;guess (a player's go, to the host), W;tid;round;text (a line
-- for everyone's log).

local ns = CowCasino.ns
local Kit = ns.SketchKit
local Words = ns.SketchWords

local TAG = "HM"
local MAX_PLAYERS = 8
local MISSES = 6
local TURN_TIMES = { 10, 15, 20, 30, 45, 60 }
local WORD_COUNTS = { 3, 5, 8, 10, 15 }
local BETS = { 10, 25, 50, 100, 250, 500, 1000, 2500 }
local REVEAL_TIME = 4
local LOG_LINES = 4
local LETTERS = "abcdefghijklmnopqrstuvwxyz"
local ART = "Interface\\AddOns\\CowCasino\\Art\\"

local DEFAULT_STATS = { solo = 0, soloWins = 0, perfect = 0, games = 0, wins = 0, solved = 0 }

local Game = {
    id = "hangman",
    name = "Hangman",
    description = "Guess the word a letter at a time, before the gallows is done.\n|cff66ccffSupports Multiplayer|r",
    icon = ART .. "HangmanIcon",   -- painted (dev/art-src/make_game_icons.py)
    wide = true,
}

local db
local ui = {}
-- What's on the table: solo, or the party game (as the host runs it, or as
-- the host last told us).
local G = { phase = "w", mask = "", guessed = "", misses = 0, round = 0, rounds = 5, log = {} }
local HS = {}   -- the host's own: word, order, pool, used, revealUntil
local room      -- the room kit (made below)
local Refresh

local function Me() return ns.Net:Me() end
local function Solo() return db and db.solo end
local function InSolo() return ui.mode == "solo" and not room:InRoom() end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
-- Letters not yet guessed show as "_" (anything that isn't a letter shows).
local function Mask(word, guessed)
    local out = {}
    for i = 1, string.len(word) do
        local ch = string.sub(word, i, i)
        local low = string.lower(ch)
        if string.find(low, "%a") and not string.find(guessed, low, 1, true) then ch = "_" end
        table.insert(out, ch)
    end
    return table.concat(out)
end

local function Hits(word, letter)
    local n = 0
    local low = string.lower(word)
    for i = 1, string.len(low) do if string.sub(low, i, i) == letter then n = n + 1 end end
    return n
end

local function Pick(list, used)
    if ns.getn(list) == 0 then return nil end
    local fresh = {}
    for _, e in ipairs(list) do if not used[Words.Norm(e.word)] then table.insert(fresh, e) end end
    if ns.getn(fresh) == 0 then
        for k in pairs(used) do used[k] = nil end
        fresh = list
    end
    local e = fresh[math.random(1, ns.getn(fresh))]
    used[Words.Norm(e.word)] = true
    return e
end

---------------------------------------------------------------------------
-- Solo
---------------------------------------------------------------------------
local function SoloPay(s) return s.misses == 0 and s.bet * 3 or s.bet * 2 end

local function SoloEnd(won)
    local s = Solo()
    s.active, s.result = nil, won and "win" or "lose"
    db.stats.solo = db.stats.solo + 1
    if won then
        db.stats.soloWins = db.stats.soloWins + 1
        if s.misses == 0 then db.stats.perfect = db.stats.perfect + 1 end
        s.paid = SoloPay(s)
        ns:AddChips(s.paid)
        ns:Sound(s.misses == 0 and "UI_EPICLOOT_TOAST" or "LOOT_WINDOW_COIN_SOUND")
    else
        s.paid = 0
        ns:Sound("IG_QUEST_FAILED")
    end
end

local function SoloStart()
    local s = Solo()
    if s.active then return end
    local list = Words.PoolHints(db.soloSet.packs, nil)
    if ns.getn(list) == 0 then
        ui.soloMsg = "Pick a word pack in Options first."
        Refresh()
        return
    end
    s.bet = ns:FitList(BETS, s.bet)
    if not ns:SpendChips(s.bet) then return end
    db.used = db.used or {}
    local e = Pick(list, db.used)
    s.word, s.hint, s.guessed, s.misses, s.active, s.result, s.paid = e.word, e.hint, "", 0, true, nil, nil
    ui.soloMsg = nil
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

local function SoloLetter(letter)
    local s = Solo()
    if not s.active or string.find(s.guessed, letter, 1, true) then return end
    s.guessed = s.guessed .. letter
    if Hits(s.word, letter) > 0 then
        ns:Sound("IG_MAINMENU_OPTION")
        if not string.find(Mask(s.word, s.guessed), "_", 1, true) then SoloEnd(true) end
    else
        s.misses = s.misses + 1
        ns:Sound("IG_QUEST_FAILED")
        if s.misses >= MISSES then SoloEnd(false) end
    end
    Refresh()
end

local function SoloSolve(text)
    local s = Solo()
    if not s.active or Words.Norm(text) == "" then return end
    if Words.Norm(text) == Words.Norm(s.word) then
        SoloEnd(true)
    else
        s.misses = s.misses + 1
        if s.misses >= MISSES then SoloEnd(false) else ns:Sound("IG_QUEST_FAILED") end
    end
    Refresh()
end

---------------------------------------------------------------------------
-- Party: the host
---------------------------------------------------------------------------
local function Log(text)
    table.insert(G.log, text)
    while ns.getn(G.log) > 30 do table.remove(G.log, 1) end
end

local function SayAll(text)
    Log(text)
    room:Send({ "W", room.tid, G.round, text })
end

-- Who guesses: everyone, but a host using their own words.
local function Guessers()
    local out = {}
    for _, p in ipairs(room.players) do
        if not (G.set.custom and p.name == room:HostName()) then table.insert(out, p.name) end
    end
    return out
end

local function NeedPlayers() return G.set.custom and 3 or 2 end

local function State()
    local left = G.deadline and math.max(0, math.floor(G.deadline - GetTime() + 0.5)) or 0
    local reveal = (G.phase == "r" or G.phase == "o") and (HS.word or "") or ""
    return { G.phase, G.round, G.set.words, G.turn or "", left, G.mask, G.guessed, G.misses, G.hint or "", reveal,
        G.solver or "", G.set.turn, G.set.packs or "", G.set.custom and "1" or "" }
end

local function GameOver()
    G.phase, G.turn, G.deadline = "o", nil, nil
    Game.CountGame()
    room:Broadcast()
    room:Offer()
    Refresh()
end

local function SetTurn(name)
    G.turn = name
    G.deadline = GetTime() + (G.set.turn or 20)
end

local function NextTurn()
    local list = Guessers()
    local n = ns.getn(list)
    if n == 0 then return end
    local at = 0
    for i, name in ipairs(list) do if name == G.turn then at = i end end
    SetTurn(list[ns.Mod(at, n) + 1])
end

local function NewWord()
    local list = Guessers()
    if ns.getn(list) < 2 or G.round >= (G.set.words or 5) then
        GameOver()
        return
    end
    local e = Pick(HS.pool, HS.used)
    if not e then GameOver() return end
    G.round = G.round + 1
    HS.word, G.hint, G.guessed, G.misses, G.solver = e.word, e.hint, "", 0, nil
    G.mask = Mask(e.word, "")
    G.phase = "p"
    G.log = {}
    -- each word starts with the next player round the table
    SetTurn(list[ns.Mod(G.round - 1, ns.getn(list)) + 1])
    room:Broadcast()
    room:Offer()
    Refresh()
end

local function EndWord(solver)
    G.phase, G.solver, G.deadline = "r", solver, nil
    G.mask = HS.word
    HS.revealUntil = GetTime() + REVEAL_TIME
    room:Broadcast()
    Refresh()
end

local function HostStart()
    if not room:IsHost() or (G.phase ~= "w" and G.phase ~= "o") then return end
    HS.pool = Words.PoolHints(G.set.packs, G.set.custom and db.custom or nil)
    HS.used = {}
    if ns.getn(HS.pool) == 0 or ns.getn(room.players) < NeedPlayers() then return end
    for _, p in ipairs(room.players) do p.score = 0 end
    G.round = 0
    ns:Sound("IG_MAINMENU_OPTION")
    NewWord()
end

local function Score(name, n)
    local p = room:Player(name)
    if p then p.score = p.score + n end
end

local function Miss(name, what)
    G.misses = G.misses + 1
    SayAll(name .. ": " .. what .. " - |cffff5050miss|r")
    if G.misses >= MISSES then
        SayAll("|cffff5050Hanged!|r Nobody gets the word.")
        EndWord(nil)
    else
        NextTurn()
        room:Broadcast()
        Refresh()
    end
end

local function HostLetter(name, letter)
    letter = string.lower(letter or "")
    if G.phase ~= "p" or name ~= G.turn or string.len(letter) ~= 1 or not string.find(LETTERS, letter, 1, true)
        or string.find(G.guessed, letter, 1, true) then return end
    G.guessed = G.guessed .. letter
    local n = Hits(HS.word, letter)
    if n == 0 then
        Miss(name, string.upper(letter))
        return
    end
    Score(name, n)
    G.mask = Mask(HS.word, G.guessed)
    SayAll(name .. ": " .. string.upper(letter) .. " |cff40ff40+" .. n .. "|r")
    if not string.find(G.mask, "_", 1, true) then
        EndWord(name)
        return
    end
    SetTurn(name)   -- a hit: go again
    room:Broadcast()
    Refresh()
end

local function HostSolve(name, text)
    if G.phase ~= "p" or name ~= G.turn then return end
    text = Words.Clean(text)
    if Words.Norm(text) == "" then return end
    if Words.Norm(text) == Words.Norm(HS.word) then
        local bonus = math.max(2, 2 * Words.Hidden(G.mask))
        Score(name, bonus)
        SayAll("|cff40ff40" .. name .. " solved it! +" .. bonus .. "|r")
        EndWord(name)
    else
        Miss(name, "\"" .. text .. "\"")
    end
end

local function HostTick(now)
    if G.phase == "p" and G.deadline and now >= G.deadline then
        SayAll((G.turn or "?") .. " ran out of time.")
        NextTurn()
        room:Broadcast()
        Refresh()
    elseif G.phase == "r" and now >= (HS.revealUntil or now) then
        NewWord()
    end
end

---------------------------------------------------------------------------
-- Party: everyone
---------------------------------------------------------------------------
local function ClientState(f)
    local was = G.phase
    G.phase = f[4] or "w"
    local round = tonumber(f[5] or "") or 0
    if round ~= G.round then G.log = {} end
    G.round = round
    G.set = { words = tonumber(f[6] or "") or 5, turn = tonumber(f[15] or "") or 20, packs = f[16] or "", custom = f[17] == "1" }
    G.turn = (f[7] ~= "") and f[7] or nil
    local left = tonumber(f[8] or "") or 0
    G.deadline = (G.phase == "p") and (GetTime() + left) or nil
    G.mask, G.guessed, G.misses = f[9] or "", f[10] or "", tonumber(f[11] or "") or 0
    G.hint = (f[12] ~= "") and f[12] or nil
    if f[13] and f[13] ~= "" then G.mask = f[13] end
    G.solver = (f[14] and f[14] ~= "") and f[14] or nil
    if G.phase == "o" and was ~= "o" and not room.fresh then Game.CountGame() end
    if G.phase == "p" and G.turn == Me() and was ~= "?" then
        if ui.lastTurn ~= G.round .. G.turn .. G.guessed then ns:Sound("RAID_WARNING") end
    end
    ui.lastTurn = G.round .. (G.turn or "") .. G.guessed
    Refresh()
end

function Game.CountGame()
    local s = db.stats
    s.games = s.games + 1
    local me, top = room:Player(Me()), 0
    for _, p in ipairs(room.players) do if p.score > top then top = p.score end end
    if me and top > 0 and me.score == top then
        s.wins = s.wins + 1
        ns:Sound("UI_EPICLOOT_TOAST")
    end
end

local function PartyLetter(letter)
    if G.phase ~= "p" or G.turn ~= Me() then return end
    if room:IsHost() then HostLetter(Me(), letter) else room:Send({ "P", room.tid, G.round, letter }) end
end

local function PartySolve(text)
    if G.phase ~= "p" or G.turn ~= Me() then return end
    text = Words.Clean(text)
    if text == "" then return end
    if room:IsHost() then HostSolve(Me(), text) else room:Send({ "V", room.tid, G.round, text }) end
end

room = ns.RoomKit.New({
    tag = TAG, id = "hangman", max = MAX_PLAYERS,
    phase = function() return G.phase end,
    state = State,
    onState = ClientState,
    onHost = function()
        G.set = db.party
        G.phase, G.round, G.turn, G.deadline, G.mask, G.guessed, G.misses, G.solver = "w", 0, nil, nil, "", "", 0, nil
        G.log = {}
    end,
    onJoin = function(name) Log(name .. " joined.") end,
    onDrop = function(name)
        if G.phase == "p" then
            if ns.getn(Guessers()) < 2 then
                EndWord(nil)
            elseif G.turn == name then
                NextTurn()
            end
        end
    end,
    onHostMessage = function(sender, f)
        if tonumber(f[4] or "") ~= G.round then return end
        if f[2] == "P" then HostLetter(sender, f[5]) elseif f[2] == "V" then HostSolve(sender, f[5]) end
    end,
    onClientMessage = function(f)
        if f[2] == "W" and tonumber(f[4] or "") == G.round then
            Log(f[5] or "")
            Refresh()
        end
    end,
    onLobby = function()
        ui.mode = "lobby"
        G.phase, G.log = "w", {}
    end,
    refresh = function() Refresh() end,
})

---------------------------------------------------------------------------
-- The gallows, drawn on a small canvas from the drawing kit
---------------------------------------------------------------------------
local WOOD, INK = 3, 1     -- colors (Kit.COLORS)
local GALLOWS = {
    { 24, 238, 150, 238 }, { 60, 238, 60, 26 }, { 60, 26, 178, 26 }, { 60, 66, 100, 26 }, { 178, 26, 178, 70 },
}
local function Ring(cx, cy, r)
    local pts = {}
    for i = 0, 20 do
        local a = i * math.pi / 10
        table.insert(pts, math.floor(cx + r * math.cos(a) + 0.5))
        table.insert(pts, math.floor(cy + r * math.sin(a) + 0.5))
    end
    return pts
end
local BODY = {
    Ring(178, 92, 22), { 178, 114, 178, 176 }, { 178, 132, 148, 160 }, { 178, 132, 208, 160 },
    { 178, 176, 152, 220 }, { 178, 176, 204, 220 },
}

local function DrawGallows(misses)
    local c = ui.gallows
    if c.shownMisses == misses and c.mode == Kit.LineMode() then return end
    c:Clear()
    for i, s in ipairs(GALLOWS) do c:AddPoints("g:" .. i, Kit.StyleChar(WOOD, 3), 1, s) end
    for i = 1, math.min(misses, MISSES) do c:AddPoints("b:" .. i, Kit.StyleChar(INK, 3), 1, BODY[i]) end
    c.shownMisses = misses
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
-- What the table shows now: { word mask, guessed, misses, hint, myGo, over }.
local function View()
    if InSolo() then
        local s = Solo()
        if not s.word then return { mask = "", guessed = "", misses = 0, myGo = false } end
        return { mask = s.active and Mask(s.word, s.guessed) or s.word, guessed = s.guessed, misses = s.misses,
            hint = s.hint, myGo = s.active, word = s.word }
    end
    return { mask = G.mask or "", guessed = G.guessed or "", misses = G.misses or 0, hint = G.hint,
        myGo = G.phase == "p" and G.turn == Me(), word = (G.phase == "r" or G.phase == "o") and G.mask or nil }
end

local function ShowMask(mask)
    local out = {}
    for i = 1, string.len(mask) do table.insert(out, string.upper(string.sub(mask, i, i))) end
    return table.concat(out, " ")
end

local function Clock()
    if not G.deadline then return "" end
    local left = math.max(0, math.floor(G.deadline - GetTime() + 0.5))
    if left <= 5 then return "|cffff5050" .. left .. "s|r" end
    return left .. "s"
end

local function RefreshLetters(v)
    local word = v.word or (InSolo() and Solo().word) or HS.word
    for i, b in ipairs(ui.letters) do
        local l = string.sub(LETTERS, i, i)
        local tried = string.find(v.guessed, l, 1, true) ~= nil
        local label = string.upper(l)
        if tried then
            -- the host (and solo) know the word; others tell a hit by the mask
            local hit
            if word then hit = Hits(word, l) > 0 else hit = string.find(string.lower(v.mask), l, 1, true) ~= nil end
            label = (hit and "|cff40ff40" or "|cffff5050") .. label .. "|r"
        end
        b:SetText(label)
        ns.SetEnabled(b, v.myGo and not tried)
    end
end

local function RefreshSide()
    local party = not InSolo()
    ns.SetShown(ui.partySide, party)
    ns.SetShown(ui.soloSide, not party)
    if party then
        for i = 1, MAX_PLAYERS do
            local row, p = ui.players[i], room.players[i]
            if p then
                local name = p.name == Me() and (p.name .. " (you)") or p.name
                if p.name == G.turn and G.phase == "p" then name = "|cffffd100> " .. name .. "|r"
                elseif p.name == G.solver and G.phase == "r" then name = "|cff40ff40" .. name .. "|r" end
                row.name:SetText(name)
                row.score:SetText(tostring(p.score))
            else
                row.name:SetText(""); row.score:SetText("")
            end
        end
        local n = ns.getn(G.log)
        for i = 1, LOG_LINES do ui.log[i]:SetText(G.log[n - LOG_LINES + i] or "") end
    else
        local s, st = Solo(), db.stats
        local lines = {
            "Win: |cffffffff2x|r your bet",
            "No misses: |cffffffff3x|r",
            " ",
            string.format("Played %d   Won %d", st.solo, st.soloWins),
            string.format("Perfect %d", st.perfect),
        }
        ui.soloInfo:SetText(table.concat(lines, "\n"))
        ns.SetShown(ui.betStep, not s.active)
        if not s.active then ui.betStep:Refresh() end
    end
end

local function RefreshWait()
    local host = room:IsHost()
    ui.picker:Refresh(host)
    ns.SetShown(ui.turnStep, host); ns.SetShown(ui.wordsStep, host)
    ns.SetShown(ui.turnLabel, host); ns.SetShown(ui.wordsLabel, host)
    if host then ui.turnStep:Refresh(); ui.wordsStep:Refresh() end
    ns.SetShown(ui.start, host)
    local n, need = ns.getn(room.players), NeedPlayers()
    local pool = host and ns.getn(Words.PoolHints(G.set.packs, G.set.custom and db.custom or nil)) or 1
    ns.SetEnabled(ui.start, host and n >= need and pool > 0)
    local note
    if host then
        if pool == 0 then note = "Pick a word pack, or add your own words."
        elseif n < need then note = "Waiting for players: " .. need .. " needed" .. (G.set.custom and " (you know your own words, so you don't guess)." or ".")
        else note = n .. " players. Start when everyone's in." end
    else
        note = (G.set.words or 5) .. " words, " .. (G.set.turn or 20) .. " seconds a turn.\n\n|cffffffffWaiting for "
            .. (room.host or "the host") .. " to start.|r"
    end
    ui.startNote:SetText(note)
end

local function RefreshTable()
    local solo = InSolo()
    local waiting = not solo and (G.phase == "w" or G.phase == "?")
    ns.SetShown(ui.wait, waiting)
    ns.SetShown(ui.play, not waiting)
    if waiting then RefreshWait() end
    local v = View()
    DrawGallows(v.misses)
    ui.word:SetText(ShowMask(v.mask))
    ui.hint:SetText(v.hint and ("Hint: " .. v.hint) or "")
    ui.misses:SetText("Misses: " .. v.misses .. " of " .. MISSES)
    RefreshLetters(v)
    ns.SetShown(ui.solveBox, v.myGo)
    ns.SetShown(ui.solve, v.myGo)
    if not v.myGo and ui.solveFocus then ui.solveBox:ClearFocus() end

    local status = ""
    if solo then
        local s = Solo()
        if s.active then status = "Pick a letter, or solve it."
        elseif s.result == "win" then
            status = "|cff40ff40You got it!|r " .. (s.misses == 0 and "No misses: " or "") .. "paid " .. ns:FormatChips(s.paid) .. "."
        elseif s.result == "lose" then status = "|cffff5050Hanged.|r The word was " .. string.upper(s.word or "") .. "."
        else status = ui.soloMsg or "Place a bet and press Play." end
        if ui.soloMsg and not s.active then status = ui.soloMsg end
        ui.main:SetText(s.active and "Give up" or ("Play for " .. ns:FormatChips(s.bet)))
        ns.SetEnabled(ui.main, s.active or (ns.db.chips >= BETS[1]))
    else
        if G.phase == "p" then
            status = (G.turn == Me()) and "|cffffd100Your turn!|r Pick a letter, or solve it." or ((G.turn or "?") .. "'s turn.")
        elseif G.phase == "r" then
            status = G.solver and ((G.solver == Me() and "You" or G.solver) .. " got the word.") or "Nobody got the word."
        elseif G.phase == "o" then
            local list = {}
            for _, p in ipairs(room.players) do table.insert(list, p) end
            table.sort(list, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
            local top = list[1]
            status = top and ("|cffffd100Game over.|r " .. (top.name == Me() and "You win" or (top.name .. " wins"))
                .. " with " .. top.score .. ".") or "Game over."
        end
        ui.main:SetText(room:IsHost() and "Close game" or "Leave game")
        ns.SetEnabled(ui.main, true)
    end
    ui.status:SetText(status)
    ui.info:SetText((not solo and G.round > 0 and G.phase ~= "o") and ("Word " .. G.round .. " of " .. (G.set.words or 5)) or "")
    ui.clock:SetText(solo and "" or Clock())
    ns.SetShown(ui.again, room:IsHost() and G.phase == "o")
    if room:IsHost() and G.phase == "o" then ns.SetEnabled(ui.again, ns.getn(room.players) >= NeedPlayers()) end
    ns.SetShown(ui.back, solo and not Solo().active)
    RefreshSide()
end

Refresh = function()
    if not ui.table then return end
    local lobby = not room:InRoom() and ui.mode ~= "solo"
    ns.SetShown(room.lobby, lobby)
    ns.SetShown(ui.table, not lobby)
    if lobby then room:RefreshLobby() else RefreshTable() end
end
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

local function Go(letter)
    if InSolo() then SoloLetter(letter) else PartyLetter(letter) end
end

local function SolveNow()
    local text = ui.solveBox:GetText() or ""
    ui.solveBox:SetText("")
    ui.solveBox:ClearFocus()
    if InSolo() then SoloSolve(text) else PartySolve(text) end
end

local function BuildWait(t)
    local w = ns.CreateFrame("Frame", nil, t)
    w:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -28)
    w:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 34)
    ui.wait = w
    local label = Text(w, "GameFontNormal", 8, -4)
    label:SetText("Words")
    ui.picker = Words.NewPicker(w, {
        get = function() return G.set end,
        text = function() return db.custom end,
        setText = function(text) db.custom = text Refresh() end,
        onChange = function() if room:IsHost() then room:SendState() end Refresh() end,
    })
    ui.picker:SetPoint("TOPLEFT", w, "TOPLEFT", 8, -22)
    local y = -22 - ui.picker.height - 4
    ui.turnLabel = Text(w, "GameFontHighlightSmall", 10, y - 6)
    ui.turnLabel:SetText("Time for a turn")
    ui.turnStep = ns.UI.Stepper(w, {
        list = TURN_TIMES, width = 70,
        label = function(v) return "|cffffffff" .. v .. " sec|r" end,
        get = function() return G.set.turn end,
        set = function(v) G.set.turn = v end,
        onChange = function() room:SendState() Refresh() end,
    })
    ui.turnStep:SetPoint("TOPLEFT", w, "TOPLEFT", 140, y)
    ui.wordsLabel = Text(w, "GameFontHighlightSmall", 10, y - 34)
    ui.wordsLabel:SetText("Words to play")
    ui.wordsStep = ns.UI.Stepper(w, {
        list = WORD_COUNTS, width = 70,
        label = function(v) return "|cffffffff" .. v .. "|r" end,
        get = function() return G.set.words end,
        set = function(v) G.set.words = v end,
        onChange = function() room:SendState() Refresh() end,
    })
    ui.wordsStep:SetPoint("TOPLEFT", w, "TOPLEFT", 140, y - 28)
    ui.start = ns.UI.Button(w, "Start", 140, function() HostStart() end, 26)
    ui.start:SetPoint("TOP", w, "TOP", 0, y - 64)
    ui.startNote = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.startNote:SetPoint("TOP", ui.start, "BOTTOM", 0, -6)
    ui.startNote:SetWidth(340)
end

local function BuildPlay(t)
    local p = ns.CreateFrame("Frame", nil, t)
    p:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -28)
    p:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 34)
    ui.play = p
    ui.word = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    ui.word = ns:BigFont(ui.word, 20)
    ui.word:SetPoint("TOP", p, "TOP", 0, -4)
    ui.word:SetWidth(370)

    local g = Kit.NewCanvas(p, { size = 140, owner = "gallows" })
    g.frame:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -52)
    ui.gallows = g
    ui.misses = Text(p, "GameFontNormalSmall", 8, -196, 140, "CENTER")

    -- the side: players and the log (party), or the payouts and stats (solo)
    local side = ns.CreateFrame("Frame", nil, p)
    side:SetPoint("TOPLEFT", p, "TOPLEFT", 158, -52)
    side:SetWidth(216); side:SetHeight(156)
    ui.partySide = side
    ui.players = {}
    for i = 1, MAX_PLAYERS do
        ui.players[i] = {
            name = Text(side, "GameFontHighlightSmall", 0, -(i - 1) * 12, 180),
            score = Text(side, "GameFontNormalSmall", 180, -(i - 1) * 12, 34, "RIGHT"),
        }
    end
    ui.log = {}
    for i = 1, LOG_LINES do ui.log[i] = Text(side, "GameFontDisableSmall", 0, -100 - (i - 1) * 12, 216) end
    local solo = ns.CreateFrame("Frame", nil, p)
    solo:SetPoint("TOPLEFT", p, "TOPLEFT", 158, -52)
    solo:SetWidth(216); solo:SetHeight(156)
    ui.soloSide = solo
    ui.soloInfo = Text(solo, "GameFontHighlight", 0, 0, 216)
    ui.betStep = ns.UI.Stepper(solo, {
        list = BETS, width = 90,
        label = function(v) return "|cffffffffBet " .. ns:FormatChips(v) .. "|r" end,
        get = function() return Solo().bet end,
        set = function(v) Solo().bet = v end,
        onChange = function() Refresh() end,
        locked = function() return Solo().active end,
    })
    ui.betStep:SetPoint("TOPLEFT", solo, "TOPLEFT", 0, -118)

    -- the letters, two rows of 13
    ui.letters = {}
    for i = 1, 26 do
        local letter = string.sub(LETTERS, i, i)
        local b = ns.UI.Button(p, string.upper(letter), 27, function() Go(letter) end, 24)
        local row, col = math.floor((i - 1) / 13), ns.Mod(i - 1, 13)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", 4 + col * 28.5, -216 - row * 26)
        ui.letters[i] = b
    end
    local box = ns.CreateFrame("EditBox", nil, p)
    box:SetWidth(270); box:SetHeight(22)
    box:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -272)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.8)
    box:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    box:SetScript("OnEditFocusGained", function() ui.solveFocus = true end)
    box:SetScript("OnEditFocusLost", function() ui.solveFocus = nil end)
    box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    box:SetScript("OnEnterPressed", function() SolveNow() end)
    ui.solveBox = box
    ui.solve = ns.UI.Button(p, "Solve", 90, function() SolveNow() end, 22)
    ui.solve:SetPoint("LEFT", box, "RIGHT", 6, 0)
    ui.status = Text(p, "GameFontHighlight", 6, -300, 370)
    ui.info = Text(p, "GameFontDisableSmall", 6, -318, 200)
end

local function BuildTable(panel)
    local t = ns.CreateFrame("Frame", nil, panel)
    t:SetAllPoints(panel)
    ui.table = t
    ui.hint = Text(t, "GameFontNormal", 6, -6, 300)
    ui.clock = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.clock:SetPoint("TOPRIGHT", t, "TOPRIGHT", -6, -4)
    BuildPlay(t)
    BuildWait(t)
    ui.main = ns.UI.Button(t, "Play", 140, function()
        if InSolo() then
            local s = Solo()
            if s.active then
                -- giving up costs the bet
                SoloEnd(false)
                Refresh()
            else
                SoloStart()
            end
        else
            room:Exit()
        end
    end, 24)
    ui.main:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -4, 6)
    ui.back = ns.UI.Button(t, "< Lobby", 80, function()
        ui.mode, ui.soloMsg = "lobby", nil
        ns:Sound("IG_MAINMENU_OPTION")
        Refresh()
    end, 24)
    ui.back:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 4, 6)
    ui.again = ns.UI.Button(t, "Play again", 110, function() HostStart() end, 24)
    ui.again:SetPoint("RIGHT", ui.main, "LEFT", -8, 0)
end

local RULES = "Guess the word a letter at a time. Six misses (head, body, two arms, two legs) and you're hanged.\n\n"
    .. "Solo: a word from the packs you pick here, for a bet. Get it and you're paid 2x your bet, or 3x with no misses. "
    .. "A wrong solve counts as a miss. Giving up loses the bet.\n\n"
    .. "Party (free): players take turns. A letter scores 1 for each time it's in the word, and you go again; "
    .. "a miss passes the turn. Solving scores 2 for each hidden letter (2 at least). The host picks the words, the time "
    .. "for a turn and how many words; a host using their own words doesn't guess."

function Game:Build(panel)
    db = ns:SetupGame(panel, "hangman", { stats = DEFAULT_STATS, felt = { 0.08, 0.07, 0.05, 1 } })
    db.solo = db.solo or {}
    db.solo.bet = db.solo.bet or 25
    db.soloSet = db.soloSet or { packs = "ecl" }
    db.party = db.party or {}
    ns.UI.Fill(db.party, { packs = "ecl", custom = false, turn = 20, words = 5 })
    db.custom = db.custom or ""
    G.set = db.party
    self.panel = panel
    ui.mode = "lobby"
    room:Restore(db)
    room:BuildLobby(panel, {
        title = "Hangman",
        info = "Guess the word before the gallows is done. Play solo for chips, or take turns with your group "
            .. "(free): letters and solves score points.",
        alone = "Join a party or raid to play with friends, or play solo.",
        buttons = { { "Play solo", function()
            ui.mode = "solo"
            ns:Sound("IG_MAINMENU_OPTION")
            Refresh()
        end, 130 } },
        stats = function()
            local s = db.stats
            return string.format("Solo: played %d, won %d   Party: games %d, wins %d", s.solo, s.soloWins, s.games, s.wins)
        end,
    })
    BuildTable(panel)
    if db.solo.active then ui.mode = "solo" end   -- a word in progress survives a reload

    ns:GameOptions(self, panel, {
        settings = true, rules = RULES,
        build = function(o)
            local label = Text(o.settings, "GameFontNormal", 16, -48)
            label:SetText("Solo words")
            o.picker = Words.NewPicker(o.settings, {
                get = function() return db.soloSet end,
                text = function() return "" end,
                setText = function() end,
            })
            o.picker:SetPoint("TOPLEFT", o.settings, "TOPLEFT", 16, -66)
            o.picker.own:Hide(); o.picker.own.label:Hide()
        end,
        refresh = function(o) if o.picker then o.picker:Refresh(true) end end,
    })
    Refresh()
end

function Game:OnShow()
    room:Ask()
    if Solo() and not Solo().active then Solo().bet = ns:FitList(BETS, Solo().bet) end
    Refresh()
end

function Game:OnHide()
    if ui.solveBox and ui.solveFocus then ui.solveBox:ClearFocus() end
end

-- A solo word holds its bet until it's done.
function Game:ChipsInPlay() return db ~= nil and db.solo.active == true end
function Game:Abandon()
    if db and db.solo.active then
        SoloEnd(false)
        Refresh()
    end
end

function Game:IsSeated() return room:InRoom() end
function Game:ChatTable() return room:ChatTable() end

function Game:ResetStats()
    local d = ns.db.hangman
    if not d then return end
    d.stats = {}
    ns.UI.Fill(d.stats, DEFAULT_STATS)
    if ui.table then Refresh() end
end

-- The clock: the host's turns and reveals, heartbeats, the countdown.
local ticker = ns.CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function()
    acc = acc + (arg1 or 0)
    if acc < 0.25 then return end
    acc = 0
    local now = GetTime()
    room:Tick(now)
    if room:IsHost() then HostTick(now) end
    if ui.clock and ui.table:IsShown() and not InSolo() then ui.clock:SetText(Clock()) end
end)

Game.G, Game.HS, Game.ui, Game.room = G, HS, ui, room
ns.Hangman = Game
ns:RegisterGame(Game)
