local generator = {}

function generator:svg(  )
	return application.printer.generator:get_svg()
end

function generator:get_svg(  )
	return application.printer.generator:get_svg()
end
function generator:get_script(  )
	return application.printer.generator:get_script()
end
function generator:get_output( )
	return application.printer.generator:get_output()
end

function generator:open_script( file )
	local res,err = pcall(function()
		application.printer.generator:open_script(file)
	end)
	if res then
		print('script loaded')
		return {status='ok',redirect='/generator'}
	end
	print('failed open gerber:', err)
	return {status='error',error=err}
end

function generator:print(  )
	local res,err = pcall(function()
		local file = application.printer.generator:prepare_print()
		if not file then
			error('failed prepare print')
		end
		assert(application.printer:print_file(file))
	end)
	if res then
		print('print started')
		return {status='ok',redirect='/home'}
	end
	print('failed print generator:', err)
	return {status='error',error=err}
end


function generator.make_routes( server )
	server:post('/api/open_script',function( request )
    	request:write_json(generator:open_script(request.file))
	end)
	server:get('/api/generator.svg',function( request )
    	request:write_data(application.printer.generator:get_svg(),'image/svg+xml')
	end)
	server:post('/api/generator/update',function( request )
		application.printer.generator:update(request:read_body())
		request:write_json({status='ok'})
	end)
	server:post('/api/generator/print',function( request )
		request:write_json(generator:print())
	end)
end

return generator