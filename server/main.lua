local QBCore = exports['qb-core']:GetCoreObject()
-- Maybe cache?
local incidents = {}
local convictions = {}
local bolos = {}

-- TODO make it departments compatible
local activeUnits = {}

local impound = {}
local dispatchMessages = {}

function IsPolice(job)
	for k, v in pairs(Config.PoliceJobs) do
        if job == k then
            return true
        end
    end
    return false
end

AddEventHandler("onResourceStart", function(resourceName)
	if (resourceName == 'qb-mdt') then
        activeUnits = {}
    end
end)

local function openMDT(src)
	local PlayerData = GetPlayerData(src)
	if not PermCheck(src, PlayerData) then return end
	local Radio = Player(src).state.radioChannel or 0
	--[[ if Radio > 100 then
		Radio = 0
	end ]]

	activeUnits[PlayerData.citizenid] = {
		cid = PlayerData.citizenid,
		callSign = PlayerData.metadata['callsign'],
		firstName = PlayerData.charinfo.firstname,
		lastName = PlayerData.charinfo.lastname,
		radio = Radio,
		unitType = PlayerData.job.name,
		duty = PlayerData.job.onduty
	}

	local JobType = GetJobType(PlayerData.job.name)
	local bulletin = GetBulletins(JobType)

	--TriggerClientEvent('mdt:client:dashboardbulletin', src, bulletin)
	TriggerClientEvent('mdt:client:open', src, bulletin)
	TriggerClientEvent('mdt:client:GetActiveUnits', src, activeUnits)
end

QBCore.Commands.Add("mdt", "Opens the mdt", {}, false, function(source)
    local src = source
	openMDT(src)
end)

