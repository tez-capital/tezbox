local function run(command, args)
	io.write("> " .. command)
	for _, arg in ipairs(args) do
		io.write(" " .. tostring(arg))
	end
	io.write("\n")

	local result = proc.spawn(command, args, {
		wait = true,
		stdio = "inherit",
	}) --[[@as SpawnResult]]

	if result.exit_code ~= 0 then
		os.exit(result.exit_code or 1)
	end
end

run("npm", { "--prefix", "tests", "ci" })
run("npm", { "--prefix", "tests", "test" })
