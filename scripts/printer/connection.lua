local class = require 'llae.class'

local Connection = class(nil,'printer.Connection')

local app = require 'app'

function Connection:_init( path  )
	self._path = path
end

function Connection:open( )
	return false
end

function Connection:close( )
	-- body
end

function Connection:configure_baud( baudrate )
	return true
end

function Connection:is_opened(  )
	return false
end

function Connection:write( data )
	-- body
end

local SerialConnection = class(Connection,'printer.SerialConnection')

function SerialConnection:_init( path , delegate)
	Connection._init(self,path)
	self._delegate = delegate
end

function SerialConnection:read_function(  )
	local data = ''
	while true do
		local e,ch = self._serial:read()
		assert(not e,e)
		if not ch then
			break
		end
		--print('>',ch)
		data = data .. ch
		while true do
			local l,t = string.match(data,'^([^\r\n]*)[\r\n]+(.*)$')
			if l then
				data = t
				self._delegate:on_data( l )
			else
				break
			end
		end
		--
	end
	print('read complete')
end

function SerialConnection:open(  )
	local err
	self._serial,err = app.openSerial(self._path);
	return self._serial
end

function SerialConnection:close( )
	if self._serial then
		self._serial:close()
	end
end

function SerialConnection:configure_baud( baudrate )
	self._serial:configure_baud(baudrate)
	if self._serial then
		self._serial:start_read(self.read_function,self) 
	end
	
	return true
end

function SerialConnection:is_opened(  )
	return self._serial
end

function SerialConnection:write( data )
	local r,err = pcall(self._serial.write,self._serial,data)
	if not r then
		print('failed write: ',err)
	end
	return r
end

local FakeConnection = class(Connection,'printer.FakeConnection')

local FakePrinter = require 'printer.fake_printer'

function FakeConnection:_init( path , delegate)
	Connection._init(self,path)
	self._delegate = delegate
	self._opened = false
	self._printer = FakePrinter.new(delegate)
end

function FakeConnection:open( )
	self._opened = true
	self._printer:start()
	return true
end

function FakeConnection:close( )
	self._opened = false
	self._printer:stop()
end

function FakeConnection:is_opened(  )
	return self._opened
end

function FakeConnection:write( data )
	return self._printer:write(data)
end



function Connection.create( path , delegate)
	if path == 'fake' then
		return FakeConnection.new(path,delegate)
	end
	return SerialConnection.new(path,delegate)
end

return Connection