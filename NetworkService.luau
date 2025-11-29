--[[
==================================================
                 NetworkService Module
==================================================
Author: UZOPH
Version: v1.0.0 RELEASE

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
  • Bindable events for server-to-server communication (NEW)

This enables developers to build scalable and secure multiplayer systems
without manually recreating routing logic, validation layers, or spam filters.

--------------------------------------------------
NEW IN v1.0.0
--------------------------------------------------

### Fixed
- **RequestServer without timeout**  
  Fixed an issue where RequestServer malfunctioned when no timeout value
  was provided. It now correctly yields until a server response is received.

- **RequestServer timeout logic (coroutine resume bug)**  
  Fixed a critical issue where timed RequestServer calls attempted to resume
  non-suspended coroutines, causing runtime errors.  
  Timeout and non-timeout logic paths are now safely separated, using
  task.spawn and coroutine handling only when appropriate.  
  Timeouts now function cleanly without blocking or crashing.

- **Timeout always waiting full duration**  
  RequestServer no longer waits the *entire* timeout period when unnecessary.
  It now checks for server responses every 1 second and returns immediately
  when a reply arrives.

- **Debug overlay instantiation**  
  The F7 debug overlay was being recreated for every event fired.
  It now initializes **once per session**, eliminating redundant
  object creation and improving performance.

### Adjusted
- **CLEAR_PLAYER_NONCE_CACHE**  
  Reduced from **10s → 4s**, enabling faster refresh cycles for nonce-based
  C2S protections. This increases security responsiveness in high-frequency
  interactions.

- **NONCE_EXPIRATION**  
  Reduced from **8s → 3s**. This significantly tightens replay protection while
  remaining fully safe across typical network latency (0.3–1.0 sec).

### Improved
- **Memory and table efficiency**  
  Internals now use pre-allocation, table reuse, and reduced dynamic
  allocations, improving performance under heavy networking load.

- **Clear, professional logging (NEW)**  
  All user-facing logs have been rewritten for clarity, consistency, and
  debugging usefulness.

### Optimized
- **Spy callback storage**  
  Spy listeners now use pre-allocated tables to reduce GC pressure and improve
  runtime efficiency.

- **Event group storage**  
  Groups now pre-size internal arrays via table.create(), avoiding unnecessary
  reallocations during gameplay.

### Added
- **Scope:RequestServer**  
  Scopes can now issue isolated RequestServer calls using:
      scope:RequestServer(remoteName, arguments, timeout)

- **Expired ratelimit cleaner**  
  Background cleanup automatically removes outdated ratelimit entries,
  preventing memory buildup and keeping module internals lean.

- **Bindable events for server-to-server communication**  
  NetworkService now includes BindableEvents for internal server-server
  communication, enhancing internal system flexibility.

==================================================
                   METHODS
==================================================

--------------------------------------------------
NetworkService:FireServer(remoteName: string, arguments: {any}, options: {requiresNonce: boolean?}?)
--------------------------------------------------
DIRECTION: CLIENT → SERVER

Description:
    Sends a request from the client to the server using a standardized
    event payload. The event name is automatically appended as the final
    argument.

    If requiresNonce is true, the client obtains and includes a nonce
    (replay protection) before firing the event.

Arguments:
    • remoteName : string — Registered C2S event name.
    • arguments  : {any}  — Data to send (table, possibly empty).
    • options    : { requiresNonce: boolean? } — Optional.

Notes:
    • Nonces protect sensitive actions (currency, purchases, progression).
    • Automatically rate-limited server-side.
    • Ignored if its group is currently disabled.

Example (Client):
    NetworkService:FireServer("PurchaseItem", {ItemId = 12}, {requiresNonce = true})

--------------------------------------------------
NetworkService:FireClient(player: Player, remoteName: string, arguments: {any})
--------------------------------------------------
DIRECTION: SERVER → CLIENT

Description:
    Sends a structured event to a specific client.
    NetworkService automatically appends the event name.

Notes:
    • Ignored if the event's group is disabled.
    • Appears in debug overlay (F7) if enabled.

Example (Server):
    NetworkService:FireClient(player, "DisplayNotification", {"Welcome back!"})

--------------------------------------------------
NetworkService:RequestServer(remoteName: string, arguments: {any}, timeout: number?) → any
--------------------------------------------------
DIRECTION: CLIENT → SERVER

Description:
    Performs a request/response (RPC) invocation to the server.

Behavior:
    • Without timeout: yields indefinitely until the server responds.
    • With timeout: checks for server response every 1 second.
    • On timeout expiration: returns false.

Arguments:
    • remoteName : string
    • arguments  : {any}
    • timeout    : number? — Optional timeout in seconds.

Notes:
    • Validated and rate-limited by the server.
    • Always check for a false result.

Example:
    local inv = NetworkService:RequestServer("GetInventory", {}, 5)
    if not inv then warn("Request timed out") end

--------------------------------------------------
NetworkService:RegisterRequestC2S(remoteName: string, handler: (player: Player, arguments: {any}) → any)
--------------------------------------------------
DIRECTION: SERVER ONLY

Description:
    Registers a server-side function to handle RequestServer calls.
    Runs in pcall for safety.

Example:
    NetworkService:RegisterRequestC2S("GetInventory", function(player)
        return player:GetAttribute("InventoryData")
    end)

--------------------------------------------------
NetworkService:AddSpy(eventName: string, callback: (eventName: string, direction: "C2S" | "S2C", sender: Player?, ...any) → ())
--------------------------------------------------
DIRECTION: GLOBAL

Description:
    Attaches a passive observer executed whenever the event fires,
    useful for analytics and security validation.

Notes:
    • Spies run in pcall.
    • Avoid heavy work inside callbacks.

Example:
    NetworkService:AddSpy("GiveCoins", function(eventName, direction, sender, amount)
        if direction == "C2S" and amount > 25000 then
            warn("[SECURITY] Suspicious currency grant:", sender, amount)
        end
    end)

--------------------------------------------------
NetworkService:FireAllClientsInRadius(targetCharacter: Model, radius: number, eventName: string, arguments: {any})
--------------------------------------------------
DIRECTION: SERVER → CLIENT

Description:
    Sends an event to all players within `radius` of the target character.

Behavior:
    • Only players within the radius receive the event.

Example (Server):
    NetworkService:FireAllClientsInRadius(
        player.Character,
        30,
        "ExplosionEvent",
        {damage = 100, position = player.Character.PrimaryPart.Position}
    )

Client Example:
    NetworkService:RegisterS2C("ExplosionEvent", function(args)
        print("Explosion at", args.position, "damage:", args.damage)
    end)

--------------------------------------------------
NetworkService:RegisterGroup / EnableGroup / DisableGroup / IsGroupEnabled
--------------------------------------------------
Purpose:
    Organize events into logical groups for dynamic enabling/disabling.

Behavior:
    • Disabled groups ignore all related events.
    • Re-enabling restores functionality.

Example:
    NetworkService:RegisterGroup("Combat", {"PlayerAttack", "AbilityUsed"})
    NetworkService:DisableGroup("Combat")
    NetworkService:EnableGroup("Combat")

--------------------------------------------------
Scopes: CreateScope / scope:RegisterS2C / scope:RequestServer / scope:Destroy
--------------------------------------------------
Purpose:
    Allows temporary systems (UI, cutscenes, menus, etc.) to register listeners
    that auto-clean when the scope is destroyed.

Example:
    local scope = NetworkService:CreateScope()

    scope:RegisterS2C("UI_Update", function(args)
        print("UI updated:", args)
    end)

    local inventory = scope:RequestServer("Inventory_Data", {}, 4)

    scope:Destroy()

Behavior:
    • Destroy() removes all listeners.
    • Prevents callback buildup and memory leaks.

--------------------------------------------------
NetworkService:FireServerBindable(arguments: {any})
--------------------------------------------------
DIRECTION: SERVER → SERVER

Description:  
    Invokes a BindableEvent from one server context to another, allowing
    internal server-to-server communication without involving clients.
    This is useful for modular systems where different server scripts
    need to send actions or data to one another in a structured way.

Example (Server):
    NetworkService:FireServerBindable(
        "Inventory_Purchase",
        {
            player = player,
            action = "Purchase",
            item = "Sword"
        }
    )
--------------------------------------------------
NetworkService:RegisterS2S(arguments: {any})
--------------------------------------------------
DIRECTION: SERVER ONLY

Description:  
    Registers a server-to-server BindableEvent listener.  
    When the specified server event is fired using `FireServerBindable`,
    the associated callback will run and receive the provided arguments.

Example:
    NetworkService:RegisterS2S("Inventory_Purchase", function(player, args)
        -- Handle purchase logic here
    end)

--------------------------------------------------
Security & Debugging Tools
--------------------------------------------------
  • Nonce-based C2S replay protection
  • Centralized rate limiting
  • Spy callbacks
  • Debug overlay (F7)
  • Clean, optimized logging (v1.0.1)
  • Timeout-aware RPC requests

==================================================
Notes & Best Practices
==================================================
  • Always validate client-submitted data.
  • Keep validation deterministic and lightweight.
  • Use Scopes for temporary or UI systems.
  • Use Nonces for sensitive actions (currency, progression).
  • Group events for modular control.
  • Use Spy logs & debug overlay for monitoring and debugging.

==================================================
END OF DOCUMENTATION
==================================================
]]--


