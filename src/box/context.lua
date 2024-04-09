local env = require "box.env"
local hjson = require "hjson"
local constants = require "box.constants"

local context = {
	protocols = {}
}

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
		::continue::
	end

	for _, configurationOverrideFile in ipairs(configurationOverrideFiles) do
		local ovverrideFilePath = path.combine(env.configurationOverridesDirectory, configurationOverrideFile)
		local newOverrideFilePath = path.combine(env.contextDirectory, configurationOverrideFile)
		if fs.file_type(ovverrideFilePath) == "directory" then
			fs.mkdirp(ovverrideFilePath)
			goto continue
		end
		if not fs.exists(newOverrideFilePath) then -- only if it wasnt applied through merge
			fs.copy_file(path.combine(env.configurationOverridesDirectory, configurationOverrideFile),
				newOverrideFilePath)
		end
		::continue::
	end

	-- load protocols
	local protocolDirectory = path.combine(env.contextDirectory, "protocols")
	local protocolFiles = fs.read_dir(protocolDirectory, {
		recurse = false,
		returnFullPaths = true,
		asDirEntries = false,
	}) --[=[@as string[]]=]

	local protocols = {}
	for _, protocolFile in ipairs(protocolFiles) do
		local protocolFileContent = fs.read_file(protocolFile)
		local protocol = hjson.decode(protocolFileContent)
		if type(protocol.id) ~= "string" then
			log_warn("valid protocol id not found in protocol file: " .. protocolFile .. ", skipping")
			goto continue
		end
		if protocols[protocol.id] then
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

		if type(protocol["vote-file"]) ~= "table" then
			log_warn("valid protocol vote file not found in protocol file: " .. protocolFile .. ", skipping")
			goto continue
		end

		protocols[protocol.id] = protocol
		protocols[protocol.hash] = protocol
		for _, alias in ipairs(protocol.aliases or {}) do
			if protocols[alias] then
				log_warn("duplicate protocol alias found: " .. alias .. ", skipping")
				goto continue
			end
			protocols[alias] = protocol
			::continue::
		end

		::continue::
	end

	context.protocols = protocols

	-- inject accounts to sandbox parameters
	local ok, accountsHjson = fs.safe_read_file(path.combine(env.contextDirectory, "accounts.json"))
	if ok then
		local accounts = hjson.decode(accountsHjson)
		if type(accounts) == "table" and #table.keys(accounts) > 0 then
			local parametersFile = path.combine(env.contextDirectory, env.sandboxParametersFile)
			local parametersHjson = fs.read_file(parametersFile)
			local parameters = hjson.decode(parametersHjson)

			parameters.bootstrap_accounts = {}
			for _, account in pairs(accounts) do
				if type(account.balance) ~= "number" or type(account.pk) ~= "string" then
					goto continue
				end
				table.insert(parameters.bootstrap_accounts, {
					account.pk,
					tostring(account.balance)
				})
				::continue::
			end

			fs.write_file(parametersFile, hjson.encode_to_json(parameters))
		end
	end

	-- create sandbox.json
	local sandboxJson = hjson.encode_to_json({
		genesis_pubkey = constants.activatorAccount.pk
	})
	fs.write_file(path.combine(env.contextDirectory, "sandbox.json"), sandboxJson)
end

return context