QBCore.Functions.CreateCallback('mdt:server:SearchProfile', function(source, cb, sentData)
	if not sentData then  return cb({}) end
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		local JobType = GetJobType(Player.PlayerData.job.name)
		if JobType == 'police' then
			local people = MySQL.query.await("SELECT p.citizenid, p.charinfo, md.pfp FROM players p LEFT JOIN mdt_data md on p.citizenid = md.cid WHERE LOWER(`charinfo`) LIKE :query OR LOWER(`citizenid`) LIKE :query OR LOWER(`fingerprint`) LIKE :query AND jobtype = :jobtype LIMIT 20", { query = string.lower('%'..sentData..'%'), jobtype = JobType })
			local citizenIds = {}
			local citizenIdIndexMap = {}
			if not next(people) then cb({}) return end

			for index, data in pairs(people) do
				people[index]['warrant'] = false
				people[index]['convictions'] = 0
				people[index]['licences'] = GetPlayerLicenses(data.citizenid)
				people[index]['pp'] = ProfPic(data.gender, data.pfp)
				citizenIds[#citizenIds+1] = data.citizenid
				citizenIdIndexMap[data.citizenid] = index
			end

			local convictions = GetConvictions(citizenIds)
			
			if next(convictions) then
				for _, conv in pairs(convictions) do
					if conv.warrant then people[citizenIdIndexMap[conv.cid]].warrant = true end

					local charges = json.decode(conv.charges)
					people[citizenIdIndexMap[conv.cid]].convictions = people[citizenIdIndexMap[conv.cid]].convictions + #charges
				end
			end
			

			return cb(people)
		end
	end

	return cb({})
end)

QBCore.Functions.CreateCallback("mdt:server:getWarrants", function(source, cb)
    local WarrantData = {}
    local data = MySQL.query.await("SELECT * FROM mdt_convictions", {})
    for _, value in pairs(data) do
        if value.warrant == "1" then
            table.insert(WarrantData, {
                cid = value.cid,
                linkedincident = value.linkedincident,
                name = GetNameFromId(value.cid),
                time = value.time
            })
        end
    end
    cb(WarrantData)
end)

QBCore.Functions.CreateCallback('mdt:server:OpenDashboard', function(source, cb)
	local PlayerData = GetPlayerData(source)
	if not PermCheck(source, PlayerData) then return end
	local JobType = GetJobType(PlayerData.job.name)
	local bulletin = GetBulletins(JobType)
	cb(bulletin)
end)

RegisterNetEvent('mdt:server:NewBulletin', function(title, info, time)
	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(src, PlayerData) then return end
	local JobType = GetJobType(PlayerData.job.name)
	local playerName = GetNameFromPlayerData(PlayerData)
	local newBulletin = MySQL.insert.await('INSERT INTO `mdt_bulletin` (`title`, `desc`, `author`, `time`, `jobtype`) VALUES (:title, :desc, :author, :time, :jt)', {
		title = title,
		desc = info,
		author = playerName,
		time = tostring(time),
		jt = JobType
	})

	AddLog(("A new bulletin was added by %s with the title: %s!"):format(playerName, title))
	TriggerClientEvent('mdt:client:newBulletin', -1, src, {id = newBulletin, title = title, info = info, time = time, author = PlayerData.CitizenId}, JobType)
end)

RegisterNetEvent('mdt:server:deleteBulletin', function(id, title)
	if not id then return false end
	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(src, PlayerData) then return end
	local JobType = GetJobType(PlayerData.job.name)

	local deletion = MySQL.query.await('DELETE FROM `mdt_bulletin` where title = ?', {title})
	AddLog("Bulletin with Title: "..title.." was deleted by " .. GetNameFromPlayerData(PlayerData) .. ".")
end)

QBCore.Functions.CreateCallback('mdt:server:GetProfileData', function(source, cb, sentId)
	if not sentId then return cb({}) end

	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(src, PlayerData) then return cb({}) end
	local JobType = GetJobType(PlayerData.job.name)
	local target = GetPlayerDataById(sentId)
	local JobName = PlayerData.job.name

	if not target or not next(target) then return cb({}) end

	-- Convert to string because bad code, yes?
	if type(target.job) == 'string' then target.job = json.decode(target.job) end
	if type(target.charinfo) == 'string' then target.charinfo = json.decode(target.charinfo) end
	if type(target.metadata) == 'string' then target.metadata = json.decode(target.metadata) end

	local job, grade = UnpackJob(target.job)

	local person = {
		cid = target.citizenid,
		firstname = target.charinfo.firstname,
		lastname = target.charinfo.lastname,
		job = job.label,
		grade = grade.name,
		pp = ProfPic(target.charinfo.gender, null),
		licences = target.metadata['licences'],
		dob = target.charinfo.birthdate,
		mdtinfo = '',
		fingerprint = '',
		tags = {},
		vehicles = {},
		properties = {},
		gallery = {},
		isLimited = false
	}

	if Config.PoliceJobs[JobName] then
		local convictions = GetConvictions({person.cid})
		person.convictions = {}
		if next(convictions) then
			for _, conv in pairs(convictions) do
				if conv.warrant then person.warrant = true end
				local charges = json.decode(conv.charges)
				for _, charge in pairs(charges) do
					person.convictions[_] = charge
				end
			end
		end
		local vehicles = GetPlayerVehicles(person.cid)
		
		
		if vehicles then
			person.vehicles = vehicles
		end
		local Coords = {}
		local Houses = {}
		local properties= GetPlayerProperties(person.cid)
		for k, v in pairs(properties) do
			table.insert(Coords, {
                coords = json.decode(v["coords"]),
            })
		end
		for index = 1, #Coords, 1 do
            table.insert(Houses, {
                label = properties[index]["label"],
                coords = tostring(Coords[index]["coords"]["enter"]["x"]..",".. Coords[index]["coords"]["enter"]["y"].. ",".. Coords[index]["coords"]["enter"]["z"]),
            })
        end
		-- if properties then
			person.properties = Houses
		-- end
	end 

	local mdtData = GetPersonInformation(sentId, JobType)
	if mdtData then
		person.mdtinfo = mdtData.information
		person.fingerprint = mdtData.fingerprint
		person.profilepic = mdtData.pfp
		person.tags = json.decode(mdtData.tags)
		person.gallery = json.decode(mdtData.gallery)
	end

	return cb(person)
end)

--[[ RegisterNetEvent('mdt:server:SaveProfile', function(pfp, information, cid, fName, sName)
	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(src) then return cb({}) end
	local JobType = GetJobType(PlayerData.job.name)
	local target = GetPlayerDataById(sendId)
	local JobName = PlayerData.job.name

	local UglyFunc = function (id, pfp, desc, job)
		-- exports.oxmysql:executeSync("UPDATE policemdtdata SET `information`=:information WHERE `id`=:id LIMIT 1", { id = id, information = information })
		-- exports.oxmysql:executeSync("UPDATE users SET `profilepic`=:profilepic WHERE `id`=:id LIMIT 1", { id = cid, profilepic = pfp })
		MySQL.update.await('UPDATE `mdt_data` SET information = ? where cid = ? LIMIT 1', {id, desc})
		AddLog(("A user with the Citizen ID "..cid.." was updated by %s %s"):format(PlayerData.charinfo.firstname, PlayerData.charinfo.lastname))
	end

	local person = MySQL.single.await('SELECT id from mdtdata WHERE cid = ? AND type = ?', {cid, JobType})
	if not person then
		return cb({})
	end
end) ]]

RegisterNetEvent("mdt:server:saveProfile", function(pfp, information, cid, fName, sName, tags, gallery, fingerprint, licenses)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	ManageLicenses(cid, licenses)
	if Player then
		local incJobType = GetJobType(Player.PlayerData.job.name)
		MySQL.Async.insert('INSERT INTO mdt_data (cid, information, pfp, jobtype, tags, gallery, fingerprint) VALUES (:cid, :information, :pfp, :jobtype, :tags, :gallery, :fingerprint) ON DUPLICATE KEY UPDATE cid = :cid, information = :information, pfp = :pfp, tags = :tags, gallery = :gallery, fingerprint = :fingerprint', {
			cid = cid,
			information = information,
			pfp = pfp,
			jobtype = incJobType,
			tags = json.encode(tags),
			gallery = json.encode(gallery),
			fingerprint = fingerprint,
		})
	end
end)

--[[ RegisterNetEvent("mdt:server:saveProfile", function(pfp, information, cid, fName, sName)
	TriggerEvent('echorp:getplayerfromid', source, function(player)
		if player then
			if player.job and (player.job.isPolice or player.job.name == 'doj') then
				local function UpdateInfo(id, pfp, desc)
					exports.oxmysql:executeSync("UPDATE policemdtdata SET `information`=:information WHERE `id`=:id LIMIT 1", { id = id, information = information })
					exports.oxmysql:executeSync("UPDATE users SET `profilepic`=:profilepic WHERE `id`=:id LIMIT 1", { id = cid, profilepic = pfp })
					TriggerEvent('mdt:server:AddLog', "A user with the Citizen ID "..cid.." was updated by "..player.fullname)

					if player.job.name == 'doj' then
						exports.oxmysql:executeSync("UPDATE users SET `firstname`=:firstname, `lastname`=:lastname WHERE `id`=:id LIMIT 1", { firstname = fName, lastname = sName, id = cid })
					end
				end

				exports.oxmysql:execute('SELECT id FROM policemdtdata WHERE cid=:cid LIMIT 1', { cid = cid }, function(user)
					if user and user[1] then
						UpdateInfo(user[1]['id'], pfp, information)
					else
						CreateUser(cid, 'policemdtdata', function(result)
							UpdateInfo(result, pfp, information)
						end)
					end
				end)
			elseif player.job and (player.job.name == 'ambulance') then
				local function UpdateInfo(id, pfp, desc)
					exports.oxmysql:executeSync("UPDATE emsmdtdata SET `information`=:information WHERE `id`=:id LIMIT 1", { id = id, information = information })
					exports.oxmysql:executeSync("UPDATE users SET `profilepic`=:profilepic WHERE `id`=:id LIMIT 1", { id = cid, profilepic = pfp })
					TriggerEvent('mdt:server:AddLog', "A user with the Citizen ID "..cid.." was updated by "..player.fullname)
				end

				exports.oxmysql:execute('SELECT id FROM emsmdtdata WHERE cid=:cid LIMIT 1', { cid = cid }, function(user)
					if user and user[1] then
						UpdateInfo(user[1]['id'], pfp, information)
					else
						CreateUser(cid, 'emsmdtdata', function(result)
							UpdateInfo(result, pfp, information)
						end)
					end
				end)
			end
		end
	end)
end) ]]

RegisterNetEvent("mdt:server:newTag", function(cid, tag)
	TriggerEvent('echorp:getplayerfromid', source, function(result)
		if result then
			if result.job and (result.job.isPolice or result.job.name == 'doj') then
				local function UpdateTags(id, tags)
					exports.oxmysql:executeSync("UPDATE policemdtdata SET `tags`=:tags WHERE `id`=:id LIMIT 1", { id = id, tags = json.encode(tags) })
					TriggerEvent('mdt:server:AddLog', "A user with the Citizen ID "..id.." was added a new tag with the text ("..tag..") by "..result.fullname)
				end

				exports.oxmysql:execute('SELECT id, tags FROM policemdtdata WHERE cid=:cid LIMIT 1', { cid = cid }, function(user)
					if user and user[1] then
						local tags = json.decode(user[1]['tags'])
						table.insert(tags, tag)
						UpdateTags(user[1]['id'], tags)
					else
						CreateUser(cid, 'policemdtdata', function(result)
							local tags = {}
							table.insert(tags, tag)
							UpdateTags(result, tags)
						end)
					end
				end)
			elseif result.job and (result.job.name == 'ambulance') then
				local function UpdateTags(id, tags)
					exports.oxmysql:executeSync("UPDATE emsmdtdata SET `tags`=:tags WHERE `id`=:id LIMIT 1", { id = id, tags = json.encode(tags) })
					TriggerEvent('mdt:server:AddLog', "A user with the Citizen ID "..id.." was added a new tag with the text ("..tag..") by "..result.fullname)
				end

				exports.oxmysql:execute('SELECT id, tags FROM emsmdtdata WHERE cid=:cid LIMIT 1', { cid = cid }, function(user)
					if user and user[1] then
						local tags = json.decode(user[1]['tags'])
						table.insert(tags, tag)
						UpdateTags(user[1]['id'], tags)
					else
						CreateUser(cid, 'emsmdtdata', function(result)
							local tags = {}
							table.insert(tags, tag)
							UpdateTags(result, tags)
						end)
					end
				end)
			end
		end
	end)
end)

RegisterNetEvent("mdt:server:removeProfileTag", function(cid, tagtext)
	TriggerEvent('echorp:getplayerfromid', source, function(result)
		if result then
			if result.job and (result.job.isPolice or result.job.name == 'doj') then

				local function UpdateTags(id, tag)
					exports.oxmysql:executeSync("UPDATE policemdtdata SET `tags`=:tags WHERE `id`=:id LIMIT 1", { id = id, tags = json.encode(tag) })
					TriggerEvent('mdt:server:AddLog', "A user with the Citizen ID "..id.." was removed of a tag with the text ("..tagtext..") by "..result.fullname)
				end

				exports.oxmysql:execute('SELECT id, tags FROM policemdtdata WHERE cid=:cid LIMIT 1', { cid = cid }, function(user)
					if user and user[1] then
						local tags = json.decode(user[1]['tags'])
						for i=1, #tags do
							if tags[i] == tagtext then
								table.remove(tags, i)
							end
						end
						UpdateTags(user[1]['id'], tags)
					else
						CreateUser(cid, 'policemdtdata', function(result)
							UpdateTags(result, {})
						end)
					end
				end)
			elseif result.job and (result.job.name == 'ambulance') then

				local function UpdateTags(id, tag)
					exports.oxmysql:executeSync("UPDATE emsmdtdata SET `tags`=:tags WHERE `id`=:id LIMIT 1", { id = id, tags = json.encode(tag) })
					TriggerEvent('mdt:server:AddLog', "A user with the Citizen ID "..id.." was removed of a tag with the text ("..tagtext..") by "..result.fullname)
				end

				exports.oxmysql:execute('SELECT id, tags FROM emsmdtdata WHERE cid=:cid LIMIT 1', { cid = cid }, function(user)
					if user and user[1] then
						local tags = json.decode(user[1]['tags'])
						for i=1, #tags do
							if tags[i] == tagtext then
								table.remove(tags, i)
							end
						end
						UpdateTags(user[1]['id'], tags)
					else
						CreateUser(cid, 'emsmdtdata', function(result)
							UpdateTags(result, {})
						end)
					end
				end)
			end
		end
	end)
end)

RegisterNetEvent("mdt:server:updateLicense", function(cid, type, status)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		if GetJobType(Player.PlayerData.job.name) == 'police' then
			ManageLicense(cid, type, status)
		end
	end
end)

RegisterNetEvent("mdt:server:addGalleryImg", function(cid, img)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		if GetJobType(Player.PlayerData.job.name) == 'police' then
			local function UpdateGallery(id, gallery)
				exports.oxmysql:executeSync("UPDATE policemdtdata SET `gallery`=:gallery WHERE `id`=:id LIMIT 1", { id = id, gallery = json.encode(gallery) })
				TriggerEvent('mdt:server:AddLog', "A user with the Citizen ID "..id.." had their gallery updated (+) by "..result.fullname)
			end

			exports.oxmysql:execute('SELECT id, gallery FROM policemdtdata WHERE cid=:cid LIMIT 1', { cid = cid }, function(user)
				if user and user[1] then
					local imgs = json.decode(user[1]['gallery'])
					table.insert(imgs, img)
					UpdateGallery(user[1]['id'], imgs)
				else
					CreateUser(cid, 'policemdtdata', function(result)
						local imgs = {}
						table.insert(imgs, img)
						UpdateGallery(result, imgs)
					end)
				end
			end)
		end
	end
end)

RegisterNetEvent("mdt:server:removeGalleryImg", function(cid, img)
	TriggerEvent('echorp:getplayerfromid', source, function(result)
		if result then
			if result.job and (result.job.isPolice or result.job.name == 'doj') then

				local function UpdateGallery(id, gallery)
					exports.oxmysql:executeSync("UPDATE policemdtdata SET `gallery`=:gallery WHERE `id`=:id LIMIT 1", { id = id, gallery = json.encode(gallery) })
					TriggerEvent('mdt:server:AddLog', "A user with the Citizen ID "..id.." had their gallery updated (-) by "..result.fullname)
				end

				exports.oxmysql:execute('SELECT id, gallery FROM policemdtdata WHERE cid=:cid LIMIT 1', { cid = cid }, function(user)
					if user and user[1] then
						local imgs = json.decode(user[1]['gallery'])
						--table.insert(imgs, img)
						for i=1, #imgs do
							if imgs[i] == img then
								table.remove(imgs, i)
							end
						end

						UpdateGallery(user[1]['id'], imgs)
					else
						CreateUser(cid, 'policemdtdata', function(result)
							local imgs = {}
							UpdateGallery(result, imgs)
						end)
					end
				end)
			elseif result.job and (result.job.name == 'ambulance') then

				local function UpdateGallery(id, gallery)
					exports.oxmysql:executeSync("UPDATE emsmdtdata SET `gallery`=:gallery WHERE `id`=:id LIMIT 1", { id = id, gallery = json.encode(gallery) })
					TriggerEvent('mdt:server:AddLog', "A user with the Citizen ID "..id.." had their gallery updated (-) by "..result.fullname)
				end

				exports.oxmysql:execute('SELECT id, gallery FROM emsmdtdata WHERE cid=:cid LIMIT 1', { cid = cid }, function(user)
					if user and user[1] then
						local imgs = json.decode(user[1]['gallery'])
						--table.insert(imgs, img)
						for i=1, #imgs do
							if imgs[i] == img then
								table.remove(imgs, i)
							end
						end

						UpdateGallery(user[1]['id'], imgs)
					else
						CreateUser(cid, 'emsmdtdata', function(result)
							local imgs = {}
							UpdateGallery(result, imgs)
						end)
					end
				end)
			end
		end
	end)
end)

-- Incidents


RegisterNetEvent('mdt:server:getAllIncidents', function()
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		if GetJobType(Player.PlayerData.job.name) == 'police' then
			exports.oxmysql:execute("SELECT * FROM `mdt_incidents` ORDER BY `id` DESC LIMIT 30", {}, function(matches)
				TriggerClientEvent('mdt:client:getAllIncidents', src, matches)
			end)
		end
	end
end)

RegisterNetEvent('mdt:server:searchIncidents', function(query)
	if query then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			if GetJobType(Player.PlayerData.job.name) == 'police' then
				exports.oxmysql:execute("SELECT * FROM `mdt_incidents` WHERE `id` LIKE :query OR LOWER(`title`) LIKE :query OR LOWER(`author`) LIKE :query OR LOWER(`details`) LIKE :query OR LOWER(`tags`) LIKE :query OR LOWER(`officersinvolved`) LIKE :query OR LOWER(`civsinvolved`) LIKE :query OR LOWER(`author`) LIKE :query ORDER BY `id` DESC LIMIT 50", {
					query = string.lower('%'..query..'%') -- % wildcard, needed to search for all alike results
				}, function(matches)
					TriggerClientEvent('mdt:client:getIncidents', src, matches)
				end)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:getIncidentData', function(sentId)
	if sentId then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			if GetJobType(Player.PlayerData.job.name) == 'police' then
				exports.oxmysql:execute("SELECT * FROM `mdt_incidents` WHERE `id` = :id", {
					id = sentId
				}, function(matches)
					local data = matches[1]
					data['tags'] = json.decode(data['tags'])
					data['officersinvolved'] = json.decode(data['officersinvolved'])
					data['civsinvolved'] = json.decode(data['civsinvolved'])
					data['evidence'] = json.decode(data['evidence'])
					exports.oxmysql:execute("SELECT * FROM `mdt_incidents` WHERE `id` = :id", {
						id = sentId
					}, function(matches)
						exports.oxmysql:execute("SELECT * FROM `mdt_convictions` WHERE `linkedincident` = :id", {
							id = sentId
						}, function(convictions)
							for i=1, #convictions do
								local res = GetNameFromId(convictions[i]['cid'])
								if res ~= nil then
									convictions[i]['name'] = res
								else
									convictions[i]['name'] = "Unknown"
								end
								convictions[i]['charges'] = json.decode(convictions[i]['charges'])
							end
							TriggerClientEvent('mdt:client:getIncidentData', src, data, convictions)
						end)
					end)
				end)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:getAllBolos', function()
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if GetJobType(Player.PlayerData.job.name) == 'police' then
		exports.oxmysql:execute("SELECT * FROM `mdt_bolos`", {}, function(matches)
			TriggerClientEvent('mdt:client:getAllBolos', src, matches)
		end)
	elseif GetJobType(Player.PlayerData.job.name) == 'ambulance' then
		exports.oxmysql:execute("SELECT * FROM `ems_icu`", {}, function(matches)
			TriggerClientEvent('mdt:client:getAllBolos', src, matches)
		end)
	end
end)

RegisterNetEvent('mdt:server:searchBolos', function(sentSearch)
	if sentSearch then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if GetJobType(Player.PlayerData.job.name) == 'police' then
			exports.oxmysql:execute("SELECT * FROM `mdt_bolos` WHERE `id` LIKE :query OR LOWER(`title`) LIKE :query OR `plate` LIKE :query OR LOWER(`owner`) LIKE :query OR LOWER(`individual`) LIKE :query OR LOWER(`detail`) LIKE :query OR LOWER(`officersinvolved`) LIKE :query OR LOWER(`tags`) LIKE :query OR LOWER(`author`) LIKE :query", {
				query = string.lower('%'..sentSearch..'%') -- % wildcard, needed to search for all alike results
			}, function(matches)
				TriggerClientEvent('mdt:client:getBolos', src, matches)
			end)
		elseif GetJobType(Player.PlayerData.job.name) == 'ambulance' then
			exports.oxmysql:execute("SELECT * FROM `ems_icu` WHERE `id` LIKE :query OR LOWER(`title`) LIKE :query OR `plate` LIKE :query OR LOWER(`owner`) LIKE :query OR LOWER(`individual`) LIKE :query OR LOWER(`detail`) LIKE :query OR LOWER(`officersinvolved`) LIKE :query OR LOWER(`tags`) LIKE :query OR LOWER(`author`) LIKE :query", {
				query = string.lower('%'..sentSearch..'%') -- % wildcard, needed to search for all alike results
			}, function(matches)
				TriggerClientEvent('mdt:client:getBolos', src, matches)
			end)
		end
	end
end)

RegisterNetEvent('mdt:server:getBoloData', function(sentId)
	if sentId then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if GetJobType(Player.PlayerData.job.name) == 'police' then
			exports.oxmysql:execute("SELECT * FROM `mdt_bolos` WHERE `id` = :id LIMIT 1", {
				id = sentId
			}, function(matches)
				local data = matches[1]
				data['tags'] = json.decode(data['tags'])
				data['officersinvolved'] = json.decode(data['officersinvolved'])
				data['gallery'] = json.decode(data['gallery'])
				TriggerClientEvent('mdt:client:getBoloData', src, data)
			end)

		elseif GetJobType(Player.PlayerData.job.name) == 'ambulance' then
			exports.oxmysql:execute("SELECT * FROM `ems_icu` WHERE `id` = :id LIMIT 1", {
				id = sentId
			}, function(matches)
				local data = matches[1]
				data['tags'] = json.decode(data['tags'])
				data['officersinvolved'] = json.decode(data['officersinvolved'])
				data['gallery'] = json.decode(data['gallery'])
				TriggerClientEvent('mdt:client:getBoloData', src, data)
			end)
		end
	end
end)

RegisterNetEvent('mdt:server:newBolo', function(existing, id, title, plate, owner, individual, detail, tags, gallery, officersinvolved, time)
	if id then
		local src = source 
		local Player = QBCore.Functions.GetPlayer(src)
		if GetJobType(Player.PlayerData.job.name) == 'police' then
			local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname

			local function InsertBolo()
				exports.oxmysql:insert('INSERT INTO `mdt_bolos` (`title`, `author`, `plate`, `owner`, `individual`, `detail`, `tags`, `gallery`, `officersinvolved`, `time`) VALUES (:title, :author, :plate, :owner, :individual, :detail, :tags, :gallery, :officersinvolved, :time)', {
					title = title,
					author = fullname,
					plate = plate,
					owner = owner,
					individual = individual,
					detail = detail,
					tags = json.encode(tags),
					gallery = json.encode(gallery),
					officersinvolved = json.encode(officersinvolved),
					time = tostring(time),
				}, function(r)
					if r then
						TriggerClientEvent('mdt:client:boloComplete', src, r)
						TriggerEvent('mdt:server:AddLog', "A new BOLO was created by "..fullname.." with the title ("..title..") and ID ("..id..")")
					end
				end)
			end

			local function UpdateBolo()
				exports.oxmysql:update("UPDATE mdt_bolos SET `title`=:title, plate=:plate, owner=:owner, individual=:individual, detail=:detail, tags=:tags, gallery=:gallery, officersinvolved=:officersinvolved WHERE `id`=:id LIMIT 1", {
					title = title,
					plate = plate,
					owner = owner,
					individual = individual,
					detail = detail,
					tags = json.encode(tags),
					gallery = json.encode(gallery),
					officersinvolved = json.encode(officersinvolved),
					id = id
				}, function(r)
					if r then
						TriggerClientEvent('mdt:client:boloComplete', src, id)
						TriggerEvent('mdt:server:AddLog', "A BOLO was updated by "..fullname.." with the title ("..title..") and ID ("..id..")")
					end
				end)
			end

			if existing then
				UpdateBolo()
			elseif not existing then
				InsertBolo()
			end
		elseif GetJobType(Player.PlayerData.job.name) == 'ambulance' then

			local function InsertBolo()
				exports.oxmysql:insert('INSERT INTO `ems_icu` (`title`, `author`, `plate`, `owner`, `individual`, `detail`, `tags`, `gallery`, `officersinvolved`, `time`) VALUES (:title, :author, :plate, :owner, :individual, :detail, :tags, :gallery, :officersinvolved, :time)', {
					title = title,
					author = fullname,
					plate = plate,
					owner = owner,
					individual = individual,
					detail = detail,
					tags = json.encode(tags),
					gallery = json.encode(gallery),
					officersinvolved = json.encode(officersinvolved),
					time = tostring(time),
				}, function(r)
					if r then
						TriggerClientEvent('mdt:client:boloComplete', src, r)
						TriggerEvent('mdt:server:AddLog', "A new ICU Check-in was created by "..fullname.." with the title ("..title..") and ID ("..id..")")
					end
				end)
			end

			local function UpdateBolo()
				exports.oxmysql:update("UPDATE `ems_icu` SET `title`=:title, plate=:plate, owner=:owner, individual=:individual, detail=:detail, tags=:tags, gallery=:gallery, officersinvolved=:officersinvolved WHERE `id`=:id LIMIT 1", {
					title = title,
					plate = plate,
					owner = owner,
					individual = individual,
					detail = detail,
					tags = json.encode(tags),
					gallery = json.encode(gallery),
					officersinvolved = json.encode(officersinvolved),
					id = id
				}, function(affectedRows)
					if affectedRows > 0 then
						TriggerClientEvent('mdt:client:boloComplete', src, id)
						TriggerEvent('mdt:server:AddLog', "A ICU Check-in was updated by "..fullname.." with the title ("..title..") and ID ("..id..")")
					end
				end)
			end

			if existing then
				UpdateBolo()
			elseif not existing then
				InsertBolo()
			end
		end
	end
end)

RegisterNetEvent('mdt:server:deleteBolo', function(id)
	if id then
		local src = source 
		local Player = QBCore.Functions.GetPlayer(src)
		if GetJobType(Player.PlayerData.job.name) == 'police' then
			local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
			exports.oxmysql:executeSync("DELETE FROM `mdt_bolos` WHERE id=:id", { id = id })
			TriggerEvent('mdt:server:AddLog', "A BOLO was deleted by "..fullname.." with the ID ("..id..")")
		end
	end
end)

RegisterNetEvent('mdt:server:deleteICU', function(id)
	if id then
		local src = source 
		local Player = QBCore.Functions.GetPlayer(src)
		if GetJobType(Player.PlayerData.job.name) == 'ambulance' then
			local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
			exports.oxmysql:executeSync("DELETE FROM `ems_icu` WHERE id=:id", { id = id })
			TriggerEvent('mdt:server:AddLog', "A ICU Check-in was deleted by "..fullname.." with the ID ("..id..")")
		end
	end
end)

RegisterNetEvent('mdt:server:incidentSearchPerson', function(query)
    if query then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			local JobType = GetJobType(Player.PlayerData.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local function ProfPic(gender, profilepic)
					if profilepic then return profilepic end;
					if gender == "f" then return "img/female.png" end;
					return "img/male.png"
				end

				--exports.oxmysql:execute("SELECT id, firstname, lastname, gender FROM `players` WHERE LOWER(`firstname`) LIKE :query OR LOWER(`lastname`) LIKE :query OR LOWER(`id`) LIKE :query OR CONCAT(LOWER(`firstname`), ' ', LOWER(`lastname`)) LIKE :query LIMIT 30", {

				exports.oxmysql:execute("SELECT p.citizenid, p.charinfo, md.pfp from players p LEFT JOIN mdt_data md on p.citizenid = md.cid WHERE LOWER(`charinfo`) LIKE :query OR LOWER(`citizenid`) LIKE :query LIMIT 30", {
					query = string.lower('%'..query..'%') -- % wildcard, needed to search for all alike results
				}, function(result)
					local data = {}
					for i=1, #result do
						local charinfo = json.decode(result[i].charinfo)
						data[i] = {id = result[i].citizenid, firstname = charinfo.firstname, lastname = charinfo.lastname, profilepic = ProfPic(charinfo.gender, result[i].pfp)}
					end
					TriggerClientEvent('mdt:client:incidentSearchPerson', src, data)
				end)
            end
        end
    end
end)

RegisterNetEvent('mdt:server:getAllReports', function()
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		local JobType = GetJobType(Player.PlayerData.job.name)
		if JobType == 'police' then
			exports.oxmysql:execute("SELECT * FROM `mdt_reports` ORDER BY `id` DESC LIMIT 30", {}, function(matches)
				TriggerClientEvent('mdt:client:getAllReports', src, matches)
			end)
		end
	end
end)

RegisterNetEvent('mdt:server:getReportData', function(sentId)
	if sentId then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			local JobType = GetJobType(Player.PlayerData.job.name)
			if JobType == 'police' or JobType == 'ambulance' then
				exports.oxmysql:execute("SELECT * FROM `mdt_reports` WHERE `id` = :id AND `jobtype` = :jobtype LIMIT 1", {
					id = sentId,
					jobtype = JobType
				}, function(matches)
					local data = matches[1]
					data['tags'] = json.decode(data['tags'])
					data['officersinvolved'] = json.decode(data['officersinvolved'])
					data['civsinvolved'] = json.decode(data['civsinvolved'])
					data['gallery'] = json.decode(data['gallery'])
					TriggerClientEvent('mdt:client:getReportData', src, data)
				end)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:searchReports', function(sentSearch)
	if sentSearch then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			local JobType = GetJobType(Player.PlayerData.job.name)
			if JobType == 'police' or JobType == 'ambulance' then
				exports.oxmysql:execute("SELECT * FROM `mdt_reports` WHERE `id` LIKE :query OR LOWER(`author`) LIKE :query OR LOWER(`title`) LIKE :query OR LOWER(`type`) LIKE :query OR LOWER(`details`) LIKE :query OR LOWER(`tags`) LIKE :query AND `jobtype` = :jobtype ORDER BY `id` DESC LIMIT 50", {
					query = string.lower('%'..sentSearch..'%'), -- % wildcard, needed to search for all alike results
					jobtype = JobType
				}, function(matches)
					TriggerClientEvent('mdt:client:getAllReports', src, matches)
				end)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:newReport', function(existing, id, title, reporttype, details, tags, gallery, officers, civilians, time)
	if id then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			local JobType = GetJobType(Player.PlayerData.job.name)
			if JobType == 'police' or JobType == 'ambulance' then
				local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
				local function InsertReport()
					exports.oxmysql:insert('INSERT INTO `mdt_reports` (`title`, `author`, `type`, `details`, `tags`, `gallery`, `officersinvolved`, `civsinvolved`, `time`, `jobtype`) VALUES (:title, :author, :type, :details, :tags, :gallery, :officersinvolved, :civsinvolved, :time, :jobtype)', {
						title = title,
						author = fullname,
						type = reporttype,
						details = details,
						tags = json.encode(tags),
						gallery = json.encode(gallery),
						officersinvolved = json.encode(officers),
						civsinvolved = json.encode(civilians),
						time = tostring(time),
						jobtype = JobType,
					}, function(r)
						if r then
							TriggerClientEvent('mdt:client:reportComplete', src, r)
							TriggerEvent('mdt:server:AddLog', "A new report was created by "..fullname.." with the title ("..title..") and ID ("..id..")")
						end
					end)
				end

				local function UpdateReport()
					exports.oxmysql:update("UPDATE `mdt_reports` SET `title` = :title, type = :type, details = :details, tags = :tags, gallery = :gallery, officersinvolved = :officersinvolved, civsinvolved = :civsinvolved, jobtype = :jobtype WHERE `id` = :id LIMIT 1", {
						title = title,
						type = reporttype,
						details = details,
						tags = json.encode(tags),
						gallery = json.encode(gallery),
						officersinvolved = json.encode(officers),
						civsinvolved = json.encode(civilians),
						jobtype = JobType,
						id = id,
					}, function(affectedRows)
						if affectedRows > 0 then
							TriggerClientEvent('mdt:client:reportComplete', src, id)
							TriggerEvent('mdt:server:AddLog', "A report was updated by "..fullname.." with the title ("..title..") and ID ("..id..")")
						end
					end)
				end

				if existing then
					UpdateReport()
				elseif not existing then
					InsertReport()
				end
			end
		end
	end
end)

QBCore.Functions.CreateCallback('mdt:server:SearchVehicles', function(source, cb, sentData)
	if not sentData then  return cb({}) end
	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(source, PlayerData) then return cb({}) end

	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		if GetJobType(Player.PlayerData.job.name) == 'police' then
			local vehicles = MySQL.query.await("SELECT pv.id, pv.citizenid, pv.plate, pv.vehicle, pv.mods, p.charinfo FROM `player_vehicles` pv LEFT JOIN players p ON pv.citizenid = p.citizenid WHERE LOWER(`plate`) LIKE :query OR LOWER(`vehicle`) LIKE :query LIMIT 25", {
				query = string.lower('%'..sentData..'%')
			})

			if not next(vehicles) then cb({}) return end

			for _, value in ipairs(vehicles) do
				if value.state == 0 then
					value.state = "Out"
				elseif value.state == 1 then
					value.state = "Garaged"
				elseif value.state == 2 then
					value.state = "Impounded"
				end

				value.bolo = false
				local boloResult = GetBoloStatus(value.plate)
				if boloResult then
					value.bolo = true
				end

				value.code = false
				value.stolen = false
				value.image = "img/not-found.jpg"
				local info = GetVehicleInformation(value.plate)
				if info then
					value.code = info['code5']
					value.stolen = info['stolen']
					value.image = info['image']
				end

				local ownerResult = json.decode(value.charinfo)

				value.owner = ownerResult['firstname'] .. " " .. ownerResult['lastname']
			end
			-- idk if this works or I have to call cb first then return :shrug:
			return cb(vehicles)
		end

		return cb({})
	end

end)

RegisterNetEvent('mdt:server:getVehicleData', function(plate)
	if plate then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			if GetJobType(Player.PlayerData.job.name) == 'police' then
				exports.oxmysql:execute("select pv.*, p.charinfo from player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid where pv.plate = :plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")}, function(vehicle)
					if vehicle and vehicle[1] then
						vehicle[1]['impound'] = false
						if vehicle.state == 2 then
							vehicle[1]['impound'] = true
						end

						vehicle[1]['bolo'] = false
						vehicle[1]['information'] = ""

						-- Bolo Status
						GetBoloStatus(vehicle[1]['plate'], function(boloStatus)
							if boloStatus and boloStatus[1] then vehicle[1]['bolo'] = true end
						end) -- Used to get BOLO status.

						vehicle[1]['name'] = "Unknown Person"		

						local ownerResult = json.decode(vehicle[1].charinfo)
						vehicle[1]['name'] = ownerResult['firstname'] .. " " .. ownerResult['lastname']

						local color1 = json.decode(vehicle[1].mods)
						vehicle[1]['color1'] = color1['color1']

						vehicle[1]['dbid'] = 0

						local info = GetVehicleInformation(vehicle[1]['plate'])
						if info then
							vehicle[1]['information'] = info['information']
							vehicle[1]['dbid'] = info['id']
							vehicle[1]['image'] = info['image']
							vehicle[1]['code'] = info['code5']
							vehicle[1]['stolen'] = info['stolen']
						end

						if vehicle[1]['image'] == nil then vehicle[1]['image'] = "img/not-found.jpg" end -- Image
					end
					
					TriggerClientEvent('mdt:client:getVehicleData', src, vehicle)
				end)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:saveVehicleInfo', function(dbid, plate, imageurl, notes, stolen, code5)
	if plate then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			if GetJobType(Player.PlayerData.job.name) == 'police' then
				if dbid == nil then dbid = 0 end;
				local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
				--exports.oxmysql:executeSync("UPDATE owned_vehicles SET `image`=:image WHERE `plate`=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1"), image = imageurl })
				TriggerEvent('mdt:server:AddLog', "A vehicle with the plate ("..plate..") has a new image ("..imageurl..") edited by "..fullname)
				if tonumber(dbid) == 0 then
					exports.oxmysql:insert('INSERT INTO `mdt_vehicleinfo` (`plate`, `information`, `image`, `code5`, `stolen`) VALUES (:plate, :information, :image, :code5, :stolen)', { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1"), information = notes, image = imageurl, code5 = code5, stolen = stolen }, function(infoResult)
						if infoResult then
							TriggerClientEvent('mdt:client:updateVehicleDbId', src, infoResult)
							TriggerEvent('mdt:server:AddLog', "A vehicle with the plate ("..plate..") was added to the vehicle information database by "..fullname)
						end
					end)
				elseif tonumber(dbid) > 0 then
					exports.oxmysql:executeSync("UPDATE mdt_vehicleinfo SET `information`= :information, `image`= :image, `code5`= :code5, `stolen`= :stolen WHERE `plate`= :plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1"), information = notes, image = imageurl, code5 = code5, stolen = stolen })
				end
			end
		end
	end
