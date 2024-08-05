local hjson = require 'hjson'
local octez = require 'box.octez'
local env = require 'box.env'
local context = require 'box.context'
local constants = require 'box.constants'
local bigint = require"bigint"

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
			"run", "remotely", "--votefile", path.combine(proto.path, constants.voteFileId), "--liquidity-baking-toggle-vote", "on", "--adaptive-issuance-vote", "on"
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
		inject_ascend_services(proto)
	end

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
