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
	exit 1
}

pkginstall() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and installing $mergepkg"
		cd $REPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $REPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $ROOTFS
	done
}

pkginstallstage() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Installing $mergepkg"
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $STAGE
	done
}

pkginstallinitrd() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Installing $mergepkg"
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $INITRD
	done
}

toolpkginstall() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and installing $mergepkg"
		cd $TCREPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $TCREPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $TOOLS -f
	done
}

pkgupdate() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and updating $mergepkg"
		cd $REPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $REPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $ROOTFS -u
	done
}

toolpkgupdate() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and updating $mergepkg"
		cd $TCREPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $TCREPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $TOOLS -f -u
	done
}

initdb() {
	local dir="$@"
	for dbindir in $dir; do
		mkdir -p $dbindir/var/lib/pkg
		touch $dbindir/var/lib/pkg/db
	done
}

rmpkg() {
	local rmpkg="$@"
	for rmpack in $rmpkg; do
		rm -rf $PACKAGES/$rmpack#*
	done
}

check_for_root() {
	if [[ $EUID -ne 0 ]]; then
		printmsgerror "This script must be run as root" 
	fi
}

setup_architecture() {
	case $BARCH in
		x86_64)
			printmsg "Using configuration for x86_64"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-linux-musl"
			export XKARCH="x86_64"
			export GCCOPTS=
			;;
		i686)
			printmsg "Using configuration for i686"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="i686-linux-musl"
			export XKARCH="i386"
			export GCCOPTS=
			;;
		aarch64)
			printmsg "Using configuration for aarch64"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
			;;
		armv7h)
			printmsg "Using configuration for armv7h"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="armv7l-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-fpu=vfpv3 --with-float=hard"
			;;
		armv6h)
			printmsg "Using configuration for armv6h"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv6 --with-fpu=vfp --with-float=hard"
			;;
		mipsel)
			printmsg "Using configuration for mipsel"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mipsel-linux-musl"
			export XKARCH="mips"
			export GCCOPTS="--with-arch=mips32r2 --with-float=soft --with-linker-hash-style=sysv"
			;;
		mips)
			printmsg "Using configuration for mips"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mips-linux-musl"
			export XKARCH="mips"
			export GCCOPTS="--with-arch=mips32r2 --with-float=soft"
			;;
		*)
			printmsgerror "BARCH variable isn't set!"
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
	export INITRD="$BUILD/initrd"
	export STAGE="$BUILD/stage"

	export LC_ALL="POSIX"
	export PATH="$KEEP/bin:$TOOLS/bin:$PATH"
	export HOSTCC="gcc"
	export HOSTCXX="g++"
	export MKOPTS="-j$(expr $(nproc) + 1)"

	export CFLAGS="-Os -g0 -pipe"
	export CXXFLAGS="$CFLAGS"
	export LDFLAGS="-s"
}

make_environment() {
	rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $INITRD $STAGE $TOOLS $PACKAGES $IMAGE

	initdb $ROOTFS $TOOLS $INITRD $STAGE
}

build_toolchain() {
	printmsg "Building cross-toolchain for $BARCH"
	pkginstall filesystem
	toolpkginstall file
	toolpkginstall pkgconf
	toolpkginstall binutils
	toolpkginstall gcc-static
	pkginstall linux-headers-bootstrap musl-bootstrap
	toolpkginstall gcc

	printmsg "Cleaning"
	rmpkg file pkgconf binutils gcc
}

bootstrap_rootfs() {
	printmsg "Bootstraping root filesystem"
	pkginstall binutils-bootstrap gcc-bootstrap busybox-bootstrap file-bootstrap libarchive-bootstrap npkg-bootstrap bootstrap-scripts
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
	bootstrap)
		check_for_root
		setup_architecture
		setup_environment
		make_environment
		build_toolchain
		bootstrap_rootfs
		;;
	enter-chroot)
		echo "In development"
		;;
	usage|*)
		mkusage
esac

exit 0

