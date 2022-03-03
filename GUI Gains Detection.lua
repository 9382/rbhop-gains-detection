local logRun = false
--Causes a little bit of lag
--Saves the file in the workspace folder
local gains = 2.7*1
--NOTE: Gain guessing is automatic. Only use this for testing
--Do not use results given with a changed value
_G.AutoScan = true
--Disable to prevent auto-scanning when spectating a bot

print("--{",tick(),"}-- > Loading")
local botManager,movement,NWVars,styles,remote
for _,t in next,getgc(true) do
    if type(t) == "table" then
        if rawget(t,"Bots") then
            botManager =  t
        end
        if rawget(t,"GetPlayerFrames") then
            movement = t
        end
        if rawget(t,"GetNWInt") then
            NWVars = t
        end
        if rawget(t,"GetStyle") then
            styles = t
        end
        if rawget(t,"Add") and rawget(t,"InitLast") then
            remote = t
        end
    end
end
--[[ 
frames[1] == {1:Tick,2:Position,3:Velocity,4:?}
frames[2] == {1:Tick,2:Angles}
frames[3] == {1:?,2:Gravity}
frames[4] == {1:Time,2:HeldKeys}

frames[4] only updates when theres a change of keys
frames[3] only occurs once
frames[2] is every frame of the runner (presumably) (Varies in length)
frames[1] is every physics tick (0.01)
--]]

local function map()
	for _,v in next,workspace:GetChildren() do
		if v:FindFirstChild("DisplayName") then
			return v
		end
	end
end

local function numToKeys(number,keys)
    local returnKeys = {}
    for i,v in next,{" ","d","s","a","w"} do
        local keyPower = 2^(5-i)
        if number-keyPower >= 0 then
            returnKeys[v] = 1
            number = number-keyPower
        else
            returnKeys[v] = 0
        end
    end
    for key,valid in next,keys do --Ignore invalid/impossible keys
        returnKeys[key] = math.min(returnKeys[key],valid)
    end
    return returnKeys
end

local function isnan(n)
    return not(n <= 0) and not(n > 0)
    --Pure stupidity
end
local function UPS(v)
    return (v.X^2+v.Z^2)^.5
end
local dot = Vector3.new().Dot
local function calculateGains(speed,angles,specifiedGains)
    local gains = specifiedGains or gains
    local var = dot(speed,angles)
    if not(var<gains) then
        return speed
    end
    return speed+(gains-var)*angles
end
local function guessGains(lastVel,curUPS,projectedGain)
    local projectedUPS = calculateGains(lastVel,projectedGain)
    projectedUPS = (projectedUPS.X^2+projectedUPS.Z^2)^.5
    -- if projectedUPS > curUPS then
    --     return --Lost speed due to something, irrelevant
    -- end
    local currentGuess = 1
    local iterator = 1
    while true do
        local projectedUPS = calculateGains(lastVel,projectedGain,2.7*currentGuess)
        projectedUPS = (projectedUPS.X^2+projectedUPS.Z^2)^.5
        if projectedUPS == curUPS then
            return currentGuess
        end
        if projectedUPS > curUPS then
            currentGuess -= iterator
            iterator /= 10
            if iterator == 0.00001 then
                if currentGuess <= 0 then
                    return "Less than\n0"
                end
                return currentGuess --Close enough :)
            end
        end
        currentGuess += iterator
    end
end

