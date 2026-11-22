-- CowCasino: the board kit. Everything Chess and Checkers share: the 8x8
-- board and its pieces, picking moves with the mouse, the move list, a
-- computer opponent (for a game whose rules have one), and party games
-- (challenges, moves over the network, draw offers, resigning, and picking
-- a game back up after a reload).
--
-- A game is ns.BoardKit.New(def), registered like any other. def:
--   id, name, description, icon, dealer   as for any game
--   tag        the first field of its party messages ("CK")
--   rules      the rules module: first, sides, names, New, Moves, Apply,
--              Result, MoveText, Encode, Same, PieceAt, SideOf, Dark, and
--              optionally Key (repeats), CheckSquare, ChoiceLabel, and
--              LEVELS + ChooseMove (a computer opponent)
--   atlas      piece -> cell (0-15) in Art\BoardPieces
--   light, dark, felt   colors of the squares and the table
--   rulesText  the Rules tab
--   noun       what a single game is called in messages ("game")
--   taken      piece -> value: show the captured pieces beside the board
--   sets       other piece sets to pick from in Options > Settings (the first
--              choice is always "Classic": atlas, light and dark above). Each:
--              key, name, texture (an atlas laid out like atlas's cells),
--              rows (the texture's rows of cells, 4 or 8), light, dark,
--              names (side -> name, in place of the rules' names), note (a
--              line under the picker), emblems (piece -> { texture, l, r, t,
--              b }: a picture drawn over that piece, e.g. a faction emblem)
--
-- Party games are free (bragging rights): nobody's chips move. A game
-- against the computer has a stake: a win pays double, a draw gives it back.
-- Rules modules work on squares 1..64 (row * 8 + col + 1, row 0 at the
-- bottom for the side that moves first). A move has a path (the squares the
-- piece visits); the player clicks them in turn.
local ns = CowCasino.ns
local Net = ns.Net

local Kit = {}
Kit.__index = Kit
ns.BoardKit = Kit

-- Board games use the whole game area (380 x 380: the window's "wide" layout).
local PANEL_W      = 380
local SQ, BX, BY   = 32, 18, -32       -- square size; the board's top-left in the panel
local SIDE_X       = BX + 8 * SQ + 10  -- the column to the right of the board
local SIDE_W       = PANEL_W - SIDE_X - 4
local LOG_LINES    = 9       -- move list lines (5 when the captured pieces show too)
local TAKEN_SIZE, TAKEN_PER_ROW = 12, 5   -- the captured-piece icons (def.taken)
local ATLAS        = "Interface\\AddOns\\CowCasino\\Art\\BoardPieces"   -- 4 x 8 cells of 64 (see make_board_pieces.py)
Kit.ATLAS = ATLAS
local STAKES       = { 10, 25, 50, 100, 250, 500, 1000, 5000 }
local THINK_PAUSE  = 0.6     -- seconds before the computer starts thinking
local THINK_STEPS  = 3       -- search slices per frame
local OFFER_EVERY  = 20
local OFFER_TIMEOUT = 60
local PING_EVERY   = 30      -- a party game says "still here" this often
local QUIET_LIMIT  = 90      -- nothing heard this long: the game can be called off
local RESIGN_DELAY = 3       -- Resign asks again; the second click only counts after this (the default; Settings)
local RESIGN_WINDOW = 5      -- ...and the question goes away this long after that
-- for games built on the kit with their own screens (Battleship)
Kit.LAYOUT = { BX = BX, BY = BY, SIDE_X = SIDE_X, SIDE_W = SIDE_W, BOARD = 8 * SQ, PANEL_W = PANEL_W }
Kit.STAKES, Kit.THINK_PAUSE, Kit.PING_EVERY = STAKES, THINK_PAUSE, PING_EVERY
local EXTRA_SOUNDS = { { key = "move", label = "The other side moves", default = "tick" } }
local DEFAULT_STATS = { games = 0, wins = 0, losses = 0, draws = 0, partyGames = 0, wagered = 0, won = 0, biggestWin = 0 }

local Fill = ns.UI.Fill
local MakeButton = ns.UI.Button
local function Fmt(n) return ns:FormatChips(n) end
local function NewId() return tostring(math.random(100000, 999999)) end

---------------------------------------------------------------------------
-- Positions from a list of moves
---------------------------------------------------------------------------
-- The squares a move takes pieces from.
local function Captures(m)
    if not m then return nil end
    if m.caps then
        if ns.getn(m.caps) > 0 then return m.caps end
        return nil
    end
    if m.cap then return { m.cap } end
    return nil
end
Kit.Captures = Captures
-- Finds the legal move a wire string stands for.
function Kit:Decode(pos, text)
    local R = self.def.rules
    for _, m in ipairs(R.Moves(pos)) do
        if R.Encode(m) == text then return m end
    end
end

-- Plays the game's moves from the start: g.pos, g.keys, g.last, g.log.
-- Returns false if a move doesn't fit (the list is cut there).
function Kit:Replay(g)
    local R = self.def.rules
    g.pos, g.keys, g.last, g.log = R.New(), {}, nil, {}
    g.taken = { [R.sides[1]] = {}, [R.sides[2]] = {} }     -- pieces each side has taken
    if R.Key then g.keys[R.Key(g.pos)] = 1 end
    local list = g.moves
    g.moves = {}
    for i, text in ipairs(list) do
        local m = self:Decode(g.pos, text)
        if not m then return false end
        self:Advance(g, m)
    end
    return true
end

-- One move on the board (no checks, no messages).
function Kit:Advance(g, m)
    local R = self.def.rules
    local text = R.MoveText(g.pos, m)
    local n = ns.getn(g.moves)
    if ns.Mod(n, 2) == 0 then
        table.insert(g.log, string.format("%d. %s", math.floor(n / 2) + 1, text))
    else
        local i = ns.getn(g.log)
        g.log[i] = g.log[i] .. "  " .. text
    end
    table.insert(g.moves, R.Encode(m))
    local caps = Captures(m)
    if caps then
        for _, c in ipairs(caps) do
            local piece = R.PieceAt(g.pos, c)
            if piece then table.insert(g.taken[g.pos.turn], piece) end
        end
    end
    g.pos = R.Apply(g.pos, m)
    g.last = m
    if R.Key then
        local k = R.Key(g.pos)
        g.keys[k] = (g.keys[k] or 0) + 1
    end
end

function Kit:Turn(g)
    if g.pos.turn == g.me then return "me" end
    return "them"
end

---------------------------------------------------------------------------
-- Talking
---------------------------------------------------------------------------
function Kit:Msg(parts) return self.def.tag .. ";" .. table.concat(parts, ";") end

function Kit:Say(event, vars, fallback, quiet)
    if ns.Dealer then ns.Dealer:React(self, event, vars, nil, fallback, quiet) end
end

function Kit:SetStatus(text, r, g, b)
    self.S.statusText = text
    if not self.ui.status then return end
    self.ui.status:SetText(text or "")
    self.ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

function Kit:SideName(side)
    local set = self:PieceSet()
    return (set.names and set.names[side]) or self.def.rules.names[side] or "?"
end

-- The piece set in use (Options > Settings), and where a piece's picture is in it.
function Kit:PieceSets()
    local def = self.def
    if not self.sets then
        self.sets = { { key = "classic", name = "Classic", texture = ATLAS, rows = 8, light = def.light, dark = def.dark } }
        for _, set in ipairs(def.sets or {}) do table.insert(self.sets, set) end
    end
    return self.sets
end

function Kit:PieceSet()
    local sets = self:PieceSets()
    local key = self.db and self.db.pieceSet
    for _, set in ipairs(sets) do if set.key == key then return set end end
    return sets[1]
end

-- Puts piece's picture from the set on texture t (false: there's none).
function Kit:PaintPiece(t, piece, set)
    local cell = piece and self.def.atlas[piece]
    if not cell then return false end
    set = set or self:PieceSet()
    local rows = set.rows or 8
    local u, v = ns.Mod(cell, 4) / 4, math.floor(cell / 4) / rows
    t:SetTexture(set.texture)
    t:SetTexCoord(u, u + 0.25, v, v + 1 / rows)
    return true
end

function Kit:OppName(g)
    if g.kind == "solo" then return "the computer" end
    return g.opp or "?"
end

function Kit:Shown() return ns.currentGame == self.id and self.ui.board ~= nil end

---------------------------------------------------------------------------
-- Starting and ending a game
---------------------------------------------------------------------------
-- kind "solo" (stake already paid) or "party". me: our side.
function Kit:Start(kind, me, opp, id, stake, level)
    local g = { kind = kind, me = me, opp = opp, id = id, stake = stake, level = level, moves = {}, heard = GetTime(), pinged = GetTime() }
    self:Replay(g)
    self.S.game, self.S.over, self.S.sel = g, nil, nil
    local db, s = self.db, self.db.stats
    if kind == "solo" then
        db.solo = { me = me, stake = stake, level = level, moves = g.moves }
        s.wagered = s.wagered + stake
    else
        db.party = { id = id, opp = opp, me = me, moves = g.moves }
        s.partyGames = s.partyGames + 1
        if ns.Dealer then ns.Dealer:SetPlayer(self, opp) end
    end
    s.games = s.games + 1
    ns:PlayGameSound(db, "newHand")
    local first = self:Turn(g) == "me" and "You move first." or (kind == "solo" and "The computer moves first." or (opp .. " moves first."))
    self:SetStatus("You play " .. self:SideName(me) .. ". " .. first)
    if kind == "solo" then
        self:Say(self.id .. "Start", { stake = Fmt(stake) }, "Your game begins.")
    else
        self:Say(self.id .. "Party", { name = opp }, "A free game against " .. opp .. ".")
    end
    if kind == "solo" and self:Turn(g) == "them" then g.thinkAt = GetTime() + THINK_PAUSE end
    self:Refresh()
end

-- The game is over. winner: a side, "draw", or nil (called off).
function Kit:Finish(winner, why)
    local g = self.S.game
    if not g then return end
    self.S.game, self.S.sel, self.S.choice, self.S.think, self.S.resignArmed = nil, nil, nil, nil, nil
    self.db.solo, self.db.party = nil, nil
    local s = self.db.stats
    local solo = g.kind == "solo"
    local opp = self:OppName(g)
    local text, r, gr, b
    if winner == nil then
        s.games = s.games - 1
        if solo then
            ns:AddChips(g.stake)
            s.wagered = s.wagered - g.stake
        else
            s.partyGames = s.partyGames - 1
        end
        text, r, gr, b = (why or "The game is called off.") .. (solo and (" Your " .. Fmt(g.stake) .. " is back.") or ""), 0.85, 0.85, 0.85
    elseif winner == "draw" then
        s.draws = s.draws + 1
        if solo then
            ns:AddChips(g.stake)
            s.won = s.won + g.stake
        end
        text, r, gr, b = "A draw: " .. (why or "agreed") .. "." .. (solo and (" Your " .. Fmt(g.stake) .. " is back.") or ""), 0.85, 0.85, 0.85
        self:Say(self.id .. "Draw", nil, "A draw.")
    elseif winner == g.me then
        s.wins = s.wins + 1
        if solo then
            ns:AddChips(g.stake * 2)
            s.won = s.won + g.stake * 2
            if g.stake > s.biggestWin then s.biggestWin = g.stake end
        end
        text, r, gr, b = "You win" .. (why and (": " .. why) or "") .. "!" .. (solo and (" You take " .. Fmt(g.stake * 2) .. ".") or ""), 0.25, 1, 0.25
        ns:PlayGameSound(self.db, "win")
        self:Say(self.id .. "Win", { name = opp }, "You win.")
    else
        s.losses = s.losses + 1
        text, r, gr, b = (solo and "The computer wins" or (opp .. " wins")) .. (why and (": " .. why) or "") .. ".", 1, 0.4, 0.4
        ns:PlayGameSound(self.db, "lose")
        self:Say(self.id .. "Lose", { name = opp }, "You lose.")
    end
    if ns.Dealer and not solo then ns.Dealer:SetImage(self, nil) end
    self.S.over = { pos = g.pos, last = g.last, log = g.log, me = g.me, taken = g.taken }
    self.db.stake = ns:FitList(STAKES, self.db.stake)
    self:SetStatus(text, r, gr, b)
    self:Refresh()
end

-- After a move: is the game over?
function Kit:CheckEnd()
    local g = self.S.game
    local winner, why = self.def.rules.Result(g.pos, nil, g.keys)
    if winner then self:Finish(winner, why) return true end
    return false
end

-- A move is made (by "me" or "them").
function Kit:Play(m, who)
    local g = self.S.game
    if not g or self:Turn(g) ~= who then return end
    self:Advance(g, m)
    self.S.sel, self.S.choice = nil, nil
    g.drawOffer = nil
    if g.kind == "party" and who == "me" then
        Net:Send(self:Msg({ "M", g.id, ns.getn(g.moves), self.def.rules.Encode(m) }))
    end
    if who == "them" then ns:PlayGameSound(self.db, "move") end
    if self:CheckEnd() then return end
    if self:Turn(g) == "me" then
        self:SetStatus("Your move.")
    else
        self:SetStatus(g.kind == "solo" and "The computer is thinking..." or ("Waiting for " .. g.opp .. "'s move."))
        if g.kind == "solo" then g.thinkAt = GetTime() + THINK_PAUSE end
    end
    self:Refresh()
end

---------------------------------------------------------------------------
-- Picking a move with the mouse
---------------------------------------------------------------------------
-- The legal moves whose path starts with `prefix`.
function Kit:Matching(prefix)
    local g = self.S.game
    local out = {}
    for _, m in ipairs(g.moves and self.def.rules.Moves(g.pos) or {}) do
        local ok = ns.getn(m.path) >= ns.getn(prefix)
        for i, s in ipairs(prefix) do if m.path[i] ~= s then ok = false end end
        if ok then table.insert(out, m) end
    end
    return out
end

function Kit:Click(s)
    local g = self.S.game
    if not g or self:Turn(g) ~= "me" or self.S.choice then return end
    local R = self.def.rules
    local sel = self.S.sel
    local piece = R.PieceAt(g.pos, s)
    local mine = piece and R.SideOf(piece) == g.me
    if mine and (not sel or ns.getn(sel) == 1) then
        if sel and sel[1] == s then self.S.sel = nil
        elseif ns.getn(self:Matching({ s })) > 0 then self.S.sel = { s }; ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        else self.S.sel = nil end
        self:Refresh()
        return
    end
    if not sel then return end
    local nextPath = {}
    for i, v in ipairs(sel) do nextPath[i] = v end
    table.insert(nextPath, s)
    local list = self:Matching(nextPath)
    if ns.getn(list) == 0 then
        self.S.sel = nil
    else
        local done = {}
        for _, m in ipairs(list) do if ns.getn(m.path) == ns.getn(nextPath) then table.insert(done, m) end end
        if ns.getn(done) == 1 and ns.getn(list) == 1 then
            self:Play(done[1], "me")
            return
        elseif ns.getn(done) > 1 then
            self.S.choice = done                  -- a promotion: which piece?
        else
            self.S.sel = nextPath                 -- a jump that goes on
        end
    end
    self:Refresh()
end

-- The mouse is over square s (nil: it left the board). Nothing by default.
function Kit:Hover(s) end

function Kit:Choose(i)
    local list = self.S.choice
    if not list or not list[i] then return end
    self:Play(list[i], "me")
end

---------------------------------------------------------------------------
-- The computer
---------------------------------------------------------------------------
function Kit:Think()
    local g = self.S.game
    if not g or g.kind ~= "solo" or self:Turn(g) ~= "them" then self.S.think = nil return end
    if not self.S.think then
        if GetTime() < (g.thinkAt or 0) then return end
        local R, pos, level = self.def.rules, g.pos, g.level
        if not coroutine then                     -- no coroutines here: think in one go
            self:Play(R.ChooseMove(pos, level, false), "them")
            return
        end
        self.S.think = coroutine.create(function() return R.ChooseMove(pos, level, true) end)
        self.S.thinkFor = g
    end
    if self.S.thinkFor ~= g then self.S.think = nil return end
    for _ = 1, THINK_STEPS do
        local ok, m = coroutine.resume(self.S.think)
        if not ok then
            self.S.think = nil
            error(m)
        end
        if coroutine.status(self.S.think) == "dead" then
            self.S.think = nil
            if m then self:Play(m, "them") end
            return
        end
    end
end

---------------------------------------------------------------------------
-- Against the computer
---------------------------------------------------------------------------
function Kit:PickSide(choice)
    local sides = self.def.rules.sides
    if choice == "?" then return sides[math.random(1, 2)] end
    return choice
end

-- The big button under the board: Play, Challenge or Withdraw.
function Kit:Go()
    if self:Mode() == "solo" then self:PlaySolo()
    elseif self.S.posted then self:Withdraw()
    else self:Post() end
end

function Kit:PlaySolo()
    if self.S.game then return end
    local stake = self.db.stake
    if not ns:SpendChips(stake) then
        self:SetStatus(ns:LowChipsText(stake), 1, 0.35, 0.35)
        return
    end
    self:Start("solo", self:PickSide(self.db.side), nil, nil, stake, self.db.level)
end

---------------------------------------------------------------------------
-- Party games
---------------------------------------------------------------------------
function Kit:OpenOffers()
    local list = {}
    for name, o in pairs(self.S.offers) do
        if GetTime() - o.heard < OFFER_TIMEOUT and Net:IsMember(name) then
            table.insert(list, { host = name, id = o.id, side = o.side, ver = o.ver })
        end
    end
    table.sort(list, function(a, b) return a.host < b.host end)
    return list
end

function Kit:SendOffer()
    local p = self.S.posted
    if not p then return end
    p.sentAt = GetTime()
    Net:Send(self:Msg({ "O", p.id, p.side, Net.PARTY_VERSION }), self.def.tag .. "-O")
end

function Kit:Post()
    if self.S.game or self.S.posted or not Net:InGroup() then return end
    self.S.posted = { id = NewId(), side = self.db.side }
    self:SendOffer()
    self:SetStatus("Challenge sent. Waiting for someone in your group to take it...")
    self:Refresh()
end

function Kit:Withdraw(quiet)
    if not self.S.posted then return end
    Net:Send(self:Msg({ "X", self.S.posted.id }), self.def.tag .. "-O")
    self.S.posted = nil
    if not quiet then self:SetStatus("Challenge withdrawn.") end
    self:Refresh()
end

function Kit:Accept(offer)
    if self.S.game or self.S.posted or self.S.accepting or not offer then return end
    self.S.accepting = { host = offer.host, id = offer.id, at = GetTime() }
    Net:Send(self:Msg({ "A", offer.id, Net.PARTY_VERSION }))
    self:SetStatus("Taking " .. offer.host .. "'s challenge...")
    self:Refresh()
end

-- Take host's challenge from a pop-up (Lobby.lua): switch to party games and accept.
function Kit:LobbyJoin(host)
    if self.S.game then return "You're already in a game of " .. self.name .. "." end
    if self:Mode() ~= "party" then self:SetMode("party") end
    for _, o in ipairs(self:OpenOffers()) do
        if o.host == host then
            self:Accept(o)
            return
        end
    end
    return host .. "'s challenge is gone."
end

function Kit:Quiet(g)
    return g and g.kind == "party" and GetTime() - (g.heard or 0) > QUIET_LIMIT
end

-- Resign (or call off a game whose other player has gone quiet).
function Kit:Resign()
    local g = self.S.game
    if not g then return end
    if g.kind == "party" then
        if self:Quiet(g) then
            Net:Send(self:Msg({ "C", g.id }))
            self:Finish(nil, g.opp .. " has gone quiet, so the game is called off.")
            return
        end
        Net:Send(self:Msg({ "F", g.id }))
    end
    self:Finish(self.def.rules.Other(g.me), "you resigned")
end

-- How long Resign waits before its second click counts (Options > Settings).
Kit.RESIGN_WAITS = { 0, 1, 2, 3, 5, 10 }
function Kit:ResignDelay()
    local d = self.db and tonumber(self.db.resignDelay)
    return d or RESIGN_DELAY
end

-- Options > Settings: the piece set (def.sets). Returns the bottom-most
-- region, for what goes under it.
function Kit:BuildPieceOption(o)
    local game = self
    local s = o.settings
    local head = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -48)
    head:SetText("Pieces")
    local keys = {}
    for _, set in ipairs(self:PieceSets()) do table.insert(keys, set.key) end
    local note = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    o.pieceStep = ns.UI.Stepper(s, {
        list = keys, width = 150,
        label = function(v)
            local set = game:PieceSet()
            for _, x in ipairs(game:PieceSets()) do if x.key == v then set = x end end
            note:SetText(set.note or " ")
            return "|cffffffff" .. set.name .. "|r"
        end,
        get = function() return game:PieceSet().key end,
        set = function(v) game.db.pieceSet = v end,
        onChange = function() game:Refresh() end,
    })
    o.pieceStep:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    note:SetPoint("TOPLEFT", o.pieceStep, "BOTTOMLEFT", 4, -6)
    note:SetWidth(320)
    note:SetJustifyH("LEFT")
    o.pieceNote = note
    return note
end

-- Options > Settings: the Resign wait. Hangs under `above` (a region on the
-- Settings tab), or at the top of the page.
function Kit:BuildResignOption(o, above)
    local game = self
    local s = o.settings
    local head = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if above then head:SetPoint("TOPLEFT", above, "BOTTOMLEFT", -4, -16)
    else head:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -48) end
    head:SetText("Resign")
    local label = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 4, -12)
    label:SetText("Wait before Confirm works")
    o.resignStep = ns.UI.Stepper(s, {
        list = Kit.RESIGN_WAITS, width = 80,
        label = function(v)
            if v == 0 then return "No wait" end
            return v .. (v == 1 and " second" or " seconds")
        end,
        get = function() return game:ResignDelay() end,
        set = function(v) game.db.resignDelay = v end,
        onChange = function() game:ResignButton() end,
    })
    o.resignStep:SetPoint("LEFT", label, "LEFT", 178, 0)
    local note = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -12)
    note:SetWidth(320)
    note:SetJustifyH("LEFT")
    note:SetText("So a stray double click can't end a game.")
    o.resignNote = note
