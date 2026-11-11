-- 3D portraits close up on the face, even when the model loads late.
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
env.GetNumPartyMembers = function() return 1 end
env.UnitName = function(u) if u == "player" then return "Host" elseif u == "party1" then return "Bob" end end
local ns = env.CowCasino.ns
local function Visible(o) while o do if not o.shown then return false end; o = o.parent end; return true end
local function Tick(sec)
  for _ = 1, math.floor(sec * 20 + 0.5) do
    env.CLOCK = env.CLOCK + 0.05
    for _, o in ipairs(env.all) do if o.scripts.OnUpdate and Visible(o) then env.Fire(o, "OnUpdate", 0.05) end end
  end
end
-- A model that, like the game, ignores the camera until it has loaded.
local LOAD_TIME = 0.33
local function Slow(m)
  local setUnit, setCamera = m.SetUnit, m.SetCamera
  m.cameraCalls = 0
  m.SetUnit = function(self, u) setUnit(self, u); self.loadedAt = env.CLOCK + LOAD_TIME; self.shownCamera = "full body" end
  m.SetCamera = function(self, c)
    self.cameraCalls = self.cameraCalls + 1
    setCamera(self, c)
    if self.loadedAt and env.CLOCK >= self.loadedAt then self.shownCamera = c end
  end
end
local parent = env.CreateFrame("Frame", nil, env.CowCasinoFrame)
local p = ns:CreatePortrait(parent, 60, 60)
Slow(p)
p:ShowUnit("player")
Check("right after choosing the model it's still loading (full body)", p.shownCamera == "full body")
Tick(1)
Check("once it loads, the portrait is on the face camera", p.shownCamera == 0, tostring(p.shownCamera))
Tick(1)                       -- past the settle time
local calls = p.cameraCalls
Tick(1)
Check("it stops re-setting the camera every frame after a moment", p.cameraCalls - calls <= 1, p.cameraCalls - calls)
Tick(2.1)
Check("the two-second recheck sets it again (in case the game reset it)", p.cameraCalls > calls)
-- out of range: question mark, no face camera
env.UNIT_VISIBLE = env.UNIT_VISIBLE or {}
local q = ns:CreatePortrait(parent, 60, 60)
Slow(q)
env.UNIT_VISIBLE.party1 = false
q:ShowUnit("party1")
local before = q.cameraCalls
Tick(2)
Check("out of range: the question mark, no face camera on it", q.model and string.find(q.model, "questionmark", 1, true) and q.cameraCalls == before)
env.UNIT_VISIBLE.party1 = nil
Tick(2.1)
Tick(1)
Check("they come into range: their face, once the model loads", q.unit == "party1" and q.shownCamera == 0, tostring(q.shownCamera))
-- the games' portraits: Blackjack's seat portrait
ns:OpenGame("blackjack")
local found
for _, o in ipairs(env.all) do if o.kind == "PlayerModel" and o.unit == "player" and Visible(o) then found = o end end
Tick(2)
Check("Blackjack's portrait uses the face camera", found and found.camera == 0)
-- hidden and shown again: chosen again with the face camera
p:Hide(); Slow(p); p:Show()
Tick(1)
Check("hidden and shown again: back on the face", p.shownCamera == 0, tostring(p.shownCamera))
io.write(ok and "PORTRAITS PASS\n" or "PORTRAITS FAIL\n")
os.exit(ok and 0 or 1)
