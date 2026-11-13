-- CowCasino: compatibility layer for WoW Forever (the modern client)
-- The game code is shared with the 1.12 client and calls the few functions
-- that differ through ns (see Compat112.lua). This file, listed only in
-- CowCasino_Mainline.toc, provides them on the modern client:
--   * frames made through ns.CreateFrame get 1.12-style script handlers
--     (this, event and arg1..arg5 are set while a handler runs), color
--     textures (SetTexture(r, g, b, a)), backdrops and font flags
--   * 1.12 sound names are played through the modern sound kit IDs
--   * group size, addon messages and the 1.12 roster events map to their
--     modern equivalents; senders arrive without their realm, like on 1.12
--   * addon messages are spread over a pool of prefixes to stay within the
--     modern client's per-prefix limit

CowCasino = CowCasino or {}
CowCasino.ns = CowCasino.ns or {}
local ns = CowCasino.ns

ns.FLAVOR = "WoW Forever"

---------------------------------------------------------------------------
-- Lua library pieces 1.12 code expects
---------------------------------------------------------------------------
function ns.getn(t) return #t end
function ns.mod(a, b) return math.fmod(a, b) end
function ns.getglobal(name) return _G[name] end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local EVENT_MAP = {
    PARTY_MEMBERS_CHANGED = "GROUP_ROSTER_UPDATE",
    RAID_ROSTER_UPDATE    = "GROUP_ROSTER_UPDATE",
}

-- Run a 1.12-style handler (which reads this / event / arg1..) from a modern
-- one (which receives self, ...).
local function Wrap(script, f)
    if type(f) ~= "function" then return f end
    if script == "OnEvent" then
        return function(self, ev, ...)
            local pt, pe, p1, p2, p3, p4, p5 = this, event, arg1, arg2, arg3, arg4, arg5
            this, event = self, ev
            arg1, arg2, arg3, arg4, arg5 = ...
            if ev == "CHAT_MSG_ADDON" then
                -- The sender as the group knows them: WoW Forever sends
                -- "Rohk Proudhorn-Realm" while UnitName gives "Rohk", so drop
                -- the realm and anything after the first name.
                if arg4 then
                    arg4 = Ambiguate(arg4, "short")
                    arg4 = string.match(arg4, "^[^%s]+") or arg4
                end
                if ns.PREFIX_POOL and ns.PREFIX_POOL[arg1] then arg1 = "CowCasino" end
            end
            f()
            this, event, arg1, arg2, arg3, arg4, arg5 = pt, pe, p1, p2, p3, p4, p5
        end
    end
    return function(self, ...)
        local pt, p1, p2, p3, p4, p5 = this, arg1, arg2, arg3, arg4, arg5
        this = self
        arg1, arg2, arg3, arg4, arg5 = ...
        f()
        this, arg1, arg2, arg3, arg4, arg5 = pt, p1, p2, p3, p4, p5
    end
end

local function AdaptTexture(t)
    local setTexture = t.SetTexture
    t.SetTexture = function(self, a, g, b, alpha)
        if type(a) == "number" and type(g) == "number" then
            return self:SetColorTexture(a, g, b, alpha or 1)
        end
        return setTexture(self, a)
    end
    return t
end

local function AdaptFontString(fs)
    local setFont = fs.SetFont
    fs.SetFont = function(self, path, size, flags) return setFont(self, path, size, flags or "") end
    return fs
end

local function Adapt(f)
    local setScript = f.SetScript
    f.SetScript = function(self, script, handler) return setScript(self, script, Wrap(script, handler)) end
    if f.RegisterEvent then
        local register, unregister = f.RegisterEvent, f.UnregisterEvent
        f.RegisterEvent = function(self, ev) return register(self, EVENT_MAP[ev] or ev) end
        f.UnregisterEvent = function(self, ev) return unregister(self, EVENT_MAP[ev] or ev) end
    end
    if f.CreateTexture then
        local createTexture = f.CreateTexture
        f.CreateTexture = function(self, ...) return AdaptTexture(createTexture(self, ...)) end
    end
    if f.CreateFontString then
        local createFontString = f.CreateFontString
        f.CreateFontString = function(self, ...) return AdaptFontString(createFontString(self, ...)) end
    end
    return f
