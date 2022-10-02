ARG ALPINE_VERSION=3.15

ARG LLVM_VERSION=14.0.0
ARG MUSL_VERSION=1.2.2
ARG BUSYBOX_VERSION=1.33.2

ARG INSTALL_PREFIX=/install
ARG LLVM_INSTALL_PATH=${INSTALL_PREFIX}/llvm
ARG MUSL_INSTALL_PATH=${INSTALL_PREFIX}/musl
ARG BUSYBOX_INSTALL_PATH=${INSTALL_PREFIX}/busybox

# final location to install llvm/musl
ARG DEST_INSTALL_PREFIX=/usr

FROM alpine:${ALPINE_VERSION} AS build-llvm

ARG LLVM_VERSION
ARG MUSL_VERSION
ARG INSTALL_PREFIX
ARG LLVM_INSTALL_PATH
ARG MUSL_INSTALL_PATH

# install prerequisites
RUN apk add --no-cache build-base cmake curl git linux-headers ninja python3 wget zlib-dev make

# download sources
ARG LLVM_DOWNLOAD_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/llvm-project-${LLVM_VERSION}.src.tar.xz"
ARG LLVM_SRC_DIR=/llvm_src
RUN mkdir -p ${LLVM_SRC_DIR} \
    && curl -L ${LLVM_DOWNLOAD_URL} | tar Jx --strip-components 1 -C ${LLVM_SRC_DIR}

# patch sources (it is also stored in patch directory)
# see discussion in: https://github.com/llvm/llvm-project/issues/51425
# NOTE patch from https://github.com/emacski/llvm-project/tree/13.0.0-debian-patches
RUN curl -L http://junsun.net/misc/patch/llvm/01-libcxx-build-to-only-link-libatomic-if-rtlib-is-gcc.patch | patch -ruN --strip=1 -d ${LLVM_SRC_DIR} \
    && curl -L http://junsun.net/misc/patch/llvm/02-general-regs-only-for-vararg.patch | patch -ruN --strip=1 -d ${LLVM_SRC_DIR} \
    && curl -L http://junsun.net/misc/patch/llvm/03-hardcode-general-regs-only.patch | patch -ruN --strip=1 -d ${LLVM_SRC_DIR}

# documentation: https://llvm.org/docs/BuildingADistribution.html

