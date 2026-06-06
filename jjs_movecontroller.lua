local WindUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ──────────────────────────────────────────────
--  CONFIG
-- ──────────────────────────────────────────────
local CONFIG = {
    BehindOffset           = 5.5,
    AlreadyBehindTolerance = 3.5,
    FireDelay              = 0.37,
    DashSpeed              = 79,
    ArcSegments            = 5,
    SideWidth              = 0.65,
    TrailLifetime          = 0.35,

    DashAnimLeft           = "rbxassetid://117223862448096",
    DashAnimRight          = "rbxassetid://75203303352791",
    AttackAnimId           = "rbxassetid://100962226150441",

    FacingDotThreshold     = -0.6,
    RetryDelay             = 0.04,
    RetryFire              = true,

    RetryDistance          = 7,
    MaxTargetVelocity      = 28,
    PostDashDelay          = 0.06,

    ESPEnabled             = true,
    ESPColor               = Color3.fromRGB(255, 50, 50),
    ESPFillTransparency    = 0.7,
    ESPOutlineTransparency = 0.3,

    -- MoveController
    MoveSpeed              = 100,
    ArriveDist             = 2,
    MoveTimeout            = 2,
}

if _G.retryfire ~= nil then
    CONFIG.RetryFire = _G.retryfire
end

-- ──────────────────────────────────────────────
--  REMOTES
-- ──────────────────────────────────────────────
local function getRemote(...)
    local path = { ... }
    local ok, remote = pcall(function()
        local node = ReplicatedStorage
        for _, child in ipairs(path) do
            node = node:WaitForChild(child, 5)
        end
        return node
    end)
    return ok and remote or nil
end

local targetRemote = getRemote("Knit", "Knit", "Services", "DivergentFistService", "RE", "Activated")
if not targetRemote then
    warn("[DivergentFist] Remote not found!")
    return
end

local returnSkillRemote = getRemote("Knit", "Knit", "Services", "ItadoriService", "RE", "RightActivated")
if not returnSkillRemote then
    warn("[DivergentFist] ReturnSkill remote not found")
end

-- ──────────────────────────────────────────────
--  ESP SYSTEM
-- ──────────────────────────────────────────────
local espObjects = {}

local function createHighlight(model, color)
    local highlight = Instance.new("Highlight")
    highlight.Name = "DivergentFistESP"
    highlight.FillTransparency = CONFIG.ESPFillTransparency
    highlight.OutlineTransparency = CONFIG.ESPOutlineTransparency
    highlight.FillColor = color
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.Adornee = model
    highlight.Parent = model
    return highlight
end

local function destroyESP()
    for _, obj in pairs(espObjects) do
        pcall(function() obj:Destroy() end)
    end
    espObjects = {}
end

local function updateESP()
    if not CONFIG.ESPEnabled then
        destroyESP()
        return
    end

    destroyESP()

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local hl = createHighlight(player.Character, CONFIG.ESPColor)
                if hl then table.insert(espObjects, hl) end
            end
        end
    end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= LocalPlayer.Character and obj:FindFirstChild("HumanoidRootPart") then
            local humanoid = obj:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 and not obj:IsDescendantOf(Players) then
                local hl = createHighlight(obj, CONFIG.ESPColor)
                if hl then table.insert(espObjects, hl) end
            end
        end
    end
end

local function applyTransparencyLive()
    for _, obj in pairs(espObjects) do
        pcall(function()
            obj.FillTransparency = CONFIG.ESPFillTransparency
            obj.OutlineTransparency = CONFIG.ESPOutlineTransparency
        end)
    end
end

task.spawn(function()
    while true do
        if CONFIG.ESPEnabled then
            updateESP()
        end
        task.wait(0.5)
    end
end)

-- ──────────────────────────────────────────────
--  UTILS
-- ──────────────────────────────────────────────
local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getAnimator()
    local char = LocalPlayer.Character
    if not char then return nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end
    return humanoid:FindFirstChildOfClass("Animator")
end

local function isAliveModel(model)
    local myChar = LocalPlayer.Character
    if model == myChar then return false end
    local root = model:FindFirstChild("HumanoidRootPart")
    local humanoid = model:FindFirstChild("Humanoid")
    return root and humanoid and humanoid.Health > 0
end

-- ──────────────────────────────────────────────
--  TARGET CHECKS
-- ──────────────────────────────────────────────
local function isTargetFacingAway(targetRoot)
    local hrp = getHRP()
    if not hrp or not targetRoot or not targetRoot.Parent then return false end
    local toPlayer = (hrp.Position - targetRoot.Position)
    if toPlayer.Magnitude < 0.01 then return false end
    local dot = targetRoot.CFrame.LookVector:Dot(toPlayer.Unit)
    return dot < CONFIG.FacingDotThreshold
end

