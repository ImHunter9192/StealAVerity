local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Players, RS, RepS = game:GetService("Players"), game:GetService("RunService"), game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer
local scriptStart = os.clock()

local CFG = {
    Bases = "Bases", Treadmill = "TreadmillLocation", Admin = "Admin Treadmill",
    BoxTool = "Box",   -- backpack tools whose name contains this get placed
    PlaceY = 0,        -- ground height used for PlaceBox
}
local on, placeDelay = {}, 0.5
local placeTarget -- defined below
local VirtualUser = game:GetService("VirtualUser")

local function root() local c = lp.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function posOf(o) return o:IsA("Model") and o:GetPivot().Position or o.Position end
-- the game shows the owner's name on Base.Origin.OwnerNameplate.PlayerName
local function mine(base)
    local l = base:FindFirstChild("PlayerName", true)
    if not (l and l:IsA("TextLabel")) then return false end
    local t = (l.Text:gsub("^@", "")):lower()
    return t == lp.DisplayName:lower() or t == lp.Name:lower()
end

local function myBase()
    local bases = workspace:FindFirstChild(CFG.Bases)
    if not bases then return end
    for _, b in ipairs(bases:GetChildren()) do
        if mine(b) then return b end
    end
end

local function myTreadmill()
    local bases = workspace:FindFirstChild(CFG.Bases)
    if not bases then return end
    for _, b in ipairs(bases:GetChildren()) do
        if mine(b) then return b:FindFirstChild(CFG.Treadmill, true) end
    end
end

local function admin()
    local o = workspace:FindFirstChild(CFG.Admin)
    return (o and (o:IsA("BasePart") or o:IsA("Model"))) and o or nil
end

local function goTo(t, up)
    local r = root()
    if r and t then r.CFrame = CFrame.new(posOf(t) + Vector3.new(0, up, 0)) return true end
    Rayfield:Notify({Title = "Teleport", Content = "Target not found", Duration = 3})
end
local function adminUp(a) return (a:IsA("BasePart") and a.Size.Y / 2 or 0) + 4 end

workspace.ChildAdded:Connect(function(c)
    if c.Name == CFG.Admin then
        Rayfield:Notify({Title = "Admin Treadmill", Content = "Spawned!", Duration = 4})
        if on.admin then task.wait(0.2) goTo(c, adminUp(c)) end
    end
end)

task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local r, a = root(), admin()
            if not r then return end
            if on.admin and a then
                if (posOf(a) - r.Position).Magnitude > 15 then goTo(a, adminUp(a)) end
            elseif on.tread then
                local t = myTreadmill()
                if t and (posOf(t) - r.Position).Magnitude > 15 then goTo(t, 4) end
            end
        end)
    end
end)

local function remote(name) return RepS:FindFirstChild(name, true) end

-- where boxes go: inside MY base, no matter where I'm standing.
-- "boxSpot" is a point saved relative to my base's Origin part (set it with the button in the Main tab).
local placeSpread = 6
local boxSpot
pcall(function()
    if readfile and isfile and isfile("stela_boxspot.txt") then
        local x, y, z = readfile("stela_boxspot.txt"):match("([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)")
        if x then boxSpot = Vector3.new(tonumber(x), tonumber(y), tonumber(z)) end
    end
end)

local function baseRef()
    local b = myBase()
    return b and (b:FindFirstChild("Origin") or b:FindFirstChild("PetBounds")), b
end

function placeTarget()
    local ref = baseRef()
    if not ref then return end
    local p = boxSpot and ref.CFrame:PointToWorldSpace(boxSpot) or ref.Position
    local off = Vector3.new(math.random(-placeSpread, placeSpread), 0, math.random(-placeSpread, placeSpread))
    return Vector3.new(p.X, CFG.PlaceY, p.Z) + off
end

local function saveBoxSpot()
    local r, ref = root(), baseRef()
    if not (r and ref) then
        Rayfield:Notify({Title = "Box spot", Content = "Couldn't find your base", Duration = 4})
        return
    end
    boxSpot = ref.CFrame:PointToObjectSpace(r.Position)
    pcall(function()
        if writefile then writefile("stela_boxspot.txt", boxSpot.X .. "," .. boxSpot.Y .. "," .. boxSpot.Z) end
    end)
    Rayfield:Notify({Title = "Box spot saved", Content = "Boxes now go here, from anywhere", Duration = 4})
end

-- auto place boxes: EquipTool(tool) then PlaceBox(Vector3) near where you stand
task.spawn(function()
    while task.wait(placeDelay) do
        if on.boxes then pcall(function()
            local r, place, equip = root(), remote("PlaceBox"), remote("EquipTool")
            if not (r and place and equip) then return end
            local tool
            for _, c in ipairs({lp.Character, lp.Backpack}) do
                for _, t in ipairs(c:GetChildren()) do
                    if t:IsA("Tool") and t.Name:find(CFG.BoxTool, 1, true) then tool = t break end
                end
                if tool then break end
            end
            if not tool then return end
            if tool.Parent ~= lp.Character then equip:FireServer(tool) task.wait(0.15) end
            local target = placeTarget()
            if not target then return end
            local back
            if on.tpPlace and (r.Position - target).Magnitude > 30 then
                back = r.CFrame -- remember where I was
                r.CFrame = CFrame.new(target + Vector3.new(0, 4, 0))
                task.wait(0.25)
            end
            pcall(function() place:FireServer(target) end)
            if back then
                task.wait(0.25)
                local r2 = root()
                if r2 then
                    r2.CFrame = back
                    r2.AssemblyLinearVelocity = Vector3.zero
                end
            end
        end) end
    end
end)

-- webhook notifier: reads the game's own night-reset announcements (PlayerGui.NightWarning)
-- e.g. "ALL BOXES RESET!" then "Winged Verity Box" + " spawned in " + "Glass House!"
local HttpService = game:GetService("HttpService")
local wh = {url = "", bosses = ""}
on.night = true
local sent = {}
local httpReq = (syn and syn.request) or (http and http.request) or http_request or request

local function validUrl(u)
    return u:find("^https://[%w%.]*discord%.com/api/webhooks/") or u:find("^https://[%w%.]*discordapp%.com/api/webhooks/")
end

local function sendWebhook(title, desc)
    if not (httpReq and validUrl(wh.url)) then return false end
    pcall(httpReq, {
        Url = wh.url, Method = "POST", Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({embeds = {{title = title, description = desc, color = 5814783, footer = {text = lp.DisplayName}}}}),
    })
    return true
end

local function trim(s) return s:match("^%s*(.-)%s*$") end

