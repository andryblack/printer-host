local class = require 'llae.class'

local PCB = class(nil,'printer.PCB')

local Parser = require 'gerber.parser'
local Bounds = require 'geom.bounds'
local SvgGenerator = require 'svg.generator'
local Geometry = require 'geom.geometry'
local GCodeGenerator = require 'gcode.generator'

PCB.root = application.config.files

local resolution = 10000

function PCB:_init(  )
	self:reset()
end

function PCB:reset(  )
	self._gerber = {}
	self._bounds = Bounds.new()
	local svg = SvgGenerator.new('10mm','10mm','0 0 10 10','pcb-svg')
	self._svg = svg:build()
	self._config = {
		outline_count = application.printer.settings.pcb_outline_count,
		outline_z = application.printer.settings.pcb_outline_z,
		outline_offset = application.printer.settings.pcb_outline_offset,
		outline_step = application.printer.settings.pcb_outline_step,
		fill_z = application.printer.settings.pcb_fill_z,
		fill_offset = application.printer.settings.pcb_fill_offset,
		fill_step = application.printer.settings.pcb_fill_step,
		fill_offset_x = application.printer.settings.pcb_fill_offset_x,
		fill_offset_y = application.printer.settings.pcb_fill_offset_y,
		position_x = 10.0,
		position_y = 10.0,
		move_speed = application.printer.settings.pcb_move_speed,
		outline_speed = application.printer.settings.pcb_outline_speed,
		fill_speed = application.printer.settings.pcb_fill_speed,
		fill_enable = false,
		backslash_x = application.printer.settings.pcb_backslash_x,
		backslash_y = application.printer.settings.pcb_backslash_y,
	}
	for k,v in pairs(self._config) do
		print('init settings:',k,v)
	end
end

function PCB:set_gerber_data( polygons )
	print('PVB set_gerber_data')
	self._gerber = polygons
	local bounds = Bounds.new()
	for _,v in ipairs(polygons) do
		bounds:extend_points(v)
	end
	self._bounds = bounds

	-- local top = bounds:y() + bounds:height()

	-- for _,c in ipairs(polygons) do
	-- 	for _,p in ipairs(c) do
	-- 		p[2] = top - p[2]
	-- 	end
	-- end

	self._polygons = polygons
	--self._config.position_x = (application.printer.settings.printer_width - bounds:width()) / 2 
	--self._config.position_y = (application.printer.settings.printer_height - bounds:height()) / 2 
	self:build_print()

end

function PCB:open_gerber( file )
	self:reset()

	self._filename = file
	print('open_gerber',file)

	local p = Parser.new()
	local f = assert(io.open(self.root .. '/' .. file))

	local state = application.printer:start_state('pcb_processing')
	local sself = self

	local coro = coroutine.create(function()
		local r,err = pcall(function()
			for l in f:lines() do
				p:parse(l)
			end
			f:close()
			p:finish()
			f = nil
			sself:set_gerber_data( p:polygons(1.0) )
			print('PCB processing complete')
			application.printer:end_state('pcb_processing',state)
		end)
		if f then
			f:close()
		end
		if not r then
			application.printer:end_state('pcb_processing',state)
			print('PCB processing error',err)
		end
		collectgarbage('collect')
	end)

	coroutine.resume(coro)

end

local function len(a,b)
	local dx = a[1]-b[1]
	local dy = a[2]-b[2]
	return dx*dx + dy*dy
end

local function sort_paths( paths )
	if #paths < 1 then
		return paths
	end
	local result = {paths[1]}
	table.remove(paths,1)
	local last = result[1][1]
	while (next(paths)) do
		local best = 1
		local best_len = len(last,paths[best][1])
		for i=2,#paths do
			local p = paths[i]
			local l = len(last,p[1])
			if l < best_len then
				best = i
				best_len = l
			end
		end
		local best_path = paths[best]
		table.insert(result,best_path)
		table.remove(paths,best)
		last = best_path[1]
	end
	return result
end

function PCB:build_print(  )
	print('PCB build_print')
	local bounds = self._bounds
	local polygons = self._polygons

	local svg = SvgGenerator.new(
		application.printer.settings.printer_width .. 'mm',
		application.printer.settings.printer_height .. 'mm',
		'0 0 '.. application.printer.settings.printer_width .. ' ' .. application.printer.settings.printer_height,
		'pcb-svg'
	)

	svg:child{'rect',x=0,y=0,
				width=application.printer.settings.printer_width,
				height=application.printer.settings.printer_height,
				style="fill:#aaaaaa"}

	local xpos = self._config.position_x - self._bounds:x()
	local ypos = self._config.position_y - self._bounds:y()
	local pcb = svg:child{'g',
		id="pcb-tr",
		transform='translate(' .. xpos .. ',' .. 
			(application.printer.settings.printer_height-ypos) .. ') scale(1,-1)' }

	pcb:child{
		'rect',
		id='pcb',
		x=self._bounds:x(),
		y=self._bounds:y(),
		width=math.abs(self._bounds:width()),
		height=math.abs(self._bounds:height()),
		style="fill:#ffff00",
	}


	pcb:draw_polygon(polygons,'stroke:none;fill:#00aa00;fill-rule:nonzero',application.printer.settings.printer_height)

	
	local geo = Geometry.import(polygons,resolution)
	local paths = {}
	for i=1,self._config.outline_count do
		local geo1 = geo
		geo1:buffer(-(i==1 and self._config.outline_offset or self._config.outline_step)*resolution)
		geo = geo1
		geo1:flush()
		for _,p in ipairs(geo1._g) do
			table.insert(paths,p:export(1.0/resolution))
		end
		pcb:draw_polygon(geo1:export(1.0/resolution),'stroke:#ff0000;stroke-width:'..(self._config.outline_step/2-0.01)..';fill:none;fill-rule:nonzero')
	end
	self._draw_paths = sort_paths(paths)


	local pass = 1
	paths = {}
	if self._config.fill_enable then
		while next(geo._g) do
			local geo1 = geo
			geo1:buffer(-(pass==1 and self._config.fill_offset or self._config.fill_step)*resolution)
			geo = geo1
			geo1:flush()
			for _,p in ipairs(geo1._g) do
				table.insert(paths,p:export(1.0/resolution))
			end
			pcb:draw_polygon(geo1:export(1.0/resolution),'stroke:#5555ff;stroke-width:'..(self._config.fill_step/2-0.01)..';fill:none;fill-rule:nonzero')
			pass = pass + 1
		end
	end
	self._fill_paths = sort_paths(paths)

	self._svg = svg:build()
	
	print('PCB build_print end')
