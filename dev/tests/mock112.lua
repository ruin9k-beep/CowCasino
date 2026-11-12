-- Strict mock of the WoW 1.12 client for CowCasino's 1.12 build.
-- Only 1.12 widget methods exist (anything else errors), script handlers get
-- no arguments (this/event/arg1 globals), strings have no methods (Lua 5.0),
-- and the Lua 5.0 library names are used.
local ADDON = arg[1]
local _select = select or SELECT_SAVED
SELECT_SAVED = _select
local _fmod = math.fmod or math.mod
local _atan = math.atan
local _gmatch = string.gmatch or string.gfind
_G = _ENV

all = {}
local usedNames = {}

local function set(list) local t = {} for w in _gmatch(list, "%S+") do t[w] = true end return t end
local FRAME = "GetScale GetLeft GetTop GetRight GetBottom SetScript GetScript Show Hide IsShown IsVisible SetWidth SetHeight GetWidth GetHeight SetPoint ClearAllPoints SetAllPoints GetPoint GetParent SetParent SetFrameLevel GetFrameLevel SetFrameStrata EnableMouse SetMovable RegisterForDrag StartMoving StopMovingOrSizing RegisterEvent UnregisterEvent CreateTexture CreateFontString SetBackdrop SetBackdropColor SetBackdropBorderColor SetAlpha GetCenter GetEffectiveScale GetName SetScale EnableMouseWheel"
local BUTTON = FRAME .. " SetText GetText Enable Disable IsEnabled RegisterForClicks SetHighlightTexture SetNormalTexture SetPushedTexture"
local API = {
  Frame = set(FRAME), Button = set(BUTTON),
  Slider = set(FRAME .. " SetMinMaxValues SetValueStep SetValue GetValue SetOrientation GetMinMaxValues"),
  PlayerModel = set(FRAME .. " SetUnit SetCamera SetModel SetModelScale SetPosition ClearModel SetFacing"), CheckButton = set(BUTTON .. " SetChecked GetChecked"),
  GameTooltip = set(FRAME .. " SetOwner AddLine SetText ClearLines"),
  EditBox = set(FRAME .. " SetText GetText SetFocus ClearFocus SetMaxLetters SetAutoFocus SetFontObject SetTextInsets SetTextColor SetJustifyH"),
  Texture = set("SetTexture SetTexCoord SetAlpha SetVertexColor SetWidth SetHeight GetWidth GetHeight SetPoint ClearAllPoints SetAllPoints Show Hide IsShown SetBlendMode"),
  FontString = set("SetText GetText SetTextColor SetFont SetShadowOffset SetShadowColor SetJustifyH SetJustifyV SetWidth SetHeight GetWidth GetHeight SetPoint ClearAllPoints SetAllPoints Show Hide IsShown SetAlpha"),
}
local OPTIONAL_ABSENT = set("SetClampedToScreen")   -- may not exist on 1.12; code must guard
local FONT_TEMPLATES = set("GameFontNormal GameFontNormalSmall GameFontNormalLarge GameFontHighlight GameFontHighlightSmall GameFontHighlightLarge GameFontDisable GameFontDisableSmall")
local FRAME_TEMPLATES = set("UIPanelButtonTemplate UICheckButtonTemplate UIPanelCloseButton OptionsSliderTemplate")
local NEEDS_NAME = set("UIPanelButtonTemplate UICheckButtonTemplate OptionsSliderTemplate")
local LAYERS = set("BACKGROUND BORDER ARTWORK OVERLAY HIGHLIGHT")
local CLICKS = set("LeftButtonUp RightButtonUp LeftButtonDown RightButtonDown MiddleButtonUp AnyUp")
CLICKS.AnyUp = nil
local SOUNDS = set("igMainMenuOption igMainMenuOptionCheckBoxOn igCharacterInfoOpen igCharacterInfoClose LOOTWINDOWCOINSOUND LEVELUPSOUND RaidWarning igQuestListComplete igQuestCancel igQuestListOpen igQuestListClose igQuestListSelect WriteQuest igMainMenuOpen igMainMenuClose BAGMENUBUTTONPRESS igQuestFailed MapPing TellMessage igPlayerInvite PVPTHROUGHQUEUE PVPENTERQUEUE AuctionWindowOpen AuctionWindowClose igCreatureAggroSelect INTERFACESOUND_LOSTTARGETUNIT TalentScreenOpen igSpellBookOpen igCharacterInfoTab")

