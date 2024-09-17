local class = require 'llae.class'
local async = require 'llae.async'
local log = require 'llae.log'
local uv = require 'llae.uv'
local json = require 'llae.json'

local KlipperAPI = class(nil,'printer.KlipperAPI')



function KlipperAPI:_init(   )
	self._msg_id = 1
	self._connection = uv.pipe.new()
	self._data = ''
	self._scheduled = {}
end

function KlipperAPI:reset(  )
	self._current = nil
	self._scheduled = {}
	self._data = ''
	--self._event:notify()
end


function KlipperAPI:_on_read( ch )
	self._data = self._data .. tostring(ch)
	while #self._data > 0 do
		local delim = string.find(self._data,'\x03',1,true)
		if delim then
			local msg = self._data:sub(1,delim-1)
			self._data = self._data:sub(delim+1)
			self:_on_msg(msg)
		else
			break
		end
	end
end

function KlipperAPI:_on_msg( msg_data )
	local msg = json.parse(msg_data)
	if msg.id then
		for i,v in ipairs(self._scheduled) do
			if v.id == msg.id then
				local req = table.remove(self._scheduled,i)
				req.result = msg.result
				req.error = msg.error
				req.done = true
				if req.this then
					local d,err = coroutine.resume(req.this)
					if not d then
						log.error('failed resume request',err)
						error(err)
					end
				end
				return
			end
		end
	end
end

function KlipperAPI:_read_thread()
	local buf
	while self._opened do
		local ch,err = self._connection:read(buf)
		if not ch then
			if err then
				log.error('failed read',err)
			end
			break
		end
		self:_on_read(ch)
		buf = ch
	end
end

function KlipperAPI:open( api_path )
	self:close()
	local res,err = self._connection:connect( api_path )
	if res then
		self._opened = true
		async.run(function()
			self:_read_thread()
		end)
		return true
	else
		log.error('failed opening klipper API socket',self._config.klipper_api,err)
	end
end

function KlipperAPI:close(  )
	if self._opened then
		self._connection:shutdown()
	end
	self._opened = false
	self:reset()
	return true
end

function KlipperAPI:is_connected(  )
	return self._opened
end

function KlipperAPI:_send_request(req)
	if not self._opened then
		return nil,'not opened'
	end
	local req_data = json.encode(req)
	return self._connection:write(req_data .. '\x03')
end
function KlipperAPI:request(method,params)
	local req = {
		id = self._msg_id + 1,
		method = method,
		params = params
	}
	self._msg_id = req.id
	table.insert(self._scheduled,req)
	local res,err = self:_send_request(req)
	if not res then
		log.error('failed write request',err)
		return nil,err
	end
	req.this = coroutine.running()
	while not req.done do
		coroutine.yield()
	end
	return req.result,req.error and json.encode(req.error)
end

return KlipperAPI
