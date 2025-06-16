local signal = require "os.signal"
local env = require "box.env"
local constants = require "box.constants"

local octez = {
	client = {},
	node = {},
	baker = {},
	dal = {}
}

---@param overrides table<string, string>
local function build_env(overrides)
	return util.merge_tables(require"eli.env".environment(), overrides, { overwrite = true })
end

---@class RunClientOptions
---@field user string?

---runs octez client
---@param args string[]
---@param options RunClientOptions?
---@return SpawnResult
function octez.client.run(args, options)
	if type(options) ~= "table" then options = {} end
	if type(args) ~= "table" then args = {} end

	log_debug("Running octez client with args: " .. string.join(" ", args))

	return proc.spawn(env.octez_client_binary, args, {
		username = options.user or env.user,
		wait = true,
		stdio = "inherit",
		env = build_env( { HOME = env.home_directory } ),
	}) --[[@as SpawnResult]]
end

---@param id string
---@param secret string
function octez.client.import_account(id, secret)
	return octez.client.run({ "--protocol", "ProtoALphaALphaALphaALphaALphaALphaALphaALphaDdp3zK", "import", "secret", "key", id, secret })
end

---@param from string
---@param transfers { destination: string, balance: string }[]
function octez.client.transfer(from, transfers)
	local hjson = require "hjson"

	local result = octez.client.run({ "multiple", "transfers", "from", from, "using", hjson.encode_to_json(transfers), "--burn-cap", "10" })
	return result
end

---@class RunNodeOptions
---@field user string?

---runs octez node
---@param args string[]
---@param options RunNodeOptions
---@return SpawnResult
function octez.node.run(args, options)
	if type(options) ~= "table" then options = {} end
	if type(args) ~= "table" then args = {} end

	log_debug("Running octez node with args: " .. string.join(" ", args))

	return proc.spawn(env.octez_node_binary, args, {
		username = options.user or env.user,
		wait = true,
		stdio = "inherit",
		env = build_env( { HOME = env.home_directory } ),
	}) --[[@as SpawnResult]]
end

---@param config_options_args table<string, string>
---@param options RunNodeOptions?
function octez.node.init_config(config_options_args, options)
	if type(config_options_args) ~= "table" then config_options_args = {} end
	if type(options) ~= "table" then options = {} end

	local args = {
		"config",
		"init",
	}
	if table.is_array(config_options_args) then
		for _, value in ipairs(config_options_args) do
			table.insert(args, value)
		end
	elseif type(config_options_args) == "table" then
		for key, value in pairs(config_options_args) do
			table.insert(args, "--" .. key .. "=" .. value)
		end
	end
	return octez.node.run(args, options)
end

---@class ExecWithNodeRunningOptions: RunNodeOptions
---@field timeout integer?

---@param exec fun()
---@param options ExecWithNodeRunningOptions?
function octez.exec_with_node_running(exec, options)
	if type(options) ~= "table" then options = {} end
	if type(exec) ~= "function" then
		return
	end

	local NODE_DIR = path.combine(env.home_directory, ".tezos-node")
	local time = os.time() + (options.timeout or 60)
	local args = {
		"run",
		"--data-dir=" .. NODE_DIR,
		"--synchronisation-threshold=0",
		"--connections=0",
		"--allow-all-rpc=0.0.0.0",
		"--no-bootstrap-peers",
		"--private-mode",
		"--sandbox=" .. path.combine(env.context_directory, "sandbox.json"),
	}

	local override_env = {}
	if env.home_directory == os.getenv("HOME") then
		override_env = { HOME = "/tmp" } -- octez node refuses to use HOME in sandbox mode so we need to override it to proceed
	end

	local node_process = proc.spawn(env.octez_node_binary, args, {
		username = options.user or env.user,
		stdio = "inherit",
		env = build_env(override_env),
	}) --[[@as EliProcess]]

	local executed = false
	while node_process:wait(100, 1000) == -1 do
		local response = net.download_string("http://127.0.0.1:8732/chains/main/blocks/head/metadata")
		if response then
			exec()
			executed = true
			break
		end
		if os.time() > time then
			break
		end
	end
	node_process:kill(signal.SIGTERM)
	local exit_code = node_process:wait(30)
	if exit_code < 0 then
		node_process:kill(signal.SIGKILL)
	end
	return executed
end

---@param options RunNodeOptions?
function octez.node.generate_identity(options)
	if type(options) ~= "table" then options = {} end
	return octez.node.run({ "identity", "generate", "0.0" }, options)
end

function octez.baker.run(short_protocol, args, options)
	if type(options) ~= "table" then options = {} end
	if type(args) ~= "table" then args = {} end

	return proc.spawn(env.octez_baker_binary .. "-" .. short_protocol, args, {
		username = options.user or env.user,
		wait = false,
		stdio = "inherit",
		env = build_env( { HOME = env.home_directory } ),
	}) --[[@as EliProcess]]
end

function octez.dal.install_trusted_setup()
	log_info("installing dal trusted setup")
	local ok, err = net.download_file(constants.dal.scripts.setup, "/tmp/install_dal_trusted_setup.sh")
	if not ok then
		log_error("failed to download dal setup script: " .. tostring(err))
		return false
	end

	for _, dependency in ipairs(constants.dal.scripts.dependencies) do
		local ok, err = net.download_file(dependency, "/tmp/" .. path.file(dependency))
		if not ok then
			log_error("failed to download dal setup script dependency " .. dependency .. ": " .. tostring(err))
			return false
		end
	end

	local args = { "/tmp/install_dal_trusted_setup.sh" }

	if os.execute("octez-node --version | grep '20.'") then
		table.insert(args, "--legacy")
	end

	local result = proc.spawn("sh", args, {
		username = env.user,
		wait = true,
		stdio = "inherit",
		env = build_env( { HOME = env.home_directory } ),
	}) --[[@as SpawnResult]]

	return result.exit_code == 0
end

function octez.reset()
	local NODE_DIR = path.combine(env.home_directory, ".tezos-node")
	local CLIENT_DIR = path.combine(env.home_directory, ".tezos-client")

	fs.remove(CLIENT_DIR, { recurse = true, content_only = true })
	fs.remove(NODE_DIR, { recurse = true, content_only = true })
end

return octez
