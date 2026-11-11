-- CowCasino: Craps
-- Two dice. The first roll is the come-out: 7 or 11 wins the Pass Line,
-- 2, 3 or 12 loses it, and any other total becomes the point. Then roll
-- until the point comes again (Pass wins) or a 7 shows (seven out: Pass
-- loses). Don't Pass is the other side of that bet (a 12 on the come-out is
-- a push). Odds go behind a Pass bet once there's a point and pay true odds.
-- Field, Any Seven and Any Craps are decided by the very next roll.
-- Bets on the table are saved, so a reload never loses them.
-- Party play (Games\PartyCraps.lua) uses the same rules and dice.

local ns = CowCasino.ns

local AREA_W      = 352
local MIN_BET     = 5
local MAX_BET     = 1000    -- per spot
local CHIP_VALUES = { 5, 25, 100, 500 }
local ODDS_CHOICES = { 1, 2, 3, 5, 10 }
local ROLL_TIME   = 0.8     -- seconds the dice tumble
local DOT = "Interface\\AddOns\\CowCasino\\Art\\Dot"

local DEFAULT_STATS = { rolls = 0, pointsMade = 0, sevenOuts = 0, biggestWin = 0, net = 0 }

---------------------------------------------------------------------------
-- Rules, shared with party play
---------------------------------------------------------------------------
local Rules = {}
ns.CrapsRules = Rules

-- The spots, in board order. code: one letter for party messages.
Rules.SPOTS = {
    { key = "pass",     code = "p", name = "Pass Line",  pays = "1:1" },
    { key = "odds",     code = "o", name = "Pass Odds",  pays = "true odds" },
    { key = "dontPass", code = "d", name = "Don't Pass", pays = "1:1, 12 pushes" },
    { key = "field",    code = "f", name = "Field",      pays = "2 pays 2:1, 12 pays 3:1" },
    { key = "any7",     code = "s", name = "Any Seven",  pays = "4:1" },
    { key = "anyCraps", code = "c", name = "Any Craps",  pays = "2, 3 or 12 pays 7:1" },
}
Rules.MIN_BET, Rules.MAX_BET = MIN_BET, MAX_BET

-- What Odds pay on top of the bet, for each point: 2:1, 3:2, 6:5. Odd
-- amounts round up, in the player's favor.
local ODDS_PAY = { [4] = { 2, 1 }, [10] = { 2, 1 }, [5] = { 3, 2 }, [9] = { 3, 2 }, [6] = { 6, 5 }, [8] = { 6, 5 } }

function Rules.OddsWin(point, amount)
    local r = ODDS_PAY[point]
    if not r then return 0 end
    return math.ceil(amount * r[1] / r[2])
end

local function IsCraps(total) return total == 2 or total == 3 or total == 12 end

-- Can a bet go on (or more chips onto) this spot right now?
function Rules.CanAdd(key, point, bets)
    if key == "pass" or key == "dontPass" then return point == nil end
    if key == "odds" then return point ~= nil and (bets.pass or 0) > 0 end
    return true
end

-- Can chips come back off this spot? Line bets stay once there's a point.
function Rules.CanRemove(key, point)
    if key == "pass" or key == "dontPass" then return point == nil end
    return true
end

-- Most that may go on a spot: Odds are limited to a multiple of the Pass bet.
function Rules.Limit(key, bets, oddsMax)
    if key == "odds" then return math.min(MAX_BET * 10, (bets.pass or 0) * (oddsMax or 3)) end
    return MAX_BET
end

