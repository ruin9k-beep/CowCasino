-- CowCasino: Texas Hold'em
-- No-limit hold'em against three computer players or your party. The blinds
-- are picked in Options (5/10 to start) and buy-ins are 20, 50 or 100 big
-- blinds; a party table uses the host's blinds and buy-in, free.
-- The table itself (betting, side pots, computer players, party play,
-- saving) is shared with Five-Card Draw: see PokerTable.lua.

local ns = CowCasino.ns

ns:RegisterGame(ns.NewPokerGame({
    id = "holdem",
    name = "Texas Hold'em",
    description = "No-limit poker against three computer players.\n|cff66ccffSupports Multiplayer|r",
    icon = "Interface\\AddOns\\CowCasino\\Art\\HoldemIcon",   -- painted (dev/art-src/make_game_icons.py)
    dealer = { idle = "Shuffle up and deal." },
    dbKey = "holdem",
    tag = "HE",                    -- first field of every Hold'em message
    say = "holdem",                -- the dealer's moments: holdemDeal, holdemFlop... (DEALERS.md)
    community = true,              -- two hole cards and a five-card board
    seats = 4,
    handSize = 2,
    streets = { "preflop", "flop", "turn", "river" },
    streetCodes = { idle = "i", preflop = "p", flop = "f", turn = "t", river = "r", showdown = "s" },
    lobbyText = "No-limit, blinds %s/%s, against three computer players.",
}))
