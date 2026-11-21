-- CowCasino: Chess, against the computer (Easy, Medium or Hard) or anyone
-- in your party or raid, on the board kit (BoardKit.lua). The rules are in
-- ChessRules.lua, the computer in ChessAI.lua.
local ns = CowCasino.ns
local R = ns.ChessRules

local Chess = ns.BoardKit.New({
    id = "chess",
    name = "Chess",
    description = "The full game, vs the computer or a friend.\n|cff66ccffSupports Multiplayer|r",
    icon = "Interface\\AddOns\\CowCasino\\Art\\ChessIcon",   -- painted (dev/art-src/make_game_icons.py)
    dealer = { idle = "Play the computer, or someone in your group." },
    tag = "CS",
    rules = R,
    atlas = { wK = 0, wQ = 1, wR = 2, wB = 3, wN = 4, wP = 5, bK = 6, bQ = 7, bR = 8, bB = 9, bN = 10, bP = 11 },
    -- captured pieces show beside the board, with what each is worth
    taken = { wQ = 9, wR = 5, wB = 3, wN = 3, wP = 1, bQ = 9, bR = 5, bB = 3, bN = 3, bP = 1 },
    light = { 0.91, 0.84, 0.69 },
    dark = { 0.55, 0.37, 0.22 },
    felt = { 0.10, 0.07, 0.05, 0.94 },
    rulesText = "Chess, the full game. White moves first.\n\n"
        .. "Vs the computer: pick a stake, Easy, Medium or Hard, and your side. A win pays double, a draw gives "
        .. "your stake back. Easy makes mistakes; Hard looks three moves ahead and never leaves a trade half "
        .. "done.\n\n"
        .. "Party game: against someone in your party or raid (both of you need CowCasino). It's free. "
        .. "Challenge your group and pick your side (or random); the first player to accept is "
        .. "your opponent.\n\n"
        .. "To move, click a piece, then where it goes. To castle, move the king two squares. A pawn reaching the "
        .. "far rank asks what to promote to.\n\n"
        .. "The game ends in checkmate, or a draw by stalemate, the fifty-move rule, the same position three "
        .. "times, or too few pieces to mate. You can also offer a draw, or resign (Resign asks again: click Confirm once its wait is up, 3 seconds unless you change it in Settings).\n\n"
        .. "A reload doesn't end the game: it picks up where you left off. In a party game, if the other player "
        .. "goes quiet for a while, you can call the game off.",
})

ns:RegisterGame(Chess)
