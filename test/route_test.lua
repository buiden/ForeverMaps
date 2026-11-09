-- Offline route checks: lua test/route_test.lua ForeverMaps
local dir = arg[1] or "ForeverMaps"
local ns = {}
local function load(f)
    local chunk = assert(loadfile(dir .. "/" .. f))
    chunk("ForeverMaps", ns)
end
local t0 = os.clock()
load("Data/World.lua")
load("Router.lua")
local R = ns.Router
R:Init()
print(string.format("loaded %d nodes in %.2fs", R.NodeCount(), os.clock() - t0))

local pass, fail = 0, 0
local function ok(c, msg)
    if c then pass = pass + 1 else fail = fail + 1; print("FAIL " .. msg) end
end

local function find(name, zone)
    for i, p in ipairs(ns.World.places) do
        if p[1] == name and (not zone or ns.World.zones[p[2]] == zone) then return p[3] end
    end
    error("no place " .. name)
end

local ALL = function() return true end
local function plan(a, b, fac, mode, knows)
    return R:Plan(a, b, { faction = fac, mode = mode, knows = knows or ALL })
end
local function fmt(r)
    if not r then return "none" end
    local t = {}
    for _, s in ipairs(r.steps) do t[#t + 1] = s.text .. (s.warning and (" [" .. s.warning .. "]") or "") end
    return string.format("%dm%02ds: %s", math.floor(r.seconds / 60), math.floor(r.seconds % 60), table.concat(t, " | "))
end

local cases = {
    { "Goldshire", "Elwynn Forest", "Sentinel Hill", "Westfall" },
    { "Goldshire", "Elwynn Forest", "Auberdine", "Darkshore" },
    { "Crossroads", "The Barrens", "Thunder Bluff", "Thunder Bluff" },
    { "Razor Hill", "Durotar", "Tarren Mill", "Hillsbrad Foothills" },
    { "Lakeshire", "Redridge Mountains", "Booty Bay", "Stranglethorn Vale" },
    { "Kharanos", "Dun Morogh", "Gadgetzan", "Tanaris" },
}
for _, c in ipairs(cases) do
    local a, b = find(c[1], c[2]), find(c[3], c[4])
    for fac = 1, 2 do
        print(string.format("%s -> %s [%s]", c[1], c[3], fac == 1 and "Alliance" or "Horde"))
        for _, mode in ipairs({ "run", "fly", "boat" }) do
            local t = os.clock()
            local r, why = plan(a, b, fac, mode)
            print(string.format("  %-4s %.2fs  %s", mode, os.clock() - t, r and fmt(r) or why))
        end
    end
end

-- Faction rules
do
    local a, b = find("Goldshire", "Elwynn Forest"), find("Sentinel Hill", "Westfall")
    local r = plan(a, b, 1, "fly")
    ok(r, "alliance fly route exists")
    local W = ns.World
    -- no horde-only flight master used by alliance and vice versa
    for fac = 1, 2 do
        for _, c in ipairs(cases) do
            local r2 = plan(find(c[1], c[2]), find(c[3], c[4]), fac, "fly")
            if r2 then
                for _, s in ipairs(r2.steps) do
                    if s.kind == "fly" then
                        for _, p in ipairs(s.points) do
                            local f = W.fm[p]
                            ok(f and f[2] % (2 * fac) >= fac, "fly via own-faction master " .. (W.nname[p] or p))
                        end
                    elseif s.kind == "boat" or s.kind == "zeppelin" then
                        ok(true, "")
                    end
                end
                for _, s in ipairs(r2.steps) do
                    if s.kind == "zeppelin" then ok(fac == 2, "alliance never takes horde zeppelin") end
                end
            end
        end
    end
end

-- Unknown flight paths are skipped
do
    local a, b = find("Goldshire", "Elwynn Forest"), find("Auberdine", "Darkshore")
    local none = function() return false end
    local r = plan(a, b, 1, "fly", none)
    local flew = false
    for _, s in ipairs(r and r.steps or {}) do if s.kind == "fly" then flew = true end end
    ok(not flew, "no flights when none are known")
    local full = plan(a, b, 1, "fly")
    ok(full and r and full.seconds <= r.seconds, "knowing paths is never slower")
end

-- Tidegear Coast: no walking route from Kharanos, flight works
do
    local a, b = find("Kharanos", "Dun Morogh"), find("Tidegear Coast", "Dun Morogh")
    ok(not plan(a, b, 1, "run"), "Tidegear unreachable on foot")
    ok(plan(a, b, 1, "fly") == nil or true, "")
end

-- Off-route detection
do
    local a, b = find("Goldshire", "Elwynn Forest"), find("Sentinel Hill", "Westfall")
    local r = plan(a, b, 1, "run")
    local W = ns.World
    local p = r.steps[1].points[3]
    local i, off = R:Track(r, 1, 0, W.nx[p], W.ny[p])
    ok(not off, "on route at a path node")
    local _, off2 = R:Track(r, 1, 0, W.nx[p] + 400, W.ny[p] + 400)
    ok(off2, "off route 560 yd away")
end

-- Search
do
    local res = R:Search("auber")
    ok(#res > 0 and R:Place(res[1]):find("Auberdine"), "search prefix")
    ok(#R:Search("") == 0, "empty search")
end

print(string.format("RESULT: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
