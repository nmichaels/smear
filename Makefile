TARGET_ARCH_CFLAG_32=-m32
TARGET_ARCH_CFLAG=$(TARGET_ARCH_CFLAG_$(TARGETBITS))
TARGET_ARCH_LDFLAG_32=-melf_i386
TARGET_ARCH_LDFLAG=$(TARGET_ARCH_LDFLAG_$(TARGETBITS))

CPU_PLAT_RAW=$(shell $(CC) -dumpmachine)
CPU_RAW=$(shell $(CC) $(TARGET_ARCH_CFLAG) -Q --help=target | grep march | awk '{print $$2}')
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
MODULES := smear cancelq number
LIBS :=
SRC := 
CC := gcc
CFLAGS := $(TARGET_ARCH_CFLAG) -ggdb3 -std=c99 -Wall -Werror -Wextra -Wno-unused-parameter -Wno-unused-function -fvisibility=hidden -O3 -fPIC -pedantic
LDFLAGS := $(TARGET_ARCH_LDFLAG) -r
INCLUDE := -Iinclude $(foreach mod, $(MODULES), -Isrc/$(mod))
VPATH := $(foreach mod, $(MODULES), src/$(mod)) include
PACKAGE=libsmear-dev
SMEAR_RELEASE_SUBDIR=smear
SMEAR_RELEASE_STAGE_DIR=$(OBJDIR)/$(SMEAR_RELEASE_SUBDIR)
SMEAR_VERSION=$(shell grep "\bSMEAR_VERSION\b" include/smear/version.h | cut -f 2 -d '"')

default: all

include tests/tests.mk
include $(patsubst %,$(SRCDIR)/%/module.mk, $(MODULES))
OBJ := $(SRC:%.c=$(OBJDIR)/%.o)

LIBS := $(sort $(LIBS))

.PHONY: clean default all tests \
        package zip tgz deb


debug:
	@echo inc $(INCLUDE)
	@echo src $(SRC)
	@echo libs $(LIBS)
	@echo obj $(OBJ)
	@echo arch $(ARCH)
	@echo os $(OS)
	@echo vpath $(VPATH)
	@echo target cpu $(TARGET_CPU)
	@echo target platform $(TARGET_PLATFORM)

all: libsmear.a libsmear.dmp tests obj/libsmear.a


-include $(OBJ:.o=.d)

%.dmp: %.a
	objdump -dSt $< > $@

obj/%.d: %.c # Slightly modified from GNU Make tutorial
	@set -e; rm -f $@; \
	  $(CC) -MM -MG $(CFLAGS) $< > $@.$$$$; \
	  sed 's,\($*\)\.o[ :]*,obj/\1.o $@ : ,g' < $@.$$$$ > $@; \
	  rm -f $@.$$$$

libsmear.a: $(OBJ)
	$(LD) $(LDFLAGS) -o $@ $^
	objcopy --localize-hidden $@

obj/libsmear.a: libsmear.a
	strip -o $@ $<

obj/%.o: %.c
	$(CC) $(CFLAGS) $(INCLUDE) $(LIBS) -c -o $@ $<

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

clean:
	rm -rf debian/$(PACKAGE)
	rm -rf debian/.debhelper
	rm -rf obj/* *.a *.dmp *.deb *.tgz *.zip *.build *.buildinfo *.changes
	rm -f debian/files debian/$(PACKAGE).substvars
	rm -f debian/debhelper-build-stamp
