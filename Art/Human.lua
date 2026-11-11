-- CowCasino card art: Human
-- The Plain card faces with a painted back: royal blue with a gold border
-- and lattice, and a heraldic shield on crossed swords under a crown.
-- (Image: Art\HumanCardBack.tga, made by dev/art-src/make_race_cards.py.)

local ns = CowCasino.ns

local BACK = "Interface\\AddOns\\CowCasino\\Art\\HumanCardBack"

ns:RegisterCardArt({
    id = "human",
    name = "Human",
    author = "ruin9k",

    Create = function(self, skin, w, h)
        ns.cardArt.plain:Create(skin, w, h)
        skin.humanBack = skin:CreateTexture(nil, "ARTWORK")
        skin.humanBack:SetAllPoints(skin)
        skin.humanBack:SetTexture(BACK)
        skin.humanBack:SetTexCoord(0, 92 / 128, 0, 1)   -- the card in the top-left 92x128 of the file
        skin.humanBack:Hide()
    end,

    ShowFace = function(self, skin, rank, suit)
        skin.humanBack:Hide()
        skin.edge:Show()
        skin.face:Show()
        ns.cardArt.plain:ShowFace(skin, rank, suit)
    end,

    ShowBack = function(self, skin)
        ns.cardArt.plain:ShowBack(skin)
        -- the painted back has its own rounded edge: hide Plain's card under it
        skin.back:Hide()
        skin.backInner:Hide()
        skin.edge:Hide()
        skin.face:Hide()
        skin.humanBack:Show()
    end,
})
