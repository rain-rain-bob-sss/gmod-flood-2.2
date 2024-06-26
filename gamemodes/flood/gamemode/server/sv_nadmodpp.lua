-- Nebual 2012 (nebual@nebtown.info) presents:
-- NADMOD Prop Protection
-- Inspired by Spacetech's Simple Prop Protection, <3's
-- Bugs? Feature requests? "why are you using JSON?!"? Email me or poke the Facepunch http://www.facepunch.com/showthread.php?t=1221183

if not NADMOD then
	-- User is running without my Admin mod NADMOD, lets just copy some required initialization stuff over here
	concommand.Add("nadmod_reload", function(ply,cmd,args) 
		if args[1] == "full" then NADMOD = nil end
		include("autorun/server/nadmod_pp.lua")
	end)
	NADMOD = util.JSONToTable(file.Read("nadmod_config.txt","DATA") or "") or {Users = {}, Groups = {}, Bans = {}, PPConfig = {}}
	function NADMOD.Save()
		file.Write("nadmod_config.txt", util.TableToJSON({Users = NADMOD.Users, Groups = NADMOD.Groups, Bans = NADMOD.Bans, PPConfig = NADMOD.PPConfig}))
	end
	hook.Add("Shutdown","NADMOD.Save",NADMOD.Save)
	function NADMOD.FindPlayer(nick) 
		if not nick or nick == "" then return end 
		nick = string.lower(nick)
		local num = tonumber(nick)
		for _,v in pairs(player.GetAll()) do
			if string.lower(v:Nick()) == nick then return v -- Exact name match
			elseif v:UserID() == num then return v 			-- UserID match (from status)
			end
		end
		-- If the above two exact searches fail, try doing a partial search
		for _,v in pairs(player.GetAll()) do
			if string.find(string.lower(v:Nick()), nick) then return v end
		end
	end
end
if not NADMOD.Props then
	-- NADMOD PP Initialization
	NADMOD.PPVersion = "1.2.6p moded by rb"
	NADMOD.Props = {} // {entid = {Ent = ent, Owner = ply, SteamID = ply:SteamID(), Name = ply:Nick() or "W" or "O"}}
	NADMOD.PropOwnersSmall = {} // A smaller buffer of PropOwner names to send to current players
	NADMOD.AutoCDPTimers = {}
	
	local oldCPPI = CPPI
	CPPI = {}
	
	-- Copy over default settings if they aren't present in the disk's PPConfig
	for k,v in pairs({toggle=true,use=true,adminall=true,autocdp=0,autocdpadmins=false}) do
		if NADMOD.PPConfig[k] == nil then NADMOD.PPConfig[k] = v end
	end
	
	--AddCSLuaFile("autorun/client/cl_nadmodpp.lua")
	util.AddNetworkString("nadmod_propowners")
	util.AddNetworkString("nadmod_ppfriends")
	util.AddNetworkString("nadmod_ppconfig")
	util.AddNetworkString("nadmod_cleanclragdolls")
	util.AddNetworkString("nadmod_notify")
	
	timer.Create("WarnOtherPPs", 0, 1, function()
		//Print a harmless error if we detect other PP's active, since this often leads to confusion. NPP'll still load fine
		//Known CPPI plugins: FPP, SPP, NPP, ULX's UPS
		if not oldCPPI or (oldCPPI.GetName and oldCPPI:GetName() == "Nadmod Prop Protection") then oldCPPI = CPPI end
		if oldCPPI and (not oldCPPI.GetName or oldCPPI:GetName() ~= "Nadmod Prop Protection") then Error("NPP has detected "..(oldCPPI.GetName and oldCPPI:GetName() or "another CPPI PP").." is installed, you probably only want one PP active at a time!!\n")
		elseif PP_Settings then Error("NPP has detected Evolve's PP plugin, you probably only want one PP active at a time!!\n")
		end
	end)
end
local metaply = FindMetaTable("Player")
local metaent = FindMetaTable("Entity")

-- Does your admin mod not seem to work with Nadmod PP? Try overriding this function!
function NADMOD.IsPPAdmin(ply)
	if NADMOD.HasPermission then
		return NADMOD.HasPermission(ply, "PP_All")
	else
		-- If the admin mod NADMOD isn't present, just default to using IsAdmin
		return ply:IsAdmin()
	end
