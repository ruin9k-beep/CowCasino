-- CowCasino: word packs for drawing games (Sketch & Guess), and how a guess
-- is checked against a word. A pack is { key, name, words }; the key is one
-- letter, so a host's choice of packs travels as a short string ("ecl").
-- Another game can add packs with table.insert(ns.SketchWords.PACKS, ...).
local ns = CowCasino.ns

local W = {}
ns.SketchWords = W

W.PACKS = {
    { key = "e", name = "Everyday", words = {
        "house", "tree", "sun", "moon", "star", "cloud", "rain", "snowman", "flower", "apple", "banana", "pizza",
        "cake", "coffee", "car", "bicycle", "train", "airplane", "boat", "clock", "book", "chair", "table", "bed",
        "door", "window", "lamp", "umbrella", "glasses", "hat", "shoe", "guitar", "drum", "piano", "balloon", "kite",
        "rainbow", "mountain", "river", "beach", "fish", "cat", "dog", "horse", "snake", "snail", "butterfly", "bee",
        "elephant", "giraffe", "penguin", "robot", "rocket", "ghost", "crown", "heart", "ladder", "candle", "bridge",
        "volcano", "island", "cactus", "mushroom", "spider web", "toothbrush", "scissors", "hammer", "light bulb" } },
    { key = "c", name = "Creatures", words = {
        "murloc", "kobold", "gnoll", "dragon", "wolf", "bear", "spider", "raptor", "kodo", "owl", "bat", "boar",
        "crocolisk", "scorpid", "turtle", "gryphon", "wind rider", "hippogryph", "ghoul", "skeleton", "ogre",
        "harpy", "fire elemental", "imp", "felhound", "basilisk", "crab", "shark", "centaur", "quilboar", "furbolg",
        "treant", "wisp", "satyr", "naga", "worg", "chimaera", "moonkin", "yeti", "tiger", "gorilla", "ooze",
        "frog", "rabbit", "chicken", "cow", "sheep", "squirrel", "abomination", "gargoyle", "infernal", "succubus",
        "voidwalker", "core hound", "bog beast", "silithid", "tallstrider" } },
    { key = "l", name = "Loot", words = {
        "sword", "shield", "axe", "mace", "staff", "wand", "bow", "gun", "dagger", "helmet", "boots", "gloves",
        "cloak", "ring", "necklace", "potion", "scroll", "bag", "gold coin", "hearthstone", "fishing pole", "pickaxe",
        "torch", "treasure map", "key", "treasure chest", "bandage", "bread", "arrow", "trinket", "tabard", "robe",
        "belt", "quiver", "spellbook", "crystal", "herb", "ore", "leather", "gem", "mount", "pet", "lockbox",
        "mining pick", "skinning knife", "elixir", "two handed sword", "spear", "anvil" } },
    { key = "s", name = "Classes & spells", words = {
        "warrior", "mage", "priest", "rogue", "druid", "hunter", "shaman", "paladin", "warlock", "orc", "tauren",
        "troll", "undead", "human", "dwarf", "gnome", "night elf", "fireball", "frost nova", "heal", "stealth",
        "bear form", "cat form", "totem", "polymorph", "fear", "blink", "resurrect", "taunt", "charge",
        "shield wall", "backstab", "sprint", "moonfire", "lightning bolt", "sap", "tank", "healer", "aggro",
        "power word shield", "ice block", "feign death", "divine shield", "mind control", "soulstone", "pull" } },
    { key = "a", name = "Around Azeroth", words = {
        "Stormwind", "Orgrimmar", "Ironforge", "Undercity", "Thunder Bluff", "Darnassus", "Goldshire", "Booty Bay",
        "Gadgetzan", "Molten Core", "Deadmines", "Westfall", "Duskwood", "Ashenvale", "Winterspring", "Moonglade",
        "Crossroads", "Elwynn Forest", "Teldrassil", "Dun Morogh", "Tirisfal Glades", "inn", "bank", "mailbox",
        "auction house", "graveyard", "flight path", "campfire", "forge", "zeppelin", "tram", "castle", "crypt",
        "mine", "farm", "windmill", "lighthouse", "tent", "portal", "dungeon", "guild", "battleground", "barber",
        "spirit healer", "fishing", "duel", "group" } },
}

