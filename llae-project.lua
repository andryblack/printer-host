project 'printer-host'
-- @modules@
module 'llae'

--cmodule 'clipperlib'

config('llae','extern_main',true)

premake{
	project = [[
	files{
		<%= format_file('src','*.cpp')%>,
		<%= format_file('src','*.h')%>,
	}
	]]
}

