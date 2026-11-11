-- Slots paytable: winning line shapes, on pages.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-62s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end
local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
env.arg = { ADDON }; env.SELECT_SAVED = select
assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
env.CowCasinoFrame:Show()
local ns = env.CowCasino.ns
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Find(text) for _, o in ipairs(env.all) do if o.kind == "Button" and o.text == text and Visible(o) then return o end end end
local function Press(text) local b = assert(Find(text), "no " .. text); assert(b.enabled, "disabled " .. text); env.Fire(b, "OnClick", "LeftButton") end
local function Shown(text) for _, f in ipairs(env.all) do if f.kind == "FontString" and Visible(f) and f.text and string.find(f.text, text, 1, true) then return true end end end

ns:OpenGame("slots")
Press("Paytable")
local pt = ns.games.slots
local o
for _, f in ipairs(env.all) do if f.lineTiles then o = f end end
Check("paytable opens on the pays page", Shown("in a row") and not Shown("Line 1") and o.page == 1)
Check("Prev disabled on the first page", Find("< Prev") and not Find("< Prev").enabled)
Check("the pays note points to the next pages", Shown("wilds, free spins and line shapes"))
Press("Next >")
Check("Next shows the wilds and free spins", Shown("Wilds and free spins") and Shown("2x, 3x or 5x") and Shown("12 free spins"))
Press("Next >")
Check("Next again shows the winning lines", Shown("Winning lines") and Shown("Line 1") and not Shown("in a row"))
local LINES = pt.LINES
local n = table.getn(LINES)
local all, shapes = true, true
for i = 1, n do
  local t = o.lineTiles[i]
  if not t then all = false else
    for r = 1, 5 do if t.lit[r] ~= LINES[i][r] then shapes = false end end
  end
end
Check("one diagram for each of the " .. n .. " lines", all)
Check("each diagram lights exactly that line's path", shapes)
-- line 5 is the V from the screenshot: rows 1,2,3,2,1
Check("line 5 is drawn as a V", table.concat(o.lineTiles[5].lit, ",") == "1,2,3,2,1", table.concat(o.lineTiles[5].lit, ","))
-- tiles stay inside the panel (352 wide) and above the buttons
local inside = true
for i = 1, n do
  local a = o.lineTiles[i].anchor
  local x, y = a[4], a[5]
  if x < 0 or x + o.lineTiles[i].w > 352 or -y + o.lineTiles[i].h > 380 - 40 then inside = false end
end
Check("all diagrams fit on the page, above the buttons", inside)
local pages = table.getn(o.pages)
Check("10 lines fit on one page of shapes (3 pages total)", pages == 3, pages)
Check("Next disabled on the last page", not Find("Next >").enabled)
Press("< Prev"); Press("< Prev")
Check("Prev goes back to the pays", o.page == 1 and Shown("in a row"))
Press("Next >"); Press("Done")
Press("Paytable")
Check("reopening starts on the pays page again", o.page == 1)
io.write(ok and "SLOTS LINES PASS\n" or "SLOTS LINES FAIL\n")
os.exit(ok and 0 or 1)
