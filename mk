#!/bin/sh

set -e

initdb() {
	local dir="$@"
	for dbindir in $dir; do
		mkdir -p $dbindir/var/lib/pkg
		touch $dbindir/var/lib/pkg/db
	done
}

pkginstall() {
	local pkg="$@"
	for mergepkg in $pkg; do
		cd $REPO/$mergepkg
		pkgmk -d -if -im -is -cf $CHREPO/pkgmk.conf
		pkgadd $PACKAGES/$mergepkg#*.pkg.tar.xz --root $ROOTFS
	done
}

pkgbuildonly() {
	local pkg="$@"
	for mergepkg in $pkg; do
		cd $REPO/$mergepkg
		pkgmk -d -if -im -is -cf $CHREPO/pkgmk.conf
	done
}

pkgchinstall() {
	local pkg="$@"
	for mergepkg in $pkg; do
		cd $CHREPO/$mergepkg
		pkgmk -d -if -im -is -cf $CHREPO/pkgmk.conf
		pkgadd $PACKAGES/chroot-$mergepkg#*.pkg.tar.xz --root $ROOTFS -f
	done
}

pkgtcinstall() {
	local pkg="$@"
	for mergepkg in $pkg; do
		cd $TCREPO/$mergepkg
		pkgmk -d -if -im -is -cf $TCREPO/pkgmk.conf
		pkgadd $PACKAGES/host-$mergepkg#*.pkg.tar.xz --root $TOOLS -f
	done
}

check_for_root() {
	if [[ $EUID -ne 0 ]]; then
		echo "This script must be run as root"
		exit 1 
	fi
}

setup_architecture() {
	case $BARCH in
		x86_64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-linux-musl"
			export XKARCH="x86_64"
			export GCCOPTS="--with-arch=x86-64 --with-tune=generic"
			;;
		aarch64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --enable-fix-cortex-a53-835769 --enable-fix-cortex-a53-843419"
			;;
		*)
			echo "Architecture is not set or is not supported by 'mk'"
			exit 1
	esac
}

setup_environment() {
	export CWD="$(pwd)"
	export BUILD="$CWD/build"
	export SOURCES="$BUILD/sources"
	export PACKAGES="$BUILD/packages"
	export ROOTFS="$BUILD/rootfs"
	export TOOLS="$BUILD/tools"
	export ISODIR="$BUILD/isodir"
	export INITRD="$BUILD/initrd"
	export STAGE="$BUILD/stage"
	export REPO="$CWD/packages"
	export TCREPO="$CWD/toolchain"
	export CHREPO="$CWD/chroot"

	export LC_ALL="POSIX"
	export PATH="$TOOLS/bin:$PATH"
	export HOSTCC="gcc"
	export HOSTCXX="g++"
	export MKOPTS="-j$(expr $(nproc) + 1)"

	export CFLAGS="-Os -pipe"
	export CXXFLAGS="$CFLAGS"
}

build_environment() {
	rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $PACKAGES $ROOTFS $TOOLS $ISODIR $INITRD $STAGE

	initdb $TOOLS $ROOTFS $INITRD $STAGE
}

build_toolchain() {
	pkgtcinstall file
	pkgtcinstall pkgconf
	pkgtcinstall binutils
	pkgtcinstall gcc-static
	pkgchinstall linux-headers
	pkgchinstall musl
	pkgtcinstall gcc
}

cleanup_toolchain() {
	rm -rf $PACKAGES/host*
}

bootstrap_rootfs() {
	pkginstall filesystem
	pkgchinstall etc
	pkgchinstall busybox
	pkgchinstall zlib
	pkgchinstall binutils
	pkgchinstall gcc
	pkgchinstall make
	pkgchinstall file
	pkgchinstall ncurses
	pkgchinstall bash
	pkgchinstall xz
	pkgchinstall patch
	pkgchinstall perl
	pkgchinstall openssl
	pkgchinstall curl
	pkgchinstall libarchive
	pkgchinstall npkg
	pkgchinstall scripts
	pkgbuildonly linux-headers
}

