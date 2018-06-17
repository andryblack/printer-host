#include "luaclipperlib.h"
#include "clipper.h"
#include "clipper_offset.h"

extern "C" {
#include <lauxlib.h>
#include <lualib.h>
}

#ifndef CLIPPERLIB_MODNAME
#define CLIPPERLIB_MODNAME   "clipperlib"
#endif

#ifndef CLIPPERLIB_VERSION
#define CLIPPERLIB_VERSION   CLIPPER_VERSION
#endif

static const char* Path_mt = "clipperlib.Path";

static int path_new(lua_State* L) {
	clipperlib::Path* r = new (lua_newuserdata(L,sizeof(clipperlib::Path))) clipperlib::Path();
	luaL_setmetatable(L,Path_mt);
	return 1;
}

static int path_free(lua_State* L) {
	clipperlib::Path* r = static_cast<clipperlib::Path*>(luaL_checkudata(L,1,Path_mt));
	r->~vector();
	return 0;
}

static int path_clear(lua_State* L) {
	clipperlib::Path* r = static_cast<clipperlib::Path*>(luaL_checkudata(L,1,Path_mt));
	r->clear();
	return 0;
}

static int path_add_point(lua_State* L) {
	clipperlib::Path* p = static_cast<clipperlib::Path*>(luaL_checkudata(L,1,Path_mt));
	lua_Integer x = luaL_checkinteger(L,2);
	lua_Integer y = luaL_checkinteger(L,3);
	p->push_back(clipperlib::Point64(x,y));
	return 0;
}

static int path_size(lua_State* L) {
	clipperlib::Path* p = static_cast<clipperlib::Path*>(luaL_checkudata(L,1,Path_mt));
	lua_pushinteger(L,p->size());
	return 1;
}

static int path_get_point(lua_State* L) {
	clipperlib::Path* p = static_cast<clipperlib::Path*>(luaL_checkudata(L,1,Path_mt));
	lua_Integer idx = luaL_checkinteger(L,2);
	if (idx < 0 || idx >= p->size()) {
		luaL_error(L,"invalid index %d (size:%d)",idx,lua_Integer(p->size()));
	}
	const clipperlib::Point64& pnt(p->at(idx));
	lua_pushinteger(L,pnt.x);
	lua_pushinteger(L,pnt.y);
	return 2;
}

static int path_import(lua_State* L) {
	luaL_checktype(L,1,LUA_TTABLE);
	lua_Integer plen = luaL_len(L,1);
	lua_Number scale = luaL_optnumber(L,2,1.0);
	clipperlib::Path* r = new (lua_newuserdata(L,sizeof(clipperlib::Path))) clipperlib::Path();
	luaL_setmetatable(L,Path_mt);
	for (lua_Integer i=1;i<=plen;++i) {
		lua_geti(L,1,i);
		luaL_checktype(L,-1,LUA_TTABLE);
		lua_geti(L,-1,1);
		lua_geti(L,-2,2);
		lua_Number x = lua_tonumber(L,-2);
		lua_Number y = lua_tonumber(L,-1);
		lua_pop(L,3);
		r->push_back(clipperlib::Point64(x*scale,y*scale));
	}
	return 1;
}

static inline const int64_t sq_len(const clipperlib::Point64& a, const clipperlib::Point64& b) {
	int64_t dx = a.x - b.x;
	int64_t dy = a.y - b.y;
	return dx * dx + dy * dy;
}

static int path_nearest_point(lua_State* L) {
	const clipperlib::Path& p(*static_cast<clipperlib::Path*>(luaL_checkudata(L,1,Path_mt)));
	lua_Integer x = luaL_checkinteger(L,2);
	lua_Integer y = luaL_checkinteger(L,3);
	size_t size = p.size();
	if (size == 0) {
		luaL_error(L,"path is empty");
	}
	clipperlib::Point64 pnt(x,y);

	int64_t min_len = sq_len(pnt,p[0]);
	size_t min_idx = 0;
	for (size_t i=1;i<size;++i) {
		int64_t sl = sq_len(pnt,p[i]);
		if (sl < min_len) {
			min_len = sl;
			min_idx = i;
		}
	}
	lua_pushinteger(L,min_idx);
	lua_pushinteger(L,min_len);
	return 2;
}

