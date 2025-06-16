local amalg = loadfile("./build/amalg.lua")

local function collect_requires(entrypoint)
	local requires = {}
	local content, _ = fs.read_file(entrypoint)
	if not content then
		return requires
	end
	for require in content:gmatch("require%s*%(?%s*['\"](.-)['\"]%s*%)?") do
		if not table.includes(requires, require) then
			-- change require to path
			local file = require:gsub("%.", "/") .. ".lua"
			if fs.file_type(file) == "file" then
				table.insert(requires, require)
				local sub_requires = collect_requires(file)
				requires = util.merge_arrays(requires, sub_requires) --[[ @as table ]]
			end
		end
	end
	return requires
end

local function inject_license(file_path)
	local content = fs.read_file(file_path)
	local _, shebang_end = content:find("#!/[^\n]*")
	local license = [[
-- Copyright (C) 2025 tez.capital

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
	local content_with_license = content:sub(1, shebang_end + 1) .. license .. content:sub(shebang_end + 1)
	fs.write_file(file_path, content_with_license)
end

os.chdir("src")

fs.mkdir("../bin")

local tezbox_entrypoint = "tezbox.lua"
local tezbox_output = "../bin/tezbox"
amalg("-o", tezbox_output, "-s", tezbox_entrypoint, table.unpack(collect_requires(tezbox_entrypoint)))
inject_license(tezbox_output)