cleanup_bootstrap() {
	rm -rf $PACKAGES/chroot*
	find $ROOTFS -name \*.la -delete
}

make_symlinks() {
	for file in awk cat dd echo env file grep ln ls pwd rm sed stty; do
		ln -sf /tools/bin/${file} $ROOTFS/usr/bin
	done

	for file in bash sh; do
		ln -sf /tools/bin/bash $ROOTFS/usr/bin/${file}
	done

	ln -sf gcc $ROOTFS/tools/bin/cc
	ln -sf /tools/bin/perl $ROOTFS/usr/bin
	ln -sf /tools/bin/install $ROOTFS/usr/bin

	ln -sf /tools/lib/libgcc_s.so $ROOTFS/usr/lib
	ln -sf /tools/lib/libgcc_s.so.1 $ROOTFS/usr/lib

	ln -sf /tools/lib/libstdc++.so $ROOTFS/usr/lib
	ln -sf /tools/lib/libstdc++.so.6 $ROOTFS/usr/lib
	ln -sf /tools/lib/libstdc++.a $ROOTFS/usr/lib

	ln -sf /tools/lib/libssp.so $ROOTFS/usr/lib
	ln -sf /tools/lib/libssp.so.0 $ROOTFS/usr/lib
	ln -sf /tools/lib/libssp.so.0.0.0 $ROOTFS/usr/lib
	ln -sf /tools/lib/libssp.a $ROOTFS/usr/lib
	ln -sf /tools/lib/libssp_nonshared.a $ROOTFS/usr/lib

	ln -sf /tools/lib/libc.so $ROOTFS/usr/lib/libc.so

	case $BARCH in
		x86_64)
			export ALINKER="ld-musl-x86_64.so.1"
			;;
		aarch64)
			export ALINKER="ld-musl-aarch64.so.1"
			;;
	esac

	ln -sf /tools/lib/libc.so $ROOTFS/usr/lib/$ALINKER
}

enter_chroot() {
	set +e
	mkdir -p $ROOTFS/output/{stage,initrd,packages,sources}
	mkdir -p $ROOTFS/usr/janus/packages

	rm -rf $ROOTFS/etc/resolv.conf
	touch $ROOTFS/etc/resolv.conf
	cat $(realpath /etc/resolv.conf) >> $ROOTFS/etc/resolv.conf

	mount --bind /proc $ROOTFS/proc
	mount --bind /sys $ROOTFS/sys
	mount --bind /dev $ROOTFS/dev
	mount --bind /tmp $ROOTFS/tmp

	mount --bind $CWD/packages $ROOTFS/usr/janus/packages

	mount --bind $BUILD/packages $ROOTFS/output/packages
	mount --bind $BUILD/sources $ROOTFS/output/sources
	mount --bind $BUILD/stage $ROOTFS/output/stage
	mount --bind $BUILD/initrd $ROOTFS/output/initrd

	chroot $ROOTFS /usr/bin/env -i \
		TERM="$TERM" \
		PS1='(januslinux chroot) \u:\w\$ ' \
		PATH="/usr/bin:/tools/bin" \
		LD_LIBRARY_PATH="/usr/lib:/tools/lib" \
		/tools/bin/ash --login

	umount $ROOTFS/usr/janus/packages
	umount $ROOTFS/proc
	umount $ROOTFS/sys
	umount $ROOTFS/dev
	umount $ROOTFS/tmp
	umount $ROOTFS/output/sources
	umount $ROOTFS/output/packages
	umount $ROOTFS/output/stage
	umount $ROOTFS/output/initrd
	set -e
}

case "$1" in
	toolchain)
		check_for_root
		setup_architecture
		setup_environment
		build_environment
		build_toolchain
		cleanup_toolchain
		;;
	bootstrap)
		check_for_root
		setup_architecture
		setup_environment
		build_environment
		build_toolchain
		cleanup_toolchain
		bootstrap_rootfs
		cleanup_bootstrap
		make_symlinks
		;;
	enter-chroot)
		check_for_root
		setup_environment
		enter_chroot
		;;
	usage|*)
		echo "In development"
esac

exit 0
