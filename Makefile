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
	cd build ; cpack -G DEB

clean:
	rm -rf build
