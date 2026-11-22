-- Layout: on every screen, nothing runs off it and nothing overlaps
-- (layout.lua works out where everything lands; text sizes are estimates,
-- so this catches collisions, not single pixels).
local H = dofile("harness.lua")
local L = dofile("layout.lua")
local Check = H.Check
local env, ns = H.Start(nil)
env.CowCasinoFrame:Show()
local optionsButton = ns.frame.optionsButton     -- (in the title row, above the game area, by design)

local function Screen(label, root, skip)
  skip = skip or {}
  table.insert(skip, optionsButton)
  local problems = L.Check(env, root, { skip = skip })
  Check(label .. ": nothing off it or overlapping", table.getn(problems) == 0, table.concat(problems, "; "))
end

local function Tabs(label, o)
  o:Show()
  local n = o.tabs and table.getn(o.tabs.frames) or 1
  for i = 1, n do
    if o.tabs then o.tabs:Select(i) end
    Screen(label .. " tab " .. i, o)
  end
  o:Hide()
end

-- the checker itself: it sees an overlap and a spill when there is one
do
  local box = env.CreateFrame("Frame", nil, ns.frame)
  box:SetWidth(200); box:SetHeight(100)
  box:SetPoint("CENTER", ns.frame, "CENTER", 0, 0)
  local a = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  a:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -10); a:SetText("Something long here")
  local b = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b:SetPoint("TOPLEFT", box, "TOPLEFT", 60, -14); b:SetText("Over it")
  local c = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 40, 0); c:SetText("Out past the edge")
  local found = L.Check(env, box)
  local joined = table.concat(found, "; ")
  Check("the checker sees an overlap and a spill", table.getn(found) == 2 and string.find(joined, "overlaps", 1, true) ~= nil
    and string.find(joined, "goes off the screen", 1, true) ~= nil, joined)
  box:Hide()
end

Screen("the game menu", ns.frame.menu)

-- every game: its intro (with every open-table row filled), its field, its Options
for _, id in ipairs(ns.gameOrder) do
  ns:OpenGame(id)
  local g = ns.games[id]
  local intro = g.intro
  Screen(g.name .. "'s intro", intro.frame)
  if intro.rows then
    local full = {}
    for i = 1, table.getn(intro.rows) do
      table.insert(full, { text = "Somebody" .. i .. ": blinds 10/20, 3 seated, 3 open", label = "Accept" })
    end
    intro:SetOffers(full)
    intro:SetNote("Tables open in your group:")
    intro:SetStatus("Your challenge is open. Waiting for someone to accept...")
    intro:SetStats("Played 123   Won 45   Lost 67   Drawn 8   Best streak 9")
    Screen(g.name .. "'s intro, with every row full", intro.frame)
    intro:SetOffers({})
  end
  g.introUp = false
  ns:UpdateIntro(g)
  Screen(g.name .. "'s field", g.panel, { intro.frame, g.options })
  Tabs(g.name .. "'s Options", g.options)
  ns:ShowMenu()
end

-- the main Options page
if ns.optionsPage then Tabs("CowCasino's Options", ns.optionsPage) end

-- board games in the middle of a game
for _, id in ipairs({ "chess", "checkers", "battleship" }) do
  ns:OpenGame(id)
  local g = ns.games[id]
  ns.db.chips = 5000
  g:SetMode("solo")
  g:Go()
  g:SetStatus("Your move. The computer took your knight on f6 after a long think about it.")
  g:Refresh()
  Screen(g.name .. " mid-game", g.panel, { g.intro.frame, g.options })
  ns:ShowMenu()
end

-- Deathroll in the middle of a duel (the portraits, the range and the rolls)
ns:OpenGame("deathroll")
ns.db.chips = 5000
env.Fire(ns.games.deathroll.intro.soloGo, "OnClick", "LeftButton")
H.Tick(0.3)
Screen("Deathroll mid-duel", ns.games.deathroll.panel, { ns.games.deathroll.intro.frame })
ns:ShowMenu()

-- party lobby pages
local function Under(o, root) while o do if o == root then return true end o = o.parent end return false end
local function ShownIn(o, root)
  while o do
    if not o.shown then return false end
    if o == root then return true end
    o = o.parent
  end
  return false
end
local function PressIn(root, prefix)
  for _, o in ipairs(env.all) do
    if o.kind == "Button" and type(o.text) == "string" and string.sub(o.text, 1, string.len(prefix)) == prefix
      and ShownIn(o, root) and o.enabled then
      env.Fire(o, "OnClick", "LeftButton")
      return true
    end
  end
  return false
end
for _, id in ipairs({ "blackjack", "craps" }) do
  ns:OpenGame(id)
  local g = ns.games[id]
  g:ShowParty()
  -- (the party screen covers the table with its own felt: just what's on it)
  local party = id == "blackjack" and ns.PartyBlackjack or ns.PartyCraps
  Screen(g.name .. "'s party lobby", party.panel)
  PressIn(g.panel, "< Back")
  ns:ShowMenu()
end
for _, id in ipairs({ "holdem", "draw" }) do
  ns:OpenGame(id)
  local g = ns.games[id]
  env.Fire(g.intro.hostGo, "OnClick", "LeftButton")
  Screen(g.name .. "'s party page", g.panel, { g.intro.frame, g.options })
  PressIn(g.panel, "Close")
  ns:ShowMenu()
end

-- card tables in the middle of a hand
ns.db.chips = 50000
local function Hand(id, steps)
  ns:OpenGame(id)
  local g = ns.games[id]
  if g.intro:IsShown() and g.intro.soloGo and g.intro.soloGo.shown then env.Fire(g.intro.soloGo, "OnClick", "LeftButton") end
  -- (a deal can end at once, on a natural say: deal again, a few times)
  for _ = 1, 6 do
    for _, step in ipairs(steps) do
      if type(step) == "number" then H.Tick(step) else PressIn(g.panel, step) end
    end
    if ns:IntroState(g) == "busy" then break end
    H.Tick(4)
  end
  Check(g.name .. ": a hand is really on (for the next check)", ns:IntroState(g) == "busy" and not g.intro:IsShown())
  Screen(g.name .. " mid-hand", g.panel, { g.intro.frame, g.options })
  ns:ShowMenu()
end
Hand("blackjack", { "Deal", 0.5 })
Hand("videopoker", { "Deal", 0.5 })
Hand("threecard", { "Deal", 0.5 })
Hand("hilo", { "25", "Bet", 0.5 })
-- the poker tables: buy in at a table against the computer and let a hand get going
for _, id in ipairs({ "holdem", "draw" }) do
  ns:OpenGame(id)
  local g = ns.games[id]
  PressIn(g.intro.soloRow, "")     -- the first buy-in
  H.Tick(3)
  Check(g.name .. ": seated at a table (for the next check)", ns:IntroState(g) == "busy")
  Screen(g.name .. " at a table", g.panel, { g.intro.frame, g.options })
  ns:ShowMenu()
end

-- the invite page and the pop-up
ns:OpenGame("chess")
ns.Lobby:ToggleInvitePage()
ns.Lobby:InviteNote("Invited Somebody to your group. The table invite follows once they join.")
Screen("the invite page", ns.frame.invitePage)
ns.frame.invitePage:Hide()
ns.Lobby:Toast({ id = "battleship", host = "Somebodywithalongname", invite = true })
Screen("the pop-up", env.CowCasinoLobbyToast)

H.Done("LAYOUT")