end

function NADMOD.PPInitPlayer(ply)
	local steamid = ply:SteamID()
	for _,v in pairs(NADMOD.Props) do
		if v.SteamID == steamid then 
			v.Owner = ply
			v.Ent.SPPOwner = ply
			v.Ent.Owner = ply
		end
	end
	net.Start("nadmod_propowners")
		net.WriteUInt(table.Count(NADMOD.Props),16)
		for k,v in pairs(NADMOD.Props) do
			net.WriteUInt(k,16)
			net.WriteString(v.Name)
		end
	net.Send(ply)
end
hook.Add("PlayerInitialSpawn", "NADMOD.PPInitPlayer", NADMOD.PPInitPlayer)

function NADMOD.RefreshOwners()
	if next(NADMOD.PropOwnersSmall) then
		net.Start("nadmod_propowners")
			net.WriteUInt(table.Count(NADMOD.PropOwnersSmall),16)
			for k,v in pairs(NADMOD.PropOwnersSmall) do
				net.WriteUInt(k,16)
				net.WriteString(v)
			end
			//net.WriteTable(NADMOD.PropOwnersSmall)
		net.Broadcast()
		table.Empty(NADMOD.PropOwnersSmall)
	end
end
timer.Create("NADMOD.RefreshOwners", 1, 0, NADMOD.RefreshOwners)

function NADMOD.IsFriendProp(ply, ent)
	if IsValid(ent) && IsValid(ply) && ply:IsPlayer() && NADMOD.Props[ent:EntIndex()] then
		local ownerSteamID = NADMOD.Props[ent:EntIndex()].SteamID
		if NADMOD.Users[ownerSteamID] then
			local friends = NADMOD.Users[ownerSteamID].Friends
			return friends && friends[ply:SteamID()]
		end
	end
	return false
end

function NADMOD.PlayerCanTouch(ply, ent)
	-- If PP is off or the ent is worldspawn, let them touch it
	if not tobool(NADMOD.PPConfig["toggle"]) or ent:IsWorld() then return true end
		-- Admins can touch anyones props + world
	if NADMOD.PPConfig["adminall"] and NADMOD.IsPPAdmin(ply) then return true end
	if !IsValid(ent) or !IsValid(ply) or ent:IsPlayer() or !ply:IsPlayer() then return false end
	
	if not NADMOD.Props[ent:EntIndex()] then
		local class = ent:GetClass()
		if(string.find(class, "stone_") == 1 or string.find(class, "rock_") == 1 or string.find(class, "stargate_") == 0 or string.find(class, "dhd_") == 0 or class == "flag" or class == "item") then
			NADMOD.SetOwnerWorld(ent)
		else
			--NADMOD.PlayerMakePropOwner(ply, ent)
			--NADMOD.Notify(ply, "You may not touch this prop.")
			return false
		end
	end
	-- Ownerless props cannot touch by all
	if NADMOD.Props[ent:EntIndex()].Name == "O" then return false end 
	-- Players can touch their own props and friends
	if NADMOD.Props[ent:EntIndex()].SteamID == ply:SteamID() or NADMOD.IsFriendProp(ply, ent) then return true end
	
	return false
end

-- We could hook directly to PlayerCanTouch, but returning true stops other hooks from being called
function NADMOD.PlayerCanTouchSafe(ply, ent)
	if !IsValid(ent) or ent:IsPlayer() then return end
	if !NADMOD.PlayerCanTouch(ply,ent) then return false end
end
hook.Add("PhysgunPickup", "NADMOD.PhysgunPickup", NADMOD.PlayerCanTouchSafe)
hook.Add("CanProperty", "NADMOD.CanProperty", function(ply, mode, ent) return NADMOD.PlayerCanTouchSafe(ply, ent) end)
hook.Add("CanEditVariable", "NADMOD.CanEditVariable", function(ent, ply, key, val, editor) return NADMOD.PlayerCanTouchSafe(ply, ent) end)

function NADMOD.OnPhysgunReload(weapon, ply)
	local tr = util.TraceLine(util.GetPlayerTrace(ply))
	if not tr.HitNonWorld or !tr.Entity:IsValid() or tr.Entity:IsPlayer() then return end
	if !NADMOD.PlayerCanTouch(ply, tr.Entity) then return false end
