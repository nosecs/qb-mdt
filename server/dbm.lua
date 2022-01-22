local QBCore = exports['qb-core']:GetCoreObject()

-- (Start) Opening the MDT and sending data
function AddLog(text)
	print(text)
    return MySQL.insert.await('INSERT INTO `mdt_logs` (`text`, `time`) VALUES (?,?)', {text, os.time() * 1000})
	-- return exports.oxmysql:execute('INSERT INTO `mdt_logs` (`text`, `time`) VALUES (:text, :time)', { text = text, time = os.time() * 1000 })
end

function GetNameFromId(cid)
	-- Should be a scalar?
	return MySQL.scalar.await('SELECT charinfo FROM `users` WHERE cid = ? LIMIT 1', { cid })
	-- return exports.oxmysql:executeSync('SELECT firstname, lastname FROM `users` WHERE id = :id LIMIT 1', { id = cid })
end

-- idk what this is used for either
function GetPersonInformation(cid, jobtype)
	return MySQL.query.await('SELECT information, tags, gallery FROM mdt_data WHERE cid = ? and jobtype = ?', { cid, jobtype })
	-- return exports.oxmysql:executeSync('SELECT information, tags, gallery FROM mdt WHERE cid= ? and type = ?', { cid, jobtype })
end

-- idk but I guess sure?
function GetIncidentName(id)
	-- Should also be a scalar
	return MySQL.query.await('SELECT title FROM `mdt_incidents` WHERE id = :id LIMIT 1', { id = id })
	-- return exports.oxmysql:executeSync('SELECT title FROM `mdt_incidents` WHERE id = :id LIMIT 1', { id = id })
end

function GetConvictions(cids)
	return MySQL.query.await('SELECT * FROM `mdt_convictions` WHERE `cid` IN(?)', { cids })
	-- return exports.oxmysql:executeSync('SELECT * FROM `mdt_convictions` WHERE `cid` IN(?)', { cids })
end

function GetLicenseInfo(cid)
	return MySQL.query.await('SELECT * FROM `licenses` WHERE `cid` = ?', { cid })
	-- return exports.oxmysql:executeSync('SELECT * FROM `licenses` WHERE `cid`=:cid', { cid = cid })
end

function CreateUser(cid, tableName)
	AddLog("A user was created with the CID: "..cid)
	-- return exports.oxmysql:insert("INSERT INTO `"..dbname.."` (cid) VALUES (:cid)", { cid = cid })
	return MySQL.insert.await("INSERT INTO `"..tableName.."` (cid) VALUES (:cid)", { cid = cid })
end

function GetVehicleInformation(cid, cb)
	return MySQL.query.await('SELECT id, plate, vehicle FROM owned_vehicles WHERE owner=:cid', { cid = cid })
	-- return exports.oxmysql:executeSync('SELECT id, plate, vehicle FROM owned_vehicles WHERE owner=:cid', { cid = cid })
end

function GetBulletins(JobType)
	return MySQL.query.await('SELECT * FROM `mdt_bulletin` WHERE `jobtype` = ? LIMIT 10', { JobType })
	-- return exports.oxmysql:executeSync('SELECT * FROM `mdt_bulletin` WHERE `type`= ? LIMIT 10', { JobType })
end

function GetPlayerDataById(id)
	return MySQL.single.await('SELECT citizenid, charinfo, job, metadata FROM players WHERE citizenid = ? LIMIT 1', { id })
	-- return exports.oxmysql:executeSync('SELECT citizenid, charinfo, job FROM players WHERE citizenid = ? LIMIT 1', { id })
end

-- Probs also best not to use
function GetImpoundStatus(vehicleid, cb)
	cb( #(exports.oxmysql:executeSync('SELECT id FROM `impound` WHERE `vehicleid`=:vehicleid', {['vehicleid'] = vehicleid })) > 0 )
end

function GetBoloStatus(plate)
	return MySQL.scalar.await('SELECT id FROM `mdt_bolos` WHERE LOWER(`plate`)=:plate', { plate = string.lower(plate)})
	-- return exports.oxmysql:scalarSync('SELECT id FROM `mdt_bolos` WHERE LOWER(`plate`)=:plate', { plate = string.lower(plate)})
end

function GetOwnerName(cid)
	return MySQL.scalar.await('SELECT charinfo FROM `players` WHERE LOWER(`citizenid`) = ? LIMIT 1', {cid})
	-- return exports.oxmysql:scalarSync('SELECT charinfo FROM `players` WHERE id=:cid LIMIT 1', { cid = cid})
end

function GetVehicleInformation(plate, cb)
	cb(exports.oxmysql:executeSync('SELECT id, information FROM `mdt_vehicleinfo` WHERE plate=:plate', { plate = plate}))
end