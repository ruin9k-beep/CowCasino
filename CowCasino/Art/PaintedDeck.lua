-- CowCasino card art: shared code for painted decks (Tauren, Orc & Troll).
-- A painted deck is four images plus text ranks, so the ranks stay sharp at
-- any card size:
--   <prefix>CardFace / <prefix>CardBack  the card in the top-left 92x128 of a 128x128 file
--   <prefix>Suits  spade, heart, diamond, club, 64x64 each in a 256x64 sheet
--   <prefix>Court  jack, queen, king, 64x64 each in a 256x64 sheet
-- The images are made by the scripts in art-src (not shipped).

local ns = CowCasino.ns

local ART = "Interface\\AddOns\\CowCasino\\Art\\"
local RANK_FONT = "Fonts\\FRIZQT__.TTF"
local CARD_U, CARD_V = 92 / 128, 1          -- where the card sits in its file
local SUIT_INDEX = { S = 0, H = 1, D = 2, C = 3 }
local COURT_INDEX = { J = 0, Q = 1, K = 2 }

-- A 64x64 cell of a 256x64 sheet.
local function Cell(tex, index)
    tex:SetTexCoord(index * 0.25, (index + 1) * 0.25, 0, 1)
end

local function Size(tex, size)
    tex:SetWidth(size); tex:SetHeight(size)
end

-- def: id, name, author, prefix (image name prefix), red and dark ({ r, g, b }
-- for the rank text of red and black suits)
function ns:RegisterPaintedDeck(def)
    local face, back = ART .. def.prefix .. "CardFace", ART .. def.prefix .. "CardBack"
    local suits, court = ART .. def.prefix .. "Suits", ART .. def.prefix .. "Court"
    local red, dark = def.red, def.dark
    return self:RegisterCardArt({
        id = def.id,
        name = def.name,
        author = def.author,

        Create = function(self, skin, w, h)
            local s = (h and h > 0) and (h / 64) or 1

            skin.card = skin:CreateTexture(nil, "BACKGROUND")
            skin.card:SetAllPoints(skin)
            skin.card:SetTexCoord(0, CARD_U, 0, CARD_V)

            skin.rank = skin:CreateFontString(nil, "OVERLAY")
            skin.rank:SetFont(RANK_FONT, math.max(6, math.floor(13 * s + 0.5)), "")
            skin.rank:SetShadowOffset(0, 0)
            skin.rank:SetPoint("TOPLEFT", skin, "TOPLEFT", 4 * s, -3 * s)

            skin.smallSuit = skin:CreateTexture(nil, "ARTWORK")
            skin.smallSuit:SetTexture(suits)
            Size(skin.smallSuit, math.max(5, 10 * s))
            skin.smallSuit:SetPoint("TOPLEFT", skin, "TOPLEFT", 4.5 * s, -18 * s)

            skin.bigSuit = skin:CreateTexture(nil, "ARTWORK")
            skin.bigSuit:SetTexture(suits)
            Size(skin.bigSuit, 24 * s)
            skin.bigSuit:SetPoint("CENTER", skin, "CENTER", 3 * s, -5 * s)

            skin.emblem = skin:CreateTexture(nil, "ARTWORK")
            skin.emblem:SetTexture(court)
            Size(skin.emblem, 31 * s)
            skin.emblem:SetPoint("CENTER", skin, "CENTER", 5 * s, -5 * s)
        end,

        ShowFace = function(self, skin, rank, suit)
            skin.card:SetTexture(face)
            local c = suit.red and red or dark
            skin.rank:SetText(rank.key)
            skin.rank:SetTextColor(c[1], c[2], c[3])
            skin.rank:Show()
            Cell(skin.smallSuit, SUIT_INDEX[suit.key] or 0)
            skin.smallSuit:Show()
            local courtIndex = COURT_INDEX[rank.key]
            if courtIndex then
                Cell(skin.emblem, courtIndex)
                skin.emblem:Show()
                skin.bigSuit:Hide()
            else
                Cell(skin.bigSuit, SUIT_INDEX[suit.key] or 0)
                skin.bigSuit:Show()
                skin.emblem:Hide()
            end
        end,

        ShowBack = function(self, skin)
            skin.card:SetTexture(back)
            skin.rank:Hide()
            skin.smallSuit:Hide()
            skin.bigSuit:Hide()
            skin.emblem:Hide()
        end,
    })
end