end

-- Resign takes two clicks: the first asks, and the second only works once
-- the wait (ResignDelay) has gone by (so a stray double click can't end a game).
function Kit:ResignClick()
    local armed = self.S.resignArmed
    if armed then
        if GetTime() - armed >= self:ResignDelay() then
            self.S.resignArmed = nil
            self:Resign()
        end
        return
    end
    self.S.resignArmed = GetTime()
    ns:Sound("IG_MAINMENU_OPTION")
    self:ResignButton()
end

-- The Resign button's text and state (it counts down while armed).
function Kit:ResignButton()
    local g, ui = self.S.game, self.ui
    if not g or not ui.resign then return end
    local word = self:Quiet(g) and "Call it off" or "Resign"
    local armed = self.S.resignArmed
    local delay = self:ResignDelay()
    if armed then
        local waited = GetTime() - armed
        if waited >= delay + RESIGN_WINDOW then
            self.S.resignArmed, armed = nil, nil
        elseif waited < delay then
            ui.resign:SetText(word .. "? " .. math.ceil(delay - waited))
            ns.SetEnabled(ui.resign, false)
            return
        else
            ui.resign:SetText("Confirm")
            ns.SetEnabled(ui.resign, true)
            return
        end
    end
    ui.resign:SetText(word)
    ns.SetEnabled(ui.resign, true)
end

-- Offer a draw, or take the one on the table.
function Kit:Draw()
    local g = self.S.game
    if not g or g.kind ~= "party" then return end
    local n = ns.getn(g.moves)
    if g.drawOffer and g.drawOffer.by == "them" and g.drawOffer.n == n then
        Net:Send(self:Msg({ "Z", g.id, n }))
        self:Finish("draw", "agreed")
        return
    end
    if g.drawOffer then return end
    g.drawOffer = { by = "me", n = n }
    Net:Send(self:Msg({ "D", g.id, n }))
    self:SetStatus("You offer a draw.")
    self:Refresh()
end

-- "I have n moves": sent now and then, and after a reload.
function Kit:Ping(g)
    g.pinged = GetTime()
    Net:Send(self:Msg({ "Y", g.id, ns.getn(g.moves) }), self.def.tag .. "-Y")
end

function Kit:OnMessage(sender, f)
    local kind, id = f[2], f[3]
    local S = self.S
    if kind == "Q" then self:SendOffer() return end
    if kind == "O" then
        S.offers[sender] = { id = id, side = f[4], ver = tonumber(f[5]), heard = GetTime() }
        if self:Shown() then self:Refresh() end
        return
    elseif kind == "X" then
        S.offers[sender] = nil
        if S.accepting and S.accepting.host == sender then
            S.accepting = nil
            self:SetStatus(sender .. " withdrew that challenge.")
        end
        if self:Shown() then self:Refresh() end
        return
    elseif kind == "A" then
        local p = S.posted
        if not p or p.id ~= id or S.game or not Net:IsMember(sender) or Net:VersionProblem(f[4]) then return end
        S.posted = nil
        local mine = self:PickSide(p.side)
        Net:Send(self:Msg({ "S", p.id, sender, mine }), self.def.tag .. "-O")
        self:Start("party", mine, sender, p.id)
        return
    elseif kind == "S" then
        S.offers[sender] = nil
        local a = S.accepting
        if a and a.host == sender and a.id == id then
            S.accepting = nil
            if f[4] ~= Net:Me() then
                self:SetStatus(f[4] .. " took " .. sender .. "'s challenge first.")
            elseif f[5] == self.def.rules.sides[1] or f[5] == self.def.rules.sides[2] then
                self:Start("party", self.def.rules.Other(f[5]), sender, id)
                return
            end
        end
        if self:Shown() then self:Refresh() end
        return
    end

    local g = S.game
    if not g or g.kind ~= "party" or g.id ~= id or sender ~= g.opp then
        self:OnLateMessage(sender, kind, f)
        return
    end
    g.heard = GetTime()
    g.quietShown = nil
    self:OnGameMessage(sender, kind, f, g)
end

-- A message about a game that's over (or not ours). Nothing by default.
function Kit:OnLateMessage(sender, kind, f) end

-- A message from the other player in a party game.
function Kit:OnGameMessage(sender, kind, f, g)
    local n = ns.getn(g.moves or {})
    if kind == "M" then
        local at = tonumber(f[4])
        if at == n + 1 and self:Turn(g) == "them" then
            local m = self:Decode(g.pos, f[5] or "")
            if m then self:Play(m, "them") end
        elseif at and at > n + 1 then
            self:Ping(g)                                   -- we missed one: ask again
        end
    elseif kind == "Y" then
        local theirs = tonumber(f[4]) or 0
        if theirs < n then
            -- they're behind (a reload, or a lost message): send what they miss
            for i = theirs + 1, n do Net:Send(self:Msg({ "M", g.id, i, g.moves[i] })) end
        elseif theirs > n then
            self:Ping(g)
        end
        if self:Shown() then self:Refresh() end
    elseif kind == "D" then
        if tonumber(f[4]) == n then
            g.drawOffer = { by = "them", n = n }
            self:SetStatus(sender .. " offers a draw. Take it, or just play on.")
            ns:Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            self:Refresh()
        end
    elseif kind == "Z" then
        if g.drawOffer and g.drawOffer.by == "me" and tonumber(f[4]) == n then self:Finish("draw", "agreed") end
    elseif kind == "F" then
        self:Finish(g.me, sender .. " resigned")
    elseif kind == "C" then
        self:Finish(nil, sender .. " called the game off.")
    end
end

function Kit:GroupChanged()
    local S = self.S
    for name in pairs(S.offers) do
        if not Net:IsMember(name) then S.offers[name] = nil end
    end
    if S.accepting and not Net:IsMember(S.accepting.host) then S.accepting = nil end
    if S.posted and not Net:InGroup() then S.posted = nil end
    local g = S.game
    if g and g.kind == "party" and not Net:IsMember(g.opp) then
        self:Finish(nil, g.opp .. " left the group, so the game is called off.")
    end
    if self:Shown() then self:Refresh() end
end

function Kit:Tick()
    if not self.db then return end
    local S, now = self.S, GetTime()
    local g = S.game
    if g and g.kind == "solo" then self:Think() end
    if self.S.resignArmed and self:Shown() then self:ResignButton() end
    if g and g.kind == "party" then
        if now - (g.pinged or 0) >= PING_EVERY then self:Ping(g) end
        if self:Quiet(g) and not g.quietShown then
            g.quietShown = true
            if self:Shown() then self:Refresh() end
        end
    end
    if S.posted and now - (S.posted.sentAt or 0) >= OFFER_EVERY then self:SendOffer() end
    if S.accepting and now - S.accepting.at > 15 then
        S.accepting = nil
        if self.ui.board then
            self:SetStatus("No answer to that challenge.")
            self:Refresh()
        end
    end
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
-- Where square s sits on screen (0-7 across, 0-7 down), seen from `me`.
local function Place(s, flipped)
    local row, col = math.floor((s - 1) / 8), ns.Mod(s - 1, 8)
    if flipped then return 7 - col, row end
    return col, 7 - row
end

---------------------------------------------------------------------------
-- Capture paths: dashed for a capture you can make, dotted for the one just
-- made. 1.12 can't draw lines, so they're rows of tiny squares.
---------------------------------------------------------------------------
local PATH_STYLES = {
    dash = { step = 2.5, on = 4, off = 2, size = 3, color = { 1, 0.35, 0.15, 0.95 } },   -- a capture you can make
    dot  = { step = 6,   on = 1, off = 0, size = 3, color = { 1, 0.85, 0.2, 0.9 } },     -- the move just made
}
local STOP_SIZE = 7      -- the dot on each square a move starts, stops or lands on
local PATH_INSET = 9     -- the path starts this far from the moving piece's center

function Kit:Dot(i)
    local ui = self.ui
    local t = ui.dots[i]
    if not t then
        t = ui.overlay:CreateTexture(nil, "OVERLAY")
        ui.dots[i] = t
    end
    return t
end

-- Center of square s on the board, from its top-left (x right, y down).
local function Center(s, flipped)
    local x, y = Place(s, flipped)
    return x * SQ + SQ / 2, y * SQ + SQ / 2
end

-- Draws each path ({ squares, style, line }): a dot on every square of the
-- move (where it starts, each hop, where it ends), and the line between them
-- unless line is false. Returns how many dots were used.
function Kit:DrawPaths(paths, flipped)
    local used = 0
    local board = self.ui.board
    local function Put(x, y, size, r, g, b, a)
        used = used + 1
        local t = self:Dot(used)
        t:SetWidth(size); t:SetHeight(size)
        t:SetTexture(r, g, b, a)
        t:ClearAllPoints()
        t:SetPoint("CENTER", board, "TOPLEFT", x, -y)
        t:Show()
    end
    for _, p in ipairs(paths) do
        local st = PATH_STYLES[p.style]
        local c = st.color
        local count = 0          -- dots along the whole path, for the dash pattern
        for i = 1, (p.line == false) and 0 or (ns.getn(p.squares) - 1) do
            local x1, y1 = Center(p.squares[i], flipped)
            local x2, y2 = Center(p.squares[i + 1], flipped)
            local dx, dy = x2 - x1, y2 - y1
            local len = math.sqrt(dx * dx + dy * dy)
            local from = (i == 1) and PATH_INSET or 0
            local d = from
            while d <= len do
                local k = ns.Mod(count, st.on + st.off)
                count = count + 1
                if k < st.on then Put(x1 + dx * d / len, y1 + dy * d / len, st.size, c[1], c[2], c[3], c[4]) end
                d = d + st.step
            end
        end
        -- the stops: a dark edge round a bright dot, so it shows on any square or piece
        for _, sq in ipairs(p.squares) do
            local x, y = Center(sq, flipped)
            Put(x, y, STOP_SIZE + 2, 0, 0, 0, 0.7)
            Put(x, y, STOP_SIZE, c[1], c[2], c[3], 1)
        end
    end
    for i = used + 1, ns.getn(self.ui.dots) do self.ui.dots[i]:Hide() end
    return used
end

-- show: { paths = {...}, threat = {sq = true}, can = {sq = true} }
function Kit:DrawBoard(pos, me, last, sel, targets, show)
    local set = self:PieceSet()
    local R, ui, def = self.def.rules, self.ui, self.def
    local flipped = me ~= R.sides[1]
    show = show or {}
    local check = R.CheckSquare and pos and R.CheckSquare(pos)
    local inLast = {}
    if last then for _, s in ipairs(last.path) do inLast[s] = true end end
    local inSel = {}
    if sel then for _, s in ipairs(sel) do inSel[s] = true end end
    for s = 1, 64 do
        local b = ui.squares[s]
        local x, y = Place(s, flipped)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ui.board, "TOPLEFT", x * SQ, -y * SQ)
        local c = R.Dark(s) and (set.dark or def.dark) or (set.light or def.light)
        b.bg:SetTexture(c[1], c[2], c[3], 1)
        local piece = pos and R.PieceAt(pos, s)
        ns.SetShown(b.piece, self:PaintPiece(b.piece, piece, set))
        local em = piece and set.emblems and set.emblems[piece]
        if em then
            b.emblem:SetTexture(em[1])
            b.emblem:SetTexCoord(em[2], em[3], em[4], em[5])
            b.emblem:Show()
        else
            b.emblem:Hide()
        end
        if s == check then
            b.mark:SetTexture(0.9, 0.1, 0.1, 0.55); b.mark:Show()
        elseif inSel[s] then
            b.mark:SetTexture(1, 0.82, 0, 0.55); b.mark:Show()
        elseif inLast[s] then
            b.mark:SetTexture(1, 0.9, 0.3, 0.25); b.mark:Show()
        else
            b.mark:Hide()
        end
        ns.SetShown(b.dot, targets and targets[s] and not (show.threat and show.threat[s]))
        ns.SetShown(b.threat, show.threat and show.threat[s])
        ns.SetShown(b.can, show.can and show.can[s])
    end
    self:DrawPaths(show.paths or {}, flipped)
    -- the edge labels follow the board's way round
    for i = 1, 8 do
        ui.files[i]:SetText(string.sub("abcdefgh", flipped and (9 - i) or i, flipped and (9 - i) or i))
        ui.ranks[i]:SetText(flipped and i or (9 - i))
    end
