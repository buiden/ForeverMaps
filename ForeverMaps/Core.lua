-- Forever Maps core: player position, faction, learned flight paths, route
-- state and live tracking.
local ADDON, ns = ...
local R = ns.Router
local W = ns.World
local Core = {}
ns.Core = Core

local KEY_SEARING_GORGE = 5396
local TICK = 0.5          -- seconds between position checks
local REPLAN_GAP = 3      -- seconds between automatic recalculations
local OFF_ROUTE = 60      -- yards from the route before recalculating

Core.route = nil          -- all three plans {run=, fly=, boat=}
Core.mode = "fly"
Core.step = 1
Core.dest = nil           -- {node=, name=, zone=}

local function chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd060Forever Maps:|r " .. msg)
end
Core.chat = chat

-- ---------------------------------------------------------------- saved data
function Core:InitDB()
    ForeverMapsCharDB = ForeverMapsCharDB or {}
    local db = ForeverMapsCharDB
    db.known = db.known or {}          -- taxiNodeID -> true (seen as learned on a flight map)
    db.override = db.override or {}    -- taxiNodeID -> true/false (player toggle)
    db.seenContinent = db.seenContinent or {}
    if db.captured == nil then db.captured = false end
    if db.popupDone == nil then db.popupDone = false end
    db.mode = db.mode or "fly"
    self.db = db
    self.mode = db.mode
end

function Core:Knows(taxiID)
    local o = self.db.override[taxiID]
    if o ~= nil then return o end
    return self.db.known[taxiID] == true
end

function Core:SetOverride(taxiID, value)
    if value == nil or value == (self.db.known[taxiID] == true) then
        self.db.override[taxiID] = nil
    else
        self.db.override[taxiID] = value
    end
    self:Replan("toggle")
end

-- ---------------------------------------------------------------- player
function Core:Faction()
    local f = UnitFactionGroup("player")
    return f == "Horde" and 2 or 1, f
end

function Core:IsDruid()
    local _, class = UnitClass("player")
    return class == "DRUID"
end

function Core:HasKey()
    local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(KEY_SEARING_GORGE))
        or (GetItemCount and GetItemCount(KEY_SEARING_GORGE)) or 0
    return count > 0
end

function Core:RunSpeed()
    local _, run = GetUnitSpeed("player")
    if not run or run < R.RUN_SPEED then return R.RUN_SPEED end
    return run
end

-- World position {cc, x, y} for a normalized position on a UI map.
function Core:MapToWorld(mapID, nx, ny)
    local zi = W.mapToZone[mapID]
    if zi then
        local b = W.zoneBounds[zi]
        local cc = R.CONT_CODE[b[6]]
        return cc, b[3] - ny * (b[3] - b[2]), b[5] - nx * (b[5] - b[4])
    end
    local c = W.continentMaps[mapID]
    if c then
        return R.CONT_CODE[c[1]], c[3] - ny * (c[3] - c[2]), c[5] - nx * (c[5] - c[4])
    end
    if C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local cont, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(nx, ny))
        if cont and pos and R.CONT_CODE[cont] then
            local x, y = pos:GetXY()
            return R.CONT_CODE[cont], x, y
        end
    end
end

-- Normalized position of a world point on a UI map (nil if not on it).
function Core:WorldToMap(mapID, cc, x, y)
    local zi = W.mapToZone[mapID]
    local xMin, xMax, yMin, yMax, mc
    if zi then
        local b = W.zoneBounds[zi]
        xMin, xMax, yMin, yMax, mc = b[2], b[3], b[4], b[5], R.CONT_CODE[b[6]]
    else
        local c = W.continentMaps[mapID]
        if not c then return end
        xMin, xMax, yMin, yMax, mc = c[2], c[3], c[4], c[5], R.CONT_CODE[c[1]]
    end
    if mc ~= cc then return end
    return (yMax - y) / (yMax - yMin), (xMax - x) / (xMax - xMin)
end

function Core:PlayerPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local nx, ny = pos:GetXY()
    if not nx then return end
    local cc, x, y = self:MapToWorld(mapID, nx, ny)
    if not cc then return end
    return cc, x, y, mapID
end

-- ---------------------------------------------------------------- flight data
local STATE_UNREACHABLE = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable or 2

function Core:CaptureTaxi()
    local mapID = GetTaxiMapID and GetTaxiMapID()
    local nodes = mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_TaxiMap.GetAllTaxiNodes(mapID)
    local added, total = 0, 0
    if nodes and #nodes > 0 then
        for _, n in ipairs(nodes) do
            if n.nodeID and n.state ~= STATE_UNREACHABLE then
                total = total + 1
                if not self.db.known[n.nodeID] then added = added + 1 end
                self.db.known[n.nodeID] = true
            end
        end
    elseif NumTaxiNodes then
        -- older API: match by name
        local byName = {}
        for node, info in pairs(W.fm) do
            local nm = W.nname[node]
            if nm then byName[nm] = info[1] end
        end
        for i = 1, NumTaxiNodes() do
            local t = TaxiNodeGetType(i)
            local id = byName[TaxiNodeName(i)]
            if id and (t == "CURRENT" or t == "REACHABLE") then
                total = total + 1
                if not self.db.known[id] then added = added + 1 end
                self.db.known[id] = true
            end
        end
    end
    if total == 0 then return end
    local cc = self:PlayerPosition()
    if cc then self.db.seenContinent[cc] = true end
    local first = not self.db.captured
    self.db.captured = true
    self.db.popupDone = true
    if first then
        chat(string.format("Saved your %d flight paths on this continent. Visit a flight master on the other continent to add those too.", total))
    elseif added > 0 then
        chat(string.format("Learned %d new flight path%s.", added, added == 1 and "" or "s"))
    end
    if ns.UI then ns.UI:OnFlightDataChanged() end
    self:Replan("flight data")
