--======================
--// SERVICES //
--======================
local HttpService 				= game:GetService("HttpService")
local ReplicatedStorage 		= game:GetService("ReplicatedStorage")
local RunService 				= game:GetService("RunService")
local Players 					= game:GetService("Players")

local isServer 					= RunService:IsServer()

--======================
--// COFNIG //
--======================
local REMOTE_NAME 				= "NetworkingRemote"
local REMOTE_FUNCTION_NAME 		= "NetworkingRemoteFunction"
local RATE_LIMIT_WINDOW 		= 1 	-- seconds, don't recommend going under 1 second
local RATE_LIMIT_MAX 			= 8 		-- max fires per window per event per player

local DEBUG 					= true
local MAX_LOG_ENTRIES 			= 40

local NONCE_EXPIRATION 			= 8 -- seconds before a nonce becomes invalid
local CLEAR_PLAYER_NONCE_CACHE 	= 10 -- seconds before clearing nonce cahce

--======================
--// STORAGE //
--======================
local remoteEvent
local remoteFunction
local requestHandlers 			= {}
local c2sListeners 				= {} 		-- eventName -> { listeners = { func }, validators = { func } }
local s2cListeners 				= {} 		-- eventName -> { listeners = { func } }
local c2sRateLimits 			= {} 		-- player -> eventName -> { count, lastReset }
local spyListeners 				= {} 		-- eventName -> { funcs } for spying on fires
local scopes 					= {} 				-- scopeId -> { disconnectors = {} }
local trafficLog 				= {}
local eventGroups 				= {}			-- groupName -> { events = { eventName }, enabled = true }
local eventToGroups				= {}		-- eventName -> groupName
local activeNonces 				= {}			-- player.UserId -> { nonceString = expirationTime }
local noncesCache 				= {}			-- player.UserId -> { eventName = { nonce, timestamp } }

--======================
--// DEBUG //
--======================
local function log(...)
	if DEBUG then
		print("[NetworkService]",...)
	end
end

--======================
--// HELPER //
--======================
local function getRemote()
	if not remoteEvent then
		remoteEvent = ReplicatedStorage.Events:FindFirstChild(REMOTE_NAME)
		if not remoteEvent then
			remoteEvent = Instance.new("RemoteEvent")
			remoteEvent.Name = REMOTE_NAME
			remoteEvent.Parent = ReplicatedStorage.Events
		end
	end
	return remoteEvent
end

local function getFunction()
	if not remoteFunction then
		remoteFunction = ReplicatedStorage.Events:FindFirstChild(REMOTE_FUNCTION_NAME)
		if not remoteFunction then
			remoteFunction = Instance.new("RemoteFunction")
			remoteFunction.Name = REMOTE_FUNCTION_NAME
			remoteFunction.Parent = ReplicatedStorage.Events
		end
	end
	return remoteFunction
end

local function checkRateLimit(Player : Player, eventName : string)
	if not c2sRateLimits[Player.UserId] then
		c2sRateLimits[Player.UserId] = {}
	end
	if not c2sRateLimits[Player.UserId][eventName] then
		c2sRateLimits[Player.UserId][eventName] = {count = 0, lastReset = os.clock()}
	end
	
	local data = c2sRateLimits[Player.UserId][eventName]
	local now = os.clock()
	
	if now - data.lastReset > RATE_LIMIT_WINDOW then
		data.count = 0
		data.lastReset = now
	end
	
	if data.count > RATE_LIMIT_MAX then
		return false, "Rate limit exceeded"
	end
	
	data.count += 1
	
	return true
end

local function validateArgs(eventName : string, Player : Player, ... : any)
	local config = c2sListeners[eventName]
	if not config then return true end 
	
	for _,validator in ipairs(config.validators) do
		local success,err = validator(Player,...)
		if not success then
			return false, err or "Validation failed"
		end
	end
	return true
end

local function isEventEnabled(eventName: string): boolean
	local groupName = eventToGroups[eventName]
	if not groupName then return true end
	local group = eventGroups[groupName]
	return group and group.enabled
end

local function fireSpies(eventName : string, direction : any, sender : any, ... : any)
	if spyListeners[eventName] then
		for _,spy in ipairs(spyListeners[eventName]) do
			pcall(spy,eventName,direction,sender,...)
		end
	end

	if DEBUG then
		local rawArgs = {...}
		local displayArgs = {}
		for i, v in ipairs(rawArgs) do
			if typeof(v) == "table" then
				displayArgs[i] = "<table>"
			elseif typeof(v) == "Instance" then
				displayArgs[i] = v:GetFullName()
			else
				displayArgs[i] = tostring(v)
			end
		end
		
		table.insert(trafficLog, 1, {
			time = os.clock(),
			event = eventName,
			dir = direction,
			sender = (sender and sender.Name) or "Server",
			args = displayArgs
		})

		if #trafficLog > MAX_LOG_ENTRIES then
			table.remove(trafficLog)
		end
	end

