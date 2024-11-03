local args = require "util.args"

local tezboxDirectory = os.getenv("TEZBOX_DIRECTORY") or "/tezbox"
local tezboxContextDirectory = path.combine(tezboxDirectory, "context")
local tezboxDataDirectory = path.combine(tezboxContextDirectory, "data")
local tezboxBakersHomeDirectory = path.combine(tezboxDataDirectory, "bakers-home")
local defaultEnv = {
	tezboxDirectory = tezboxDirectory,
	configurationDirectory = path.combine(tezboxDirectory, "configuration"),
	configurationOverridesDirectory = path.combine(tezboxDirectory, "overrides"),
	contextDirectory = tezboxContextDirectory,

	-- octez directories
	homeDirectory = tezboxDataDirectory,
	bakersHomeDirectory = tezboxBakersHomeDirectory,

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
	bakersHomeDirectory = args.options["bakers-home-directory"] or env.get_env("BAKERS_HOME_DIRECTORY"),

	octezNodeBinary = args.options["octez-node-binary"] or env.get_env("OCTEZ_NODE_BINARY"),
	octezClientBinary = args.options["octez-client-binary"] or env.get_env("OCTEZ_CLIENT_BINARY"),

	user = args.options["user"] or env.get_env("TEZBOX_USER"),
}, defaultEnv)

fs.mkdirp(env.configurationDirectory)
fs.mkdirp(env.configurationOverridesDirectory)
fs.mkdirp(env.contextDirectory)
fs.mkdirp(env.homeDirectory)
fs.mkdirp(env.bakersHomeDirectory)

return env
