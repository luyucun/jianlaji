-- V1.1：玩家进入 Entrance_Solo 范围后停留5秒，传送至对局 Place。策划案范围内只做单人局，其余入口不处理。
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BATTLE_PLACE_ID = 78013815855891
local COUNTDOWN_SECONDS = 5

local entrancePart = workspace.Base.RoundEntrances.Entrance_Solo

local enterTimes = {}
local teleporting = {}

local function isInEntrance(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end

	local relative = entrancePart.CFrame:PointToObjectSpace(rootPart.Position)
	local halfSize = entrancePart.Size / 2

	return math.abs(relative.X) <= halfSize.X
		and math.abs(relative.Z) <= halfSize.Z
		and relative.Y >= -halfSize.Y - 2
		and relative.Y <= halfSize.Y + 6
end

local function teleportPlayer(player)
	teleporting[player] = true
	enterTimes[player] = nil

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(BATTLE_PLACE_ID, { player })
	end)

	if not ok then
		warn(("传送玩家 %s 到对局 Place 失败: %s"):format(player.Name, tostring(err)))
		teleporting[player] = nil
	end
end

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		if not teleporting[player] then
			if isInEntrance(player) then
				local startTime = enterTimes[player]
				if not startTime then
					enterTimes[player] = os.clock()
				elseif os.clock() - startTime >= COUNTDOWN_SECONDS then
					teleportPlayer(player)
				end
			else
				enterTimes[player] = nil
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	enterTimes[player] = nil
	teleporting[player] = nil
end)