--======================
--// TYPES //
--======================
type Validator       = ( player: Player, args: { any }) -> ( boolean, string? )
type Listener        = ( player: Player, args: { any } ) -> ()
type S2SListener	 = (args: { any } ) -> ()

type C2SEventConfig  = {
	validators: { Validator },
	listeners:  { Listener },
	options: { any }?
}

type S2SEventConfig = {
	listeners: { Listener }
}

type S2CListener     = (args: {any}) -> ()
type S2CEventConfig  = {
	listeners: { S2CListener },
}
type RequestHandler  = (player: Player, args: { any }?) -> any

type SpyCallback     = (eventName: string, direction: "C2S" | "S2C", player: Player?, ...any) -> ()
type RateLimitEntry  = {
	count: number,
	lastReset: number,
}
type ScopeEntry      = {
	disconnectors: { () -> () },
}
type Scope           = {
	RegisterS2C: ( self: Scope, eventName: string, listener: S2CListener ) -> (),
	RequestServer: ( self: Scope, eventName: string, args: { any }, timeout: number?) -> (),
	Destroy:     ( self: Scope ) -> (),
}
type EventGroup      = {
	events: { string },
	enabled: boolean,
}
type NonceEntry      = { [ string ]: number } 
type NonceCacheEntry = {
	nonce: string,
	timestamp: number,
}
type NonceCacheMap   = { [ string ]: NonceCacheEntry }
type TrafficEntry    = {
	time: number,
	event: string,
	dir: string,
	sender: string,
	args: { string },
}
type FireOptions     = {
	requiresNonce: boolean?
}

