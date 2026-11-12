-- CowCasino: game sound effects
-- Card games play a sound when you win a hand, lose a hand, and when a new
-- hand starts. Each game keeps its own choices (db.sounds) and shows them in
-- its Options with ns:CreateSoundOptions.
--
-- Every sound below is a name the 1.12 client knows: they're used by the
-- game's own 1.12.1 interface code or by popular 1.12 addons. WoW Forever
-- plays the matching sound kit (CompatModern.lua). The louder, easy-to-tell-
-- apart ones come first; the quiet book and menu sounds are at the end.

local ns = CowCasino.ns

ns.SOUND_CHOICES = {
    { id = "none",       name = "None" },
    { id = "coins",      name = "Coins",            sound = "LOOTWINDOWCOINSOUND" },
    { id = "fanfare",    name = "Level-up fanfare", sound = "LEVELUPSOUND" },
    { id = "questDone",  name = "Quest complete",   sound = "igQuestListComplete" },
    { id = "questDrop",  name = "Quest abandoned",  sound = "igQuestCancel" },
    { id = "questFail",  name = "Quest failed",     sound = "igQuestFailed" },
    { id = "mapPing",    name = "Map ping",         sound = "MapPing" },
    { id = "whisper",    name = "Whisper",          sound = "TellMessage" },
    { id = "invite",     name = "Party invite",     sound = "igPlayerInvite" },
    { id = "bgReady",    name = "Battle horn",      sound = "PVPTHROUGHQUEUE" },
    { id = "bgQueue",    name = "Battleground queue", sound = "PVPENTERQUEUE" },
    { id = "auctionOpen", name = "Auction bell",    sound = "AuctionWindowOpen" },
    { id = "auctionClose", name = "Auction close",  sound = "AuctionWindowClose" },
    { id = "aggro",      name = "Hostile target",   sound = "igCreatureAggroSelect" },
    { id = "targetLost", name = "Target lost",      sound = "INTERFACESOUND_LOSTTARGETUNIT" },
    { id = "talents",    name = "Talents open",     sound = "TalentScreenOpen" },
    { id = "spellbook",  name = "Spellbook open",   sound = "igSpellBookOpen" },
    { id = "tab",        name = "Tab click",        sound = "igCharacterInfoTab" },
    { id = "pageTurn",   name = "Page turn",        sound = "igQuestListOpen" },
    { id = "bookClose",  name = "Book close",       sound = "igQuestListClose" },
    { id = "select",     name = "Select",           sound = "igQuestListSelect" },
    { id = "quill",      name = "Quill",            sound = "WriteQuest" },
    { id = "raidWarn",   name = "Raid warning",     sound = "RaidWarning" },
    { id = "click",      name = "Click",            sound = "igMainMenuOption" },
    { id = "tick",       name = "Tick",             sound = "igMainMenuOptionCheckBoxOn" },
    { id = "menuOpen",   name = "Menu open",        sound = "igMainMenuOpen" },
    { id = "menuClose",  name = "Menu close",       sound = "igMainMenuClose" },
    { id = "bag",        name = "Bag button",       sound = "BAGMENUBUTTONPRESS" },
}

ns.SOUND_EVENTS = {
    { key = "win",     label = "You win a hand" },
    { key = "lose",    label = "You lose a hand" },
    { key = "newHand", label = "A new hand starts" },
}

local DEFAULTS = { win = "coins", lose = "questDrop", newHand = "mapPing" }

local function Choice(id)
    for i, c in ipairs(ns.SOUND_CHOICES) do
        if c.id == id then return c, i end
    end
    return nil
end

-- Fill in a game's sound settings (and drop any choice that no longer exists).
-- extra: a game's own moments beyond the three above, { { key, label, default } }.
function ns:InitSounds(db, extra)
    db.sounds = db.sounds or {}
    for key, id in pairs(DEFAULTS) do
        if not Choice(db.sounds[key]) then db.sounds[key] = id end
    end
    for _, ev in ipairs(extra or {}) do
        if not Choice(db.sounds[ev.key]) then db.sounds[ev.key] = ev.default end
    end
