local printer = {}

printer.terminal = (require 'printer.terminal').new( printer )
printer.settings = require 'printer.settings_mgmt'

local GCodeParser = require 'gcode.parser'
local GCodeFileSource = require 'gcode.file'

local llae = require 'llae'

printer._temperature = {}
printer._temperature_history = {}
printer._max_temperature_history = 100
printer._temperature_elements = {
	{var='T',alt={'T0'}},
	{var='B',is_bed=true}
}

local state_disconnected = 'disconnected'
local state_idle = 'idle'
local state_printing = 'printing'
local state_paused = 'paused'
local state_flashing = 'flashing'

function printer:init(  )
	self._settings_file = application.config.files .. '/.printer/settings.json'
	self._state = state_disconnected
	self._coord = {x=0,y=0,z=0}
	self.settings:init()
	self.settings:load( self._settings_file )
	if self.terminal:init{
		path = self.settings.device,
		speed = self.settings.baudrate
	} then
		self:on_connected()
	end

	self.pcb = (require 'printer.pcb').new()
	self.generator = (require 'printer.generator').new()
	self:update_from_settings()
end

function printer:update_from_settings(  )
	for _,v in ipairs(self._temperature_elements) do
		if v.is_bed then
			v.values = self.settings.printer_bed_temperatures
		else
			v.values = self.settings.printer_temperatures
		end
	end

	self._print_sd = self.settings.printer_sd_emulation
	print('SD emulation:',self._print_sd)
end

printer._actions = {}
printer._actions['home-x'] = function( self )
	self:send_cmd('G28 X0')
	self._coord.x = 0
	self._need_position = true
end
printer._actions['home-y'] = function( self )
	self:send_cmd('G28 Y0')
	self._coord.y = 0
	self:send_cmd('M114')
end
printer._actions['home-z'] = function( self )
	self:send_cmd('G28 Z0')
	self._coord.z = 0
	self:send_cmd('M114')
end
printer._actions['home-all'] = function( self )
	self:send_cmd('G28')
	self._coord.x = 0
	self._coord.y = 0
	self._coord.z = 0
	self:send_cmd('M114')
end
printer._actions['move'] = function( self , data)
	local cmd = 'G1'
	if data.x then
		self._coord.x = (self._coord.x or 0) + data.x
		cmd = cmd .. ' X' .. self._coord.x
	end
	if data.y then
		self._coord.y = (self._coord.y or 0) + data.y
		cmd = cmd .. ' Y' .. self._coord.y
	end
	if data.z then
		self._coord.z = (self._coord.z or 0) + data.z
		cmd = cmd .. ' Z' .. self._coord.z
	end
	print('move cmd:',cmd)
	self:send_cmd(cmd)
	self:send_cmd('M114')
end
printer._actions['set-temperature'] = function( self , data)
	if data.v == 'T' then
		self:send_cmd('M104 S'..data.t)
	elseif data.v == 'B' then
		self:send_cmd('M140 S'..data.t)
	else
		error('unknown temperature ' .. tostring(data.v))
	end
end


function printer:stop(  )
	self:disconnect()
end

function printer:disconnect(  )
	if self.terminal:close() then
		self._state = state_disconnected
	end
end

function printer:connect(  )
	if self.terminal:init{
		path = self.settings.device,
		speed = self.settings.baudrate
	} then
		self:on_connected()
	end
end

function printer:pause(  )
	self._resume_state = self:start_state(state_paused)
	if self._print_sd then
		self:send_cmd('M25')
	end
end

function printer:resume(  )
	self:end_state(state_paused,self._resume_state)
	self._resume_state = nil
	if self._print_sd then
		self:send_cmd('M24')
	end
end

function printer:print_stop(  )
	self:end_state(state_paused,state_idle)
	self._resume_state = nil
end

function printer:on_connected(  )
	self._state = state_idle
	self._delay = 3
	self._start_cmd_idx = 1
	self.terminal:reset()
end

function printer:start_state( state )
	local res = self._state
	self._state = state
	return res
end

function printer:end_state( state , new_state)
	if self._state == state then
		self._state = new_state
	end
end

function printer:save_settings(  )
	self.settings:store(self._settings_file )
	self:update_from_settings()
end

function printer:send_cmd( cmd )
	local code = GCodeParser.parse(cmd)
	if not code then
		print('not gcode:',cmd)
		return self:send_gcode({cmd=cmd})
	end
	return self:send_gcode(code)
end

function printer:action( action , data)
	local fn = self._actions[action]
	if fn then
		fn(self,data)
	else
		error('unknown action ' .. action)
	end
end

function printer:send_gcode( cmd )
	cmd.obj = self
	return self.terminal:send_gcode(cmd)
end

function printer:get_state(  )
	return {
		state = self._state,
		coord = self._coord,
		progress = self._progress,
		temperature = self._temperature
	}
end

function printer:is_connected(  )
	return self._state == state_idle
end

function printer:on_ok_rx(  )
	--self._delay = 1
end

function printer:on_rx( data )
	--print('rx:',data)
	local tdata = {}
	for n,v in string.gmatch(data,'([%u%d]+):(%-?%d+%.?%d*)') do
		--print(n,v)
		tdata[n]=tonumber(v)
	end
	if next(tdata) then
		local has_temp = false
		for _,v in ipairs(self._temperature_elements) do
			if tdata[v.var] then
				has_temp = true
				self._temperature[v.var] = tdata[v.var]
			elseif v.alt then
				for _,a in ipairs(v.alt) do
					if tdata[a] then
						has_temp = true
						tdata[v.var] = tdata[a]
						tdata[a] = nil
						self._temperature[v.var] = tdata[v.var]
					end
				end
			end
		end
		if has_temp then
			table.insert(self._temperature_history,tdata)
			if #self._temperature_history > self._max_temperature_history then
				table.remove(self._temperature_history,1)
			end
		end
	end
	if tdata.X then
		self._coord.x = tdata.X
	end
	if tdata.Y then
		self._coord.y = tdata.Y
	end
	if tdata.Z then
		self._coord.z = tdata.Z
	end
