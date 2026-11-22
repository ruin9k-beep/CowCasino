-- CowCasino dealer: Fizzlecog, the goblin (the default dealer)
-- Picture: Art\DealerGoblin.tga, made by dev/art-src/make_dealer.py.
-- Lines are keyed by game event; {name}, {amount} and the like are filled in.

local ns = CowCasino.ns
local ART = "Interface\\AddOns\\CowCasino\\Art\\"

ns:RegisterDealer({ id = "goblin", name = "Goblin", title = "Fizzlecog", author = "ruin9k",
    image = ART .. "DealerGoblin",
    portrait = { npc = 3391 },      -- a 3D stand-in where there is one (Gazlowe)
    lines = {
        -- Blackjack
        deal = {
            "Cards are flyin'! Time is money, friend.",
            "Fresh outta the Steamwheedle shoe. {player} for you, and I'm showin' {up}.",
            "Ante's in, cards are out. No refunds!",
            "{player} for you. Let's see that famous adventurer luck.",
            "Dealin'! Keep your hands where I can see 'em.",
        },
        insurance = {
            "Ace up! Want some insurance? Goblin-backed, mostly honest.",
            "I'm showin' an Ace. Insurance, friend? Small fee, big peace of mind.",
        },
        evenMoney = {
            "Blackjack! But I got an Ace up... take even money? A sure thing's a sure thing.",
        },
        hitHighSafe = {
            "Hittin' on {before}?! Crazier than a Gadgetzan engineer... and luckier. {player}!",
            "Bold move! That's {player} and you're still breathin'.",
            "Phew, {player}. I almost had to sweep your chips up.",
            "Hit on {before} and lived? Somebody's been rubbin' a rabbit's foot.",
        },
        twentyOne = {
            "Twenty-one! Now that's what I call a return on investment.",
            "21 on the nose! Show-off.",
        },
        playerBust = {
            "{player}! Kaboom! Like a shredder with no oil.",
            "Bust! Your chips just joined the Steamwheedle Cartel.",
            "{player}. Too much, friend. Shoulda listened to the goblin.",
            "Kaboom! {player}. I'll take those, thanks.",
        },
        standLow = {
            "Standin' on {player}? Brave... or cheap. Can't tell with you.",
            "{player} and you're done? Your call, pal. My profit.",
        },
        double = {
            "Doublin' down? Now we're talkin' business!",
            "Double the bet, double the fun! Mostly for me.",
            "Ooh, big spender! One card, make it count.",
        },
        split = {
            "Splittin' 'em up? Two hands, twice the profit... for somebody.",
            "Split! I like it. More bets, more business.",
        },
        dealerTurn = {
            "My turn. Let's see what the house has got.",
            "Flippin' the hole card... no peekin'!",
            "Time to earn my commission.",
        },
        playerBlackjack = {
            "Blackjack! Three to two... ugh, the boss is gonna dock my pay. Take your {win}.",
            "A natural! Fine, fine, there's your {win}. Don't spend it all in Booty Bay.",
        },
        dealerBlackjack = {
            "Blackjack for the house! Nothin' personal, friend. Just business.",
            "Twenty-one, baby! The Cartel thanks you for your generous donation.",
        },
        dealerBust = {
            "I bust with {total}?! This shoe is rigged... against ME! You win {win}.",
            "{total}! Kaboom. Take your {win} before I change my mind.",
        },
        win = {
            "Dealer stands on {total}. You win {win}. Don't get used to it.",
            "{total} for me, and you beat it. Here's {win}, ya swindler.",
            "You win {win}! I'm gonna get docked for this.",
        },
        lose = {
            "Dealer stands on {total}. House wins! Time is money, and now it's MY money.",
            "{total} takes it. Thanks for the chips, friend!",
            "House wins. Come back anytime! Especially with more chips.",
        },
        push = {
            "We push. Nobody wins... my least favorite kind of math.",
            "A tie? Bah. Keep your chips, I'll get 'em next round.",
        },
        surrender = {
            "Givin' up half? Smart money... boring, but smart.",
            "Surrender accepted. Half for you, half for the goblin. Pleasure doin' business.",
        },
        broke = {
            "Outta chips? I could offer a loan... at thirty percent a week.",
            "Cleaned out! Grab more chips from the menu, friend. The goblin's always open.",
        },

        -- Craps (solo and party tables)
        crapsNatural = {
            "{name}! A natural! Pass line pays... reluctantly.",
            "{total}, front line winner! Ugh, I hate payin' out.",
            "Natural {total}! Somebody check those dice... for my fingerprints. Kiddin'!",
        },
        crapsCraps = {
            "Craps! {name}! Pass line loses. I love that sound.",
            "{name}! Line away! Your gold's comin' home to papa.",
            "Craps, {total}! The dice giveth... mostly to me.",
        },
        crapsPoint = {
            "The point is {total}! Odds are open, and so is my wallet.",
            "{total} is the point. Roll it again before a seven and I'll pretend to be happy for ya.",
            "Point's {total}! Back it up with odds. I get a cut. Not really. Maybe.",
        },
        crapsMade = {
            "Winner! {total}! Point made, Pass line pays!",
            "Point made! {total}! There goes my retirement fund.",
            "{total}! The shooter hits it! ...I'm gonna go cry into my gold.",
        },
        crapsSevenOut = {
            "Seven out! Line away! Come to Fizzlecog, little coins.",
            "Seven! Pass loses, Don't Pass wins. The nose knew.",
            "Seven out! Pay the Don'ts, take the rest. Mostly the rest.",
        },
        crapsRoll = {
            "{total}. Keep 'em rollin'! Point is {point}.",
            "{total}! No decision on the line. Shooter, roll!",
            "Rolled {total}. Come on, seven! I mean... come on, {point}!",
        },
        crapsRollWin = {
            "{total}! That pays you {win}. Don't spend it all at once... spend it here.",
            "Ka-ching! {win} for you on {total}. My nose is weepin'.",
        },
        crapsNewShooter = {
            "New shooter! {name}, the dice are yours. Blow on 'em for luck... and my profit.",
            "Dice go to {name}! Let's see whatcha got.",
        },
        crapsYourDice = {
            "The dice are yours, friend! Make 'em dance.",
            "New shooter: you! Roll big, lose bigger. Kiddin'! Mostly.",
        },
        crapsBroke = {
            "Outta chips? Fizzlecog Financial is always open. Fifty percent interest, compounded hourly!",
            "Cleaned out! The dice always come home to papa. Grab more chips from the menu, friend.",
        },

        -- Five-Card Draw (solo and party tables)
        drawDeal = {
            "Five cards each, no peekin' at your neighbor's. That's MY job. {button} has the button.",
            "Dealin' draw! Blinds are {sb} and {bb}. Tips are... encouraged.",
            "Five for you, five for you... and none for me. Story of my life.",
            "Fresh hand! I can smell a full house. Or that's my lunch.",
        },
        drawDraw = {
            "Time to draw! Toss your junk, I'll find it a good home.",
            "Draw time! Up to three cards, four if you're holdin' an Ace. No funny business.",
            "The draw! Old cards to me, new cards to you. Fair trade. Mostly.",
        },
        drawSecond = {
            "Second round of bettin'! Now we find out who's bluffin'.",
            "New cards, new bets. My nose is twitchin'!",
        },
        drawStandPat = {
            "{name} stands pat! Either a monster or a liar. I respect both.",
            "No cards for {name}? Ooh, somebody's confident.",
            "{name} stands pat. My nose smells... somethin'.",
        },
        drawYouStandPat = {
            "Standin' pat? Bold! Or you're bluffin'. Your secret's safe with me. For a fee.",
        },
        drawBigDraw = {
            "{name} takes {count}! Fishin' in the deep end, eh?",
            "{count} new cards for {name}. Hope springs eternal!",
        },
        drawAllIn = {
            "{name} shoves {amount}! Now we're cookin'!",
            "All-in from {name}! {amount} on the line. Somebody hold my nose!",
        },
        drawYouAllIn = {
            "All-in for {amount}?! Fizzlecog approves of this level of risk.",
        },
        drawWin = {
            "{name} takes {pot} with {hand}! Don't forget your favorite dealer.",
            "{hand} wins it for {name}! {pot}. I'll just... count that for ya.",
        },
        drawYouWin = {
            "You win {pot} with {hand}! Finder's fee? No? Rude.",
            "{hand}! {pot} for you. My nose is weepin' again.",
        },
        drawFoldWin = {
            "Everybody folds to {name}! {pot}, no questions asked.",
            "{name} scoops {pot} uncontested. That's my kinda business model.",
        },
        drawYouFoldWin = {
            "They all folded! {pot} for you. Were you bluffin'? Don't tell me, I'll sell it.",
        },
        drawSplit = {
            "A split pot! Sharin' gold. Ugh, my least favorite.",
            "Chop it! {pot} between the winners. So wholesome I could gag.",
        },
        drawKnockout = {
            "{name} is busted! Fizzlecog Financial is open, friend. Fifty percent, compounded hourly!",
            "{name}'s outta chips! The gold always comes home... to me.",
        },
        drawYouBust = {
            "Cleaned out, friend! Leave the table to buy back in. I'll keep your seat warm. And your chips.",
        },

        -- Texas Hold'em (solo and party tables)
        holdemDeal = {
            "Cards in the air! {button} has the button. Blinds are {sb} and {bb}... plus a small dealer's fee. Kiddin'! Mostly.",
            "Shufflin'... totally fair shufflin'. Don't look at my sleeves. {button}'s on the button.",
            "New hand! I can smell gold from here, and this nose don't lie.",
            "Blinds, antes and tips for the dealer. Okay, fine, just the blinds: {sb} and {bb}.",
            "Dealin' 'em out! Remember, friends: the house always wins. I'm the house. Sorta.",
        },
        holdemFlop = {
            "Here's the flop! Three cards, zero refunds.",
            "The flop! Somebody just smiled. My nose twitched. That's never a good sign.",
            "Flop's out. Anybody need a loan? Fizzlecog Financial is open. Terrible rates!",
        },
        holdemTurn = {
            "The turn! Things are heatin' up. I love the smell of a growin' pot.",
            "Turn card. Ooh, I can almost taste the gold.",
        },
        holdemRiver = {
            "The river! Last card, last chance to make me rich... I mean, make yourselves rich.",
            "River card. Every coin on this table is lookin' right at me. I can feel it.",
        },
        holdemAllIn = {
            "{name} shoves {amount}! Now THAT'S my kinda customer!",
            "All-in from {name}! {amount} on the line. My nose is tinglin'!",
            "{name} pushes it all in! I'll hold those chips for safekeepin'... wink wink.",
            "{name} is all-in for {amount}! Somebody call a goblin banker!",
        },
        holdemYouAllIn = {
            "You're all-in for {amount}? Bold! Want me to hold your wallet too?",
            "All of it?! {amount}! I like you. I'll miss you. Maybe.",
        },
        holdemWin = {
            "{name} takes {pot} with {hand}! Don't forget to tip your dealer.",
            "{hand} wins it! {pot} to {name}. I didn't touch a single coin. Check my pockets... no, don't.",
            "{name} rakes in {pot}! My nose says there's more where that came from.",
        },
        holdemYouWin = {
            "You win {pot} with {hand}! Ten percent finder's fee? No? Worth a shot.",
            "{hand}! That's {pot} for you. My nose is cryin' a little.",
            "Pot's yours: {pot}! Just leave a little somethin' for ol' Fizzlecog, eh?",
        },
        holdemFoldWin = {
            "Everybody folds! {name} scoops {pot} without even showin'. Scam artist! I respect it.",
            "{name} takes {pot} uncontested. That's my kinda business: no work, all profit.",
        },
        holdemYouFoldWin = {
            "They all folded! {pot} for you, no questions asked. You'd make a fine goblin.",
            "Took it down! {pot}. Was it a bluff? Don't tell me, I'll sell the secret.",
        },
        holdemSplit = {
            "A split pot! Nothin' sadder than sharin' gold.",
            "Chop it up! {pot} split between the winners. Ugh, so wholesome.",
        },
        holdemKnockout = {
            "{name} is busted! Don't worry, friend: Fizzlecog Financial offers loans at only fifty percent!",
            "And {name} is outta chips! The gold always finds its way home... to me.",
            "{name}'s out! Leave your chips at the... oh wait, you don't have any.",
        },
        holdemYouBust = {
            "You're busted, friend! I'd offer a loan, but... nah. Leave the table to buy back in.",
            "Cleaned out! Your gold's in good hands now. Mine. Leave the table to buy in again.",
        },

        -- Three Card Poker
        tcpDeal = {
            "Three cards each. Small hands, big profits. For me, mostly.",
            "{hand}, eh? Play it or fold it, but decide before my nose gets itchy.",
            "Cards are out! Queen high or better and I'm in. And I'm ALWAYS in. Kiddin'.",
        },
        tcpFold = {
            "Folded! Your Ante goes in my pocket. Very warm in there.",
            "Ah, a fold. Smart. Cowardly, but smart. I had {dealer}, by the way.",
        },
        tcpNoQualify = {
            "Bah! {dealer}. I don't even qualify. Take your Ante and stop smilin'.",
            "No Queen, no game. Your Ante wins. Ugh, payin' out hurts my nose.",
        },
        tcpWin = {
            "{hand} beats my {dealer}. That's {amount} walkin' outta my bank!",
            "You win! {amount}. I'll be countin' my coins twice tonight.",
            "Your {hand} takes it. Somebody check this deck. Not me. Somebody.",
        },
        tcpLose = {
            "My {dealer} beats your {hand}! Gold comes home to papa.",
            "Dealer wins! Don't worry, your gold's gonna have a great life with me.",
        },
        tcpPush = {
            "A tie! Nobody wins. Worst kinda hand there is.",
        },
        tcpBigPairPlus = {
            "{hand} on the Pair Plus?! Who let you near my deck?!",
            "That Pair Plus just cost me a new pair of boots. Enjoy 'em.",
        },

        -- Deathroll
        deathrollStart = {
            "A deathroll for {stake}? From {start}? Ha! You roll first, friend.",
            "{stake} on the line! Roll a 1 and it's mine. Roll anything else and... well, it's still gonna be mine.",
            "Deathroll! The purest form of gamblin'. No skill, all greed. My favorite!",
        },
        deathrollParty = {
            "A duel with {name}! {stake} each, from {start}. Fizzlecog's holdin' the pot. Totally safe.",
            "{name} wants a deathroll! Place your bets, everybody. Well, them. Not you lot.",
        },
        deathrollClose = {
            "Ooh, {name} rolled {value}! Now we're gettin' somewhere.",
            "{value}! Single digits! I can hear the gold rattlin'.",
            "Down to {value}. Somebody's sweatin'. My nose can smell it.",
        },
        deathrollWin = {
            "You beat {name}! {amount} up. Don't spend it all in one goblin shop. Actually, do.",
            "{name} rolled a 1! Ha! The winner, and still champion: you.",
        },
        deathrollLose = {
            "A 1! Ouch. {name} takes it. Wanna go again? Double or nothin'?",
            "You rolled the big one... the little one. A 1! Gold's gone, friend.",
        },

        -- Checkers
        checkersStart = {
            "Checkers for {stake}! The machine's never lost a piece it didn't mean to. Probably.",
            "{stake} on the board. Black goes first. Jump when you can, kid - you have to anyway!",
        },
        checkersParty = {
            "{name} wants a game of checkers! Friendly, free, and I'm still watching.",
        },
        checkersWin = {
            "You cleaned the board! The house pays up. Grudgingly.",
            "Crowned and conquered! Nice game, friend.",
        },
        checkersLose = {
            "Out-jumped! Happens to the best of us. Mostly to you, though.",
            "Not a piece left to move. Rack 'em up again?",
        },
        checkersDraw = {
            "A draw! Nobody wins, nobody pays. My least favorite kind of game.",
        },

        -- Chess
        chessStart = {
            "Chess for {stake}! The machine's been readin' books. Well, one book. It's mostly pictures.",
            "{stake} says you can outthink a box of gears. I'll hold the chips.",
        },
        chessParty = {
            "Chess with {name}! Quiet please, the brains are workin'.",
            "{name} at the board! White moves first. No touchin' my pieces, they're rented.",
        },
        chessWin = {
            "Checkmate! A grandmaster in my casino. Should I start charging admission?",
            "You beat {name}! Somebody write that down.",
        },
        chessLose = {
            "{name} takes it. Tip over your king, nobody's lookin'. Everybody's lookin'.",
            "That's the game. Chess is hard, friend. Try deathroll, it's mostly luck!",
        },
        -- Battleship
        battleshipStart = {
            "{stake} on the high seas! The machine hides its boats under a rock. I've seen it.",
            "Battleship for {stake}. Hide 'em well, kid. Then go fishin'.",
        },
        battleshipParty = {
            "{name} wants a sea battle! Free, friendly, and I'm keepin' score.",
        },
        battleshipWin = {
            "Every last boat on the bottom! Admiral of the casino, you are.",
            "You sank 'em all! I'll get my snorkel and collect the winnings... for you.",
        },
        battleshipLose = {
            "Your fleet's sleepin' with the fishes. Better luck next voyage.",
            "Glub glub. That's the sound of your chips sinkin', friend.",
        },

        chessDraw = {
            "A draw! Very sportsmanlike. Very boring. Shake hands, you two.",
        },
    } })
