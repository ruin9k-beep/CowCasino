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
    light = { 0.86, 0.78, 0.62 },
    dark = { 0.24, 0.36, 0.22 },
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
        .. "your stake back. Party game: free. Offer a draw or resign at any time (Resign asks again: click Confirm once its 3 seconds are up).",
})

ns:RegisterGame(Checkers)
