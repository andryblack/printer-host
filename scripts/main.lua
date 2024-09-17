

local llae = require 'llae'
local async = require 'llae.async'
local fs = require 'llae.fs'
local uv = require 'llae.uv'
local path = require 'llae.path'
local json = require 'llae.json'
local log = require 'llae.log'
local posix = require 'posix'

local http_server = require 'http.server'
local printer = require 'printer.printer'

async.run(function()
	log.info('start application')
	application = {}
	local config = {
		files = 'bin/files',
		rootdir = path.join(path.dirname(fs.exepath()),'..'),
		port = 1339
	}
	if args.config then
		local exconf = fs.load_file(args.config)
		exconf = json.decode(exconf)
		for k,v in pairs(exconf) do
			config[k] = v
		end
	end
	if args.logfile then
		config.logfile = args.logfile
	end
	if not fs.isdir(config.files) then
		fs.mkdir(config.files)
	end
	if not fs.isdir(config.files .. '/.printer') then
		fs.mkdir(config.files .. '/.printer')
	end
	if config.logfile then
		application.log_fd = assert(posix.open(config.logfile,posix.O_WRONLY|posix.O_CREAT|posix.O_TRUNC,
				posix.S_IRUSR|posix.S_IWUSR|posix.S_IRGRP|posix.S_IWGRP|posix.S_IROTH))
		assert(posix.dup2(application.log_fd , posix.STDOUT_FILENO ))
		assert(posix.dup2(application.log_fd, posix.STDERR_FILENO ))
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
