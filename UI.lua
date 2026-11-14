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
-- The Options overlay. spec:
--   title      "Keno Options"
--   rules      how the game plays (shown at the top)
--   rulesTop   where the rules start (default 40 from the top)
--   onReset    resets the stats (after a second click within 3 seconds)
--   sounds     function returning the game's sound options frame
--   onRefresh  called whenever the overlay is shown (for extra settings)
-- Returns the overlay; o.body is where extra settings can go, and o:Refresh()
-- updates it. Reset stats asks "Sure?" first.
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
    o.body = o

    if spec.rules then
        local rules = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rules:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -(spec.rulesTop or 40))
        rules:SetPoint("RIGHT", o, "RIGHT", -16, 0)
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
    if spec.sounds then
        local sounds = UI.Button(o, "Sounds", 80, function() spec.sounds():Show() end)
        sounds:SetPoint("BOTTOM", o, "BOTTOM", 0, 40)
    end
    local done = UI.Button(o, "Done", 90, function() o:Hide() end)
    done:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -16, 40)

    function o:Refresh()
        if not (reset.armed and GetTime() - reset.armed <= 3) then
            reset.armed = nil
            reset:SetText("Reset stats")
        end
        if spec.onRefresh then spec.onRefresh(self) end
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
