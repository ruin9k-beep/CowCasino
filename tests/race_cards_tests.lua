-- Orc & Troll deck and Human back: every card, every size, real files, selectable.
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
local function FileOf(path)
  local rel = string.gsub(string.gsub(path, "^Interface\\AddOns\\CowCasino\\", ""), "\\", "/")
  return ADDON .. "/" .. rel .. ".tga"
end
local function TgaOk(path)
  local f = io.open(FileOf(path), "rb"); if not f then return false, "missing" end
  local hdr = f:read(18); f:close()
  local w = string.byte(hdr, 13) + 256 * string.byte(hdr, 14)
  local h = string.byte(hdr, 15) + 256 * string.byte(hdr, 16)
  local function p2(x) return x > 0 and math.floor(math.log(x, 2) + 0.5) == math.log(x, 2) end
  return p2(w) and p2(h) and string.byte(hdr, 17) == 32 and string.byte(hdr, 3) == 2, w .. "x" .. h
end

local order = table.concat(ns.cardArtOrder, ",")
Check("the list is Plain, Tauren, Orc & Troll, Human", order == "plain,tauren,orc,human", order)
local SIZES = { { 46, 64 }, { 30, 42 }, { 26, 36 } }

-- painted decks (Tauren still works the same through the shared code)
for _, id in ipairs({ "tauren", "orc" }) do
  ns:SetCardArt(id)
  local used, problems = {}, {}
  for _, size in ipairs(SIZES) do
    local parent = env.CreateFrame("Frame", nil, env.CowCasinoFrame); parent:Show()
    local w = ns:CreateCardWidget(parent, size[1], size[2])
    for suit = 1, 4 do for rank = 1, 13 do
      w:SetCard({ rank = rank, suit = suit }, true)
      local skin = w.skins[id]
      local r, su = ns.RANKS[rank], ns.SUITS[suit]
      used[skin.card.tex] = true; used[skin.smallSuit.tex] = true
      if not (skin.card.shown and skin.rank.shown and skin.smallSuit.shown) then table.insert(problems, r.key .. su.key .. " parts") end
      if skin.rank.text ~= r.key then table.insert(problems, r.key .. su.key .. " rank") end
      local want = ({ S = 0, H = 1, D = 2, C = 3 })[su.key] * 0.25
      if skin.smallSuit.coords[1] ~= want then table.insert(problems, r.key .. su.key .. " suit icon") end
      if r.face then
        used[skin.emblem.tex] = true
        if not skin.emblem.shown or skin.bigSuit.shown or skin.emblem.coords[1] ~= ({ J = 0, Q = 0.25, K = 0.5 })[r.key] then table.insert(problems, r.key .. su.key .. " emblem") end
      elseif not skin.bigSuit.shown or skin.emblem.shown or skin.bigSuit.coords[1] ~= want then
        table.insert(problems, r.key .. su.key .. " center suit")
      end
      local c = skin.rank.color
      if (su.red and c[1] < 0.5) or (not su.red and c[1] > 0.5) then table.insert(problems, r.key .. su.key .. " color") end
    end end
    w:SetCard({ rank = 1, suit = 1 }, false)
    local skin = w.skins[id]
    used[skin.card.tex] = true
    if not skin.card.shown or skin.rank.shown or skin.smallSuit.shown or skin.bigSuit.shown or skin.emblem.shown
      or not string.find(skin.card.tex, "Back", 1, true) then table.insert(problems, "back at " .. size[2]) end
  end
  Check(ns.cardArt[id].name .. ": 52 faces and the back at all three sizes", table.getn(problems) == 0, table.concat(problems, "; "))
  local n, bad = 0, {}
  for path in pairs(used) do
    n = n + 1
    if not string.find(path, "\\" .. (id == "orc" and "Orc" or "Tauren"), 1, true) then table.insert(bad, path .. " (wrong deck)") end
    local good, info = TgaOk(path); if not good then table.insert(bad, path .. " " .. info) end
  end
  Check(ns.cardArt[id].name .. ": its 4 images exist, 32-bit power-of-two TGAs", n == 4 and table.getn(bad) == 0, n .. " " .. table.concat(bad, ", "))
