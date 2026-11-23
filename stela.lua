local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Players, RS, RepS = game:GetService("Players"), game:GetService("RunService"), game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

local CFG = {
    Bases = "Bases", Treadmill = "TreadmillLocation", Admin = "Admin Treadmill",
    BoxRemote = {"Remotes", "PlaceBox"}, BoxArgs = {},
}
local on, hitSize, placeDelay, saved = {}, 10, 0.5, {}

local function root() local c = lp.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function posOf(o) return o:IsA("Model") and o:GetPivot().Position or o.Position end
local function isMe(v) v = tostring(v) return v == tostring(lp.UserId) or v == lp.Name end

local function scan(obj, fn)
    for k, v in pairs(obj:GetAttributes()) do if fn(k, v) then return true end end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("ValueBase") and fn(d.Name, d.Value) then return true end
    end
end

local function mine(base)
    local n = base.Name:match("%d+")
    return scan(lp, function(k, v)
        return v == base or tostring(v) == base.Name or (k:lower():find("base") and tostring(v) == n)
    end) or scan(base, function(_, v) return v == lp or isMe(v) end)
end

local function myTreadmill()
    local bases, r = workspace:FindFirstChild(CFG.Bases), root()
    if not (bases and r) then return end
    local best, bd
    for _, b in ipairs(bases:GetChildren()) do
        local t = b:FindFirstChild(CFG.Treadmill, true)
        if t then
            if mine(b) then return t end
            local d = (posOf(t) - r.Position).Magnitude
            if not bd or d < bd then best, bd = t, d end
        end
    end
    return best
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

task.spawn(function()
    while task.wait(placeDelay) do
        if on.boxes then
            local o = RepS
            for _, n in ipairs(CFG.BoxRemote) do o = o and o:FindFirstChild(n) end
            if o then pcall(function()
                if o:IsA("RemoteEvent") then o:FireServer(table.unpack(CFG.BoxArgs))
                else o:InvokeServer(table.unpack(CFG.BoxArgs)) end
            end) end
        end
    end
end)

local function resetHitboxes()
    for hrp, s in pairs(saved) do if hrp.Parent then hrp.Size, hrp.Transparency = s, 1 end end
    table.clear(saved)
end

RS.Heartbeat:Connect(function()
    if on.hitbox then
        for _, p in ipairs(Players:GetPlayers()) do
            local h = p ~= lp and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if h then
                saved[h] = saved[h] or h.Size
                h.Size, h.Transparency, h.CanCollide = Vector3.new(hitSize, hitSize, hitSize), 0.7, false
            end
        end
    end
    if on.ragdoll then
        local c = lp.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum.PlatformStand = false
        local s = hum:GetState()
        if s == Enum.HumanoidStateType.Ragdoll or s == Enum.HumanoidStateType.FallingDown then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("BallSocketConstraint") then d:Destroy()
            elseif d:IsA("Motor6D") then d.Enabled = true end
        end
        if c:GetAttribute("Ragdoll") then c:SetAttribute("Ragdoll", false) end
    end
end)

local Window = Rayfield:CreateWindow({
    Name = "Stela A Verity", LoadingTitle = "Stela A Verity", LoadingSubtitle = "Loading...",
    ConfigurationSaving = {Enabled = true, FolderName = "StelaAVerity", FileName = "Config"},
    KeySystem = false,
})
local Main, Combat, Player = Window:CreateTab("Main"), Window:CreateTab("Combat"), Window:CreateTab("Player")

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
Main:CreateSlider({Name = "Place Delay", Range = {0.1, 5}, Increment = 0.1, Suffix = "s",
    CurrentValue = 0.5, Flag = "PlaceDelay", Callback = function(v) placeDelay = v end})

toggle(Combat, "Bat Hitbox Expander", "hitbox", function(v) if not v then resetHitboxes() end end)
Combat:CreateSlider({Name = "Hitbox Size", Range = {2, 40}, Increment = 1, Suffix = " studs",
    CurrentValue = 10, Flag = "HitboxSize", Callback = function(v) hitSize = v end})

toggle(Player, "Anti Ragdoll", "ragdoll")

Rayfield:LoadConfiguration()
