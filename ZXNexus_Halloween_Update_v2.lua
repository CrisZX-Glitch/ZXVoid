-- Prevent duplicate script loads
if getgenv().ZXNexusLoaded then
    warn("⚠ ZXNexus is already running!")
    return
end
getgenv().ZXNexusLoaded = true

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local TeleportService = game:GetService("TeleportService")
local Stats = game:GetService("Stats")
local TextChatService = game:GetService("TextChatService")

-- Player
local player = Players.LocalPlayer
local WindUI

-- Tester whitelist
local TESTERS = {
    ["cris_gamesrivals000"] = true,
    ["Denny123841"] = true,
    ["meisn468"] = true,
	["jaonkkj"] = true,
}

if not TESTERS[player.Name] then
    player:Kick("This script is only for testers.")
    return
end

-- Configuration
local CONFIG = {
	MAIN_COLOR = Color3.fromRGB(255, 125, 25), -- Halloween orange accent
	DEFAULT_WALK_SPEED = 16,
	DEFAULT_JUMP_POWER = 50,
	CONFIG_FILE = "ZXNexus_MM2.json",
	CONFIG_VERSION = 10,
	VALID_TARGET_ROLES = { "Sheriff", "Hero", "Innocent" },
	TOGGLE_SPACING = 52,
	BUTTON_HEIGHT = 48,
	SPACING = 8
}

-- Global states
local FLOATING_STYLES = {
    ShootMurderer = {Size = 104, Height = 44, Shape = "Rectangle", Text = "Shoot Murderer"},
    FakeBombJump = {Size = 58, Height = 58, Shape = "Circle", Text = "Bomb Jump"},
    GrabGun = {Size = 58, Height = 58, Shape = "Circle", Text = "Get Gun"},
    Fly = {Size = 58, Height = 58, Shape = "Circle", Text = "Fly"},
    Noclip = {Size = 58, Height = 58, Shape = "Circle", Text = "Noclip"},
    JumpBoost = {Size = 70, Height = 46, Shape = "Rectangle", Text = "Jump Boost"},
    StealGun = {Size = 70, Height = 46, Shape = "Rectangle", Text = "Steal Gun"},
}

local function floatingCorner(shape, size)
    if shape == "Circle" then return UDim.new(1, 0) end
    if shape == "Rectangle" then return UDim.new(0, 5) end
    return UDim.new(0, 2) -- Square
end

local function applyFloatingShape(frame, shape, size)
    if not frame then return end
    shape = (shape == "Circle" or shape == "Square" or shape == "Rectangle") and shape or "Rectangle"
    if shape == "Circle" or shape == "Square" then
        local side = math.max(frame.Size.X.Offset, frame.Size.Y.Offset, tonumber(size) or 0)
        frame.Size = UDim2.fromOffset(side, side)
    end
    local corner = frame:FindFirstChildOfClass("UICorner")
    if not corner then corner = Instance.new("UICorner"); corner.Parent = frame end
    corner.CornerRadius = floatingCorner(shape, size)
    frame.Rotation = 0
    local stroke = frame:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Thickness = 2.25
        stroke.Color = Color3.fromRGB(255, 145, 35)
        local gradient = stroke:FindFirstChildOfClass("UIGradient")
        if not gradient then gradient = Instance.new("UIGradient"); gradient.Parent = stroke end
        gradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 38, 0)),
            ColorSequenceKeypoint.new(0.28, Color3.fromRGB(255, 105, 10)),
            ColorSequenceKeypoint.new(0.52, Color3.fromRGB(255, 215, 145)),
            ColorSequenceKeypoint.new(0.76, Color3.fromRGB(255, 135, 25)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 38, 0)),
        })
        gradient.Rotation = 25
    end
end
local ROLE_HELPERS
local ZXNexusSkidFling
local refreshDropESP
local updateHitboxESP

local AIMLOCK = {
    Enabled = false,
    Connection = nil,
    BodyPart = "Head",
    TargetRole = "Auto",
    UseDistance = false,
    MaxDistance = 150,
    WallCheck = true,
    PreviousShiftLock = nil,
    ChangedShiftLock = false,
    ShiftLockCaptured = false,
}
local getMM2MouseLockEvent, getMM2ShiftLockState, setMM2ShiftLock, waitForMM2ShiftLockState
local HITBOX_ESP = {
    Enabled = false,
    Size = 8,
    Objects = {},
}

local DROP_ESP = {
    Gun = false,
    Trap = false,
    Objects = {},
}
local ROUND_STATE = {Active = false, Known = false}
local resetInitialTrapExclusion

local SHOOT_CONFIG = {
    -- YARHM basic prediction defaults.
    ShootOffset = 2.8,
    OffsetToPingMult = 1,
    WallCheck = true,
}

-- YARHM basic prediction adapted for ZXNexus.
-- Formula kept equivalent to YARHM's basic predictor:
-- velocity weighting + Humanoid.MoveDirection * shootOffset,
-- then the optional ping multiplier.
local function getPredictedPosition(targetPlayer, _offset)
    if not targetPlayer or not targetPlayer.Character then
        return Vector3.zero
    end

    local targetCharacter = targetPlayer.Character
    local targetPart = targetCharacter:FindFirstChild("UpperTorso")
        or targetCharacter:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")

    if not targetPart or not targetHumanoid then
        return targetPart and targetPart.Position or Vector3.zero
    end

    local velocity = targetPart.AssemblyLinearVelocity
    local moveDirection = targetHumanoid.MoveDirection
    local shootOffset = tonumber(SHOOT_CONFIG.ShootOffset) or 2.8
    local offsetToPingMult = tonumber(SHOOT_CONFIG.OffsetToPingMult) or 1

    local predictedPosition = targetPart.Position
        + (velocity * Vector3.new(0.75, 0.5, 0.75)) * (shootOffset / 15)
        + moveDirection * shootOffset

    predictedPosition = predictedPosition * (
        ((player:GetNetworkPing() * 1000) * ((offsetToPingMult - 1) * 0.01)) + 1
    )

    return predictedPosition
end
local ZXNexus_ANTI_FLING = {
    Enabled = false,
    Detection = nil,
    Neutralizer = nil,
    LastPos = Vector3.zero,
}
local STATES = {
	AutoFarm = {
		Enabled = false,
		Farming = false,
		BagFull = false,
		Resetting = false,
		StartPosition = nil,
        CandyMode = false,
        AutoResetAt50 = false,
        CandyLimit = 50,
        LastCandyReset = 0,
        FlingMurderer = false,
        KillAll = false,
	},
	KillAll = {
		Enabled = false,
		AttackDelay = 0.5
	},
	Movement = {
		SpeedWalk = { Enabled = false, Value = CONFIG.DEFAULT_WALK_SPEED },
		JumpPower = { Enabled = false, Value = CONFIG.DEFAULT_JUMP_POWER }
	},
	ShootMurderer = {
		ButtonData = nil,
		ShootFunction = nil,
		Position = nil,
		Locked = false
	},
	FakeBombJump = {
		ButtonData = nil,
		Position = nil,
		Locked = false
	},
	GrabGun = {
		ButtonData = nil,
		Position = nil,
		Locked = false
	},
	GUIVisible = true,
	Performance = {
		Enabled = false,
		Overlay = nil,
		Position = nil
	},
	AntiFling = {
		Enabled = false,
		Connections = nil
	},
	MuteRadio = {
		Enabled = false
	},
    MovementExtras = {
        Noclip = false,
        Fly = false,
        JumpBoost = false,
        FlySpeed = 60,
        NoclipConnection = nil,
        FlyConnection = nil,
        FlyVelocity = nil,
        JumpBoostConnection = nil,
        JumpBoostLastAt = 0,
    },
    OFXRemoved = false,
}

-- Farming statistics
local FARMING_STATS = {
	CoinsCollected = 0,
	StartTime = 0,
	IsRunning = false
}

-- RemoteEvents cache
local REMOTE_EVENTS = {
	CoinCollected = nil,
	RoundStart = nil,
	RoundEnd = nil
}

-- Outline gradients
local STROKE_GRADIENT = {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 38, 0)),
        ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 105, 10)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 205, 115)),
        ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 135, 25)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 38, 0))
    }),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.04),
        NumberSequenceKeypoint.new(0.25, 0),
        NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(0.75, 0),
        NumberSequenceKeypoint.new(1, 0.04)
    })
}

-- UI elements
local UI_ELEMENTS = {
	ScreenGui = nil,
	OpenCloseGui = nil,
	MainFrame = nil,
	TabButtonsContainer = nil,
	ContentFrame = nil,
	Tabs = {},
	ToggleCallbacks = {},
	ToggleStates = {}
}

-- Notification queue
local ActiveNotifications = {} -- legacy, never displayed
local NOTIFICATION_HEIGHT = 85

-- Utility functions
local UTILS = {}

function UTILS.playClickSound()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://138656262630730"
	sound.Volume = 0.7
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 2)
end

function UTILS.showNotification(title, message, duration)
    -- Legacy ZXNexus notification UI intentionally disabled.
    -- WindUI is the only visible notification system.
end

function UTILS.createInstance(className, parent, properties)
	local obj = Instance.new(className, parent)
	for prop, value in pairs(properties) do
		obj[prop] = value
	end
	return obj
end

function UTILS.safeDestroy(obj)
	if obj and obj.Parent then
		obj:Destroy()
	end
end

function UTILS.secondsToMinutes(seconds)
	if seconds == -1 then return "" end
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	return string.format("%dm %ds", minutes, remainingSeconds)
end

function UTILS.getHRP()
	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		return player.Character.HumanoidRootPart
	end
	return nil
end

function UTILS.addSpacer(parent, positionY, height)
	return UTILS.createInstance("Frame", parent, {
		Name = "Spacer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		Position = UDim2.new(0, 0, 0, positionY)
	})
end

function UTILS.updateCanvasSize(scrollingFrame, contentFrame)
	if not scrollingFrame or not contentFrame or not scrollingFrame:IsA("ScrollingFrame") then
		return
	end
	
	local totalHeight = 0
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			totalHeight = totalHeight + child.AbsoluteSize.Y
		end
	end
	
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 100)
	contentFrame.Size = UDim2.new(1, 0, 0, totalHeight + 80)
end

function UTILS.updateTabButtonsContainerSize(container)
	local totalHeight = 0
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			totalHeight = totalHeight + child.AbsoluteSize.Y + 8
		end
	end
	
	container.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
end

function UTILS.joinAnotherServer()
    -- Server hop: find another public server for the same place.
    local HttpService = game:GetService("HttpService")
    local currentJobId = game.JobId
    local cursor = ""
    local candidates = {}

    for _ = 1, 3 do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s"):format(
            game.PlaceId,
            cursor ~= "" and ("&cursor=" .. HttpService:UrlEncode(cursor)) or ""
        )
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if not ok then break end

        local okJson, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not okJson or not data then break end

        for _, server in ipairs(data.data or {}) do
            if server.id ~= currentJobId and (server.playing or 0) < (server.maxPlayers or 0) then
                table.insert(candidates, server.id)
            end
        end

        cursor = data.nextPageCursor or ""
        if cursor == "" then break end
    end

    if #candidates > 0 then
        local target = candidates[math.random(1, #candidates)]
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, target, player)
        end)
    else
        pcall(function()
            TeleportService:Teleport(game.PlaceId, player)
        end)
    end
end

local function findTeleportPart(container, preferredNames)
    if not container then return nil end
    for _, name in ipairs(preferredNames) do
        local obj = container:FindFirstChild(name, true)
        if obj and obj:IsA("BasePart") then return obj end
    end
    for _, obj in ipairs(container:GetDescendants()) do
        if obj:IsA("SpawnLocation") or (obj:IsA("BasePart") and obj.Name:lower():find("spawn")) then
            return obj
        end
    end
    return nil
end

function UTILS.teleportToMap()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    local map = workspace:FindFirstChild("Map")
    if map then
        local part = findTeleportPart(map, {"Spawn", "SpawnLocation", "MapSpawn", "PlayerSpawn"})
        if not part then
            -- MM2 maps often contain a single SpawnLocation somewhere inside the map model.
            part = findTeleportPart(map, {})
        end
        if part then
            root.AssemblyLinearVelocity = Vector3.zero
            char:PivotTo(part.CFrame + Vector3.new(0, 3, 0))
            return true
        end
    end
    return false
end

function UTILS.teleportToLobby()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    local lobby = workspace:FindFirstChild("Lobby")
    local part = findTeleportPart(lobby, {"Spawn", "SpawnLocation", "LobbySpawn", "PlayerSpawn"})
    if not part then
        -- Some MM2 builds expose lobby spawn parts directly in Workspace.
        part = findTeleportPart(workspace, {"LobbySpawn", "LobbySpawnLocation"})
    end
    if part then
        root.AssemblyLinearVelocity = Vector3.zero
        char:PivotTo(part.CFrame + Vector3.new(0, 3, 0))
        return true
    end
    return false
end

function UTILS.rejoinServer()
    -- Rejoin the exact current public server.
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
    end)
end

function UTILS.createStaticStroke(frame)
	local stroke = UTILS.createInstance("UIStroke", frame, {
		Thickness = 2,
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	})
	
	local gradient = UTILS.createInstance("UIGradient", stroke, {
		Color = STROKE_GRADIENT.Color,
		Transparency = STROKE_GRADIENT.Transparency,
		Rotation = 0
	})
	
	return stroke
end

function UTILS.createWithStaticStroke(className, parent, properties)
	local obj = UTILS.createInstance(className, parent, properties)
	if className == "Frame" or className == "TextButton" or className == "ScrollingFrame" then
		UTILS.createStaticStroke(obj)
	end
	return obj
end

-- ESP and highlight system
local ESP_SYSTEM = {}

ESP_SYSTEM.ESP_STATES = {
	ESPName = false,
	MurdererName = true,
	SheriffName = true,
	HeroName = true,
	InnocentName = true
}

ESP_SYSTEM.ESP_HIGHLIGHT_STATES = {
	ESPHighlight = false,
	ESPHighlightMurderer = true,
	ESPHighlightSheriff = true,
	ESPHighlightHero = true,
	ESPHighlightInnocent = true
}

-- ESP line states (updated logic)
ESP_SYSTEM.ESP_LINE_STATES = {
    ESPLine = false,           -- master line toggle
    MurdererLine = true,       -- Murderer lines
    SheriffLine = true,        -- Sheriff lines
    HeroLine = true,           -- Hero lines
    InnocentLine = true,       -- Innocent lines
    LineThickness = 1.4,       -- line thickness
    LineTransparency = 1       -- line transparency (1 = visible, 0 = invisible)
}

ESP_SYSTEM.ROLE_COLORS = {
	Murderer = Color3.fromRGB(255, 0, 0),
	Sheriff = Color3.fromRGB(0, 0, 255),
	Hero = Color3.fromRGB(255, 255, 0),
	Innocent = Color3.fromRGB(0, 255, 0)
}

ESP_SYSTEM.billboards = {}
ESP_SYSTEM.currentRoles = {}
ESP_SYSTEM.Camera = workspace.CurrentCamera
ESP_SYSTEM.LineDrawings = {}

ESP_SYSTEM.MIN_DISTANCE = 5
ESP_SYSTEM.MAX_DISTANCE = 100
ESP_SYSTEM.MIN_SIZE = UDim2.new(0, 50, 0, 12)
ESP_SYSTEM.MAX_SIZE = UDim2.new(0, 200, 0, 50)
ESP_SYSTEM.MIN_TEXT_SIZE = 8
ESP_SYSTEM.MAX_TEXT_SIZE = 18

local cachedRolesData = {}
local lastRoleUpdate = 0
local UPDATE_INTERVAL = 0.15
local lineConnections = {} -- Stores line connections

function ESP_SYSTEM.IsPlayerOnScreen(targetPlayer)
    if not ESP_SYSTEM.Camera then return true end
    
    local character = targetPlayer.Character
    if not character then return false end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return false end
    
    local screenPoint, onScreen = ESP_SYSTEM.Camera:WorldToViewportPoint(humanoidRootPart.Position)
    
    if onScreen then
        local viewportSize = ESP_SYSTEM.Camera.ViewportSize
        if screenPoint.X >= -50 and screenPoint.X <= viewportSize.X + 50 and
           screenPoint.Y >= -50 and screenPoint.Y <= viewportSize.Y + 50 then
            return true
        end
    end
    
    return false
end

function ESP_SYSTEM.IsPlayerVisible(targetPlayer)
    if not ESP_SYSTEM.IsPlayerOnScreen(targetPlayer) then
        return false
    end
    return true
end

function ESP_SYSTEM.GetRolesData()
	local currentTime = tick()
	if currentTime - lastRoleUpdate < UPDATE_INTERVAL then
		return cachedRolesData
	end
	
	local success, rolesData = pcall(function()
		local getPlayerData = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
		if getPlayerData and getPlayerData:IsA("RemoteFunction") then
			return getPlayerData:InvokeServer()
		end
		return {}
	end)
	
	if success and rolesData then
		cachedRolesData = rolesData
		lastRoleUpdate = currentTime
	end
	
	return cachedRolesData
end

function ESP_SYSTEM.IsAlive(targetPlayer, rolesData)
	if not rolesData then return false end
	
	local playerData = rolesData[targetPlayer.Name]
	return playerData and not playerData.Killed and not playerData.Dead
end

function ESP_SYSTEM.getPlayerRole(targetPlayer, rolesData)
	if not rolesData then return nil, false end
	
	local playerData = rolesData[targetPlayer.Name]
	if not playerData then return nil, false end
	
	return playerData.Role, ESP_SYSTEM.IsAlive(targetPlayer, rolesData)
end

function ESP_SYSTEM.GetPlayerColorByRole(role, isAlive)
	if not isAlive then
		return Color3.fromRGB(150, 150, 150)
	end
	
	if role == "Murderer" then
		return Color3.fromRGB(255, 0, 0)
	elseif role == "Sheriff" then
		return Color3.fromRGB(0, 0, 255)
	elseif role == "Hero" then
		return Color3.fromRGB(255, 255, 0)
	elseif role == "Innocent" then
		return Color3.fromRGB(0, 255, 0)
	else
		return Color3.fromRGB(255, 255, 255)
	end
end

-- Checks whether a line should be shown for the selected role
function ESP_SYSTEM.ShouldShowLineForRole(role)
	if not ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
		return false
	end
	
	if role == "Murderer" and ESP_SYSTEM.ESP_LINE_STATES.MurdererLine then
		return true
	elseif role == "Sheriff" and ESP_SYSTEM.ESP_LINE_STATES.SheriffLine then
		return true
	elseif role == "Hero" and ESP_SYSTEM.ESP_LINE_STATES.HeroLine then
		return true
	elseif role == "Innocent" and ESP_SYSTEM.ESP_LINE_STATES.InnocentLine then
		return true
	end
	return false
end

-- Reliable tracer using regular ScreenGui/Frame objects instead of the Drawing API.
local TRACER_GUI
local function ensureTracerGui()
    if TRACER_GUI and TRACER_GUI.Parent then return TRACER_GUI end
    TRACER_GUI = Instance.new("ScreenGui")
    TRACER_GUI.Name = "ZXNexusTracerGui"
    TRACER_GUI.ResetOnSpawn = false
    TRACER_GUI.IgnoreGuiInset = true
    TRACER_GUI.ZIndexBehavior = Enum.ZIndexBehavior.Global
    TRACER_GUI.DisplayOrder = 999
    TRACER_GUI.Parent = CoreGui
    return TRACER_GUI
end

function ESP_SYSTEM.CreateLineDrawing()
    local frame = Instance.new("Frame")
    frame.Name = "Tracer"
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BorderSizePixel = 0
    frame.BackgroundColor3 = Color3.new(1, 1, 1)
    frame.BackgroundTransparency = 0
    frame.Visible = false
    frame.ZIndex = 999
    frame.Parent = ensureTracerGui()
    return frame
end

function ESP_SYSTEM.GetLineForPlayer(playerName)
    local drawing = ESP_SYSTEM.LineDrawings[playerName]
    if not drawing or not drawing.Parent then
        drawing = ESP_SYSTEM.CreateLineDrawing()
        ESP_SYSTEM.LineDrawings[playerName] = drawing
    end
    return drawing
end

function ESP_SYSTEM.RemoveLineForPlayer(playerName)
    local drawing = ESP_SYSTEM.LineDrawings[playerName]
    if drawing then
        drawing:Destroy()
        ESP_SYSTEM.LineDrawings[playerName] = nil
    end
end

function ESP_SYSTEM.ClearAllLines()
    for playerName, drawing in pairs(ESP_SYSTEM.LineDrawings) do
        if drawing then pcall(function() drawing:Destroy() end) end
    end
    ESP_SYSTEM.LineDrawings = {}
end

function ESP_SYSTEM.UpdateCamera()
    ESP_SYSTEM.Camera = workspace.CurrentCamera
end

function ESP_SYSTEM.StopAllLines()
    for _, conn in ipairs(lineConnections) do
        if conn then pcall(function() conn:Disconnect() end) end
    end
    lineConnections = {}
    ESP_SYSTEM.ClearAllLines()
end

function ESP_SYSTEM.InitializePlayerLines(targetPlayer)
    if not targetPlayer or targetPlayer == player then return nil end
    local line = ESP_SYSTEM.GetLineForPlayer(targetPlayer.Name)
    local cachedRole, cachedIsAlive = nil, false
    local lastRoleFetch = 0

    local connection
    connection = RunService.RenderStepped:Connect(function()
        if not ESP_SYSTEM.ESP_LINE_STATES.ESPLine or not targetPlayer.Parent then
            line.Visible = false
            if not targetPlayer.Parent then
                pcall(function() connection:Disconnect() end)
                ESP_SYSTEM.RemoveLineForPlayer(targetPlayer.Name)
            end
            return
        end

        ESP_SYSTEM.UpdateCamera()
        local char = targetPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 or not ESP_SYSTEM.Camera then
            line.Visible = false
            return
        end

        if tick() - lastRoleFetch >= 0.25 then
            local rolesData = ESP_SYSTEM.GetRolesData()
            cachedRole, cachedIsAlive = ESP_SYSTEM.getPlayerRole(targetPlayer, rolesData)
            lastRoleFetch = tick()
        end

        if not cachedIsAlive or not ESP_SYSTEM.ShouldShowLineForRole(cachedRole) then
            line.Visible = false
            return
        end

        local screenPos, onScreen = ESP_SYSTEM.Camera:WorldToViewportPoint(hrp.Position)
        local vp = ESP_SYSTEM.Camera.ViewportSize
        local from = Vector2.new(vp.X / 2, vp.Y / 2)
        local to = Vector2.new(screenPos.X, screenPos.Y)
        -- Tracer is visible only while the target is inside the camera viewport.
        if not onScreen or screenPos.Z < 0
            or screenPos.X < 0 or screenPos.X > vp.X
            or screenPos.Y < 0 or screenPos.Y > vp.Y then
            line.Visible = false
            return
        end
        to = Vector2.new(math.clamp(to.X, 4, vp.X - 4), math.clamp(to.Y, 4, vp.Y - 4))
        local delta = to - from
        local length = delta.Magnitude
        if length < 2 then
            line.Visible = false
            return
        end

        line.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
        line.Size = UDim2.fromOffset(length, math.max(1, ESP_SYSTEM.ESP_LINE_STATES.LineThickness))
        line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
        line.BackgroundColor3 = ESP_SYSTEM.GetPlayerColorByRole(cachedRole, cachedIsAlive)
        line.BackgroundTransparency = 1 - ESP_SYSTEM.ESP_LINE_STATES.LineTransparency
        line.Visible = true
    end)

    return connection
end

-- Start all lines
function ESP_SYSTEM.StartAllLines()
    ESP_SYSTEM.StopAllLines()
    
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then
            local conn = ESP_SYSTEM.InitializePlayerLines(targetPlayer)
            table.insert(lineConnections, conn)
        end
    end
end

function ESP_SYSTEM.updatePlayerBillboard(targetPlayer, role, isAlive)
	if targetPlayer == player then return end
	
	local character = targetPlayer.Character
	if not character then return end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end
	
	local distance = (ESP_SYSTEM.Camera.CFrame.Position - humanoidRootPart.Position).Magnitude
	local billboard = humanoidRootPart:FindFirstChild("PlayerBillboard")
	
	local color
	if role == "Murderer" and isAlive then
		color = ESP_SYSTEM.ROLE_COLORS.Murderer
	elseif role == "Sheriff" and isAlive then
		color = ESP_SYSTEM.ROLE_COLORS.Sheriff
	elseif role == "Hero" and isAlive then
		color = ESP_SYSTEM.ROLE_COLORS.Hero
	elseif role == "Innocent" and isAlive then
		color = ESP_SYSTEM.ROLE_COLORS.Innocent
	else
		color = Color3.fromRGB(255, 255, 255)
	end
	
	if billboard then
		local textLabel = billboard:FindFirstChild("PlayerName")
		if textLabel then
			textLabel.TextColor3 = color
			textLabel.Text = targetPlayer.Name
		end
	else
		billboard = Instance.new("BillboardGui")
		billboard.Name = "PlayerBillboard"
		billboard.Adornee = humanoidRootPart
		billboard.AlwaysOnTop = true
		billboard.Size = UDim2.new(0, 100, 0, 30)
		billboard.StudsOffset = Vector3.new(0, 2.5, 0)
		billboard.ResetOnSpawn = false
		
		local textLabel = Instance.new("TextLabel")
		textLabel.Name = "PlayerName"
		textLabel.Size = UDim2.new(1, 0, 1, 0)
		textLabel.BackgroundTransparency = 1
		textLabel.Text = targetPlayer.Name
		textLabel.TextColor3 = color
		textLabel.Font = Enum.Font.GothamBold
		textLabel.TextSize = 14
		textLabel.TextStrokeTransparency = 0.5
		textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		textLabel.Parent = billboard
		
		billboard.Parent = humanoidRootPart
		ESP_SYSTEM.billboards[targetPlayer] = billboard
	end
end

function ESP_SYSTEM.removePlayerBillboard(targetPlayer)
	if targetPlayer == player then return end
	
	if ESP_SYSTEM.billboards[targetPlayer] then
		ESP_SYSTEM.billboards[targetPlayer]:Destroy()
		ESP_SYSTEM.billboards[targetPlayer] = nil
	end
	
	local character = targetPlayer.Character
	if character then
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			local billboard = humanoidRootPart:FindFirstChild("PlayerBillboard")
			if billboard then
				billboard:Destroy()
			end
		end
	end
end

function ESP_SYSTEM.clearAllESP()
	for targetPlayer, billboard in pairs(ESP_SYSTEM.billboards) do
		if billboard and billboard.Parent then
			billboard:Destroy()
		end
	 end
	ESP_SYSTEM.billboards = {}
end

function ESP_SYSTEM.updatePlayerHighlight(targetPlayer, role, isAlive)
	if targetPlayer == player then return end
	
	local character = targetPlayer.Character
	if not character then return end
	
	local highlight = character:FindFirstChild("PlayerHighlight")
	
	if not highlight or not highlight:IsA("Highlight") then
		if highlight then
			highlight:Destroy()
		end
		
		highlight = Instance.new("Highlight")
		highlight.Name = "PlayerHighlight"
		highlight.Adornee = character
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 0.7
		highlight.OutlineTransparency = 0.4
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.Parent = character
	end
	
	local color
	if role == "Murderer" and isAlive then
		color = Color3.fromRGB(255, 0, 0)
	elseif role == "Sheriff" and isAlive then
		color = Color3.fromRGB(0, 0, 255)
	elseif role == "Hero" and isAlive then
		color = Color3.fromRGB(255, 255, 0)
	elseif role == "Innocent" and isAlive then
		color = Color3.fromRGB(0, 255, 0)
	else
		color = Color3.fromRGB(255, 255, 255)
	end
	
	highlight.FillColor = color
end

function ESP_SYSTEM.removePlayerHighlight(targetPlayer)
	if targetPlayer == player then return end
	
	local character = targetPlayer.Character
	if character then
		local highlight = character:FindFirstChild("PlayerHighlight")
		if highlight and highlight:IsA("Highlight") then
			highlight:Destroy()
		end
	end