local results = {} --Log all results for displaying
local function check(BotId)
    local botInstance = botManager.GetBotFromId(BotId)
    local frames = movement.GetPlayerFrames(botInstance)
    if not frames then
        -- print("The BotID of",wantedBot,"is invalid. Check F9 for the IDs of bots")
        return
    end
    local style = styles.Type[NWVars.GetNWInt(botInstance,"Style")]
    local logText = tick().."\n"..gains.."\n"..#frames[1].."\nL=Last\nC=Current\nP=Predicted\nBT=Bot Tick"

    local indexedAngles = {}
    for _,t in next,frames[2] do --Reduce FPS Loss
        local floored = math.floor(t[1]*5)
        if not indexedAngles[floored] then
            indexedAngles[floored] = {}
        end
        indexedAngles[floored][#indexedAngles[floored]+1] = t
    end

    local lastVel
    local tickCount,accurateCount,failedTicks = 0,0,0
    local accuracyScore = {}
    local gainGuesses = {}
    local suspectedGains = {}
    local averageFPS = {}
    local warns = 0
    local fpsStats = {min=9e9,mint=0,max=0,maxt=0}
    local calculationStart = tick()
    local frames1len = #frames[1]
    for i,t in next,frames[1] do
        if i % 5000 == 0 then
            local progress = i/frames1len
            print("\nProgress: ",progress*100,"%\n["..string.rep("#",math.floor(progress*100))..string.rep("-",100-math.floor(progress*100)).."]")
            wait(.2)
            continue --Short pause
        end
        local curTick = t[1]
        if curTick < 1 then
            continue
        end
        local roundedTick = math.round(curTick*100)/100
        local curVel = t[3]
        if not lastVel then
            lastVel = curVel
            continue
        end
        local angleBefore,angleAfter
        local floored = math.floor(curTick*5)
        for _,i in next,{floored-1,floored,floored+1} do
            if indexedAngles[i] then
                for _,v in next,indexedAngles[i] do
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
            failedTicks += 1
            lastVel = curVel
            if logRun then
                logText ..= "\nBT: "..roundedTick.."\nBroken Tick"
            end
            continue
        end
        local curFPS = 1/(angleAfter[1]-angleBefore[1])
        if curFPS > 600 then
            warns += 1
            if warns <= 20 then
                warn(botInstance.Name,"just hit",curFPS,"FPS (Warning threshold 600) on",roundedTick)
            elseif warns == 21 then
                warn(botInstance.Name,"passed maximum warn limit for FPS of 20 on",roundedTick)
            end
        end
        averageFPS[#averageFPS+1] = curFPS
        if curFPS < fpsStats.min then
            fpsStats.min = curFPS
            fpsStats.mint = roundedTick
        end
        if curFPS > fpsStats.max then
            fpsStats.max = curFPS
            fpsStats.maxt = roundedTick
        end
        local heldKeys
        for _,v in next,frames[4] do
            if v[1] < curTick then
                heldKeys = v[2]
            else
                break
            end
        end
        local keys = numToKeys(heldKeys,style["keys"])
        local curAngle = angleBefore[2]:Lerp(angleAfter[2],1-(angleAfter[1]-curTick)/(angleAfter[1]-angleBefore[1]))
        -- print(angleBefore[1],curTick,angleAfter[1],curAngle)
        local ycos = math.cos(curAngle.Y)
        local ysin = math.sin(curAngle.Y)
        local SmW = keys["s"] - keys["w"]
        local DmA = keys["d"] - keys["a"]
        --l__Vector3_new__15(v415 * v325 + v418 * v326, 0, v418 * v325 - v415 * v326).unit;
        local projectedGain = Vector3.new(DmA*ycos+SmW*ysin,0,SmW*ycos-DmA*ysin).unit
        if isnan(projectedGain.X) then --Dont even ask me how
            lastVel = curVel
            if logRun then
                logText ..= "\nBT: "..roundedTick.."\nNo Relevant Movement"
            end
            continue --No movement (-nan(ind))
        end
        local projectedUPS = UPS(calculateGains(lastVel,projectedGain))
        local curUPS = UPS(curVel)
        local devMessage = "\nBT: "..roundedTick..
                "\nL UPS: "..UPS(lastVel)..
                "\nC UPS: "..curUPS..
                "\nP UPS: "..projectedUPS
        if logRun then
            logText ..= devMessage
        end
        local guessedGains = (curUPS==projectedUPS and 1) or guessGains(lastVel,curUPS,projectedGain)
        if not suspectedGains[guessedGains] then
            suspectedGains[guessedGains] = 0
        end
        suspectedGains[guessedGains] += 1
        if logRun then
            logText ..= "\nGains Guess: "..guessedGains
        end
        lastVel = curVel
        tickCount += 1
        accurateCount + = (curUPS==projectedUPS and 1) or 0
        accuracyScore[#accuracyScore+1] = accurateCount/tickCount
        gainGuesses[roundedTick] = guessedGains
    end
    local totalFPS = 0
    for _,f in next,averageFPS do
        totalFPS += f
    end
    totalFPS = totalFPS / #averageFPS
    local calculationTime = tick()-calculationStart
    print("Calculation time:",calculationTime)
    logText ..= "\nCalculation time: "..calculationTime
    local summaryMessage = "\nSummary for "..botInstance.Name.." ( ID "..botInstance.BotId.." ) ( "..gains.." )"..
        "\nMap:            "..map().DisplayName.Value.." / "..map().name..
        "\nStyle:          "..style.name..
        "\nChecked Ticks:  "..tickCount..
        "\nAccurate Ticks: "..accurateCount..
        "\nBroken Ticks:   "..failedTicks..
        "\nAverage FPS:    "..totalFPS..
        "\nMinimum FPS:    "..fpsStats.min.." ( "..fpsStats.mint.." )"..
        "\nMaximum FPS:    "..fpsStats.max.." ( "..fpsStats.maxt.." )"..
        "\n>600FPS Frames: "..warns..
        "\nAccuracy%:      "..accurateCount/tickCount*100
    print(summaryMessage)
    if logRun then
        logText ..= summaryMessage
    end
    if accurateCount/tickCount < 0.4 then --Not looking good
        local totalWeight = 0
        local bestValue = {0,0}
        for guess,weight in next,suspectedGains do
            totalWeight += weight
            if weight > bestValue[2] then
                bestValue = {guess,weight}
            end
        end
        local extraMessage = "\nExtra Info for "..botInstance.Name.." ( ID "..botInstance.BotId.." )"..
            "\nAccuracy% mid way ( "..math.floor(#accuracyScore/2)/100 .." ): "..accuracyScore[math.floor(#accuracyScore/2)]*100 ..
            "\nPredicted Gains:      "..bestValue[1].." ( "..bestValue[1]*gains .." ) at "..(bestValue[2]/totalWeight)*100 .." %"
        print(extraMessage)
        if logRun then
            logText ..= extraMessage
        end
    end
    if writefile and logRun then
        if not isfolder("rbhop-gains-detection") then
            makefolder("rbhop-gains-detection")
        end
        local name = "rbhop-gains-detection/gs-"..map().DisplayName.Value.."-"..style.name
        if accurateCount/tickCount < 0.35 then
            writefile(name.."-suspicious.txt",logText)
        else
            writefile(name.."-legit.txt",logText)
        end
    end
    -- remote.Call("Chatted",style["name"].." done")
    results[BotId] = gainGuesses
    return true
end

local text = Instance.new("TextLabel",Instance.new("ScreenGui",game.CoreGui))
text.Size = UDim2.fromOffset(200,100)
text.Position = UDim2.new(0.5,-100,0,0)
text.TextSize = 30

local specTarget
remote.Subscribe("SetSpectating",function(u)
    specTarget = type(u) == "table" and u
end)
game:GetService'RunService'.RenderStepped:Connect(function()
    local gainGuesses = results[specTarget and specTarget.BotId]
    if not(specTarget and gainGuesses) then
        text.Visible = false
        return
    end
    local curTime = math.round(NWVars.GetNWFloat(specTarget,"TimeNow")*100)/100+1
    if gainGuesses[curTime] then
        text.Text = gainGuesses[curTime]
        text.Visible = true
    end
end)

if _G.AutoScan and not _G.Subscribed then
    local scanned = {}
    botManager.BotAdded(function(p)
        if type(p) == "table" and _G.AutoScan and not scanned[p.BotId] then
            print("Autoscan start:",p.BotId)
            while wait(0.5) do
                if scanned[p.BotId] then
                    break
                end
                if check(p.BotId) then
                    scanned[p.BotId] = true
                    break
                end
                if not _G.AutoScan then
                    break
                end
            end
            print("Autoscan done:",p.BotId)
        end
    end)
    _G.Subscribed = true
end
print("--{",tick(),"}-- > Loaded")