end

-- The captured pieces, for a game (or the one just over).
function Kit:DrawTaken(g)
    local def, R = self.def, self.def.rules
    local me = g and g.me or (self.db.side == "?" and R.sides[1] or self.db.side)
    local them = R.Other(me)
    local taken = g and g.taken or {}
    local worth = {}
    -- row 1: what they took (your pieces); row 2: what you took
    for k, side in ipairs({ them, me }) do
        local list = {}
        for _, p in ipairs(taken[side] or {}) do table.insert(list, p) end
        -- most valuable first; equal values by name (so checkers' kings, "bK", come before men, "bM")
        table.sort(list, function(a, b)
            local va, vb = def.taken[a] or 0, def.taken[b] or 0
            if va ~= vb then return va > vb end
            return a < b
        end)
        local row, sum = self.ui.taken[k], 0
        local set = self:PieceSet()
        for i, t in ipairs(row.icons) do ns.SetShown(t, self:PaintPiece(t, list[i], set)) end
        for _, p in ipairs(list) do sum = sum + (def.taken[p] or 0) end
        row:SetHeight(math.max(1, math.ceil(ns.getn(list) / TAKEN_PER_ROW) * TAKEN_SIZE))
        worth[k] = sum
    end
    local diff = worth[2] - worth[1]
    self.ui.taken[1].lead:SetText(diff < 0 and ("|cffff7070+" .. -diff .. "|r") or "")
    self.ui.taken[2].lead:SetText(diff > 0 and ("|cff66ff66+" .. diff .. "|r") or "")
end

function Kit:StatsText()
    local s = self.db.stats
    local text = string.format("Games %d  Won %d  Lost %d  Drawn %d", s.games, s.wins, s.losses, s.draws)
    if self.def.rules.ChooseMove then text = text .. "  Net " .. ns.UI.Net(s.won - s.wagered) .. "|r" end
    return text
end

function Kit:Refresh()
    local ui, S, R, db = self.ui, self.S, self.def.rules, self.db
    if not ui.board then return end
    ns:UpdateChipsDisplay()
    local g = S.game
    local solo = self:Mode() == "solo"
    if ui.soloTab then
        ns.SetEnabled(ui.soloTab, g == nil and not S.posted and not solo)
        ns.SetEnabled(ui.partyTab, g == nil and solo)
        ui.soloTab:SetText((solo and "|cffffff00" or "") .. "Vs the computer")
        ui.partyTab:SetText((not solo and "|cffffff00" or "") .. "Party game")
    end

    -- the board: the game, the one just finished, or the starting position
    local targets
    if g then
        local show = { paths = {}, threat = {}, can = {} }
        local myTurn = self:Turn(g) == "me" and not S.choice
        if S.sel and myTurn then
            -- where the picked piece can go; captures get a dashed path and
            -- the pieces they'd take are marked
            targets = {}
            local depth = ns.getn(S.sel) + 1
            for _, m in ipairs(self:Matching(S.sel)) do
                if m.path[depth] then targets[m.path[depth]] = true end
                local caps = Captures(m)
                if caps then
                    table.insert(show.paths, { squares = m.path, style = "dash" })
                    for _, c in ipairs(caps) do show.threat[c] = true end
                end
            end
        elseif myTurn then
            -- your turn: the pieces that can capture are marked
            for _, m in ipairs(R.Moves(g.pos)) do
                if Captures(m) then show.can[m.path[1]] = true end
            end
        end
        -- the move just made: a dot where it started, where it ended (and each
        -- hop between), joined by a dotted line when it was a capture
        if g.last and not S.sel then
            table.insert(show.paths, { squares = g.last.path, style = "dot", line = Captures(g.last) ~= nil })
        end
        self:DrawBoard(g.pos, g.me, g.last, S.sel, targets, show)
    elseif S.over then
        local show = { paths = {} }
        if S.over.last then
            table.insert(show.paths, { squares = S.over.last.path, style = "dot", line = Captures(S.over.last) ~= nil })
        end
        self:DrawBoard(S.over.pos, S.over.me, S.over.last, nil, nil, show)
    else
        local side = db.side == "?" and R.sides[1] or db.side
        self:DrawBoard(R.New(), side)
    end

    -- the promotion choice
    local choice = S.choice
    for i = 1, 4 do
        local b = ui.choices[i]
        if choice and choice[i] then
            b:SetText(R.ChoiceLabel and R.ChoiceLabel(choice[i]) or tostring(i))
            b:Show()
        else
            b:Hide()
        end
    end
    ns.SetShown(ui.choiceBox, choice ~= nil)

    -- whose turn, and the moves so far
    if g then
        local me = self:SideName(g.me)
        if self:Turn(g) == "me" then
            ui.turn:SetText("|cff66ff66Your move|r")
        else
            ui.turn:SetText("Their move")
        end
        ui.against:SetText("You: " .. me .. "\n" .. (g.kind == "solo" and ("vs " .. R.LEVELS[g.level].name .. " AI\nfor " .. Fmt(g.stake))
            or ("vs " .. g.opp .. "\n(free)")))
    else
        ui.turn:SetText(S.over and "Game over" or "")
        ui.against:SetText("")
    end
    local log = (g and g.log) or (S.over and S.over.log) or {}
    local n = ns.getn(log)
    local lines = self.logLines
    for i = 1, lines do ui.log[i]:SetText(log[n - lines + i] or "") end
    ns.SetShown(ui.logBg, n > 0)
    if ui.taken then self:DrawTaken(g or S.over) end

    -- the party lobby, over the board between games
    self:RefreshLobby(not solo and not g)

    -- the pickers
    for _, p in ipairs(ui.pickers) do p:Refresh() end
    -- (hidden during a game: the column says what it's for)
    ns.SetShown(ui.side, g == nil)
    if ui.stake then
        ns.SetShown(ui.stake, solo and g == nil)
        ns.SetShown(ui.level, solo and g == nil)
    end

    -- the buttons
    if g then
        ui.go:Hide()
        ui.resign:Show()
        self:ResignButton()
        ns.SetShown(ui.draw, g.kind == "party")
        if g.kind == "party" then
            local offer = g.drawOffer
            if offer and offer.by == "them" then ui.draw:SetText("Accept draw"); ns.SetEnabled(ui.draw, true)
            elseif offer then ui.draw:SetText("Draw offered"); ns.SetEnabled(ui.draw, false)
            else ui.draw:SetText("Offer draw"); ns.SetEnabled(ui.draw, true) end
        end
    else
        ui.resign:Hide()
        ui.draw:Hide()
        ui.go:Show()
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

-- The party lobby over the board (shown between party games).
function Kit:RefreshLobby(shown)
    local ui, S, R = self.ui, self.S, self.def.rules
    ns.SetShown(ui.lobby, shown)
    if not shown then return end
    local list = self:OpenOffers()
    for r = 1, 4 do
        local row, offer = ui.rows[r], list[r]
        row.offer = offer
        if offer then
            local side = offer.side == "?" and "random sides" or
                (R.OfferText and R.OfferText(offer.side) or ("plays " .. self:SideName(offer.side)))
            row.text:SetText(offer.host .. " (" .. side .. ")" .. Net:VersionNote(offer.ver))
            row:Show()
            ns.SetEnabled(row.accept, not S.accepting and not S.posted and not Net:VersionProblem(offer.ver))
        else
            row:Hide()
        end
    end
    ui.lobbyTitle:SetText(S.posted and "Your challenge is open. Waiting..." or (list[1] and "Open challenges in your group:" or
        (Net:InGroup() and "No open challenges yet.\nChallenge your group below." or "Join a party or raid to play\nyour friends.")))
end

function Kit:Mode()
    if not self.def.rules.ChooseMove then return "party" end
    return self.db.mode
end

function Kit:SetMode(mode)
    if self.S.game or self.S.posted or self.db.mode == mode then return end
    self.db.mode = mode
    self.S.over = nil
    ns:Sound("IG_MAINMENU_OPTION")
    self:Welcome()
    self:Refresh()
end

function Kit:Welcome()
    if self:Mode() == "party" then
        Net:Send(self:Msg({ "Q" }))
        self:SetStatus(Net:InGroup() and "Challenge your group, or take a challenge." or "Join a party or raid to play your friends.")
    else
        self:SetStatus("Pick a stake, a level and your side, then Play.")
    end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
-- The board: cols x rows squares of size sq (8 x 8 of 30 by default; a
-- game can ask for another size, keeping it 240 across).
function Kit:BuildBoard(panel)
    local ui = self.ui
    local game = self
    local cols, rows, sq = self.cols, self.rows, self.sq
    local frame = ns.CreateFrame("Frame", nil, panel)
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", BX, BY)
    frame:SetWidth(cols * sq); frame:SetHeight(rows * sq)
    local edge = frame:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
    edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
    edge:SetTexture(0.16, 0.10, 0.05, 1)
    ui.board = frame
    ui.squares = {}
    for s = 1, cols * rows do
        local s = s     -- own copy for the closure (Lua 5.0)
        local b = ns.CreateFrame("Button", nil, frame)
        b:SetWidth(sq); b:SetHeight(sq)
        b.sq = s
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints(b)
        b.mark = b:CreateTexture(nil, "BORDER")
        b.mark:SetAllPoints(b)
        b.mark:Hide()
        b.piece = b:CreateTexture(nil, "ARTWORK")
        b.piece:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        b.piece:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        b.piece:SetTexture(ATLAS)
        b.piece:Hide()
        -- a picture over the piece (a set's emblems)
        b.emblem = b:CreateTexture(nil, "OVERLAY")
        b.emblem:SetWidth(18); b.emblem:SetHeight(18)
        b.emblem:SetPoint("CENTER", b, "CENTER", 0, 1)
        b.emblem:Hide()
        b.dot = b:CreateTexture(nil, "OVERLAY")
        b.dot:SetWidth(10); b.dot:SetHeight(10)
        b.dot:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.dot:SetTexture(0.2, 0.95, 0.3, 0.8)
        b.dot:Hide()
        -- a piece a capture would take: a red wash under it
        b.threat = b:CreateTexture(nil, "BORDER")
        b.threat:SetAllPoints(b)
        b.threat:SetTexture(0.95, 0.15, 0.1, 0.45)
        b.threat:Hide()
        -- a piece that can capture this turn: an orange corner
        b.can = b:CreateTexture(nil, "OVERLAY")
        b.can:SetWidth(7); b.can:SetHeight(7)
        b.can:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        b.can:SetTexture(1, 0.45, 0.1, 0.95)
        b.can:Hide()
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b)
        hl:SetTexture(1, 1, 1, 0.15)
        b:SetScript("OnClick", function() game:Click(s) end)
        b:SetScript("OnEnter", function() game:Hover(s) end)
        b:SetScript("OnLeave", function() game:Hover(nil) end)
        ui.squares[s] = b
    end
    -- capture paths draw over the pieces
    ui.overlay = ns.CreateFrame("Frame", nil, frame)
    ui.overlay:SetAllPoints(frame)
    ui.overlay:SetFrameLevel(frame:GetFrameLevel() + 4)
    ui.dots = {}

    ui.files, ui.ranks = {}, {}
    for i = 1, cols do
        local f = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f:SetPoint("TOP", frame, "BOTTOMLEFT", (i - 0.5) * sq, -4)
        ui.files[i] = f
    end
    for i = 1, rows do
        local r = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r:SetPoint("RIGHT", frame, "TOPLEFT", -5, -(i - 0.5) * sq)
        ui.ranks[i] = r
    end

    -- promotion: which piece?
    local box = ns.CreateFrame("Frame", nil, frame)
    box:SetFrameLevel(frame:GetFrameLevel() + 10)
    box:SetWidth(8 * SQ - 40); box:SetHeight(84)
    box:SetPoint("CENTER", frame, "CENTER", 0, 0)
    box:EnableMouse(true)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(box)
    bg:SetTexture(0, 0, 0, 0.88)
    local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", box, "TOP", 0, -8)
    label:SetText("Promote to:")
    ui.choices = {}
    for i = 1, 4 do
        local i = i
        local b = MakeButton(box, "?", 84, function() game:Choose(i) end)
        b:SetPoint("TOPLEFT", box, "TOPLEFT", 6 + ns.Mod(i - 1, 2) * 88, -26 - math.floor((i - 1) / 2) * 26)
        ui.choices[i] = b
    end
    box:Hide()
    ui.choiceBox = box
end

function Kit:BuildLobby(panel)
    local ui, game = self.ui, self
    local lobby = ns.CreateFrame("Frame", nil, ui.board)
    lobby:SetAllPoints(ui.board)
    lobby:SetFrameLevel(ui.board:GetFrameLevel() + 8)
    lobby:EnableMouse(true)
    local bg = lobby:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(lobby)
    bg:SetTexture(0, 0, 0, 0.72)
    ui.lobbyTitle = lobby:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.lobbyTitle:SetPoint("TOP", lobby, "TOP", 0, -12)
    ui.lobbyTitle:SetWidth(8 * SQ - 12)
    ui.rows = {}
    for r = 1, 4 do
        local r = r
        local row = ns.CreateFrame("Frame", nil, lobby)
        row:SetWidth(8 * SQ - 16); row:SetHeight(36)
        row:SetPoint("TOP", lobby, "TOP", 0, -44 - (r - 1) * 40)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.text:SetWidth(8 * SQ - 90)
        row.text:SetJustifyH("LEFT")
        row.accept = MakeButton(row, "Accept", 66, function() game:Accept(game.ui.rows[r].offer) end)
        row.accept:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row:Hide()
        ui.rows[r] = row
    end
    lobby:Hide()
    ui.lobby = lobby
end

-- The column beside the board, top to bottom: whose move, who against,
-- what's happening, the captured pieces (def.taken), and the moves so far
-- (at the foot, level with the board's bottom). Each piece hangs from the
-- one above it, so a long message pushes the rest down.
function Kit:BuildSide(panel)
    local ui = self.ui
    ui.turn = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.turn:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE_X, BY - 2)
    ui.turn:SetWidth(SIDE_W)
    ui.turn:SetJustifyH("LEFT")
    ui.against = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.against:SetPoint("TOPLEFT", ui.turn, "BOTTOMLEFT", 0, -4)
    ui.against:SetWidth(SIDE_W)
    ui.against:SetJustifyH("LEFT")
    ui.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ui.status:SetPoint("TOPLEFT", ui.against, "BOTTOMLEFT", 0, -8)
    ui.status:SetWidth(SIDE_W)
    ui.status:SetJustifyH("LEFT")

    -- the captured pieces: what the other side took, then what you took
    -- (most valuable first), and who's ahead
    local lines = LOG_LINES
    if self.def.taken then
        ui.taken = {}
        local above = ui.status
        for k = 1, 2 do
            local box = ns.CreateFrame("Frame", nil, panel)
            box:SetWidth(SIDE_W); box:SetHeight(1)
            box:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, k == 1 and -8 or -3)
            box.icons = {}
            for i = 1, 16 do
                local t = box:CreateTexture(nil, "ARTWORK")
                t:SetWidth(TAKEN_SIZE); t:SetHeight(TAKEN_SIZE)
                t:SetPoint("TOPLEFT", box, "TOPLEFT", ns.Mod(i - 1, TAKEN_PER_ROW) * TAKEN_SIZE,
                    -math.floor((i - 1) / TAKEN_PER_ROW) * TAKEN_SIZE)
                t:SetTexture(ATLAS)
                t:Hide()
                box.icons[i] = t
            end
            box.lead = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            box.lead:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -1)
            ui.taken[k] = box
            above = box
        end
        lines = 5
    end
    self.logLines = lines

    -- the moves so far, at the foot of the column
    local bottom = BY - 8 * SQ
    ui.logBg = panel:CreateTexture(nil, "BORDER")
    ui.logBg:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", SIDE_X - 2, bottom)
    ui.logBg:SetWidth(SIDE_W + 4); ui.logBg:SetHeight(lines * 13 + 6)
    ui.logBg:SetTexture(0, 0, 0, 0.35)
    ui.log = {}
    for i = 1, lines do
        local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", SIDE_X + 1, bottom + 3 + (lines - i) * 13)
        t:SetWidth(SIDE_W)
        t:SetJustifyH("LEFT")
        ui.log[i] = t
    end
