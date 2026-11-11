local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return _G[k] end })
env.arg = { arg[1] }; env.SELECT_SAVED = select
assert(loadfile(os.getenv("MOCK") or "mock112.lua", "t", env))()
for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
env.CowCasinoFrame:Show()
local ns = env.CowCasino.ns
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Find(text) for _, o in ipairs(env.all) do if o.kind == "Button" and o.text and string.find(o.text, text, 1, true) == 1 and Visible(o) then return o end end end
local function Tick(sec) for _ = 1, math.floor(sec * 10 + 0.5) do env.CLOCK = env.CLOCK + 0.1; for _, o in ipairs(env.all) do if o.scripts.OnUpdate and Visible(o) then env.Fire(o, "OnUpdate", 0.1) end end end end
ns.db.chips = 25
ns:OpenGame("mines")
local db = ns.db.mines
db.bet = 25
ns.games.mines:OnShow()
env.Fire(Find("Bet"), "OnClick", "LeftButton")
io.write("active ", tostring(db.active ~= nil), " chips ", ns.db.chips, "\n")
local mine; for i = 1, 25 do if db.active.board[i] then mine = i end end
-- click the mine tile
local tiles = {}
for _, o in ipairs(env.all) do if o.kind == "Button" and o.w == 46 and o.h == 46 and Visible(o) then table.insert(tiles, o) end end
env.Fire(tiles[mine], "OnClick", "LeftButton")
io.write("after mine: active ", tostring(db.active ~= nil), " chips ", ns.db.chips, " inplay ", tostring(ns:ChipsInPlay()), " broke ", tostring(ns:IsBroke()), "\n")
for id, g in pairs(ns.games) do if g.ChipsInPlay and g:ChipsInPlay() then io.write("  in play: ", id, "\n") end end
for _, g in ipairs(ns.partyGames) do if g.ChipsInPlay and g:ChipsInPlay() then io.write("  party in play: ", g.id, "\n") end end
Tick(4)
io.write("rebuy page shown: ", tostring(ns.rebuyPage and ns.rebuyPage.shown), " current ", tostring(ns.currentGame), "\n")