end

function ESP_SYSTEM.clearAllHighlights()
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player then
			ESP_SYSTEM.removePlayerHighlight(targetPlayer)
		end
	end
end

function ESP_SYSTEM.updateESP()
	if not ESP_SYSTEM.ESP_STATES.ESPName then
		ESP_SYSTEM.clearAllESP()
		return
	end
	
	local rolesData = ESP_SYSTEM.GetRolesData()
	
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer == player then continue end
		
		local character = targetPlayer.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		
		if not character or not humanoidRootPart then
			ESP_SYSTEM.removePlayerBillboard(targetPlayer)
			continue
		end
		
		local role, isAlive = ESP_SYSTEM.getPlayerRole(targetPlayer, rolesData)
		
		local shouldShow = false
		if role == "Murderer" and ESP_SYSTEM.ESP_STATES.MurdererName then
			shouldShow = true
		elseif role == "Sheriff" and ESP_SYSTEM.ESP_STATES.SheriffName then
			shouldShow = true
		elseif role == "Hero" and ESP_SYSTEM.ESP_STATES.HeroName then
			shouldShow = true
		elseif role == "Innocent" and ESP_SYSTEM.ESP_STATES.InnocentName then
			shouldShow = true
		elseif not role or (role ~= "Murderer" and role ~= "Sheriff" and role ~= "Hero" and role ~= "Innocent") then
			-- Lobby / intermission / unknown role: keep the player ESP visible.
			shouldShow = true
		end
		
		if shouldShow then
			ESP_SYSTEM.updatePlayerBillboard(targetPlayer, role, isAlive)
		else
			ESP_SYSTEM.removePlayerBillboard(targetPlayer)
		end
	end
end

function ESP_SYSTEM.updateHighlights()
	if not ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
		ESP_SYSTEM.clearAllHighlights()
		return
	end
	
	local rolesData = ESP_SYSTEM.GetRolesData()
	
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer == player then continue end
		
		local character = targetPlayer.Character
		if not character then 
			ESP_SYSTEM.removePlayerHighlight(targetPlayer)
			continue
		end
		
		local role, isAlive = ESP_SYSTEM.getPlayerRole(targetPlayer, rolesData)
		
		local shouldShow = false
		if role == "Murderer" and ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlightMurderer then
			shouldShow = true
		elseif role == "Sheriff" and ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlightSheriff then
			shouldShow = true
		elseif role == "Hero" and ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlightHero then
			shouldShow = true
		elseif role == "Innocent" and ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlightInnocent then
			shouldShow = true
		elseif not role or (role ~= "Murderer" and role ~= "Sheriff" and role ~= "Hero" and role ~= "Innocent") then
			-- Lobby / intermission / unknown role.
			shouldShow = true
		end
		
		if shouldShow then
			ESP_SYSTEM.updatePlayerHighlight(targetPlayer, role, isAlive)
		else
			ESP_SYSTEM.removePlayerHighlight(targetPlayer)
		end
	end
end

function ESP_SYSTEM.initializePlayer(targetPlayer)
	if targetPlayer == player then return end
	
	local function onCharacterAdded(character)
		task.wait(0.5)
		ESP_SYSTEM.updateESP()
	end
	
	local function onCharacterRemoving()
		ESP_SYSTEM.removePlayerBillboard(targetPlayer)
		ESP_SYSTEM.removePlayerHighlight(targetPlayer)
	end
	
	targetPlayer.CharacterAdded:Connect(onCharacterAdded)
	targetPlayer.CharacterRemoving:Connect(onCharacterRemoving)
	
	if targetPlayer.Character then
		task.spawn(onCharacterAdded, targetPlayer.Character)
	end
end

-- Anti-fling system
local ANTI_FLING = {}

function ANTI_FLING.enable()
    if STATES.AntiFling.Enabled then
        return
    end
    
    STATES.AntiFling.Enabled = true
    
    local localPlayer = player
    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
    
    local function disableAllPlayersParts()
        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            if targetPlayer ~= localPlayer and targetPlayer.Character then
                for _, part in ipairs(targetPlayer.Character:GetDescendants()) do
                    if part:IsA("BasePart") and not part.Anchored then
                        part.CanCollide = false
                    end
                end
            end
        end
    end
    
    disableAllPlayersParts()
    
    local antiFlingTask = nil
    antiFlingTask = task.spawn(function()
        while STATES.AntiFling.Enabled do
            task.wait(0.3)
            
            if not character or character.Parent == nil then
                character = localPlayer.Character
                if character then
                    humanoid = character:FindFirstChild("Humanoid")
                    if humanoid then
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                    end
                end
            end
            
            disableAllPlayersParts()
        end
    end)
    
    local function onPlayerAdded(targetPlayer)
        if targetPlayer ~= localPlayer then
            targetPlayer.CharacterAdded:Connect(function(char)
                task.wait(0.2)
                if STATES.AntiFling.Enabled then
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") and not part.Anchored then
                            part.CanCollide = false
                        end
                    end
                end
            end)
        end
    end
    
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        onPlayerAdded(targetPlayer)
    end
    
    local playerAddedConnection
    playerAddedConnection = Players.PlayerAdded:Connect(onPlayerAdded)
    
    local characterAddedConnection
    characterAddedConnection = localPlayer.CharacterAdded:Connect(function(newChar)
        character = newChar
        humanoid = character:FindFirstChild("Humanoid")
        if humanoid and STATES.AntiFling.Enabled then
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        end
        task.wait(0.2)
        if STATES.AntiFling.Enabled then
            disableAllPlayersParts()
        end
    end)
    
    STATES.AntiFling.Connections = {
        task = antiFlingTask,
        playerAdded = playerAddedConnection,
        characterAdded = characterAddedConnection
    }
end

function ANTI_FLING.disable()
    if not STATES.AntiFling.Enabled then
        return
    end
    
    STATES.AntiFling.Enabled = false
    
    if STATES.AntiFling.Connections and STATES.AntiFling.Connections.task then
        task.cancel(STATES.AntiFling.Connections.task)
    end
    
    if STATES.AntiFling.Connections and STATES.AntiFling.Connections.playerAdded then
        STATES.AntiFling.Connections.playerAdded:Disconnect()
    end
    
    if STATES.AntiFling.Connections and STATES.AntiFling.Connections.characterAdded then
        STATES.AntiFling.Connections.characterAdded:Disconnect()
    end
    
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player and targetPlayer.Character then
            for _, part in ipairs(targetPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
    end
    
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
        end
    end
    
    STATES.AntiFling.Connections = nil
end

-- Mute Radio function
local function toggleMuteRadio(value)
    STATES.MuteRadio.Enabled = value
    
    local function muteRadioSounds()
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Sound") and obj.Name == "RadioSound" then
                if value then
                    obj.Volume = 0
                else
                    obj.Volume = 1
                end
            end
        end
    end
    
    muteRadioSounds()
    
    local connection
    connection = workspace.DescendantAdded:Connect(function(descendant)
        if STATES.MuteRadio.Enabled and descendant:IsA("Sound") and descendant.Name == "RadioSound" then
            descendant.Volume = 0
        end
    end)
    
    if value then
        if not STATES.MuteRadio.Connection then
            STATES.MuteRadio.Connection = connection
        end
    else
        if STATES.MuteRadio.Connection then
            STATES.MuteRadio.Connection:Disconnect()
            STATES.MuteRadio.Connection = nil
        end
    end
end

-- Farming systems
local FARMING = {}

function FARMING.isRoundActive()
    if ROUND_STATE.Known then return ROUND_STATE.Active == true end
    local map = workspace:FindFirstChild("Map")
    if not map then return false end
    -- Fallback when remote events were missed: require an active map with a coin container.
    for _, obj in ipairs(map:GetDescendants()) do
        if obj.Name == "CoinContainer" and #obj:GetChildren() > 0 then return true end
    end
    return false
end

function FARMING.getNearestCoin()
    if not FARMING.isRoundActive() then return nil, math.huge end
	local root = UTILS.getHRP()
	if not root then return nil, math.huge end
	
	local nearestCoin = nil
	local nearestDistance = math.huge
	
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:FindFirstChild("CoinContainer") then
			for _, coin in ipairs(obj.CoinContainer:GetChildren()) do
				local coinId = coin:GetAttribute("CoinID")
                local isCandy = coinId == "Candy" or coin.Name:lower():find("candy") ~= nil
                local wanted = STATES.AutoFarm.CandyMode and isCandy or (not STATES.AutoFarm.CandyMode and coinId == "Coin")
                if coin:IsA("BasePart") and wanted and coin:FindFirstChild("TouchInterest") then
					local distance = (root.Position - coin.Position).Magnitude
					if distance < nearestDistance then
						nearestDistance = distance
						nearestCoin = coin
					end
				end
			end
		end
	end
	
	return nearestCoin, nearestDistance
end

local farmingLoopActive = true

function FARMING.startFarmingLoop()
	task.spawn(function()
		while farmingLoopActive do
			local waitTime = 0.1
			
			if STATES.AutoFarm.Enabled and STATES.AutoFarm.Farming and not STATES.AutoFarm.BagFull and FARMING.isRoundActive() then
				local coin, dist = FARMING.getNearestCoin()
				local hrp = UTILS.getHRP()
				
				if coin and hrp then
					if dist > 150 then
						hrp.CFrame = coin.CFrame
					else
						local tween = TweenService:Create(hrp, TweenInfo.new(dist / 25, Enum.EasingStyle.Linear), {CFrame = coin.CFrame})
						tween:Play()
						
						local startTime = tick()
						repeat
							task.wait()
							if tick() - startTime > 5 then break end
						until not coin:FindFirstChild("TouchInterest") or not STATES.AutoFarm.Farming or not STATES.AutoFarm.Enabled
						
						if tween then tween:Cancel() end
					end
				end
            elseif STATES.AutoFarm.Enabled then
                -- Stay idle in the lobby/intermission; only the round-start signal or
                -- the map fallback may permit coin/candy movement.
                STATES.AutoFarm.Farming = FARMING.isRoundActive()
                waitTime = 0.75
			else
				waitTime = 1
			end
			
			task.wait(waitTime)
		end
	end)
end

function FARMING.autoReset()
    if not STATES.AutoFarm.Enabled or not STATES.AutoFarm.BagFull then return end
    if STATES.AutoFarm.CandyMode and STATES.AutoFarm.AutoResetAt50 then
        if tick() - (STATES.AutoFarm.LastCandyReset or 0) < 3 then return end
        STATES.AutoFarm.LastCandyReset = tick()
        STATES.AutoFarm.Resetting = true
        STATES.AutoFarm.Farming = false
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then pcall(function() humanoid.Health = 0 end) end
        task.delay(2.5, function()
            STATES.AutoFarm.BagFull = false
            STATES.AutoFarm.Resetting = false
            if STATES.AutoFarm.Enabled then STATES.AutoFarm.Farming = FARMING.isRoundActive() end
        end)
    else
        STATES.AutoFarm.Farming = false
        STATES.AutoFarm.Resetting = false
    end
end
-- Kill All system
local KILL_ALL = {}

function KILL_ALL.getPlayerRoleFromServer(targetPlayer)
    if not targetPlayer then return nil end
    local roles = ESP_SYSTEM and ESP_SYSTEM.GetRolesData and ESP_SYSTEM.GetRolesData()
    local entry = roles and (roles[targetPlayer.Name] or roles[tostring(targetPlayer.UserId)] or roles[targetPlayer.UserId])
    return entry and (entry.Role or entry.role or entry.RoleName or entry.roleName or entry.TeamRole) or nil
end

function KILL_ALL.hasKnife()
    local char = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")
    return (char and char:FindFirstChild("Knife") ~= nil) or (backpack and backpack:FindFirstChild("Knife") ~= nil) or false
end

function KILL_ALL.equipKnife()
    local backpack = player:FindFirstChildOfClass("Backpack")
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid then return false end
    local knife = character:FindFirstChild("Knife") or (backpack and backpack:FindFirstChild("Knife"))
    if not knife then return false end
    if knife.Parent ~= character then
        local ok = pcall(function() humanoid:EquipTool(knife) end)
        if not ok then pcall(function() knife.Parent = character end) end
    end
    return character:FindFirstChild("Knife") ~= nil
end

function KILL_ALL.getNearestTarget()
    local validTargets = {}
    local myRoot = UTILS.getHRP()
    if not myRoot then return nil end
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player and targetPlayer.Character then
            local role = KILL_ALL.getPlayerRoleFromServer(targetPlayer)
            local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
            local root = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            if role and humanoid and humanoid.Health > 0 and root and table.find(CONFIG.VALID_TARGET_ROLES, role) then
                table.insert(validTargets, {Player = targetPlayer, Distance = (myRoot.Position - root.Position).Magnitude})
            end
        end
    end
    table.sort(validTargets, function(a, b) return a.Distance < b.Distance end)
    return validTargets[1] and validTargets[1].Player or nil
end

function KILL_ALL.getAllValidTargets(roleFilter)
    local validTargets = {}
    local roles = ESP_SYSTEM and ESP_SYSTEM.GetRolesData and ESP_SYSTEM.GetRolesData()
    if not roles then return validTargets end
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player and targetPlayer.Character then
            local record = roles[targetPlayer.Name] or roles[tostring(targetPlayer.UserId)] or roles[targetPlayer.UserId]
            local role = record and (record.Role or record.role or record.RoleName or record.roleName or record.TeamRole)
            local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
            if role and humanoid and humanoid.Health > 0 and table.find(CONFIG.VALID_TARGET_ROLES, role) and (not roleFilter or role == roleFilter) then
                table.insert(validTargets, targetPlayer)
            end
        end
    end
    return validTargets
end

function KILL_ALL.killTargetThroughEvent(target)
    if not target or target == player or not target.Character or not KILL_ALL.equipKnife() then return false end
    local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")
    local character = player.Character
    local knife = character and character:FindFirstChild("Knife")
    if not targetHumanoid or targetHumanoid.Health <= 0 or not knife then return false end
    pcall(function() knife:Activate() end)
    local stab = knife:FindFirstChild("Stab", true)
    if stab and stab:IsA("RemoteEvent") then pcall(function() stab:FireServer("Down") end) end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local killEvent = remotes and remotes:FindFirstChild("Gameplay") and remotes.Gameplay:FindFirstChild("KillEvent")
    if killEvent and killEvent:IsA("RemoteEvent") then
        return pcall(function() killEvent:FireServer(target.Name, Color3.new(1, 0, 0)) end)
    end
    return false
end

local killAllLoopActive = true
local killAllRunning = false

function KILL_ALL.killAllPlayers(forceRun, roleFilter)
    if killAllRunning then return false end
    if not forceRun and not STATES.KillAll.Enabled and not STATES.AutoFarm.KillAll then return false end
    if not KILL_ALL.equipKnife() then return false end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local myRoot = UTILS.getHRP()
    local knife = character and character:FindFirstChild("Knife")
    if not character or not humanoid or humanoid.Health <= 0 or not myRoot or not knife then return false end

    local allTargets = KILL_ALL.getAllValidTargets(roleFilter)
    if #allTargets == 0 then return false end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local gameplay = remotes and remotes:FindFirstChild("Gameplay")
    local killEvent = gameplay and gameplay:FindFirstChild("KillEvent")
    local stab = knife:FindFirstChild("Stab", true)
    killAllRunning = true
    local processed = 0
    local ok, err = xpcall(function()
        -- Keep the Murderer's character in place. Arrange every target in front of
        -- the Murderer first; do not teleport the local player from one target to another.
        local forward = myRoot.CFrame.LookVector
        local right = myRoot.CFrame.RightVector
        local center = myRoot.Position
        local positioned = {}
        for index, target in ipairs(allTargets) do
            if target ~= player and target.Parent == Players then
                local targetChar = target.Character
                local targetHumanoid = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
                local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
                if targetHumanoid and targetHumanoid.Health > 0 and targetRoot then
                    local row = math.floor((#positioned) / 3)
                    local column = (#positioned % 3) - 1
                    local destination = center + forward * (3.25 + row * 1.8) + right * (column * 1.7)
                    pcall(function()
                        targetRoot.CFrame = CFrame.lookAt(destination, center)
                        targetRoot.AssemblyLinearVelocity = Vector3.zero
                        targetRoot.AssemblyAngularVelocity = Vector3.zero
                    end)
                    table.insert(positioned, target)
                end
            end
        end

        -- Equip once and attack from the same location. Server-side validation still
        -- determines whether the existing MM2 remotes accept each attack.
        task.wait(0.06)
        pcall(function() knife:Activate() end)
        if stab and stab:IsA("RemoteEvent") then
            pcall(function() stab:FireServer("Down") end)
        end
        for _, target in ipairs(positioned) do
            if not forceRun and not STATES.KillAll.Enabled and not STATES.AutoFarm.KillAll then break end
            local targetChar = target.Character
            local targetHumanoid = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
            if targetHumanoid and targetHumanoid.Health > 0 then
                if killEvent and killEvent:IsA("RemoteEvent") then
                    pcall(function() killEvent:FireServer(target.Name, Color3.new(1, 0, 0)) end)
                end
                processed += 1
                task.wait(0.025)
            end
        end
    end, debug.traceback)

    killAllRunning = false
    if not ok then warn("[ZXNexus Kill All] " .. tostring(err)) end
    return ok and processed > 0
end

function KILL_ALL.startKillAllLoop()
    task.spawn(function()
        while killAllLoopActive do
            if STATES.KillAll.Enabled or STATES.AutoFarm.KillAll then
                if KILL_ALL.hasKnife() then
                    KILL_ALL.killAllPlayers(false)
                    task.wait(0.45)
                else
                    task.wait(0.25)
                end
            else
                task.wait(0.35)
            end
        end
    end)
end

-- Movement systems
local MOVEMENT = {}

function MOVEMENT.updateWalkSpeed()
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		player.Character.Humanoid.WalkSpeed = STATES.Movement.SpeedWalk.Enabled and 
			STATES.Movement.SpeedWalk.Value or CONFIG.DEFAULT_WALK_SPEED
	end
end

function MOVEMENT.updateJumpPower()
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		player.Character.Humanoid.JumpPower = STATES.Movement.JumpPower.Enabled and 
			STATES.Movement.JumpPower.Value or CONFIG.DEFAULT_JUMP_POWER
	end
end

-- RemoteEvents system
local REMOTE_SYSTEM = {}

function REMOTE_SYSTEM.findRemoteEvents()
	for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
		if obj:IsA("RemoteEvent") then
			if obj.Name == "CoinCollected" then
				REMOTE_EVENTS.CoinCollected = obj
			elseif obj.Name == "RoundStart" then
				REMOTE_EVENTS.RoundStart = obj
			elseif obj.Name == "RoundEnd" then
				REMOTE_EVENTS.RoundEnd = obj
			end
		end
		
		if REMOTE_EVENTS.CoinCollected and REMOTE_EVENTS.RoundStart and REMOTE_EVENTS.RoundEnd then
			break
		end
	end
end

function REMOTE_SYSTEM.connectRemoteEvents()
	if REMOTE_EVENTS.CoinCollected then
		REMOTE_EVENTS.CoinCollected.OnClientEvent:Connect(function(_, current, max)
			if STATES.AutoFarm.Enabled then
				FARMING_STATS.CoinsCollected = FARMING_STATS.CoinsCollected + 1
			end
			
			local candyLimitReached = STATES.AutoFarm.CandyMode and tonumber(current) and tonumber(current) >= (STATES.AutoFarm.CandyLimit or 50)
            if (candyLimitReached or current == max) and not STATES.AutoFarm.Resetting then
				STATES.AutoFarm.BagFull = true
				if STATES.AutoFarm.Enabled then task.spawn(FARMING.autoReset) end
			end
		end)
	end
	
	if REMOTE_EVENTS.RoundStart then
        REMOTE_EVENTS.RoundStart.OnClientEvent:Connect(function()
            ROUND_STATE.Known = true
            ROUND_STATE.Active = true
            if resetInitialTrapExclusion then resetInitialTrapExclusion() end
            refreshDropESP()
			STATES.AutoFarm.Farming = true
			STATES.AutoFarm.BagFull = false
			
			local hrp = UTILS.getHRP()
			if hrp then
				STATES.AutoFarm.StartPosition = hrp.CFrame
			end
		end)
	end
	
	if REMOTE_EVENTS.RoundEnd then
        REMOTE_EVENTS.RoundEnd.OnClientEvent:Connect(function()
            ROUND_STATE.Known = true
            ROUND_STATE.Active = false
            if resetInitialTrapExclusion then resetInitialTrapExclusion() end
            refreshDropESP()
			STATES.AutoFarm.Farming = false
			STATES.KillAll.Enabled = false
		end)
	end
end

-- Creates the performance stats overlay
local function createPerformanceOverlay()
    if STATES.Performance.Overlay then
        return
    end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "StatsOverlay"
    screenGui.Parent = CoreGui
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    screenGui.DisplayOrder = 95
    screenGui.ResetOnSpawn = false
    
    local frame = UTILS.createWithStaticStroke("Frame", screenGui, {
        Name = "StatsFrame",
        Size = UDim2.new(0, 100, 0, 40),
        Position = STATES.Performance.Position or UDim2.new(0.5, -50, 0.5, -20),
        BackgroundColor3 = Color3.fromRGB(18, 30, 50),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 5
    })
    
    UTILS.createInstance("UICorner", frame, {CornerRadius = UDim.new(0, 4)})
    
    local bgGradient = UTILS.createInstance("UIGradient", frame, {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 55, 85)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 35, 58))
        }),
        Rotation = 90
    })
    
    local statsContainer = UTILS.createInstance("Frame", frame, {
        Name = "StatsContainer",
        Size = UDim2.new(1, -4, 1, -4),
        Position = UDim2.new(0, 2, 0, 2),
        BackgroundTransparency = 1,
        ZIndex = 6
    })
    
    local pingLabel = UTILS.createInstance("TextLabel", statsContainer, {
        Name = "PingLabel",
        Size = UDim2.new(1, 0, 0.5, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(232, 245, 255),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
        TextSize = 10,
        RichText = true,
        Text = "<font color='rgb(50, 150, 255)'>●</font> Ping: ...",
        ZIndex = 7
    })
    
    local fpsLabel = UTILS.createInstance("TextLabel", statsContainer, {
        Name = "FPSLabel",
        Size = UDim2.new(1, 0, 0.5, 0),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(232, 245, 255),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
        TextSize = 10,
        RichText = true,
        Text = "<font color='rgb(50, 150, 255)'>●</font> FPS: ...",
        ZIndex = 7
    })
    
    local isDragging = false
    local dragStartPos
    local frameStartPos
    local dragTouchId
    local DRAG_THRESHOLD = 5
    
    local dragButton = UTILS.createInstance("TextButton", frame, {
        Name = "DragButton",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 10
    })
    
    dragButton.AutoButtonColor = false
    dragButton.Selected = false
    
    local function onDragStart(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then

                -- Locked buttons can be clicked but cannot be dragged.
                if STATES.GrabGun.Locked then
                    isDragging = false
                    wasClick = true
                    dragTouchId = nil
                    dragStartPos = nil
                    buttonStartPos = nil
                    return Enum.ContextActionResult.Sink
                end

                -- Locked buttons can be clicked but cannot be dragged.
                if STATES.FakeBombJump.Locked then
                    isDragging = false
                    wasClick = true
                    dragTouchId = nil
                    dragStartPos = nil
                    buttonStartPos = nil
                    return Enum.ContextActionResult.Sink
                end
            
            isDragging = false
            dragTouchId = input.UserInputType == Enum.UserInputType.Touch and input
            dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
            frameStartPos = frame.Position
            
            frame.BackgroundColor3 = Color3.fromRGB(30, 48, 75)
            
            return Enum.ContextActionResult.Sink
        end
    end
    
    local function onDrag(input)
        if not dragStartPos then return end
        
        if input.UserInputType == Enum.UserInputType.Touch then
            if not dragTouchId or dragTouchId ~= input then
                return
            end
        end
        
        local currentPos = Vector2.new(input.Position.X, input.Position.Y)
        local delta = currentPos - dragStartPos
        
        if not isDragging and delta.Magnitude > DRAG_THRESHOLD then
            isDragging = true
        end
        
        if isDragging then
            local newPosition = UDim2.new(
                frameStartPos.X.Scale,
                frameStartPos.X.Offset + delta.X,
                frameStartPos.Y.Scale,
                frameStartPos.Y.Offset + delta.Y
            )
            
            frame.Position = newPosition
        end
    end
    
    local function onDragEnd(input)
        frame.BackgroundColor3 = Color3.fromRGB(18, 30, 50)
        
        if isDragging then
            local finalPosition = frame.Position
            if not STATES.Performance then
                STATES.Performance = {}
            end
            STATES.Performance.Position = finalPosition
        end
        
        isDragging = false
        dragStartPos = nil
        dragTouchId = nil
        frameStartPos = nil
    end
    
    dragButton.InputBegan:Connect(onDragStart)
    dragButton.InputChanged:Connect(onDrag)
    dragButton.InputEnded:Connect(onDragEnd)
    
    local lastTime = tick()
    local frameCount = 0
    local updateConnection
    
    updateConnection = RunService.RenderStepped:Connect(function()
        frameCount = frameCount + 1
        if tick() - lastTime >= 1 then
            local success, ping = pcall(function()
                return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            
            if success then
                local pingColor
                if ping < 50 then
                    pingColor = "rgb(100, 255, 100)"
                elseif ping < 100 then
                    pingColor = "rgb(255, 255, 100)"
                elseif ping < 200 then
                    pingColor = "rgb(255, 150, 100)"
                else
                    pingColor = "rgb(255, 100, 100)"
                end
                
                pingLabel.Text = string.format(
                    "<font color='rgb(50, 150, 255)'>●</font> Ping: <font color='%s'>%d</font>",
                    pingColor, ping
                )
            else
                pingLabel.Text = "<font color='rgb(50, 150, 255)'>●</font> Ping: ..."
            end
            
            local fpsColor
            if frameCount >= 60 then
                fpsColor = "rgb(100, 255, 100)"
            elseif frameCount >= 30 then
                fpsColor = "rgb(255, 255, 100)"
            else
                fpsColor = "rgb(255, 100, 100)"
            end
            
            fpsLabel.Text = string.format(
                "<font color='rgb(50, 150, 255)'>●</font> FPS: <font color='%s'>%d</font>",
                fpsColor, frameCount
            )
            
            frameCount = 0
            lastTime = tick()
        end
    end)
    
    STATES.Performance.Overlay = {
        gui = screenGui,
        frame = frame,
        connections = {
            update = updateConnection
        },
        destroy = function()
            if updateConnection then updateConnection:Disconnect() end
            if screenGui then screenGui:Destroy() end
            STATES.Performance.Overlay = nil
        end
    }
end

-- WindUI bridge registries (legacy callbacks are preserved)
local LEGACY_TOGGLES = {}
local LEGACY_BUTTONS = {}

-- Factory for styled buttons
local function createStyledButton(parent, config)
    config = config or {}
    
    local buttonContainer = UTILS.createWithStaticStroke("Frame", parent, {
        Name = config.name or "StyledButton",
        BackgroundColor3 = config.backgroundColor or Color3.fromRGB(22, 35, 55),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Size = config.size or UDim2.new(1, -20, 0, 50),
        Position = config.position or UDim2.new(0, 10, 0, 0),
        ZIndex = 5
    })
    
    UTILS.createInstance("UICorner", buttonContainer, {CornerRadius = UDim.new(0, 8)})
    
    local iconContainer = UTILS.createInstance("Frame", buttonContainer, {
        Name = "IconContainer",
        BackgroundColor3 = Color3.fromRGB(38, 65, 100),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 36, 0, 36),
        Position = UDim2.new(0, 12, 0.5, -18),
        ZIndex = 6
    })
    UTILS.createInstance("UICorner", iconContainer, {CornerRadius = UDim.new(1, 0)})
    
    local icon = UTILS.createInstance("ImageLabel", iconContainer, {
        Name = "Icon",
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(0.5, -12, 0.5, -12),
        Image = config.icon or "rbxthumb://type=Asset&id=77289067728929&w=150&h=150",
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 7
    })
    
    local titleLabel = UTILS.createInstance("TextLabel", buttonContainer, {
        Name = "Title",
        Text = config.title or "Button",
        TextColor3 = Color3.fromRGB(232, 245, 255),
        TextSize = 15,
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 55, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 7
    })
    
    local button = UTILS.createInstance("TextButton", buttonContainer, {
        Name = "Button",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 8
    })
    
    button.MouseEnter:Connect(function()
        TweenService:Create(buttonContainer, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(35, 55, 85),
            BackgroundTransparency = 0.1
        }):Play()
        
        TweenService:Create(titleLabel, TweenInfo.new(0.15), {
            TextColor3 = Color3.fromRGB(255, 255, 255)
        }):Play()
        
        TweenService:Create(iconContainer, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(80, 65, 100)
        }):Play()
    end)
    
    button.MouseLeave:Connect(function()
        TweenService:Create(buttonContainer, TweenInfo.new(0.15), {
            BackgroundColor3 = config.backgroundColor or Color3.fromRGB(22, 35, 55),
            BackgroundTransparency = 0.2
        }):Play()
        
        TweenService:Create(titleLabel, TweenInfo.new(0.15), {
            TextColor3 = Color3.fromRGB(232, 245, 255)
        }):Play()
        
        TweenService:Create(iconContainer, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(38, 65, 100)
        }):Play()
    end)
    
    button.MouseButton1Click:Connect(function()
        UTILS.playClickSound()
        
        TweenService:Create(buttonContainer, TweenInfo.new(0.05), {
            Size = UDim2.new(1, -20, 0, 48)
        }):Play()
        
        task.wait(0.05)
        
        TweenService:Create(buttonContainer, TweenInfo.new(0.05), {
            Size = config.size or UDim2.new(1, -20, 0, 50)
        }):Play()
        
        local originalColor = buttonContainer.BackgroundColor3
        buttonContainer.BackgroundColor3 = config.accentColor or CONFIG.MAIN_COLOR
        task.wait(0.1)
        buttonContainer.BackgroundColor3 = originalColor
        
        if config.onClick then
            config.onClick()
        end
    end)
    
    if config.title and config.onClick then
        LEGACY_BUTTONS[config.title] = config.onClick
    end

    return {
        container = buttonContainer,
        button = button,
        title = titleLabel,
        icon = icon
    }
