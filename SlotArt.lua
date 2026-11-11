-- CowCasino: slot machine art
-- The same idea as card art (Cards.lua): the Slots game never draws symbols
-- itself. It asks for a symbol widget and tells it which symbol to show; the
-- selected slot theme does the drawing. Themes change the look only, never
-- the odds or the paytable. See SLOT_ART.md for how to make a theme.

local ns = CowCasino.ns

local DEFAULT_THEME = "azeroth"

---------------------------------------------------------------------------
-- Symbols, highest paying first. Themes receive these info tables.
---------------------------------------------------------------------------
ns.SLOT_SYMBOLS = {
    { index = 1, id = "seven",  name = "Seven",  plural = "Sevens",   short = "7" },
    { index = 2, id = "bar",    name = "Bar",    plural = "Bars",     short = "BAR" },
    { index = 3, id = "bell",   name = "Bell",   plural = "Bells",    short = "BELL" },
    { index = 4, id = "plum",   name = "Plum",   plural = "Plums",    short = "PLUM" },
    { index = 5, id = "orange", name = "Orange", plural = "Oranges",  short = "ORANGE" },
    { index = 6, id = "lemon",  name = "Lemon",  plural = "Lemons",   short = "LEMON" },
    { index = 7, id = "cherry", name = "Cherry", plural = "Cherries", short = "CHERRY" },
}
ns.SLOT_SYMBOL = {}
for _, s in ipairs(ns.SLOT_SYMBOLS) do ns.SLOT_SYMBOL[s.id] = s end

-- Special symbols: the same painted pictures in every theme, so a theme
-- only ever draws the seven ordinary symbols above.
ns.SLOT_SPECIALS = {
    { id = "wild",    name = "Wild",    plural = "Wilds",    short = "WILD", special = true,
      image = "Interface\\AddOns\\CowCasino\\Art\\SlotWild" },
    { id = "scatter", name = "Scatter", plural = "Scatters", short = "FREE", special = true,
      image = "Interface\\AddOns\\CowCasino\\Art\\SlotScatter" },
}
for _, s in ipairs(ns.SLOT_SPECIALS) do ns.SLOT_SYMBOL[s.id] = s end

---------------------------------------------------------------------------
-- Theme registry
-- A theme is a table with:
--   id, name, author
--   Create(self, skin, w, h)          build textures/fonts on the empty frame `skin`
--   ShowSymbol(self, skin, symbol)    draw one symbol (an info table above)
--   names                             optional { id = { "Name", "Plural" } } so the
--                                     game's messages match the pictures
---------------------------------------------------------------------------
ns.slotThemes = {}
ns.slotThemeOrder = {}

local widgets = setmetatable({}, { __mode = "k" })

function ns:RegisterSlotTheme(theme)
    assert(type(theme) == "table" and type(theme.id) == "string", "CowCasino: slot theme needs an id")
    for _, fn in ipairs({ "Create", "ShowSymbol" }) do
        assert(type(theme[fn]) == "function",
            "CowCasino: slot theme '" .. theme.id .. "' is missing " .. fn)
    end
    theme.name = theme.name or theme.id
    if not self.slotThemes[theme.id] then
        table.insert(self.slotThemeOrder, theme.id)
    end
    self.slotThemes[theme.id] = theme
    return theme
end

function ns:GetSlotTheme()
    local id = self.db and self.db.slotTheme
    return self.slotThemes[id] or self.slotThemes[DEFAULT_THEME] or self.slotThemes[self.slotThemeOrder[1]]
end

-- The symbol's name in the current theme ("Diamond" rather than "Seven").
function ns:SlotSymbolName(id, plural)
    local theme = self:GetSlotTheme()
    local custom = theme and theme.names and theme.names[id]
    if custom then return plural and (custom[2] or custom[1]) or custom[1] end
    local s = self.SLOT_SYMBOL[id]
    if not s then return tostring(id) end
    return plural and s.plural or s.name
end

function ns:SetSlotTheme(id)
    if not self.slotThemes[id] then return end
    self.db.slotTheme = id
    self.db.slotThemeChosen = true
    for w in pairs(widgets) do w:ApplyArt() end
end

