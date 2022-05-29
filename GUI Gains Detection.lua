--Causes a little bit of lag
--Saves the file in the workspace folder
local logRun = true

--NOTE: Gain guessing is automatic. Only use this for testing
--Do not use results given with a changed value
local gains = 2.7

-- Where it should warn about fps limit
local fpsWarnAt = 600

--Disable to prevent auto-scanning when spectating a bot
_G.AutoScan = true

print("--{", tick(), "}-- > Loading")

local botManager, movement, NWVars, styles, remote
local cos = math.cos
local sin = math.sin
local insert = table.insert

for _, t in next, getgc(true) do
	if type(t) == "table" then
		if rawget(t, "Bots") then
			botManager = t
		end
		if rawget(t, "GetPlayerFrames") then
			movement = t
		end
		if rawget(t, "GetNWInt") then
			NWVars = t
		end
		if rawget(t, "GetStyle") then
			styles = t
		end
		if rawget(t, "Add") and rawget(t, "InitLast") then
			remote = t
		end
	end
end

--[[
	frames[1] == {1:Tick,2:Position,3:Velocity,4:?}
	frames[1] is every physics tick (0.01)
	frames[2] == {1:Tick,2:Angles}
	frames[2] is every frame of the runner (presumably) (Varies in length)
	frames[3] == {1:?,2:Gravity}
	frames[3] only occurs once
	frames[4] == {1:Time,2:HeldKeys}
	frames[4] only updates when theres a change of keys
]]

local function map()
	return workspace:FindFirstChild("DisplayName", true).Parent
end

local function numToKeys(number, keys)
	local returnKeys = {}

	for i, v in next, {" ", "d", "s", "a", "w"} do
		local keyPower = 2 ^ (5 - i)
		if number - keyPower >= 0 then
			returnKeys[v] = 1
			number = number - keyPower
		else
			returnKeys[v] = 0
		end
	end

	for key, valid in next, keys do --Ignore invalid/impossible keys
		returnKeys[key] = math.min(returnKeys[key], valid)
	end

	return returnKeys
end

local function round(n)
	-- Accurate to 4 decimal places, good enough
	return math.round(n * 1e5) / 1e5
end

local function isNaN(n)
	return n ~= n -- NaN is the only number that isn't equal to itself
end

local function UPS(v)
	return (v.X * v.X + v.Z * v.Z) ^ 0.5
end

local dot = Vector3.new().Dot

local function calculateGains(speed, angles)
	local var = dot(speed, angles)

	if not (var < gains) then
		return speed
	end

	return speed + (gains - var) * angles
end

local function guessGains(lastVel, curVel, angles)
	return round(((curVel - lastVel).X / angles.X + dot(lastVel, angles)) / 2.7)
end

local results = {}

