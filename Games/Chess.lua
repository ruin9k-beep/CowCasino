-- CowCasino: Chess, against anyone in your party or raid, on the board kit
-- (BoardKit.lua). The rules are in ChessRules.lua.
local ns = CowCasino.ns
local R = ns.ChessRules

local Chess = ns.BoardKit.New({
    id = "chess",
    name = "Chess",
    description = "The full game, against a friend in your group.\n|cff66ccffSupports Multiplayer|r",
    icon = "Interface\\AddOns\\CowCasino\\Art\\ChessIcon",   -- painted (dev/art-src/make_game_icons.py)
    dealer = { idle = "Chess? Find a worthy opponent in your group." },
    tag = "CS",
    rules = R,
    atlas = { wK = 0, wQ = 1, wR = 2, wB = 3, wN = 4, wP = 5, bK = 6, bQ = 7, bR = 8, bB = 9, bN = 10, bP = 11 },
    light = { 0.91, 0.84, 0.69 },
    dark = { 0.55, 0.37, 0.22 },
    felt = { 0.10, 0.07, 0.05, 0.94 },
    rulesText = "Chess, against someone in your party or raid (both of you need CowCasino). It's free: just for "
        .. "bragging rights.\n\n"
        .. "Challenge your group and pick your side (or random); the first player to accept is your opponent. "
        .. "White moves first.\n\n"
        .. "To move, click a piece, then where it goes. To castle, move the king two squares. A pawn reaching the "
        .. "far rank asks what to promote to.\n\n"
        .. "The game ends in checkmate, or a draw by stalemate, the fifty-move rule, the same position three "
        .. "times, or too few pieces to mate. You can also offer a draw, or resign.\n\n"
        .. "A reload doesn't end the game: it picks up where you left off. If the other player goes quiet for a "
        .. "while, you can call the game off.",
})

ns:RegisterGame(Chess)
