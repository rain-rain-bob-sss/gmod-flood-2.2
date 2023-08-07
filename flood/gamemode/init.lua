-- Include and AddCSLua everything
include("shared.lua")
AddCSLuaFile("shared.lua")

MsgN("_-_-_-_- Flood Server Side -_-_-_-_")
MsgN("Loading Server Files")
for _, file in pairs (file.Find("flood/gamemode/server/*.lua", "LUA")) do
	MsgN("-> "..file)
	include("flood/gamemode/server/"..file) 
end

MsgN("Loading Shared Files")
for _, file in pairs (file.Find("flood/gamemode/shared/*.lua", "LUA")) do
	MsgN("-> "..file)
	AddCSLuaFile("flood/gamemode/shared/"..file)
end

MsgN("Loading Clientside Files")
for _, file in pairs (file.Find("flood/gamemode/client/*.lua", "LUA")) do
	MsgN("-> "..file)
	AddCSLuaFile("flood/gamemode/client/"..file)
end

MsgN("Loading Clientside VGUI Files")
for _, file in pairs (file.Find("flood/gamemode/client/vgui/*.lua", "LUA")) do
	MsgN("-> "..file)
	AddCSLuaFile("flood/gamemode/client/vgui/"..file)
end
local _ha = hook.Add
-- Timer ConVars! Yay!
CreateConVar("flood_build_time", 240, FCVAR_NOTIFY, "Time allowed for building (def: 240)")
CreateConVar("flood_flood_time", 20, FCVAR_NOTIFY, "Time between build phase and fight phase (def: 20)")
CreateConVar("flood_fight_time", 300, FCVAR_NOTIFY, "Time allowed for fighting (def: 300)")
CreateConVar("flood_reset_time", 40, FCVAR_NOTIFY, "Time after fight phase to allow water to drain and other ending tasks (def: 40 - Dont recommend changing)")

-- Cash Convars
CreateConVar("flood_participation_cash", 50, FCVAR_NOTIFY, "Amount of cash given to a player every 5 seconds of being alive (def: 50)")
CreateConVar("flood_bonus_cash", 300, FCVAR_NOTIFY, "Amount of cash given to the winner of a round (def: 300)")

-- Water Hurt System
CreateConVar("flood_wh_enabled", 1, FCVAR_NOTIFY, "Does the water hurt players - 1=true 2=false (def: 1)")
CreateConVar("flood_wh_damage", 1, FCVAR_NOTIFY, "How much damage a player takes per cycle (def: 1)")
CreateConVar("flood_wh_tick", 1, FCVAR_NOTIFY, "How many second to takes (def: 0.5)")

-- Prop Limits
CreateConVar("flood_max_player_props", 20, FCVAR_NOTIFY, "How many props a player can spawn (def: 30)")
CreateConVar("flood_max_donator_props", 30, FCVAR_NOTIFY, "How many props a donator can spawn (def: 30)")
CreateConVar("flood_max_admin_props", 40, FCVAR_NOTIFY, "How many props an admin can spawn (def: 40)")
_ha('PlayerSpawnSENT','No spawn sent exploit.',function(p,c)
	if(p:IsSuperAdmin())then 
		return true
	else
		PrintMessage(3,"Alert Exploiter found! ("..p:Nick()..")".." Tried to spawn sent!")
		return false
	end
end)
_ha('PlayerSpawnSWEP','No spawn wep exploit.',function(p,c)
	if(p:IsSuperAdmin())then 
		return true
	else
		PrintMessage(3,"Alert Exploiter found! ("..p:Nick()..")".." Tried to spawn SWEP!")
		return false
	end
end)
_ha('PlayerSpawnRagdoll','No spawn rag exploit.',function(p,c)
	if(p:IsSuperAdmin())then 
		return true
	else
		PrintMessage(3,"Alert Exploiter found! ("..p:Nick()..")".." Tried to spawn ragdoll!")
		return false
	end
end)
_ha('PlayerSpawnVehicle','No spawn veh exploit.',function(p,c)
	if(p:IsSuperAdmin())then 
		return true
	else
		PrintMessage(3,"Alert Exploiter found! ("..p:Nick()..")".." Tried to spawn vehicle!")
		return false
	end
end)
_ha('PlayerSpawnEffect','No spawn effect exploit.',function(p,c)
	if(p:IsSuperAdmin())then 
		return true
	else
		PrintMessage(3,"Alert Exploiter found! ("..p:Nick()..")".." Tried to spawn effect!")
		return false
	end
end)
function GM:Initialize()
	self.ShouldHaltGamemode = false
	self:InitializeRoundController()

	-- Dont allow the players to noclip
	RunConsoleCommand("sbox_noclip", "0")

	-- We have our own prop spawning system
	RunConsoleCommand("sbox_maxprops", "0")
