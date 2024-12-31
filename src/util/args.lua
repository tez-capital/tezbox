local args = cli.parse_args(arg)

local option_aliases = {
	["l"] = "log-level",
	["t"] = "timeout"
}

local parameters = {}
local options = {}
local command = nil

for _, v in ipairs(args) do
	if v.type == "parameter" then
		if command == nil then
			command = tostring(v.value)
		else
			table.insert(parameters, v.value)
		end
	elseif v.type == "option" then
		if option_aliases[v.id] then
			v.id = option_aliases[v.id]
		end
		options[v.id] = v.value
	end
end

return {
	command = command,
	parameters = parameters,
	options = options
}