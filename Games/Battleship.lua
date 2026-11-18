-- CowCasino: Battleship. Built on the board kit (BoardKit.lua): the kit's
-- board, lobby, challenges, stakes, Resign and pickers, with Battleship's
-- own way of playing on top. The rules and the computer are in
-- BattleshipRules.lua.
--
-- A game has two phases. Placing: your fleet is on the big board (it starts
-- placed at random); click a ship to pick it up, Turn to swing it round, click
-- to put it down, Shuffle for a new random fleet, then Ready. Firing: the big
-- board is the enemy's sea, your own fleet is the small board beside it, and
-- you take turns firing one shot at a time.
--
-- Party games keep each fleet secret. When you're Ready your client sends a
-- fingerprint of your fleet (R.Hash of the fleet and a secret salt). At the
-- end both fleets are shown, and each client checks the other's against its
-- fingerprint and every answer it gave, so a player who lied about a hit is
-- caught.
--
-- Party messages (after the kit's own lobby ones): K;id;fingerprint (ready),
-- B;id;n;square (shot n), H;id;n;answer (its answer), E;id;n;side;square;answer
-- (a shot again, for a client that missed it), Y;id;shots;ready (still here,
-- and how far along), R;id;fleet;salt (the fleet, at the end).
local ns = CowCasino.ns
local Net = ns.Net
local Kit = ns.BoardKit
local R = ns.BattleshipRules

local B = setmetatable({}, { __index = Kit })
B.__index = B

local SIZE, FLEET = R.SIZE, R.FLEET
local L = Kit.LAYOUT
local SQ = L.BOARD / SIZE                    -- 24
local MINI = 7                               -- the small board's squares
local LOG_LINES = 4
local ANSWER_PAUSE = 0.35                    -- the computer "checks" before answering your shot
local WATER, WATER2 = { 0.12, 0.30, 0.50 }, { 0.10, 0.27, 0.46 }
local CELL = { left = 16, right = 17, top = 18, bottom = 19, across = 20, down = 21, miss = 22, hit = 23 }
local function Fmt(n) return ns:FormatChips(n) end

local function Cell(t, cell)
    local u, v = ns.Mod(cell, 4) / 4, math.floor(cell / 4) / 8
    t:SetTexCoord(u, u + 0.25, v, v + 0.125)
end

-- Which ship part goes on each square of a ship: { [square] = cell }.
local function ShipParts(out, cells, down)
    local n = ns.getn(cells)
    for i, c in ipairs(cells) do
        if i == 1 then out[c] = down and CELL.top or CELL.left
        elseif i == n then out[c] = down and CELL.bottom or CELL.right
        else out[c] = down and CELL.down or CELL.across end
    end
end

local function FleetParts(fleet, skip)
    local out = {}
    for k = 1, ns.getn(FLEET) do
        if k ~= skip and fleet[k] and fleet[k].start then
            ShipParts(out, R.ShipCells(fleet, k), fleet[k].down)
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The game's state
---------------------------------------------------------------------------
function B:Shooter(g) return ns.Mod(ns.getn(g.events), 2) == 0 and "a" or "b" end

function B:Turn(g)
    if g.phase ~= "play" then return "none" end
    return self:Shooter(g) == g.me and "me" or "them"
end

-- The shots one side has fired: { [square] = answer }, and the squares hit.
function B:Shots(g, by)
    local shots, hits = {}, {}
    for _, e in ipairs(g.events) do
        if e.by == by then
            shots[e.sq] = e.res
            if e.res ~= "m" then hits[e.sq] = true end
        end
    end
    return shots, hits
end

function B:Save()
    local g = self.S.game
    if not g then return end
    local ev = {}
    for _, e in ipairs(g.events) do table.insert(ev, e.by .. "," .. e.sq .. "," .. e.res) end
    local rec = { me = g.me, fleet = R.EncodeFleet(g.fleet), phase = g.phase, events = ev }
    if g.kind == "solo" then
        rec.stake, rec.level, rec.cfleet = g.stake, g.level, g.cfleet and R.EncodeFleet(g.cfleet)
        self.db.solo = rec
    else
        rec.id, rec.opp, rec.salt, rec.commit, rec.theirs = g.id, g.opp, g.salt, g.commit, g.theirCommit
        rec.ready = g.ready
        rec.pending = g.pending and (g.pending.n .. "," .. g.pending.sq) or nil
        self.db.party = rec
    end
end

function B:Load(rec, kind)
    local g = { kind = kind, me = rec.me, phase = rec.phase or "place", events = {}, heard = GetTime(), pinged = 0 }
    g.fleet = R.DecodeFleet(rec.fleet or "") or R.RandomFleet()
    for _, text in ipairs(rec.events or {}) do
        local p = Net.Split(text, ",")
        table.insert(g.events, { by = p[1], sq = tonumber(p[2]), res = p[3] })
    end
    if kind == "solo" then
        g.stake, g.level = rec.stake, rec.level or 2
        g.cfleet = rec.cfleet and R.DecodeFleet(rec.cfleet) or R.RandomFleet()
    else
        g.id, g.opp, g.salt, g.commit, g.theirCommit, g.ready = rec.id, rec.opp, rec.salt, rec.commit, rec.theirs, rec.ready
        if rec.pending then
            local p = Net.Split(rec.pending, ",")
            g.pending = { n = tonumber(p[1]), sq = tonumber(p[2]) }
        end
    end
    return g
end

---------------------------------------------------------------------------
-- Starting, placing, firing, ending
---------------------------------------------------------------------------
function B:Start(kind, me, opp, id, stake, level)
    local g = { kind = kind, me = me, opp = opp, id = id, stake = stake, level = level, phase = "place",
        fleet = R.RandomFleet(), events = {}, heard = GetTime(), pinged = GetTime() }
    local S = self.S
    S.game, S.over, S.pick, S.down = g, nil, nil, false
    local s = self.db.stats
    if kind == "solo" then
        s.wagered = s.wagered + stake
    else
        s.partyGames = s.partyGames + 1
        if ns.Dealer then ns.Dealer:SetPlayer(self, opp) end
    end
    s.games = s.games + 1
    self:Save()
    ns:PlayGameSound(self.db, "newHand")
    self:SetStatus("Place your fleet: click a ship to move it, then Ready.")
    if kind == "solo" then
        self:Say("battleshipStart", { stake = Fmt(stake) }, "Ships in the water! Good hunting.")
    else
        self:Say("battleshipParty", { name = opp }, "A friendly game. Good luck to you both!")
    end
    self:Refresh()
end

-- The fleet's in place: start firing (solo), or say so (party).
function B:Ready()
    local g = self.S.game
    if not g or g.phase ~= "place" or g.ready or not R.Complete(g.fleet) then return end
    self.S.pick = nil
    if g.kind == "solo" then
        g.cfleet = R.RandomFleet()
        self:BeginPlay(g)
        return
    end
    g.ready = true
    g.salt = tostring(math.random(100000, 999999)) .. tostring(math.random(100000, 999999))
    g.commit = R.Hash(R.EncodeFleet(g.fleet) .. "/" .. g.salt)
    Net:Send(self:Msg({ "K", g.id, g.commit }))
    if g.theirCommit then
        self:BeginPlay(g)
    else
        self:SetStatus("Ready. Waiting for " .. g.opp .. " to place their fleet...")
        self:Save()
        self:Refresh()
    end
end

function B:BeginPlay(g)
    g.phase = "play"
    self:Save()
    if self:Turn(g) == "me" then
        self:SetStatus("Your shot: pick a square on the enemy's sea.")
    else
        self:SetStatus(g.kind == "solo" and "The computer fires first..." or (g.opp .. " fires first..."))
        if g.kind == "solo" then g.thinkAt = GetTime() + Kit.THINK_PAUSE end
    end
    ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    self:Refresh()
end

function B:Fire(s)
    local g = self.S.game
    if not g or self:Turn(g) ~= "me" or g.pending then return end
    local mine = self:Shots(g, g.me)
    if mine[s] then return end
    g.pending = { n = ns.getn(g.events) + 1, sq = s }
    if g.kind == "solo" then
        g.answerAt = GetTime() + ANSWER_PAUSE
    else
        Net:Send(self:Msg({ "B", g.id, g.pending.n, s }))
        self:Save()
    end
    self:SetStatus("Firing at " .. R.Name(s) .. "...")
    self:Refresh()
end

-- A shot and its answer go in the record; the turn passes (or the game ends).
function B:Resolve(by, s, res)
    local g = self.S.game
    table.insert(g.events, { by = by, sq = s, res = res })
    if by == g.me then g.pending = nil end
    self:Save()
    local kind, k = R.Parse(res)
    local mineShot = by == g.me
    local who = mineShot and "You" or (g.kind == "solo" and "The computer" or g.opp)
    local text
    if kind == "m" then
        text = who .. " fired at " .. R.Name(s) .. ": a miss."
    elseif kind == "h" then
        text = who .. " fired at " .. R.Name(s) .. ": a hit!"
    else
        local name = FLEET[k] and FLEET[k].name or "ship"
        text = mineShot and ("You sank their " .. name .. "!") or (who .. " sank your " .. name .. "!")
    end
    if not mineShot then ns:PlayGameSound(self.db, "move") end
    if kind == "w" then
        self:Finish(by, mineShot and "you sank the whole fleet" or "your whole fleet is sunk")
        return
    end
    if kind ~= "m" then ns:Sound(mineShot and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION") end
    if self:Turn(g) == "me" then
        self:SetStatus(text .. " Your shot.")
    else
        self:SetStatus(text)
        if g.kind == "solo" then g.thinkAt = GetTime() + Kit.THINK_PAUSE end
    end
    self:Refresh()
end

-- The game's over: the kit settles it; Battleship shows both fleets and, in
-- a party game, reveals ours so the other side can check it.
function B:Finish(winner, why)
    local g = self.S.game
    if not g then return end
    self.S.pick = nil
    Kit.Finish(self, winner, why)
    local over = self.S.over
    if not over then return end
    over.bs = g
    if g.kind == "solo" then
        over.theirFleet = g.cfleet
    elseif g.ready and g.salt then
        Net:Send(self:Msg({ "R", g.id, R.EncodeFleet(g.fleet), g.salt }))
    end
    if g.kind == "party" and g.theirFleet then self:Verify(over) end
    self:Refresh()
end

-- Checks the other player's revealed fleet against its fingerprint and every
-- answer they gave; adds the verdict to the status.
function B:Verify(over)
    local g = over.bs
    local fleet, salt = g.theirFleet, g.theirSalt
    local ok, why = true, nil
    if not g.theirCommit or R.Hash(R.EncodeFleet(fleet) .. "/" .. salt) ~= g.theirCommit then
        ok, why = false, "their fleet doesn't match the one they started with"
    else
        local hits = {}
        for _, e in ipairs(g.events) do
            if e.by == g.me then
                local want = R.Answer(fleet, hits, e.sq)
                if R.Parse(want) ~= R.Parse(e.res) then
                    ok, why = false, "their answer at " .. R.Name(e.sq) .. " was wrong"
                    break
                end
                if want ~= "m" then hits[e.sq] = true end
            end
        end
    end
    over.theirFleet = fleet
    local line = ok and ("|cff66ff66Fleet check: " .. g.opp .. "'s ships match every answer.|r")
        or ("|cffff5050Fleet check failed: " .. why .. "!|r")
    if not over.checked then
        over.checked = true
        self.ui.status:SetText((self.S.statusText or "") .. "\n" .. line)
    end
end

---------------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------------
function B:Click(s)
    local g = self.S.game
    if not g then return end
    if g.phase == "place" then
        if g.ready then return end
        local S = self.S
        if S.pick then
            local ship = g.fleet[S.pick]
            if R.Fits(g.fleet, S.pick, s, S.down) then
                ship.start, ship.down = s, S.down
                S.pick = nil
                ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
                self:Save()
            end
        else
            local k = R.ShipAt(g.fleet, s)
            if k then
                S.pick, S.down = k, g.fleet[k].down
                g.fleet[k].start = nil
                ns:Sound("IG_MAINMENU_OPTION")
            end
        end
        self:Refresh()
        return
    end
    self:Fire(s)
end

-- The big button: Ready while placing, otherwise as the kit has it.
function B:Go()
    local g = self.S.game
    if g and g.phase == "place" then self:Ready() return end
    Kit.Go(self)
end

function B:Hover(s)
    self.S.hover = s
    local g = self.S.game
    if g and g.phase == "place" and self.S.pick then self:DrawBoards() end
end

function B:Turn90()
    local g, S = self.S.game, self.S
    if not g or g.phase ~= "place" or g.ready then return end
    if S.pick then
        S.down = not S.down
    else
        -- no ship in hand: turn the last one picked... or nothing to do
        return
    end
    self:Refresh()
end

function B:Shuffle()
    local g = self.S.game
    if not g or g.phase ~= "place" or g.ready then return end
    g.fleet = R.RandomFleet()
    self.S.pick = nil
    self:Save()
    ns:Sound("IG_MAINMENU_OPTION")
    self:Refresh()
end

---------------------------------------------------------------------------
-- The computer
---------------------------------------------------------------------------
function B:Think()
    local g = self.S.game
    if not g or g.kind ~= "solo" or g.phase ~= "play" then return end
    -- answering your shot
    if g.pending and g.answerAt and GetTime() >= g.answerAt then
        local _, hits = self:Shots(g, g.me)
        local s = g.pending.sq
        g.answerAt = nil
        self:Resolve(g.me, s, R.Answer(g.cfleet, hits, s))
        return
    end
    -- its own shot
    if self:Turn(g) == "them" and GetTime() >= (g.thinkAt or 0) then
        local them = R.Other(g.me)
        local shots = self:Shots(g, them)
        local sunk = {}
        for _, res in pairs(shots) do
            local kind, k = R.Parse(res)
            if kind == "s" or kind == "w" then sunk[k] = true end
        end
        local s = R.ChooseShot({ shots = shots, sunk = sunk }, g.level)
        local _, hits = self:Shots(g, them)
        self:Resolve(them, s, R.Answer(g.fleet, hits, s))
    end
end

---------------------------------------------------------------------------
-- Party messages
---------------------------------------------------------------------------
function B:Ping(g)
    g.pinged = GetTime()
    Net:Send(self:Msg({ "Y", g.id, ns.getn(g.events), g.ready and 1 or 0 }), self.def.tag .. "-Y")
    -- anything of ours still waiting on them goes again
    if g.phase == "place" and g.ready then Net:Send(self:Msg({ "K", g.id, g.commit })) end
    if g.pending then Net:Send(self:Msg({ "B", g.id, g.pending.n, g.pending.sq })) end
end

-- Their shot at square s (shot number n): answer it.
function B:TheirShot(g, n, s)
    local count = ns.getn(g.events)
    if n <= count then
        local e = g.events[n]          -- answered already: say it again
        if e and e.by ~= g.me then Net:Send(self:Msg({ "H", g.id, n, e.res })) end
        return
    end
    if n ~= count + 1 or self:Turn(g) ~= "them" or not s or s < 1 or s > SIZE * SIZE then return end
    local them = R.Other(g.me)
    local shots, hits = self:Shots(g, them)
    if shots[s] then return end
    local res = R.Answer(g.fleet, hits, s)
    Net:Send(self:Msg({ "H", g.id, n, res }))
    self:Resolve(them, s, res)
end

function B:OnGameMessage(sender, kind, f, g)
    local n = tonumber(f[4])
    if kind == "K" then
        local first = not g.theirCommit
        g.theirCommit = f[4]
        if g.ready and first then Net:Send(self:Msg({ "K", g.id, g.commit })) end
        if g.ready and g.phase == "place" then self:BeginPlay(g) else self:Save(); self:Refresh() end
    elseif kind == "B" then
        if g.phase == "place" and g.ready and g.theirCommit then self:BeginPlay(g) end
        if g.phase == "play" then self:TheirShot(g, n, tonumber(f[5])) end
    elseif kind == "H" then
        if g.pending and n == g.pending.n and f[5] then self:Resolve(g.me, g.pending.sq, f[5]) end
    elseif kind == "E" then
        -- a shot we missed, sent again
        if n == ns.getn(g.events) + 1 and g.phase == "play" then
            local by, s, res = f[5], tonumber(f[6]), f[7]
            if by == g.me and g.pending and g.pending.sq == s then
                self:Resolve(g.me, s, res)
            elseif by == R.Other(g.me) then
                local _, hits = self:Shots(g, by)
                self:Resolve(by, s, R.Answer(g.fleet, hits, s))   -- (our own answer, worked out again)
            end
        end
    elseif kind == "Y" then
        local theirs = n or 0
        local count = ns.getn(g.events)
        if theirs < count then
            for i = theirs + 1, count do
                local e = g.events[i]
                Net:Send(self:Msg({ "E", g.id, i, e.by, e.sq, e.res }))
            end
        elseif theirs > count then
            self:Ping(g)
        end
        if g.ready then Net:Send(self:Msg({ "K", g.id, g.commit })) end
        -- they're back (or just checking in): a shot still waiting goes again
        if g.pending then Net:Send(self:Msg({ "B", g.id, g.pending.n, g.pending.sq })) end
    elseif kind == "R" then
        g.theirFleet, g.theirSalt = R.DecodeFleet(f[4] or ""), f[5]
    else
        Kit.OnGameMessage(self, sender, kind, f, g)
    end
end

-- The other player's fleet, after the game's over here.
function B:OnLateMessage(sender, kind, f)
    local over = self.S.over
    if kind ~= "R" or not over or not over.bs or over.bs.id ~= f[3] or over.bs.opp ~= sender then return end
    local fleet = R.DecodeFleet(f[4] or "")
    if not fleet then return end
    over.bs.theirFleet, over.bs.theirSalt = fleet, f[5]
    self:Verify(over)
    if self:Shown() then self:DrawBoards() end
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
-- The big board and the small one.
function B:DrawBoards()
    local ui, S = self.ui, self.S
    local g = S.game or (S.over and S.over.bs)
    local over = S.game == nil and S.over
    local placing = S.game and g.phase == "place"
    local parts, markers, washes = {}, {}, {}
    if placing then
        parts = FleetParts(g.fleet, S.pick)
        if S.pick and S.hover then
            local cells = R.Cells(S.hover, FLEET[S.pick].size, S.down)
            local fits = R.Fits(g.fleet, S.pick, S.hover, S.down)
            if cells then
                ShipParts(parts, cells, S.down)
                for _, c in ipairs(cells) do washes[c] = fits and "ok" or "bad" end
            else
                washes[S.hover] = "bad"
            end
        end
    elseif g then
        -- the enemy's sea: our shots, and the ships we sank (all of them once it's over)
        local shots = self:Shots(g, g.me)
        for sq, res in pairs(shots) do
            markers[sq] = res == "m" and CELL.miss or CELL.hit
            local kind, k, ship = R.Parse(res)
            if (kind == "s" or kind == "w") and ship then
                ShipParts(parts, R.Cells(ship.start, FLEET[k].size, ship.down) or {}, ship.down)
            end
        end
        if over and over.theirFleet then
            for k = 1, ns.getn(FLEET) do
                local cells = R.ShipCells(over.theirFleet, k)
                if cells then ShipParts(parts, cells, over.theirFleet[k].down) end
            end
        end
        if g.pending then washes[g.pending.sq] = "aim" end
    end
    local last
    if g and not placing then
        for i = ns.getn(g.events), 1, -1 do
            if g.events[i].by == g.me then last = g.events[i].sq break end
        end
    end
    for s = 1, SIZE * SIZE do
        local b = ui.squares[s]
        local row, col = R.RowCol(s)
        local c = ns.Mod(row + col, 2) == 0 and WATER or WATER2
        b.bg:SetTexture(c[1], c[2], c[3], 1)
        if parts[s] then Cell(b.piece, parts[s]); b.piece:Show() else b.piece:Hide() end
        if markers[s] then Cell(b.top, markers[s]); b.top:Show() else b.top:Hide() end
        local w = washes[s]
        if w then
            local col4 = (w == "ok" and { 0.2, 0.9, 0.3, 0.35 }) or (w == "bad" and { 0.95, 0.15, 0.1, 0.45 }) or { 1, 0.82, 0, 0.45 }
            b.mark:SetTexture(col4[1], col4[2], col4[3], col4[4]); b.mark:Show()
        elseif s == last then
            b.mark:SetTexture(1, 0.9, 0.3, 0.3); b.mark:Show()
        else
            b.mark:Hide()
        end
    end

    -- the small board: our fleet and their shots
    local myParts = g and FleetParts(g.fleet, placing and S.pick or nil) or {}
    local theirs = g and self:Shots(g, R.Other(g.me)) or {}
    for s = 1, SIZE * SIZE do
        local t = ui.mini[s]
        local res = theirs[s]
        if res and res ~= "m" then t:SetTexture(0.95, 0.2, 0.1, 1)
        elseif res then t:SetTexture(0.85, 0.92, 1, 0.9)
        elseif myParts[s] then t:SetTexture(0.62, 0.66, 0.72, 1)
        else t:SetTexture(WATER[1], WATER[2], WATER[3], 1) end
    end
end

function B:Refresh()
    local ui, S, db = self.ui, self.S, self.db
    if not ui.board then return end
    ns:UpdateChipsDisplay()
    local g = S.game
    local solo = self:Mode() == "solo"
    ns.SetEnabled(ui.soloTab, g == nil and not S.posted and not solo)
    ns.SetEnabled(ui.partyTab, g == nil and solo)
    ui.soloTab:SetText((solo and "|cffffff00" or "") .. "Vs the computer")
    ui.partyTab:SetText((not solo and "|cffffff00" or "") .. "Party game")
    self:DrawBoards()

    -- the side column
    if g then
        local text
        if g.phase == "place" then
            text = g.ready and "Waiting..." or "|cff66ff66Place ships|r"
        elseif self:Turn(g) == "me" then
            text = g.pending and "Firing..." or "|cff66ff66Your shot|r"
        else
            text = "Their shot"
        end
        ui.turn:SetText(text)
        ui.against:SetText(g.kind == "solo" and ("vs " .. R.LEVELS[g.level].name .. " AI\nfor " .. Fmt(g.stake))
            or ("vs " .. g.opp .. "\n(free)"))
    else
        ui.turn:SetText(S.over and "Game over" or "")
        ui.against:SetText("")
    end
    -- the latest shots, newest last
    local list = {}
    local ev = (g and g.events) or (S.over and S.over.bs and S.over.bs.events) or {}
    local me = (g and g.me) or (S.over and S.over.bs and S.over.bs.me)
    for _, e in ipairs(ev) do
        local kind = R.Parse(e.res)
        local word = (kind == "m" and "miss") or (kind == "h" and "hit") or "sunk"
        table.insert(list, (e.by == me and "You " or "Foe ") .. R.Name(e.sq) .. " " .. word)
    end
    local n = ns.getn(list)
    for i = 1, LOG_LINES do ui.log[i]:SetText(list[n - LOG_LINES + i] or "") end
    ns.SetShown(ui.logBg, n > 0)

    self:RefreshLobby(not solo and not g)

    -- the bottom: pickers between games; Turn / Shuffle while placing
    local placing = g and g.phase == "place" and not g.ready
    for _, p in ipairs(ui.pickers) do p:Refresh() end
    ns.SetShown(ui.side, g == nil)
    ns.SetShown(ui.stake, solo and g == nil)
    ns.SetShown(ui.level, solo and g == nil)
    ns.SetShown(ui.turn90, placing)
    ns.SetShown(ui.shuffle, placing)
    if placing then ns.SetEnabled(ui.turn90, S.pick ~= nil) end
    ui.draw:Hide()
    if g then
        ui.resign:Show()
        self:ResignButton()
        ui.go:ClearAllPoints()
        ui.resign:ClearAllPoints()
        if g.phase == "place" then
            -- Ready and Resign side by side
            ui.go:Show()
            ui.go:SetText(g.ready and "Waiting..." or "Ready")
            ns.SetEnabled(ui.go, not g.ready and R.Complete(g.fleet))
            ui.go:SetWidth(120)
            ui.go:SetPoint("BOTTOMRIGHT", self.panel, "BOTTOM", -4, 18)
            ui.resign:SetPoint("BOTTOMLEFT", self.panel, "BOTTOM", 4, 19)
        else
            ui.go:Hide()
            ui.resign:SetPoint("BOTTOM", self.panel, "BOTTOM", 0, 19)
        end
    else
        ui.resign:Hide()
        ui.go:Show()
        ui.go:ClearAllPoints()
        ui.go:SetWidth(180)
        ui.go:SetPoint("BOTTOM", self.panel, "BOTTOM", 0, 18)
        if solo then
            ui.go:SetText("Play for " .. Fmt(db.stake))
            ns.SetEnabled(ui.go, ns.db.chips >= db.stake)
        elseif S.posted then
            ui.go:SetText("Withdraw challenge")
            ns.SetEnabled(ui.go, true)
        else
            ui.go:SetText("Challenge the group")
            ns.SetEnabled(ui.go, Net:InGroup() and not S.accepting)
        end
    end
    ui.stats:SetText(self:StatsText())
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function B:BuildSide(panel)
    local ui = self.ui
    local x, w = L.SIDE_X, L.SIDE_W
    ui.turn = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.turn:SetPoint("TOPLEFT", panel, "TOPLEFT", x, L.BY - 2)
    ui.turn:SetWidth(w)
    ui.turn:SetJustifyH("LEFT")
    ui.against = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.against:SetPoint("TOPLEFT", ui.turn, "BOTTOMLEFT", 0, -4)
    ui.against:SetWidth(w)
    ui.against:SetJustifyH("LEFT")
    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ui.status:SetPoint("TOPLEFT", ui.against, "BOTTOMLEFT", 0, -8)
    ui.status:SetWidth(w)
    ui.status:SetJustifyH("LEFT")

    -- the small board (our fleet), above the shot list at the column's foot
    local bottom = L.BY - L.BOARD
    local mini = ns.CreateFrame("Frame", nil, panel)
    mini:SetWidth(SIZE * MINI); mini:SetHeight(SIZE * MINI)
    mini:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", x + 2, bottom + LOG_LINES * 13 + 12)
    local edge = mini:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", mini, "TOPLEFT", -2, 2)
    edge:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", 2, -2)
    edge:SetTexture(0.05, 0.05, 0.08, 1)
    ui.mini = {}
    for s = 1, SIZE * SIZE do
        local row, col = R.RowCol(s)
        local t = mini:CreateTexture(nil, "ARTWORK")
        t:SetWidth(MINI - 1); t:SetHeight(MINI - 1)
        t:SetPoint("TOPLEFT", mini, "TOPLEFT", col * MINI, -row * MINI)
        ui.mini[s] = t
    end
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("BOTTOMLEFT", mini, "TOPLEFT", 0, 3)
    label:SetText("Your fleet")
    ui.miniFrame = mini

    ui.logBg = panel:CreateTexture(nil, "BORDER")
    ui.logBg:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", x - 2, bottom)
    ui.logBg:SetWidth(w + 4); ui.logBg:SetHeight(LOG_LINES * 13 + 6)
    ui.logBg:SetTexture(0, 0, 0, 0.35)
    ui.log = {}
    for i = 1, LOG_LINES do
        local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", x + 1, bottom + 3 + (LOG_LINES - i) * 13)
        t:SetWidth(w)
        t:SetJustifyH("LEFT")
        ui.log[i] = t
    end
    self.logLines = LOG_LINES
end

function B:Build(panel)
    local def, game = self.def, self
    self.db = ns:SetupGame(panel, self.id, {
        defaults = { mode = "solo", stake = 50, level = 2, side = "a" },
        stats = { games = 0, wins = 0, losses = 0, draws = 0, partyGames = 0, wagered = 0, won = 0, biggestWin = 0 },
        sounds = { { key = "move", label = "The other side fires", default = "tick" } },
        felt = def.felt,
    })
    local ui = self.ui
    ui.soloTab = ns.UI.Button(panel, "Vs the computer", 150, function() game:SetMode("solo") end)
    ui.soloTab:SetPoint("TOPRIGHT", panel, "TOP", -4, -4)
    ui.partyTab = ns.UI.Button(panel, "Party game", 150, function() game:SetMode("party") end)
    ui.partyTab:SetPoint("TOPLEFT", panel, "TOP", 4, -4)
    self:BuildBoard(panel)
    -- a second layer on each square, for the hit and miss markers
    for s = 1, SIZE * SIZE do
        local b = ui.squares[s]
        b.top = b:CreateTexture(nil, "OVERLAY")
        b.top:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
        b.top:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
        b.top:SetTexture(Kit.ATLAS)
        b.top:Hide()
        local row, col = R.RowCol(s)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ui.board, "TOPLEFT", col * SQ, -row * SQ)
    end
    for i = 1, SIZE do
        ui.files[i]:SetText(i)
        ui.ranks[i]:SetText(string.sub("ABCDEFGHIJ", i, i))
    end
    self:BuildLobby(panel)
    self:BuildSide(panel)
    self:BuildBottom(panel)
    ui.turn90 = ns.UI.Button(panel, "Turn", 80, function() game:Turn90() end)
    ui.turn90:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -4, 50)
    ui.shuffle = ns.UI.Button(panel, "Shuffle", 80, function() game:Shuffle() end)
    ui.shuffle:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 4, 50)
    ui.turn90:Hide(); ui.shuffle:Hide()
    self.panel = panel
    ui.options = ns:GameOptions(self, panel, {
        rules = def.rulesText,
        onReset = function() game:ResetStats() end,
        db = function() return game.db end,
        sounds = { { key = "move", label = "The other side fires", default = "tick" } },
    })

    -- a game from before a reload
    local db = self.db
    if db.party then
        local g = self:Load(db.party, "party")
        self.S.game = g
        self:Ping(g)
        self:SetStatus("Welcome back - your game with " .. tostring(g.opp) .. " is still on.")
    elseif db.solo then
        local g = self:Load(db.solo, "solo")
        self.S.game = g
        g.thinkAt = GetTime() + Kit.THINK_PAUSE
        if g.phase == "play" and g.pending == nil then
            -- a shot of ours that wasn't answered before the reload is simply gone
        end
        self:SetStatus("Welcome back - your game is still on.")
    else
        self:Welcome()
    end
    self:Refresh()
