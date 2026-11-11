# CowCasino card art

Every card game in CowCasino draws its cards through the selected **card art pack**.
Games never draw cards themselves, so a new pack changes the look of every game at once.
Players pick a pack in the **CowCasino Options** (the Options button on the game list) under **Card art**; the choice is saved and shared by all games.

CowCasino ships with four packs:

- **Plain**, drawn entirely in code (`Art\Plain.lua`)
- **Tauren**, painted images for the card, suits and court cards with the ranks drawn as text (`Art\Tauren.lua`)
- **Orc & Troll**, painted the same way: parchment and iron, blood-red war paint, crossed axes, a voodoo mask and a tusked helm (`Art\Orc.lua`)
- **Human**, the Plain faces with a painted royal blue and gold heraldic back (`Art\Human.lua`)

Tauren and Orc & Troll share `Art\PaintedDeck.lua`: give it an image name prefix
and two rank colors, and it builds the deck from four small images
(`<prefix>CardFace`, `<prefix>CardBack`, `<prefix>Suits`, `<prefix>Court`),
cut up with texture coordinates, plus text ranks that stay sharp at any card size.
`Art\Human.lua` shows how to reuse another pack and change only the back.

There are two ways to add a pack. Both work from inside CowCasino or from a
separate addon.

---

## 1. Image deck (easiest)

Put one image per card in a folder, plus a back, and register the folder.

File names are the rank key followed by the suit key:

| Ranks | `A 2 3 4 5 6 7 8 9 10 J Q K` |
|-------|------------------------------|
| Suits | `S` spades, `H` hearts, `D` diamonds, `C` clubs |

So the folder holds `AS`, `2S` ... `KS`, `AH` ... `KC` (52 files) and `back`.
Use `.tga` or `.blp`, with power-of-two sizes (for example 128 x 256). The game only
finds new image files after a full restart, not a /reload.

```lua
CowCasino.RegisterTextureDeck({
    id     = "mydeck",                              -- unique, never changes
    name   = "My Deck",                             -- shown in Options
    author = "you",
    path   = "Interface\\AddOns\\MyDeck\\Cards\\",
})
```

Optional fields:

- `ext` – file extension, if you want it explicit (`".tga"`)
- `back` – back file name (default `"back"`), or `backFile` for a full path
- `FaceFile = function(rank, suit) return file, left, right, top, bottom end`
  – use your own file names, or a **sprite sheet** by returning texture coordinates
- `backCoords = { left, right, top, bottom }` – coordinates for the back on a sheet

## 2. Code-drawn pack (full control)

Register a table with three functions. Each card widget gives your pack an empty
frame (`skin`) the size of the card; build whatever you like on it.

```lua
CowCasino.RegisterCardArt({
    id = "neon", name = "Neon", author = "you",

    -- Called once per card widget. Create textures and font strings on `skin`.
    Create = function(self, skin, width, height) end,

    -- Show a face. rank = { index, key, name, face }, suit = { index, key, name, symbol, red }
    ShowFace = function(self, skin, rank, suit) end,

    -- Show the back.
    ShowBack = function(self, skin) end,
})
```

`Art\Plain.lua` is a complete working example.

## As a separate addon

Make a folder such as `CowCasino_MyDeck` with a .toc that loads after CowCasino:

```
## Interface: 11200
## Title: CowCasino - My Deck
## Dependencies: CowCasino

MyDeck.lua
```

For WoW Forever as well, put a copy of that .toc in the same folder named after
the folder plus `_Mainline` (for example `CowCasino_MyDeck_Mainline.toc`) with
`## Interface: 16001`. WoW Forever reads that one; the 1.12 client ignores it.

`MyDeck.lua` contains just the `RegisterTextureDeck` or `RegisterCardArt` call.
If a player removes a pack they had selected, CowCasino falls back to Plain.

## Inside CowCasino

Add a file under `Art\`, start it with `local ns = CowCasino.ns`, register the pack with `ns:RegisterCardArt(...)` or
`ns:RegisterTextureDeck(...)`, and list it in `CowCasino.toc` (the release script copies the file list into `CowCasino_Mainline.toc`) after `Art\Plain.lua` (and after `Art\PaintedDeck.lua` if it
uses `ns:RegisterPaintedDeck`).
