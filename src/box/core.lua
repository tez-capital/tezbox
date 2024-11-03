local hjson = require 'hjson'
local octez = require 'box.octez'
local env = require 'box.env'
local context = require 'box.context'
local constants = require 'box.constants'
local bigint = require "bigint"

local core = {}

---@class ProtocolDefinition
---@field id string
---@field short string
---@field hash string
---@field aliases string[]?
---@field path string

local function split_account_balances(accounts, bakers)
	local bakerAccounts = table.values(bakers)

	local index = 1

	for _, account in pairs(accounts) do
		if not account.balance then
			goto continue
		end
		if not account.pkh then
			goto continue
		end
		local baker = bakerAccounts[index]
		if type(baker.deposits) ~= "table" then
			baker.deposits = {}
		end
		baker.deposits[account.pkh] = account.balance

		index = index + 1
		if index > #bakerAccounts then
			index = 1
		end
		::continue::
	end
end

---@class injectServicesOptions
---@field withDal boolean?

---@param protocol ProtocolDefinition
---@param bakers table<string, table>
---@param options injectServicesOptions?
local function inject_ascend_services(protocol, bakers, options)
	if type(options) ~= "table" then options = {} end
	local extraServices = {}
	if options.withDal then
		for _, service in ipairs(constants.dal.services) do
			table.insert(extraServices, service)
		end
	end

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
		BAKERS_HOME = env.bakersHomeDirectory,
		VOTE_FILE = path.combine(protocol.path, constants.voteFileId),
		USER = env.user,
	}
	vars = util.merge_tables(vars, contextVars, { overwrite = true })

	local serviceDirectory = path.combine(env.contextDirectory, "services")
	local serviceFiles = fs.read_dir(serviceDirectory, {
		recurse = false,
		returnFullPaths = false,
		asDirEntries = false,
	}) --[=[@as string[]]=]

	for _, serviceFileName in ipairs(serviceFiles) do
		local servicePath = path.combine(serviceDirectory, serviceFileName)
		if not servicePath:match("%.json$") and not servicePath:match("%.hjson$") then
			goto continue
		end

		local serviceTemplate = fs.read_file(servicePath)
		local service = string.interpolate(serviceTemplate, vars)
		local serviceFilePath = path.combine(servicesDirectory, serviceFileName)
		if serviceFilePath:match("%.json$") then -- services have to be hjson files
			serviceFilePath = serviceFilePath:sub(1, -5) -- remove .json ext
			serviceFilePath = serviceFilePath .. "hjson"
		end
		local ok = fs.safe_write_file(serviceFilePath, service)
		if not ok then
			log_error("failed to write service file " .. serviceFilePath)
			os.exit(1)
		end
		::continue::
	end

	local service_templates_directory = path.combine(serviceDirectory, "template")
	local baker_service_template = fs.read_file(path.combine(service_templates_directory, "baker.json"))
	for bakerId, bakerOptions in pairs(bakers) do
		local serviceFilePath = path.combine(servicesDirectory, bakerId .. ".hjson")
		if fs.exists(serviceFilePath) then
			log_debug("service file " .. serviceFilePath .. " already exists, skipping")
			goto continue
		end

		local args = { "run", "with", "local", "node", "${HOME}/.tezos-node", bakerId, "--votefile", "${VOTE_FILE}" }
        if table.is_array(bakerOptions.args) then
			for _, arg in ipairs(bakerOptions.args) do
				table.insert(args, arg)
			end
			util.merge_arrays(args, bakerOptions.args, { arrayMergeStrategy = "combine"})
		end
		if options.withDal then
			table.insert(args, "--dal-node")
			table.insert(args, "http://127.0.0.1:10732")
		end

		vars = util.merge_tables(vars, {
			BAKER_ARGS =  string.interpolate(hjson.encode_to_json(args), vars),
		}, { overwrite = true })
		baker_service_template = baker_service_template:gsub("\"${BAKER_ARGS}\"", "${BAKER_ARGS}")
		local service = string.interpolate(baker_service_template, vars)

		local ok = fs.safe_write_file(serviceFilePath, service)
		if not ok then
			log_error("failed to write service file " .. serviceFilePath)
			os.exit(1)
		end
		::continue::
	end

	local serviceExtraTemplatesDirectory = path.combine(serviceDirectory, "extra")
	for _, extraServiceFileName in ipairs(extraServices) do
		local serviceTemplatePath = path.combine(serviceExtraTemplatesDirectory, extraServiceFileName .. ".json")
		local serviceFilePath = path.combine(servicesDirectory, extraServiceFileName .. ".hjson")
		if fs.exists(serviceFilePath) then
			log_debug("service file " .. serviceFilePath .. " already exists, skipping")
			goto continue
		end

		local serviceTemplate = fs.read_file(serviceTemplatePath)
		local service = string.interpolate(serviceTemplate, vars)
		local ok = fs.safe_write_file(serviceFilePath, service)
		if not ok then
			log_error("failed to copy extra service file " .. serviceTemplatePath .. " to " .. serviceFilePath)
			os.exit(1)
		end
		::continue::
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
---@field withDal boolean?
---@field init string?

