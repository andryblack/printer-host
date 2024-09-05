

local llae = require 'llae'
local async = require 'llae.async'
local fs = require 'llae.fs'
local uv = require 'llae.uv'
local path = require 'llae.path'
local json = require 'llae.json'
local log = require 'llae.log'

local http_server = require 'http.server'
local printer = require 'printer.printer'

async.run(function()
	log.info('start application')
	application = {}
	local config = {
		files = 'bin/files',
		rootdir = path.join(path.dirname(fs.exepath()),'..'),
	}
	if args.config then
		local exconf = fs.load_file(args.config)
		exconf = json.decode(exconf)
		for k,v in pairs(exconf) do
			config[k] = v
		end
	end
	if not fs.isdir(config.files) then
		fs.mkdir(config.files)
	end
	if not fs.isdir(config.files .. '/.printer') then
		fs.mkdir(config.files .. '/.printer')
	end

	application.config = config

	application.http = http_server.new( config )
	application.http:start()

	application.printer = printer
	application.printer:init()

	application.timer_sec = uv.timer.new()
	application.timer_sec:start(function()
		application.printer:on_timer(application.timer_sec)
	end,1000,1000)

end,true)

--llae.set_handler()
--local timer_sec = llae.newTimer()

-- local main_coro = coroutine.create(function()
-- 	local res,err = xpcall(function()

-- 		application = {}
-- 		application.args = require 'cli_args'


-- 		local table_load = require 'table_load'
-- 		local config = table_load.load(table_load.get_path('default_config.lua'),{
-- 			scripts_root = dir,
-- 			lua = _G
-- 		})
-- 		if application.args.config then
-- 			config = table_load.load(application.args.config,config)
-- 		end
-- 		application.config = config
-- 		package.path = package.path .. ';' .. config.modules
-- 		package.cpath = package.cpath .. ';' .. config.cmodules

-- 		local files_root = application.config.files

-- 		if not os.isdir(files_root) then
-- 		    os.mkdir(files_root)
-- 		end

-- 		if not os.isdir(files_root .. '/.printer') then
-- 		    os.mkdir(files_root .. '/.printer')
-- 		end

-- 		application.http = require 'http.server'
-- 		application.http:start()

-- 		application.printer = require 'printer.printer'
-- 		application.printer:init()

-- 		timer_sec:start(function()
-- 			application.printer:on_timer(timer_sec)
-- 		end,1000,1000)

-- 	end,
-- 	debug.traceback)

-- 	if not res then
-- 		print('failed start printer')
-- 		error(err)
-- 	end

-- end)

-- local res,err = coroutine.resume(main_coro)
-- if not res then
-- 	print('failed main thread',err)
-- 	error(err)
-- end

-- llae.run()
-- timer_sec:stop()
-- application.http:stop()
-- application.printer:stop()

-- application = nil

-- print('stop')
-- collectgarbage('collect')
-- llae.dump()
