-- CowCasino: the shared drawing kit. Any game can put a drawing on screen,
-- let people draw on it and keep everyone's copy in step over the party:
--
--   local Kit = ns.SketchKit
--   local canvas = Kit.NewCanvas(parent, { size = 256, owner = Net:Me() })
--   local tools  = Kit.NewTools(parent, canvas)                -- colors, sizes, eraser, undo, clear
--   local sync   = Kit.NewSync({ tag = "SK", canvas = canvas }) -- strokes over the group
--   sync:Begin(context, { [artist] = true })   -- a new drawing (who may draw on it)
--   Net.handlers.SK: if sync:Handle(sender, fields) then return end
--   every frame or so: sync:Tick()
--   a newcomer: sync:Request()   (the artists send their strokes again)
--
-- A drawing is strokes in a 256 x 256 space, whatever size it's shown at.
-- A stroke has a color, a size and its points; it's drawn as rotated line
-- textures with round dots at the joins ("lines"), or as a chain of dots
-- ("dots"), for a client that can't rotate a texture. Strokes are keyed
-- "<owner>:<n>", so several people can draw on one canvas.
--
-- On the wire (each part is a field, after the game's tag):
--   D;ctx;owner;n;style;seq;points    points of stroke n from point seq on
--   E;ctx;owner;n                     stroke erased
--   C;ctx                             canvas cleared (by an artist)
--   N;ctx                             please send your strokes again
-- ctx is the game's name for the drawing (it must not hold ";" or "~"), so
-- messages for an older drawing are ignored. A point is 3 characters.

local ns = CowCasino.ns
local Net = ns.Net

local Kit = {}
ns.SketchKit = Kit

Kit.SPACE = 256
Kit.PAPER = { 0.96, 0.94, 0.88 }
Kit.COLORS = {
    { 0.08, 0.07, 0.06 }, { 0.50, 0.50, 0.50 }, { 0.50, 0.31, 0.14 }, { 0.86, 0.13, 0.10 }, { 0.98, 0.55, 0.10 },
    { 0.93, 0.80, 0.08 }, { 0.16, 0.62, 0.22 }, { 0.16, 0.40, 0.86 }, { 0.56, 0.24, 0.72 },
}
Kit.SIZES = { 2, 4, 8, 14 }
Kit.MAX_TEXTURES = 6000        -- per canvas; past this, new strokes are kept but not drawn
local ART = "Interface\\AddOns\\CowCasino\\Art\\"
local LINE_TEX, DOT_TEX = ART .. "SketchLine", ART .. "SketchDot"
-- SketchLine.tga: a bar from u = MARGIN to 1 - MARGIN, v = 0.25 to 0.75
local MARGIN, BAND = 2 / 32, 0.5

---------------------------------------------------------------------------
-- Packing points and styles into text
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VAL = {}
for i = 1, 64 do VAL[string.sub(B64, i, i)] = i - 1 end
local function Ch(v) return string.sub(B64, v + 1, v + 1) end

function Kit.StyleChar(color, size) return Ch((color - 1) * 4 + (size - 1)) end
function Kit.ParseStyle(ch)
    local v = VAL[ch or ""] or 0
    local color, size = math.floor(v / 4) + 1, ns.Mod(v, 4) + 1
    if not Kit.COLORS[color] then color = 1 end
    return color, size
end

-- pts is flat (x1, y1, x2, y2, ...); points first..last (by number).
function Kit.EncodePoints(pts, first, last)
    local out = {}
    for i = first, last do
        local x, y = pts[i * 2 - 1], pts[i * 2]
        local v = x * 256 + y
        table.insert(out, Ch(math.floor(v / 4096)) .. Ch(ns.Mod(math.floor(v / 64), 64)) .. Ch(ns.Mod(v, 64)))
    end
    return table.concat(out)
end

function Kit.DecodePoints(text)
    local out = {}
    for i = 1, math.floor(string.len(text or "") / 3) do
        local a, b, c = VAL[string.sub(text, i * 3 - 2, i * 3 - 2)], VAL[string.sub(text, i * 3 - 1, i * 3 - 1)], VAL[string.sub(text, i * 3, i * 3)]
        if not (a and b and c) then return out end
        local v = a * 4096 + b * 64 + c
        table.insert(out, math.floor(v / 256))
        table.insert(out, ns.Mod(v, 256))
    end
    return out
end

---------------------------------------------------------------------------
-- How lines are drawn: "lines" (rotated textures) or "dots". Stored in
-- ns.db.sketchLines; "lines" unless the client can't rotate a texture.
---------------------------------------------------------------------------
local canRotate
function Kit.CanRotate(tex)
    if canRotate == nil and tex then
        canRotate = pcall(tex.SetTexCoord, tex, 0, 0, 0, 1, 1, 0, 1, 1) and true or false
    end
    return canRotate ~= false
end

function Kit.LineMode()
    local m = ns.db and ns.db.sketchLines
    if m == "dots" or not Kit.CanRotate() then return "dots" end
    return "lines"
end

local canvases = setmetatable({}, { __mode = "k" })
function Kit.SetLineMode(mode)
    ns.db.sketchLines = mode
    for c in pairs(canvases) do c:Redraw() end
end

---------------------------------------------------------------------------
-- The canvas
---------------------------------------------------------------------------
local Canvas = {}
Canvas.__index = Canvas
Kit.Canvas = Canvas

-- opts: size (shown size, default 256), owner (whose strokes this client
-- draws), onEvent(event, key) for local changes: "draw" (points added to
-- key), "end" (stroke finished), "erase" (key removed), "clear", "undo".
function Kit.NewCanvas(parent, opts)
    opts = opts or {}
    local size = opts.size or Kit.SPACE
    local f = ns.CreateFrame("Frame", nil, parent)
    f:SetWidth(size); f:SetHeight(size)
    local C = setmetatable({ frame = f, k = size / Kit.SPACE, strokes = {}, order = {}, pool = {}, used = 0,
        owner = opts.owner or "me", onEvent = opts.onEvent, count = 0, color = 1, size = 2, tool = "pen" }, Canvas)
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints(f)
    paper:SetTexture(Kit.PAPER[1], Kit.PAPER[2], Kit.PAPER[3], 1)
    C.paper = paper
    Kit.CanRotate(paper)                 -- (a client that refuses eight coordinates gets dots)
    paper:SetTexCoord(0, 1, 0, 1)
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function() C:Press(arg1) end)
    f:SetScript("OnMouseUp", function() C:Release() end)
    f:SetScript("OnUpdate", function() if C.down then C:Move() end end)
    f:SetScript("OnHide", function() C:Release() end)
    canvases[C] = true
    return C
