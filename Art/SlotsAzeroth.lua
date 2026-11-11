-- CowCasino slot theme: Azeroth (the default)
-- In-game item icons: a diamond jackpot, a stack of gold, and fruit sold by
-- vendors in the original game. Icon names checked against warcraft.wiki.gg.
-- To use different icons, change the paths below; nothing else needs touching.

local ns = CowCasino.ns

ns:RegisterSlotIconTheme({
    id = "azeroth",
    name = "Azeroth",
    author = "ruin9k",
    background = { 0.12, 0.10, 0.08, 1 },
    inset = 5,
    icons = {
        seven  = "Interface\\Icons\\INV_Misc_Gem_Diamond_01",   -- jackpot
        bar    = "Interface\\Icons\\INV_Misc_Coin_02",          -- stack of gold
        bell   = "Interface\\Icons\\INV_Misc_Food_22",          -- Snapvine Watermelon
        plum   = "Interface\\Icons\\INV_Misc_Food_25",          -- Moon Harvest Pumpkin
        orange = "Interface\\Icons\\INV_Misc_Food_42",          -- Heaven Peach
        lemon  = "Interface\\Icons\\INV_Misc_Food_24",          -- Tel'Abim Banana
        cherry = "Interface\\Icons\\INV_Misc_Food_19",          -- Shiny Red Apple
    },
    -- Names used in the game's messages, so they match the pictures.
    names = {
        seven  = { "Diamond", "Diamonds" },
        bar    = { "Gold", "Gold" },
        bell   = { "Watermelon", "Watermelons" },
        plum   = { "Pumpkin", "Pumpkins" },
        orange = { "Peach", "Peaches" },
        lemon  = { "Banana", "Bananas" },
        cherry = { "Apple", "Apples" },
    },
})
