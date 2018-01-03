#!/bin/sh

set -e

usage() {
	echo "Soon!"
}

check_root() {
	if [ $(id -u) -ne 0 ]; then
		echo "You must be root to execute: $(basename $0) $@"
		exit 1
	fi
}

prepare_build() {
	export CWD="$(pwd)"
	export SOURCES="$(pwd)/sources"
	export ROOTFS="$(pwd)/rootfs"
	export TOOLS="$(pwd)/tools"
	export ISODIR="$(pwd)/iso"
	export KEEP="$(pwd)/KEEP"

	rm -rf $SOURCES $ROOTFS $TOOLS $ISODIR
	mkdir -p $SOURCES $ROOTFS $TOOLS $ISODIR

	export MAKEOPTS="-j$(expr $(nproc) + 1)"

	export PATH="$TOOLS/bin:$PATH"

	export LC_ALL=POSIX
	export LANG=POSIX

	export CONFIGURE="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --bindir=/usr/bin --sbindir=/usr/bin --sysconfdir=/etc --localstatedir=/var --disable-static"

	export XCFLAGS="-g0 -Os -s -pipe -fno-stack-protector -fomit-frame-pointer -U_FORTIFY_SOURCE"
	export XCXXFLAGS="$XCFLAGS"
	export XLDFLAGS="-s"
}

prepare_cross() {
	case $BARCH in
		x86_64)
			export XTARGET="x86_64-linux-musl"
			export XKARCH="x86_64"
			;;
		i486)
			export XTARGET="i486-linux-musl"
			export XKARCH="i386"
			;;
		arm64)
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			;;
		arm)
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			;;
		*)
			echo "BARCH variable isn't set..."
			exit 0
	esac
}

build_prepare() {
	unset CFLAGS CXXFLAGS LDFLAGS
	export CFLAGS="$XCFLAGS"
	export CXXFLAGS="$XCXXFLAGS"
	export LDFLAGS="$XLDFLAGS -Wl,-rpath,$ROOTFS/usr/lib"
	export CC="$XTARGET-gcc --sysroot=$ROOTFS"
	export CXX="$XTARGET-g++ --sysroot=$ROOTFS"
	export LD="$XTARGET-ld --sysroot=$ROOTFS"
	export AS="$XTARGET-as --sysroot=$ROOTFS"
	export AR="$XTARGET-ar"
	export NM="$XTARGET-nm"
	export OBJCOPY="$XTARGET-objcopy"
	export RANLIB="$XTARGET-ranlib"
	export READELF="$XTARGET-readelf"
	export STRIP="$XTARGET-strip"
	export SIZE="$XTARGET-size"
}

get_toolchain() {
	cd $SOURCES
	wget -c https://github.com/jprjr/musl-cross-make-static/releases/download/4/gcc-7.2.0-$XTARGET.tar.gz
	tar -xf gcc-7.2.0-$XTARGET.tar.gz -C $TOOLS
}

setup_rootfs() {
	mkdir -p $ROOTFS/{boot,dev,etc/{init.d,skel},home}
	mkdir -p $ROOTFS/{mnt,opt,proc,srv,sys}
	mkdir -p $ROOTFS/var/{cache,lib,local,lock,log,opt,run,spool}
	install -d -m 0750 $ROOTFS/root
	install -d -m 1777 $ROOTFS/{var/,}tmp
	mkdir -p $ROOTFS/usr/{,local/}{bin,include,lib/modules,share}

	cd $ROOTFS/usr
	ln -sf bin sbin

	cd $ROOTFS
	ln -sf usr/bin bin
	ln -sf usr/lib lib
	ln -sf usr/bin sbin

	ln -sf /proc/mounts $ROOTFS/etc/mtab

	for f in fstab host.conf hosts issue profile shadow sysctl.conf group hostname inittab passwd securetty shells; do
		install -m644 $KEEP/$f $ROOTFS/etc
	done

	chmod 640 $ROOTFS/etc/shadow

	for f in rcS rc.shutdown rc.dhcp; do
		install -m644 $KEEP/$f $ROOTFS/etc/init.d
		chmod +x $ROOTFS/etc/init.d/$f
	done

	touch $ROOTFS/var/log/lastlog
	chmod 664 $ROOTFS/var/log/lastlog
}