end

local function Take(C, path)
    local t = table.remove(C.pool)
    if not t then t = C.frame:CreateTexture(nil, "ARTWORK") end
    t:SetTexture(path)
    t:ClearAllPoints()
    t:Show()
    C.used = C.used + 1
    return t
end

local function Release(C, st)
    for _, t in ipairs(st.tex) do
        t:Hide()
        table.insert(C.pool, t)
    end
    C.used = C.used - ns.getn(st.tex)
    st.tex = {}
end

local function Tint(t, st)
    local c = Kit.COLORS[st.color]
    t:SetVertexColor(c[1], c[2], c[3], 1)
end

local function Dot(C, st, x, y, w)
    if C.used >= Kit.MAX_TEXTURES then return end
    local t = Take(C, DOT_TEX)
    t:SetTexCoord(0, 1, 0, 1)
    local d = w * 1.1
    t:SetWidth(d); t:SetHeight(d)
    t:SetPoint("TOPLEFT", C.frame, "TOPLEFT", x - d / 2, -(y - d / 2))
    Tint(t, st)
    table.insert(st.tex, t)
end

-- One stretch of a stroke, (x1, y1) to (x2, y2), in shown pixels (y down).
local function Segment(C, st, x1, y1, x2, y2, w)
    local dx, dy = x2 - x1, y1 - y2                -- dy up, as the texture math wants
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 0.5 then return end
    if C.mode == "dots" then
        local step = math.max(1, w * 0.35)
        local t = step
        while t < l do
            Dot(C, st, x1 + (x2 - x1) * t / l, y1 + (y2 - y1) * t / l, w)
            t = t + step
        end
        return
    end
    if C.used >= Kit.MAX_TEXTURES then return end
    -- the bar texture, turned to lie along the segment: an upright box
    -- around it, with each corner told which spot of the texture it shows
    local c, s = dx / l, dy / l
    local L, Wd = l / (1 - 2 * MARGIN), w / BAND
    local hw = (L * math.abs(c) + Wd * math.abs(s)) / 2
    local hh = (L * math.abs(s) + Wd * math.abs(c)) / 2
    local function U(px, py) return 0.5 + (px * c + py * s) / L end
    local function V(px, py) return 0.5 - (py * c - px * s) / Wd end
    local t = Take(C, LINE_TEX)
    t:SetTexCoord(U(-hw, hh), V(-hw, hh), U(-hw, -hh), V(-hw, -hh), U(hw, hh), V(hw, hh), U(hw, -hh), V(hw, -hh))
    t:SetWidth(hw * 2); t:SetHeight(hh * 2)
    t:SetPoint("TOPLEFT", C.frame, "TOPLEFT", (x1 + x2) / 2 - hw, -((y1 + y2) / 2 - hh))
    Tint(t, st)
    table.insert(st.tex, t)
