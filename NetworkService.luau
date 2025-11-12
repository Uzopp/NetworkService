--[[
==================================================
                 NetworkService Module
==================================================
Author: UZOPH
Version: v.0.2 [BETA]

v.0.2  ADDED:
--------------------------------------------------
Nonces (Client → Server Replay Protection)
--------------------------------------------------
Purpose:
    Nonces provide **one-time-use, expiration-based tokens** that the client
    must present when sending certain sensitive C2S events. This prevents
    replay attacks where an exploiter captures a previously valid RemoteEvent
    call and replays it to duplicate purchases, currency, abilities, etc.

How it works:
    • The client requests a nonce from the server (via `__NONCE` request).
    • The server generates a GUID and stores it in an internal nonce table.
    • The client includes the nonce when firing the protected C2S event.
    • The server verifies the nonce, consumes it, and rejects replays.

Security properties:
    • Nonces expire automatically (configurable, default 8 seconds).
    • Each nonce is **one-time-use** — once validated, it is deleted.
    • The client cannot generate or guess valid nonces on their own.
    • Replay attempts are silently rejected server-side.

Usage EXAMPLE (Client → Server):
    NetworkService:FireServer("PurchaseItem", { itemId }, { requiresNonce = true })

On the server C2S validator:
    -- The validator will automatically reject packets missing / invalid nonces
    NetworkService:RegisterC2S("PurchaseItem", function(player, args)
        return true -- normal validation logic
    end, function(player, args)
        -- runs only if nonce was valid and event was authorized
    end)

Manual Nonce Request (advanced):
    local nonce = NetworkService:RequestServer("__NONCE", { EventName = "MyEvent" })
    NetworkService:FireServer("MyEvent", { data, nonce, true })
	Don't recommend using this since it's easier for exploiters to detect

Notes:
    • Only enable nonces for events that directly translate to value changes,
      such as currency rewards, ability triggers, item purchases, trades, etc.
    • Nonces are optional per event — use `requiresNonce = true` to enforce.
    • Invalid or expired nonces do not error; the event is simply ignored.


NOTE! This module is still in BETA and you might encounter errors and problems. Please report them trough discord to user: @uzuphh



==================================================
                   PUBLIC METHODS
==================================================

--------------------------------------------------
NetworkService:FireClient(player: Player, remoteName: string, arguments: {any})
--------------------------------------------------
DIRECTION: SERVER → CLIENT

Usage (ServerScript):
    NetworkService:FireClient(player, "RemoteName", { arg1, arg2, ... })

Description:
    Sends data from the server to a specific client. The final element in the
    arguments table is reserved for `remoteName`. An arguments table must be
    provided even if empty.

Client listener (LocalScript):
    NetworkService:RegisterS2C("RemoteName", function(arguments: {any})
        local remoteName = arguments[#arguments] -- remoteName is appended by the system
        -- handle args...
    end)

--------------------------------------------------
NetworkService:FireServer(remoteName: string, arguments: {any})
--------------------------------------------------
DIRECTION: CLIENT → SERVER

Usage (LocalScript):
    NetworkService:FireServer("RemoteName", { arg1, arg2, ... })

Description:
    Sends data from the client to the server. The final element in the
    arguments table is reserved for `remoteName`. An arguments table must be
    provided even if empty.

Server registration (ServerScript):
    NetworkService:RegisterC2S("RemoteName",
        function(player, arguments) -- Validator: return true/false
            -- Validate incoming data, return false to reject
            return true
        end,
        function(player, arguments) -- Listener: runs if validator returned true
            -- action logic
        end
    )

Notes:
	- Validator receives (player, ...) and should perform strict checks: types,
    ranges, permissions, etc. Keep validators fast and deterministic.

--------------------------------------------------
NetworkService:RequestServer(remoteName: string, arguments: {any}) → any
--------------------------------------------------
DIRECTION: CLIENT → SERVER (Request/Response)

Usage (LocalScript):
    local result = NetworkService:RequestServer("RemoteName", { arg1, arg2 })

Server handler (ServerScript):
    NetworkService:RegisterRequestC2S("RemoteName", function(player, arguments)
        -- handle request
        return someResult
    end)

Description:
    - Invokes a server-side handler and returns whatever the handler returns.
    - Server-side RPCs are rate-limited and validated before execution.

--------------------------------------------------
NetworkService:AddSpy(eventName: string, spyCallback: function)
--------------------------------------------------
DIRECTION: GLOBAL (Client or Server)

Usage (Developer / Debugging):
    NetworkService:AddSpy("RemoteName", function(eventName, direction, sender, ...)
        -- direction: "C2S" or "S2C"
        -- sender: Player (for C2S) or nil (for server broadcasts)
        -- ... : original args passed
    end)

Description:
    - Registers a passive observer (spy) called every time `eventName` fires.
    - Spies do NOT block or alter normal flow — they are for logging, analytics,
    debugging, or lightweight exploit detection.

Parameters passed to spyCallback:
    eventName : string
    direction : "C2S" | "S2C"
    sender    : Player? (nil for broadcasts)
    ...       : any additional arguments sent with the event

Important notes:
  - Spies run with pcall, so they won't crash remotes if they error.
  - Keep spy logic lightweight; expensive operations can impact runtime.
  - Use spies for telemetry, heuristic anomaly detection, and dev overlays.

Example (suspicious-currency detection):
    NetworkService:AddSpy("GiveCoins", function(eventName, direction, sender, amount)
        if direction == "C2S" and amount and amount > 25000 then
            warn("[SECURITY] Possible exploit:", sender and sender.Name, "requested", amount)
        end
    end)

--------------------------------------------------
--------------------------------------------------
NetworkService:FireAllClientsInRadius(targetCharacter: Model, radius: number, eventName: string, arguments: {any})
--------------------------------------------------
DIRECTION: SERVER → CLIENT (Proximity-based)

Usage (ServerScript):
NetworkService:FireAllClientsInRadius(
    player.Character, -- center point character
    30,               -- radius in studs
    "ExplosionEvent", -- remote event name
    {damageAmount, forceVector} -- arguments table
)

Description:
	- Fires a remote event to all clients within a given radius of a target character.
	- The final element in the arguments table is automatically reserved for the `remoteName`.

Behavior & Notes:
	- Only players whose HumanoidRootPart is within the radius receive the event.
	- Useful for localized effects like explosions, area buffs, or environmental triggers.
	- Works only on the server; the client cannot call this function.
	- The radius must be greater than 0. If targetCharacter is nil or missing HumanoidRootPart, no events are fired.
	- Arguments table must be provided, even if empty.

Client listener (LocalScript):
	NetworkService:RegisterS2C("ExplosionEvent", function(args)
		local remoteName = args[#args] -- automatically appended
		local damageAmount, forceVector = unpack(args)
		-- handle explosion effect
	end)

Best practices:
	- Combine with validators or cooldowns if using for repeated or damaging events.
	- Keep the arguments table small to avoid network congestion.
	- Can be paired with AddSpy for debugging or detecting abnormal broadcast patterns.
--------------------------------------------------

--------------------------------------------------
NetworkService:RegisterGroup / EnableGroup / DisableGroup / IsGroupEnabled
--------------------------------------------------
PURPOSE: Organize events into logical groups that can be enabled or disabled dynamically.
This is useful for subsystems like UI modules, mini-games, or temporary features.

Usage (ServerScript or Client LocalScript):
-- Define a group of combat-related events
NetworkService:RegisterGroup("Combat", { "PlayerAttack", "AbilityUsed", "DamageTaken" })

-- Disable all combat events (e.g., when a match ends)
NetworkService:DisableGroup("Combat")

-- Attempting to fire an event in a disabled group will be skipped
NetworkService:FireClient(player, "PlayerAttack", { damage = 50 }) -- Won't fire

-- Re-enable the combat events (e.g., new match starts)
NetworkService:EnableGroup("Combat")

-- Now events in the group fire normally
NetworkService:FireClient(player, "PlayerAttack", { damage = 50 })

-- Check if a group is currently enabled
local isCombatEnabled = NetworkService:IsGroupEnabled("Combat")

Description:
- A group is a logical container of multiple events.
- When a group is disabled:
    • FireClient, FireAllClients, FireServer calls for events in the group are ignored.
    • C2S or S2C listeners in the disabled group are skipped.
- Events not assigned to any group are always enabled.
- Groups do not interfere with scopes; scope destruction still cleans up registered listeners.
- Useful for temporarily disabling entire subsystems like combat, UI, or seasonal features without removing listeners individually.

Best practices:
- Combine with scopes for subsystem-specific cleanup.
- Use meaningful group names for clarity (e.g., "Combat", "UI", "MiniGame").
- Keep arguments small to reduce network load when firing group events.
- Use in combination with AddSpy to monitor skipped events during debugging.
--------------------------------------------------
Scopes: CreateScope / scope:RegisterS2C / scope:Destroy
--------------------------------------------------
PURPOSE: Lifecycle-managed listener groups, ideal for UI or temporary systems.

Create and usage (Client LocalScript UI example):

	-- When UI opens
    local scope = NetworkService:CreateScope()
    scope:RegisterS2C("UI_Update", function(args) ... end)
    scope:RegisterS2C("XP_Gain",   function(args) ... end)

    -- When the UI closes:
    scope:Destroy() -- removes all listeners registered on this scope

Behavior & rationale:
  • A scope is a logical container for listeners. When destroyed it removes all
    registered listeners so they don't linger (prevents memory leaks and stray callbacks).
  • Scopes are perfect for UI modules that open and close frequently: register
    listeners when UI opens, destroy scope when UI closes, recreate scope when UI opens again.
  • Scopes do not affect global listeners registered directly on NetworkService.
  • Scopes simplify cleanup: one call removes everything the scope added.

Recommended pattern:
  • Create a new scope on UI show.
  • Register all UI-specific S2C or temporary handlers with the scope.
  • Destroy the scope on UI hide or module unload.

--------------------------------------------------
Other Built-in protections / tooling
--------------------------------------------------
  • Rate limiting (per-player, per-event) to reduce spam and brute-force abuse.
  • Validator callback on C2S to centralize server-side validation logic.
  • Debug-only overlay + traffic logging (DEBUG flag) for studio debugging. ENABLE/DISABLE F7
  • FireAllClientsInRadius utility to support proximity-based updates.

==================================================
Notes & Best practices:
  • Always validate ANY client-sent data on the server side.
  • Keep validator functions cheap and deterministic.
  • Use AddSpy & debug overlays only for development or very-lightweight analytics.
  • Use Scopes to avoid memory leaks for UI and temporary subsystems.
  • Consider ACL checks (player permissions) inside validators for sensitive remotes.

==================================================
]]


--======================
--// SERVICES //
--======================
local HttpService 				= game:GetService("HttpService")
local ReplicatedStorage 		= game:GetService("ReplicatedStorage")
local RunService 				= game:GetService("RunService")
local Players 					= game:GetService("Players")

local isServer 					= RunService:IsServer()

if not ReplicatedStorage:FindFirstChild("Events") then
	local EventsFolder = Instance.new("Folder")
	EventsFolder.Name = "Events"
	EventsFolder.Parent = ReplicatedStorage
end

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