static int path_export(lua_State* L) {
	clipperlib::Path* p = static_cast<clipperlib::Path*>(luaL_checkudata(L,1,Path_mt));
	lua_Number s = luaL_optnumber(L,2,1.0);
	lua_createtable(L,p->size(),0);
	lua_Integer i = 1;
	for (clipperlib::Path::const_iterator it=p->begin();it!=p->end();++it) {
		lua_createtable(L,2,0);
		lua_pushnumber(L,it->x*s);
		lua_seti(L,-2,1);
		lua_pushnumber(L,it->y*s);
		lua_seti(L,-2,2);
		lua_seti(L,-2,i);
		++i;
	}
	return 1;
}

static void lua_pushPaths(lua_State* L, clipperlib::Paths& paths) {
	lua_createtable(L,paths.size(),0);
	lua_Integer i = 1;
	for (clipperlib::Paths::iterator it = paths.begin();it!=paths.end();++it) {
		clipperlib::Path& p(*it);
		clipperlib::Path* r = new (lua_newuserdata(L,sizeof(clipperlib::Path))) clipperlib::Path();
		r->swap(p);
		luaL_setmetatable(L,Path_mt);
		lua_seti(L,-2,i);
		++i;
	}
}

static const char* Clipper_mt = "clipperlib.Clipper";

static int clipper_new(lua_State* L) {
	clipperlib::Clipper* cl = new (lua_newuserdata(L,sizeof(clipperlib::Clipper))) clipperlib::Clipper();
	luaL_setmetatable(L,Clipper_mt);
	return 1;
}
static int clipper_free(lua_State* L) {
	clipperlib::Clipper* cl = static_cast<clipperlib::Clipper*>(luaL_checkudata(L,1,Clipper_mt));
	cl->~Clipper();
	return 0;
}
static int clipper_clear(lua_State* L) {
	clipperlib::Clipper* cl = static_cast<clipperlib::Clipper*>(luaL_checkudata(L,1,Clipper_mt));
	cl->Clear();
	return 0;
}
static int clipper_add_path(lua_State* L) {
	clipperlib::Clipper* cl = static_cast<clipperlib::Clipper*>(luaL_checkudata(L,1,Clipper_mt));
	clipperlib::Path* path = static_cast<clipperlib::Path*>(luaL_checkudata(L,2,Path_mt));
	clipperlib::PathType polytype = static_cast<clipperlib::PathType>(luaL_checkinteger(L,3));
	bool is_open = lua_toboolean(L,4);
	cl->AddPath(*path,polytype,is_open);
	return 0;
}

static int clipper_add_paths(lua_State* L) {
	clipperlib::Clipper* cl = static_cast<clipperlib::Clipper*>(luaL_checkudata(L,1,Clipper_mt));
	luaL_checktype(L,2,LUA_TTABLE);
	clipperlib::PathType polytype = static_cast<clipperlib::PathType>(luaL_checkinteger(L,3));
	bool is_open = lua_toboolean(L,4);
	lua_Integer plen = luaL_len(L,2);
	for (lua_Integer p=1;p<=plen;++p) {
		lua_geti(L,2,p);
		clipperlib::Path* path = static_cast<clipperlib::Path*>(luaL_checkudata(L,-1,Path_mt));
		cl->AddPath(*path,polytype,is_open);
		lua_pop(L,1);
	}
	return 0;
}

static int clipper_execute(lua_State* L) {
	clipperlib::Clipper* cl = static_cast<clipperlib::Clipper*>(luaL_checkudata(L,1,Clipper_mt));
	clipperlib::ClipType clipType = static_cast<clipperlib::ClipType>(luaL_checkinteger(L,2));
	clipperlib::Paths solution_closed;
	clipperlib::Paths solution_open;
	clipperlib::FillRule fr = static_cast<clipperlib::FillRule>(luaL_checkinteger(L,3));
	bool res = cl->Execute(clipType,solution_closed,solution_open,fr);
	lua_pushboolean(L,res ? 1 : 0);
	if (res) {
		lua_pushPaths(L,solution_closed);
		lua_pushPaths(L,solution_open);
		return 3; 
	}
	return 1;
}

