-- CowCasino dealer: Whiskers, the rat. A hidden dealer: he only turns up
-- (and takes over the table, the first time) for players who have Whiskers
-- the Rat as a companion: the Rat Cage (item 23015) in their bags, a
-- companion spell by that name, or the pet journal where there is one.
-- Picture: his 3D model where the client can show it skinned (the modern
-- client by npc 16549, once it's seen him; 1.12 when he's out nearby, copied
-- by name); his painted portrait
-- (dev/art-src/make_dealer.py) otherwise, and in Options. Lines are keyed by game event; {name}, {amount} and the
-- like are filled in (see DEALERS.md).

local ns = CowCasino.ns

ns:RegisterDealer({ id = "whiskers", name = "Whiskers", title = "Whiskers", author = "a very small paw",
    image = "Interface\\AddOns\\CowCasino\\Art\\DealerWhiskers",
    model = { npc = 16549, name = "Whiskers the Rat" },
    unlock = function() return ns:HasCompanion({ "Whiskers the Rat", "Whiskers" }, 23015) end,
    unlockMessage = "Whiskers the Rat has taken over the dealer's chair. (Options > Display > Dealer to change it back.)",
    lines = {
        -- Blackjack
        deal = {
            "Cards are out! {player} for you, and I'm showing {up}. Squeak if you want another.",
            "Fresh from the shoe, still warm. {player} for you.",
            "{player}. Not bad for a big cheese like you.",
            "Dealing! Keep your paws where I can see them.",
            "{player} for you, {up} for me. Let the rat race begin.",
        },
        insurance = {
            "I'm showing an Ace. Insurance? I know a rat who knows a rat.",
            "Ace up! Want to cover your tail?",
        },
        evenMoney = {
            "Blackjack! But I've got an Ace... even money? A crumb in the paw beats two in the trap.",
        },
        hitHighSafe = {
            "Hitting on {before}? You've got nerve. And now {player}. I smell luck.",
            "Phew, {player}. That was closer than a cat on a cheese wheel.",
            "{player} and still standing! You must have nine lives. Wrong animal, but still.",
        },
        twentyOne = {
            "Twenty-one! Gouda job.",
            "21 on the nose. And I know noses.",
        },
        playerBust = {
            "{player}. Bust! Snap goes the trap.",
            "Bust! Don't worry, I'll keep your chips nice and cozy in my nest.",
            "{player}. You nibbled one card too many.",
            "Squeak! {player}. That's a bust.",
        },
        standLow = {
            "Standing on {player}? Bold. Or you're just playing it a little mousy.",
            "{player} and done? I've seen braver cheese.",
        },
        double = {
            "Doubling down! Going whole hog. Whole rat. Whole something.",
            "Double! Twice the chips, twice the cheese.",
        },
        split = {
            "Splitting! Like sharing a crumb with your littermate.",
            "Two hands! Twice the tails to chase.",
        },
        dealerTurn = {
            "My turn. Let's see what's under the floorboards.",
            "Flipping my card. Don't hold your breath, it's dusty down here.",
        },
        playerBlackjack = {
            "Blackjack! You're the big cheese now. {win} for you.",
            "Blackjack! That's brie-lliant. Here's {win}.",
        },
        dealerBlackjack = {
            "Blackjack for me. Sorry. Rats always find a way in.",
            "Dealer blackjack! I'd say I'm sorry, but I'm a rat.",
        },
        dealerBust = {
            "I bust with {total}! I got greedy. Occupational hazard. {win} for you.",
            "{total}. Bust! Took too big a bite. Here's {win}.",
        },
        win = {
            "You win with {total}! {win} is yours. I'll stick to the crumbs.",
            "{total} takes it! Gouda game. {win} for you.",
            "You win {win}! Whisker-thin, but a win's a win.",
        },
        lose = {
            "{total} wasn't enough. I'll add your chips to my hoard.",
            "The house wins. The house is a hole in the wall, but it wins.",
        },
        push = {
            "A push. Nobody gets the cheese.",
            "We tie. Call it a rat-tie. That's not a thing. It is now.",
        },
        surrender = {
            "Surrender? Smart rats know when to scurry. Half back to you.",
        },
        broke = {
            "Out of chips! Even I can't find crumbs in an empty pocket.",
            "All gone. Don't worry, I've lived on less.",
        },

        -- Craps
        crapsNatural = {
            "{total}! {name} rolls a natural. Squeak squeak!",
            "{total} on the come-out! The dice like {name}.",
        },
        crapsCraps = {
            "{total}. Craps. {name} rolled snake eyes on the cheese.",
            "Craps! {total}. Even rats know to avoid that one.",
        },
        crapsPoint = {
            "The point is {total}. Roll it again before a 7 comes sniffing.",
        },
        crapsMade = {
            "{total}! The point's made. That's some fine scavenging.",
        },
        crapsSevenOut = {
            "Seven out! The trap snaps shut.",
            "Seven. Scurry along, dice go to the next one.",
        },
        crapsRoll = {
            "{total}. Still chasing {point}.",
            "{total}. Keep rolling, the cheese is close. Point's {point}.",
        },
        crapsRollWin = {
            "{total}! That pays {win}. Pass me a crumb?",
        },
        crapsNewShooter = {
            "New shooter: {name}. Give those dice a good sniff first.",
        },
        crapsYourDice = {
            "Your dice! Roll them like you're tipping over a bin.",
        },
        crapsBroke = {
            "No chips left. That's a bare cupboard.",
        },

        -- Five-Card Draw
        drawDeal = {
            "Five cards each. {button} has the button, blinds {sb} and {bb}. Nobody gnaw on the cards.",
        },
        drawDraw = {
            "Time to draw. Swap your scraps for something tastier.",
        },
        drawSecond = {
            "Second round of betting. Who's got the cheese?",
        },
        drawStandPat = {
            "{name} stands pat. Either a big hand or a big bluff. I smell a rat... and I'd know.",
        },
        drawYouStandPat = {
            "Standing pat? Ooh, mysterious.",
        },
        drawBigDraw = {
            "{name} takes {count}. Rummaging through the bin!",
        },
        drawAllIn = {
            "{name} goes all in for {amount}! Whole wheel of cheese on the table.",
        },
        drawYouAllIn = {
            "All in for {amount}! You're a rat with nothing to lose.",
        },
        drawWin = {
            "{name} takes {pot} with {hand}.",
        },
        drawYouWin = {
            "You take {pot} with {hand}! Big cheese energy.",
        },
        drawFoldWin = {
            "Everyone folds. {name} sneaks off with {pot}.",
        },
        drawYouFoldWin = {
            "They all scurried! {pot} is yours.",
        },
        drawSplit = {
            "A split pot, {pot}. Shared like a crust.",
        },
        drawKnockout = {
            "{name} is out of chips. Back to the sewers for them.",
        },
        drawYouBust = {
            "You're out of chips. Even the crumbs are gone.",
        },

        -- Texas Hold'em
        holdemDeal = {
            "New hand. {button} on the button, blinds {sb} and {bb}. Paws off the table till it's your turn.",
        },
        holdemFlop = {
            "The flop. Three cards, freshly scavenged.",
            "Here's the flop. Sniff it out.",
        },
        holdemTurn = {
            "The turn. Plot thickens like old cheese.",
        },
        holdemRiver = {
            "The river. Rats are great swimmers, you know.",
        },
        holdemAllIn = {
            "{name} is all in for {amount}! That's a lot of cheddar.",
        },
        holdemYouAllIn = {
            "All in for {amount}! No turning tail now.",
        },
        holdemWin = {
            "{name} wins {pot} with {hand}.",
        },
        holdemYouWin = {
            "You win {pot} with {hand}! That's a real cheese pull.",
        },
        holdemFoldWin = {
            "Everyone folds. {name} scurries off with {pot}.",
        },
        holdemYouFoldWin = {
            "They all ran! {pot} is yours, no showdown needed.",
        },
        holdemSplit = {
            "Split pot, {pot}. Everybody gets a nibble.",
        },
        holdemKnockout = {
            "{name} is out! Caught in the trap.",
        },
        holdemYouBust = {
            "You're out of chips. That's the rat race for you.",
        },

        -- Three Card Poker
        tcpDeal = {
            "Three cards for you: {hand}. I play with Queen high or better.",
        },
        tcpFold = {
            "Folded. I had {dealer}. Sometimes you just scurry.",
        },
        tcpNoQualify = {
            "I've got {dealer}. Doesn't qualify. A rat with no cheese.",
        },
        tcpWin = {
            "{hand} beats my {dealer}! {amount} for you. Gouda hand.",
        },
        tcpLose = {
            "My {dealer} beats your {hand}. I'll add it to the hoard.",
        },
        tcpPush = {
            "A tie! We split the crumbs.",
        },
        tcpBigPairPlus = {
            "{hand} on the Pair Plus! That's the whole cheese wheel!",
        },

        -- Deathroll
        deathrollStart = {
            "Deathroll from {start}, {stake} each. Roll a 1 and you're cat food.",
        },
        deathrollParty = {
            "{name} wants a deathroll from {start}! For {stake}. May the luckiest rat win.",
        },
        deathrollClose = {
            "{name} is down to {value}. Whiskers are twitching!",
        },
        deathrollWin = {
            "{name} rolls the 1! You win {amount}. Sweet, sweet cheese.",
        },
        deathrollLose = {
            "A 1. That's you. {name} takes the cheese.",
        },

        -- Checkers
        checkersStart = {
            "Checkers for {stake}! Hop, hop, hop. I love a jumping game.",
        },
        checkersParty = {
            "{name} wants a game of checkers! I'll be under the table, watching.",
        },
        checkersWin = {
            "You win! Crowned like the rat king.",
        },
        checkersLose = {
            "You lose. Jumped like a rat over a gutter.",
        },
        checkersDraw = {
            "A draw. Nobody gets the cheese.",
        },

        -- Chess
        chessStart = {
            "Chess for {stake}. I'll be quiet. Rats are very good at quiet.",
        },
        chessParty = {
            "{name} wants a game of chess! I'll be the one squeaking from the sidelines.",
        },
        chessWin = {
            "Checkmate! You cornered {name} like a rat in a pantry.",
            "You win! Even the cheese is impressed.",
        },
        chessLose = {
            "Checkmate. {name} had you trapped.",
        },
        chessDraw = {
            "A draw. Two rats, one crumb, no winner.",
        },

        -- Battleship
        battleshipStart = {
            "Battleship for {stake}! Rats always know which ship is about to sink.",
        },
        battleshipParty = {
            "{name} wants a sea battle! I'll be in the cargo hold.",
        },
        battleshipWin = {
            "Every ship sunk! And I got off them all in time.",
        },
        battleshipLose = {
            "Your fleet sank. Good thing I jumped ship early.",
        },
    } })
