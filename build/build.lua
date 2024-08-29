local amalg = loadfile("./build/amalg.lua")

local function collect_requires(entrypoint)
	local requires = {}
	local ok, content = fs.safe_read_file(entrypoint)
	if not ok then
		return requires
	end
	for require in content:gmatch("require%s*%(?%s*['\"](.-)['\"]%s*%)?") do
		if not table.includes(requires, require) then
			-- change require to path
			local file = require:gsub("%.", "/") .. ".lua"
			if fs.file_type(file) == "file" then
				table.insert(requires, require)
				local subRequires = collect_requires(file)
				requires = util.merge_arrays(requires, subRequires) --[[ @as table ]]
			end
		end
	end
	return requires
end

local function inject_license(filePath)
	local _content = fs.read_file(filePath)
	local _, _shebangEnd = _content:find("#!/[^\n]*")
	local _license = [[
-- Copyright (C) 2024 tez.capital

-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.

-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
	]]
	local _contentWithLicense = _content:sub(1, _shebangEnd + 1) .. _license .. _content:sub(_shebangEnd + 1)
	fs.write_file(filePath, _contentWithLicense)
end

os.chdir("src")

fs.mkdir("../bin")

local tezboxEntrypoint = "tezbox.lua"
local tezboxOutput = "../bin/tezbox"
amalg("-o", tezboxOutput, "-s", tezboxEntrypoint, table.unpack(collect_requires(tezboxEntrypoint)))
inject_license(tezboxOutput)