local wantedBot = 1
local logRun = true
--Causes a little bit of lag
--Saves the file in the workspace folder
local gains = 2.7*1
--NOTE: Gain guessing is now automatic. Only use this for dev
--Do not use results given with a changed value
local DEVMODE = false
--If a number, its prints that tick
--If True, it prints all ticks. Causes console spam and lag on 15+ second bots
_G.AutoScan = true
--Disable to prevent auto-scanning when spectating a bot

print("--{",tick(),"}--")
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
    if projectedUPS > curUPS then
        return --Lost speed due to something, irrelevant
    end
    local currentGuess = 1.1
    local iterator = .1
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
                return currentGuess --Close enough :)
            end
        end
        currentGuess += iterator
    end
end

local function check(BotId)
    local botInstance = botManager.GetBotFromId(BotId)
    local frames = movement.GetPlayerFrames(botInstance)
    if not frames then
        -- print("The BotID of",wantedBot,"is invalid. Check F9 for the IDs of bots")
        return
    end
    local style = styles.Type[NWVars.GetNWInt(botInstance,"Style")]
    local logText = tostring(tick()).."\n"..gains.."\n"..#frames[1]
    
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
    local gainsOffset = {}
    local suspectedGains = {}
    local calculationStart = tick()
    for _,t in next,frames[1] do
        local curTick = t[1]
        if curTick < 1 then
            continue
        end
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
                logText ..= "\nBot tick: "..math.round(curTick*100)/100 .."\nBroken Tick"
            end
            continue
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
        if not(projectedGain.X >= 0) and not(projectedGain.X <= 0) then
            lastVel = curVel
            if logRun then
                logText ..= "\nBot tick: "..math.round(curTick*100)/100 .."\nNo Relevant Movement"
            end
            continue --No movement (-nan(ind))
        end
        local projectedUPS = calculateGains(lastVel,projectedGain)
        projectedUPS = (projectedUPS.X^2+projectedUPS.Z^2)^.5
        local curUPS = (curVel.X^2+curVel.Z^2)^.5
        local devMessage = "\nBot tick:      "..math.round(curTick*100)/100 ..
                "\nPrevious UPS:  "..(lastVel.X^2+lastVel.Z^2)^.5 ..
                "\nCurrent UPS:   "..curUPS..
                "\nPredicted UPS: "..projectedUPS
        if DEVMODE == true or math.round(curTick*100)/100 == DEVMODE then
            print(devMessage)
        end
        if logRun then
            logText ..= devMessage
        end
        if not(curUPS==projectedUPS) then
            local guessedGains = guessGains(lastVel,curUPS,projectedGain)
            if guessedGains then
                if not suspectedGains[guessedGains] then
                    suspectedGains[guessedGains] = 0
                end
                suspectedGains[guessedGains] += 1
                if logRun then
                    logText ..= "\nGains Guess returned "..guessedGains
                end
            end
        end
        lastVel = curVel
        tickCount += 1
        accurateCount + = (curUPS==projectedUPS and 1) or 0
        accuracyScore[#accuracyScore+1] = accurateCount/tickCount
        gainsOffset[#gainsOffset+1] = math.min(.5,projectedUPS-curUPS) --Outliers are a bitch
    end
    local calculationTime = tick()-calculationStart
    print("Calculation time:",calculationTime)
    logText ..= "\nCalculation time: "..calculationTime
    local summaryMessage = "\nSummary for "..botInstance.Name.." ( ID "..botInstance.BotId.." )"..
        "\nMap:            "..map().name..
        "\nStyle:          "..style.name..
        "\nChecked Ticks:  "..tickCount..
        "\nAccurate Ticks: "..accurateCount..
        "\nBroken Ticks:   "..failedTicks..
        "\nAccuracy%:      "..accurateCount/tickCount*100
    print(summaryMessage)
    logText ..= summaryMessage
    if accurateCount/tickCount < 0.4 then --Not looking good
        local averageGainsOffset = 0
        for _,offset in next,gainsOffset do
            averageGainsOffset += offset
        end
        local totalWeight = 0
        local bestValue = {0,0}
        for guess,weight in next,suspectedGains do
            totalWeight += weight
            if weight > bestValue[2] then
                bestValue = {guess,weight}
            end
        end
        averageGainsOffset = averageGainsOffset / #gainsOffset
        local extraMessage = "\nExtra Info for "..botInstance.Name.." ( ID "..botInstance.BotId.." )"..
            "\nAccuracy% mid way ( "..math.floor(#accuracyScore/2)/100 .." ): "..accuracyScore[math.floor(#accuracyScore/2)]*100 ..
            "\nAverage gains offset: "..averageGainsOffset..
            "\nPredicted Gains:      "..bestValue[1].." ( "..bestValue[1]*2.7 .." ) at "..(bestValue[2]/totalWeight)*100 .." %"
        print(extraMessage)
        logText ..= extraMessage
    end
    if writefile and logRun then
        local name = "gs-"..map().DisplayName.Value.."-"..style.name
        if accurateCount/tickCount < 0.35 then
            writefile(name.."-sus.txt",logText)
        else
            writefile(name.."-legit.txt",logText)
        end
    end
    return true
end
check(wantedBot)
if _G.AutoScan and not _G.Subscribed then
    local scanned = {}
    remote.Subscribe("SetSpectating",function(p)
        if type(p) == "table" and _G.AutoScan and not scanned[p.BotId] then
            while wait(1) do
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
        end
    end)
    _G.Subscribed = true
end
