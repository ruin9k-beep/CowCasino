-- WoW Forever: addon messages within the modern client's per-prefix limit.
local ADDON = arg[1]
local base = _G
local ok = true
local function Check(name, cond, extra)
  io.write(string.format("%-66s %s%s\n", name, cond and "PASS" or "FAIL", extra and ("  " .. tostring(extra)) or ""))
  ok = ok and cond and true or false
end
local CLOCK = 0
local env = setmetatable({}, { __index = function(t, k) if k == "select" or k == "print" then return nil end return base[k] end })
env.arg = { ADDON }; env.SELECT_SAVED = select
assert(loadfile("mockretail.lua", "t", env))()
env.GetTime = function() return CLOCK end
env.GetNumPartyMembers = function() return 1 end
env.UnitName = function(u) if u == "player" then return "Host" elseif u == "party1" then return "Bob" end end
local sent, parts = {}, {}
env.SendAddonMessage = function(p, text, chan, logged)
  table.insert(sent, { p = p, text = text, logged = logged, at = CLOCK })
  if string.sub(text, 1, 3) == "CH;" then table.insert(parts, text) else
    local start = 1
    while true do
      local i = string.find(text, "~", start, true)
      if not i then table.insert(parts, string.sub(text, start)) break end
      table.insert(parts, string.sub(text, start, i - 1)); start = i + 1
    end
  end
end
local printed = {}
env.DEFAULT_CHAT_FRAME.AddMessage = function(self, m) table.insert(printed, m) end
for _, o in ipairs(env.all) do if o.scripts.OnEvent and rawget(o, "events") and o.events.ADDON_LOADED then env.Fire(o, "OnEvent", "CowCasino", "ADDON_LOADED") end end
local ns = env.CowCasino.ns
local Net = ns.Net
local function Tick(sec)
  for _ = 1, math.floor(sec * 20 + 0.5) do
    CLOCK = CLOCK + 0.05
    for _, o in ipairs(env.all) do if o.shown and o.scripts.OnUpdate and not o.parent then env.Fire(o, "OnUpdate", 0.05) end end
  end
end
Check("8 prefixes registered", env.C_ChatInfo.IsAddonMessagePrefixRegistered("CowCasino") and env.C_ChatInfo.IsAddonMessagePrefixRegistered("CowCasino8"))
for i = 1, 100 do Net:Send("T;" .. i .. ";" .. string.rep("x", 30)) end
Tick(30)
local inOrder = true
for i = 1, 100 do if parts[i] ~= "T;" .. i .. ";" .. string.rep("x", 30) then inOrder = false end end
Check("100 game messages sent at once all arrive, in order", table.getn(parts) == 100 and inOrder, table.getn(parts))
Check("...packed into far fewer addon messages", table.getn(sent) <= 20, table.getn(sent) .. " addon messages")
local longest = 0
for _, m in ipairs(sent) do longest = math.max(longest, string.len(m.p) + string.len(m.text)) end
Check("...each within the size limit", longest <= 254, longest)
Check("the game dropped none of them", env.THROTTLE_DROPS == 0, env.THROTTLE_DROPS)
local last = sent[table.getn(sent)].at
Check("and they're all out within Net's own pace (600 characters a second)", last < 8, string.format("%.1fs", last))
-- A flood bigger than one prefix's allowance spreads over the pool
-- (chat lines always go one per message)
sent, parts = {}, {}
for i = 1, 200 do Net:Send("CH;HE;Host;1;line " .. i) end
Tick(60)
local per = {}
for _, m in ipairs(sent) do per[m.p] = (per[m.p] or 0) + 1 end
local n = 0 for _ in pairs(per) do n = n + 1 end
local chatOrder = true
for i = 1, 200 do if not sent[i] or sent[i].text ~= "CH;HE;Host;1;line " .. i then chatOrder = false end end
Check("a flood of 200 chat lines: all sent in order, none dropped", table.getn(sent) == 200 and chatOrder and env.THROTTLE_DROPS == 0,
  table.getn(sent) .. " sent")
Check("...spread over all 8 prefixes", n == 8, n)
Check("nothing left waiting", Net:Queued() == 0)
-- Steady traffic for a minute: a message every 0.2s
sent, parts = {}, {}
for s = 1, 300 do Net:Send("S;" .. s); Tick(0.2) end
Tick(5)
Check("steady 5 a second for a minute: none dropped, none lost", table.getn(parts) == 300 and env.THROTTLE_DROPS == 0, table.getn(parts))
-- Receiving on a pool prefix
local got
Net.handlers["ZZ"] = function(sender, f) got = sender .. ":" .. f[2] end
for _, o in ipairs(env.all) do
  if rawget(o, "events") and o.events.CHAT_MSG_ADDON then env.Fire(o, "OnEvent", "CowCasino5", "CHAT_MSG_ADDON", "ZZ;hi", "PARTY", "Bob-Nordanaar") end
end
Check("messages on any pool prefix reach the addon", got == "Bob:hi", got)
got = nil
for _, o in ipairs(env.all) do
  if rawget(o, "events") and o.events.CHAT_MSG_ADDON then env.Fire(o, "OnEvent", "OtherAddon", "CHAT_MSG_ADDON", "ZZ;nope", "PARTY", "Bob-Nordanaar") end
end
Check("other addons' messages are ignored", got == nil)
-- Chat goes through the logged send
sent, parts = {}, {}
Net:Send("CH;HE;Host;1;hi ~ there")
Net:Send("HE;S;state")
Net:Send("HE;A;act")
Tick(2)
Check("table chat goes alone, logged, even with a ~ in it", sent[1].logged == true and sent[1].text == "CH;HE;Host;1;hi ~ there")
Check("game messages are packed together, not logged", sent[2].logged == false and sent[2].text == "HE;S;state~HE;A;act")
-- Receiving a packed message: each part handled, in order
local seen = {}
Net.handlers["YY"] = function(sender, f) table.insert(seen, f[2]) end
for _, o in ipairs(env.all) do
  if rawget(o, "events") and o.events.CHAT_MSG_ADDON then env.Fire(o, "OnEvent", "CowCasino3", "CHAT_MSG_ADDON", "YY;1~YY;2~YY;3", "PARTY", "Bob-Nordanaar") end
end
Check("a packed message is unpacked and handled in order", table.concat(seen, ",") == "1,2,3", table.concat(seen, ","))
-- An account the game won't let send: one warning, no endless retries
local real = env.C_ChatInfo.SendAddonMessage
local calls = 0
env.C_ChatInfo.SendAddonMessage = function() calls = calls + 1; return env.Enum.SendAddonMessageResult.GeneralError end
for i = 1, 5 do Net:Send("X;" .. i) end
Tick(5)
local warns = 0
for _, m in ipairs(printed) do if string.find(m, "won't send party play messages", 1, true) then warns = warns + 1 end end
Check("refused outright: one warning, messages not retried forever", warns == 1 and calls == 1 and Net:Queued() == 0,
  calls .. " call (5 messages packed), " .. warns .. " warning")
env.C_ChatInfo.SendAddonMessage = real
io.write(ok and "NET THROTTLE PASS\n" or "NET THROTTLE FAIL\n")
os.exit(ok and 0 or 1)
