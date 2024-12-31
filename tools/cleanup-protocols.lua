local protocols = os.getenv('PROTOCOLS')
local tezbox_directory = os.getenv("TEZBOX_DIRECTORY") or "/tezbox"
local tezbox_context_directory = path.combine(tezbox_directory, "configuration")

if type (protocols) ~= "string" then
	return
end

if protocols == "all" then
	return
end

-- split by coma
local protocols = string.split(protocols, ",")

local protocol_directory = path.combine(tezbox_context_directory, "protocols")

local protocol_directories = fs.read_dir(protocol_directory, {
	recurse = false,
	return_full_paths = false,
	as_dir_entries = false,
}) --[=[@as string[]]=]

-- remove all directories not in protocols
for _, protocol_directory in ipairs(protocol_directories) do
	if not table.includes(protocols, protocol_directory) then
		fs.remove(path.combine(protocol_directory, protocol_directory), { recurse = true, content_only = false })
	end
end

-- print kept protocols
local protocol_directories = fs.read_dir(protocol_directory, {
	recurse = false,
	return_full_paths = false,
	as_dir_entries = false,
}) --[=[@as string[]]=]

for _, protocol_directory in ipairs(protocol_directories) do
	print(protocol_directory)
end