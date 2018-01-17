#!/bin/sh

set -e

usage() {
	cat <<EOF

mk - the JanusLinux build tool.

Usage: sudo BARCH=[supported architecture] ./mk [one of following option]

	toolchain	Build a cross-toolchain
	image		Build a bootable *.iso image
	container	Build a docker container
	all		Build a full JanusLinux system

EOF
	exit 0
}

check_root() {
	if [ $(id -u) -ne 0 ]; then
		echo "You must be root to execute: $(basename $0) $@"
		exit 1
	fi
}

setup_build_env() {
	export BUILD="$(pwd)/build"
	export SOURCES="$BUILD/sources"
	export ROOTFS="$BUILD/rootfs"
	export TOOLS="$BUILD/tools"
	export KEEP="$(pwd)/KEEP"

	rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $TOOLS

	export LC_ALL=POSIX

	export PATH="$TOOLS/bin:$PATH"

	export XCONFIGURE="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --bindir=/usr/bin --sbindir=/usr/bin --sysconfdir=/etc --localstatedir=/var --enable-shared --disable-static"

	export JOBS="$(expr $(nproc) + 1)"
}

configure_arch() {
	case $BARCH in
		x86_64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-pc-linux-musl"
			export XKARCH="x86_64"
			export GCCOPTS="--with-arch=x86-64 --with-tune=generic --enable-long-long"
			;;
		i686)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="i686-pc-linux-musl"
			export XKARCH="i386"
			export GCCOPTS="--with-arch=i686 --with-tune=generic"
			;;
		arm64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-pc-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
			;;
		arm)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-pc-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-float=hard --with-fpu=neon"
			;;
		*)
			echo "BARCH variable isn't set..."
			exit 0
	esac
}

case "$1" in
	toolchain)
		check_root
		configure_arch
		setup_build_env
		build_toolchain
		;;
	usage|*)
		usage
esac

exit 0

