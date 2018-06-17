local settings = {}

function settings.make_routes( server )
	
	server:post('/api/settings_add_list_element',function( request )
		local value_name = request.json.list_name
		print('add element for',value_name)
		application.printer.settings:item(value_name):add_item()
		request:write_json({status='ok'})
	end)
	server:post('/api/settings_remove_list_element',function( request )
		local value_name = request.json.list_name
		local idx = request.json.idx
		print('remove element for',value_name,idx)
		application.printer.settings:item(value_name):remove_item(idx)
		request:write_json({status='ok'})
	end)

end

return settings