end

-- Draw points from..n of a stroke (already in st.pts).
local function DrawFrom(C, st, from)
    local k = C.k
    local w = Kit.SIZES[st.size] * k
    local p = st.pts
    for i = from, st.n do
        local x, y = p[i * 2 - 1] * k, p[i * 2] * k
        if i > 1 then Segment(C, st, p[i * 2 - 3] * k, p[i * 2 - 2] * k, x, y, w) end
        Dot(C, st, x, y, w)
    end
end

function Canvas:Stroke(key) return self.strokes[key] end

-- Points for stroke key (created with this style if new), starting at
-- point number seq. Repeats are skipped, so a stroke sent again is harmless.
function Canvas:AddPoints(key, style, seq, flat)
    self.mode = self.mode or Kit.LineMode()
    local st = self.strokes[key]
    if not st then
        local color, size = Kit.ParseStyle(style)
        st = { key = key, style = style, color = color, size = size, pts = {}, n = 0, tex = {}, sent = 0 }
        self.strokes[key] = st
        table.insert(self.order, st)
    end
    local before = st.n
    for i = 1, math.floor(ns.getn(flat) / 2) do
        if seq + i - 1 > st.n then
            st.n = st.n + 1
            st.pts[st.n * 2 - 1], st.pts[st.n * 2] = flat[i * 2 - 1], flat[i * 2]
        end
    end
    if st.n > before then DrawFrom(self, st, before + 1) end
    return st
end

function Canvas:Remove(key)
    local st = self.strokes[key]
    if not st then return false end
    Release(self, st)
    self.strokes[key] = nil
    for i, s in ipairs(self.order) do
        if s == st then table.remove(self.order, i) break end
    end
    return true
end

function Canvas:Clear()
    for _, st in ipairs(self.order) do Release(self, st) end
    self.strokes, self.order = {}, {}
    self:Release()
end

-- Draw everything again (the line mode changed).
function Canvas:Redraw()
    self.mode = Kit.LineMode()
    for _, st in ipairs(self.order) do
        Release(self, st)
        DrawFrom(self, st, 1)
    end
end

-- The strokes owned by name, oldest first.
function Canvas:Owned(name)
    local out = {}
    for _, st in ipairs(self.order) do
        if string.sub(st.key, 1, string.len(name) + 1) == name .. ":" then table.insert(out, st) end
    end
    return out
end

-- The newest stroke with a point within r of (x, y), or nil.
function Canvas:StrokeAt(x, y, r)
    for i = ns.getn(self.order), 1, -1 do
        local st = self.order[i]
        local reach = r + Kit.SIZES[st.size] / 2
        local p = st.pts
        for j = 1, st.n do
            -- the distance to the stretch from point j - 1 to point j
            local ax, ay = p[j * 2 - 1], p[j * 2]
            local bx, by = ax, ay
            if j > 1 then bx, by = p[j * 2 - 3], p[j * 2 - 2] end
            local vx, vy = bx - ax, by - ay
            local len2 = vx * vx + vy * vy
            local t = 0
            if len2 > 0 then t = math.max(0, math.min(1, ((x - ax) * vx + (y - ay) * vy) / len2)) end
            local dx, dy = ax + vx * t - x, ay + vy * t - y
            if dx * dx + dy * dy <= reach * reach then return st end
        end
    end
