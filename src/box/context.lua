local env = require "box.env"
local hjson = require "hjson"
local constants = require "box.constants"

local context = {
	protocolMapping = {},
	protocols = {}
}

function context.setup_file_ownership()
	if env.user ~= "" and env.user ~= "root" then
		local ok, uid = fs.safe_getuid(env.user)
		if not ok then
			log_error("user " .. env.user .. " does not exist")
			os.exit(1)
		end

		fs.chown(env.contextDirectory, uid, uid, { recurse = true })
	end
end

function context.build()
	-- build context
	local configurationFiles = fs.read_dir(env.configurationDirectory, {
		recurse = true,
		returnFullPaths = false,
		asDirEntries = false,
	}) --[=[@as string[]]=]

	local configurationOverrideFiles = fs.read_dir(env.configurationOverridesDirectory, {
		recurse = true,
		returnFullPaths = false,
		asDirEntries = false,
	}) --[=[@as string[]]=]

	for _, configurationFile in ipairs(configurationFiles) do
		local configurationFilePath = path.combine(env.configurationDirectory, configurationFile)
		if fs.file_type(configurationFilePath) == "directory" then
			fs.mkdirp(configurationFilePath)
			goto continue
		end

		local configurationFileContent = fs.read_file(configurationFilePath)
		if configurationFilePath:match("%.hjson$") then
			local configuration = hjson.decode(configurationFileContent)

			local configurationOverridesFile = path.combine(env.configurationOverridesDirectory, configurationFile)
			local ok, configurationOverridesFileContent = fs.safe_read_file(configurationOverridesFile)
			if ok then
				local configurationOverrides = hjson.decode(configurationOverridesFileContent)
				configuration = util.merge_tables(configuration, configurationOverrides,
					{ overwrite = true, arrayMergeStrategy = "prefer-t2" })
			end

			local contextFile = path.combine(env.contextDirectory, configurationFile)
			fs.mkdirp(path.dir(contextFile))
			if contextFile:match("%.hjson$") then
				contextFile = contextFile:sub(1, -6) -- remove .hjson extension
				contextFile = contextFile .. "json" -- add .json extension
			end
			fs.write_file(contextFile, hjson.encode_to_json(configuration))
		else
			local contextFile = path.combine(env.contextDirectory, configurationFile)
			local configurationOverridesFile = path.combine(env.configurationOverridesDirectory, configurationFile)
			fs.mkdirp(path.dir(contextFile))
			if fs.exists(configurationOverridesFile) then
				fs.copy_file(configurationOverridesFile, contextFile)
			else
				fs.copy_file(configurationFilePath, contextFile)
			end
		end
		::continue::
	end

	for _, configurationOverrideFile in ipairs(configurationOverrideFiles) do
		local overrideFilePath = path.combine(env.configurationOverridesDirectory, configurationOverrideFile)
		local newOverrideFilePath = path.combine(env.contextDirectory, configurationOverrideFile)
		if fs.file_type(overrideFilePath) == "directory" then
			fs.mkdirp(overrideFilePath)
			goto continue
		end
		if not fs.exists(newOverrideFilePath) then -- only if it wasnt applied through merge
			fs.mkdirp(path.dir(newOverrideFilePath))
			fs.copy_file(path.combine(env.configurationOverridesDirectory, configurationOverrideFile),
				newOverrideFilePath)
		end
		::continue::
	end

	-- load protocols
	local protocolDirectory = path.combine(env.contextDirectory, "protocols")
	local protocolDirectories = fs.read_dir(protocolDirectory, {
		recurse = false,
		returnFullPaths = true,
		asDirEntries = false,
	}) --[=[@as string[]]=]

	local protocolMapping = {}
	local protocols = {}
	for _, protocolDirectory in ipairs(protocolDirectories) do
		local protocolFile = path.combine(protocolDirectory, constants.protocolFileId)
		local protocolFileContent = fs.read_file(protocolFile)
		local protocol = hjson.decode(protocolFileContent)
		if type(protocol.id) ~= "string" then
			log_warn("valid protocol id not found in protocol file: " .. protocolFile .. ", skipping")
			goto continue
		end
		if protocolMapping[protocol.id] then
			log_warn("duplicate protocol id found: " .. protocol.id .. ", skipping")
			goto continue
		end
		if type(protocol.short) ~= "string" then
			log_warn("valid protocol short name not found in protocol file: " .. protocolFile .. ", skipping")
			goto continue
		end
		if type(protocol.hash) ~= "string" then
			log_warn("valid protocol hash not found in protocol file: " .. protocolFile .. ", skipping")
			goto continue
		end

		protocol.path = protocolDirectory

		protocolMapping[string.lower(protocol.id)] = protocol
		protocolMapping[string.lower(protocol.hash)] = protocol
		protocols[protocol.id] = protocol
		for _, alias in ipairs(protocol.aliases or {}) do
			local alias = string.lower(alias)
			if protocolMapping[alias] then
				log_warn("duplicate protocol alias found: " .. alias .. ", skipping")
				goto continue
			end
			protocolMapping[alias] = protocol
			::continue::
		end

		::continue::
	end

	context.protocolMapping = protocolMapping
	context.protocols = protocols

	-- create sandbox.json
	local sandboxJson = hjson.encode_to_json({
		genesis_pubkey = constants.activatorAccount.pk
	})
	fs.write_file(path.combine(env.contextDirectory, "sandbox.json"), sandboxJson)

	context.setup_file_ownership()
end

return context