end)

RegisterNetEvent('mdt:server:knownInformation', function(dbid, type, status, plate)
	if plate then
		TriggerEvent('echorp:getplayerfromid', source, function(result)
			if result then
				if result.job and (result.job.isPolice or result.job.name == 'doj') then
					if dbid == nil then dbid = 0 end;

					if type == 'code5' and status == true then
						exports.oxmysql:executeSync("UPDATE owned_vehicles SET `code`=:code WHERE `plate`=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1"), code = 5 })
						TriggerEvent('mdt:server:AddLog', "A vehicle with the plate ("..plate..") was set to CODE 5 by "..result['fullname'])
					elseif type == 'code5' and not status then
						exports.oxmysql:executeSync("UPDATE owned_vehicles SET `code`=:code WHERE `plate`=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1"), code = 0 })
						TriggerEvent('mdt:server:AddLog', "A vehicle with the plate ("..plate..") had it's CODE 5 status removed by "..result['fullname'])
					elseif type == 'stolen' and status then
						exports.oxmysql:executeSync("UPDATE owned_vehicles SET `stolen`=:stolen WHERE `plate`=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1"), stolen = 1 })
						TriggerEvent('mdt:server:AddLog', "A vehicle with the plate ("..plate..") was set to STOLEN by "..result['fullname'])
					elseif type == 'stolen' and not status then
						exports.oxmysql:executeSync("UPDATE owned_vehicles SET `stolen`=:stolen WHERE `plate`=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1"), stolen = 0 })
						TriggerEvent('mdt:server:AddLog', "A vehicle with the plate ("..plate..") had it's STOLEN status removed by "..result['fullname'])
					end

					if tonumber(dbid) == 0 then
						exports.oxmysql:insert('INSERT INTO `pd_vehicleinfo` (`plate`) VALUES (:plate)', { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1") }, function(infoResult)
							if infoResult then
								TriggerClientEvent('mdt:client:updateVehicleDbId', result.source, infoResult)
								TriggerEvent('mdt:server:AddLog', "A vehicle with the plate ("..plate..") was added to the vehicle information database by "..result['fullname'])
							end
						end)
					end
				end
			end
		end)
	end
