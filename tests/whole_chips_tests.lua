-- Chips are always whole: Blackjack's odd amounts round, old half chips round on load.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-62s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end
local function Start(saved)
  local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
  env.arg = { ADDON }; env.SELECT_SAVED = select
  assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
  env.CowCasinoDB = saved
  for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
  env.CowCasinoFrame:Show()
  return env, env.CowCasino.ns
end
local env, ns = Start(nil)
Check("blackjack on 25 pays 63 back (25 + 37.5 rounded up)", ns.BlackjackPay(25) == 63)
Check("blackjack on 10 pays 25 back (exact 3:2)", ns.BlackjackPay(10) == 25)
Check("surrendering 25 gives 13 back", ns.SurrenderBack(25) == 13)
Check("insuring 25 costs 13", ns.InsuranceCost(25) == 13)
Check("insuring 5 (the minimum bet) costs 3", ns.InsuranceCost(5) == 3)
ns:AddChips(2.5)
Check("adding a half chip can't make a fraction", ns.db.chips == math.floor(ns.db.chips))
local env2, ns2 = Start({ chips = 5.5, bestChips = 1037.5,
  partybj = { seat = { host = "Nobody", tid = "1", stack = 312.5 } },
  holdem = { seat = { stacks = { 412.5, 600, 1000, 900 }, bots = {}, button = 1 } } })
Check("a saved 5.5 chips loads as 6", ns2.db.chips == 6, ns2.db.chips)
Check("best chips 1037.5 loads as 1038", ns2.db.bestChips == 1038)
Check("a saved party blackjack stack of 312.5 becomes 313", ns2.db.partybj.seat.stack == 313)
Check("a saved hold'em stack of 412.5 becomes 413", ns2.db.holdem.seat.stacks[1] == 413)
-- Play many Blackjack rounds at an odd bet: the wallet never goes fractional
local env3, ns3 = Start(nil)
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Find(text) for _, o in ipairs(env3.all) do if o.kind == "Button" and o.text and string.find(o.text, text, 1, true) == 1 and Visible(o) and o.enabled then return o end end end
local function Tick(sec) for _ = 1, math.floor(sec * 10 + 0.5) do env3.CLOCK = env3.CLOCK + 0.1; for _, o in ipairs(env3.all) do if o.shown and o.scripts.OnUpdate and not o.parent then env3.Fire(o, "OnUpdate", 0.1) end end end end
ns3:OpenGame("blackjack")
ns3.db.chips = 100000
ns3.db.blackjack.bet = 25
local whole, rounds, insured = true, 0, 0
for _ = 1, 400 do
  local b = Find("Deal")
  if b then env3.Fire(b, "OnClick", "LeftButton"); rounds = rounds + 1 end
  local ins = Find("Insure")
  if ins then env3.Fire(ins, "OnClick", "LeftButton"); insured = insured + 1 end
  local sur = Find("Surrender")
  if sur and math.random() < 0.3 then env3.Fire(sur, "OnClick", "LeftButton") end
  local st = Find("Stand")
  if st then env3.Fire(st, "OnClick", "LeftButton") end
  Tick(1)
  if ns3.db.chips ~= math.floor(ns3.db.chips) then whole = false end
end
Check("400 rounds of Blackjack at 25 (with insurance and surrenders): always whole", whole and rounds > 100, rounds .. " rounds, " .. insured .. " insured")
io.write(ok and "WHOLE CHIPS PASS\n" or "WHOLE CHIPS FAIL\n")
os.exit(ok and 0 or 1)
