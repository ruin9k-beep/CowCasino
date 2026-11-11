-- Blackjack: net chips stat, bigger player cards centered under the dealer
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-66s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end
local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
env.arg = { ADDON }; env.SELECT_SAVED = select
assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
env.CowCasinoFrame:Show()
local ns = env.CowCasino.ns
ns.db.chips = 1000000
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Find(text) for _, o in ipairs(env.all) do if o.kind == "Button" and o.text and string.find(o.text, text, 1, true) == 1 and Visible(o) and o.enabled then return o end end end
local function Press(text) local b = Find(text); if b then env.Fire(b, "OnClick", "LeftButton") end; return b ~= nil end
local function Tick(sec) for _ = 1, math.floor(sec * 10 + 0.5) do env.CLOCK = env.CLOCK + 0.1; for _, o in ipairs(env.all) do if o.scripts.OnUpdate and Visible(o) then env.Fire(o, "OnUpdate", 0.1) end end end end
local function Cards()
  local out = {}
  for _, o in ipairs(env.all) do if rawget(o, "skins") and rawget(o, "card") and Visible(o) then table.insert(out, o) end end
  return out
end
-- center of each visible row of cards, in panel coordinates
local function RowCenters()
  local rows, order = {}, {}
  for _, c in ipairs(Cards()) do
    local row = c.parent
    if not rows[row] then rows[row] = { lo = 1e9, hi = -1e9, w = c.w, h = c.h, n = 0 }; table.insert(order, row) end
    local r = rows[row]
    r.lo = math.min(r.lo, c.anchor[4]); r.hi = math.max(r.hi, c.anchor[4] + c.w); r.n = r.n + 1
  end
  local out = {}
  for _, row in ipairs(order) do
    local r = rows[row]
    -- row -> group frame -> (panel | player area -> panel)
    local x, f = 0, row.parent
    while f and f.anchor and f ~= ns.games.blackjack.panel do x = x + (f.anchor[4] or 0); f = f.anchor[2] end
    r.center = x + (r.lo + r.hi) / 2
    table.insert(out, r)
  end
  return out
end
ns:OpenGame("blackjack")
local bj = ns.db.blackjack
Check("old saves get a net stat of 0", bj.stats.net == 0, bj.stats.net)
local stats
for _, o in ipairs(env.all) do if o.kind == "FontString" and o.text and string.find(o.text, "^Rounds") then stats = o end end
Check("stats line shows Net", stats and string.find(stats.text, "Net |cffcccccc0", 1, true) ~= nil, stats and stats.text)

bj.bet = 25
Press("Deal 25"); Press("No thanks")
local dealer, player
for _, r in ipairs(RowCenters()) do if r.w == 46 then dealer = r elseif r.w == 55 then player = r end end
Check("dealer cards stay 46x64", dealer ~= nil and dealer.h == 64)
Check("your cards are 20% bigger (55x77)", player ~= nil and player.h == 77, player and (player.w .. "x" .. player.h))
Check("your cards are centered under the dealer's", dealer ~= nil and player ~= nil and math.abs(dealer.center - player.center) < 0.01,
  dealer and player and (dealer.center .. " vs " .. player.center))
for _ = 1, 6 do if not Press("Stand") then break end end
Tick(4)

-- net matches the chips won and lost over many rounds (splits, doubles, insurance included)
local start = ns.db.chips
local netStart = bj.stats.net
local splitCentered, splits = true, 0
for round = 1, 300 do
  Press("Deal 25")
  if math.mod(round, 3) == 0 then Press("Insure") else Press("No thanks") end
  if Find("Split") then
    Press("Split"); splits = splits + 1
    local rs = {}
    for _, r in ipairs(RowCenters()) do if r.w == 55 then table.insert(rs, r) end end
    if table.getn(rs) == 2 then
      local mid = (rs[1].center + rs[2].center) / 2
      if math.abs(mid - 176) > 4 then splitCentered = false end
    end
    for _ = 1, 3 do if Find("Split") then Press("Split") end end
  elseif math.mod(round, 4) == 0 and Find("Double") then Press("Double") end
  for _ = 1, 20 do if not Press("Stand") then break end end
  Tick(4)
end
Check("net stat = chips won minus chips lost", bj.stats.net - netStart == ns.db.chips - start, (bj.stats.net - netStart) .. " vs " .. (ns.db.chips - start))
Check("two split hands sit centered under the dealer", splitCentered and splits > 0, splits)
Check("stats line shows the signed net", string.find(stats.text, "Net ", 1, true) ~= nil and string.find(stats.text, ns:FormatChips(math.abs(bj.stats.net)) .. "|r$") ~= nil, stats.text)
ns.games.blackjack:ResetStats()
Check("a fresh stack starts net at 0", bj.stats.net == 0 and string.find(stats.text, "Net |cffcccccc0", 1, true) ~= nil)
io.write(ok and "BJ LAYOUT PASS\n" or "BJ LAYOUT FAIL\n")
os.exit(ok and 0 or 1)
