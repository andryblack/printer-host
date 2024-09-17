local log = require 'llae.log'
local async = require 'llae.async'
local json = require 'llae.json'
local klipper_api = require 'printer.klipper_api'

local printer = {}

printer.terminal = (require 'printer.terminal').new( printer )
printer.settings = require 'printer.settings_mgmt'

local GCodeParser = require 'gcode.parser'
local GCodeFileSource = require 'gcode.file'


printer._temperature = {}
printer._temperature_history = {}
printer._max_temperature_history = 100
printer._temperature_elements = {
	{var='T',alt={'T0'},status='extruder'},
	{var='B',is_bed=true,status='heater_bed'}
}

local state_disconnected = 'disconnected'
local state_idle = 'idle'
local state_printing = 'printing'
local state_paused = 'paused'
local state_flashing = 'flashing'
local state_wait = 'wait'

function printer:init(  )
	self._settings_file = application.config.files .. '/.printer/settings.json'
	self._state = state_disconnected
	self._coord = {x=0,y=0,z=0}
	self._klipper_api = klipper_api.new()
	self.settings:init()
	self.settings:load( self._settings_file )



	self.generator = (require 'printer.generator').new()
	self:update_from_settings()

	self:connect()
end

function printer:update_from_settings(  )
	for _,v in ipairs(self._temperature_elements) do
		if v.is_bed then
			v.values = self.settings.printer_bed_temperatures
		else
			v.values = self.settings.printer_temperatures
		end
	end
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
	log.info('move cmd:',cmd)
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
		
	end
	self._klipper_api:close()
	self._state = state_disconnected
end

function printer:connect(  )
	self._state = state_disconnected

	local res,err = self.terminal:init(application.config.klipper)
	if not res  then
		log.error('failed open klipper',err)
		self.terminal:add_history{
			type = 'err',
			line = 'failed open klipper ' .. tostring(err),
		}
		return false
	end
	
	if not self:open_klipper_api() then
		return false
	end
	
	
	self._delay = 3
	self._start_cmd_idx = 1
	self.terminal:reset()
end

function printer:pause(  )
	return self:wait_state_command('pause_resume/pause',{})
end

function printer:resume(  )
	return self:wait_state_command('pause_resume/resume',{})
	-- self:end_state(state_paused,self._resume_state)
	-- self._resume_state = nil
	-- self:send_cmd('M24')
end


function printer:cancel(  )
	if self._state == state_wait then
		log.info('request cancel printer')
		local res, err = self._klipper_api:request('pause_resume/cancel',{})
		if not res then
			self:on_klipper_api_err(err)
		else
			log.info('cancel result:',json.encode(res))
		end
	end
end

function printer:print_stop(  )
	if self._state == state_paused then
		return self:wait_state_command('pause_resume/cancel',{})
	end
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
		log.info('not gcode:',cmd)
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
	--log.info('rx:',data)
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

function printer:on_klipper_api_err(data)
	local msg = data
	local s,err = json.decode(data,true)
	if s then
		msg = s.message or s.error
	end
	self.terminal:add_history{
		type = 'err',
		line = 'klipper api: ' .. tostring(msg),
	}
end

function printer:configure_klipper()
	if not self._klipper_api:is_connected() then
		log.error('not connected')
		return
	end
	local res,err = self._klipper_api:request('info',{})
	if res then
		log.info('info received:',json.encode(res))
		self.terminal:add_history{
			type = 'sys',
			line = res.state_message
		}
	else
		self:on_klipper_api_err(err)
	end
end

function printer:on_timer(  )
	
end

function printer:process_klipper_state(obj)
	log.info('>>>',json.encode(obj))
	local status = obj.status or {}
	local webhooks = status.webhooks or {}
	local state = webhooks.state 
	local old_state = self._state
	if state then
		if state == 'ready' then
			self._state = state_idle
			local virtual_sdcard = status.virtual_sdcard or {} 
			local pause_resume = status.pause_resume or {}
			if pause_resume.is_paused then
				self._state = state_paused
			else
				if virtual_sdcard.is_active then
					self._progress = virtual_sdcard.progress
					self._state = state_printing
				end
				self._progress = virtual_sdcard.progress
			end
			
		elseif state == 'error' then
			self._state = state_disconnected
		else
			self._state = state_disconnected
		end
	end

	for _,v in ipairs(self._temperature_elements) do
		if v.status then
			local hs = status[v.status]
			if hs and hs.temperature then
				self._temperature[v.var] = hs.temperature
			end
		end
	end
			

	if self._state  ~= old_state then
		self.terminal:add_history{
			type = 'sys',
			line = webhooks.state_message or self._state 
		}
	end