--======================
--// SERVICES //
--======================
local HttpService       	= game:GetService("HttpService")
local ReplicatedStorage 	= game:GetService("ReplicatedStorage")
local RunService        	= game:GetService("RunService")
local Players           	= game:GetService("Players")
local MessagingService		= game:GetService("MessagingService")
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
local REMOTE_BINDABLE_NAME		= "NetworkingRemoteBindable"
local RATE_LIMIT_WINDOW     	= 1   -- seconds
local RATE_LIMIT_MAX        	= 8   -- fires per window(frame) per event per player

local DEBUG                 	= true
local MAX_LOG_ENTRIES       	= 15 -- 15 log entries before the oldest entry gets removed for the new one to appear

local NONCE_EXPIRATION     	 	= 8   -- seconds
local CLEAR_PLAYER_NONCE_CACHE 	= 4 -- clears nonce cache for given eventName and allows for a new nonce

local CLEANUP_TIME = 60 -- seconds

--======================
--// STORAGE //
--======================
local remoteEvent: RemoteEvent?
local remoteFunction: RemoteFunction?
local remoteBindable: BindableEvent?
local requestHandlers: { [ string ]: RequestHandler } = {}
local c2sListeners:   { [ string ]: C2SEventConfig } = {}
local s2cListeners:   { [ string ]: S2CEventConfig } = {}
local s2sListeners:	   { [ string ]: S2SEventConfig } = {}
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

