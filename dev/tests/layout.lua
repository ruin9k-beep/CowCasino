-- Layout checks for the tests: works out where each region of a screen lands
-- (from the anchors and sizes the mock records), then reports what spills
-- off the screen and what overlaps. Text has no real font here, so its size
-- is estimated from the font: that's close enough to catch real collisions,
-- and the checks allow a few pixels either way.
--
--   local L = dofile("layout.lua")
--   local problems = L.Check(env, root, { skip = { region, ... } })
--   -- each: "\"Play\" (Button) overlaps \"Stake 50\" (FontString)" and the like
local L = {}

local SLACK = 2     -- pixels of overlap or spill that don't count

local function FontSize(o)
  if rawget(o, "fontSize") then return o.fontSize end
  local f = rawget(o, "font") or "GameFontNormal"
  if string.find(f, "Large") then return 16 end
  if string.find(f, "Small") then return 10 end
  return 12
end

local function Plain(text)
  if type(text) ~= "string" then return "" end     -- (some frames keep a font string in .text)
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "|T.-|t", "WW")
  text = string.gsub(text, "||", "|")
  return text
end

-- A font string's text: its width (one line), and lines when wrapped at width w.
local function Measure(o, w)
  local size = FontSize(o)
  local charW, lineH = size * 0.5, size + 2
  local widest, lines = 0, 0
  for line in (string.gmatch or string.gfind)(Plain(o.text) .. "\n", "(.-)\n") do
    local tw = string.len(string.gsub(line, "[\128-\191]", "")) * charW   -- (characters, not bytes)
    if w and w > 0 then
      lines = lines + math.max(1, math.ceil(tw / w))
      widest = math.max(widest, math.min(tw, w))
    else
      lines = lines + 1
      widest = math.max(widest, tw)
    end
  end
  return widest, math.max(1, lines) * lineH, lines
end

local function H(point) -- the horizontal part of an anchor point
  if string.find(point, "LEFT") then return "L" elseif string.find(point, "RIGHT") then return "R" end
  return "C"
end
local function V(point)
  if string.find(point, "TOP") then return "T" elseif string.find(point, "BOTTOM") then return "B" end
  return "C"
end

-- { l, b, r, t } (y grows upward, as in WoW), or nil when it can't be told.
function L.Rect(o, cache)
  cache = cache or {}
  if cache[o] ~= nil then return cache[o] or nil end
  cache[o] = false
  local pts = rawget(o, "points")
  local rect
  if not pts or not pts[1] then
    if not o.parent and o.kind == "Frame" and o.w > 0 then rect = { 0, 0, o.w, o.h } end   -- UIParent
    cache[o] = rect or false
    return rect
  end
  local l, r, cx, t, b, cy
  for _, p in ipairs(pts) do
    local rel = L.Rect(p[2], cache)
    if not rel then return nil end
    local hx = H(p[3])
    local ax = (hx == "L" and rel[1]) or (hx == "R" and rel[3]) or (rel[1] + rel[3]) / 2
    local vy = V(p[3])
    local ay = (vy == "T" and rel[4]) or (vy == "B" and rel[2]) or (rel[2] + rel[4]) / 2
    ax, ay = ax + p[4], ay + p[5]
    local h, v = H(p[1]), V(p[1])
    if h == "L" then l = ax elseif h == "R" then r = ax else cx = ax end
    if v == "T" then t = ay elseif v == "B" then b = ay else cy = ay end
  end
  local w, hgt = o.w, o.h
  local text = o.kind == "FontString"
  if text then
    local boxW = (l and r) and (r - l) or w
    local tw, th = Measure(o, boxW)
    if not (w and w > 0) and not (l and r) then w = tw end
    if not (hgt and hgt > 0) and not (t and b) then hgt = th end
  end
  if not (l and r) then
    if not (w and w > 0) then return nil end
    if l then r = l + w elseif r then l = r - w else l = cx - w / 2; r = cx + w / 2 end
  end
  if not (t and b) then
    if not (hgt and hgt > 0) then return nil end
    if t then b = t - hgt elseif b then t = b + hgt else b = cy - hgt / 2; t = cy + hgt / 2 end
  end
  rect = { l, b, r, t }
  if text then
    -- a box wider than its one line of text: only the text counts
    local tw, th, lines = Measure(o, r - l)
    if lines == 1 and tw < r - l then
      local j = rawget(o, "justifyH") or "CENTER"
      if j == "LEFT" then rect[3] = l + tw elseif j == "RIGHT" then rect[1] = r - tw
      else rect[1] = (l + r - tw) / 2; rect[3] = (l + r + tw) / 2 end
    end
    if th < t - b then
      local mid = (t + b) / 2
      rect[2], rect[4] = mid - th / 2, mid + th / 2
    end
  end
  cache[o] = rect
  return rect
