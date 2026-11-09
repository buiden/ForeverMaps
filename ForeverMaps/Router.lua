-- Forever Maps route engine: one graph of walking links, flight paths and
-- boats/zeppelins/tram; Dijkstra per travel mode, filtered by faction and by
-- the flight paths the character knows.
local _, ns = ...
local W = ns.World
local R = {}
ns.Router = R

local floor, sqrt, huge = math.floor, math.sqrt, math.huge

R.RUN_SPEED = 7.0        -- yards per second on foot
R.FLY_SPEED = 30.4       -- yards per second on a flight path
R.FLY_OVERHEAD = 10      -- seconds to talk to the flight master, take off and land
R.HOSTILE_PENALTY = 2.5  -- running through enemy towns/guards costs this much more
R.ARRIVE_RADIUS = 25     -- yards from a step's end that counts as reached

local N                      -- node count
local cont, zone, kind, fac  -- decoded node metadata
local walk, flyOut, trans    -- adjacency
local comp                   -- ground piece id per node
local fmByTaxi = {}          -- taxi node id -> graph node

local function dist(a, b)
    local dx, dy = W.nx[a] - W.nx[b], W.ny[a] - W.ny[b]
    return sqrt(dx * dx + dy * dy)
end
R.dist = dist

function R:Init()
    if N then return end
    N = #W.nx
    cont, zone, kind, fac = {}, {}, {}, {}
    for i = 1, N do
        local m = W.nmeta[i]
        cont[i] = floor(m / 1000000)
        zone[i] = floor(m / 1000) % 1000
        kind[i] = floor(m / 10) % 100
        fac[i] = m % 10
    end
    walk, flyOut, trans = {}, {}, {}
    for i = 1, N do walk[i] = {} end
    local E = W.edges
    for j = 1, #E, 3 do
        local a, b, f = E[j], E[j + 1], E[j + 2]
        local len = dist(a, b)
        local wa, wb = walk[a], walk[b]
        wa[#wa + 1] = b; wa[#wa + 1] = f; wa[#wa + 1] = len
        wb[#wb + 1] = a; wb[#wb + 1] = f; wb[#wb + 1] = len
    end
    local F = W.flights
    for j = 1, #F, 3 do
        local a = F[j]
        flyOut[a] = flyOut[a] or {}
        local t = flyOut[a]
        t[#t + 1] = F[j + 1]; t[#t + 1] = F[j + 2]
    end
    for ti, t in ipairs(W.transports) do
        local a, b = t[1], t[2]
        trans[a] = trans[a] or {}; trans[b] = trans[b] or {}
        local ta, tb = trans[a], trans[b]
        ta[#ta + 1] = b; ta[#ta + 1] = ti
        tb[#tb + 1] = a; tb[#tb + 1] = ti
    end
    for node, info in pairs(W.fm) do fmByTaxi[info[1]] = node end
    -- connected pieces of ground (tram joins two cities): lets a run search
    -- that can't succeed stop at once instead of exploring the whole world
    comp = {}
    local stack, c = {}, 0
    for s0 = 1, N do
        if not comp[s0] then
            c = c + 1
            comp[s0] = c
            stack[1] = s0
            local top = 1
            while top > 0 do
                local u = stack[top]; stack[top] = nil; top = top - 1
                local w = walk[u]
                for j = 1, #w, 3 do
                    local v = w[j]
                    if not comp[v] then comp[v] = c; top = top + 1; stack[top] = v end
                end
                local t = trans[u]
                if t then
                    for j = 1, #t, 2 do
                        local v = t[j]
                        if W.transports[t[j + 1]][3] == "tram" and not comp[v] then
                            comp[v] = c; top = top + 1; stack[top] = v
                        end
                    end
                end
            end
        end
    end
end

function R.NodeCount() return N end
function R.Continent(i) return cont[i] end
function R.Zone(i) return W.zones[zone[i]] end
function R.Kind(i) return W.kinds[kind[i] + 1] end
function R.Name(i) return W.nname[i] end
function R.FlightNodeFor(taxiID) return fmByTaxi[taxiID] end
function R.TaxiID(i) local f = W.fm[i]; return f and f[1] end

-- Continent ids used by the data: 0 Eastern Kingdoms, 1 Kalimdor, 2 Zephras Isle, 3 Darkspear Islands.
local CONT_CODE = { [0] = 0, [1] = 1, [2991] = 2, [2997] = 3 }
R.CONT_CODE = CONT_CODE

-- Nearest node with walking links on the same continent.
function R:Snap(cc, x, y)
    self:Init()
    local best, bd = nil, huge
    local nx, ny = W.nx, W.ny
    for i = 1, N do
        if cont[i] == cc and #walk[i] > 0 and not W.terminal[i] then
            local dx, dy = nx[i] - x, ny[i] - y
            local d = dx * dx + dy * dy
            if d < bd then bd, best = d, i end
        end
    end
    return best, best and sqrt(bd)
end

-- ---------------------------------------------------------------- heap
local hk, hv, hn = {}, {}, 0
local function push(k, v)
    hn = hn + 1
    local i = hn
    while i > 1 do
        local p = floor(i / 2)
        if hk[p] <= k then break end
        hk[i], hv[i] = hk[p], hv[p]
        i = p
    end
    hk[i], hv[i] = k, v
end
local function pop()
    local k0, v0 = hk[1], hv[1]
    local k, v = hk[hn], hv[hn]
    hk[hn], hv[hn] = nil, nil
    hn = hn - 1
    local i = 1
    while true do
        local c = i * 2
        if c > hn then break end
        if c < hn and hk[c + 1] < hk[c] then c = c + 1 end
        if hk[c] >= k then break end
        hk[i], hv[i] = hk[c], hv[c]
        i = c
    end
    if hn > 0 then hk[i], hv[i] = k, v end
    return k0, v0
end

-- ---------------------------------------------------------------- search
-- Work tables are reused between searches; G[v] == gen marks entries that
-- belong to the current search, so nothing is allocated per search.
local G_, D_, P_, H_, F_, gen = {}, {}, {}, {}, {}, 0
-- opts: faction (1 Alliance, 2 Horde), mode ("run" | "fly" | "boat"),
--       knows(taxiID) -> bool, druid (bool), hasKey (bool), speed (yd/s)
local function search(src, dst, o)
    local speed = o.speed or R.RUN_SPEED
    local myBit = o.faction
    local hostileBit = myBit == 1 and 8 or 16
    local useFly = o.mode == "fly"
    local useBoat = o.mode == "boat" or o.mode == "fly"
    if o.mode == "run" and comp[src] ~= comp[dst] then return nil end
    gen = gen + 1
    local G, D, P, H, F = G_, D_, P_, H_, F_
    G[src], D[src], P[src], H[src] = gen, 0, false, 0
    hn = 0
    push(0, src)
    while hn > 0 do
        local du, u = pop()
        if du <= D[u] then
            if u == dst then break end
            -- walking: boarding-only dock nodes are not walked through
            if not W.terminal[u] or u == src or H[u] == 2 then
                local w = walk[u]
                for j = 1, #w, 3 do
                    local v, f, len = w[j], w[j + 1], w[j + 2]
                    if not (f >= 32 and f % 64 >= 32 and not o.hasKey) then
                        local c = len / speed
                        if f % 32 >= 8 and floor(f / 8) % 4 == (hostileBit == 8 and 1 or 2) then
                            c = c * R.HOSTILE_PENALTY
                        end
                        local nd = du + c
                        if G[v] ~= gen or nd < D[v] then
                            G[v], D[v], P[v], H[v], F[v] = gen, nd, u, 0, f
                            push(nd, v)
                        end
                    end
                end
            end
            if useFly then
                local t = flyOut[u]
                local fu = W.fm[u]
                if t and fu and fu[2] % (2 * myBit) >= myBit and (not fu[3] or o.druid) and o.knows(fu[1]) then
                    for j = 1, #t, 2 do
                        local v, yards = t[j], t[j + 1]
                        local fv = W.fm[v]
                        if fv and fv[2] % (2 * myBit) >= myBit and (not fv[3] or o.druid) and o.knows(fv[1]) then
                            local nd = du + yards / R.FLY_SPEED + R.FLY_OVERHEAD
                            if G[v] ~= gen or nd < D[v] then
                                G[v], D[v], P[v], H[v], F[v] = gen, nd, u, 1, yards
                                push(nd, v)
                            end
                        end
                    end
                end
            end
            local t = trans[u]
            if t then
                for j = 1, #t, 2 do
                    local v, ti = t[j], t[j + 1]
                    local tr = W.transports[ti]
                    local isTram = tr[3] == "tram"
                    if (isTram or useBoat) and tr[4] % (2 * myBit) >= myBit then
                        local nd = du + tr[5]
                        if G[v] ~= gen or nd < D[v] then
                            G[v], D[v], P[v], H[v], F[v] = gen, nd, u, 2, ti
                            push(nd, v)
                        end
                    end
                end
            end
        end
    end
    if G[dst] ~= gen then return nil end
    local rp, rh, rr = {}, {}, {}
    local v = dst
    while v do
        rp[#rp + 1], rh[#rh + 1], rr[#rr + 1] = v, H[v], F[v]
        v = P[v]
    end
    local path, hows, refs, n = {}, {}, {}, #rp
    for k = 1, n do path[k], hows[k], refs[k] = rp[n + 1 - k], rh[n + 1 - k], rr[n + 1 - k] end
    return path, hows, refs, D[dst]
end

-- Name for a walking leg's end point: the node itself, or the nearest named node near it.
local function placeName(i)
    if W.nname[i] then return W.nname[i] end
    return R.Zone(i)
end

-- "Menethil Harbor (Wetlands)": short place name plus the zone it is in.
local function withZone(name, zoneName)
    name = (name or ""):gsub(",.*$", ""):gsub("%s+%(.-%)$", "")
    if name == "" then return zoneName end
    if name == zoneName or name:find(zoneName, 1, true) then return name end
    return name .. " (" .. zoneName .. ")"
end
R.WithZone = withZone
function R.Label(i, name) return withZone(name or placeName(i), R.Zone(i)) end

local function buildSteps(path, hows, refs, o)
    local steps = {}
    local hostileBit = o.faction == 1 and 1 or 2
    local cur
    local function close()
        if cur then steps[#steps + 1] = cur; cur = nil end
    end
    for k = 2, #path do
        local a, b, h, r = path[k - 1], path[k], hows[k], refs[k]
        if h == 0 then
            if not cur or cur.kind ~= "run" then
                close()
                cur = { kind = "run", from = a, to = b, yards = 0, seconds = 0, points = { a } }
            end
            local len = dist(a, b)
            cur.yards = cur.yards + len
            local c = len / (o.speed or R.RUN_SPEED)
            if floor(r / 8) % 4 == hostileBit then
                cur.hostile = cur.hostile or {}
                cur.hostile[R.Zone(b)] = true
            end
            if r % 64 >= 32 then cur.needsKey = true end
            if r % 128 >= 64 then cur.portal = true end
            cur.seconds = cur.seconds + c
            cur.to = b
            cur.points[#cur.points + 1] = b
        elseif h == 1 then
            if not cur or cur.kind ~= "fly" then
                close()
                cur = { kind = "fly", from = a, to = b, yards = 0, seconds = R.FLY_OVERHEAD, points = { a }, hops = 0 }
            end
            cur.yards = cur.yards + r
            cur.seconds = cur.seconds + r / R.FLY_SPEED
            cur.hops = cur.hops + 1
            cur.to = b
            cur.points[#cur.points + 1] = b
        else
            close()
            local tr = W.transports[r]
            local forward = tr[1] == a
            steps[#steps + 1] = { kind = tr[3], from = a, to = b, seconds = tr[5], points = { a, b },
                fromLabel = forward and tr[6] or tr[7], toLabel = forward and tr[7] or tr[6] }
        end
    end
    close()
    -- drop tiny walking legs that only join a dock or flight master to the next leg
    local out = {}
    for _, s in ipairs(steps) do
        if not (s.kind == "run" and s.yards < 15 and #steps > 1) then out[#out + 1] = s end
    end
    local VERB = { boat = "Take the boat", zeppelin = "Take the zeppelin", tram = "Ride the Deeprun Tram" }
    for _, s in ipairs(out) do
        if s.kind == "run" then
            local nm
            if _ == #out and o.destName then
                nm = withZone(o.destName, R.Zone(s.to))
            elseif W.fm[s.to] then
                nm = "the flight master at " .. R.Label(s.to)
            else
                nm = R.Label(s.to)
            end
            s.text = "Run to " .. nm
            local warn = {}
            if s.hostile then
                for z in pairs(s.hostile) do warn[#warn + 1] = z end
                table.sort(warn)
                s.warning = "Passes enemy territory in " .. table.concat(warn, ", ")
            end
            if s.needsKey then s.warning = (s.warning and s.warning .. ". " or "") .. "Needs the Key to Searing Gorge" end
            if s.portal then s.text = s.text .. " (via the Darnassus portal)" end
        elseif s.kind == "fly" then
            s.text = "Fly from " .. R.Label(s.from) .. " to " .. R.Label(s.to)
        else
            s.text = VERB[s.kind] .. " from " .. withZone(s.fromLabel, R.Zone(s.from)) .. " to " .. withZone(s.toLabel, R.Zone(s.to))
        end
    end
    return out
end

-- Plan one mode. Returns route = {mode, seconds, steps, path} or nil, reason.
function R:Plan(src, dst, o)
    self:Init()
    if not src or not dst then return nil, "no location" end
    if src == dst then return { mode = o.mode, seconds = 0, steps = {}, path = { src } } end
    local path, hows, refs, cost = search(src, dst, o)
    if not path then
        return nil, o.mode == "run" and "No walking route" or "No route"
    end
    local used = {}
    for k = 2, #hows do used[hows[k]] = true end
    local steps = buildSteps(path, hows, refs, o)
    local secs = 0
    for _, s in ipairs(steps) do secs = secs + s.seconds end
    local route = { mode = o.mode, seconds = secs, steps = steps, path = path, cost = cost }
    if o.mode == "fly" and not used[1] then route.note = "No flight path helps here" end
    if o.mode == "boat" and not used[2] then route.note = "No boat needed" end
    return route
end

function R:PlanAll(src, dst, o)
    local out = {}
    for _, mode in ipairs({ "run", "fly", "boat" }) do
        local oo = setmetatable({ mode = mode }, { __index = o })
        local r, why = self:Plan(src, dst, oo)
        out[mode] = r or { mode = mode, unavailable = why }
    end
    return out
end

-- Progress along a route: index of the step the player is on, and whether
-- the player has left the route (farther than `tol` yards from every link
-- of the current and next step).
local function segDist(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay
    local L = vx * vx + vy * vy
    local t = L > 0 and ((px - ax) * vx + (py - ay) * vy) / L or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local dx, dy = ax + t * vx - px, ay + t * vy - py
    return sqrt(dx * dx + dy * dy)
end

function R:Track(route, stepIndex, cc, px, py, tol)
    tol = tol or 60
    local steps = route.steps
    local s = steps[stepIndex]
    if not s then return stepIndex, false, 0 end
    -- reached end of the current step?
    local e = s.to
    local dx, dy = W.nx[e] - px, W.ny[e] - py
    local toEnd = sqrt(dx * dx + dy * dy)
    if toEnd < R.ARRIVE_RADIUS and cont[e] == cc then
        return stepIndex + 1, false, toEnd
    end
    if s.kind ~= "run" then return stepIndex, false, toEnd end   -- riding: no off-route check
    if cont[s.from] ~= cc then return stepIndex, false, toEnd end
    local best = huge
    local pts = s.points
    for k = 2, #pts do
        local a, b = pts[k - 1], pts[k]
        local dd = segDist(px, py, W.nx[a], W.ny[a], W.nx[b], W.ny[b])
        if dd < best then best = dd end
    end
    return stepIndex, best > tol, toEnd
end

-- Next point to aim the arrow at: the first path node on the current step
-- that is more than 20 yards ahead of the player.
function R:NextWaypoint(step, px, py)
    local pts = step.points
    local bestK, bestD = 1, huge
    for k = 1, #pts do
        local dx, dy = W.nx[pts[k]] - px, W.ny[pts[k]] - py
        local d = dx * dx + dy * dy
        if d < bestD then bestD, bestK = d, k end
    end
    for k = bestK, #pts do
        local dx, dy = W.nx[pts[k]] - px, W.ny[pts[k]] - py
        if dx * dx + dy * dy > 400 then return pts[k] end
    end
    return pts[#pts]
end

-- Search places by name (case-insensitive, prefix matches first).
function R:Search(text, limit)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return {} end
    limit = limit or 8
    local pre, mid = {}, {}
    for i, p in ipairs(W.places) do
        local n = p[1]:lower()
        local zn = W.zones[p[2]]:lower()
        if n:sub(1, #text) == text then pre[#pre + 1] = i
        elseif n:find(text, 1, true) or (zn:sub(1, #text) == text) then mid[#mid + 1] = i end
    end
    local function byLen(a, b) return #W.places[a][1] < #W.places[b][1] end
    table.sort(pre, byLen); table.sort(mid, byLen)
    local out = {}
    for _, i in ipairs(pre) do if #out < limit then out[#out + 1] = i end end
    for _, i in ipairs(mid) do if #out < limit then out[#out + 1] = i end end
    return out
end

function R:Place(i)
    local p = W.places[i]
    return p[1], W.zones[p[2]], p[3]
end

-- Nearest flight master the character can use (by straight distance, same continent).
function R:NearestFlightMaster(cc, x, y, factionBit, druid)
    self:Init()
    local best, bd
    for node, info in pairs(W.fm) do
        if cont[node] == cc and info[2] % (2 * factionBit) >= factionBit and (not info[3] or druid)
            and flyOut[node] then
            local dx, dy = W.nx[node] - x, W.ny[node] - y
            local d = dx * dx + dy * dy
            if not bd or d < bd then best, bd = node, d end
        end
    end
    return best, bd and sqrt(bd)
end