end
hook.Add("OnPhysgunReload", "NADMOD.OnPhysgunReload", NADMOD.OnPhysgunReload)

-- Basically just PlayerCanTouchSafe, but world props are fine to gravgun
function NADMOD.GravGunPickup(ply, ent)
	if !IsValid(ent) or ent:IsPlayer() then return end
	if NADMOD.Props[ent:EntIndex()] and NADMOD.Props[ent:EntIndex()].Name == "W" then return end
	if !NADMOD.PlayerCanTouch(ply,ent) then return false end
end
hook.Add("GravGunPunt", "NADMOD.GravGunPunt", NADMOD.GravGunPickup)
hook.Add("GravGunPickupAllowed", "NADMOD.GravGunPickupAllowed", NADMOD.GravGunPickup)

NADMOD.PPWeirdTraces = {"wire_winch","wire_hydraulic","slider","hydraulic","winch","muscle"}
function NADMOD.CanTool(ply, tr, mode)
	local ent = tr.Entity
	if !ent:IsWorld() and (!ent:IsValid() or ent:IsPlayer()) then return false end
	if !NADMOD.PlayerCanTouch(ply, ent) then
		if not ((NADMOD.Props[ent:EntIndex()] or {}).Name == "W" and (mode == "wire_debugger" or mode == "wire_adv")) then 
			return false
		end
	elseif(mode == "nail") then
		local Trace = {}
		Trace.start = tr.HitPos
		Trace.endpos = tr.HitPos + (ply:GetAimVector() * 16.0)
		Trace.filter = {ply, tr.Entity}
		local tr2 = util.TraceLine(Trace)
		if(tr2.Hit and IsValid(tr2.Entity) and !tr2.Entity:IsPlayer()) then
			if(!NADMOD.PlayerCanTouch(ply, tr2.Entity)) then
				return false
			end
		end
	elseif(table.HasValue(NADMOD.PPWeirdTraces, mode)) then
		local Trace = {}
		Trace.start = tr.HitPos
		Trace.endpos = Trace.start + (tr.HitNormal * 16384)
		Trace.filter = {ply}
		local tr2 = util.TraceLine(Trace)
		if(tr2.Hit and IsValid(tr2.Entity) and !tr2.Entity:IsPlayer()) then
			if(!NADMOD.PlayerCanTouch(ply, tr2.Entity)) then
				return false
			end
		end
	elseif(mode == "remover") then
		if(ply:KeyDown(IN_ATTACK2) or ply:KeyDownLast(IN_ATTACK2)) then
			for k,v in pairs(constraint.GetAllConstrainedEntities(ent) or {}) do
				if !NADMOD.PlayerCanTouch(ply, v) then
					return false
				end
			end
		end
	end
end
hook.Add("CanTool", "NADMOD.CanTool", NADMOD.CanTool)

function NADMOD.PlayerUse(ply, ent)
	if !NADMOD.PPConfig["use"] or NADMOD.PlayerCanTouch(ply, ent) or (ent:IsValid() and NADMOD.Props[ent:EntIndex()].Name == "W") then
		return
	end
	return false
end
hook.Add("PlayerUse", "NADMOD.PlayerUse", NADMOD.PlayerUse)

--==========================================================--
--   Ownership Setting Functions							--
--==========================================================--

function NADMOD.PlayerMakePropOwner(ply,ent)
	if !IsValid(ent) or !IsValid(ply) or ent:IsPlayer() or !ply:IsPlayer() then return end
	NADMOD.Props[ent:EntIndex()] = {
		Ent = ent,
		Owner = ply,
		SteamID = ply:SteamID(),
		Name = ply:Nick()
	}
	NADMOD.PropOwnersSmall[ent:EntIndex()] = ply:Nick()
	ent.SPPOwner = ply
	ent.Owner = ply
end
-- Hook into the cleanup and sbox-limit adding functions to catch most props
if(cleanup) then
	local backupcleanupAdd = cleanup.Add
	function cleanup.Add(ply, enttype, ent)
		if IsValid(ent) and ply:IsPlayer() then
			NADMOD.PlayerMakePropOwner(ply, ent)
		end
		backupcleanupAdd(ply, enttype, ent)
	end
