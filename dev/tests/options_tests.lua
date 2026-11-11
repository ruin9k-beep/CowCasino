-- CowCasino options: window size and game order.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-62s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end
local function Start(saved)
  local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
  env.arg = { ADDON }; env.SELECT_SAVED = select
  assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
  env.CowCasinoDB = saved
  for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
  env.CowCasinoFrame:Show()
  return env, env.CowCasino.ns
end
local env, ns = Start(nil)
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Find(text) for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == text and Visible(o) then return o end end end
local function All(text) local t = {} for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == text and Visible(o) then table.insert(t, o) end end return t end
local function Press(b) assert(b, "missing button"); assert(b.enabled, "disabled " .. tostring(b.text)); env.Fire(b, "OnClick", "LeftButton") end
-- menu position of each game, top to bottom
local function MenuOrder(e, n)
  local rows = {}
  -- page by page, top to bottom
  for id, row in pairs(n.menuRows) do table.insert(rows, { id = id, y = row.anchor[5] - 10000 * row.menuPage }) end
  table.sort(rows, function(a, b) return a.y > b.y end)
  local out = {}
  for _, r in ipairs(rows) do table.insert(out, r.id) end
  return table.concat(out, ",")
end
local default = table.concat(ns.gameOrder, ",")
Check("menu starts in the default order", MenuOrder(env, ns) == default, MenuOrder(env, ns))
Press(Find("Options"))
Check("Options opens the CowCasino options", ns.optionsPage:IsShown() and Find("Default order") ~= nil)
local ups, downs = All("Up"), All("Down")
Check("one row per game", table.getn(ups) == table.getn(ns.gameOrder) and table.getn(downs) == table.getn(ns.gameOrder))
Check("first can't go up, last can't go down", not ups[1].enabled and not downs[table.getn(downs)].enabled)
Press(downs[1])      -- Blackjack down one
local o = ns.gameOrder
local swapped = {}
for i = 1, table.getn(o) do swapped[i] = o[i] end
swapped[1], swapped[2] = o[2], o[1]
Check("Down moves a game down the menu", MenuOrder(env, ns) == table.concat(swapped, ","), MenuOrder(env, ns))
-- move the last game to the top
for i = table.getn(o), 2, -1 do Press(All("Up")[i]) end
local now = MenuOrder(env, ns)
local last = o[table.getn(o)]
Check("Up moves a game to the top", string.sub(now, 1, string.len(last)) == last, now)
local found = false
for _, f in ipairs(env.all) do if f.kind == "FontString" and Visible(f) and f.text == "1. " .. ns.games[last].name then found = true end end
Check("the options list shows the new order", found)
local saved = ns.db
local env2, ns2 = Start(saved)
Check("order is kept after a restart", MenuOrder(env2, ns2) == now, MenuOrder(env2, ns2))
-- a saved order missing a game (added later) still shows it, at the end
local partial = {}
for i = 1, table.getn(o) - 1 do partial[i] = o[i] end
saved.order = partial
local env3, ns3 = Start(saved)
Check("games missing from a saved order go at the end", MenuOrder(env3, ns3) == default, MenuOrder(env3, ns3))
saved.order = { "nosuchgame", o[3] }
local env4, ns4 = Start(saved)
Check("unknown games in a saved order are ignored", string.sub(MenuOrder(env4, ns4), 1, string.len(o[3])) == o[3])
Press(Find("Default order"))
Check("Default order puts it back", MenuOrder(env, ns) == default and ns.db.order == nil)

-- Window size
local slider
for _, f in ipairs(env.all) do if f.kind == "Slider" then slider = f end end
Check("the size slider starts at 100%", slider and slider.value == 1)
local frame = env.CowCasinoFrame

-- A real drag: every frame the game turns the mouse position into a value
-- using the slider's size and place on screen right now, which depend on the
-- window's current size. (Slider: 16 from the window's left edge, 200 wide.)
local WINDOW_LEFT = 300
local function Drag(toX, frames)
  local scales = {}
  for _ = 1, frames do
    local s = frame:GetScale()
    local left, width = WINDOW_LEFT + 30 * s, 200 * s
    local f = math.max(0, math.min(1, (toX - left) / width))
    slider:SetValue(0.5 + f)
    table.insert(scales, frame:GetScale())
  end
  return scales