-- Settle one roll. bets: key -> chips on the spot. Returns
--   back:  key -> chips returned (bet plus winnings, or 0 if lost) for every
--          bet decided this roll; bets not in it stay up
--   point: the point after this roll (nil = off)
--   event: "natural", "craps", "point", "made", "sevenOut" or "roll"
function Rules.Settle(bets, point, d1, d2)
    local total = d1 + d2
    local back = {}
    local function Win(key, amount) if (bets[key] or 0) > 0 then back[key] = bets[key] + amount end end
    local function Lose(key) if (bets[key] or 0) > 0 then back[key] = 0 end end

    -- one-roll bets
    if total == 2 then Win("field", bets.field and bets.field * 2 or 0)
    elseif total == 12 then Win("field", bets.field and bets.field * 3 or 0)
    elseif total == 3 or total == 4 or total == 9 or total == 10 or total == 11 then Win("field", bets.field or 0)
    else Lose("field") end
    if total == 7 then Win("any7", (bets.any7 or 0) * 4) else Lose("any7") end
    if IsCraps(total) then Win("anyCraps", (bets.anyCraps or 0) * 7) else Lose("anyCraps") end

    local event
    if point == nil then
        if total == 7 or total == 11 then
            Win("pass", bets.pass or 0); Lose("dontPass")
            event = "natural"
        elseif IsCraps(total) then
            Lose("pass")
            if total == 12 then Win("dontPass", 0) else Win("dontPass", bets.dontPass or 0) end
            event = "craps"
        else
            point = total
            event = "point"
        end
        if (bets.odds or 0) > 0 then back.odds = bets.odds end      -- no point: odds come back
    elseif total == point then
        Win("pass", bets.pass or 0)
        Win("odds", Rules.OddsWin(point, bets.odds or 0))
        Lose("dontPass")
        point, event = nil, "made"
    elseif total == 7 then
        Lose("pass"); Lose("odds")
        Win("dontPass", bets.dontPass or 0)
        point, event = nil, "sevenOut"
    else
        event = "roll"
    end
    return back, point, event
end

-- A short line about a roll, for the status bar.
function Rules.Describe(d1, d2, event, point, oldPoint)
    local total = d1 + d2
    local s = d1 .. " + " .. d2 .. " = " .. total
    if event == "natural" then return s .. ". Natural - Pass wins!" end
    if event == "craps" then return s .. ". Craps" .. (total == 12 and " - Don't Pass pushes." or ".") end
    if event == "point" then return s .. ". The point is " .. point .. "." end
    if event == "made" then return s .. ". Point made!" end
    if event == "sevenOut" then return s .. ". Seven out." end
    return s .. ". Point is still " .. (oldPoint or "?") .. "."
end

function Rules.Roll() return math.random(1, 6), math.random(1, 6) end

-- Bets packed for a message: chips per spot in board order, joined by ","
function Rules.Pack(bets)
    local out = {}
    for i, s in ipairs(Rules.SPOTS) do out[i] = tostring(bets[s.key] or 0) end
    return table.concat(out, ",")
end

function Rules.Unpack(text)
    local bets, i = {}, 1
    local parts = ns.Net.Split(text or "", ",")
    for _, s in ipairs(Rules.SPOTS) do
        local n = tonumber(parts[i] or "") or 0
        if n > 0 then bets[s.key] = n end
        i = i + 1
    end
    return bets
end

function Rules.Total(bets)
    local n = 0
    for _, v in pairs(bets) do n = n + v end
    return n
end

---------------------------------------------------------------------------
-- Dice: a pair of drawn dice that tumble when rolled. Shared with party play.
---------------------------------------------------------------------------
local PIPS = {
    [1] = { 5 }, [2] = { 1, 9 }, [3] = { 1, 5, 9 }, [4] = { 1, 3, 7, 9 },
    [5] = { 1, 3, 5, 7, 9 }, [6] = { 1, 3, 4, 6, 7, 9 },
}

local function MakeDie(parent, size)
    local d = ns.CreateFrame("Frame", nil, parent)
    d:SetWidth(size); d:SetHeight(size)
    local edge = d:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(d)
    edge:SetTexture(0.25, 0.04, 0.04, 1)
    local face = d:CreateTexture(nil, "BORDER")
    face:SetPoint("TOPLEFT", d, "TOPLEFT", 2, -2)
    face:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -2, 2)
    face:SetTexture(0.93, 0.90, 0.82, 1)
    d.pips = {}
    local pip = math.floor(size * 0.2)
    local step = size * 0.27
    for k = 1, 9 do
        local t = d:CreateTexture(nil, "ARTWORK")
        t:SetTexture(DOT)
        t:SetVertexColor(0.55, 0.06, 0.06)
        t:SetWidth(pip); t:SetHeight(pip)
        local col, row = ns.Mod(k - 1, 3) - 1, math.floor((k - 1) / 3) - 1
        t:SetPoint("CENTER", d, "CENTER", col * step, -row * step)
        t:Hide()
        d.pips[k] = t
    end
    function d:Show_(n)
        for k = 1, 9 do self.pips[k]:Hide() end
        for _, k in ipairs(PIPS[n] or {}) do self.pips[k]:Show() end
        self.value = n
    end
    return d