end

local function Emit(C, event, key) if C.onEvent then C.onEvent(event, key) end end

-- Undo: the owner's newest stroke goes.
function Canvas:Undo()
    local mine = self:Owned(self.owner)
    local st = mine[ns.getn(mine)]
    if not st then return end
    self:Remove(st.key)
    Emit(self, "erase", st.key)
end

function Canvas:Wipe()
    self:Clear()
    Emit(self, "clear")
end

---------------------------------------------------------------------------
-- Drawing with the mouse (when SetDrawing(true)): left button draws with
-- the pen (or erases, with the eraser picked), right button always erases.
---------------------------------------------------------------------------
function Canvas:SetDrawing(on)
    self.drawing = on and true or nil
    if not on then self:Release() end
end

function Canvas:SetStyle(color, size)
    if color then self.color = color end
    if size then self.size = size end
end

function Canvas:SetTool(tool) self.tool = tool end

-- The mouse in drawing space, kept inside the edge.
function Canvas:Cursor()
    local f = self.frame
    local x, y = GetCursorPosition()
    local s = f:GetEffectiveScale()
    local left, top = f:GetLeft() or 0, f:GetTop() or 0
    x, y = (x / s - left) / self.k, (top - y / s) / self.k
    local r = math.ceil(Kit.SIZES[self.size] / 2) + 1
    x = math.floor(math.max(r, math.min(Kit.SPACE - 1 - r, x)) + 0.5)
    y = math.floor(math.max(r, math.min(Kit.SPACE - 1 - r, y)) + 0.5)
    return x, y
end

local function EraseAt(C, x, y)
    local st = C:StrokeAt(x, y, 5)
    if st then
        C:Remove(st.key)
        Emit(C, "erase", st.key)
    end
end

function Canvas:Press(button)
    if not self.drawing then return end
    local x, y = self:Cursor()
    if button == "RightButton" or self.tool == "eraser" then
        self.down = "erase"
        EraseAt(self, x, y)
        return
    end
    self.count = self.count + 1
    self.down = self.owner .. ":" .. self.count
    self.lastX, self.lastY = x, y
    self:AddPoints(self.down, Kit.StyleChar(self.color, self.size), 1, { x, y })
    Emit(self, "draw", self.down)
end

function Canvas:Move()
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("RightButton") then
        self:Release()
        return
    end
    local x, y = self:Cursor()
    if self.down == "erase" then
        EraseAt(self, x, y)
        return
    end
    local st = self.strokes[self.down]
    if not st then self.down = nil return end
    local dx, dy = x - self.lastX, y - self.lastY
    local gap = math.max(2, Kit.SIZES[st.size] * 0.5)
    if dx * dx + dy * dy < gap * gap then return end
    self.lastX, self.lastY = x, y
    self:AddPoints(st.key, st.style, st.n + 1, { x, y })
    Emit(self, "draw", st.key)
end

function Canvas:Release()
    local key = self.down
    self.down = nil
    if key and key ~= "erase" then Emit(self, "end", key) end
end

