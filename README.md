# Flood-2.2

Flood 2.0 Credits:  
1) [MS] Mythic (Mythikos) - for development of serverside and clientside code.  
2) Freezebug - for development of serverside code.   
3) Nebual - for the development of NADMOD and permission to use it in our gamemode.

Flood 2.2 Credits:  
1)  [TW]Rain_bob Fix bugs and add new things

Installation:  
1) Drop the flood folder into your gamemode folder. Simple as that.

CHAT COMMAND
SEE FLOOD 2.0 WORKSHOP
(NEW:!pay <playername> <Cash>)

Convars:  
flood_build_time - Time allowed for building (def: 240)  
flood_flood_time - Time between build phase and fight phase (def: 20)  
flood_fight_time - Time allowed for fighting (def: 300)  
flood_reset_time - Time after fight phase to allow water to drain and other ending tasks (def: 40 - Dont recommend changing)  

flood_participation_cash - Amount of cash given to a player every 5 seconds of being alive (def: 50)  
flood_damage_cashmul - Higher means more cash on hit props 0 to disable (def: 1)  
flood_bonus_cash - Amount of cash given to the winner of a round (def: 300)  

flood_wh_enabled - Does the water hurt players - 1=true 2=false (def: 1)  
flood_wh_damage - How much damage a player takes per cycle (def: 1)  
flood_wh_tick - Water Hurt delay


Flood 2.0 Workshop: http://steamcommunity.com/sharedfiles/filedetails/?id=474900236  
Flood 2.2 Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3016332015    

READ ME FFS:  
EDIT server/sv_entitieshealth.lua if you want  
EDIT init.lua if you want (line 142:wepsdamagealt is weapon damage alt table,entitesdmg.. yeah you know what does this does,line 235 is can damage player table,edit this to make some weapon able to damage player!)  

Projects to use flood 2.0:
  https://github.com/WTC-GhostCommunity/The-Purge-Gamemode
