#!/bin/bash

set -e

do_build_config() {
	export BDIR="$(pwd)/build-dir"
	export ROOTFS="$BDIR/rootfs"
	export TOOLS="$BDIR/tools"
	export SRC="$BDIR/sources"
	export KEEP="$(pwd)/KEEP"

	export JOBS="$(expr $(nproc) + 1)"
	export PATH="$TOOLS/bin:$PATH"

	rm -rf $BDIR
	mkdir -p $BDIR $ROOTFS $TOOLS $SRC

	export CONFIGURE="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --bindir=/usr/bin --sbindir=/usr/bin --sysconfdir=/etc --localstatedir=/var --disable-static"
}

do_build_after_toolchain() {
	rm -rf $SRC/*
	export CFLAGS=""
	export CXXFLAGS="$CFLAGS"
	export LDFLAGS="-Wl,-rpath,$ROOTFS/usr/lib"
	export CC="$TARGET-gcc --sysroot=$ROOTFS"
	export CXX="$TARGET-g++ --sysroot=$ROOTFS"
	export LD="$TARGET-ld --sysroot=$ROOTFS"
	export AS="$TARGET-as --sysroot=$ROOTFS"
	export AR="$TARGET-ar"
	export NM="$TARGET-nm"
	export OBJCOPY="$TARGET-objcopy"
	export RANLIB="$TARGET-ranlib"
	export READELF="$TARGET-readelf"
	export STRIP="$TARGET-strip"
	export SIZE="$TARGET-size"
}

do_build_cross_config() {
	case $XARCH in
		x86_64)
			export HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')
			export TARGET="x86_64-pc-linux-musl"
			export KARCH="x86_64"
			export LIBSUFFIX="64"
			export MULTILIB="--enable-multilib --with-multilib-list=m64"
			export GCCOPTS="--with-arch=nocona"
			;;
		i386)
			export HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')
			export TARGET="i686-pc-linux-musl"
			export KARCH="i386"
			export LIBSUFFIX=
			export MULTILIB="--enable-multilib --with-multilib-list=m32"
			export GCCOPTS="--with-arch=i686"
			;;
		*)
			echo "XARCH isn't set!"
			echo "Please run: XARCH=[supported architecture] sh make.sh"
			echo "Supported architectures: x86_64, i386(i686)"
			exit 0
	esac
}

do_build_toolchain() {
	mkdir -p $TOOLS/{bin,share,lib,include}
	cd $TOOLS
	ln -sf bin sbin
	ln -sf . $TARGET

	case $XARCH in
		x86_64)
			cd $TOOLS
			ln -sf lib lib64
	esac

	cd $TOOLS
	ln -sf . usr

	cd $SRC
	wget -c http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.bz2
	tar -xf binutils-2.29.1.tar.bz2
	cd binutils-2.29.1
	mkdir build
	cd build
	AR=ar AS=as \
	../configure \
		--build=$HOST \
		--host=$HOST \
		--target=$TARGET \
		--prefix=$TOOLS \
		--with-sysroot=$TOOLS \
		--enable-deterministic-archives \
		--disable-compressed-debug-sections \
		--disable-nls \
		--disable-ppl-version-check \
		--disable-cloog-version-check \
		$MULTILIB
	make configure-host -j$JOBS
	make -j$JOBS
	make install

	cd $SRC
	wget -c http://ftp.gnu.org/gnu/gcc/gcc-7.2.0/gcc-7.2.0.tar.xz
	wget -c http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpfr/mpfr-3.1.6.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz
	tar -xf gcc-7.2.0.tar.xz
	cd gcc-7.2.0
	tar xf ../mpfr-3.1.6.tar.xz
	mv mpfr-3.1.6 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.0.3.tar.gz
	mv mpc-1.0.3 mpc
	mkdir build
	cd build
	AR=ar \
	../configure \
		--build=$HOST \
		--host=$HOST \
		--target=$TARGET \
		--prefix=$TOOLS \
		--with-sysroot=$TOOLS \
		--with-local-prefix=$TOOLS \
		--with-system-zlib \
		--with-newlib \
		--without-headers \
		--enable-languages=c \
		--enable-checking=release \
		--enable-linker-build-id \
		--disable-decimal-float \
		--disable-libmpx \
		--disable-libquadmath \
		--disable-libsanitizer \
		--disable-libatomic \
		--disable-libmudflap \
		--disable-libcilkrts \
		--disable-libstdcxx \
		--disable-gnu-indirect-function \
		--disable-decimal-float \
		--disable-shared \
		--disable-libvtv \
		--disable-nls \
		--disable-static \
		--disable-threads \
		--disable-libitm \
		--disable-libssp \
		--disable-libgomp \
		$MULTILIB \
		$GCCOPTS
	make all-gcc all-target-libgcc -j$JOBS
	make install-gcc install-target-libgcc
	rm -rf $TOOLS/include/limits.h

	cd $SRC
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.10.tar.xz
	tar -xf linux-4.14.10.tar.xz
	cd linux-4.14.10
	make mrproper
	make ARCH=$KARCH CROSS_COMPILE=$TARGET- INSTALL_HDR_PATH=$TOOLS headers_install

	cd $SRC
	wget -c http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure \
		CROSS_COMPILE=$TARGET- \
		--prefix=/ \
		--target=$TARGET
	make -j$JOBS
	make DESTDIR=$TOOLS install

	cd $SRC
	rm -rf gcc-7.2.0
	tar -xf gcc-7.2.0.tar.xz
	cd gcc-7.2.0
	tar xf ../mpfr-3.1.6.tar.xz
	mv mpfr-3.1.6 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.0.3.tar.gz
	mv mpc-1.0.3 mpc
	mkdir build
	cd build
	AR=ar \
	../configure \
		--build=$HOST \
		--host=$HOST \
		--target=$TARGET \
		--prefix=$TOOLS \
		--with-sysroot=$TOOLS \
		--enable-languages=c,c++ \
		--enable-c99 \
		--enable-__cxa_atexit \
		--enable-clocale=generic \
		--enable-tls \
		--enable-long-long \
		--enable-libstdcxx-time \
		--enable-checking=release \
		--enable-fully-dynamic-string \
		--enable-linker-build-id \
		--disable-symvers \
		--disable-gnu-indirect-function \
		--disable-libmudflap \
		--disable-libsanitizer \
		--disable-libmpx \
		--disable-nls \
		--disable-lto-plugin \
		$MULTILIB \
		$GCCOPTS
	make AS_FOR_TARGET="$TARGET-as" LD_FOR_TARGET="$TARGET-ld" -j$JOBS
	make install
}

do_build_setup_filesystem() {
	mkdir -p $ROOTFS/{boot,dev,etc/skel,home}
	mkdir -p $ROOTFS/{mnt,opt,proc,srv,sys}
	mkdir -p $ROOTFS/var/{cache,lib,local,lock,log,opt,run,spool}
	install -d -m 0750 $ROOTFS/root
	install -d -m 1777 $ROOTFS/{var/,}tmp
	mkdir -p $ROOTFS/usr/{bin,include,lib/{firmware,modules},share}
	mkdir -p $ROOTFS/usr/local/{bin,include,lib,sbin,share}

	cd $ROOTFS/usr
	ln -sf bin sbin

	cd $ROOTFS
	ln -sf usr/bin bin
	ln -sf usr/bin sbin
	ln -sf usr/lib lib

	ln -sf /proc/mounts $ROOTFS/etc/mtab

	touch $ROOTFS/var/log/lastlog
	chmod -v 664 $ROOTFS/var/log/lastlog

	for f in fstab group host.conf hostname hosts inittab issue passwd profile rc.conf securetty shells sysctl.conf; do
		install -D -m 644 $KEEP/etc/${f} $ROOTFS/etc/${f}
	done

	install -D -m 640 $KEEP/etc/shadow $ROOTFS/etc/shadow

	cp -a $KEEP/rocket $ROOTFS/usr/bin/rocket
}

do_build_build_core() {
	cd $SRC
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.10.tar.xz
	tar -xf linux-4.14.10.tar.xz
	cd linux-4.14.10
	make mrproper
	make ARCH=$KARCH CROSS_COMPILE=$TARGET- INSTALL_HDR_PATH=$ROOTFS/usr headers_install
	find $ROOTFS/usr/include -name .install -or -name ..install.cmd | xargs rm -rf

	cd $SRC
	wget -c http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure CROSS_COMPILE=$TARGET- \
		$CONFIGURE \
		--enable-optimize= \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget -c http://zlib.net/zlib-1.2.11.tar.xz
	tar -xf zlib-1.2.11.tar.xz
	cd zlib-1.2.11
	CHOST=$TARGET \
	CROSS_COMPILE=$TARGET- \
	./configure \
		--prefix=/usr \
		--libdir=/usr/lib \
		--shared
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget -c ftp://ftp.astron.com/pub/file/file-5.32.tar.gz
	tar -xf file-5.32.tar.gz
	cd file-5.32
	./configure CROSS_COMPILE=$TARGET- \
		$CONFIGURE \
		--disable-static \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SRC
	wget http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.bz2
	tar -xf binutils-2.29.1.tar.bz2
	cd binutils-2.29.1
	mkdir build
	cd build
	../configure CROSS_COMPILE=$TARGET- \
		$CONFIGURE \
		--with-sysroot=$ROOTFS \
		--with-system-zlib \
		--enable-gold \
		--enable-ld=default \
		--enable-plugins \
		--disable-multilib \
		--disable-nls \
		--disable-werror \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SRC
	wget http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	tar -xf gmp-6.1.2.tar.xz
	cd gmp-6.1.2
	CROSS_COMPILE=$TARGET- \
	./configure CROSS_COMPILE=$TARGET- \
		$CONFIGURE \
		--enable-cxx \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SRC
	wget http://www.mpfr.org/mpfr-3.1.6/mpfr-3.1.6.tar.xz
	tar -xf mpfr-3.1.6.tar.xz
	cd mpfr-3.1.6
	CROSS_COMPILE=$TARGET- \
	./configure CROSS_COMPILE=$TARGET- \
		$CONFIGURE \
		--with-gmp=$ROOTFS/usr \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SRC
	wget http://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz
	tar -xf mpc-1.0.3.tar.gz
	cd mpc-1.0.3
	./configure CROSS_COMPILE=$TARGET- \
		$CONFIGURE \
		--with-gmp=$ROOTFS/usr \
		--with-mpfr=$ROOTFS/usr \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SRC
	wget http://ftp.gnu.org/gnu/gcc/gcc-7.2.0/gcc-7.2.0.tar.xz
	tar -xf gcc-7.2.0.tar.xz
	cd gcc-7.2.0
	mkdir build
	cd build
	libat_cv_have_ifunc=no \
	CROSS_COMPILE=$TARGET- \
	../configure CROSS_COMPILE=$TARGET- \
		$CONFIGURE \
		--with-system-zlib \
		--enable-__cxa_atexit \
		--enable-languages=c,c++ \
		--enable-clocale=generic \
		--enable-threads=posix \
		--enable-tls \
		--enable-lto \
		--enable-libssp \
		--enable-libstdcxx-time \
		--enable-checking=release \
		--enable-fully-dynamic-string \
		--disable-bootstrap \
		--disable-gnu-indirect-function \
		--disable-libcilkrts \
		--disable-libitm \
		--disable-libmudflap \
		--disable-libmpx \
		--disable-libsanitizer \
		--disable-libstdcxx-pch \
		--disable-multilib \
		--disable-nls \
		--disable-symvers \
		--disable-werror \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la
}

do_build_config
do_build_cross_config
do_build_toolchain
do_build_after_toolchain
do_build_setup_filesystem
do_build_build_core

exit 0

