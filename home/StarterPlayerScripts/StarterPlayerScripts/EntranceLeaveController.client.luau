-- V1.1.1：倒计时期间显示 LeaveButton 并驱动倒计时文本，点击 Leave 请求服务端强制离场
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local main = playerGui:WaitForChild("Main")
local leaveButtonFrame = main:WaitForChild("LeaveButton")
local leaveButton = leaveButtonFrame:WaitForChild("Leave")
local countdownLabel = leaveButtonFrame:WaitForChild("CoundownTime")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local homeRemotesFolder = remotesFolder:WaitForChild("Home")
local countdownSyncRemote = homeRemotesFolder:WaitForChild("EntranceCountdownSync")
local requestLeaveRemote = homeRemotesFolder:WaitForChild("RequestLeaveEntrance")

local countdownEndTime = nil
local heartbeatConnection = nil

local function stopCountdownDisplay()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	countdownEndTime = nil
	leaveButtonFrame.Visible = false
end

local function startCountdownDisplay(duration)
	countdownEndTime = os.clock() + duration
	leaveButtonFrame.Visible = true

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if not countdownEndTime then
			return
		end
		local remaining = math.max(0, math.ceil(countdownEndTime - os.clock()))
		countdownLabel.Text = remaining .. "S"
	end)
end

countdownSyncRemote.OnClientEvent:Connect(function(isActive, duration)
	if isActive then
		startCountdownDisplay(duration)
	else
		stopCountdownDisplay()
	end
end)

leaveButton.Activated:Connect(function()
	requestLeaveRemote:FireServer()
end)

leaveButtonFrame.Visible = false
