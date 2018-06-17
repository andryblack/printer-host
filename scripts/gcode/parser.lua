local class = require 'llae.class'

local Parser = class(nil,'gcode.Parser')

function Parser.parse( line )
	local c,t = string.match(line,'^(%u%d+)%s*(.*)$')
	if not c then
		return nil
	end
	local comm = string.find(t,';',1,true)
	if comm then
		t = string.sub(t,comm-1)
	end
	local r = {
		cmd = c .. ' ' .. t,
		code = c
	}
	for k,v in string.gmatch(t, "(%u)(%d+)") do
       r[k]=v
    end
	return r
end

return Parser