-- A drawing for checking how lines look: a star, a ring and some scribbles
-- in every color and size (as the canvas owner's strokes).
function Canvas:TestPattern()
    local n = 0
    local function Add(color, size, pts)
        n = n + 1
        self.count = self.count + 1
        local key = self.owner .. ":" .. self.count
        self:AddPoints(key, Kit.StyleChar(color, size), 1, pts)
        Emit(self, "draw", key)
        Emit(self, "end", key)
    end
    local star = {}
    for i = 0, 5 do
        local a = math.pi / 2 + i * 4 * math.pi / 5
        table.insert(star, math.floor(80 + 56 * math.cos(a) + 0.5))
        table.insert(star, math.floor(84 - 56 * math.sin(a) + 0.5))
    end
    Add(1, 2, star)
    local ring = {}
    for i = 0, 36 do
        local a = i * math.pi / 18
        table.insert(ring, math.floor(184 + 44 * math.cos(a) + 0.5))
        table.insert(ring, math.floor(84 + 44 * math.sin(a) + 0.5))
    end
    Add(8, 3, ring)
    for c = 1, ns.getn(Kit.COLORS) do
        local wave = {}
        for i = 0, 20 do
            table.insert(wave, 20 + i * 11)
            table.insert(wave, math.floor(150 + (c - 1) * 10 + 5 * math.sin(i * 0.9 + c) + 0.5))
        end
        Add(c, ns.Mod(c - 1, 4) + 1, wave)
    end
    Add(4, 4, { 30, 245, 120, 238, 226, 246 })
    return n
end

---------------------------------------------------------------------------
-- The tools bar: colors, brush sizes, eraser, Undo and Clear (256 wide, two
-- rows). opts.width (default 256). Returns a frame with :Refresh().
---------------------------------------------------------------------------
local SWATCH = 22

local function Swatch(parent, onClick)
    local b = ns.CreateFrame("Button", nil, parent)
    b:SetWidth(SWATCH); b:SetHeight(SWATCH)
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(b)
    edge:SetTexture(0.15, 0.12, 0.08, 1)
    b.edge = edge
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    b.fill = fill
    b:SetScript("OnClick", function() onClick() end)
    return b
end

local function Mark(b, on)
    if on then b.edge:SetTexture(1, 0.82, 0, 1) else b.edge:SetTexture(0.15, 0.12, 0.08, 1) end
end

function Kit.NewTools(parent, C, opts)
    opts = opts or {}
    local f = ns.CreateFrame("Frame", nil, parent)
    f:SetWidth(opts.width or 256); f:SetHeight(2 * SWATCH + 6)
    f.colors, f.sizes = {}, {}
    for i = 1, ns.getn(Kit.COLORS) do
        local i = i   -- own copy for closures (Lua 5.0)
        local b = Swatch(f, function()
            C:SetStyle(i)
            C:SetTool("pen")
            ns:Sound("IG_MAINMENU_OPTION")
            f:Refresh()
        end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (SWATCH + 2), 0)
        local c = Kit.COLORS[i]
        b.fill:SetTexture(c[1], c[2], c[3], 1)
        f.colors[i] = b
    end
    for i = 1, ns.getn(Kit.SIZES) do
        local i = i
        local b = Swatch(f, function()
            C:SetStyle(nil, i)
            if C.tool == "eraser" then C:SetTool("pen") end
            ns:Sound("IG_MAINMENU_OPTION")
            f:Refresh()
        end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (SWATCH + 2), -(SWATCH + 4))
        b.fill:SetTexture(Kit.PAPER[1], Kit.PAPER[2], Kit.PAPER[3], 1)
        local dot = b:CreateTexture(nil, "OVERLAY")
        dot:SetTexture(DOT_TEX)
        local d = math.min(SWATCH - 6, Kit.SIZES[i] + 1)
        dot:SetWidth(d); dot:SetHeight(d)
        dot:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.dot = dot
        f.sizes[i] = b
    end
    local x = ns.getn(Kit.SIZES) * (SWATCH + 2) + 4
    f.eraser = ns.UI.Button(f, "Eraser", 58, function()
        C:SetTool(C.tool == "eraser" and "pen" or "eraser")
        ns:Sound("IG_MAINMENU_OPTION")
        f:Refresh()
    end)
    f.eraser:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(SWATCH + 4))
    f.undo = ns.UI.Button(f, "Undo", 50, function() C:Undo() end)
    f.undo:SetPoint("LEFT", f.eraser, "RIGHT", 2, 0)
    local clear
    clear = ns.UI.Button(f, "Clear", 50, function()
        -- twice within 3 seconds, so a stray click keeps the drawing
        if rawget(clear, "armed") and GetTime() - clear.armed <= 3 then
            clear.armed = nil
            C:Wipe()
        else
            clear.armed = GetTime()
        end
        f:Refresh()
    end)
    clear:SetPoint("LEFT", f.undo, "RIGHT", 2, 0)
    f.clear = clear
    function f:Refresh()
        for i, b in ipairs(self.colors) do Mark(b, C.tool ~= "eraser" and C.color == i) end
        local col = Kit.COLORS[C.color]
        for i, b in ipairs(self.sizes) do
            Mark(b, C.size == i)
            b.dot:SetVertexColor(col[1], col[2], col[3], 1)
        end
        self.eraser:SetText(C.tool == "eraser" and "|cffffd100Eraser|r" or "Eraser")
        local armed = rawget(clear, "armed")
        if armed and GetTime() - armed > 3 then clear.armed, armed = nil, nil end
        clear:SetText(armed and "Sure?" or "Clear")
        ns.SetEnabled(self.undo, ns.getn(C:Owned(C.owner)) > 0)
    end
    f:Refresh()
    return f
