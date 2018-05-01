#!/bin/sh

set -e

install_host() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $TCREPO/$dpkg
		makepkg --config $BUILD/host-makepkg.conf -d -c -C -f --skipchecksums
		yes y | sudo pacman -U $PKGS/$dpkg-*.pkg.tar.xz --root $TOOLS --force
	done
}

install_target() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $REPO/$dpkg
		makepkg --config $BUILD/target-makepkg.conf -d -c -C -f --skipchecksums
		yes y | sudo pacman -U $PKGS/$dpkg-*.pkg.tar.xz --root $ROOTFS --arch $BARCH
	done
}

install_host_target() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $REPO/$dpkg
		makepkg --config $BUILD/host-makepkg.conf -d -c -f -C --skipchecksums
		yes y | sudo pacman -U $PKGS/$dpkg-*.pkg.tar.xz --root $ROOTFS --arch $BARCH
	done
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
		*)
			echo "BARCH variable isn't set!"
			exit 1
	esac
}

setup_build_env() {
	export CWD="$(pwd)"
	export BUILD="$CWD/build"
	export SOURCES="$BUILD/sources"
	export ROOTFS="$BUILD/rootfs"
	export TOOLS="$BUILD/tools"
	export PKGS="$BUILD/packages"
	export LOGS="$BUILD/logs"
	export REPO="$CWD/packages"
	export TCREPO="$CWD/toolchain"

	sudo rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $TOOLS $PKGS $LOGS

	export LC_ALL="POSIX"
	export PATH="$TOOLS/bin:$PATH"
	export MKOPTS="-j$(expr $(nproc) + 1)"
	export HOSTCC="gcc"
}

prepare_build() {
	export CFLAGS="-Os -g0"
	export CXXFLAGS="$CFLAGS"
	export LDFLAGS="-s"

	cp -a $TCREPO/makepkg.conf $BUILD/host-makepkg.conf
	cp -a $REPO/makepkg.conf $BUILD/target-makepkg.conf

	for files in $BUILD/host-makepkg.conf $BUILD/target-makepkg.conf; do
		sed -i $files \
			-e "s|@CARCH[@]|$BARCH|g" \
			-e "s|@CHOST[@]|$XTARGET|g" \
			-e "s|@CFLAGS[@]|$CFLAGS|g" \
			-e "s|@CXXFLAGS[@]|$CXXFLAGS|g" \
			-e "s|@LDFLAGS[@]|$LDFLAGS|g" \
			-e "s|@MKOPTS[@]|$MKOPTS|g" \
			-e "s|@PKGS[@]|$PKGS|g" \
			-e "s|@SOURCES[@]|$SOURCES|g" \
			-e "s|@LOGS[@]|$LOGS|g" \
			-e "s|@ROOTFS[@]|$ROOTFS|g" \
			-e "s|@TOOLS[@]|$TOOLS|g" \
			-e "s|@UTILS[@]|$UTILS|g" \
			-e "s|@XHOST[@]|$XHOST|g" \
			-e "s|@XTARGET[@]|$XTARGET|g" \
			-e "s|@XKARCH[@]|$XKARCH|g" \
			-e "s|@GCCOPTS[@]|$GCCOPTS|g" \
			-e "s|@LC_ALL[@]|$LC_ALL|g" \
			-e "s|@HOSTCC[@]|$HOSTCC|g" \
			-e "s|@PATH[@]|$PATH|g"
	done

	mkdir -p {$ROOTFS,$TOOLS}/var/lib/pacman

	cd $TOOLS
	mkdir -p {bin,include,lib,$XTARGET/{bin,include,lib}}
}

build_toolchain() {
	install_host file
	install_host pkgconf
	install_host_target filesystem
	install_host_target linux-headers
	install_host binutils
	install_host gcc-static
	install_host_target musl
	install_host gcc-final
}

clean_tool_pkg() {
	for toolpkg in file pkgconf binutils gcc-static gcc-final; do
		rm -rf $PKGS/$toolpkg-*.pkg.tar.xz
	done
}

build_rootfs() {
	for PKG in zlib m4 bison flex libelf binutils gmp mpfr mpc gcc attr acl libcap sed pkgconf ncurses shadow util-linux e2fsprogs procps-ng coreutils libtool iproute2 bzip2 perl gdbm readline autoconf automake bash bc file gawk findutils pcre grep less gzip iputils kbd libpipeline make xz kmod expat libressl patch psmisc tar gperf eudev; do
		install_target $PKG
	done
}

configure_arch
setup_build_env
prepare_build
build_toolchain
clean_tool_pkg
build_rootfs

exit 0

