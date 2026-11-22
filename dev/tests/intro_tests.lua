-- The intro screen, part of the core (Intro.lua): every game has one; it
-- shows when a game is opened between rounds; Play goes to the field; the
-- window's back button steps back (field, intro, game list); and a round in
-- progress keeps the field up.
local H = dofile("harness.lua")
local Check = H.Check
local env, ns = H.Start(nil)
env.CowCasinoFrame:Show()
local back = ns.frame.back
local function Back() env.Fire(back, "OnClick", "LeftButton") end

-- every game
local missing = {}
for _, id in ipairs(ns.gameOrder) do
  ns:OpenGame(id)
  local g = ns.games[id]
  if not (g.intro and g.intro:IsShown()) then table.insert(missing, id) end
  ns:ShowMenu()
end
Check("every game opens on its intro", table.getn(missing) == 0, table.concat(missing, ", "))

-- a solo game's default intro: name, description, Play
ns:OpenGame("mines")
local G = ns.games.mines
local intro = G.intro
Check("...with its stats at the foot", (intro.stats.text or "") ~= "", intro.stats.text)
Check("Mines gets the simple intro: its description and Play", intro:IsShown()
  and intro.blurb.text == G.description and intro.soloGo.text == "Play" and back.text == "< Games")
env.Fire(intro.soloGo, "OnClick", "LeftButton")
Check("Play goes to the field, and the back button says < Setup", not intro:IsShown() and back.text == "< Setup")
Back()
Check("< Setup goes back to the intro", intro:IsShown() and back.text == "< Games" and ns.currentGame == "mines")
Back()
Check("...and < Games from there to the game list", ns.currentGame == nil and ns.frame.menu.shown)

-- a round in progress keeps the field
ns:OpenGame("mines")
env.Fire(G.intro.soloGo, "OnClick", "LeftButton")
local saved = G.ChipsInPlay
G.ChipsInPlay = function() return true end
H.Tick(0.3)
Check("mid-round: no intro, and back goes to the games", not intro:IsShown() and back.text == "< Games")
ns:ShowMenu()
ns:OpenGame("mines")
Check("...opening the game mid-round goes straight to the field", not intro:IsShown())
G.ChipsInPlay = saved
H.Tick(0.3)
Check("...once it's over, back says < Setup again", back.text == "< Setup")

-- a game whose intro is all there is away from a table (poker)
ns:ShowMenu()
ns:OpenGame("holdem")
local P = ns.games.holdem
Check("Hold'em away from a table: the intro, and it stays", P.intro:IsShown() and ns:IntroState(P) == "intro")
Back()
Check("...so back goes straight to the games", ns.currentGame == nil)

-- Blackjack and Craps can skip it (Options > Settings)
for _, id in ipairs({ "blackjack", "craps" }) do
  ns:OpenGame(id)
  local g = ns.games[id]
  g.options:Show()
  local function Under(o, root) while o do if o == root then return true end o = o.parent end return false end
  local cbox
  for _, o in ipairs(env.all) do
    if o.kind == "FontString" and Under(o, g.options) and o.text == "Go straight to the table (skip the intro)" then
      local r = o.points and o.points[1] and o.points[1][2]
      if r and r.kind == "CheckButton" then cbox = r end
    end
  end
  Check(g.name .. ": Options has Go straight to the table", cbox ~= nil)
  cbox:SetChecked(1); env.Fire(cbox, "OnClick", "LeftButton")
  g.options:Hide()
  ns:ShowMenu()
  ns:OpenGame(id)
  Check(g.name .. ": ...ticked, opening it goes straight to the table", not g.intro:IsShown() and back.text == "< Setup")
  Back()
  Check(g.name .. ": ...and < Setup still goes to the intro", g.intro:IsShown())
  cbox:SetChecked(nil); env.Fire(cbox, "OnClick", "LeftButton")
  ns:ShowMenu()
  ns:OpenGame(id)
  Check(g.name .. ": ...unticked, it's the intro again", g.intro:IsShown())
  ns:ShowMenu()
end

H.Done("INTRO")
