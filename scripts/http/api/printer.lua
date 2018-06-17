local printer = {}

printer.pcb = require 'http.api.pcb'
printer.generator = require 'http.api.generator'

function printer:get_terminal_log( from )
	return application.printer.terminal:get_log( from or 0)
end

function printer:get_state(  )
	return application.printer:get_state()
end

function printer:send_cmd( cmd )
	local res,err = application.printer:send_cmd(cmd)
	if res then
		return {
			status = 'ok'
		}
	else
		return {
			status = 'error',
			error = err
		}
	end
end

function printer:disconnect( )
	application.printer:disconnect()
	return self:get_state()
end

function printer:connect( )
	application.printer:connect()
	return self:get_state()
end

function printer:pause( )
	application.printer:pause()
	return self:get_state()
end

function printer:resume( )
	application.printer:resume()
	return self:get_state()
end

function printer:stop( )
	application.printer:print_stop()
	return self:get_state()
end

function printer:action( action , data )
	application.printer:action(action,data)
	return self:get_state()
end

function printer:get_temperature_elements(  )
	return application.printer:get_temperature_elements()
end

function printer:get_temperature_history( )
	return application.printer:get_temperature_history()
end

function printer:get_temperature_history_max_length(  )
	return application.printer:get_temperature_history_max_length();
end

function printer:open_gcode( file )
	local r,err = application.printer:print_file(file)
	if r then
		return {redirect='/home',status='ok'}
	end
	return {status='error',error=err}
end

function printer:flash_firmware( file )
	local r,err = application.printer:flash_file(file)
	if r then
		return {redirect='/home',status='ok'}
	end
	return {status='error',error=err}
end


function printer.make_routes( server )
	local printer_api = server.printer_api

	server:get('/api/state',function( request )
		request:write_json(printer_api:get_state())
	end)

	 server:get('/api/terminal',function( request )
	    request:write_json(printer_api:get_terminal_log(tonumber(request.from)))
	end)
	server:post('/api/terminal/send',function( request )
	    request:write_json(printer_api:send_cmd(request.json.cmd))
	end)

	server:post('/api/disconnect',function( request )
	    request:write_json(printer_api:disconnect())
	end)
	server:post('/api/connect',function( request )
	    request:write_json(printer_api:connect())
	end)
	server:post('/api/pause',function( request )
	    request:write_json(printer_api:pause())
	end)
	server:post('/api/resume',function( request )
	    request:write_json(printer_api:resume())
	end)
	server:post('/api/stop',function( request )
	    request:write_json(printer_api:stop())
	end)
	server:post('/api/open_gcode',function( request )
	    request:write_json(printer_api:open_gcode(request.file))
	end)
	server:post('/api/flash_firmware',function( request )
	    request:write_json(printer_api:flash_firmware(request.file))
	end)
	server:post('/api/action',function( request )
	    request:write_json(printer_api:action(request.json.action,request.json.data))
	end)
end

return printer