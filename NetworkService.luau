--[[
==================================================
                 NetworkService Module
==================================================
Author: UZOPH
Version: v0.2.2 [BETA]

--------------------------------------------------
OVERVIEW
--------------------------------------------------
NetworkService is a unified communication layer for Roblox projects,
providing a secure, modular, and structured approach to handling
RemoteEvents and RemoteFunctions.

It eliminates repetitive boilerplate and introduces:
  • Centralized rate limiting and validation
  • Replay protection via Nonces (C2S)
  • Scoped listener management for UI and temporary systems
  • Group-based enable/disable controls
  • Request/Response-style RPCs
  • Built-in traffic logging and debug overlay

This allows developers to build scalable and secure multiplayer systems
without manually recreating event validation, request routing, or spam filters.

--------------------------------------------------
NEW IN v0.2.2
--------------------------------------------------
• Added request timeout support to `RequestServer`
• Change whole documentation to be more clear

--------------------------------------------------
FIXES
--------------------------------------------------
• Fixed log entries going over the log entries frame, limited to 15 log entries which after the older entry gets deleted for the new one to appear


==================================================
                   METHODS
==================================================

--------------------------------------------------
NetworkService:FireServer(remoteName: string, arguments: {any}, options: {requiresNonce: boolean?}?)
--------------------------------------------------
DIRECTION: CLIENT → SERVER

Description:
    Sends a request from the client to the server using a standardized
    event payload format. The final element in the `arguments` table
    is automatically reserved for the event name.

    If the event requires a **nonce** (replay protection), the client
    automatically requests one from the server before sending the event.

Arguments:
    • remoteName : string — Registered C2S event name.
    • arguments  : {any}  — Data to send. Must be a table (can be empty).
    • options    : { requiresNonce: boolean? } — Optional.
      When true, event will include and validate a nonce.

Notes:
    • Nonce enforcement protects sensitive events (purchases, currency, etc.).
    • Automatically rate-limited per player and per event on the server.
    • Skipped if the event belongs to a disabled group.

Example (Client):
    NetworkService:FireServer("PurchaseItem", {ItemId = 12}, {requiresNonce = true})

--------------------------------------------------
NetworkService:FireClient(player: Player, remoteName: string, arguments: {any})
--------------------------------------------------
DIRECTION: SERVER → CLIENT

Description:
    Sends data from the server to a single client. The system automatically
    appends the event name to the argument list for listener reference.

Notes:
    • Skipped if the target event is part of a disabled group.
    • Automatically visible in the debug overlay if enabled (F7 toggle).

Example (Server):
    NetworkService:FireClient(player, "DisplayNotification", {"Welcome back!"})

--------------------------------------------------
NetworkService:RequestServer(remoteName: string, arguments: {any}, timeout: number?) → any
--------------------------------------------------
DIRECTION: CLIENT → SERVER (Request/Response)

Description:
    Performs a **remote procedure call (RPC)** to the server and yields
    until the server returns a result or the operation times out.

Behavior:
    • If the server responds before the timeout, the response value is returned.
    • If the timeout (in seconds) elapses without a response, the call returns `false`.
    • If no timeout is defined, the request may yield indefinitely until the server responds.

Arguments:
    • remoteName : string — Registered request name.
    • arguments  : {any}  — Arguments to pass to the server handler.
    • timeout    : number? — Maximum time (in seconds) to wait for response.

Notes:
    • Server handlers are registered via `RegisterRequestC2S`.
    • Requests are rate-limited and validated automatically.
    • Always handle potential `false` returns gracefully.

Example (Client):
    local data = NetworkService:RequestServer("GetInventory", {}, 5)
    if data then
        print("Inventory received:", data)
    else
        warn("Server request timed out")
    end

--------------------------------------------------
NetworkService:RegisterRequestC2S(remoteName: string, handler: (player: Player, arguments: {any}) → any)
--------------------------------------------------
DIRECTION: SERVER ONLY

Description:
    Registers a server-side request handler that responds to
    `RequestServer` calls from clients.

    The function runs in a protected (pcall) environment to prevent
    runtime errors from breaking remote communication.

Example (Server):
    NetworkService:RegisterRequestC2S("GetInventory", function(player)
        return player:GetAttribute("InventoryData")
    end)

--------------------------------------------------
NetworkService:AddSpy(eventName: string, callback: (eventName: string, direction: "C2S" | "S2C", sender: Player?, ...any) → ())
--------------------------------------------------
DIRECTION: GLOBAL (Client or Server)

Description:
    Attaches a passive observer function to a specific event.
    Spies are called every time the event is fired, allowing
    for analytics, debugging, or security logging.

Notes:
    • Spies are run in pcall for safety.
    • Ideal for lightweight telemetry or anomaly detection.
    • Do not perform expensive operations inside spy callbacks.

Example:
    NetworkService:AddSpy("GiveCoins", function(eventName, direction, sender, amount)
        if direction == "C2S" and amount and amount > 25000 then
            warn("[SECURITY] Suspicious currency grant:", sender and sender.Name, amount)
        end
    end)

--------------------------------------------------
NetworkService:FireAllClientsInRadius(targetCharacter: Model, radius: number, eventName: string, arguments: {any})
--------------------------------------------------
DIRECTION: SERVER → CLIENT (Proximity-based)

Description:
    Sends a remote event to all clients within a specified radius of
    a given character. Useful for local visual or sound effects.

Behavior:
    • Only players whose HumanoidRootPart is within `radius` receive the event.
    • The event name is automatically appended to the argument list.

Example (Server):
    NetworkService:FireAllClientsInRadius(
        player.Character,
        30,
        "ExplosionEvent",
        {damage = 100, position = player.Character.PrimaryPart.Position}
    )

Client Example:
    NetworkService:RegisterS2C("ExplosionEvent", function(args)
        local damage = args.damage
        local position = args.position
        print("Explosion at", position, "damage:", damage)
    end)

--------------------------------------------------
NetworkService:RegisterGroup / EnableGroup / DisableGroup / IsGroupEnabled
--------------------------------------------------
PURPOSE:
    Organize events into logical groups that can be enabled or disabled
    dynamically. Useful for subsystems like UI, minigames, or combat.

Behavior:
    • When a group is disabled, all events inside it are ignored.
    • Re-enabling restores normal functionality.
    • Events not in any group remain always active.

Example (Server):
    NetworkService:RegisterGroup("Combat", {"PlayerAttack", "AbilityUsed"})
    NetworkService:DisableGroup("Combat")
    NetworkService:FireClient(player, "PlayerAttack", {damage = 50}) -- Ignored
    NetworkService:EnableGroup("Combat")

--------------------------------------------------
Scopes: CreateScope / scope:RegisterS2C / scope:Destroy
--------------------------------------------------
PURPOSE:
    Allows UI or temporary systems to register listeners that can be
    automatically cleaned up when no longer needed.

Example (Client):
    local scope = NetworkService:CreateScope()
    scope:RegisterS2C("UI_Update", function(args)
        print("UI update received:", args)
    end)
    -- When UI closes:
    scope:Destroy()

Behavior:
    • A scope automatically removes all registered listeners on `Destroy()`.
    • Prevents memory leaks and callback buildup from dynamic systems.
    • Ideal for menus, temporary UI elements, or limited-duration features.

--------------------------------------------------
Security & Debugging Tools
--------------------------------------------------
  • Nonces — replay protection for sensitive C2S events.
  • Rate limiting — prevents remote event spam and brute-force attacks.
  • AddSpy — passive monitoring for analytics or security.
  • Debug Overlay (F7) — live view of traffic and event activity.
  • Timeout-aware RequestServer calls to avoid indefinite yielding.

==================================================
Notes & Best Practices
==================================================
  • Always validate all client-sent data on the server.
  • Keep validator functions deterministic and lightweight.
  • Use Scopes to manage listeners for temporary systems.
  • Enable Nonces for anything involving in-game currency or rewards.
  • Use AddSpy or traffic logs only for development or monitoring.
  • Combine Groups with Scopes for modular, safe, and flexible systems.

==================================================
END OF DOCUMENTATION
==================================================
]]