end

function Kit:BuildBottom(panel)
    local ui, game, R = self.ui, self, self.def.rules
    local function Locked() return game.S.game ~= nil or game.S.posted ~= nil end
    local function Refresh() game:Refresh() end
    local row = ns.CreateFrame("Frame", nil, panel)
    row:SetWidth(PANEL_W - 8); row:SetHeight(24)
    row:SetPoint("BOTTOM", panel, "BOTTOM", 0, 50)
    ui.pickers = {}
    ui.side = ns.UI.Stepper(row, {
        list = { R.sides[1], R.sides[2], "?" }, width = 60,
        label = function(v) return v == "?" and "|cffffffffRandom|r" or ("|cffffffff" .. game:SideName(v) .. "|r") end,
        get = function() return game.db.side end,
        set = function(v) game.db.side = v end,
        locked = Locked, onChange = Refresh,
    })
    table.insert(ui.pickers, ui.side)
    if R.ChooseMove then
        ui.stake = ns.UI.Stepper(row, {
            list = STAKES, width = 66,
            label = function(v) return "Stake |cffffffff" .. Fmt(v) .. "|r" end,
            get = function() return game.db.stake end,
            set = function(v) game.db.stake = v end,
            locked = Locked, onChange = Refresh,
        })
        ui.stake:SetPoint("LEFT", row, "LEFT", 0, 0)
        ui.level = ns.UI.Stepper(row, {
            list = { 1, 2, 3 }, width = 52,
            label = function(v) return "|cffffffff" .. R.LEVELS[v].name .. "|r" end,
            get = function() return game.db.level end,
            set = function(v) game.db.level = v end,
            locked = Locked, onChange = Refresh,
        })
        ui.level:SetPoint("LEFT", ui.stake, "RIGHT", 4, 0)
        table.insert(ui.pickers, ui.stake)
        table.insert(ui.pickers, ui.level)
        ui.side:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    else
        ui.side:SetPoint("CENTER", row, "CENTER", 0, 0)
    end

    ui.go = MakeButton(panel, "Play", 180, function() game:Go() end, 28)
    ui.go:SetPoint("BOTTOM", panel, "BOTTOM", 0, 18)
    ui.resign = MakeButton(panel, "Resign", 110, function() game:ResignClick() end, 26)
    ui.resign:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -4, 19)
    -- a red wash, so it never looks like the Play button
    local wash = ui.resign:CreateTexture(nil, "ARTWORK")
    wash:SetPoint("TOPLEFT", ui.resign, "TOPLEFT", 3, -3)
    wash:SetPoint("BOTTOMRIGHT", ui.resign, "BOTTOMRIGHT", -3, 3)
    wash:SetTexture(0.75, 0.05, 0.05, 0.5)
    ui.resign.wash = wash
    ui.resign:Hide()
    ui.draw = MakeButton(panel, "Offer draw", 110, function() game:Draw() end, 26)
    ui.draw:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 4, 19)
    ui.draw:Hide()
    ui.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", panel, "BOTTOM", 0, 3)
