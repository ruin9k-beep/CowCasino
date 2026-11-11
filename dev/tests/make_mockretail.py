s=open('mock112.lua').read()
def rep(a,b):
    global s
    assert s.count(a)==1, a
    s=s.replace(a,b)
rep('''-- Strict mock of the WoW 1.12 client for CowCasino's 1.12 build.
-- Only 1.12 widget methods exist (anything else errors), script handlers get
-- no arguments (this/event/arg1 globals), strings have no methods (Lua 5.0),
-- and the Lua 5.0 library names are used.''','''-- Strict mock of the modern client (WoW Forever) for CowCasino's WoW Forever build.
-- Script handlers get (self, ...) and no this/event/arg1 globals; color
-- textures need SetColorTexture, backdrops need BackdropTemplate, sounds are
-- numbers, fonts need flags, unknown events error, addon messages go through
-- C_ChatInfo with a registered prefix, senders carry their realm, models are .m2.''')
rep('''local FRAME = "GetScale GetLeft''','''local FRAME = "SetSize SetShown GetScale GetLeft''')
rep('''local BUTTON = FRAME .. " SetText''','''local BUTTON = FRAME .. " SetEnabled SetText''')
rep('''  Texture = set("SetTexture SetTexCoord''','''  Texture = set("SetColorTexture SetTexture SetTexCoord''')
rep('''local FRAME_TEMPLATES = set("UIPanelButtonTemplate UICheckButtonTemplate UIPanelCloseButton OptionsSliderTemplate")
local NEEDS_NAME = set("UIPanelButtonTemplate UICheckButtonTemplate OptionsSliderTemplate")''','''local FRAME_TEMPLATES = set("UIPanelButtonTemplate UICheckButtonTemplate UIPanelCloseButton OptionsSliderTemplate BackdropTemplate UISliderTemplate")
local NEEDS_NAME = set("")''')
rep('''function Fire(o, script, a1, ev, a2, a3, a4)
  local f = o.scripts[script]
  if not f then return end
  local p1, p2, p3, p4, pe, pt = arg1, arg2, arg3, arg4, event, this
  this, arg1, event, arg2, arg3, arg4 = o, a1, ev, a2, a3, a4
  f()
  this, arg1, event, arg2, arg3, arg4 = pt, p1, pe, p2, p3, p4
end''','''-- Fire a script the modern way: (self, ...) and no globals.
-- (Same call signature as the 1.12 mock, so the tests work with both.)
function Fire(o, script, a1, ev, a2, a3, a4)
  local f = o.scripts[script]
  if not f then return end
  if script == "OnEvent" then f(o, ev, a1, a2, a3, a4) else f(o, a1, a2, a3, a4) end
end''')
i = s.index('function methods:SetTexture(')
j = s.index('\nend\n', i) + 5
s = s[:i] + '''function methods:SetTexture(a, g, b, al)
  assert(g == nil, "modern client: SetTexture takes a file; colors need SetColorTexture")
  assert(a == nil or type(a) == "string" or type(a) == "number", "bad texture")
  self.tex = a
end
function methods:SetColorTexture(r, g, b, al)
  assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "bad color")
  self.color = { r, g, b, al or 1 }
end
function methods:SetSize(w, h) self.w, self.h = w, h end
function methods:SetShown(b) if b then self:Show() else self:Hide() end end
function methods:SetEnabled(b) self.enabled = b and 1 or nil end
function methods:SetBackdrop(b) assert(rawget(self, "backdropOK"), "modern client: SetBackdrop needs BackdropTemplate") end
''' + s[j:]
rep('''function methods:SetFont(path, size, flags) assert(type(path) == "string" and type(size) == "number" and size > 0, "bad SetFont") end''','''function methods:SetFont(path, size, flags) assert(type(path) == "string" and type(size) == "number" and size > 0 and type(flags) == "string", "bad SetFont (modern client wants flags)") end''')
rep('''function methods:SetModel(m) assert(type(m) == "string"); self.model = m; self.unit = nil end''','''function methods:SetModel(m) assert(type(m) == "string" and string.find(m, "%.m2$"), "modern client models are .m2: " .. tostring(m)); self.model = m; self.unit = nil end''')
rep('''function methods:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end''','''local EVENTS = set("ADDON_LOADED CHAT_MSG_ADDON GROUP_ROSTER_UPDATE PLAYER_LOGIN PLAYER_ENTERING_WORLD")
function methods:RegisterEvent(e) assert(EVENTS[e], "modern client has no event " .. tostring(e)); self.events = self.events or {}; self.events[e] = true end''')
rep('''  if name then _G[name] = o end
  if template == "OptionsSliderTemplate" then''','''  if name then _G[name] = o end
  if template == "BackdropTemplate" then o.backdropOK = true end
  if template == "OptionsSliderTemplate" and name then''')