end

local function Under(o, root)
  local p = o
  while p do
    if p == root then return true end
    p = p.parent
  end
  return false
end

local function ShownTo(o, root)
  local p = o
  while p do
    if not p.shown then return false end
    if p == root then return true end
    p = p.parent
  end
  return false
end

local function InsideButton(o, root)
  local p = o.parent
  while p and p ~= root do
    if p.kind == "Button" or p.kind == "CheckButton" then return true end
    p = p.parent
  end
  return false
end

local function Name(o)
  local text = Plain(o.text)
  if text == "" and o.kind == "EditBox" then text = "(input)" end
  if string.len(text) > 40 then text = string.sub(text, 1, 40) .. "..." end
  return "\"" .. text .. "\" (" .. o.kind .. ")"
end

-- What on screen root (shown) spills off it or overlaps. opts.skip: regions
-- whose whole subtree isn't checked (a hidden-behind layer, say).
function L.Check(env, root, opts)
  opts = opts or {}
  local cache, items, problems = {}, {}, {}
  local rootRect = L.Rect(root, cache)
  if not rootRect then return { "the screen itself has no size" } end
  local function Skipped(o)
    for _, s in ipairs(opts.skip or {}) do if Under(o, s) then return true end end
    return false
  end
  for _, o in ipairs(env.all) do
    local kind = o.kind
    local wanted = (kind == "FontString" and Plain(o.text) ~= "" and not InsideButton(o, root))
      or kind == "Button" or kind == "CheckButton" or kind == "EditBox"
    if wanted and o ~= root and Under(o, root) and ShownTo(o, root) and not Skipped(o) then
      local rect = L.Rect(o, cache)
      if rect and rect[3] - rect[1] > 0 and rect[4] - rect[2] > 0 then
        table.insert(items, { o = o, r = rect })
      end
    end
  end
  for _, it in ipairs(items) do
    local r = it.r
    if r[1] < rootRect[1] - SLACK or r[3] > rootRect[3] + SLACK or r[2] < rootRect[2] - SLACK or r[4] > rootRect[4] + SLACK then
      table.insert(problems, Name(it.o) .. " goes off the screen")
    end
  end
  for i = 1, table.getn(items) do
    for j = i + 1, table.getn(items) do
      local a, b = items[i], items[j]
      -- text over a button with no label of its own is that button's label (Roulette's numbers)
      local label = (a.o.kind == "FontString" and b.o.kind == "Button" and Plain(b.o.text) == "")
        or (b.o.kind == "FontString" and a.o.kind == "Button" and Plain(a.o.text) == "")
        -- (and click areas with no label can lie over each other: Roulette's splits)
        or (a.o.kind == "Button" and b.o.kind == "Button" and Plain(a.o.text) == "" and Plain(b.o.text) == "")
      if not label and not Under(a.o, b.o) and not Under(b.o, a.o) then
        local w = math.min(a.r[3], b.r[3]) - math.max(a.r[1], b.r[1])
        local h = math.min(a.r[4], b.r[4]) - math.max(a.r[2], b.r[2])
        if w > SLACK and h > SLACK then
          table.insert(problems, Name(a.o) .. " overlaps " .. Name(b.o))
        end
      end
    end
  end
  return problems
end

return L