end

-- Creates toggles without size animation
local function createToggle(parent, text, positionY, stateTable, stateKey, callback)
    local toggleFrame = UTILS.createWithStaticStroke("Frame", parent, {
        Name = text .. "Toggle",
        Size = UDim2.new(1, -20, 0, 45),
        Position = UDim2.new(0, 10, 0, positionY),
        BackgroundColor3 = Color3.fromRGB(22, 35, 55),
        BackgroundTransparency = 0.5,
        ZIndex = 5
    })
    UTILS.createInstance("UICorner", toggleFrame, {CornerRadius = UDim.new(0, 8)})
    
    local title = UTILS.createInstance("TextLabel", toggleFrame, {
        Text = text,
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 15, 0, 0),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(230, 230, 230),
        TextSize = 14,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6
    })
    
    local switchBg = UTILS.createInstance("Frame", toggleFrame, {
        Size = UDim2.new(0, 40, 0, 20),
        Position = UDim2.new(1, -55, 0.5, -10),
        BackgroundColor3 = stateTable[stateKey] and CONFIG.MAIN_COLOR or Color3.fromRGB(60, 50, 70),
        ZIndex = 6
    })
    UTILS.createInstance("UICorner", switchBg, {CornerRadius = UDim.new(1, 0)})
    
    local ball = UTILS.createInstance("Frame", switchBg, {
        Size = UDim2.new(0, 16, 0, 16),
        Position = stateTable[stateKey] and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        ZIndex = 7
    })
    UTILS.createInstance("UICorner", ball, {CornerRadius = UDim.new(1, 0)})
    
    local button = UTILS.createInstance("TextButton", toggleFrame, {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = 8
    })
    
    button.MouseButton1Click:Connect(function()
        stateTable[stateKey] = not stateTable[stateKey]
        local newState = stateTable[stateKey]
        
        TweenService:Create(switchBg, TweenInfo.new(0.3), {
            BackgroundColor3 = newState and CONFIG.MAIN_COLOR or Color3.fromRGB(60, 50, 70)
        }):Play()
        
        TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
            Position = newState and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        }):Play()
        
        if callback then
            task.spawn(callback, newState)
        end        
        UTILS.playClickSound()
    end)
    
    button.MouseEnter:Connect(function()
        TweenService:Create(toggleFrame, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(45, 35, 55),
            BackgroundTransparency = 0.3
        }):Play()
    end)
    
    button.MouseLeave:Connect(function()
        TweenService:Create(toggleFrame, TweenInfo.new(0.2), {
            BackgroundColor3 = Color3.fromRGB(22, 35, 55),
            BackgroundTransparency = 0.5
        }):Play()
    end)
    
    LEGACY_TOGGLES[text] = {
        stateTable = stateTable,
        stateKey = stateKey,
        callback = callback,
    }

    return toggleFrame, button
end

-- UI system
local UI_SYSTEM = {}

function UI_SYSTEM.createPlayerInfoContainer(parent)
	local playerInfoContainer = UTILS.createWithStaticStroke("Frame", parent, {
		Name = "PlayerInfoContainer",
		BackgroundColor3 = Color3.fromRGB(25, 40, 65),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 360, 0, 100),
		Position = UDim2.new(0, 8, 0, 8),
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", playerInfoContainer, {CornerRadius = UDim.new(0, 8)})
	
	local avatarInfoFrame = UTILS.createInstance("Frame", playerInfoContainer, {
		Name = "AvatarInfoFrame",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.new(0, 8, 0, 8),
		ZIndex = 6
	})
	
	local playerAvatar = UTILS.createInstance("ImageLabel", avatarInfoFrame, {
		Name = "PlayerAvatar",
		BackgroundColor3 = Color3.fromRGB(38, 62, 95),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 64, 0, 64),
		Position = UDim2.new(0, 0, 0, 0),
		Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", player.UserId),
		ZIndex = 7
	})
	
	UTILS.createInstance("UICorner", playerAvatar, {CornerRadius = UDim.new(0, 8)})
	
	local infoFrame = UTILS.createInstance("Frame", avatarInfoFrame, {
		Name = "InfoFrame",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -72, 1, 0),
		Position = UDim2.new(0, 72, 0, 0),
		ZIndex = 6
	})
	
	UTILS.createInstance("TextLabel", infoFrame, {
		Name = "DisplayName",
		Text = player.DisplayName,
		TextColor3 = Color3.fromRGB(250, 240, 255),
		TextSize = 18,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0, 0),
		ZIndex = 7
	})
	
	UTILS.createInstance("TextLabel", infoFrame, {
		Name = "Username",
		Text = "@" .. player.Name,
		TextColor3 = Color3.fromRGB(205, 225, 245),
		TextSize = 12,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 24),
		ZIndex = 7
	})
	
	UTILS.createInstance("TextLabel", infoFrame, {
		Name = "GameName",
		Text = "Murder Mystery 2",
		TextColor3 = Color3.fromRGB(175, 215, 245),
		TextSize = 14,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 48),
		ZIndex = 7
	})
	
	UTILS.createInstance("TextLabel", infoFrame, {
		Name = "PlayerId",
		Text = "Player ID: " .. tostring(player.UserId),
		TextColor3 = Color3.fromRGB(205, 225, 245),
		TextSize = 12,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(0.48, -4, 0, 18),
		Position = UDim2.new(0, 0, 0, 72),
		ZIndex = 7
	})
	
	UTILS.createInstance("TextLabel", infoFrame, {
		Name = "ServerId",
		Text = "Server ID: " .. tostring(game.PlaceId),
		TextColor3 = Color3.fromRGB(205, 225, 245),
		TextSize = 12,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(0.48, -4, 0, 18),
		Position = UDim2.new(0.52, 0, 0, 72),
		ZIndex = 7
	})
	
	return playerInfoContainer
end

function UI_SYSTEM.createSpeedJumpContainer(parent)
	local speedJumpContainer = UTILS.createWithStaticStroke("Frame", parent, {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(18, 30, 50),
		BackgroundTransparency = 0.5,
		Size = UDim2.new(0, 360, 0, 180),
		Position = UDim2.new(0, 8, 0, 116),
		Name = "SpeedJumpContainer",
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", speedJumpContainer, {CornerRadius = UDim.new(0, 8)})
	
	UTILS.createInstance("TextLabel", speedJumpContainer, {
		Name = "SpeedJumpTitle",
		Text = "Speed And Jump",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextSize = 14,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 8),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6
	})
	
	local speedWalkToggle = createToggle(speedJumpContainer, "Speed Walk", 32, STATES.Movement.SpeedWalk, "Enabled", function(isEnabled)
		STATES.Movement.SpeedWalk.Enabled = isEnabled
		MOVEMENT.updateWalkSpeed()
	end)
	
	local speedWalkSliderContainer = UTILS.createInstance("Frame", speedJumpContainer, {
		Name = "SpeedWalkSliderContainer",
		BackgroundColor3 = Color3.fromRGB(22, 35, 55),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.new(0, 10, 0, 76),
		ZIndex = 6
	})
	
	UTILS.createInstance("UICorner", speedWalkSliderContainer, {CornerRadius = UDim.new(0, 8)})
	
	local speedWalkSlider = UTILS.createInstance("Frame", speedWalkSliderContainer, {
		Name = "SpeedWalkSlider",
		BackgroundColor3 = Color3.fromRGB(80, 60, 100),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		ZIndex = 7
	})
	
	UTILS.createInstance("UICorner", speedWalkSlider, {CornerRadius = UDim.new(0, 8)})
	
	local speedWalkValue = UTILS.createInstance("TextLabel", speedWalkSliderContainer, {
		Name = "SpeedWalkValue",
		Text = "16",
		TextColor3 = Color3.fromRGB(232, 245, 255),
		TextSize = 12,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 8
	})
	
	local jumpPowerToggle = createToggle(speedJumpContainer, "Jump Power", 104, STATES.Movement.JumpPower, "Enabled", function(isEnabled)
		STATES.Movement.JumpPower.Enabled = isEnabled
		MOVEMENT.updateJumpPower()
	end)
	
	local jumpPowerSliderContainer = UTILS.createInstance("Frame", speedJumpContainer, {
		Name = "JumpPowerSliderContainer",
		BackgroundColor3 = Color3.fromRGB(22, 35, 55),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.new(0, 10, 0, 148),
		ZIndex = 6
	})
	
	UTILS.createInstance("UICorner", jumpPowerSliderContainer, {CornerRadius = UDim.new(0, 8)})
	
	local jumpPowerSlider = UTILS.createInstance("Frame", jumpPowerSliderContainer, {
		Name = "JumpPowerSlider",
		BackgroundColor3 = Color3.fromRGB(80, 60, 100),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		ZIndex = 7
	})
	
	UTILS.createInstance("UICorner", jumpPowerSlider, {CornerRadius = UDim.new(0, 8)})
	
	local jumpPowerValue = UTILS.createInstance("TextLabel", jumpPowerSliderContainer, {
		Name = "JumpPowerValue",
		Text = "50",
		TextColor3 = Color3.fromRGB(232, 245, 255),
		TextSize = 12,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 8
	})
	
	local speedWalkSliderObj = UI_SYSTEM.createSlider(
		speedWalkSlider,
		speedWalkValue,
		16, 116, 16,
		function(value)
			STATES.Movement.SpeedWalk.Value = value
			if STATES.Movement.SpeedWalk.Enabled then
				MOVEMENT.updateWalkSpeed()
			end
		end
	)
	
	local jumpPowerSliderObj = UI_SYSTEM.createSlider(
		jumpPowerSlider,
		jumpPowerValue,
		50, 150, 50,
		function(value)
			STATES.Movement.JumpPower.Value = value
			if STATES.Movement.JumpPower.Enabled then
				MOVEMENT.updateJumpPower()
			end
		end
	)
	
	return speedJumpContainer
end

function UI_SYSTEM.createSlider(sliderFrame, valueLabel, minValue, maxValue, defaultValue, callback)
	local isDragging = false
	local currentValue = defaultValue or minValue
	local startPercentage = (defaultValue - minValue) / (maxValue - minValue)
	
	local thumb = UTILS.createInstance("Frame", sliderFrame.Parent, {
		Name = "SliderThumb",
		Size = UDim2.new(0, 20, 0, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(startPercentage, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 15
	})
	
	UTILS.createInstance("UICorner", thumb, {CornerRadius = UDim.new(1, 0)})
	UTILS.createInstance("UIStroke", thumb, {
		Thickness = 2,
		Color = Color3.fromRGB(50, 150, 255)
	})
	
	sliderFrame.Size = UDim2.new(startPercentage, 0, 1, 0)
	
	local function updateSlider(positionX)
		local containerWidth = sliderFrame.Parent.AbsoluteSize.X
		local newX = math.clamp(positionX, 0, containerWidth)
		local percentage = newX / containerWidth
		local value = math.floor(minValue + (maxValue - minValue) * percentage)
		
		TweenService:Create(sliderFrame, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(percentage, 0, 1, 0)
		}):Play()
		
		TweenService:Create(thumb, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(percentage, 0, 0.5, 0)
		}):Play()
		
		valueLabel.Text = tostring(value)
		currentValue = value
		
		thumb.BackgroundColor3 = isDragging and Color3.fromRGB(80, 170, 255) or Color3.fromRGB(255, 255, 255)
		sliderFrame.BackgroundColor3 = isDragging and Color3.fromRGB(120, 80, 150) or Color3.fromRGB(80, 60, 100)
		
		if callback then callback(value) end
	end
	
	local containerButton = UTILS.createInstance("TextButton", sliderFrame.Parent, {
		Name = "SliderButton",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 10
	})
	
	local thumbButton = UTILS.createInstance("TextButton", thumb, {
		Name = "ThumbButton",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 20
	})
	
	local function handleContainerInputBegan(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			local containerPosition = sliderFrame.Parent.AbsolutePosition
			local relativeX = input.Position.X - containerPosition.X
			updateSlider(relativeX)
		end
	end
	
	local thumbStartPos, thumbStartMousePos
	
	local function handleThumbInputBegan(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			thumbStartPos = thumb.Position
			thumbStartMousePos = input.Position
			thumb.BackgroundColor3 = Color3.fromRGB(80, 170, 255)
		end
	end
	
	local function handleInputEnded(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = false
			thumbStartPos = nil
			thumbStartMousePos = nil
			
			TweenService:Create(thumb, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			}):Play()
			
			TweenService:Create(sliderFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = Color3.fromRGB(80, 60, 100)
			}):Play()
		end
	end
	
	local function handleThumbInputChanged(input)
		if isDragging and thumbStartPos and thumbStartMousePos and 
		   (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local containerPosition = sliderFrame.Parent.AbsolutePosition
			local containerWidth = sliderFrame.Parent.AbsoluteSize.X
			local deltaX = input.Position.X - thumbStartMousePos.X
			local newX = math.clamp((thumbStartPos.X.Scale * containerWidth) + deltaX, 0, containerWidth)
			updateSlider(newX)
		end
	end
	
	local function handleContainerInputChanged(input)
		if isDragging and not thumbStartPos and 
		   (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local containerPosition = sliderFrame.Parent.AbsolutePosition
			local relativeX = input.Position.X - containerPosition.X
			updateSlider(relativeX)
		end
	end
	
	containerButton.InputBegan:Connect(handleContainerInputBegan)
	containerButton.InputEnded:Connect(handleInputEnded)
	containerButton.InputChanged:Connect(handleContainerInputChanged)
	
	thumbButton.InputBegan:Connect(handleThumbInputBegan)
	thumbButton.InputEnded:Connect(handleInputEnded)
	thumbButton.InputChanged:Connect(handleThumbInputChanged)
	
	local function setValue(newValue)
		newValue = math.clamp(newValue, minValue, maxValue)
		local percentage = (newValue - minValue) / (maxValue - minValue)
		
		TweenService:Create(sliderFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(percentage, 0, 1, 0)
		}):Play()
		
		TweenService:Create(thumb, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(percentage, 0, 0.5, 0)
		}):Play()
		
		valueLabel.Text = tostring(newValue)
		currentValue = newValue
		
		if callback then callback(newValue) end
	end
	
	thumbButton.MouseEnter:Connect(function()
		if not isDragging then
			TweenService:Create(thumb, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 24, 0, 24),
				BackgroundColor3 = Color3.fromRGB(230, 230, 255)
			}):Play()
		end
	end)
	
	thumbButton.MouseLeave:Connect(function()
		if not isDragging then
			TweenService:Create(thumb, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 20, 0, 20),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			}):Play()
		end
	end)
	
	containerButton.MouseEnter:Connect(function()
		TweenService:Create(sliderFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(90, 70, 110)
		}):Play()
	end)
	
	containerButton.MouseLeave:Connect(function()
		if not isDragging then
			TweenService:Create(sliderFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = Color3.fromRGB(80, 60, 100)
			}):Play()
		end
	end)
	
	setValue(defaultValue)
	
	return {
		setValue = setValue,
		getValue = function() return currentValue end,
		thumb = thumb
	}
end

function UI_SYSTEM.createTabButton(parent, text, positionY, tabName, contentFrame)
	local tabFrame = UTILS.createWithStaticStroke("Frame", parent, {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(32, 52, 82),
		Size = UDim2.new(0, 116, 0, 48),
		Position = UDim2.new(0, 4, 0, positionY),
		Name = "Tab_" .. tabName,
		BackgroundTransparency = 0.7,
		ZIndex = 12
	})
	
	UTILS.createInstance("UICorner", tabFrame, {CornerRadius = UDim.new(0, 5)})
	
	local tabButton = UTILS.createInstance("TextButton", tabFrame, {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Name = "TabButton_" .. tabName,
		ZIndex = 15
	})
	
	local textLabel = UTILS.createInstance("TextLabel", tabFrame, {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(225, 240, 255),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
		TextSize = 13,
		TextWrapped = true,
		ZIndex = 13
	})
	
	local tabContentScrolling = UTILS.createInstance("ScrollingFrame", contentFrame, {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Name = "content_" .. tabName,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.fromRGB(70, 110, 150),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 5
	})
	
	local tabContent = UTILS.createInstance("Frame", tabContentScrolling, {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Name = "contentContainer_" .. tabName,
		ZIndex = 5
	})
	
	return tabButton, tabFrame, tabContent, textLabel, tabContentScrolling
end


local function hasLineOfSight(targetCharacter, origin, targetPosition)
    if not targetCharacter or not origin or not targetPosition then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    -- Exclude only the local character; a hit on the target character is valid.
    params.FilterDescendantsInstances = {player.Character}
    local result = workspace:Raycast(origin, targetPosition - origin, params)
    return result == nil or result.Instance:IsDescendantOf(targetCharacter)
end