end)


RegisterNetEvent('mdt:server:getAllLogs', function()
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		-- if Config.LogPerms[Player.PlayerData.job.name] then
		-- 	if Config.LogPerms[Player.PlayerData.job.name][Player.PlayerData.job.grade.level] then
				local JobType = GetJobType(Player.PlayerData.job.name)
				exports.oxmysql:execute('SELECT * FROM mdt_logs WHERE `jobtype` = :jobtype ORDER BY `id` DESC LIMIT 250', {jobtype = JobType}, function(infoResult)
					TriggerLatentClientEvent('mdt:client:getAllLogs', src, 30000, infoResult)
				end)
		-- 	end
		-- end
	end
end)

-- Penal Code

local function IsCidFelon(sentCid, cb)
	if sentCid then
		exports.oxmysql:execute('SELECT charges FROM mdt_convictions WHERE cid=:cid', { cid = sentCid }, function(convictions)
			local Charges = {}
			for i=1, #convictions do
				local currCharges = json.decode(convictions[i]['charges'])
				for x=1, #currCharges do
					table.insert(Charges, currCharges[x])
				end
			end
			for i=1, #Charges do
				for p=1, #PenalCode do
					for x=1, #PenalCode[p] do
						if PenalCode[p][x]['title'] == Charges[i] then
							if PenalCode[p][x]['class'] == 'Felony' then
								cb(true)
								return
							end
							break
						end
					end
				end
			end
			cb(false)
		end)
	end
