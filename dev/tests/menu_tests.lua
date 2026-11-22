-- The game menu: the filter tabs (All, Favorites, Recent, Multiplayer,
-- Cards, Board, Luck), favorites (right-click a tile) and recently played.
local H = dofile("harness.lua")
local Check = H.Check
local env, ns = H.Start(nil)
env.CowCasinoFrame:Show()
ns:ShowMenu()
local menu = ns.frame.menu

local function ShownTiles()
  local out = {}
  for id, tile in pairs(ns.menuRows) do if tile.shown then table.insert(out, id) end end
  table.sort(out)
  return out
end
local function Count() return table.getn(ShownTiles()) end
local function Filter(key) env.Fire(menu.filters[key], "OnClick", "LeftButton") end
Check("the filter tabs are there, All picked", menu.filters.all and menu.filters.fav and menu.filters.recent
  and menu.filters.mp and menu.filters.cards and menu.filters.board and menu.filters.luck and menu.filters.all.mark.shown
  and not menu.filters.cards.mark.shown)
Check("All shows every game", Count() == table.getn(ns.gameOrder), Count())
Filter("cards")
Check("Cards: the card games only", Count() == 6 and ns.menuRows.blackjack.shown and ns.menuRows.holdem.shown
  and not ns.menuRows.chess.shown and ns.db.menuFilter == "cards" and menu.filters.cards.mark.shown, Count())
Filter("board")
Check("Board: Checkers, Chess, Battleship", Count() == 3 and ns.menuRows.chess.shown and ns.menuRows.battleship.shown)
Filter("luck")
Check("Luck: the games of chance", ns.menuRows.slots.shown and ns.menuRows.roulette.shown and ns.menuRows.deathroll.shown
  and not ns.menuRows.blackjack.shown)
Filter("mp")
Check("Multiplayer: every game you can play with your group", Count() == 11 and ns.menuRows.sketch.shown
  and ns.menuRows.blackjack.shown and not ns.menuRows.keno.shown, Count())
Filter("fav")
Check("Favorites starts empty, with a word on how to add one", Count() == 0
  and string.find(menu.empty.text or "", "Right-click", 1, true) ~= nil)

-- right-click a tile to add it to (or take it out of) Favorites
Filter("all")
env.Fire(ns.menuRows.keno, "OnClick", "RightButton")
Check("right-click adds a game to Favorites (and doesn't open it)", ns:IsFavorite("keno") and ns.currentGame == nil
  and ns.menuRows.keno.fav.shown and not ns.menuRows.chess.fav.shown)
Check("...under All, favorites come first", ns:MenuList()[1] == "keno")
Filter("fav")
Check("...and Favorites shows it", Count() == 1 and ns.menuRows.keno.shown and (menu.empty.text or "") == "")
env.Fire(ns.menuRows.keno, "OnClick", "RightButton")
Check("right-click again takes it out", not ns:IsFavorite("keno") and Count() == 0)

-- Recent: newest first
Filter("recent")
Check("Recent starts empty", Count() == 0 and string.find(menu.empty.text or "", "play", 1, true) ~= nil)
ns:OpenGame("chess"); ns:ShowMenu()
ns:OpenGame("keno"); ns:ShowMenu()
ns:OpenGame("chess"); ns:ShowMenu()
Check("Recent lists what you've played, newest first", Count() == 2 and ns.db.recent[1] == "chess" and ns.db.recent[2] == "keno")
Check("...chess in the first spot", ns:MenuList()[1] == "chess" and ns:MenuList()[2] == "keno")

-- the filter is remembered
local saved = env.CowCasinoDB
local env2, ns2 = H.Start(saved)
env2.CowCasinoFrame:Show()
ns2:ShowMenu()
Check("the filter you picked is kept after a reload", ns2.db.menuFilter == "recent" and ns2.frame.menu.filters.recent.mark.shown)

H.Done("MENU")
