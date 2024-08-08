local args = require "util.args"

local tezboxDirectory = os.getenv("TEZBOX_DIRECTORY") or "/tezbox"
local tezboxDataDirectory = path.combine(tezboxDirectory, "data")
local tezboxContextDirectory = path.combine(tezboxDirectory, "context")
local defaultEnv = {
	tezboxDirectory = tezboxDirectory,
	configurationDirectory = path.combine(tezboxDirectory, "configuration"),
	configurationOverridesDirectory = path.combine(tezboxDirectory, "overrides"),
	contextDirectory = tezboxContextDirectory,

	-- octez directories
	homeDirectory = tezboxDataDirectory,

	octezNodeBinary = "octez-node",
	octezClientBinary = "octez-client",
	octezBakerBinary = "octez-baker",

	user = "tezbox",
}

local env = util.merge_tables({
	configurationDirectory = args.options["configuration-directory"] or env.get_env("CONFIGURATION_DIRECTORY"),
	configurationOverridesDirectory = args.options["configuration-overrides-directory"] or
		env.get_env("CONFIGURATION_OVERRIDES_DIRECTORY"),
	contextDirectory = args.options["context-directory"] or env.get_env("CONTEXT_DIRECTORY"),

	homeDirectory = args.options["home-directory"] or env.get_env("HOME_DIRECTORY"),

	octezNodeBinary = args.options["octez-node-binary"] or env.get_env("OCTEZ_NODE_BINARY"),
	octezClientBinary = args.options["octez-client-binary"] or env.get_env("OCTEZ_CLIENT_BINARY"),

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
