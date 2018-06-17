local pcb = {}

function pcb:svg(  )
	return application.printer.pcb:get_svg()
end

function pcb:get_svg(  )
	return application.printer.pcb:get_svg()
end

function pcb:get_config(  )
	return application.printer.pcb:get_config()
end

function pcb:open_gerber( file )
	local res,err = pcall(function()
		application.printer.pcb:open_gerber(file)
	end)
	if res then
		print('gerber loaded')
		return {status='ok',redirect='/pcb'}
	end
	print('failed open gerber:', err)
	return {status='error',error=err}
end

function pcb:print(  )
	local res,err = pcall(function()
		local file = application.printer.pcb:prepare_print()
		if not file then
			error('failed prepare print')
		end
		assert(application.printer:print_file(file))
	end)
	if res then
		print('print started')
		return {status='ok',redirect='/home'}
	end
	print('failed print gerber:', err)
	return {status='error',error=err}
end


function pcb.make_routes( server )
	server:post('/api/open_gerber',function( request )
    	request:write_json(pcb:open_gerber(request.file))
	end)
	server:get('/api/pcb.svg',function( request )
    	request:write_data(application.printer.pcb:get_svg(),'image/svg+xml')
	end)
	server:post('/api/pcb/update',function( request )
		application.printer.pcb:update(request.json)
		request:write_json({status='ok'})
	end)
	server:post('/api/pcb/print',function( request )
		request:write_json(pcb:print())
	end)
end

return pcb