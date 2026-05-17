-- V1PRWARE | maintained by mitsuki | original by v1pr/glov
print("V1PRWARE loaded")

------------------------------------------------------------------------
-- services
------------------------------------------------------------------------
local svc = {
    Players        = game:GetService("Players"),
    Run            = game:GetService("RunService"),
    Input          = game:GetService("UserInputService"),
    RS             = game:GetService("ReplicatedStorage"),
    WS             = game:GetService("Workspace"),
    TweenService   = game:GetService("TweenService"),
    TextChat       = game:GetService("TextChatService"),
    Http           = game:GetService("HttpService"),
}

local lp  = svc.Players.LocalPlayer
local gui = lp:WaitForChild("PlayerGui", 10)

------------------------------------------------------------------------
-- filesystem shims
------------------------------------------------------------------------
local fs = {
    hasFolder = isfolder     or function() return false end,
    makeFolder= makefolder   or function() end,
    write     = writefile    or function() end,
    hasFile   = isfile       or function() return false end,
    read      = readfile     or function() return "" end,
    asset     = getcustomasset or function(p) return p end,
}

------------------------------------------------------------------------
-- config
------------------------------------------------------------------------
local cfg = {}
do
    local DIR  = "V1PRWARE"
    local FILE = DIR .. "/config.json"
    local function prep()
        if not fs.hasFolder(DIR) then fs.makeFolder(DIR) end
    end
    function cfg.load()
        prep()
        if not fs.hasFile(FILE) then return end
        local ok, t = pcall(svc.Http.JSONDecode, svc.Http, fs.read(FILE))
        if ok and type(t) == "table" then cfg._data = t end
    end
    function cfg.save()
        prep()
        local ok, s = pcall(svc.Http.JSONEncode, svc.Http, cfg._data)
        if ok then fs.write(FILE, s) end
    end
    function cfg.get(k, default)
        local v = cfg._data[k]
        return v ~= nil and v or default
    end
    function cfg.set(k, v)
        cfg._data[k] = v
        cfg.save()
    end
    cfg._data = {}
    cfg.load()
end

------------------------------------------------------------------------
-- WindUI
------------------------------------------------------------------------
local ui = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

local win = ui:CreateWindow({
    Title          = "V1PRWARE",
    Icon           = "sparkles",
    Author         = "V1PR / Glovsaken",
    Folder         = "V1PRWARE",
    Size           = UDim2.fromOffset(350, 300),
    Transparent    = false,
    Theme          = "Dark",
    Resizable      = false,
    SideBarWidth   = 150,
    HideSearchBar  = true,
    ScrollBarEnabled = false,
})

win:SetToggleKey(Enum.KeyCode.L)
ui:SetFont("rbxasset://fonts/families/AccanthisADFStd.json")

win:EditOpenButton({
    Title          = "V1PRWARE",
    Icon           = "sparkles",
    CornerRadius   = UDim.new(0, 16),
    StrokeThickness = 0,
    Color = ColorSequence.new(Color3.fromHex("000000"), Color3.fromHex("000000")),
    OnlyMobile = true,
    Enabled    = true,
    Draggable  = true,
})

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------
local function getTeamFolder(name)
    local root = svc.WS:FindFirstChild("Players")
    return root and root:FindFirstChild(name)
end
local function getIngame()
    local m = svc.WS:FindFirstChild("Map")
    return m and m:FindFirstChild("Ingame")
end
local function getMapContent()
    local ig = getIngame()
    return ig and ig:FindFirstChild("Map")
end

-- FIX: centralised Network require so path is corrected in one place
local _networkModule = nil
local function getNetwork()
    if _networkModule then return _networkModule end
    local ok, m = pcall(function()
        return require(svc.RS.Modules.Network.Network)
    end)
    if ok and m then _networkModule = m end
    return _networkModule
end

------------------------------------------------------------------------
------------------------------------------------------------------------
-- TAB: SETTINGS
------------------------------------------------------------------------
------------------------------------------------------------------------
local tabSettings = win:Tab({ Title = "Settings", Icon = "settings" })
local secInterface = tabSettings:Section({ Title = "Interface", Opened = true })

local chatForceEnabled = cfg.get("chatForceEnabled", false)
local chatForceConn    = nil
local function enforceChatOn()
    if not chatForceEnabled then return end
    local cw = svc.TextChat:FindFirstChild("ChatWindowConfiguration")
    local ci = svc.TextChat:FindFirstChild("ChatInputBarConfiguration")
    if cw and not cw.Enabled then cw.Enabled = true end
    if ci and not ci.Enabled then ci.Enabled = true end
