local skynet = require "skynet"
local string = string
local table = table
local tonumber = tonumber
local ipairs = ipairs
local unpack = unpack
local redis_server = ...
local fd
local write_fd
local readline_fd
local read_fd
local close_fd

local function init_fd(fdstr)
	fd = fdstr
	write_fd = "WRITE "..fd.." "
	readline_fd = "READLINE ".. fd .." \r\n"
	read_fd = "READ " .. fd .. " "
	close_fd = "CLOSE "..fd
end

local function init()
	fd = skynet.call(".connection", "CONNECT " .. redis_server)
	if fd == nil then
		print("Connect to redis server error : ", redis_server)
		skynet.exit()
		return true
	end
	init_fd(fd)
end


local function compose_message(msg)
	local lines = { "*" .. #msg }
	for _,v in ipairs(msg) do
		table.insert(lines,"$"..#v)
		table.insert(lines,v)
	end
	table.insert(lines,"")

	local cmd =  table.concat(lines,"\r\n")
	return cmd
end

local redcmd = {}

redcmd[42] = function(data)	-- '*'
	local n = tonumber(data)
	if n < 1 then
		skynet.ret(skynet.pack(true, nil))
		return
	end
	local bulk = {}
	for i = 1,n do
		local line = skynet.call(".connection", readline_fd)
		local bytes = tonumber(string.sub(line,2) + 2)
		local data = skynet.call(".connection", read_fd .. bytes)
		table.insert(result, string.sub(data,1,-3))
	end
	skynet.ret(skynet.pack(true,bulk))
end

redcmd[36] = function(data) -- '$'
	local bytes = tonumber(data)
	if bytes < 0 then
		skynet.ret(skynet.pack(true, nil))
		return
	end
	local firstline = skynet.call(".connection", read_fd .. (bytes + 2))
	skynet.ret(skynet.pack(true,string.sub(firstline,1,-3)))
end

redcmd[43] = function(data) -- '+'
	skynet.ret(skynet.pack(true, data))
end

redcmd[45] = function(data) -- '-'
	skynet.ret(skynet.pack(false, data))
end

redcmd[58] = function(data) -- ':'
	skynet.ret(skynet.pack(true, tonumber(data)))
end

skynet.dispatch(function(msg, sz, session, address)
	local message = { skynet.unpack(msg,sz) }
	local write_cmd = write_fd .. compose_message(message)
	local result
	while true do
		skynet.send(".connection", write_cmd )
		result = skynet.call(".connection", readline_fd)
		if result then
			break
		end
		-- reconnect
		if init() then
			skynet.ret(skynet.pack(false , "Disconnected"))
			return
		end
	end
	local firstchar = string.byte(result)
	local data = string.sub(result,2)
	local f = redcmd[firstchar]
	if f == nil then
		skynet.ret(skynet.pack(false , "Invalid result"))
		skynet.send(".connection", close_fd)
		init()
	else
		f(data)
	end
end)

skynet.start(init)