local function canRetry(targetRoot)
    local hrp = getHRP()
    if not hrp or not targetRoot or not targetRoot.Parent then return false end
    local dist = (hrp.Position - targetRoot.Position).Magnitude
    if dist > CONFIG.RetryDistance then return false end
    local behindDot = targetRoot.CFrame.LookVector:Dot(
        (hrp.Position - targetRoot.Position).Unit
    )
    local behindEnough = behindDot < -0.45
    local targetVelocity = targetRoot.AssemblyLinearVelocity.Magnitude
    if targetVelocity > CONFIG.MaxTargetVelocity then return false end
    return behindEnough
end

-- ──────────────────────────────────────────────
--  TARGET FINDER
-- ──────────────────────────────────────────────
local function findNearestTarget()
    local hrp = getHRP()
    if not hrp then return nil end

    local nearest = nil
    local bestDist = math.huge

    local function checkModel(model)
        if not isAliveModel(model) then return end
        local root = model:FindFirstChild("HumanoidRootPart")
        local dist = (hrp.Position - root.Position).Magnitude
        if dist < bestDist then
            bestDist = dist
            nearest = model
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            checkModel(player.Character)
        end
    end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            checkModel(obj)
        end
    end

    return nearest
end

-- ──────────────────────────────────────────────
--  TRAIL
-- ──────────────────────────────────────────────
local function createTrail(rootPart)
    local a0 = Instance.new("Attachment", rootPart)
    local a1 = Instance.new("Attachment", rootPart)
    a1.Position = Vector3.new(0, 2, 0)

    local trail = Instance.new("Trail", rootPart)
    trail.Attachment0 = a0
    trail.Attachment1 = a1
    trail.Color = ColorSequence.new(Color3.fromRGB(255,255,255))
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.Lifetime = CONFIG.TrailLifetime
    trail.MinLength = 0
    trail.FaceCamera = true

    task.delay(CONFIG.TrailLifetime + 0.1, function()
        trail:Destroy()
        a0:Destroy()
        a1:Destroy()
    end)
end

-- ──────────────────────────────────────────────
--  ANIMATIONS
-- ──────────────────────────────────────────────
local cachedAnims = {}

local function playDashAnimation(direction, duration)
    local animator = getAnimator()
    if not animator then return nil end

    local animId = (direction == "Left")
        and CONFIG.DashAnimLeft
        or CONFIG.DashAnimRight

    if not cachedAnims[direction] then
        local anim = Instance.new("Animation")
        anim.AnimationId = animId
        anim.Name = "DivergentDash_" .. direction
        cachedAnims[direction] = anim
    end

    local track = animator:LoadAnimation(cachedAnims[direction])
    track:Play(0.05)
    return track
end

local function playAttackAnimation()
    local animator = getAnimator()
    if not animator then return end

    if not cachedAnims["Attack"] then
        local anim = Instance.new("Animation")
        anim.AnimationId = CONFIG.AttackAnimId
        anim.Name = "DivergentAttack"
        cachedAnims["Attack"] = anim
    end

    local track = animator:LoadAnimation(cachedAnims["Attack"])
    track:Play(0.05)

    task.delay(1.113, function()
        if track.IsPlaying then
            track:Stop()
        end
    end)
end

-- ──────────────────────────────────────────────
--  MOVECONTROLLER - Loop to back
-- ──────────────────────────────────────────────
local function moveControllerToBehind(targetRoot, onDone)
    local char = LocalPlayer.Character
    if not char then return end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local hrp = getHRP()
    if not humanoid or not hrp then return end

    local originalSpeed = humanoid.WalkSpeed
    humanoid.WalkSpeed = CONFIG.MoveSpeed

    local elapsed = 0
    local conn

    createTrail(hrp)

    conn = RunService.Heartbeat:Connect(function(dt)
        elapsed += dt

        if not targetRoot.Parent or not hrp.Parent then
            conn:Disconnect()
            humanoid.WalkSpeed = originalSpeed
            return
        end

        local behindCF  = targetRoot.CFrame * CFrame.new(0, 0, CONFIG.BehindOffset)
        local behindPos = Vector3.new(behindCF.Position.X, hrp.Position.Y, behindCF.Position.Z)
        local dist      = (hrp.Position - behindPos).Magnitude

        if dist < CONFIG.ArriveDist or elapsed > CONFIG.MoveTimeout then
            conn:Disconnect()
            humanoid.WalkSpeed = originalSpeed

            hrp.CFrame = CFrame.lookAt(
                behindPos,
                Vector3.new(targetRoot.Position.X, behindPos.Y, targetRoot.Position.Z)
            )

            playAttackAnimation()
            if onDone then onDone() end
            return
        end

        -- Arc logic: if we're in front of the target, arc around the side
        local toTarget  = (targetRoot.Position - hrp.Position).Unit
        local facingDot = targetRoot.CFrame.LookVector:Dot(toTarget)

        if facingDot > 0.3 and dist < 12 then
            -- Pick shortest arc side based on where we currently are
            local right = targetRoot.CFrame.RightVector
            local toMe  = (hrp.Position - targetRoot.Position).Unit
            local side  = (toMe:Dot(right) >= 0) and right or -right

            local arcPos = Vector3.new(
                targetRoot.Position.X + side.X * (CONFIG.BehindOffset + 2),
                hrp.Position.Y,
                targetRoot.Position.Z + side.Z * (CONFIG.BehindOffset + 2)
            )

            humanoid:MoveTo(arcPos)
        else
            -- Already on side or behind, go straight to behind
            humanoid:MoveTo(behindPos)
        end
    end)
