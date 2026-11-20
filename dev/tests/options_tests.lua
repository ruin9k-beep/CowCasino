-- CowCasino options: window size and game order.
local ADDON = arg[1]
local H = dofile("harness.lua")
local Check, Start, Visible, Find = H.Check, H.Start, H.Visible, H.Find
local env, ns = Start(nil)
local function All(text) local t = {} for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == text and Visible(o) then table.insert(t, o) end end return t end
local function Press(b) assert(b, "missing button"); assert(b.enabled, "disabled " .. tostring(b.text)); env.Fire(b, "OnClick", "LeftButton") end
-- menu position of each game, top to bottom
local function MenuOrder(e, n)
  local rows = {}
  -- page by page, top to bottom
  -- page by page, then row by row, then left to right
  for id, row in pairs(n.menuRows) do table.insert(rows, { id = id, key = row.menuPage * 100000 - row.anchor[5] * 100 + row.anchor[4] }) end
  table.sort(rows, function(a, b) return a.key < b.key end)
  local out = {}
  for _, r in ipairs(rows) do table.insert(out, r.id) end
  return table.concat(out, ",")
end
local default = table.concat(ns.gameOrder, ",")
Check("menu starts in the default order", MenuOrder(env, ns) == default, MenuOrder(env, ns))
Press(Find("Options"))
Press(Find("Games"))
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
Press(Find("Display"))
local slider
for _, f in ipairs(env.all) do if f.kind == "Slider" then slider = f end end
Check("the size slider starts at 100%", slider and slider.value == 1)
local frame = env.CowCasinoFrame

-- A real drag: every frame the game turns the mouse position into a value
-- using the slider's size and place on screen right now, which depend on the
-- window's current size. (Slider: 114 from the window's left edge, 130 wide;
-- 75% to 250%.)
local WINDOW_LEFT = 300
local MINS, MAXS = 0.75, 2.5
Check("the size goes from 75% to 250%", ns.MIN_SCALE == MINS and ns.MAX_SCALE == MAXS)
local function SliderAt(s) return WINDOW_LEFT + 114 * s, 130 * s end
local function Drag(toX, frames)
  local scales = {}
  for _ = 1, frames do
    local left, width = SliderAt(frame:GetScale())
    local f = math.max(0, math.min(1, (toX - left) / width))
    slider:SetValue(MINS + f * (MAXS - MINS))
    table.insert(scales, frame:GetScale())
  end
  return scales
end
local function Release() env.Fire(slider, "OnMouseUp", "LeftButton") end
local during = Drag(WINDOW_LEFT, 20)               -- all the way left
local steady = true
for _, sc in ipairs(during) do if sc ~= 1 then steady = false end end
Check("dragging doesn't resize the window under the mouse", steady)
Release()
Check("letting go applies it: 75%", frame:GetScale() == 0.75, frame:GetScale())
-- the slider is now shorter; drag it all the way right
local l, w = SliderAt(0.75)
Drag(l + w + 5, 20)
Release()
Check("...and it can be dragged back up: 250%", frame:GetScale() == 2.5, frame:GetScale())
l, w = SliderAt(2.5)
Drag(l + w * (1 - MINS) / (MAXS - MINS), 20)        -- where 100% is, at 250%
Release()
Check("...and down to 100%", frame:GetScale() == 1, frame:GetScale())
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
Check("size stays within 75%-250%", frame:GetScale() == 2.5)
slider:SetValue(0.1); Release()
Check("...at both ends", frame:GetScale() == 0.75)
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