end

exports('IsCidFelon', IsCidFelon) -- exports['erp_mdt']:IsCidFelon()

RegisterCommand("isfelon", function(source, args, rawCommand)
	IsCidFelon(1998, function(res)
		print(res)
	end)
end, false)

RegisterNetEvent('mdt:server:getPenalCode', function()
	local src = source
	TriggerClientEvent('mdt:client:getPenalCode', src, Config.PenalCodeTitles, Config.PenalCode)
end)

RegisterNetEvent('mdt:server:toggleDuty', function(cid, status)
	TriggerEvent('echorp:getplayerfromid', source, function(result)
		local player = exports['echorp']:GetPlayerFromCid(cid)
		if player then
			if player.job.name == "ambulance" and player.job.duty == 0 then
                local mzDist = #(GetEntityCoords(GetPlayerPed(source)) - vector3(-475.15, -314.0, 62.15))
                if mzDist > 100 then TriggerClientEvent('erp_notifications:client:SendAlert', source, { type = 'error', text = 'You must be at Mount Zonah to clock in!!', length = 5000 }) TriggerClientEvent('mdt:client:exitMDT',source) return end
            end
			if player.job.isPolice or player.job.name == 'ambulance' or player.job.name == 'doj' then
				local isPolice = false
				if policeJobs[player.job.name] then isPolice = true end;
				exports['echorp']:SetPlayerData(player.source, 'job', {name = player.job.name, grade = player.job.grade, duty = status, isPolice = isPolice})
				exports.oxmysql:executeSync("UPDATE users SET duty=:duty WHERE id=:cid", { duty = status, cid = cid})
				if status == 0 then
					TriggerEvent('mdt:server:AddLog', result['fullname'].." set "..player['fullname']..'\'s duty to 10-7')
				else
					TriggerEvent('mdt:server:AddLog', result['fullname'].." set "..player['fullname']..'\'s duty to 10-8')
				end
			end
		end
	end)
end)

