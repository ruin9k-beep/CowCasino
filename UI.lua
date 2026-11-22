-- CowCasino: building blocks the games share, so they look and behave the
-- same and a change to one (a new stats line, say) is made once:
--   UI.Button(parent, text, width, onClick, height)  a standard button
--   UI.Fill(t, defaults)                fill in missing saved values
--   UI.Net(n)                           a colored +N / -N / 0 for stats lines
--   UI.History(parent)                  the last few games' net, newest first
--   UI.Options(panel, spec)             the Options overlay: title, how it
--                                       plays, Reset stats, Sounds and Done
--   UI.Stepper(parent, spec)            a "< label >" picker over a list

local ns = CowCasino.ns
local UI = {}
ns.UI = UI

local function Fmt(n) return ns:FormatChips(n) end

-- A standard panel button. onClick gets (button, mouse button).
function UI.Button(parent, text, width, onClick, height)
    local b = ns.CreateFrame("Button", ns:NewName(), parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(height or 22)
    b:SetText(text)
    b:SetScript("OnClick", function() onClick(this, arg1) end)
    return b
end

-- Fill in any saved values that are missing (new settings, new stats).
function UI.Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
    return t
end

-- A net amount in color for a stats line: green +N, red -N, gray 0. The
-- caller closes the color with |r.
function UI.Net(n)
    n = n or 0
    if n > 0 then return "|cff40ff40+" .. Fmt(n) end
    if n < 0 then return "|cffff5050-" .. Fmt(-n) end
    return "|cffcccccc0"
end

---------------------------------------------------------------------------
-- The last few games along one line, newest on the left: what each one won
-- or lost after its bet. It lasts for the session (like Plinko's), and
-- clears with the game's stats.
--   local h = UI.History(panel, list); h:SetPoint(...)
--   UI.AddHistory(list, net)   after each game (works before the screen is built)
--   h:Update()   to redraw it;   UI.ClearHistory(list)   when the stats reset
---------------------------------------------------------------------------
local HISTORY_SHOWN, HISTORY_KEPT = 6, 12

function UI.AddHistory(list, n)
    table.insert(list, 1, n)
    if ns.getn(list) > HISTORY_KEPT then table.remove(list) end
end

function UI.ClearHistory(list)
    for i = ns.getn(list), 1, -1 do table.remove(list, i) end
end

function UI.History(parent, list)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.list = list or {}
    function h:Text()
        local parts = {}
        for i = 1, math.min(HISTORY_SHOWN, ns.getn(self.list)) do
            local n = self.list[i]
            local text = (n > 0 and ("|cff40ff40+" .. Fmt(n))) or (n < 0 and ("|cffff7070-" .. Fmt(-n))) or "|cffaaaaaa0"
            table.insert(parts, text .. "|r")
        end
        return table.concat(parts, "  ")
    end
    function h:Update() self:SetText(self:Text()) end
    function h:Add(n)
        UI.AddHistory(self.list, n)
        self:Update()
    end
    function h:Clear()
        UI.ClearHistory(self.list)
        self:Update()
    end
    return h
end

---------------------------------------------------------------------------
-- Tabs along the bottom of a page, the way WoW's own windows have them.
-- names: the tab labels, in order. Returns tabs with:
--   tabs.frames[i]   tab i's content (it fills the page; anchor to the page)
--   tabs.buttons[i]  its button
--   tabs:Select(i)   shows tab i (onSelect(i) runs after)
-- The first tab starts selected. A single tab draws no buttons.
---------------------------------------------------------------------------
local TAB_W, TAB_GAP = 84, 4

function UI.Tabs(page, names, y, onSelect)
    local tabs = { frames = {}, buttons = {}, marks = {}, current = 1 }
    local n = ns.getn(names)
    local bar = ns.CreateFrame("Frame", nil, page)
    bar:SetWidth(n * TAB_W + (n - 1) * TAB_GAP); bar:SetHeight(24)
    bar:SetPoint("BOTTOM", page, "BOTTOM", 0, y or 8)
    ns.SetShown(bar, n > 1)
    tabs.bar = bar
    function tabs:Select(i)
        self.current = i
        for k = 1, n do
            ns.SetShown(self.frames[k], k == i)
            ns.SetShown(self.marks[k], k == i)
        end
        if onSelect then onSelect(i) end
    end
    for i = 1, n do
        local i = i   -- own copy for closures (Lua 5.0)
        local f = ns.CreateFrame("Frame", nil, page)
        f:SetAllPoints(page)
        tabs.frames[i] = f
        local b = UI.Button(bar, names[i], TAB_W, function()
            if tabs.current ~= i then ns:Sound("IG_MAINMENU_OPTION") end
            tabs:Select(i)
        end)
        b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (TAB_W + TAB_GAP), 0)
        tabs.buttons[i] = b
        -- the selected tab's gold underline
        local mark = bar:CreateTexture(nil, "OVERLAY")
        mark:SetHeight(2); mark:SetWidth(TAB_W - 12)
        mark:SetPoint("TOP", b, "BOTTOM", 0, 1)
        mark:SetTexture(1, 0.82, 0, 0.9)
        tabs.marks[i] = mark
    end
    tabs:Select(1)
    return tabs
end

---------------------------------------------------------------------------
-- The Options overlay, in tabs. spec:
--   title      "Keno Options"
--   note       a small line under the title, on every tab (optional)
--   settings   true for a Settings tab (o.settings): the game's own controls
--   rules      how the game plays: a Rules tab
--   sounds     true for a Sounds tab (o.soundsTab)
--   onReset    resets the stats (after a second click within 3 seconds)
--   onRefresh  called whenever the overlay is shown (for extra settings)
--   canReset   function -> false while Reset stats can't be used (optional)
-- Every tab fills the page, so controls anchor to the page itself (o) and
-- are parented to their tab. Reset stats and Done sit above the tabs.
-- o:Refresh() updates the page; Reset stats asks "Sure?" first.
-- Games don't call this directly: ns:GameOptions (below) builds their
-- Options and hooks it up to the window's Options button.
---------------------------------------------------------------------------
function UI.Options(panel, spec)
    local o = ns.CreateFrame("Frame", nil, panel)
    o:SetAllPoints(panel)
    o:SetFrameLevel(panel:GetFrameLevel() + 50)
    o:EnableMouse(true)
    o:Hide()
    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0, 0, 0, 0.94)
    local title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", o, "TOP", 0, -10)
    title:SetText(spec.title or "Options")
    o.title = title
    if spec.note then
        local note = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOP", title, "BOTTOM", 0, -2)
        note:SetWidth(330)      -- (one line: the tabs' content starts just below it)
        note:SetText(spec.note)
        o.note = note
    end

    local names, keys = {}, {}
    if spec.settings then table.insert(names, "Settings"); table.insert(keys, "settings") end
    if spec.rules then table.insert(names, "Rules"); table.insert(keys, "rulesTab") end
    if spec.sounds then table.insert(names, "Sounds"); table.insert(keys, "soundsTab") end
    if ns.getn(names) > 0 then
        o.tabs = UI.Tabs(o, names, 8, function(i)
            local f = o.tabs and o.tabs.frames[i]
            if f and rawget(f, "Refresh") then f:Refresh() end
        end)
        for i, key in ipairs(keys) do o[key] = o.tabs.frames[i] end
    end

    if spec.rules then
        local rules = o.rulesTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rules:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -(spec.note and 52 or 40))
        rules:SetWidth(320)
        rules:SetJustifyH("LEFT")
        rules:SetText(spec.rules)
        o.rules = rules
    end

    local reset
    reset = UI.Button(o, "Reset stats", 110, function()
        if reset.armed and GetTime() - reset.armed <= 3 then
            reset.armed = nil
            reset:SetText("Reset stats")
            if spec.onReset then spec.onReset() end
            return
        end
        reset.armed = GetTime()
        reset:SetText("Sure? Click again")
    end)
    reset:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", 16, 40)
    o.reset = reset
    local done = UI.Button(o, "Done", 90, function() o:Hide() end)
    done:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -16, 40)

    function o:Refresh()
        if not (reset.armed and GetTime() - reset.armed <= 3) then
            reset.armed = nil
            reset:SetText("Reset stats")
        end
        if spec.canReset then ns.SetEnabled(reset, spec.canReset()) end
        if spec.onRefresh then spec.onRefresh(self) end
        local tab = self.tabs and self.tabs.frames[self.tabs.current]
        if tab and rawget(tab, "Refresh") then tab:Refresh() end
    end
    o:SetScript("OnShow", function() this:Refresh() end)
    return o
