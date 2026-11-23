-- CowCasino: the parts every single-player chip game shares (Mines, Plinko,
-- Crash, Hi-Lo...): its saved settings and stats, the felt, a status line, a
-- stats line, a chip bet row, recording a round, and the core's hooks (the
-- intro's stats, resetting stats). Each game keeps its own play area and
-- rules.
--
--   local kit = ns.SoloKit.New(Game, {
--       key = "mines",                    -- ns.db.mines
--       defaults = { bet = 25, mines = 3 }, -- settings it starts with
--       stats = DEFAULT_STATS,            -- the stats and their starting values
--       statsLine = { ... },              -- UI.StatsLine's spec (UI.lua)
--       felt = { r, g, b, a }, sounds = EXTRA_SOUNDS,   -- (as ns:SetupGame takes them)
--       minBet = 1, maxBet = 1000,
--       canBet = function() return not busy end,   -- the bet can change now
--       refresh = function() Refresh() end,
--   })
--   db = kit:Setup(panel)          in Build: the saved settings, the felt
--   ui.status = kit:Status(parent, width)    the status line (kit:SetStatus)
--   kit:BetRow(parent, opts)       the chip buttons (UI.BetRow's opts)
--   kit:AddBet(amount)  kit:Record(bet, payout, mult)  kit:StatsText()
--   kit:FreshBet()                 a bet that fits your chips again (OnShow)

local ns = CowCasino.ns

local SK = {}
ns.SoloKit = SK

local Kit = {}
Kit.__index = Kit

function SK.New(game, spec)
    local kit = setmetatable({ game = game, spec = spec }, Kit)
    game.defaultStats = spec.stats       -- (ns:ResetStats)
    game.dbKey = spec.key
    function game:IntroStats() return kit:StatsText() end
    function game:OnStatsReset() if kit.status then kit:Refresh() end end
    return kit
end

function Kit:Refresh() if self.spec.refresh then self.spec.refresh() end end

-- The saved settings (with their defaults), stats, sounds and the felt
-- (ns:SetupGame, UI.lua).
function Kit:Setup(panel)
    self.db = ns:SetupGame(panel, self.spec.key, self.spec)
    return self.db
end

function Kit:Status(parent, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if width then fs:SetWidth(width) end
    self.status = fs
    return fs
end

function Kit:SetStatus(text, r, g, b) ns.UI.SetStatus(self.status, text, r, g, b, self.game) end

function Kit:StatsText()
    if not self.db then return "" end
    return ns.UI.StatsLine(self.db.stats, self.spec.statsLine or {})
end

-- The bet, nudged by amount (from 0 up to the table's limit and your chips).
function Kit:AddBet(amount)
    if self.spec.canBet and not self.spec.canBet() then return end
    self.db.bet = ns:NudgeBet(self.db.bet, amount, self.spec.maxBet or 1000)
    self:Refresh()
end

function Kit:BetRow(parent, opts)
    opts = opts or {}
    local kit = self
    opts.onAdd = function(amount) kit:AddBet(amount) end
    local row = ns.UI.BetRow(parent, opts)
    self.betRow = row
    return row
end

-- One round's result into the stats (ns:RecordResult).
function Kit:Record(bet, payout, mult) return ns:RecordResult(self.db.stats, bet, payout, mult) end

-- Coming back to the game: a bet your chips cover again.
function Kit:FreshBet()
    if self.db then self.db.bet = ns:FreshBet(self.db.bet, self.spec.minBet or 1) end
end
