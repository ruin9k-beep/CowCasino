-- CowCasino: cards
-- Shared by every card game: card data, the shoe, the card art registry
-- and the card widget. Games never draw cards themselves; they ask for a
-- widget and tell it which card to show. The selected art pack does the rest.
-- See CARD_ART.md for how to make an art pack.

local ns = CowCasino.ns

local DEFAULT_ART = "plain"

---------------------------------------------------------------------------
-- Card data
-- A card is { rank = 1..13, suit = 1..4 }. Art packs receive the full
-- rank and suit info tables below.
---------------------------------------------------------------------------
ns.SUITS = {
    { index = 1, key = "S", name = "Spades",   symbol = "\226\153\160", red = false },
    { index = 2, key = "H", name = "Hearts",   symbol = "\226\153\165", red = true  },
    { index = 3, key = "D", name = "Diamonds", symbol = "\226\153\166", red = true  },
    { index = 4, key = "C", name = "Clubs",    symbol = "\226\153\163", red = false },
}

ns.RANKS = {}
do
    local keys  = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
    local names = { "Ace", "Two", "Three", "Four", "Five", "Six", "Seven",
                    "Eight", "Nine", "Ten", "Jack", "Queen", "King" }
    for i = 1, 13 do
        ns.RANKS[i] = { index = i, key = keys[i], name = names[i], face = i >= 11 }
    end
end

---------------------------------------------------------------------------
-- Shoe: one or more shuffled decks with a cut card.
---------------------------------------------------------------------------
local Shoe = {}
Shoe.__index = Shoe

-- penetration: share of the shoe dealt before it asks for a reshuffle.
function ns:NewShoe(decks, penetration)
    local shoe = setmetatable({
        decks = decks or 1,
        penetration = penetration or 0.75,
        cards = {},
    }, Shoe)
    shoe:Shuffle()
    return shoe
end

function Shoe:Shuffle()
    local cards = {}
    for _ = 1, self.decks do
        for s = 1, 4 do
            for r = 1, 13 do
                cards[ns.getn(cards) + 1] = { rank = r, suit = s }
            end
        end
    end
    for i = ns.getn(cards), 2, -1 do
        local j = math.random(i)
        cards[i], cards[j] = cards[j], cards[i]
    end
    self.cards = cards
    self.cutCard = math.floor(ns.getn(cards) * (1 - self.penetration))
    self.needsShuffle = false
end

function Shoe:Draw()
    if ns.getn(self.cards) == 0 then self:Shuffle() end
    local card = table.remove(self.cards)
    if ns.getn(self.cards) <= self.cutCard then self.needsShuffle = true end
    return card
end

function Shoe:Remaining()
    return ns.getn(self.cards)
end

---------------------------------------------------------------------------
-- Card art registry
-- A pack is a table with:
--   id, name                      required id, display name
--   author                        optional
--   Create(self, skin, w, h)      build textures/fonts on the empty frame `skin`
--   ShowFace(self, skin, rank, suit)   show a card face (rank/suit info tables)
--   ShowBack(self, skin)          show the card back
---------------------------------------------------------------------------
ns.cardArt = {}
ns.cardArtOrder = {}

local widgets = setmetatable({}, { __mode = "k" })

function ns:RegisterCardArt(pack)
    assert(type(pack) == "table" and type(pack.id) == "string", "CowCasino: card art needs an id")
    for _, fn in ipairs({ "Create", "ShowFace", "ShowBack" }) do
        assert(type(pack[fn]) == "function",
            "CowCasino: card art '" .. pack.id .. "' is missing " .. fn)
    end
    pack.name = pack.name or pack.id
    if not self.cardArt[pack.id] then
        table.insert(self.cardArtOrder, pack.id)
    end
    self.cardArt[pack.id] = pack
    return pack
end

function ns:GetCardArt()
    local id = self.db and self.db.cardArt
    return self.cardArt[id] or self.cardArt[DEFAULT_ART] or self.cardArt[self.cardArtOrder[1]]
end

function ns:SetCardArt(id)
    if not self.cardArt[id] then return end
    self.db.cardArt = id
    for w in pairs(widgets) do w:ApplyArt() end
end