end
if(metaply.AddCount) then
	local backupAddCount = metaply.AddCount
	function metaply:AddCount(enttype, ent)
		NADMOD.PlayerMakePropOwner(self, ent)
		backupAddCount(self, enttype, ent)
	end
end
hook.Add("PlayerSpawnedSENT", "NADMOD.PlayerSpawnedSENT", NADMOD.PlayerMakePropOwner)
hook.Add("PlayerSpawnedVehicle", "NADMOD.PlayerSpawnedVehicle", NADMOD.PlayerMakePropOwner)
hook.Add("PlayerSpawnedSWEP", "NADMOD.PlayerSpawnedSWEP", NADMOD.PlayerMakePropOwner)

function metaent:CPPISetOwnerless(bool)
	if !IsValid(self) or self:IsPlayer() then return end
	if(bool) then
		NADMOD.Props[self:EntIndex()] = {
			Ent = self,
			Owner = game.GetWorld(),
			SteamID = "O",
			Name = "O"
		}
		NADMOD.PropOwnersSmall[self:EntIndex()] = "O"
		self.SPPOwner = game.GetWorld()
		self.Owner = game.GetWorld()
	else
		NADMOD.EntityRemoved(self)
	end
end

function NADMOD.SetOwnerWorld(ent)
	NADMOD.Props[ent:EntIndex()] = {
		Ent = ent,
		Owner = game.GetWorld(),
		SteamID = "W",
		Name = "W"
	}
	ent.SPPOwner = game.GetWorld()
	ent.Owner = game.GetWorld()
end

-- Loop through all entities that exist when the map is loaded, these are all "world owned" entities
function NADMOD.WorldOwner()
	local WorldEnts = 0
	for k,v in pairs(ents.FindByClass("*")) do
		if(!v:IsPlayer() and !NADMOD.Props[v:EntIndex()]) and not IsValid(v.Owner) then
			if game.GetMap() == "gm_construct" and v:GetClass() == "func_brush" then
				v:CPPISetOwnerless(true)
			else
				NADMOD.SetOwnerWorld(v)
			end
			WorldEnts = WorldEnts + 1
		end
	end
	print("Nadmod Prop Protection: "..WorldEnts.." props belong to world")
end
if CurTime() < 5 then timer.Create("NADMOD.PPFindWorldProps",7,1,NADMOD.WorldOwner) end


function NADMOD.EntityRemoved(ent)
	NADMOD.Props[ent:EntIndex()] = nil
	NADMOD.PropOwnersSmall[ent:EntIndex()] = "-"
	if ent:IsValid() and ent:IsPlayer() and not ent:IsBot() then
		-- This is more reliable than PlayerDisconnect
		local steamid, nick = ent:SteamID(), ent:Nick()
		if NADMOD.PPConfig.autocdp > 0 and (NADMOD.PPConfig.autocdpadmins or not NADMOD.IsPPAdmin(ent)) then 
			timer.Create("NADMOD.AutoCDP_"..steamid, NADMOD.PPConfig.autocdp, 1, function() 
				local count = NADMOD.CleanupPlayerProps(steamid)
				if count > 0 then NADMOD.Notify(nick.."'s props ("..count..") have been autocleaned.") end
			end)
			NADMOD.AutoCDPTimers[nick] = steamid
		end
	end
end
hook.Add("EntityRemoved", "NADMOD.EntityRemoved", NADMOD.EntityRemoved)
-- AutoCDP timer removal
function NADMOD.ClearAutoCDP( ply, steamid, uniqueid )
	timer.Remove("NADMOD.AutoCDP_"..steamid)
end
hook.Add( "PlayerAuthed", "NADMOD.ClearAutoCDP", NADMOD.ClearAutoCDP ) -- This occurs at PlayerInitialSpawn, late
hook.Add( "PlayerConnect", "NADMOD.ClearAutoCDP", function(nick, address) -- This occurs early but is unreliable
	NADMOD.ClearAutoCDP(nil, NADMOD.AutoCDPTimers[nick] or "")
end)




--==========================================================--
--   Useful Concommands				  	 					--
--==========================================================--
function NADMOD.CleanupPlayerProps(steamid)
	local count = 0
	for k,v in pairs(NADMOD.Props) do
		if(v.SteamID == steamid) then
			if IsValid(v.Ent) then 
				v.Ent:Remove() 
				count = count + 1 
			else
				NADMOD.EntityRemoved(v.Ent)
			end
		end
	end
	return count
