-- CowCasino card art: Plain (the default)
-- Drawn entirely in code: a cream card with the rank and suit symbol,
-- and a blue back. Scales to whatever size the game asks for.

local ns = CowCasino.ns

local SUIT_FONT = "Fonts\\ARIALN.TTF"
local RANK_FONT = "Fonts\\FRIZQT__.TTF"

local RED   = { 0.80, 0.10, 0.10 }
local BLACK = { 0.10, 0.10, 0.10 }

local function Font(parent, file, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(file, math.max(6, math.floor(size + 0.5)), "")
    fs:SetShadowOffset(0, 0)
    return fs
end

ns:RegisterCardArt({
    id = "plain",
    name = "Plain",
    author = "ruin9k",

    Create = function(self, skin, w, h)
        local s = (h and h > 0) and (h / 70) or 1

        skin.edge = skin:CreateTexture(nil, "BACKGROUND")
        skin.edge:SetAllPoints(skin)
        skin.edge:SetTexture(0, 0, 0, 1)

        skin.face = skin:CreateTexture(nil, "BORDER")
        skin.face:SetPoint("TOPLEFT", skin, "TOPLEFT", 1, -1)
        skin.face:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -1, 1)
        skin.face:SetTexture(0.97, 0.97, 0.94, 1)

        skin.rank = Font(skin, RANK_FONT, 14 * s)
        skin.rank:SetPoint("TOPLEFT", skin, "TOPLEFT", 4 * s, -4 * s)

        skin.smallSuit = Font(skin, SUIT_FONT, 12 * s)
        skin.smallSuit:SetPoint("TOP", skin.rank, "BOTTOM", 0, -1)

        skin.bigSuit = Font(skin, SUIT_FONT, 30 * s)
        skin.bigSuit:SetPoint("CENTER", skin, "CENTER", 4 * s, -6 * s)

        skin.back = skin:CreateTexture(nil, "ARTWORK")
        skin.back:SetPoint("TOPLEFT", skin, "TOPLEFT", 3, -3)
        skin.back:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -3, 3)
        skin.back:SetTexture(0.10, 0.20, 0.55, 1)

        skin.backInner = skin:CreateTexture(nil, "ARTWORK")
        skin.backInner:SetPoint("TOPLEFT", skin, "TOPLEFT", 8 * s, -8 * s)
        skin.backInner:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -8 * s, 8 * s)
        skin.backInner:SetTexture(0.20, 0.35, 0.75, 1)
    end,

    ShowFace = function(self, skin, rank, suit)
        local c = suit.red and RED or BLACK
        skin.rank:SetText(rank.key)
        skin.smallSuit:SetText(suit.symbol)
        skin.bigSuit:SetText(suit.symbol)
        for _, fs in ipairs({ skin.rank, skin.smallSuit, skin.bigSuit }) do
            fs:SetTextColor(c[1], c[2], c[3])
            fs:Show()
        end
        skin.back:Hide()
        skin.backInner:Hide()
    end,

    ShowBack = function(self, skin)
        skin.rank:Hide()
        skin.smallSuit:Hide()
        skin.bigSuit:Hide()
        skin.back:Show()
        skin.backInner:Show()
    end,
})
