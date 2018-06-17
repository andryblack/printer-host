
DEPMODULES= \
	lua-resty-template\
	router\
	llae

PACKAGE=printer-host
PACKAGEBIN=printer-host
LOCALTREE=local

.PHONY: all src-distr

all: build

files:
		mkdir -p local/var/files

project: premake5.lua 
		premake5 gmake

build: project
		make -C build verbose=1

release: project
		make -C build config=release verbose=1

run: all files
		./bin/$(PACKAGEBIN) scripts/main.lua

$(LOCALTREE):
		mkdir -p $(LOCALTREE)


local-module-lua-resty-template:
		mkdir -p $(LOCALTREE)/share/$(PACKAGE)/lib/resty
		cp -r extlib/lua-resty-template/lib/resty/* $(LOCALTREE)/share/$(PACKAGE)/lib/resty

local-module-router:
		mkdir -p $(LOCALTREE)/share/$(PACKAGE)/lib
		cp -r extlib/router.lua/router.lua $(LOCALTREE)/share/$(PACKAGE)/lib/

local-module-llae:
		mkdir -p $(LOCALTREE)/share/$(PACKAGE)/lib/llae
		mkdir -p $(LOCALTREE)/share/$(PACKAGE)/lib/net
		mkdir -p $(LOCALTREE)/share/$(PACKAGE)/lib/db
		cp -r extlib/llae/scripts/llae/* $(LOCALTREE)/share/$(PACKAGE)/lib/llae
		cp -r extlib/llae/scripts/net/* $(LOCALTREE)/share/$(PACKAGE)/lib/net
		cp -r extlib/llae/scripts/db/* $(LOCALTREE)/share/$(PACKAGE)/lib/db


local-modules: $(LOCALTREE) $(patsubst %,local-module-%,$(DEPMODULES))

clean:
		rm -rf bin/*
		rm -rf build/*
		rm -rf lib/*



debian-distr:
		dpkg-buildpackage -b

		
debian-package:
		fakeroot debian/rules binary


		
