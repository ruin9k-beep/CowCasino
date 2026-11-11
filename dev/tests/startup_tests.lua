-- Startup with saved data: the user's real CowCasino save, then drag + restart.
local ADDON, SAVED = arg[1], arg[2]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-60s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. extra) or ""))
  ok = ok and cond and true or false
end
local function Start(savedDB)
  local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
  env.arg = { ADDON }
  env.SELECT_SAVED = select
  assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
  env.CowCasinoDB = savedDB          -- SavedVariables arrive before ADDON_LOADED
  local okLoad, err = pcall(function()
    for _, o in ipairs(env.all) do
      if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end
    end
  end)
  return env, okLoad, err
end
local function Rows(env)
  local n = 0
  for _, o in ipairs(env.all) do if o.kind == "Button" and rawget(o, "menuPage") ~= nil and o.parent and o.parent.parent == env.CowCasinoFrame.menu then n = n + 1 end end
  return n
end

-- 1) The user's actual save file, with its window position emptied (the
-- state that once broke the window on 1.12).
local saved = {}
assert(loadfile(SAVED, "t", saved))()
local pach = saved.CowCasinoDB.pachinko or {}
local wantChips = math.floor(saved.CowCasinoDB.chips + 0.5) + (pach.tray or 0) + (pach.inFlight or 0)   -- half chips round; pachinko balls are cashed in
local wantHands = saved.CowCasinoDB.holdem and saved.CowCasinoDB.holdem.stats and saved.CowCasinoDB.holdem.stats.hands
saved.CowCasinoDB.point = {}
local env, okLoad, err = Start(saved.CowCasinoDB)
Check("startup with your saved data: no error", okLoad, err and tostring(err))
Check("menu has every game", okLoad and Rows(env) == table.getn(env.CowCasino.ns.gameOrder) and Rows(env) >= 9, okLoad and (Rows(env) .. " rows") or "")
Check("minimap button exists", okLoad and env.CowCasinoMinimapButton ~= nil)
Check("empty saved position reset to the center", okLoad and env.CowCasinoDB.point[1] == "CENTER")
Check("chips (plus cashed-in pachinko balls) and stats kept", okLoad and env.CowCasinoDB.chips == wantChips and env.CowCasinoDB.holdem.stats.hands == wantHands)

-- 2) Drag the window, then restart with what was saved.
local f = env.CowCasinoFrame
env.Fire(f, "OnDragStart"); env.Fire(f, "OnDragStop")
local p = env.CowCasinoDB.point
Check("drag saves a real position", p[1] == "TOPLEFT" and p[2] == "BOTTOMLEFT" and p[3] == 412.5 and p[4] == 655,
  tostring(p[1]) .. " " .. tostring(p[3]) .. "," .. tostring(p[4]))
local env2, ok2, err2 = Start(env.CowCasinoDB)
local a = ok2 and env2.CowCasinoFrame.anchor
Check("restart after a drag: window where you left it", ok2 and a and a[1] == "TOPLEFT" and a[4] == 412.5 and a[5] == 655, err2 and tostring(err2))
Check("restart after a drag: menu and minimap intact", ok2 and Rows(env2) == table.getn(env2.CowCasino.ns.gameOrder) and env2.CowCasinoMinimapButton ~= nil)

-- 3) /casino reset still works.
env2.SlashCmdList.COWCASINO("reset")
Check("/casino reset centers the window", env2.CowCasinoDB.point[1] == "CENTER" and env2.CowCasinoFrame.anchor[1] == "CENTER")
io.write(ok and "STARTUP PASS\n" or "STARTUP FAIL\n")
