#!/bin/sh

set -e

export RELEASE="$(date +%y%m%d)"

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
			export GCCOPTS=''
			;;
		i486)
			printmsg "Using configuration for i486"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="i486-linux-musl"
			export XKARCH="i386"
			export GCCOPTS="--with-arch=i486 --with-tune=generic"
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
			export GCCOPTS="--with-arch=mips32r2 --with-float=soft --with-linker-hash-style=sysv"
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

	export CFLAGS="-Os -g0 -s -pipe"
	export CXXFLAGS="$CFLAGS"
}

make_environment() {
	umount $ROOTFS/usr/janus/KEEP $ROOTFS/usr/janus/packages $ROOTFS/usr/janus/toolchain || true
	umount $ROOTFS/proc $ROOTFS/sys $ROOTFS/dev $ROOTFS/tmp || true
	umount $ROOTFS/output/sources $ROOTFS/output/packages || true
	umount $ROOTFS/output/stage $ROOTFS/output/initrd || true

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
	pkginstall linux-headers musl-bootstrap
	toolpkginstall gcc

	printmsg "Cleaning"
	rmpkg file pkgconf binutils gcc gcc-static
}

bootstrap_rootfs() {
	printmsg "Bootstraping root filesystem"
	pkginstall zlib-bootstrap binutils-bootstrap gcc-bootstrap make-bootstrap busybox-bootstrap ncurses-bootstrap bash-bootstrap file-bootstrap perl-bootstrap xz-bootstrap libarchive-bootstrap libressl-bootstrap curl-bootstrap npkg-bootstrap patch-bootstrap bootstrap-scripts
}

clean_packages() {
	printmsg "Cleaning"
	rmpkg linux-headers-bootstrap musl-bootstrap zlib-bootstrap binutils-bootstrap gcc-bootstrap make-bootstrap busybox-bootstrap ncurses-bootstrap bash-bootstrap file-bootstrap perl-bootstrap xz-bootstrap libarchive-bootstrap libressl-bootstrap curl-bootstrap npkg-bootstrap patch-bootstrap bootstrap-scripts
}

mountall() {
	mount --bind $BUILD/packages $ROOTFS/output/packages || true
	mount --bind $BUILD/sources $ROOTFS/output/sources || true
	mount --bind $BUILD/stage $ROOTFS/output/stage || true
	mount --bind $BUILD/initrd $ROOTFS/output/initrd || true
}

umountall() {
	umount $ROOTFS/output/sources $ROOTFS/output/packages || true
	umount $ROOTFS/output/stage $ROOTFS/output/initrd || true
}

enter_chroot() {
	set +e
	mkdir -p $ROOTFS/output/{stage,initrd}
	mkdir -p $ROOTFS/usr/janus/{KEEP,packages,toolchain}

	mount --bind /proc $ROOTFS/proc
	mount --bind /sys $ROOTFS/sys
	mount --bind /dev $ROOTFS/dev
	mount --bind /tmp $ROOTFS/tmp

	mount --bind $CWD/KEEP $ROOTFS/usr/janus/KEEP
	mount --bind $CWD/packages $ROOTFS/usr/janus/packages
	mount --bind $CWD/toolchain $ROOTFS/usr/janus/toolchain

	mount --bind $BUILD/packages $ROOTFS/output/packages
	mount --bind $BUILD/sources $ROOTFS/output/sources
	mount --bind $BUILD/stage $ROOTFS/output/stage
	mount --bind $BUILD/initrd $ROOTFS/output/initrd

	chroot $ROOTFS /busybox/bin/env -i \
		TERM="$TERM" \
		PS1='(januslinux chroot) \u:\w\$ ' \
		PATH="/busybox/bin:/usr/local/sbin:/usr/local/bin:/usr/bin" \
		/usr/bin/bash --login +h

	umount $ROOTFS/usr/janus/KEEP $ROOTFS/usr/janus/packages $ROOTFS/usr/janus/toolchain
	umount $ROOTFS/proc $ROOTFS/sys $ROOTFS/dev $ROOTFS/tmp
	umount $ROOTFS/output/sources $ROOTFS/output/packages
	umount $ROOTFS/output/stage $ROOTFS/output/initrd
}

