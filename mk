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
	stage				Build stage archive
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
		cd $CROSS/$dpkg
		makepkg --config $BUILD/target-makepkg.conf -d -c -C -f --skipchecksums
		yes y | sudo pacman -U $PKGS/$dpkg-*.pkg.tar.xz --root $ROOTFS --arch $BARCH
	done
}

build_target_only() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $CROSS/$dpkg
		makepkg --config $BUILD/target-makepkg.conf -d -c -C -f --skipchecksums
	done
}

install_target_only() {
	XPKG=$1
	for dpkg in $XPKG; do
		yes y | sudo pacman -U $PKGS/$dpkg*.pkg.tar.xz --root $ROOTFS --arch $BARCH
	done
}

install_target_nodeps() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $CROSS/$dpkg
		makepkg --config $BUILD/target-makepkg.conf -d -c -C -f --skipchecksums
		yes y | sudo pacman -U $PKGS/$dpkg-*.pkg.tar.xz --root $ROOTFS --arch $BARCH -dd
	done
}

install_target_multiple() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $CROSS/$dpkg
		makepkg --config $BUILD/target-makepkg.conf -d -c -C -f --skipchecksums
		yes y | sudo pacman -U $PKGS/$dpkg*.pkg.tar.xz --root $ROOTFS --arch $BARCH
	done
}

install_host_target() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $CROSS/$dpkg
		makepkg --config $BUILD/host-makepkg.conf -d -c -f -C --skipchecksums
		yes y | sudo pacman -U $PKGS/$dpkg-*.pkg.tar.xz --root $ROOTFS --arch $BARCH
	done
}

updatesumscross() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $CROSS/$dpkg
		updpkgsums
	done
}

updatesumsnative() {
	XPKG=$1
	for dpkg in $XPKG; do
		cd $REPO/$dpkg
		updpkgsums
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
			;;
		aarch64)
			print_green "Using config for aarch64"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
			;;
		armhf)
			print_green "Using config for armhf"
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-fpu=vfpv3 --with-float=hard"
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
	export STAGEFS="$BUILD/stagefs"
	export TOOLS="$BUILD/tools"
	export PKGS="$BUILD/packages"
	export LOGS="$BUILD/logs"
	export IMGDIR="$BUILD/imgdir"
	export TCREPO="$CWD/toolchain"
	export CROSS="$CWD/cross"
	export REPO="$CWD/packages"
}

setup_build_env() {
	sudo rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $FINALFS $TOOLS $PKGS $LOGS $IMGDIR $STAGEFS

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
	cp -a $CROSS/makepkg.conf $BUILD/target-makepkg.conf

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
	install_host binutils
	install_host gcc-static
	install_host_target linux-headers
	install_host_target musl
	install_host gcc-final
}

clean_tool_pkg() {
	for toolpkg in file pkgconf binutils gcc-static gcc-final; do
		rm -rf $PKGS/$toolpkg-*.pkg.tar.xz
	done
}

build_repository() {
	print_green "Building core packages"
	sleep 1
	case $BARCH in
		x86_64)
			export BOOTLOADER="grub syslinux efivar efibootmgr"
			;;
	esac

	for PKG in zlib m4 bison flex libelf binutils gmp mpfr mpc isl gcc attr acl libcap pkgconf ncurses util-linux e2fsprogs libtool bzip2 gdbm perl readline autoconf automake bash bc file gettext less kbd make xz kmod expat libressl ca-certificates patch gperf eudev busybox linux sudo libnl-tiny wireless_tools wpa_supplicant curl libarchive fakeroot pacman git dosfstools popt $BOOTLOADER; do
		case "$PKG" in
			gmp)
				install_target_nodeps gmp
				;;
			gcc)
				install_target_multiple gcc
				;;
			libtool)
				install_target_nodeps libtool
				;;
			*)
				install_target $PKG
		esac
	done
}

