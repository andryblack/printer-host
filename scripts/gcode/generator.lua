local class = require 'llae.class'

local Generator = class(nil,'gcode.Generator')

function Generator:_init(  )
	self._position = {
		x = 0,
		y = 0,
		z = 0
	}
	self._speed = 100.0
end

function Generator:writel( l )
	print(l)
end


function Generator:release(  )

end

local noarg = 'noarg'
local function f( n , v )
	if not v then
		return noarg
	end
	return n .. string.format('%0.4f',v)
end

local function fmt( code, ... )
	local r = {code}
	for _,v in ipairs({...}) do
		if v ~= noarg then
			table.insert(r,v)
		end
	end
	return table.concat(r,' ')
end

function Generator:move( x , y, z , s)
	self:writel( fmt('G0',f('X',x),f('Y',y),f('Z',z),f('F',s) ))
	self._position.x = x or self._position.x
	self._position.y = y or self._position.y
	self._position.z = z or self._position.z
	self._speed = speed or self._speed
end

function Generator:draw( x , y, z , s )
	self:writel( fmt('G1',f('X',x),f('Y',y),f('Z',z),f('F',s) ))
	self._position.x = x or self._position.x
	self._position.y = y or self._position.y
	self._position.z = z or self._position.z
	self._speed = speed or self._speed
end

return Generator