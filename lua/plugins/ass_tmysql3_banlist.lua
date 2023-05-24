local PLUGIN = {}

PLUGIN.Name = "TMySQL3 Banlist"
PLUGIN.Author = "Slayer3032"
PLUGIN.Date = "21st June 2016"
PLUGIN.Filename = PLUGIN_FILENAME
PLUGIN.ClientSide = false
PLUGIN.ServerSide = true
PLUGIN.APIVersion = 2.3
PLUGIN.Gamemodes = {}

local d,e

local function CreateTable()
	tmysql.query("CREATE TABLE ass_bans (id BIGINT UNSIGNED NOT NULL,name TEXT NOT NULL,unbantime INT NOT NULL DEFAULT 0,reason TEXT NOT NULL,adminname TEXT NOT NULL,adminid BIGINT UNSIGNED NOT NULL,PRIMARY KEY (id))",function(res,status,err)
		if status == QUERY_FAIL then
			ErrorNoHalt("ASS Banlist -> Cannot create ass_bans table! "..err)
			chat.AddText(Color(0, 229, 238), "ASS Banlist -> Cannot create ass_bans table!")
		end
	end)
end

local function dropreason(name, time, reason)
	if time == 0 then
		return name .. " is permanently banned. \nReason: \"" .. reason .. "\""
	elseif time > os.time() then
		return name .. " is banned. Time left: " .. string.NiceTime(time-os.time()) .. "\nReason: \"" .. reason .. "\""
	end
end

function PLUGIN.Registered()
	if (ASS_Config["banlist"] != PLUGIN.Name) then return end
	if ASS_Config["banlist_caching"] == nil then
		ASS_Config["banlist_caching"] = true
		ASS_WriteConfig()
	end

	require("tmysql")
	hook.Add("CheckPassword", "ASS_CheckPassword", PLUGIN.CheckPassword)
	hook.Add("PlayerInitialSpawn", "ASS_SpawnBanCheck", function(pl) PLUGIN.CheckPlayer(pl:AssID()) end)

	if !ASS_TMySQL3_DB then 
		d,e = tmysql.initialize(ASS_MySQLInfo.IP, ASS_MySQLInfo.User, ASS_MySQLInfo.Pass, ASS_MySQLInfo.DB, ASS_MySQLInfo.Port)
		if d == nil and e == nil then
			d = "D is for Database!"
			ASS_TMySQL3_DB = d
		end
		print("ASS Writer -> TMySQL3 connection initalized!")
	else
		d = ASS_TMySQL3_DB
	end
	if d then
		tmysql.query("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='"..ASS_MySQLInfo.DB.."' AND TABLE_NAME='ass_bans'",function(res,status,err)
			if !res then ErrorNoHalt("ASS Banlist -> Unable to retrieve query results!"..err) end
			if status == QUERY_FAIL then ErrorNoHalt("ASS Banlist -> Error checking for ban table: "..err) end
			if !res[1] or !res[1]["TABLE_NAME"] then
				print("ASS Banlist -> Could not find ass_bans table in "..ASS_MySQLInfo.DB.."! Creating...")
				CreateTable()
			end
			
			if res[1] then
				if res[1]["TABLE_NAME"] then
					print("ASS Banlist -> TMySQL3 Banlist initalized!")
					if ASS_Config["banlist_caching"] then
						PLUGIN.LoadBanlist()
						timer.Create("ASS_MySQL_BanRefresh", 90, 0, PLUGIN.LoadBanlist)
					end
				else
					ErrorNoHalt("ASS Banlist -> Error checking for ban table: "..err)
				end
			end
		end,QUERY_FLAG_ASSOC)
	else
		ErrorNoHalt("ASS Banlist -> Error connecting to database: "..e or "error")
		chat.AddText(Color(0, 229, 238), "ASS Banlist -> Error connecting to database!")
	end
end

function PLUGIN.LoadBanlist()
	if (ASS_Config["banlist"] != PLUGIN.Name) then return end

	if d then
		tmysql.query("SELECT id,name,unbantime,reason,adminname,adminid FROM ass_bans",function(res,status,err)
			if !res then error("ASS Banlist -> Unable to retrieve query results!") end
			if status == QUERY_FAIL then error("ASS Banlist -> Unable to load banlist: "..err) chat.AddText(Color(0, 229, 238), "ASS Banlist -> Cannot load banlist! MySQL Error!") end

			if res then
				local x = res
				local bt = ASS_GetBanTable()
				for k,v in pairs(x) do
					bt[tostring(v["id"])] = {}
					bt[tostring(v["id"])].Name = tostring(v["name"])
					bt[tostring(v["id"])].UnbanTime = tonumber(v["unbantime"])
					bt[tostring(v["id"])].Reason	= tostring(v["reason"])
					bt[tostring(v["id"])].AdminName = tostring(v["adminname"])
					bt[tostring(v["id"])].AdminID = tostring(v["adminid"])
					if IsValid(player.GetBySteamID64(tostring(v["id"]))) then
						PLUGIN.CheckPlayer(tostring(v["id"]))
					end
				end
			end
		end,QUERY_FLAG_ASSOC)
	else
		ErrorNoHalt("ASS Banlist -> Cannot load banlist! MySQL could not connect to database!")
		chat.AddText(Color(0, 229, 238), "ASS Banlist -> Cannot load banlist! MySQL could not connect to database!")
	end
