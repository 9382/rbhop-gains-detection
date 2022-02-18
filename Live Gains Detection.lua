--The label at the top will represent the data from the last
--2 seconds of scanning of whoever you are spectating

--Keep in mind the ingame spectate is behind whatever the server
--is telling us, so it may look desynced. No fix for that, deal with it

local gains = 2.7*1
--NOTE: Gain guessing is automatic. Only use this for testing
--Do not use results given with a value other than 2.7

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

--[[
Movement Replication
all comes from the Movement remote in RS
2 arguments: first is the user, second is the frame data
all frame data same format (LOOK UP)
(THERE MAY BE NO f[3] OR f[4])
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

local text = Instance.new("TextLabel",Instance.new("ScreenGui",game.CoreGui))
text.Size = UDim2.fromOffset(200,100)
text.Position = UDim2.new(0.5,-100,0,0)
text.TextSize = 30
text.Text = "Waiting for\ntarget"

local lastKnownKeys = {}
local currentScores = {}
local function check(user,frames)
    local style = styles.Type[NWVars.GetNWInt(user,"Style")]
    local indexedAngles = {}
    for _,t in next,frames[2] do --Reduce FPS Loss
        local floored = math.floor(t[1]*2)
        if not indexedAngles[floored] then
            indexedAngles[floored] = {}
        end
        indexedAngles[floored][#indexedAngles[floored]+1] = t
    end

    local lastVel
    local suspectedGains = {}
    local tracker = currentScores[user.UserId] or {}
    for i,t in next,frames[1] do
        local curTick = t[1]
        local roundedTick = math.round(curTick*100)/100
        local curVel = t[3]
        if not lastVel then
            lastVel = curVel
            continue
        end
        local angleBefore,angleAfter
        local floored = math.floor(curTick*2)
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
            lastVel = curVel
            continue
        end
        local heldKeys
        if frames[4] then
            for _,v in next,frames[4] do
                if v[1] < curTick then
                    heldKeys = v[2]
                    lastKnownKeys[user.UserId] = v[2]
                else
                    break
                end
            end
        end
        heldKeys = heldKeys or lastKnownKeys[user.UserId]
        if heldKeys == nil then
            text.Text = "Waiting for\nkeys update"
            continue
        end
        local keys = numToKeys(heldKeys,style["keys"])
        if not keys[" "] then
            lastVel = curVel
            continue
        end --If not jumping, we dont care
        local curAngle = angleBefore[2]:Lerp(angleAfter[2],1-(angleAfter[1]-curTick)/(angleAfter[1]-angleBefore[1]))
        local ycos = math.cos(curAngle.Y)
        local ysin = math.sin(curAngle.Y)
        local SmW = keys["s"] - keys["w"]
        local DmA = keys["d"] - keys["a"]
        --l__Vector3_new__15(v415 * v325 + v418 * v326, 0, v418 * v325 - v415 * v326).unit;
        local projectedGain = Vector3.new(DmA*ycos+SmW*ysin,0,SmW*ycos-DmA*ysin).unit
        if not(projectedGain.X >= 0) and not(projectedGain.X <= 0) then
            lastVel = curVel
            continue --No movement (-nan(ind))
        end
        local projectedUPS = calculateGains(lastVel,projectedGain)
        projectedUPS = (projectedUPS.X^2+projectedUPS.Z^2)^.5
        local curUPS = (curVel.X^2+curVel.Z^2)^.5
        local guessedGains = (curUPS==projectedUPS and 1) or guessGains(lastVel,curUPS,projectedGain)
        tracker[tick()] = guessedGains
        lastVel = curVel
    end
    local suspectedGains = {}
    local expired = {}
    for time,gains in next,tracker do
        if tick()-time > 2 then
            expired[#expired+1] = time
        else
            suspectedGains[gains] = suspectedGains[gains] or 0
            suspectedGains[gains] += 1
        end
    end
    for _,t in next,expired do
        tracker[t] = nil
    end
    currentScores[user.UserId] = tracker
    local totalWeight = 0
    local bestValue = {0,0}
    for guess,weight in next,suspectedGains do
        totalWeight += weight
        if weight > bestValue[2] then
            bestValue = {guess,weight}
        end
    end
    local gain = bestValue[1]
    local score = bestValue[2]
    if totalWeight > 100 and score/totalWeight >= .9 and gain ~= 1 and tonumber(gain) then
        warn("[GC Live]",user,"just hit 90%+ certainty on irregular gains",gain)
    end
    return true
end

local specTarget
remote.Subscribe("SetSpectating",function(u)
    specTarget = type(u) == "userdata" and u
end)
game:GetService("ReplicatedStorage").Movement.OnClientEvent:Connect(function(user,frames)
    check(user,frames)
end)
local function len(t)
    local c=0 for _,_ in next,t do c+=1 end return c
end
game:GetService("RunService").RenderStepped:Connect(function()
    if not specTarget then
        text.Visible = false
        return
    end
    text.Visible = true
    local tracker = currentScores[specTarget.UserId]
    if tracker then
        local suspectedGains = {} --Im lazy, so lets do a horrible approach!
        for time,gains in next,tracker do
            suspectedGains[gains] = suspectedGains[gains] or 0
            suspectedGains[gains] += 1
        end
        local totalWeight = 0
        local bestValue = {0,0}
        for guess,weight in next,suspectedGains do
            totalWeight += weight
            if weight > bestValue[2] then
                bestValue = {guess,weight}
            end
        end
        if totalWeight > 0 then
            text.Text = bestValue[1].."\n("..(math.floor(bestValue[2]/totalWeight*1000)/10).."%)"
        else
            text.Text = "Not enough\ndata"
        end
    end
end)
print("--{",tick(),"}-- > Loaded")
