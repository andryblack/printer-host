local class = require 'llae.class'
local llae = require 'llae'
local gcode_parser = require 'gcode.parser'

local FakePrinter = class(nil,'printer.FakePrinter')

	
function FakePrinter:_init( delegate )
	self._delegate = delegate
	self._timer = llae.newTimer()
	
	self._scheduled = {}
	self._temp = {
		T = 25,
		B = 25
	}
	self._temp_t = {}
	for k,v in pairs(self._temp) do self._temp_t[k]=v end
end

function FakePrinter:schedule(  )
	self._timer:start(function()
		self:handle_timer()
	end,100,0)
end

function FakePrinter:start(  )

end

function FakePrinter:stop(  )
	self._timer:stop()
end

function FakePrinter:handle_timer(  )
	local d = table.remove(self._scheduled,1)
	if d then
		self._delegate:on_data(d)
	end
	if next(self._scheduled) then
		self:schedule()
	end
	for k,v in pairs(self._temp) do 
		local t= self._temp_t[k]
		if t > v then
			v = v + 1
		elseif t < v then
			v = v - 1
		end
		self._temp[k]=v
	end
end

function FakePrinter:add_response( data )
	table.insert(self._scheduled,data)
	if #self._scheduled == 1 then
		self:schedule()
	end
end

function FakePrinter:write( data )
	--print('FakePrinter:write',data)
	local n,c = string.match(data,'^N(%d+) (.+)')
	if n then
		self:add_response('ok ' .. n)
	end
	local cmd = gcode_parser.parse(c)
	if not cmd then
		return false,'failed parse'
	end
	if cmd.code == 'M105' then
		self:add_response('T:' .. tostring(self._temp.T) .. ' B:' .. tostring(self._temp.B))
	end
	if cmd.code == 'M104' then
		self._temp_t.T = tonumber(cmd.S)
		if self._temp_t.T < 25 then
			self._temp_t.T = 25
		end
	elseif cmd.code == 'M140' then
		self._temp_t.B = tonumber(cmd.S)
		if self._temp_t.B < 25 then
			self._temp_t.B = 25
		end
	end
	return true
end

return FakePrinter