static const char* ClipperOffset_mt = "clipperlib.ClipperOffset";

static int clipperoffset_new(lua_State* L) {
	lua_Number miter_limit = luaL_optnumber(L,1,2.0);
	lua_Number arc_tolerance = luaL_optnumber(L,2,0.0);
	
	clipperlib::ClipperOffset* co 
		= new (lua_newuserdata(L,sizeof(clipperlib::ClipperOffset))) 
			clipperlib::ClipperOffset(miter_limit,arc_tolerance);
	luaL_setmetatable(L,ClipperOffset_mt);
	return 1;
}
static int clipperoffset_free(lua_State* L) {
	clipperlib::ClipperOffset* co = static_cast<clipperlib::ClipperOffset*>(luaL_checkudata(L,1,ClipperOffset_mt));
	co->~ClipperOffset();
	return 0;
}
static int clipperoffset_clear(lua_State* L) {
	clipperlib::ClipperOffset* co = static_cast<clipperlib::ClipperOffset*>(luaL_checkudata(L,1,ClipperOffset_mt));
	co->Clear();
	return 0;
}
static int clipperoffset_add_path(lua_State* L) {
	clipperlib::ClipperOffset* co = static_cast<clipperlib::ClipperOffset*>(luaL_checkudata(L,1,ClipperOffset_mt));
	clipperlib::Path* path = static_cast<clipperlib::Path*>(luaL_checkudata(L,2,Path_mt));
	clipperlib::JoinType jt = static_cast<clipperlib::JoinType>(luaL_checkinteger(L,3));
	clipperlib::EndType et = static_cast<clipperlib::EndType>(luaL_checkinteger(L,4));
	co->AddPath(*path,jt,et);
	return 0;
}
static int clipperoffset_add_paths(lua_State* L) {
	clipperlib::ClipperOffset* co = static_cast<clipperlib::ClipperOffset*>(luaL_checkudata(L,1,ClipperOffset_mt));
	luaL_checktype(L,2,LUA_TTABLE);
	clipperlib::JoinType jt = static_cast<clipperlib::JoinType>(luaL_checkinteger(L,3));
	clipperlib::EndType et = static_cast<clipperlib::EndType>(luaL_checkinteger(L,4));
	lua_Integer plen = luaL_len(L,2);
	for (lua_Integer p=1;p<=plen;++p) {
		lua_geti(L,2,p);
		clipperlib::Path* path = static_cast<clipperlib::Path*>(luaL_checkudata(L,-1,Path_mt));
		co->AddPath(*path,jt,et);
		lua_pop(L,1);
	}
	return 0;
}
static int clipperoffset_execute(lua_State* L) {
	clipperlib::ClipperOffset* co = static_cast<clipperlib::ClipperOffset*>(luaL_checkudata(L,1,ClipperOffset_mt));
	lua_Number delta = luaL_checknumber(L,2);
	clipperlib::Paths sol;
	co->Execute(sol,delta);
	lua_pushPaths(L,sol);
	return 1;
}