function UI_SYSTEM.createShootMurdererButton()
	local ScreenGui_1 = UTILS.createInstance("ScreenGui", CoreGui, {
		Name = "ShootMurdererGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
		DisplayOrder = 50
	})
	
	local shootButton_2 = UTILS.createWithStaticStroke("Frame", ScreenGui_1, {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(25, 40, 65),
		Size = UDim2.fromOffset(FLOATING_STYLES.ShootMurderer.Size, FLOATING_STYLES.ShootMurderer.Height),
		Position = STATES.ShootMurderer.Position or UDim2.new(1, -14, 0, 80),
		AnchorPoint = Vector2.new(1, 0),
		Name = "shootButton",
		BackgroundTransparency = 0.3,
		ZIndex = 1
	})
	
	UTILS.createInstance("UICorner", shootButton_2, {CornerRadius = floatingCorner(FLOATING_STYLES.ShootMurderer.Shape, FLOATING_STYLES.ShootMurderer.Size)})
    applyFloatingShape(shootButton_2, FLOATING_STYLES.ShootMurderer.Shape, math.max(FLOATING_STYLES.ShootMurderer.Size, FLOATING_STYLES.ShootMurderer.Height))
	
	local backgroundGradient = UTILS.createInstance("UIGradient", shootButton_2, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 55, 85)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 35, 58))
		}),
		Rotation = 90
	})
	
	local TextLabel_5 = UTILS.createInstance("TextLabel", shootButton_2, {
		BorderSizePixel = 0,
		TextSize = 14,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = FLOATING_STYLES.ShootMurderer.Text or "🎃 SHOOT",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextScaled = false,
		TextWrapped = true,
		ZIndex = 2
	})
	
	local isDragging = false
	local dragStartPos
	local buttonStartPos
	local dragTouchId
	local wasClick = false
	local DRAG_THRESHOLD = 5
	
	local instakillshoot = false
	
	local function findMurderer()
        -- Prefer the same server role snapshot used by Own ESP; tools are a fallback.
        local fromRoles = ROLE_HELPERS and ROLE_HELPERS.getMurderer and ROLE_HELPERS.getMurderer()
        if fromRoles then return fromRoles end
		for _, i in ipairs(Players:GetPlayers()) do
            local backpack = i:FindFirstChildOfClass("Backpack")
			if backpack and backpack:FindFirstChild("Knife") then return i end
		end
		for _, i in ipairs(Players:GetPlayers()) do
			local char = i.Character
			if char and char:FindFirstChild("Knife") then return i end
		end
		return nil
	end
	
	local function findSheriff()
		for _, i in ipairs(Players:GetPlayers()) do
            local backpack = i:FindFirstChildOfClass("Backpack")
			if backpack and backpack:FindFirstChild("Gun") then
				return i
			end
		end
	
		for _, i in ipairs(Players:GetPlayers()) do
			if not i.Character then continue end
			if i.Character:FindFirstChild("Gun") then
				return i
			end
		end
	
		return nil
	end
	
	local function shootMurdererFunction(forceWallCheck)
		if findSheriff() ~= player then 
			return false
		end
	
        local wallCheckEnabled = forceWallCheck == true or SHOOT_CONFIG.WallCheck == true
        local murderer = findMurderer()
        -- Never wait several seconds on a tap; if roles have not replicated yet, fail fast.
        if not murderer or murderer == player then return false end
        local localCharacter = player.Character
        if not localCharacter or not localCharacter:IsDescendantOf(workspace) then return false end
        local localHumanoid = localCharacter:FindFirstChildOfClass("Humanoid")
        if not localHumanoid or localHumanoid.Health <= 0 then return false end
	
        local backpack = player:FindFirstChildOfClass("Backpack")
        local gun = localCharacter:FindFirstChild("Gun")
        if not gun then
            local backpackGun = backpack and backpack:FindFirstChild("Gun")
            if not backpackGun then return false end
            local okEquip = pcall(function() localHumanoid:EquipTool(backpackGun) end)
            if not okEquip then return false end
            RunService.Heartbeat:Wait()
            localCharacter = player.Character
            gun = localCharacter and localCharacter:FindFirstChild("Gun")
            if not gun then return false end
        end

        local murdererCharacter = murderer.Character
        local murdererHRP = murdererCharacter and murdererCharacter:FindFirstChild("HumanoidRootPart")
        if not murdererCharacter or not murdererHRP then return false end
	
		local predictedPosition = getPredictedPosition(murderer, SHOOT_CONFIG.ShootOffset)
        if AIMLOCK.Enabled then
            local cam = workspace.CurrentCamera
            local body = murderer.Character:FindFirstChild(AIMLOCK.BodyPart) or murderer.Character:FindFirstChild("HumanoidRootPart")
            if cam and body then
                local aimDistance = 2000
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Exclude
                rayParams.FilterDescendantsInstances = {player.Character}
                local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * aimDistance, rayParams)
                if hit and hit.Instance:IsDescendantOf(murderer.Character) then
                    predictedPosition = hit.Position
                else
                    predictedPosition = cam.CFrame.Position + cam.CFrame.LookVector * aimDistance
                end
            end
        end
        if wallCheckEnabled then
            local originPart = player.Character:FindFirstChild("RightHand")
                or player.Character:FindFirstChild("HumanoidRootPart")
            if not originPart or not hasLineOfSight(murderer.Character, originPart.Position, predictedPosition) then
                return false
            end
        end
	
		local args
		if instakillshoot then
			args = {
				CFrame.new(murdererHRP.Position + Vector3.new(0, 1, 0)),
				CFrame.new(murdererHRP.Position)
			}
		else
			if not player.Character:FindFirstChild("RightHand") then
				return false
			end
			args = {
				CFrame.new(player.Character.RightHand.Position),
				CFrame.new(predictedPosition)
			}
		end
		
        local currentCharacter = player.Character
        local equippedGun = currentCharacter and currentCharacter:FindFirstChild("Gun")
        local shootEvent = equippedGun and equippedGun:FindFirstChild("Shoot")
        if not shootEvent or not shootEvent:IsA("RemoteEvent") then return false end
        -- Fire immediately; never hold the FloatingButton in an unbounded WaitForChild.
        shootEvent:FireServer(unpack(args))

        task.spawn(function()
            pcall(function()
                if shootButton_2 and shootButton_2.Parent then
                    local originalColor = shootButton_2.BackgroundColor3
                    local flashTween = TweenService:Create(shootButton_2, TweenInfo.new(0.05), {
                        BackgroundColor3 = Color3.fromRGB(255, 100, 100)
                    })
                    flashTween:Play()
                    task.wait(0.05)
                    if shootButton_2 and shootButton_2.Parent then
                        TweenService:Create(shootButton_2, TweenInfo.new(0.05), {
                            BackgroundColor3 = originalColor
                        }):Play()
                    end
                end
            end)
        end)
		return true
	end
	
	local function onDragStart(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or 
		   input.UserInputType == Enum.UserInputType.Touch then

			-- Locked buttons still click, but cannot be moved.
			if STATES.ShootMurderer.Locked then
                isDragging = false
                wasClick = true
                dragTouchId = nil
                dragStartPos = nil
                buttonStartPos = nil
                return Enum.ContextActionResult.Sink
            end
			
			isDragging = false
			wasClick = true
			dragTouchId = input.UserInputType == Enum.UserInputType.Touch and input
			dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
			buttonStartPos = shootButton_2.Position
			
			shootButton_2.BackgroundColor3 = Color3.fromRGB(32, 55, 90)
			shootButton_2.BackgroundTransparency = 0.2
			
			return Enum.ContextActionResult.Sink
		end
	end
	
	local function onDrag(input)
		if STATES.ShootMurderer.Locked then return end
		if not dragStartPos then return end
		
		if input.UserInputType == Enum.UserInputType.Touch then
			if not dragTouchId or dragTouchId ~= input then
				return
			end
		end
		
		local currentPos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = currentPos - dragStartPos
		
		if not isDragging and delta.Magnitude > DRAG_THRESHOLD then
			isDragging = true
			wasClick = false
		end
		
		if isDragging then
			local newPosition = UDim2.new(
				buttonStartPos.X.Scale,
				buttonStartPos.X.Offset + delta.X,
				buttonStartPos.Y.Scale,
				buttonStartPos.Y.Offset + delta.Y
			)
			
			shootButton_2.Position = newPosition
		end
	end
	
	local function onDragEnd(input)
		if wasClick and not isDragging then
            task.defer(UTILS.playClickSound)
            task.spawn(function()
                local ok, err = xpcall(shootMurdererFunction, debug.traceback)
                if not ok then warn("[ZXNexus Shoot Murderer] " .. tostring(err)) end
            end)
		end
		
		shootButton_2.BackgroundColor3 = Color3.fromRGB(25, 40, 65)
		shootButton_2.BackgroundTransparency = 0.3
		TextLabel_5.TextColor3 = Color3.fromRGB(225, 240, 255)
		
		if isDragging then
			local finalPosition = shootButton_2.Position
			STATES.ShootMurderer.Position = finalPosition
		end
		
		isDragging = false
		wasClick = false
		dragStartPos = nil
		dragTouchId = nil
		buttonStartPos = nil
	end
	
	local dragButton = UTILS.createInstance("TextButton", shootButton_2, {
		Name = "DragButton",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 10
	})
	
	dragButton.InputBegan:Connect(onDragStart)
	dragButton.InputChanged:Connect(onDrag)
	dragButton.InputEnded:Connect(onDragEnd)
	
	dragButton.MouseEnter:Connect(function()
		if not isDragging then
			shootButton_2.BackgroundTransparency = 0.2
			shootButton_2.BackgroundColor3 = Color3.fromRGB(30, 48, 75)
			TextLabel_5.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end)
	
	dragButton.MouseLeave:Connect(function()
		if not isDragging then
			shootButton_2.BackgroundTransparency = 0.3
			shootButton_2.BackgroundColor3 = Color3.fromRGB(25, 40, 65)
			TextLabel_5.TextColor3 = Color3.fromRGB(225, 240, 255)
		end
	end)
	
	local shootResult = {
		gui = ScreenGui_1,
		frame = shootButton_2,
        shoot = shootMurdererFunction,
		destroy = function()
			if ScreenGui_1 then ScreenGui_1:Destroy() end
		end
	}
	STATES.ShootMurderer.ShootFunction = shootMurdererFunction
	return shootResult
end

function UI_SYSTEM.createEspContainer(parent)
	local espContainer = UTILS.createWithStaticStroke("Frame", parent, {
		Name = "EspContainer",
		BackgroundColor3 = Color3.fromRGB(25, 40, 65),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 300),
		Position = UDim2.new(0, 10, 0, 20),
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", espContainer, {CornerRadius = UDim.new(0, 8)})
	
	UTILS.createInstance("TextLabel", espContainer, {
		Name = "EspTitle",
		Text = "ESP",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextSize = 16,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6
	})
	
	local currentY = 40
	local toggleSpacing = 52
	
	local espNameToggle = createToggle(espContainer, "ESP Name", currentY, ESP_SYSTEM.ESP_STATES, "ESPName", function(isEnabled)
		if not isEnabled then
			ESP_SYSTEM.clearAllESP()
		else
			ESP_SYSTEM.updateESP()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local murdererToggle = createToggle(espContainer, "Murderer Name", currentY, ESP_SYSTEM.ESP_STATES, "MurdererName", function(isEnabled)
		if ESP_SYSTEM.ESP_STATES.ESPName then
			ESP_SYSTEM.updateESP()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local sheriffToggle = createToggle(espContainer, "Sheriff Name", currentY, ESP_SYSTEM.ESP_STATES, "SheriffName", function(isEnabled)
		if ESP_SYSTEM.ESP_STATES.ESPName then
			ESP_SYSTEM.updateESP()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local heroToggle = createToggle(espContainer, "Hero Name", currentY, ESP_SYSTEM.ESP_STATES, "HeroName", function(isEnabled)
		if ESP_SYSTEM.ESP_STATES.ESPName then
			ESP_SYSTEM.updateESP()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local innocentToggle = createToggle(espContainer, "Innocent Name", currentY, ESP_SYSTEM.ESP_STATES, "InnocentName", function(isEnabled)
		if ESP_SYSTEM.ESP_STATES.ESPName then
			ESP_SYSTEM.updateESP()
		end
	end)
	
	return espContainer
end

function UI_SYSTEM.createEspHighlightContainer(parent)
	local espHighlightContainer = UTILS.createWithStaticStroke("Frame", parent, {
		Name = "EspHighlightContainer",
		BackgroundColor3 = Color3.fromRGB(25, 40, 65),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 300),
		Position = UDim2.new(0, 10, 0, 330),
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", espHighlightContainer, {CornerRadius = UDim.new(0, 8)})
	
	UTILS.createInstance("TextLabel", espHighlightContainer, {
		Name = "EspHighlightTitle",
		Text = "ESP Highlight",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextSize = 16,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6
	})
	
	local currentY = 40
	local toggleSpacing = 52
	
	local espHighlightToggle = createToggle(espHighlightContainer, "ESP Highlight", currentY, ESP_SYSTEM.ESP_HIGHLIGHT_STATES, "ESPHighlight", function(isEnabled)
		if not isEnabled then
			ESP_SYSTEM.clearAllHighlights()
		else
			ESP_SYSTEM.updateHighlights()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espHighlightMurderer = createToggle(espHighlightContainer, "ESP Highlight Murderer", currentY, ESP_SYSTEM.ESP_HIGHLIGHT_STATES, "ESPHighlightMurderer", function(isEnabled)
		if ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
			ESP_SYSTEM.updateHighlights()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espHighlightSheriff = createToggle(espHighlightContainer, "ESP Highlight Sheriff", currentY, ESP_SYSTEM.ESP_HIGHLIGHT_STATES, "ESPHighlightSheriff", function(isEnabled)
		if ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
			ESP_SYSTEM.updateHighlights()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espHighlightHero = createToggle(espHighlightContainer, "ESP Highlight Hero", currentY, ESP_SYSTEM.ESP_HIGHLIGHT_STATES, "ESPHighlightHero", function(isEnabled)
		if ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
			ESP_SYSTEM.updateHighlights()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espHighlightInnocent = createToggle(espHighlightContainer, "ESP Highlight Innocent", currentY, ESP_SYSTEM.ESP_HIGHLIGHT_STATES, "ESPHighlightInnocent", function(isEnabled)
		if ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
			ESP_SYSTEM.updateHighlights()
		end
	end)
	
	return espHighlightContainer
end

function UI_SYSTEM.createEspLineContainer(parent)
	local espLineContainer = UTILS.createWithStaticStroke("Frame", parent, {
		Name = "EspLineContainer",
		BackgroundColor3 = Color3.fromRGB(25, 40, 65),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 300),
		Position = UDim2.new(0, 10, 0, 640),
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", espLineContainer, {CornerRadius = UDim.new(0, 8)})
	
	UTILS.createInstance("TextLabel", espLineContainer, {
		Name = "EspLineTitle",
		Text = "Tracers",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextSize = 16,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6
	})
	
	local currentY = 40
	local toggleSpacing = 52
	
	local espLineToggle = createToggle(espLineContainer, "ESP Tracer", currentY, ESP_SYSTEM.ESP_LINE_STATES, "ESPLine", function(isEnabled)
		if isEnabled then
			ESP_SYSTEM.StartAllLines()
		else
			ESP_SYSTEM.StopAllLines()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espLineMurderer = createToggle(espLineContainer, "Murderer Tracer", currentY, ESP_SYSTEM.ESP_LINE_STATES, "MurdererLine", function(isEnabled)
		if ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
			ESP_SYSTEM.StartAllLines()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espLineSheriff = createToggle(espLineContainer, "Sheriff Tracer", currentY, ESP_SYSTEM.ESP_LINE_STATES, "SheriffLine", function(isEnabled)
		if ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
			ESP_SYSTEM.StartAllLines()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espLineHero = createToggle(espLineContainer, "Hero Tracer", currentY, ESP_SYSTEM.ESP_LINE_STATES, "HeroLine", function(isEnabled)
		if ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
			ESP_SYSTEM.StartAllLines()
		end
	end)
	currentY = currentY + toggleSpacing
	
	local espLineInnocent = createToggle(espLineContainer, "Innocent Tracer", currentY, ESP_SYSTEM.ESP_LINE_STATES, "InnocentLine", function(isEnabled)
		if ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
			ESP_SYSTEM.StartAllLines()
		end
	end)
	
	return espLineContainer
end

function UI_SYSTEM.createMainTabContent(content)
	UI_SYSTEM.createPlayerInfoContainer(content)
	UI_SYSTEM.createSpeedJumpContainer(content)
    
    local performanceY = 116 + 180 + 20
    local performanceToggle = createToggle(content, "Performance (Ping & Fps)", performanceY, STATES.Performance, "Enabled", function(isEnabled)
		if isEnabled then
			createPerformanceOverlay()
		else
			if STATES.Performance.Overlay then
				STATES.Performance.Overlay.destroy()
			end
		end
	end)
end

function UI_SYSTEM.createVisualTabContent(content)
	local espContainer = UI_SYSTEM.createEspContainer(content)
	local espHighlightContainer = UI_SYSTEM.createEspHighlightContainer(content)
	local espLineContainer = UI_SYSTEM.createEspLineContainer(content)
	return espContainer, espHighlightContainer, espLineContainer
end

function UI_SYSTEM.createCombatTabContent(content)
	local shootToggle = createToggle(content, "Shoot The Murderer", 32, STATES, "ShootMurdererTemp", function(isEnabled)
		if isEnabled then
			if not STATES.ShootMurderer.ButtonData then
				STATES.ShootMurderer.ButtonData = UI_SYSTEM.createShootMurdererButton()
			end
		else
			if STATES.ShootMurderer.ButtonData then
				STATES.ShootMurderer.ButtonData.destroy()
				STATES.ShootMurderer.ButtonData = nil
			end
		end
	end)

	local shootLockToggle = createToggle(content, "Lock Shoot Button", 84, STATES, "ShootMurdererLocked", function(isLocked)
		STATES.ShootMurdererLocked = isLocked
        STATES.ShootMurderer.Locked = isLocked
	end)
end

STATES.ShootMurdererTemp = false
STATES.ShootMurderer = STATES.ShootMurderer or {}
STATES.ShootMurderer.Locked = false
STATES.ShootMurdererLocked = false

function UI_SYSTEM.createTeleportTabContent(content)
    local currentY = 20
    
    local bombContainer = UTILS.createWithStaticStroke("Frame", content, {
        Name = "FakeBombJumpContainer",
        BackgroundColor3 = CONFIG.MAIN_COLOR,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 0, 152),
        Position = UDim2.new(0, 10, 0, currentY),
        ZIndex = 5
    })
    
    UTILS.createInstance("UICorner", bombContainer, {CornerRadius = UDim.new(0, 8)})
    
    UTILS.createInstance("TextLabel", bombContainer, {
        Name = "BombContainerTitle",
        Text = "Fake Bomb Jump",
        TextColor3 = Color3.fromRGB(225, 240, 255),
        TextSize = 16,
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 0, 5),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 6
    })
    
    local bombButtonData = nil
    
    local function createBombButton()
        if bombButtonData then return end
        
        local bombGui = UTILS.createInstance("ScreenGui", CoreGui, {
            Name = "FakeBombJumpGui",
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            ResetOnSpawn = false,
            DisplayOrder = 50
        })
        
        local bombFrame = UTILS.createWithStaticStroke("Frame", bombGui, {
            Name = "BombJumpFrame",
            BackgroundColor3 = CONFIG.MAIN_COLOR,
            BackgroundTransparency = 0.12,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(FLOATING_STYLES.FakeBombJump.Size, FLOATING_STYLES.FakeBombJump.Size),
            Position = STATES.FakeBombJump.Position or UDim2.new(0.5, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0.5, 0.5),
            ZIndex = 1
        })
        
        UTILS.createInstance("UICorner", bombFrame, {CornerRadius = floatingCorner(FLOATING_STYLES.FakeBombJump.Shape, FLOATING_STYLES.FakeBombJump.Size)})
        applyFloatingShape(bombFrame, FLOATING_STYLES.FakeBombJump.Shape, math.max(FLOATING_STYLES.FakeBombJump.Size, FLOATING_STYLES.FakeBombJump.Height))
        
        local backgroundGradient = UTILS.createInstance("UIGradient", bombFrame, {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 55, 85)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 35, 58))
            }),
            Rotation = 90
        })
        
        local textLabel = UTILS.createInstance("TextLabel", bombFrame, {
            Name = "BombText",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = FLOATING_STYLES.FakeBombJump.Text or "☠",
            TextColor3 = Color3.fromRGB(225, 240, 255),
            TextSize = 30,
            FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
            TextWrapped = true,
            ZIndex = 2
        })
        
        local button = UTILS.createInstance("TextButton", bombFrame, {
            Name = "BombButton",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3
        })
        
        local bombAvailable = true
        local bombCooldown = 22
        local cooldownActive = false
        local isDragging = false
        local dragStartPos
        local buttonStartPos
        local dragTouchId
        local wasClick = false
        local DRAG_THRESHOLD = 5
        
        local COLORS = {
            READY = Color3.fromRGB(225, 240, 255),
            READY_HOVER = Color3.fromRGB(255, 255, 255),
            COOLDOWN = Color3.fromRGB(255, 150, 150)
        }
        
        local function updateUI(status, message)
            if status == "ready" then
                textLabel.Text = "💣"
                cooldownActive = false
                textLabel.TextColor3 = COLORS.READY
            elseif status == "cooldown" then
                textLabel.Text = tostring(message) .. "s"
                cooldownActive = true
                textLabel.TextColor3 = COLORS.COOLDOWN
            end
        end
        
        local function useBomb()
            if bombAvailable and not cooldownActive then
                bombAvailable = false
                cooldownActive = true
                
                local player = Players.LocalPlayer
                local character = player.Character
                
                if not character then
                    bombAvailable = true
                    cooldownActive = false
                    updateUI("ready")
                    return
                end
                
                local backpack = player.Backpack
                
                local bomb = backpack:FindFirstChild("FakeBomb") or character:FindFirstChild("FakeBomb")
                if not bomb then
                    local remote = ReplicatedStorage:FindFirstChild("Remotes")
                    if remote then
                        local extras = remote:FindFirstChild("Extras")
                        if extras then
                            local replicateToy = extras:FindFirstChild("ReplicateToy")
                            if replicateToy then
                                pcall(function()
                                    replicateToy:InvokeServer("FakeBomb")
                                end)
                            end
                        end
                    end
                    
                    bomb = backpack:WaitForChild("FakeBomb", 5)
                    if not bomb then
                        bombAvailable = true
                        cooldownActive = false
                        updateUI("ready")
                        return
                    end
                end
                
                bomb.Parent = character
                
                if bomb:IsDescendantOf(character) and character:FindFirstChild("Humanoid") then
                    local humanoid = character.Humanoid
                    local hrp = character:FindFirstChild("HumanoidRootPart")
                    
                    if hrp then
                        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                        humanoid.JumpPower = 53
                        
                        if bomb:FindFirstChild("Remote") then
                            bomb.Remote:FireServer(hrp.CFrame * CFrame.new(0, -3, 0), 50)
                        end
                        
                        task.wait(0.3)
                        
                        if bomb and bomb.Parent == character then
                            bomb.Parent = backpack
                        end
                        
                        if humanoid then
                            humanoid.JumpPower = 51
                        end
                    end
                end
                
                local startTime = time()
                local characterCheck = character
                
                while time() - startTime < bombCooldown do
                    if Players.LocalPlayer.Character ~= characterCheck then
                        bombAvailable = true
                        cooldownActive = false
                        updateUI("ready")
                        return
                    end
                    
                    local remaining = math.ceil(bombCooldown - (time() - startTime))
                    updateUI("cooldown", remaining)
                    task.wait(1)
                end
                
                bombAvailable = true
                cooldownActive = false
                updateUI("ready")
            end
        end
        
        local function onDragStart(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or 
               input.UserInputType == Enum.UserInputType.Touch then
                
                -- Locked buttons can be clicked but cannot be moved.
                if STATES.FakeBombJump.Locked then
                    isDragging = false
                    wasClick = true
                    dragTouchId = nil
                    dragStartPos = nil
                    buttonStartPos = nil
                    return Enum.ContextActionResult.Sink
                end

                isDragging = false
                wasClick = true
                dragTouchId = input.UserInputType == Enum.UserInputType.Touch and input
                dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
                buttonStartPos = bombFrame.Position
                
                bombFrame.BackgroundColor3 = CONFIG.MAIN_COLOR:Lerp(Color3.new(1,1,1), 0.18)
                bombFrame.BackgroundTransparency = 0.2
                
                return Enum.ContextActionResult.Sink
            end
        end
        
        local function onDrag(input)
            if STATES.FakeBombJump.Locked then return end
            if not dragStartPos then return end
            
            if input.UserInputType == Enum.UserInputType.Touch then
                if not dragTouchId or dragTouchId ~= input then
                    return
                end
            end
            
            local currentPos = Vector2.new(input.Position.X, input.Position.Y)
            local delta = currentPos - dragStartPos
            
            if not isDragging and delta.Magnitude > DRAG_THRESHOLD then
                isDragging = true
                wasClick = false
            end
            
            if isDragging then
                local newPosition = UDim2.new(
                    buttonStartPos.X.Scale,
                    buttonStartPos.X.Offset + delta.X,
                    buttonStartPos.Y.Scale,
                    buttonStartPos.Y.Offset + delta.Y
                )
                
                bombFrame.Position = newPosition
            end
        end
        
        local function onDragEnd(input)
            if wasClick and not isDragging then
                UTILS.playClickSound()
                if not cooldownActive then
                    useBomb()
                end
            end
            
            bombFrame.BackgroundColor3 = CONFIG.MAIN_COLOR
            bombFrame.BackgroundTransparency = 0.3
            local targetColor = cooldownActive and COLORS.COOLDOWN or COLORS.READY
            textLabel.TextColor3 = targetColor
            
            if isDragging then
                local finalPosition = bombFrame.Position
                STATES.FakeBombJump.Position = finalPosition
            end
            
            isDragging = false
            wasClick = false
            dragStartPos = nil
            dragTouchId = nil
            buttonStartPos = nil
        end
        
        button.InputBegan:Connect(onDragStart)
        button.InputChanged:Connect(onDrag)
        button.InputEnded:Connect(onDragEnd)
        
        button.MouseEnter:Connect(function()
            if not isDragging then
                bombFrame.BackgroundTransparency = 0.2
                bombFrame.BackgroundColor3 = CONFIG.MAIN_COLOR:Lerp(Color3.new(1,1,1), 0.12)
                
                if not cooldownActive then
                    textLabel.TextColor3 = COLORS.READY_HOVER
                end
            end
        end)
        
        button.MouseLeave:Connect(function()
            if not isDragging then
                bombFrame.BackgroundTransparency = 0.3
                bombFrame.BackgroundColor3 = CONFIG.MAIN_COLOR
                
                local targetColor = cooldownActive and COLORS.COOLDOWN or COLORS.READY
                textLabel.TextColor3 = targetColor
            end
        end)
        
        updateUI("ready")
        
        bombButtonData = {
            gui = bombGui,
            frame = bombFrame,
            destroy = function()
                if bombGui then bombGui:Destroy() end
                bombButtonData = nil
                STATES.FakeBombJump.ButtonData = nil
            end
        }
        STATES.FakeBombJump.ButtonData = bombButtonData
    end
    
    local function destroyBombButton()
        if bombButtonData then
            bombButtonData.destroy()
        end
    end
    
    STATES.FakeBombJumpTemp = false
STATES.FakeBombJump = STATES.FakeBombJump or {}
STATES.FakeBombJump.Locked = false
STATES.FakeBombJumpLocked = false
    local bombToggle = createToggle(bombContainer, "Fake Bomb Jump Button", 40, STATES, "FakeBombJumpTemp", function(isEnabled)
        if isEnabled then
            createBombButton()
        else
            destroyBombButton()
        end
    end)

    local bombLockToggle = createToggle(bombContainer, "Lock Fake Bomb Button", 92, STATES, "FakeBombJumpLocked", function(isLocked)
        STATES.FakeBombJumpLocked = isLocked
        STATES.FakeBombJump.Locked = isLocked
    end)
    
    currentY = currentY + 152 + 20
    
    local grabberContainer = UTILS.createWithStaticStroke("Frame", content, {
        Name = "GrabberContainer",
        BackgroundColor3 = CONFIG.MAIN_COLOR,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 0, 257),
        Position = UDim2.new(0, 10, 0, currentY),
        ZIndex = 5
    })
    
    UTILS.createInstance("UICorner", grabberContainer, {CornerRadius = UDim.new(0, 8)})
    
    UTILS.createInstance("TextLabel", grabberContainer, {
        Name = "GrabberTitle",
        Text = "Grabber",
        TextColor3 = Color3.fromRGB(225, 240, 255),
        TextSize = 16,
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 0, 5),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 6
    })
    
    local function findGunDropFast()
        local gun = workspace:FindFirstChild("GunDrop", true)
        if gun and gun:IsA("BasePart") then return gun end
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name == "GunDrop" then return obj end
        end
        return nil
    end

    local function touchGunDrop(gun)
        local hrp = UTILS.getHRP()
        if not hrp or not gun or not gun:IsA("BasePart") then return false end
        pcall(function()
            firetouchinterest(hrp, gun, 0)
            firetouchinterest(hrp, gun, 1)
        end)
        return true
    end

    local function GrabGunRemote()
        local gun = findGunDropFast()
        if not gun then return false end
        touchGunDrop(gun)
        -- A few very short retries handle the case where the drop exists but
        -- the touch/ownership update has not replicated on the same frame.
        for _ = 1, 4 do
            if player.Backpack:FindFirstChild("Gun") or (player.Character and player.Character:FindFirstChild("Gun")) then
                return true
            end
            task.wait(0.025)
            gun = findGunDropFast()
            if not gun then return false end
            touchGunDrop(gun)
        end
        return player.Backpack:FindFirstChild("Gun") ~= nil or (player.Character and player.Character:FindFirstChild("Gun")) ~= nil
    end
    
    local grabGunButton = createStyledButton(grabberContainer, {
        name = "GrabGunStyledButton",
        title = "Grab Gun",
        icon = "rbxthumb://type=Asset&id=77289067728929&w=150&h=150",
        accentColor = CONFIG.MAIN_COLOR,
        position = UDim2.new(0, 10, 0, 40),
        onClick = function()
            GrabGunRemote()
        end
    })
    
    local toggleY = 100
    
    local grabGunButtonData = nil
    
    local function createGunDropButton()
        if grabGunButtonData then return end
        
        local gunGui = UTILS.createInstance("ScreenGui", CoreGui, {
            Name = "GunDropButtonGui",
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            ResetOnSpawn = false,
            DisplayOrder = 50
        })
        
        local gunFrame = UTILS.createWithStaticStroke("Frame", gunGui, {
            Name = "GunDropFrame",
            BackgroundColor3 = CONFIG.MAIN_COLOR,
            BackgroundTransparency = 0.12,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(FLOATING_STYLES.GrabGun.Size, FLOATING_STYLES.GrabGun.Size),
            Position = STATES.GrabGun.Position or UDim2.new(1, -14, 0, 128),
            AnchorPoint = Vector2.new(1, 0),
            ZIndex = 1
        })
        
        UTILS.createInstance("UICorner", gunFrame, {CornerRadius = floatingCorner(FLOATING_STYLES.GrabGun.Shape, FLOATING_STYLES.GrabGun.Size)})
        applyFloatingShape(gunFrame, FLOATING_STYLES.GrabGun.Shape, math.max(FLOATING_STYLES.GrabGun.Size, FLOATING_STYLES.GrabGun.Height))
        
        local backgroundGradient = UTILS.createInstance("UIGradient", gunFrame, {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 55, 85)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 35, 58))
            }),
            Rotation = 90
        })
        
        local textLabel = UTILS.createInstance("TextLabel", gunFrame, {
            Name = "GunText",
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            Text = FLOATING_STYLES.GrabGun.Text or "🔫",
            TextColor3 = Color3.fromRGB(225, 240, 255),
            TextSize = 10,
            FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
            TextScaled = false,
            TextWrapped = true,
            ZIndex = 2
        })
        
        local button = UTILS.createInstance("TextButton", gunFrame, {
            Name = "GunButton",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3
        })
        
        local isDragging = false
        local dragStartPos
        local buttonStartPos
        local dragTouchId
        local wasClick = false
        local DRAG_THRESHOLD = 5
        
        local function onDragStart(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or 
               input.UserInputType == Enum.UserInputType.Touch then
                
                -- Locked buttons can be clicked but cannot be moved.
                if STATES.GrabGun.Locked then
                    isDragging = false
                    wasClick = true
                    dragTouchId = nil
                    dragStartPos = nil
                    buttonStartPos = nil
                    return Enum.ContextActionResult.Sink
                end

                isDragging = false
                wasClick = true
                dragTouchId = input.UserInputType == Enum.UserInputType.Touch and input
                dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
                buttonStartPos = gunFrame.Position
                
                gunFrame.BackgroundColor3 = CONFIG.MAIN_COLOR:Lerp(Color3.new(1,1,1), 0.18)
                
                return Enum.ContextActionResult.Sink
            end
        end
        
        local function onDrag(input)
            if STATES.GrabGun.Locked then return end
            if not dragStartPos then return end
            
            if input.UserInputType == Enum.UserInputType.Touch then
                if not dragTouchId or dragTouchId ~= input then
                    return
                end
            end
            
            local currentPos = Vector2.new(input.Position.X, input.Position.Y)
            local delta = currentPos - dragStartPos
            
            if not isDragging and delta.Magnitude > DRAG_THRESHOLD then
                isDragging = true
                wasClick = false
            end
            
            if isDragging then
                local newPosition = UDim2.new(
                    buttonStartPos.X.Scale,
                    buttonStartPos.X.Offset + delta.X,
                    buttonStartPos.Y.Scale,
                    buttonStartPos.Y.Offset + delta.Y
                )
                
                gunFrame.Position = newPosition
            end
        end
        
        local function onDragEnd(input)
            if wasClick and not isDragging then
                UTILS.playClickSound()
                GrabGunRemote()
            end
            
            gunFrame.BackgroundTransparency = 0.3
            gunFrame.BackgroundColor3 = CONFIG.MAIN_COLOR
            textLabel.TextColor3 = Color3.fromRGB(225, 240, 255)
            
            if isDragging then
                local finalPosition = gunFrame.Position
                STATES.GrabGun.Position = finalPosition
            end
            
            isDragging = false
            wasClick = false
            dragStartPos = nil
            dragTouchId = nil
            buttonStartPos = nil
        end
        
        button.InputBegan:Connect(onDragStart)
        button.InputChanged:Connect(onDrag)
        button.InputEnded:Connect(onDragEnd)
        
        button.MouseEnter:Connect(function()
            if not isDragging then
                gunFrame.BackgroundTransparency = 0.2
                gunFrame.BackgroundColor3 = CONFIG.MAIN_COLOR:Lerp(Color3.new(1,1,1), 0.12)
                textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            end
        end)
        
        button.MouseLeave:Connect(function()
            if not isDragging then
                gunFrame.BackgroundTransparency = 0.3
                gunFrame.BackgroundColor3 = CONFIG.MAIN_COLOR
                textLabel.TextColor3 = Color3.fromRGB(225, 240, 255)
            end
        end)
        
        grabGunButtonData = {
            gui = gunGui,
            frame = gunFrame,
            destroy = function()
                if gunGui then gunGui:Destroy() end
                grabGunButtonData = nil
                STATES.GrabGun.ButtonData = nil
            end
        }
        STATES.GrabGun.ButtonData = grabGunButtonData
    end
    
    local function destroyGunDropButton()
        if grabGunButtonData then
            grabGunButtonData.destroy()
        end
    end
    
    STATES.GrabGunTemp = false
STATES.GrabGun = STATES.GrabGun or {}
STATES.GrabGun.Locked = false
STATES.GrabGunLocked = false
    local grabGunToggle = createToggle(grabberContainer, "GrabGun Button", toggleY, STATES, "GrabGunTemp", function(isEnabled)
        if isEnabled then
            createGunDropButton()
        else
            destroyGunDropButton()
        end
    end)

    local grabGunLockToggle = createToggle(grabberContainer, "Lock Grab Gun Button", toggleY + 52, STATES, "GrabGunLocked", function(isLocked)
        STATES.GrabGunLocked = isLocked
        STATES.GrabGun.Locked = isLocked
    end)
    
    toggleY = toggleY + 104
    
    local autoGrabGunActive = false
    local autoGrabGunConnection = nil
    
    STATES.AutoGrabGunTemp = false
    local autoGrabGunToggle = createToggle(grabberContainer, "AutoGrabGun", toggleY, STATES, "AutoGrabGunTemp", function(isEnabled)
        autoGrabGunActive = isEnabled
        
        if isEnabled then
            if autoGrabGunConnection then
                autoGrabGunConnection:Disconnect()
            end
            
            autoGrabGunConnection = RunService.Heartbeat:Connect(function()
                if autoGrabGunActive then
                    GrabGunRemote()
                    task.wait(0.03)
                end
            end)
        else
            if autoGrabGunConnection then
                autoGrabGunConnection:Disconnect()
                autoGrabGunConnection = nil
            end
        end
    end)
    
    return bombContainer, grabberContainer
end

function UI_SYSTEM.createAutoFarmTabContent(content)
	local currentY = 20
	
	local farmContainer = UTILS.createWithStaticStroke("Frame", content, {
		Name = "FarmContainer",
		BackgroundColor3 = CONFIG.MAIN_COLOR,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -20, 0, 160),
		Position = UDim2.new(0, 10, 0, currentY),
		ZIndex = 5
	})
	
	UTILS.createInstance("UICorner", farmContainer, {CornerRadius = UDim.new(0, 8)})
	
	local farmY = 10
	local autoFarmToggle = createToggle(farmContainer, "Auto Farm", farmY, STATES.AutoFarm, "Enabled", function(isEnabled)
		STATES.AutoFarm.Enabled = isEnabled
        if isEnabled then
            STATES.AutoFarm.Farming = FARMING.isRoundActive()
        else
			STATES.AutoFarm.Farming = false
		end
	end)
	
	farmY = farmY + 52
	local autoResetToggle = createToggle(farmContainer, "Auto Reset (Full Bag)", farmY, STATES.AutoFarm, "Resetting", function(isEnabled)
        -- Legacy compatibility only: this toggle no longer resets the character.
        STATES.AutoFarm.Resetting = false
        STATES.AutoFarm.Farming = STATES.AutoFarm.Enabled and not STATES.AutoFarm.BagFull
    end)
	
	farmY = farmY + 52
	local autoKillToggle = createToggle(farmContainer, "Auto Kill All (Murderer)", farmY, STATES.KillAll, "Enabled", function(isEnabled)
		STATES.KillAll.Enabled = isEnabled
		if not isEnabled then 
			STATES.AutoFarm.BagFull = false 
		end
	end)
	
	currentY = currentY + 160 + 20
	
	local statsFrame = UTILS.createWithStaticStroke("Frame", content, {
		Name = "StatsContainer",
		Size = UDim2.new(1, -20, 0, 100),
		Position = UDim2.new(0, 10, 0, currentY),
		BackgroundColor3 = Color3.fromRGB(22, 35, 55),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 5
	})
	UTILS.createInstance("UICorner", statsFrame, {CornerRadius = UDim.new(0, 8)})
	
	UTILS.createInstance("TextLabel", statsFrame, {
		Name = "StatsTitle",
		Text = "Farming Statistics",
		TextColor3 = Color3.fromRGB(225, 240, 255),
		TextSize = 14,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6
	})
	
	local coinLabel = UTILS.createInstance("TextLabel", statsFrame, {
		Name = "CoinLabel",
		Text = "Coin: 0",
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 25),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
		TextSize = 13,
		ZIndex = 6
	})

	local hourLabel = UTILS.createInstance("TextLabel", statsFrame, {
		Name = "HourLabel",
		Text = "Coins/hour: 0",
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 45),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(200, 255, 200),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
		TextSize = 13,
		ZIndex = 6
	})

	local timeLabel = UTILS.createInstance("TextLabel", statsFrame, {
		Name = "TimeLabel",
		Text = "0h 0m 0s",
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 65),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
		TextSize = 13,
		ZIndex = 6
	})
	
	RunService.Heartbeat:Connect(function()
		if STATES.AutoFarm.Enabled then
			if not FARMING_STATS.IsRunning then
				FARMING_STATS.StartTime = tick()
				FARMING_STATS.IsRunning = true
				FARMING_STATS.CoinsCollected = 0
			end
			
			local elapsed = tick() - FARMING_STATS.StartTime
			local hours = math.floor(elapsed / 3600)
			local minutes = math.floor((elapsed % 3600) / 60)
			local seconds = math.floor(elapsed % 60)
			
			timeLabel.Text = string.format("%dh %dm %ds", hours, minutes, seconds)
			coinLabel.Text = "Coin: " .. FARMING_STATS.CoinsCollected
			
			if elapsed > 0 then
				local cph = math.floor((FARMING_STATS.CoinsCollected / elapsed) * 3600)
				hourLabel.Text = "Coins/hour: " .. cph
			end
		else
			FARMING_STATS.IsRunning = false
		end
	end)
	
	return farmContainer, statsFrame
