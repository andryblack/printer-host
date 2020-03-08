local class = require 'llae.class'
local app = require 'app'

local flasher = class()

function flasher:_init( config )
	self._config = config
	self._timeout = 5
end


function flasher:connect()
	self._serial,err = app.openSerial(self._config.path);
	if not self._serial then
		print('failed open device',err)
		return false
	end
	self._serial:configure_baud(self._config.speed,true)
	if self._serial then
		self._serial:start_read(self.read_func,self) 
	end
	return self._serial
end

function flasher:close(  )
	if self._serial then
		self._serial:close()
	end
	return true
end

function flasher:is_connected(  )
	return self._serial
end

local function print_hex( data )
	local d = {}
	for i=1,#data do
		table.insert(d,string.format('%02x',string.unpack('<I1',data,i)))
	end
	return table.concat(d,',')
end

function flasher:read_func( data )
	self._rc = nil
	while true do
		local e,ch = self._serial:read()
		assert(not e,e)
		if not ch then
			break
		end
		
		print('>',print_hex(ch))
		self._rc = (self._rc or '') .. ch
		--
	end
	print('read complete')
end

function flasher:readb(  )
	local start = os.time()
	while not self._rc do
		coroutine.yield()
		if os.difftime(os.time(),start) > self._timeout then
			print('readb timeout')
			return nil
		end
	end
	local b = string.unpack('<I1',self._rc)
	self._rc = string.sub(self._rc,2)
	if #self._rc == 0 then
		self._rc = nil
	end
	return b
end

function flasher:delay( t )
	local start = os.time()
	while os.difftime(os.time(),start) < t do
		coroutine.yield()
	end
end

function flasher:readn( len )
	local d = {}
	for i=1,len do
		local b = self:readb()
		if not b then
			print('failed read ',i,'byte')
			return nil
		end
		table.insert(d,string.pack('<I1',b))
	end
	return table.concat(d,'')
end

function flasher:sync(  )
	self._rc = nil
	self._serial:write(string.pack('<I1',0x7f))
	while true do
		local res,val = self:wait_ask('sync')
		if res or 
			val == 0x1F -- nack
			then
			return true
		end
		self:delay(1.0)
		self._rc = nil
		self._serial:write(string.pack('<I1',0x7f))
	end
	return true
end

function flasher:wait_ask( info )
	local b = self:readb()
	if not b then
		print('timeout')
		return false,0
	end
	if b == 0x79 then
		return true
	end
	if b == 0x1F then
		print('NACK',info)		
		self._rc = nil
	else
		print('Unknown',string.format('%02x',b),info)
	end
	return false,b
end

function flasher:cmdGeneric( cmd )
	local d = string.pack('<I1I1',cmd,cmd ~ 0xff)
	self._serial:write( d )
	return self:wait_ask( string.format('0x%02x',cmd))
end

function flasher:sendPaket( data , why)
	local b = 0
	if #data == 1 then
		b = string.unpack('<I1',data,1) ~ 0xff
	else
		for i=1,#data do
			b = (b ~ string.unpack('<I1',data,i)) & 0xff
		end
	end
	data = data .. string.pack('<I1',b)
	self._serial:write( data )
	return self:wait_ask( why or 'packet')
end

function flasher:cmdGet(  )
	if self:cmdGeneric(0x00) then
		local len = self:readb()
		if not len then
			return false
		end
		local version = self:readb()
		if not version then
			return false
		end
		local data = self:readn(len)
		if not data then
			return false
		end
		for i=1,#data do
			if string.unpack('<I1',data,i) == 0x44 then
				self.extended_erase = true
			end
		end
		self:wait_ask('0x00 end')
		print('cmdGet:',len,version,print_hex(data))
		return version
	else
		return false
	end
end

function flasher:cmdGetID(  )
	if self:cmdGeneric(0x02) then
		local len = self:readb()
		if not len then
			return false
		end
		print('cmdGetID len:',len)
		local data = self:readn(len+1)
		if not data then
			return false
		end
		self:wait_ask('0x02 end')
		return string.unpack('>I2',data)
	else
		error('faled cmdGetID')
	end