-- the game list: a grid of tiles, 5 x 4 a page, blue borders for multiplayer
do
  local menu = env.CowCasinoFrame.menu
  ns:ShowMenu()
  ns.db.order = nil
  ns:LayoutMenu()
  local shown, xs, ys, fits = 0, {}, {}, true
  for _, tile in pairs(ns.menuRows) do
    if tile:IsShown() then
      shown = shown + 1
      xs[tile.anchor[4]] = true
      ys[tile.anchor[5]] = true
      if tile.anchor[4] + 66 > 352 or -tile.anchor[5] + 62 > 318 - 28 - 24 then fits = false end
    end
  end
  local cols, rows = 0, 0
  for _ in pairs(xs) do cols = cols + 1 end
  for _ in pairs(ys) do rows = rows + 1 end
  local n = table.getn(ns.gameOrder)
  Check("the games are a grid: 5 across, up to 4 down", cols == math.min(5, n) and rows == math.min(4, math.ceil(n / 5))
    and shown == math.min(20, n), cols .. "x" .. rows)
  Check("...that fits the window, with room for the description and page buttons", fits)
  Check("one page for 20 games, page buttons beyond", (n <= 20) == (not menu.pager:IsShown()))
  local bj, mines = ns.menuRows.blackjack, ns.menuRows.mines
  Check("multiplayer games have a blue border, single player gold", bj.multiplayer and not mines.multiplayer
    and bj.border[3] == 1 and mines.border[3] < 0.5)
  Check("Sketch & Guess, Hangman and Mafia count as multiplayer", ns.menuRows.sketch.multiplayer
    and ns.menuRows.hangman.multiplayer and ns.menuRows.mafia.multiplayer)
  Check("under the grid, a key to the borders", string.find(menu.desc.text, "multiplayer") ~= nil)
  env.Fire(mines, "OnEnter")
  Check("hovering a game: its description under the grid", string.find(menu.desc.text, "dodge the mines", 1, true) ~= nil)
  Check("...and in a tooltip", env.GameTooltip:IsShown())
  env.Fire(mines, "OnLeave")
  Check("leaving it puts the key back", string.find(menu.desc.text, "multiplayer") ~= nil and not env.GameTooltip:IsShown())
  env.Fire(bj, "OnEnter")
  Check("a multiplayer game's line drops the Supports Multiplayer tag (the border says it)",
    string.find(menu.desc.text, "Beat the dealer", 1, true) ~= nil and not string.find(menu.desc.text, "Supports", 1, true))
  env.Fire(bj, "OnLeave")

  -- Multiplayer games first (Options > Games)
  Press(Find("Options"))
  Press(Find("Games"))
  local box = ns.optionsPage.mpFirst
  Check("Options > Games has a Multiplayer games first box, off", box ~= nil and Visible(box) and not box.checked)
  box.checked = true            -- (a real click ticks the box before OnClick)
  env.Fire(box, "OnClick", "LeftButton")
  local order = ns:MenuOrder()
  local firstSP
  for i, id in ipairs(order) do if not ns:IsMultiplayer(ns.games[id]) then firstSP = firstSP or i end end
  local after = true
  for i, id in ipairs(order) do if i > (firstSP or 999) and ns:IsMultiplayer(ns.games[id]) then after = false end end
  Check("ticked: every multiplayer game comes before the single player ones", ns.db.mpFirst and firstSP and firstSP > 1 and after)
  local mpIds, spIds = {}, {}
  for _, id in ipairs(ns.gameOrder) do
    if ns:IsMultiplayer(ns.games[id]) then table.insert(mpIds, id) else table.insert(spIds, id) end
  end
  for _, id in ipairs(spIds) do table.insert(mpIds, id) end
  Check("...each group keeping its own order, and the grid follows", table.concat(order, ",") == table.concat(mpIds, ",")
    and MenuOrder(env, ns) == table.concat(mpIds, ","))
  box.checked = nil
  env.Fire(box, "OnClick", "LeftButton")
  Check("unticked: back to the plain order", not ns.db.mpFirst and MenuOrder(env, ns) == table.concat(ns.gameOrder, ","))
  ns:OpenGame("blackjack")
