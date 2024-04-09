--- Log module
---@param id string
return function(id)
	---#DES log_success
	---
	---@diagnostic disable-next-line: undefined-doc-param
	---@param msg LogMessage|string
	---@param vars table?
	log_success,
	---#DES log_trace
	---
	---@diagnostic disable-next-line: undefined-doc-param
	---@param msg LogMessage|string
	---@param vars table?
	log_trace,
	---#DES log_debug
	---
	---@diagnostic disable-next-line: undefined-doc-param
	---@param msg LogMessage|string
	---@param vars table?
	log_debug,
	---#DES log_info
	---
	---@diagnostic disable-next-line: undefined-doc-param
	---@param msg LogMessage|string
	---@param vars table?
	log_info,
	---#DES log_warn
	---
	---@diagnostic disable-next-line: undefined-doc-param
	---@param msg LogMessage|string
	---@param vars table?
	log_warn,
	---#DES log_error
	---
	---@diagnostic disable-next-line: undefined-doc-param
	---@param msg LogMessage|string
	---@param vars table?
	log_error = util.global_log_factory(id, "success", "trace", "debug", "info", "warn", "error")
end
