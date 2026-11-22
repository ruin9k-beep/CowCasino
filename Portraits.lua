-- CowCasino: player portraits
-- A 3D head-and-shoulders model of a player, for seats at the card tables.
--   local p = ns:CreatePortrait(parent, width, height, facing)
--   p:ShowUnit("party2")    -- or nil to hide it
--   p:ShowCreature(spec)    -- a creature's model (a dealer's: pack.model or
--                           -- pack.portrait), where the client can show it;
--                           -- p.onCreature(up) says when it's up (or isn't)
-- facing (optional, radians) turns the model: positive to the viewer's
-- right, negative to the left (two portraits can face each other).
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
local SCAN_EVERY = 3    -- seconds between tries at a creature that isn't there yet
local WAIT = 1.5        -- seconds for a creature's model to load before giving up on it
local portraits = {}

-- the face close-up, turned the portrait's way
local function Frame(m)
    ns.FaceCamera(m)
    if m.facing then m:SetFacing(m.facing) end
end

local function Apply(m)
    if m.inRange then
        m:SetModelScale(1)
        m:SetPosition(0, 0, 0)
        m:SetUnit(m.unitId)
        Frame(m)
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
    m.creature, m.cstate = nil, nil
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

---------------------------------------------------------------------------
-- A creature (ns.LoadCreature, Compat*.lua): the modern client by npc id,
-- 1.12 by copying it when it's out nearby. Hidden until its model is up.
---------------------------------------------------------------------------
local function CreatureUp(m)
    m.cstate = "shown"
    m:Show()
    Frame(m)
    m.settle = SETTLE
    if m.onCreature then m.onCreature(true) end
end

local function CreatureTick(m)
    local now = GetTime()
    if m.cstate == "try" then
        if now < (m.cnext or 0) then return end
        local r = ns.LoadCreature(m, m.creature)
        if r == true then
            CreatureUp(m)
        elseif r == "wait" then
            m.cstate, m.cnext = "wait", now + WAIT
            m:Show()        -- (empty until it loads)
        else
            m.cnext = now + SCAN_EVERY
        end
    elseif m.cstate == "wait" and now >= (m.cnext or 0) then
        if ns.CreatureModelLoaded(m) then
            CreatureUp(m)
        else
            m.cstate = "picture"    -- this client can't show it
            m:Hide()
            if m.onCreature then m.onCreature(false) end
        end
    end
end

local function ShowCreature(m, spec)
    if not (spec and ns.CanShowCreature(spec)) then
        ShowUnit(m, nil)
        if m.onCreature then m.onCreature(false) end
        return
    end
    if m.creature == spec then return end
    m.unitId, m.inRange = nil, nil
    m.creature, m.cstate, m.cnext = spec, "try", 0
    m:Hide()
    if m.onCreature then m.onCreature(false) end
    if m:GetParent():IsVisible() then CreatureTick(m) end
end

function ns:CreatePortrait(parent, width, height, facing)
    local m = ns.CreateFrame("PlayerModel", nil, parent)
    m:SetWidth(width); m:SetHeight(height)
    m.facing = facing
    m:SetFrameLevel(parent:GetFrameLevel() + 2)
    -- models forget their unit and camera while hidden
    m:SetScript("OnShow", function()
        if this.unitId then Apply(this)
        elseif this.cstate == "shown" then this.cstate, this.cnext = "try", 0 end
    end)
    -- keep the face camera on while the model finishes loading
    m:SetScript("OnUpdate", function()
        if not this.settle then return end
        this.settle = this.settle - (arg1 or 0)
        if this.inRange or this.cstate == "shown" then Frame(this) end
        if this.settle <= 0 then this.settle = nil end
    end)
    m:Hide()
    m.ShowUnit = ShowUnit
    m.ShowCreature = ShowCreature
    table.insert(portraits, m)
    return m
end

-- Players walk in and out of range: recheck the portraits on screen.
ns:Every(2, function()
    for _, m in ipairs(portraits) do
        if m.creature and m.cstate ~= "shown" and m.cstate ~= "picture" and m:GetParent():IsVisible() then
            CreatureTick(m)
        elseif m.unitId and m:IsVisible() then
            ShowUnit(m, m.unitId)
            if m.inRange then Frame(m) end   -- in case the game reset it
        end
    end
end)