end

function UI_SYSTEM.createActMgrTabContent(content)
    local currentY = 20
    
    local joinButton = createStyledButton(content, {
        name = "JoinAnotherServer",
        title = "Join Another Server",
        icon = "rbxthumb://type=Asset&id=77289067728929&w=150&h=150",
        accentColor = CONFIG.MAIN_COLOR,
        position = UDim2.new(0, 10, 0, currentY),
        onClick = function()
            UTILS.joinAnotherServer()
        end
    })
    
    currentY = currentY + 60
    
    local rejoinButton = createStyledButton(content, {
        name = "RejoinServer",
        title = "Rejoin",
        icon = "rbxthumb://type=Asset&id=77289067728929&w=150&h=150",
        accentColor = CONFIG.MAIN_COLOR,
        position = UDim2.new(0, 10, 0, currentY),
        onClick = function()
            UTILS.rejoinServer()
        end
    })
    
    currentY = currentY + 60
    
    local antiAFKInterval = 5
    
    local antiAFKEnabled = false
    local antiAFKTask = nil
    
    local function getVirtualUser()
        local VirtualUser = cloneref and cloneref(game:GetService("VirtualUser")) or game:GetService("VirtualUser")
        return VirtualUser
    end
    
    local function simulateActivity()
        local VirtualUser = getVirtualUser()
        local camera = workspace.CurrentCamera
        
        if VirtualUser and camera then
            pcall(function()
                VirtualUser:Button2Down(Vector2.new(0, 0), camera.CFrame)
                task.wait(0.1)
                VirtualUser:Button2Up(Vector2.new(0, 0), camera.CFrame)
            end)
        end
    end
    
    local function toggleAntiAFK(value)
        antiAFKEnabled = value
        
        if value then
            if antiAFKTask then
                task.cancel(antiAFKTask)
                antiAFKTask = nil
            end
            
            antiAFKTask = task.spawn(function()
                while antiAFKEnabled do
                    task.wait(antiAFKInterval * 60)
                    simulateActivity()
                end
            end)
        else
            if antiAFKTask then
                task.cancel(antiAFKTask)
                antiAFKTask = nil
            end
        end
    end
    
    STATES.AntiAFKTemp = false
    local antiAFKToggle = createToggle(content, "Anti-AFK (every " .. antiAFKInterval .. " min)", currentY, STATES, "AntiAFKTemp", function(isEnabled)
        toggleAntiAFK(isEnabled)
    end)
    
    currentY = currentY + 60
    
    local antiFlingToggle = createToggle(content, "Anti-Fling", currentY, STATES.AntiFling, "Enabled", function(isEnabled)
        if isEnabled then
            ANTI_FLING.enable()
        else
            ANTI_FLING.disable()
        end
    end)
    
    currentY = currentY + 60
    
    local muteRadioToggle = createToggle(content, "Mute Radio", currentY, STATES.MuteRadio, "Enabled", function(isEnabled)
        toggleMuteRadio(isEnabled)
    end)
    
    return joinButton.container, rejoinButton.container, antiAFKToggle, antiFlingToggle, muteRadioToggle
end

-- =========================
-- ZXNexus / EXTRA VISUAL + COMBAT SYSTEMS
-- =========================

local function destroyDropESP(obj)
    local data = DROP_ESP.Objects[obj]
    if data then
        if data.billboard then pcall(function() data.billboard:Destroy() end) end
        if data.highlight then pcall(function() data.highlight:Destroy() end) end
    end
    DROP_ESP.Objects[obj] = nil
end

local function getDropAdornee(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function addDropESP(obj, label, color)
    if not obj or DROP_ESP.Objects[obj] or not obj:IsDescendantOf(workspace) then return end
    local adornee = getDropAdornee(obj)
    if not adornee then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "ZXNexusDropHighlight"
    highlight.Adornee = obj:IsA("Model") and obj or adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.OutlineColor = Color3.new(1, 1, 1)
    highlight.FillTransparency = 0.72
    highlight.OutlineTransparency = 0.05
    highlight.Parent = CoreGui

    local gui = Instance.new("BillboardGui")
    gui.Name = "ZXNexusDropESP"
    gui.Adornee = adornee
    gui.Size = UDim2.fromOffset(150, 34)
    gui.StudsOffset = Vector3.new(0, 2.5, 0)
    gui.AlwaysOnTop = true
    gui.MaxDistance = 0
    gui.Parent = CoreGui

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.fromScale(1, 1)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = label
    textLabel.TextColor3 = color
    textLabel.TextStrokeTransparency = 0.15
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextSize = 14
    textLabel.Parent = gui

    DROP_ESP.Objects[obj] = {billboard = gui, highlight = highlight}
end

local ignoredInitialTraps = setmetatable({}, {__mode = "k"})
local initialTrapIgnoredThisRound = false

resetInitialTrapExclusion = function()
    ignoredInitialTraps = setmetatable({}, {__mode = "k"})
    initialTrapIgnoredThisRound = false
end

local function isTrapActiveInMatch(obj)
    if not obj or not obj:IsDescendantOf(workspace) then return false end
    if ROUND_STATE.Known then
        return ROUND_STATE.Active
    end
    -- Fallback for scripts loaded after RoundStart: active MM2 maps are normally
    -- parented under workspace.Map, while the lobby is not.
    local map = workspace:FindFirstChild("Map")
    return map ~= nil and obj:IsDescendantOf(map)
end

local function shouldIgnoreInitialTrap(obj)
    if not obj or obj.Name ~= "Trap" or not isTrapActiveInMatch(obj) then return false end
    if ignoredInitialTraps[obj] then return true end
    if not initialTrapIgnoredThisRound then
        initialTrapIgnoredThisRound = true
        ignoredInitialTraps[obj] = true
        return true
    end
    return false
end

refreshDropESP = function()
    for obj in pairs(DROP_ESP.Objects) do
        if not obj.Parent
            or (obj.Name == "Trap" and (not isTrapActiveInMatch(obj) or shouldIgnoreInitialTrap(obj))) then
            destroyDropESP(obj)
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if DROP_ESP.Gun and obj.Name == "GunDrop" then
            addDropESP(obj, "Dropped Gun", Color3.fromRGB(255, 235, 60))
        elseif DROP_ESP.Trap and obj.Name == "Trap" and isTrapActiveInMatch(obj) and not shouldIgnoreInitialTrap(obj) then
            addDropESP(obj, "Trap", Color3.fromRGB(255, 70, 70))
        end
    end
end

workspace.DescendantAdded:Connect(function(obj)
    if DROP_ESP.Gun and obj.Name == "GunDrop" then addDropESP(obj, "Dropped Gun", Color3.fromRGB(255, 235, 60)) end
    if DROP_ESP.Trap and obj.Name == "Trap" and isTrapActiveInMatch(obj) and not shouldIgnoreInitialTrap(obj) then
        addDropESP(obj, "Trap", Color3.fromRGB(255, 70, 70))
    end
end)

local function setDropESP(kind, enabled)
    DROP_ESP[kind] = enabled
    refreshDropESP()
end


local KNIFE_THROW = {
    Auto = false, Connection = nil, FloatingButton = nil, FloatingEnabled = false,
    Locked = false, WallCheck = true, Position = UDim2.new(1, -14, 0, 172),
}
local AUTO_SHOOT = {Enabled = false, Connection = nil, LastShot = 0, Cooldown = 0.12}
local KEYBINDS = {
    ToggleUI = Enum.KeyCode.RightShift,
    ShootMurderer = Enum.KeyCode.F,
    ThrowKnife = Enum.KeyCode.G,
    Bomb = Enum.KeyCode.B,
    Extra1 = Enum.KeyCode.H,
    Extra2 = Enum.KeyCode.J,
}
local KEYBIND_CAPTURE = {Active = nil, Connection = nil}
local CONFIG_LOADED = false
local AUTO_GET_GUN = {Enabled = false, Connection = nil, AddedConnection = nil}
local ACTION_FLOATERS = {
    Fly = {Enabled = false, Position = UDim2.new(1, -14, 0, 216), Button = nil, Locked = false},
    Noclip = {Enabled = false, Position = UDim2.new(1, -14, 0, 260), Button = nil, Locked = false},
    JumpBoost = {Enabled = false, Position = UDim2.new(1, -14, 0, 304), Button = nil, Locked = false},
    StealGun = {Enabled = false, Position = UDim2.new(1, -14, 0, 348), Button = nil, Locked = false},
}
-- =========================
-- ZXNexus local configuration / keybind persistence
-- =========================
local function configAvailable()
    -- Some mobile executors expose readfile/writefile but omit isfile; do not reject them.
    return type(writefile) == "function" and type(readfile) == "function"
end

local function serializeKeyCode(key)
    return key and key.Name or nil
end

local function deserializeKeyCode(name, fallback)
    if type(name) ~= "string" then return fallback end
    local ok, key = pcall(function() return Enum.KeyCode[name] end)
    return ok and key or fallback
end

-- Configuration is written only when the user explicitly clicks Save Settings.
local function saveConfig(force)
    if force ~= true then return false end
    if not configAvailable() then return false end
    local data = {
        version = CONFIG.CONFIG_VERSION,
        toggles = {},
        positions = {},
        styles = {},
        values = {},
        keybinds = {},
    }

    for title, entry in pairs(LEGACY_TOGGLES) do
        if entry and entry.stateTable and entry.stateKey then
            data.toggles[title] = entry.stateTable[entry.stateKey] == true
        end
    end

    data.toggles["Auto Shoot"] = AUTO_SHOOT.Enabled == true
    data.toggles["Auto Throw Knife"] = KNIFE_THROW.Auto == true
    data.toggles["Throw Knife FloatingButton"] = KNIFE_THROW.FloatingEnabled == true
    data.toggles["Lock Throw Knife FloatingButton"] = KNIFE_THROW.Locked == true
    data.toggles["Shoot Wall Check"] = SHOOT_CONFIG.WallCheck ~= false
    data.toggles["Knife Wall Check"] = KNIFE_THROW.WallCheck ~= false
    data.toggles["Aimlock"] = AIMLOCK.Enabled == true
    data.toggles["Auto Get Gun"] = AUTO_GET_GUN.Enabled == true
    data.toggles["Anti-Fling"] = ZXNexus_ANTI_FLING.Enabled == true
    data.toggles["ESP Gun"] = DROP_ESP.Gun == true
    data.toggles["ESP Trap"] = DROP_ESP.Trap == true
    data.toggles["Hitbox ESP"] = HITBOX_ESP.Enabled == true
    data.toggles["Camlock"] = AIMLOCK.Enabled == true
    data.toggles["Camlock Wall Check"] = AIMLOCK.WallCheck == true
    data.toggles["Camlock Distance"] = AIMLOCK.UseDistance == true
    data.toggles["Noclip"] = STATES.MovementExtras.Noclip == true
    data.toggles["Fly"] = STATES.MovementExtras.Fly == true
    data.toggles["AutoFarm Fling Murderer"] = STATES.AutoFarm.FlingMurderer == true
    data.toggles["AutoFarm Kill All"] = STATES.AutoFarm.KillAll == true
    data.toggles["Candy Farm Mode"] = STATES.AutoFarm.CandyMode == true
    data.toggles["Reset at 50 Candies"] = STATES.AutoFarm.AutoResetAt50 == true
    data.toggles["Jump Boost"] = STATES.MovementExtras.JumpBoost == true
    data.toggles["Jump Boost FloatingButton"] = ACTION_FLOATERS.JumpBoost.Enabled == true
    data.toggles["Lock Jump Boost FloatingButton"] = ACTION_FLOATERS.JumpBoost.Locked == true
    data.toggles["Fly FloatingButton"] = ACTION_FLOATERS.Fly.Enabled == true
    data.toggles["Noclip FloatingButton"] = ACTION_FLOATERS.Noclip.Enabled == true
    data.toggles["Lock Fly FloatingButton"] = ACTION_FLOATERS.Fly.Locked == true
    data.toggles["Lock Noclip FloatingButton"] = ACTION_FLOATERS.Noclip.Locked == true
    data.toggles["Steal Gun FloatingButton"] = ACTION_FLOATERS.StealGun.Enabled == true
    data.toggles["Lock Steal Gun FloatingButton"] = ACTION_FLOATERS.StealGun.Locked == true

    local function savePos(name, pos)
        if typeof(pos) == "UDim2" then
            data.positions[name] = {
                xs = pos.X.Scale, xo = pos.X.Offset,
                ys = pos.Y.Scale, yo = pos.Y.Offset,
            }
        end
    end
    savePos("ShootMurderer", STATES.ShootMurderer.Position)
    savePos("FakeBombJump", STATES.FakeBombJump.Position)
    savePos("GrabGun", STATES.GrabGun.Position)
    savePos("ThrowKnife", KNIFE_THROW.Position)
    savePos("Fly", ACTION_FLOATERS.Fly.Position)
    savePos("Noclip", ACTION_FLOATERS.Noclip.Position)
    savePos("JumpBoost", ACTION_FLOATERS.JumpBoost.Position)
    savePos("StealGun", ACTION_FLOATERS.StealGun.Position)

    for name, style in pairs(FLOATING_STYLES) do
        data.styles[name] = {Size = style.Size, Height = style.Height, Shape = style.Shape, Text = style.Text}
    end

    data.values.WalkSpeed = STATES.Movement.SpeedWalk.Value
    data.values.FlySpeed = STATES.MovementExtras.FlySpeed
    data.values.CamlockBodyPart = AIMLOCK.BodyPart
    data.values.CamlockTargetRole = AIMLOCK.TargetRole
    data.values.CamlockMaxDistance = AIMLOCK.MaxDistance
    data.values.JumpPower = STATES.Movement.JumpPower.Value
    data.values.HitboxSize = HITBOX_ESP.Size
    data.values.ShootConfig = {
        ShootOffset = SHOOT_CONFIG.ShootOffset,
        OffsetToPingMult = SHOOT_CONFIG.OffsetToPingMult,
    }

    for name, key in pairs(KEYBINDS) do
        data.keybinds[name] = serializeKeyCode(key)
    end

    local ok, encoded = pcall(function()
        return game:GetService("HttpService"):JSONEncode(data)
    end)
    if not ok then return false end
    local wrote = pcall(function() writefile(CONFIG.CONFIG_FILE, encoded) end)
    return wrote
end

local function loadConfig()
    if not configAvailable() then return false end
    local ok, raw = pcall(function() return readfile(CONFIG.CONFIG_FILE) end)
    if not ok or type(raw) ~= "string" then return false end
    local decodedOk, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(raw)
    end)
    if not decodedOk or type(data) ~= "table" then return false end

    local positionsAreCurrent = (tonumber(data.version) or 0) >= 5
    local function loadPos(name)
        if not positionsAreCurrent then return nil end
        local p = data.positions and data.positions[name]
        if type(p) ~= "table" then return nil end
        return UDim2.new(tonumber(p.xs) or 0, tonumber(p.xo) or 0, tonumber(p.ys) or 0, tonumber(p.yo) or 0)
    end

    STATES.ShootMurderer.Position = loadPos("ShootMurderer") or STATES.ShootMurderer.Position
    STATES.FakeBombJump.Position = loadPos("FakeBombJump") or STATES.FakeBombJump.Position
    STATES.GrabGun.Position = loadPos("GrabGun") or STATES.GrabGun.Position
    KNIFE_THROW.Position = loadPos("ThrowKnife") or KNIFE_THROW.Position
    ACTION_FLOATERS.Fly.Position = loadPos("Fly") or ACTION_FLOATERS.Fly.Position
    ACTION_FLOATERS.Noclip.Position = loadPos("Noclip") or ACTION_FLOATERS.Noclip.Position
    ACTION_FLOATERS.JumpBoost.Position = loadPos("JumpBoost") or ACTION_FLOATERS.JumpBoost.Position
    ACTION_FLOATERS.StealGun.Position = loadPos("StealGun") or ACTION_FLOATERS.StealGun.Position

    for name, style in pairs(FLOATING_STYLES) do
        local saved = data.styles and data.styles[name]
        if type(saved) == "table" then
            style.Size = tonumber(saved.Size) or style.Size
            style.Height = tonumber(saved.Height) or style.Height
            if type(saved.Shape) == "string" and (saved.Shape == "Circle" or saved.Shape == "Square" or saved.Shape == "Rectangle") then style.Shape = saved.Shape end
            if type(saved.Text) == "string" then style.Text = saved.Text end
        end
    end

    if data.values then
        STATES.Movement.SpeedWalk.Value = tonumber(data.values.WalkSpeed) or STATES.Movement.SpeedWalk.Value
        STATES.Movement.JumpPower.Value = tonumber(data.values.JumpPower) or STATES.Movement.JumpPower.Value
        HITBOX_ESP.Size = tonumber(data.values.HitboxSize) or HITBOX_ESP.Size
        STATES.MovementExtras.FlySpeed = tonumber(data.values.FlySpeed) or STATES.MovementExtras.FlySpeed
        if type(data.values.CamlockBodyPart) == "string" then AIMLOCK.BodyPart = data.values.CamlockBodyPart end
        if type(data.values.CamlockTargetRole) == "string" then AIMLOCK.TargetRole = data.values.CamlockTargetRole end
        AIMLOCK.MaxDistance = tonumber(data.values.CamlockMaxDistance) or AIMLOCK.MaxDistance
        local sc = data.values.ShootConfig
        if type(sc) == "table" then
            SHOOT_CONFIG.ShootOffset = tonumber(sc.ShootOffset) or SHOOT_CONFIG.ShootOffset
            SHOOT_CONFIG.OffsetToPingMult = tonumber(sc.OffsetToPingMult) or SHOOT_CONFIG.OffsetToPingMult
        end
    end

    local function setSavedToggle(title, default)
        local v = data.toggles and data.toggles[title]
        if type(v) == "boolean" then return v end
        return default
    end
    for title, entry in pairs(LEGACY_TOGGLES) do
        if entry and entry.stateTable and entry.stateKey then
            entry.stateTable[entry.stateKey] = setSavedToggle(title, entry.stateTable[entry.stateKey] == true)
        end
    end

    AUTO_SHOOT.Enabled = setSavedToggle("Auto Shoot", AUTO_SHOOT.Enabled)
    KNIFE_THROW.Auto = setSavedToggle("Auto Throw Knife", KNIFE_THROW.Auto)
    KNIFE_THROW.FloatingEnabled = setSavedToggle("Throw Knife FloatingButton", KNIFE_THROW.FloatingEnabled)
    KNIFE_THROW.Locked = setSavedToggle("Lock Throw Knife FloatingButton", KNIFE_THROW.Locked)
    SHOOT_CONFIG.WallCheck = setSavedToggle("Shoot Wall Check", true)
    KNIFE_THROW.WallCheck = setSavedToggle("Knife Wall Check", true)
    AIMLOCK.Enabled = setSavedToggle("Camlock", AIMLOCK.Enabled)
    STATES.AutoFarm.CandyMode = setSavedToggle("Candy Farm Mode", STATES.AutoFarm.CandyMode)
    STATES.AutoFarm.AutoResetAt50 = setSavedToggle("Reset at 50 Candies", STATES.AutoFarm.AutoResetAt50)
    AUTO_GET_GUN.Enabled = setSavedToggle("Auto Get Gun", AUTO_GET_GUN.Enabled)
    ZXNexus_ANTI_FLING.Enabled = setSavedToggle("Anti-Fling", ZXNexus_ANTI_FLING.Enabled)
    DROP_ESP.Gun = setSavedToggle("ESP Gun", DROP_ESP.Gun)
    DROP_ESP.Trap = setSavedToggle("ESP Trap", DROP_ESP.Trap)
    HITBOX_ESP.Enabled = setSavedToggle("Hitbox ESP", HITBOX_ESP.Enabled)
    AIMLOCK.Enabled = setSavedToggle("Camlock", AIMLOCK.Enabled)
    AIMLOCK.WallCheck = setSavedToggle("Camlock Wall Check", AIMLOCK.WallCheck)
    AIMLOCK.UseDistance = setSavedToggle("Camlock Distance", AIMLOCK.UseDistance)
    STATES.MovementExtras.Noclip = setSavedToggle("Noclip", STATES.MovementExtras.Noclip)
    STATES.MovementExtras.Fly = setSavedToggle("Fly", STATES.MovementExtras.Fly)
    STATES.AutoFarm.FlingMurderer = setSavedToggle("AutoFarm Fling Murderer", STATES.AutoFarm.FlingMurderer)
    STATES.AutoFarm.KillAll = setSavedToggle("AutoFarm Kill All", STATES.AutoFarm.KillAll)
    STATES.MovementExtras.JumpBoost = setSavedToggle("Jump Boost", STATES.MovementExtras.JumpBoost)
    ACTION_FLOATERS.JumpBoost.Enabled = setSavedToggle("Jump Boost FloatingButton", ACTION_FLOATERS.JumpBoost.Enabled)
    ACTION_FLOATERS.JumpBoost.Locked = setSavedToggle("Lock Jump Boost FloatingButton", ACTION_FLOATERS.JumpBoost.Locked)
    ACTION_FLOATERS.Fly.Enabled = setSavedToggle("Fly FloatingButton", ACTION_FLOATERS.Fly.Enabled)
    ACTION_FLOATERS.Noclip.Enabled = setSavedToggle("Noclip FloatingButton", ACTION_FLOATERS.Noclip.Enabled)
    ACTION_FLOATERS.Fly.Locked = setSavedToggle("Lock Fly FloatingButton", ACTION_FLOATERS.Fly.Locked)
    ACTION_FLOATERS.Noclip.Locked = setSavedToggle("Lock Noclip FloatingButton", ACTION_FLOATERS.Noclip.Locked)
    ACTION_FLOATERS.StealGun.Enabled = setSavedToggle("Steal Gun FloatingButton", ACTION_FLOATERS.StealGun.Enabled)
    ACTION_FLOATERS.StealGun.Locked = setSavedToggle("Lock Steal Gun FloatingButton", ACTION_FLOATERS.StealGun.Locked)

    for name, fallback in pairs(KEYBINDS) do
        KEYBINDS[name] = deserializeKeyCode(data.keybinds and data.keybinds[name], fallback)
    end
    CONFIG_LOADED = true
    return true
end

local function getNearestPlayer()
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local nearest, distance = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            local d = (plr.Character.HumanoidRootPart.Position - root.Position).Magnitude
            if d < distance then nearest, distance = plr, d end
        end
    end
    return nearest
end

local function playNativeKnifeThrowAnimation(knife, humanoid)
    if not knife or not humanoid then return end
    -- First let the game's Tool/LocalScript handle its own normal animation.
    pcall(function() knife:Activate() end)
    -- Fallback for versions that expose the throw Animation object directly.
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return end
    for _, obj in ipairs(knife:GetDescendants()) do
        if obj:IsA("Animation") and tostring(obj.Name):lower():find("throw") then
            pcall(function() animator:LoadAnimation(obj):Play(0.05, 1, 1) end)
            break
        end
    end
end

