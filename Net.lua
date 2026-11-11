-- CowCasino: network layer for party play.
-- Hidden addon messages to the party or raid (the 1.12 client has no private
-- addon whispers, so everything goes to the whole group). Sends are queued and
-- rate-limited so a busy table never floods the server; a message sent with a
-- key replaces any queued message with the same key, so only the newest table
-- state goes out.
--
-- To send as few addon messages as possible, sends are gathered for a moment
-- and packed together: everything waiting goes out in as few messages as fit,
-- joined by "~" (which no game message uses), and is unpacked on arrival.
-- Table chat (CH) can contain anything typed, so it always goes out alone.

local ns = CowCasino.ns

local PREFIX = "CowCasino"
local CPS    = 600      -- characters per second we allow ourselves
local BURST  = 900
local SEP    = "~"      -- joins packed messages
local PACKET = 240      -- longest packed message (prefix + message must stay under 255)
local GATHER = 0.2      -- seconds to collect sends before they go out together

local Net = { handlers = {}, groupHandlers = {} }
ns.Net = Net

function Net.Split(s, sep)
    local out, start = {}, 1
    while true do
        local i = string.find(s, sep, start, true)
        if not i then
            table.insert(out, string.sub(s, start))
            break
        end
        table.insert(out, string.sub(s, start, i - 1))
        start = i + 1
    end
    return out
end

function Net:Me()
    return UnitName("player")
end

function Net:Channel()
    if ns.NumRaid() > 0 then return "RAID" end
    if ns.NumParty() > 0 then return "PARTY" end
    return nil
end

function Net:InGroup()
    return self:Channel() ~= nil
end

function Net:GroupSize()
    local raid = ns.NumRaid()
    if raid > 0 then return raid end
    return ns.NumParty() + 1
end

-- Is `name` in our party or raid (or us)?
function Net:IsMember(name)
    if not name then return false end
    if name == self:Me() then return true end
    local raid = ns.NumRaid()
    if raid > 0 then
        for i = 1, raid do
            if UnitName("raid" .. i) == name then return true end
        end
        return false
    end
    for i = 1, ns.NumParty() do
        if UnitName("party" .. i) == name then return true end
    end
    return false
end

-- The unit id ("player", "party2", "raid17") for a group member, or nil.
function Net:UnitFor(name)
    if not name then return nil end
    if name == self:Me() then return "player" end
    local raid = ns.NumRaid()
    if raid > 0 then
        for i = 1, raid do
            if UnitName("raid" .. i) == name then return "raid" .. i end
        end
        return nil
    end
    for i = 1, ns.NumParty() do
        if UnitName("party" .. i) == name then return "party" .. i end
    end
    return nil
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local queue = {}
local tokens = BURST
local gathered = 0
Net.sentCount, Net.longest, Net.packedCount = 0, 0, 0

local function Packable(text)
    return string.sub(text, 1, 3) ~= "CH;" and not string.find(text, SEP, 1, true)
end

-- The next addon message: as many queued messages from the front as fit.
-- Returns the text and how many queued messages it carries.
local function NextPacket()
    local text = queue[1].text
    if not Packable(text) then return text, 1 end
    local n = 1
    while queue[n + 1] do
        local nextText = queue[n + 1].text
        if not Packable(nextText) or string.len(text) + 1 + string.len(nextText) > PACKET then break end
        text = text .. SEP .. nextText
        n = n + 1
    end
    return text, n
end

local pump = ns.CreateFrame("Frame")
pump:Hide()
pump:SetScript("OnUpdate", function()
    tokens = math.min(BURST, tokens + CPS * (arg1 or 0))
    gathered = gathered + (arg1 or 0)
    if gathered < GATHER then return end
    while queue[1] do
        local text, n = NextPacket()
        local cost = string.len(text) + 30
        if tokens < cost then return end
        local chan = Net:Channel()
        if chan then
            -- A client that limits addon messages (WoW Forever) can refuse a
            -- send for now: keep it queued and try again on a later frame.
            -- (The 1.12 client never refuses.)
            if ns.SendAddonMessage(PREFIX, text, chan) == false then return end
            Net.sentCount = Net.sentCount + 1
            Net.packedCount = Net.packedCount + n
            if string.len(text) > Net.longest then Net.longest = string.len(text) end
        end
        tokens = tokens - cost
        for _ = 1, n do table.remove(queue, 1) end
    end
    gathered = 0
    this:Hide()
end)

function Net:Send(text, key)
    if not self:InGroup() then return end
    if key then
        -- Drop the older copy and queue the new one at the back, so it never
        -- overtakes messages sent after the old one.
        for i, m in ipairs(queue) do
            if m.key == key then
                table.remove(queue, i)
                break
            end
        end
    end
    table.insert(queue, { text = text, key = key })
    pump:Show()
end

function Net:Queued() return ns.getn(queue) end

---------------------------------------------------------------------------
-- Receiving: handlers[tag](sender, fields), where tag is the first field.
---------------------------------------------------------------------------
local listener = ns.CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_ADDON")
listener:RegisterEvent("PARTY_MEMBERS_CHANGED")
listener:RegisterEvent("RAID_ROSTER_UPDATE")
listener:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
        if arg1 ~= PREFIX or arg4 == Net:Me() then return end
        local text = arg2 or ""
        local parts
        if string.sub(text, 1, 3) == "CH;" then parts = { text } else parts = Net.Split(text, SEP) end
        local sender = arg4
        for _, part in ipairs(parts) do
            local fields = Net.Split(part, ";")
            local handler = Net.handlers[fields[1]]
            if handler then handler(sender, fields) end
        end
    else
        for _, h in pairs(Net.groupHandlers) do h() end
    end
end)
