-- Tauren card art: every card, every size, real files, and it's selectable.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-66s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end
local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
env.arg = { ADDON }; env.SELECT_SAVED = select
assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
env.CowCasinoFrame:Show()
local ns = env.CowCasino.ns
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end

local order = table.concat(ns.cardArtOrder, ",")
Check("Tauren is in the card art list", string.find(order, "tauren", 1, true) ~= nil, order)
-- every texture it uses is a real file in the addon
local used = {}
local function FileOf(path)
  local rel = string.gsub(string.gsub(path, "^Interface\\AddOns\\CowCasino\\", ""), "\\", "/")
  return ADDON .. "/" .. rel .. ".tga"
end
ns:SetCardArt("tauren")
local function Shown(skin)
  local out = {}
  for _, k in ipairs({ "card", "rank", "smallSuit", "bigSuit", "emblem" }) do
    local o = skin[k]
    if o and o.shown then out[k] = o end
  end
  return out
end
local allOk, problems = true, {}
for _, size in ipairs({ { 46, 64 }, { 30, 42 }, { 26, 36 } }) do
  local parent = env.CreateFrame("Frame", nil, env.CowCasinoFrame)
  local w = ns:CreateCardWidget(parent, size[1], size[2])
  parent:Show()
  for suit = 1, 4 do
    for rank = 1, 13 do
      w:SetCard({ rank = rank, suit = suit }, true)
      local skin = w.skins.tauren
      local s = Shown(skin)
      local r, su = ns.RANKS[rank], ns.SUITS[suit]
      used[skin.card.tex] = true
      if not (s.card and s.rank and s.smallSuit) then table.insert(problems, r.key .. su.key .. " missing parts") end
      if skin.rank.text ~= r.key then table.insert(problems, r.key .. su.key .. " rank text " .. tostring(skin.rank.text)) end
      local want = ({ S = 0, H = 1, D = 2, C = 3 })[su.key] * 0.25
      if skin.smallSuit.coords[1] ~= want then table.insert(problems, r.key .. su.key .. " wrong suit icon") end
      used[skin.smallSuit.tex] = true
      if r.face then
        local wantC = ({ J = 0, Q = 0.25, K = 0.5 })[r.key]
        if not s.emblem or s.bigSuit or skin.emblem.coords[1] ~= wantC then table.insert(problems, r.key .. su.key .. " emblem") end
        used[skin.emblem.tex] = true
      else
        if not s.bigSuit or s.emblem or skin.bigSuit.coords[1] ~= want then table.insert(problems, r.key .. su.key .. " center suit") end
      end
      local c = skin.rank.color
      if (su.red and c[1] < 0.5) or (not su.red and c[1] > 0.5) then table.insert(problems, r.key .. su.key .. " rank color") end
    end
  end
  w:SetCard({ rank = 1, suit = 1 }, false)
  local s = Shown(w.skins.tauren)
  used[w.skins.tauren.card.tex] = true
  if not (s.card and not s.rank and not s.bigSuit and not s.emblem and not s.smallSuit) then table.insert(problems, "back at " .. size[2]) end
  if string.find(w.skins.tauren.card.tex, "Back", 1, true) == nil then table.insert(problems, "back texture") end
end
Check("all 52 faces and the back draw right at 46x64, 30x42 and 26x36", table.getn(problems) == 0, table.concat(problems, "; "))
local missing = {}
local n = 0
for path in pairs(used) do
  n = n + 1
  local f = io.open(FileOf(path), "rb")
  if f then f:close() else table.insert(missing, path) end
end
Check("every image it uses is in the addon (" .. n .. " files)", table.getn(missing) == 0 and n == 4, table.concat(missing, ", "))
-- TGAs are power-of-two and 32-bit
local badSize = {}
for path in pairs(used) do
  local f = io.open(FileOf(path), "rb"); local hdr = f:read(18); f:close()
  local w = string.byte(hdr, 13) + 256 * string.byte(hdr, 14)
  local h = string.byte(hdr, 15) + 256 * string.byte(hdr, 16)
  local bpp = string.byte(hdr, 17)
  local function p2(x) return x > 0 and math.floor(math.log(x, 2) + 0.5) == math.log(x, 2) end
  if not (p2(w) and p2(h) and bpp == 32 and string.byte(hdr, 3) == 2) then table.insert(badSize, path .. " " .. w .. "x" .. h .. "x" .. bpp) end
end
Check("images are uncompressed 32-bit TGAs with power-of-two sizes", table.getn(badSize) == 0, table.concat(badSize, ", "))
-- picking it in the CowCasino Options, and the games use it
ns:SetCardArt("plain")
local function Find(text) for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == text and Visible(o) then return o end end end
ns:ShowMenu()
env.Fire(Find("Options"), "OnClick", "LeftButton")
local guard = 0
while ns:GetCardArt().id ~= "tauren" and guard < 10 do
  local nextB
  for _, o in ipairs(env.all) do if not nextB and o.kind == "Button" and o.text == ">" and Visible(o) then nextB = o end end
  env.Fire(nextB, "OnClick", "LeftButton"); guard = guard + 1
end
local label, by
for _, f in ipairs(env.all) do if f.kind == "FontString" and Visible(f) and f.text == "Tauren" then label = f end end
for _, f in ipairs(env.all) do if f.kind == "FontString" and Visible(f) and f.text == "by ruin9k" then by = f end end
Check("CowCasino Options: pick Tauren with >", ns:GetCardArt().id == "tauren" and label ~= nil and by ~= nil)
local previews = 0
local function OnPage(o) while o do if o == ns.optionsPage then return true end; o = o.parent end end
for _, o in ipairs(env.all) do if o.kind == "Texture" and Visible(o) and OnPage(o) and type(o.tex) == "string" and string.find(o.tex, "TaurenCard", 1, true) then previews = previews + 1 end end
Check("...with a preview: an ace, a queen and a back", previews == 3, previews)
env.Fire(Find("Done"), "OnClick", "LeftButton")
ns:OpenGame("blackjack")
env.Fire(Find("Options"), "OnClick", "LeftButton")
local bjPicker = false
for _, f in ipairs(env.all) do if f.kind == "FontString" and Visible(f) and f.text == "Card art" then bjPicker = true end end
Check("Blackjack's Options no longer have a card art picker", not bjPicker)
env.Fire(Find("Done"), "OnClick", "LeftButton")
ns.db.blackjack.bet = 25
env.Fire(Find("Deal 25"), "OnClick", "LeftButton")
local tauren = 0
for _, o in ipairs(env.all) do if o.kind == "Texture" and Visible(o) and o.tex and type(o.tex) == "string" and string.find(o.tex, "TaurenCard", 1, true) then tauren = tauren + 1 end end
Check("dealt cards use the Tauren art", tauren >= 3, tauren)
Check("the choice is saved for every game", ns.db.cardArt == "tauren")
io.write(ok and "TAUREN CARDS PASS\n" or "TAUREN CARDS FAIL\n")
os.exit(ok and 0 or 1)
