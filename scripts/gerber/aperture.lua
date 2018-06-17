local class = require 'llae.class'

local Geometry = require 'geom.geometry'

local Aperture = class(nil,'gerber.Aperture')

local function parse_params( data )
	local r = {}
	for p in string.gmatch(data, '([%.%d]+)X?') do
		table.insert(r,tonumber(p))
	end
	return r
end 

function Aperture:_init(  )

end

function Aperture:draw_contour( canvas, contour )
	error('pure virtual aperture call')
end
function Aperture:flash( canvas, contour )
	error('pure virtual aperture call')
end


local ApertureCircle = class(Aperture,'gerber.ApertureCircle')

function ApertureCircle:_init( diameter, hole )
	self._diameter = diameter
	self._hole = hole
end

function ApertureCircle:draw_contour( canvas, contour )
	local g = contour:build_buffer(self._diameter)
	canvas:union(g)
	return canvas
end
function ApertureCircle:flash( canvas, x, y )
	--print('circle flash: ',x,y,self._diameter)
	local g = Geometry.new_circle(x,y,self._diameter / 2)
	--print(g:dump())
	canvas:union(g)
	return canvas
end


function Aperture.new_std_C( data , s)
	local p = parse_params(data)
	if not p[1] then
		error('C need diameter')
	end
	return ApertureCircle.new(p[1]*s,p[2] and p[2]*s)
end

local AperturePolygon = class(Aperture,'gerber.AperturePolygon')

function AperturePolygon:_init( diameter, vertices, rot, hole )
	self._diameter = diameter
	self._vertices = vertices
	self._rot = rot
	self._hole = hole
end
function AperturePolygon:draw_contour( canvas, contour )
	error('draw polygon not supported')
	return canvas
end

function AperturePolygon:flash( canvas, x , y )
	--print('circle flash: ',x,y,self._diameter)
	local g = Geometry.new_circle(x,y,self._diameter / 2,self._vertices,self._rot)
	--print(g:dump())
	canvas:union(g)
	return canvas
end

function Aperture.new_std_P( data , s)
	local p = parse_params(data)
	if not p[1] then
		error('P need Outer diameter')
	end
	if not p[2] then
		error('P need Number of vertices')
	end
	return AperturePolygon.new(p[1]*s,p[2],p[3],p[4] and p[4]*s)
end

local ApertureRectangle = class(Aperture,'gerber.ApertureRectangle')

function ApertureRectangle:_init( w,h , hole )
	self._w = w
	self._h = h
	self._hole = hole
end

function ApertureRectangle:draw_contour( canvas, contour )
	error('draw rectangle not supported')
	return canvas
end

function ApertureRectangle:flash( canvas, x, y )
	local w = self._w
	local h = self._h
	local g = Geometry.new_polygon{
		{x-w/2,y-h/2},
		{x+w/2,y-h/2},
		{x+w/2,y+h/2},
		{x-w/2,y+h/2},
		
	}
	canvas:union(g)
	return canvas
end


function Aperture.new_std_R( data , s)
	local p = parse_params(data)
	if not p[1] then
		error('P need X size')
	end
	if not p[2] then
		error('P need Y size')
	end
	return ApertureRectangle.new(p[1]*s,p[2]*s,p[3] and p[3]*s)
end

return Aperture
