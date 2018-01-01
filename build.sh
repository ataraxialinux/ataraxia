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
	export SOURCES="$(pwd)/sources"
	export ROOTFS="$(pwd)/rootfs"
	export TOOLS="$(pwd)/tools"
	export KEEP="$(pwd)/KEEP"

	rm -rf $SOURCES $ROOTFS $TOOLS
	mkdir -p $SOURCES $ROOTFS $TOOLS

	export MAKEOPTS="-j$(expr $(nproc) + 1)"

	export PATH="$TOOLS/bin:$PATH"
	export LD_LIBRARY_PATH="$TOOLS/lib"
	export LD_RUN_PATH="$TOOLS/lib"

	export LC_ALL=POSIX
	export LANG=POSIX

	export CONFIGURE="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --bindir=/usr/bin --sbindir=/usr/bin --sysconfdir=/etc --localstatedir=/var --disable-static"
}

prepare_cross() {
	case $BARCH in
		x86_64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-pc-linux-musl"
			export XKARCH="x86_64"
			export MULTILIB="--enable-multilib --with-multilib-list=m64"
			export GCCOPTS="--with-arch=x86-64 --with-tune=generic --enable-long-long"
			;;
		i486)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="i486-pc-linux-musl"
			export XKARCH="i386"
			export MULTILIB="--enable-multilib --with-multilib-list=m32"
			export GCCOPTS="--with-arch=i486 --with-tune=generic"
			;;
		*)
			echo "BARCH variable isn't set..."
			exit 0
	esac
}

prepare_toolchain() {
	cd $TOOLS
	mkdir bin lib

	ln -sf bin sbin
	ln -sf . $XTARGET

	case $BARCH in
		x86_64)
			ln -sf lib lib64
			;;
	esac

	ln -sf . usr
}

build_prepare() {
	unset LD_LIBRARY_PATH LD_RUN_PATH
	rm -rf $SOURCES/*
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
	export LD_LIBRARY_PATH="$ROOTFS/usr/lib"
	export LD_RUN_PATH="$ROOTFS/usr/lib"
}

setup_rootfs() {
	mkdir -p $ROOTFS/{boot,dev,etc,home}
	mkdir -p $ROOTFS/{mnt,opt,proc,srv,sys}
	mkdir -p $ROOTFS/var/{cache,lib,local,lock,log,opt,run,spool}
	install -d -m 0750 $ROOTFS/root
	install -d -m 1777 $ROOTFS/{var/,}tmp
	mkdir -p $ROOTFS/usr/{,local/}{bin,include,lib/{firmware,modules},share}

	cd $ROOTFS/usr
	ln -sf bin sbin

	cd $ROOTFS
	ln -sf usr/bin bin
	ln -sf usr/lib lib
	ln -sf usr/bin sbin

	ln -sf /proc/mounts $ROOTFS/etc/mtab

	touch $ROOTFS/var/log/lastlog
	chmod 664 $ROOTFS/var/log/lastlog
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
		--disable-nls \
		--disable-werror \
		$MULTILIB
	make MAKEINFO="true" $MAKEOPTS
	make MAKEINFO="true" install

	cd $SOURCES
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.10.tar.xz
	tar -xf linux-4.14.10.tar.xz
	cd linux-4.14.10
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
		--disable-nls \
		$MULTILIB \
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
		--disable-nls \
		--disable-lto-plugin \
		$MULTILIB \
		$GCCOPTS
	make AS_FOR_TARGET="$XTARGET-as" LD_FOR_TARGET="$XTARGET-ld" $MAKEOPTS
	make install
}

check_root
prepare_build
prepare_cross
prepare_toolchain
cook_toolchain
build_prepare
setup_rootfs

exit 0

