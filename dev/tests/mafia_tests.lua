-- Mafia: the rules (setups, the Mafia's pick, nights, votes, wins) and a
-- 20-player raid game between isolated clients: the roster in parts, the
-- deal (each client sees only what its player may), nights ending early once
-- everyone's acted, the Doctor and the Detective, Mafia talk, majority and
-- timed lynches, secret votes, a latecomer watching, the end and stats.
local H = dofile("harness.lua")
local Check = H.Check

local env, ns = H.Start(nil)
local R = ns.MafiaRules

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
local function Count(list)
  local c = {}
  for _, k in ipairs(list) do c[k] = (c[k] or 0) + 1 end
  return c
end
local s20 = Count(R.Setup(20, { mafia = "auto", specials = "GDHVBY" }))
Check("20 players, defaults: 5 Mafia (one the Godfather), the five specials, 10 Townsfolk",
  s20.G == 1 and s20.M == 4 and s20.D == 1 and s20.H == 1 and s20.V == 1 and s20.B == 1 and s20.Y == 1 and s20.T == 10 and not s20.J)
Check("...described plainly", R.Describe(R.Setup(20, { mafia = "auto", specials = "GDHVBY" }))
  == "5 Mafia (one the Godfather), Detective, Doctor, Vigilante, Bodyguard, Mayor, 10 Townsfolk")
local s5 = Count(R.Setup(5, { mafia = "auto", specials = "GDHVBYJ" }))
Check("5 players: one Mafia (no Godfather alone), specials while seats last", s5.M == 1 and not s5.G and (s5.T or 0) == 0
  and s5.D == 1 and s5.H == 1 and s5.V == 1 and s5.B == 1)
Check("Mafia never half the table", R.MafiaCount(10, 8) == 4 and R.MafiaCount(7, "auto") == 1 and R.MafiaCount(30, "auto") == 7)
local dealt = R.Deal(20, { mafia = 3, specials = "J" })
local d = Count((function() local t = {} for i = 1, 20 do table.insert(t, string.sub(dealt, i, i)) end return t end)())
Check("a deal is one letter a seat, with the setup's roles", string.len(dealt) == 20 and d.M == 3 and d.J == 1 and d.T == 16)

local roles = "GMTDHBVYTJ"   -- seats 1..10
Check("the Mafia's pick: the most picked", R.MafiaTarget({ [1] = 3, [2] = 5, [9] = 5 }, roles) == 5)
Check("...a tie goes the Godfather's way", R.MafiaTarget({ [1] = 3, [2] = 5 }, roles) == 3)
local all = {}
for s = 1, 10 do all[s] = true end
local deaths = R.Night(roles, all, { kill = 3, save = 3 })
Check("the Doctor's save stops the kill", table.getn(deaths) == 0)
deaths = R.Night(roles, all, { kill = 3, guard = 3 })
Check("the Bodyguard dies in place of the one they guard", table.getn(deaths) == 1 and deaths[1].seat == 6 and deaths[1].how == "guard")
deaths = R.Night(roles, all, { kill = 3, shoot = 1 })
Check("a kill and the Vigilante's shot", table.getn(deaths) == 2 and deaths[1].seat == 3 and deaths[2].seat == 1)
local _, c1 = R.Night(roles, all, { check = 1 })
local _, c2 = R.Night(roles, all, { check = 2 })
local _, c3 = R.Night(roles, all, { check = 3 })
Check("the Detective sees Mafia, but the Godfather as innocent", c2 == "m" and c1 == "t" and c3 == "t")
local _, total, majority = R.Tally({ [8] = 2, [3] = 2, [4] = 2, [5] = 2 }, roles, all)
Check("the Mayor's vote counts twice: 5 of 11 isn't a majority", total == 11 and majority == nil)
_, _, majority = R.Tally({ [8] = 2, [3] = 2, [4] = 2, [5] = 2, [6] = 2 }, roles, all)
Check("...6 of 11 is", majority == 2)
Check("most votes when time's up; a tie lynches nobody", R.Lynch({ [3] = 2, [4] = 2, [5] = 1 }, roles, all) == 2
  and R.Lynch({ [3] = 2, [4] = 1 }, roles, all) == nil and R.Lynch({ [3] = 0, [4] = 0, [5] = 2 }, roles, all) == nil)
Check("wins: no Mafia, Town; as many Mafia as others, Mafia", R.Winner(roles, { [3] = true, [4] = true }) == "town"
  and R.Winner(roles, { [1] = true, [3] = true }) == "mafia" and R.Winner(roles, all) == nil)

---------------------------------------------------------------------------
-- A 20-player raid
---------------------------------------------------------------------------
local party = H.Party({ game = "mafia", object = function(ns) return ns.Mafia end })
local NewClient, GroupChanged, Run = party.NewClient, party.GroupChanged, party.Run
local function InPanel(cl, o)
  local root = cl.P.panel
  while o do
    if not o.shown then return false end
    if o == root then return true end
    o = o.parent
  end
  return false
end
local function FindIn(cl, text)
  for _, o in ipairs(cl.env.all) do
    -- (text ending in * matches the start: "Play again*")
    if o.kind == "Button" and InPanel(cl, o) and (o.text == text or (string.sub(text, -1) == "*"
      and string.find(o.text or "", string.sub(text, 1, -2), 1, true) == 1)) then return o end
  end
end
local function PressIn(cl, text)
  local b = FindIn(cl, text)
  if not b then error(cl.name .. ": no button " .. text) end
  assert(b.enabled, cl.name .. ": button disabled: " .. text)
  cl.env.Fire(b, "OnClick", "LeftButton")
end

local NAMES = { "Ann", "Bob", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy", "Jon",
  "Kit", "Lou", "Max", "Ned", "Oda", "Pip", "Quin", "Rex", "Sue", "Tom" }
party.group = {}
for _, n in ipairs(NAMES) do table.insert(party.group, n) end
local clients = {}
for _, n in ipairs(NAMES) do table.insert(clients, NewClient(n)) end
GroupChanged()
local ann = clients[1]
PressIn(ann, "Host a game")
Run(0.5)
for i = 2, 20 do
  PressIn(clients[i], "Refresh")
  Run(0.3)
  PressIn(clients[i], "Join")
end
Run(2)
local room, AG, HS = ann.P.room, ann.P.G, ann.P.HS
local everyone = true
for _, cl in ipairs(clients) do if table.getn(cl.P.room.players) ~= 20 then everyone = false end end
Check("20 players in a raid: everyone's list has all 20 (the roster comes in parts)", table.getn(room.players) == 20 and everyone)
Check("the host sees the setup to come", string.find(ann.P.ui.preview.text, "5 Mafia") ~= nil)
PressIn(ann, "Deal the roles")
Run(1)
local roles20 = HS.roles
local function RoleOf(cl) return string.sub(roles20, cl.P.room:Player(cl.name).seat, cl.P.room:Player(cl.name).seat) end
local function Seat(cl) return cl.P.room:Player(cl.name).seat end
local function ByRole(letter)
  local out = {}
  for _, cl in ipairs(clients) do if RoleOf(cl) == letter then table.insert(out, cl) end end
  return out
end
local same = true
for _, cl in ipairs(clients) do if cl.P.G.roles ~= roles20 then same = false end end
Check("the deal reaches everyone; night 1 falls", same and AG.phase == "n" and AG.day == 1 and clients[7].P.G.phase == "n")
local town = ByRole("T")[1]
-- (checks below look at the host's screen too, when the host is that player)
local mafia = ByRole("M")
local godfather = ByRole("G")[1]
local function Sees(cl, other) return cl.P.ui.seats[Seat(other)].info.text end
Check("each client shows its own role", string.find(town.P.ui.role.text, "Townsfolk") ~= nil
  and string.find(godfather.P.ui.role.text, "Godfather") ~= nil)
Check("the Town can't see anyone's role", Sees(town, mafia[1]) == "" and Sees(town, godfather) == "")
Check("the Mafia see each other (and are told who)", string.find(Sees(mafia[1], godfather), "Godfather") ~= nil
  and string.find(mafia[1].P.ui.role.text, godfather.name) ~= nil and Sees(mafia[1], town) == "")
Check("the Mafia get a private talk box; the Town doesn't", InPanel(mafia[1], mafia[1].P.ui.talk) and not InPanel(town, town.P.ui.talk))

-- Mafia talk
mafia[1].env.TypeInto(mafia[1].P.ui.talk, "get the doctor")
mafia[1].env.Fire(mafia[1].P.ui.talk, "OnEnterPressed")
Run(1)
local function Logged(cl, pat) return string.find(table.concat(cl.P.G.log, "\n"), pat, 1, true) ~= nil end
Check("Mafia talk reaches the Mafia only", Logged(godfather, "get the doctor") and Logged(mafia[2], "get the doctor")
  and not Logged(town, "get the doctor"))

-- night 1: the Mafia go for the Mayor; the Doctor protects the Mayor; the Detective checks a Mafia
local doctor, detective, mayor = ByRole("H")[1], ByRole("D")[1], ByRole("Y")[1]
local function Click(cl, target)
  local s = target == 0 and 0 or Seat(target)
  if s == 0 then cl.env.Fire(cl.P.ui.skip, "OnClick", "LeftButton")
  else
    assert(cl.P.ui.seats[s].enabled, cl.name .. " can't click " .. target.name)
    cl.env.Fire(cl.P.ui.seats[s], "OnClick", "LeftButton")
  end
  Run(0.5)
end
Check("Mafia can't pick Mafia", not godfather.P.ui.seats[Seat(mafia[1])].enabled and godfather.P.ui.seats[Seat(mayor)].enabled)
Check("the Town can't click anyone at night", not town.P.ui.seats[Seat(mayor)].enabled)
for _, m in ipairs(mafia) do Click(m, mayor) end
Check("the Mafia see each other's picks", string.find(Sees(godfather, mafia[1]), mayor.name) ~= nil
  and not string.find(Sees(town, mafia[1]), mayor.name))
Click(godfather, mayor)
Click(doctor, mayor)
Click(detective, mafia[1])
Click(ByRole("B")[1], 0)
Check("the night waits for everyone who acts", AG.phase == "n")
Click(ByRole("V")[1], 0)
Run(2)
Check("...and ends as soon as they all have: day 1", AG.phase == "d" and clients[12].P.G.phase == "d")
Check("the Doctor saved the Mayor: nobody died", AG.alive[Seat(mayor)] and Logged(town, "nobody died"))
Check("the Detective (only) learns it's Mafia", Logged(detective, "is Mafia!") and not Logged(town, "Your check"))

-- day 1: a majority lynches a Mafia at once
local target = mafia[1]
local voters = 0
for _, cl in ipairs(clients) do
  if cl ~= target and AG.phase == "d" then
    Click(cl, target)
    voters = voters + 1
  end
end
Run(2)
Check("a majority lynches at once; the role is shown to all", AG.phase == "n" and not AG.alive[Seat(target)]
  and town.P.G.shown[Seat(target)] == "M" and voters <= 11 and Logged(town, "lynches " .. target.name))
Check("the dead see every role", string.find(Sees(target, town), "Townsfolk") ~= nil)

-- night 2: the Mafia kill the Doctor (the Doctor saves someone else)
for _, m in ipairs(ByRole("M")) do if m ~= target then Click(m, doctor) end end
Click(godfather, doctor)
Click(doctor, town)
Check("the Doctor can't protect the same player two nights running", not doctor.P.ui.seats[Seat(mayor)].enabled)
Click(detective, godfather)
Click(ByRole("B")[1], 0)
Click(ByRole("V")[1], 0)
Run(2)
Check("night 2: the Doctor is killed and revealed", AG.phase == "d" and not AG.alive[Seat(doctor)] and town.P.G.shown[Seat(doctor)] == "H")
Check("the Godfather checks out innocent", Logged(detective, godfather.name .. " is not Mafia"))

-- secret votes from here on (set by the host between games: change it now for the next one)
-- day 2: time runs out with a plurality
Click(clients[2] == godfather and clients[3] or clients[2], 0)
local before = 0
for s = 1, 20 do if AG.alive[s] then before = before + 1 end end
local lynchee = ByRole("T")[2]
local three = 0
for _, cl in ipairs(clients) do
  if three < 3 and cl ~= lynchee and AG.alive[Seat(cl)] and cl.P.G.choice == nil then
    Click(cl, lynchee)
    three = three + 1
  end
end
Run(2)
Check("votes show for everyone as they come in", string.find(town.P.ui.seats[Seat(lynchee)].name.text, "(3)", 1, true) ~= nil
  or (town == lynchee))
Run(125)
Check("time up: the most votes lynches", AG.phase == "n" and not AG.alive[Seat(lynchee)])

-- play it out: the town lynches the Mafia one by one; the Mafia stop killing
local guard = 0
while AG.phase ~= "o" and guard < 20 do
  guard = guard + 1
  if AG.phase == "n" then
    Run(31)
  elseif AG.phase == "d" then
    local bad
    for _, cl in ipairs(clients) do
      local r = RoleOf(cl)
      if AG.alive[Seat(cl)] and (r == "M" or r == "G") then bad = cl break end
    end
    for _, cl in ipairs(clients) do
      if AG.phase == "d" and cl ~= bad and AG.alive[Seat(cl)] then Click(cl, bad) end
    end
    Run(2)
  end
end
Check("the Town wins once the Mafia are gone", AG.phase == "o" and AG.winner == "town" and town.P.G.phase == "o")
Check("game over: every role shown to everyone", string.find(Sees(town, godfather), "Godfather") ~= nil)
Check("stats: a win for the Town, a loss for the Mafia", town.ns.db.mafia.stats.wins == 1 and godfather.ns.db.mafia.stats.wins == 0
  and godfather.ns.db.mafia.stats.games == 1)

-- next game: secret votes, and a latecomer who watches
party.group = {}
for _, n in ipairs(NAMES) do table.insert(party.group, n) end
table.insert(party.group, "Una")
local una = NewClient("Una")
GroupChanged()
ann.P.G.set.secret = true
PressIn(ann, "Deal again*")
Run(1)
PressIn(una, "Refresh")
Run(0.5)
PressIn(una, "Join")
Run(2)
Check("someone joining partway watches: no role, no clicks", una.P.room.mode == "client" and Seat(una) == 0
  and string.find(una.P.ui.role.text, "watching") ~= nil and not una.P.ui.seats[1].enabled)
Check("a new deal", ann.P.G.phase == "n" and ann.P.G.day == 1)
Run(31)
local voter = clients[5]
if AG.alive[Seat(voter)] then
  local other = clients[6]
  Click(voter, other)
  Run(2)
  Check("secret votes: others see only that someone voted", string.find(Sees(town == voter and clients[7] or town, voter), "(voted)", 1, true) ~= nil
    and not string.find(Sees(clients[8], voter), other.name, 1, true))
end

local s9 = Seat(clients[9])
local wasAlive = AG.alive[s9]
PressIn(clients[9], "Leave game")
Run(1)
Check("a player leaving mid-game dies, and their role is shown", not wasAlive or AG.phase == "o"
  or (not AG.alive[s9] and town.P.G.shown[s9] ~= nil))
PressIn(ann, "Close game")
Run(1)
Check("closing sends everyone back to the lobby", clients[20].P.room.mode == "lobby" and una.P.room.mode == "lobby")

Check("no addon message ran long", party.stats.longest <= 254, party.stats.longest)
H.Done("MAFIA")
