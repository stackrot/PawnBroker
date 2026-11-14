-- Runs every scenario against the addon in the repo root with mocked game
-- APIs and real scan data, each in its own LuaJIT process so no state leaks
-- between them. Works on Linux, macOS and Windows.
-- usage: luajit tests/run.lua [-v]	(-v shows chat output)

local windows = package.config:sub(1, 1) == "\\"
local here = arg[0]:match("^(.*)[/\\]") or "."
local lua = arg[-1] or "luajit"
local verbose = arg[1] == "-v"

local function quote(s)
	return '"' .. s .. '"'
end

-- A quoted path in this OS's separators, for the shell.
local function path(s)
	return quote(windows and s:gsub("/", "\\") or s)
end

-- os.execute gives a number in Lua 5.1 mode and a boolean in 5.2 mode.
local function run(cmd)
	-- cmd.exe strips the outer quotes of a command that starts with one.
	local status = os.execute(windows and quote(cmd) or cmd)
	return status == 0 or status == true
end

local function scenarios()
	local cmd = windows
		and ("dir /b " .. path(here .. "/scenarios/*.lua"))
		or ("ls " .. path(here .. "/scenarios"))
	local names = {}
	local p = assert(io.popen(cmd))
	for line in p:lines() do
		local name = line:match("^(.-)%.lua%s*$")
		-- Names go into a shell command, so only plain ones are run.
		if name and name:find("^[%w_%-]+$") then
			names[#names + 1] = name
		elseif name then
			error("scenario names may only use letters, digits, _ and -: "
				.. line, 0)
		end
	end
	p:close()
	table.sort(names)
	return names
end

local function readAll(path)
	local f = io.open(path, "rb")
	if not f then
		return ""
	end
	local s = f:read("*a")
	f:close()
	os.remove(path)
	return s
end

local function indent(text)
	return (text:gsub("[^\n]+", "     %0"))
end

local out = here .. "/.scenario-output"
local failed = 0
for _, name in ipairs(scenarios()) do
	local cmd = table.concat({
		quote(lua),
		verbose and "-e VERBOSE=true" or "",
		path(here .. "/harness.lua"), path(here .. "/mockdata.lua"),
		path(here .. "/gear.lua"), path(here .. "/.."),
		path(here .. "/scenarios/" .. name .. ".lua"),
		">" .. path(out), "2>&1",
	}, " ")
	local ok = run(cmd)
	local text = readAll(out)
	print((ok and "ok   " or "FAIL ") .. name)
	if not ok or verbose then
		io.write(indent(text))
	end
	if not ok then
		failed = failed + 1
	end
end
if failed > 0 then
	os.exit(1)
end