end

-- ns:CreateDice(parent, size) -> pair with :Set(d1, d2), :Tumble(d1, d2, onDone), :Blank()
function ns:CreateDice(parent, size)
    local pair = ns.CreateFrame("Frame", nil, parent)
    pair:SetWidth(size * 2 + 10); pair:SetHeight(size)
    pair.a = MakeDie(pair, size)
    pair.a:SetPoint("LEFT", pair, "LEFT", 0, 0)
    pair.b = MakeDie(pair, size)
    pair.b:SetPoint("RIGHT", pair, "RIGHT", 0, 0)
    function pair:Set(d1, d2)
        self.rolling = nil
        self.a:Show_(d1); self.b:Show_(d2)
    end
    function pair:Blank() self:Set(0, 0) end
    -- Tumble for a moment, then land on d1, d2. The dice keep going even
    -- while the window is hidden (the result is already known).
    function pair:Tumble(d1, d2, onDone)
        self.rolling = { d1 = d1, d2 = d2, left = ROLL_TIME, flip = 0, onDone = onDone }
        self.driver:Show()
    end
    pair.driver = ns.CreateFrame("Frame")
    pair.driver:Hide()
    pair.driver:SetScript("OnUpdate", function()
        local r = pair.rolling
        if not r then this:Hide() return end
        local dt = arg1 or 0
        r.left = r.left - dt
        r.flip = r.flip - dt
        if r.left <= 0 then
            this:Hide()
            pair:Set(r.d1, r.d2)
            if r.onDone then r.onDone() end
            return
        end
        if r.flip <= 0 then
            r.flip = 0.07
            pair.a:Show_(math.random(1, 6)); pair.b:Show_(math.random(1, 6))
        end
    end)
    pair:Blank()
    return pair
end

