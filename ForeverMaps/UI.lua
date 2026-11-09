-- Forever Maps UI (layout B): floating window, search, three mode tabs,
-- next-step box with arrow, flight path toggles, welcome popup (style A),
-- world-map right-click "Route here" and route line.
local _, ns = ...
local R, W, Core = ns.Router, ns.World, ns.Core
local UI = {}
ns.UI = UI

local GOLD = { 0.94, 0.75, 0.31 }
local MODES = { { "run", "Run" }, { "fly", "Fly" }, { "boat", "Boat" } }

local function fmtTime(s)
    if not s then return "-" end
    s = math.floor(s + 0.5)
    if s >= 3600 then return string.format("%dh %02dm", math.floor(s / 3600), math.floor(s % 3600 / 60)) end
    if s >= 60 then return string.format("%dm %02ds", math.floor(s / 60), s % 60) end
    return s .. "s"
end
UI.fmtTime = fmtTime

local function backdrop(f, alpha)
    if not f.SetBackdrop and BackdropTemplateMixin then Mixin(f, BackdropTemplateMixin) end
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.08, 0.06, 0.04, alpha or 0.92)
        f:SetBackdropBorderColor(0.78, 0.59, 0.18, 1)
    end
end

local function label(parent, size, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", size == "big" and "GameFontNormalLarge"
        or size == "small" and "GameFontHighlightSmall" or "GameFontHighlight")
    if text then fs:SetText(text) end
    return fs
end