end

function NADMOD.CleanPlayer(tar)
	if IsValid(tar) and tar:IsPlayer() then 
		local count = NADMOD.CleanupPlayerProps(tar:SteamID())
		NADMOD.Notify(tar:Nick().."'s props have been cleaned up ("..count..")")
	end
end

function NADMOD.CleanupProps(ply, cmd, args)
	local EntIndex = args[1]
	if not EntIndex or EntIndex == "" then
		local count = NADMOD.CleanupPlayerProps(ply:SteamID())
		NADMOD.Notify(ply,"Your props have been cleaned up ("..count..")")
	elseif !ply:IsValid() or NADMOD.IsPPAdmin(ply) then
		NADMOD.CleanPlayer(Entity(EntIndex))
	end
end
concommand.Add("nadmod_cleanupprops", NADMOD.CleanupProps)

function NADMOD.CleanPlayerConCommand(ply, cmd, args, fullstr)
	if ply:IsValid() and not NADMOD.IsPPAdmin(ply) then return end
	NADMOD.CleanPlayer(NADMOD.FindPlayer(fullstr))
end
concommand.Add("nadmod_cleanplayer", NADMOD.CleanPlayerConCommand)

-- Cleans all props whose owner's name contained arg1. nadmod_cleanplayer is better, but only works on online players
function NADMOD.CleanName(ply, cmd, args, fullstr)
	if ply:IsValid() and not NADMOD.IsPPAdmin(ply) then return end
	if fullstr == "" or fullstr == "W" then return end
	local tarname = string.lower(fullstr)
	local count = 0
	for k,v in pairs(NADMOD.Props) do
		if IsValid(v.Ent) and string.find(string.lower(v.Name),tarname,1,true) then 
			v.Ent:Remove() 
			count = count + 1
		end
	end
	NADMOD.Notify(fullstr.."'s props ("..count..") have been cleaned up")
end
concommand.Add("nadmod_cleanname",NADMOD.CleanName)

function NADMOD.CDP(ply, cmd, args)
	if ply:IsValid() and not NADMOD.IsPPAdmin(ply) then return end
	local count = 0
	for k,v in pairs(NADMOD.Props) do
		if not v.Ent:IsValid() then
			NADMOD.EntityRemoved(v.Ent)
		elseif not IsValid(v.Owner) and (v.Name != "O" and v.Name != "W") then 
			v.Ent:Remove() 
			count = count + 1
		end
	end
	NADMOD.Notify("Disconnected players props ("..count..") have been cleaned up")
end
concommand.Add("nadmod_cdp",NADMOD.CDP)

function NADMOD.CleanClass(ply,cmd,args)
	if ply:IsValid() and not NADMOD.IsPPAdmin(ply) then return end
	if args[1] == "npc_*" then NADMOD.Notify("NPCs have been cleaned up")
	elseif args[1] == "prop_ragdol*" then NADMOD.Notify("Ragdolls have been cleaned up")
	else NADMOD.Notify(args[1].." have been cleaned up")
	end
	for _,v in ipairs(ents.FindByClass(args[1])) do v:Remove() end
end
concommand.Add("nadmod_cleanclass", NADMOD.CleanClass)

function NADMOD.CleanCLRagdolls(ply,cmd,args)
	if ply:IsValid() and not NADMOD.IsPPAdmin(ply) then return end
	NADMOD.Notify("Clientside Ragdolls have been cleaned up")
	net.Start("nadmod_cleanclragdolls") net.Broadcast()
end
concommand.Add("nadmod_cleanclragdolls", NADMOD.CleanCLRagdolls)

-- Sends a Hint to the player specified
-- If only one argument, broadcast to all players
function NADMOD.Notify(ply, text)
	net.Start("nadmod_notify")
	if not text then
		net.WriteString(ply)
		net.Broadcast()
		print("NADMOD: "..ply)
	else
		net.WriteString(text)
		net.Send(ply)
	end
end

