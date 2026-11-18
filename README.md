# CowCasino

A just-for-fun casino addon for World of Warcraft. No real gold is ever wagered:
you play with pretend chips, and if you run out you pick a fresh stack.

One addon folder runs on two clients:

- **1.12** (Octo, Turtle WoW and other 1.12 servers), through `CowCasino.toc`
- **WoW Forever** (the modern client), through `CowCasino_Mainline.toc`

## Games

- **Blackjack**, solo or at a party table (up to four players, one hosting)
- **Texas Hold'em** with your party, plus computer players
- **Five-Card Draw**: you and four computer players, or up to five from your party (the host sets
  the blinds and buy-in, and whether computer players fill empty seats)
- **Craps**, solo or at a party table: Pass Line, odds, Field and more
- **Roulette**
- **Slots**: 3x3, 5x4 and 5x5 machines with wild multipliers, scatters, free spins
  with a rising multiplier, big win banners and auto spin
- **Mines**
- **Plinko**: 8, 12 or 16 rows, three risk levels, up to 100 balls a drop
- **Crash**, with auto cash-out
- **Hi-Lo**: higher or lower, with the multiplier growing each right guess
- **Video Poker**: Jacks or Better (the 9/6 pay table), one to five coins, hold and draw
- **Three Card Poker**: Ante and Play against the dealer, with the Ante bonus and a Pair Plus side bet
- **Keno**: pick 1 to 10 of 80 numbers, twenty are drawn; quick pick and auto play
- **Deathroll**: the classic gold duel, against the dealer or with your party (real /rolls)
- **Checkers**: American checkers against the computer (Easy, Medium or Hard) or anyone in your party
- **Chess**: the full game against the computer (Easy, Medium or Hard) or anyone in your party; a reload
  picks the game back up
- **Battleship**: the classic 10 x 10 sea, against the computer (Easy, Medium or Hard) or anyone in your party;
  party fleets stay secret and are checked against every answer at the end
- **Sketch & Guess**: a party drawing game. Everyone takes a turn drawing a secret word while the
  others race to guess it; the host picks the words (built-in packs, their own list or both), the
  time to draw and the turns each. Practice mode lets you doodle on your own

Party tables, party duels and party board games are free to join: everyone plays with the stack the host
picks, and nobody's own chips are touched. Run short at a table and you can top back up to
that stack between hands. Everyone at a table needs the same party version of CowCasino;
a table from another version shows in the list but can't be joined.

A goblin dealer sits on top of the window and talks you through the game (Blackjack, Texas Hold'em, Five-Card Draw, Craps, Three Card Poker, Deathroll, Checkers, Chess and Battleship).
Pick another dealer in Options (the Display tab), or add your own ([DEALERS.md](DEALERS.md)); `Dealer.lua`
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

Releases: when a push to main changes the version in `CowCasino.toc`, the GitHub workflow in
`.github/workflows/release.yml` builds the zip and publishes release `v<version>` with
`CowCasino-forever.zip` attached, the name updaters such as wowui.io look for. (It can also be
run by hand from the repository's Actions tab; it skips a version that's already released.)

Drawing games share a kit, `Games/SketchKit.lua` (`ns.SketchKit`): a canvas (strokes in a 256 x 256
space, drawn as rotated lines or as dots), a tools bar (colors, sizes, eraser, Undo, Clear) and a sync
that keeps everyone's copy of a drawing in step over the party (several artists can share one canvas).
Word packs live in `Games/SketchWords.lua`. `Games/Sketch.lua` shows how a game puts them together.

Test files share `dev/tests/harness.lua`: `Check`, `Start` (a fresh client), `Find`,
`Press`, `Tick`, `Done`, and `H.Party` for party tests (isolated clients on a simulated
party channel).

By ruin9k.
