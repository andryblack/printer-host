
local llae = require 'extlib/llae/premake/llae'
llae.root = 'extlib/llae'

solution 'printer-host'
	configurations { 'debug', 'release' }
	language 'c++'
	objdir 'build' 
	location 'build'
	targetdir 'bin'
	cppdialect "C++11"

	configuration{ 'debug'}
		symbols "On"
	configuration{ 'release'}
		optimize "On"
	configuration{}

	llae.lib()

	project 'clipperlib'
		kind 'StaticLib'
		targetdir 'lib'
		buildoptions{ 
			llae.pkgconfig('lua-5.3','cflags'),
		}
		linkoptions { 
			llae.pkgconfig('lua-5.3','libs'),
		}
		files {
			path.join('src/clipperlib','clipper*.cpp'),
			path.join('src/clipperlib','clipper*.h')
		}

	project 'printer-host'
		kind 'ConsoleApp'
		includedirs {
			'src',
			'extlib/llae/src'
		}
		llae.link()
		buildoptions{ 
			llae.pkgconfig('lua-5.3','cflags'),
			llae.pkgconfig('libuv','cflags'),
		}
		
		links {
			'clipperlib',
		}
		files {
			'src/serial.*',
			'src/main.cpp',
			'src/clipper_uv.cpp',
			'src/*.h',
		}
	
