-- Shared test helpers. A test file does
--   local H = dofile("harness.lua")
-- and then uses H.Check, H.Start, H.Find, H.Press and H.Tick (or local
-- copies of them), and ends with H.Done("NAME").
local ADDON = arg[1]
local base = _G
local H = { ok = true, width = 66 }

-- One line per check: name, PASS or FAIL, and anything extra to show.
function H.Check(name, cond, extra)
  io.write(string.format("%-" .. H.width .. "s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  H.ok = H.ok and cond and true or false
  return cond
end

-- Prints the verdict and exits with its code.
function H.Done(label)
  io.write(label .. (H.ok and " PASS\n" or " FAIL\n"))
  os.exit(H.ok and 0 or 1)
end

-- A fresh client in its own environment: the mock (MOCK, default the 1.12
-- one) with the addon loaded, `saved` as its saved variables, then
-- ADDON_LOADED. setup(env) runs before ADDON_LOADED (to fake a party, say),
-- prep(ns) just after it.
function H.Start(saved, prep, setup)
  local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
  env.arg = { ADDON }; env.SELECT_SAVED = select
  assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
  if setup then setup(env) end
  env.CowCasinoDB = saved
  for _, o in ipairs(env.all) do
    if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end
  end
  if prep then prep(env.CowCasino.ns) end
  env.CowCasinoFrame:Show()
  if not H.env then H.Use(env) end
  return env, env.CowCasino.ns
end

-- Find, Press and Tick work on this client (the first one started, unless
-- changed here).
function H.Use(env) H.env, H.ns = env, env.CowCasino.ns end

-- Shown all the way up, and inside H.panel when one is set.
function H.Visible(o)
  local inPanel = H.panel == nil
  while o do
    if not o.shown then return false end
    if o == H.panel then inPanel = true end
    o = o.parent
  end
  return inPanel
end

-- A visible button with this text (or starting with it, with prefix set).
function H.Find(text, prefix)
  for _, o in ipairs(H.env.all) do
    if o.kind == "Button" and H.Visible(o) and type(o.text) == "string"
      and (o.text == text or (prefix and string.sub(o.text, 1, string.len(text)) == text)) then return o end
  end
end

function H.Press(text, prefix)
  local b = H.Find(text, prefix)
  assert(b, "no button " .. text)
  assert(b.enabled, "disabled " .. text)
  H.env.Fire(b, "OnClick", "LeftButton")
end

-- Runs the clock forward, firing OnUpdate on every visible frame.
function H.Tick(sec)
  local env = H.env
  for _ = 1, math.floor(sec * 10 + 0.5) do
    env.CLOCK = env.CLOCK + 0.1
    for _, o in ipairs(env.all) do if o.scripts.OnUpdate and H.Visible(o) then env.Fire(o, "OnUpdate", 0.1) end end
  end
end

---------------------------------------------------------------------------
-- Party play: isolated clients talking over a simulated party channel.
-- opts: game (the key to open), button (pressed after opening, such as
-- "Party play"), object(ns) (the party game, its table at .T), prep(ns)
-- (before the game opens), onPart(name, part) (sees every message part
-- sent), dealer (also tick the dealer's frame), chips (each wallet,
-- default 5,000).
-- Returns the party: clock, group (names in join order), wire, stats,
-- clients, byName, onTick, and InGroup, Others, NewClient(name, saved),
-- Deliver, GroupChanged, Tick(dt) and Run(seconds).
---------------------------------------------------------------------------
function H.Party(opts)
  local P = { clock = 0, group = {}, wire = {}, stats = { sent = 0, longest = 0, chars = 0, parts = 0 }, clients = {}, byName = {} }
  local wire, stats = P.wire, P.stats   -- (P.group may be replaced: a new party)

  function P.InGroup(name)
    for _, n in ipairs(P.group) do if n == name then return true end end
    return false
  end
  function P.Others(name)
    local out = {}
    for _, n in ipairs(P.group) do if n ~= name then table.insert(out, n) end end
    return out
  end

  -- Messages may be packed together, joined by "~" (chat always goes alone).
  local function Parts(text)
    if string.sub(text, 1, 3) == "CH;" then return { text } end
    local parts, start = {}, 1
    while true do
      local i = string.find(text, "~", start, true)
      if not i then table.insert(parts, string.sub(text, start)) return parts end
      table.insert(parts, string.sub(text, start, i - 1)); start = i + 1
    end
  end

  function P.NewClient(name, saved)
    local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
    env.arg = { ADDON }
    env.PLAYER_NAME = name
    env.SELECT_SAVED = select
    assert(loadfile((os.getenv("MOCK") or "mock112.lua"), "t", env))()
    env.GetTime = function() return P.clock end
    -- more than five in P.group makes it a raid
    local function Raid() return P.InGroup(name) and table.getn(P.group) > 5 end
    env.UnitName = function(u)
      if u == "player" then return name end
      local _, _, r = string.find(u, "^raid(%d+)$")
      if r then return Raid() and P.group[tonumber(r)] or nil end
      local _, _, n = string.find(u, "^party(%d)$")
      if n and P.InGroup(name) and not Raid() then return P.Others(name)[tonumber(n)] end
      return nil
    end
    env.GetNumPartyMembers = function()
      if P.InGroup(name) and not Raid() and table.getn(P.group) > 1 then return table.getn(P.group) - 1 end
      return 0
    end
    env.GetNumRaidMembers = function() return Raid() and table.getn(P.group) or 0 end
    env.IsInRaid = function() return Raid() end
    env.GetNumGroupMembers = function()
      if Raid() then return table.getn(P.group) end
      local n = env.GetNumPartyMembers()
      return n > 0 and n + 1 or 0
    end
    env.SendAddonMessage = function(prefix, text, chan)
      assert(type(text) == "string" and (chan == (Raid() and "RAID" or "PARTY")), "bad addon message channel: " .. tostring(chan))
      local len = string.len(prefix) + string.len(text)
      assert(len <= 254, "addon message too long (" .. len .. "): " .. text)
      stats.sent = stats.sent + 1
      stats.chars = stats.chars + len
      if len > stats.longest then stats.longest = len end
      table.insert(wire, { from = name, prefix = prefix, text = text, chan = chan })
      local parts = Parts(text)
      stats.parts = stats.parts + table.getn(parts)
      if opts.onPart then for _, part in ipairs(parts) do opts.onPart(name, part) end end
    end
    env.CowCasinoDB = saved
    for _, o in ipairs(env.all) do
      if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end
    end
    local ns = env.CowCasino.ns
    ns.db.chips = opts.chips or 5000
    env.CowCasinoFrame:Show()
    if opts.prep then opts.prep(ns) end
    ns:OpenGame(opts.game)
    if opts.button then
      for _, o in ipairs(env.all) do
        if o.kind == "Button" and o.text == opts.button then env.Fire(o, "OnClick", "LeftButton") end
      end
    end
    local c = { name = name, env = env, ns = ns, P = opts.object(ns) }
    c.T = c.P.T
    c.updaters = {}
    for _, o in ipairs(env.all) do
      if not o.parent and o.scripts.OnUpdate then table.insert(c.updaters, o) end
    end
    if opts.dealer and ns.Dealer.UI() then table.insert(c.updaters, ns.Dealer.UI()) end
    table.insert(P.clients, c)
    P.byName[name] = c
    return c
  end

  function P.Deliver()
    while wire[1] do
      local m = table.remove(wire, 1)
      if P.InGroup(m.from) then
        for _, c in ipairs(P.clients) do
          if P.InGroup(c.name) and c.env.PrefixHeard(m.prefix) then   -- the modern client only delivers registered prefixes
            for _, o in ipairs(c.env.all) do
              if rawget(o, "events") and o.events.CHAT_MSG_ADDON then
                c.env.Fire(o, "OnEvent", m.prefix, "CHAT_MSG_ADDON", m.text, m.chan, m.from .. c.env.REALM_SUFFIX)
              end
            end
          end
        end
      end
    end
  end

  function P.GroupChanged()
    for _, c in ipairs(P.clients) do
      for _, o in ipairs(c.env.all) do
        if rawget(o, "events") and o.events[c.env.ROSTER_EVENT] then c.env.Fire(o, "OnEvent", nil, c.env.ROSTER_EVENT) end
      end
    end
  end

  function P.Tick(dt)
    dt = dt or 0.1
    P.clock = P.clock + dt
    for _, c in ipairs(P.clients) do
      for _, o in ipairs(c.updaters) do
        if o.shown and o.scripts.OnUpdate then c.env.Fire(o, "OnUpdate", dt) end
      end
    end
    P.Deliver()
    if P.onTick then P.onTick() end
  end
  function P.Run(seconds) for _ = 1, math.floor(seconds * 10 + 0.5) do P.Tick(0.1) end end

  return P
end

return H
