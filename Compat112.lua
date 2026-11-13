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