---@param protocol string
---@param options TezboxInitializeOptions
function core.initialize(protocol, options)
	if type(options) ~= "table" then options = {} end
	protocol = string.lower(protocol)

	local initializedProtocolFilePath = path.combine(env.homeDirectory, "tezbox-initialized")

	local ok, initializedProtocol = fs.safe_read_file(initializedProtocolFilePath)

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

	local proto = context.protocolMapping[protocol] --[[@as ProtocolDefinition?]]
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

	-- split account balances
	split_account_balances(accounts, bakerAccounts)

	-- inject accounts to sandbox parameters
	local parametersHjson = fs.read_file(sandboxParametersFile)
	local parameters = hjson.decode(parametersHjson)

	parameters.bootstrap_accounts = {}
	for accountId, account in pairs(bakerAccounts) do
		if (type(account.balance) ~= "number" and type(account.balance) ~= "string") or type(account.pk) ~= "string" then
			error("invalid baker balance or pk for account " .. tostring(accountId))
		end
		local balance = account.balance
		local extra = table.reduce(table.values(account.deposits or {}), function(acc, v)
			return acc + bigint.new(v)
		end, bigint.new(0))
		balance = bigint.new(balance) + extra

		table.insert(parameters.bootstrap_accounts, {
			account.pk,
			tostring(balance * constants.MUTEZ_MULTIPLIER)
		})
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
			"run", "remotely", "--votefile", path.combine(proto.path, constants.voteFileId)
		})

		os.sleep(2)
		for bakerId, baker in pairs(bakerAccounts) do
			if not baker.deposits then
				goto continue
			end
			local transfers = {}
			for pkh, balance in pairs(baker.deposits) do
				table.insert(transfers, {
					destination = pkh,
					amount = tostring(balance)
				})
			end
			local result = octez.client.transfer(bakerId, transfers)
			if result.exitcode ~= 0 then
				error("failed to send deposit from baker " .. bakerId)
			end
			::continue::
		end
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
		inject_ascend_services(proto, bakerAccounts, { withDal = options.withDal })
	end

	-- copy .tezos-client from homeDirectory to bakersHomeDirectory
	local octezClientPath = path.combine(env.homeDirectory, ".tezos-client")
	local octezClientTargetPath = path.combine(env.bakersHomeDirectory, ".tezos-client")
	local ok, err = fs.safe_copy(octezClientPath, octezClientTargetPath, { overwrite = true, ignore = function (path)
		return path:match("logs")
	end })
	if not ok then
		log_error("failed to copy .tezos-client to " .. octezClientTargetPath .. " - error: " .. tostring(err))
		os.exit(1)
	end

	if options.withDal and not octez.dal.install_trusted_setup() then
		log_error("failed to install dal trusted setup")
		os.exit(1)
	end

	if type(options.init) == "string" and not os.execute(options.init) then
		log_error("failed to run init script")
		os.exit(1)
	end

	local init_script_path = path.combine(env.contextDirectory, "init")
	if fs.exists(init_script_path) then
		os.execute(init_script_path)
	end

	context.setup_file_ownership() -- fixup after external init scripts
	-- finalize
	fs.write_file(initializedProtocolFilePath, protocol)
end

function core.list_protocols()
	context.build() -- rebuild context

	local protocols = context.protocols
	for protocol, protocolDetail in pairs(protocols) do
		local aliases = util.merge_arrays({ protocolDetail.id, protocolDetail.short, protocolDetail.hash },
			protocolDetail.aliases or {})
		print(protocol .. " (available as: " .. string.join(", ", aliases) .. ")")
	end
end

function core.run()
	error("not implemented")
	-- // TODO: run for setup without container
end

return core
