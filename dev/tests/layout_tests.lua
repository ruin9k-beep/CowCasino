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

-- the invite page and the pop-up
ns:OpenGame("chess")
ns.Lobby:ToggleInvitePage()
ns.Lobby:InviteNote("Invited Somebody to your group. The table invite follows once they join.")
Screen("the invite page", ns.frame.invitePage)
ns.frame.invitePage:Hide()
ns.Lobby:Toast({ id = "battleship", host = "Somebodywithalongname", invite = true })
Screen("the pop-up", env.CowCasinoLobbyToast)

H.Done("LAYOUT")