--======================
--// TYPES //
--======================
export type Validator       = ( player: Player, args: { any }) -> ( boolean, string? )
export type Listener        = ( player: Player, args: { any } ) -> ()
export type C2SEventConfig  = {
	validators: { Validator },
	listeners:  { Listener },
	options: { any }?
}
export type S2CListener     = (args: {any}) -> ()
export type S2CEventConfig  = {
	listeners: { S2CListener },
}
export type RequestHandler  = (player: Player, args: { any }?) -> any
export type SpyCallback     = (eventName: string, direction: "C2S" | "S2C", player: Player?, ...any) -> ()
export type RateLimitEntry  = {
	count: number,
	lastReset: number,
}
export type ScopeEntry      = {
	disconnectors: { () -> () },
}
export type Scope           = {
	RegisterS2C: ( self: Scope, eventName: string, listener: S2CListener ) -> (),
	Destroy:     ( self: Scope ) -> (),
}
export type EventGroup      = {
	events: { string },
	enabled: boolean,
}
export type NonceEntry      = { [ string ]: number } 
export type NonceCacheEntry = {
	nonce: string,
	timestamp: number,
}
export type NonceCacheMap   = { [ string ]: NonceCacheEntry }
export type TrafficEntry    = {
	time: number,
	event: string,
	dir: string,
	sender: string,
	args: { string },
}
export type FireOptions     = {
	requiresNonce: boolean?
}

