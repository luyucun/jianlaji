-- V1.1.1：支持多个同名 Entrance_Solo 各自独立占用/倒计时/传送；倒计时中可随时离开；占用期间用碰撞组隔离挡住其他玩家。
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BATTLE_PLACE_ID = 78013815855891
local COUNTDOWN_SECONDS = 5
local WALL_THICKNESS = 1
local WALL_HEIGHT = 8

local WALL_GROUP = "EntranceWall"
local OCCUPANT_GROUP = "EntranceOccupant"
local DEFAULT_GROUP = "Default"
local IDLE_TEXT = "0/1"
local OCCUPIED_TEXT = "1/1"
local OCCUPIED_COLOR = Color3.fromRGB(0, 200, 0)

-- 碰撞组名重复注册会报错，Studio 反复 Playtest 时用 pcall 吞掉重复注册的错误
pcall(function()
	PhysicsService:RegisterCollisionGroup(WALL_GROUP)
end)
pcall(function()
	PhysicsService:RegisterCollisionGroup(OCCUPANT_GROUP)
end)
PhysicsService:CollisionGroupSetCollidable(WALL_GROUP, OCCUPANT_GROUP, false)

-- Remotes：ReplicatedStorage/Remotes/Home 下的 RemoteEvent 是非脚本实例，Script Sync 不同步，用代码保证存在
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local homeRemotesFolder = remotesFolder:FindFirstChild("Home")
if not homeRemotesFolder then
	homeRemotesFolder = Instance.new("Folder")
	homeRemotesFolder.Name = "Home"
	homeRemotesFolder.Parent = remotesFolder
end

local function ensureRemoteEvent(name)
	local existing = homeRemotesFolder:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = homeRemotesFolder
	return remote
end

local countdownSyncRemote = ensureRemoteEvent("EntranceCountdownSync")
local requestLeaveRemote = ensureRemoteEvent("RequestLeaveEntrance")

local entrancesFolder = workspace.Base.RoundEntrances

-- 每个 Entrance_Solo 实例独立维护一份状态：{ occupant, startTime, walls, tipsLabel, idleColor }
local entranceStates = {}

local function getTipsLabel(entrance)
	local tips = entrance:FindFirstChild("Tips")
	local state = tips and tips:FindFirstChild("State")
	local label = state and state:FindFirstChild("TextLabel")
	return label
end

local function initEntranceState(entrance)
	local label = getTipsLabel(entrance)
	local idleColor = label and label.TextColor3 or Color3.new(1, 1, 1)

	entranceStates[entrance] = {
		occupant = nil,
		startTime = nil,
		walls = {},
		tipsLabel = label,
		idleColor = idleColor,
	}

	if label then
		label.Text = IDLE_TEXT
		label.TextColor3 = idleColor
	end
end

local function isSoloEntrance(instance)
	return instance.Name == "Entrance_Solo" and instance:IsA("BasePart")
end

for _, entrance in ipairs(entrancesFolder:GetChildren()) do
	if isSoloEntrance(entrance) then
		initEntranceState(entrance)
	end
end

entrancesFolder.ChildAdded:Connect(function(child)
	if isSoloEntrance(child) then
		initEntranceState(child)
	end
end)

entrancesFolder.ChildRemoved:Connect(function(child)
	entranceStates[child] = nil
end)

