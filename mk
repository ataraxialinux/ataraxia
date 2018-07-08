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
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $ROOTFS || pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $ROOTFS -u
	done
}

toolpkginstall() {
	local pkg="$@"
	for mergepkg in $pkg; do
		printmsg "Building and installing $mergepkg"
		cd $TCREPO/$mergepkg
		pkgmk -d -if -im -is -ns -cf $TCREPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $TOOLS -f || pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $TOOLS -f -u
	done
}

initdb() {
	local dir="$@"
	for dbindir in $dir; do
		mkdir -p $dbindir/var/lib/pkg
		touch $dbindir/var/lib/pkg/db
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
			export GCCOPTS="--with-arch=x86-64 --with-tune=generic"
			;;
		aarch64)
			printmsg "Using configuration for aarch64"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
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

	export CPPFLAGS="-D_FORTIFY_SOURCE=2"
	export CFLAGS="-Os -g0 -fstack-protector-strong -fno-plt -pipe"
	export CXXFLAGS="-Os -g0 -fstack-protector-strong -fno-plt -pipe"
	export LDFLAGS="-s -Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"
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
	pkginstall linux-headers musl
	toolpkginstall gcc

	printmsg "Cleaning"
	rm -rf $PACKAGES/{file,pkgconf,binutils,gcc-static,gcc}#*
}

bootstrap_rootfs() {
	printmsg "Bootstraping root filesystem"
	pkginstall zlib m4 bison flex libelf binutils gmp mpfr mpc isl gcc attr acl libcap pkgconf ncurses util-linux e2fsprogs libtool perl readline autoconf automake bash bc file kbd make xz patch busybox libressl ca-certificates linux libnl wpa_supplicant curl libarchive git npkg prt-get
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