local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 90, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- ---------------------------------------------------------------- main window
function UI:Init()
    if self.frame then return end
    local f = CreateFrame("Frame", "ForeverMapsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.frame = f
    local saved = Core.db.window
    f:SetSize(saved and saved.w or 300, saved and saved.h or 360)
    if saved and saved.x then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
    end
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(280, 300, 800, 900)
    elseif f.SetMinResize then f:SetMinResize(280, 300); f:SetMaxResize(800, 900) end
    local function save()
        Core.db.window = { w = f:GetWidth(), h = f:GetHeight(), x = f:GetLeft(), y = f:GetTop() }
    end
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing(); save() end)
    -- drag the bottom-right corner to make the window wider or longer
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); save(); UI:Layout() end)
    self.grip = grip
    f:SetScript("OnSizeChanged", function() UI:Layout() end)
    f:SetFrameStrata("MEDIUM")
    backdrop(f)
    f:Hide()

    local title = label(f, "big", "Forever Maps")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetTextColor(unpack(GOLD))
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local fp = button(f, "Flight paths", 90, function() UI:ToggleFlightList() end)
    fp:SetPoint("TOPRIGHT", -28, -8)

    -- search box
    local box = CreateFrame("EditBox", "ForeverMapsSearch", f, "InputBoxTemplate")
    self.box = box
    box:SetHeight(22)
    box:SetPoint("TOPLEFT", 16, -38)
    box:SetPoint("TOPRIGHT", -14, -38)
    box:SetAutoFocus(false)
    box:SetScript("OnTextChanged", function(b, user) if user then UI:Suggest(b:GetText()) end end)
    box:SetScript("OnEnterPressed", function(b) UI:SearchAndGo(b:GetText()); b:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(b) b:ClearFocus(); UI:HideSuggest() end)
    local hint = label(box, "small", "Where to?")
    hint:SetPoint("LEFT", 4, 0); hint:SetTextColor(0.6, 0.55, 0.45)
    box.hint = hint
    box:SetScript("OnEditFocusGained", function() hint:Hide() end)
    box:SetScript("OnEditFocusLost", function(b) if b:GetText() == "" then hint:Show() end end)

    -- from line
    local from = label(f, "small", "")
    from:SetPoint("TOPLEFT", 14, -66)
    from:SetPoint("TOPRIGHT", -14, -66)
    from:SetJustifyH("LEFT"); from:SetWordWrap(false)
    self.from = from

    -- mode tabs
    self.tabs = {}
    for i, m in ipairs(MODES) do
        local t = CreateFrame("Button", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
        t:SetSize(88, 40)
        t.index = i
        backdrop(t, 0.7)
        t.name = label(t, nil, m[2]); t.name:SetPoint("TOP", 0, -6)
        t.time = label(t, "small", "-"); t.time:SetPoint("BOTTOM", 0, 6)
        t.mode = m[1]
        t:SetScript("OnClick", function() Core:SetMode(m[1]) end)
        self.tabs[m[1]] = t
    end

    -- next step box
    local ns_ = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.next = ns_
    ns_:SetHeight(70)
    ns_:SetPoint("TOPLEFT", 12, -130)
    ns_:SetPoint("TOPRIGHT", -12, -130)
    backdrop(ns_, 0.95)
    local arrow = ns_:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow:SetSize(44, 44)
    arrow:SetPoint("LEFT", 10, 0)
    self.arrow = arrow
    local head = label(ns_, nil, ""); head:SetPoint("TOPLEFT", 62, -10); head:SetPoint("TOPRIGHT", -10, -10); head:SetJustifyH("LEFT")
    local dist = label(ns_, "big", ""); dist:SetPoint("BOTTOMLEFT", 62, 10)
    self.head, self.dist = head, dist

    -- warning + step list
    local warn = label(f, "small", ""); warn:SetPoint("TOPLEFT", ns_, "BOTTOMLEFT", 2, -6)
    warn:SetPoint("TOPRIGHT", ns_, "BOTTOMRIGHT", -2, -6); warn:SetJustifyH("LEFT")
    warn:SetTextColor(1, 0.45, 0.3)
    self.warn = warn
    self.lines = {}
    for i = 1, 20 do
        local l = label(f, "small", "")
        local prev = self.lines[i - 1] or warn
        l:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
        l:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -4)
        l:SetJustifyH("LEFT")
        self.lines[i] = l
    end
    local banner = label(f, "small", "")
    banner:SetPoint("BOTTOMLEFT", 14, 12); banner:SetJustifyH("LEFT")
    banner:SetTextColor(unpack(GOLD))
    self.banner = banner
    local clear = button(f, "Clear", 60, function() Core:ClearRoute() end)
    clear:SetPoint("BOTTOMRIGHT", -22, 10)
    banner:SetPoint("RIGHT", clear, "LEFT", -8, 0)

    self:InitSuggest()
    self:HookWorldMap()
    self:Layout()
    self:Refresh()
end