end
-- the window style: Modern by default, Tauren in Options > Display
do
  local f = env.CowCasinoFrame
  Check("the window is Modern by default (the Tauren art hidden)", f.modern:IsShown() and not f.skin:IsShown()
    and not f.totemL:IsShown() and not f.hornR:IsShown())
  ns:ShowMenu()
  Press(Find("Options"))
  Press(Find("Display"))
  local st = ns.optionsPage.styleStep
  Check("Options > Display: Window style, Modern", st ~= nil and Visible(st) and string.find(st.text.text, "Modern", 1, true) ~= nil)
  env.Fire(st.up, "OnClick", "LeftButton")
  Check("...switching to Tauren brings back the totems and horns", ns.db.frameStyle == "tauren" and f.skin:IsShown()
    and f.totemL:IsShown() and f.hornL:IsShown() and not f.modern:IsShown())
  env.Fire(st.down, "OnClick", "LeftButton")
  Check("...and back to Modern", ns.db.frameStyle == "modern" and f.modern:IsShown() and not f.skin:IsShown())
  Press(Find("Options"))
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
-- multiplayer games say so (the menu turns it into a blue border); every
-- description fits the line under the grid
do
  local mp, bad = {}, {}
  for _, id in ipairs(ns.gameOrder) do
    local d = ns.games[id].description or ""
    local s = string.find(d, "\n|cff66ccffSupports Multiplayer|r", 1, true)
    if s then mp[id] = true end
    local first = string.sub(d, 1, (s or (string.find(d, "\n", 1, true) or 0)) - 1)
    if s == nil and not string.find(d, "\n", 1, true) then first = d end
    if string.len(first) > 90 then table.insert(bad, id .. " description too long") end
  end
  Check("Blackjack, Hold'em, Craps and Hangman say Supports Multiplayer on line two", mp.blackjack and mp.holdem and mp.craps
    and mp.hangman and not mp.slots and not mp.hilo and table.getn(bad) == 0, table.concat(bad, "; "))
end
-- Tabs: each page splits into Settings / Rules / Sounds, only the ones it has
do
  local function Tabs(id)
    ns:OpenGame(id)
    local o = ns.games[id].options
    o:Show()
    local names = {}
    if o.tabs and o.tabs.bar.shown then for _, b in ipairs(o.tabs.buttons) do table.insert(names, b.text) end end
    return o, table.concat(names, ",")
  end
  local o, names = Tabs("keno")
  Check("Keno's options: Settings, Rules and Sounds tabs", names == "Settings,Rules,Sounds", names)
  Check("...Settings first, the rules out of sight", Visible(o.settings) and not Visible(o.rules) and Find("Defaults") == nil)
  Press(Find("Rules"))
  Check("Rules shows the rules and hides the settings", Visible(o.rules) and not Visible(o.settings))
  Press(Find("Sounds"))
  Check("Sounds shows the sound choices", Find("Defaults") ~= nil and not Visible(o.rules))
  Check("Reset stats and Done are on every tab", Find("Reset stats") ~= nil and Find("Done") ~= nil)
  Press(Find("Done"))
  o:Show()
  Check("the page reopens on the tab you left it on", Find("Defaults") ~= nil)
  o:Hide()
  local _, mines = Tabs("mines")
  Check("Mines (no rules, no sounds) draws no tabs", mines == "", mines)
  local _, hilo = Tabs("hilo")
  Check("Hi-Lo: Rules and Sounds", hilo == "Rules,Sounds", hilo)
  local _, roulette = Tabs("roulette")
  Check("Roulette's plain page has no tabs", roulette == "", roulette)
  ns:ShowMenu()
  ns.optionsPage:Show()
  local t = {}
  for _, b in ipairs(ns.optionsPage.tabs.buttons) do table.insert(t, b.text) end
  Check("CowCasino options: Display, Games, Chat and Chips tabs", table.concat(t, ",") == "Display,Games,Chat,Chips", table.concat(t, ","))
  Press(Find("Chips"))
  Check("Chips has Start over, and the game order is out of sight", Find("Start over") ~= nil and Find("Default order") == nil)
  ns.optionsPage:Hide()
end
H.Done("OPTIONS")