end

function Kit:Build(panel)
    local def, game, R = self.def, self, self.def.rules
    self.db = ns:SetupGame(panel, self.id, {
        defaults = { mode = R.ChooseMove and "solo" or "party", stake = 50, level = 2, side = R.sides[1] },
        stats = DEFAULT_STATS,
        sounds = EXTRA_SOUNDS,
        felt = def.felt,
    })
    if R.ChooseMove then
        self.ui.soloTab = MakeButton(panel, "Vs the computer", 150, function() game:SetMode("solo") end)
        self.ui.soloTab:SetPoint("TOPRIGHT", panel, "TOP", -4, -4)
        self.ui.partyTab = MakeButton(panel, "Party game", 150, function() game:SetMode("party") end)
        self.ui.partyTab:SetPoint("TOPLEFT", panel, "TOP", 4, -4)
    else
        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", panel, "TOP", 0, -10)
        title:SetText("Party " .. string.lower(def.name) .. " - play anyone in your group")
    end
    self:BuildBoard(panel)
    self:BuildLobby(panel)
    self:BuildSide(panel)
    self:BuildBottom(panel)
    self.ui.options = ns:GameOptions(self, panel, {
        rules = def.rulesText,
        onReset = function() game:ResetStats() end,
        db = function() return game.db end,
        sounds = EXTRA_SOUNDS,
        settings = true,
        build = function(o)
            local above = def.sets and game:BuildPieceOption(o)
            game:BuildResignOption(o, above)
        end,
        refresh = function(o)
            if o.pieceStep then o.pieceStep:Refresh() end
            o.resignStep:Refresh()
        end,
    })

    -- a game from before a reload
    local db = self.db
    if db.party then
        local p = db.party
        local g = { kind = "party", id = p.id, opp = p.opp, me = p.me, moves = p.moves or {}, heard = GetTime(), pinged = GetTime() }
        self:Replay(g)
        db.party.moves = g.moves
        self.S.game = g
        self:Ping(g)
        self:SetStatus("Your game with " .. tostring(p.opp) .. " is still on.")
    elseif db.solo and R.ChooseMove then
        local p = db.solo
        local g = { kind = "solo", me = p.me, stake = p.stake, level = p.level or 2, moves = p.moves or {} }
        self:Replay(g)
        db.solo.moves = g.moves
        self.S.game = g
        g.thinkAt = GetTime() + THINK_PAUSE
        self:SetStatus("Your game is still on.")
        if self:CheckEnd() then return end
    else
        self:Welcome()
    end
    self:Refresh()
