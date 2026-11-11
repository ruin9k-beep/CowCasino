# CowCasino dealers

Games with a dealer (Blackjack so far) show a strip on top of the window with the
dealer's picture, name and what they're saying. The picture and name come from the
selected **dealer**. Players pick one in the **CowCasino Options** (the Options button
on the game list) under **Dealer**; the choice is saved and used by every game.

CowCasino ships with two dealers, painted by `dev/art-src/make_dealer.py`:

- **Goblin** (the default): Fizzlecog, a grinning goblin croupier with a green visor and a gold tooth (`Art\DealerGoblin`)
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
})
```

`image` is any texture path: your own image, or a game icon such as
`"Interface\\Icons\\INV_Misc_Head_Orc_01"`. To show only part of a texture, give
`{ path, left, right, top, bottom }` in texture coordinates (0 to 1), for example
`{ "Interface\\Icons\\INV_Misc_Head_Orc_01", 0.08, 0.92, 0.08, 0.92 }` to trim an
icon's border.

The picture is shown square, about 44 pixels on screen. A 64x64 or 128x128 image
works well. For the 1.12 client, images must be .tga or .blp with sides that are a
power of two (64, 128, 256...).

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
