ARCH ?= posix
LIBS += -pthread
VPATH := $(VPATH) src/cancelq/$(ARCH)/
SRC += cancellable.zig
#SRC += cancellable.c
OBJ += obj/libcancellable.a
INCLUDE += -Isrc/cancelq/$(ARCH)/

# Source includes are weird. Here's an explicit dependency.
#obj/cancellable.o: heap.c

obj/libcancellable.a: cancellable.zig smeartime.h cancellable.h
	zig build-lib src/cancelq/cancellable.zig -lc -isystem src/smear -isystem src/cancelq --output-dir obj -fno-stack-check
