-- The lobby hub (Lobby.lua): pop-ups when someone in the group opens a table
-- or invites you (click to open the game and join), badges on the minimap
-- button and the tiles, and the Invite button and page while you host.
local H = dofile("harness.lua")
local Check = H.Check

local party = H.Party({ game = "chess", object = function(ns) return ns.games.chess end })
local NewClient, GroupChanged, Run = party.NewClient, party.GroupChanged, party.Run

local function Shown(o) while o do if not o.shown then return false end o = o.parent end return true end
local function FindButton(c, text, within)
  for _, o in ipairs(c.env.all) do
    if o.kind == "Button" and o.text == text and Shown(o) then
      if not within then return o end
      local p = o.parent
      while p do if p == within then return o end p = p.parent end
    end
  end
end
local function Press(c, text, within)
  local b = FindButton(c, text, within)
  assert(b, c.name .. ": no button " .. text)
  assert(b.enabled, c.name .. ": button disabled: " .. text)
  c.env.Fire(b, "OnClick", "LeftButton")
end
local function Toast(c)
  local t = rawget(c.env, "CowCasinoLobbyToast")
  return (t and t.shown) and t.text.text or nil
end
local function Has(text, part) return text ~= nil and string.find(text, part, 1, true) ~= nil end
local function ClickToast(c, button) c.env.Fire(c.env.CowCasinoLobbyToast, "OnClick", button or "LeftButton") end
local function Badge(f) return f and f.lobbyBadge and f.lobbyBadge.shown and f.lobbyBadge.text.text or nil end

party.group = { "Host", "Guest" }
local host = NewClient("Host")
local guest = NewClient("Guest")
GroupChanged()
guest.ns:ShowMenu()

Check("every multiplayer game is hooked up to the lobby", (function()
  for _, id in ipairs({ "blackjack", "craps", "holdem", "draw", "deathroll", "checkers", "chess", "battleship",
    "sketch", "hangman", "mafia" }) do
    if not host.ns.Lobby.specs[id] then return false end
  end
  return true
end)())

---------------------------------------------------------------------------
-- A challenge: pop-up, badges, click to join
---------------------------------------------------------------------------
host.P:SetMode("party")
Press(host, "Challenge the group")
Run(2)
Check("a challenge pops up for the rest of the group", Has(Toast(guest), "Host challenges the group to")
  and Has(Toast(guest), "Chess"), Toast(guest))
Check("...but not for the one who posted it", Toast(host) == nil)
Check("...the minimap button and Chess's tile carry a count", Badge(guest.ns.minimapButton) == "1"
  and Badge(guest.ns.menuRows.chess) == "1" and Badge(guest.ns.menuRows.checkers) == nil)
Check("the host gets an Invite button in the title row", host.ns.frame.inviteButton.shown
  and not guest.ns.frame.inviteButton.shown)
ClickToast(guest)
Run(2)
Check("clicking it opens Chess and takes the challenge", guest.ns.currentGame == "chess" and guest.P.S.game ~= nil
  and host.P.S.game ~= nil and host.P.S.game.opp == "Guest")
Check("...the pop-up and the badges go (you're playing)", Toast(guest) == nil and Badge(guest.ns.minimapButton) == nil)
Check("...and the Invite button goes with the challenge", not host.ns.frame.inviteButton.shown)
host.P:Resign()
Run(2)

---------------------------------------------------------------------------
-- Pop-ups off: invites still come; inviting by name
---------------------------------------------------------------------------
guest.ns:ShowMenu()
guest.ns.db.lobbyQuiet = true
host.ns:OpenGame("hangman")
Press(host, "Host a game")
Run(2)
Check("with pop-ups off, a new game shows no pop-up, only the badge", Toast(guest) == nil
  and Badge(guest.ns.menuRows.hangman) == "1")
Check("hosting Hangman: the Invite button is up", host.ns.frame.inviteButton.shown)
host.env.Fire(host.ns.frame.inviteButton, "OnClick", "LeftButton")
local page = host.ns.frame.invitePage
Check("Invite opens the invite page", page.shown and Has(page.title.text, "Hangman"))
page.box:SetText("guest")
Press(host, "Invite", page)
Run(1)
Check("inviting a group member by name (any case) says so", Has(page.note.text, "Invited Guest."), page.note.text)
Check("...and it pops up for them, even with pop-ups off", Has(Toast(guest), "Host invites you to")
  and Has(Toast(guest), "Hangman"), Toast(guest))
ClickToast(guest)
Run(3)
Check("clicking it opens Hangman and joins the host's game", guest.ns.currentGame == "hangman"
  and guest.ns.Hangman.room.mode == "client" and table.getn(host.ns.Hangman.room.players) == 2)

-- someone not in the group: a party invite first, then the table invite
page.box:SetText("Stranger")
Press(host, "Invite", page)
Check("inviting someone outside the group invites them to the group", Has(page.note.text, "to your group")
  and host.env.GROUP_INVITES[1] == "Stranger")
local stranger = NewClient("Stranger")
stranger.ns:ShowMenu()
stranger.ns.db.lobbyQuiet = true
party.group = { "Host", "Guest", "Stranger" }
GroupChanged()
Run(2)
Check("...and once they join it, the table invite pops up for them", Has(Toast(stranger), "Host invites you to")
  and Has(Toast(stranger), "Hangman"), Toast(stranger))
ClickToast(stranger, "RightButton")
Check("right-click closes a pop-up", Toast(stranger) == nil)
Press(host, "Invite the whole group", page)
Run(1)
Check("Invite the whole group reaches everyone not already in", Has(Toast(stranger), "Host invites you to")
  and Toast(guest) == nil)
ClickToast(stranger, "RightButton")
Press(host, "Done", page)
Check("Done closes the invite page", not page.shown)

---------------------------------------------------------------------------
-- Party tables shown inside another game's window, and the poker tables
---------------------------------------------------------------------------
guest.ns.db.lobbyQuiet = nil
host.ns:OpenGame("blackjack")
Press(host, "Party play")
Press(host, "Host a table")
Run(2)
Check("a party blackjack table pops up", Has(Toast(guest), "Host opened a") and Has(Toast(guest), "Blackjack"), Toast(guest))
ClickToast(guest)
Run(3)
Check("clicking it opens Blackjack's party play and takes a seat", guest.ns.currentGame == "blackjack"
  and guest.ns.PartyBlackjack.T.mode == "client" and host.ns.PartyBlackjack.T.seats[2].name == "Guest")

stranger.ns.db.lobbyQuiet = nil
host.ns:OpenGame("draw")
Press(host, "Play with your party")
Press(host, "Host a table")
Run(2)
local t = 0
while Toast(stranger) and not Has(Toast(stranger), "Five-Card Draw") and t < 10 do ClickToast(stranger, "RightButton"); t = t + 1 end
Check("a party draw table pops up", Has(Toast(stranger), "Five-Card Draw"), Toast(stranger))
ClickToast(stranger)
Run(3)
Check("clicking it opens Five-Card Draw's party tables and takes a seat", stranger.ns.currentGame == "draw"
  and stranger.ns.Lobby:Busy("draw"))

-- a pop-up goes away on its own
Run(25)
Check("pop-ups close themselves after a while", Toast(guest) == nil and Toast(stranger) == nil)

H.Done("LOBBY")