local function getBindable(): BindableEvent
	if not remoteBindable then
		remoteBindable = ReplicatedStorage.Events:FindFirstChild(REMOTE_BINDABLE_NAME)
		if not remoteBindable then
			remoteBindable = Instance.new("BindableEvent")
			remoteBindable.Name = REMOTE_BINDABLE_NAME
			remoteBindable.Parent = ReplicatedStorage.Events
		end
	end
	return remoteBindable
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

local function cleanupExpiredRateLimits()
	local now = os.clock()
	for userId, events in pairs(c2sRateLimits) do
		for eventName, data in pairs(events) do
			print(data)
			if now - data.lastReset > RATE_LIMIT_WINDOW * 2 then
				events[eventName] = nil
			end
		end
		if next(events) == nil then
			c2sRateLimits[userId] = nil
		end
	end
	if DEBUG then
		log("Cleaned expired rate limits")
	end
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
		local argCount = #rawArgs
		local displayArgs = table.create(argCount)
		
		for i = 1, argCount do
			local v = rawArgs[i]
			local vType = typeof(v)
			if vType == "table" then
				displayArgs[i] = "<table>"
			elseif vType == "Instance" then
				displayArgs[i] = v:GetFullName()
			else
				displayArgs[i] = tostring(v)
			end
		end

		table.insert(trafficLog, {
			time = os.clock(),
			event = eventName,
			dir = direction,
			sender = (sender and sender.Name) or "Server",
			args = displayArgs
		})

		if #trafficLog > MAX_LOG_ENTRIES then
			table.remove(trafficLog, 1)
		end
	end

end

local function GenerateNonce(Player: Player, eventName: string): string | false
	local userId = Player.UserId
	local userCache = noncesCache[userId]
	
	if not userCache then
		userCache = {}
		noncesCache[userId] = userCache
	end
	
	local cachedEntry = userCache[eventName]
	if cachedEntry then 
		if tick() - cachedEntry.timestamp >= CLEAR_PLAYER_NONCE_CACHE then
			userCache[eventName] = nil
		else
			warn("[NetworkService] Cache found for event: "..eventName..", can't create nonce")
			return false 
		end
	end
	
	local nonce = HttpService:GenerateGUID(false)
	local now = os.clock()

	local userNonces = activeNonces[userId]
	if not userNonces then
		userNonces = {}
		activeNonces[userId] = userNonces
	end

	userNonces[nonce] = now + NONCE_EXPIRATION

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

function NetworkService:RegisterS2S(eventName: string,listener: S2SListener)
	if not isServer then error("RegisterS2S can only be called from server") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid eventName") end
	
	if not s2sListeners[eventName] then
		s2sListeners[eventName] = {listeners = {}} :: S2SEventConfig
	end
	
	table.insert(s2sListeners[eventName].listeners,listener)
	
	log("Registered S2S Event: ",eventName)
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
	log("Fired from client to server: ",eventName)
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
	log("Fired from server to client: ", Player.Name,eventName)
end