end

local function GenerateNonce(Player: Player, eventName: string): string?
	if not noncesCache[Player.UserId] then
		noncesCache[Player.UserId] = {}
	end
	if noncesCache[Player.UserId][eventName] then 
		if tick() - noncesCache[Player.UserId][eventName].timestamp >= CLEAR_PLAYER_NONCE_CACHE then
			noncesCache[Player.UserId][eventName] = nil
		else
			warn("[NetworkService] Cache found for event: "..eventName..", can't create nonce") return false 
		end
	end
	local nonce = HttpService:GenerateGUID(false)
	local now = os.clock()

	if not activeNonces[Player.UserId] then
		activeNonces[Player.UserId] = {}
	end

	activeNonces[Player.UserId][nonce] = now + NONCE_EXPIRATION

	return nonce
end

--======================
--// CORE //
--======================

local NetworkService = {}
NetworkService.__index = {}

function NetworkService:ValidateNonce(Player: Player,nonce: string,eventName: string): boolean
	if not activeNonces[Player.UserId] then return false end
	if not activeNonces[Player.UserId][nonce] then return false end

	if os.clock() > activeNonces[Player.UserId][nonce] then
		activeNonces[Player.UserId][nonce] = nil
		return false 
	end

	activeNonces[Player.UserId][nonce] = nil

	if not noncesCache[Player.UserId] then
		noncesCache[Player.UserId] = {}
	end
	
	noncesCache[Player.UserId][eventName] = {nonce = nonce,timestamp = tick()}

	return true
end

function NetworkService:RegisterC2S(eventName : string, validator : any, listener : any)
	if not isServer then error("RegisterC2S can only be called from server") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid eventName") end
	
	

	if not c2sListeners[eventName] then
		c2sListeners[eventName] = {listeners = {}, validators = {}}
	end
	
	table.insert(c2sListeners[eventName].validators,validator)

	if listener then
		table.insert(c2sListeners[eventName].listeners,listener)
	end
	log("Registered C2S event: ",eventName)
end

function NetworkService:RegisterS2C(eventName : string, listener : any)
	if isServer then error("RegisterS2C can only be called from the client") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end
	
	if not s2cListeners[eventName] then
		s2cListeners[eventName] = {listeners = {}}
	end
	
	table.insert(s2cListeners[eventName].listeners, listener)
	log("Registered S2C event: ",eventName)
end

function NetworkService:RegisterRequestC2S(eventName: string, handler: any)
	if not isServer then error("RegisterRequest can only be used to server") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid request name") end
	if typeof(handler) ~= "function" then error("Handler must be a function") end
	
	requestHandlers[eventName] = handler
	log("Registered C2S RPC:",eventName)
end

function NetworkService:AddSpy(eventName : string, spy : any)
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end
	if typeof(spy) ~= "function" then error("Spy must be a function") end
	
	if not spyListeners[eventName] then
		spyListeners[eventName] = {}
	end
	
	table.insert(spyListeners[eventName],spy)
	log("Added spy for event: ",eventName)
	
end

function NetworkService:FireServer(eventName : string, args : any,options: {any}?)
	if isServer then error("FireServer can only be called from the client") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end
	
	if not isEventEnabled(eventName) then
		log("Skipped firing event (group disabled): "..eventName)
		return
	end

	if options then
		if options.requiresNonce == true then
			local nonce = NetworkService:RequestServer("__NONCE",{EventName = eventName})
			if not nonce then warn("Error generating nonce for event: "..eventName) return end
			table.insert(args,nonce)
			table.insert(args,options.requiresNonce)
		elseif options.requiresNonce == false then
			table.insert(args,options.requiresNonce)
		end
	end

	table.insert(args,eventName)
	
	local remote = getRemote()
	remote:FireServer(args)
	fireSpies(eventName,"C2S",nil,args)
	log("Fired to server: ",eventName)
end