cook_system() {
	cd $SOURCES
	wget -c http://sethwklein.net/iana-etc-2.30.tar.bz2
	tar -xf iana-etc-2.30.tar.bz2
	cd iana-etc-2.30
	make get
	make STRIP=yes
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.11.tar.xz
	tar -xf linux-4.14.11.tar.xz
	cd linux-4.14.11
	make mrproper
	make ARCH=$XKARCH CROSS_COMPILE="$XTARGET-" INSTALL_HDR_PATH=$ROOTFS/usr headers_install

	cd $SOURCES
	wget -c http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	CROSS_COMPILE="$XTARGET-" \
	./configure \
		$CONFIGURE \
		--syslibdir=/usr/lib \
		--enable-optimize \
		--host=$XTARGET
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c https://sortix.org/libz/release/libz-1.2.8.2015.12.26.tar.gz
	tar -xf libz-1.2.8.2015.12.26.tar.gz
	cd libz-1.2.8.2015.12.26
	CROSS_COMPILE="$XTARGET-" \
	./configure \
		$CONFIGURE \
		--host=$XTARGET
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.bz2
	tar -xf binutils-2.29.1.tar.bz2
	cd binutils-2.29.1
	mkdir build
	cd build
	CROSS_COMPILE="$XTARGET-" \
	../configure \
		$CONFIGURE \
		--with-sysroot=$ROOTFS \
		--with-system-zlib \
		--enable-gold \
		--enable-ld=default \
		--enable-plugins \
		--disable-multilib \
		--disable-nls \
		--disable-werror \
		--host=$XTARGET
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SOURCES
	wget http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	tar -xf gmp-6.1.2.tar.xz
	cd gmp-6.1.2
	CROSS_COMPILE=$XTARGET- \
	./configure \
		$CONFIGURE \
		--enable-cxx \
		--host=$XTARGET
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SOURCES
	wget http://www.mpfr.org/mpfr-3.1.6/mpfr-3.1.6.tar.xz
	tar -xf mpfr-3.1.6.tar.xz
	cd mpfr-3.1.6
	CROSS_COMPILE=$XTARGET- \
	./configure \
		$CONFIGURE \
		--with-gmp=$ROOTFS/usr \
		--host=$XTARGET
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SOURCES
	wget http://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz
	tar -xf mpc-1.0.3.tar.gz
	cd mpc-1.0.3
	CROSS_COMPILE=$XTARGET- \
	./configure \
		$CONFIGURE \
		--with-gmp=$ROOTFS/usr \
		--with-mpfr=$ROOTFS/usr \
		--host=$XTARGET
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

#	cd $SOURCES
#	wget -c http://ftp.gnu.org/gnu/gcc/gcc-7.2.0/gcc-7.2.0.tar.xz
#	tar -xf gcc-7.2.0.tar.xz
#	cd gcc-7.2.0
#	mkdir build
#	cd build
#	CROSS_COMPILE="$XTARGET-" \
#	../configure \
#		$CONFIGURE \
#		--with-system-zlib \
#		--enable-deterministic-archives \
#		--enable-threads=posix \
#		--enable-clocale=generic \
#		--enable-languages=c,c++ \
#		--enable-libstdcxx-time \
#		--enable-tls \
#		--enable-lto \
#		--enable-libssp \
#		--disable-bootstrap \
#		--disable-decimal-float \
#		--disable-fixed-point \
#		--disable-gnu-indirect-function \
#		--disable-libmpx \
#		--disable-libmudflap \
#		--disable-libquadmath \
#		--disable-libstdcxx-pch \
#		--disable-libsanitizer \
#		--disable-multilib \
#		--disable-nls \
#		--disable-symvers \
#		--disable-werror \
#		--host=$XTARGET
#	make AS_FOR_TARGET="$XTARGET-as" LD_FOR_TARGET="$XTARGET-ld" $MAKEOPTS
#	make DESTDIR=$ROOTFS install
#	rm -rf $ROOTFS/usr/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/make/make-4.2.1.tar.bz2
	tar -xf make-4.2.1.tar.bz2
	cd make-4.2.1
	CROSS_COMPILE="$XTARGET-" \
	./configure \
		$CONFIGURE \
		--without-dmalloc \
		--without-guile \
		--disable-nls \
		--host=$XTARGET
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-0.2.1.tar.xz
	tar -xf netbsd-curses-0.2.1.tar.xz
	cd netbsd-curses-0.2.1
	cat << EOF > config.mak
CC=$XTARGET-gcc --sysroot=$ROOTFS
CFLAGS="$XFLAGS -fPIC"
PREFIX=/usr
DESTDIR=$ROOTFS
EOF
	make $MAKEOPTS
	make install

	cd $SOURCES
	wget -c https://github.com/MirBSD/mksh/archive/mksh-R56b.tar.gz
	tar -xf mksh-R56b.tar.gz
	cd mksh-R56b
	sh Build.sh -r
	install -D -m 755 mksh $ROOTFS/usr/bin/mksh
	cd $ROOTFS/usr/bin
	ln -sf mksh sh

	cd $SOURCES
	wget -c https://www.kernel.org/pub/linux/utils/fs/xfs/xfsprogs/xfsprogs-4.14.0.tar.xz
	tar -xf xfsprogs-4.14.0.tar.xz
	cd xfsprogs-4.14.0
	CROSS_COMPILE="$XTARGET-" \
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c http://busybox.net/downloads/busybox-1.28.0.tar.bz2
	tar -xf busybox-1.28.0.tar.bz2
	cd busybox-1.28.0
	make ARCH=$XKARCH CROSS_COMPILE="$XTARGET-" defconfig
	sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config
	sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config
	make ARCH=$XKARCH CROSS_COMPILE="$XTARGET-" $MAKEOPTS
	cp busybox $ROOTFS/usr/bin
	cd $ROOTFS
	ln -sf usr/bin/busybox init
	chroot $ROOTFS /usr/bin/busybox --install -s

	cd $SOURCES
	wget -c https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-2.6.4.tar.gz
	tar -xf libressl-2.6.4.tar.gz
	cd libressl-2.6.4
	CROSS_COMPILE="$XTARGET-" \
	./configure \
		$CONFIGURE \
		--host=$XTARGET
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c https://invisible-mirror.net/archives/lynx/tarballs/lynx2.8.8rel.2.tar.gz
	tar -xf lynx2.8.8rel.2.tar.gz
	cd lynx2-8-8
	CROSS_COMPILE="$XTARGET-" \
	./configure \
		$CONFIGURE \
		--with-ssl \
		--enable-ipv6 \
		--disable-nls \
		--host=$XTARGET
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c https://matt.ucc.asn.au/dropbear/releases/dropbear-2017.75.tar.bz2
	tar -xf dropbear-2017.75.tar.bz2
	cd dropbear-2017.75
	CROSS_COMPILE="$XTARGET-" \
	./configure \
		$CONFIGURE \
		--host=$XTARGET
	make $MAKEOPTS
	make DESTDIR=$ROOTFS install
}