end

function ns.CreateFrame(kind, name, parent, template)
    -- Plain frames, buttons and edit boxes may get a backdrop (the window,
    -- menu rows, the table chat and its typing box).
    if template == nil and (kind == "Frame" or kind == "Button" or kind == "EditBox") then template = "BackdropTemplate" end
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if not ok then
        if template ~= "OptionsSliderTemplate" then error(f, 2) end
        -- a client without the options slider: a plain slider plus its labels
        f = CreateFrame(kind, name, parent, "UISliderTemplate")
        for _, part in ipairs({ "Low", "High", "Text" }) do
            if name and not _G[name .. part] then
                _G[name .. part] = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            end
        end
    end
    return Adapt(f)
end

---------------------------------------------------------------------------
-- Sounds: 1.12 sound names -> modern sound kit IDs (first one that exists)
---------------------------------------------------------------------------
local SOUND_KITS = {
    igMainMenuOption           = { "IG_MAINMENU_OPTION" },
    igMainMenuOptionCheckBoxOn = { "IG_MAINMENU_OPTION_CHECKBOX_ON" },
    igCharacterInfoOpen        = { "IG_CHARACTER_INFO_OPEN" },
    igCharacterInfoClose       = { "IG_CHARACTER_INFO_CLOSE" },
    igMainMenuOpen             = { "IG_MAINMENU_OPEN" },
    igMainMenuClose            = { "IG_MAINMENU_CLOSE" },
    LOOTWINDOWCOINSOUND        = { "LOOT_WINDOW_COIN_SOUND" },
    LEVELUPSOUND               = { "UI_LEVEL_UP", "LEVEL_UP", 888 },
    igQuestListComplete        = { "IG_QUEST_LIST_COMPLETE" },
    igQuestCancel              = { "IG_QUEST_CANCEL" },
    igQuestListOpen            = { "IG_QUEST_LIST_OPEN" },
    igQuestListClose           = { "IG_QUEST_LIST_CLOSE" },
    igQuestListSelect          = { "IG_QUEST_LIST_SELECT" },
    WriteQuest                 = { "WRITE_QUEST" },
    RaidWarning                = { "RAID_WARNING" },
    BAGMENUBUTTONPRESS         = { "BAG_MENU_BUTTON_PRESS", "IG_BACKPACK_OPEN" },
    igQuestFailed              = { "IG_QUEST_FAILED", 847 },
    MapPing                    = { "MAP_PING", 3175 },
    TellMessage                = { "TELL_MESSAGE", 3081 },
    igPlayerInvite             = { "IG_PLAYER_INVITE", 880 },
    PVPTHROUGHQUEUE            = { "PVP_THROUGH_QUEUE", 8459 },
    PVPENTERQUEUE              = { "PVP_ENTER_QUEUE", 8458 },
    AuctionWindowOpen          = { "AUCTION_WINDOW_OPEN", 5274 },
    AuctionWindowClose         = { "AUCTION_WINDOW_CLOSE", 5275 },
    igCreatureAggroSelect      = { "IG_CREATURE_AGGRO_SELECT" },
    INTERFACESOUND_LOSTTARGETUNIT = { "INTERFACE_SOUND_LOST_TARGET_UNIT" },
    TalentScreenOpen           = { "TALENT_SCREEN_OPEN" },
    igSpellBookOpen            = { "IG_SPELLBOOK_OPEN" },
    igCharacterInfoTab         = { "IG_CHARACTER_INFO_TAB" },
}

function ns.PlaySound(name)
    local kits = SOUND_KITS[name]
    if not kits then return end
    for _, k in ipairs(kits) do
        local id = (type(k) == "number") and k or (SOUNDKIT and SOUNDKIT[k])
        if id then
            PlaySound(id)
            return
        end
    end
