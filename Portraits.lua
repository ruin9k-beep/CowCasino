-- CowCasino: player portraits
-- A 3D head-and-shoulders model of a player, for seats at the card tables.
--   local p = ns:CreatePortrait(parent, width, height)
--   p:ShowUnit("party2")    -- or nil to hide it
-- The game only has a model for players near you; anyone out of range (or
-- offline) gets a floating question mark until they're close enough. Every
-- portrait rechecks that every two seconds.
--
-- The close-up on the face comes from ns.FaceCamera (Compat112.lua: the
-- model's face camera, camera 0; CompatModern.lua: the modern client's
-- portrait zoom, since its face camera only frames some models). The game
-- loads a player's model a moment after it's asked for, and framing set
-- before then is lost (leaving the full body), so it's set again every
-- frame for a moment after the model is chosen, and again at every
-- two-second recheck.

local ns = CowCasino.ns

local QUESTION_MARK = ns.QUESTION_MARK_MODEL
local SETTLE = 1.5      -- seconds to keep setting the face camera after choosing a model
local portraits = {}

local function Apply(m)
    if m.inRange then
        m:SetModelScale(1)
        m:SetPosition(0, 0, 0)
        m:SetUnit(m.unitId)
        ns.FaceCamera(m)
        m.settle = SETTLE
    else
        m.settle = nil
        m:ClearModel()
        m:SetModelScale(4.25)
        m:SetPosition(0, 0, -1)
        m:SetModel(QUESTION_MARK)
    end
end

local function ShowUnit(m, unit, force)
    if not unit then
        m.unitId = nil
        m:Hide()
        return
    end
    local inRange = (UnitIsVisible(unit) and UnitIsConnected(unit)) and true or false
    if not force and m.unitId == unit and m.inRange == inRange and m:IsShown() then return end
    m.unitId, m.inRange = unit, inRange
    m:Show()
    Apply(m)
end

function ns:CreatePortrait(parent, width, height)
    local m = ns.CreateFrame("PlayerModel", nil, parent)
    m:SetWidth(width); m:SetHeight(height)
    m:SetFrameLevel(parent:GetFrameLevel() + 2)
    -- models forget their unit and camera while hidden
    m:SetScript("OnShow", function() if this.unitId then Apply(this) end end)
    -- keep the face camera on while the model finishes loading
    m:SetScript("OnUpdate", function()
        if not this.settle then return end
        this.settle = this.settle - (arg1 or 0)
        if this.inRange then ns.FaceCamera(this) end
        if this.settle <= 0 then this.settle = nil end
    end)
    m:Hide()
    m.ShowUnit = ShowUnit
    table.insert(portraits, m)
    return m
end

-- Players walk in and out of range: recheck the portraits on screen.
local ticker = ns.CreateFrame("Frame")
local wait = 0
ticker:SetScript("OnUpdate", function()
    wait = wait + (arg1 or 0)
    if wait < 2 then return end
    wait = 0
    for _, m in ipairs(portraits) do
        if m.unitId and m:IsVisible() then
            ShowUnit(m, m.unitId)
            if m.inRange then ns.FaceCamera(m) end   -- in case the game reset it
        end
    end
end)