RegisterNetEvent('mdt:server:setCallsign', function(cid, newcallsign)
	local Player = QBCore.Functions.GetPlayerByCitizenId(cid)
	Player.Functions.SetMetaData("callsign", newcallsign)
end)

RegisterNetEvent('mdt:server:saveIncident', function(id, title, information, tags, officers, civilians, evidence, associated, time)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		if GetJobType(Player.PlayerData.job.name) == 'police' then
			if id == 0 then
				local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
				exports.oxmysql:insert('INSERT INTO `mdt_incidents` (`author`, `title`, `details`, `tags`, `officersinvolved`, `civsinvolved`, `evidence`, `time`, `jobtype`) VALUES (:author, :title, :details, :tags, :officersinvolved, :civsinvolved, :evidence, :time, :jobtype)',
				{
					author = fullname,
					title = title,
					details = information,
					tags = json.encode(tags),
					officersinvolved = json.encode(officers),
					civsinvolved = json.encode(civilians),
					evidence = json.encode(evidence),
					time = time,
					jobtype = 'police',
				}, function(infoResult)
					if infoResult then
						for i=1, #associated do
							exports.oxmysql:executeSync('INSERT INTO `mdt_convictions` (`cid`, `linkedincident`, `warrant`, `guilty`, `processed`, `associated`, `charges`, `fine`, `sentence`, `recfine`, `recsentence`, `time`) VALUES (:cid, :linkedincident, :warrant, :guilty, :processed, :associated, :charges, :fine, :sentence, :recfine, :recsentence, :time)', {
								cid = associated[i]['Cid'],
								linkedincident = infoResult,
								warrant = associated[i]['Warrant'],
								guilty = associated[i]['Guilty'],
								processed = associated[i]['Processed'],
								associated = associated[i]['Isassociated'],
								charges = json.encode(associated[i]['Charges']),
								fine = tonumber(associated[i]['Fine']),
								sentence = tonumber(associated[i]['Sentence']),
								recfine = tonumber(associated[i]['recfine']),
								recsentence = tonumber(associated[i]['recsentence']),
								time = time
							})
						end
						TriggerClientEvent('mdt:client:updateIncidentDbId', src, infoResult)
						--TriggerEvent('mdt:server:AddLog', "A vehicle with the plate ("..plate..") was added to the vehicle information database by "..player['fullname'])
					end
				end)
			elseif id > 0 then
				exports.oxmysql:executeSync("UPDATE mdt_incidents SET title=:title, details=:details, civsinvolved=:civsinvolved, tags=:tags, officersinvolved=:officersinvolved, evidence=:evidence WHERE id=:id", {
					title = title,
					details = information,
					tags = json.encode(tags),
					officersinvolved = json.encode(officers),
					civsinvolved = json.encode(civilians),
					evidence = json.encode(evidence),
					id = id
				})
				for i=1, #associated do
					TriggerEvent('mdt:server:handleExistingConvictions', associated[i], id, time)
				end
			end
		end
	end
end)

