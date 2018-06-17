#ifndef _LUACLIPPERLIB_H_INCLUDED_
#define _LUACLIPPERLIB_H_INCLUDED_

extern "C" {
#include <lua.h>
}

extern "C" int luaopen_clipperlib(lua_State* L);

#endif /*_LUACLIPPERLIB_H_INCLUDED_*/