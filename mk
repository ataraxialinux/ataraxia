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
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-tune=generic-armv7-a --with-fpu=vfpv3-d16 --with-float=hard --with-abi=aapcs-linux --with-mode=thumb"
			;;
		armv6h)
			printmsg "Using configuration for armv6h"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv6zk --with-tune=arm1176jzf-s --with-fpu=vfp --with-float=hard --with-abi=aapcs-linux"
			;;
		mipsel)
			printmsg "Using configuration for mipsel"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mipsel-linux-musl"
			export XKARCH="mips"
			export GCCOPTS="--with-arch=mips32 --with-mips-plt --with-float=soft --with-abi=32 --with-linker-hash-style=sysv"
			;;
		mips)
			printmsg "Using configuration for mips"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mips-linux-musl"
			export XKARCH="mips"
			export GCCOPTS="--with-arch=mips32 --with-mips-plt --with-float=soft --with-abi=32 --with-linker-hash-style=sysv"
			;;
		ppc64le)
			printmsg "Using configuration for ppc64le"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc64le-linux-musl"
			export XKARCH="powerpc"
			export GCCOPTS="--with-abi=elfv2 --enable-secureplt --enable-decimal-float=no --enable-targets=powerpcle-linux"
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
	export CXXFLAGS="-Os -g0 -pipe"
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
	pkginstall linux-headers musl
	toolpkginstall gcc

	printmsg "Cleaning"
	rmpkg file pkgconf binutils gcc-static gcc
}

bootstrap_rootfs() {
	printmsg "Bootstraping root filesystem"
	pkginstall zlib m4 bison flex libelf binutils gmp mpfr mpc isl gcc attr acl libcap pkgconf ncurses util-linux e2fsprogs libtool perl readline autoconf automake bash bc file kbd make xz patch busybox libressl ca-certificates linux libnl wpa_supplicant curl wget libarchive git npkg prt-get
}

generate_stage_archive() {
	printmsg "Building stage archive"

	pkginstallstage filesystem linux-headers musl zlib m4 bison flex libelf binutils gmp mpfr mpc isl gcc attr acl libcap pkgconf ncurses util-linux e2fsprogs libtool perl readline autoconf automake bash bc file kbd make xz patch busybox libressl ca-certificates linux curl wget libarchive git npkg prt-get

	chown -R root:root $STAGE

	cd $STAGE
	tar jcfv $CWD/januslinux-1.0-beta4-$BARCH.tar.bz2 *
}

generate_initrd() {
	printmsg "Building initrd archive"

	pkginstallinitrd filesystem linux-headers musl zlib attr acl libcap ncurses util-linux e2fsprogs readline bash file kbd xz busybox libressl ca-certificates linux libnl wpa_supplicant curl wget

	cd $INITRD
	rm -rf usr/include
	find . | cpio -R root:root -H newc -o | xz -9 --check=none > $IMAGE/rootfs.cpio.xz

	cp boot/vmlinuz* $IMAGE/vmlinuz
}

generate_iso() {
	printmsg "Building *.iso image"
	cd $SOURCES
	curl -C - -O -L https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
	tar -xf syslinux-6.03.tar.xz

	cp syslinux-6.03/bios/core/isolinux.bin $IMAGE/isolinux.bin
	cp syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 $IMAGE/ldlinux.c32

cat << CEOF > $IMAGE/syslinux.cfg
PROMPT 1
TIMEOUT 50
DEFAULT boot
LABEL boot
	LINUX vmlinuz
	APPEND quiet
	INITRD rootfs.cpio.xz
CEOF

	mkdir -p $IMAGE/efi/boot
cat << CEOF > $IMAGE/efi/boot/startup.nsh
echo januslinux starting...
\\vmlinuz quiet initrd=\\rootfs.cpio.xz
CEOF

	genisoimage \
		-J -r -o $CWD/januslinux-1.0-beta4-$BARCH.iso \
		-b isolinux.bin \
		-c boot.cat \
		-input-charset UTF-8 \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		$IMAGE
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
	stage)
		check_for_root
		setup_architecture
		setup_environment
		generate_stage_archive
		;;
	image)
		check_for_root
		setup_architecture
		setup_environment
		generate_initrd
		generate_iso
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
	package-update)
		check_for_root
		setup_architecture
		setup_environment
		pkgupdate $JPKG
		;;
	host-package-update)
		check_for_root
		setup_architecture
		setup_environment
		toolpkgupdate $JPKG
		;;
	usage|*)
		mkusage
esac

exit 0

