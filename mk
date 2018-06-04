#!/bin/sh

set -e

mkusage() {
	cat <<EOF
mk - small and simple januslinux build system

Usage:	BARCH=[supported architecture] ./mk [option] [package (only in 'package' option)]
	toolchain			Build cross-toolchain
	repository			Build every package
	package				Build specific package
	image				Build bootable .iso image
EOF
	exit 0
}

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

install_target_nodeps() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $REPO/$dpkg
		makepkg --config $BUILD/target-makepkg.conf -d -c -C -f --skipchecksums
		yes y | sudo pacman -U $PKGS/$dpkg-*.pkg.tar.xz --root $ROOTFS --arch $BARCH -dd
	done
}

install_target_multiple() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $REPO/$dpkg
		makepkg --config $BUILD/target-makepkg.conf -d -c -C -f --skipchecksums
		yes y | sudo pacman -U $PKGS/$dpkg*.pkg.tar.xz --root $ROOTFS --arch $BARCH
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

print_green() {
	local msg=$(echo $1 | tr -s / /)
	printf "\e[1m\e[32m>>>\e[0m $msg\n"
}

print_red() {
	local msg=$(echo $1 | tr -s / /)
	printf "\e[1m\e[31m>>>\e[0m $msg\n"
}

configure_arch() {
	case $BARCH in
		x86_64)
			print_green "Using config for x86_64"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-linux-musl"
			export XKARCH="x86_64"
			export GCCOPTS="--with-arch=x86-64 --with-tune=generic --enable-long-long"
			;;
		aarch64)
			print_green "Using config for aarch64"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
			;;
		*)
			print_red "BARCH variable isn't set!"
			exit 1
	esac
}

setup_build_dirs() {
	print_green "Setting up build environment"
	sleep 1
	export CWD="$(pwd)"
	export BUILD="$CWD/build"
	export SOURCES="$BUILD/sources"
	export ROOTFS="$BUILD/rootfs"
	export FINALFS="$BUILD/finalfs"
	export TOOLS="$BUILD/tools"
	export PKGS="$BUILD/packages"
	export LOGS="$BUILD/logs"
	export REPO="$CWD/packages"
	export TCREPO="$CWD/toolchain"
}

setup_build_env() {
	sudo rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $FINALFS $TOOLS $PKGS $LOGS

	export PATH="$TOOLS/bin:$PATH"
	export MKOPTS="-j$(expr $(nproc) + 1)"
	export HOSTCC="gcc"
	export HOSTCXX="g++"
}

prepare_build() {
	export CFLAGS="-Os -g0"
	export CXXFLAGS="$CFLAGS"
	export CPPFLAGS="-D_FORTIFY_SOURCE=2"
	export LDFLAGS="-s"

	cp -a $TCREPO/makepkg.conf $BUILD/host-makepkg.conf
	cp -a $REPO/makepkg.conf $BUILD/target-makepkg.conf

	for files in $BUILD/host-makepkg.conf $BUILD/target-makepkg.conf; do
		sed -i $files \
			-e "s|@CARCH[@]|$BARCH|g" \
			-e "s|@CHOST[@]|$XTARGET|g" \
			-e "s|@CFLAGS[@]|$CFLAGS|g" \
			-e "s|@CXXFLAGS[@]|$CXXFLAGS|g" \
			-e "s|@CPPFLAGS[@]|$CPPFLAGS|g" \
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
			-e "s|@HOSTCC[@]|$HOSTCC|g" \
			-e "s|@HOSTCXX[@]|$HOSTCXX|g" \
			-e "s|@PATH[@]|$PATH|g"
	done

	mkdir -p {$ROOTFS,$TOOLS}/var/lib/pacman

	cd $TOOLS
	mkdir -p {bin,include,lib,$XTARGET/{bin,include,lib}}
}

build_toolchain() {
	print_green "Building cross-toolchain for $BARCH"
	sleep 1
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

build_repository() {
	print_green "Building repository"
	sleep 1
	case $BARCH in
		x86_64)
			export BOOTLOADER="syslinux"
			;;
		aarch64)
			export BOOTLOADER=""
			;;
	esac

	for PKG in zlib m4 bison flex libelf binutils gmp mpfr mpc gcc attr acl libcap pkgconf ncurses util-linux e2fsprogs libtool bzip2 gdbm perl readline autoconf automake bash bc file less kbd make xz kmod expat libressl ca-certificates patch gperf eudev busybox linux $BOOTLOADER openssh sudo libffi python python2 libarchive libnl-tiny wireless_tools wpa_supplicant curl git fakeroot pacman rsync cmake re2c ninja meson base build-essential; do
		case "$PKG" in
			gmp)
				install_target_nodeps gmp
				;;
			gcc)
				install_target_multiple gcc
				;;
			*)
				install_target $PKG
		esac
	done

	print_green "Building repository database"
	sleep 1
	repo-add $PKGS/repo.db.tar.gz $PKGS/*.pkg.tar.xz
}

install_base_packages() {
	print_green "Installing base system"
	sleep 1
	cp -a $REPO/pacman.conf $BUILD/target-pacman.conf
	sed -i $BUILD/target-pacman.conf -e "s|@PKGS[@]|$PKGS|g"
	sudo mkdir -p $FINALFS/var/lib/pacman
	sudo pacman -Syy --root $FINALFS --arch $BARCH --config $BUILD/target-pacman.conf
	yes y | sudo pacman -S base --root $FINALFS --arch $BARCH --config $BUILD/target-pacman.conf
}

OPT="$1"
JPKG="$2"

case "$OPT" in
	toolchain)
		configure_arch
		setup_build_dirs
		setup_build_env
		prepare_build
		build_toolchain
		clean_tool_pkg
		;;
	repository)
		configure_arch
		setup_build_dirs
		setup_build_env
		prepare_build
		build_toolchain
		clean_tool_pkg
		build_repository
		;;
	package)
		configure_arch
		setup_build_dirs
		install_target $JPKG
		;;
	image)
		configure_arch
		setup_build_dirs
		install_base_packages
#		build_iso_image
		;;
	usage|*)
		mkusage
esac

exit 0