function NetworkService:FireClient(Player : Player, eventName : string, ... : any)
	if not isServer then error("FireClient can only be called from the server") end
	if typeof(Player) ~= "Instance" or not Player:IsA("Player") then error("Invalid player") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end
	
	if not isEventEnabled(eventName) then
		log("Skipped firing event (group disabled): "..eventName)
		return
	end

	table.insert(...,eventName)
	
	local remote = getRemote()
	remote:FireClient(Player,...)
	fireSpies(eventName,"S2C",Player,...)
	log("Fired to client: ", Player.Name,eventName)
end

function NetworkService:FireAllClients(eventName : string, ... : any)
	if not isServer then error("FireAllClients can only be called from the server") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end
	
	table.insert(...,eventName)
	
	local remote = getRemote()
	remote:FireAllClients(...)
	fireSpies(eventName,"S2C",nil,...)
	log("Fired to all clients: ",eventName)
end

function NetworkService:FireAllClientsInRadius(eventName: string,radius: number,targetCharacter: Model,... : any)
	if not isServer then error("FireAllClientsInRadius can only be called from the server") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end
	if radius == 0 then error("Radius must be grater than 0") end 

	if not isEventEnabled(eventName) then
		log("Skipped firing event (group disabled): "..eventName)
		return
	end

	table.insert(...,eventName)

	for _,Player in pairs(Players:GetPlayers()) do
		local character = Player.character
		if character then
			if (character.HumanoidRootPart.Position - targetCharacter.HumanoidRootPart.Position).Magnitude <= radius then
				local remote = getRemote()
				remote:FireClient(Player,...)
			end
		end
	end
end



function NetworkService:CreateScope()
	local id = HttpService:GenerateGUID(false)
	scopes[id] = { disconnectors = {} }

	local scope = {}
	log("Created scope: "..tostring(id))

	function scope:RegisterS2C(eventName: string,listener: any)
		NetworkService:RegisterS2C(eventName,listener)

		table.insert(scopes[id].disconnectors,function()
			local config = s2cListeners[eventName]
			if config then
				for i,fn in ipairs(config.listeners) do
					if fn == listener then
						table.remove(config.listeners,i)
						break
					end
				end
			end
		end)
		log("Register S2C event for scope: "..tostring(id))
	end

	function scope:Destroy()
		for _,undo in ipairs(scopes[id].disconnectors) do
			pcall(undo)
		end
		scopes[id] = nil
		log("Destroyed scope: "..tostring(id))
	end

	return scope
end

function NetworkService:RequestServer(eventName: string, args: {any?})
	if isServer then error("RequestServer can only be used on client") end
	if typeof(eventName) ~= "string" then error("Invalid event name") end
	
	local func = getFunction()
	return func:InvokeServer(eventName,args)
end

function NetworkService:RegisterGroup(groupName: string,events: {string})
	if typeof(groupName) ~= "string" or groupName == "" then
		error("Invalid group name")
	end
	if typeof(events) ~= "table" then
		error("Events must be provided in a table")
	end

	eventGroups[groupName] = { events = {}, enabled = true}
	for _,eventName in ipairs(events) do
		if typeof(eventName) == "string" and eventName ~= "" then
			table.insert(eventGroups[groupName].events,eventName)
			eventToGroups[eventName] = groupName
		end
	end
	log("Registered group: "..groupName.." with events: "..table.concat(events,", "))
end

function NetworkService:EnableGroup(groupName: string)
	local group = eventGroups[groupName]
	if not group then
		warn("Group doesnt exists: "..groupName)
		return
	end

	group.enabled = true
	log("Enabled group: "..groupName)
end

function NetworkService:DisableGroup(groupName: string)
	local group = eventGroups[groupName]
	if not group then
		warn("Group doesnt exists: "..groupName)
		return
	end
	group.enabled = false
	log("Disabled group: "..groupName)
end

function NetworkService:IsGroupEnabled(groupName: string): boolean
	local group = eventGroups[groupName]
	if not group then
		warn("Group doesnt exists: "..groupName)
		return
	end
	return group.enabled
end

