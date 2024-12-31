#!/usr/bin/env eli
require "util.log" ("tezbox")

local args = require "util.args"

if args.command == "version" or args.options["version"] then
	print(string.interpolate("tezbox ${version}", { version = require "version-info".VERSION }))
	os.exit(0)
end

GLOBAL_LOGGER.options.level = args.options["log-level"] or "info"

local core = require "box.core"

if args.command == "init" or args.command == "initialize" then
	if #args.parameters < 1 then
		log_error("missing protocol")
		os.exit(1)
	end

	local protocol = args.parameters[1]
	local options = {}
	if args.options["setup-services"] then
		options.inject_services = true
	end

	if args.options["with-dal"] then
		options.with_dal = true
	end

	if type(args.options["with-init"]) == "string" then
		options.init = args.options["with-init"]
	end


	core.initialize(protocol, options)
	os.exit(0)
end

if args.command == "list-protocols" then
	core.list_protocols()
	os.exit(0)
end

if args.command == "run" then
	core.run()
	os.exit(0)
end

os.exit(1)
