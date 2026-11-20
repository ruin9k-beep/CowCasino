-- CowCasino: compatibility layer for the 1.12 client (Octo / Turtle WoW)
-- The game code is shared with WoW Forever. It calls the few functions that
-- differ between the clients through ns (ns.CreateFrame, ns.PlaySound, ...).
-- On 1.12 these are the client's own functions; CompatModern.lua provides
-- them on WoW Forever. Only one of the two is loaded: CowCasino.toc lists
-- this file, CowCasino_Mainline.toc lists the other.

CowCasino = CowCasino or {}
CowCasino.ns = CowCasino.ns or {}
local ns = CowCasino.ns

ns.FLAVOR = "1.12"

-- Each one looks up the client function when called, so the shared code
-- always uses whatever the game provides at that moment.
function ns.getn(t) return table.getn(t) end
function ns.mod(a, b) return math.mod(a, b) end
function ns.getglobal(name) return getglobal(name) end
function ns.CreateFrame(kind, name, parent, template) return CreateFrame(kind, name, parent, template) end
function ns.PlaySound(name) return PlaySound(name) end
function ns.NumParty() return GetNumPartyMembers() end
function ns.AddonVersion() return GetAddOnMetadata("CowCasino", "Version") or "?" end
function ns.NumRaid() return GetNumRaidMembers() end

-- The 1.12 client sends everything it is given (it never refuses).
function ns.SendAddonMessage(prefix, text, channel)
    SendAddonMessage(prefix, text, channel)
    return true
end

ns.QUESTION_MARK_MODEL = "Interface\\Buttons\\talktomequestionmark.mdx"

-- A portrait's close-up on the face: the model's face camera.
function ns.FaceCamera(model) model:SetCamera(0) end

-- A creature's 3D model on 1.12: an addon can't skin a model it loads by
-- file, but it can copy a unit it can point at. So when the creature is out
-- nearby (spec.name), it's found the way rare scanners do: TargetByName, copy
-- it while it's the target, then put the old target back, all in one go. When
-- it isn't found the target never changes. Never in combat.
function ns.CanShowCreature(spec) return spec and spec.name and true or false end

local function IsNamed(unit, name)
    return UnitExists(unit) and string.lower(UnitName(unit) or "") == string.lower(name)
end

-- true: the creature is on the model now; false: not nearby (or in combat).
function ns.LoadCreature(m, spec)
    local name = spec.name
    for _, unit in ipairs({ "target", "mouseover" }) do
        if IsNamed(unit, name) then
            m:SetUnit(unit)
            m:SetCamera(0)
            return true
        end
    end
    if UnitAffectingCombat("player") then return false end
    local had = UnitExists("target")
    TargetByName(name, true)
    if not IsNamed("target", name) then return false end
    m:SetUnit("target")
    m:SetCamera(0)
    if had then TargetLastTarget() else ClearTarget() end
    return true
end
function ns.CreatureModelLoaded(m) return true end

-- Bags and the spellbook (for the hidden dealers).
function ns.BagSlots(bag) return GetContainerNumSlots(bag) or 0 end
function ns.BagLink(bag, slot) return GetContainerItemLink(bag, slot) end
function ns.SpellNameAt(i) return GetSpellName(i, "spell") end
