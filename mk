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

setup_build_env() {
	print_green "Setting up build environment"
	export CWD="$(pwd)"
	export BUILD="$CWD/build"
	export SOURCES="$BUILD/sources"
	export ROOTFS="$BUILD/rootfs"
	export FINALFS="$BUILD/finalfs"
	export IMAGEFS="$BUILD/imagefs"
	export TOOLS="$BUILD/tools"
	export PKGS="$BUILD/packages"
	export LOGS="$BUILD/logs"
	export ISODIR="$BUILD/isodir"
	export REPO="$CWD/packages"
	export TCREPO="$CWD/toolchain"

	sudo rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $FINALFS $TOOLS $PKGS $LOGS $IMAGEFS $ISODIR

	export LC_ALL="POSIX"
	export PATH="$TOOLS/bin:$PATH"
	export MKOPTS="-j$(expr $(nproc) + 1)"
	export HOSTCC="gcc"
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
			-e "s|@LC_ALL[@]|$LC_ALL|g" \
			-e "s|@HOSTCC[@]|$HOSTCC|g" \
			-e "s|@PATH[@]|$PATH|g"
	done

	mkdir -p {$ROOTFS,$TOOLS}/var/lib/pacman

	cd $TOOLS
	mkdir -p {bin,include,lib,$XTARGET/{bin,include,lib}}
}

build_toolchain() {
	print_green "Building cross-toolchain for $BARCH"
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
	case $BARCH in
		x86_64)
			export BOOTLOADER="grub"
			;;
		aarch64)
			export BOOTLOADER=""
			;;
	esac

	for PKG in zlib m4 bison flex libelf binutils gmp mpfr mpc gcc attr acl libcap pkgconf ncurses util-linux e2fsprogs libtool bzip2 perl gdbm readline autoconf automake bash bc file less kbd make xz kmod expat libressl ca-certificates libffi python patch busybox gperf openrc eudev linux $BOOTLOADER libarchive dropbear libnl-tiny wireless_tools wpa_supplicant curl git fakeroot pacman rsync cmake; do
		install_target $PKG
	done
}

build_stage_archive() {
	print_green "Installing core packages"

	sudo mkdir -p $FINALFS/var/lib/pacman
	yes y | sudo pacman -U $PKGS/{filesystem,linux-headers,musl,zlib,m4,bison,flex,libelf,binutils,gmp,mpfr,mpc,gcc,attr,acl,libcap,pkgconf,ncurses,util-linux,e2fsprogs,libtool,bzip2,perl,gdbm,readline,autoconf,automake,bash,bc,file,less,kbd,make,xz,kmod,libressl,ca-certificates,patch,busybox,gperf,openrc,eudev,libarchive,libnl-tiny,wireless_tools,wpa_supplicant,curl,fakeroot,pacman}-*.pkg.tar.xz --root $FINALFS --arch $BARCH

	yes y | sudo pacman -U $PKGS/linux-*.pkg.tar.xz --root $FINALFS --arch $BARCH

	case $BARCH in
		x86_64)
			yes y | sudo pacman -U $PKGS/grub-*.pkg.tar.xz --root $FINALFS --arch $BARCH
			;;
	esac

	print_green "Generating stage archive"
	cd $FINALFS
	sudo tar cfJ $CWD/januslinux-1.0-$(date -Idate)-$BARCH.tar.xz .
}

build_installer_image() {
	print_green "Installing installer packages"
	sudo mkdir -p $IMAGEFS/var/lib/pacman
	yes y | sudo pacman -U $PKGS/{filesystem,linux-headers,musl,zlib,attr,acl,libcap,ncurses,util-linux,e2fsprogs,gdbm,readline,bash,file,less,kbd,xz,kmod,libressl,ca-certificates,busybox,gperf,openrc,eudev,libnl-tiny,wireless_tools,wpa_supplicant}-*.pkg.tar.xz --root $IMAGEFS --arch $BARCH
	yes y | sudo pacman -U $PKGS/linux-*.pkg.tar.xz --root $IMAGEFS --arch $BARCH
}

build_iso_image() {
	print_green "Generating initrd image"
	cd $IMAGEFS
	find . -print | cpio -o -H newc | gzip -9 > $ISODIR/rootfs.gz

	print_green "Copying Linux kernel image"
	cp $IMAGEFS/boot/vmlinuz $ISODIR/bzImage

	print_green "Generating .iso image"
	cd $SOURCES
	wget https://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
	tar -xf syslinux-6.03.tar.xz

	cd $ISODIR
	cp $SOURCES/syslinux-6.03/bios/core/isolinux.bin $ISODIR/isolinux.bin
	cp $SOURCES/syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 $ISODIR/ldlinux.c32

	mkdir -p $ISODIR/efi/boot

cat << CEOF > $ISODIR/efi/boot/startup.nsh
echo -off
echo januslinux is starting...
\\bzImage initrd=\\rootfs.gz
CEOF

	echo 'default bzImage initrd=rootfs.gz' > ${isodir}/isolinux.cfg
		
	xorriso \
		-as mkisofs -J -r \
		-o $CWD/januslinux-1.0-$(date -Idate)-$BARCH.iso \
		-b isolinux.bin \
		-c boot.cat \
		-input-charset UTF-8 \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		$ISODIR

	print_green "januslinux was build successfuly"
	cd $CWD
}

configure_arch
setup_build_env
prepare_build
build_toolchain
clean_tool_pkg
build_repository
build_stage_archive
build_installer_image
build_iso_image

exit 0