local function isInEntrance(entrance, player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end

	local relative = entrance.CFrame:PointToObjectSpace(rootPart.Position)
	local halfSize = entrance.Size / 2

	return math.abs(relative.X) <= halfSize.X
		and math.abs(relative.Z) <= halfSize.Z
		and relative.Y >= -halfSize.Y - 2
		and relative.Y <= halfSize.Y + 6
end

local function setCharacterCollisionGroup(character, groupName)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = groupName
		end
	end
end

-- 在入口四周生成4块不可见挡板，把入口围起来挡住场上其他玩家（占用者本人的碰撞组被单独设成跟挡板不碰撞，可以自由出入）
local function createWalls(entrance)
	local halfSize = entrance.Size / 2
	local walls = {}

	local sides = {
		{ offset = Vector3.new(halfSize.X + WALL_THICKNESS / 2, 0, 0), size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, entrance.Size.Z + WALL_THICKNESS * 2) },
		{ offset = Vector3.new(-(halfSize.X + WALL_THICKNESS / 2), 0, 0), size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, entrance.Size.Z + WALL_THICKNESS * 2) },
		{ offset = Vector3.new(0, 0, halfSize.Z + WALL_THICKNESS / 2), size = Vector3.new(entrance.Size.X + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS) },
		{ offset = Vector3.new(0, 0, -(halfSize.Z + WALL_THICKNESS / 2)), size = Vector3.new(entrance.Size.X + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS) },
	}

	for i, side in ipairs(sides) do
		local wall = Instance.new("Part")
		wall.Name = "EntranceWall_" .. i
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanQuery = false
		wall.Transparency = 1
		wall.CollisionGroup = WALL_GROUP
		wall.Size = side.size
		wall.CFrame = entrance.CFrame * CFrame.new(side.offset + Vector3.new(0, WALL_HEIGHT / 2, 0))
		wall.Parent = workspace
		table.insert(walls, wall)
	end

	return walls
end

local function destroyWalls(state)
	for _, wall in ipairs(state.walls) do
		wall:Destroy()
	end
	state.walls = {}
end

local function setTips(state, text, color)
	if state.tipsLabel then
		state.tipsLabel.Text = text
		state.tipsLabel.TextColor3 = color
	end
end

local function occupyEntrance(entrance, state, player)
	state.occupant = player
	state.startTime = os.clock()
	state.walls = createWalls(entrance)
	setTips(state, OCCUPIED_TEXT, OCCUPIED_COLOR)

	local character = player.Character
	if character then
		setCharacterCollisionGroup(character, OCCUPANT_GROUP)
	end

	countdownSyncRemote:FireClient(player, true, COUNTDOWN_SECONDS)
end

local function releaseEntrance(entrance, state)
	local occupant = state.occupant
	state.occupant = nil
	state.startTime = nil
	destroyWalls(state)
	setTips(state, IDLE_TEXT, state.idleColor)

	if occupant then
		local character = occupant.Character
		if character then
			setCharacterCollisionGroup(character, DEFAULT_GROUP)
		end
		if occupant.Parent then
			countdownSyncRemote:FireClient(occupant, false, 0)
		end
	end
end

local function teleportOccupant(entrance, state)
	local player = state.occupant
	releaseEntrance(entrance, state)

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(BATTLE_PLACE_ID, { player })
	end)

	if not ok then
		warn(("传送玩家 %s 到对局 Place 失败: %s"):format(player.Name, tostring(err)))
	end
end

RunService.Heartbeat:Connect(function()
	for entrance, state in pairs(entranceStates) do
		if state.occupant then
			local player = state.occupant
			if player.Parent and isInEntrance(entrance, player) then
				if os.clock() - state.startTime >= COUNTDOWN_SECONDS then
					teleportOccupant(entrance, state)
				end
			else
				releaseEntrance(entrance, state)
			end
		else
			for _, player in ipairs(Players:GetPlayers()) do
				if isInEntrance(entrance, player) then
					occupyEntrance(entrance, state, player)
					break
				end
			end
		end
	end
end)

requestLeaveRemote.OnServerEvent:Connect(function(player)
	for entrance, state in pairs(entranceStates) do
		if state.occupant == player then
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local pushDirection = entrance.CFrame.LookVector
				local targetPosition = entrance.Position + pushDirection * (entrance.Size.Z + 6)
				character:PivotTo(CFrame.new(targetPosition, targetPosition + pushDirection))
			end
			releaseEntrance(entrance, state)
			break
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for entrance, state in pairs(entranceStates) do
		if state.occupant == player then
			releaseEntrance(entrance, state)
			break
		end
	end
end)