RegisterNetEvent('mdt:server:handleExistingConvictions', function(data, incidentid, time)
	exports.oxmysql:execute('SELECT * FROM mdt_convictions WHERE cid=:cid AND linkedincident=:linkedincident', {
		cid = data['Cid'],
		linkedincident = incidentid
	}, function(convictionRes)
		if convictionRes and convictionRes[1] and convictionRes[1]['id'] then
			exports.oxmysql:executeSync('UPDATE mdt_convictions SET cid=:cid, linkedincident=:linkedincident, warrant=:warrant, guilty=:guilty, processed=:processed, associated=:associated, charges=:charges, fine=:fine, sentence=:sentence, recfine=:recfine, recsentence=:recsentence WHERE cid=:cid AND linkedincident=:linkedincident', {
				cid = data['Cid'],
				linkedincident = incidentid,
				warrant = data['Warrant'],
				guilty = data['Guilty'],
				processed = data['Processed'],
				associated = data['Isassociated'],
				charges = json.encode(data['Charges']),
				fine = tonumber(data['Fine']),
				sentence = tonumber(data['Sentence']),
				recfine = tonumber(data['recfine']),
				recsentence = tonumber(data['recsentence']),
			})
		else
			exports.oxmysql:executeSync('INSERT INTO `mdt_convictions` (`cid`, `linkedincident`, `warrant`, `guilty`, `processed`, `associated`, `charges`, `fine`, `sentence`, `recfine`, `recsentence`, `time`) VALUES (:cid, :linkedincident, :warrant, :guilty, :processed, :associated, :charges, :fine, :sentence, :recfine, :recsentence, :time)', {
				cid = data['Cid'],
				linkedincident = incidentid,
				warrant = data['Warrant'],
				guilty = data['Guilty'],
				processed = data['Processed'],
				associated = data['Isassociated'],
				charges = json.encode(data['Charges']),
				fine = tonumber(data['Fine']),
				sentence = tonumber(data['Sentence']),
				recfine = tonumber(data['recfine']),
				recsentence = tonumber(data['recsentence']),
				time = time
			})
		end
	end)
end)

RegisterNetEvent('mdt:server:removeIncidentCriminal', function(cid, incident)
	exports.oxmysql:executeSync('DELETE FROM mdt_convictions WHERE cid=:cid AND linkedincident=:linkedincident', {
		cid = cid,
		linkedincident = incident
	})
end)

-- Dispatch