build_kernel() {
	cd $SOURCES
	rm -rf linux-4.14.11
	tar -xf linux-4.14.11.tar.xz
	cd linux-4.14.11
	make ARCH=$XKARCH CROSS_COMPILE="$XTARGET-" defconfig
	sed -i "s/.*CONFIG_DEFAULT_HOSTNAME.*/CONFIG_DEFAULT_HOSTNAME=\"janus\"/" .config
	sed -i "s/.*CONFIG_OVERLAY_FS.*/CONFIG_OVERLAY_FS=y/" .config
	echo "CONFIG_OVERLAY_FS_REDIRECT_DIR=y" >> .config
	echo "CONFIG_OVERLAY_FS_INDEX=y" >> .config
	sed -i "s/.*\\(CONFIG_KERNEL_.*\\)=y/\\#\\ \\1 is not set/" .config
	sed -i "s/.*CONFIG_KERNEL_XZ.*/CONFIG_KERNEL_XZ=y/" .config
	sed -i "s/.*CONFIG_FB_VESA.*/CONFIG_FB_VESA=y/" .config
	sed -i "s/^CONFIG_DEBUG_KERNEL.*/\\# CONFIG_DEBUG_KERNEL is not set/" .config
	sed -i "s/.*CONFIG_EFI_STUB.*/CONFIG_EFI_STUB=y/" .config
	echo "CONFIG_RESET_ATTACK_MITIGATION=y" >> .config
	echo "CONFIG_APPLE_PROPERTIES=n" >> .config
	if [ "`grep "CONFIG_X86_64=y" .config`" = "CONFIG_X86_64=y" ] ; then
		echo "CONFIG_EFI_MIXED=y" >> .config
	fi
	make ARCH=$XKARCH CROSS_COMPILE="$XTARGET-" $MAKEOPTS
	make ARCH=$XKARCH CROSS_COMPILE="$XTARGET-" INSTALL_MOD_PATH=$ROOTFS modules_install
	cp arch/x86/boot/bzImage $ROOTFS/boot/bzImage-4.14.10
	cp arch/x86/boot/bzImage $ISODIR/bzImage
}

strip_filesystem() {
	echo Soon!
}

generate_iso() {
	cd $ROOTFS
	find . -print | cpio -o -H newc | gzip -9 > $ISODIR/rootfs.gz

	cd $SOURCES
	wget http://kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
	tar -xf syslinux-6.03.tar.xz
	cd syslinux-6.03
	cp bios/core/isolinux.bin $ISODIR/isolinux.bin
	cp bios/com32/elflink/ldlinux/ldlinux.c32 $ISODIR/ldlinux.c32
	cp bios/com32/libutil/libutil.c32 $ISODIR/libutil.c32
	cp bios/com32/menu/menu.c32 $ISODIR/menu.c32
	
	cd $ISODIR

	cat << CEOF > ./isolinux.cfg
UI menu.c32
PROMPT 0
 
MENU TITLE JanusLinux Boot Menu:
TIMEOUT 60
DEFAULT default
 
LABEL default
        MENU LABEL JanusLinux
        LINUX bzImage
        INITRD rootfs.gz
CEOF

	mkdir -p efi/boot
	cat << CEOF > ./efi/boot/startup.nsh
	echo -off
	echo Please wait...
	\\bzImage initrd=\\rootfs.gz
CEOF

	genisoimage -J -r \
		-o $CWD/januslinux-1.0-alpha-$BARCH.iso \
		-b isolinux.bin \
		-c boot.cat \
		-input-charset UTF-8 \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		-joliet-long \
		$ISODIR
		
	isohybrid -u $CWD/januslinux-1.0-alpha-$BARCH.iso 2>/dev/null || true
}

generate_docker() {
	echo Soon!
}

check_root
prepare_build
prepare_cross
get_toolchain
build_prepare
setup_rootfs
cook_system
# strip_filesystem
# generate_docker
build_kernel
generate_iso

exit 0

