-- Blackjack splits, under real Lua 5.0 table sizes: the cards you see are the cards you have.
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
-- visible cards per hand row (rows in screen order, left to right)
local function Rows()
  local rows, order = {}, {}
  for _, o in ipairs(env.all) do
    if rawget(o, "skins") and rawget(o, "card") and Visible(o) and o.parent and o.parent ~= ns.frame then
      local row = o.parent
      if not rows[row] then rows[row] = 0; table.insert(order, row) end
      rows[row] = rows[row] + 1
    end
  end
  return rows, order
end
local function PlayerRows()
  -- the dealer's row is the topmost; player rows sit below it
  local rows, order = Rows()
  local out = {}
  for _, r in ipairs(order) do
    local y = r.parent and r.parent.anchor and r.parent.anchor[5] or 0
    table.insert(out, { row = r, n = rows[r], x = (r.parent.anchor and r.parent.anchor[4]) or 0, dealer = (r.parent == nil) })
  end
  return out
end
ns:OpenGame("blackjack")
ns.db.blackjack.bet = 25
local tried, splitOk, hitOk, standOk, rounds = 0, true, true, true, 0
local detail = ""
for round = 1, 600 do
  Press("Deal 25"); Press("No thanks")
  if Find("Split") then
    tried = tried + 1
    local before = 0
    for _, o in ipairs(env.all) do if rawget(o, "skins") and rawget(o, "card") and Visible(o) then before = before + 1 end end
    Press("Split")
    local after = 0
    for _, o in ipairs(env.all) do if rawget(o, "skins") and rawget(o, "card") and Visible(o) then after = after + 1 end end
    -- split: the pair is spread over two hands and hand 1 gets a card (aces: both do)
    if after ~= before + 1 and after ~= before + 2 then splitOk = false; detail = "after split " .. before .. " -> " .. after end
    if Find("Hit") then
      local n0 = after
      Press("Hit")
      local n1 = 0
      for _, o in ipairs(env.all) do if rawget(o, "skins") and rawget(o, "card") and Visible(o) then n1 = n1 + 1 end end
      -- the new card; plus hand 2's second card if the hit ends hand 1 (21 or bust)
      if n1 ~= n0 + 1 and n1 ~= n0 + 2 then hitOk = false; detail = "hit after split " .. n0 .. " -> " .. n1 end
    end
    -- play it out: every hand must finish and the round must settle
    for _ = 1, 20 do if not Press("Stand") then break end end
    Tick(4)
    if not Find("Deal 25") then standOk = false; detail = "round never settled after a split" end
    if tried >= 25 then break end
  else
    for _ = 1, 6 do if not Press("Stand") then break end end
    Tick(3)
  end
end
Check("found pairs to split", tried >= 10, tried)
Check("splitting spreads the pair over two hands, cards on screen", splitOk, detail)
Check("hitting a split hand shows the new card", hitOk, detail)
Check("every split round finishes and settles", standOk, detail)
io.write(ok and "SPLIT PASS\n" or "SPLIT FAIL\n")
os.exit(ok and 0 or 1)
