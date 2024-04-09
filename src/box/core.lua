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
---@field vote-file table?
---@field sandbox-overrides table?

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
		SANDBOX_FILE = path.combine(env.contextDirectory, env.sandboxParametersFile),
		HOME = env.homeDirectory,
		VOTE_FILE = env.voteFile,
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
end

---@class TezboxInitializeOptions
---@field injectServices boolean?

---@param protocol string
---@param options TezboxInitializeOptions
function core.initialize(protocol, options)
	if type(options) ~= "table" then options = {} end

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

	accounts.activator = constants.activatorAccount

	for accountId, account in pairs(accounts) do
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

	log_info("activating protocol " .. proto.hash)
	octez.exec_with_node_running(function()
		local result = octez.client.run({ "-block", "genesis", "activate", "protocol", proto.hash, "with", "fitness", "1",
			"and",
			"key", "activator", "and", "parameters", path.combine(env.contextDirectory, env.sandboxParametersFile) })
		if result.exitcode ~= 0 then
			error("failed to activate protocol " .. proto.hash)
		end
	end)

	if type(proto["andbox-overrides"]) == "table" then
		log_info("injecting protocol sandbox overrides")

		if type(accounts) == "table" and #table.keys(accounts) > 0 then
			local parametersFile = path.combine(env.contextDirectory, env.sandboxParametersFile)
			local parametersHjson = fs.read_file(parametersFile)
			local parameters = hjson.decode(parametersHjson)

			parameters = util.merge_tables(parameters, proto["sandbox-overrides"],
				{ arrayMergeStrategy = "prefer-t2", overwrite = true })

			fs.write_file(parametersFile, hjson.encode_to_json(parameters))
		end
	end

	-- create vote file
	if not fs.exists(env.voteFile) then
		local voteFileJson = hjson.encode_to_json(proto["vote-file"])
		fs.write_file(env.voteFile, voteFileJson)
	end

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
