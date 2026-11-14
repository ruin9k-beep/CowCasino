-- Party Hold'em simulation: three isolated 1.12 clients (Host, Bob, Cid)
-- talking over a simulated party channel. Each client loads the real addon
-- into its own environment on top of the strict 1.12 mock.
local H = dofile("harness.lua")
local Check = H.Check

local party = H.Party({
  game = "holdem",
  object = function(ns) return ns.games.holdem end,
  onPart = function(name, part)
    if string.sub(part, 1, 5) == "HE;K;" then LAST_KICK = part end
    if string.sub(part, 1, 5) == "HE;P;" and name == "Host" then LAST_P = part end
  end,
})
local wire, stats, clients, byName = party.wire, party.stats, party.clients, party.byName
local InGroup, Others, NewClient, Deliver = party.InGroup, party.Others, party.NewClient, party.Deliver
local GroupChanged, Tick, Run = party.GroupChanged, party.Tick, party.Run

-- Buttons inside a client's poker window
local function InPoker(c, o)
  local root = c.P.panel
  while o do
    if not o.shown then return false end
    if o == root then return true end
    o = o.parent
  end
  return false
end
local function Find(c, text, prefix)
  for _, o in ipairs(c.env.all) do
    if o.kind == "Button" and InPoker(c, o) then
      if o.text == text or (prefix and string.sub(o.text, 1, string.len(text)) == text) then return o end
    end
  end
end
local function Press(c, text, prefix)
  local b = Find(c, text, prefix)
  assert(b, c.name .. ": no button " .. text)
  assert(b.enabled, c.name .. ": button disabled: " .. b.text)
  c.env.Fire(b, "OnClick", "LeftButton")
  return b
end
local function Enabled(c, text, prefix) local b = Find(c, text, prefix); return b ~= nil and b.enabled ~= nil end

local function MyTurn(c)
  local T = c.T
  local me = T.seats[T.mySeat]
  return T.street ~= "idle" and me and T.actor == T.mySeat and not me.folded and not me.allIn and not me.out
    and (not me.acted or me.bet < T.currentBet) and not (T.mode == "client" and T.sent == T.version)
end

local function TableChips(T)
  local s = T.pot
  for i = 1, 4 do s = s + T.seats[i].stack + T.seats[i].bet end
  return s
end