end

function printer:wait_state_command(command,params)
	if self._state_command then
		return false, 'wait'
	end
	self._state = state_wait
	self._state_command = {command,params}
	return true
end

function printer:open_klipper_api()
	local res,err = self._klipper_api:open(application.config.klipper_api)
	if not res then
		log.error('failed open klipper api',err)
		self.terminal:add_history{
			type = 'err',
			line = 'failed open klipper api: ' .. tostring(err),
		}
		return false
	end
	return true
end

function printer:process_loop()
	if not self._klipper_api:is_connected() then
		async.pause(1000)
		self:open_klipper_api()
		return
	end
	if self.terminal:is_connected() and self.terminal:is_empty() then
		if self._start_cmd_idx then
			local cmd = self.settings.printer_start_commands[self._start_cmd_idx]
			log.info('start cmd:',self._start_cmd_idx,cmd)
			if not cmd then
				self._start_cmd_idx = nil
				self:configure_klipper()
			else 
				self:send_cmd(cmd)
				self._start_cmd_idx = self._start_cmd_idx + 1
			end
		end
	elseif self.terminal:is_connected() then
		self.terminal:process()
	else
		async.pause(1000)
	end

	if not self._start_cmd_idx then
		if self._state_command and self._state == state_wait then
			local command = self._state_command
			self._state_command = nil
			log.info('request state command',table.unpack(command))
			local res,err = self._klipper_api:request(table.unpack(command))
			log.info('response state command',json.encode(res),json.encode(err))
			if not res then
				self:on_klipper_api_err(err)
			else
				log.info('state change success:',command[1],json.encode(res))
			end
		else
			local res,err = self._klipper_api:request('objects/query',{objects={
				toolhead = json.array{'position'},
				virtual_sdcard = json.array{'is_active','progress'},
				webhooks = json.array{'state','state_message'},
				pause_resume = json.array{'is_paused'},
				heater = json.array{'temperature','extruder'},
				extruder = json.array{'temperature','target'},
				heater_bed = json.array{'temperature','target'},
			}})
			if not res then
				self:on_klipper_api_err(err)
			else
				self:process_klipper_state(res)
			end
			async.pause(1000)
		end
	end
end

function printer:start()
	async.run(function()
		while true do
			self:process_loop()
		end
	end)
end

function printer:update_temperatures()

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



function printer:print_sd( source )
	local state = self:start_state(state_printing)
	log.info('print sd:',source)

	while string.sub(source,1,1) == '/' do
		source = string.sub(source,2,-1)
	end
	
	log.info('SD file:',source)
	
	self._progress = 0
	
	local r,e = self:send_cmd( 'M23 ' .. source )
	if not r then
		log.error('send gcode failed:',e)
		return false, e
	end

	r,e = self:send_cmd( 'M24' )
	if not r then
		log.error('send gcode failed:',e)
		return false, e
	end

	self._sd_printing_complete = false
	return true
end

function printer:print_file( file )
	return self:print_sd( file )
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
	async.run(function() 
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
		log.error('send gcode failed:',e)
		self:end_state(state_printing,state)
		return
	end
	log.info('firmware update start, close connection')
	self.terminal:close()
	local flasher = (require 'printer.flasher').new{
		path = self.settings.device,
		speed = self.settings.baudrate
	}
	log.info('connect to bootloader')
	if not flasher:connect() then
		log.error('flasher connect failed')
		self:end_state(state_printing,state)
		return
	end
	log.info('flsh firmware')
	flasher:flash( data , self.settings.flash_addr )

	flasher:close()

	self:connect()
end


return printer