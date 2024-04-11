local hjson = require 'hjson'
local octez = require 'box.octez'
local env = require 'box.env'
local context = require 'box.context'
local constants = require 'box.constants'

local core = {}

---@class ProtocolDefinition
---@field id string
---@field short string
---@field hash string
---@field aliases string[]?
---@field path string

---@param protocol ProtocolDefinition
local function inject_ascend_services(protocol)
	local servicesDirectory = os.getenv "ASCEND_SERVICES"
	if not servicesDirectory then
		log_error("ASCEND_SERVICES environment variable not set")
		os.exit(1)
	end

	local vars = require "eli.env".environment()
	local contextVars = {
		PROTOCOL_SHORT = protocol.short,
		PROTOCOL_HASH = protocol.hash,
		SANDBOX_FILE = path.combine(protocol.path, constants.sandboxParametersFileId),
		HOME = env.homeDirectory,
		VOTE_FILE = path.combine(protocol.path, constants.voteFileId),
		USER = env.user,
	}
	vars = util.merge_tables(vars, contextVars, { overwrite = true })

	local serviceTemplatesDirectory = path.combine(env.contextDirectory, "services")
	local serviceTemplateFiles = fs.read_dir(serviceTemplatesDirectory, {
		recurse = true,
		returnFullPaths = false,
		asDirEntries = false,
	}) --[=[@as string[]]=]

	for _, serviceTemplateFileName in ipairs(serviceTemplateFiles) do
		local serviceTemplate = fs.read_file(path.combine(serviceTemplatesDirectory, serviceTemplateFileName))
		local service = string.interpolate(serviceTemplate, vars)
		local serviceFilePath = path.combine(servicesDirectory, serviceTemplateFileName)
		if serviceFilePath:match("%.json$") then -- services have to be hjson files
			serviceFilePath = serviceFilePath:sub(1, -5) -- remove .json ext
			serviceFilePath = serviceFilePath .. "hjson"
		end
		local ok = fs.safe_write_file(serviceFilePath, service)
		if not ok then
			log_error("failed to write service file " .. serviceFilePath)
			os.exit(1)
		end
	end

	-- healthchecks
	local ascendHealthchecksDirectory = os.getenv "ASCEND_HEALTHCHECKS"
	if not ascendHealthchecksDirectory then
		log_error("ASCEND_SERVICES environment variable not set")
		os.exit(1)
	end
	local healthchecksDirectory = path.combine(env.contextDirectory, "healthchecks")
	local healthcheckFiles = fs.read_dir(healthchecksDirectory, {
		recurse = true,
		returnFullPaths = false,
		asDirEntries = false,
	}) --[=[@as string[]]=]

	for _, healthcheckFileName in ipairs(healthcheckFiles) do
		local sourcePath = path.combine(healthchecksDirectory, healthcheckFileName)
		local targetPath = path.combine(ascendHealthchecksDirectory, healthcheckFileName)
		local ok = fs.safe_copy(sourcePath, targetPath)
		if not ok then
			log_error("failed to copy healthcheck file " .. sourcePath .. " to " .. targetPath)
			os.exit(1)
		end
		local ok = fs.chmod(targetPath, "rwxr--r--")
		if not ok then
			log_error("failed to chmod healthcheck file " .. targetPath)
			os.exit(1)
		end
	end
end

---@class TezboxInitializeOptions
---@field injectServices boolean?

---@param protocol string
---@param options TezboxInitializeOptions
function core.initialize(protocol, options)
	if type(options) ~= "table" then options = {} end
	protocol = string.lower(protocol)

	local ok, initializedProtocol = fs.safe_read_file(path.combine(env.tezboxDirectory, "tezbox-initialized"))

	if ok then
		if initializedProtocol == protocol then
			log_info("tezbox already initialized for protocol " .. initializedProtocol)
			return
		end
		log_info("found tezbox-initialized file, but protocol is different, reinitializing")
	end

	log_debug("resetting state")
	octez.reset() -- reset octez state
	context.build() -- rebuild context

	local proto = context.protocols[protocol] --[[@as ProtocolDefinition?]]
	if not proto then
		log_error("protocol " .. protocol .. " not found in context")
		os.exit(1)
	end

	log_info("generating node identity")
	local result = octez.node.generate_identity()
	if result.exitcode ~= 0 then
		log_error("failed to generate node identity")
		os.exit(1)
	end

	log_info("initializing node configuration")
	local initConfigArgsHjson = fs.read_file(path.combine(env.contextDirectory, 'init-config-args.json'))
	local initConfigArgs = hjson.parse(initConfigArgsHjson)
	local result = octez.node.init_config(initConfigArgs)
	if result.exitcode ~= 0 then
		log_error("failed to initialize node configuration")
		os.exit(1)
	end

	log_info("importing accounts")
	local accountsHjson = fs.read_file(path.combine(env.contextDirectory, 'accounts.json'))
	local accounts = hjson.decode(accountsHjson)

	local bakersHjson = fs.read_file(path.combine(env.contextDirectory, 'bakers.json'))
	local bakerAccounts = hjson.decode(bakersHjson)

	accounts.activator = constants.activatorAccount

	for accountId, account in pairs(util.merge_tables(accounts, bakerAccounts)) do
		if not account.sk then
			log_debug("skipped importing account " .. accountId .. " (no secret key)")
			goto continue
		end
		log_debug("importing account " .. accountId)
		local result = octez.client.import_account(accountId, account.sk)
		if result.exitcode ~= 0 then
			log_error("failed to import account " .. accountId)
			os.exit(1)
		end
		::continue::
	end

	local sandboxParametersFile = path.combine(proto.path, constants.sandboxParametersFileId)

	-- inject accounts to sandbox parameters
	local parametersHjson = fs.read_file(sandboxParametersFile)
	local parameters = hjson.decode(parametersHjson)

	parameters.bootstrap_accounts = {}
	for _, account in pairs(bakerAccounts) do
		if (type(account.balance) ~= "number" and type(account.balance) ~= "string") or type(account.pk) ~= "string" then
			goto continue
		end
		table.insert(parameters.bootstrap_accounts, {
			account.pk,
			tostring(account.balance)
		})
		
		::continue::
	end

	fs.write_file(sandboxParametersFile, hjson.encode_to_json(parameters))

	log_info("activating protocol " .. proto.hash)
	octez.exec_with_node_running(function()
		local result = octez.client.run({ "-block", "genesis", "activate", "protocol", proto.hash, "with", "fitness", "1",
			"and",
			"key", "activator", "and", "parameters", sandboxParametersFile })
		if result.exitcode ~= 0 then
			error("failed to activate protocol " .. proto.hash)
		end

		-- run baker and inject transfers
		local proc = octez.baker.run(proto.short, {
			"run" , "remotely", "--votefile", path.combine(proto.path, constants.voteFileId) 
		})

		local transfers = {}
		for _, account in pairs(accounts) do
			if not account.balance then
				goto continue
			end
			table.insert(transfers, {
				destination = account.pkh,
				amount = tostring(account.balance)
			})
			::continue::
		end
		os.sleep(2)
		local result = octez.client.transfer("faucet", transfers)
		proc:kill()
		proc:wait(30)
		if proc:get_exitcode() < 0 then
			proc:kill(require "os.signal".SIGKILL)
		end
		if result.exitcode ~= 0 then
			error("failed to top up accounts")
		end
	end)

	-- patch services
	if options.injectServices then
		inject_ascend_services(proto)
	end

	-- finalize
	fs.write_file("tezbox-initialized", protocol)
end

function core.run()
	error("not implemented")
	-- // TODO: run for setup without container
end

return core
