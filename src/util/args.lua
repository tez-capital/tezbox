local args = cli.parse_args(arg)

local optionAliases = {
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
		if optionAliases[v.id] then
			v.id = optionAliases[v.id]
		end
		options[v.id] = v.value
	end
end

return {
	command = command,
	parameters = parameters,
	options = options
}