-- Helper for picture themes: one image per symbol.
-- def = {
--   id, name, author,
--   icons = { seven = "path", bar = "path", ... }   every symbol id
--           a value can also be { "path", left, right, top, bottom } for a sprite sheet
--   names       optional { id = { "Name", "Plural" } }, e.g. seven = { "Diamond", "Diamonds" }
--   background  optional { r, g, b, a } color behind each picture
--   inset       optional padding around the picture in pixels (default 4)
--   crop        optional share trimmed off each edge of a picture (default 0.07,
--               which hides the border baked into WoW icons; use 0 for your own art)
--   stretch     true to fill the whole cell instead of keeping pictures square
-- }
function ns:RegisterSlotIconTheme(def)
    assert(type(def) == "table" and def.id and type(def.icons) == "table",
        "CowCasino: slot icon theme needs an id and icons")
    for _, s in ipairs(self.SLOT_SYMBOLS) do
        assert(def.icons[s.id], "CowCasino: slot icon theme '" .. def.id .. "' has no icon for " .. s.id)
    end
    local inset = def.inset or 4
    local crop = def.crop or 0.07

    return self:RegisterSlotTheme({
        id = def.id,
        name = def.name,
        author = def.author,
        names = def.names,
        Create = function(_, skin, w, h)
            if def.background then
                local bg = skin:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints(skin)
                local c = def.background
                bg:SetTexture(c[1], c[2], c[3], c[4] or 1)
            end
            skin.tex = skin:CreateTexture(nil, "ARTWORK")
            if def.stretch or not (w and h and w > 0 and h > 0) then
                skin.tex:SetPoint("TOPLEFT", skin, "TOPLEFT", inset, -inset)
                skin.tex:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -inset, inset)
            else
                local size = math.min(w, h) - 2 * inset
                skin.tex:SetWidth(size); skin.tex:SetHeight(size)
                skin.tex:SetPoint("CENTER", skin, "CENTER", 0, 0)
            end
        end,
        ShowSymbol = function(_, skin, symbol)
            local icon = def.icons[symbol.id]
            if type(icon) == "table" then
                skin.tex:SetTexture(icon[1])
                skin.tex:SetTexCoord(icon[2] or 0, icon[3] or 1, icon[4] or 0, icon[5] or 1)
            else
                skin.tex:SetTexture(icon)
                skin.tex:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
            end
        end,
    })
end

---------------------------------------------------------------------------
-- Symbol widget
-- local w = ns:CreateSymbolWidget(parent, width, height)
-- w:SetSymbol(id)   w:Clear()   w:SetLevel(n)
---------------------------------------------------------------------------
local Widget = {}

-- Wild and scatter: one picture, whatever the theme.
local function ShowSpecial(self, symbol)
    local skin = self.special
    if not skin then
        skin = ns.CreateFrame("Frame", nil, self)
        skin:SetAllPoints(self)
        skin:SetFrameLevel(self:GetFrameLevel() + 1)
        local bg = skin:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(skin)
        bg:SetTexture(0.10, 0.06, 0.14, 1)
        skin.tex = skin:CreateTexture(nil, "ARTWORK")
        local w, h = self:GetWidth() or 40, self:GetHeight() or 40
        local size = math.min(w, h) - 2
        skin.tex:SetWidth(size); skin.tex:SetHeight(size)
        skin.tex:SetPoint("CENTER", skin, "CENTER", 0, 0)
        self.special = skin
    end
    skin.tex:SetTexture(symbol.image)
    skin:Show()
end

function Widget:ApplyArt()
    local theme = ns:GetSlotTheme()
    if not theme then return end

    local symbol = self.symbol and ns.SLOT_SYMBOL[self.symbol]
    if symbol and symbol.special then
        for _, skin in pairs(self.skins) do skin:Hide() end
        ShowSpecial(self, symbol)
        return
    end
    if self.special then self.special:Hide() end

    for id, skin in pairs(self.skins) do
        if id ~= theme.id then skin:Hide() end
    end

    local skin = self.skins[theme.id]
    if not skin then
        skin = ns.CreateFrame("Frame", nil, self)
        skin:SetAllPoints(skin:GetParent())
        skin:SetFrameLevel(self:GetFrameLevel() + 1)
        self.skins[theme.id] = skin
        theme:Create(skin, self:GetWidth(), self:GetHeight())
    end

    if not symbol then
        skin:Hide()
        return
    end
    theme:ShowSymbol(skin, symbol)
    skin:Show()
end

function Widget:SetSymbol(id)
    if self.symbol == id and (self.skins[ns:GetSlotTheme().id] or (self.special and self.special:IsShown())) then
        self:Show()
        return
    end
    self.symbol = id
    self:ApplyArt()
    self:Show()
end

function Widget:Clear()
    self.symbol = nil
    self:Hide()
end

function Widget:SetLevel(level)
    self:SetFrameLevel(level)
    for _, skin in pairs(self.skins) do skin:SetFrameLevel(level + 1) end
    if self.special then self.special:SetFrameLevel(level + 1) end
end

function ns:CreateSymbolWidget(parent, width, height)
    local f = ns.CreateFrame("Frame", nil, parent)
    f:SetWidth(width); f:SetHeight(height)
    f.skins = {}
    for k, v in pairs(Widget) do f[k] = v end
    widgets[f] = true
    f:Hide()
    return f
end

---------------------------------------------------------------------------
-- Public API for other addons. See SLOT_ART.md.
---------------------------------------------------------------------------
CowCasino = CowCasino or {}
CowCasino.SLOT_SYMBOLS = ns.SLOT_SYMBOLS
function CowCasino.RegisterSlotTheme(theme) return ns:RegisterSlotTheme(theme) end
function CowCasino.RegisterSlotIconTheme(def) return ns:RegisterSlotIconTheme(def) end