end

function PLUGIN.PlayerBan(admin, pl, time, reason)
	if (ASS_Config["banlist"] != PLUGIN.Name) then return end

	local bt = ASS_GetBanTable()
	bt[pl:SteamID64()] = {}
	bt[pl:SteamID64()].Name = pl:Nick()
	bt[pl:SteamID64()].AdminName = admin:Nick()
	bt[pl:SteamID64()].AdminID = admin:SteamID64()
	bt[pl:SteamID64()].UnbanTime = os.time()+(tonumber(time)*60)
	bt[pl:SteamID64()].Reason = reason or "no reason"

	if d then
		tmysql.query("INSERT INTO ass_bans (id,name,unbantime,reason,adminname,adminid) VALUES("..pl:SteamID64()..",'"..tmysql.escape(pl:Nick()).."',"..os.time()+(tonumber(time)*60)..",'"..tmysql.escape(reason).."','"..tmysql.escape(admin:Nick()).."',"..admin:SteamID64()..") ON DUPLICATE KEY UPDATE name='"..tmysql.escape(pl:Nick()).."',unbantime="..os.time()+(tonumber(time)*60)..",reason='"..tmysql.escape(reason).."',adminname='"..tmysql.escape(admin:Nick()).."',adminid="..admin:SteamID64())
	else
		ErrorNoHalt("ASS Banlist -> Cannot ban player! MySQL could not connect to database!")
		chat.AddText(Color(0, 229, 238), "ASS Banlist -> Cannot ban player! MySQL could not connect to database!")
	end
end

function PLUGIN.PlayerUnban(id, admin)
	if (ASS_Config["banlist"] != PLUGIN.Name) then return end

	local bt = ASS_GetBanTable()
	if bt[id] then
		bt[id] = nil
	end

	if d then
		tmysql.query("DELETE FROM ass_bans WHERE id="..tmysql.escape(id), function(res,status,err) 
			if !err then
				if IsValid(admin) then ASS_MessagePlayer(admin, "ASS Banlist -> Unable to remove ban. MySQL Error!") end
				error("ASS Banlist -> Unable to remove ban: "..err)
			end
		end)
	else
		ErrorNoHalt("ASS Banlist -> Cannot unban player! MySQL could not connect to database!")
		chat.AddText(Color(0, 229, 238), "ASS Banlist -> Cannot unban player! MySQL could not connect to database!")
	end
end

function PLUGIN.QueryBanlist(id)
	if (ASS_Config["banlist"] != PLUGIN.Name) then return end

	if d then
		tmysql.query("SELECT id,name,unbantime,reason,adminname,adminid FROM ass_bans WHERE id='"..tmysql.escape(id).."'",function(res,status,err)
			if !res then ErrorNoHalt("ASS Banlist -> Unable to retrieve query results!") end
			if status == QUERY_FAIL then ErrorNoHalt("ASS Banlist -> Error checking for ban table: "..err) end

			local bt = ASS_GetBanTable()
			if !res[1] then
				if bt[id] then
					bt[id] = nil
				end
			end
			if res[1] then
				if !bt[id] then
					local x = res[1]
					bt[id] = {}
					bt[id].Name = tostring(x["name"])
					bt[id].UnbanTime = tonumber(x["unbantime"])
					bt[id].Reason	= tostring(x["reason"])
					bt[id].AdminName = tostring(x["adminname"])
					bt[id].AdminID = tostring(x["adminid"])
					PLUGIN.CheckPlayer(id)
				end
			end
		end,QUERY_FLAG_ASSOC)
	else
		ErrorNoHalt("ASS Banlist -> QueryBanlist failed! MySQL could not connect to database!")
		chat.AddText(Color(0, 229, 238), "ASS Banlist -> QueryBanlist failed! MySQL could not connect to database!")
	end
end

function PLUGIN.CheckBanlist(id)
	if (ASS_Config["banlist"] != PLUGIN.Name) then return end
	
	PLUGIN.QueryBanlist(id)
	
	local bt = ASS_GetBanTable()
	
	if (bt[id]) then
		return bt[id]
	else
		return false
	end
end

function PLUGIN.CheckPlayer(id)
	if (ASS_Config["banlist"] != PLUGIN.Name) then return end
	if ASS_GetBanTable()[id] then
		local btbl = ASS_GetBanTable()[id]
		if btbl.UnbanTime > os.time() or btbl.UnbanTime == 0 then
			print("ASS Banlist -> Player ban loaded for "..btbl.Name.."("..id.."), dropping client...")
			ASS_DropClient(util.SteamIDFrom64(id), dropreason(btbl.Name, btbl.UnbanTime, btbl.Reason))
		else
			PLUGIN.PlayerUnban(id)
		end
	end
end

function PLUGIN.CheckPassword(id, ip, svpass, clpass, name)
	if (ASS_Config["banlist"] != PLUGIN.Name) then return end
	if svpass != "" and svpass != clpass then return false, "Incorrect password." end
	
	local btbl = PLUGIN.CheckBanlist(id)
	
	if btbl then
		if btbl.UnbanTime > os.time() or btbl.UnbanTime == 0 then
			return false, dropreason(name, btbl.UnbanTime, btbl.Reason)
		end
	end
end

ASS_RegisterPlugin(PLUGIN)