-- Re-flow the window for its current size.
function UI:Layout()
    local f = self.frame
    if not f then return end
    local w, h = f:GetWidth() or 300, f:GetHeight() or 360
    local tw = (w - 24 - 8) / 3
    for _, m in ipairs(MODES) do
        local t = self.tabs[m[1]]
        t:ClearAllPoints()
        t:SetSize(tw, 40)
        t:SetPoint("TOPLEFT", 12 + (t.index - 1) * (tw + 4), -84)
    end
    -- next-step box grows with a long instruction
    local hh = self.head:GetStringHeight() or 14
    self.next:SetHeight(math.max(70, hh + 44))
    -- show as many steps as fit above the bottom bar; never draw over it
    local top = 130 + math.max(70, hh + 44) + 6 + (self.warn:GetText() ~= "" and ((self.warn:GetStringHeight() or 12) + 4) or 0)
    local room = h - top - 40
    local texts = {}
    for _, l in ipairs(self.lines) do
        if l.full and l.full ~= "" then texts[#texts + 1] = l.full end
        l:SetText(""); l:Hide()
    end
    -- how many full steps fit
    local used, fit = 0, 0
    for i, t in ipairs(texts) do
        local l = self.lines[i]
        l:SetText(t)
        local lh = (l:GetStringHeight() or 12) + 4
        if used + lh > room then break end
        used = used + lh; fit = i
    end
    local hidden = #texts - fit
    if hidden > 0 then
        -- keep one line free for a "+ N more" note so nothing overlaps the bottom bar
        fit = math.max(fit - 1, 0); hidden = #texts - fit
    end
    for i = 1, fit do self.lines[i]:SetText(texts[i]); self.lines[i]:Show() end
    for i = fit + 1, #self.lines do self.lines[i]:SetText(""); self.lines[i]:Hide() end
    if hidden > 0 and room >= 16 then
        local l = self.lines[fit + 1]
        l:SetText(string.format("|cff998866+ %d more step%s (drag the corner to see all)|r", hidden, hidden == 1 and "" or "s"))
        l:Show()
    end
    self.hiddenSteps = hidden
end

function UI:Show() self:Init(); self.frame:Show(); self:Refresh() end
function UI:Toggle()
    self:Init()
    if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

-- ---------------------------------------------------------------- search
function UI:InitSuggest()
    local s = CreateFrame("Frame", nil, self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    s:SetPoint("TOPLEFT", self.box, "BOTTOMLEFT", -6, -2)
    s:SetPoint("TOPRIGHT", self.box, "BOTTOMRIGHT", 2, -2)
    s:SetHeight(8 * 18 + 8)
    s:SetFrameStrata("DIALOG")
    backdrop(s, 0.98)
    s:Hide()
    self.suggest = s
    s.rows = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, s)
        b:SetHeight(18)
        b:SetPoint("TOPLEFT", 5, -4 - (i - 1) * 18)
        b:SetPoint("TOPRIGHT", -5, -4 - (i - 1) * 18)
        b.text = label(b, "small", ""); b.text:SetPoint("LEFT", 2, 0); b.text:SetPoint("RIGHT", -2, 0)
        b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:SetScript("OnClick", function(btn) UI:Pick(btn.place) end)
        s.rows[i] = b
    end
end

function UI:Suggest(text)
    local res = R:Search(text, 8)
    self.results = res
    if #res == 0 then return self:HideSuggest() end
    for i, row in ipairs(self.suggest.rows) do
        local p = res[i]
        if p then
            local name, zone = R:Place(p)
            row.place = p
            row.text:SetText(name .. "  |cff998866" .. zone .. "|r")
            row:Show()
        else row:Hide() end
    end
    self.suggest:SetHeight(#res * 18 + 8)
    self.suggest:Show()
end

function UI:HideSuggest() if self.suggest then self.suggest:Hide() end end

function UI:Pick(p)
    local name, zone, node = R:Place(p)
    self.box:SetText(name)
    self:HideSuggest()
    Core.pin = nil
    Core:SetDestination(node, name)
end

function UI:SearchAndGo(text)
    local res = R:Search(text, 1)
    if res[1] then self:Pick(res[1]) else Core.chat("No place called \"" .. text .. "\".") end
end

-- ---------------------------------------------------------------- refresh
local function stepText(s)
    if s.kind == "fly" and s.hops and s.hops > 1 then return s.text .. " (" .. s.hops .. " hops)" end
    return s.text
end

function UI:Refresh()
    if not self.frame then return end
    local plans = Core.route
    for mode, t in pairs(self.tabs) do
        local r = plans and plans[mode]
        t.time:SetText(not r and "-" or r.unavailable and "|cff888888none|r" or fmtTime(r.seconds))
        if mode == Core.mode then t:SetBackdropBorderColor(1, 0.85, 0.3, 1) else t:SetBackdropBorderColor(0.4, 0.3, 0.15, 1) end
    end
    local dest = Core.dest
    self.from:SetText(dest and ("From your location  ->  |cffffd060" .. R.WithZone(dest.name, R.Zone(dest.node)) .. "|r") or (Core.status or "Search a place, or right-click the world map."))
    local r = Core:Current()
    for i, l in ipairs(self.lines) do l:SetText(""); l.full = nil end
    self.warn:SetText("")
    if not r then
        local u = plans and plans[Core.mode]
        self.head:SetText(u and u.unavailable and (u.unavailable .. " for this mode.") or (dest and Core.status or "No route yet."))
        self.dist:SetText("")
        self.arrow:Hide()
    else
        local s = r.steps[Core.step]
        self.head:SetText(s and stepText(s) or "You're there.")
        self.arrow:Show()
        if s and s.warning then self.warn:SetText("! " .. s.warning) end
        local shown = 0
        for k = Core.step + 1, #r.steps do
            shown = shown + 1
            if self.lines[shown] then
                self.lines[shown].full = string.format("%d. %s  |cff998866%s|r", k, stepText(r.steps[k]), fmtTime(r.steps[k].seconds))
            end
        end
        if r.note then self.warn:SetText(r.note) end
    end
    local banner = ""
    if not Core.db.captured then banner = "Visit a flight master to load your flight paths."
    elseif Core.mode == "fly" and r and r.tip then banner = r.tip end
    self.banner:SetText(banner)
    self:Layout()
    self:DrawMapRoute()
    if self.flist and self.flist:IsShown() then self:FillFlightList() end
end

function UI:UpdateLive(cc, x, y)
    local r = Core:Current()
    if not r or not self.frame or not self.frame:IsShown() then return end
    local s = r.steps[Core.step]
    if not s then return end
    if s ~= self.lastStep then self.lastStep = s; self:Refresh() end
    local wp = R:NextWaypoint(s, x, y)
    local dx, dy = W.nx[wp] - x, W.ny[wp] - y
    local facing = GetPlayerFacing and GetPlayerFacing()
    if facing and s.kind == "run" then
        local ang = math.atan2(dy, dx) - facing
        self.arrow:SetRotation(ang)
        self.arrow:Show()
    else
        self.arrow:Hide()
    end
    self.dist:SetText(string.format("%d yd", math.floor((Core.toEnd or 0) + 0.5)))
end

function UI:OnFlightDataChanged()
    if self.welcome then self.welcome:Hide() end
    self:Refresh()
end

-- ---------------------------------------------------------------- flight list
function UI:ToggleFlightList()
    if not self.flist then self:BuildFlightList() end
    if self.flist:IsShown() then self.flist:Hide() else self.flist:Show(); self:FillFlightList() end
end

function UI:BuildFlightList()
    local f = CreateFrame("Frame", "ForeverMapsFlights", self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.flist = f
    f:SetWidth(260)
    f:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", -4, 0)
    f:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMLEFT", -4, 0)
    backdrop(f)
    local t = label(f, nil, "Flight paths"); t:SetPoint("TOPLEFT", 12, -10); t:SetTextColor(unpack(GOLD))
    local h = label(f, "small", "Ticked = the route may use it"); h:SetPoint("TOPLEFT", 12, -26)
    local sf = CreateFrame("ScrollFrame", "ForeverMapsFlightScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -44); sf:SetPoint("BOTTOMRIGHT", -28, 8)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(220, 10)
    sf:SetScrollChild(child)
    f.child = child
    f.rows = {}
    f:Hide()
end

function UI:FlightEntries()
    local bit = (Core:Faction())
    local druid = Core:IsDruid()
    local list = {}
    for node, info in pairs(W.fm) do
        if info[2] % (2 * bit) >= bit and (not info[3] or druid) then
            list[#list + 1] = { node = node, id = info[1], name = (W.nname[node] or "?"):gsub(",.*$", ""), zone = R.Zone(node) }
        end
    end
    table.sort(list, function(a, b) if a.zone ~= b.zone then return a.zone < b.zone end return a.name < b.name end)
    return list
end

function UI:FillFlightList()
    local f = self.flist
    local list = self:FlightEntries()
    local y, i, lastZone = 0, 0, nil
    for _, e in ipairs(list) do
        if e.zone ~= lastZone then
            i = i + 1
            local row = f.rows[i] or self:FlightRow(i)
            row.check:Hide(); row.text:SetText("|cffffd060" .. e.zone .. "|r"); row.entry = nil
            row:SetPoint("TOPLEFT", 0, -y); row:Show()
            y = y + 18; lastZone = e.zone
        end
        i = i + 1
        local row = f.rows[i] or self:FlightRow(i)
        row.entry = e
        row.check:Show(); row.check:SetChecked(Core:Knows(e.id))
        local tag = Core.db.override[e.id] ~= nil and " |cff998866(set by you)|r" or ""
        row.text:SetText(e.name .. tag)
        row:SetPoint("TOPLEFT", 0, -y); row:Show()
        y = y + 18
    end
    for k = i + 1, #f.rows do f.rows[k]:Hide() end
    f.child:SetHeight(math.max(y, 10))
end

function UI:FlightRow(i)
    local f = self.flist
    local row = CreateFrame("Frame", nil, f.child)
    row:SetSize(220, 18)
    local c = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    c:SetSize(20, 20); c:SetPoint("LEFT", 0, 0)
    c:SetScript("OnClick", function(btn)
        local e = row.entry
        if e then Core:SetOverride(e.id, btn:GetChecked() and true or false); UI:FillFlightList() end
    end)
    row.check = c
    row.text = label(row, "small", ""); row.text:SetPoint("LEFT", 22, 0); row.text:SetWidth(196); row.text:SetJustifyH("LEFT")
    f.rows[i] = row
    return row
end

-- ---------------------------------------------------------------- welcome popup (style A)
function UI:ShowWelcome()
    self:Init()
    local w = self.welcome
    if not w then
        w = CreateFrame("Frame", "ForeverMapsWelcome", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        self.welcome = w
        w:SetSize(340, 190)
        w:SetPoint("CENTER", 0, 80)
        w:SetFrameStrata("DIALOG")
        backdrop(w, 0.97)
        local t = label(w, "big", "Welcome to Forever Maps"); t:SetPoint("TOP", 0, -14); t:SetTextColor(unpack(GOLD))
        local body = label(w, nil, "Talk to |cffffd060any flight master once|r so Forever Maps can see which flight paths you've learned.")
        body:SetPoint("TOP", 0, -40); body:SetWidth(300)
        w.near = label(w, "small", ""); w.near:SetPoint("TOP", 0, -88); w.near:SetWidth(300)
        local go = button(w, "Route there", 100, function()
            if w.fm then Core.pin = nil; Core:SetDestination(w.fm, "Flight master: " .. R.Label(w.fm)); Core:SetMode("run"); UI:Show() end
            w:Hide()
        end)
        go:SetPoint("BOTTOMLEFT", 16, 16)
        local ok = button(w, "Got it", 90, function() Core.db.popupDone = true; w:Hide() end)
        ok:SetPoint("BOTTOM", 0, 16)
        local later = button(w, "Later", 90, function() w:Hide() end)
        later:SetPoint("BOTTOMRIGHT", -16, 16)
        w.go = go
    end
    local cc, x, y = Core:PlayerPosition()
    local fm, d
    if cc then fm, d = R:NearestFlightMaster(cc, x, y, (Core:Faction()), Core:IsDruid()) end
    w.fm = fm
    if fm then
        w.near:SetText(string.format("Nearest: |cffffd060%s|r  ·  %d yd", (W.nname[fm] or ""):gsub(",.*$", ""), math.floor(d + 0.5)))
        w.go:Enable()
    else
        w.near:SetText("No flight master found nearby.")
        w.go:Disable()
    end
    w:Show()
end

-- ---------------------------------------------------------------- world map
function UI:HookWorldMap()
    if self.mapHooked or not WorldMapFrame then return end
    self.mapHooked = true
    local menu = CreateFrame("Frame", "ForeverMapsPinMenu", WorldMapFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetSize(130, 52); menu:SetFrameStrata("TOOLTIP"); backdrop(menu, 0.98); menu:Hide()
    local here = CreateFrame("Button", nil, menu)
    here:SetSize(120, 20); here:SetPoint("TOP", 0, -5)
    here.t = label(here, nil, "Route here"); here.t:SetPoint("LEFT", 6, 0); here.t:SetTextColor(unpack(GOLD))
    here:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    here:SetScript("OnClick", function()
        menu:Hide()
        Core:SetDestinationAtMap(menu.mapID, menu.nx, menu.ny)
        UI:Show()
    end)
    local out = CreateFrame("Button", nil, menu)
    out:SetSize(120, 20); out:SetPoint("TOP", 0, -27)
    out.t = label(out, nil, "Zoom out"); out.t:SetPoint("LEFT", 6, 0)
    out:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    out:SetScript("OnClick", function() menu:Hide(); WorldMapFrame:NavigateToParentMap() end)
    self.pinMenu = menu
    WorldMapFrame:AddCanvasClickHandler(function(map, btn, cx, cy)
        if btn == "RightButton" then
            local mapID = map:GetMapID()
            if not Core:MapToWorld(mapID, cx, cy) then return false end
            menu.mapID, menu.nx, menu.ny = mapID, cx, cy
            local scale = UIParent:GetEffectiveScale()
            local mx, my = GetCursorPosition()
            menu:ClearAllPoints()
            menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx / scale + 4, my / scale - 4)
            menu:Show()
            return true
        end
        menu:Hide()
        return false
    end)
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function() UI:DrawMapRoute() end)
    WorldMapFrame:HookScript("OnShow", function() UI:DrawMapRoute() end)
    WorldMapFrame:HookScript("OnHide", function() menu:Hide() end)
    self.mapLines = {}
end

-- Draw the active route on the world map canvas as line segments.
function UI:DrawMapRoute()
    if not self.mapHooked or not WorldMapFrame:IsShown() then return end
    for _, l in ipairs(self.mapLines) do l:Hide() end
    local r = Core:Current()
    if not r then return end
    local canvas = WorldMapFrame:GetCanvas()
    local mapID = WorldMapFrame:GetMapID()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local used = 0
    local COLORS = { run = { 0.3, 0.8, 1 }, fly = { 1, 0.82, 0.25 }, boat = { 0.4, 1, 0.5 }, zeppelin = { 0.4, 1, 0.5 }, tram = { 0.8, 0.6, 1 } }
    for k = Core.step, #r.steps do
        local s = r.steps[k]
        local pts = s.points
        local col = COLORS[s.kind] or COLORS.run
        local last
        for j = 1, #pts do
            local p = pts[j]
            local nx, ny = Core:WorldToMap(mapID, R.Continent(p), W.nx[p], W.ny[p])
            if nx and nx >= -0.05 and nx <= 1.05 and ny >= -0.05 and ny <= 1.05 then
                if last and (math.abs(nx - last[1]) + math.abs(ny - last[2]) > 0.004 or j == #pts) then
                    used = used + 1
                    local l = self.mapLines[used]
                    if not l then
                        l = canvas:CreateLine(nil, "OVERLAY")
                        l:SetTexture("Interface\\Buttons\\WHITE8X8")
                        self.mapLines[used] = l
                    end
                    l:SetThickness(s.kind == "run" and 3 or 2)
                    l:SetColorTexture(col[1], col[2], col[3], 0.9)
                    l:SetStartPoint("TOPLEFT", canvas, last[1] * w, -last[2] * h)
                    l:SetEndPoint("TOPLEFT", canvas, nx * w, -ny * h)
                    l:Show()
                    last = { nx, ny }
                elseif not last then
                    last = { nx, ny }
                end
            else
                last = nil
            end
        end
    end
end