end

-- ──────────────────────────────────────────────
--  HOOK
-- ──────────────────────────────────────────────
local isCooling  = false
local isRetrying = false
local oldNamecall

oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if getnamecallmethod() ~= "FireServer" or self ~= targetRemote then
        return oldNamecall(self, ...)
    end

    if isRetrying then return oldNamecall(self, ...) end
    if isCooling  then return oldNamecall(self, ...) end

    isCooling = true

    local result = oldNamecall(self, ...)
    local args   = { ... }

    local target     = findNearestTarget()
    local targetRoot = target and target:FindFirstChild("HumanoidRootPart")

    task.delay(CONFIG.FireDelay, function()

        if targetRoot and targetRoot.Parent and not isTargetFacingAway(targetRoot) then

            if returnSkillRemote then
                pcall(function() returnSkillRemote:FireServer() end)
            end

            task.spawn(function()
                task.wait(CONFIG.RetryDelay)

                if not targetRoot.Parent or not isAliveModel(targetRoot.Parent) then
                    isCooling = false
                    return
                end

                moveControllerToBehind(targetRoot, function()
                    task.wait(CONFIG.PostDashDelay)

                    local shouldRetryFire = (
                        _G.retryfire ~= nil
                    ) and _G.retryfire or CONFIG.RetryFire

                    if not canRetry(targetRoot) then
                        -- skip
                    elseif not shouldRetryFire then
                        -- skip
                    else
                        isRetrying = true

                        pcall(function()
                            targetRemote:FireServer(table.unpack(args))
                        end)

                        task.wait(CONFIG.FireDelay)

                        pcall(function()
                            targetRemote:FireServer(table.unpack(args))
                        end)

                        isRetrying = false
                    end

                    task.defer(function()
                        isCooling = false
                    end)
                end)
            end)

        else

            pcall(function()
                targetRemote:FireServer(table.unpack(args))
            end)

            task.defer(function()
                isCooling = false
            end)
        end
    end)

    task.spawn(function()
        if not targetRoot or not targetRoot.Parent then return end
        moveControllerToBehind(targetRoot)
    end)

    return result
end)

-- ──────────────────────────────────────────────
--  WINDUI GUI
-- ──────────────────────────────────────────────
local Window = WindUI:CreateWindow({
    Title  = "Script Loader",
    Icon   = "zap",
    Theme  = "Dark",
    Author = "By Mitsuki",
})

local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })

SettingsTab:Slider({
    Title = "Move Speed (MoveController)",
    Step  = 1,
    Value = { Min = 50, Max = 300, Default = CONFIG.MoveSpeed },
    Callback = function(v) CONFIG.MoveSpeed = v end,
})

SettingsTab:Slider({
    Title = "Behind Offset",
    Step  = 0.5,
    Value = { Min = 3, Max = 10, Default = CONFIG.BehindOffset },
    Callback = function(v) CONFIG.BehindOffset = v end,
})

SettingsTab:Slider({
    Title = "Fire Delay (seconds)",
    Step  = 0.01,
    Value = { Min = 0.10, Max = 1.00, Default = CONFIG.FireDelay },
    Callback = function(v) CONFIG.FireDelay = v end,
})

SettingsTab:Slider({
    Title = "Arrive Distance",
    Step  = 0.5,
    Value = { Min = 1, Max = 6, Default = CONFIG.ArriveDist },
    Callback = function(v) CONFIG.ArriveDist = v end,
})

SettingsTab:Toggle({
    Title    = "Retry Fire",
    Value    = CONFIG.RetryFire,
    Callback = function(v)
        CONFIG.RetryFire = v
        _G.retryfire = v
    end,
})

local ESPTab = Window:Tab({ Title = "ESP", Icon = "eye" })

ESPTab:Toggle({
    Title    = "Enable ESP",
    Value    = CONFIG.ESPEnabled,
    Callback = function(v)
        CONFIG.ESPEnabled = v
        if not v then destroyESP() else updateESP() end
    end,
})

ESPTab:Slider({
    Title = "Fill Transparency",
    Step  = 0.01,
    Value = { Min = 0.00, Max = 1.00, Default = CONFIG.ESPFillTransparency },
    Callback = function(v)
        CONFIG.ESPFillTransparency = v
        applyTransparencyLive()
    end,
})

ESPTab:Slider({
    Title = "Outline Transparency",
    Step  = 0.01,
    Value = { Min = 0.00, Max = 1.00, Default = CONFIG.ESPOutlineTransparency },
    Callback = function(v)
        CONFIG.ESPOutlineTransparency = v
        applyTransparencyLive()
    end,
})

ESPTab:Button({
    Title    = "Refresh ESP",
    Callback = function() updateESP() end,
})
