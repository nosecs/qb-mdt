local QBCore = exports['qb-core']:GetCoreObject()

function GetPlayerData(source)
	print(source)
	local Player = QBCore.Functions.GetPlayer(source)
	return Player.PlayerData
end

function UnpackJob(data)
	local job = {
		name = data.name,
		label =data.label
	}
	local grade = {
		name = data.job.grade.name,
	}

	return job, grade
end

-- Do Perm Check
function PermCheck(src)
	local PlayerData = GetPlayerData(src)
	local result = true

	-- if job is not in config
	if not Config.AllowedJobs[PlayerData.job.name] then
		-- idk if you have better log system or a notify system
		print(("UserId: %s(%d) tried to access the mdt even though they are not authorised (server direct)"):format(GetPlayerName(src), src))
		result = false
	end

	return result
end

-- Get Profile Pic for Gender?
function ProfPic(gender, profilepic)
	if profilepic then return profilepic end;
	if gender == "f" then return "img/female.png" end;
	return "img/male.png"
end

-- There is probably a better way but mehhhhhhh
function GetJobType(PlayerData)
	local JobTypes = {}
	for key, value in pairs(Config.PoliceJobs) do
		if value then
			JobTypes[key] = 'police'
		end
	end

	for key, value in pairs(Config.AmbulanceJobs) do
		if value then
			JobTypes[key] = 'ambulance'
		end
	end

	for key, value in pairs(Config.DojJobs) do
		if value then
			JobTypes[key] = 'doj'
		end
	end

	return JobTypes[PlayerData.job.name]
end

function GetNameFromPlayerData(PlayerData)
	return ('%s %s'):format(PlayerData.charinfo.firstname, PlayerData.charinfo.lastname)
end