-- Table chat: a flyout for the players at your party table.
local host = NewClient("Host")
local bob = NewClient("Bob")
local cid = NewClient("Cid")
local dan = NewClient("Dan")      -- not in the party
for _, c in ipairs({ host, bob, cid, dan }) do c.P.SetSims(10) end
party.group = { "Host", "Bob", "Cid" }
GroupChanged()
Run(1)
local function C(c) return c.ns.Chat end
local function Arrow(c) return C(c).ui.toggle end
local function Fly(c) return C(c).ui.fly end
local function Vis(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Say(c, text)
  local box = C(c).ui.box
  c.env.Fire(box, "OnEditFocusGained")
  c.env.TypeInto(box, text)
  c.env.Fire(box, "OnEnterPressed")
end
local function Lines(c)
  local out = {}
  for _, r in ipairs(C(c).rows) do if not r.system then table.insert(out, (r.first and (r.name .. ": ") or "") .. r.text) end end
  return table.concat(out, " / ")
end
local sentChat = {}
for _, c in ipairs({ host, bob, cid, dan }) do
  c.env.SendChatMessage = function() error(c.name .. " used the game's chat") end
end

Check("no table, no chat arrow", not Vis(Arrow(host)) and not Vis(Arrow(bob)))
Press(host, "Play with your party")
Press(host, "Host a table")
Run(2)
Press(bob, "Play with your party")
Run(1)
Press(bob, "Join")
Run(8)
Check("host and bob are at the table", bob.T.mode == "client" and host.T.mode == "host")
Check("both get the chat arrow on the right of the window", Vis(Arrow(host)) and Vis(Arrow(bob))
  and Arrow(host).anchor[3] == "RIGHT")
Check("cid (in the party.group, not at the table) gets none", not Vis(Arrow(cid)))
Check("chat starts closed", not Vis(Fly(bob)))
bob.env.Fire(Arrow(bob), "OnClick", "LeftButton")
Check("the arrow opens the flyout beside the window", Vis(Fly(bob)) and Fly(bob).anchor[1] == "BOTTOMLEFT" and Fly(bob).anchor[3] == "BOTTOMRIGHT")
Check("it says whose table it is", C(bob).ui.where.text == "at Host's table")

Say(bob, "hello table")
Run(2)
Check("bob sees his own line", string.find(Lines(bob), "Bob: hello table", 1, true) ~= nil, Lines(bob))
Check("host gets it", string.find(Lines(host), "Bob: hello table", 1, true) ~= nil, Lines(host))
Check("cid and dan don't", Lines(cid) == "" and Lines(dan) == "")
Check("host's chat opened when bob talked", Vis(Fly(host)))
Check("the box is empty again and lets go of the keyboard", C(bob).ui.box.text == "" and not C(bob).ui.box.focus)
-- portrait beside the line
local row1
for _, r in ipairs(C(host).ui.rows) do if r.name.text and string.find(r.name.text, "Bob", 1, true) then row1 = r end end
Check("bob's line on host's screen has his 3D portrait (party1)", row1 and Vis(row1.portrait) and row1.portrait.unit == "party1")
host.env.UNIT_VISIBLE.party1 = false
C(host):Refresh()
Check("out of range: no portrait, a blank space instead", not Vis(row1.portrait) and Vis(row1.blank))
host.env.UNIT_VISIBLE.party1 = nil
C(host):Refresh()
Check("back in range: the portrait comes back", Vis(row1.portrait))
Say(host, "hi bob")
Run(2)
Check("host's own line shows his own portrait", (function()
  for _, r in ipairs(C(host).ui.rows) do if r.name.text and string.find(r.name.text, "Host", 1, true) then return r.portrait.unit == "player" end end end)())
Check("bob gets host's line", string.find(Lines(bob), "Host: hi bob", 1, true) ~= nil)

-- Long and odd text
local long = string.rep("word ", 60)   -- 300 letters
Say(bob, long)
Run(3)
local rows = 0
for _, r in ipairs(C(host).rows) do if r.name == "Bob" and not r.system then rows = rows + 1 end end
Check("a long message is capped at 200 letters and wraps over rows", rows >= 3 and string.len(C(host).rows[table.getn(C(host).rows)].text) <= 90, rows)
Say(bob, "a|cffff0000red|r;semi")
Run(2)
local lastText = C(host).ui.rows[table.getn(C(host).ui.rows)].text.text
Check("color codes show as typed, and ; survives", lastText == "a||cffff0000red||r;semi", lastText)
local sent = stats.sent
Say(bob, "   ")
Run(1)
Check("an empty message isn't sent", stats.sent == sent)
-- Escape
c = bob
bob.env.Fire(C(bob).ui.box, "OnEditFocusGained"); C(bob).ui.box.focus = true
bob.env.TypeInto(C(bob).ui.box, "never mind")
bob.env.Fire(C(bob).ui.box, "OnEscapePressed")
Check("Escape clears the box and lets go", C(bob).ui.box.text == "" and not C(bob).ui.box.focus)

-- Spoofing: cid (in the party.group, not seated) can't post into the table
table.insert(wire, { from = "Cid", prefix = "CowCasino", text = "CH;HE;Host;" .. host.T.tid .. ";i'm not seated", chan = "PARTY" })
Run(1)
Check("someone not seated at the table can't post to it", string.find(Lines(host), "not seated", 1, true) == nil)
-- Other table keys are ignored
table.insert(wire, { from = "Bob", prefix = "CowCasino", text = "CH;HE;Host;99999;wrong table", chan = "PARTY" })
Run(1)
Check("messages for another table are ignored", string.find(Lines(host), "wrong table", 1, true) == nil)

-- Closed chat with auto-open off: a count on the arrow
C(host):SetOpen(false)
C(host):Settings().autoOpen = false
Say(bob, "you there?")
Run(2)
Check("auto-open off: the arrow shows how many are unread", not Vis(Fly(host)) and C(host).ui.badge.text == "|cff40ff401|r")
host.env.Fire(Arrow(host), "OnClick", "LeftButton")
Check("opening clears the count", Vis(Fly(host)) and C(host).ui.badge.text == "")

-- Options: side, show
host.ns:ShowMenu()
Run(1)
local function FindAll(c, text) local o2 for _, o in ipairs(c.env.all) do if o.kind == "Button" and o.text == text and Vis(o) then o2 = o end end return o2 end
host.env.Fire(FindAll(host, "Options"), "OnClick", "LeftButton")
host.env.Fire(FindAll(host, "Chat"), "OnClick", "LeftButton")
local found = false
for _, f in ipairs(host.env.all) do if f.kind == "FontString" and Vis(f) and f.text == "Right side" then found = true end end
Check("Options shows the chat settings", found)
local sideBtn
for _, o in ipairs(host.env.all) do if o.kind == "Button" and o.text == ">" and Vis(o) and o.anchor and o.anchor[1] == "LEFT" and o.anchor[2].text == "Right side" then sideBtn = o end end
host.env.Fire(sideBtn, "OnClick", "LeftButton")
Check("switching to the left moves the arrow and flyout to the left", Arrow(host).anchor[3] == "LEFT" and Fly(host).anchor[1] == "BOTTOMRIGHT" and Fly(host).anchor[3] == "BOTTOMLEFT"
  and C(host):Settings().side == "left")
local showBox
for _, o in ipairs(host.env.all) do if o.kind == "CheckButton" and Vis(o) and o.checked then showBox = showBox or o end end
host.env.Fire(showBox, "OnClick", "LeftButton")
showBox.checked = nil; host.env.Fire(showBox, "OnClick", "LeftButton")
Check("turning the chat off hides the arrow and flyout", not Vis(Arrow(host)) and not Vis(Fly(host)) and C(host):Settings().enabled == false)
C(host):Settings().enabled = true
host.ns.optionsPage:Hide()
host.ns:OpenGame("holdem")
C(host):Refresh()

-- Leaving the table: chat goes away, and a new table starts fresh
for _ = 1, 600 do
  Tick(0.2)
  if bob.T.street == "idle" and Find(bob, "Leave table", true) and Find(bob, "Leave table", true).enabled then break end
  if MyTurn(bob) then Press(bob, "Fold") end
  if MyTurn(host) then
    local b = (Enabled(host, "Check") and "Check") or (Find(host, "Call", true) and Find(host, "Call", true).enabled and "Call") or "Fold"
    Press(host, b, true)
  end
end
Press(bob, "Leave table", true)
Run(3)
Check("bob left: his arrow is gone", bob.T.mode ~= "client" and not Vis(Arrow(bob)))

-- Party Blackjack uses the same chat
host.ns:OpenGame("holdem")
local closeB = Find(host, "Close table", true) or Find(host, "Leave table", true)
if closeB then host.env.Fire(closeB, "OnClick", "LeftButton") end
Run(12)
host.ns:OpenGame("blackjack"); bob.ns:OpenGame("blackjack")
local function PressAny(c, text)
  for _, o in ipairs(c.env.all) do if o.kind == "Button" and o.text == text and Vis(o) and o.enabled then c.env.Fire(o, "OnClick", "LeftButton") return true end end
end
PressAny(host, "Party play"); PressAny(host, "Host a table"); Run(2)
PressAny(bob, "Party play"); Run(2)
PressAny(bob, "Join"); Run(8)
Check("blackjack party table: both have the chat arrow", bob.ns.PartyBlackjack.T.mode == "client" and Vis(Arrow(host)) and Vis(Arrow(bob)))
Check("a new table starts with a fresh chat", string.find(Lines(bob), "hello table", 1, true) == nil)
bob.env.Fire(Arrow(bob), "OnClick", "LeftButton")
Say(bob, "hit me")
Run(2)
Check("blackjack table chat reaches the host", string.find(Lines(host), "Bob: hit me", 1, true) ~= nil, Lines(host))
Check("cid still sees nothing", Lines(cid) == "")

H.Done("CHAT")