function W.Pack(key)
    for _, p in ipairs(W.PACKS) do if p.key == key then return p end end
end

-- Only what a word may carry over the wire (no ; ~ | , which messages use).
function W.Clean(text)
    text = string.gsub(text or "", "[;~|,%c]", " ")
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^ ", "")
    text = string.gsub(text, " $", "")
    return string.sub(text, 1, 40)
end

-- A host's own words: a comma (or new line) separated list.
function W.ParseCustom(text)
    local out, seen = {}, {}
    text = string.gsub(text or "", "[\n;]", ",")
    for _, part in ipairs(ns.Net.Split(text, ",")) do
        local w = W.Clean(part)
        local key = W.Norm(w)
        if key ~= "" and not seen[key] then
            seen[key] = true
            table.insert(out, w)
        end
    end
    return out
end

-- Every word the chosen packs (and, with custom set, the host's list) hold.
function W.Pool(packs, customText)
    local out = {}
    for i = 1, string.len(packs or "") do
        local p = W.Pack(string.sub(packs, i, i))
        if p then for _, w in ipairs(p.words) do table.insert(out, w) end end
    end
    if customText then
        for _, w in ipairs(W.ParseCustom(customText)) do table.insert(out, w) end
    end
    return out
end

-- How a guess compares: lower case, letters and digits only ("Night-elf",
-- "night elf" and "nightelf" all match).
function W.Norm(text)
    return string.gsub(string.lower(text or ""), "[^%w]", "")
end

-- One letter added, dropped or changed (for "close!").
function W.Close(a, b)
    local la, lb = string.len(a), string.len(b)
    if la < 4 or math.abs(la - lb) > 1 or a == b then return false end
    local i, j, edits = 1, 1, 0
    while i <= la or j <= lb do
        if string.sub(a, i, i) == string.sub(b, j, j) then
            i, j = i + 1, j + 1
        else
            edits = edits + 1
            if edits > 1 then return false end
            if la > lb then i = i + 1
            elseif lb > la then j = j + 1
            else i, j = i + 1, j + 1 end
        end
    end
    return true
end

-- The word with its hidden letters as "_" (revealed: set of positions shown).
function W.Mask(word, revealed)
    local out = {}
    for i = 1, string.len(word) do
        local ch = string.sub(word, i, i)
        if string.find(ch, "%w") and not (revealed and revealed[i]) then ch = "_" end
        table.insert(out, ch)
    end
    return table.concat(out)
end

-- How a mask is shown: "_ _ a _   _ _" (letters spaced, gaps between words wider).
function W.ShowMask(mask)
    local out = {}
    for i = 1, string.len(mask or "") do
        local ch = string.sub(mask, i, i)
        table.insert(out, ch == " " and " " or ch)
    end
    return table.concat(out, " ")
end

function W.Hidden(mask)
    local n = 0
    for i = 1, string.len(mask or "") do if string.sub(mask, i, i) == "_" then n = n + 1 end end
    return n
end

-- A light disguise for the word sent to the artist: the 1.12 client has no
-- private addon messages, so it goes to the whole group. This only keeps it
-- from showing in plain text; it isn't secret from a determined peek.
local HEX = "0123456789abcdef"
local function KeyAt(key, i) return string.byte(key, ns.Mod(i - 1, string.len(key)) + 1) end
function W.Hide(word, key)
    local out = {}
    for i = 1, string.len(word) do
        local v = ns.Mod(string.byte(word, i) + KeyAt(key, i) + i * 7, 256)
        table.insert(out, string.sub(HEX, math.floor(v / 16) + 1, math.floor(v / 16) + 1))
        table.insert(out, string.sub(HEX, ns.Mod(v, 16) + 1, ns.Mod(v, 16) + 1))
    end
    return table.concat(out)
end

function W.Reveal(code, key)
    local out = {}
    for i = 1, math.floor(string.len(code or "") / 2) do
        local hi = string.find(HEX, string.sub(code, i * 2 - 1, i * 2 - 1), 1, true)
        local lo = string.find(HEX, string.sub(code, i * 2, i * 2), 1, true)
        if not hi or not lo then return nil end
        local v = ns.Mod((hi - 1) * 16 + (lo - 1) - KeyAt(key, i) - i * 7, 256)
        table.insert(out, string.char(v))
    end
    return table.concat(out)
end

-- Like Pool, with each word's pack name as a hint: { word = , hint = }.
function W.PoolHints(packs, customText)
    local out = {}
    for i = 1, string.len(packs or "") do
        local p = W.Pack(string.sub(packs, i, i))
        if p then for _, w in ipairs(p.words) do table.insert(out, { word = w, hint = p.name }) end end
    end
    if customText then
        for _, w in ipairs(W.ParseCustom(customText)) do table.insert(out, { word = w, hint = "the host's own words" }) end
    end
    return out
end

---------------------------------------------------------------------------
-- A word picker any game can show: a check box per pack, "My own words" and
-- a box to type them in, and a count. 250 wide.
--   spec: get() -> the settings table ({ packs = "ec", custom = true/false }),
--         text() / setText(t) for the typed words, onChange(), own (label,
--         default "My own words").
-- Returns a frame with :Refresh(editable) and .height.
---------------------------------------------------------------------------
function W.NewPicker(parent, spec)
    local f = ns.CreateFrame("Frame", nil, parent)
    f:SetWidth(250)
    local function Label(x, y, text, font)
        local t = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        t:SetJustifyH("LEFT")
        t:SetText(text or "")
        return t
    end
    local function Check(x, y, text, onClick)
        local c = ns.CreateFrame("CheckButton", ns:NewName(), f, "UICheckButtonTemplate")
        c:SetWidth(22); c:SetHeight(22)
        c:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        c:SetScript("OnClick", function() onClick() end)
        c.label = Label(x + 24, y - 5, text)
        return c
    end
    local function Changed()
        ns:Sound("IG_MAINMENU_OPTION")
        if spec.onChange then spec.onChange() end
        f:Refresh(true)
    end
    f.checks = {}
    for i, p in ipairs(W.PACKS) do
        local key = p.key
        local c = Check(ns.Mod(i - 1, 2) * 124, -math.floor((i - 1) / 2) * 22, p.name, function()
            local s = spec.get()
            local packs = s.packs or ""
            local at = string.find(packs, key, 1, true)
            if at then packs = string.sub(packs, 1, at - 1) .. string.sub(packs, at + 1) else packs = packs .. key end
            s.packs = packs
            Changed()
        end)
        c.key = key
        table.insert(f.checks, c)
    end
    local n = ns.getn(W.PACKS)
    f.own = Check(ns.Mod(n, 2) * 124, -math.floor(n / 2) * 22, spec.own or "My own words", function()
        local s = spec.get()
        s.custom = not s.custom
        Changed()
    end)
    local y = -math.floor(n / 2 + 1) * 22
    local box = ns.CreateFrame("EditBox", nil, f)
    box:SetWidth(246); box:SetHeight(22)
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y - 2)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(2000)
    box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.8)
    box:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", box, "LEFT", 7, 0)
    hint:SetText("Your words, separated by commas")
    local focused = false
    box:SetScript("OnEditFocusGained", function() focused = true hint:Hide() end)
    box:SetScript("OnEditFocusLost", function() focused = false ns.SetShown(hint, (box:GetText() or "") == "") end)
    box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    box:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    box:SetScript("OnTextChanged", function()
        if f.filling then return end
        spec.setText(box:GetText() or "")
        ns.SetShown(hint, (box:GetText() or "") == "" and not focused)
        f:Refresh(true)
    end)
    f.box, f.hint = box, hint
    f.count = Label(4, y - 26, "", "GameFontDisableSmall")
    f.height = -(y - 40)
    f:SetHeight(f.height)
    f.filling = true
    box:SetText(spec.text() or "")
    f.filling = nil
    ns.SetShown(hint, (spec.text() or "") == "")

    function f:Refresh(editable)
        local s = spec.get()
        for _, c in ipairs(self.checks) do
            c:SetChecked(string.find(s.packs or "", c.key, 1, true) ~= nil)
            ns.SetEnabled(c, editable)
        end
        self.own:SetChecked(s.custom and true or nil)
        ns.SetEnabled(self.own, editable)
        ns.SetShown(self.box, editable and s.custom)
        self.count:SetText((editable and s.custom) and (ns.getn(W.ParseCustom(spec.text())) .. " of your own words") or "")
    end
    return f
end
