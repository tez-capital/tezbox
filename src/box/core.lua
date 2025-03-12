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

---@class BakerAccountProperties
---@field pkh string
---@field pk string
---@field sk string
---@field balance number
---@field deposits table<string, number>?

---@alias Accounts table<string, { pkh?: string, pk: string?, sk: string?, balance?: number }>

---@param accounts Accounts
---@param bakers table<string, BakerAccountProperties>
local function split_account_balances(accounts, bakers)
	local baker_accounts = table.values(bakers)

	local index = 1

	for _, account in pairs(accounts) do
		if not account.balance then
			goto continue
		end
		if not account.pkh then
			goto continue
		end
		local baker = baker_accounts[index]
		if type(baker.deposits) ~= "table" then
			baker.deposits = {}
		end
		baker.deposits[account.pkh] = account.balance

		index = index + 1
		if index > #baker_accounts then
			index = 1
		end
		::continue::
	end
end

---@class injectServicesOptions
---@field with_dal boolean?

---@param protocol ProtocolDefinition
---@param bakers table<string, table>
---@param options injectServicesOptions?
local function inject_ascend_services(protocol, bakers, options)
	if type(options) ~= "table" then options = {} end
	local extra_services = {}
	if options.with_dal then
		for _, service in ipairs(constants.dal.services) do
			table.insert(extra_services, service)
		end
	end

	local services_directory = os.getenv "ASCEND_SERVICES"
	if not services_directory then
		log_error("ASCEND_SERVICES environment variable not set")
		os.exit(1)
	end

	local vars = require "eli.env".environment()
	local context_vars = {
		PROTOCOL_SHORT = protocol.short,
		PROTOCOL_HASH = protocol.hash,
		SANDBOX_FILE = path.combine(protocol.path, constants.sandbox_parameters_file_id),
		HOME = env.home_directory,
		VOTE_FILE = path.combine(protocol.path, constants.vote_file_id),
		USER = env.user,
	}
	vars = util.merge_tables(vars, context_vars, { overwrite = true })

	local service_directory = path.combine(env.context_directory, "services")
	local service_files = fs.read_dir(service_directory, {
		recurse = false,
		return_full_paths = false,
		as_dir_entries = false,
	}) --[=[@as string[]]=]

	for _, service_file_name in ipairs(service_files) do
		local service_path = path.combine(service_directory, service_file_name)
		if not service_path:match("%.json$") and not service_path:match("%.hjson$") then
			goto continue
		end

		local service_template = fs.read_file(service_path)
		local service = string.interpolate(service_template, vars)
		local service_file_path = path.combine(services_directory, service_file_name)
		if service_file_path:match("%.json$") then -- services have to be hjson files
			service_file_path = service_file_path:sub(1, -5) -- remove .json ext
			service_file_path = service_file_path .. "hjson"
		end
		local ok = fs.safe_write_file(service_file_path, service)
		if not ok then
			log_error("failed to write service file " .. service_file_path)
			os.exit(1)
		end
		::continue::
	end

	local service_templates_directory = path.combine(service_directory, "template")
	local baker_service_template = fs.read_file(path.combine(service_templates_directory, "baker.json"))
	for baker_id, baker_options in pairs(bakers) do
		local service_file_path = path.combine(services_directory, baker_id .. ".hjson")
		if fs.exists(service_file_path) then
			log_debug("service file " .. service_file_path .. " already exists, skipping")
			goto continue
		end

		local args = { "run", "with", "local", "node", "${HOME}/.tezos-node", baker_id, "--votefile", "${VOTE_FILE}" }
        if table.is_array(baker_options.args) then
			for _, arg in ipairs(baker_options.args) do
				table.insert(args, arg)
			end
			util.merge_arrays(args, baker_options.args, { merge_strategy = "combine"})
		end
		if options.with_dal then
			table.insert(args, "--dal-node")
			table.insert(args, "http://127.0.0.1:10732")
		else
			table.insert(args, "--without-dal")
		end

		vars = util.merge_tables(vars, {
			BAKER_ARGS =  string.interpolate(hjson.encode_to_json(args), vars),
		}, { overwrite = true })
		baker_service_template = baker_service_template:gsub("\"${BAKER_ARGS}\"", "${BAKER_ARGS}")
		local service = string.interpolate(baker_service_template, vars)

		local ok = fs.safe_write_file(service_file_path, service)
		if not ok then
			log_error("failed to write service file " .. service_file_path)
			os.exit(1)
		end
		::continue::
	end

	local service_extra_templates_directory = path.combine(service_directory, "extra")
	for _, extra_service_file_name in ipairs(extra_services) do
		local service_template_path = path.combine(service_extra_templates_directory, extra_service_file_name .. ".json")
		local service_file_path = path.combine(services_directory, extra_service_file_name .. ".hjson")
		if fs.exists(service_file_path) then
			log_debug("service file " .. service_file_path .. " already exists, skipping")
			goto continue
		end

		local service_template = fs.read_file(service_template_path)
		local service = string.interpolate(service_template, vars)
		local ok = fs.safe_write_file(service_file_path, service)
		if not ok then
			log_error("failed to copy extra service file " .. service_template_path .. " to " .. service_file_path)
			os.exit(1)
		end
		::continue::
	end

	-- healthchecks
	local ascend_healthchecks_directory = os.getenv "ASCEND_HEALTHCHECKS"
	if not ascend_healthchecks_directory then
		log_error("ASCEND_SERVICES environment variable not set")
		os.exit(1)
	end
	local healthchecks_directory = path.combine(env.context_directory, "healthchecks")
	local healthcheck_files = fs.read_dir(healthchecks_directory, {
		recurse = true,
		return_full_paths = false,
		as_dir_entries = false,
	}) --[=[@as string[]]=]

	for _, healthcheck_file_name in ipairs(healthcheck_files) do
		local source_path = path.combine(healthchecks_directory, healthcheck_file_name)
		local target_path = path.combine(ascend_healthchecks_directory, healthcheck_file_name)
		local ok = fs.safe_copy(source_path, target_path)
		if not ok then
			log_error("failed to copy healthcheck file " .. source_path .. " to " .. target_path)
			os.exit(1)
		end
		local ok = fs.chmod(target_path, "rwxr--r--")
		if not ok then
			log_error("failed to chmod healthcheck file " .. target_path)
			os.exit(1)
		end
	end