local function checkBot(botID)
	local botInstance = botManager.GetBotFromId(botID)
	local frames = movement.GetPlayerFrames(botInstance)

	if not frames then
		return
	end

	local style = styles.Type[NWVars.GetNWInt(botInstance, "Style")]
	local logText = tick() .. "\n" .. gains .. "\n" .. #frames[1] .. "\nL=Last\nC=Current\nP=Predicted\nBT=Bot Tick"

	local indexedAngles = {}
	local FPSValues = {}
	local warns = 0
	local fpsStats = {min=9e9, mint=0, max=0, maxt=0}
	local startTime = frames[1][1][1]

	for i, t in next, frames[2] do
		local prevFrame = frames[2][i - 1]

		if prevFrame then
			local roundedTick = round(t[1] - startTime)
			local curFPS = 1 / (t[1] - prevFrame[1])

			if curFPS > fpsWarnAt then
				warns = warns + 1

				if warns <= 20 then
					warn(botInstance.Name, "just hit", curFPS, "FPS (Warning threshold:", fpsWarnAt, ") on tick", roundedTick)
				elseif warns == 21 then
					warn(botInstance.Name, "passed maximum warn limit for FPS of 20 on", roundedTick)
				end
			end

			insert(FPSValues, curFPS)

			if curFPS < fpsStats.min then
				fpsStats.min = curFPS
				fpsStats.mint = roundedTick
			end

			if curFPS > fpsStats.max then
				fpsStats.max = curFPS
				fpsStats.maxt = roundedTick
			end
		end

		local floored = math.floor(t[1] * 5)

		if not indexedAngles[floored] then
			indexedAngles[floored] = {}
		end

		insert(indexedAngles[floored], t)
	end

	local lastVel
	local tickCount, accurateCount, failedTicks = 0, 0, 0
	local accuracyScore = {}
	local gainGuesses = {}
	local suspectedGains = {}
	local calculationStart = tick()
	local frames1Len = #frames[1]

	for i, t in next, frames[1] do
		if i % 1000 == 0 then
			if i % 5000 == 0 then
				print("--{", tick(), "}-- > Calculating:", i / frames1Len * 100 .. "%")
			end
			task.wait(0.1)
		end

		local curTick = t[1]

		if curTick < 1 then continue end

		local roundedTick = round(curTick)
		local curVel = t[3]

		if not lastVel then
			lastVel = curVel

			continue
		end

		local angleBefore, angleAfter
		local floored = math.floor(curTick * 5)

		for a = -1, 1, 1 do
			a = floored + a

			if indexedAngles[a] then
				for _, v in next, indexedAngles[a] do
					if v[1] < curTick then
						angleBefore = v
					else
						angleAfter = v
						break
					end
				end
			end

			if angleAfter then
				break
			end
		end

		if not angleBefore or not angleAfter then
			failedTicks = failedTicks + 1
			lastVel = curVel

			logText = logText .. "\nBT: " .. roundedTick .. "\nBroken Tick"

			continue
		end

		local heldKeys
		for _, v in next, frames[4] do
			if v[1] < curTick then
				heldKeys = v[2]
			else
				break
			end
		end

		local keys = numToKeys(heldKeys, style["keys"])
		local curAngle = angleBefore[2]:Lerp(angleAfter[2], (-angleBefore[1] + curTick) / (angleAfter[1] - angleBefore[1]))
		local yCos = cos(curAngle.Y)
		local ySin = sin(curAngle.Y)
		local SmW = keys["s"] - keys["w"]
		local DmA = keys["d"] - keys["a"]
		local projectedGain = Vector3.new(DmA * yCos + SmW * ySin, 0, SmW * yCos - DmA * ySin).unit

		if isNaN(projectedGain.X) then
			lastVel = curVel

			logText = logText .. "\nBT: " .. roundedTick .. "\nNo Relevant Movement"

			continue
		end

		local projectedUPS = UPS(calculateGains(lastVel, projectedGain))
		local curUPS = UPS(curVel)
		logText = logText ..
				"\nBT: " .. roundedTick ..
				"\nL UPS: " .. UPS(lastVel) ..
				"\nC UPS: " .. curUPS ..
				"\nP UPS: " .. projectedUPS

		local guessedGains = (curUPS == projectedUPS and 1) or guessGains(lastVel, curVel, projectedGain)

		if not suspectedGains[guessedGains] then
			suspectedGains[guessedGains] = 0
		end

		suspectedGains[guessedGains] = suspectedGains[guessedGains] + 1
		logText = logText .. "\nGains Guess: " .. guessedGains

		lastVel = curVel
		tickCount = tickCount + 1
		accurateCount = accurateCount + (curUPS == projectedUPS and 1 or 0)
		insert(accuracyScore, accurateCount / tickCount)
		gainGuesses[roundedTick] = guessedGains
	end

	local totalFPS = 0
	local squareTotalFPS = 0

	for _, x in next, FPSValues do
		totalFPS = totalFPS + x
		squareTotalFPS = squareTotalFPS + x ^ 2
	end

	local meanFPS = totalFPS / #FPSValues
	local stdDevFPS = ((squareTotalFPS - totalFPS ^ 2 / #FPSValues) / (#FPSValues - 1)) ^ 0.5
	local calculationTime = tick() - calculationStart

	print("Calculation time:", calculationTime)
	logText = logText .. "\nCalculation time: " .. calculationTime .. "\n"

	local summaryMessage = "Summary for " .. botInstance.Name .. " (ID " .. botID .. ") (" .. gains .. ")" ..
		"\nMap:            " .. map().DisplayName.Value .. " / " .. map().name ..
		"\nStyle:          " .. style.name ..
		"\nChecked Ticks:  " .. tickCount ..
		"\nAccurate Ticks: " .. accurateCount ..
		"\nBroken Ticks:   " .. failedTicks ..
		"\nAverage FPS:    " .. meanFPS ..
		"\nstdDev FPS:     " .. stdDevFPS ..
		"\nMinimum FPS:    " .. fpsStats.min .. " (" .. fpsStats.mint .. ")" ..
		"\nMaximum FPS:    " .. fpsStats.max .. " (" .. fpsStats.maxt .. ")" ..
		"\n>" .. fpsWarnAt .."FPS Frames: " .. warns .. " / " .. #frames[2] ..
		"\nAccuracy%:      " .. accurateCount / tickCount * 100

	print(summaryMessage)
	logText = logText .. summaryMessage

	if accurateCount / tickCount < 0.5 then --Not looking good
		local totalWeight = 0
		local bestValue = {0, 0}

		for guess, weight in next, suspectedGains do
			totalWeight = totalWeight + weight

			if weight > bestValue[2] then
				bestValue = {guess, weight}
			end
		end

		local extraMessage = "\nExtra Info for " .. botInstance.Name .. " (ID " .. botID .. ")" ..
			"\nAccuracy% mid way (" .. math.floor(#accuracyScore / 2) / 100 .."): " .. accuracyScore[math.floor(#accuracyScore / 2)] * 100 ..
			"\nPredicted Gains:      " .. bestValue[1] .. " (" .. bestValue[1] * gains .. ") at " .. (bestValue[2] / totalWeight) * 100 .. "%"

		warn(extraMessage)
		logText = logText ..  extraMessage
	end

	if writefile and logRun then
		if not isfolder("rbhop-gains-detection") then
			makefolder("rbhop-gains-detection")
		end

		local displayName = map().DisplayName.Value

		-- Parse for invalid characters
		local invalidChars = {"/", "\\", ":", "*", "?", '"', "<", ">", "|"}

		for _, v in next, invalidChars do
			displayName = displayName:gsub(v, "")
		end

		local name = "rbhop-gains-detection/gs-" .. displayName .. "-" .. style.name .. "-" .. botInstance.Name:sub(7)

		if accurateCount / tickCount < 0.5 then
			writefile(name .. "-suspicious.txt", logText)
		else
			writefile(name .. "-legit.txt", logText)
		end
	end

	results[botID] = gainGuesses
	return true
end

local text = Instance.new("TextLabel", Instance.new("ScreenGui", game.CoreGui))
text.Size = UDim2.fromOffset(200, 100)
text.Position = UDim2.new(0.5, -100, 0, 0)
text.TextSize = 30

local specTarget
remote.Subscribe("SetSpectating", function(u)
	specTarget = type(u) == "table" and u
end)

game:GetService("RunService").RenderStepped:Connect(function()
	local gainGuesses = results[specTarget and specTarget.BotId]

	if not (specTarget and gainGuesses) then
		text.Visible = false
		return
	end

	local curTime = math.round(NWVars.GetNWFloat(specTarget, "TimeNow") * 100) / 100 + 1

	if gainGuesses[curTime] then
		if tonumber(gainGuesses[curTime]) then
			text.Text = round(gainGuesses[curTime])
		else
			text.Text = gainGuesses[curTime]
		end

		text.Visible = true
	end
end)

if _G.AutoScan and not _G.Subscribed then
	local scanned = {}

	botManager.BotAdded(function(p)
		if type(p) == "table" and _G.AutoScan and not scanned[p.BotId] then
			print("Autoscan start:", p.BotId)

			while task.wait(0.5) do
				if scanned[p.BotId] then
					break
				end

				if checkBot(p.BotId) then
					scanned[p.BotId] = true
					break
				end

				if not _G.AutoScan then
					break
				end
			end

			print("Autoscan done:", p.BotId)
		end
	end)

	_G.Subscribed = true
end

print("--{", tick(), "}-- > Loaded")
