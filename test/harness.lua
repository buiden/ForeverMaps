-- Mock WoW client for Forever Maps. Run: lua test/harness.lua ForeverMaps
local dir = arg[1] or "ForeverMaps"
local pass, fail = 0, 0
local function ok(c, msg) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. msg) end end

-- ---------------------------------------------------------------- mock state
local S = { faction = "Alliance", class = "WARRIOR", map = 1429, px = 0.42, py = 0.65, time = 0,
    taxi = nil, facing = 0, keys = 0, onTaxi = false, speed = 7 }
local chat = {}
local events, updaters = {}, {}
local allFrames = {}

-- generic frame: any unknown method is a no-op that returns nil
local frameMT = {}
frameMT.__index = function(t, k)
    local v = rawget(frameMT, k)
    if v then return v end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
end
function frameMT.RegisterEvent(self, e) events[e] = events[e] or {}; table.insert(events[e], self) end
function frameMT.SetScript(self, k, fn)
    self.scripts[k] = fn
    if k == "OnUpdate" then
        for i = #updaters, 1, -1 do if updaters[i] == self then table.remove(updaters, i) end end
        if fn then updaters[#updaters + 1] = self end
    end
end
function frameMT.HookScript(self, k, fn) local o = self.scripts[k]; self.scripts[k] = function(...) if o then o(...) end; fn(...) end end
function frameMT.GetScript(self, k) return self.scripts[k] end
function frameMT.Show(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function frameMT.Hide(self) self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function frameMT.IsShown(self) return self.shown end
function frameMT.SetText(self, t) self.text = t end
function frameMT.GetText(self) return self.text or "" end
function frameMT.SetChecked(self, v) self.checked = v end
function frameMT.GetChecked(self) return self.checked end
function frameMT.Enable(self) self.enabled = true end
function frameMT.Disable(self) self.enabled = false end
function frameMT.GetWidth(self) return self.w or 1000 end
function frameMT.GetHeight(self) return self.h or 667 end
function frameMT.SetSize(self, w, h) self.w, self.h = w, h end
function frameMT.SetFrameLevel(self, l) self.level = l end
function frameMT.SetHeight(self, h) self.h = h end
function frameMT.GetStringHeight(self) local n = math.max(1, math.ceil(#(self.text or "") / 45)); return 12 * n end
function frameMT.SetRotation(self, r) self.rotation = r end
function frameMT.Click(self) if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
local function newFrame(kind, name)
    local f = setmetatable({ scripts = {}, shown = true, kind = kind }, frameMT)
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end
function frameMT.CreateFontString(self) return newFrame("FontString") end
function frameMT.CreateTexture(self) return newFrame("Texture") end
function frameMT.CreateLine(self) local l = newFrame("Line"); self.lines = (self.lines or 0) + 1; return l end
function CreateFrame(kind, name, parent, template)
    local f = newFrame(kind, name)
    f.parent = parent
    if kind == "Frame" and parent == UIParent then f.shown = true end
    return f
end
UIParent = newFrame("Frame", "UIParent")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
SlashCmdList = {}
Enum = { FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 } }
function UnitFactionGroup() return S.faction, S.faction end
function UnitClass() return "Class", S.class end
function GetUnitSpeed() return 0, S.speed end
function GetTime() return S.time end
function GetPlayerFacing() return S.facing end
function UnitOnTaxi() return S.onTaxi end
function GetCursorPosition() return 500, 400 end
function GetItemCount(id) return id == 5396 and S.keys or 0 end
C_Item = { GetItemCount = GetItemCount }
function hooksecurefunc(t, k, fn) local o = t[k]; t[k] = function(...) local r = o and o(...); fn(...); return r end end
function Mixin(t, ...) return t end
function UIParent.GetEffectiveScale() return 1 end
C_Map = {
    GetBestMapForUnit = function() return S.map end,
    GetPlayerMapPosition = function(m) return { GetXY = function() return S.px, S.py end } end,
}
local taxiNodes
function GetTaxiMapID() return S.taxiMap end
C_TaxiMap = { GetAllTaxiNodes = function() return taxiNodes end }

-- world map with a canvas click handler registry
local clickHandlers = {}
WorldMapFrame = newFrame("Frame", "WorldMapFrame")
WorldMapFrame.shown = false
WorldMapFrame.mapID = 1429
-- like Blizzard's registry: highest priority first, stops at the first handler returning true
function WorldMapFrame:AddCanvasClickHandler(fn, prio)
    clickHandlers[#clickHandlers + 1] = { fn = fn, prio = prio or 0 }
    table.sort(clickHandlers, function(a, b) return a.prio > b.prio end)
end
function WorldMapFrame:ProcessCanvasClickHandlers(btn, x, y)
    for _, h in ipairs(clickHandlers) do if h.fn(self, btn, x, y) then return true end end
    return false
end
function WorldMapFrame:GetMapID() return self.mapID end
function WorldMapFrame:GetCanvas() self.canvas = self.canvas or newFrame("Frame"); return self.canvas end
function WorldMapFrame:OnMapChanged() end
function WorldMapFrame:NavigateToParentMap() self.navigatedUp = true end
local function rightClick(nx, ny)
    return WorldMapFrame:ProcessCanvasClickHandlers("RightButton", nx, ny)
end

local function fire(e, ...)
    for _, f in ipairs(events[e] or {}) do f.scripts.OnEvent(f, e, ...) end
end
local function advance(sec)
    local steps = math.floor(sec / 0.5)
    for _ = 1, steps do
        S.time = S.time + 0.5
        for _, f in ipairs(updaters) do f.scripts.OnUpdate(f, 0.5) end
    end
end
local function lastChat() return chat[#chat] or "" end

-- ---------------------------------------------------------------- load addon
local ns = {}
local t0 = os.clock()
for _, f in ipairs({ "Data/World.lua", "Router.lua", "Core.lua", "UI.lua" }) do
    assert(loadfile(dir .. "/" .. f))("ForeverMaps", ns)
end
local load = os.clock() - t0
local W, R, Core, UI = ns.World, ns.Router, ns.Core, ns.UI
fire("ADDON_LOADED", "ForeverMaps")
fire("PLAYER_LOGIN")
print(string.format("addon loaded in %.2fs", load))

-- helpers to place the player at a node
local function zoneMap(zoneName)
    for mid, zi in pairs(W.mapToZone) do if W.zones[zi] == zoneName then return mid end end
end
local function placeAt(node)
    local zone = R.Zone(node)
    local mid = zoneMap(zone)
    local nx, ny = Core:WorldToMap(mid, R.Continent(node), W.nx[node], W.ny[node])
    S.map, S.px, S.py = mid, nx, ny
end
local function placeNode(name, zone)
    for _, p in ipairs(W.places) do
        if p[1] == name and W.zones[p[2]] == zone then return p[3] end
    end
    error(name)
end
local function fmNodesFor(bit)
    local t = {}
    for node, info in pairs(W.fm) do if info[2] % (2 * bit) >= bit and not info[3] then t[#t + 1] = info[1] end end
    return t
end

-- ---------------------------------------------------------------- 1. first-run popup
local goldshire = placeNode("Goldshire", "Elwynn Forest")
placeAt(goldshire)
UI:ShowWelcome()
local w = _G.ForeverMapsWelcome
ok(w and w:IsShown(), "welcome popup shows on first login")
ok(w.near.text and w.near.text:find("Stormwind"), "popup names nearest alliance flight master: " .. tostring(w.near.text))
ok(not Core.db.captured, "no flight data before visiting a flight master")
ok(UI.banner.text:find("flight master") ~= nil, "window banner reminds to visit a flight master")
w.go:Click()
ok(Core.dest and Core.dest.name:find("Stormwind"), "Route there sets nearest flight master as destination")
ok(not w:IsShown(), "popup closes after Route there")

-- ---------------------------------------------------------------- 2. flight capture
taxiNodes = {}
local stormwind, sentinel, lakeshire
for node, info in pairs(W.fm) do
    local nm = W.nname[node] or ""
    if nm:find("^Stormwind") then stormwind = info[1] end
    if nm:find("^Sentinel Hill") then sentinel = info[1] end
    if nm:find("^Lakeshire") then lakeshire = info[1] end
end
taxiNodes = { { nodeID = stormwind, state = 0 }, { nodeID = sentinel, state = 1 }, { nodeID = lakeshire, state = 2 } }
S.taxiMap = 1415
UI:ShowWelcome()
fire("TAXIMAP_OPENED")
ok(Core.db.captured and Core.db.popupDone, "flight data saved on first flight map")
ok(Core:Knows(stormwind) and Core:Knows(sentinel) and not Core:Knows(lakeshire), "learned = current+reachable only")
ok(not w:IsShown(), "popup auto-closes once data captured")
ok(lastChat():find("Saved your 2 flight paths"), "chat confirms capture: " .. lastChat())

-- ---------------------------------------------------------------- 3. search + three tabs
local res = R:Search("lakes")
ok(#res > 0, "autocomplete finds Lakeshire")
UI:Show()
UI.box:SetText("lakes"); UI:Suggest("lakes")
ok(UI.suggest:IsShown() and UI.suggest.rows[1].text.text:find("Lakeshire"), "suggestion list shows Lakeshire")
UI.suggest.rows[1]:Click()
ok(Core.dest and Core.dest.name == "Lakeshire", "picking a suggestion sets destination")
ok(Core.route.run and Core.route.fly and Core.route.boat, "all three modes planned")
for _, m in ipairs({ "run", "fly", "boat" }) do
    ok(UI.tabs[m].time.text and UI.tabs[m].time.text ~= "-", m .. " tab shows a time: " .. tostring(UI.tabs[m].time.text))
end
local flyNoLake = Core.route.fly
for _, s in ipairs(flyNoLake.steps) do
    if s.kind == "fly" then ok(R.TaxiID(s.to) ~= lakeshire, "unlearned Lakeshire not used") end
end
print("  Goldshire->Lakeshire fly: " .. UI.fmtTime(flyNoLake.seconds) .. " | " .. UI.head.text)

-- ---------------------------------------------------------------- 4. toggles
UI:ToggleFlightList()
ok(UI.flist:IsShown(), "flight path list opens")
local lakeRow
for _, row in ipairs(UI.flist.rows) do if row.entry and row.entry.id == lakeshire then lakeRow = row end end
ok(lakeRow and not lakeRow.check.checked, "Lakeshire row present, unticked")
local hordeShown = false
for _, row in ipairs(UI.flist.rows) do
    if row.entry and W.fm[row.entry.node][2] == 2 then hordeShown = true end
end
ok(not hordeShown, "alliance list hides horde-only flight masters")
local before = Core.replans
lakeRow.check.checked = true
lakeRow.check:Click()
ok(Core.replans == before + 1, "toggle triggers instant recalculation")
ok(Core:Knows(lakeshire), "toggle marks Lakeshire learned")
local usesLake = false
for _, s in ipairs(Core.route.fly.steps) do if s.kind == "fly" and R.TaxiID(s.to) == lakeshire then usesLake = true end end
ok(usesLake, "fly route now uses Lakeshire flight")
ok(Core.route.fly.seconds < flyNoLake.seconds, "learned path makes route faster")
do local t = {} for _, s in ipairs(Core.route.fly.steps) do t[#t+1] = s.text end
print("  after toggle fly: " .. UI.fmtTime(Core.route.fly.seconds) .. " mode=" .. Core.mode .. " step=" .. Core.step .. " head=" .. UI.head.text .. " :: " .. table.concat(t, " | ")) end

-- ---------------------------------------------------------------- 5. live updates
Core:SetMode("run")
local run = Core:Current()
ok(run and #run.steps >= 1, "run route has steps")
local pts = run.steps[1].points
local mid = pts[math.floor(#pts / 2)]
placeAt(mid); S.facing = 1.0
local rp = Core.replans
advance(1)
ok(Core.replans == rp, "on route: no recalculation")
ok(UI.dist.text and UI.dist.text:find("yd"), "next step shows distance: " .. tostring(UI.dist.text))
ok(UI.arrow.rotation ~= nil, "arrow rotates toward next point")
-- walk far off route
S.px = S.px + 0.08; S.py = S.py + 0.08
advance(4)
ok(Core.replans > rp, "off route: route recalculated")
ok(lastChat():find("recalculating"), "chat says recalculating")
-- arrive
placeAt(Core.dest.node)
advance(1)
ok(Core.dest == nil and lastChat():find("arrived"), "arrival clears route: " .. lastChat())

ok(#updaters == 0, "no position timer once the route is cleared")
-- standing off the paths: one recalculation, then quiet until the player moves
do
    local node = placeNode("Lakeshire", "Redridge Mountains")
    placeAt(goldshire); Core:SetDestination(node, "Lakeshire"); Core:SetMode("run")
    ok(#updaters == 1, "position timer runs while routing")
    S.px = S.px + 0.08; S.py = S.py + 0.08
    local before = Core.replans
    advance(30)
    ok(Core.replans - before <= 1, "standing off route replans at most once: " .. (Core.replans - before))
    Core:ClearRoute()
end

-- ---------------------------------------------------------------- 6. pin drop
WorldMapFrame:Show()
WorldMapFrame.mapID = 1436 -- Westfall
local handled = rightClick(0.56, 0.48)
ok(handled and _G.ForeverMapsPinMenu:IsShown(), "right-click world map opens Route here menu")
local pinMenu = _G.ForeverMapsPinMenu
-- first button child is "Route here": invoke via stored menu data
Core:SetDestinationAtMap(pinMenu.mapID, pinMenu.nx, pinMenu.ny)
ok(Core.dest and Core.dest.name == "Pin in Westfall", "pin destination set: " .. tostring(Core.dest and Core.dest.name))
UI:DrawMapRoute()
ok((UI.mapLayer and UI.mapLayer.lines or 0) > 0, "route line drawn on world map: " .. tostring(UI.mapLayer and UI.mapLayer.lines))
WorldMapFrame.mapID = 99999
ok(not rightClick(0.5, 0.5), "unknown map: right-click falls through to normal zoom-out")
Core:ClearRoute()


-- ---------------------------------------------------------------- 6b. OpenMap (stitched world map)
do
    -- OpenMap's real behaviour: a click handler at priority 1000 that takes every click, art above
    -- the canvas, and the map underneath only the part the view is on (here Elwynn while we look
    -- at Westfall). API v4 as in openmap-world/openmap.
    local om = { stitched = true, zoomOuts = 0, cbs = {} }
    WorldMapFrame:AddCanvasClickHandler(function(_, btn)
        if not om.stitched then return false end
        if btn == "RightButton" then om.zoomOuts = om.zoomOuts + 1 end
        return true
    end, 1000)
    local westfall = zoneMap("Westfall")
    OpenMapAPI = { major = 1, version = 4,
        IsStitched = function() return om.stitched end,
        CursorPosition = function() return 0.40, 0.70 end,
        MapAt = function() return westfall end,
        MapFromWorld = function(id, u, v) return 0.56, 0.48 end,
        ArtTopLevel = function() return 2100 end,
        CanvasFromWorldPos = function(c, x, y) om.asked = (om.asked or 0) + 1; om.cont = c; return 1.6, -0.3 + (om.asked % 7) * 0.2 end,
        RegisterCallback = function(owner, ev, m) om.cbs[ev] = function(...) owner[m](owner, ...) end end,
    }
    UI.omHooked = nil; UI:HookOpenMap()
    WorldMapFrame.mapID = zoneMap("Elwynn Forest")
    _G.ForeverMapsPinMenu:Hide()
    ok(rightClick(0.1, 0.1) and _G.ForeverMapsPinMenu:IsShown(), "OpenMap: right-click still opens Route here")
    ok(om.zoomOuts == 0, "OpenMap: its zoom-out doesn't eat the right-click first")
    local pm = _G.ForeverMapsPinMenu
    ok(pm.mapID == westfall and pm.nx == 0.56 and pm.ny == 0.48, "OpenMap: pin is the zone under the cursor, not the map underneath: " .. tostring(pm.mapID))
    Core:SetDestinationAtMap(pm.mapID, pm.nx, pm.ny)
    ok(Core.dest and Core.dest.name == "Pin in Westfall", "OpenMap: pin destination set in Westfall")
    -- Zoom out on our menu hands the click to OpenMap
    local zo = 0
    for _, c in ipairs(allFrames) do if c.parent == pm and c.kind == "Button" then zo = zo + 1; if zo == 2 then c:Click() end end end
    ok(om.zoomOuts == 1 and not WorldMapFrame.navigatedUp, "OpenMap: Zoom out goes to OpenMap's zoom, once")
    om.asked = 0; UI.mapLayer = nil
    WorldMapFrame.canvas = nil
    UI.mapLines = {}
    UI:DrawMapRoute()
    local lines = UI.mapLayer and UI.mapLayer.lines or 0
    ok((om.asked or 0) > 0 and om.cont == 0, "OpenMap: route placed by OpenMap's CanvasFromWorldPos on Eastern Kingdoms: " .. tostring(om.cont))
    ok(lines > 0, "OpenMap: route lines drawn off the map underneath too: " .. lines)
    ok(UI.mapLayer.level == 2101, "OpenMap: route layer above OpenMap's art: " .. tostring(UI.mapLayer.level))
    local before = om.asked
    om.cbs.OpenMap_ViewChanged(0.4, 0.7, 3)
    ok(om.asked > before, "OpenMap: route redrawn when its view pans/zooms")
    -- OpenMap installed but showing Blizzard's map: old behaviour
    om.stitched = false
    WorldMapFrame.mapID = westfall; WorldMapFrame.navigatedUp = nil
    ok(rightClick(0.56, 0.48) and pm.mapID == westfall and pm.nx == 0.56, "OpenMap off: right-click uses the click on the map")
    om.asked = 0; UI:DrawMapRoute()
    ok(om.asked == 0, "OpenMap off: route placed on Blizzard's map as before")
    Core:ClearRoute()
    OpenMapAPI = nil
    for i = #clickHandlers, 1, -1 do if clickHandlers[i].prio == 1000 then table.remove(clickHandlers, i) end end
    pm:Hide()
end

-- ---------------------------------------------------------------- 7. horde
S.faction = "Horde"
ForeverMapsCharDB = nil; Core:InitDB()
for _, id in ipairs(fmNodesFor(2)) do Core.db.known[id] = true end
Core.db.captured = true
local xroads = placeNode("Crossroads", "The Barrens")
placeAt(xroads)
Core:SetDestination(placeNode("Thunder Bluff", "Thunder Bluff"), "Thunder Bluff")
Core:SetMode("fly")
local hf = Core:Current()
ok(hf and hf.seconds < Core.route.run.seconds, "horde flies Crossroads->Thunder Bluff faster than running")
for _, s in ipairs(hf.steps) do
    if s.kind == "fly" then for _, p in ipairs(s.points) do ok(W.fm[p][2] % 4 >= 2, "horde uses horde/neutral masters") end end
end
UI:ToggleFlightList(); UI:ToggleFlightList()
local allyShown = false
for _, row in ipairs(UI.flist.rows) do if row:IsShown() and row.entry and W.fm[row.entry.node][2] == 1 then allyShown = true end end
ok(not allyShown, "horde list hides alliance-only masters")
S.faction = "Alliance"
Core:Replan("test")
local af = Core:Current()
local allyUsesFlight = false
for _, s in ipairs(af and af.steps or {}) do if s.kind == "fly" then allyUsesFlight = true end end
ok(not allyUsesFlight, "alliance at Crossroads gets no horde flights")

-- ---------------------------------------------------------------- 7b. resize / no overlap
do
    S.faction = "Alliance"
    Core.db.window = nil
    placeAt(goldshire)
    Core:SetDestination(placeNode("Gadgetzan", "Tanaris"), "Gadgetzan")
    Core:SetMode("boat")
    local f = UI.frame
    ok(UI.grip ~= nil, "resize grip exists")
    local function shownLines() local n = 0 for _, l in ipairs(UI.lines) do if l:IsShown() and (l.text or "") ~= "" then n = n + 1 end end return n end
    f:SetSize(300, 300); UI:Layout()
    local small, hidSmall = shownLines(), UI.hiddenSteps
    local noteSmall = UI.lines[small] and UI.lines[small].text or ""
    f:SetSize(500, 800); UI:Layout()
    local big, hidBig = shownLines(), UI.hiddenSteps
    ok(big >= small, "taller window shows more steps: " .. small .. " -> " .. big)
    ok(hidSmall > 0 and noteSmall:find("more step") ~= nil, "small window: hidden steps get a '+ N more' note instead of overlapping")
    ok(hidBig == 0, "big window shows every step")
    -- no step line may reach the bottom bar: total height used <= room
    f:SetSize(300, 300); UI:Layout()
    local used = 0
    for _, l in ipairs(UI.lines) do if l:IsShown() and (l.text or "") ~= "" then used = used + l:GetStringHeight() + 4 end end
    local top = 130 + UI.next:GetHeight() + 6 + ((UI.warn.text or "") ~= "" and UI.warn:GetStringHeight() + 4 or 0)
    ok(top + used <= 300 - 40, "steps stay above the Clear button: " .. (top + used) .. " <= 260")
    local f2 = UI.frame.scripts.OnDragStop; f2()
    ok(Core.db.window and Core.db.window.w == 300, "window size saved")
    Core:ClearRoute()
end

-- ---------------------------------------------------------------- 8. slash + no location
Core:SetDestination(placeNode("Lakeshire", "Redridge Mountains"), "Lakeshire")
S.map = nil
Core:Replan("test")
ok(Core.status and Core.status:find("location"), "no position: friendly status: " .. tostring(Core.status) .. " dest " .. tostring(Core.dest))
SlashCmdList.FOREVERMAPS("")
ok(true, "slash toggles without error")

print(string.format("RESULT: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
