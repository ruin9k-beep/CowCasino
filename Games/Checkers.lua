-- CowCasino: Checkers. American checkers on the board kit (BoardKit.lua):
-- play the computer for chips, or anyone in your party or raid for free.
-- The rules are in CheckersRules.lua.
local ns = CowCasino.ns
local R = ns.CheckersRules

local Checkers = ns.BoardKit.New({
    id = "checkers",
    name = "Checkers",
    description = "Jump, crown and clear the board, vs the computer.\n|cff66ccffSupports Multiplayer|r",
    icon = "Interface\\AddOns\\CowCasino\\Art\\CheckersIcon",   -- painted (dev/art-src/make_game_icons.py)
    dealer = { idle = "Black moves first." },
    tag = "CK",
    rules = R,
    atlas = { bM = 12, bK = 13, rM = 14, rK = 15 },
    -- captured pieces show beside the board (kings first); the lead counts pieces
    taken = { bK = 1, bM = 1, rK = 1, rM = 1 },
    light = { 0.86, 0.78, 0.62 },
    dark = { 0.24, 0.36, 0.22 },
    -- other piece sets (Options > Settings), painted by dev/art-src/make_board_sets.py;
    -- the faction set's men wear the client's own faction emblems
    sets = {
        { key = "faction", name = "Horde vs Alliance", texture = "Interface\\AddOns\\CowCasino\\Art\\BoardPiecesFaction", rows = 4,
            light = { 0.77, 0.74, 0.66 }, dark = { 0.29, 0.30, 0.33 },
            names = { b = "Alliance", r = "Horde" }, note = "The Alliance plays Black (moves first), the Horde Red.",
            emblems = { bM = { "Interface\\TargetingFrame\\UI-PVP-Alliance", 0, 0.625, 0, 0.625 },
                        rM = { "Interface\\TargetingFrame\\UI-PVP-Horde", 0, 0.625, 0, 0.625 } } },
        { key = "goblin", name = "Goblins vs Gnomes", texture = "Interface\\AddOns\\CowCasino\\Art\\BoardPiecesGoblin", rows = 4,
            light = { 0.84, 0.71, 0.46 }, dark = { 0.36, 0.26, 0.17 },
            names = { b = "Gnomes", r = "Goblins" }, note = "The Gnomes play Black (move first), the Goblins Red." },
    },
    felt = { 0.07, 0.13, 0.07, 0.94 },
    rulesText = "American checkers. Black moves first. Pieces move one square diagonally, on the dark squares: "
        .. "men only forward, kings either way. A man that reaches the far row is crowned a king (and that ends "
        .. "its move).\n\n"
        .. "Jumps: jump an enemy piece by hopping over it to the empty square beyond, and keep jumping while you "
        .. "can. If you can jump, you must (pick which jump if there's more than one). Men only jump forward.\n\n"
        .. "You win when the other side can't move: no pieces left, or every piece blocked. Forty moves each with "
        .. "no jump and no man moved is a draw.\n\n"
        .. "To move, click a piece, then the square to go to (for a double jump, each landing square in turn).\n\n"
        .. "Vs the computer: pick a stake, Easy, Medium or Hard, and your side. A win pays double, a draw gives "
        .. "your stake back. Party game: free. Offer a draw or resign at any time (Resign asks again; set its wait in Settings).",
})

ns:RegisterGame(Checkers)