end

function Kit:OnShow()
    if self.ui.board then
        if self:Mode() == "party" and not self.S.game then Net:Send(self:Msg({ "Q" })) end
        self:Refresh()
    end
end

function Kit:OnHide()
    if self.ui.options then self.ui.options:Hide() end
end

function Kit:ChipsInPlay()
    local d = ns.db[self.id]
    return (self.S.game ~= nil and self.S.game.kind == "solo") or (d ~= nil and d.solo ~= nil)
end

-- Start over (Options): a game in progress is resigned.
function Kit:Abandon()
    if self.S.posted then self:Withdraw(true) end
    local g = self.S.game
    if g then
        if g.kind == "party" then Net:Send(self:Msg({ "F", g.id })) end
        self:Finish(self.def.rules.Other(g.me), "you resigned")
    else
        local d = ns.db[self.id]
        if d then d.solo, d.party = nil, nil end
    end
end

function Kit:ResetStats()
    local d = ns.db[self.id]
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    if self.ui.stats and self.db then self:Refresh() end
end

---------------------------------------------------------------------------
-- A new board game
---------------------------------------------------------------------------
-- class: a table of methods that replace some of the kit's (its __index
-- should fall back to Kit), for a game that plays differently (Battleship).
function Kit.New(def, class)
    local game = setmetatable({
        id = def.id, name = def.name, description = def.description, icon = def.icon, dealer = def.dealer,
        def = def, ui = {}, S = { offers = {} }, wide = true,
        cols = def.cols or 8, rows = def.rows or 8, sq = def.sq or SQ,
    }, class or Kit)
    Net.handlers[def.tag] = function(sender, f) game:OnMessage(sender, f) end
    Net.groupHandlers[def.id] = function() game:GroupChanged() end
    -- the lobby hub (Lobby.lua): pop-ups, badges and invites
    ns.Lobby:Register(def.id, {
        noun = "challenge",
        offers = function()
            local out = {}
            for _, o in ipairs(game:OpenOffers()) do
                if not Net:VersionProblem(o.ver) then table.insert(out, { host = o.host, key = o.id }) end
            end
            return out
        end,
        ask = function() Net:Send(game:Msg({ "Q" })) end,
        join = function(host) return game:LobbyJoin(host) end,
        hosting = function() return game.S.posted ~= nil end,
        busy = function() return game.S.game ~= nil or game.S.posted ~= nil or game.S.accepting ~= nil end,
    })
    local ticker = ns.CreateFrame("Frame")
    local wait = 0
    ticker:SetScript("OnUpdate", function()
        wait = wait + (arg1 or 0)
        -- the computer thinks every frame; the rest can wait a moment
        if game.S.think or wait >= 0.1 then
            wait = 0
            game:Tick()
        end
    end)
    return game
end