-- Helper for image-based decks: one image per card plus a back.
-- def = {
--   id, name, author,
--   path      folder, e.g. "Interface\\AddOns\\MyCards\\Images\\"
--   ext       optional file extension (".tga", ".blp"); WoW finds the file without one
--   back      optional back file name (default "back")
--   FaceFile  optional function(rank, suit) -> file [, left, right, top, bottom]
--             for other file names or a sprite sheet
--   backFile, backCoords  optional overrides for the back
-- }
-- Default file names are rank key + suit key: AS, 10H, KD, 7C ... and back.
function ns:RegisterTextureDeck(def)
    assert(type(def) == "table" and def.id and def.path,
        "CowCasino: texture deck needs an id and a path")

    local path = def.path
    local last = string.sub(path, -1)
    if last ~= "\\" and last ~= "/" then path = path .. "\\" end
    local ext = def.ext or ""
    local backFile = def.backFile or (path .. (def.back or "back") .. ext)
    local backCoords = def.backCoords or { 0, 1, 0, 1 }

    local function FaceFile(rank, suit)
        if def.FaceFile then return def.FaceFile(rank, suit) end
        return path .. rank.key .. suit.key .. ext
    end

    return self:RegisterCardArt({
        id = def.id,
        name = def.name,
        author = def.author,
        Create = function(_, skin)
            skin.tex = skin:CreateTexture(nil, "ARTWORK")
            skin.tex:SetAllPoints(skin)
        end,
        ShowFace = function(_, skin, rank, suit)
            local file, l, r, t, b = FaceFile(rank, suit)
            skin.tex:SetTexture(file)
            skin.tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
        end,
        ShowBack = function(_, skin)
            skin.tex:SetTexture(backFile)
            skin.tex:SetTexCoord(backCoords[1], backCoords[2], backCoords[3], backCoords[4])
        end,
    })
end

---------------------------------------------------------------------------
-- Card widget
-- local w = ns:CreateCardWidget(parent, width, height)
-- w:SetCard(card, faceUp)   faceUp defaults to true
-- w:Clear()                 hide it
-- w:SetLevel(n)             frame level, for overlapping cards
-- Each widget keeps one "skin" frame per art pack it has used, so switching
-- art (even mid-hand) just swaps which skin is shown.
---------------------------------------------------------------------------
local Widget = {}

function Widget:ApplyArt()
    local pack = ns:GetCardArt()
    if not pack then return end

    for id, skin in pairs(self.skins) do
        if id ~= pack.id then skin:Hide() end
    end

    local skin = self.skins[pack.id]
    if not skin then
        skin = ns.CreateFrame("Frame", nil, self)
        skin:SetAllPoints(skin:GetParent())
        skin:SetFrameLevel(self:GetFrameLevel() + 1)
        self.skins[pack.id] = skin
        pack:Create(skin, self:GetWidth(), self:GetHeight())
    end

    if not self.card then
        skin:Hide()
        return
    end
    if self.faceUp then
        pack:ShowFace(skin, ns.RANKS[self.card.rank], ns.SUITS[self.card.suit])
    else
        pack:ShowBack(skin)
    end
    skin:Show()
end

function Widget:SetCard(card, faceUp)
    self.card = card
    self.faceUp = faceUp ~= false
    self:ApplyArt()
    self:Show()
end

function Widget:Clear()
    self.card = nil
    self:Hide()
end

function Widget:SetLevel(level)
    self:SetFrameLevel(level)
    for _, skin in pairs(self.skins) do skin:SetFrameLevel(level + 1) end
end

function ns:CreateCardWidget(parent, width, height)
    local f = ns.CreateFrame("Frame", nil, parent)
    f:SetWidth(width); f:SetHeight(height)
    f.skins = {}
    for k, v in pairs(Widget) do f[k] = v end
    widgets[f] = true
    f:Hide()
    return f
end

---------------------------------------------------------------------------
-- Public API for other addons (card art packs). See CARD_ART.md.
---------------------------------------------------------------------------
CowCasino = CowCasino or {}
CowCasino.SUITS = ns.SUITS
CowCasino.RANKS = ns.RANKS
function CowCasino.RegisterCardArt(pack) return ns:RegisterCardArt(pack) end
function CowCasino.RegisterTextureDeck(def) return ns:RegisterTextureDeck(def) end