local methods = {}
local MT = { __index = function(t, k)
  if type(k) == "string" and string.find(k, "^%u") then
    if OPTIONAL_ABSENT[k] then return nil end
    if not API[rawget(t, "kind")][k] then
      error("1.12 has no " .. rawget(t, "kind") .. ":" .. k, 2)
    end
    return methods[k]
  end
  return nil
end }

local function newObj(kind, parent)
  local o = setmetatable({ kind = kind, parent = parent, scripts = {}, shown = true,
    enabled = 1, level = (parent and rawget(parent, "level") or 0) + 1, w = 0, h = 0, text = "" }, MT)
  o.file = LOADING_FILE
  all[#all + 1] = o
  return o
end

-- Fire a script the 1.12 way: no arguments, globals instead.
function Fire(o, script, a1, ev, a2, a3, a4)
  local f = o.scripts[script]
  if not f then return end
  local p1, p2, p3, p4, pe, pt = arg1, arg2, arg3, arg4, event, this
  this, arg1, event, arg2, arg3, arg4 = o, a1, ev, a2, a3, a4
  f()
  this, arg1, event, arg2, arg3, arg4 = pt, p1, pe, p2, p3, p4
end

function methods:SetScript(n, f) assert(f == nil or type(f) == "function"); self.scripts[n] = f end
function methods:GetScript(n) return self.scripts[n] end
function methods:SetText(t) self.text = tostring(t or "") end
function methods:GetText() return self.text end
function methods:Enable() self.enabled = 1 end
function methods:Disable() self.enabled = nil end
function methods:IsEnabled() return self.enabled end
function methods:Show() local was = self.shown; self.shown = true; if not was then Fire(self, "OnShow") end end
function methods:Hide() local was = self.shown; self.shown = false; if was then Fire(self, "OnHide") end end
function methods:IsShown() return self.shown and 1 or nil end
function methods:IsVisible() return self.shown and 1 or nil end
function methods:SetWidth(w) assert(type(w) == "number"); self.w = w end
function methods:SetHeight(h) assert(type(h) == "number"); self.h = h end
function methods:GetWidth() return self.w end
function methods:GetHeight() return self.h end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(l) assert(type(l) == "number"); self.level = l end
function methods:GetParent() return self.parent end
function methods:GetName() return self.name end
function methods:SetPoint(point, rel, relPoint, x, y)
  assert(type(point) == "string", "SetPoint needs a point")
  assert(type(rel) == "table", "1.12 SetPoint needs a relative frame (got " .. tostring(rel) .. ")")
  assert(relPoint == nil or type(relPoint) == "string", "bad relative point")
  assert(x == nil or type(x) == "number", "bad x"); assert(y == nil or type(y) == "number", "bad y")
end
function methods:SetAllPoints(rel) assert(type(rel) == "table", "1.12 SetAllPoints needs a frame") end
-- Like the real 1.12 client after a drag: no anchor is reported.
function methods:GetPoint() return nil end
function methods:GetLeft() return 412.5 end
function methods:GetTop() return 655 end
function methods:SetPoint(point, rel, relPoint, x, y)
  assert(type(point) == "string", "SetPoint needs a point")
  assert(type(rel) == "table", "1.12 SetPoint needs a relative frame (got " .. tostring(rel) .. ")")
  assert(relPoint == nil or type(relPoint) == "string", "bad relative point")
  assert(x == nil or type(x) == "number", "bad x"); assert(y == nil or type(y) == "number", "bad y")
  self.anchor = { point, rel, relPoint, x, y }
end
function methods:CreateTexture(name, layer, ...)
  assert(_select("#", ...) == 0, "CreateTexture takes 2 arguments on 1.12")
  assert(layer == nil or LAYERS[layer], "bad layer " .. tostring(layer))
  return newObj("Texture", self)
end
function methods:CreateFontString(name, layer, template)
  assert(template == nil or FONT_TEMPLATES[template], "font template missing in 1.12: " .. tostring(template))
  return newObj("FontString", self)
end
function methods:SetTexture(a, g, b, al)
  if type(a) == "number" then assert(type(g) == "number" and type(b) == "number") else assert(a == nil or type(a) == "string") end
  self.tex = a; if type(a) == "number" then self.color = { a, g, b, al or 1 } end
end
function methods:SetFont(path, size, flags) assert(type(path) == "string" and type(size) == "number" and size > 0, "bad SetFont") end
function methods:RegisterForClicks(...)
  for i = 1, _select("#", ...) do assert(CLICKS[_select(i, ...)], "bad click type " .. tostring(_select(i, ...))) end
end
function methods:SetFocus() self.focus = true; Fire(self, "OnEditFocusGained") end
function methods:ClearFocus() if self.focus then self.focus = nil; Fire(self, "OnEditFocusLost") end end
function methods:SetMaxLetters(n) assert(type(n) == "number" and n > 0); self.maxLetters = n end
function methods:SetAutoFocus(b) self.autoFocus = b end
function methods:SetFontObject(f) assert(type(f) == "table" and rawget(f, "fontObject"), "SetFontObject needs a font object") end
function methods:SetTextInsets(l, r, t, b) assert(type(l) == "number" and type(r) == "number" and type(t) == "number" and type(b) == "number") end
function methods:EnableMouseWheel(b) self.wheel = b end
-- Typing into an edit box (tests): sets the text the way the client would, capped at the max letters.
function TypeInto(o, text)
  assert(o.kind == "EditBox")
  if o.maxLetters then text = string.sub(text, 1, o.maxLetters) end
  o.text = text
  Fire(o, "OnTextChanged")
end
function methods:SetChecked(b) self.checked = b and 1 or nil end
function methods:GetChecked() return self.checked end
function methods:GetCenter() return 500, 500 end
function methods:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
function methods:UnregisterEvent(e) if self.events then self.events[e] = nil end end
function methods:GetEffectiveScale() return self.scale or 1 end
function methods:SetScale(x) assert(type(x) == "number" and x > 0, "bad scale"); self.scale = x end
function methods:GetScale() return self.scale or 1 end
function methods:SetMinMaxValues(a, b) assert(type(a) == "number" and type(b) == "number" and a < b); self.minv, self.maxv = a, b end
function methods:GetMinMaxValues() return self.minv, self.maxv end
function methods:SetValueStep(x) assert(type(x) == "number") end
function methods:SetValue(v)
  assert(type(v) == "number")
  v = math.max(self.minv or v, math.min(self.maxv or v, v))
  local changed = v ~= self.value
  self.value = v
  if changed then Fire(self, "OnValueChanged", v) end
end
function methods:GetValue() return self.value or 0 end
function methods:SetUnit(u) assert(type(u) == "string", "SetUnit needs a unit"); self.unit = u; self.model = nil end
function methods:SetModel(m) assert(type(m) == "string"); self.model = m; self.unit = nil end
function methods:ClearModel() self.unit, self.model = nil, nil end
function methods:SetCamera(c) assert(type(c) == "number"); self.camera = c end
function methods:SetTexCoord(l, r, t, b)
  assert(type(l) == "number" and type(r) == "number" and type(t) == "number" and type(b) == "number", "SetTexCoord needs 4 numbers")
  self.coords = { l, r, t, b }
end
function methods:SetAlpha(a) assert(type(a) == "number", "SetAlpha needs a number"); self.alpha = a end
function methods:SetTextColor(r, g, b, a) assert(type(r) == "number" and type(g) == "number" and type(b) == "number"); self.color = { r, g, b, a or 1 } end
function methods:SetModelScale(x) assert(type(x) == "number") end
function methods:SetPosition(x, y, z) assert(type(x) == "number" and type(y) == "number" and type(z) == "number") end
function methods:SetFacing(f) assert(type(f) == "number") end
for k in pairs(set(FRAME .. " " .. BUTTON .. " SetOwner AddLine ClearLines SetTexCoord SetVertexColor SetBlendMode SetTextColor SetShadowOffset SetShadowColor SetJustifyH SetJustifyV")) do
  if not methods[k] then methods[k] = function() end end
end

function CreateFrame(kind, name, parent, template)
  assert(API[kind], "unknown frame type " .. tostring(kind))
  assert(template == nil or FRAME_TEMPLATES[template], "template missing in 1.12: " .. tostring(template))
  if template and NEEDS_NAME[template] then assert(name, template .. " needs a name on 1.12") end
  if name then assert(not usedNames[name], "duplicate frame name " .. name); usedNames[name] = true end
  local o = newObj(kind, parent)
  o.name = name
  if name then _G[name] = o end
  if template == "OptionsSliderTemplate" then
    for _, part in ipairs({ "Low", "High", "Text" }) do _G[name .. part] = newObj("FontString", o) end
  end
  return o
end

getglobal = function(n) return _G[n] end
for f in pairs(FONT_TEMPLATES) do _G[f] = { fontObject = f } end
UIParent = newObj("Frame"); UISpecialFrames = {}; tinsert = table.insert
strlower = string.lower
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
PlaySound = function(name) assert(type(name) == "string" and SOUNDS[name], "unknown 1.12 sound " .. tostring(name)) end
SlashCmdList = {}
GameTooltip = newObj("GameTooltip")
Minimap = newObj("Frame"); Minimap.w = 140
GetCursorPosition = function() return 400, 600 end
IsShiftKeyDown = function() return nil end
PLAYER_NAME = PLAYER_NAME or "Tester"
UnitName = function(u) if u == "player" then return PLAYER_NAME end return nil end
GetNumPartyMembers = function() return 0 end
GetNumRaidMembers = function() return 0 end
UNIT_VISIBLE = UNIT_VISIBLE or {}
UnitIsVisible = function(u) if UNIT_VISIBLE[u] == false then return nil end return UnitName(u) and 1 or nil end
UnitIsConnected = function(u) return UnitName(u) and 1 or nil end
SendAddonMessage = function() end
CLOCK = 0
GetTime = function() return CLOCK end
DEFAULT_CHAT_FRAME = newObj("Frame"); API.Frame.AddMessage = true; methods.AddMessage = function() end

-- Lua 5.0 library: no string methods, 5.0 names, nothing from 5.1+.
getmetatable("").__index = nil
math.mod = _fmod; math.fmod = nil
math.atan2 = function(y, x) return _atan(y, x) end
-- Lua 5.0 table sizes (lauxlib.c luaL_getn/luaL_setn): getn uses a numeric
-- field n, else a size recorded by setn (which table.insert and table.remove
-- call), else counts from 1 to the first nil. A size once recorded is NOT
-- updated by plain t[i] = v assignments, which is a real 1.12 pitfall.
-- (Installed once; the library is shared by every mock client in a run.)
if not rawget(table, "_lua50") then
  local orig = { insert = table.insert, remove = table.remove, sort = table.sort, concat = table.concat }
  local sizes = setmetatable({}, { __mode = "k" })
  local function getn(t)
    local n = rawget(t, "n")
    if type(n) == "number" then return n end
    if sizes[t] then return sizes[t] end
    local i = 0
    while rawget(t, i + 1) ~= nil do i = i + 1 end
    return i
  end
  local function setn(t, n)
    if type(rawget(t, "n")) == "number" then rawset(t, "n", n) else sizes[t] = n end
  end
  table.getn, table.setn = getn, setn
  table.insert = function(t, ...)
    local argc = _select("#", ...)
    local n = getn(t) + 1
    local pos, v
    if argc == 1 then pos, v = n, (...)
    else
      pos, v = ...
      assert(type(pos) == "number", "table.insert: bad position")
      if pos > n then n = pos end
    end
    setn(t, n)
    local i = n
    while i - 1 >= pos do rawset(t, i, rawget(t, i - 1)); i = i - 1 end
    rawset(t, pos, v)
  end
  table.remove = function(t, pos)
    local n = getn(t)
    pos = pos or n
    if n <= 0 then return nil end
    setn(t, n - 1)
    local v = rawget(t, pos)
    for i = pos, n - 1 do rawset(t, i, rawget(t, i + 1)) end
    rawset(t, n, nil)
    return v
  end
  table.concat = function(t, sep, i, j) return orig.concat(t, sep or "", i or 1, j or getn(t)) end
  table.sort = function(t, comp)
    local n = getn(t)
    local tmp = {}
    for i = 1, n do tmp[i] = rawget(t, i) end
    orig.sort(tmp, comp)
    for i = 1, n do rawset(t, i, tmp[i]) end
  end
  rawset(table, "_lua50", true)
end
string.gfind = _gmatch; string.gmatch = nil; string.match = nil
table.unpack = nil
print = nil

-- What the tests need to know about this client (the retail mock has its own).
ROSTER_EVENT = "PARTY_MEMBERS_CHANGED"   -- the group changed
REALM_SUFFIX = ""                        -- added to addon message senders
QUESTION_MODEL = "Interface\\Buttons\\talktomequestionmark.mdx"
function PrefixHeard(prefix) return true end   -- 1.12 delivers every prefix
function SoundName(id) return id end           -- sounds are already 1.12 names

-- Load the addon the way 1.12 does: no arguments to the file.
local TOC_FILES = {}
for line in io.lines(ADDON .. "/CowCasino.toc") do
  line = string.gsub(string.gsub(line, "\r", ""), "^%s+", "")
  if line ~= "" and string.sub(line, 1, 2) ~= "##" then
    TOC_FILES[#TOC_FILES + 1] = (string.gsub(line, "\\", "/"))
  end
end
for _, f in ipairs(TOC_FILES) do
  local chunk = assert(loadfile(ADDON .. "/" .. f, "t", _ENV))
  LOADING_FILE = f
  chunk()
  LOADING_FILE = nil
end
select = nil