-- A betting spot: a box with the bet's name, what it pays, chips on it and
-- the last result. Left-click adds the chosen chip, right-click takes it off.
function ns:CreateCrapsSpot(parent, spot, w, h, onClick)
    local b = ns.CreateFrame("Button", nil, parent)
    b:SetWidth(w); b:SetHeight(h)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(b)
    edge:SetTexture(0.85, 0.78, 0.55, 0.9)
    b.fill = b:CreateTexture(nil, "BORDER")
    b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.fill:SetTexture(0.04, 0.24, 0.10, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetTexture(1, 1, 1, 0.10)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -4)
    b.name:SetText(spot.name)
    b.pays = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.pays:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 5, 4)
    b.pays:SetText(spot.pays)
    b.amount = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.amount:SetPoint("TOPRIGHT", b, "TOPRIGHT", -5, -4)
    b.result = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.result:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -5, 4)
    b.spot = spot
    b:SetScript("OnClick", function() onClick(spot.key, arg1 == "RightButton") end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText(spot.name)
        GameTooltip:AddLine(spot.help, 1, 1, 1, true)
        GameTooltip:AddLine("Left-click: add your chip. Right-click: take it back.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- amount on the spot, whether it can take chips now, and its last result
    function b:Draw(amount, open, result)
        self.amount:SetText((amount and amount > 0) and ns:FormatChips(amount) or "")
        self:SetAlpha(open and 1 or 0.55)
        if result == nil then
            self.result:SetText("")
        elseif result > 0 then
            self.result:SetText("|cff40ff40+" .. ns:FormatChips(result) .. "|r")
        elseif result < 0 then
            self.result:SetText("|cffff5050-" .. ns:FormatChips(-result) .. "|r")
        else
            self.result:SetText("|cffccccccpush|r")
        end
    end
    return b
end

Rules.SPOTS[1].help = "Come-out: 7 or 11 wins, 2, 3 or 12 loses, anything else sets the point. Then the point wins and a 7 loses."
Rules.SPOTS[2].help = "Behind a Pass bet once there's a point. Pays 2:1 on 4 and 10, 3:2 on 5 and 9, 6:5 on 6 and 8; loses on a 7."
Rules.SPOTS[3].help = "The opposite of Pass. Come-out: 2 or 3 wins, 12 pushes, 7 or 11 loses. Then a 7 wins and the point loses."
Rules.SPOTS[4].help = "One roll. 3, 4, 9, 10 or 11 pays 1:1, 2 pays 2:1, 12 pays 3:1. 5, 6, 7 or 8 loses."
Rules.SPOTS[5].help = "One roll. Any 7 pays 4:1."
Rules.SPOTS[6].help = "One roll. A 2, 3 or 12 pays 7:1."

---------------------------------------------------------------------------
-- Solo table
---------------------------------------------------------------------------
local Craps = {
    id = "craps",
    name = "Craps",
    description = "Roll the dice: Pass Line, odds, Field and more. Party play too.",
    icon = "Interface\\AddOns\\CowCasino\\Art\\CrapsIcon",   -- painted dice (1.12 has no dice icon)
}

local db
local ui = {}
local S = { rolling = false, results = {} }

local function Fmt(n) return ns:FormatChips(n) end

local function Fill(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function SetStatus(text, r, g, b)
    ui.status:SetText(text or "")
    ui.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function StatsText()
    local s = db.stats
    local net = s.net
    local netText = (net > 0 and ("|cff40ff40+" .. Fmt(net))) or (net < 0 and ("|cffff5050-" .. Fmt(-net))) or "|cffcccccc0"
    return string.format("Rolls %d  Points made %d  Seven-outs %d  Net %s|r", s.rolls, s.pointsMade, s.sevenOuts, netText)
end

-- Same bets: put back what was on each spot before the last roll, where
-- that's allowed now (line bets only on a come-out, odds only behind Pass
-- during a point). Returns the chips to add per spot and their total.
local function RebetPlan()
    local plan, need = {}, 0
    if not db.lastBets then return plan, 0 end
    local after = {}
    for k, v in pairs(db.bets) do after[k] = v end
    -- Pass first, so odds can go behind a Pass bet it puts back
    for _, spot in ipairs(Rules.SPOTS) do
        local key = spot.key
        local want, have = db.lastBets[key] or 0, after[key] or 0
        if want > have and Rules.CanAdd(key, db.point, after) then
            local add = math.min(want - have, Rules.Limit(key, after, db.oddsMax) - have)
            if add > 0 then
                plan[key] = add
                after[key] = have + add
                need = need + add
            end
        end
    end
    return plan, need
end

local function Refresh()
    if not ui.spots then return end
    ns:UpdateChipsDisplay()
    local bets, point = db.bets, db.point
    for _, b in ipairs(ui.spots) do
        local key = b.spot.key
        local open = not S.rolling and (Rules.CanAdd(key, point, bets) or ((bets[key] or 0) > 0 and Rules.CanRemove(key, point)))
        b:Draw(bets[key], open, S.results[key])
    end
    if point then
        ui.point:SetText("Point " .. point)
        ui.point:SetTextColor(1, 0.82, 0)
    else
        ui.point:SetText("Come-out")
        ui.point:SetTextColor(0.7, 0.7, 0.7)
    end
    for i, b in ipairs(ui.chipButtons) do
        ns.SetShown(b.chosen, CHIP_VALUES[i] == db.chip)
    end
    local onTable = Rules.Total(bets)
    ui.onTable:SetText("On the table: " .. Fmt(onTable))
    ns.SetEnabled(ui.roll, not S.rolling and onTable > 0)
    ns.SetEnabled(ui.clear, not S.rolling and onTable > 0)
    local _, need = RebetPlan()
    ns.SetEnabled(ui.rebet, not S.rolling and need > 0 and need <= ns.db.chips)
    if ui.partyButton then ns.SetEnabled(ui.partyButton, not S.rolling and onTable == 0) end
    ui.stats:SetText(StatsText())
end

local function Place(key, remove)
    if S.rolling then return end
    local bets, point = db.bets, db.point
    local have = bets[key] or 0
    if remove then
        if have <= 0 or not Rules.CanRemove(key, point) then return end
        local back = math.min(have, db.chip)
        bets[key] = (have - back > 0) and (have - back) or nil
        ns:AddChips(back)
        S.results = {}
    else
        if not Rules.CanAdd(key, point, bets) then
            if key == "odds" then SetStatus("Odds go behind a Pass bet once there's a point.")
            else SetStatus("Line bets go down before the come-out roll.") end
            return
        end
        local room = Rules.Limit(key, bets, db.oddsMax) - have
        local add = math.min(db.chip, room)
        if add <= 0 then SetStatus("That spot is at its limit.") return end
        if not ns:SpendChips(add) then SetStatus("Not enough chips.", 1, 0.35, 0.35) return end
        bets[key] = have + add
        S.results = {}
    end
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

-- Odds can't stay without the Pass bet they back (it can't leave during a
-- point, so this only matters on the come-out).
local function ClearAll()
    if S.rolling then return end
    local back = 0
    for key, v in pairs(db.bets) do
        if Rules.CanRemove(key, db.point) then
            back = back + v
            db.bets[key] = nil
        end
    end
    if back > 0 then ns:AddChips(back) end
    S.results = {}
    Refresh()
end

local function Rebet()
    if S.rolling then return end
    local plan, need = RebetPlan()
    if need <= 0 then return end
    if not ns:SpendChips(need) then
        SetStatus("Not enough chips for the same bets.", 1, 0.35, 0.35)
        return
    end
    for k, add in pairs(plan) do db.bets[k] = (db.bets[k] or 0) + add end
    S.results = {}
    ns:Sound("IG_MAINMENU_OPTION")
    Refresh()
end

local function Finish(d1, d2)
    local bets, oldPoint = db.bets, db.point
    local back, point, event = Rules.Settle(bets, oldPoint, d1, d2)
    local staked, returned = 0, 0
    S.results = {}
    for key, amount in pairs(back) do
        staked = staked + bets[key]
        returned = returned + amount
        S.results[key] = amount - bets[key]
        bets[key] = nil
    end
    db.point = point
    if returned > 0 then ns:AddChips(returned) end
    local net = returned - staked
    local s = db.stats
    s.rolls = s.rolls + 1
    s.net = s.net + net
    if net > s.biggestWin then s.biggestWin = net end
    if event == "made" then s.pointsMade = s.pointsMade + 1 end
    if event == "sevenOut" then s.sevenOuts = s.sevenOuts + 1 end
    S.rolling = false

    local line = Rules.Describe(d1, d2, event, point, oldPoint)
    if net > 0 then
        SetStatus(line .. " You win " .. Fmt(net) .. ".", 0.25, 1, 0.25)
        ns:PlayGameSound(db, "win")
    elseif net < 0 then
        SetStatus(line .. " You lose " .. Fmt(-net) .. ".", 1, 0.35, 0.35)
        ns:PlayGameSound(db, "lose")
    else
        SetStatus(line, 0.9, 0.9, 0.9)
    end
    if ns.db.chips < 1 and Rules.Total(bets) == 0 then SetStatus(ns:LowChipsText(MIN_BET), 1, 0.35, 0.35) end
    Refresh()
end

local function Roll()
    if S.rolling or Rules.Total(db.bets) <= 0 then return end
    db.lastBets = {}            -- for Same bets after this roll
    for k, v in pairs(db.bets) do db.lastBets[k] = v end
    S.rolling = true
    S.results = {}
    SetStatus("Rolling...")
    ns:PlayGameSound(db, "newHand")
    local d1, d2 = Rules.Roll()
    Refresh()
    ui.dice:Tumble(d1, d2, function() Finish(d1, d2) end)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function MakeButton(parent, text, width, onClick, height)
    local b = ns.CreateFrame("Button", ns:NewName(), parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(height or 22)
    b:SetText(text)
    b:SetScript("OnClick", function() onClick(this, arg1) end)
    return b
end

local function BuildOptions(panel)
    local o = ns.CreateFrame("Frame", nil, panel)
    o:SetAllPoints(panel)
    o:SetFrameLevel(panel:GetFrameLevel() + 50)
    o:EnableMouse(true)
    o:Hide()
    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(o)
    bg:SetTexture(0, 0, 0, 0.94)
    local title = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", o, "TOP", 0, -10)
    title:SetText("Craps Options")

    local label = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -50)
    label:SetText("Most odds behind a Pass bet")
    local value = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local function Step(dir)
        local idx = 1
        for i, v in ipairs(ODDS_CHOICES) do if v == db.oddsMax then idx = i end end
        idx = math.max(1, math.min(ns.getn(ODDS_CHOICES), idx + dir))
        db.oddsMax = ODDS_CHOICES[idx]
        o:Refresh()
    end
    local nextB = MakeButton(o, ">", 26, function() Step(1) end)
    nextB:SetPoint("TOPRIGHT", o, "TOPRIGHT", -16, -46)
    value:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    value:SetWidth(60)
    value:SetJustifyH("CENTER")
    local prevB = MakeButton(o, "<", 26, function() Step(-1) end)
    prevB:SetPoint("RIGHT", value, "LEFT", -6, 0)

    local rules = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rules:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -84)
    rules:SetWidth(AREA_W - 32)
    rules:SetJustifyH("LEFT")
    rules:SetText("How it plays: the come-out roll wins the Pass Line on 7 or 11 and loses it on 2, 3 or 12. "
        .. "Any other total is the point: keep rolling until the point comes again (Pass wins) or a 7 shows "
        .. "(seven out). Don't Pass is the other side. Odds go behind Pass once there's a point and pay true odds. "
        .. "Field, Any Seven and Any Craps are decided by the next roll. Hover a spot for its details.")

    local reset
    reset = MakeButton(o, "Reset stats", 110, function()
        if reset.armed and GetTime() - reset.armed <= 3 then
            reset.armed = nil
            reset:SetText("Reset stats")
            db.stats = {}
            Fill(db.stats, DEFAULT_STATS)
            Refresh()
            return
        end
        reset.armed = GetTime()
        reset:SetText("Sure? Click again")
    end)
    reset:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", 16, 40)
    local sounds = MakeButton(o, "Sounds", 80, function() ui.sounds:Show() end)
    sounds:SetPoint("BOTTOM", o, "BOTTOM", 0, 40)
    local done = MakeButton(o, "Done", 90, function() o:Hide() end)
    done:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -16, 40)

    function o:Refresh()
        value:SetText(db.oddsMax .. "x")
        if not (reset.armed and GetTime() - reset.armed <= 3) then
            reset.armed = nil
            reset:SetText("Reset stats")
        end
    end
    o:SetScript("OnShow", function() this:Refresh() end)
    return o