end

-- Human: Plain faces, painted back
ns:SetCardArt("human")
local problems = {}
for _, size in ipairs(SIZES) do
  local parent = env.CreateFrame("Frame", nil, env.CowCasinoFrame); parent:Show()
  local w = ns:CreateCardWidget(parent, size[1], size[2])
  for suit = 1, 4 do for rank = 1, 13 do
    w:SetCard({ rank = rank, suit = suit }, true)
    local skin = w.skins.human
    if skin.humanBack.shown or not skin.face.shown or not skin.edge.shown or skin.back.shown
      or not skin.rank.shown or skin.rank.text ~= ns.RANKS[rank].key then table.insert(problems, ns.RANKS[rank].key .. ns.SUITS[suit].key) end
  end end
  w:SetCard({ rank = 1, suit = 1 }, false)
  local skin = w.skins.human
  if not skin.humanBack.shown or skin.face.shown or skin.edge.shown or skin.back.shown or skin.backInner.shown
    or skin.rank.shown or skin.bigSuit.shown then table.insert(problems, "back at " .. size[2]) end
  -- face again after a back: Plain's card comes back
  w:SetCard({ rank = 12, suit = 2 }, true)
  if skin.humanBack.shown or not skin.face.shown or not skin.edge.shown then table.insert(problems, "face after back at " .. size[2]) end
  local good, info = TgaOk(skin.humanBack.tex)
  if not good then table.insert(problems, "back image " .. info) end
end
Check("Human: Plain faces, the painted back hides Plain's card", table.getn(problems) == 0, table.concat(problems, "; "))

-- a widget switching decks between hands only shows one deck
ns:SetCardArt("orc")
local parent = env.CreateFrame("Frame", nil, env.CowCasinoFrame); parent:Show()
local w = ns:CreateCardWidget(parent, 46, 64)
w:SetCard({ rank = 5, suit = 3 }, false)
ns:SetCardArt("human"); w:SetCard({ rank = 5, suit = 3 }, false)
local stray = 0
for _, o in ipairs(env.all) do if o.kind == "Texture" and Visible(o) and type(o.tex) == "string" and o.parent and (o.parent == w or o.parent.parent == w) and string.find(o.tex, "Orc", 1, true) then stray = stray + 1 end end
Check("switching Orc & Troll to Human leaves no Orc art showing", stray == 0, stray)

-- picking them in CowCasino Options
ns:SetCardArt("plain")
local function Find(text) for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == text and Visible(o) then return o end end end
local function OnPage(o) while o do if o == ns.optionsPage then return true end; o = o.parent end end
ns:ShowMenu()
env.Fire(Find("Options"), "OnClick", "LeftButton")
for _, pick in ipairs({ { "orc", "Orc & Troll", "OrcCard" }, { "human", "Human", "HumanCardBack" } }) do
  local guard = 0
  while ns:GetCardArt().id ~= pick[1] and guard < 10 do env.Fire(Find(">"), "OnClick", "LeftButton"); guard = guard + 1 end
  local label
  for _, f in ipairs(env.all) do if f.kind == "FontString" and Visible(f) and OnPage(f) and f.text == pick[2] then label = f end end
  local previews = 0
  for _, o in ipairs(env.all) do if o.kind == "Texture" and Visible(o) and OnPage(o) and type(o.tex) == "string" and string.find(o.tex, pick[3], 1, true) then previews = previews + 1 end end
  Check("Options: pick " .. pick[2] .. " with >, preview shows its art", ns:GetCardArt().id == pick[1] and label ~= nil and previews >= 1, previews)
end
env.Fire(Find("Done"), "OnClick", "LeftButton")
Check("the choice is saved", ns.db.cardArt == "human")
io.write(ok and "RACE CARDS PASS\n" or "RACE CARDS FAIL\n")
os.exit(ok and 0 or 1)