end

---------------------------------------------------------------------------
-- A "< label >" picker over a list of values. spec:
--   list       the values, in order
--   get / set  read and store the current value
--   label      function(value) -> the text between the arrows
--   width      the label's width (default 100)
--   locked     function() -> true while it can't be changed (a hand is on)
--   onChange   called after a change
-- Returns a frame (anchor it with SetPoint) with :Refresh(), .down and .up.
---------------------------------------------------------------------------
function UI.Stepper(parent, spec)
    local f = ns.CreateFrame("Frame", nil, parent)
    local width = spec.width or 100
    f:SetWidth(width + 2 * 26 + 4); f:SetHeight(24)
    local function Index()
        local cur = spec.get()
        for i, v in ipairs(spec.list) do if v == cur then return i end end
        return 1
    end
    local function Step(dir)
        if spec.locked and spec.locked() then return end
        local i = math.max(1, math.min(ns.getn(spec.list), Index() + dir))
        spec.set(spec.list[i])
        ns:Sound("IG_MAINMENU_OPTION")
        if spec.onChange then spec.onChange() end
        f:Refresh()
    end
    f.down = UI.Button(f, "<", 24, function() Step(-1) end)
    f.down:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("LEFT", f.down, "RIGHT", 2, 0)
    f.text:SetWidth(width)
    f.up = UI.Button(f, ">", 24, function() Step(1) end)
    f.up:SetPoint("LEFT", f.text, "RIGHT", 2, 0)
    function f:Refresh()
        local i = Index()
        local locked = spec.locked and spec.locked()
        self.text:SetText(spec.label(spec.list[i]))
        ns.SetEnabled(self.down, not locked and i > 1)
        ns.SetEnabled(self.up, not locked and i < ns.getn(spec.list))
    end
    return f
