# CowCasino dealers

Games with a dealer (Blackjack, Texas Hold'em and Craps so far) show a strip on top of the window with the
dealer's picture, name and what they're saying. The picture and name come from the
selected **dealer**. Players pick one in the **CowCasino Options** (the Options button
on the game list) under **Dealer**; the choice is saved and used by every game.

CowCasino ships with two dealers, painted by `dev/art-src/make_dealer.py`:

- **Goblin** (the default): Fizzlecog, a grinning goblin croupier with a green visor and a gold tooth (`Art\DealerGoblin`). He has his own lines for Blackjack, Hold'em and Craps.
- **Human**: Harold, a human croupier (`Art\DealerHuman`)

When a game shows a player's 3D portrait in the strip (a party member dealing,
say), that replaces the picture until the game puts it back.

---

## Adding a dealer

A dealer is one picture and a few words:

```lua
CowCasino.RegisterDealer({
    id     = "myorc",                 -- unique; saved as the player's choice
    name   = "Orc",                   -- shown in the Options picker
    title  = "Grukk",                 -- the dealer's name, shown on the strip (default "Dealer")
    author = "you",                   -- optional, shown as "by you" in Options
    image  = "Interface\\AddOns\\CowCasino_MyDealer\\Grukk",
    lines  = {                        -- optional: what this dealer says (below)
        deal = { "Cards out. {player} for you.", "Grukk deals! {player}." },
        lose = "Grukk wins! {total} beats you.",
    },
})
```

`image` is any texture path: your own image, or a game icon such as
`"Interface\\Icons\\INV_Misc_Head_Orc_01"`. To show only part of a texture, give
`{ path, left, right, top, bottom }` in texture coordinates (0 to 1), for example
`{ "Interface\\Icons\\INV_Misc_Head_Orc_01", 0.08, 0.92, 0.08, 0.92 }` to trim an
icon's border.

The picture is shown square, about 108 pixels on screen. A 128x128 image works
well. For the 1.12 client, images must be .tga or .blp with sides that are a
power of two (64, 128, 256...).

## Lines

A dealer can have its own lines for the moments of a game. For each moment,
give one line or a list; one is picked at random (never the same twice in a
row). Words in braces are filled in. Any moment without lines gets CowCasino's
plain words instead (or nothing), so a dealer can have as few lines as you like.

Blackjack (single player):

| Moment | When | Fills in |
|---|---|---|
| `deal` | the cards are dealt | `{player}` your total, `{up}` the dealer's card ("an Ace", "a 7") |
| `insurance` | the dealer shows an Ace | |
| `evenMoney` | ...and you have blackjack | |
| `hitHighSafe` | you hit on a hard 16 or more and didn't bust | `{before}`, `{player}` |
| `twentyOne` | a hit makes 21 | `{player}` |
| `playerBust` | you bust (and the round's call, if every hand bust) | `{player}` |
| `standLow` | you stand on 12 or less | `{player}` |
| `double` | you double down | `{player}`, `{bet}` |
| `split` | you split | |
| `dealerTurn` | the dealer plays | `{up}` |
| `playerBlackjack` | the round's call: you won with a blackjack | `{win}`, `{total}` (dealer), `{player}` |
| `dealerBlackjack` | ...the dealer had blackjack | same |
| `dealerBust` | ...you won and the dealer bust | same |
| `win` / `lose` / `push` | ...otherwise | same, and `{loss}` |
| `surrender` | ...you surrendered | same |
| `broke` | you're out of chips after a round | |

Texas Hold'em (solo and party tables; every player hears their own chosen dealer):

| Moment | When | Fills in |
|---|---|---|
| `holdemDeal` | a hand is dealt | `{button}` who has the button, `{sb}`, `{bb}` |
| `holdemFlop` / `holdemTurn` / `holdemRiver` | the board cards come (skipped if the dealer is busy talking) | |
| `holdemAllIn` | another player goes all-in | `{name}`, `{amount}` |
| `holdemYouAllIn` | you go all-in | `{amount}` |
| `holdemWin` / `holdemYouWin` | the hand is won at the showdown | `{name}`, `{pot}`, `{hand}` |
| `holdemFoldWin` / `holdemYouFoldWin` | ...won when everyone else folded | `{name}`, `{pot}` |
| `holdemSplit` | the pot is split | `{name}` (one of them), `{pot}`, `{hand}` |
| `holdemKnockout` | another player runs out of chips | `{name}` |
| `holdemYouBust` | you run out of chips | |

Craps (solo and party tables; everyone at a party table hears the call):

| Moment | When | Fills in |
|---|---|---|
| `crapsNatural` | 7 or 11 on the come-out | `{total}`, `{name}` ("Yo-leven", or the number) |
| `crapsCraps` | 2, 3 or 12 on the come-out | `{total}`, `{name}` ("Snake eyes", "Ace-deuce", "Boxcars") |
| `crapsPoint` | a point is set | `{total}` |
| `crapsMade` | the point is made | `{total}` |
| `crapsSevenOut` | seven out | `{total}` |
| `crapsRollWin` | any other roll that paid you (Field, props) | `{total}`, `{point}`, `{win}` |
| `crapsRoll` | any other roll (skipped if the dealer is busy talking) | `{total}`, `{point}` |
| `crapsNewShooter` / `crapsYourDice` | party play: the dice move on after a seven out | `{name}` |
| `crapsBroke` | you're out of chips with nothing on the table | |

Every roll also fills in `{win}` and `{loss}` (what it won or lost you) and `{name}`.

`Dealer.lua` has Fizzlecog's lines as an example.

Registering an `id` again replaces that dealer. A dealer without an `id` or an
`image` is refused with an error.

## As a separate addon

Make a folder such as `CowCasino_MyDealer` with a .toc that loads after CowCasino:

```
## Interface: 11200
## Title: CowCasino - My Dealer
## Dependencies: CowCasino

MyDealer.lua
```

For WoW Forever as well, put a copy of that .toc in the same folder named after
the folder plus `_Mainline` (for example `CowCasino_MyDealer_Mainline.toc`) with
`## Interface: 16001`. WoW Forever reads that one; the 1.12 client ignores it.

`MyDealer.lua` contains just the `CowCasino.RegisterDealer` call, and the folder
holds the image. If a player removes a dealer they had selected, CowCasino falls
back to the goblin.

## Inside CowCasino

Put the image in `Art\` and add a `ns:RegisterDealer(...)` call at the bottom of
`Dealer.lua`, next to the goblin and the human.

## For game authors

A game turns the strip on with a `dealer` table (`dealer = { idle = "Place your bets." }`)
and drives it through `ns.Dealer`. Leave out `image` and `name` to use the player's
chosen dealer; `Dealer.lua` explains the rest.
