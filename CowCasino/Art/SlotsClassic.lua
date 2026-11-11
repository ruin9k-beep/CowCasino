-- CowCasino slot theme: Classic (the default)
-- Drawn entirely in code: each symbol is a colored badge with its name,
-- like an old fruit machine. Scales to whatever size the game asks for.

local ns = CowCasino.ns

local FONT = "Fonts\\FRIZQT__.TTF"

-- text, font size at 56px tall, text color, badge color
local STYLES = {
    seven  = { "7",      34, { 0.90, 0.08, 0.08 }, { 0.98, 0.95, 0.86 } },
    bar    = { "BAR",    20, { 0.08, 0.08, 0.08 }, { 0.95, 0.78, 0.20 } },
    bell   = { "BELL",   17, { 1.00, 0.85, 0.15 }, { 0.14, 0.20, 0.48 } },
    plum   = { "PLUM",   17, { 1.00, 1.00, 1.00 }, { 0.45, 0.15, 0.52 } },
    orange = { "ORANGE", 13, { 1.00, 1.00, 1.00 }, { 0.92, 0.48, 0.08 } },
    lemon  = { "LEMON",  14, { 0.22, 0.20, 0.04 }, { 0.98, 0.91, 0.30 } },
    cherry = { "CHERRY", 13, { 1.00, 1.00, 1.00 }, { 0.72, 0.06, 0.14 } },
}

ns:RegisterSlotTheme({
    id = "classic",
    name = "Classic",
    author = "ruin9k",

    Create = function(self, skin, w, h)
        -- Text was designed for an 84 x 56 cell; shrink to fit narrower cells.
        skin.scale = (h and h > 0 and w and w > 0) and math.min(h / 56, w / 84) or 1

        skin.edge = skin:CreateTexture(nil, "BACKGROUND")
        skin.edge:SetPoint("TOPLEFT", skin, "TOPLEFT", 3, -3)
        skin.edge:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -3, 3)
        skin.edge:SetTexture(0, 0, 0, 0.6)

        skin.badge = skin:CreateTexture(nil, "BORDER")
        skin.badge:SetPoint("TOPLEFT", skin, "TOPLEFT", 4, -4)
        skin.badge:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -4, 4)

        skin.shine = skin:CreateTexture(nil, "ARTWORK")
        skin.shine:SetPoint("TOPLEFT", skin.badge, "TOPLEFT", 0, 0)
        skin.shine:SetPoint("TOPRIGHT", skin.badge, "TOPRIGHT", 0, 0)
        skin.shine:SetHeight(math.max(2, 8 * skin.scale))
        skin.shine:SetTexture(1, 1, 1, 0.18)

        skin.text = skin:CreateFontString(nil, "OVERLAY")
        skin.text:SetPoint("CENTER", skin, "CENTER", 0, 0)
        skin.text:SetShadowOffset(0, 0)
    end,

    ShowSymbol = function(self, skin, symbol)
        local st = STYLES[symbol.id]
        local size = math.max(6, math.floor(st[2] * skin.scale + 0.5))
        skin.text:SetFont(FONT, size, symbol.id == "seven" and "THICKOUTLINE" or "")
        skin.text:SetText(st[1])
        skin.text:SetTextColor(st[3][1], st[3][2], st[3][3])
        skin.badge:SetTexture(st[4][1], st[4][2], st[4][3], 1)
    end,
})