end

---------------------------------------------------------------------------
-- A game's Options. The window owns the one Options button (next to the
-- title, top right); each game fills in its own page by calling this from
-- its Build, and the button opens whichever game is showing. spec:
--   rules, note    as for UI.Options
--   settings       true when the game adds its own controls: they go on the
--                  Settings tab, o.settings (anchored to o)
--   build(o)       adds them (or the game adds them after this returns)
--   refresh(o)     updates them whenever the page is shown
--   db()           the game's saved table: gives the page a Sounds tab
--   sounds         extra sounds for that page (see ns:CreateSoundOptions)
--   onReset        what Reset stats does (default: the game's ResetStats)
--   canReset()     false while Reset stats can't be used
-- Returns the page. A game that doesn't call this still gets a plain page
-- (Reset stats, Done).
---------------------------------------------------------------------------
function ns:GameOptions(game, panel, spec)
    spec = spec or {}
    local title = (game.name or "Game") .. " Options"
    local o = UI.Options(panel, {
        title = title, note = spec.note, rules = spec.rules,
        settings = spec.settings, sounds = spec.db ~= nil,
        onReset = spec.onReset or function() if game.ResetStats then game:ResetStats() end end,
        canReset = spec.canReset,
        onRefresh = spec.refresh,
    })
    if spec.db then ns:CreateSoundOptions(o.soundsTab, spec.db, spec.sounds) end
    if spec.build then spec.build(o) end
    game.options = o
    return o
end

---------------------------------------------------------------------------
-- The start of every game's Build: its saved table, with any missing
-- settings and stats filled in, its sounds, and the felt behind it.
--   db = ns:SetupGame(panel, "keno", {
--       defaults = { bet = 10 },        -- settings, filled in where missing
--       stats = DEFAULT_STATS,          -- db.stats, filled in where missing
--       sounds = true,                  -- or a list of the game's extra sounds
--       felt = { r, g, b, a },          -- the table color behind everything
--   })
---------------------------------------------------------------------------
function ns:SetupGame(panel, key, spec)
    ns.db[key] = ns.db[key] or {}
    local db = ns.db[key]
    if spec.defaults then UI.Fill(db, spec.defaults) end
    if spec.stats then
        db.stats = db.stats or {}
        UI.Fill(db.stats, spec.stats)
    end
    if spec.sounds then ns:InitSounds(db, spec.sounds ~= true and spec.sounds or nil) end
    if spec.felt then
        local c = spec.felt
        local felt = panel:CreateTexture(nil, "BACKGROUND")
        felt:SetAllPoints(panel)
        felt:SetTexture(c[1], c[2], c[3], c[4] or 1)
    end
    return db
end

