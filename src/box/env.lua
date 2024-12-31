local args = require "util.args"

local tezbox_directory = os.getenv("TEZBOX_DIRECTORY") or "/tezbox"
local tezbox_context_directory = path.combine(tezbox_directory, "context")
local tezbox_data_directory = path.combine(tezbox_context_directory, "data")
local tezbox_bakers_home_directory = path.combine(tezbox_data_directory, "bakers-home")
local default_env = {
	tezbox_directory = tezbox_directory,
	configuration_directory = path.combine(tezbox_directory, "configuration"),
	configuration_overrides_directory = path.combine(tezbox_directory, "overrides"),
	context_directory = tezbox_context_directory,

	-- octez directories
	home_directory = tezbox_data_directory,

	octez_node_binary = "octez-node",
	octez_client_binary = "octez-client",
	octez_baker_binary = "octez-baker",

	user = "tezbox",
}

local env = util.merge_tables({
	configuration_directory = args.options["configuration-directory"] or env.get_env("CONFIGURATION_DIRECTORY"),
	configuration_overrides_directory = args.options["configuration-overrides-directory"] or
		env.get_env("CONFIGURATION_OVERRIDES_DIRECTORY"),
	context_directory = args.options["context-directory"] or env.get_env("CONTEXT_DIRECTORY"),

	home_directory = args.options["home-directory"] or env.get_env("TEZBOX_HOME"),

	octez_node_binary = args.options["octez-node-binary"] or env.get_env("OCTEZ_NODE_BINARY"),
	octez_client_binary = args.options["octez-client-binary"] or env.get_env("OCTEZ_CLIENT_BINARY"),
	octez_baker_binary = args.options["octez-baker-binary"] or env.get_env("OCTEZ_BAKER_BINARY"),

	user = args.options["user"] or env.get_env("TEZBOX_USER"),
}, default_env)

fs.mkdirp(env.configuration_directory)
fs.mkdirp(env.configuration_overrides_directory)
fs.mkdirp(env.context_directory)
fs.mkdirp(env.home_directory)

return env