end
secInterface:Toggle({
    Title = "Show Chat Logs", Type = "Checkbox", Default = chatForceEnabled,
    Callback = function(on)
        chatForceEnabled = on; cfg.set("chatForceEnabled", on)
        if chatForceConn then chatForceConn:Disconnect(); chatForceConn = nil end
        if on then
            enforceChatOn()
            chatForceConn = svc.Run.Heartbeat:Connect(enforceChatOn)
            for _, key in ipairs({ "ChatWindowConfiguration", "ChatInputBarConfiguration" }) do
                local obj = svc.TextChat:FindFirstChild(key)
                if obj then obj:GetPropertyChangedSignal("Enabled"):Connect(enforceChatOn) end
            end
        end
    end
})

------------------------------------------------------------------------
------------------------------------------------------------------------
-- TAB: GLOBAL
------------------------------------------------------------------------
------------------------------------------------------------------------
local tabGlobal  = win:Tab({ Title = "Global", Icon = "globe" })
local secStamina = tabGlobal:Section({ Title = "Stamina", Opened = true })

local stam = {
    on      = cfg.get("stamOn",      false),
    loss    = cfg.get("stamLoss",    10),
    gain    = cfg.get("stamGain",    20),
    max     = cfg.get("stamMax",     100),
    current = cfg.get("stamCurrent", 100),
    noLoss  = cfg.get("stamNoLoss",  false),
    thread  = nil,
}

-- FIX: corrected path — verify this in your explorer under ReplicatedStorage.Systems
local function stamModule()
    local ok, m = pcall(function() return require(svc.RS.Systems.Character.Game.Sprinting) end)
    return ok and m or nil
end
local function stamIsKiller()
    local ch = lp.Character; if not ch then return false end
    local kf = getTeamFolder("Killers")
    return kf and ch:IsDescendantOf(kf)
end
local function stamApply()
    local m = stamModule(); if not m then return end
    if not m.DefaultsSet then pcall(function() m.Init() end) end
    local forceNoLoss = stam.noLoss or stamIsKiller()
    m.StaminaLoss = stam.loss; m.StaminaGain = stam.gain
    local abilityCapActive = type(m.StaminaCap) == "number" and m.StaminaCap < (m.MaxStamina or math.huge)
    if not abilityCapActive then
        m.MaxStamina = stam.max
        if type(m.StaminaCap) == "number" then m.StaminaCap = stam.max end
    end
    m.StaminaLossDisabled = forceNoLoss
    if m.Stamina and m.Stamina > stam.max then m.Stamina = stam.current end
    pcall(function() if m.__staminaChangedEvent then m.__staminaChangedEvent:Fire() end end)
end
local function stamStart()
    if stam.thread then return end
    stam.thread = task.spawn(function()
        while stam.on do
            if lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") then stamApply() end
            task.wait(0.5)
        end; stam.thread = nil
    end)
end
local function stamStop()
    if stam.thread then task.cancel(stam.thread); stam.thread = nil end
end

secStamina:Toggle({
    Title = "Enable Stamina Mod", Type = "Checkbox", Default = stam.on,
    Callback = function(on)
        stam.on = on; cfg.set("stamOn", on)
        if on then stamStart() else stamStop() end
    end
})
secStamina:Slider({
    Title = "Stamina Loss", Value = { Min = 0, Max = 100, Default = stam.loss }, Step = 1,
    Callback = function(v) stam.loss = v; cfg.set("stamLoss", v) end
})
secStamina:Slider({
    Title = "Stamina Gain", Value = { Min = 0, Max = 100, Default = stam.gain }, Step = 1,
    Callback = function(v) stam.gain = v; cfg.set("stamGain", v) end
})
secStamina:Slider({
    Title = "Max Stamina", Value = { Min = 0, Max = 500, Default = stam.max }, Step = 5,
    Callback = function(v) stam.max = v; cfg.set("stamMax", v) end
})
secStamina:Toggle({
    Title = "No Stamina Loss", Type = "Checkbox", Default = stam.noLoss,
    Callback = function(on) stam.noLoss = on; cfg.set("stamNoLoss", on) end
})

