local class = require 'llae.class'

local Source = class(nil,'gcode.Source')

function Source:_init(  )
	-- body
end

function Source:release(  )
	-- body
end

function Source:progress(  )
	return 0
end

function Source:get(  )
	return nil
end

return Source