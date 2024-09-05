local class = require 'llae.class'

local Generator = class(nil,'printer.Generator')

local Bounds = require 'geom.bounds'
local SvgGenerator = require 'svg.generator'
--local Geometry = require 'geom.geometry'
local GCodeGenerator = require 'gcode.generator'

Generator.root = application.config.files

local resolution = 10000

function Generator:_init(  )
	self._filename = 'generator.lua'
	self:reset()
end

function Generator:reset(  )
	self._bounds = Bounds.new()
	local svg = SvgGenerator.new('10mm','10mm','0 0 10 10','generator-svg')
	self._svg = svg:build()
	self._script = [[
print('hello world')
printer:cmd('G90')
printer:cmd('M452')
printer:cmd('G28')
printer:move(10,10)
printer:draw(10,30)
printer:draw(30,30)
printer:draw(30,10)
printer:draw(10,10)
]]
	self._output = ''
	self:exec_script()
end

function Generator:open_script( file )
	self:reset()
	self._filename = file
	local f = io.open(self.root .. '/' .. self._filename,'r')
	self._script = f:read('a')
	f:close()
	self:exec_script()
end

function Generator:update( script )
	self._script = script
	local f = io.open(self.root .. '/' .. self._filename,'w')
	if not f then
		self._output = 'failed opening file ' .. self._filename
		return false
	end
	f:write(self._script)
	f:close()
	self:exec_script()
end

function Generator:get_svg( )
	return self._svg
end

function Generator:get_script( )
	return self._script
end

function Generator:get_output( )
	return self._output
end

function Generator:prepare_print(  )
	local file =  self._filename .. '.gcode'
	local f = assert(io.open(self.root .. '/' .. file,'w'))
	if not f then
		return false
	end
	f:write(self._gcode)
	f:close()
	return file
end

local GeneratorPrinter = class(nil,'printer.GeneratorPrinter')

function GeneratorPrinter:_init(  )
	self._gcode_gen = GCodeGenerator.new()
	self._svg = SvgGenerator.new(
		application.printer.settings.printer_width .. 'mm',
		application.printer.settings.printer_height .. 'mm',
		'0 0 '.. application.printer.settings.printer_width .. ' ' .. application.printer.settings.printer_height,
		'generator-svg')
	self._svg:child{'rect',x=0,y=0,
				width=application.printer.settings.printer_width,
				height=application.printer.settings.printer_height,
				style="fill:#aaaaaa"}
	self._gcode = {}
	self._move_speed = 100
	self._draw_speed = 100
	self._need_move_speed = true
	self._need_draw_speed = true
	self._last_pos = {x=0,y=0}
	

	local tr = self._svg:child{'g',
		id="generator-tr",
		transform='translate(' .. 0 .. ',' .. 
			(application.printer.settings.printer_height) .. ') scale(1,-1)'}

	self._moves = tr:child{'g',
		id="generator-moves",
		style='stroke:#444444;stroke-width:0.01' }
	self._draw = tr:child{'g',
		id="generator-draw",
		style='stroke:#ff0444;stroke-width:0.01' }

	local sself = self

	function self._gcode_gen:writel( l )
		table.insert(sself._gcode,l)
	end
	self._console = {}
end

function GeneratorPrinter:print( ... )
	table.insert(self._console,table.concat({...},'\t'))
end

function GeneratorPrinter:move_speed( s )
	self._move_speed = s
	self._need_move_speed = true
end

function GeneratorPrinter:draw_speed( s )
	self._draw_speed = s
	self._need_draw_speed = true
end

function GeneratorPrinter:cmd(l)
	self._gcode_gen:writel(l)
end
function GeneratorPrinter:move( x,y , z)
	self._gcode_gen:move(
						x,
						y,
						z,
						self._need_move_speed and self._move_speed)
	self._need_z = false
	self._moves:draw_line(
		self._last_pos.x,
		self._last_pos.y,
		x,y)
	self._last_pos.x = x or self._last_pos.x
	self._last_pos.y = y or self._last_pos.y
	self._need_move_speed = false
	self._need_draw_speed = true
end

function GeneratorPrinter:draw( x,y)
	self._gcode_gen:draw(
						x,
						y,
						nil,
						self._need_draw_speed and self._draw_speed)
	self._draw:draw_line(
		self._last_pos.x,
		self._last_pos.y,
		x,y)
	self._last_pos.x = x or self._last_pos.x
	self._last_pos.y = y or self._last_pos.y
	self._need_draw_speed = false
	self._need_move_speed = true
end

function Generator:exec_script(  )
	local printer = GeneratorPrinter.new()
	local env = {
		printer = printer,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		math = math,
		string = string,
		table = table,
	}
	env.print = function(...) printer:print(...) end
	local f,err = load(self._script,'script','t',env)
	if not f then
		printer:print(err)
	else
		local r,err = pcall(f)
		if not r then
			printer:print(err)
		end
	end
	self._gcode = table.concat(printer._gcode,'\n')
	self._svg = printer._svg:build()
	self._output = table.concat(printer._console,'\n')
end

return Generator