function NetworkService:FireServerBindable(eventName: string, ... : any)
	if not isServer then error("FireServerBindable can only be called from the server") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end
	if not isEventEnabled(eventName) then
		log("Skipped firing event (group disabled): "..eventName)
		return
	end
	
	table.insert(...,eventName)
	
	local remote = getBindable()
	remote:Fire(...)
	fireSpies(eventName,"S2S",nil,...)
	log("Fire from server to server: ",eventName)
end

function NetworkService:FireAllClients(eventName : string, ... : any)
	if not isServer then error("FireAllClients can only be called from the server") end
	if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end

	table.insert(...,eventName)

	local remote = getRemote()
	remote:FireAllClients(...)
	fireSpies(eventName,"S2C",nil,...)
	log("Fired to all clients from server: ",eventName)
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

function NetworkService:CreateScope(Player: Player?): Scope
	local id = HttpService:GenerateGUID(false)
	scopes[id] = {
		disconnectors = {},
	} :: ScopeEntry

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
	
	function scope:RequestServer(eventName: string,args: {any}, timeout: number?)
		if isServer then error("RequestServer can only be called from the client") end
		if typeof(eventName) ~= "string" or eventName == "" then error("Invalid event name") end
		if not isEventEnabled(eventName) then
			log("Skipped firing event (group disabled): "..eventName)
			return
		end
	
		local func = getFunction()
		local success, result = pcall(func.InvokeServer, func, eventName, args)
		if success then
			return result
		else
			warn("RequestServer error (no timeout):", result)
			return false
		end
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

    if not timeout then
        local success, result = pcall(func.InvokeServer, func, eventName, args)
        if success then
            return result
        else
            warn("RequestServer error (no timeout):", result)
            return false
        end
    end


    local start = os.clock()
    local co = coroutine.running()
    local responseReceived = false
    local responseValue

    task.spawn(function()
        local success, result = pcall(func.InvokeServer, func, eventName, args)
        if not responseReceived then 
            responseValue = success and result or false
            responseReceived = true
            if coroutine.status(co) == "suspended" then
                coroutine.resume(co)
            end
        end
    end)

    while os.clock() - start < timeout do
        if responseReceived then
            return responseValue
        end
        task.wait()
    end

    responseReceived = true 
    log("RequestServer timed out: " .. eventName)
    return false
end

function NetworkService:RegisterGroup(groupName: string,events: {string})
	if typeof(groupName) ~= "string" or groupName == "" then
		error("Invalid group name")
	end
	if typeof(events) ~= "table" then
		error("Events must be provided in a table")
	end

	local eventCount = #events
	eventGroups[groupName] = {
		events = table.create(eventCount),
		enabled = true
	}
	local groupEvents = eventGroups[groupName].events
	for _, eventName in ipairs(events) do
		if typeof(eventName) == "string" and eventName ~= "" then
			table.insert(groupEvents, eventName)
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
	getBindable().Event:Connect(function(args: {any})
		local args = args or {}
		local max = #args
		local eventName = args[max]
		
		if typeof(eventName) ~= "string" then
			log("Invalid eventName type")
			return
		end
		
		local config = s2sListeners[eventName]
		if not config then
			log("No listener for event: "..eventName)
			return
		end
		
		for _,listener in ipairs(config.listeners) do
			local ok,err = pcall(listener, args)
			if not ok then
				warn("Error in S2S handler for: ",eventName,":",err)
			end
		end
		
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
		local max = #args
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
	if DEBUG and RunService:IsStudio() then
			task.spawn(function()
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
		end)
	end
	getRemote().OnClientEvent:Connect(function(...)
		local args = ...
		local max = #args
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
	task.spawn(function()
		while true do
			task.wait(CLEANUP_TIME)
			cleanupExpiredRateLimits()
		end
	end)
	Players.PlayerRemoving:Connect(function(Player : Player)
		c2sListeners[Player.UserId] = nil 
		activeNonces[Player.UserId] = nil
	end)
end

return NetworkService
