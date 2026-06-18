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

local test_image = "tezbox-e2e:current-branch"

run("eli", { "./build/build.lua" })
run("docker", {
	"build",
	"--build-arg", "PROTOCOLS=PtSeouLo,PtTALLiN",
	"--build-arg", "IMAGE_TAG=octez-v24.4",
	"--build-arg", "GITHUB_TOKEN=" .. (os.getenv("GITHUB_TOKEN") or ""),
	"-t", test_image,
	"-f", "containers/tezos/Containerfile",
	".",
})
run("npm", { "--prefix", "tests", "ci" })
run("npm", { "--prefix", "tests", "test" })