end

function B:Welcome()
    if self:Mode() == "party" then
        Net:Send(self:Msg({ "Q" }))
        self:SetStatus(Net:InGroup() and "Challenge your group, or take a challenge." or "Join a party or raid to play your friends.")
    else
        self:SetStatus("Pick a stake, a level and who fires first, then Play.")
    end
end

function B:Tick()
    Kit.Tick(self)
    local g = self.S.game
    -- a party game's opening: keep telling the other side we're ready
    if g and g.kind == "party" and g.phase == "place" and g.ready and not g.theirCommit
        and GetTime() - (g.pinged or 0) >= 5 then
        self:Ping(g)
    end
end

---------------------------------------------------------------------------
local Battleship = Kit.New({
    id = "battleship",
    name = "Battleship",
    description = "Hide your fleet, then hunt theirs down.\n|cff66ccffSupports Multiplayer|r",
    icon = "Interface\\AddOns\\CowCasino\\Art\\BattleshipIcon",   -- painted (dev/art-src/make_game_icons.py)
    dealer = { idle = "Battleship? Hide your boats, kid. Then sink theirs." },
    tag = "BS",
    rules = R,
    cols = SIZE, rows = SIZE, sq = SQ,
    felt = { 0.05, 0.09, 0.14, 0.94 },
    rulesText = "Battleship on a 10 x 10 sea. Each side has a Carrier (5), Battleship (4), Cruiser (3), "
        .. "Submarine (3) and Destroyer (2).\n\n"
        .. "First, place your fleet: it starts placed at random. Click a ship to pick it up, Turn to swing it "
        .. "round, and click where it goes (green: it fits). Shuffle gives a new random fleet. Then Ready.\n\n"
        .. "Then take turns firing one shot at a time at the enemy's sea (the big board). Your own fleet and "
        .. "their shots are on the small board. Sink every ship to win.\n\n"
        .. "Vs the computer: pick a stake, Easy, Medium or Hard, and who fires first. A win pays double. "
        .. "Party game: free. Each fleet stays secret; at the end both are shown, and CowCasino checks the "
        .. "other player's fleet against every answer they gave (a fingerprint sent at the start keeps it "
        .. "honest).\n\n"
        .. "Resign asks again: click Confirm once its 3 seconds are up.",
}, B)

ns:RegisterGame(Battleship)
