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
- **Plinko**: 8, 12 or 16 rows, three risk levels, up to 100 balls a drop
- **Crash**, with auto cash-out
- **Hi-Lo**: higher or lower, with the multiplier growing each right guess

A goblin dealer sits on top of the window and talks you through the game (Blackjack, Texas Hold'em and Craps so far).
Pick another dealer in Options, or add your own ([DEALERS.md](DEALERS.md)); `Dealer.lua`
explains how a game drives it, including showing a party member's 3D portrait.

Also: swappable card art (Plain, Tauren, Orc & Troll, Human) and slot themes, 3D player
portraits and table chat at party tables, a minimap button and per-game sounds.
Type `/casino` to open it.

## Install

**With an addon manager** (GitAddonsManager, the Turtle WoW launcher, WowUp and others that
install from GitHub): add `https://github.com/ruin9k-beep/CowCasino`. The repo is the addon
folder itself, so it installs as `Interface\AddOns\CowCasino` and updates in place.

**By hand:** download the zip from the latest release, or **Code > Download ZIP** here. Put the
folder in your game's `Interface\AddOns` folder and make sure it's named exactly `CowCasino`
(GitHub's download is named `CowCasino-main`; rename it). The same folder works for both
clients. Restart the game afterwards.

## Making your own art

- Card art packs: [CARD_ART.md](CARD_ART.md)
- Slot themes: [SLOT_ART.md](SLOT_ART.md)
- Dealers: [DEALERS.md](DEALERS.md)

The painted images are made by the Python scripts in `dev/art-src` (they need Pillow).
`dev/art-src/slots-math` has the model the Slots odds were tuned with.

## Building and testing

Everything for development lives in `dev/` (the game never loads it):

```
python3 dev/release.py            # check, test on both clients, write dev/CowCasino.zip
python3 dev/release.py --no-zip   # check and test only
```

`release.py` writes `CowCasino_Mainline.toc` from `CowCasino.toc` (edit only the 1.12 one),
checks every file for Lua 5.0 problems, and runs the tests in `dev/tests` against a strict
mock of each client. The tests run with `texlua` (LuaTeX's Lua). `startup_tests` loads a
real saved-variables file; point `COWCASINO_SAVE` at one to include it. The zip it makes
holds just the addon, ready to unzip into `Interface\AddOns`.

By ruin9k.
