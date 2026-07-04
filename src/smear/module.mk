OS ?= linux
SRC += smear.zig
LIBS += -pthread
CFLAGS += -D_POSIX_C_SOURCE=199309L

obj/smear.o: src/smear/smear.zig
	zig build

obj/smear.d: # No .d files for zig
	touch obj/smear.d
