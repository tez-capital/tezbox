local args = require "util.args"

local tezboxDirectory = os.getenv("TEZBOX_DIRECTORY") or "/tezbox"
local tezboxDataDirectory = path.combine(tezboxDirectory, "data")
local tezboxContextDirectory = path.combine(tezboxDirectory, "context")
local defaultEnv = {
	tezboxDirectory = tezboxDirectory,
	configurationDirectory = path.combine(tezboxDirectory, "configuration"),
	configurationOverridesDirectory = path.combine(tezboxDirectory, "overrides"),
	contextDirectory = tezboxContextDirectory,
	sandboxParametersFile = "sandbox-parameters.json",
	protocol = "proxford",

	-- octez directories
	homeDirectory = tezboxDataDirectory,

	octezNodeBinary = "octez-node",
	octezClientBinary = "octez-client",
	voteFile = path.combine(tezboxContextDirectory, "vote.json"),

	user = "tezbox",
}

local env = util.merge_tables({
	configurationDirectory = args.options["configuration-directory"] or env.get_env("CONFIGURATION_DIRECTORY"),
	configurationOverridesDirectory = args.options["configuration-overrides-directory"] or
		env.get_env("CONFIGURATION_OVERRIDES_DIRECTORY"),
	contextDirectory = args.options["context-directory"] or env.get_env("CONTEXT_DIRECTORY"),
	sandboxParametersFile = args.options["sandbox-parameters-file"] or env.get_env("SANDBOX_PARAMETERS_FILE"),
	protocol = args.options["protocol"] or env.get_env("PROTOCOL"),

	homeDirectory = args.options["home-directory"] or env.get_env("HOME_DIRECTORY"),

	octezNodeBinary = args.options["octez-node-binary"] or env.get_env("OCTEZ_NODE_BINARY"),
	octezClientBinary = args.options["octez-client-binary"] or env.get_env("OCTEZ_CLIENT_BINARY"),
	voteFile = args.options["vote-file"] or env.get_env("VOTE_FILE"),

	user = args.options["user"] or env.get_env("USER"),
}, defaultEnv)

fs.mkdirp(env.configurationDirectory)
fs.mkdirp(env.configurationOverridesDirectory)
fs.mkdirp(env.contextDirectory)
fs.mkdirp(env.homeDirectory)

if env.user ~= "" and env.user ~= "root" then
	local ok, uid = fs.safe_getuid(env.user)
	if not ok then
		log_error("user " .. env.user .. " does not exist")
		os.exit(1)
	end

	fs.chown(env.tezboxDirectory, uid, uid, { recurse = true })
end

return env
