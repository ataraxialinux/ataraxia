#!/bin/bash

set -e

# Colors!
export C_CLEAR='\e[m'
export C_RED='\e[1;31m'
export C_GREEN='\e[1;32m'

message() {
	echo -e " ${C_GREEN}>>${C_CLEAR} ${@}"
}

error() {
	echo -e " ${C_RED}>>${C_CLEAR} ${@}"
}

configure_arch() {
	case $BARCH in
		x86_64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-linux-musl"
			export XKARCH="x86_64"
			export GCCOPTS="--with-arch=x86-64 --with-tune=generic --enable-long-long"
			;;
		i686)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="i686-linux-musl"
			export XKARCH="i386"
			export GCCOPTS="--with-arch=i686 --with-tune=generic"
			;;
		aarch64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
			;;
		armv7l)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-float=hard --with-fpu=neon"
			;;
		mips64el)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mips64el-linux-musl"
			export XKARCH="mips"
			export GCCOPTS="--with-arch=mips3 --with-tune=mips64 --with-mips-plt --with-float=soft --with-abi=64"
			;;
		mipsel)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mipsel-linux-musl"
			export XKARCH="mips"
			export GCCOPTS="--with-arch=mips32 --with-mips-plt --with-float=soft --with-abi=32"
			;;
		powerpc64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc64le-linux-musl"
			export XKARCH="powerpc64le"
			export GCCOPTS="--with-abi=elfv2 --enable-secureplt --enable-decimal-float=no --enable-targets=powerpcle-linux"
			;;
		powerpc)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc-linux-musl"
			export XKARCH="powerpc"
			export GCCOPTS="--enable-secureplt --enable-decimal-float=no"
			;;
		*)
			error "BARCH variable isn't set!"
			exit 0
	esac
}

setup_build_env() {
	message "Preparing build environment..."
	sleep 1
	export CWD="$(pwd)"
	export BUILD="$CWD/build"
	export SOURCES="$BUILD/sources"
	export ROOTFS="$BUILD/rootfs"
	export TOOLS="$BUILD/tools"
	export PKGS="$BUILD/packages"
	export KEEP="$CWD/KEEP"
	export REPO="$CWD/pkgs"
	export TC="$CWD/toolchain"
	export UTILS="$CWD/utils"

	rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $TOOLS $PKGS

	export LC_ALL="POSIX"
	export PATH="$UTILS:$TOOLS/bin:$PATH"
	export MKOPTS="-j$(expr $(nproc) + 1)"
	export HOSTCC="gcc"
}

prepare_toolchain() {
	message "Setting up toolchain optimizations..."
	sleep 1
	export CFLAGS="-Os -g0"
	export CXXFLAGS="$CFLAGS"
	export LDFLAGS="-s"

	case $BARCH in
		x86_64|aarch64|mips64el|powerpc64)
			cd $TOOLS
			mkdir -p $TOOLS/lib
			ln -s lib lib64
			mkdir -p $TOOLS/$XTARGET/lib
			cd $TOOLS/$XTARGET
			ln -s lib lib64
			;;
	esac

	cd $TOOLS
	ln -sf . usr
}

build_toolchain() {
	message "Building cross-toolchain for $XTARGET..."
	sleep 1
	MODE=toolchain buildpkg $TC/file
	MODE=toolchain buildpkg $TC/pkgconf
	MODE=toolchain buildpkg $TC/linux-headers
	MODE=toolchain buildpkg $TC/binutils
	MODE=toolchain buildpkg $TC/gcc-static
	MODE=toolchain buildpkg $TC/musl
	MODE=toolchain buildpkg $TC/gcc-final
	MODE=toolchain buildpkg $TC/finish
}

prepare_build() {
	message "Setting up optimzations and toolset for rootfs build..."
	sleep 1
	export CFLAGS="-Os -g0"
	export CXXFLAGS="$CFLAGS"
	export LDFLAGS="-s -Wl,-rpath-link,$ROOTFS/usr/lib"
	export CC="$XTARGET-gcc --sysroot=$ROOTFS"
	export CXX="$XTARGET-g++ --sysroot=$ROOTFS"
	export AR="$XTARGET-ar"
	export AS="$XTARGET-as"
	export LD="$XTARGET-ld --sysroot=$ROOTFS"
	export RANLIB="$XTARGET-ranlib"
	export READELF="$XTARGET-readelf"
	export STRIP="$XTARGET-strip"
	export PKG_CONFIG_PATH="$ROOTFS/usr/lib/pkgconfig"
}

build_rootfs() {
	message "Setting up filesystem..."
	sleep 1
	. $UTILS/setup-rootfs

	message "Building rootfs..."
	sleep 1
	for PKG in linux-headers musl libz m4 bison flex libelf binutils gmp mpfr mpc gcc attr acl libcap sed pkgconf ncurses util-linux e2fsprogs iana-etc libtool iproute2 perl readline autoconf automake bash bc file gawk grep less kbd make xz kmod expat patch gperf eudev busybox vim grub libressl openssh curl git libarchive lynx libnl wpa_supplicant linux; do
		buildpkg $REPO/$PKG $PKGS/$PKG
	done
}

configure_arch
setup_build_env
prepare_toolchain
build_toolchain
prepare_build
build_rootfs

exit 0

