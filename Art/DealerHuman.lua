-- CowCasino dealer: Harold, the human
-- Picture: Art\DealerHuman.tga, made by dev/art-src/make_dealer.py.
-- A quiet one: he has no lines, so the games show their own plain messages.

local ns = CowCasino.ns
local ART = "Interface\\AddOns\\CowCasino\\Art\\"

ns:RegisterDealer({ id = "human", name = "Human", title = "Harold", author = "ruin9k",
    image = ART .. "DealerHuman" })