------------------------------------------------------------------------
------------------------------------------------------------------------
-- TAB: AI PLAY (Killer-side)
------------------------------------------------------------------------
------------------------------------------------------------------------
local tabAI = win:Tab({ Title = "AI", Icon = "cpu" })
local secAIMain = tabAI:Section({ Title = "Killer AI", Opened = true })

secAIMain:Paragraph({
    Title   = "What this does",
    Content = "Pathfinds to the nearest survivor using PathfindingService. Killer-only — switch to killer before enabling.",
})

local ai_enabled      = cfg.get("aiKillerEnabled",  false)
local ai_resetOnDeath = cfg.get("aiResetOnDeath",   true)
local ai_thread       = nil
local PathfindingService = game:GetService("PathfindingService")

local function getKillerTeamFolder()
    local wsp = svc.WS:FindFirstChild("Players")
    return wsp and wsp:FindFirstChild("Killers")
end

local function getNearestSurvivor()
    local char = lp.Character; if not char then return nil end
    local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return nil end
    local pf   = svc.WS:FindFirstChild("Players")
    local sf   = pf and pf:FindFirstChild("Survivors")
    if not sf then return nil end
    local best, bd = nil, math.huge
    for _, model in ipairs(sf:GetChildren()) do
        local shrp = model:FindFirstChild("HumanoidRootPart")
        local hum  = model:FindFirstChildOfClass("Humanoid")
        if shrp and hum and hum.Health > 0 then
            local d = (shrp.Position - hrp.Position).Magnitude
            if d < bd then bd = d; best = shrp end
        end
    end
    return best
end

local function getClosestGenerator()
    local char = lp.Character; if not char then return nil end
    local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return nil end
    local ig   = getIngame(); if not ig then return nil end
    local mapC = ig:FindFirstChild("Map"); if not mapC then return nil end
    local best, bd = nil, math.huge
    for _, v in ipairs(mapC:GetChildren()) do
        if v.Name == "Generator" then
            local pp = v:FindFirstChild("HumanoidRootPart") or v.PrimaryPart or v:FindFirstChildOfClass("BasePart")
            if pp then
                local d = (pp.Position - hrp.Position).Magnitude
                if d < bd then bd = d; best = pp end
            end
        end
    end
    return best
end

-- FIXED: Corrected fireAbility function for Forsaken
local function fireAbility(abilityName)
    local net = getNetwork()
    if not net then 
        print("[DEBUG] Network module not found")
        return false 
    end
    if not net.FireServerConnection then 
        print("[DEBUG] FireServerConnection not found")
        return false 
    end
    
    print("[DEBUG] Firing ability: " .. abilityName)
    pcall(function()
        net:FireServerConnection("UseActorAbility", "REMOTE_EVENT", abilityName)
    end)
    return true
end

local abilityConfig = {
    lastAbilityTime = 0,
    cooldown = 2,
    range = 13,
}

local function aiKillerLoop()
    local lastAbilityTime = 0
    local abilityFireCooldown = 2 -- Cooldown between abilities (2 seconds)
    
    while ai_enabled do
        task.wait(0.15)
        local char = lp.Character; if not char then task.wait(1); continue end
        
        local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
        local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then
            if ai_resetOnDeath then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Dead) end) end
            task.wait(3); continue
        end

        local targetHRP = getNearestSurvivor()
        if targetHRP then
            local distance = (targetHRP.Position - hrp.Position).Magnitude
            
            -- Fire ability if within range and cooldown is ready
            if distance <= abilityConfig.range then
                local currentTime = tick()
                if currentTime - lastAbilityTime >= abilityConfig.cooldown then
                    fireAbility("Slash")
                    lastAbilityTime = currentTime
                end
            end
            
            -- Pathfind toward target
            local path = PathfindingService:CreatePath({
                AgentRadius = 2, AgentHeight = 5,
                AgentCanJump = true, AgentJumpHeight = 7.2,
            })
            local ok = pcall(function() path:ComputeAsync(hrp.Position, targetHRP.Position) end)
            if ok and path.Status == Enum.PathStatus.Success then
                for _, wp in ipairs(path:GetWaypoints()) do
                    if not ai_enabled then break end
                    if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
                    hum:MoveTo(wp.Position)
                    local reached = hum.MoveToFinished:Wait()
                    if not reached then break end
                end
            else
                -- Fallback: direct MoveTo (no teleport)
                hum:MoveTo(targetHRP.Position)
                task.wait(0.5)
            end
        end
    end