end

---@class TezboxInitializeOptions
---@field inject_services boolean?
---@field with_dal boolean?
---@field init string?

---@param protocol string
---@param options TezboxInitializeOptions
function core.initialize(protocol, options)
	if type(options) ~= "table" then options = {} end
	protocol = string.lower(protocol)

	local initialized_protocol_file_path = path.combine(env.home_directory, "tezbox-initialized")

	local ok, initialized_protocol = fs.safe_read_file(initialized_protocol_file_path)

	if ok then
		if initialized_protocol == protocol then
			log_info("tezbox already initialized for protocol " .. initialized_protocol)
			return
		end
		log_info("found tezbox-initialized file, but protocol is different, reinitializing")
	end

	log_debug("resetting state")
	octez.reset() -- reset octez state
	context.build() -- rebuild context

	local proto = context.protocol_mapping[protocol] --[[@as ProtocolDefinition?]]
	if not proto then
		log_error("protocol " .. protocol .. " not found in context")
		os.exit(1)
	end

	log_info("generating node identity")
	local result = octez.node.generate_identity()
	if result.exit_code ~= 0 then
		log_error("failed to generate node identity")
		os.exit(1)
	end

	log_info("initializing node configuration")
	local init_config_args_raw = fs.read_file(path.combine(env.context_directory, 'init-config-args.json'))
	local init_config_args = hjson.parse(init_config_args_raw)
	local result = octez.node.init_config(init_config_args)
	if result.exit_code ~= 0 then
		log_error("failed to initialize node configuration")
		os.exit(1)
	end

	log_info("importing accounts")
	local accounts_raw = fs.read_file(path.combine(env.context_directory, 'accounts.json'))
	local accounts = hjson.decode(accounts_raw)

	local bakers_raw = fs.read_file(path.combine(env.context_directory, 'bakers.json'))
	local baker_accounts = hjson.decode(bakers_raw)

	accounts.activator = constants.activator_account

	for account_id, account in pairs(util.merge_tables(accounts, baker_accounts)) do
		if not account.sk then
			log_debug("skipped importing account " .. account_id .. " (no secret key)")
			goto continue
		end
		log_debug("importing account " .. account_id)
		local result = octez.client.import_account(account_id, account.sk)
		if result.exit_code ~= 0 then
			log_error("failed to import account " .. account_id)
			os.exit(1)
		end
		::continue::
	end

	local sandbox_parameters_file = path.combine(proto.path, constants.sandbox_parameters_file_id)

	-- split account balances
	split_account_balances(accounts, baker_accounts)

	-- inject accounts to sandbox parameters
	local parameters_raw = fs.read_file(sandbox_parameters_file)
	local parameters = hjson.decode(parameters_raw)

	parameters.bootstrap_accounts = {}
	for account_id, account in pairs(baker_accounts) do
		if (type(account.balance) ~= "number" and type(account.balance) ~= "string") or type(account.pk) ~= "string" then
			error("invalid baker balance or pk for account " .. tostring(account_id))
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

	fs.write_file(sandbox_parameters_file, hjson.encode_to_json(parameters))

	log_info("activating protocol " .. proto.hash)
	octez.exec_with_node_running(function()
		local result = octez.client.run({ "-block", "genesis", "activate", "protocol", proto.hash, "with", "fitness", "1",
			"and",
			"key", "activator", "and", "parameters", sandbox_parameters_file })
		if result.exit_code ~= 0 then
			error("failed to activate protocol " .. proto.hash)
		end

		-- run baker and inject transfers
		local proc = octez.baker.run(proto.short, {
			"run", "remotely", "--without-dal", "--votefile", path.combine(proto.path, constants.vote_file_id)
		})

		os.sleep(2)
		for baker_id, baker in pairs(baker_accounts) do
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
			local result = octez.client.transfer(baker_id, transfers)
			if result.exit_code ~= 0 then
				error("failed to send deposit from baker " .. baker_id)
			end
			::continue::
		end
		proc:kill()
		proc:wait(30)
		if proc:get_exit_code() < 0 then
			proc:kill(require "os.signal".SIGKILL)
		end
		if result.exit_code ~= 0 then
			error("failed to top up accounts")
		end
	end)

	-- patch services
	if options.inject_services then
		inject_ascend_services(proto, baker_accounts, { with_dal = options.with_dal })
	end

	-- copy .tezos-client from homeDirectory to HOME
	local octez_client_path = path.combine(env.home_directory, ".tezos-client")
	local octez_client_target_path = path.combine(os.getenv("HOME") or ".", ".tezos-client")
	local ok, err = fs.safe_copy(octez_client_path, octez_client_target_path, { overwrite = true, ignore = function (path)
		return path:match("logs")
	end })
	if not ok then
		log_error("failed to copy .tezos-client to " .. octez_client_target_path .. " - error: " .. tostring(err))
		os.exit(1)
	end

	if options.with_dal and not octez.dal.install_trusted_setup() then
		log_error("failed to install dal trusted setup")
		os.exit(1)
	end

	if type(options.init) == "string" and not os.execute(options.init) then
		log_error("failed to run init script")
		os.exit(1)
	end

	local init_script_path = path.combine(env.context_directory, "init")
	if fs.exists(init_script_path) then
		os.execute(init_script_path)
	end

	context.setup_file_ownership() -- fixup after external init scripts
	-- finalize
	fs.write_file(initialized_protocol_file_path, protocol)
end

function core.list_protocols()
	context.build() -- rebuild context

	local protocols = context.protocols
	for protocol, protocol_detail in pairs(protocols) do
		local aliases = util.merge_arrays({ protocol_detail.id, protocol_detail.short, protocol_detail.hash },
			protocol_detail.aliases or {})
		print(protocol .. " (available as: " .. string.join(", ", aliases) .. ")")
	end
end

function core.run()
	error("not implemented")
	-- // TODO: run for setup without container
end

return core