end

-- Party play: the party lobby and table (Games\PartyCraps.lua) take over
-- this window, the way Blackjack's do.
local function BuildParty(panel)
    local party = ns.PartyCraps
    if not party then return end
    local partyFrame = ns.CreateFrame("Frame", nil, panel)
    partyFrame:SetAllPoints(panel)
    partyFrame:SetFrameLevel(panel:GetFrameLevel() + 20)
    partyFrame:EnableMouse(true)
    partyFrame:Hide()
    ui.partyFrame = partyFrame
    party:Build(partyFrame)
    party.onBack = function()
        partyFrame:Hide()
        Refresh()
    end
    partyFrame:SetScript("OnShow", function() ui.solo:Hide() end)
    partyFrame:SetScript("OnHide", function() ui.solo:Show() Refresh() end)
    ui.partyButton = MakeButton(ui.solo, "Party play", 80, function()
        if S.rolling or Rules.Total(db.bets) > 0 then return end
        partyFrame:Show()
        party:OnShow()
    end)
    ui.partyButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -2)
    ui.partyButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Party play")
        GameTooltip:AddLine("Host or join a craps table with your party or raid. Take your bets down first.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ui.partyButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Craps:Build(panel)
    ns.db.craps = ns.db.craps or {}
    db = ns.db.craps
    db.bets = db.bets or {}
    db.stats = db.stats or {}
    Fill(db.stats, DEFAULT_STATS)
    db.chip = db.chip or 25
    db.oddsMax = db.oddsMax or 3
    ns:InitSounds(db)

    local felt = panel:CreateTexture(nil, "BACKGROUND")
    felt:SetAllPoints(panel)
    felt:SetTexture(0.05, 0.30, 0.12, 0.92)

    local solo = ns.CreateFrame("Frame", nil, panel)
    solo:SetAllPoints(panel)
    ui.solo = solo

    local optionsButton = MakeButton(panel, "Options", 70, function()
        ns.SetShown(ui.options, not ui.options:IsShown())
    end)
    optionsButton:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 6)

    -- dice and the point
    ui.dice = ns:CreateDice(solo, 40)
    ui.dice:SetPoint("TOP", solo, "TOP", 0, -10)
    ui.point = ns:BigFont(solo:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 16)
    ui.point:SetPoint("TOPRIGHT", solo, "TOPRIGHT", -10, -22)

    -- the board, two spots to a row
    ui.spots = {}
    local W, H, GAP = 170, 44, 6
    for i, spot in ipairs(Rules.SPOTS) do
        local b = ns:CreateCrapsSpot(solo, spot, W, H, Place)
        local col, row = ns.Mod(i - 1, 2), math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", solo, "TOPLEFT", 3 + col * (W + GAP), -62 - row * (H + GAP))
        ui.spots[i] = b
    end

    ui.status = solo:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.status:SetPoint("TOP", solo, "TOP", 0, -216)
    ui.status:SetWidth(AREA_W - 8)
    ui.onTable = solo:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.onTable:SetPoint("TOP", solo, "TOP", 0, -252)

    -- chip to bet with
    local chipLabel = solo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chipLabel:SetPoint("BOTTOMLEFT", solo, "BOTTOMLEFT", 6, 70)
    chipLabel:SetText("Chip")
    ui.chipButtons = {}
    for i, v in ipairs(CHIP_VALUES) do
        local v = v   -- own copy for closures (Lua 5.0)
        local b = MakeButton(solo, tostring(v), 44, function()
            db.chip = v
            ns:Sound("IG_MAINMENU_OPTION")
            Refresh()
        end)
        b:SetPoint("BOTTOMLEFT", solo, "BOTTOMLEFT", 34 + (i - 1) * 48, 66)
        b.chosen = b:CreateTexture(nil, "OVERLAY")    -- marks the chip you bet with
        b.chosen:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
        b.chosen:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
        b.chosen:SetTexture(1, 0.82, 0, 0.35)
        b.chosen:Hide()
        ui.chipButtons[i] = b
    end
    ui.clear = MakeButton(solo, "Take down", 80, ClearAll)
    ui.clear:SetPoint("BOTTOMRIGHT", solo, "BOTTOMRIGHT", -6, 66)

    ui.roll = MakeButton(solo, "Roll", 150, Roll, 26)
    ui.roll:SetPoint("BOTTOMLEFT", solo, "BOTTOMLEFT", 40, 32)
    ui.rebet = MakeButton(solo, "Same bets", 100, Rebet, 26)
    ui.rebet:SetPoint("LEFT", ui.roll, "RIGHT", 10, 0)

    ui.stats = solo:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.stats:SetPoint("BOTTOM", solo, "BOTTOM", 0, 12)

    ui.options = BuildOptions(panel)
    ui.sounds = ns:CreateSoundOptions(panel, "Craps Options", function() return db end)
    BuildParty(panel)

    if Rules.Total(db.bets) > 0 then
        SetStatus("Welcome back - your bets are still on the table.")
    elseif db.point then
        db.point = nil          -- nothing riding on an old point
        SetStatus("Place your bets and roll.")
    else
        SetStatus("Place your bets and roll.")
    end
    Refresh()
end

function Craps:OnShow()
    if ui.spots then Refresh() end
    -- Back at your party table, if you're at one.
    local party = ns.PartyCraps
    if party and ui.partyFrame and (party:IsSeated() or ui.partyFrame:IsShown()) then
        ui.partyFrame:Show()
        party:OnShow()
    end
end

function Craps:OnHide()
    if ui.options then ui.options:Hide() end
    if ui.sounds then ui.sounds:Hide() end
end

-- For the out-of-chips check: bets on the table or dice in the air.
function Craps:ChipsInPlay()
    local d = ns.db.craps
    return S.rolling or (d ~= nil and d.bets ~= nil and Rules.Total(d.bets) > 0)
end

-- A fresh stack after running out (Core.lua): stats start over.
function Craps:ResetStats()
    local d = ns.db.craps
    if not d then return end
    d.stats = {}
    Fill(d.stats, DEFAULT_STATS)
    if ui.stats and db then Refresh() end
end

-- Exposed for tests.
Craps.S, Craps.ui = S, ui

ns:RegisterGame(Craps)