end

function ns:PlayGameSound(db, event)
    local c = db and db.sounds and Choice(db.sounds[event])
    if c and c.sound then ns.PlaySound(c.sound) end
end

-- A full-panel overlay: one row per event, each with < name > and Play.
-- getDb returns the game's saved table (with .sounds); extra adds a game's
-- own moments (as for InitSounds).
function ns:CreateSoundOptions(panel, title, getDb, extra)
    local o = ns.CreateFrame("Frame", nil, panel)
    o:SetAllPoints(panel)
    o:SetFrameLevel(panel:GetFrameLevel() + 80)
    o:EnableMouse(true)
    o:Hide()
    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0, 0, 0, 0.95)

    local head = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOP", o, "TOP", 0, -10)
    head:SetText(title)
    local sub = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOP", head, "BOTTOM", 0, -4)
    sub:SetText("Sound effects")

    local events = {}
    for _, ev in ipairs(ns.SOUND_EVENTS) do table.insert(events, ev) end
    for _, ev in ipairs(extra or {}) do table.insert(events, ev) end
    local rows = {}
    for i, ev in ipairs(events) do
        local i, ev = i, ev   -- own copies for closures (Lua 5.0)
        local y = -60 - (i - 1) * 56
        local label = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", o, "TOPLEFT", 16, y)
        label:SetText(ev.label)

        local value = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        local function Step(dir)
            local db = getDb()
            local _, idx = Choice(db.sounds[ev.key])
            idx = ns.Mod((idx or 1) - 1 + dir, ns.getn(ns.SOUND_CHOICES)) + 1
            db.sounds[ev.key] = ns.SOUND_CHOICES[idx].id
            ns:PlayGameSound(db, ev.key)     -- hear it as you pick it
            o:Refresh()
        end
        local prev = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
        prev:SetWidth(26); prev:SetHeight(22)
        prev:SetText("<")
        prev:SetPoint("TOPLEFT", o, "TOPLEFT", 24, y - 18)
        prev:SetScript("OnClick", function() Step(-1) end)
        value:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        value:SetWidth(130)
        value:SetJustifyH("CENTER")
        local nextB = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
        nextB:SetWidth(26); nextB:SetHeight(22)
        nextB:SetText(">")
        nextB:SetPoint("LEFT", value, "RIGHT", 6, 0)
        nextB:SetScript("OnClick", function() Step(1) end)
        local play = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
        play:SetWidth(60); play:SetHeight(22)
        play:SetText("Play")
        play:SetPoint("LEFT", nextB, "RIGHT", 10, 0)
        play:SetScript("OnClick", function() ns:PlayGameSound(getDb(), ev.key) end)
        rows[i] = { key = ev.key, value = value, play = play }
    end

    local reset = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    reset:SetWidth(110); reset:SetHeight(22)
    reset:SetText("Defaults")
    reset:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", 16, 14)
    reset:SetScript("OnClick", function()
        getDb().sounds = nil
        ns:InitSounds(getDb(), extra)
        o:Refresh()
    end)
    local done = ns.CreateFrame("Button", ns:NewName(), o, "UIPanelButtonTemplate")
    done:SetWidth(90); done:SetHeight(22)
    done:SetText("Done")
    done:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -16, 14)
    done:SetScript("OnClick", function() o:Hide() end)

    function o:Refresh()
        local db = getDb()
        for _, r in ipairs(rows) do
            local c = Choice(db.sounds[r.key])
            r.value:SetText(c and c.name or "None")
            ns.SetEnabled(r.play, c ~= nil and c.sound ~= nil)
        end
    end
    o:SetScript("OnShow", function() this:Refresh() end)
    return o
end