local function knifeThrow(forceWallCheck)
    local wallCheckEnabled = forceWallCheck == true or KNIFE_THROW.WallCheck == true
    local target = getNearestPlayer()
    if not target and wallCheckEnabled and forceWallCheck ~= true then
        local deadline = os.clock() + 5
        repeat
            task.wait(0.1)
            target = getNearestPlayer()
        until target or os.clock() >= deadline
    end
    if not target or not target.Character then return end
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return end
    if not char:FindFirstChild("Knife") then
        local knife = player.Backpack:FindFirstChild("Knife")
        if not knife then return end
        hum:EquipTool(knife)
        task.wait()
    end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    local hand = char:FindFirstChild("RightHand")
    local knife = char:FindFirstChild("Knife")
    if not hrp or not hand or not knife then return end
    -- Keep knife throw behavior unchanged; YARHM prediction is used by Shoot.
    local predicted = hrp.Position

    local wallCheckEnabled = forceWallCheck == true or KNIFE_THROW.WallCheck == true
    if wallCheckEnabled and not hasLineOfSight(target.Character, hand.Position, predicted) then
        return
    end
    playNativeKnifeThrowAnimation(knife, hum)
    task.wait()
    local args = {CFrame.new(hand.Position), CFrame.new(predicted)}
    local event = knife:FindFirstChild("Events") and knife.Events:FindFirstChild("KnifeThrown")
    if event then pcall(function() event:FireServer(unpack(args)) end) end
end

local function setKnifeAuto(enabled)
    KNIFE_THROW.Auto = enabled
    if KNIFE_THROW.Connection then KNIFE_THROW.Connection:Disconnect(); KNIFE_THROW.Connection = nil end
    if enabled then
        KNIFE_THROW.Connection = task.spawn(function()
            while KNIFE_THROW.Auto do
                knifeThrow(true)
                task.wait(1.5)
            end
        end)
    end
    task.spawn(saveConfig)
end

local function createKnifeFloatingButton()
    if KNIFE_THROW.FloatingButton then return KNIFE_THROW.FloatingButton end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ZXNexusKnifeThrowFloating"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.DisplayOrder = 80
    gui.Parent = CoreGui

    local frame = UTILS.createWithStaticStroke("Frame", gui, {
        Name = "KnifeThrowButton",
        Size = UDim2.fromOffset(40, 40),
        Position = KNIFE_THROW.Position,
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = CONFIG.MAIN_COLOR,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        ZIndex = 1,
    })
    applyFloatingShape(frame, "Circle", 40)
    UTILS.createInstance("UIGradient", frame, {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 80, 140)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 55, 100)),
        }),
        Rotation = 90,
    })

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = "Knife"
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Parent = frame

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.fromScale(1, 1)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.Parent = frame

    local dragging, dragStart, startPos, moved = false, nil, nil, false
    hit.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if KNIFE_THROW.Locked then
            moved = false
            return
        end
        dragging, moved = false, false
        dragStart, startPos = Vector2.new(input.Position.X, input.Position.Y), frame.Position
    end)
    hit.InputChanged:Connect(function(input)
        if not dragStart or KNIFE_THROW.Locked then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        if delta.Magnitude > 5 then dragging, moved = true, true end
        if dragging then
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    hit.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not moved then
            UTILS.playClickSound()
            knifeThrow()
        else
            KNIFE_THROW.Position = frame.Position
            task.spawn(saveConfig)
        end
        dragStart = nil
        dragging = false
    end)

    hit.MouseEnter:Connect(function()
        TweenService:Create(frame, TweenInfo.new(0.12), {
            BackgroundTransparency = 0.02,
        }):Play()
    end)
    hit.MouseLeave:Connect(function()
        TweenService:Create(frame, TweenInfo.new(0.12), {
            BackgroundTransparency = 0.12,
        }):Play()
    end)

    KNIFE_THROW.FloatingButton = {gui = gui, frame = frame}
    return KNIFE_THROW.FloatingButton
end

local function destroyKnifeFloatingButton()
    if KNIFE_THROW.FloatingButton and KNIFE_THROW.FloatingButton.gui then
        KNIFE_THROW.FloatingButton.gui:Destroy()
    end
    KNIFE_THROW.FloatingButton = nil
end

local function setKnifeFloating(enabled)
    KNIFE_THROW.FloatingEnabled = enabled
    if enabled then createKnifeFloatingButton() else destroyKnifeFloatingButton() end
    task.spawn(saveConfig)
end

local function setAutoShoot(enabled)
    AUTO_SHOOT.Enabled = enabled
    if AUTO_SHOOT.Connection then AUTO_SHOOT.Connection:Disconnect(); AUTO_SHOOT.Connection = nil end
    -- Auto Shoot is background-only; remove any visible Shoot button.
    if enabled and STATES.ShootMurderer.ButtonData then
        pcall(function() STATES.ShootMurderer.ButtonData.destroy() end)
        STATES.ShootMurderer.ButtonData = nil
    end
    if enabled then
        if not STATES.ShootMurderer.ShootFunction then
            local bridge = UI_SYSTEM.createShootMurdererButton()
            if bridge and bridge.destroy then pcall(bridge.destroy) end
            STATES.ShootMurderer.ButtonData = nil
        end
        AUTO_SHOOT.Connection = RunService.Heartbeat:Connect(function()
            if not AUTO_SHOOT.Enabled then return end
            local shootFn = STATES.ShootMurderer.ShootFunction
            if shootFn and (os.clock() - AUTO_SHOOT.LastShot) >= AUTO_SHOOT.Cooldown then
                AUTO_SHOOT.LastShot = os.clock()
                task.spawn(function() pcall(function() shootFn(true) end) end)
            end
        end)
    end
    task.spawn(saveConfig)
end

local function ownsGunTool()
    local char = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")
    return (char and char:FindFirstChild("Gun") ~= nil) or (backpack and backpack:FindFirstChild("Gun") ~= nil) or false
end

local function getGunDropPart()
    local drop = workspace:FindFirstChild("GunDrop", true)
    if not drop then return nil end
    if drop:IsA("BasePart") then return drop end
    if drop:IsA("Model") or drop:IsA("Tool") then
        return drop:FindFirstChildWhichIsA("BasePart", true)
    end
    return drop:FindFirstChildWhichIsA("BasePart", true)
end

local function tryPickupDroppedGun()
    if ownsGunTool() then return true end
    local root = UTILS.getHRP()
    local gunPart = getGunDropPart()
    if not root or not gunPart or not gunPart:IsDescendantOf(workspace) then return false end
    if type(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(root, gunPart, 0)
            firetouchinterest(root, gunPart, 1)
        end)
    end
    return ownsGunTool()
end

local function watchForGunDrop(duration)
    local deadline = os.clock() + (duration or 6)
    repeat
        if tryPickupDroppedGun() then return true end
        RunService.Heartbeat:Wait()
    until os.clock() >= deadline
    return ownsGunTool()
end

local function setAutoGetGun(enabled)
    AUTO_GET_GUN.Enabled = enabled == true

    if AUTO_GET_GUN.Connection then AUTO_GET_GUN.Connection:Disconnect(); AUTO_GET_GUN.Connection = nil end
    if AUTO_GET_GUN.AddedConnection then AUTO_GET_GUN.AddedConnection:Disconnect(); AUTO_GET_GUN.AddedConnection = nil end

    if AUTO_GET_GUN.Enabled then
        -- DescendantAdded fires on the exact frame the drop replicates; Heartbeat is
        -- retained as a fast fallback in case the drop existed before the listener.
        AUTO_GET_GUN.AddedConnection = workspace.DescendantAdded:Connect(function(obj)
            if not AUTO_GET_GUN.Enabled or obj.Name ~= "GunDrop" then return end
            task.defer(function()
                if AUTO_GET_GUN.Enabled then
                    tryPickupDroppedGun()
                    task.spawn(watchForGunDrop, 0.35)
                end
            end)
        end)
        AUTO_GET_GUN.Connection = RunService.Heartbeat:Connect(function()
            if not AUTO_GET_GUN.Enabled or ownsGunTool() then return end
            tryPickupDroppedGun()
        end)
        task.defer(tryPickupDroppedGun)
    end
    task.spawn(saveConfig)
end


-- =========================
-- ZXNexus / EXTRA COMBAT SYSTEMS
-- =========================

ROLE_HELPERS = ROLE_HELPERS or {}

function ROLE_HELPERS.findByRoleItem(itemName)
    for _, plr in ipairs(Players:GetPlayers()) do
        local backpack = plr:FindFirstChildOfClass("Backpack")
        if (backpack and backpack:FindFirstChild(itemName)) or (plr.Character and plr.Character:FindFirstChild(itemName)) then
            return plr
        end
    end
end

local function findPlayerByRoleName(roleName)
    local roles = ESP_SYSTEM and ESP_SYSTEM.GetRolesData and ESP_SYSTEM.GetRolesData()
    if type(roles) ~= "table" then return nil end
    for key, record in pairs(roles) do
        local role = type(record) == "table" and (record.Role or record.role or record.RoleName or record.roleName or record.TeamRole)
        if role == roleName then
            local userName = type(record) == "table" and (record.Name or record.Username or record.UserName or record.DisplayName)
            local id = type(record) == "table" and (record.UserId or record.UserID or record.userId or record.UserID)
            local keyText = tostring(key)
            local plr = (type(userName) == "string" and Players:FindFirstChild(userName))
                or Players:FindFirstChild(keyText)
            local numericKey = tonumber(keyText)
            if not plr and (id or numericKey) then
                local userId = tonumber(id) or numericKey
                for _, candidate in ipairs(Players:GetPlayers()) do
                    if candidate.UserId == userId then plr = candidate; break end
                end
            end
            if plr then return plr end
        end
    end
    return nil
end

function ROLE_HELPERS.getMurderer()
    -- Use the same role-event data as Own ESP first; tool checks are fallback only.
    return findPlayerByRoleName("Murderer") or ROLE_HELPERS.findByRoleItem("Knife")
end

function ROLE_HELPERS.getSheriffOrHero()
    return findPlayerByRoleName("Sheriff") or findPlayerByRoleName("Hero") or ROLE_HELPERS.findByRoleItem("Gun")
end

-- ZXNexus anti-fling logic adapted to ZXNexus/WindUI.
function ZXNexus_ANTI_FLING.enable()
    if ZXNexus_ANTI_FLING.Enabled then return end
    ZXNexus_ANTI_FLING.Enabled = true
    ZXNexus_ANTI_FLING.LastPos = Vector3.zero

    ZXNexus_ANTI_FLING.Detection = RunService.Heartbeat:Connect(function()
        if not ZXNexus_ANTI_FLING.Enabled then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player and plr.Character and plr.Character:IsDescendantOf(workspace) and plr.Character.PrimaryPart then
                local root = plr.Character.PrimaryPart
                if root.AssemblyAngularVelocity.Magnitude > 50 or root.AssemblyLinearVelocity.Magnitude > 100 then
                    for _, part in ipairs(plr.Character:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                            part.AssemblyAngularVelocity = Vector3.zero
                            part.AssemblyLinearVelocity = Vector3.zero
                            pcall(function()
                                part.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0)
                            end)
                        end
                    end
                end
            end
        end
    end)

    ZXNexus_ANTI_FLING.Neutralizer = RunService.Heartbeat:Connect(function()
        local char = player.Character
        local root = char and char.PrimaryPart
        if not root then return end

        if root.AssemblyLinearVelocity.Magnitude > 250 or root.AssemblyAngularVelocity.Magnitude > 250 then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            if ZXNexus_ANTI_FLING.LastPos ~= Vector3.zero then
                root.CFrame = CFrame.new(ZXNexus_ANTI_FLING.LastPos)
            end
        else
            ZXNexus_ANTI_FLING.LastPos = root.Position
        end
    end)
end

function ZXNexus_ANTI_FLING.disable()
    ZXNexus_ANTI_FLING.Enabled = false
    if ZXNexus_ANTI_FLING.Detection then ZXNexus_ANTI_FLING.Detection:Disconnect() end
    if ZXNexus_ANTI_FLING.Neutralizer then ZXNexus_ANTI_FLING.Neutralizer:Disconnect() end
    ZXNexus_ANTI_FLING.Detection = nil
    ZXNexus_ANTI_FLING.Neutralizer = nil
end

ZXNexusSkidFling = function(targetPlayer)
    if not targetPlayer or targetPlayer == player or not targetPlayer.Character then return false end
    if ZXNexus_ANTI_FLING.Enabled then return false end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    local targetCharacter = targetPlayer.Character
    local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
    local targetRoot = targetHumanoid and targetHumanoid.RootPart
    local targetHead = targetCharacter and targetCharacter:FindFirstChild("Head")
    local basePart = targetHead or targetRoot
    if not character or not humanoid or not root or not targetCharacter or not targetHumanoid or not basePart then return false end

    -- Keep a real, safe map position. Never use the void as the fallback.
    local returnCF = root.CFrame
    local returnPos = returnCF.Position
    local oldFallen = workspace.FallenPartsDestroyHeight
    local bv
    local targetWasMoving = false
    local success = false

    local function hardReturn()
        local c = player.Character
        local r = c and c:FindFirstChild("HumanoidRootPart")
        if not r or not c then return end
        pcall(function()
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
            r.CFrame = returnCF
            c:PivotTo(returnCF)
            task.wait()
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
            r.CFrame = returnCF
            c:PivotTo(returnCF)
        end)
    end

    local ok = pcall(function()
        -- Keep the old fling mechanic, but give it a bounded lifetime.
        workspace.FallenPartsDestroyHeight = 0/0
        bv = Instance.new("BodyVelocity")
        bv.Name = "ZXNexusEpixVel"
        bv.Velocity = Vector3.new(9e8, 9e8, 9e8)
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.Parent = root
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

        local started = os.clock()
        local angle = 0
        while os.clock() - started < 2.5 do
            if humanoid.Health <= 0 or not root.Parent or not basePart.Parent or targetPlayer.Parent ~= Players then break end

            angle += 115
            local targetPos = basePart.Position
            root.CFrame = CFrame.new(targetPos) * CFrame.new(0, 1.5, 0) * CFrame.Angles(math.rad(angle), 0, 0)
            character:PivotTo(root.CFrame)
            root.AssemblyLinearVelocity = Vector3.new(9e7, 9e8, 9e7)
            root.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
            task.wait()

            if basePart.Parent then
                root.CFrame = CFrame.new(basePart.Position) * CFrame.new(0, -1.5, 0) * CFrame.Angles(math.rad(angle), 0, 0)
                character:PivotTo(root.CFrame)
                root.AssemblyLinearVelocity = Vector3.new(9e7, 9e8, 9e7)
                root.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
            end
            task.wait()

            local targetVel = targetRoot and targetRoot.AssemblyLinearVelocity.Magnitude or 0
            if targetVel > 500 then
                targetWasMoving = true
                -- Give physics a few extra frames to actually carry the target.
                task.wait(0.08)
                if targetRoot and targetRoot.Parent and targetRoot.AssemblyLinearVelocity.Magnitude > 150 then
                    success = true
                    break
                end
            end
        end
    end)

    if bv and bv.Parent then bv:Destroy() end
    if humanoid and humanoid.Parent then
        pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end)
    end
    pcall(function() workspace.FallenPartsDestroyHeight = oldFallen end)

    -- IMPORTANT: restore the local player after physics has had a chance to settle.
    -- This prevents the occasional successful fling from dragging us into the void.
    hardReturn()

    -- If Roblox physics/network ownership moves us away after the first return,
    -- immediately recover to the saved map position for a short safety window.
    task.spawn(function()
        local deadline = os.clock() + 0.65
        while os.clock() < deadline do
            local c = player.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if not r or not r.Parent then break end
            local distance = (r.Position - returnPos).Magnitude
            if distance > 45 or r.Position.Y < -50 then
                hardReturn()
            end
            task.wait(0.03)
        end
    end)

    -- A target that did not receive enough impulse is considered a failed attempt,
    -- so flingUntilSuccess will try again instead of reporting a false success.
    return ok and success and targetWasMoving
end


local function flingUntilSuccess(targetPlayer, attempts)
    attempts = attempts or 5
    for _ = 1, attempts do
        if not targetPlayer or not targetPlayer.Parent then return false end
        local ok = ZXNexusSkidFling(targetPlayer)
        if ok then return true end
        task.wait(0.05)
    end
    return false
end
local stealGunSessionRunning = false
local function performStealGun()
    if stealGunSessionRunning then return end
    stealGunSessionRunning = true
    local autoGetWasEnabled = AUTO_GET_GUN.Enabled == true
    setAutoGetGun(true)

    task.spawn(function()
        local ok, err = xpcall(function()
            -- Wait briefly for the current round's Sheriff role to replicate.
            local sheriff = nil
            local roleDeadline = os.clock() + 20
            repeat
                sheriff = findPlayerByRoleName("Sheriff")
                if sheriff then break end
                task.wait(0.1)
            until os.clock() >= roleDeadline or (ROUND_STATE.Known and not ROUND_STATE.Active)

            if sheriff and sheriff ~= player then
                -- Keep the existing steal mechanic, but the gun watcher is already active.
                flingUntilSuccess(sheriff, 2)
            end

            local sheriffHumanoid = sheriff and sheriff.Character and sheriff.Character:FindFirstChildOfClass("Humanoid")
            local sheriffDied = false
            if sheriff then
                while true do
                    if ROUND_STATE.Known and not ROUND_STATE.Active then break end
                    local currentSheriff = findPlayerByRoleName("Sheriff")
                    if not sheriff.Parent or (sheriffHumanoid and sheriffHumanoid.Health <= 0) or currentSheriff ~= sheriff then
                        sheriffDied = true
                        break
                    end
                    if not ROUND_STATE.Known and ROLE_HELPERS.getMurderer() == nil then break end
                    RunService.Heartbeat:Wait()
                end
            end

            -- Keep Auto Get Gun enabled after the Sheriff dies so it can catch the drop.
            if sheriffDied and (ROUND_STATE.Active or not ROUND_STATE.Known) then
                local pickupDeadline = os.clock() + 6
                repeat
                    if ownsGunTool() then break end
                    tryPickupDroppedGun()
                    RunService.Heartbeat:Wait()
                until os.clock() >= pickupDeadline or (ROUND_STATE.Known and not ROUND_STATE.Active)
            end
        end, debug.traceback)

        if not autoGetWasEnabled then setAutoGetGun(false) end
        stealGunSessionRunning = false
        if not ok then warn("[ZXNexus Steal Gun] " .. tostring(err)) end
    end)
end

local function aimlockUpdate()
    if not AIMLOCK.Enabled then return end
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hum or hum.Health <= 0 then return end

    local backpack = player:FindFirstChildOfClass("Backpack")
    local isMurderer = (char:FindFirstChild("Knife") ~= nil) or (backpack and backpack:FindFirstChild("Knife") ~= nil)
    local target
    if AIMLOCK.TargetRole == "Sheriff" or (AIMLOCK.TargetRole == "Auto" and isMurderer) then
        target = ROLE_HELPERS.getSheriffOrHero()
        if target == player then target = nil end
    else
        -- Sheriff/Hero aims at the Murderer; if roles have not replicated, wait safely.
        if ROLE_HELPERS.getSheriffOrHero() ~= player then return end
        target = ROLE_HELPERS.getMurderer()
    end
    local targetChar = target and target.Character
    local part = targetChar and (targetChar:FindFirstChild(AIMLOCK.BodyPart) or targetChar:FindFirstChild("UpperTorso") or targetChar:FindFirstChild("HumanoidRootPart"))
    if not target or not part then return end
    if AIMLOCK.UseDistance and root and (part.Position - root.Position).Magnitude > AIMLOCK.MaxDistance then return end
    if AIMLOCK.WallCheck and root and not hasLineOfSight(targetChar, root.Position, part.Position) then return end
    local cam = workspace.CurrentCamera
    if cam then cam.CFrame = CFrame.lookAt(cam.CFrame.Position, part.Position) end
end
local function setAimlock(enabled)
    enabled = enabled == true
    if AIMLOCK.Connection then AIMLOCK.Connection:Disconnect(); AIMLOCK.Connection = nil end

    if enabled then
        -- Capture Shift Lock exactly once. This also runs correctly when a saved
        -- config starts Camlock already enabled.
        if not AIMLOCK.ShiftLockCaptured then
            AIMLOCK.PreviousShiftLock = getMM2ShiftLockState and getMM2ShiftLockState() or nil
            AIMLOCK.ChangedShiftLock = AIMLOCK.PreviousShiftLock ~= true
            AIMLOCK.ShiftLockCaptured = true
            if AIMLOCK.ChangedShiftLock and setMM2ShiftLock then
                pcall(function() setMM2ShiftLock(true) end)
            end
        elseif getMM2ShiftLockState and getMM2ShiftLockState() == false and setMM2ShiftLock then
            pcall(function() setMM2ShiftLock(true) end)
        end
    elseif AIMLOCK.ShiftLockCaptured then
        if AIMLOCK.ChangedShiftLock and setMM2ShiftLock then
            pcall(function() setMM2ShiftLock(AIMLOCK.PreviousShiftLock == true) end)
        end
        AIMLOCK.ChangedShiftLock = false
        AIMLOCK.PreviousShiftLock = nil
        AIMLOCK.ShiftLockCaptured = false
    end

    AIMLOCK.Enabled = enabled
    if enabled then AIMLOCK.Connection = RunService.RenderStepped:Connect(aimlockUpdate) end
    task.spawn(saveConfig)
end

local function clearHitboxESP()
    for _, obj in pairs(HITBOX_ESP.Objects) do
        pcall(function() obj:Destroy() end)
    end
    HITBOX_ESP.Objects = {}
end

updateHitboxESP = function()
    clearHitboxESP()
    if not HITBOX_ESP.Enabled then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local adorn = Instance.new("BoxHandleAdornment")
                adorn.Name = "ZXNexusHitboxESP"
                adorn.Adornee = root
                adorn.AlwaysOnTop = true
                adorn.ZIndex = 5
                adorn.Size = Vector3.new(HITBOX_ESP.Size, HITBOX_ESP.Size, HITBOX_ESP.Size)
                adorn.Transparency = 0.75
                adorn.Color3 = CONFIG.MAIN_COLOR
                adorn.Parent = workspace.Terrain
                HITBOX_ESP.Objects[plr] = adorn
            end
        end
    end
end

Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function()
        task.wait(0.5)
        if HITBOX_ESP.Enabled then updateHitboxESP() end
        if ESP_SYSTEM.ESP_LINE_STATES.ESPLine then ESP_SYSTEM.StartAllLines() end
    end)
end)

-- Webhook: username + executor + local date/time.
local WEBHOOK_URL = "https://discord.com/api/webhooks/1541130654945771621/LQBw768SmR2k1JzpW8nSw0nPTyUVfYu2y-77cTLBfXd-gHbmJFyWn1SQCcIyej-SKTie"
local function sendLoadWebhook()
    local request = (syn and syn.request) or (http and http.request) or request or http_request
    if not request then return end
    local HttpService = game:GetService("HttpService")
    local executor = identifyexecutor or getexecutorname
    local executorName = executor and executor() or "Unknown"
    local payload = {
        username = "ZXNexus",
        embeds = {{
            title = "ZXNexus loaded",
            color = 3447003,
            fields = {
                {name = "User", value = tostring(player.Name), inline = true},
                {name = "Executor", value = tostring(executorName), inline = true},
                {name = "Game", value = tostring(game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name), inline = true},
                {name = "Date / Time", value = os.date("%Y-%m-%d %H:%M:%S"), inline = false},
            },
            thumbnail = {
                url = ("https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=150&height=150&format=png"):format(player.UserId)
            },
            footer = {text = "Made by CrisZX"}
        }}
    }
    pcall(function()
        request({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(payload)
        })
    end)
end

local CONTROL_REFS