generate_stage_archive() {
	set +e
	printmsg "Building stage archive"

	pkginstallstage filesystem linux-headers musl zlib m4 bison flex libelf binutils gmp mpfr mpc isl gcc attr acl libcap sed pkgconf ncurses shadow util-linux e2fsprogs libtool bzip2 perl readline autoconf automake bash bc diffutils file gettext kbd make xz kmod patch busybox libressl ca-certificates dosfstools gperf eudev linux nano vim lzip lzo lz4 zstd btrfs-progs xfsprogs curl wget libarchive git npkg prt-get

	cd $STAGE
	tar -cJf $CWD/januslinux-$RELEASE-$BARCH.tar.xz .
}

generate_initrd() {
	set +e
	printmsg "Building initrd archive"

	pkginstallinitrd filesystem linux-headers musl zlib attr acl libcap sed ncurses shadow util-linux e2fsprogs bzip2 readline bash file kbd xz kmod busybox libressl ca-certificates dosfstools eudev linux lzo lz4 zstd btrfs-progs xfsprogs nano libnl wpa_supplicant curl lzip

	cd $INITRD
	ln -sf busybox usr/bin/wget
	rm -rf usr/include
	rm -rf usr/lib/*.a*
	find . | cpio -R root:root -H newc -o | xz -9 --check=none > $IMAGE/rootfs.cpio.xz

	cp boot/vmlinuz* $IMAGE/vmlinuz
}

generate_iso_x86() {
	set +e
	printmsg "Building *.iso image"
	cd $SOURCES
	curl -C - -O -L https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
	tar -xf syslinux-6.03.tar.xz

	cp syslinux-6.03/bios/core/isolinux.bin $IMAGE/isolinux.bin
	cp syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 $IMAGE/ldlinux.c32
	cp syslinux-6.03/bios/com32/libutil/libutil.c32 $IMAGE/libutil.c32
	cp syslinux-6.03/bios/com32/menu/menu.c32 $IMAGE/menu.c32

cat << CEOF > $IMAGE/syslinux.cfg
UI menu.c32
PROMPT 0

TIMEOUT 10
DEFAULT default

MENU TITLE januslinux boot menu:
MENU MARGIN 10 
MENU VSHIFT 5
MENU ROWS 5
MENU TABMSGROW 14
MENU TABMSG Press ENTER to boot, TAB to edit, or press F1 for more information.
MENU HELPMSGROW 15
MENU HELPMSGENDROW -3
MENU AUTOBOOT BIOS default device boot in # second{,s}...

LABEL default
        MENU LABEL januslinux
	TEXT HELP
	Fast and compact Linux distribution which uses musl libc.
	Coded and built by januslinux Inc. 2016-2018
	ENDTEXT
	LINUX vmlinuz
	INITRD rootfs.cpio.xz
	APPEND quiet loglevel=4

CEOF

	mkdir -p $IMAGE/efi/boot
cat << CEOF > $IMAGE/efi/boot/startup.nsh
echo -off
echo januslinux starting...
\\vmlinuz quiet loglevel=4 initrd=\\rootfs.cpio.xz
CEOF

	xorriso \
		-as mkisofs \
		-J -r -o $CWD/januslinux-$RELEASE-$BARCH.iso \
		-b isolinux.bin \
		-c boot.cat \
		-input-charset UTF-8 \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		$IMAGE

	isohybrid $CWD/januslinux-$RELEASE-$BARCH.iso
}

generate_iso_arm() {
	mkdir -p $IMAGE/efi/boot
cat << CEOF > $IMAGE/efi/boot/startup.nsh
echo -off
echo januslinux starting...
\\vmlinuz quiet initrd=\\rootfs.cpio.xz
CEOF

	xorriso \
		-as mkisofs \
		-J -r -o $CWD/januslinux-$RELEASE-$BARCH.iso \
		-input-charset UTF-8 \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		$IMAGE

	isohybrid -u $CWD/januslinux-$RELEASE-$BARCH.iso 2>/dev/null || true
}

generate_iso() {
	case $BARCH in
		x86_64*|i686*)
			generate_iso_x86
			;;
		aarch64|armv7h)
			generate_iso_arm
			;;
		*)
			printmsgerror "Unsupported for $BARCH"
	esac
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
		clean_packages
		;;
	enter-chroot)
		check_for_root
		setup_environment
		enter_chroot
		;;
	stage)
		check_for_root
		setup_architecture
		setup_environment
		mountall
		generate_stage_archive
		umountall
		;;
	image)
		check_for_root
		setup_architecture
		setup_environment
		mountall
		generate_initrd
		generate_iso
		umountall
		;;
	usage|*)
		mkusage
esac

exit 0