if isServer then
    NetworkService:RegisterRequestC2S("__NONCE", function(Player: Player,args: {any})
        local EventName = args.EventName

        if Player and EventName then
            local nonce = GenerateNonce(Player,EventName)
            if nonce ~= false then
                return nonce
            end
        end
        return false
    end)
	getFunction().OnServerInvoke = function(Player: Player, eventName: string, args: {any}?)
		
		local success, rateErr = checkRateLimit(Player,eventName)
		if not success then return nil end
		
		local handler = requestHandlers[eventName]
		if not handler then
			log("Unregistered RPC Request")
			return nil
		end
		
		local ok,result = pcall(handler,Player,args)
		if not ok then
			warn("RPC Handler Error: ",eventName,result)
			return nil
		end
		return result
	end
	getRemote().OnServerEvent:Connect(function(Player : Player, ... : any)
		local args = ...
		local max = table.maxn(...)
		local eventName = args[max]
		local requiresNonce = args[max-1]
		if requiresNonce == true then
			local nonce = args[max-2]
			if NetworkService:ValidateNonce(Player,nonce,eventName) == false then
				warn("[NETWORKSERVICE] Nonce: "..tostring(nonce).." is no longer valid")
				return
			else
				log("Nonce: "..tostring(nonce).." registered")
				table.remove(args,max-1)
				table.remove(args,max-2)
			end
		end
		
		
		if typeof(eventName) ~= "string" then
			log("Invalid eventName type from", Player.Name)
			return
		end
		
		fireSpies(eventName,"C2S",Player,...)
		
		local success,rateErr = checkRateLimit(Player,eventName)
		if not success then
			log("Rate limit hit: ",Player.Name,eventName,rateErr)
			return
		end
		
		local valSuccess, valErr = validateArgs(eventName,Player,...)
		if not valSuccess then
			log("Validation failed: ",Player.Name,eventName,valErr)
			return
		end
		
		local config = c2sListeners[eventName]
		if config then
			for _,listener in ipairs(config.listeners) do
				local ok,err = pcall(listener, Player, args)
				if not ok then
					warn("Error in C2S handler for: ",eventName,":",err)
				end
			end
		else
			log("Unregistered C2S event: ",eventName)
		end
	end)
else
	getRemote().OnClientEvent:Connect(function(...)

		if DEBUG and RunService:IsStudio() then
			task.defer(function()

				local Player = game.Players.LocalPlayer
				local PlayerGui = Player:WaitForChild("PlayerGui")

				if PlayerGui:FindFirstChild("NetworkDebugOverlay") then return end

				local ScreenGui = Instance.new("ScreenGui")
				ScreenGui.Name = "NetworkDebugOverlay"
				ScreenGui.IgnoreGuiInset = true
				ScreenGui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")

				local Frame = Instance.new("Frame")
				Frame.BackgroundColor3 = Color3.fromRGB(20,20,20)
				Frame.BackgroundTransparency = 0.3
				Frame.Size = UDim2.new(0.35,0,0.3,0)
				Frame.Position = UDim2.new(0.8,0,0.3,0)
				Frame.AnchorPoint = Vector2.new(0.5,0.5)
				Frame.Parent = ScreenGui
				Frame.Name = "MainFrame"

				local TextBox = Instance.new("TextLabel")
				TextBox.BackgroundTransparency = 1
				TextBox.TextXAlignment = Enum.TextXAlignment.Left
				TextBox.TextYAlignment = Enum.TextYAlignment.Top
				TextBox.Size = UDim2.new(1,0,1,0)
				TextBox.Font = Enum.Font.Code
				TextBox.TextSize = 20
				TextBox.TextColor3 = Color3.new(1,1,1)
				TextBox.Parent = Frame

				game:GetService("UserInputService").InputBegan:Connect(function(Input: InputObject)
					if Input.KeyCode == Enum.KeyCode.F7 then
						if Frame.Visible == false then
							Frame.Visible = true
						elseif Frame.Visible == true then
							Frame.Visible = false
						end
					end
				end)
				
				task.spawn(function()
					while ScreenGui.Parent do
						task.wait(0.25)
						local output = {"Network Monitor:"}
						for _,log in ipairs(trafficLog) do
							output[#output+1] = string.format("[%s] %s -> %s | %s",
							log.dir,
							log.sender,
							log.event,
							table.concat(log.args,", ")
						)
						end
						TextBox.Text = table.concat(output,"\n")
					end
				end)
			end)
		end

		local args = ...
		local max = table.maxn(...)
		local eventName = args[max]

		if typeof(eventName) ~= "string" then
			log("Invalid eventName type from", eventName)
			return
		end
		
		fireSpies(eventName,"S2C",nil,...)
		
		local config = s2cListeners[eventName]
		if config then
			for _,listener in pairs(config.listeners) do
				local ok,err = pcall(listener,...)
				if not ok then
					warn("Error in S2C handler for: ",eventName,":",err)
				end
			end
		else
			log("Unregistered S2C event: ",eventName)
		end
	end)

end

if isServer then
	Players.PlayerRemoving:Connect(function(Player : Player)
		c2sListeners[Player] = nil 
	end)
end


return NetworkService

