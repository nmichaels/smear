TARGETBITS=64
TARGET_ARCH_CFLAG_64=-m64
TARGET_ARCH_CFLAG=$(TARGET_ARCH_CFLAG_$(TARGETBITS))
TARGET_ARCH_LDFLAG=$(TARGET_ARCH_LDFLAG_$(TARGETBITS))

CPU_PLAT_RAW=$(shell $(CC) -dumpmachine)
CPU_RAW=$(shell $(CC) $(TARGET_ARCH_CFLAG) -Q --help=target | grep march | head -n 1 | awk '{print $$2}')
CPU_x86_64=amd64
CPU_x86-64=amd64
CPU_nocona=amd64
CPU_i386=i386
CPU_i686=i386
TARGET_CPU=$(CPU_$(CPU_RAW))
PLAT_RAW=$(shell echo "$(CPU_PLAT_RAW)" | cut -d "-" -f 2,3)
PLAT_unknown-linux=linux
PLAT_linux-gnu=linux
PLAT_unknown-mingw32=windows
PLAT_w64-mingw32=windows
TARGET_PLATFORM=$(PLAT_$(PLAT_RAW))

ifeq ($(OS),Windows_NT)
PKGEXT=zip
else
PKGEXT=tgz deb
endif

OBJDIR := obj
SRCDIR := src
LIBS :=
SRC := $(wildcard src/*.zig)
CSMEAR_O := obj/smear.o
CSMEAR_C := gen/smear.c
CC ?= gcc
OBJDUMP ?= objdump
OBJCOPY ?= objcopy
INCLUDE=-Iinclude
CFLAGS := $(TARGET_ARCH_CFLAG) -ggdb3 -std=c99 -Wall -Werror -Wextra -Wno-unused-parameter -Wno-unused-function -fvisibility=hidden -O3 -fPIC # -pedantic
C_BACKEND_CFLAGS := $(TARGET_ARCH_CFLAG) -ggdb3 -std=c99 -Wno-builtin-declaration-mismatch -Og
ZIG_LIBDIR=$(shell zig env | grep lib_dir | cut -f 2 -d '=' | tr -d ',')
C_BACKEND_INCLUDE=-I$(ZIG_LIBDIR)
ZIG ?= zig
ZIGFLAGS ?= 
PACKAGE=libsmear-dev
SMEAR_RELEASE_SUBDIR=smear
SMEAR_RELEASE_STAGE_DIR=$(OBJDIR)/$(SMEAR_RELEASE_SUBDIR)
SMEAR_VERSION=$(shell grep "\bSMEAR_VERSION\b" include/smear/version.h | cut -f 2 -d '"')

default: all

include tests/tests.mk

.PHONY: clean default all tests package zip tgz deb ALWAYS

debug:
	@echo src $(SRC)
	@echo libs $(LIBS)
	@echo arch $(ARCH)
	@echo os $(OS)
	@echo target cpu $(TARGET_CPU)
	@echo target platform $(TARGET_PLATFORM)
	@echo raw cpu $(CPU_RAW)
	@echo c-backend-include $(C_BACKEND_INCLUDE)

all: libsmear.a libsmear.dmp tests obj/libsmear.a


%.dmp: %.a
	$(OBJDUMP) -dSt $< > $@

$(CSMEAR_C): $(SRC)
	$(ZIG) build -Dc_backend=true

# Generate a smear.o using the C backend. I thought this might make
# using helgrind easier, but it still uses custom primitives without
# the helgrind.h ANNOTATE_* macros, so helgrind is still useless.
$(CSMEAR_O): $(CSMEAR_C)
	$(CC) -c -o $@ $(C_BACKEND_INCLUDE) $(TARGET_ARCH_CFLAG) $(C_BACKEND_CFLAGS) $(C_BACKEND_INCLUDE) $^

libsmear.a: $(SRC)
	$(ZIG) build $(ZIGFLAGS)

obj/libsmear.a: libsmear.a
	strip -o $@ $<

stage: libsmear.a
	rm -rf $(SMEAR_RELEASE_STAGE_DIR)
	mkdir -p $(SMEAR_RELEASE_STAGE_DIR)
	cp $< $(SMEAR_RELEASE_STAGE_DIR)
	cp -r include $(SMEAR_RELEASE_STAGE_DIR)
	cp CHANGES $(SMEAR_RELEASE_STAGE_DIR)
	cp LICENSE $(SMEAR_RELEASE_STAGE_DIR)
	cp README.md $(SMEAR_RELEASE_STAGE_DIR)

package: $(foreach EXT,$(PKGEXT),$(PACKAGE)_$(SMEAR_VERSION)-$(TARGET_PLATFORM)_$(TARGET_CPU).$(EXT))

zip: $(PACKAGE)_$(SMEAR_VERSION)-$(TARGET_PLATFORM)_$(TARGET_CPU).zip
$(PACKAGE)_$(SMEAR_VERSION)-$(TARGET_PLATFORM)_$(TARGET_CPU).zip: stage
	cd $(OBJDIR) && \
	if type zip >/dev/null 2>&1; then \
	    zip -r $@ $(SMEAR_RELEASE_SUBDIR); \
	elif type 7z >/dev/null 2>&1; then \
	    7z a $@ $(SMEAR_RELEASE_SUBDIR); \
	fi
	mv $(OBJDIR)/$@ .

tgz: $(PACKAGE)_$(SMEAR_VERSION)-$(TARGET_PLATFORM)_$(TARGET_CPU).tgz
$(PACKAGE)_$(SMEAR_VERSION)-linux_$(TARGET_CPU).tgz: stage
	cd $(OBJDIR) && \
	fakeroot tar -czf $@ $(SMEAR_RELEASE_SUBDIR)
	mv $(OBJDIR)/$@ .

deb: $(PACKAGE)_$(SMEAR_VERSION)-$(TARGET_PLATFORM)_$(TARGET_CPU).deb
$(PACKAGE)_$(SMEAR_VERSION)-linux_$(TARGET_CPU).deb: libsmear.a
	debuild -i -us -uc -nc -b
	mv ../$(PACKAGE)_$(SMEAR_VERSION)-$(TARGET_PLATFORM)_$(TARGET_CPU).deb .
	mv ../libsmear_$(SMEAR_VERSION)-$(TARGET_PLATFORM)_$(TARGET_CPU).* .

zigtest: ALWAYS
	$(ZIG) build test

clean:
	rm -rf debian/$(PACKAGE)
	rm -rf debian/.debhelper
	rm -rf obj/* *.a *.dmp *.deb *.tgz *.zip *.build *.buildinfo *.changes
	rm -rf gen
	rm -f debian/files debian/$(PACKAGE).substvars
	rm -f debian/debhelper-build-stamp
	rm -rf .zig-cache
	rm -rf zig-out
