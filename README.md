# aarch64-soft-float-busybox

Unlike 32bit ARM, AArch64 does not define an official "soft-float" ABI.  By definition all 64bit ARM CPUs must have floating point and NEON SIMD support.

However, there are special situations where we want to run soft-float userland, e.g., avoiding floating-point bugs, special CPU, development of emulator or translators, etc.

In this project we leverage llvm "-mgeneral-regs-only" option to build a soft-float, statically linked busybox.  We use docker and alpine linux to fix the codify the build process.  Here is an over sketch of the idea.

* use gcc to build stage0 clang/llvm with "soft-float" patches
* use stage0 clang/llvm to build stage1 clang/llvm, mostly to avoid gcc RT libraries and patch llvm RT libraries with "soft-float" support
* use stage1 clang/llvm to build musl C library with "soft-float" patch
* install stage1 clang/llvm and patched musl C library to build busybox statically

## Host setup - Ubuntu
* Prepare an aarch64/Linux machine (e.g., Ubuntu on AWS arm64 instance)
* install docker, `sudo apt update && sudo apt install -y docker.io`
* add user to docker group in order to run docker, `sudo usermod -aG docker $USER && newgrp docker`
* clone the source, `git clone https://github.com/monkey-jsun/aarch64-soft-float-busybox.git`

## Build
```bash
cd aarch64-soft-float-busybox
docker build --rm=true -t monkey-jsun/aarch64-soft-float-busybox:latest .
```

## Fetch Build Artifacts
```bash
docker cp <container id>:/install output/
```

## Compile other programs
### Dynamic Linking
```bash
docker run -it --rm -v ${PWD}:/project monkey-jsun/aarch64-soft-float-busybox:latest clang++ main.cpp -o a.out # compile
docker run -it --rm -v ${PWD}:/project monkey-jsun/aarch64-soft-float-busybox:latest ./a.out # run
docker run -it --rm -v ${PWD}:/project monkey-jsun/aarch64-soft-float-busybox:latest ldd ./a.out # show shared libs
```

### Static Linking
```bash
docker run -it --rm -v ${PWD}:/project gmonkey-jsun/aarch64-soft-float-busybox:latest clang++ main.cpp -static -lc++ -lc++abi -o main
```

## Credits
* Thanks to [Gen Shen](https://github.com/genshen) who have set a [good base](https://github.com/genshen/docker-clang-toolchain) to start with.
* Thanks to Amanieu for all the soft-float related patches
