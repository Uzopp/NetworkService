🛰️ NetworkService (Roblox Luau)

Author: UZOPH
Version: v0.2 [BETA]

A modular, secure networking abstraction layer for Roblox Studio that simplifies RemoteEvent communication between the client and server while adding built-in security features like nonces, rate limiting, event grouping, and scopes.

🚧 Version 0.2 — Updates
🔒 Added: Nonces (Client → Server Replay Protection)

Purpose:
Nonces provide one-time-use, expiration-based tokens that the client must present when sending certain sensitive C2S events. This prevents replay attacks where an exploiter replays old RemoteEvent calls to duplicate purchases, rewards, or other sensitive actions.

⚙️ How It Works

The client requests a nonce from the server (__NONCE request).

The server generates a GUID and stores it in an internal nonce table.

The client includes the nonce when firing the protected C2S event.

The server verifies, consumes, and rejects replays automatically.

✅ Security Properties

Nonces expire automatically (default: 8 seconds, configurable).

Each nonce is one-time-use — consumed on validation.

The client cannot guess or forge valid nonces.

Replay attempts are silently rejected server-side.

💡 Example (Client → Server)
NetworkService:FireServer("PurchaseItem", { itemId }, { requiresNonce = true })


Server-side validator:

NetworkService:RegisterC2S("PurchaseItem", function(player, args)
	return true -- normal validation logic
end, function(player, args)
	-- runs only if nonce was valid and event authorized
end)


Manual nonce request (advanced):

local nonce = NetworkService:RequestServer("__NONCE", { EventName = "MyEvent" })
NetworkService:FireServer("MyEvent", { data, nonce, true })


⚠️ Not recommended — easier for exploiters to detect.

When to use:
Enable nonces only for value-changing events like:

Purchases

Currency updates

Ability triggers

Trades

Invalid or expired nonces do not error — events are silently ignored.

🧩 Methods
🔹 NetworkService:FireClient(player: Player, remoteName: string, arguments: {any})

Direction: Server → Client

Usage:

NetworkService:FireClient(player, "RemoteName", { arg1, arg2 })


Client Listener:

NetworkService:RegisterS2C("RemoteName", function(arguments)
	local remoteName = arguments[#arguments]
end)


Description:
Sends data from the server to a specific client. The final element in arguments is automatically reserved for remoteName.

🔹 NetworkService:FireServer(remoteName: string, arguments: {any})

Direction: Client → Server

Usage:

NetworkService:FireServer("RemoteName", { arg1, arg2 })


Server Registration:

NetworkService:RegisterC2S("RemoteName",
	function(player, arguments)
		return true -- validator
	end,
	function(player, arguments)
		-- listener
	end
)


Notes:

Always validate client-sent data server-side.

Validators should be deterministic and fast.

🔹 NetworkService:RequestServer(remoteName: string, arguments: {any}) → any

Direction: Client → Server (Request/Response)

Usage:

local result = NetworkService:RequestServer("GetPlayerData", { userId })


Server Handler:

NetworkService:RegisterRequestC2S("GetPlayerData", function(player, arguments)
	return someResult
end)


Performs a request-response (RPC) pattern. Automatically validated and rate-limited.

🔹 NetworkService:AddSpy(eventName: string, spyCallback: function)

Direction: Global (Client or Server)

Usage:

NetworkService:AddSpy("GiveCoins", function(eventName, direction, sender, amount)
	if direction == "C2S" and amount and amount > 25000 then
		warn("[SECURITY] Possible exploit:", sender.Name, "requested", amount)
	end
end)


Description:
Registers a passive observer for debugging, telemetry, or exploit detection.
Does not modify normal event flow. Safe to use in production if lightweight.

🔹 NetworkService:FireAllClientsInRadius(targetCharacter: Model, radius: number, eventName: string, arguments: {any})

Direction: Server → Client (Proximity-based)

Usage:

NetworkService:FireAllClientsInRadius(
	player.Character,
	30,
	"ExplosionEvent",
	{ damageAmount, forceVector }
)


Behavior:

Fires to all clients within radius of targetCharacter.

Perfect for localized effects (explosions, buffs, etc).

Works only on the server.

Client Listener:

NetworkService:RegisterS2C("ExplosionEvent", function(args)
	local damageAmount, forceVector = unpack(args)
end)

🔹 Groups: RegisterGroup, EnableGroup, DisableGroup, IsGroupEnabled

Purpose:
Organize events into logical groups that can be toggled dynamically (e.g., combat, UI, mini-games).

Example:

NetworkService:RegisterGroup("Combat", { "PlayerAttack", "AbilityUsed" })
NetworkService:DisableGroup("Combat")
NetworkService:EnableGroup("Combat")


Description:

Disabled groups ignore all events in that group.

Unassigned events are always active.

Useful for toggling subsystems without destroying listeners.

🔹 Scopes: CreateScope, scope:RegisterS2C, scope:Destroy

Purpose:
Create lifecycle-managed listener sets — ideal for UIs or temporary systems.

Example (Client UI):

local scope = NetworkService:CreateScope()
scope:RegisterS2C("UI_Update", function(args) ... end)
scope:RegisterS2C("XP_Gain", function(args) ... end)

-- On UI close
scope:Destroy()


Behavior:

A scope auto-cleans all its listeners when destroyed.

Prevents memory leaks and stray callbacks.

Great for systems that open/close repeatedly.

🧠 Built-in Protections & Tools

⚙️ Rate limiting per player and per event

✅ Validator callbacks for server-side checks

🧰 Debug overlay + traffic logs (toggle with F7)

📡 FireAllClientsInRadius utility for proximity updates

📝 Notes & Best Practices

Always validate client input.

Keep validators fast and deterministic.

Use AddSpy for analytics and exploit detection.

Use Scopes to prevent memory leaks.

Combine Groups + Scopes for flexible event control.

Consider ACLs or permission checks in validators for sensitive remotes.

⚠️ Disclaimer

This module is currently in BETA — you may encounter bugs or unexpected behavior.
Please report issues or feedback via Discord: @uzophh

📄 License — “UZOPH Module License”

Copyright © 2025 UZOPH

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to use, copy, modify, and distribute the Software provided that the following conditions are met:

Attribution: You must give clear credit to the original author “UZOPH” in all copies, forks, or derivative works.

No Rebranding: You may not rename, rebrand, or redistribute this module under another author’s name or claim authorship.

Derivative Sharing: Modified versions may be shared, provided that this same license and credit notice are included.

Commercial Use: Allowed, as long as credit and original author attribution remain intact.

Warranty Disclaimer: The software is provided “as is”, without warranty of any kind.

By using or distributing this software, you agree to the above conditions.

Would you like me to also generate a short LICENSE.txt version of that custom license for your repo’s root folder (so GitHub shows it as a license file)?