end

function flasher:cmdWriteMemory( addr, data )
	print('cmdWriteMemory:',string.format('0x%08x',addr),#data)
	if self:cmdGeneric(0x31) then
       	if not self:sendPaket(string.pack('>I4',addr),'addr') then
			return false
		end
        local len = #data - 1
        if self:sendPaket(string.pack('>I1',len) .. 
        	data, 'data') then
        	return true
        end
    else
		error('faled cmdWriteMemory')
	end
end

function flasher:cmdReadMemory( addr , readlen)
	if self:cmdGeneric(0x11) then
       	if not self:sendPaket(string.pack('>I4',addr),'addr') then
			return false
		end
        local len = readlen - 1
        if not self:sendPaket(string.pack('>I1',len),params) then
        	return false
        end
        return self:readn( readlen )
    else
		error('faled cmdReadMemory')
	end
end

function flasher:cmdExtendedEraseMemory(  )
	if self:cmdGeneric(0x44) then
		local tmp = self._timeout
		self._timeout = 30
       	if self:sendPaket(string.pack('>I2',0xffff),'masserase') then
       		self._timeout = tmp
			return true
		end
		return false
    else
		error('faled cmdExtendedEraseMemory')
	end
end

function flasher:reboot( addr )
	if self:cmdGeneric(0x21) then
		if self:sendPaket(string.pack('>I4',addr),'addr') then
			return true
		end
	end
	return false
end

function flasher:writeMemory( data, addr )
	local len = #data
	local offset = 1
	while len > 256 do
		if not self:cmdWriteMemory(addr,string.sub(data,offset,offset+256-1)) then
			return false
		end
		offset = offset + 256
		addr = addr + 256
		len = len - 256
	end
	if len > 0 then
		if not self:cmdWriteMemory(addr,string.sub(data,offset,offset+len-1) .. string.rep(string.pack('>I1',0xff),256-len)) then
			return false
		end
	end
	return true
end

function flasher:readMemory( addr, len )
	local res = {}
	while len > 256 do
		local ch = self:cmdReadMemory(addr,256)
		if not ch then
			return false
		end
		offset = offset + 256
		addr = addr + 256
		len = len - 256
		table.insert(res,ch)
	end
	if len > 0 then
		local ch = self:cmdReadMemory(addr,len)
		if not ch then
			return false
		end
		table.insert(res,ch)
	end
	return table.concat(res,'')
end

function flasher:erase( addr )
	if self.extended_erase then
		return self:cmdExtendedEraseMemory()
	end
end

function flasher:flash(  data , addr )
	print('start sync')
	if not self:sync() then
		return false
	end
	print('synced')
	self:delay(1.0)
	local bootversion = self:cmdGet()
	while not bootversion do 
		self:delay(1.0)
		bootversion = self:cmdGet()
	end
	print('bootversion:',string.format('0x%02x',bootversion))
	self:delay(1.0)
	local id = self:cmdGetID()
	while not id do
		self:delay(1.0)
		id = self:cmdGetID()
	end
	print('id:',string.format('0x%04x',id))
	self:delay(1.0)

	print('erase')
	self:erase()
	print('erase done')
	self:delay(0.5)

	-- id = self:cmdGetID()
	-- while not id do
	-- 	self:delay(1.0)
	-- 	id = self:cmdGetID()
	-- end
	-- self:delay(1.0)

	print('start write')
	if self:writeMemory(data,addr) then
		print('write ok')
		self._error = 'write failed'
	else
		print('write failed')
	end
	self:delay(1.0)
	if not self._error then
		print('read')
		local validata = self:readMemory(addr,#data)
		if validata then
			if validata == data then
				print('writed ok')
			else
				print('validate failed')
				self._error = 'validate failed'
			end
		else
			self._error = 'failed read memory'
			print('failed read')
		end
	end
	self:delay(1.0)
	print('reboot')
	while not self:reboot( addr ) do
		self:delay(1.0)
	end
end

return flasher