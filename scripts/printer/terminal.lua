local class = require 'llae.class'
local async = require 'llae.async'
local log = require 'llae.log'

local Connection = require 'printer.connection'
local Terminal = class(nil,'printer.Terminal')


local notify_event = class()

function notify_event:_init()
	self._wait = {}
end

function notify_event:wait()
	local c = coroutine.running()
	--log.debug('<<<','wait',c)
	table.insert(self._wait,c)
	coroutine.yield()
end

function notify_event:notify()
	local len = #self._wait
	for _ = 1,len do
		local u = table.remove(self._wait,1)
		if u then
			--log.debug('>>>','notify',u,debug.traceback())
			coroutine.resume(u)
		else
			return
		end
	end
end

function Terminal:_init(  delegate )
	self._history = {}
	self._line_id = 1
	self._send_line = 1
	self._max_history = 50
	self._scheduled = {}
	self._delegate = delegate
	self._event = notify_event.new()
end

function Terminal:reset(  )
	self._current = nil
	self._scheduled = {}
	self._event:notify()
end

function Terminal:init( config )
	self._config = config
	return self:open()
end

function Terminal:open(  )
	self._connection = Connection.create(self._config.path,self)
	local res,err = self._connection:open()
	if res then
		if self._connection:configure_baud(self._config.speed) then
			self:on_opened()
			return true
		else
			log.error('failed configure serial device speed')
		end
	else
		log.error('failed opening serial device',self._config.path,err)
	end
end

function Terminal:close(  )
	self._connection:close()
	return true
end

function Terminal:on_opened(  )
	self._scheduled = {}
	self._send_line = 1
end

function Terminal:is_connected(  )
	return self._connection:is_opened()
end

function Terminal:add_history( data )
	if data.cmd and data.cmd.code and data.cmd.code == 'M105' then
		return
	end
	if data.resp and data.resp.code and data.resp.code == 'M105' then
		return
	end
	table.insert(self._history,data)
	if #self._history > self._max_history then
		table.remove(self._history,1)
	end
	data.id = self._line_id
	self._line_id = self._line_id + 1
end
function Terminal:on_data( data )
	if data == '' then
		return
	end
	if (data == 'wait') then
		log.info('wait')
		return
	end
	--print('rx:',data)
	self:add_history{
		type = 'rx',
		line = data,
		resp = self._current or self._last
	}
	
	
	local err = string.match(data,'^Error:(.+)$')
	if err then
		self:on_error_response(err);
		return
	end

	local line = string.match(data,'^Resend:(%d+)$')
	if line then
		self._send_line = tonumber(line)
		return
	else
		line = string.match(data,'^ok%s(%d+)$')
		if line then
			self:on_ok_response(tonumber(line))
			return
		end
		line = string.match(data,'^skip%s(%d+)$')
		if line then
			self:on_skip_response(tonumber(line))
			return
		end
		local respdata = string.match(data,'^ok%s(.+)$')
		if respdata then
			if self._delegate then
				self._delegate:on_rx(respdata)
			end
			if self._current then
				self:on_ok_response(self._current.line)
			end
			return
		end
		if self._current and self._current.on_rx then
			self._current.on_rx( data )
		end
		if data == 'ok' and self._current then
			self:on_ok_response(self._current.line)
			return
		end
	end
	if self._delegate then
		self._delegate:on_rx(data)
	end
	
end

function Terminal:is_empty(  )
	return not next(self._scheduled) and not self._current
end

function Terminal:do_send_cmd( cmd )
	cmd.line = self._send_line
	local data = string.format('N%d',cmd.line) .. ' ' .. cmd.cmd
	
	if self._connection:write(data .. '\n') then
		self._current = cmd
		--print('tx:',data)
		self:add_history{
			type = 'tx',
			line = data,
			cmd = cmd
		}
		return true
	else
		log.error('failed wtite cmd',cmd)
	end
	return false
end

function Terminal:on_skip_response( line )
	if self._current then
		if self._current.line == line then
			local current = self._current
			current.error = 'skip'
			self._last = self._current
			self._current = nil
			self._send_line = self._send_line + 1
			self:do_next_command()
		else
			log.error('different line ok',self._config.line,line)
		end
	end
end

function Terminal:on_ok_response( line )
	if self._current then
		if self._current.line == line then
			local current = self._current
			current.ok = true
			self._delegate:on_ok_rx()
			self._last = self._current
			self._current = nil
			self._send_line = self._send_line + 1
			self:do_next_command()
		else
			log.error('different line ok',self._config.line,line)
		end
	end
end

function Terminal:on_error_response( err )
	if self._current then
		log.error('rx error: ',err)
		self._current.error = err
		self._event:notify()
	end
end

function Terminal:do_next_command()
	if next(self._scheduled) then
		local cmd = table.remove(self._scheduled,1)
		if not self:do_send_cmd(cmd) then
			table.insert(self._scheduled,1,cmd)
		end
	end
	self._event:notify()
end

function Terminal:send_gcode( cmd )
	if not self._connection or not self._connection:is_opened() then
		return nil,'serial connection closed'
	end
	if self._current then
		log.info('busy, scheduled',#self._scheduled)
		table.insert(self._scheduled,cmd)
	else
		if not self:do_send_cmd(cmd) then
			table.insert(self._scheduled,1,cmd)
		end
	end
	self._event:notify()
	return true
end

function Terminal:send_cmd( command , obj)
	local cmd = {
		cmd = command,
		obj = obj
	}
	return self:send_gcode(cmd)
end

function Terminal:wait_process()
	self._event:wait()
end

function Terminal:process( )
	if self._current then
		self._current.timeout = (self._current.timeout or 0) + 1
		if self._current.timeout > 10 then
			log.error('cmd timeout')
			self:on_error_response( 'timeout' )
		end
	end

	if self._current and self._current.error then
		self:add_history{
			type = 'err',
			line = self._current.error,
			cmd = self._current
		}
		self._last = self._current
		self._current = nil
		self._event:notify()
	end
end

function Terminal:get_log( _from )
	local from = _from or 0
	local r = {}
	for _,v in ipairs(self._history) do
		if v.id > from then
			table.insert(r,{id=v.id,line=v.line,type=v.type})
		end
	end
	return r
end

return Terminal
