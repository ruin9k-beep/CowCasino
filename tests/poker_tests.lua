-- Hold'em tests, shared by the retail and 1.12 harnesses.
-- env: ns, Find, FindPrefix, Enabled, Flush, Press(button), SetStacked(cards)
return function(env)
  local ns, Flush, Press = env.ns, env.Flush, env.Press
  -- Only look at buttons inside the poker window that are on screen.
  local function InPoker(o)
    local root = ns.games.holdem.panel
    while o do
      if not o.shown then return false end
      if o == root then return true end
      o = o.parent
    end
    return false
  end
  local function Find(text)
    for _, o in ipairs(env.all) do
      if o.kind == "Button" and o.text == text and InPoker(o) then return o end
    end
  end
  local function FindPrefix(pre)
    for _, o in ipairs(env.all) do
      if o.kind == "Button" and string.sub(o.text, 1, string.len(pre)) == pre and InPoker(o) then return o end
    end
  end
  local gm = string.gmatch or string.gfind
  local P = ns.games.holdem
  local T = P.T
  local ok = true
  local function Check(name, cond, extra)
    io.write(string.format("%-46s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. extra) or ""))
    ok = ok and cond and true or false
  end

  local RANKS = { A = 1, J = 11, Q = 12, K = 13 }
  local SUITS = { s = 1, h = 2, d = 3, c = 4 }
  local function H(str)
    local out = {}
    for tok in gm(str, "%S+") do
      local r, s = string.sub(tok, 1, -2), string.sub(tok, -1)
      table.insert(out, { rank = RANKS[r] or tonumber(r), suit = SUITS[s] })
    end
    return out
  end
  local E, C, D = P.Evaluate, P.Compare, P.Describe

  -- Hand ranking
  local names = {
    { "As Ks Qs Js 10s 2d 3c", "Royal Flush" },
    { "5h 4h 3h 2h Ah Kd Kc", "Straight Flush, Five high" },
    { "9c 9d 9h 9s Ac 2d 3h", "Four of a Kind, Nines" },
    { "Kc Kd Kh 7s 7c 7d 2h", "Full House, Kings full of Sevens" },
    { "Ah 9h 6h 4h 2h Kd Kc", "Flush, Ace high" },
    { "Ad 2c 3h 4s 5d Kc Qh", "Straight, Five high" },
    { "10d Jc Qh Ks Ad 2c 2h", "Straight, Ace high" },
    { "8c 8d 8h Ks 3c 2d 6h", "Three of a Kind, Eights" },
    { "Kc Kd 7h 7s 3c 3d Ah", "Two Pair, Kings and Sevens" },
    { "Qc Qd 9h 7s 3c 2d 4h", "Pair of Queens" },
    { "Ac Jd 9h 7s 3c 2d 4h", "Ace high" },
  }
  local allNames = true
  for _, n in ipairs(names) do
    local got = D(E(H(n[1])))
    if got ~= n[2] then allNames = false; io.write("  ", n[1], " -> ", got, " (want ", n[2], ")\n") end
  end
  Check("holdem: 11 hand names", allNames)
  Check("holdem: kicker decides pair of aces", C(E(H("Ac Ad Kh 7s 3c 2d 4h")), E(H("Ac Ad Qh 7s 3c 2d 4h"))) == 1)
  Check("holdem: third pair plays as two-pair kicker", C(E(H("Kc Kd 7h 7s 3c 3d Ah")), E(H("Kc Kd 7h 7s 3c 3d Qh"))) == 1)
  Check("holdem: board plays = split", C(E(H("As Ks Qs Js 10s 2d 3c")), E(H("As Ks Qs Js 10s 4d 5c"))) == 0)
  Check("holdem: flush beats straight", C(E(H("Ah 9h 6h 4h 2h Kd Kc")), E(H("10d Jc Qh Ks Ad 2c 2h"))) == 1)
  Check("holdem: six-high straight beats the wheel", C(E(H("2c 3h 4s 5d 6d Kc Qh")), E(H("Ad 2c 3h 4s 5d Kc Qh"))) == 1)
  Check("holdem: full house from two sets", D(E(H("9c 9d 9h 4s 4c 4d Ah"))) == "Full House, Nines full of Fours")

  P.SetSims(3000)
  local eqAA, eq72 = P.Equity(H("Ac Ad"), {}, 1), P.Equity(H("7c 2d"), {}, 1)
  Check("holdem: equity AA vs 1 (~0.85)", eqAA > 0.80 and eqAA < 0.90, string.format("%.3f", eqAA))
  Check("holdem: equity 72o vs 1 (~0.35)", eq72 > 0.29 and eq72 < 0.41, string.format("%.3f", eq72))
  P.SetSims(20)

  -- Playing hands through the UI
  ns:OpenGame("holdem")
  ns.db.chips = 1000
  local realDecide = P.Decide
  local script = {}
  P.Decide = function(p)
    local q = script[p.seat]
    local a = q and table.remove(q, 1)
    if not a then
      if T.currentBet - p.bet > 0 then return "call" end
      return "check"
    end
    if a == "allin" then return "raise", 999999 end
    if type(a) == "number" then return "raise", a end
    return a
  end

  local function MyTurn() return T.street ~= "idle" and T.actor == 1 end
  local function RaiseButton() return FindPrefix("Raise to") or FindPrefix("Bet") or (function()
      local found
      for _, o in ipairs(env.all) do
        if o.kind == "Button" and string.sub(o.text, 1, 6) == "All-in" and InPoker(o) then found = o end
      end
      return found end)() end
  local function Human(a)
    local rb = RaiseButton()
    if (a == "min" or a == "max" or a == "plus") and not (rb and rb.enabled) then a = "call" end
    if a == "fold" then Press(Find("Fold"))
    elseif a == "call" then Press(FindPrefix("Call") or Find("Check") or FindPrefix("All-in"))
    elseif a == "min" then Press(RaiseButton())
    elseif a == "max" then Press(Find("Max")); Press(RaiseButton())
    elseif a == "plus" then Press(Find("+")); Press(RaiseButton())
    end
    Flush()
  end
  local function Play(humanScript)
    local guard = 0
    while T.street ~= "idle" do
      guard = guard + 1
      assert(guard < 200, "hand never finished")
      if MyTurn() then
        Human(table.remove(humanScript, 1) or "call")
      else
        Flush()
      end
    end
  end
  local function Deal(button, cards, stacks)
    T.button = button - 1
    if T.button < 1 then T.button = 4 end
    if stacks then for i = 1, 4 do T.seats[i].stack = stacks[i] end end
    env.SetStacked(cards)
    Press(Find("Deal"))
  end
  local function Stacks() local s = {}; for i = 1, 4 do s[i] = T.seats[i].stack end return s end
  local function Sum() local s = 0; for i = 1, 4 do s = s + T.seats[i].stack end return s end

  Press(Find("200"))          -- buy in; the first hand starts straight away
  Check("holdem: buy-in takes 200 from the wallet", ns.db.chips == 800 and T.seats[1] ~= nil)
  script = { [2] = { "fold" }, [3] = { "fold" }, [4] = { "fold" } }
  Play({ "fold" })
  for i = 2, 4 do script[i] = {} end

  -- 1) Everyone folds to your raise. Button = you, SB 2, BB 3, UTG 4.
  local junk = H("2c 3d 4h 5s 7c 8d 9h 10s Jc Qd Kh 2s 3h")
  script = { [2] = { "fold" }, [3] = { "fold" }, [4] = { "fold" } }
  Deal(1, junk, { 500, 500, 500, 500 })
  local before = 500
  Play({ "min" })
  Check("holdem: uncontested raise wins the blinds", T.seats[1].stack == before + 15, "stack " .. T.seats[1].stack)

  -- 2) Check it down; your aces win a 40 pot.
  for i = 2, 4 do script[i] = {} end
  -- deal order from seat 2: 2,3,4,1,2,3,4,1 then the board
  Deal(1, H("2c 3d 4h As 7c 8d 9h Ad Jc Qd Kh 5s 6h"), { 500, 500, 500, 500 })
  Play({ "call", "call", "call", "call" })
  Check("holdem: showdown, aces win 40", T.seats[1].stack == 530, "stack " .. T.seats[1].stack)
  Check("holdem: showdown reveals and names hands", T.reveal and T.seats[1].last == "Pair of Aces")

  -- 3) Side pots: 2 has 50, 3 has 100, you 200, 4 has 1000; all in.
  --    2 (aces) wins 200, 3 (kings) wins 150, you (queens) win 200, 4 loses 200.
  script = { [2] = { "allin" }, [3] = { "allin" }, [4] = { "call", "call" } }
  Deal(1, H("As Ks 7c Qs Ad Kd 2h Qd 3c 8h 9d Jc 4s"), { 200, 50, 100, 1000 })
  Play({ "max" })
  local s = Stacks()
  Check("holdem: side pots paid correctly", s[1] == 200 and s[2] == 200 and s[3] == 150 and s[4] == 800,
    string.format("%d %d %d %d", s[1], s[2], s[3], s[4]))

  -- 4) Short all-in doesn't reopen the betting for you.
  --    Button 4: you are SB and first after the flop. 4 has 40.
  script = { [2] = {}, [3] = {}, [4] = { "call", "allin" } }
  Deal(4, H("2c 3d 4h 5s 7c 8d 9h 10s Jc Qd Kh 2s 3h"), { 500, 500, 500, 40 })
  local sum0 = 500 + 500 + 500 + 40
  -- preflop: 3 calls, 4 calls, you complete, 2 checks
  while not MyTurn() do Flush() end
  Human("call")
  while not MyTurn() do Flush() end
  Human("plus")                         -- bet 20 on the flop
  while not MyTurn() do Flush() end     -- 2 and 3 call, 4 all-in for 30 (a raise of only 10)
  local raiseBtn = RaiseButton()
  Check("holdem: incomplete all-in raise doesn't reopen", T.seats[4].allIn and T.currentBet == 30
    and T.lastRaise == 20 and not raiseBtn.enabled and (FindPrefix("Call") or {}).enabled,
    string.format("to call %d", T.currentBet - T.seats[1].bet))
  Play({ "call" })
  Check("holdem: chips conserved in that hand", Sum() == sum0)

  -- 5) Long random session with the real computer players.
  local tally = { fold = 0, call = 0, check = 0, raise = 0 }
  local pre = { fold = 0, play = 0 }
  P.Decide = function(p)
    local act, to = realDecide(p)
    tally[act] = (tally[act] or 0) + 1
    if T.street == "preflop" then
      if act == "fold" then pre.fold = pre.fold + 1 else pre.play = pre.play + 1 end
    end
    return act, to
  end
  P.SetSims(150)
  math.randomseed(7)
  local hands, leaves, problems = 0, 0, 0
  local actions = { "fold", "call", "call", "call", "min", "plus", "max" }
  for n = 1, 600 do
    ns.db.chips = 100000
    if not T.seats[1] then Press(Find("500")) end
    if T.seats[1].stack <= 0 then Press(Find("Leave table")); Press(Find("500")) end
    -- Deal without running the computer players yet, so the chips can be counted.
    local dealBtn = Find("Deal")
    if T.street == "idle" and dealBtn and dealBtn.enabled then
      if env.FireOnly then env.FireOnly(dealBtn) else dealBtn.scripts.OnClick(dealBtn, "LeftButton") end
    end
    local total = T.pot
    for i = 1, 4 do total = total + T.seats[i].stack + T.seats[i].bet end
    local guard = 0
    while T.street ~= "idle" do
      guard = guard + 1
      if guard > 300 then problems = problems + 1; break end
      if MyTurn() then
        local a = actions[math.random(#actions)]
        local b
        if a == "fold" then b = Find("Fold")
        elseif a == "call" then b = FindPrefix("Call") or Find("Check") or FindPrefix("All-in")
        else b = nil end
        if b and b.enabled then Press(b); Flush() else Human(a) end
        if MyTurn() then Human("call") end
      else
        Flush()
      end
    end
    local after = 0
    for i = 1, 4 do after = after + T.seats[i].stack end
    if after ~= total then problems = problems + 1; io.write("  chip mismatch in hand ", n, ": ", total, " -> ", after, "\n") end
    for i = 1, 4 do if T.seats[i].stack < 0 then problems = problems + 1 end end
    hands = hands + 1
    if n % 150 == 0 then Press(Find("Leave table")); leaves = leaves + 1 end
  end
  io.write(string.format("  bot decisions: fold %d, check %d, call %d, raise %d; preflop fold rate %.0f%%\n",
    tally.fold, tally.check, tally.call, tally.raise, 100 * pre.fold / math.max(1, pre.fold + pre.play)))
  P.SetSims(20)
  Check("holdem: 600 random hands, chips conserved, none stuck", problems == 0,
    string.format("%d hands, %d problems", hands, problems))

  ns.db.chips = 100000
  -- Card art is a general setting now: Hold'em's Options only point to it,
  -- and switching packs in the CowCasino Options redraws the cards on the table.
  while T.street ~= "idle" do if MyTurn() then Human("fold") else Flush() end end
  if not T.seats[1] then Press(Find("500")) end
  local startArt = ns:GetCardArt().id
  Press(Find("Options"))
  local pokerPicker = false
  for _, o in ipairs(env.all) do if o.kind == "FontString" and InPoker(o) and o.text == "Card art" and o.shown then pokerPicker = true end end
  local pointer = false
  for _, o in ipairs(env.all) do if o.kind == "FontString" and InPoker(o) and o.text and string.find(o.text, "Card art is in the CowCasino Options", 1, true) then pointer = true end end
  Press(Find("Done"))
  Check("holdem: Options no longer has a card art picker, just a pointer", not pokerPicker and pointer)
  ns:ShowMenu()
  local function Vis(o) while o do if not o.shown then return false end; o = o.parent end; return true end
  local function Global(text) local b for _, o in ipairs(env.all) do if not b and o.kind == "Button" and o.text == text and Vis(o) then b = o end end return b end
  Press(Global("Options"))
  Press(Global(">"))                       -- the card art one (first on the page)
  local newArt = ns:GetCardArt().id
  Press(Global("Done"))
  ns:OpenGame("holdem")
  local redrawn = false
  for _, o in ipairs(env.all) do
    local skins = rawget(o, "skins")
    if skins and InPoker(o) and rawget(o, "card") and skins[newArt] and skins[newArt].shown
       and (not skins[startArt] or not skins[startArt].shown) then redrawn = true end
  end
  Check("holdem: card art picked in the CowCasino Options, table cards redraw", newArt ~= startArt and redrawn, startArt .. " -> " .. newArt)
  ns:SetCardArt(startArt)

  -- 6) Leaving pays the stack back into the wallet.
  if not T.seats[1] then Press(Find("500")) end
  while T.street ~= "idle" do if MyTurn() then Human("fold") else Flush() end end
  local stack, wallet = T.seats[1].stack, ns.db.chips
  Press(Find("Leave table"))
  Check("holdem: leaving returns the stack to the wallet", ns.db.chips == wallet + stack and T.seats[1] == nil and ns.db.holdem.seat == nil)

  -- 7) A reload in the middle of a hand cancels it and restores the stacks.
  ns.db.chips = 1000
  Press(Find("1,000") or Find("1000"))
  while T.street ~= "idle" do if MyTurn() then Human("fold") else Flush() end end
  local saved = Stacks()
  local dealBtn = Find("Deal")
  if env.FireOnly then env.FireOnly(dealBtn) else dealBtn.scripts.OnClick(dealBtn, "LeftButton") end
  Check("holdem: mid-hand state is marked", ns.db.holdem.seat.inHand == true and T.street ~= "idle")
  P:Build(CowCasino.ns.CreateFrame("Frame", nil, UIParent))
  local r = Stacks()
  Check("holdem: reload cancels the hand, stacks restored",
    T.street == "idle" and r[1] == saved[1] and r[2] == saved[2] and r[3] == saved[3] and r[4] == saved[4]
    and not ns.db.holdem.seat.inHand)
  Flush()
  Check("holdem: stale timers from the old hand do nothing", T.street == "idle")

  io.write(ok and "HOLDEM PASS\n" or "HOLDEM FAIL\n")
  return ok
end