end

---------------------------------------------------------------------------
-- Groups and addon messages
---------------------------------------------------------------------------
function ns.NumParty() return GetNumSubgroupMembers() end
function ns.NumRaid() return IsInRaid() and GetNumGroupMembers() or 0 end
-- Addon messages. The modern client gives each prefix an allowance of 10
-- messages that comes back at 1 per second, and drops anything over it, which
-- is far less than a busy table needs. So CowCasino sends on a pool of
-- prefixes, keeps track of each one's allowance, and refuses a send (Net.lua
-- keeps it queued and retries) rather than have the game drop it. Everything
-- arriving on the pool reads as plain "CowCasino" to the rest of the addon.
local PREFIX = "CowCasino"
local POOL_SIZE = 8
local ALLOWANCE, REGAIN = 10, 1    -- messages, and messages per second
local RESERVE = 1                  -- leave one in hand in case the server counts differently
local pool, inPool = {}, {}
for i = 1, POOL_SIZE do
    local p = (i == 1) and PREFIX or (PREFIX .. i)
    pool[i] = { prefix = p, left = ALLOWANCE, at = 0 }
    inPool[p] = true
    C_ChatInfo.RegisterAddonMessagePrefix(p)
end
ns.PREFIX_POOL = inPool

function ns.AddonVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get("CowCasino", "Version") or "?"
end

local function Refill(b)
    local now = GetTime()
    b.left = math.min(ALLOWANCE, b.left + (now - b.at) * REGAIN)
    b.at = now
end

local R = Enum and Enum.SendAddonMessageResult or {}
local warned

-- For /casino net: how many sends each prefix has left right now.
function ns.PrefixAllowance()
    local t = {}
    for _, b in ipairs(pool) do
        Refill(b)
        table.insert(t, math.floor(b.left))
    end
    return table.concat(t, " ")
end

-- Returns false when no prefix has allowance left right now (try again soon).
function ns.SendAddonMessage(prefix, text, channel)
    local best
    for _, b in ipairs(pool) do
        Refill(b)
        if b.left >= 1 + RESERVE and (not best or b.left > best.left) then best = b end
    end
    if not best then return false end
    -- Chat typed by players goes through the logged send, as the game asks
    -- of addons that pass on what people write.
    local send = C_ChatInfo.SendAddonMessage
    if string.sub(text, 1, 3) == "CH;" and C_ChatInfo.SendAddonMessageLogged then send = C_ChatInfo.SendAddonMessageLogged end
    local result = send(best.prefix, text, channel)
    best.left = best.left - 1
    ns.lastSendResult = result
    for k, v in pairs(R) do if v == result then ns.lastSendResult = k end end
    if result == nil or result == true or result == 0 or result == R.Success then return true end
    if result == R.AddonMessageThrottle or result == R.ChannelThrottle then
        best.left = 0              -- the server says this one's spent: wait for it
        return false
    end
    -- Anything else won't get better by retrying (e.g. accounts that may not
    -- send addon messages): say so once, and drop the message.
    if not warned then
        warned = true
        local why = tostring(result)
        for k, v in pairs(R) do if v == result then why = k end end
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd100CowCasino:|r the game won't send party play messages (" .. why .. ").")
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Models and the addon compartment
---------------------------------------------------------------------------
ns.QUESTION_MARK_MODEL = "Interface\\Buttons\\talktomequestionmark.m2"

-- A portrait's close-up on the face. The modern client's camera 0 only
-- frames some models (the rest stay full body); portrait zoom frames every
-- player's head and shoulders, the way the game's own unit portraits do.
function ns.FaceCamera(model)
    if model.SetPortraitZoom then
        model:SetPortraitZoom(1)
        if model.SetCamDistanceScale then model:SetCamDistanceScale(1) end
    else
        model:SetCamera(0)
    end
end

function CowCasino_OnAddonCompartmentClick()
    if ns.Toggle then ns:Toggle() end
end