# build projects with gcc toolchain, runtimes with newly built projects
# NOTE for some reason LIB*_USE_COMPILER_RT is not passed to runtimes... Using CLANG_DEFAULT_RTLIB instead.
ARG GCC_LLVM_INSTALL_PATH=/usr/local/lib/gcc-llvm
RUN cd ${LLVM_SRC_DIR}/ \
    && cmake -B./build -H./llvm -DCMAKE_BUILD_TYPE=Release -G Ninja \
        -DCMAKE_INSTALL_PREFIX=${GCC_LLVM_INSTALL_PATH} \
        -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON \
        -DLLVM_ENABLE_PROJECTS="clang;lld" \
        -DLLVM_ENABLE_RUNTIMES="compiler-rt;libunwind;libcxxabi;libcxx" \
        -DBUILTINS_CMAKE_ARGS="-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF" \
        -DRUNTIMES_CMAKE_ARGS="-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF" \
        -DLLVM_PARALLEL_LINK_JOBS=4 \
        -DLLVM_ENABLE_BINDINGS=OFF \
        -DLLVM_ENABLE_ZLIB=YES \
        -DCOMPILER_RT_BUILD_BUILTINS=ON \
        -DCOMPILER_RT_BUILD_CRT=ON \
        -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
        -DCOMPILER_RT_BUILD_XRAY=OFF \
        -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
        -DCOMPILER_RT_BUILD_PROFILE=OFF \
        -DCOMPILER_RT_BUILD_MEMPROF=OFF \
        -DCOMPILER_RT_BUILD_ORC=OFF \
        -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
        -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
        -DLIBUNWIND_USE_COMPILER_RT=ON \
        -DLIBCXXABI_USE_COMPILER_RT=ON \
        -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
        -DLIBCXX_HAS_MUSL_LIBC=ON \
        -DLIBCXX_USE_COMPILER_RT=ON \
        -DCLANG_DEFAULT_RTLIB=compiler-rt \
        -DCLANG_DEFAULT_LINKER=lld \
        -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-alpine-linux-musl \
        -DLLVM_TARGETS_TO_BUILD="Native" \
    && cmake --build ./build --target install \
    && rm -rf build \
    && mkdir -p /usr/local/lib /usr/local/bin /usr/local/include \
    && ln -s ${GCC_LLVM_INSTALL_PATH}/bin/*       /usr/local/bin/ \
    && ln -s ${GCC_LLVM_INSTALL_PATH}/lib/*       /usr/local/lib/ \
    && ln -s ${GCC_LLVM_INSTALL_PATH}/include/c++ /usr/local/include/

# TODO build zlib with llvm toolchain

# build and link clang+lld with llvm toolchain
# NOTE link jobs with LTO can use more than 10GB each!
# NOTE execinfo.h not available on musl -> lldb and compiler-rt:fuzzer/sanitizer/profiler cannot be built!
ARG LDFLAGS="-rtlib=compiler-rt -unwindlib=libunwind -stdlib=libc++ -L/usr/local/lib -Wno-unused-command-line-argument"
RUN cd ${LLVM_SRC_DIR}/ \
    && cmake -B./build -H./llvm -DCMAKE_BUILD_TYPE=MinSizeRel -G Ninja \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DLLVM_USE_LINKER=lld \
        -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
        -DCMAKE_MODULE_LINKER_FLAGS="${LDFLAGS}" \
        -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
        -DCMAKE_INSTALL_PREFIX=${LLVM_INSTALL_PATH} \
        -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON \
        -DLLVM_ENABLE_PROJECTS="clang;lld" \
        -DLLVM_ENABLE_RUNTIMES="compiler-rt;libunwind;libcxxabi;libcxx" \
        -DBUILTINS_CMAKE_ARGS="-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF;-DCMAKE_SHARED_LINKER_FLAGS='${LDFLAGS}';-DCMAKE_MODULE_LINKER_FLAGS='${LDFLAGS}';-DCMAKE_EXE_LINKER_FLAGS='${LDFLAGS}'" \
        -DRUNTIMES_CMAKE_ARGS="-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF;-DCMAKE_SHARED_LINKER_FLAGS='${LDFLAGS}';-DCMAKE_MODULE_LINKER_FLAGS='${LDFLAGS}';-DCMAKE_EXE_LINKER_FLAGS='${LDFLAGS}'" \
        -DLLVM_PARALLEL_LINK_JOBS=4 \
        -DLLVM_ENABLE_LTO=ON \
        -DLLVM_ENABLE_LIBCXX=ON \
        -DLLVM_ENABLE_BINDINGS=OFF \
        -DLLVM_ENABLE_EH=ON \
        -DLLVM_ENABLE_RTTI=ON \
        -DLLVM_ENABLE_ZLIB=ON \
        -DCOMPILER_RT_BUILD_BUILTINS=ON \
        -DCOMPILER_RT_BUILD_CRT=ON \
        -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
        -DCOMPILER_RT_BUILD_XRAY=OFF \
        -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
        -DCOMPILER_RT_BUILD_PROFILE=OFF \
        -DCOMPILER_RT_BUILD_MEMPROF=OFF \
        -DCOMPILER_RT_BUILD_ORC=OFF \
        -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
        -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
        -DLIBUNWIND_USE_COMPILER_RT=ON \
        -DLIBCXXABI_USE_COMPILER_RT=ON \
        -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
        -DLIBCXX_HAS_MUSL_LIBC=ON \
        -DLIBCXX_USE_COMPILER_RT=ON \
        -DCLANG_DEFAULT_LINKER=lld \
        -DCLANG_DEFAULT_RTLIB=compiler-rt \
        -DCLANG_DEFAULT_UNWINDLIB=libunwind \
        -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
        -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-alpine-linux-musl  \
        -DLLVM_TARGETS_TO_BUILD="AArch64" \
        -DLLVM_DISTRIBUTION_COMPONENTS="clang;LTO;clang-format;clang-resource-headers;lld;builtins;runtimes" \
    && cmake --build ./build --target install-distribution \
    && rm -rf build

################################################################
FROM alpine:${ALPINE_VERSION} AS build-musl

ARG LLVM_VERSION
ARG MUSL_VERSION
ARG INSTALL_PREFIX
ARG LLVM_INSTALL_PATH
ARG MUSL_INSTALL_PATH
ARG DEST_INSTALL_PREFIX

COPY --from=build-llvm ${INSTALL_PREFIX} ${INSTALL_PREFIX}

RUN mkdir -p ${DEST_INSTALL_PREFIX}/lib ${DEST_INSTALL_PREFIX}/bin ${DEST_INSTALL_PREFIX}/include \
    && ln -s ${LLVM_INSTALL_PATH}/bin/*       ${DEST_INSTALL_PREFIX}/bin/ \
    && ln -s ${LLVM_INSTALL_PATH}/lib/*       ${DEST_INSTALL_PREFIX}/lib/ \
    && ln -s ${LLVM_INSTALL_PATH}/include/c++ ${DEST_INSTALL_PREFIX}/include/ \

ARG CC=clang
ARG CXX=clang++
ARG CFLAGS=""
ARG CXXFLAGS="-stdlib=libc++"
ARG LDFLAGS="-rtlib=compiler-rt -unwindlib=libunwind -stdlib=libc++ -lc++ -lc++abi"

# other build prerequiste
RUN apk add --no-cache binutils curl linux-headers make patch

# build musl
ARG MUSL_SRC_DIR=/musl_src
ARG MUSL_DOWNLOAD_URL=https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz
RUN mkdir -p ${MUSL_SRC_DIR} \
    && curl -L ${MUSL_DOWNLOAD_URL} | tar xz --strip-components 1 -C ${MUSL_SRC_DIR} 

# apply patch
RUN curl -L http://junsun.net/misc/patch/musl/01-remove-inline-assembly-float-optimization.patch | patch -ruN --strip=1 -d ${MUSL_SRC_DIR} 

RUN cd ${MUSL_SRC_DIR} \
    && CC=clang ./configure --prefix=${MUSL_INSTALL_PATH} \
    && make -j`nproc` \
    && make install

################################################################
FROM alpine:${ALPINE_VERSION} AS build-busybox

ARG INSTALL_PREFIX
ARG LLVM_INSTALL_PATH
ARG MUSL_INSTALL_PATH
ARG BUSYBOX_INSTALL_PATH
ARG BUSYBOX_VERSION
ARG DEST_INSTALL_PREFIX

# assemble final image
COPY --from=build-musl ${INSTALL_PREFIX} ${INSTALL_PREFIX}
RUN mkdir -p ${DEST_INSTALL_PREFIX}/lib ${DEST_INSTALL_PREFIX}/bin ${DEST_INSTALL_PREFIX}/include \
    && ln -s ${LLVM_INSTALL_PATH}/bin/*       ${DEST_INSTALL_PREFIX}/bin/ \
    && ln -s ${LLVM_INSTALL_PATH}/lib/*       ${DEST_INSTALL_PREFIX}/lib/ \
    && ln -s ${LLVM_INSTALL_PATH}/include/c++ ${DEST_INSTALL_PREFIX}/include/ \
    && ln -s ${MUSL_INSTALL_PATH}/bin/*       ${DEST_INSTALL_PREFIX}/bin/ \
    && ln -s ${MUSL_INSTALL_PATH}/lib/*       ${DEST_INSTALL_PREFIX}/lib/ \
    && ln -s ${MUSL_INSTALL_PATH}/include/*   ${DEST_INSTALL_PREFIX}/include/
RUN apk add --no-cache binutils linux-headers zlib curl make

# set llvm toolchain as default
ENV CC=clang
ENV CXX=clang++
ENV CFLAGS=""
ENV CXXFLAGS="-stdlib=libc++"
#ENV LDFLAGS="-rtlib=compiler-rt -unwindlib=libunwind -stdlib=libc++ -lc++ -lc++abi"
ENV LDFLAGS="--static -rtlib=compiler-rt -unwindlib=libunwind"

RUN ln -sf ${DEST_INSTALL_PREFIX}/bin/clang ${DEST_INSTALL_PREFIX}/bin/cc \
    && ln -sf ${DEST_INSTALL_PREFIX}/bin/clang ${DEST_INSTALL_PREFIX}/bin/gcc \
    && ln -sf ${DEST_INSTALL_PREFIX}/bin/clang++ ${DEST_INSTALL_PREFIX}/bin/c++ \
    && ln -sf ${DEST_INSTALL_PREFIX}/bin/lld ${DEST_INSTALL_PREFIX}/bin/ld

# add user mount point
ARG BUSYBOX_SRC_DIR=/busybox-src
RUN mkdir -p ${BUSYBOX_SRC_DIR} \
    && curl -L https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 | tar xj --strip-components 1 -C ${BUSYBOX_SRC_DIR} 

RUN cd ${BUSYBOX_SRC_DIR} \
    && make defconfig \
    && make CONFIG_PREFIX=/install/busybox install

RUN mkdir -p /project
WORKDIR /project
