# docker-clang-toolchain
> clang-toolchain without gnu.

clang/clang++ will link [musl libc](https://www.musl-libc.org), [libc++](http://libcxx.llvm.org),
[libcxxabi](https://libcxxabi.llvm.org), libunwind and [compiler-rt](http://compiler-rt.llvm.org) 
as C/C++ standard library or C++ runtime,
not glibc、libstdc++ and libgcc in GNU C/C++ compiler.

## Build
```bash
docker build --rm=true -t monkey-jsun/clang-musl:latest .
```

## Usage

### Dynamic Linking
```bash
docker run -it --rm -v ${PWD}:/project genshen/clang-toolchain:latest clang++ main.cpp -o a.out # compile
docker run -it --rm -v ${PWD}:/project genshen/clang-toolchain:latest ./a.out # run
docker run -it --rm -v ${PWD}:/project genshen/clang-toolchain:latest ldd ./a.out # show shared libs
	/lib/ld-musl-x86_64.so.1 (0x7fc960e6f000)
	libc++.so.1 => /usr/local/lib/libc++.so.1 (0x7fc960cc6000)
	libc++abi.so.1 => /usr/local/lib/libc++abi.so.1 (0x7fc960c67000)
	libc.musl-x86_64.so.1 => /lib/ld-musl-x86_64.so.1 (0x7fc960e6f000)
```

### Static Linking
```bash
docker run -it --rm -v ${PWD}:/project genshen/clang-toolchain:latest clang++ main.cpp -static -lc++ -lc++abi -o main
```
