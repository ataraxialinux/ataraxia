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
	export LD_LIBRARY_PATH="$TOOLS/lib"

	export LC_ALL=POSIX
	export LANG=POSIX

	export CONFIGURE="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --bindir=/usr/bin --sbindir=/usr/bin --sysconfdir=/etc --localstatedir=/var --enable-shared --disable-static"

	export XCFLAGS="-g0 -Os -s -pipe -fno-stack-protector -fomit-frame-pointer -U_FORTIFY_SOURCE"
	export XCXXFLAGS="$XCFLAGS"
	export XLDFLAGS="-s"
}

prepare_cross() {
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
			export XTARGET="arm-pc-linux-musleabi"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-float=soft --with-fpu=neon"
			;;
		armhf)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-pc-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-float=hard --with-fpu=neon"
			;;
		ppc64le)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc64le-pc-linux-musl"
			export XKARCH="powerpc64le"
			export GCCOPTS=
			;;
		ppc)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc-pc-linux-musl"
			export XKARCH="powerpc"
			export GCCOPTS="--enable-secureplt"
			;;
		*)
			echo "BARCH variable isn't set..."
			exit 0
	esac
}

build_prepare() {
	rm -rf $SOURCES/*
	unset CFLAGS CXXFLAGS LDFLAGS
	export LIBLOOK="-Wl,-rpath,$ROOTFS/usr/lib"
	export CFLAGS="$XCFLAGS"
	export CXXFLAGS="$XCXXFLAGS"
	export LDFLAGS="$XLDFLAGS $LIBLOOK"
	export CC="$XTARGET-gcc --sysroot=$ROOTFS"
	export CXX="$XTARGET-g++ --sysroot=$ROOTFS"
	export AR="$XTARGET-ar"
	export AS="$XTARGET-as"
	export LD="$XTARGET-ld --sysroot=$ROOTFS"
	export RANLIB="$XTARGET-ranlib"
	export READELF="$XTARGET-readelf"
	export STRIP="$XTARGET-strip"
}

prepare_toolchain() {
	cd $TOOLS
	mkdir bin

	ln -sf bin sbin

	ln -sf . usr

	export CFLAGS="$XCFLAGS"
	export CXXFLAGS="$XCXXFLAGS"
	export LDFLAGS="$XLDFLAGS"
}

cook_toolchain() {
	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.bz2
	tar -xf binutils-2.29.1.tar.bz2
	cd binutils-2.29.1
	mkdir build
	cd build
	AR=ar AS=as \
	../configure \
		--prefix=$TOOLS \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=$TOOLS \
		--enable-deterministic-archives \
		--disable-compressed-debug-sections \
		--disable-cloog-version-check \
		--disable-ppl-version-check \
		--disable-multilib \
		--disable-nls \
		--disable-werror
	make MAKEINFO="true" $MAKEOPTS
	make MAKEINFO="true" install

	cd $SOURCES
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.13.tar.xz
	tar -xf linux-4.14.13.tar.xz
	cd linux-4.14.13
	make mrproper
	make ARCH=$XKARCH INSTALL_HDR_PATH=$TOOLS headers_install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gcc/gcc-7.2.0/gcc-7.2.0.tar.xz
	wget -c http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpfr/mpfr-3.1.6.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz
	wget -c http://isl.gforge.inria.fr/isl-0.18.tar.xz
	tar -xf gcc-7.2.0.tar.xz
	cd gcc-7.2.0
	tar xf ../mpfr-3.1.6.tar.xz
	mv mpfr-3.1.6 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.0.3.tar.gz
	mv mpc-1.0.3 mpc
	tar xf ../isl-0.18.tar.xz
	mv isl-0.18 isl
	mkdir build
	cd build
	AR=ar \
	../configure \
		--prefix=$TOOLS \
		--build=$XHOST \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=$TOOLS \
		--with-newlib \
		--without-headers \
		--without-ppl \
		--without-cloog \
		--enable-languages=c \
		--enable-clocale=generic \
		--disable-gnu-indirect-function \
		--disable-shared \
		--disable-threads \
		--disable-decimal-float \
		--disable-libgomp \
		--disable-libssp \
		--disable-libatomic \
		--disable-libitm \
		--disable-libquadmath \
		--disable-libvtv \
		--disable-libcilkrts \
		--disable-libstdcxx \
		--disable-libmudflap \
		--disable-libsanitizer \
		--disable-libmpx \
		--disable-multilib \
		--disable-nls \
		$GCCOPTS
	make all-gcc all-target-libgcc $MAKEOPTS
	make install-gcc install-target-libgcc

	cd $SOURCES
	wget -c http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	CC="$XTARGET-gcc" CROSS_COMPILE="$XTARGET-" \
	./configure \
		--prefix= \
		--syslibdir=/lib \
		--enable-debug \
		--enable-optimize
	make $MAKEOPTS
	make DESTDIR=$TOOLS install

	cd $SOURCES
	rm -rf gcc-7.2.0
	tar -xf gcc-7.2.0.tar.xz
	cd gcc-7.2.0
	tar xf ../mpfr-3.1.6.tar.xz
	mv mpfr-3.1.6 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.0.3.tar.gz
	mv mpc-1.0.3 mpc
	tar xf ../isl-0.18.tar.xz
	mv isl-0.18 isl
	mkdir build
	cd build
	AR=ar \
	../configure \
		--prefix=$TOOLS \
		--build=$XHOST \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=$TOOLS \
		--enable-languages=c,c++ \
		--enable-clocale=generic \
		--enable-tls \
		--enable-libstdcxx-time \
		--enable-checking=release \
		--enable-fully-dynamic-string \
		--disable-symvers \
		--disable-gnu-indirect-function \
		--disable-libmudflap \
		--disable-libsanitizer \
		--disable-libmpx \
		--disable-multilib \
		--disable-nls \
		--disable-lto-plugin \
		$GCCOPTS
	make AS_FOR_TARGET="$XTARGET-as" LD_FOR_TARGET="$XTARGET-ld" $MAKEOPTS
	make install
}

econfigure() {
	./configure \
		AR="$AR" AS="$AS" LD="$LD" RANLIB="$RANLIB" READELF="$READELF" STRIP="$STRIP" \
		CC="$CC" CXX="$CXX" \
		CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" \
		$CONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--target=$XTARGET \
		$1
}

subeconfigure() {
	mkdir build
	cd build
	../configure \
		AR="$AR" AS="$AS" LD="$LD" RANLIB="$RANLIB" READELF="$READELF" STRIP="$STRIP" \
		CC="$CC" CXX="$CXX" \
		CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" \
		$CONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--target=$XTARGET \
		$1
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

	for f in fstab host.conf hosts issue profile shadow sysctl.conf group hostname inittab passwd securetty shells crypttab; do
		install -m644 $KEEP/$f $ROOTFS/etc
	done

	chmod 640 $ROOTFS/etc/shadow $ROOTFS/etc/crypttab

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
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.13.tar.xz
	tar -xf linux-4.14.13.tar.xz
	cd linux-4.14.13
	make mrproper
	make ARCH=$XKARCH CROSS_COMPILE=$XTARGET- INSTALL_HDR_PATH=$ROOTFS/usr headers_install
	find $ROOTFS/usr/include \( -name .install -o -name ..install.cmd \) -delete

	cd $SOURCES
	wget -c http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	econfigure \
		--syslibdir=/usr/lib \
		--enable-optimize
	make CROSS_COMPILE=$XTARGET- $MAKEOPTS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c https://sortix.org/libz/release/libz-1.2.8.2015.12.26.tar.gz
	tar -xf libz-1.2.8.2015.12.26.tar.gz
	cd libz-1.2.8.2015.12.26
	econfigure
	make CROSS_COMPILE=$XTARGET- $MAKEOPTS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.bz2
	tar -xf binutils-2.29.1.tar.bz2
	cd binutils-2.29.1
	subeconfigure \
		--with-sysroot=$ROOTFS \
		--with-system-zlib \
		--enable-deterministic-archives \
		--enable-gold \
		--enable-ld=default \
		--enable-plugins \
		--enable-shared \
		--disable-multilib \
		--disable-nls \
		--disable-werror
	make CROSS_COMPILE=$XTARGET- $MAKEOPTS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SOURCES
	wget http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	tar -xf gmp-6.1.2.tar.xz
	cd gmp-6.1.2
	econfigure \
		--enable-cxx
	make CROSS_COMPILE=$XTARGET- $MAKEOPTS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SOURCES
	wget http://www.mpfr.org/mpfr-3.1.6/mpfr-3.1.6.tar.xz
	tar -xf mpfr-3.1.6.tar.xz
	cd mpfr-3.1.6
	econfigure \
		--with-sysroot=$ROOTFS
	make CROSS_COMPILE=$XTARGET- $MAKEOPTS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SOURCES
	wget http://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz
	tar -xf mpc-1.0.3.tar.gz
	cd mpc-1.0.3
	econfigure \
		--with-sysroot=$ROOTFS
	make CROSS_COMPILE=$XTARGET- $MAKEOPTS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gcc/gcc-7.2.0/gcc-7.2.0.tar.xz
	tar -xf gcc-7.2.0.tar.xz
	cd gcc-7.2.0
	subeconfigure \
		--with-sysroot=$ROOTFS \
		--with-system-zlib \
		--enable-__cxa_atexit \
		--enable-checking=release \
		--enable-clocale=generic \
		--enable-deterministic-archives \
		--enable-fully-dynamic-string \
		--enable-languages=c,c++ \
		--enable-libssp \
		--enable-libstdcxx-time \
		--enable-lto \
		--enable-threads=posix \
		--enable-tls \
		--disable-bootstrap \
		--disable-decimal-float \
		--disable-gnu-indirect-function \
		--disable-libcilkrts \
		--disable-libitm \
		--disable-libmpx \
		--disable-libmudflap \
		--disable-libsanitizer \
		--disable-libstdcxx-pch \
		--disable-libquadmath \
		--disable-multilib \
		--disable-nls \
		--disable-symvers \
		--disable-werror
	gcc_cv_libc_provides_ssp=yes \
	make CROSS_COMPILE=$XTARGET- $MAKEOPTS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/make/make-4.2.1.tar.bz2
	tar -xf make-4.2.1.tar.bz2
	cd make-4.2.1
	econfigure \
		--without-dmalloc \
		--without-guile \
		--disable-nls
	make CROSS_COMPILE=$XTARGET- $MAKEOPTS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c https://github.com/MirBSD/mksh/archive/mksh-R56b.tar.gz
	tar -xf mksh-R56b.tar.gz
	cd mksh-mksh-R56b
	sh Build.sh -r
	install -D -m 755 mksh $ROOTFS/usr/bin/mksh
	cd $ROOTFS/usr/bin
	ln -sf mksh sh

	cd $SOURCES
	wget -c http://busybox.net/downloads/busybox-1.28.0.tar.bz2
	tar -xf busybox-1.28.0.tar.bz2
	cd busybox-1.28.0
	make ARCH=$XKARCH CROSS_COMPILE=$XTARGET- defconfig
	sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config
	sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config
	make ARCH=$XKARCH CROSS_COMPILE=$XTARGET- $MAKEOPTS
	cp busybox $ROOTFS/usr/bin/busybox
	chroot $ROOTFS /usr/bin/busybox --install -s
	cd $ROOTFS
	ln -sf usr/bin/busybox init
}

build_kernel() {
	cd $SOURCES
	rm -rf linux-4.14.13
	tar -xf linux-4.14.13.tar.xz
	cd linux-4.14.13
	make ARCH=$XKARCH CROSS_COMPILE=$XTARGET- defconfig
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
	make ARCH=$XKARCH CROSS_COMPILE=$XTARGET- $MAKEOPTS
	make ARCH=$XKARCH CROSS_COMPILE=$XTARGET- INSTALL_MOD_PATH=$ROOTFS modules_install
	cp arch/$XKARCH/boot/bzImage $ROOTFS/boot/bzImage-4.14.13
	cp arch/$XKARCH/boot/bzImage $ISODIR/bzImage
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
	kernel /bzImage
	append initrd=/rootfs.gz quiet vga=791
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
prepare_toolchain
cook_toolchain
build_prepare
setup_rootfs
cook_system
# strip_filesystem
# generate_docker
# build_kernel
# generate_iso

exit 0

