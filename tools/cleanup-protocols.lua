local protocols = os.getenv('PROTOCOLS')
local tezboxDirectory = os.getenv("TEZBOX_DIRECTORY") or "/tezbox"
local tezboxContextDirectory = path.combine(tezboxDirectory, "configuration")

if type (protocols) ~= "string" then
	return
end

if protocols == "all" then
	return
end

-- split by coma
local protocols = string.split(protocols, ",")

local protocolsDirectory = path.combine(tezboxContextDirectory, "protocols")

local protocolDirectories = fs.read_dir(protocolsDirectory, {
	recurse = false,
	returnFullPaths = false,
	asDirEntries = false,
}) --[=[@as string[]]=]

-- remove all directories not in protocols
for _, protocolDirectory in ipairs(protocolDirectories) do
	if not table.includes(protocols, protocolDirectory) then
		fs.remove(path.combine(protocolsDirectory, protocolDirectory), { recurse = true, contentOnly = false })
	end
end

-- print kept protocols
local protocolDirectories = fs.read_dir(protocolsDirectory, {
	recurse = false,
	returnFullPaths = false,
	asDirEntries = false,
}) --[=[@as string[]]=]

for _, protocolDirectory in ipairs(protocolDirectories) do
	print(protocolDirectory)
end