end
local function Release() env.Fire(slider, "OnMouseUp", "LeftButton") end
local during = Drag(WINDOW_LEFT + 30, 20)          -- all the way left
local steady = true
for _, sc in ipairs(during) do if sc ~= 1 then steady = false end end
Check("dragging doesn't resize the window under the mouse", steady)
Release()
Check("letting go applies it: 50%", frame:GetScale() == 0.5, frame:GetScale())
-- the slider is now half as long; drag it all the way right
Drag(WINDOW_LEFT + 15 + 100, 20)
Release()
Check("...and it can be dragged back up: 150%", frame:GetScale() == 1.5, frame:GetScale())
Drag(WINDOW_LEFT + 45 + 150, 20)                    -- the middle, at 150%
Release()
Check("...and to the middle: 100%", frame:GetScale() == 1, frame:GetScale())
-- not applied until release; closing the screen applies a pending size too
slider:SetValue(0.75)
Check("a size isn't applied until the mouse is let go", frame:GetScale() == 1)
ns.optionsPage:Hide()
Check("closing the options applies a size not yet applied", frame:GetScale() == 0.75)
ns.optionsPage:Show()
slider:SetValue(1)
Release()
slider:SetValue(0.75)
Release()
Check("slider shrinks the whole window", frame:GetScale() == 0.75 and ns.db.scale == 0.75)
local a = frame.anchor
Check("...keeping its top-left corner in place", a[1] == "TOPLEFT" and math.abs(a[4] - 412.5 / 0.75) < 0.01 and math.abs(a[5] - 655 / 0.75) < 0.01,
  a[4] .. "," .. a[5])
local pct = false
for _, f in ipairs(env.all) do if f.kind == "FontString" and Visible(f) and f.text == "75%" then pct = true end end
Check("shows the size as a percentage", pct)
slider:SetValue(1.4); Release()
Check("slider grows it too", frame:GetScale() == 1.4)
slider:SetValue(5); Release()
Check("size stays within 50%-150%", frame:GetScale() == 1.5)
slider:SetValue(0.8); Release()
local env5, ns5 = Start(ns.db)
Check("size is kept after a restart", env5.CowCasinoFrame:GetScale() == 0.8)
Press(Find("100%"))
Check("100% button resets the size", frame:GetScale() == 1 and slider.value == 1)
slider:SetValue(0.6); Release()
env.SlashCmdList.COWCASINO("reset")
Check("/casino reset: normal size, centered", frame:GetScale() == 1 and frame.anchor[1] == "CENTER")
Press(Find("Done"))
Check("Done closes the options", not ns.optionsPage:IsShown())
Press(Find("Options"))
ns:OpenGame("blackjack")
Check("opening a game closes the options", not ns.optionsPage:IsShown())

-- the game list: two lines for every description, four games a page
do
  local menu = env.CowCasinoFrame.menu
  ns:ShowMenu()
  ns.db.order = nil
  ns:LayoutMenu()
  local shown, descOk = 0, true
  for _, row in pairs(ns.menuRows) do
    if row:IsShown() then shown = shown + 1 end
    if row.h ~= 56 or row.desc.h ~= 24 then descOk = false end
  end
  Check("menu rows are full height with two lines for the description", descOk)
  Check("four games a page, with page buttons", shown == 4 and menu.pager:IsShown() and menu.pageText.text == "Page 1 of 2", menu.pageText.text)
  Check("...Prev is off on page 1", not menu.prevPage.enabled and menu.nextPage.enabled)
  env.Fire(menu.nextPage, "OnClick", "LeftButton")
  shown = 0
  local showsCrash = false
  for id, row in pairs(ns.menuRows) do if row:IsShown() then shown = shown + 1; if id == "crash" then showsCrash = true end end end
  Check("Next shows the rest of the games", menu.page == 2 and shown == 4 and showsCrash and not menu.nextPage.enabled)
  env.Fire(menu.list, "OnMouseWheel", 1)
  Check("the mouse wheel turns back a page", menu.page == 1)
  local lowest = 0
  for _, row in pairs(ns.menuRows) do
    if row:IsShown() then local bottom = -row.anchor[5] + 56; if bottom > lowest then lowest = bottom end end
  end
  Check("the page fits above the page buttons", lowest <= 318 - 24, lowest)
end
-- every game on the menu has its own painted icon, a 64x64 32-bit TGA in the addon
do
  local bad, seen = {}, {}
  for _, id in ipairs(ns.gameOrder) do
    local icon = ns.games[id].icon or ""
    local rel = string.gsub(string.gsub(icon, "^Interface\\AddOns\\CowCasino\\", ""), "\\", "/")
    local f = (rel ~= icon) and io.open(ADDON .. "/" .. rel .. ".tga", "rb")
    local hdr = f and f:read(18)
    if f then f:close() end
    if not hdr or string.byte(hdr, 3) ~= 2 or string.byte(hdr, 13) ~= 64 or string.byte(hdr, 15) ~= 64 or string.byte(hdr, 17) ~= 32 then
      table.insert(bad, id .. " " .. icon)
    end
    if seen[icon] then table.insert(bad, id .. " shares " .. seen[icon] .. "'s icon") end
    seen[icon] = id
  end
  Check("every game has its own painted icon (64x64, 32-bit TGA)", table.getn(bad) == 0, table.concat(bad, "; "))
end
io.write(ok and "OPTIONS PASS\n" or "OPTIONS FAIL\n")
os.exit(ok and 0 or 1)