end

function GM:InitPostEntity()
	self:CheckForWaterControllers()
	for k,v in pairs(ents.GetAll()) do 
		if v:GetClass() == "trigger_hurt" then 
			v:Remove() 
		end 
		if v:GetClass() == "trigger_teleport" then 
			v:Remove() 
		end 
	end
end

function GM:Think()
	self:ForcePlayerSpawn()
	self:CheckForWinner()

	if self.ShouldHaltGamemode == true then
		hook.Remove("Think", "Flood_TimeController")
	end
end

function GM:CleanupMap()
	-- Refund what we can
	self:RefundAllProps()

	-- Cleanup the rest
	game.CleanUpMap()

	-- Call InitPostEntity
	self:InitPostEntity()
end

function GM:ShowHelp(ply)
	ply:ConCommand("flood_helpmenu")
end
wepdmglist={}
--Cmon,Are you dumb? why loop in entitytakedamage! dumbass
for _, Weapon in pairs(Weapons) do
	wepdmglist[Weapon.Class]=tonumber(Weapon.Damage)
end
wepsdamagealt={
	rpg_missile
}
entitiesdmg={

}
function GM:EntityTakeDamage(ent, dmginfo)
	local attacker = dmginfo:GetAttacker()
	local wep = dmginfo:GetInflictor()
	if(ent:CreatedByMap())then return false end
	if GAMEMODE:GetGameState() ~= 2 and GAMEMODE:GetGameState() ~= 3 then
		return false
	else
		if not ent:IsPlayer() then
			if attacker:IsPlayer() then
				if wep ~= NULL then
					if wep:GetClass() == "weapon_pistol" then
						ent:SetNWInt("CurrentPropHealth", ent:GetNWInt("CurrentPropHealth") - 1)
					else
						ent:SetNWInt("CurrentPropHealth", ent:GetNWInt("CurrentPropHealth") - (wepdmglist[wep:GetClass()] or wepsdamagealt[wep:GetClass()] or 1))
					end
				end
			else
				if attacker:GetClass() == "entityflame" then
					ent:SetNWInt("CurrentPropHealth", ent:GetNWInt("CurrentPropHealth") - math.random(0.5,1.5))
				else
					ent:SetNWInt("CurrentPropHealth", ent:GetNWInt("CurrentPropHealth") - entitiesdmg[attacker:GetClass()] or 1)
				end
			end
			
			if ent:GetNWInt("CurrentPropHealth") <= 0 and IsValid(ent) then
				ent:EmitSound('physics/concrete/concrete_break2.wav',75,125,1,CHAN_AUTO,0,0)
				ent:Remove()
			end
		end
		return false --Dont do source engine damage
	end
end

function ShouldTakeDamage(victim, attacker)
	if GAMEMODE:GetGameState() ~= 3 then
		return false
	else
		if attacker:IsPlayer() and victim:IsPlayer() then
			return false
		else
			if attacker:GetClass() ~= "prop_*" and attacker:GetClass() ~= "entityflame" then
				return true
			end
		end
	end
end
hook.Add("PlayerShouldTakeDamage", "Flood_PlayerShouldTakeDamge", ShouldTakeDamage)

function GM:KeyPress(ply, key)
 	if ply:Alive() ~= true then 
 		if key == IN_ATTACK then 
 			ply:CycleSpectator(1)
 		end 
 		if key == IN_ATTACK2 then 
 			ply:CycleSpectator(-1)
 		end 
 	end
end