end

function printer:on_timer(  )
	if self._delay then
		self._delay = self._delay - 1 
		if self._delay > 0 then
			return
		end
		self._delay = nil
	end
	
	if self:is_connected() and self.terminal:is_empty() then
		if self._start_cmd_idx then
			local cmd = self.settings.printer_start_commands[self._start_cmd_idx]
			print('start cmd:',self._start_cmd_idx,cmd)
			if not cmd then
				self._start_cmd_idx = nil
			else 
				self:send_cmd(cmd)
				self._start_cmd_idx = self._start_cmd_idx + 1
			end
			
		else
			self:send_cmd('M105')
		end
	elseif self:is_connected() then
		self.terminal:process()
	end
	if self._print_thread_timer then
		self._print_thread_timer()
	end
end

function printer:get_temperature_history( )
	return self._temperature_history;
end

function printer:get_temperature_history_max_length(  )
	return self._max_temperature_history
end

function printer:get_temperature_elements( )
	return self._temperature_elements
end


function printer:_print_thread_func( state, source )
	while true do
		local line = source:get()
		if not line then
			break
		end
		print('line:',line)
		local code = GCodeParser.parse(line)
		self._progress = source:progress()
		if code and code.cmd then
			while not self.terminal:is_empty() do
				print('terminal busy')
				coroutine.yield()
			end
			while self._state == state_paused do
				coroutine.yield()
			end
			if self._state == state_idle then
				break
			end
			
			local r,e = self:send_gcode( code )
			if not r then
				print('send gcode failed:',e)
				break
			end
			while not code.ok and not code.error do
				coroutine.yield()
			end
			if code.error then
				print('printing failed: ', code.error)
				break
			end
		else
			print('skip line:',line)
		end
	end
	self._print_thread = nil
	source:release()
	self._progress = nil
	self:end_state(state_printing,state)
end

function printer:_print_sd_thread_func( state, source )
	
	while string.sub(source,1,1) == '/' do
		source = string.sub(source,2,-1)
	end
	
	print('SD file:',source)
	
	self._progress = 0
	
	local r,e = self:send_cmd( 'M23 ' .. source )
	if not r then
		print('send gcode failed:',e)
		return 
	end

	r,e = self:send_cmd( 'M24' )
	if not r then
		print('send gcode failed:',e)
		return
	end

	local printing_complete = false
	local function on_status_rx(data)
		print('on_status_rx:',data)
		local cur,total = string.match(data,'SD printing byte (%d+)/(%d+)')
		if cur then
			self._progress = tonumber(cur) / tonumber(total)
		elseif string.match(data,'Not SD printing.') then
			printing_complete = true
		end
	end

	while not printing_complete do

		local code = GCodeParser.parse('M27')
		code.on_rx = on_status_rx
		r,e = self:send_gcode(code)

		if not r then
			print('send gcode failed:',e)
		end

		coroutine.yield()

		if self._state == state_idle then
			printing_complete = true
		end
	end

end

function printer:print( source )
	local state = self:start_state(state_printing)
	self._print_thread = llae.newThread()
	self._print_thread:start(
		function(th) 
			local res,err = xpcall(function()
				self:_print_thread_func(state,source)
			end,debug.traceback)
			if not res then
				print('failed print thread',err)
				error(err)
			end
		end)
end

function printer:print_sd( source )
	local state = self:start_state(state_printing)
	print('print sd:',source)
	self._print_thread_timer = coroutine.wrap( function(th) 
			local res,err = xpcall(function()
				self:_print_sd_thread_func(state,source)
			end,debug.traceback)

			self._print_thread_timer = nil
			self._progress = nil
			self:end_state(state_printing,state)

			if not res then
				print('failed print thread',err)
				error(err)
			end
		end) 
	return true
		
end

function printer:print_file( file )
	if self._print_sd then
		return self:print_sd( file )
	end
	print('print file:',file)
	local file_path = application.config.files .. '/' .. file
	local src,err = GCodeFileSource.open(file_path)
	if src then
		self:print(src)
		return true
	end
	return false,err
end

function printer:print_sd_file( file )
	if file then
		self:print_sd(file)
		return true
	end
	return false,err
end

function printer:flash_file( file )
	local file_path = application.config.files .. '/' .. file
	local f,err = io.open(file_path,'rb')
	if not f then
		error(err)
	end
	local firmware_data = f:read('a')
	f:close()

	local state = self:start_state(state_flashing)
	self._print_thread = llae.newThread()
	self._print_thread:start(
		function(th) 
			local res,err = xpcall(function()
				self:_flash_thread_func(state,firmware_data)
			end,debug.traceback)
			if not res then
				print('failed flash thread',err)
				error(err)
			end
		end)
end

function printer:_flash_thread_func( state, data )
	local r,e = self:send_cmd( 'M242 S242' )
	if not r then
		print('send gcode failed:',e)
		self:end_state(state_printing,state)
		return
	end
	print('firmware update start, close connection')
	self.terminal:close()
	local flasher = (require 'printer.flasher').new{
		path = self.settings.device,
		speed = self.settings.baudrate
	}
	print('connect to bootloader')
	if not flasher:connect() then
		print('flasher connect failed')
		self:end_state(state_printing,state)
		return
	end
	print('flsh firmware')
	flasher:flash( data , self.settings.flash_addr )

	flasher:close()

	self._print_thread = nil

	self:connect()
end


return printer