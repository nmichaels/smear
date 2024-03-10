ARCH ?= posix
LIBS += -pthread
VPATH := $(VPATH) src/cancelq/$(ARCH)/
SRC += cancellable.zig

# Source includes are weird. Here's an explicit dependency.

obj/cancellable.o: src/cancelq/cancellable.zig
	zig build

obj/cancellable.d: # No .d files for zig
	touch obj/cancellable.d

.PHONY: clean-zig
clean-zig:
	rm -rf zig-cache

clean: clean-zig
