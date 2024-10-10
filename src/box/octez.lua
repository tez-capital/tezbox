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
local function buildEnv(overrides)
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

	return proc.spawn(env.octezClientBinary, args, {
		username = options.user or env.user,
		wait = true,
		stdio = "inherit",
		env = buildEnv( { HOME = env.homeDirectory } ),
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

	return proc.spawn(env.octezNodeBinary, args, {
		username = options.user or env.user,
		wait = true,
		stdio = "inherit",
		env = buildEnv( { HOME = env.homeDirectory } ),
	}) --[[@as SpawnResult]]
end

---@param configOptionsArgs table<string, string>
---@param options RunNodeOptions?
function octez.node.init_config(configOptionsArgs, options)
	if type(configOptionsArgs) ~= "table" then configOptionsArgs = {} end
	if type(options) ~= "table" then options = {} end

	local args = {
		"config",
		"init",
	}
	if table.is_array(configOptionsArgs) then
		for _, value in ipairs(configOptionsArgs) do
			table.insert(args, value)
		end
	elseif type(configOptionsArgs) == "table" then
		for key, value in pairs(configOptionsArgs) do
			table.insert(args, "--" .. key .. "=" .. value)
		end
	end
	return octez.node.run(args, options)
end

---@class FooOptions: RunNodeOptions
---@field timeout integer?

---@param exec fun()
---@param options FooOptions?
function octez.exec_with_node_running(exec, options)
	if type(options) ~= "table" then options = {} end
	if type(exec) ~= "function" then
		return
	end

	local NODE_DIR = path.combine(env.homeDirectory, ".tezos-node")
	local time = os.time() + (options.timeout or 60)
	local args = {
		"run",
		"--data-dir=" .. NODE_DIR,
		"--synchronisation-threshold=0",
		"--connections=0",
		"--allow-all-rpc=0.0.0.0",
		"--no-bootstrap-peers",
		"--private-mode",
		"--sandbox=" .. path.combine(env.contextDirectory, "sandbox.json"),
	}

	local overrideEnv = {}
	if env.homeDirectory == os.getenv("HOME") then
		overrideEnv = { HOME = "/tmp" } -- octez node refuses to use HOME in sandbox mode so we need to override it to proceed
	end

	local nodeProc = proc.spawn(env.octezNodeBinary, args, {
		username = options.user or env.user,
		stdio = "inherit",
		env = buildEnv(overrideEnv),
	}) --[[@as EliProcess]]

	local executed = false
	while nodeProc:wait(100, 1000) == -1 do
		local ok = net.safe_download_string("http://127.0.0.1:8732/chains/main/blocks/head/metadata")
		if ok then
			exec()
			executed = true
			break
		end
		if os.time() > time then
			break
		end
	end
	nodeProc:kill(signal.SIGTERM)
	local exitCode = nodeProc:wait(30)
	if exitCode < 0 then
		nodeProc:kill(signal.SIGKILL)
	end
	return executed
end

---@param options RunNodeOptions?
function octez.node.generate_identity(options)
	if type(options) ~= "table" then options = {} end
	return octez.node.run({ "identity", "generate", "0.0" }, options)
end

function octez.baker.run(shortProtocol, args, options)
	if type(options) ~= "table" then options = {} end
	if type(args) ~= "table" then args = {} end

	return proc.spawn(env.octezBakerBinary .. "-" .. shortProtocol, args, {
		username = options.user or env.user,
		wait = false,
		stdio = "inherit",
		env = buildEnv( { HOME = env.homeDirectory } ),
	}) --[[@as EliProcess]]
end

function octez.dal.install_trusted_setup()
	log_info("installing dal trusted setup")
	local ok = net.safe_download_file(constants.dal.scripts.setup, "/tmp/install_dal_trusted_setup.sh")
	if not ok then
		log_error("failed to download dal setup script")
		return false
	end

	for _, dependency in ipairs(constants.dal.scripts.dependencies) do
		local ok = net.safe_download_file(dependency, "/tmp/" .. path.file(dependency))
		if not ok then
			log_error("failed to download dal setup script dependency " .. dependency)
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
		env = buildEnv( { HOME = env.homeDirectory } ),
	}) --[[@as SpawnResult]]

	return result.exitcode == 0
end

function octez.reset()
	local NODE_DIR = path.combine(env.homeDirectory, ".tezos-node")
	local CLIENT_DIR = path.combine(env.homeDirectory, ".tezos-client")

	fs.remove(CLIENT_DIR, { recurse = true, contentOnly = true })
	fs.remove(NODE_DIR, { recurse = true, contentOnly = true })
end

return octez