install_base_packages() {
	print_green "Installing base system"
	sudo rm -rf $STAGEFS
	sudo mkdir -p $STAGEFS/var/lib/pacman
	yes y | sudo pacman -U $PKGS/{filesystem,linux-headers,musl,zlib,m4,bison,flex,libelf,binutils,gmp,mpfr,mpc,isl,gcc,attr,acl,libcap,pkgconf,ncurses,util-linux,e2fsprogs,libtool,bzip2,gdbm,perl,readline,autoconf,automake,bash,bc,file,gettext,less,kbd,make,xz,kmod,expat,libressl,ca-certificates,patch,gperf,eudev,busybox,sudo,libnl-tiny,wireless_tools,wpa_supplicant,curl,libarchive,fakeroot,pacman,git,dosfstools}-*.pkg.tar.xz --root $STAGEFS --arch $BARCH
	case $BARCH in
		x86_64)
			yes y | sudo pacman -U $PKGS/linux*.pkg.tar.xz --root $STAGEFS --arch $BARCH
			;;
	esac
}

install_iso_packages() {
	print_green "Installing base system for *.iso image"
	sudo rm -rf $FINALFS
	sudo mkdir -p $FINALFS/var/lib/pacman
	yes y | sudo pacman -U $PKGS/{filesystem,linux,musl,gcc-libs,zlib,attr,acl,libcap,ncurses,util-linux,e2fsprogs,dosfstools,bzip2,gdbm,readline,bash,file,less,kbd,xz,kmod,expat,libressl,ca-certificates,eudev,busybox,libnl-tiny,wireless_tools,wpa_supplicant,curl,fakeroot,pacman,syslinux,efibootmgr,grub}-*.pkg.tar.xz --root $FINALFS --arch $BARCH
}

prepare_files() {
	print_green "Preparing files for .iso image"
	mkdir -p $IMGDIR/boot

	print_green "Building rootfs archive"
	cd $FINALFS
	sudo find . -print | cpio -o -H newc | gzip -9 > $IMGDIR/boot/rootfs.gz

	print_green "Copying kernel"
	cp $FINALFS/boot/vmlinuz $IMGDIR/boot/vmlinuz
}

install_loader() {
	print_green "Preparing syslinux for .iso image"
	cd $BUILD
	rm -rf syslinux-*
	cp $SOURCES/syslinux-* .
	tar -xf syslinux-*

	mkdir -p $IMGDIR/boot/syslinux
	cp syslinux-*/bios/core/isolinux.bin $IMGDIR/boot/syslinux
	cp syslinux-*/bios/com32/elflink/ldlinux/ldlinux.c32 $IMGDIR/boot/syslinux

cat << CEOF > $IMGDIR/boot/syslinux/syslinux.cfg
PROMPT 1
TIMEOUT 50
DEFAULT boot

LABEL boot
	LINUX /boot/vmlinuz
	APPEND quiet
	INITRD /boot/rootfs.gz
CEOF

	mkdir -p $IMGDIR/efi/boot
cat << CEOF > $IMGDIR/efi/boot/startup.nsh
echo -off
echo Booting, please wait...
\boot\vmlinuz quiet initrd=\boot\rootfs.gz
CEOF
}

make_iso() {
	print_green "Generating .iso image"
	cd $IMGDIR
	xorriso \
		-as mkisofs \
		-o $CWD/januslinux.iso \
		-b boot/syslinux/isolinux.bin \
		-c boot/syslinux/boot.cat \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		$IMGDIR

	print_green "Generation of .iso file was completed!"
}

build_iso_image() {
	case $BARCH in
		x86_64)
			prepare_files
			install_loader
			make_iso
			;;
		*)
			print_red "Building .iso file isn't supported for architecture"
			exit 1
	esac
}

build_stage_archive() {
	print_green "Generating stage archive"
	cd $STAGEFS
	sudo tar -cJf $CWD/januslinux.tar.xz .
	print_green "Generation stage archive was completed!"
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
	host-package)
		configure_arch
		setup_build_dirs
		install_host $JPKG
		;;
	update-package)
		configure_arch
		setup_build_dirs
		rm -rf $PKGS/$JPKG-*.pkg.tar.xz
		install_target $JPKG
		;;
	image)
		configure_arch
		setup_build_dirs
		install_iso_packages
		build_iso_image
		;;
	stage)
		configure_arch
		setup_build_dirs
		install_base_packages
		build_stage_archive
		;;
	update-sums-cross)
		setup_build_dirs
		updatesumscross $JPKG
		;;
	update-sums-native)
		setup_build_dirs
		updatesumsnative $JPKG
		;;
	usage|*)
		mkusage
esac

exit 0

