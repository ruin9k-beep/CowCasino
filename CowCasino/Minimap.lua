-- CowCasino: minimap button
-- Click to open or close the casino, drag to move it around the minimap.

local ns = CowCasino.ns

local EDGE_OFFSET = 10   -- how far outside the minimap edge the button sits

local function UpdatePosition(button)
    local angle = math.rad(ns.db.minimap.angle or 225)
    local x, y = math.cos(angle), math.sin(angle)
    local radius = (Minimap:GetWidth() / 2) + EDGE_OFFSET

    x, y = x * radius, y * radius

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function DragUpdate(button)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    ns.db.minimap.angle = ns.Mod(math.deg(math.atan2(py - my, px - mx)), 360)
    UpdatePosition(button)
end

local function ShowTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffffd100CowCasino|r")
    GameTooltip:AddLine("Click to open or close.", 1, 1, 1)
    GameTooltip:AddLine("Chips: " .. ns:FormatChips(ns.db.chips), 1, 1, 1)
    GameTooltip:AddLine("Drag to move.  /casino minimap to hide.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function ns:BuildMinimapButton()
    if self.minimapButton or not Minimap then return end

    local b = ns.CreateFrame("Button", "CowCasinoMinimapButton", Minimap)
    b:SetWidth(31); b:SetHeight(31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetWidth(20); bg:SetHeight(20)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(17); icon:SetHeight(17)
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetWidth(53); border:SetHeight(53)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function() ns:Toggle() end)
    b:SetScript("OnMouseDown", function() icon:SetTexCoord(0, 1, 0, 1) end)
    b:SetScript("OnMouseUp", function() icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end)
    b:SetScript("OnEnter", function() ShowTooltip(this) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function() local self = this
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function() DragUpdate(this) end)
    end)
    b:SetScript("OnDragStop", function() local self = this
        self:SetScript("OnUpdate", nil)
        icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    end)

    self.minimapButton = b
    UpdatePosition(b)
    self:SetMinimapButtonShown(not self.db.minimap.hide)
end

function ns:SetMinimapButtonShown(shown)
    self.db.minimap.hide = not shown
    if self.minimapButton then
        ns.SetShown(self.minimapButton, shown)
    end
end