end

function PCB:update( config )
	for k,v in pairs(config) do
		self._config[k] = v
		print('set config value:',k,v,type(v))
	end
	local sself = self
	local state = application.printer:start_state('pcb_processing')

	local coro = coroutine.create(function()
		local r,err = pcall(function()
			sself:build_print()
			print('PCB update complete')
			application.printer:end_state('pcb_processing',state)
		end)
		if not r then
			application.printer:end_state('pcb_processing',state)
			print('PCB update error',err)
		end
		collectgarbage('collect')
	end)

	coroutine.resume(coro)
end

function PCB:get_svg( )
	return self._svg
end

function PCB:get_config( )
	return self._config
end


function PCB:write_gcode( gen )
	local polygons = self._polygons

	local resolution = 10000
	gen:move(self._config.position_x,
		self._config.position_y,
		self._config.outline_z,
		self._config.move_speed)

	gen:writel('M3')

	local xpos = self._config.position_x - self._bounds:x()
	local ypos = self._config.position_y - self._bounds:y()

	local prev_pos_x = self._config.position_x
	local prev_pos_y = self._config.position_y

	local prev_dir_x = true
	local prev_dir_y = true

	local backslash_dx = 0
	local backslash_dy = 0

	local speed = nil 

	local function check_backslash( x, y )
		local dx = x - prev_pos_x
		local dy = y - prev_pos_y
		local changed = false
		if (dx ~= 0) then
			local dir_x = dx > 0
			if dir_x ~= prev_dir_x then
				backslash_dx = dir_x and self._config.backslash_x or -self._config.backslash_x
				changed = true
				prev_dir_x = dir_x
			end
		end
		if (dy ~= 0) then
			local dir_y = dy > 0
			if dir_y ~= prev_dir_y then
				backslash_dy = dir_y and self._config.backslash_y or -self._config.backslash_y
				changed = true
				prev_dir_y = dir_y
			end
		end
		if changed then
			gen:move(prev_pos_x+backslash_dx,prev_pos_y+backslash_dy,nil,
				self._config.move_speed)
			speed = self._config.move_speed
		end
	end
	
	local function move(x,y)
		check_backslash(x,y)
		local s = (not speed or speed ~= self._config.move_speed) and self._config.move_speed or nil
		gen:move(
						x + backslash_dx,
						y + backslash_dy,
						nil,
						s)
		prev_pos_x = x
		prev_pos_y = y
		speed = self._config.move_speed
	end

	local function draw(x,y)
		check_backslash(x,y)
		local s = (not speed or speed ~= self._config.outline_speed) and self._config.outline_speed or nil
		gen:draw(
						x + backslash_dx,
						y + backslash_dy,
						nil,
						s)
		prev_pos_x = x
		prev_pos_y = y
		speed = self._config.outline_speed
	end

	for _,r in ipairs(self._draw_paths) do
		if #r > 1 then
			
			for i,p in ipairs(r) do
				if i == 1 then
					move(
						xpos + r[1][1],
						ypos + r[1][2])
				else
					draw(
						xpos + p[1],
						ypos + p[2])
				end
			end
			draw(
					xpos + r[1][1],
					ypos + r[1][2])
		end
	end

	if next(self._fill_paths) then
		gen:move(self._config.position_x,
			self._config.position_y,
			self._config.fill_z,
			self._config.move_speed)

		xpos = xpos + self._config.fill_offset_x
		ypos = ypos + self._config.fill_offset_y
		
		for _,r in ipairs(self._fill_paths) do
			if #r > 1 then
				
				for i,p in ipairs(r) do
					if i == 1 then
						gen:move(
							xpos + p[1],
							ypos + p[2],
							nil,
							self._config.move_speed)
					else
						gen:draw(
							xpos + p[1],
							ypos + p[2],
							nil,
							i == 2 and self._config.fill_speed)
					end
				end
				gen:draw(
						xpos + r[1][1],
						ypos + r[1][2],
						nil,
						nil)
			end
		end
	end

	gen:writel('M5')

end

function PCB:prepare_print(  )
	local file =  self._filename .. '.gcode'
	local f = assert(io.open(self.root .. '/' .. file,'w'))
	if not f then
		return false
	end
	local gen = GCodeGenerator()
	function gen:writel( l )
		f:write(l..'\n')
	end
	gen:writel('G90')
	gen:writel('M452')
	gen:writel('G28')
	self:write_gcode(gen)
	f:close()
	return file
end

return PCB