rep('''getglobal = function(n) return _G[n] end
''','')
i = s.index('PlaySound = function(name)')
j = s.index('\n', i) + 1
s = s[:i] + '''PlaySound = function(id) assert(type(id) == "number", "modern PlaySound takes a sound kit number, got " .. tostring(id)) end
SOUNDKIT = { IG_MAINMENU_OPTION = 852, IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_CHARACTER_INFO_OPEN = 839,
  IG_CHARACTER_INFO_CLOSE = 840, IG_MAINMENU_OPEN = 850, IG_MAINMENU_CLOSE = 851, LOOT_WINDOW_COIN_SOUND = 120,
  IG_QUEST_LIST_COMPLETE = 878, IG_QUEST_CANCEL = 879, IG_QUEST_LIST_OPEN = 875, IG_QUEST_LIST_CLOSE = 876,
  IG_QUEST_LIST_SELECT = 877, WRITE_QUEST = 880, RAID_WARNING = 8959, IG_BACKPACK_OPEN = 862 }
''' + s[j:]
rep('''GetNumPartyMembers = function() return 0 end
GetNumRaidMembers = function() return 0 end
''','')
rep('''SendAddonMessage = function() end''','''-- Groups and addon messages. (Tests hook in through GetNumPartyMembers /
-- SendAddonMessage on the test side; the addon must use the modern calls.)
GetNumSubgroupMembers = function() local f = rawget(_G, "GetNumPartyMembers"); return f and f() or 0 end
GetNumGroupMembers = function() local n = GetNumSubgroupMembers(); return n > 0 and n + 1 or 0 end
IsInRaid = function() return false end
IsInGroup = function() return GetNumSubgroupMembers() > 0 end
Ambiguate = function(n, mode) assert(mode == "short" or mode == "none"); return (string.gsub(n, "%-.*$", "")) end
local prefixes = {}
-- The modern client's addon message throttle: each prefix has an allowance
-- of 10 messages, regaining 1 per second; over it, the send fails with
-- AddonMessageThrottle and the message is never delivered.
Enum = Enum or {}
Enum.SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
  InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8,
  GeneralError = 9, NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12 }
local allowance = {}
THROTTLE_DROPS = 0
local function Send(p, text, chan, logged)
  assert(prefixes[p], "modern client: addon prefix not registered: " .. tostring(p))
  assert(string.len(p) <= 16, "prefix too long")
  assert(string.len(text) <= 255, "addon message too long")
  local now = GetTime()
  local a = allowance[p] or { left = 10, at = now }
  a.left = math.min(10, a.left + (now - a.at))
  a.at = now
  allowance[p] = a
  if a.left < 1 then
    THROTTLE_DROPS = THROTTLE_DROPS + 1
    return Enum.SendAddonMessageResult.AddonMessageThrottle
  end
  a.left = a.left - 1
  if logged then assert(not string.find(text, "[%c]"), "logged addon messages must be plain text") end
  local hook = rawget(_G, "SendAddonMessage")
  if hook then hook(p, text, chan, logged) end
  return Enum.SendAddonMessageResult.Success
end
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(p) prefixes[p] = true; return Enum.SendAddonMessageResult and true end,
  IsAddonMessagePrefixRegistered = function(p) return prefixes[p] == true end,
  SendAddonMessage = function(p, text, chan) return Send(p, text, chan, false) end,
  SendAddonMessageLogged = function(p, text, chan) return Send(p, text, chan, true) end,
}''')
rep('''getmetatable("").__index = nil''','''getmetatable("").__index = string''')
a = s.index('-- Load the addon the way 1.12 does')
b = s.index('select = nil', a)
s = s[:a] + '''-- Load the addon in .toc order (the modern client also passes name, namespace).
local tocFiles = {}
for line in io.lines(ADDON .. "/CowCasino_Mainline.toc") do
  if not string.find(line, "^##") and string.find(line, "%S") then
    table.insert(tocFiles, (string.gsub(string.gsub(line, "\\\\", "/"), "%s+$", "")))
  end
end
local addonNS = {}
for _, f in ipairs(tocFiles) do
  local chunk = assert(loadfile(ADDON .. "/" .. f, "t", _ENV))
  LOADING_FILE = f
  chunk("CowCasino", addonNS)
  LOADING_FILE = nil
end
''' + s[b:]
rep("math.mod = _fmod; math.fmod = nil", "math.fmod = _fmod; math.mod = _fmod   -- mod only for the test code")
rep("string.gfind = _gmatch; string.gmatch = nil; string.match = nil", "string.gmatch = _gmatch; string.gfind = _gmatch   -- gfind only for the test code")
rep('''ROSTER_EVENT = "PARTY_MEMBERS_CHANGED"   -- the group changed
REALM_SUFFIX = ""                        -- added to addon message senders
QUESTION_MODEL = "Interface\\\\Buttons\\\\talktomequestionmark.mdx"
function PrefixHeard(prefix) return true end   -- 1.12 delivers every prefix
function SoundName(id) return id end           -- sounds are already 1.12 names
''', '''ROSTER_EVENT = "GROUP_ROSTER_UPDATE"
REALM_SUFFIX = "-Nordanaar"
QUESTION_MODEL = "Interface\\\\Buttons\\\\talktomequestionmark.m2"
function PrefixHeard(prefix) return C_ChatInfo.IsAddonMessagePrefixRegistered(prefix) end
-- sound kit numbers back to the 1.12 names the tests use
local SOUND_NAMES = { [852] = "igMainMenuOption", [856] = "igMainMenuOptionCheckBoxOn", [839] = "igCharacterInfoOpen",
  [840] = "igCharacterInfoClose", [850] = "igMainMenuOpen", [851] = "igMainMenuClose", [120] = "LOOTWINDOWCOINSOUND",
  [888] = "LEVELUPSOUND", [878] = "igQuestListComplete", [879] = "igQuestCancel", [875] = "igQuestListOpen",
  [876] = "igQuestListClose", [877] = "igQuestListSelect", [880] = "WriteQuest", [8959] = "RaidWarning", [862] = "BAGMENUBUTTONPRESS" }
function SoundName(id) return SOUND_NAMES[id] or id end
''')
# the modern client reads the Mainline .toc
s = s.replace('io.lines(ADDON .. "/CowCasino.toc")', 'io.lines(ADDON .. "/CowCasino_Mainline.toc")')
open('mockretail.lua','w').write(s)
print("ok")
