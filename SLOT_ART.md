# CowCasino slot themes

The Slots game draws every symbol through the selected **slot theme**, the same way
card games use card art packs (see CARD_ART.md). A theme changes how the symbols look;
it never changes the odds or the paytable.
Players pick a theme in **Slots > Paytable > Symbol theme**; the choice is saved.

CowCasino ships with two themes:

- **Azeroth** (default) – in-game item icons (`Art\SlotsAzeroth.lua`). The easiest file to copy.
- **Classic** – colored fruit-machine badges drawn in code (`Art\SlotsClassic.lua`).

## Symbols

Every theme must draw all seven symbols. Ids, from the highest paying:

`seven`, `bar`, `bell`, `plum`, `orange`, `lemon`, `cherry`

The two special symbols, `wild` and `scatter`, are drawn by CowCasino itself
(`Art\SlotWild` and `Art\SlotScatter`) and look the same in every theme, so a theme
never needs them.

A symbol cell on the reels is between 60 x 38 and 80 x 60 pixels depending on the
machine; the paytable shows smaller copies, so draw to whatever size you are given.

---

## 1. Picture theme (easiest)

One image per symbol:

```lua
CowCasino.RegisterSlotIconTheme({
    id     = "fruity",                 -- unique, never changes
    name   = "Fruity",                 -- shown in the Paytable
    author = "you",
    icons  = {
        seven  = "Interface\\AddOns\\MySlots\\Images\\seven",
        bar    = "Interface\\AddOns\\MySlots\\Images\\bar",
        bell   = "Interface\\AddOns\\MySlots\\Images\\bell",
        plum   = "Interface\\AddOns\\MySlots\\Images\\plum",
        orange = "Interface\\AddOns\\MySlots\\Images\\orange",
        lemon  = "Interface\\AddOns\\MySlots\\Images\\lemon",
        cherry = "Interface\\AddOns\\MySlots\\Images\\cherry",
    },
})
```

- Any WoW icon path works too, e.g. `"Interface\\Icons\\INV_Misc_Coin_02"`.
- For a **sprite sheet**, give `{ "path", left, right, top, bottom }` instead of a path.
- Optional `background = { r, g, b, a }` paints behind each picture.
- Optional `inset` sets the padding around each picture (default 4).
- Pictures stay square and centered in the cell; `stretch = true` fills the cell instead.
- Optional `crop` trims each edge (default 0.07, which hides the border built into WoW icons). Use `crop = 0` for your own art.
- Optional `names = { seven = { "Diamond", "Diamonds" }, ... }` renames symbols in the game's messages
  ("Three Diamonds pays 200x") so the wording matches your pictures.
- A theme missing any symbol is rejected with an error naming the missing one.

## 2. Code-drawn theme (full control)

```lua
CowCasino.RegisterSlotTheme({
    id = "neon", name = "Neon", author = "you",

    -- Called once per symbol cell. Build textures and font strings on `skin`.
    Create = function(self, skin, width, height) end,

    -- Draw one symbol: symbol = { index, id, name, plural, short }
    ShowSymbol = function(self, skin, symbol) end,
})
```

`Art\SlotsClassic.lua` is a complete working example. Code themes can also set `names`.

## As a separate addon

```
## Interface: 11200
## Title: CowCasino - My Slots
## Dependencies: CowCasino

MySlots.lua
```

For WoW Forever as well, put a copy of that .toc in the same folder named after
the folder plus `_Mainline` (for example `CowCasino_MyDeck_Mainline.toc`) with
`## Interface: 16001`. WoW Forever reads that one; the 1.12 client ignores it.

`MySlots.lua` holds just the register call. If a player removes a theme they had
selected, CowCasino falls back to Azeroth.

## Inside CowCasino

Add a file under `Art\`, start it with `local ns = CowCasino.ns`, register the theme with `ns:RegisterSlotTheme(...)` or
`ns:RegisterSlotIconTheme(...)`, and list it in `CowCasino.toc` (the release script copies the file list into `CowCasino_Mainline.toc`) after `Art\SlotsClassic.lua`.