end

---------------------------------------------------------------------------
-- Keeping a drawing in step across the group
---------------------------------------------------------------------------
local Sync = {}
Sync.__index = Sync
Kit.Sync = Sync

local FLUSH = 0.4        -- seconds between sends of new points
local CHUNK = 55         -- points per message
local RESEND_GAP = 3     -- seconds between answering "send it again"

-- spec: tag (the game's message tag), canvas, me (default Net:Me()).
-- The canvas's local changes go out by themselves.
function Kit.NewSync(spec)
    local s = setmetatable({ tag = spec.tag, canvas = spec.canvas, me = spec.me or Net:Me(), artists = {},
        ctx = nil, flushed = 0, answered = -100 }, Sync)
    local C = spec.canvas
    C.owner = s.me
    local chain = C.onEvent
    C.onEvent = function(event, key)
        s:Local(event, key)
        if chain then chain(event, key) end
    end
    return s
end

function Sync:Send(parts) Net:Send(self.tag .. ";" .. table.concat(parts, ";")) end

function Sync:IsArtist(name) return self.artists[name] == true end

-- A new drawing: an empty canvas, and who may draw on it.
function Sync:Begin(ctx, artists)
    self.ctx = ctx
    self.artists = artists or {}
    self.canvas:Clear()
    self.canvas.count = 0
end

function Sync:Local(event, key)
    if not self.ctx or not self:IsArtist(self.me) then return end
    if event == "end" then
        self:Flush()
    elseif event == "erase" then
        local owner, n = self:Split(key)
        self:Send({ "E", self.ctx, owner, n })
    elseif event == "clear" then
        self:Send({ "C", self.ctx })
    end
end

function Sync:Split(key)
    local _, _, owner, n = string.find(key, "^(.*):(%d+)$")
    return owner or key, n or "0"
end

-- Send every point of our strokes that hasn't gone out yet.
function Sync:Flush()
    self.flushed = GetTime()
    if not self.ctx or not self:IsArtist(self.me) then return end
    for _, st in ipairs(self.canvas:Owned(self.me)) do
        while st.sent < st.n do
            local first = st.sent + 1
            local last = math.min(st.n, st.sent + CHUNK)
            local _, n = self:Split(st.key)
            self:Send({ "D", self.ctx, self.me, n, st.style, first, Kit.EncodePoints(st.pts, first, last) })
            st.sent = last
        end
    end
end

function Sync:Tick()
    if self.ctx and GetTime() - self.flushed >= FLUSH then self:Flush() end
end

-- Ask the artists for the whole drawing (joining partway through).
function Sync:Request()
    if self.ctx then self:Send({ "N", self.ctx }) end
end

-- A message for this drawing? Handles it and returns true.
function Sync:Handle(sender, f)
    local kind = f[2]
    if kind ~= "D" and kind ~= "E" and kind ~= "C" and kind ~= "N" then return false end
    if f[3] ~= self.ctx or not self.ctx then return true end
    local C = self.canvas
    if kind == "N" then
        if self:IsArtist(self.me) and GetTime() - self.answered >= RESEND_GAP then
            self.answered = GetTime()
            for _, st in ipairs(C:Owned(self.me)) do st.sent = 0 end
            self:Flush()
        end
        return true
    end
    if not self:IsArtist(sender) then return true end
    if kind == "C" then
        C:Clear()
    elseif kind == "E" then
        C:Remove((f[4] or "") .. ":" .. (f[5] or ""))
    elseif f[4] == sender then
        local key = sender .. ":" .. (f[5] or "0")
        C:AddPoints(key, f[6], tonumber(f[7]) or 1, Kit.DecodePoints(f[8]))
    end
    return true
end
