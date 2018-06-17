package = "clipperlib"
version = "0.1"
source = {
  dir = "clipperlib"
}
description = {
   summary = "A barebones router for Lua. It matches urls and executes lua functions",
   detailed = "Features: 1) Allows binding a method and a path to a function 2) Parses parameters like /app/services/:service_id 3) It's platform-agnostic. It has been tested with openresty.",
   homepage = "https://github.com/APItools/router.lua",
   license = "MIT"
}
dependencies = {
   "lua == 5.3"
}
build = {
   type = "cmake"
}
