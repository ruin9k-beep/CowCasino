# CowCasino

A just-for-fun casino addon for World of Warcraft. No real gold is ever wagered:
you play with pretend chips, and if you run out you pick a fresh stack.

One addon folder runs on two clients:

- **1.12** (Octo, Turtle WoW and other 1.12 servers), through `CowCasino.toc`
- **WoW Forever** (the modern client), through `CowCasino_Mainline.toc`

## Games

- **Blackjack**, solo or at a party table (up to four players, one hosting)
- **Texas Hold'em** with your party, plus computer players
- **Craps**, solo or at a party table: Pass Line, odds, Field and more
- **Roulette**
- **Slots**: 3x3, 5x4 and 5x5 machines with wild multipliers, scatters, free spins
  with a rising multiplier, big win banners and auto spin
- **Mines**
- **Plinko**: 8, 12 or 16 rows, three risk levels, up to 10 balls a drop
- **Crash**, with auto cash-out

Also: swappable card art (Plain, Tauren, Orc & Troll, Human) and slot themes, 3D player
portraits and table chat at party tables, a minimap button and per-game sounds.
Type `/casino` to open it.

## Install

Copy the `CowCasino` folder into your game's `Interface\AddOns` folder (the same folder
works for both clients), then restart the game.

## Making your own art

- Card art packs: [CowCasino/CARD_ART.md](CowCasino/CARD_ART.md)
- Slot themes: [CowCasino/SLOT_ART.md](CowCasino/SLOT_ART.md)

The painted images are made by the Python scripts in `art-src` (they need Pillow).
`art-src/slots-math` has the model the Slots odds were tuned with.

## Building and testing

```
python3 release.py            # check, test on both clients, write CowCasino.zip
python3 release.py --no-zip   # check and test only
```

`release.py` writes `CowCasino_Mainline.toc` from `CowCasino.toc` (edit only the 1.12 one),
checks every file for Lua 5.0 problems, and runs the tests in `tests/` against a strict
mock of each client. The tests run with `texlua` (LuaTeX's Lua). `startup_tests` loads a
real saved-variables file; point `COWCASINO_SAVE` at one to include it.

By ruin9k.