static int lua_clipperlib_new(lua_State *L) {
	lua_newtable(L);

	luaL_newmetatable(L,Path_mt);
	luaL_Reg Path_f[] = {
        { "new",        	path_new },
        { "clear",			path_clear },
        { "size",			path_size },
        { "add_point",		path_add_point },
        { "get_point",		path_get_point },
        { "import",			path_import },
        { "export",			path_export },
        { "nearest_point",	path_nearest_point },
        { "__gc",        	path_free },
       	{ NULL, NULL }
    };
	luaL_setfuncs(L, Path_f, 0);
    lua_pushvalue(L,-1);
    lua_setfield(L,-2,"__index");
    lua_setfield(L,-2,"Path");

	luaL_newmetatable(L,Clipper_mt);
	luaL_Reg Clipper_f[] = {
        { "new",        	clipper_new },
        { "clear",			clipper_clear },
        { "add_path",		clipper_add_path },
        { "add_paths",		clipper_add_paths },
        { "execute",		clipper_execute },
        { "__gc",        	clipper_free },
       	{ NULL, NULL }
    };
   	luaL_setfuncs(L, Clipper_f, 0);
    lua_pushvalue(L,-1);
    lua_setfield(L,-2,"__index");
    lua_setfield(L,-2,"Clipper");

    luaL_newmetatable(L,ClipperOffset_mt);
	luaL_Reg ClipperOffset_f[] = {
        { "new",        	clipperoffset_new },
        { "clear",			clipperoffset_clear },
        { "add_path",		clipperoffset_add_path },
        { "add_paths",		clipperoffset_add_paths },
        { "execute",		clipperoffset_execute },
        { "__gc",        	clipperoffset_free },
       	{ NULL, NULL }
    };
   	luaL_setfuncs(L, ClipperOffset_f, 0);
    lua_pushvalue(L,-1);
    lua_setfield(L,-2,"__index");
    lua_setfield(L,-2,"ClipperOffset");

    lua_newtable(L);
    lua_pushinteger(L,clipperlib::ctNone);
    lua_setfield(L,-2,"None");
    lua_pushinteger(L,clipperlib::ctIntersection);
    lua_setfield(L,-2,"Intersection");
    lua_pushinteger(L,clipperlib::ctUnion);
    lua_setfield(L,-2,"Union");
    lua_pushinteger(L,clipperlib::ctDifference);
    lua_setfield(L,-2,"Difference");
    lua_pushinteger(L,clipperlib::ctXor);
    lua_setfield(L,-2,"Xor");
    lua_setfield(L,-2,"ClipType");

    lua_newtable(L);
    lua_pushinteger(L,clipperlib::ptSubject);
    lua_setfield(L,-2,"Subject");
    lua_pushinteger(L,clipperlib::ptClip);
    lua_setfield(L,-2,"Clip");
    lua_setfield(L,-2,"PathType");

    lua_newtable(L);
    lua_pushinteger(L,clipperlib::frEvenOdd);
    lua_setfield(L,-2,"EvenOdd");
    lua_pushinteger(L,clipperlib::frNonZero);
    lua_setfield(L,-2,"NonZero");
    lua_pushinteger(L,clipperlib::frPositive);
    lua_setfield(L,-2,"Positive");
    lua_pushinteger(L,clipperlib::frNegative);
    lua_setfield(L,-2,"Negative");
    lua_setfield(L,-2,"FillRule");

    lua_newtable(L);
    lua_pushinteger(L,clipperlib::kSquare);
    lua_setfield(L,-2,"Square");
    lua_pushinteger(L,clipperlib::kRound);
    lua_setfield(L,-2,"Round");
    lua_pushinteger(L,clipperlib::kMiter);
    lua_setfield(L,-2,"Miter");
    lua_setfield(L,-2,"JoinType");

    lua_newtable(L);
    lua_pushinteger(L,clipperlib::kPolygon);
    lua_setfield(L,-2,"Polygon");
    lua_pushinteger(L,clipperlib::kOpenJoined);
    lua_setfield(L,-2,"OpenJoined");
    lua_pushinteger(L,clipperlib::kOpenButt);
    lua_setfield(L,-2,"OpenButt");
    lua_pushinteger(L,clipperlib::kOpenSquare);
    lua_setfield(L,-2,"OpenSquare");
    lua_pushinteger(L,clipperlib::kOpenRound);
    lua_setfield(L,-2,"OpenRound");
    lua_setfield(L,-2,"EndType");

	/* Set module name / version fields */
    lua_pushliteral(L, CLIPPERLIB_MODNAME);
    lua_setfield(L, -2, "_NAME");
    lua_pushliteral(L, CLIPPERLIB_VERSION);
    lua_setfield(L, -2, "_VERSION");
    return 1;
}

extern "C" int luaopen_clipperlib(lua_State* L) {
	lua_clipperlib_new(L);
	return 1;
}