end

secAIMain:Toggle({
    Title = "Enable Killer AI Farm", Type = "Checkbox", Default = ai_enabled,
    Callback = function(on)
        ai_enabled = on; cfg.set("aiKillerEnabled", on)
        if on then
            if ai_thread then task.cancel(ai_thread) end
            ai_thread = task.spawn(aiKillerLoop)
        else
            if ai_thread then task.cancel(ai_thread); ai_thread = nil end
            local char = lp.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum:MoveTo(char.HumanoidRootPart.Position) end
            end
        end
    end
})

secAIMain:Toggle({
    Title = "Auto Reset on Death", Type = "Checkbox", Default = ai_resetOnDeath,
    Callback = function(on) ai_resetOnDeath = on; cfg.set("aiResetOnDeath", on) end
})

local secAICtrl = tabAI:Section({ Title = "Control", Opened = true })
secAICtrl:Button({
    Title = "Stop AI", Callback = function()
        ai_enabled = false
        if ai_thread then task.cancel(ai_thread); ai_thread = nil end
    end
})

------------------------------------------------------------------------
------------------------------------------------------------------------
-- TAB: SPOOF DEVICE
------------------------------------------------------------------------
------------------------------------------------------------------------
local tabSpoof = win:Tab({ Title = "Spoof", Icon = "smartphone" })

do
    local secSpoof = tabSpoof:Section({ Title = "Spoof Device", Opened = true })

    secSpoof:Paragraph({
        Title   = "How it works",
        Content = "Hooks UserInputService.TouchEnabled and the Network module so the server reads the spoofed platform. Apply BEFORE joining a match for best results.",
    })

    local spoof_device  = cfg.get("spoofDevice",  "PC")
    local spoof_applied = false

    local deviceMap = {
        PC      = { touch = false, platform = "Windows" },
        Mobile  = { touch = true,  platform = "IOS"     },
        Console = { touch = false,  platform = "XBoxOne" },
    }

    local function applySpoof(device)
        local info = deviceMap[device]
        if not info then return end

        -- Hook TouchEnabled
        pcall(function()
            local uis = svc.Input
            local mt  = getrawmetatable and getrawmetatable(uis)
            if mt then
                local old_index = mt.__index
                setreadonly(mt, false)
                mt.__index = function(self, key)
                    if key == "TouchEnabled" then return info.touch end
                    return old_index(self, key)
                end
                setreadonly(mt, true)
            end
        end)

        -- Hook Network platform field
        pcall(function()
            local m = require(svc.RS.Modules.Network.Network)
            if m and m.FireServerConnection then
                local orig = m.FireServerConnection
                m.FireServerConnection = function(self, event, etype, data, ...)
                    if type(data) == "table" and data.Platform ~= nil then
                        data.Platform = info.platform
                    end
                    return orig(self, event, etype, data, ...)
                end
            end
        end)

        spoof_applied = true
        warn("[V1PRWARE] Spoof applied: " .. device .. " (" .. tostring(info.touch) .. " touch, " .. info.platform .. ")")
    end

    local deviceOptions = { "PC", "Mobile", "Console" }
    secSpoof:Dropdown({
        Title = "Spoof As", Values = deviceOptions, Default = spoof_device,
        Callback = function(v)
            spoof_device = type(v) == "table" and v[1] or v
            cfg.set("spoofDevice", spoof_device)
        end
    })

    secSpoof:Button({
        Title = "Apply Spoof", Callback = function()
            applySpoof(spoof_device)
        end
    })

    secSpoof:Paragraph({
        Title   = "Note",
        Content = "Spoofing requires access to setreadonly / getrawmetatable (provided by your exploit). If your executor doesn't support these, only the Network hook will apply.",
    })
end

------------------------------------------------------------------------
------------------------------------------------------------------------
-- TAB: INTERFACE
------------------------------------------------------------------------
------------------------------------------------------------------------
local tabInterface = win:Tab({ Title = "Interface", Icon = "layout-dashboard" })
local sec_030 = tabInterface:Section({ Title = "UI Functions", Opened = true })

sec_030:Button({ Title = "Close UI", Locked = false, Callback = function()
    local ok = pcall(function() win:Destroy() end)
    if not ok then pcall(function() win:Close() end) end
end })

print("V1PRWARE ready")