RegisterNetEvent('mdt:server:setWaypoint', function(callid)
	local src = source
	local Player = QBCore.Functions.GetPlayer(source)
	local JobType = GetJobType(Player.PlayerData.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		if callid then
			local calls = exports['qb-dispatch']:GetDispatchCalls()
			TriggerClientEvent('mdt:client:setWaypoint', src, calls[callid])
		end
	end
end)

RegisterNetEvent('mdt:server:callDetach', function(callid)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	local playerdata = {
		fullname = Player.PlayerData.charinfo.firstname.. " "..Player.PlayerData.charinfo.lastname,
		job = Player.PlayerData.job,
		cid = Player.PlayerData.citizenid,
		callsign = Player.PlayerData.metadata.callsign
	}
	local JobType = GetJobType(Player.PlayerData.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		if callid then
			TriggerEvent('dispatch:removeUnit', callid, playerdata, function(newNum)
				TriggerClientEvent('mdt:client:callDetach', -1, callid, newNum)
			end)
		end
	end
end)

RegisterNetEvent('mdt:server:callAttach', function(callid)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	local playerdata = {
		fullname = Player.PlayerData.charinfo.firstname.. " "..Player.PlayerData.charinfo.lastname,
		job = Player.PlayerData.job,
		cid = Player.PlayerData.citizenid,
		callsign = Player.PlayerData.metadata.callsign
	}
	local JobType = GetJobType(Player.PlayerData.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		if callid then
			TriggerEvent('dispatch:addUnit', callid, playerdata, function(newNum)
				TriggerClientEvent('mdt:client:callAttach', -1, callid, newNum)
			end)
		end
	end
		
end)

RegisterNetEvent('mdt:server:attachedUnits', function(callid)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	local JobType = GetJobType(Player.PlayerData.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		if callid then
			local calls = exports['qb-dispatch']:GetDispatchCalls()
			TriggerClientEvent('mdt:client:attachedUnits', src, calls[callid]['units'], callid)
		end
	end
end)

RegisterNetEvent('mdt:server:callDispatchDetach', function(callid, cid)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	local playerdata = {
		fullname = Player.PlayerData.charinfo.firstname.. " "..Player.PlayerData.charinfo.lastname,
		job = Player.PlayerData.job,
		cid = Player.PlayerData.citizenid,
		callsign = Player.PlayerData.metadata.callsign
	}
	local callid = tonumber(callid)
	local JobType = GetJobType(Player.PlayerData.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		if callid then
			TriggerEvent('dispatch:removeUnit', callid, playerdata, function(newNum)
				TriggerClientEvent('mdt:client:callDetach', -1, callid, newNum)
			end)
		end
	end
end)

RegisterNetEvent('mdt:server:setDispatchWaypoint', function(callid, cid)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	local callid = tonumber(callid)
	local JobType = GetJobType(Player.PlayerData.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		if callid then
			local calls = exports['qb-dispatch']:GetDispatchCalls()
			TriggerClientEvent('mdt:client:setWaypoint', src, calls[callid])
		end
	end
	
end)

RegisterNetEvent('mdt:server:callDragAttach', function(callid, cid)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	local playerdata = {
		name = Player.PlayerData.charinfo.firstname.. " "..Player.PlayerData.charinfo.lastname,
		job = Player.PlayerData.job.name,
		cid = Player.PlayerData.citizenid,
		callsign = Player.PlayerData.metadata.callsign
	}
	local callid = tonumber(callid)
	local JobType = GetJobType(Player.PlayerData.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		if callid then
			TriggerEvent('dispatch:addUnit', callid, playerdata, function(newNum)
				TriggerClientEvent('mdt:client:callAttach', -1, callid, newNum)
			end)
		end
	end
end)

RegisterNetEvent('mdt:server:setWaypoint:unit', function(cid)
	local src = source
	local Player = QBCore.Functions.GetPlayerByCitizenId(cid)
	local PlayerCoords = GetEntityCoords(GetPlayerPed(Player.PlayerData.source))
	TriggerClientEvent("mdt:client:setWaypoint:unit", src, PlayerCoords)
end)

-- Dispatch chat

RegisterNetEvent('mdt:server:sendMessage', function(message, time)
	if message and time then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			exports.oxmysql:execute("SELECT pfp FROM `mdt_data` WHERE cid=:id LIMIT 1", {
				id = Player.PlayerData.citizenid -- % wildcard, needed to search for all alike results
			}, function(data)
				if data and data[1] then
					local ProfilePicture = ProfPic(Player.PlayerData.charinfo.gender, data[1]['profilepic'])
					local callsign = GetResourceKvpString(Player.PlayerData.metadata.callsign..'-callsign') or "000"
					local Item = {
						profilepic = ProfilePicture,
						callsign = Player.PlayerData.metadata.callsign,
						cid = Player.PlayerData.citizenid,
						name = '('..callsign..') '..Player.PlayerData.charinfo.firstname.. " "..Player.PlayerData.charinfo.lastname,
						message = message,
						time = time,
						job = Player.PlayerData.job.name
					}
					table.insert(dispatchMessages, Item)
					TriggerClientEvent('mdt:client:dashboardMessage', -1, Item)
					-- Send to all clients, for auto updating stuff, ya dig.
				end
			end)
		end
	end
end)

RegisterNetEvent('mdt:server:refreshDispatchMsgs', function()
	local src = source
	local PlayerData = GetPlayerData(src)
	if IsJobAllowedToMDT(PlayerData.job.name) then
		TriggerClientEvent('mdt:client:dashboardMessages', src, dispatchMessages)
	end
end)

RegisterNetEvent('mdt:server:getCallResponses', function(callid)
	TriggerEvent('echorp:getplayerfromid', source, function(result)
		if result then
			if result.job and (result.job.isPolice or (result.job.name == 'ambulance')) then
				local calls = exports['qb-dispatch']:GetDispatchCalls()
				TriggerClientEvent('mdt:client:getCallResponses', result.source, calls[callid]['responses'], callid)
			end
		end
	end)
end)

RegisterNetEvent('mdt:server:sendCallResponse', function(message, time, callid)
	TriggerEvent('echorp:getplayerfromid', source, function(result)
		if result then
			if result.job and (result.job.isPolice or (result.job.name == 'ambulance')) then
				TriggerEvent('dispatch:sendCallResponse', result, callid, message, time, function(isGood)
					if isGood then
						TriggerClientEvent('mdt:client:sendCallResponse', -1, message, time, callid, result['fullname'])
					end
				end)
			end
		end
	end)
end)

RegisterNetEvent('mdt:server:setRadio', function(cid, newcallsign)
	TriggerEvent('echorp:getplayerfromid', source, function(result)
		if result then
			if result.job.isPolice or result.job.name == 'ambulance' or result.job.name == 'doj' then
				local tgtPlayer = exports['echorp']:GetPlayerFromCid(cid)
				if tgtPlayer then
					TriggerClientEvent('mdt:client:setRadio', tgtPlayer['source'], newcallsign, result['fullname'])
					TriggerClientEvent("QBCore:Notify", source, 'Radio updated.', 'success')
				end
			end
		end
	end)
end)

local function isRequestVehicle(vehId)
	local found = false
	for i=1, #impound do
		if impound[i]['vehicle'] == vehId then
			found = true
			impound[i] = nil
			break
		end
	end
	return found
end
exports('isRequestVehicle', isRequestVehicle) -- exports['erp_mdt']:isRequestVehicle()

RegisterNetEvent('mdt:server:impoundVehicle', function(sentInfo, sentVehicle)
	TriggerEvent('echorp:getplayerfromid', source, function(player)
		if player then
			if player.job.isPolice then
				if sentInfo and type(sentInfo) == 'table' then
					local plate, linkedreport, fee, time = sentInfo['plate'], sentInfo['linkedreport'], sentInfo['fee'], sentInfo['time']
					if (plate and linkedreport and fee and time) then
						exports.oxmysql:execute("SELECT id, plate FROM `owned_vehicles` WHERE plate=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")}, function(vehicle)
							if vehicle and vehicle[1] then
								local data = vehicle[1]
								exports.oxmysql:insert('INSERT INTO `impound` (`vehicleid`, `linkedreport`, `fee`, `time`) VALUES (:vehicleid, :linkedreport, :fee, :time)', {
									vehicleid = data['id'],
									linkedreport = linkedreport,
									fee = fee,
									time = os.time() + (time * 60)
								}, function(res)
									-- notify?
									local data = {
										vehicleid = data['id'],
										plate = plate,
										beingcollected = 0,
										vehicle = sentVehicle,
										officer = player['fullname'],
										number = player['phone_number'],
										time = os.time() * 1000,
										src = player['source']
									}
									local vehicle = NetworkGetEntityFromNetworkId(sentVehicle)
									FreezeEntityPosition(vehicle, true)
									table.insert(impound, data)
									TriggerClientEvent('mdt:client:notifyMechanics', -1, data)
								end)
							end
						end)
					end
				end
			end
		end
	end)
end)

-- mdt:server:getImpoundVehicles


RegisterNetEvent('mdt:server:getImpoundVehicles', function()
	TriggerClientEvent('mdt:client:getImpoundVehicles', source, impound)
end)

RegisterNetEvent('mdt:server:collectVehicle', function(sentId)
	TriggerEvent('echorp:getplayerfromid', source, function(player)
		if player then
			local source = source
			for i=1, #impound do
				local id = impound[i]['vehicleid']
				if tostring(id) == tostring(sentId) then
					local vehicle = NetworkGetEntityFromNetworkId(impound[i]['vehicle'])
					if not DoesEntityExist(vehicle) then
						TriggerClientEvent('erp_phone:sendNotification', source, {img = 'vehiclenotif.png', title = "Impound", content = "This vehicle has already been impounded.", time = 5000 })
						impound[i] = nil
						return
					end
					local collector = impound[i]['beingcollected']
					if collector ~= 0 and GetPlayerPing(collector) >= 0 then
						TriggerClientEvent('erp_phone:sendNotification', source, {img = 'vehiclenotif.png', title = "Impound", content = "This vehicle is being collected.", time = 5000 })
						return
					end
					impound[i]['beingcollected'] = source
					TriggerClientEvent('mdt:client:collectVehicle', source, GetEntityCoords(vehicle))
					TriggerClientEvent('erp_phone:sendNotification', impound[i]['src'], {img = 'vehiclenotif.png', title = "Impound", content = player['fullname'].." is collecing the vehicle with plate "..impound[i]['plate'].."!", time = 5000 })
					break
				end
			end
		end
	end)
end)

RegisterNetEvent('mdt:server:removeImpound', function(plate)
	TriggerEvent('echorp:getplayerfromid', source, function(player)
		if player then
			if player.job.isPolice then
				exports.oxmysql:execute("SELECT id, plate FROM `owned_vehicles` WHERE plate=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")}, function(vehicle)
					if vehicle and vehicle[1] then
						local data = vehicle[1]
						exports.oxmysql:executeSync("DELETE FROM `impound` WHERE vehicleid=:vehicleid", { vehicleid = data['id'] })
					end
				end)
			end
		end
	end)
end)

RegisterNetEvent('mdt:server:statusImpound', function(plate)
	TriggerEvent('echorp:getplayerfromid', source, function(player)
		if player then
			if player.job.isPolice then
				exports.oxmysql:execute("SELECT id, plate FROM `owned_vehicles` WHERE plate=:plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")}, function(vehicle)
					if vehicle and vehicle[1] then
						local data = vehicle[1]
						exports.oxmysql:execute("SELECT * FROM `impound` WHERE vehicleid=:vehicleid LIMIT 1", { vehicleid = data['id'] }, function(impoundinfo)
							if impoundinfo and impoundinfo[1] then
								TriggerClientEvent('mdt:client:statusImpound', player['source'], impoundinfo[1], plate)
							end
						end)
					end
				end)
			end
		end
	end)
end)

function GetBoloStatus(plate)
    exports.oxmysql:execute("SELECT * FROM mdt_bolos where plate = ?", {plate}, function(bolo)
		if bolo and bolo[1] then
			return true
		else
			return false
		end
	end)
end

function GetVehicleInformation(plate)
	local result = MySQL.Sync.fetchAll('SELECT * FROM mdt_vehicleinfo WHERE plate = @plate', {['@plate'] = plate})
    if result[1] then
        return result[1]
    else
        return false
    end
end
