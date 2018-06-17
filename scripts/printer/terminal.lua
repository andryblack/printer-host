local class = require 'llae.class'

local Connection = require 'printer.connection'
local Terminal = class(nil,'printer.Terminal')

function Terminal:_init(  delegate )
	self._history = {}
	self._line_id = 1
	self._send_line = 1
	self._max_history = 50
	self._scheduled = {}
	self._delegate = delegate
end

function Terminal:reset(  )
	self._current = nil
	self._scheduled = {}
end

function Terminal:init( config )
	self._config = config
	return self:open()
end

function Terminal:open(  )
	self._connection = Connection.create(self._config.path,self)
	if self._connection:open() then
		if self._connection:configure_baud(self._config.speed) then
			self:on_opened()
			return true
		else
			print('failed configure serial device speed')
		end
	else
		print('failed opening serial device',self._config.path)
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
		print('wait')
		return
	end
	print('rx:',data)
	self:add_history{
		type = 'rx',
		line = data,
		resp = self._current or self._last
	}
	
	
	local err = string.match(data,'^Error:(.+)$')
	if err then
		self:on_error_response(err);
	end

	local line = string.match(data,'^Resend:(%d+)$')
	if line then
		self._send_line = tonumber(line)
	else
		line = string.match(data,'^ok%s(%d+)$')
		if line then
			self:on_ok_response(tonumber(line))
		end
		line = string.match(data,'^skip%s(%d+)$')
		if line then
			self:on_skip_response(tonumber(line))
		end
		if data == 'ok' and self._current then
			self:on_ok_response(self._current.line)
		end
	end
	if self._delegate and not line and not err then
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
		print('tx:',data)
		self:add_history{
			type = 'tx',
			line = data,
			cmd = cmd
		}
		return true
	else
		print('failed wtite cmd',cmd)
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
			print('different line ok',self._config.line,line)
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
			print('different line ok',self._config.line,line)
		end
	end
end

function Terminal:on_error_response( err )
	if self._current then
		print('rx error: ',err)
		self._current.error = err
	end
end

function Terminal:do_next_command()
	if next(self._scheduled) then
		local cmd = table.remove(self._scheduled,1)
		if not self:do_send_cmd(cmd) then
			table.insert(self._scheduled,1,cmd)
		end
	end
end

function Terminal:send_gcode( cmd )
	if not self._connection or not self._connection:is_opened() then
		return nil,'serial connection closed'
	end
	if self._current then
		print('busy, scheduled',data)
		table.insert(self._scheduled,cmd)
	else
		if not self:do_send_cmd(cmd) then
			table.insert(self._scheduled,1,cmd)
		end
	end
	return true
end

function Terminal:process( )
	if self._current then
		self._current.timeout = (self._current.timeout or 0) + 1
		if self._current.timeout > 10 then
			print('cmd timeout')
			self:on_error_response( 'timeout' )
		end
	end

	if self._current and self._current.error then
		self:add_history{
			type = 'err',
			line = error,
			cmd = self._current
		}
		self._last = self._current
		self._current = nil
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
