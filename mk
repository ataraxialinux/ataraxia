#!/bin/sh

set -e

printmsg() {
	local msg=$(echo $1 | tr -s / /)
	printf "\e[1m\e[32m==>\e[0m $msg\n"
	sleep 1
}

printmsgerror() {
	local msg=$(echo $1 | tr -s / /)
	printf "\e[1m\e[31m==!\e[0m $msg\n"
	sleep 1
}

pkginstall() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and installing $mergepkg"
		cd $REPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $REPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.gz --root $ROOTFS
	done
}

toolpkginstall() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and installing $mergepkg"
		cd $TCREPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $TCREPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.gz --root $TOOLS -f
	done
}

check_for_root() {
	:
}

setup_architecture() {
	case $BARCH in
		x86_64)
			printmsg "Using configuration for x86_64"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-linux-musl"
			export XKARCH="x86_64"
			export GCCOPTS="--with-arch=x86-64 --with-tune=generic"
			;;
		aarch64)
			printmsg "Using configuration for aarch64"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
			;;
		armhf)
			printmsg "Using configuration for armhf"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-float=hard --with-fpu=neon"
			;;
		*)
			printmsgerror "BARCH variable isn't set!"
			exit 1
	esac
}

setup_environment() {
	printmsg "Setting up build environment"
	export CWD="$(pwd)"
	export KEEP="$CWD/KEEP"
	export BUILD="$CWD/build"
	export REPO="$CWD/packages"
	export TCREPO="$CWD/toolchain"
	export SOURCES="$BUILD/sources"
	export ROOTFS="$BUILD/rootfs"
	export TOOLS="$BUILD/tools"
	export PACKAGES="$BUILD/packages"
	export IMAGE="$BUILD/image"

	export LC_ALL="POSIX"
	export PATH="$TOOLS/usr/bin:$TOOLS/bin:$PATH"
	export HOSTCC="gcc"
	export HOSTCXX="g++"
	export MKOPTS="-j$(expr $(nproc) + 1)"

	export CPPFLAGS="-D_FORTIFY_SOURCE=2"
	export CFLAGS="-Os -g0 -fstack-protector-strong -fno-plt -pipe"
	export CXXFLAGS="-Os -g0 -fstack-protector-strong -fno-plt -pipe"
	export LDFLAGS="-s -Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"
}

make_environment() {
	rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS/var/lib/pkg $TOOLS/var/lib/pkg $PACKAGES $IMAGE
	touch {$ROOTFS/var/lib/pkg,$TOOLS/var/lib/pkg}/db
}

build_toolchain() {
	printmsg "Building cross-toolchain for $BARCH"
	pkginstall filesystem
	toolpkginstall file
	toolpkginstall pkgconf
	toolpkginstall binutils
	toolpkginstall gcc-static
	pkginstall linux-headers musl
	toolpkginstall gcc
	toolpkginstall go

	printmsg "Cleaning"
	rm -rf $PACKAGES/{file,pkgconf,binutils,gcc-static,gcc,go}#*
}

build_rootfs() {
	printmsg "Building root filesystem"
	case $BARCH in
		x86_64)
			export BOOTLOADER="grub"
			;;
	esac
	pkginstall zlib m4 bison flex libelf binutils gmp mpfr mpc isl gcc attr acl libcap pkgconf ncurses util-linux e2fsprogs libtool perl readline autoconf automake bash bc file kbd make xz patch busybox libressl ca-certificates linux $BOOTLOADER curl libarchive pkgutils expat go
}

OPT="$1"
JPKG="$2"

case "$OPT" in
	toolchain)
		check_for_root
		setup_architecture
		setup_environment
		make_environment
		build_toolchain
		;;
	image)
		check_for_root
		setup_architecture
		setup_environment
		make_environment
		build_toolchain
		build_rootfs
		;;
	package)
		check_for_root
		setup_architecture
		setup_environment
		pkginstall $JPKG
		;;
	host-package)
		check_for_root
		setup_architecture
		setup_environment
		toolpkginstall $JPKG
		;;
	usage|*)
		mkusage
esac

exit 0

