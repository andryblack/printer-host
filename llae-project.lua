project 'printer-host'
-- @modules@
module 'llae'

--cmodule 'clipperlib'

premake{
	project = [[
	files{
		<%= format_file('src','*.cpp')%>,
		<%= format_file('src','*.h')%>,
	}
	]]
}
