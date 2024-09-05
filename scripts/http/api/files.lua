local files = {}
local fs = require 'llae.fs'
local log = require 'llae.log'
local lpath = require 'llae.path'

files.root = application.config.files

local icons_map = {
	gcode = 'layers',
    gbr = 'cpu',
    GTL = 'cpu',
    GBL = 'cpu',
    GBS = 'cpu',
    GTS = 'cpu',
    DRL = 'crosshair',
    xln = 'crosshair',
    GTO = 'lock',
    GKO = 'maximize',
    bin = 'hard-drive'
}

local actions_map = {
    gcode = {icon='play',action='open_gcode'},
    gbr = {icon='edit',action='open_gerber'},
    xln = {icon='edit',action='open_drill'},
    GTL = {icon='edit',action='open_gerber'},
    GBL = {icon='edit',action='open_gerber'},
    GTS = {icon='edit',action='open_gerber'},
    GBS = {icon='edit',action='open_gerber'},
    DRL = {icon='edit',action='open_drill'},
    GTO = {icon='edit',action='open_gerber'},
    GKO = {icon='edit',action='open_gerber'},
    bin = {icon='cpu',action='flash_firmware'}
}

function files:get_list( path )
	local dirs = {}
	local files = {}
	local folder = lpath.join(self.root , path )
    local files_list,err = fs.scandir(folder)
    log.info('scandir:',files_list,err,folder)
    if not files_list then
        error(err or 'failed scandir')
    end
	for _,file in ipairs(files_list) do
        local name = file.name
        if name:sub(1,1) ~= "." then
            local f = lpath.join(folder,name)
            log.info ("\t "..f)
            if file.isdir then
                table.insert(dirs,name)
            elseif file.isfile then
            	table.insert(files,file)
            end
        end
    end
    local res = {}
    table.sort(dirs)
    table.sort(files,function(a,b) return a.name < b.name end)
    for _,v in ipairs(dirs) do
    	table.insert(res,{
    		name = v,
    		dir = true
    		})
    end
    for _,v in ipairs(files) do
    	local ext = string.match(v.name,'.+%.(%w+)') or ''
    	table.insert(res,{
    		name = v.name,
    		ext = ext,
    		icon = icons_map[ext] or 'file',
            btn = actions_map[ext]
    	})
    end
    return res
end

function files:mkdir( path )
	local res,err = fs.mkdir(lpath.join(self.root, path))
	if res then
		return {
			status = 'ok',
			path = path
		}
	else
		return {
			status = 'error',
			path = path,
			error = err
		}
	end
end

function files:remove( path )
    local res,err = fs.unlink(lpath.join(self.root ,path))
    if res then
        return {
            status = 'ok',
            path = path
        }
    else
        return {
            status = 'error',
            path = path,
            error = err
        }
    end
end


function files:upload( req )

    if not req.multipart then
        return {
            status = 'error',
            error = 'need multipart'
        }
    end

    local file_part
    local path_part

    for _,v in ipairs(req.multipart) do
        log.info('data:',v.name,v.filename,#v.data)
        if v.name == 'file' then
            file_part = v
            log.info('found file:',v.filename)
        elseif v.name == 'path' then
            path_part = v
            log.info('found path:',v.data)
        end
    end

    if not file_part then
        return {
            status = 'error',
            error = 'need file'
        }
    end
    if not path_part then
        return {
            status = 'error',
            error = 'need path'
        }
    end
  
    fs.write_file(lpath.join(self.root , path_part.data , file_part.filename), file_part.data)

    return {
        status = 'ok',
        name = file_part.filename
    }
end


function files.make_routes( server )
    server:get('/api/files',function( request , res )
        res:json(files:get_list(request.query.path))
    end)
    server:post('/api/mkdir',function( request, res )
        res:json(files:mkdir(request.query.path))
    end)
    server:post('/api/upload',function( request, res )
        res:json(files:upload(request))
    end)
    server:post('/api/remove',function( request , res)
        res:json(files:remove(request.query.file))
    end)

    server:get('/files/:files_path',function( req, res )
        log.info('req',req.params.files_path)
        return res:render('layout',{
                route = 'files',
                json = require 'llae.json',
                sidebar = server.sidebar,
                sidebar_active = 'files',
                content = 'files',
                printer = application.printer,
                path = req.params.files_path,
                printer_state = server._printer_api:get_state(),
            })
    end)
end

return files