function NADMOD.DebugTotals(ply,cmd,args)
	-- Prints out a list of how many props are owned by each player.
	-- This information is available in the clientside admin panel, but this is nice for rcon
	if IsValid(ply) then return end -- PrintTable only shows in serverconsole
	local tab = {}
	for k,v in pairs(NADMOD.Props) do
		local name = v.Name
		if name == "O" then name = "Ownerless"
		elseif name == "W" then name = "World"
		elseif not v.Owner:IsValid() then name = "[Disconnected]"..name
		end
		tab[name] = (tab[name] or 0) + 1
	end
	PrintTable(tab)
end
concommand.Add("nadmod_totals", NADMOD.DebugTotals)


--=========================================================--
--   Clientside Callbacks for the Friends/Options panels   --
--=========================================================--
concommand.Add("npp_refreshconfig",function(ply,cmd,args)
	if not ply:IsValid() or not NADMOD.IsPPAdmin(ply) then return end
	net.Start("nadmod_ppconfig")
		net.WriteTable(NADMOD.PPConfig)
	net.Send(ply)
end)
net.Receive("nadmod_ppconfig",function(len,ply)
	if not ply:IsValid() or not NADMOD.IsPPAdmin(ply) then return end
	NADMOD.PPConfig = net.ReadTable()
	NADMOD.Save()
	NADMOD.Notify(ply, "Settings received!")
end)
concommand.Add("npp_refreshfriends",function(ply,cmd,args)
	if not ply:IsValid() then return end
	local friends = {}
	if NADMOD.Users[ply:SteamID()] then friends = table.Copy(NADMOD.Users[ply:SteamID()].Friends) or {} end
	if NADMOD.PPConfig["adminall"] then
		for _,v in pairs(player.GetAll()) do
			--Dafaq,its doesn't mean you should check it
			--if NADMOD.IsPPAdmin(v) then friends[v:SteamID()] = true end
		end
	end
	net.Start("nadmod_ppfriends")
		net.WriteTable(friends)
	net.Send(ply)
end)
net.Receive("nadmod_ppfriends",function(len,ply)
	if not ply:IsValid() then return end
	if !NADMOD.Users[ply:SteamID()] then NADMOD.Users[ply:SteamID()] = {Rank = 1} end
	NADMOD.Users[ply:SteamID()].Friends = NADMOD.Users[ply:SteamID()].Friends or {}
	local outtab = NADMOD.Users[ply:SteamID()].Friends
	
	local players = {}
	for _,v in pairs(player.GetAll()) do players[v:SteamID()] = v end
	
	for steamid,bool in pairs(net.ReadTable()) do
		if players[steamid] and (not bool or not (NADMOD.IsPPAdmin(players[steamid]) and NADMOD.PPConfig["adminall"])) then -- Users may not add admins to their friends list
			if bool then outtab[steamid] = true else outtab[steamid] = nil end -- Don't bother storing falses
		end
	end
	NADMOD.Save()
	NADMOD.Notify(ply, "Friends received!")
end)

function CPPI:GetName() return "Nadmod Prop Protection" end
function CPPI:GetVersion() return NADMOD.PPVersion end
function metaply:CPPIGetFriends()
	if not self:IsValid() then return {} end
	local ret = {}
	local friends = (NADMOD.Users[self:SteamID()] or {Friends={}}).Friends or {}
	for _,v in pairs(player.GetAll()) do
		if NADMOD.IsPPAdmin(v) or friends[v:SteamID()] then table.insert(ret,v) end
	end
	return ret
end
function metaply:NADMODISFRIEND(PLY)
	local friends = (NADMOD.Users[self:SteamID()] or {Friends={}}).Friends
	return friends[PLY:SteamID()]
end
function metaent:CPPIGetOwner() return self.Owner end
function metaent:CPPISetOwner(ply) return NADMOD.PlayerMakePropOwner(ply, self) end
function metaent:CPPICanTool(ply,mode) return NADMOD.CanTool(ply,{Entity=self},mode) != false end
function metaent:CPPICanPhysgun(ply) return NADMOD.PlayerCanTouchSafe(ply,self) != false end
function metaent:CPPICanPickup(ply) return NADMOD.GravGunPickup(ply, self) != false end
function metaent:CPPICanPunt(ply) return NADMOD.GravGunPickup(ply, self) != false end

print("[NADMOD PP - NADMOD Prop Protection Module v"..NADMOD.PPVersion.." Loaded]")