--======================
--// SERVICES //
--======================
local HttpService       	= game:GetService("HttpService")
local ReplicatedStorage 	= game:GetService("ReplicatedStorage")
local RunService        	= game:GetService("RunService")
local Players           	= game:GetService("Players")
local isServer: boolean 	= RunService:IsServer()

if not ReplicatedStorage:FindFirstChild("Events") then
	local EventsFolder = Instance.new("Folder")
	EventsFolder.Name = "Events"
	EventsFolder.Parent = ReplicatedStorage
end

--======================
--// CONFIG //
--======================
local REMOTE_NAME           	= "NetworkingRemote"
local REMOTE_FUNCTION_NAME  	= "NetworkingRemoteFunction"
local RATE_LIMIT_WINDOW     	= 1   -- seconds
local RATE_LIMIT_MAX        	= 8   -- fires per window(frame) per event per player

local DEBUG                 	= true
local MAX_LOG_ENTRIES       	= 15 -- 15 log entries before the oldest entry gets removed for the new one to appear

local NONCE_EXPIRATION     	 	= 8   -- seconds
local CLEAR_PLAYER_NONCE_CACHE 	= 10 -- clears nonce cache for given eventName and allows for a new nonce

--======================
--// STORAGE //
--======================
local remoteEvent: RemoteEvent?
local remoteFunction: RemoteFunction?
local requestHandlers: { [ string ]: RequestHandler } = {}
local c2sListeners:   { [ string ]: C2SEventConfig } = {}
local s2cListeners:   { [ string ]: S2CEventConfig } = {}
local c2sRateLimits:  { [ number ]: { [ string ]: RateLimitEntry } } = {}
local spyListeners:   { [ string ]: { SpyCallback } } = {}
local scopes:         { [ string ]: ScopeEntry } = {}
local trafficLog:     { TrafficEntry } = {}
local eventGroups:    { [ string ]: EventGroup } = {}
local eventToGroups:  { [ string ]: string } = {}
local activeNonces:   { [ number ]: NonceEntry } = {}
local noncesCache:    { [ number ]: NonceCacheMap } = {}

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
local function getRemote(): RemoteEvent
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

local function getFunction(): RemoteFunction
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

local function checkRateLimit(Player : Player, eventName : string): (boolean,string?)
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

local function validateArgs(eventName : string, Player : Player, ... : any): (boolean,string?)
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
			table.remove(trafficLog,1)
		end
	end

end

local function GenerateNonce(Player: Player, eventName: string): string | false
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
		log("Nonce "..nonce.." expired")
		return false 
	end

	activeNonces[Player.UserId][nonce] = nil

	if not noncesCache[Player.UserId] then
		noncesCache[Player.UserId] = {}
	end

	noncesCache[Player.UserId][eventName] = {nonce = nonce,timestamp = tick()}

	return true
end

