local env = require "box.env"
local hjson = require "hjson"
local constants = require "box.constants"

local context = {
	protocol_mapping = {},
	protocols = {}
}

function context.setup_file_ownership()
	if env.user ~= "" and env.user ~= "root" then
		local uid, err = fs.getuid(env.user)
		if not uid then
			log_error("can't get uid for user '" .. env.user .. "': " .. tostring(err))
			os.exit(1)
		end

		fs.chown(env.context_directory, uid, uid, { recurse = true })
	end
end

function context.build()
	-- build context
	local configuration_files = fs.read_dir(env.configuration_directory, {
		recurse = true,
		return_full_paths = false,
		as_dir_entries = false,
	}) --[=[@as string[]]=]

	local configuration_override_files = fs.read_dir(env.configuration_overrides_directory, {
		recurse = true,
		return_full_paths = false,
		as_dir_entries = false,
	}) --[=[@as string[]]=]

	for _, configuration_file in ipairs(configuration_files) do
		local configuration_file_path = path.combine(env.configuration_directory, configuration_file)
		if fs.file_type(configuration_file_path) == "directory" then
			fs.mkdirp(configuration_file_path)
			goto continue
		end

		local configuration_file_raw = fs.read_file(configuration_file_path)
		if configuration_file_path:match("%.hjson$") then
			local configuration = hjson.decode(configuration_file_raw)

			local configuration_overrides_file_path = path.combine(env.configuration_overrides_directory, configuration_file)
			local configuration_overrides_file_raw, _ = fs.read_file(configuration_overrides_file_path)
			if configuration_overrides_file_raw then
				local configuration_override = hjson.decode(configuration_overrides_file_raw)
				configuration = util.merge_tables(configuration, configuration_override,
					{ overwrite = true, array_merge_strategy = "prefer-t2" })
			end

			local context_file = path.combine(env.context_directory, configuration_file)
			fs.mkdirp(path.dir(context_file))
			if context_file:match("%.hjson$") then
				context_file = context_file:sub(1, -6) -- remove .hjson extension
				context_file = context_file .. "json" -- add .json extension
			end
			fs.write_file(context_file, hjson.encode_to_json(configuration))
		else
			local context_file = path.combine(env.context_directory, configuration_file)
			local configuration_overrides_file = path.combine(env.configuration_overrides_directory, configuration_file)
			fs.mkdirp(path.dir(context_file))
			if fs.exists(configuration_overrides_file) then
				fs.copy_file(configuration_overrides_file, context_file)
			else
				fs.copy_file(configuration_file_path, context_file)
			end
		end
		::continue::
	end

	for _, configuration_override_file in ipairs(configuration_override_files) do
		local override_file_path = path.combine(env.configuration_overrides_directory, configuration_override_file)
		local new_override_file_path = path.combine(env.context_directory, configuration_override_file)
		if fs.file_type(override_file_path) == "directory" then
			fs.mkdirp(override_file_path)
			goto continue
		end
		if not fs.exists(new_override_file_path) then -- only if it wasnt applied through merge
			fs.mkdirp(path.dir(new_override_file_path))
			fs.copy_file(path.combine(env.configuration_overrides_directory, configuration_override_file),
				new_override_file_path)
		end
		::continue::
	end

	-- load protocols
	local protocol_directory = path.combine(env.context_directory, "protocols")
	local protocol_directories = fs.read_dir(protocol_directory, {
		recurse = false,
		return_full_paths = true,
		as_dir_entries = false,
	}) --[=[@as string[]]=]

	local protocol_mapping = {}
	local protocols = {}
	for _, protocol_directory in ipairs(protocol_directories) do
		local protocol_file_path = path.combine(protocol_directory, constants.protocol_file_id)
		local protocol_file_raw = fs.read_file(protocol_file_path)
		local protocol = hjson.decode(protocol_file_raw)
		if type(protocol.id) ~= "string" then
			log_warn("valid protocol id not found in protocol file: " .. protocol_file_path .. ", skipping")
			goto continue
		end
		if protocol_mapping[protocol.id] then
			log_warn("duplicate protocol id found: " .. protocol.id .. ", skipping")
			goto continue
		end
		if type(protocol.short) ~= "string" then
			log_warn("valid protocol short name not found in protocol file: " .. protocol_file_path .. ", skipping")
			goto continue
		end
		if type(protocol.hash) ~= "string" then
			log_warn("valid protocol hash not found in protocol file: " .. protocol_file_path .. ", skipping")
			goto continue
		end

		protocol.path = protocol_directory

		protocol_mapping[string.lower(protocol.id)] = protocol
		protocol_mapping[string.lower(protocol.hash)] = protocol
		protocols[protocol.id] = protocol
		for _, alias in ipairs(protocol.aliases or {}) do
			local alias = string.lower(alias)
			if protocol_mapping[alias] then
				log_warn("duplicate protocol alias found: " .. alias .. ", skipping")
				goto continue
			end
			protocol_mapping[alias] = protocol
			::continue::
		end

		::continue::
	end

	context.protocol_mapping = protocol_mapping
	context.protocols = protocols

	-- create sandbox.json
	local sandbox_json = hjson.encode_to_json({
		genesis_pubkey = constants.activator_account.pk
	})
	fs.write_file(path.combine(env.context_directory, "sandbox.json"), sandbox_json)

	context.setup_file_ownership()
end

return context