end

-- ---------------------------------------------------------------- routing
function Core:Options(mode)
    return {
        mode = mode,
        faction = (self:Faction()),
        druid = self:IsDruid(),
        hasKey = self:HasKey(),
        speed = self:RunSpeed(),
        destName = self.dest and self.dest.name,
        knows = function(id) return self:Knows(id) end,
    }
end

function Core:SetDestination(node, name)
    self.dest = { node = node, name = name or R.Name(node) or R.Zone(node) }
    self:Replan("new destination")
end

-- Destination from a point on a UI map (world-map pin).
function Core:SetDestinationAtMap(mapID, nx, ny)
    local cc, x, y = self:MapToWorld(mapID, nx, ny)
    if not cc then chat("Can't route to that spot."); return end
    local node = R:Snap(cc, x, y)
    if not node then chat("Can't route to that spot."); return end
    local zone = R.Zone(node)
    self.pin = { cc = cc, x = x, y = y }
    self:SetDestination(node, "Pin in " .. zone)
end

function Core:ClearRoute()
    self.dest, self.route, self.pin, self.step = nil, nil, nil, 1
    self:SetTicking(false)
    if ns.UI then ns.UI:Refresh() end
end

function Core:Replan(reason)
    if not self.dest then return end
    self:SetTicking(true)
    local cc, x, y = self:PlayerPosition()
    if not cc then
        self.route = nil
        self.status = "Your location isn't available here."
        if ns.UI then ns.UI:Refresh() end
        return
    end
    local src = R:Snap(cc, x, y)
    self.status = nil
    local plans = {}
    for _, mode in ipairs({ "run", "fly", "boat" }) do
        local r, why = R:Plan(src, self.dest.node, self:Options(mode))
        plans[mode] = r or { mode = mode, unavailable = why }
    end
    self.route = plans
    self.lastPos = { cc, x, y }
    self.step = 1
    self.lastPlan = GetTime()
    self.replans = (self.replans or 0) + 1
    if reason == "off route" then chat("Off route, recalculating.") end
    if ns.UI then ns.UI:Refresh() end
end

function Core:SetMode(mode)
    self.mode = mode
    self.db.mode = mode
    self.step = 1
    if ns.UI then ns.UI:Refresh() end
end

function Core:Current()
    local r = self.route and self.route[self.mode]
    if r and not r.unavailable then return r end
end

function Core:Tick()
    local r = self:Current()
    if not r or (UnitOnTaxi and UnitOnTaxi("player")) then return end
    local cc, x, y = self:PlayerPosition()
    if not cc then return end
    local step, off, toEnd = R:Track(r, self.step, cc, x, y, OFF_ROUTE)
    if step > #r.steps then
        chat("You have arrived at " .. R.WithZone(self.dest.name, R.Zone(self.dest.node)) .. ".")
        self:ClearRoute()
        return
    end
    self.step = step
    self.toEnd = toEnd
    if off and GetTime() - (self.lastPlan or 0) > REPLAN_GAP then
        -- only recalculate after moving away from where the last plan was
        -- made; standing somewhere off the paths must not replan forever
        local lp = self.lastPos
        local moved = not lp or lp[1] ~= cc or (lp[2] - x) ^ 2 + (lp[3] - y) ^ 2 > OFF_ROUTE * OFF_ROUTE
        if moved then
            self:Replan("off route")
            return
        end
    end
    if ns.UI then ns.UI:UpdateLive(cc, x, y) end
end

-- ---------------------------------------------------------------- events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TAXIMAP_OPENED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        Core:InitDB()
        R:Init()
    elseif event == "PLAYER_LOGIN" then
        if ns.UI then ns.UI:Init() end
        if not Core.db.popupDone and ns.UI then ns.UI:ShowWelcome() end
    elseif event == "TAXIMAP_OPENED" then
        Core:CaptureTaxi()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if Core.dest then Core:Replan("zone change") end
    end
end)
local acc = 0
local function onUpdate(_, elapsed)
    acc = acc + elapsed
    if acc >= TICK then
        acc = 0
        Core:Tick()
    end
end
-- the position timer runs only while there is a destination
function Core:SetTicking(on)
    if on and not self.ticking then f:SetScript("OnUpdate", onUpdate)
    elseif not on and self.ticking then f:SetScript("OnUpdate", nil) end
    self.ticking = on and true or false
end

SLASH_FOREVERMAPS1 = "/fmaps"
SLASH_FOREVERMAPS2 = "/forevermaps"
SlashCmdList.FOREVERMAPS = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "welcome" then ns.UI:ShowWelcome()
    elseif msg == "reset" then
        ForeverMapsCharDB = nil; Core:InitDB(); chat("Flight data cleared for this character.")
    elseif msg ~= "" then
        ns.UI:Show(); ns.UI:SearchAndGo(msg)
    else ns.UI:Toggle() end
end

function ForeverMaps_OnCompartmentClick() ns.UI:Toggle() end