-- selectable lists for the notification filters (edit or add names here)
local LISTS = {
    areas = {"Forest", "Ruins", "Desert", "Backrooms", "Dungeon", "Ocean", "Abyss", "Elysium", "Fracture",
        "Inferno", "Genesis", "Eternity", "Candyland", "Moonfall", "Glass House", "Observatory",
        "Haunted Graveyard", "Heaven's Gate", "Event Horizon", "Frostfire", "Checkmate", "Dread Keep"},
    boxes = {"Happy", "Smiling", "Annoyed", "Moggity", "Creepy", "Enraged", "True", "Golem", "Lord",
        "King", "Divine", "Winged", "Prism"},
}
-- the game stores each area's name on Workspace.Areas.AreaN (attribute DisplayName): use it if present
pcall(function()
    local af = workspace:FindFirstChild("Areas")
    if not af then return end
    local list = {}
    for _, a in ipairs(af:GetChildren()) do
        local n = a:GetAttribute("DisplayName")
        if n then list[#list + 1] = {tonumber(a.Name:match("%d+")) or 0, n} end
    end
    table.sort(list, function(x, y) return x[1] < y[1] end)
    if #list > 0 then
        LISTS.areas = {}
        for _, e in ipairs(list) do table.insert(LISTS.areas, e[2]) end
    end
end)
-- boss tiers (Normal, Winged, ...) come from the game's own BossConfig
LISTS.tiers = {"Normal", "Winged"}
pcall(function()
    local cfg = require(RepS.Shared.BossConfig)
    local t = {}
    for _, tier in ipairs(cfg.BOSS_TIERS) do table.insert(t, tier.Name == "" and "Normal" or tier.Name) end
    if #t > 0 then LISTS.tiers = t end
end)
local function copy(t) local c = {} for i, v in ipairs(t) do c[i] = v end return c end

-- a "selection" = which names of LISTS[key] are ticked in one picker
local function makeSel(key)
    local picked, all = {}, true
    local o = {}
    function o.set(list)
        picked = {}
        local n = 0
        for _, name in ipairs(list) do picked[name:lower()] = true n = n + 1 end
        all = n >= #LISTS[key]
    end
    -- exact name read from the map. Names the script doesn't know only pass while everything is ticked.
    function o.allowed(t)
        for _, opt in ipairs(LISTS[key]) do
            if t:lower() == opt:lower() then return picked[opt:lower()] == true end
        end
        return all
    end
    -- free text like "Winged Verity Box": passes if a ticked name is inside it; unknown text always passes
    function o.allowedText(text)
        local t, known = text:lower(), false
        for _, opt in ipairs(LISTS[key]) do
            if t:find(opt:lower(), 1, true) then
                known = true
                if picked[opt:lower()] then return true end
            end
        end
        return not known
    end
    o.set(LISTS[key])
    return o
end
-- three independent sets: in-game popups, Discord, ESP
local SEL = {
    notifAreas = makeSel("areas"), notifBoxes = makeSel("boxes"),
    hookAreas = makeSel("areas"), hookBoxes = makeSel("boxes"),
    espAreas = makeSel("areas"), espBoxes = makeSel("boxes"),
    bossAreas = makeSel("areas"), bossTiers = makeSel("tiers"),
}

local function findOpt(key, word)
    for _, opt in ipairs(LISTS[key]) do
        if opt:lower() == word:lower() then return opt:lower() end
    end
end


-- comma separated filter; empty = match everything
local function passes(filter, text)
    local any = false
    for item in filter:lower():gmatch("[^,]+") do
        item = trim(item)
        if item ~= "" then
            any = true
            if text:lower():find(item, 1, true) then return true end
        end
    end
    return not any
end

local function readAnnouncements(gui)
    local list = {}
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text:lower():find("spawned in", 1, true) then
            local sibs = {}
            for _, c in ipairs(d.Parent:GetChildren()) do
                if c:IsA("TextLabel") and c.Text:match("%S") then sibs[#sibs + 1] = c end
            end
            table.sort(sibs, function(a, b)
                if a.LayoutOrder ~= b.LayoutOrder then return a.LayoutOrder < b.LayoutOrder end
                return a.AbsolutePosition.X < b.AbsolutePosition.X
            end)
            for i, c in ipairs(sibs) do
                if c == d and sibs[i - 1] and sibs[i + 1] then
                    local area = trim(sibs[i + 1].Text):gsub("!+$", "")
                    list[#list + 1] = {box = trim(sibs[i - 1].Text), area = area}
                end
            end
        end
    end
    return list
end

local function processAnnouncements(force)
    local gui = lp.PlayerGui:FindFirstChild("NightWarning")
    if not gui then return false end
    local toastLines, hookLines, now = {}, {}, os.clock()
    for _, a in ipairs(readAnnouncements(gui)) do
        local sig = a.box .. "@" .. a.area
        local line = "• **" .. a.box .. "** in **" .. a.area .. "**"
        local function fresh(dest) return force or not sent[dest .. sig] or now - sent[dest .. sig] > 200 end
        if fresh("t") and SEL.notifBoxes.allowedText(a.box) and SEL.notifAreas.allowedText(a.area) then
            sent["t" .. sig] = now
            toastLines[#toastLines + 1] = line
        end
        if fresh("h") and SEL.hookBoxes.allowedText(a.box) and SEL.hookAreas.allowedText(a.area) then
            sent["h" .. sig] = now
            hookLines[#hookLines + 1] = line
        end
    end
    if #hookLines > 0 then sendWebhook("Boxes reset: new spawns", table.concat(hookLines, "\n")) end
    if #toastLines > 0 then
        Rayfield:Notify({Title = "New boxes", Content = (table.concat(toastLines, "\n"):gsub("%*", "")), Duration = 8})
    end
    return #hookLines > 0 or #toastLines > 0
end

-- wait until the announcements stop changing for 3s, then send them as one message
local token = 0
local function schedule()
    if not on.night then return end
    token = token + 1
    local my = token
    task.delay(3, function() if my == token then pcall(processAnnouncements) end end)
end

local function hookGui(gui)
    local function watch(d)
        if d:IsA("TextLabel") then d:GetPropertyChangedSignal("Text"):Connect(schedule) end
    end
    for _, d in ipairs(gui:GetDescendants()) do watch(d) end
    gui.DescendantAdded:Connect(function(d) watch(d) if d:IsA("TextLabel") then schedule() end end)
end

local pg = lp:WaitForChild("PlayerGui")
local nw = pg:FindFirstChild("NightWarning")
if nw then hookGui(nw) end
pg.ChildAdded:Connect(function(c) if c.Name == "NightWarning" then hookGui(c) end end)

-- boss prediction: the game picks bosses with its own fixed formula (BossConfig), so we just ask it
local okC, BossConfig = pcall(function() return require(RepS.Shared.BossConfig) end)
local okP, BossPortal = pcall(function() return require(RepS.Shared.BossPortalConfig) end)
local canPredict = okC and okP and type(BossConfig) == "table" and type(BossPortal) == "table"
    and type(BossConfig.AreaForBand) == "function" and type(BossConfig.SlotIndex) == "function"
    and type(BossPortal.SignStateAt) == "function"

local BAND_NAMES = {"Normal", "High", "Top"}
local bandOfKey = {Normal = 1, High = 2, Top = 3}
local PRED_SLOTS = 4
local predLabels, infoCache, areaNames = {}, {}, nil

local function areaName(id)
    if not areaNames then
        areaNames = {}
        local af = workspace:FindFirstChild("Areas")
        for _, a in ipairs(af and af:GetChildren() or {}) do
            local aid, dn = a:GetAttribute("AreaId"), a:GetAttribute("DisplayName")
            if aid and dn then areaNames[aid] = dn end
        end
    end
    return areaNames[id] or tostring(id)
end

local function shortNum(n)
    local units = {{"Dc", 1e33}, {"No", 1e30}, {"Oc", 1e27}, {"Sp", 1e24}, {"Sx", 1e21}, {"Qi", 1e18},
        {"Qa", 1e15}, {"T", 1e12}, {"B", 1e9}, {"M", 1e6}, {"K", 1e3}}
    for _, u in ipairs(units) do
        if n >= u[2] then return string.format("%.2f", n / u[2]) .. u[1] end
    end
    return tostring(math.floor(n))
end

local function mmss(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- the boss for one portal ("band") in one time slot: its area, its tier and the speed needed to enter
local function bossInfo(slot, band)
    local key = slot .. ":" .. band
    if infoCache[key] then return infoCache[key] end
    local ok, info = pcall(function()
        local area = BossConfig.AreaForBand(slot, band)
        if not area then return nil end
        local tname = BossConfig.TierName(BossConfig.TierFor(slot, band))
        local tierLabel = (tname == nil or tname == "") and "Normal" or tname
        local an = areaName(area.Id)
        return {
            area = an, tierLabel = tierLabel, speed = BossConfig.EntrySpeedFor(area.Id),
            full = (tierLabel ~= "Normal" and (tierLabel .. " ") or "") .. an .. " boss",
        }
    end)
    if ok and info then infoCache[key] = info return info end
end

-- for the "boss soon" Discord alert: returns skip, text
local function bossLine(key)
    if not canPredict then return false, "" end
    local now = workspace:GetServerTimeNow()
    if (BossPortal.SignStateAt(now)) then return true, "" end -- the clock is counting to the portal CLOSING
    local info = bossInfo(BossConfig.SlotIndex(now) + 1, bandOfKey[key] or 1)
    if not info then return false, "" end
    if not (SEL.bossAreas.allowed(info.area) and SEL.bossTiers.allowed(info.tierLabel)) then return true, "" end
    return false, " - **" .. info.full .. "**"
end

-- keep the Boss tab labels up to date
task.spawn(function()
    while task.wait(1) do
        if canPredict and next(predLabels) then
            pcall(function()
                local now = workspace:GetServerTimeNow()
                local open, left = BossPortal.SignStateAt(now)
                local cur = BossConfig.SlotIndex(now)
                local first = open and cur or cur + 1
                for i = 1, PRED_SLOTS do
                    local pl, slot = predLabels[i], first + i - 1
                    local startT = BossConfig.SlotStart(slot)
                    local head
                    if i == 1 and open then
                        head = "OPEN NOW - closes in " .. mmss(left)
                    else
                        head = "Starts in " .. mmss(startT - now) .. "  (" .. os.date("%H:%M", math.floor(startT)) .. ")"
                    end
                    if pl.headText ~= head then pl.head:Set(head) pl.headText = head end
                    local bands = BossConfig.BandsForSlot(slot)
                    for b = 1, 3 do
                        local txt
                        if table.find(bands, b) then
                            local info = bossInfo(slot, b)
                            if info then
                                local need = (info.speed and info.speed > 0) and ("needs " .. shortNum(info.speed) .. " speed") or "no minimum"
                                txt = BAND_NAMES[b] .. ": " .. info.full .. " (" .. need .. ")"
                            else
                                txt = BAND_NAMES[b] .. ": ?"
                            end
                        else
                            txt = BAND_NAMES[b] .. ": -"
                        end
                        if pl.rowText[b] ~= txt then pl.rows[b]:Set(txt) pl.rowText[b] = txt end
                    end
                end
            end)
        end
    end
end)

-- boss timers + alerts (the three portal signs show the countdown and the speed needed)
local TIERS = {
    {key = "Normal", gui = "BossPortalSign"},
    {key = "High", gui = "BossPortalSignHigh"},
    {key = "Top", gui = "BossPortalSignTop"},
}
local bossLabels, lastSecs, lastText = {}, {}, {}
local bossTiers = {Normal = true, High = true, Top = true}
local bossWarn = 60
on.bossSoon, on.bossEvent = false, false

local function readTier(t)
    local g = lp.PlayerGui:FindFirstChild(t.gui)
    if not g then return end
    local clock = g:FindFirstChild("Clock", true)
    local req
    -- the speed needed is a label somewhere under an object called "Speed"
    for _, d in ipairs(g:GetDescendants()) do
        if d.Name == "Speed" then
            local labels = d:IsA("TextLabel") and {d} or {}
            for _, x in ipairs(d:GetDescendants()) do
                if x:IsA("TextLabel") then labels[#labels + 1] = x end
            end
            for _, l in ipairs(labels) do
                if l.Text ~= "" and l.Text:lower() ~= "speed" then req = l.Text break end
            end
            if req then break end
        end
    end
    if not req then -- fallback: a label that looks like a number such as 600M or 1T
        for _, d in ipairs(g:GetDescendants()) do
            if d:IsA("TextLabel") and d ~= clock and d.Text:match("^[%d%.,]+%s*%a*$") then req = d.Text break end
        end
    end
    return clock and clock.Text or "?", req or "?"
end

local function toSecs(txt)
    local a, b, c = txt:match("^(%d+):(%d+):(%d+)$")
    if a then return tonumber(a) * 3600 + tonumber(b) * 60 + tonumber(c) end
    a, b = txt:match("^(%d+):(%d+)$")
    if a then return tonumber(a) * 60 + tonumber(b) end
end

task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local lines = {}
            for _, t in ipairs(TIERS) do
                local clock, req = readTier(t)
                if clock then
                    local need = (req == "0" or req == "") and "no minimum" or ("needs " .. req .. " speed")
                    local txt = t.key .. " (" .. need .. "): " .. clock
                    local lbl = bossLabels[t.key]
                    if lbl and lastText[t.key] ~= txt then lbl:Set(txt) lastText[t.key] = txt end
                    local secs, prev = toSecs(clock), lastSecs[t.key]
                    if secs then
                        if on.bossSoon and bossTiers[t.key] and prev and prev > bossWarn and secs <= bossWarn then
                            local skip, who = bossLine(t.key)
                            if not skip then
                                lines[#lines + 1] = "• **" .. t.key .. "** portal (" .. need .. ") in " .. clock .. who
                            end
                        end
                        lastSecs[t.key] = secs
                    end
                end
            end
            if #lines > 0 then
                local desc = table.concat(lines, "\n")
                sendWebhook("Boss fight soon", desc)
                local plain = desc:gsub("%*", "")
                Rayfield:Notify({Title = "Boss soon", Content = plain, Duration = 8})
            end
        end)
    end
end)

-- game-side boss announcements: we forward whatever the remote sends so you can see boss names
local function fmt(v, d)
    d = d or 0
    local t = typeof(v)
    if t == "table" and d < 2 then
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. fmt(x, d + 1) end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "Instance" then
        return v.Name
    end
    return tostring(v)
end

for _, name in ipairs({"BossAnnounce", "BossPortalOffer"}) do
    task.spawn(function()
        local folder = RepS:WaitForChild("Remotes", 15)
        local r = folder and folder:WaitForChild(name, 15)
        if not r then return end
        r.OnClientEvent:Connect(function(...)
            if not on.bossEvent then return end
            local args, parts = table.pack(...), {}
            for i = 1, args.n do parts[#parts + 1] = fmt(args[i]) end
            local text = table.concat(parts, " | ")
            if not passes(wh.bosses, text) then return end
            local msg = name .. ": " .. (text ~= "" and text or "(no data)")
            sendWebhook("Boss event", msg)
            Rayfield:Notify({Title = "Boss event", Content = msg:sub(1, 200), Duration = 8})
        end)
    end)
end

-- stats: money / speed change since you executed the script
local SUFFIX = {{"Dc", 1e33}, {"No", 1e30}, {"Oc", 1e27}, {"Sp", 1e24}, {"Sx", 1e21}, {"Qi", 1e18},
    {"Qa", 1e15}, {"T", 1e12}, {"B", 1e9}, {"M", 1e6}, {"K", 1e3}}

local function parseNum(txt)
    if txt == nil then return end
    local num, suf = tostring(txt):match("^%+?%$?%s*([%d%.,]+)%s*(%a*)")
    if not num then return end
    local n = tonumber((num:gsub(",", "")))
    if not n then return end
    if suf == "" then return n end
    for _, x in ipairs(SUFFIX) do
        if x[1]:lower() == suf:lower() then return n * x[2] end
    end
end

local function abbr(n)
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    for _, x in ipairs(SUFFIX) do
        if n >= x[2] then return sign .. string.format("%.2f", n / x[2]) .. x[1] end
    end
    return sign .. string.format("%.2f", n)
end

local function pct(now, start)
    if not (now and start) or start == 0 then return "n/a" end
    return string.format("%+.2f%%", (now - start) / start * 100)
end

local function hms(sec)
    sec = math.floor(sec)
    return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60)
end

local function readSpeed()
    local ls = lp:FindFirstChild("leaderstats")
    local v = ls and ls:FindFirstChild("Speed")
    return v and parseNum(v.Value)
end

local function readMoneyRate()
    local a = lp:GetAttribute("AdvancedCashRate")
    if type(a) == "number" then return a end
    local ls = lp:FindFirstChild("leaderstats")
    local v = ls and ls:FindFirstChild("Money/s")
    return v and parseNum(v.Value)
end

-- current money isn't in leaderstats, so read the HUD text that looks like "$52.1B"
local moneyLabel
local function isMoneyText(t) return t:match("^%$[%d%.,]+%s*%a*$") and not t:find("/") end
local function readMoney()
    if moneyLabel and moneyLabel:IsDescendantOf(game) and isMoneyText(moneyLabel.Text) then
        return parseNum(moneyLabel.Text)
    end
    moneyLabel = nil
    local best, bestSize = nil, -1
    for _, root in ipairs({lp.PlayerGui:FindFirstChild("StealAVerityHUD"), lp.PlayerGui}) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("TextLabel") and d.Visible and isMoneyText(d.Text) and d.TextSize > bestSize then
                    best, bestSize = d, d.TextSize
                end
            end
        end
        if best then break end
    end
    moneyLabel = best
    return best and parseNum(best.Text)
end

local statLabels, statText = {}, {}
local function setStat(key, txt)
    local l = statLabels[key]
    if l and statText[key] ~= txt then l:Set(txt) statText[key] = txt end
end

task.spawn(function()
    local samples, speed0, money0 = {}, nil, nil
    while task.wait(1) do
        pcall(function()
            setStat("timer", "Script running: " .. hms(os.clock() - scriptStart))
            local speed, money, mrate = readSpeed(), readMoney(), readMoneyRate()
            speed0 = speed0 or speed
            money0 = money0 or money
            setStat("money", "Money: " .. (money and ("$" .. abbr(money)) or "not found") .. "  (" .. pct(money, money0) .. ")")
            setStat("speed", "Speed: " .. (speed and abbr(speed) or "?") .. "  (" .. pct(speed, speed0) .. ")")
            if speed then -- speed/s averaged over the last 30 seconds
                samples[#samples + 1] = {os.clock(), speed}
                while #samples > 1 and os.clock() - samples[1][1] > 30 do table.remove(samples, 1) end
            end
            local sps = "..."
            if #samples >= 2 then
                local f, l = samples[1], samples[#samples]
                sps = abbr((l[2] - f[2]) / math.max(l[1] - f[1], 1))
            end
            setStat("sps", "Speed/s: " .. sps)
            setStat("mps", "Money/s: " .. (mrate and ("$" .. abbr(mrate)) or "?"))
        end)
    end
end)

-- REAL boxes are the models in Workspace.BoxRuntime (Areas.X.Boxes.Box are only 1x1 spawn markers).
-- An area box = a BoxRuntime model that sits on one of the area floors.
on.espArea, on.espMood, on.espLabel = false, false, false
local areaBounds, areaIdx = {}, {}
for i, n in ipairs(LISTS.areas) do areaIdx[n] = i end

local function refreshAreaBounds()
    table.clear(areaBounds)
    local af = workspace:FindFirstChild("Areas")
    if not af then return end
    for _, a in ipairs(af:GetChildren()) do
        local name = a:GetAttribute("DisplayName")
        if name then
            local f = a:FindFirstChild("Floor")
            if f and f:IsA("BasePart") then areaBounds[#areaBounds + 1] = {name = name, cf = f.CFrame, size = f.Size} end
            local split = a:FindFirstChild("FloorSplit")
            if split and split:IsA("Model") then
                local cf, size = split:GetBoundingBox()
                areaBounds[#areaBounds + 1] = {name = name, cf = cf, size = size}
            end
        end
    end
end

local function areaOf(pos)
    for _, b in ipairs(areaBounds) do
        local p = b.cf:PointToObjectSpace(pos)
        if math.abs(p.X) <= b.size.X / 2 + 2 and math.abs(p.Z) <= b.size.Z / 2 + 2 and math.abs(p.Y) <= 60 then
            return b.name
        end
    end
end

-- face image id -> box type, built from the game's own BoxConfig.ById (only ids that belong to one box type)
local boxTypeByImage = {}
local function prettyId(id)
    local x = id:gsub("_box$", "")
    return (x:gsub("^%l", string.upper))
end
pcall(function()
    local cfg = require(RepS.Shared.BoxConfig)
    local owners = {}
    local function walk(v, id, d)
        if type(v) == "string" then
            for digits in v:gmatch("%d%d%d%d%d+") do
                owners[digits] = owners[digits] or {}
                owners[digits][id] = true
            end
        elseif type(v) == "table" and d < 3 then
            for _, x in pairs(v) do walk(x, id, d + 1) end
        end
    end
    for id, entry in pairs(cfg.ById) do walk(entry, prettyId(id), 0) end
    for digits, ids in pairs(owners) do
        local only, n = nil, 0
        for id in pairs(ids) do only, n = id, n + 1 end
        if n == 1 then boxTypeByImage[digits] = only end
    end
end)

local function faceDigits(model)
    local face = model:FindFirstChild("Face", true)
    local img = face and face:IsA("ImageLabel") and face.Image or ""
    return img:match("%d+")
end

local function boxTypeOf(model)
    for _, o in ipairs({model, model:FindFirstChild("Core")}) do
        if o then
            for k, v in pairs(o:GetAttributes()) do
                if type(v) == "string" and v ~= "" and k ~= "BoxUid" then return v end
            end
        end
    end
    local d = faceDigits(model)
    if d and boxTypeByImage[d] then return boxTypeByImage[d] end
    -- rare boxes share one face image, so tell them apart by their ornament/part names (e.g. "Lord_Hat")
    local KEYS = {{"lord", "Lord"}, {"king", "King"}, {"golem", "Golem"}, {"wing", "Winged"},
        {"divine", "Winged"}, {"prism", "Prism"}, {"true", "True"}}
    for _, c in ipairs(model:GetDescendants()) do
        local n = c.Name:lower()
        for _, k in ipairs(KEYS) do
            if n:find(k[1], 1, true) then return k[2] end
        end
    end
    return d and ("Face " .. d) or "Unknown"
end

local function areaBoxes()
    refreshAreaBounds()
    local res = {}
    local br = workspace:FindFirstChild("BoxRuntime")
    if not br then return res end
    for _, m in ipairs(br:GetChildren()) do
        if m:IsA("Model") then
            local core = m:FindFirstChild("Core") or m.PrimaryPart
            if core then
                local area = areaOf(core.Position)
                if area then res[#res + 1] = {model = m, core = core, area = area, type = boxTypeOf(m)} end
            end
        end
    end
    return res
end

local espSingle, espColor, espTransp, typeColors = false, Color3.fromRGB(255, 200, 0), 0.6, {}
local espTextSize, espRange, espShowArea = 13, 100, false
local function colorFor(t)
    if espSingle then return espColor end
    if typeColors[t] then return typeColors[t] end
    local h = 0
    for i = 1, #t do h = (h * 31 + t:byte(i)) % 360 end
    return Color3.fromHSV(h / 360, 0.8, 1)
end

-- ESP
local espObjs = {}
local function espClear()
    for _, o in pairs(espObjs) do o.folder:Destroy() end
    table.clear(espObjs)
end

local function styleOne(o)
    o.label.TextSize = espTextSize
    o.label.Text = espShowArea and (o.type .. " - " .. o.area) or o.type
    o.gui.MaxDistance = espRange
    o.gui.Size = UDim2.fromOffset(espTextSize * 12, espTextSize + 6)
    o.gui.Enabled = on.espLabel
end
local function espRestyle() for _, o in pairs(espObjs) do styleOne(o) end end

task.spawn(function()
    while task.wait(2) do
        if not (on.espArea or on.espMood) then
            if next(espObjs) then espClear() end
        else
            pcall(function()
                local parent = (gethui and gethui()) or game:GetService("CoreGui")
                local live = {}
                for _, b in ipairs(areaBoxes()) do
                    if (on.espArea and SEL.espAreas.allowed(b.area)) or (on.espMood and SEL.espBoxes.allowed(b.type)) then
                        live[b.model] = true
                        local o = espObjs[b.model]
                        if not o then
                            local f = Instance.new("Folder")
                            local adorn = Instance.new("BoxHandleAdornment")
                            adorn.Adornee, adorn.AlwaysOnTop, adorn.ZIndex = b.core, true, 1
                            adorn.Size, adorn.Transparency = b.model:GetExtentsSize(), 0.6
                            adorn.Parent = f
                            local gui = Instance.new("BillboardGui")
                            gui.Adornee, gui.AlwaysOnTop = b.core, true
                            gui.Size, gui.StudsOffset = UDim2.fromOffset(160, 22), Vector3.new(0, 3, 0)
                            local tl = Instance.new("TextLabel", gui)
                            tl.Size, tl.BackgroundTransparency = UDim2.fromScale(1, 1), 1
                            tl.TextScaled, tl.Font, tl.TextStrokeTransparency = false, Enum.Font.GothamBold, 0.5
                            gui.Parent = f
                            f.Parent = parent
                            o = {folder = f, adorn = adorn, gui = gui, label = tl}
                            espObjs[b.model] = o
                        end
                        local c = colorFor(b.type)
                        o.adorn.Color3, o.label.TextColor3 = c, c
                        o.adorn.Transparency = espTransp
                        o.type, o.area = b.type, b.area
                        styleOne(o)
                    end
                end
                for m, o in pairs(espObjs) do
                    if not live[m] then o.folder:Destroy() espObjs[m] = nil end
                end
            end)
        end
    end
end)

-- summary of every box on the map, grouped by area (sent after each night reset)
local function boxSummary(areaSel, typeSel)
    local byArea, order = {}, {}
    for _, b in ipairs(areaBoxes()) do
        if areaSel.allowed(b.area) and typeSel.allowed(b.type) then
            if not byArea[b.area] then byArea[b.area] = {} order[#order + 1] = b.area end
            byArea[b.area][b.type] = (byArea[b.area][b.type] or 0) + 1
        end
    end
    table.sort(order, function(x, y) return (areaIdx[x] or 99) < (areaIdx[y] or 99) end)
    local lines = {}
    for _, area in ipairs(order) do
        local parts = {}
        for ty, n in pairs(byArea[area]) do parts[#parts + 1] = ty .. (n > 1 and (" x" .. n) or "") end
        table.sort(parts)
        lines[#lines + 1] = "**" .. area .. "**: " .. table.concat(parts, ", ")
    end
    return table.concat(lines, "\n"), #order
end

local function sendBoxSummary()
    local hookDesc, hn = boxSummary(SEL.hookAreas, SEL.hookBoxes)
    local toastDesc, tn = boxSummary(SEL.notifAreas, SEL.notifBoxes)
    if hn > 0 then sendWebhook("Boxes on the map", hookDesc:sub(1, 4000)) end
    if tn > 0 then
        Rayfield:Notify({Title = "Boxes on the map", Content = (toastDesc:gsub("%*", "")):sub(1, 200), Duration = 8})
    end
    return hn > 0 or tn > 0
end

-- night reset = the NightReadout countdown jumps from ~0 back up to minutes
local lastNight
task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local g = lp.PlayerGui:FindFirstChild("NightReadout")
            if not g then return end
            local txt
            for _, d in ipairs(g:GetDescendants()) do
                if d:IsA("TextLabel") and d.Text:find("%d+s") then txt = d.Text break end
            end
            if not txt then return end
            local m, sec = txt:match("(%d+)m%s*(%d+)s")
            local secs = m and (tonumber(m) * 60 + tonumber(sec)) or tonumber(txt:match("(%d+)s"))
            if not secs then return end
            if on.night and lastNight and lastNight <= 20 and secs > lastNight + 100 then
                task.delay(6, function() pcall(sendBoxSummary) end) -- give the new boxes time to spawn
            end
            lastNight = secs
        end)
    end
end)

-- debug: every box with its area, detected type and face image id
local function scanReport()
    local out = {}
    for _, b in ipairs(areaBoxes()) do
        out[#out + 1] = b.area .. " | " .. b.type .. " | face=" .. tostring(faceDigits(b.model))
    end
    table.sort(out)
    local text = table.concat(out, "\n")
    if setclipboard then setclipboard(text) end
    print(text)
    Rayfield:Notify({Title = "Box scan", Content = #out .. " boxes scanned (copied to clipboard)", Duration = 4})
end

-- boxes menu: one dropdown per area listing the boxes in it; picking one teleports you next to it
local menuDD, menuMap, menuSig, menuSuppress, lastPos = {}, {}, {}, false, nil

local function tpToBox(m)
    local r = root()
    local core = m and m.Parent and (m:FindFirstChild("Core") or m.PrimaryPart)
    if not (r and core) then
        Rayfield:Notify({Title = "Boxes", Content = "That box is gone (night reset?)", Duration = 3})
        return
    end
    lastPos = r.CFrame
    r.CFrame = CFrame.new(core.Position + Vector3.new(0, 5, 0))
    r.AssemblyLinearVelocity = Vector3.zero
end

local function refreshBoxMenu()
    local byArea = {}
    for _, b in ipairs(areaBoxes()) do
        byArea[b.area] = byArea[b.area] or {}
        table.insert(byArea[b.area], b)
    end
    for _, area in ipairs(LISTS.areas) do
        local dd = menuDD[area]
        if dd then
            local list = byArea[area] or {}
            table.sort(list, function(x, y)
                if x.type ~= y.type then return x.type < y.type end
                return x.model.Name < y.model.Name
            end)
            local count = {}
            for _, b in ipairs(list) do count[b.type] = (count[b.type] or 0) + 1 end
            local seen, labels, map = {}, {}, {}
            for _, b in ipairs(list) do
                seen[b.type] = (seen[b.type] or 0) + 1
                local label = count[b.type] > 1 and (b.type .. " #" .. seen[b.type]) or b.type
                labels[#labels + 1] = label
                map[label] = b.model
            end
            menuMap[area] = map
            local sig = table.concat(labels, ",")
            if sig ~= menuSig[area] then
                menuSig[area] = sig
                if #labels == 0 then labels = {"(no boxes)"} end
                menuSuppress = true
                pcall(function() dd:Refresh(labels) end)
                menuSuppress = false
            end
        end
    end
end

task.spawn(function()
    while task.wait(3) do pcall(refreshBoxMenu) end
end)

-- anti-AFK
on.afk = false
lp.Idled:Connect(function()
    if on.afk then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

-- re-run this script after server hops / rejoins
local loaderUrl = "https://raw.githubusercontent.com/ImHunter9192/StealAVerity/refs/heads/main/stela.lua"
local function loaderSrc() return 'loadstring(game:HttpGet("' .. loaderUrl .. '"))()' end
local queueFn = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
on.reexec = false
lp.OnTeleport:Connect(function()
    if on.reexec and queueFn then pcall(queueFn, loaderSrc()) end
end)

local function rayfieldGui()
    local roots = {game:GetService("CoreGui"), lp.PlayerGui}
    if gethui then table.insert(roots, 1, gethui()) end
    for _, root in ipairs(roots) do
        for _, g in ipairs(root:GetChildren()) do
            if g:IsA("ScreenGui") and g.Name:find("Rayfield") and g:FindFirstChild("Main") then return g end
        end
    end
end
local function rayfieldMain()
    local g = rayfieldGui()
    return g and g.Main
end

local Window = Rayfield:CreateWindow({
    Name = "Stela A Verity", LoadingTitle = "Stela A Verity", LoadingSubtitle = "Loading...",
    ConfigurationSaving = {Enabled = true, FolderName = "StelaAVerity", FileName = "Config"},
    KeySystem = false,
})
local Main = Window:CreateTab("Main")

local function toggle(tab, name, key, cb)
    tab:CreateToggle({Name = name, CurrentValue = false, Flag = key,
        Callback = function(v) on[key] = v if cb then cb(v) end end})
end

Main:CreateButton({Name = "Go To My Treadmill", Callback = function() goTo(myTreadmill(), 4) end})
Main:CreateButton({Name = "Go To Admin Treadmill", Callback = function()
    local a = admin()
    if a then goTo(a, adminUp(a)) else Rayfield:Notify({Title = "Admin Treadmill", Content = "Not spawned", Duration = 3}) end
end})
toggle(Main, "Auto Go To Treadmill", "tread")
toggle(Main, "Auto Go To Admin Treadmill", "admin")
toggle(Main, "Auto Place Verity Boxes", "boxes")
on.tpPlace = true
Main:CreateToggle({Name = "Teleport to base while placing, then back", CurrentValue = true, Flag = "TpPlace",
    Callback = function(v) on.tpPlace = v end})
Main:CreateButton({Name = "Set Box Spot To Where I'm Standing", Callback = saveBoxSpot})
Main:CreateButton({Name = "Reset Box Spot (use base center)", Callback = function()
    boxSpot = nil
    pcall(function() if writefile then writefile("stela_boxspot.txt", "") end end)
    Rayfield:Notify({Title = "Box spot", Content = "Reset to base center", Duration = 3})
end})
Main:CreateSlider({Name = "Box Spread Around Spot", Range = {0, 20}, Increment = 1, Suffix = " studs",
    CurrentValue = 6, Flag = "PlaceSpread", Callback = function(v) placeSpread = v end})
Main:CreateSlider({Name = "Place Delay", Range = {0.1, 5}, Increment = 0.1, Suffix = "s",
    CurrentValue = 0.5, Flag = "PlaceDelay", Callback = function(v) placeDelay = v end})



-- scrollable multi-select dropdown. A search bar + Select all / Clear all are injected at the top of the
-- opened list (they only show while the dropdown is open, because they live inside it).
local function addHeader(title, getDD, getCurrent, setCurrent)
    task.spawn(function()
        for _ = 1, 20 do
            task.wait(0.5)
            local ok = pcall(function()
                local g = rayfieldGui()
                local el
                for _, d in ipairs(g:GetDescendants()) do
                    if d.Name == title and d:IsA("Frame") and d:FindFirstChild("List") then el = d break end
                end
                if not el then error("no element") end
                local list = el.List
                if list:FindFirstChild("!SearchHeader") then return end
                local lay = list:FindFirstChildOfClass("UIListLayout")
                if lay then lay.SortOrder = Enum.SortOrder.LayoutOrder end
                pcall(function()
                    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
                    list.CanvasSize = UDim2.new(0, 0, 0, 0)
                end)
                local h = Instance.new("Frame")
                h.Name, h.LayoutOrder, h.BackgroundTransparency = "!SearchHeader", -100, 1
                h.Size = UDim2.new(1, -10, 0, 70)
                local box = Instance.new("TextBox")
                box.Size, box.Position = UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 2)
                box.BackgroundColor3, box.TextColor3 = Color3.fromRGB(45, 45, 52), Color3.new(1, 1, 1)
                box.PlaceholderText, box.PlaceholderColor3 = "Search...", Color3.fromRGB(150, 150, 160)
                box.Text, box.ClearTextOnFocus, box.TextSize = "", false, 14
                box.Font, box.TextXAlignment = Enum.Font.Gotham, Enum.TextXAlignment.Left
                Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
                local pad = Instance.new("UIPadding", box)
                pad.PaddingLeft = UDim.new(0, 8)
                box.Parent = h
                local function visibleNames()
                    local out = {}
                    for _, f in ipairs(list:GetChildren()) do
                        if f:IsA("GuiObject") and f.Name ~= "!SearchHeader" and f.Name ~= "Template"
                            and f.Name ~= "Placeholder" and f.Visible then out[#out + 1] = f.Name end
                    end
                    return out
                end
                box:GetPropertyChangedSignal("Text"):Connect(function()
                    local q = box.Text:lower()
                    for _, f in ipairs(list:GetChildren()) do
                        if f:IsA("GuiObject") and f.Name ~= "!SearchHeader" and f.Name ~= "Template"
                            and f.Name ~= "Placeholder" and f.Name ~= "UIListLayout" then
                            f.Visible = q == "" or f.Name:lower():find(q, 1, true) ~= nil
                        end
                    end
                end)
                local function btn(text, x, fn)
                    local b = Instance.new("TextButton")
                    b.Size, b.Position = UDim2.new(0.5, -3, 0, 28), UDim2.new(x, x == 0 and 0 or 3, 0, 38)
                    b.BackgroundColor3, b.TextColor3 = Color3.fromRGB(60, 60, 70), Color3.new(1, 1, 1)
                    b.Text, b.TextSize, b.Font = text, 13, Enum.Font.GothamBold
                    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
                    b.MouseButton1Click:Connect(fn)
                    b.Parent = h
                end
                btn("Select all", 0, function()
                    local merged, have = copy(getCurrent()), {}
                    for _, n in ipairs(merged) do have[n] = true end
                    for _, n in ipairs(visibleNames()) do if not have[n] then merged[#merged + 1] = n end end
                    setCurrent(merged)
                    pcall(function() getDD():Set(copy(merged)) end)
                end)
                btn("Clear all", 0.5, function()
                    local gone, out = {}, {}
                    for _, n in ipairs(visibleNames()) do gone[n] = true end
                    for _, n in ipairs(getCurrent()) do if not gone[n] then out[#out + 1] = n end end
                    setCurrent(out)
                    pcall(function() getDD():Set(copy(out)) end)
                end)
                h.Parent = list
            end)
            if ok then return end
        end
    end)
end

local function selectPicker(tab, title, key, flag, sel)
    local current, dd = copy(LISTS[key]), nil
    dd = tab:CreateDropdown({Name = title, Options = copy(LISTS[key]),
        CurrentOption = copy(LISTS[key]), MultipleOptions = true, Flag = flag,
        Callback = function(o)
            if type(o) == "string" then o = {o} end
            local clean = {}
            for _, n in ipairs(o) do if findOpt(key, n) then clean[#clean + 1] = n end end
            current = clean
            sel.set(clean)
        end})
    addHeader(title, function() return dd end, function() return current end,
        function(l) current = l sel.set(l) end)
end

local Stats = Window:CreateTab("Stats")
Stats:CreateSection("Session")
statLabels.timer = Stats:CreateLabel("Script running: 00:00:00")
Stats:CreateSection("Change since you executed the script")
statLabels.money = Stats:CreateLabel("Money: loading...")
statLabels.speed = Stats:CreateLabel("Speed: loading...")
Stats:CreateSection("Rates")
statLabels.sps = Stats:CreateLabel("Speed/s: loading...")
statLabels.mps = Stats:CreateLabel("Money/s: loading...")


local Visuals = Window:CreateTab("Visuals")
toggle(Visuals, "ESP by area (on/off)", "espArea")
toggle(Visuals, "ESP by mood (on/off)", "espMood")
toggle(Visuals, "Show box labels", "espLabel", function() espRestyle() end)
Visuals:CreateToggle({Name = "Include area name in label", CurrentValue = false, Flag = "EspShowArea",
    Callback = function(v) espShowArea = v espRestyle() end})
Visuals:CreateSlider({Name = "Label text size", Range = {8, 24}, Increment = 1, CurrentValue = 13,
    Flag = "EspTextSize", Callback = function(v) espTextSize = v espRestyle() end})
Visuals:CreateSlider({Name = "Label range (studs)", Range = {20, 500}, Increment = 10, CurrentValue = 100,
    Flag = "EspRange", Callback = function(v) espRange = v espRestyle() end})
selectPicker(Visuals, "ESP areas", "areas", "EspAreas", SEL.espAreas)
selectPicker(Visuals, "ESP moods", "boxes", "EspTypes", SEL.espBoxes)
Visuals:CreateButton({Name = "Scan Boxes (copy report)", Callback = scanReport})
Visuals:CreateSection("ESP colors")
Visuals:CreateToggle({Name = "Use one color for all boxes", CurrentValue = false, Flag = "EspSingle",
    Callback = function(v) espSingle = v end})
Visuals:CreateColorPicker({Name = "One color", Color = espColor, Flag = "EspColor",
    Callback = function(c) espColor = c end})
Visuals:CreateSlider({Name = "ESP fill transparency", Range = {0, 0.95}, Increment = 0.05, CurrentValue = 0.6,
    Flag = "EspTransp", Callback = function(v) espTransp = v end})
local colorType, pickerReady = LISTS.boxes[1], false
task.delay(3, function() pickerReady = true end) -- ignore the color picker's startup callback
Visuals:CreateDropdown({Name = "Pick a box type to recolor", Options = copy(LISTS.boxes),
    CurrentOption = {LISTS.boxes[1]}, MultipleOptions = false,
    Callback = function(o) colorType = type(o) == "table" and o[1] or o end})
Visuals:CreateColorPicker({Name = "Color for that box type", Color = Color3.fromRGB(255, 255, 255),
    Callback = function(c) if pickerReady and colorType then typeColors[colorType] = c end end})
Visuals:CreateButton({Name = "Reset per-type colors", Callback = function() table.clear(typeColors) end})

local BoxesTab = Window:CreateTab("Boxes")
BoxesTab:CreateSection("Tap an area to open it, tap a box to teleport to it")
BoxesTab:CreateButton({Name = "Go back to where I was", Callback = function()
    local r = root()
    if r and lastPos then
        r.CFrame = lastPos
        r.AssemblyLinearVelocity = Vector3.zero
    else
        Rayfield:Notify({Title = "Boxes", Content = "No saved position yet", Duration = 3})
    end
end})
BoxesTab:CreateButton({Name = "Refresh boxes now", Callback = function() pcall(refreshBoxMenu) end})
for _, area in ipairs(LISTS.areas) do
    menuDD[area] = BoxesTab:CreateDropdown({Name = area, Options = {"(loading)"}, CurrentOption = {},
        MultipleOptions = false,
        Callback = function(o)
            if menuSuppress then return end
            local label = type(o) == "table" and o[1] or o
            local m = menuMap[area] and menuMap[area][label]
            if m then
                tpToBox(m)
                task.defer(function()
                    menuSuppress = true
                    pcall(function() menuDD[area]:Set({}) end)
                    menuSuppress = false
                end)
            end
        end})
end

local Misc = Window:CreateTab("Misc")
Misc:CreateSection("Utility")
toggle(Misc, "Anti-AFK", "afk")
Misc:CreateSection("Interface")
Misc:CreateDropdown({Name = "UI color theme",
    Options = {"Default", "AmberGlow", "Amethyst", "Bloom", "DarkBlue", "Green", "Light", "Ocean", "Serenity"},
    CurrentOption = {"Default"}, MultipleOptions = false, Flag = "UiTheme",
    Callback = function(o)
        local name = type(o) == "table" and o[1] or o
        if not pcall(function() Window.ModifyTheme(name) end) then
            Rayfield:Notify({Title = "Theme", Content = "This Rayfield version can't change themes", Duration = 4})
        end
    end})
Misc:CreateSlider({Name = "UI size", Range = {50, 150}, Increment = 5, Suffix = "%", CurrentValue = 100,
    Flag = "UiScale", Callback = function(v)
        pcall(function()
            local m = rayfieldMain()
            if not m then return end
            local sc = m:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", m)
            sc.Scale = v / 100
        end)
    end})
Misc:CreateSection("Auto execute")
Misc:CreateInput({Name = "Script link to auto execute", CurrentValue = loaderUrl, PlaceholderText = loaderUrl,
    RemoveTextAfterFocusLost = false, Flag = "LoaderUrl",
    Callback = function(t) t = trim(t or "") if t ~= "" then loaderUrl = t end end})
toggle(Misc, "Re-run script after server hop / rejoin", "reexec")
Misc:CreateButton({Name = "Save to executor autoexec folder", Callback = function()
    local ok = pcall(function()
        if makefolder and isfolder and not isfolder("autoexec") then makefolder("autoexec") end
        writefile("autoexec/StelaAVerity.lua", loaderSrc())
    end)
    Rayfield:Notify({Title = "Auto execute", Duration = 5,
        Content = ok and "Saved autoexec/StelaAVerity.lua (delete it to turn this off)" or "Your executor can't write files"})
end})


local Hook = Window:CreateTab("Webhook")
Hook:CreateInput({Name = "Webhook URL", PlaceholderText = "https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost = false, Flag = "WebhookUrl", Callback = function(t) wh.url = t end})
Hook:CreateToggle({Name = "Notify after every night reset", CurrentValue = true, Flag = "WebhookNight",
    Callback = function(v) on.night = v end})
Hook:CreateButton({Name = "Send Test Message", Callback = function()
    local ok = sendWebhook("Test", "Webhook works!")
    Rayfield:Notify({Title = "Webhook", Duration = 3,
        Content = ok and "Test sent" or "Invalid URL or your executor has no request function"})
end})
Hook:CreateButton({Name = "Read Current Announcements Now", Callback = function()
    if not processAnnouncements(true) then
        Rayfield:Notify({Title = "Webhook", Content = "No matching announcements on screen right now", Duration = 4})
    end
end})

Hook:CreateButton({Name = "Send Box Summary Now", Callback = function()
    if not sendBoxSummary() then
        Rayfield:Notify({Title = "Webhook", Content = "No boxes matched your filters", Duration = 4})
    end
end})

selectPicker(Hook, "Discord areas", "areas", "HookAreas", SEL.hookAreas)
selectPicker(Hook, "Discord moods", "boxes", "HookTypes", SEL.hookBoxes)

local Filters = Window:CreateTab("Notif Filters")
selectPicker(Filters, "Popup areas", "areas", "FilterAreas", SEL.notifAreas)
selectPicker(Filters, "Popup moods", "boxes", "FilterBoxes", SEL.notifBoxes)

local Boss = Window:CreateTab("Boss")
Boss:CreateSection("Next boss timers")
for _, t in ipairs(TIERS) do bossLabels[t.key] = Boss:CreateLabel(t.key .. ": loading...") end
Boss:CreateButton({Name = "Copy boss sign info (debug)", Callback = function()
    local out = {}
    for _, t in ipairs(TIERS) do
        local g = lp.PlayerGui:FindFirstChild(t.gui)
        if g then
            for _, d in ipairs(g:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("ValueBase") then
                    out[#out + 1] = d:GetFullName() .. " [" .. d.ClassName .. "] = " .. tostring(d:IsA("TextLabel") and d.Text or d.Value)
                end
            end
        end
    end
    local text = table.concat(out, "\n")
    if setclipboard then setclipboard(text) end
    print(text)
end})
Boss:CreateSection("Predicted bosses (from the game's own boss formula)")
if canPredict then
    for i = 1, PRED_SLOTS do
        local pl = {rowText = {}, rows = {}}
        pl.head = Boss:CreateLabel("Loading...")
        for b = 1, 3 do pl.rows[b] = Boss:CreateLabel(BAND_NAMES[b] .. ": ...") end
        predLabels[i] = pl
    end
    Boss:CreateButton({Name = "Check prediction vs portal displays", Callback = function()
        local now = workspace:GetServerTimeNow()
        local open = BossPortal.SignStateAt(now)
        local slot = BossConfig.SlotIndex(now) + (open and 0 or 1)
        local lines = {}
        for b, nm in ipairs({"BossPortal", "BossPortalHigh", "BossPortalTop"}) do
            local portal = workspace:FindFirstChild(nm)
            local d = portal and portal:FindFirstChild("DisplayBoss")
            local shown = d and (areaName(d:GetAttribute("AreaId")) .. " tier " .. tostring(d:GetAttribute("BossTier"))) or "no display"
            local info = bossInfo(slot, b)
            lines[#lines + 1] = BAND_NAMES[b] .. ": portal shows " .. shown .. " | predicted " .. (info and info.full or "?")
        end
        local text = table.concat(lines, "\n")
        print(text)
        if setclipboard then setclipboard(text) end
        Rayfield:Notify({Title = "Prediction check", Content = text:sub(1, 220), Duration = 10})
    end})
else
    Boss:CreateLabel("Prediction unavailable: couldn't read the game's boss code")
end
Boss:CreateSection("Discord alerts (uses the URL from the Webhook tab)")
Boss:CreateToggle({Name = "Alert shortly before the boss starts", CurrentValue = false, Flag = "BossSoon",
    Callback = function(v) on.bossSoon = v end})
Boss:CreateSlider({Name = "Alert when this many seconds away", Range = {10, 300}, Increment = 5, Suffix = "s",
    CurrentValue = 60, Flag = "BossWarn", Callback = function(v) bossWarn = v end})
Boss:CreateDropdown({Name = "Which portals to alert for", Options = {"Normal", "High", "Top"},
    CurrentOption = {"Normal", "High", "Top"}, MultipleOptions = true, Flag = "BossTiers",
    Callback = function(o)
        if type(o) == "string" then o = {o} end
        bossTiers = {}
        for _, k in ipairs(o) do bossTiers[k] = true end
    end})
Boss:CreateToggle({Name = "Alert when the game announces a boss", CurrentValue = false, Flag = "BossEvent",
    Callback = function(v) on.bossEvent = v end})
Boss:CreateInput({Name = "Boss names (comma separated, empty = all)", PlaceholderText = "name1, name2",
    RemoveTextAfterFocusLost = false, Flag = "BossNames", Callback = function(t) wh.bosses = t end})

selectPicker(Boss, "Boss areas to alert for", "areas", "BossAreas", SEL.bossAreas)
selectPicker(Boss, "Boss tiers to alert for", "tiers", "BossTiers", SEL.bossTiers)

Rayfield:LoadConfiguration()