-- Compact action FloatingButtons used by Movement and Steal Gun.
local function createActionFloatingButton(name, state, text, onClick)
    if state.Button then return state.Button end
    local gui = Instance.new("ScreenGui")
    gui.Name = "ZXNexus" .. name .. "Floating"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.DisplayOrder = 85
    gui.Parent = CoreGui
    local style = FLOATING_STYLES[name] or {Size = 46, Height = 46, Shape = "Circle", Text = text}
    local frame = UTILS.createWithStaticStroke("Frame", gui, {
        Name = name .. "Button", Size = UDim2.fromOffset(style.Size, style.Height), Position = state.Position,
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = CONFIG.MAIN_COLOR, BackgroundTransparency = 0.12, BorderSizePixel = 0, ZIndex = 1,
    })
    applyFloatingShape(frame, style.Shape, math.max(style.Size, style.Height))
    local gradient = Instance.new("UIGradient", frame)
    gradient.Color = ColorSequence.new(Color3.fromRGB(45,80,140), Color3.fromRGB(25,55,100)); gradient.Rotation = 90
    local label = Instance.new("TextLabel", frame)
    label.Size = UDim2.fromScale(1,1); label.BackgroundTransparency = 1; label.Text = style.Text or text
    label.TextColor3 = Color3.new(1,1,1); label.Font = Enum.Font.GothamBold; label.TextSize = 9; label.ZIndex = 2
    local hit = Instance.new("TextButton", frame)
    hit.Size = UDim2.fromScale(1,1); hit.BackgroundTransparency = 1; hit.Text = ""; hit.ZIndex = 3
    local dragging, dragStart, startPos, moved = false, nil, nil, false
    local clickConsumed = false
    local activatedByGui = false
    local function begin(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        moved = false
        clickConsumed = false
        activatedByGui = false
        if not state.Locked then dragStart, startPos = Vector2.new(input.Position.X,input.Position.Y), frame.Position end
    end
    local function changed(input)
        if state.Locked or not dragStart then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = Vector2.new(input.Position.X,input.Position.Y) - dragStart
        if delta.Magnitude > 5 then dragging, moved = true, true end
        if dragging then frame.Position = UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y) end
    end
    local function performClick(fromActivated)
        if clickConsumed or moved then return end
        clickConsumed = true
        if fromActivated then activatedByGui = true end
        task.defer(UTILS.playClickSound)
        -- Run the feature immediately on its own scheduler and contain transient respawn errors.
        task.spawn(function()
            local ok, err = xpcall(onClick, debug.traceback)
            if not ok then warn("[ZXNexus FloatingButton] " .. tostring(err)) end
        end)
    end
    local function ended(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not moved and not activatedByGui then performClick(false) end
        if moved then
            state.Position = frame.Position
            task.spawn(saveConfig)
        end
        dragStart, startPos, dragging, moved = nil, nil, false, false
    end
    hit.InputBegan:Connect(begin); hit.InputChanged:Connect(changed); hit.InputEnded:Connect(ended)
    -- Activated is the reliable path on mobile; clickConsumed prevents double execution
    -- when InputEnded also fires.
    hit.Activated:Connect(function() performClick(true) end)
    hit.MouseEnter:Connect(function() frame.BackgroundTransparency = 0.02 end)
    hit.MouseLeave:Connect(function() frame.BackgroundTransparency = 0.12 end)
    state.Button = {gui=gui, frame=frame, destroy=function() if gui then gui:Destroy() end; state.Button=nil end}
    return state.Button
end
local function destroyActionFloatingButton(state)
    if state.Button then state.Button.destroy() end
end
-- Forward declarations: floating-button callbacks are created before the movement functions below.
local setNoclip, setFly, setJumpBoost

local function setFlyFloating(enabled)
    ACTION_FLOATERS.Fly.Enabled = enabled
    if enabled then createActionFloatingButton("Fly", ACTION_FLOATERS.Fly, "Fly", function() setFly(not STATES.MovementExtras.Fly) end) else destroyActionFloatingButton(ACTION_FLOATERS.Fly) end
    task.spawn(saveConfig)
end
local function setNoclipFloating(enabled)
    ACTION_FLOATERS.Noclip.Enabled = enabled
    if enabled then
        createActionFloatingButton("Noclip", ACTION_FLOATERS.Noclip, "Noclip", function() setNoclip(not STATES.MovementExtras.Noclip) end)
    else
        destroyActionFloatingButton(ACTION_FLOATERS.Noclip)
    end
    task.spawn(saveConfig)
end
local function setJumpBoostFloating(enabled)
    ACTION_FLOATERS.JumpBoost.Enabled = enabled
    if enabled then
        createActionFloatingButton("JumpBoost", ACTION_FLOATERS.JumpBoost, "Jump+", function()
            setJumpBoost(not STATES.MovementExtras.JumpBoost)
        end)
    else
        destroyActionFloatingButton(ACTION_FLOATERS.JumpBoost)
    end
    task.spawn(saveConfig)
end
local function setStealFloating(enabled)
    ACTION_FLOATERS.StealGun.Enabled = enabled
    if enabled then createActionFloatingButton("StealGun", ACTION_FLOATERS.StealGun, "Steal", performStealGun)
    else destroyActionFloatingButton(ACTION_FLOATERS.StealGun) end
    task.spawn(saveConfig)
end

-- =========================
-- ZXNexus V3 extra systems
-- =========================
local noclipOriginalCollisions = setmetatable({}, {__mode = "k"})
local noclipCharacterAddedConnection = nil
local noclipDescendantAddedConnection = nil

local function applyNoclipToPart(part)
    if not part or not part:IsA("BasePart") then return end
    if noclipOriginalCollisions[part] == nil then
        noclipOriginalCollisions[part] = part.CanCollide
    end
    part.CanCollide = false
end

local function applyNoclipToCharacter(character)
    if noclipDescendantAddedConnection then
        noclipDescendantAddedConnection:Disconnect()
        noclipDescendantAddedConnection = nil
    end
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do applyNoclipToPart(part) end
    noclipDescendantAddedConnection = character.DescendantAdded:Connect(applyNoclipToPart)
end

local function restoreNoclipCollisions()
    -- Restoration is synchronous in the toggle callback, not deferred to a later Stepped frame.
    for part, wasCollidable in pairs(noclipOriginalCollisions) do
        if part and part.Parent then
            pcall(function() part.CanCollide = wasCollidable end)
        end
        noclipOriginalCollisions[part] = nil
    end
end

setNoclip = function(enabled)
    enabled = enabled == true
    STATES.MovementExtras.Noclip = enabled
    if STATES.MovementExtras.NoclipConnection then STATES.MovementExtras.NoclipConnection:Disconnect() end
    STATES.MovementExtras.NoclipConnection = nil
    if noclipCharacterAddedConnection then noclipCharacterAddedConnection:Disconnect(); noclipCharacterAddedConnection = nil end
    if noclipDescendantAddedConnection then noclipDescendantAddedConnection:Disconnect(); noclipDescendantAddedConnection = nil end

    if enabled then
        if player.Character then applyNoclipToCharacter(player.Character) end
        noclipCharacterAddedConnection = player.CharacterAdded:Connect(applyNoclipToCharacter)
    else
        restoreNoclipCollisions()
    end
    task.spawn(saveConfig)
end

setFly = function(enabled)
    enabled = enabled == true
    STATES.MovementExtras.Fly = enabled
    if STATES.MovementExtras.FlyConnection then STATES.MovementExtras.FlyConnection:Disconnect() end
    STATES.MovementExtras.FlyConnection = nil
    if STATES.MovementExtras.FlyVelocity then
        pcall(function() STATES.MovementExtras.FlyVelocity:Destroy() end)
        STATES.MovementExtras.FlyVelocity = nil
    end
    if enabled then
        STATES.MovementExtras.FlyConnection = RunService.RenderStepped:Connect(function()
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not hum or hum.Health <= 0 or not root or not root.Parent then return end

            local bv = STATES.MovementExtras.FlyVelocity
            if not bv or not bv.Parent or bv.Parent ~= root then
                if bv then pcall(function() bv:Destroy() end) end
                bv = Instance.new("BodyVelocity")
                bv.Name = "ZXNexusFly"
                bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
                bv.P = 1e4
                bv.Velocity = Vector3.zero
                bv.Parent = root
                STATES.MovementExtras.FlyVelocity = bv
            end

            -- Humanoid.MoveDirection works for both keyboard WASD and mobile thumbsticks.
            local move = hum.MoveDirection
            local horizontal = Vector3.new(move.X, 0, move.Z)
            if horizontal.Magnitude > 1 then horizontal = horizontal.Unit end
            local vertical = 0
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump then vertical += 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then vertical -= 1 end
            local dir = horizontal + Vector3.yAxis * vertical
            if dir.Magnitude > 1 then dir = dir.Unit end
            bv.Velocity = dir * math.max(10, tonumber(STATES.MovementExtras.FlySpeed) or 60)
        end)
    end
    task.spawn(saveConfig)
end

-- Jump Boost: a modest forward burst on each jump request while the player is moving.
-- A short cooldown and velocity cap keep repeated jumps fast without becoming absurd.
setJumpBoost = function(enabled)
    enabled = enabled == true
    STATES.MovementExtras.JumpBoost = enabled
    if STATES.MovementExtras.JumpBoostConnection then
        STATES.MovementExtras.JumpBoostConnection:Disconnect()
        STATES.MovementExtras.JumpBoostConnection = nil
    end

    if enabled then
        STATES.MovementExtras.JumpBoostConnection = UserInputService.JumpRequest:Connect(function()
            if not STATES.MovementExtras.JumpBoost then return end
            local now = os.clock()
            if now - (STATES.MovementExtras.JumpBoostLastAt or 0) < 0.14 then return end
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not humanoid or humanoid.Health <= 0 or not root or not root.Parent then return end

            local direction = humanoid.MoveDirection
            local horizontalDirection = Vector3.new(direction.X, 0, direction.Z)
            if horizontalDirection.Magnitude < 0.15 then return end
            horizontalDirection = horizontalDirection.Unit

            local velocity = root.AssemblyLinearVelocity
            local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
            local boostedVelocity = horizontalVelocity + horizontalDirection * 22
            local maxHorizontalSpeed = 44
            if boostedVelocity.Magnitude > maxHorizontalSpeed then
                boostedVelocity = boostedVelocity.Unit * maxHorizontalSpeed
            end
            root.AssemblyLinearVelocity = Vector3.new(boostedVelocity.X, velocity.Y, boostedVelocity.Z)
            STATES.MovementExtras.JumpBoostLastAt = now
        end)
    end
    task.spawn(saveConfig)
end

local function removeOFX()
    STATES.OFXRemoved = true
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Decal") or obj:IsA("Texture") then
            obj:Destroy()
        elseif obj:IsA("BasePart") then
            obj.Material = Enum.Material.SmoothPlastic
            obj.Reflectance = 0
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            obj.Enabled = false
        end
    end
end

-- =========================
local function applyLoadedSettings()
    -- Re-apply legacy callbacks and newly-added systems after a manual Load.
    for title, entry in pairs(LEGACY_TOGGLES) do
        if entry and entry.stateTable and entry.stateKey and entry.callback then
            task.spawn(entry.callback, entry.stateTable[entry.stateKey] == true)
        end
    end
    setNoclip(STATES.MovementExtras.Noclip)
    setFly(STATES.MovementExtras.Fly)
    setJumpBoost(STATES.MovementExtras.JumpBoost)
    setAutoGetGun(AUTO_GET_GUN.Enabled)
    setAimlock(AIMLOCK.Enabled)
    setAutoShoot(AUTO_SHOOT.Enabled)
    setKnifeAuto(KNIFE_THROW.Auto)
    setKnifeFloating(KNIFE_THROW.FloatingEnabled)
    setFlyFloating(ACTION_FLOATERS.Fly.Enabled)
    setNoclipFloating(ACTION_FLOATERS.Noclip.Enabled)
    setJumpBoostFloating(ACTION_FLOATERS.JumpBoost.Enabled)
    setStealFloating(ACTION_FLOATERS.StealGun.Enabled)
    if ZXNexus_ANTI_FLING.Enabled then
        ZXNexus_ANTI_FLING.Enabled = false
        ZXNexus_ANTI_FLING.enable()
    end
    if HITBOX_ESP.Enabled then updateHitboxESP() end
    if DROP_ESP.Gun or DROP_ESP.Trap then refreshDropESP() end
    if CONTROL_REFS then
        for title, control in pairs(CONTROL_REFS) do
            local entry = LEGACY_TOGGLES[title]
            if entry and control and type(control.Set) == "function" then pcall(function() control:Set(entry.stateTable[entry.stateKey] == true) end) end
        end
    end
end

-- Main initialization
function UI_SYSTEM.init()
    -- Keep the original UI builders alive as a hidden callback bridge.
    -- The visible interface is 100% WindUI; floating buttons remain native ScreenGuis.
    local legacyGui = UTILS.createInstance("ScreenGui", CoreGui, {
        Name = "ZXNexusLegacyUIBridge",
        ResetOnSpawn = false,
        DisplayOrder = -100,
        Enabled = false,
    })

    local function makeLegacyContent(name)
        local frame = UTILS.createInstance("Frame", legacyGui, {
            Name = name,
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(1, 1),
        })
        return frame
    end

    -- Build the original controls invisibly so every original callback/function
    -- remains intact. Nothing from this bridge is shown to the player.
    UI_SYSTEM.createMainTabContent(makeLegacyContent("Main"))
    UI_SYSTEM.createVisualTabContent(makeLegacyContent("Visual"))
    UI_SYSTEM.createCombatTabContent(makeLegacyContent("Combat"))
    UI_SYSTEM.createTeleportTabContent(makeLegacyContent("Teleport"))
    UI_SYSTEM.createAutoFarmTabContent(makeLegacyContent("AutoFarm"))
    UI_SYSTEM.createActMgrTabContent(makeLegacyContent("ActMgr"))

    -- Restore the saved values before building controls, so their initial state and
    -- key mappings match the previous session. Effects are re-applied after controls exist.
    local configLoadedAtStartup = loadConfig()
    local ok; ok, WindUI = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)
    if not ok or not WindUI then
        error("ZXNexus: failed to load WindUI")
    end
    pcall(function()
        WindUI:AddTheme({
            Name = "Halloween",
            Accent = "#f97316",
            Dialog = "#25152f",
            Outline = "#fb923c",
            Text = "#fff7ed",
            Placeholder = "#c4b5fd",
            Background = "#130b1c",
            Button = "#4c1d4a",
            Icon = "#fb923c",
        })
    end)

    local Window = WindUI:CreateWindow({
        Title = "🎃 Murder Mystery 2 | ZXNexus",
        Author = "ZXNexus",
        Icon = "gamepad-2",
        Folder = "ZXNexus_MM2",
        Theme = "Halloween",
        Size = UDim2.fromOffset(500, 440),
        MinSize = Vector2.new(440, 380),
        MaxSize = Vector2.new(680, 600),
        Resizable = true,
        HideSearchBar = false,
        OpenButton = {
            Title = "🎃 ZXNexus",
            CornerRadius = UDim.new(0, 16),
            StrokeThickness = 2,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(135, 45, 0)),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 160, 45)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 145)),
            }),
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
            Scale = 0.55,
        },
        Topbar = {
            Height = 44,
            ButtonsType = "Default",
        },
    })


    -- Compact match notifications. Suppress role and match messages unless the local player participates in the round.
    local lastRoundActive = false
    local lastMurdererPowerSignature = nil
    local notifiedGunDrop = false
    local notifiedTrapCount = 0
    local activeZXToasts = {}
    local toastGui = Instance.new("ScreenGui")
    toastGui.Name = "ZXNexusCompactNotifications"
    toastGui.ResetOnSpawn = false
    toastGui.IgnoreGuiInset = true
    toastGui.DisplayOrder = 120
    toastGui.Parent = CoreGui

    local function relayoutZXToasts()
        local total = #activeZXToasts
        for index, toast in ipairs(activeZXToasts) do
            if toast and toast.Parent then
                -- Newest toast stays at the bottom; older ones move upward.
                local stackOffset = (total - index) * 44
                local targetPos = UDim2.new(0, 12, 1, -12 - stackOffset)
                TweenService:Create(toast, TweenInfo.new(0.12), {Position = targetPos}):Play()
            end
        end
    end

    local function zxNotify(message, duration)
        local toast = Instance.new("Frame")
        toast.Name = "ZXNexusToast"
        toast.Size = UDim2.fromOffset(226, 38)
        toast.AnchorPoint = Vector2.new(0, 1)
        toast.Position = UDim2.new(0, -238, 1, -12)
        toast.BackgroundColor3 = Color3.fromRGB(18, 24, 36)
        toast.BackgroundTransparency = 0.08
        toast.BorderSizePixel = 0
        toast.ClipsDescendants = true
        toast.Parent = toastGui
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = toast
        local stroke = Instance.new("UIStroke")
        stroke.Color = CONFIG.MAIN_COLOR
        stroke.Thickness = 1
        stroke.Transparency = 0.25
        stroke.Parent = toast

        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Position = UDim2.fromOffset(8, 3)
        title.Size = UDim2.new(1, -16, 0, 12)
        title.Font = Enum.Font.GothamBold
        title.Text = "ZXNexus says:"
        title.TextSize = 9
        title.TextColor3 = Color3.fromRGB(125, 180, 255)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = toast

        local body = Instance.new("TextLabel")
        body.BackgroundTransparency = 1
        body.Position = UDim2.fromOffset(8, 15)
        body.Size = UDim2.new(1, -16, 0, 20)
        body.Font = Enum.Font.GothamMedium
        body.Text = tostring(message)
        body.TextSize = 10
        body.TextColor3 = Color3.fromRGB(245, 247, 252)
        body.TextWrapped = true
        body.TextTruncate = Enum.TextTruncate.AtEnd
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextYAlignment = Enum.TextYAlignment.Center
        body.Parent = toast

        table.insert(activeZXToasts, toast)
        relayoutZXToasts()
        task.delay(duration or 1.8, function()
            for index, item in ipairs(activeZXToasts) do
                if item == toast then table.remove(activeZXToasts, index); break end
            end
            if toast and toast.Parent then
                local tween = TweenService:Create(toast, TweenInfo.new(0.12), {BackgroundTransparency = 1})
                tween:Play()
                task.delay(0.13, function() if toast then toast:Destroy() end end)
            end
            relayoutZXToasts()
        end)
    end

    local function getRecordRole(record)
        if type(record) ~= "table" then return nil end
        return record.Role or record.role or record.RoleName or record.roleName or record.TeamRole
    end

    local function findExplicitPower(record, plr)
        local function valueToPower(value)
            if type(value) == "string" and value ~= "" then return value end
            if typeof(value) == "Instance" then return value.Name end
            if type(value) == "table" then
                for _, key in ipairs({"Name", "name", "DisplayName", "displayName", "Equipped", "equipped", "Power", "Ability", "Perk"}) do
                    local v = value[key]
                    if type(v) == "string" and v ~= "" then return v end
                end
                for k, v in pairs(value) do
                    if v == true and type(k) == "string" then return k end
                end
            end
            return nil
        end
        local function scanTable(tbl)
            if type(tbl) ~= "table" then return nil end
            for key, value in pairs(tbl) do
                local keyLower = tostring(key):lower()
                if keyLower:find("power", 1, true) or keyLower:find("ability", 1, true)
                    or keyLower:find("perk", 1, true) or keyLower:find("skill", 1, true) then
                    local found = valueToPower(value)
                    if found then return found end
                end
                if type(value) == "table" then
                    for nestedKey, nestedValue in pairs(value) do
                        local nestedLower = tostring(nestedKey):lower()
                        if nestedLower:find("power", 1, true) or nestedLower:find("ability", 1, true)
                            or nestedLower:find("perk", 1, true) or nestedLower:find("skill", 1, true) then
                            local found = valueToPower(nestedValue)
                            if found then return found end
                        end
                    end
                end
            end
            return nil
        end
        local found = scanTable(record)
        if found then return found end
        local function scanAttributes(instance)
            if not instance then return nil end
            for key, value in pairs(instance:GetAttributes()) do
                local low = tostring(key):lower()
                if low:find("power", 1, true) or low:find("ability", 1, true)
                    or low:find("perk", 1, true) or low:find("skill", 1, true) then
                    local result = valueToPower(value)
                    if result then return result end
                end
            end
            return nil
        end
        found = scanAttributes(plr) or scanAttributes(plr and plr.Character)
        if found then return found end
        local char = plr and plr.Character
        if char then
            for _, item in ipairs(char:GetDescendants()) do
                local low = item.Name:lower()
                if low:find("power", 1, true) or low:find("ability", 1, true) or low:find("perk", 1, true) then
                    if item:IsA("StringValue") and item.Value ~= "" then return item.Value end
                    if item:IsA("BoolValue") and item.Value then return item.Name end
                end
            end
        end
        return "Unknown"
    end

    local function notificationHeartbeat()
        local roundActive = ROUND_STATE.Active == true
        local data = ESP_SYSTEM.GetRolesData()
        if type(data) ~= "table" then
            if ROUND_STATE.Known and not roundActive and lastRoundActive then
                lastMurdererPowerSignature = nil
                notifiedGunDrop = false
                notifiedTrapCount = 0
                lastRoundActive = false
            end
            return
        end
        local entries, murdererName, murdererRecord, murdererPlayer = {}, nil, nil, nil
        local ownRole, sheriffName, sheriffPlayer = nil, nil, nil
        for key, record in pairs(data) do
            local role = getRecordRole(record)
            if role == "Murderer" or role == "Sheriff" or role == "Hero" or role == "Innocent" then
                local name = (type(record) == "table" and (record.Name or record.Username or record.UserName)) or tostring(key)
                local id = type(record) == "table" and (record.UserId or record.UserID or record.userId)
                local keyText = tostring(key)
                local resolvedPlayer = Players:FindFirstChild(name) or Players:FindFirstChild(keyText)
                if not resolvedPlayer and id then
                    for _, candidate in ipairs(Players:GetPlayers()) do
                        if candidate.UserId == tonumber(id) then resolvedPlayer = candidate; break end
                    end
                end
                if not resolvedPlayer then
                    local numericKey = tonumber(key)
                    if numericKey then
                        for _, candidate in ipairs(Players:GetPlayers()) do
                            if candidate.UserId == numericKey then resolvedPlayer = candidate; break end
                        end
                    end
                end
                if resolvedPlayer then name = resolvedPlayer.Name end
                table.insert(entries, {Name = name, Role = role, Record = record, Player = resolvedPlayer})
                if resolvedPlayer == player or name == player.Name or keyText == player.Name
                    or (id and tonumber(id) == player.UserId) or tonumber(keyText) == player.UserId then
                    ownRole = role
                end
                if role == "Murderer" then
                    murdererName = name
                    murdererRecord = record
                    murdererPlayer = resolvedPlayer
                elseif role == "Sheriff" then
                    sheriffName = name
                    sheriffPlayer = resolvedPlayer
                end
            end
        end

        -- If RoundStart was received, trust that state. If the script was injected
        -- mid-round and missed the event, the local player's assigned role + Murderer
        -- record confirm that this client is an actual participant, not a lobby spectator.
        local roleDataConfirmsRound = ownRole ~= nil and murdererName ~= nil and #entries >= 2
        local inMatch = false
        if ROUND_STATE.Known then
            inMatch = roundActive and roleDataConfirmsRound
        else
            inMatch = roleDataConfirmsRound
        end
        if not inMatch then
            if ROUND_STATE.Known and not roundActive then
                lastMurdererPowerSignature = nil
                notifiedGunDrop = false
                notifiedTrapCount = 0
                lastRoundActive = false
            end
            return
        end
        lastRoundActive = true

        if ownRole == "Murderer" then
            if sheriffName then
                local sheriffSignature = "Sheriff|" .. tostring(sheriffName)
                if sheriffSignature ~= lastMurdererPowerSignature then
                    lastMurdererPowerSignature = sheriffSignature
                    zxNotify("Sheriff: " .. tostring(sheriffName), 2.2)
                end
            end
        elseif murdererName and #entries >= 2 then
            if not murdererPlayer then murdererPlayer = Players:FindFirstChild(murdererName) end
            local power = findExplicitPower(murdererRecord, murdererPlayer)
            local powerSignature = tostring(murdererName) .. "|" .. tostring(power)
            if powerSignature ~= lastMurdererPowerSignature then
                lastMurdererPowerSignature = powerSignature
                zxNotify("Murderer: " .. tostring(murdererName) .. " | Power: " .. tostring(power), 2.2)
            end
        end

        local gun = workspace:FindFirstChild("GunDrop", true)
        if gun and not notifiedGunDrop then
            notifiedGunDrop = true
            zxNotify("The gun was dropped.", 1.7)
        elseif not gun then
            notifiedGunDrop = false
        end

        local traps = 0
        for _, descendant in ipairs(workspace:GetDescendants()) do
            if descendant.Name == "Trap" and isTrapActiveInMatch(descendant) and not shouldIgnoreInitialTrap(descendant) then
                traps += 1
            end
        end
        if traps > notifiedTrapCount then
            notifiedTrapCount = traps
            zxNotify("A trap appeared.", 1.7)
        elseif traps == 0 then
            notifiedTrapCount = 0
        end
    end
    task.spawn(function() while task.wait(0.15) do notificationHeartbeat() end end)

    local function bindToggle(tab, title)
        local entry = LEGACY_TOGGLES[title]
        if not entry then
            warn("ZXNexus WindUI: missing legacy toggle: " .. title)
            return nil
        end

        local control = tab:Toggle({
            Title = title,
            Value = entry.stateTable[entry.stateKey] == true,
            Callback = function(value)
                entry.stateTable[entry.stateKey] = value
                if entry.callback then
                    task.spawn(entry.callback, value)
                end
                task.spawn(saveConfig)
            end,
        })
        CONTROL_REFS[title] = control
        return control
    end

    local function bindButton(tab, title, icon)
        local callback = LEGACY_BUTTONS[title]
        if not callback then
            warn("ZXNexus WindUI: missing legacy button: " .. title)
            return nil
        end

        return tab:Button({
            Title = title,
            Icon = icon or "play",
            Callback = function()
                task.spawn(callback)
            end,
        })
    end

    CONTROL_REFS = {}
    local tabs = {}
    tabs.Main = Window:Tab({Title = "Changelogs", Icon = "scroll-text"})
    tabs.Movement = Window:Tab({Title = "Movement", Icon = "move"})
    tabs.Visual = Window:Tab({Title = "Visual", Icon = "eye"})
    tabs.Sheriff = Window:Tab({Title = "Sheriff", Icon = "crosshair"})
    tabs.Murderer = Window:Tab({Title = "Murderer", Icon = "skull"})
    tabs.Innocent = Window:Tab({Title = "Innocent", Icon = "shield"})
    tabs.Optimization = Window:Tab({Title = "Optimization", Icon = "gauge"})
    tabs.Teleport = Window:Tab({Title = "Teleport", Icon = "map-pin"})
    tabs.AutoFarm = Window:Tab({Title = "Auto Farm", Icon = "coins"})
    tabs.Emote = Window:Tab({Title = "Emote", Icon = "smile"})
    tabs.Misc = Window:Tab({Title = "Misc", Icon = "sliders-horizontal"})
    tabs.Music = Window:Tab({Title = "Music", Icon = "music"})

    -- Keybind system: click a "Set" button, then press the desired key.
    local function executeKeybind(name)
        if name == "ToggleUI" then
            pcall(function() Window:Toggle() end)
        elseif name == "ShootMurderer" then
            local data = STATES.ShootMurderer.ButtonData
            if data and data.shoot then data.shoot() end
        elseif name == "ThrowKnife" then
            knifeThrow()
        elseif name == "Bomb" then
            local data = STATES.FakeBombJump.ButtonData
            local button = data and data.frame and data.frame:FindFirstChild("BombButton")
            if button then pcall(function() button:Activate() end) end
        elseif name == "Extra1" then
            setAimlock(not AIMLOCK.Enabled)
        elseif name == "Extra2" then
            local entry = LEGACY_TOGGLES["ESP Name"]
            if entry then
                local value = not (entry.stateTable[entry.stateKey] == true)
                entry.stateTable[entry.stateKey] = value
                if entry.callback then task.spawn(entry.callback, value) end
            end
        end
    end

    local function keybindLabel(name)
        local key = KEYBINDS[name]
        return key and key.Name or "None"
    end

    local function captureKeybind(name)
        if KEYBIND_CAPTURE.Connection then
            KEYBIND_CAPTURE.Connection:Disconnect()
            KEYBIND_CAPTURE.Connection = nil
        end
        KEYBIND_CAPTURE.Active = name
        KEYBIND_CAPTURE.Connection = UserInputService.InputBegan:Connect(function(input, _processed)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            if input.KeyCode == Enum.KeyCode.Unknown then return end
            KEYBINDS[name] = input.KeyCode
            KEYBIND_CAPTURE.Active = nil
            KEYBIND_CAPTURE.Connection:Disconnect()
            KEYBIND_CAPTURE.Connection = nil
            task.spawn(saveConfig)
            zxNotify("Keybind set: " .. name .. " = " .. input.KeyCode.Name, 1.5)
        end)
        zxNotify("Press a key for " .. name .. ".", 1.5)
    end

    local keybindTitles = {
        ToggleUI = "Minimize / Open GUI",
        ShootMurderer = "Shoot Murderer",
        ThrowKnife = "Throw Knife",
        Bomb = "Bomb",
        Extra1 = "Extra: Camlock",
        Extra2 = "Extra: ESP Name",
    }

    -- One global input listener handles all saved mappings.
    UserInputService.InputBegan:Connect(function(input, _processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if KEYBIND_CAPTURE.Active then return end
        if UserInputService:GetFocusedTextBox() then return end
        for name, key in pairs(KEYBINDS) do
            if input.KeyCode == key then
                task.spawn(function()
                    local ok, err = xpcall(function() executeKeybind(name) end, debug.traceback)
                    if not ok then warn("[ZXNexus Keybind] " .. tostring(err)) end
                end)
                break
            end
        end
    end)

    -- Changelogs / tester warning
    tabs.Main:Paragraph({
        Title = "ZXNexus — Tester Build",
        Desc = "This version of the script is for TESTERS ONLY. Any leaked version of this script will result in a BAN.",
    })
    tabs.Main:Paragraph({
        Title = "Changelog",
        Desc = "WindUI migration • role-based tabs • configurable FloatingButtons • improved ESP/tracers • ZXNexus integrations • server rejoin/server hop.",
    })
    tabs.Main:Paragraph({
        Title = "Credits",
        Desc = "Made by CrisZX",
    })

    -- Movement: each tool has its own section so settings are not mixed together.
    tabs.Movement:Section({Title = "Flight"})
    tabs.Movement:Toggle({Title = "Fly", Desc = "Use the movement stick/WASD to steer; jump goes up and Ctrl/Shift goes down.", Value = STATES.MovementExtras.Fly, Callback = setFly})
    tabs.Movement:Slider({Title = "Fly Speed", Step = 5, Value = {Min = 10, Max = 200, Default = STATES.MovementExtras.FlySpeed}, Callback = function(v) STATES.MovementExtras.FlySpeed = v; task.spawn(saveConfig) end})
    tabs.Movement:Toggle({Title = "Fly FloatingButton", Value = ACTION_FLOATERS.Fly.Enabled, Callback = setFlyFloating})
    tabs.Movement:Toggle({Title = "Lock Fly FloatingButton", Value = ACTION_FLOATERS.Fly.Locked, Callback = function(v) ACTION_FLOATERS.Fly.Locked = v; task.spawn(saveConfig) end})

    tabs.Movement:Section({Title = "Noclip"})
    tabs.Movement:Toggle({Title = "Noclip", Desc = "Disabling restores each part's original collision immediately.", Value = STATES.MovementExtras.Noclip, Callback = setNoclip})
    tabs.Movement:Toggle({Title = "Noclip FloatingButton", Value = ACTION_FLOATERS.Noclip.Enabled, Callback = setNoclipFloating})
    tabs.Movement:Toggle({Title = "Lock Noclip FloatingButton", Value = ACTION_FLOATERS.Noclip.Locked, Callback = function(v) ACTION_FLOATERS.Noclip.Locked = v; task.spawn(saveConfig) end})

    tabs.Movement:Section({Title = "Jump Boost"})
    tabs.Movement:Toggle({Title = "Jump Boost", Desc = "Adds a moderate forward burst when jumping while moving.", Value = STATES.MovementExtras.JumpBoost, Callback = setJumpBoost})
    tabs.Movement:Toggle({Title = "Jump Boost FloatingButton", Value = ACTION_FLOATERS.JumpBoost.Enabled, Callback = setJumpBoostFloating})
    tabs.Movement:Toggle({Title = "Lock Jump Boost FloatingButton", Value = ACTION_FLOATERS.JumpBoost.Locked, Callback = function(v) ACTION_FLOATERS.JumpBoost.Locked = v; task.spawn(saveConfig) end})

    tabs.Movement:Section({Title = "Movement Stats"})
    bindToggle(tabs.Movement, "Speed Walk")
    tabs.Movement:Slider({
        Title = "Walk Speed",
        Step = 1,
        Value = {Min = 16, Max = 116, Default = STATES.Movement.SpeedWalk.Value},
        Callback = function(v)
            STATES.Movement.SpeedWalk.Value = v
            if STATES.Movement.SpeedWalk.Enabled then MOVEMENT.updateWalkSpeed() end
            task.spawn(saveConfig)
        end,
    })
    bindToggle(tabs.Movement, "Jump Power")
    tabs.Movement:Slider({
        Title = "Jump Power",
        Step = 1,
        Value = {Min = 50, Max = 150, Default = STATES.Movement.JumpPower.Value},
        Callback = function(v)
            STATES.Movement.JumpPower.Value = v
            if STATES.Movement.JumpPower.Enabled then MOVEMENT.updateJumpPower() end
            task.spawn(saveConfig)
        end,
    })

    -- Visual
    tabs.Visual:Section({Title = "Player ESP"})
    for _, title in ipairs({"ESP Name", "Murderer Name", "Sheriff Name", "Hero Name", "Innocent Name"}) do
        bindToggle(tabs.Visual, title)
    end
    tabs.Visual:Section({Title = "Highlights"})
    for _, title in ipairs({"ESP Highlight", "ESP Highlight Murderer", "ESP Highlight Sheriff", "ESP Highlight Hero", "ESP Highlight Innocent"}) do
        bindToggle(tabs.Visual, title)
    end
    tabs.Visual:Section({Title = "ESP Lines"})
    for _, title in ipairs({"ESP Tracer", "Murderer Tracer", "Sheriff Tracer", "Hero Tracer", "Innocent Tracer"}) do
        bindToggle(tabs.Visual, title)
    end
    tabs.Visual:Paragraph({Title = "Line behavior", Desc = "ESP Lines disappear when the target leaves your camera viewport and reappear when the target returns."})
    tabs.Visual:Section({Title = "ZXNexus ESP"})
    tabs.Visual:Toggle({Title = "ESP Gun", Value = DROP_ESP.Gun, Callback = function(v) setDropESP("Gun", v); task.spawn(saveConfig) end})
    tabs.Visual:Toggle({Title = "ESP Trap", Value = DROP_ESP.Trap, Callback = function(v) setDropESP("Trap", v); task.spawn(saveConfig) end})
    tabs.Visual:Section({Title = "Hitbox ESP"})
    tabs.Visual:Toggle({Title = "Hitbox ESP", Value = HITBOX_ESP.Enabled, Callback = function(v) HITBOX_ESP.Enabled = v; updateHitboxESP(); task.spawn(saveConfig) end})
    tabs.Visual:Slider({Title = "Hitbox Size", Step = 1, Value = {Min = 2, Max = 16, Default = HITBOX_ESP.Size}, Callback = function(v) HITBOX_ESP.Size = v; if HITBOX_ESP.Enabled then updateHitboxESP() end; task.spawn(saveConfig) end})

    -- Role ESP shortcuts: show the role as a label above the player instead of posting to chat.
    tabs.Innocent:Section({Title = "🎃 Role ESP Labels"})
    tabs.Innocent:Button({Title = "Show Murderer Name in ESP", Icon = "skull", Callback = function()
        ESP_SYSTEM.ESP_STATES.ESPName = true
        ESP_SYSTEM.ESP_STATES.MurdererName = true
        ESP_SYSTEM.updateESP()
        zxNotify("Murderer labels enabled in ESP.", 2)
    end})
    tabs.Innocent:Button({Title = "Show Sheriff Name in ESP", Icon = "crosshair", Callback = function()
        ESP_SYSTEM.ESP_STATES.ESPName = true
        ESP_SYSTEM.ESP_STATES.SheriffName = true
        ESP_SYSTEM.updateESP()
        zxNotify("Sheriff labels enabled in ESP.", 2)
    end})

    -- Sheriff
    tabs.Sheriff:Section({Title = "Shoot Murderer"})
    tabs.Sheriff:Paragraph({Title = "Shoot Murderer", Desc = "Manual shooting and Auto Shoot. Manual Wall Check can be toggled; Auto Shoot always keeps Wall Check enabled."})
    tabs.Sheriff:Toggle({Title = "Auto Shoot", Value = AUTO_SHOOT.Enabled, Callback = function(v)
        setAutoShoot(v)
    end})
    bindToggle(tabs.Sheriff, "Shoot The Murderer")
    tabs.Sheriff:Toggle({Title = "Shoot Wall Check", Value = SHOOT_CONFIG.WallCheck, Callback = function(v) SHOOT_CONFIG.WallCheck = v; task.spawn(saveConfig) end})
    bindToggle(tabs.Sheriff, "Lock Shoot Button")

    tabs.Sheriff:Section({Title = "Camlock"})
    tabs.Sheriff:Toggle({Title = "Camlock", Desc = "Locks the camera to the selected Murderer body part.", Value = AIMLOCK.Enabled, Callback = setAimlock})
    tabs.Sheriff:Dropdown({Title = "Camlock Target", Values = {"Auto", "Murderer", "Sheriff"}, Value = AIMLOCK.TargetRole, Callback = function(v) AIMLOCK.TargetRole = v; task.spawn(saveConfig) end})
    tabs.Sheriff:Dropdown({Title = "Camlock Body Part", Values = {"Head","UpperTorso","LeftUpperArm","RightUpperArm","LeftUpperLeg","RightUpperLeg"}, Value = AIMLOCK.BodyPart, Callback = function(v) AIMLOCK.BodyPart = v; task.spawn(saveConfig) end})
    tabs.Sheriff:Toggle({Title = "Camlock Distance", Value = AIMLOCK.UseDistance, Callback = function(v) AIMLOCK.UseDistance = v; task.spawn(saveConfig) end})
    tabs.Sheriff:Slider({Title = "Camlock Max Distance", Step = 5, Value = {Min = 25, Max = 500, Default = AIMLOCK.MaxDistance}, Callback = function(v) AIMLOCK.MaxDistance = v; task.spawn(saveConfig) end})
    tabs.Sheriff:Toggle({Title = "Camlock Wall Check", Value = AIMLOCK.WallCheck, Callback = function(v) AIMLOCK.WallCheck = v; task.spawn(saveConfig) end})
    tabs.Sheriff:Paragraph({Title = "Camlock + Auto Shoot", Desc = "When Camlock is active, Auto Shoot uses the same camera direction/target point."})

    tabs.Sheriff:Section({Title = "Shoot Prediction"})
    tabs.Sheriff:Paragraph({Title = "YARHM Basic Prediction", Desc = "Shoot uses YARHM's basic velocity + MoveDirection prediction. Recommended Shoot Offset: 2.8.\nOffset-to-ping multiplier default: 1."})
    tabs.Sheriff:Slider({Title = "Shoot Offset", Step = 0.1, Value = {Min = 0, Max = 5, Default = SHOOT_CONFIG.ShootOffset}, Callback = function(v) SHOOT_CONFIG.ShootOffset = v; task.spawn(saveConfig) end})
    tabs.Sheriff:Slider({Title = "Offset-to-Ping Multiplier", Step = 0.1, Value = {Min = 0, Max = 5, Default = SHOOT_CONFIG.OffsetToPingMult}, Callback = function(v) SHOOT_CONFIG.OffsetToPingMult = v; task.spawn(saveConfig) end})

    -- Murderer
    tabs.Murderer:Section({Title = "🎃 Murderer"})
    tabs.Murderer:Section({Title = "🎃 Aimlock"})
    tabs.Murderer:Toggle({Title = "Aimlock Sheriff/Hero", Desc = "Auto-targets the Sheriff when you hold the knife.", Value = AIMLOCK.Enabled, Callback = setAimlock})
    bindToggle(tabs.Murderer, "Auto Kill All (Murderer)")
    tabs.Murderer:Button({Title = "Kill All", Icon = "skull", Callback = function()
        task.defer(function() KILL_ALL.killAllPlayers(true) end)
    end})
    local function killRoleOnce(roleName)
        task.defer(function() KILL_ALL.killAllPlayers(true, roleName) end)
    end
    tabs.Murderer:Button({Title = "Kill Sheriff", Icon = "crosshair", Callback = function() killRoleOnce("Sheriff") end})
    tabs.Murderer:Button({Title = "Kill Hero", Icon = "zap", Callback = function() killRoleOnce("Hero") end})
    tabs.Murderer:Button({Title = "Kill Innocents", Icon = "users", Callback = function() killRoleOnce("Innocent") end})
    tabs.Murderer:Button({Title = "Throw Knife", Icon = "swords", Callback = knifeThrow})
    tabs.Murderer:Toggle({Title = "Auto Throw Knife", Value = KNIFE_THROW.Auto, Callback = setKnifeAuto})
    tabs.Murderer:Toggle({
        Title = "Knife Wall Check",
        Value = KNIFE_THROW.WallCheck,
        Callback = function(v) KNIFE_THROW.WallCheck = v; task.spawn(saveConfig) end,
    })
    tabs.Murderer:Toggle({Title = "Throw Knife FloatingButton", Value = KNIFE_THROW.FloatingEnabled, Callback = setKnifeFloating})
    tabs.Murderer:Toggle({Title = "Lock Throw Knife FloatingButton", Value = KNIFE_THROW.Locked, Callback = function(v) KNIFE_THROW.Locked = v; task.spawn(saveConfig) end})

    -- Innocent
    tabs.Innocent:Section({Title = "Innocent / Get Gun"})
    tabs.Innocent:Paragraph({Title = "Get Gun", Desc = "Use these controls when you are Innocent and want to obtain the dropped gun."})
    bindButton(tabs.Innocent, "Grab Gun", "crosshair")
    tabs.Innocent:Toggle({Title = "Auto Get Gun", Value = AUTO_GET_GUN.Enabled, Callback = setAutoGetGun})
    bindToggle(tabs.Innocent, "GrabGun Button")
    bindToggle(tabs.Innocent, "Lock Grab Gun Button")
    tabs.Innocent:Section({Title = "Fling / Steal"})
    tabs.Innocent:Button({Title = "Fling Sheriff", Icon = "wind", Callback = function()
        local target = ROLE_HELPERS.getSheriffOrHero()
        if target and target ~= player then flingUntilSuccess(target, 5) end
    end})
    tabs.Innocent:Button({Title = "Fling Murderer", Icon = "wind", Callback = function()
        local target = ROLE_HELPERS.getMurderer()
        if target and target ~= player then flingUntilSuccess(target, 5) end
    end})
    tabs.Innocent:Button({Title = "Steal Gun", Icon = "hand", Callback = performStealGun})
    tabs.Innocent:Toggle({Title = "Steal Gun FloatingButton", Value = ACTION_FLOATERS.StealGun.Enabled, Callback = setStealFloating})
    tabs.Innocent:Toggle({Title = "Lock Steal Gun FloatingButton", Value = ACTION_FLOATERS.StealGun.Locked, Callback = function(v) ACTION_FLOATERS.StealGun.Locked = v; task.spawn(saveConfig) end})

    -- Optimization
    tabs.Optimization:Paragraph({
        Title = "Coming Soon",
        Desc = "Additional optimization and performance features are coming soon.",
    })
    tabs.Optimization:Section({Title = "Available"})
    tabs.Optimization:Button({Title = "Remove OFX", Icon = "sparkles", Callback = removeOFX})
    tabs.Optimization:Paragraph({Title = "Remove OFX Note", Desc = "This is permanent for the current session. Leave the game to restore the original visuals."})
    tabs.Optimization:Toggle({
        Title = "Anti-Fling",
        Desc = "ZXNexus anti-fling implementation.",
        Value = false,
        Callback = function(v)
            if v then ZXNexus_ANTI_FLING.enable() else ZXNexus_ANTI_FLING.disable() end
            task.spawn(saveConfig)
        end,
    })
    bindToggle(tabs.Optimization, "Anti-AFK (every 5 min)")
    bindToggle(tabs.Optimization, "Mute Radio")
    bindToggle(tabs.Optimization, "Performance (Ping & Fps)")

    -- Teleport
    tabs.Teleport:Section({Title = "Servers"})
    tabs.Teleport:Button({Title = "Rejoin Current Server", Icon = "refresh-cw", Callback = UTILS.rejoinServer})
    tabs.Teleport:Button({Title = "Server Hop", Icon = "shuffle", Callback = UTILS.joinAnotherServer})
    tabs.Teleport:Section({Title = "Location"})
    tabs.Teleport:Button({Title = "Teleport to Map", Icon = "map", Callback = function()
        local ok = UTILS.teleportToMap()
        if not ok then zxNotify("Map spawn not found.", 1.7) end
    end})
    tabs.Teleport:Button({Title = "Teleport to Lobby", Icon = "home", Callback = function()
        local ok = UTILS.teleportToLobby()
        if not ok then zxNotify("Lobby spawn not found.", 1.7) end
    end})
    tabs.Teleport:Paragraph({Title = "Rejoin", Desc = "Returns to the exact current server instance."})
    tabs.Teleport:Paragraph({Title = "Server Hop", Desc = "Finds another public server for the same game."})

    -- Auto Farm
    tabs.AutoFarm:Section({Title = "🎃 Halloween Farm"})
    bindToggle(tabs.AutoFarm, "Auto Farm")
    tabs.AutoFarm:Toggle({Title = "🎃 Candy Farm Mode", Desc = "Prioritizes candy pickups during the Halloween event.", Value = STATES.AutoFarm.CandyMode, Callback = function(v)
        STATES.AutoFarm.CandyMode = v
        STATES.AutoFarm.BagFull = false
        if STATES.AutoFarm.Enabled then STATES.AutoFarm.Farming = FARMING.isRoundActive() end
        task.spawn(saveConfig)
    end})
    tabs.AutoFarm:Toggle({Title = "Reset at 50 Candies", Desc = "Resets your character when the candy counter reaches 50, then resumes farming.", Value = STATES.AutoFarm.AutoResetAt50, Callback = function(v)
        STATES.AutoFarm.AutoResetAt50 = v
        task.spawn(saveConfig)
    end})
    tabs.AutoFarm:Paragraph({Title = "Full Bag", Desc = "Candy reset is optional and only runs in Candy Farm Mode when the counter reaches 50."})
    tabs.AutoFarm:Toggle({Title = "Fling Murderer", Value = STATES.AutoFarm.FlingMurderer, Callback = function(v) STATES.AutoFarm.FlingMurderer = v; task.spawn(saveConfig) end})
    tabs.AutoFarm:Toggle({Title = "Kill All", Value = STATES.AutoFarm.KillAll, Callback = function(v) STATES.AutoFarm.KillAll = v; STATES.KillAll.Enabled = v; task.spawn(saveConfig) end})

    -- Emote
    tabs.Emote:Paragraph({
        Title = "Emote",
        Desc = "Emote functionality will be added later. Coming soon.",
    })

    -- Misc / FloatingButtons
    tabs.Misc:Section({Title = "Bomb Jump"})
    bindToggle(tabs.Misc, "Fake Bomb Jump Button")
    bindToggle(tabs.Misc, "Lock Fake Bomb Button")

    local function addFloatingStyleControls(tab, title, state, d)
        tab:Section({Title = title})
        tab:Slider({Title = "Width", Step = 2, Value = {Min = 40, Max = 300, Default = state.Size}, Callback = function(v)
            state.Size = v
            if d() then d().frame.Size = UDim2.fromOffset(v, state.Height); applyFloatingShape(d().frame, state.Shape, math.max(state.Size, state.Height)) end
            task.spawn(saveConfig, true)
        end})
        tab:Slider({Title = "Height", Step = 2, Value = {Min = 40, Max = 160, Default = state.Height}, Callback = function(v)
            state.Height = v
            if d() then d().frame.Size = UDim2.fromOffset(state.Size, v); applyFloatingShape(d().frame, state.Shape, math.max(state.Size, state.Height)) end
            task.spawn(saveConfig, true)
        end})
        tab:Dropdown({Title = "Shape", Values = {"Circle", "Square", "Rectangle"}, Value = state.Shape, Callback = function(v)
            state.Shape = v
            if d() then applyFloatingShape(d().frame, v, math.max(state.Size, state.Height)) end
            task.spawn(saveConfig, true)
        end})
        tab:Input({Title = "Button Text", Placeholder = state.Text or "Text displayed on button", Callback = function(v)
            state.Text = tostring(v or "")
            local data = d()
            if data and data.frame then
                local labelName = state == FLOATING_STYLES.FakeBombJump and "BombText"
                    or state == FLOATING_STYLES.GrabGun and "GunText"
                    or nil
                local label = labelName and data.frame:FindFirstChild(labelName, true)
                if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
                    label.Text = state.Text
                else
                    for _, child in ipairs(data.frame:GetDescendants()) do
                        if child:IsA("TextLabel") then child.Text = state.Text; break end
                    end
                end
            end
            task.spawn(saveConfig, true)
        end})
    end

    addFloatingStyleControls(tabs.Misc, "Shoot Murderer FloatingButton", FLOATING_STYLES.ShootMurderer, function() return STATES.ShootMurderer.ButtonData end)
    addFloatingStyleControls(tabs.Misc, "Fake Bomb Jump FloatingButton", FLOATING_STYLES.FakeBombJump, function() return STATES.FakeBombJump.ButtonData end)
    addFloatingStyleControls(tabs.Misc, "Get Gun FloatingButton", FLOATING_STYLES.GrabGun, function() return STATES.GrabGun.ButtonData end)
    addFloatingStyleControls(tabs.Misc, "Fly FloatingButton", FLOATING_STYLES.Fly, function() return ACTION_FLOATERS.Fly.Button end)
    addFloatingStyleControls(tabs.Misc, "Noclip FloatingButton", FLOATING_STYLES.Noclip, function() return ACTION_FLOATERS.Noclip.Button end)
    addFloatingStyleControls(tabs.Misc, "Jump Boost FloatingButton", FLOATING_STYLES.JumpBoost, function() return ACTION_FLOATERS.JumpBoost.Button end)
    addFloatingStyleControls(tabs.Misc, "Steal Gun FloatingButton", FLOATING_STYLES.StealGun, function() return ACTION_FLOATERS.StealGun.Button end)
    tabs.Misc:Section({Title = "Knife Throw FloatingButton"})
    tabs.Misc:Slider({Title = "Knife Width", Step = 2, Value = {Min = 40, Max = 120, Default = 40}, Callback = function(v)
        if KNIFE_THROW.FloatingButton then KNIFE_THROW.FloatingButton.frame.Size = UDim2.fromOffset(v, KNIFE_THROW.FloatingButton.frame.Size.Y.Offset) end
    end})
    tabs.Misc:Slider({Title = "Knife Height", Step = 2, Value = {Min = 40, Max = 120, Default = 40}, Callback = function(v)
        if KNIFE_THROW.FloatingButton then KNIFE_THROW.FloatingButton.frame.Size = UDim2.fromOffset(KNIFE_THROW.FloatingButton.frame.Size.X.Offset, v) end
    end})
    tabs.Misc:Dropdown({Title = "Knife Shape", Values = {"Circle", "Square", "Rectangle"}, Value = "Circle", Callback = function(v)
        if KNIFE_THROW.FloatingButton then applyFloatingShape(KNIFE_THROW.FloatingButton.frame, v, math.max(KNIFE_THROW.FloatingButton.frame.Size.X.Offset, KNIFE_THROW.FloatingButton.frame.Size.Y.Offset)) end
        task.spawn(saveConfig)
    end})

    tabs.Misc:Section({Title = "Keybinds"})
    for _, name in ipairs({"ToggleUI","ShootMurderer","ThrowKnife","Bomb","Extra1","Extra2"}) do
        local keyName = keybindTitles[name]
        tabs.Misc:Button({
            Title = keyName .. " [" .. keybindLabel(name) .. "]",
            Icon = "keyboard",
            Callback = function()
                captureKeybind(name)
            end,
        })
    end
    tabs.Misc:Paragraph({
        Title = "Keybinds",
        Desc = "Tap a keybind button above, then press the new keyboard key. Mappings are saved locally.",
    })


    -- Music: native UI/Boombox scan + direct playback.
    local musicIds = {}
    local musicSound = nil
    local musicLooping = false
    local musicEndedConnection = nil
    local musicInputValue = ""
    local function scanNativeMusicIds()
        local found = {}
        local seen = {}
        local function add(id)
            id = tostring(id or ""):match("(%d+)")
            if id and not seen[id] then seen[id] = true; table.insert(found, id) end
        end
        for _, root in ipairs({player:FindFirstChildOfClass("PlayerGui"), player:FindFirstChild("PlayerGui")}) do
            if root then
                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("Sound") then
                        local sid = tostring(d.SoundId):match("(%d+)")
                        if sid then add(sid) end
                    elseif d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                        local text = tostring(d.Text or "")
                        if text:lower():find("music") or text:lower():find("boombox") or text:lower():find("radio") then
                            for id in text:gmatch("%d%d%d%d%d%d%d+") do add(id) end
                        end
                    end
                end
            end
        end
        musicIds = found
        return found
    end
    local function disconnectMusicLoop()
        if musicEndedConnection then
            pcall(function() musicEndedConnection:Disconnect() end)
            musicEndedConnection = nil
        end
    end

    local function stopMusic()
        disconnectMusicLoop()
        if musicSound then
            pcall(function() musicSound:Stop() end)
            pcall(function() musicSound:Destroy() end)
            musicSound = nil
        end
    end

    local function playMusic(id)
        id = tostring(id or ""):match("%d+")
        if not id then return end
        stopMusic()
        musicSound = Instance.new("Sound")
        musicSound.Name = "ZXNexusMusic"
        musicSound.SoundId = "rbxassetid://" .. id
        musicSound.Volume = 1
        musicSound.Parent = SoundService

        if musicLooping then
            musicEndedConnection = musicSound.Ended:Connect(function()
                if musicLooping and musicSound and musicSound.Parent then
                    pcall(function()
                        musicSound.TimePosition = 0
                        musicSound:Play()
                    end)
                end
            end)
        end
        pcall(function() musicSound:Play() end)
    end

    local function setMusicLooping(enabled)
        musicLooping = enabled == true
        disconnectMusicLoop()
        if musicLooping and musicSound then
            musicEndedConnection = musicSound.Ended:Connect(function()
                if musicLooping and musicSound and musicSound.Parent then
                    pcall(function()
                        musicSound.TimePosition = 0
                        musicSound:Play()
                    end)
                end
            end)
        end
    end

    tabs.Music:Section({Title = "Boombox / Music"})
    tabs.Music:Input({Title = "Music ID", Placeholder = "Enter Roblox audio ID", Callback = function(v) musicInputValue = tostring(v) end})
    tabs.Music:Button({Title = "Play", Icon = "play", Callback = function() playMusic(musicInputValue) end})
    tabs.Music:Button({Title = "Replay", Icon = "rotate-ccw", Callback = function() if musicInputValue ~= "" then playMusic(musicInputValue) end end})
    tabs.Music:Toggle({Title = "Looping This Music", Value = musicLooping, Callback = function(v)
        setMusicLooping(v)
    end})
    tabs.Music:Button({Title = "Stop Looping", Icon = "repeat-1", Callback = function()
        setMusicLooping(false)
    end})
    tabs.Music:Button({Title = "Stop", Icon = "square", Callback = stopMusic})
    tabs.Music:Button({Title = "Refresh Native Music List", Icon = "refresh-cw", Callback = function()
        local ids = scanNativeMusicIds()
        zxNotify(#ids > 0 and (tostring(#ids) .. " audio IDs found.") or "No audio IDs found.", 1.5)
    end})
    tabs.Music:Paragraph({Title = "Native list", Desc = "The scanner reads visible Boombox/Radio UI and Sound objects from the game's PlayerGui. Use Refresh to rescan."})

    tabs.Misc:Section({Title = "Save Management"})
    tabs.Misc:Button({Title = "Create / Update Save", Icon = "save", Callback = function()
        if saveConfig(true) then
            zxNotify("Save created / updated.", 1.5)
        else
            zxNotify("Save API unavailable.", 1.5)
        end
    end})
    tabs.Misc:Button({Title = "Load Settings", Icon = "folder-open", Callback = function()
        if loadConfig() then
            applyLoadedSettings()
            zxNotify("Settings loaded.", 1.5)
        else
            zxNotify("No save found.", 1.5)
        end
    end})
    tabs.Misc:Button({Title = "Delete Save", Icon = "trash-2", Callback = function()
        local canRead = type(readfile) == "function"
        local exists = false
        if canRead then exists = pcall(function() return readfile(CONFIG.CONFIG_FILE) end) end
        if type(delfile) == "function" and exists then
            local deleted = pcall(delfile, CONFIG.CONFIG_FILE)
            zxNotify(deleted and "Save deleted." or "Could not delete save.", 1.5)
        else
            zxNotify("No save found or delete API unavailable.", 1.5)
        end
    end})

    Window:Tag({Title = "MM2", Icon = "gamepad-2", Border = true})

    if configLoadedAtStartup then
        task.defer(function()
            applyLoadedSettings()
            zxNotify("Saved settings restored.", 1.6)
        end)
    end

    -- The legacy bridge stays disabled; WindUI is the visible interface.
    UI_ELEMENTS.MainFrame = nil

    return Window, legacyGui
end

local function init()
    local screenGui, openCloseGui = UI_SYSTEM.init()

    REMOTE_SYSTEM.findRemoteEvents()
    REMOTE_SYSTEM.connectRemoteEvents()

    FARMING.startFarmingLoop()
    KILL_ALL.startKillAllLoop()

    player.CharacterAdded:Connect(function(character)
        character:WaitForChild("Humanoid")
        task.wait(0.1)
        MOVEMENT.updateWalkSpeed()
        MOVEMENT.updateJumpPower()
    end)

    if player.Character and player.Character:FindFirstChild("Humanoid") then
        MOVEMENT.updateWalkSpeed()
        MOVEMENT.updateJumpPower()
    end

    local espConnection
    local highlightConnection

    espConnection = RunService.Heartbeat:Connect(function()
        if ESP_SYSTEM.ESP_STATES.ESPName then
            ESP_SYSTEM.updateESP()
        else
            ESP_SYSTEM.clearAllESP()
        end
    end)

    highlightConnection = RunService.Heartbeat:Connect(function()
        if ESP_SYSTEM.ESP_HIGHLIGHT_STATES.ESPHighlight then
            ESP_SYSTEM.updateHighlights()
        else
            ESP_SYSTEM.clearAllHighlights()
        end
    end)

    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then
            ESP_SYSTEM.initializePlayer(targetPlayer)
        end
    end

    Players.PlayerAdded:Connect(function(targetPlayer)
        if targetPlayer ~= player then
            ESP_SYSTEM.initializePlayer(targetPlayer)
        end
    end)

    Players.PlayerRemoving:Connect(function(targetPlayer)
        if targetPlayer ~= player then
            ESP_SYSTEM.removePlayerBillboard(targetPlayer)
            ESP_SYSTEM.removePlayerHighlight(targetPlayer)
            ESP_SYSTEM.RemoveLineForPlayer(targetPlayer.Name)
        end
    end)

    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        ESP_SYSTEM.Camera = workspace.CurrentCamera
    end)
    
    Players.PlayerAdded:Connect(function(newPlayer)
        if newPlayer ~= player and ESP_SYSTEM.ESP_LINE_STATES.ESPLine then
            local conn = ESP_SYSTEM.InitializePlayerLines(newPlayer)
            table.insert(lineConnections, conn)
        end
    end)

    task.spawn(sendLoadWebhook)
    task.spawn(function()
        while task.wait(1) do
            if HITBOX_ESP.Enabled then updateHitboxESP() end
            if DROP_ESP.Gun or DROP_ESP.Trap then refreshDropESP() end
        end
    end)

    return screenGui, openCloseGui
end

return init()
