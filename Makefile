GIT_COMMIT_TIME=$(shell git show --no-patch --format=%ct HEAD)
SOURCE_DATE_EPOCH=$(GIT_COMMIT_TIME)

.PHONY: clean default all tests \
        package smear deb

default: all

all: smear

build:
	cmake -B build

smear: build
	cmake --build build --target smear

package: build
	cmake --build build --target package

deb: package build
	umask 022 ; cd build ; cpack -G DEB

clean:
	rm -rf build
