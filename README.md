[![Linux Build Status](https://img.shields.io/travis/com/smudgelang/smear.svg?label=Linux%20build&branch=master)](https://travis-ci.com/smudgelang/smear)
[![Windows Build Status](https://img.shields.io/appveyor/ci/smudgelang/smear.svg?label=Windows%20Build&branch=master)](https://ci.appveyor.com/project/smudgelang/smear)

# The Smear Library

Smear is the SMudge Environment And Runtime, a standard library for
the Smudge state machine programming language.

## Getting Smear

### Splat

Instead of installing Smear by itself, most people will want to install
[Splat, the Smudge Platform](https://github.com/smudgelang/splat), which
bundles together everything you need to use Smudge.  To download, go to
the [Splat releases page](https://github.com/smudgelang/splat/releases)
for the latest platform release.

### Binaries

If you really want to install the Smear library by itself, there are
binary releases available for Windows and Linux available on the
[Smear releases page](https://github.com/smudgelang/smear/releases).

### Building and Linking

To use this package in your own Smudge projects, build `libsmear.a`.
In your shell of choice, run:

    $ make

Put the library in your library include path. Then link your code with
`-lsmear -pthread`. Also put `include/smear/*` in your include path.

## Using Smear

### Autogenerate Smear Bindings

To get Smudge to generate bindings directly to smear for your project,
along with a minimal `main`, run:

    $ smudge --c-smear --c-stubs machine.smudge

### Manual Smear Bindings

Smear implements all the functions whose names start with `SMUDGE_`,
and has handy macros for generating your event handlers. Put this in
one of your .c files:

    #include <smear.h>

    // Call this macro once per Smudge state machine. This is how you
    // would call it for a machine called "machine".
    SRT_HANDLERS(machine)

    // And this is how you'd call it for another machine called
    // "traffic_light".
    SRT_HANDLERS(traffic_light)

Then, before you send any events in your program, call
`SRT_init()`. Once your program is initialized, you can call
`SRT_run()` to start processing events. If you ever want to stop the
state machines, you can call `SRT_stop()` and if you want to run
forever in a happy little Smudge world, you can call `SRT_join()`.
