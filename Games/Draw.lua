-- CowCasino: Five-Card Draw
-- No-limit five-card draw against four computer players, or up to five
-- players from your party (computer players can fill the empty seats).
-- Each player gets five cards; a betting round; everyone still in may swap
-- up to three cards (four if they keep an Ace); a second betting round;
-- showdown. The blinds are picked in Options (5/10 to start) and buy-ins are
-- 20, 50 or 100 big blinds; a party table uses the host's blinds and buy-in,
-- free. The table itself (betting, side pots, computer players, party play,
-- saving) is shared with Texas Hold'em: see PokerTable.lua.

local ns = CowCasino.ns

ns:RegisterGame(ns.NewPokerGame({
    id = "draw",
    name = "Five-Card Draw",
    description = "Classic draw poker against four computer players.\n|cff66ccffSupports Multiplayer|r",
    icon = "Interface\\AddOns\\CowCasino\\Art\\DrawIcon",     -- painted (dev/art-src/make_game_icons.py)
    dealer = { idle = "Five cards each. Ante up!" },
    dbKey = "draw",
    tag = "DR",                    -- first field of every Five-Card Draw message
    say = "draw",                  -- the dealer's moments: drawDeal, drawDraw... (DEALERS.md)
    community = false,             -- five cards each, and the draw
    seats = 5,
    handSize = 5,
    streets = { "first", "draw", "second" },
    streetCodes = { idle = "i", first = "p", draw = "d", second = "b", showdown = "s" },
    lobbyText = "No-limit five-card draw, blinds %s/%s, against four computer players.",
}))
