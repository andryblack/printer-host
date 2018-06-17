local class = require 'llae.class'

local File = class(require 'gcode.source','gcode.File')

function File:_init( f )
	local lines = 0
	for _ in f:lines() do
		lines = lines + 1
	end
	f:seek('set',0)
	if lines < 1 then
		lines = 1
	end
	self._total_lines = lines
	self._readed_lines = 0
	self._file = f
end

function File:get(  )
	self._readed_lines = self._readed_lines + 1
	return self._file:read()
end

function File:progress(  )
	return self._readed_lines / self._total_lines
end

function File:release(  )
	self._file:close()
end

function File.open( path )
	local f,err = io.open(path,'r')
	if f then
		return File.new(f)
	end
	return nil,err
end

return File