function NetworkService:RegisterC2S(eventName : string, validator : Validator, listener : Listener, options: FireOptions?)
	if not isServer then error("RegisterC2S can only be called from server") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid eventName") end

	if not c2sListeners[eventName] then
		c2sListeners[eventName] = {listeners = {}, validators = {}, options = options } :: C2SEventConfig
	end

	table.insert(c2sListeners[eventName].validators,validator)

	if listener then
		table.insert(c2sListeners[eventName].listeners,listener)
	end
	log("Registered C2S event: ",eventName)
end

function NetworkService:RegisterS2C(eventName : string, listener : S2CListener)
	if isServer then error("RegisterS2C can only be called from the client") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end

	if not s2cListeners[eventName] then
		s2cListeners[eventName] = {listeners = {}} :: S2CEventConfig
	end

	table.insert(s2cListeners[eventName].listeners, listener)
	log("Registered S2C event: ",eventName)
end

function NetworkService:RegisterRequestC2S(eventName: string, handler: RequestHandler)
	if not isServer then error("RegisterRequest can only be used to server") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid request name") end
	if typeof(handler) ~= "function" then error("Handler must be a function") end

	requestHandlers[eventName] = handler
	log("Registered C2S RPC:",eventName)
end

function NetworkService:AddSpy(eventName : string, spy : SpyCallback)
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end
	if typeof(spy) ~= "function" then error("Spy must be a function") end

	if not spyListeners[eventName] then
		spyListeners[eventName] = {}
	end

	table.insert(spyListeners[eventName],spy)
	log("Added spy for event: ",eventName)

end

function NetworkService:FireServer(eventName : string, args : any,options: FireOptions?)
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
		if character and character:FindFirstChild("HumanoidRootPart") then
			if (character.HumanoidRootPart.Position - targetCharacter.HumanoidRootPart.Position).Magnitude <= radius then
				local remote = getRemote()
				remote:FireClient(Player,...)
			end
		end
	end
end

function NetworkService:CreateScope(): Scope
	local id = HttpService:GenerateGUID(false)
	scopes[id] = { disconnectors = {} } :: ScopeEntry

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

function NetworkService:RequestServer(eventName: string, args: {any?}, timeout: number?): any
	if isServer then error("RequestServer can only be used on client") end
	if typeof(eventName) ~= "string" then error("Invalid event name") end

	local func = getFunction()
	local data
	task.spawn(function()
		data = func:InvokeServer(eventName,args)
	end)
	task.wait(timeout)
	if not data then
		log("Request Server "..eventName.." timed out in: "..tostring(timeout))
		return false
	else
		return data
	end
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

function NetworkService:EnableGroup(groupName: string): ()
	local group = eventGroups[groupName]
	if not group then
		warn("Group doesnt exists: "..groupName)
		return
	end

	group.enabled = true
	log("Enabled group: "..groupName)
end

function NetworkService:DisableGroup(groupName: string): ()
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

		if typeof(eventName) ~= "string" then
			log("Invalid eventName type from", Player.Name)
			return
		end

		local config = c2sListeners[eventName]
		if not config then
			log("Unregister C2S event: "..eventName)
		end

		if config.options then
			if config.options.requiresNonce then
				local clientSentNonceFlag = args[max-1]

				if clientSentNonceFlag ~= true then
					warn("[NetworkService] Event requires nonce but client didn't provide one: "..eventName)
					return
				end

				local nonce = args[max-2]
				if not NetworkService:ValidateNonce(Player,nonce,eventName) then
					warn("[NetworkService] Invalid nonce for event: "..eventName.." from "..Player.Name)
					return
				else
					log("Nonce validated for: "..eventName)
					table.remove(args,max-1)
					table.remove(args,max-2)
				end
			else
				local clientSentNonceFlag = args[max-1]
				if clientSentNonceFlag == true or clientSentNonceFlag == false then
					table.remove(args,max-1)
					if clientSentNonceFlag == true then
						table.remove(args,max-2)
					end
				end
			end
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
		c2sListeners[Player.UserId] = nil 
		activeNonces[Player.UserId] = nil
		noncesCache[Player.UserId] = nil
	end)
end

return NetworkService
