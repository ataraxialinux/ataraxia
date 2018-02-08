#!/bin/sh

set -e

usage() {
cat <<EOF
mk - the JanusLinux build tool.
Usage: sudo BARCH=[supported architecture] ./mk [one of following option]
	all		Build a full JanusLinux system
	container	Build a docker container
	image		Build a bootable *.iso image
	toolchain	Build a cross-toolchain
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
	export IMGDIR="$BUILD/imgdir"
	export KEEP="$(pwd)/KEEP"

	rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $TOOLS $IMGDIR

	export LC_ALL=POSIX

	export PATH="$TOOLS/bin:$PATH"

	export XCONFIGURE="--prefix=/ --libdir=/lib --libexecdir=/libexec --bindir=/bin --sbindir=/sbin --sysconfdir=/etc --localstatedir=/var"

	export XJOBS="$(expr $(nproc) + 1)"

	export HOSTCC="gcc"
}

configure_arch() {
	case $BARCH in
		x86_64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-linux-musl"
			export XKARCH="x86_64"
			export GCCOPTS="--with-arch=x86-64 --with-tune=generic --enable-long-long"
			export KIMG="bzImage"
			;;
		i686)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="i686-linux-musl"
			export XKARCH="i386"
			export GCCOPTS="--with-arch=i686 --with-tune=generic"
			export KIMG="bzImage"
			;;
		arm64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
			export KIMG="uImage"
			;;
		arm)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-float=hard --with-fpu=neon"
			export KIMG="uImage"
			;;
		*)
			echo "BARCH variable isn't set..."
			exit 0
	esac
}

prepare_toolchain() {
	export CFLAGS="-g0 -Os"
	export CXXFLAGS="$CFLAGS"
	export LDFLAGS="-s"

	cd $TOOLS
	mkdir -p bin lib $XTARGET/{bin,lib}

	case $BARCH in
		x86_64|arm64)
			cd $TOOLS
			ln -sf lib lib64
			cd $TOOLS/$XTARGET
			ln -sf lib lib64
			;;
	esac

	cd $TOOLS
	ln -sf . usr
}

build_toolchain() {
	cd $SOURCES
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.15.2.tar.xz
	tar -xf linux-4.15.2.tar.xz
	cd linux-4.15.2
	make mrproper
	make ARCH=$XKARCH INSTALL_HDR_PATH=$TOOLS headers_install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/binutils/binutils-2.30.tar.xz
	tar -xf binutils-2.30.tar.xz
	cd binutils-2.30
	mkdir build
	cd build
	AR="ar" AS="as" \
	../configure \
		--prefix=$TOOLS \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=$TOOLS \
		--enable-deterministic-archives \
		--disable-cloog-version-check \
		--disable-compressed-debug-sections \
		--disable-multilib \
		--disable-nls \
		--disable-ppl-version-check \
		--disable-werror
	make MAKEINFO="true" -j$XJOBS
	make MAKEINFO="true" install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gcc/gcc-7.3.0/gcc-7.3.0.tar.xz
	wget -c http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpfr/mpfr-4.0.0.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz
	tar -xf gcc-7.3.0.tar.xz
	cd gcc-7.3.0
	for f in 0001-ssp_nonshared.diff 0002-posix_memalign.diff 0003-cilkrts.diff 0004-libatomic-test-fix.diff 0005-libgomp-test-fix.diff 0006-libitm-test-fix.diff 0007-libvtv-test-fix.diff 0008-j2.diff 0009-s390x-muslldso.diff; do
		patch -Np1 -i $KEEP/gcc-patches/$f
	done
	tar xf ../mpfr-4.0.0.tar.xz
	mv mpfr-4.0.0 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.1.0.tar.gz
	mv mpc-1.1.0 mpc
	mkdir build
	cd build
	AR="ar"\
	../configure \
		--prefix=$TOOLS \
		--build=$XHOST \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=$TOOLS \
		--with-newlib \
		--without-cloog \
		--without-headers \
		--without-ppl \
		--enable-clocale=generic \
		--enable-languages=c \
		--disable-decimal-float \
		--disable-gnu-indirect-function \
		--disable-libatomic \
		--disable-libcilkrts \
		--disable-libgomp \
		--disable-libitm \
		--disable-libmpx \
		--disable-libmudflap \
		--disable-libquadmath \
		--disable-libsanitizer \
		--disable-libssp \
		--disable-libstdcxx \
		--disable-libvtv \
		--disable-multilib \
		--disable-nls \
		--disable-shared \
		--disable-threads \
		$GCCOPTS
	make all-gcc all-target-libgcc -j$XJOBS
	make install-gcc install-target-libgcc

	cd $SOURCES
	wget -c http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure CC="$XTARGET-gcc" CROSS_COMPILE="$XTARGET-" \
		--prefix= \
		--syslibdir=/lib \
		--enable-optimize
	make -j$XJOBS
	make DESTDIR=$TOOLS install

	cd $SOURCES
	rm -rf gcc-7.3.0
	tar -xf gcc-7.3.0.tar.xz
	cd gcc-7.3.0
	for f in 0001-ssp_nonshared.diff 0002-posix_memalign.diff 0003-cilkrts.diff 0004-libatomic-test-fix.diff 0005-libgomp-test-fix.diff 0006-libitm-test-fix.diff 0007-libvtv-test-fix.diff 0008-j2.diff 0009-s390x-muslldso.diff; do
		patch -Np1 -i $KEEP/gcc-patches/$f
	done
	tar xf ../mpfr-4.0.0.tar.xz
	mv mpfr-4.0.0 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.1.0.tar.gz
	mv mpc-1.1.0 mpc
	mkdir build
	cd build
	AR="ar"\
	../configure \
		--prefix=$TOOLS \
		--build=$XHOST \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=$TOOLS \
		--enable-checking=release \
		--enable-clocale=generic \
		--enable-fully-dynamic-string \
		--enable-languages=c,c++ \
		--enable-libstdcxx-time \
		--enable-tls \
		--disable-gnu-indirect-function \
		--disable-libmpx \
		--disable-libmudflap \
		--disable-libsanitizer \
		--disable-lto-plugin \
		--disable-multilib \
		--disable-nls \
		--disable-symvers \
		$GCCOPTS
	make AS_FOR_TARGET="$XTARGET-as" LD_FOR_TARGET="$XTARGET-ld"
	make install
}

clean_sources() {
	unset CFLAGS CXXFLAGS LDFLAGS

	rm -rf $SOURCES/*
}

setup_variables() {
	export CFLAGS="-g0 -Os"
	export CXXFLAGS="$CFLAGS"
	export LDFLAGS="-s -Wl,-rpath-link,$ROOTFS/lib"
	export CC="$XTARGET-gcc --sysroot=$ROOTFS"
	export CXX="$XTARGET-g++ --sysroot=$ROOTFS"
	export AR="$XTARGET-ar"
	export AS="$XTARGET-as"
	export LD="$XTARGET-ld --sysroot=$ROOTFS"
	export RANLIB="$XTARGET-ranlib"
	export READELF="$XTARGET-readelf"
	export STRIP="$XTARGET-strip"
	export PKG_CONFIG_PATH="$ROOTFS/lib/pkgconfig"
}

setup_rootfs() {
	mkdir -p $ROOTFS/{boot,bin,dev,etc/{skel,init.d,service},home,lib/modules,mnt,proc,sbin,share,srv,sys,var}
	mkdir -p $ROOTFS/var/{cache,lib,local,lock,log,opt,run,service,spool}
	install -d -m 0750 $ROOTFS/root
	install -d -m 1777 $ROOTFS/{var/,}tmp

	cd $ROOTFS
	ln -sf . usr

	ln -sf /proc/mounts $ROOTFS/etc/mtab

	touch $ROOTFS/var/log/lastlog
	chmod 664 $ROOTFS/var/log/lastlog

	for f in fstab group host.conf hostname hosts inittab issue passwd profile securetty shells sysctl.conf; do
		install -m644 $KEEP/etc/$f $ROOTFS/etc
	done

	install -m600 $KEEP/etc/shadow $ROOTFS/etc

	for f in rc.dhcp rc.functions rc.shutdown rc.startup; do
		install -m644 $KEEP/rc/$f $ROOTFS/etc/init.d
		chmod +x $ROOTFS/etc/init.d/$f
	done

	cp -a $KEEP/service/* $ROOTFS/etc/service
}

build_rootfs() {
	cd $SOURCES
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.15.2.tar.xz
	tar -xf linux-4.15.2.tar.xz
	cd linux-4.15.2
	make mrproper
	make ARCH=$XKARCH INSTALL_HDR_PATH=$ROOTFS/usr headers_install
	find $ROOTFS/usr/include \( -name .install -o -name ..install.cmd \) -delete

	cd $SOURCES
	wget -c http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	CROSS_COMPILE="$XTARGET-" \
	./configure \
		$XCONFIGURE \
		--enable-optimize=size
	make -j$XJOBS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c http://sortix.org/libz/release/libz-1.2.8.2015.12.26.tar.gz
	tar -xf libz-1.2.8.2015.12.26.tar.gz
	cd libz-1.2.8.2015.12.26
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c ftp://ftp.astron.com/pub/file/file-5.32.tar.gz
	tar -xf file-5.32.tar.gz
	cd file-5.32
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/m4/m4-1.4.18.tar.xz
	tar -xf m4-1.4.18.tar.xz
	cd m4-1.4.18
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz
	tar -xf flex-2.6.4.tar.gz
	cd flex-2.6.4
	ac_cv_func_malloc_0_nonnull=yes \
	ac_cv_func_realloc_0_nonnull=yes \
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/bison/bison-3.0.4.tar.xz
	tar -xf bison-3.0.4.tar.xz
	cd bison-3.0.4
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--enable-threads=posix \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.barfooze.de/pub/sabotage/tarballs/libelf-compat-0.152c001.tar.bz2
	tar -xf libelf-compat-0.152c001.tar.bz2
	cd libelf-compat-0.152c001
	echo "CFLAGS += $CFLAGS -fPIC" > config.mak
	sed -i 's@HEADERS = src/libelf.h@HEADERS = src/libelf.h src/gelf.h@' Makefile
	make -j$XJOBS
	make prefix=/ DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/binutils/binutils-2.30.tar.bz2
	tar -xf binutils-2.30.tar.bz2
	cd binutils-2.30
	mkdir build
	cd build
	../configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--target=$XTARGET \
		--with-system-zlib \
		--enable-deterministic-archives \
		--enable-gold \
		--enable-ld=default \
		--enable-plugins \
		--enable-shared \
		--disable-multilib \
		--disable-nls \
		--disable-werror
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	tar -xf gmp-6.1.2.tar.xz
	cd gmp-6.1.2
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--enable-cxx
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://www.mpfr.org/mpfr-4.0.0/mpfr-4.0.0.tar.xz
	tar -xf mpfr-4.0.0.tar.xz
	cd mpfr-4.0.0
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz
	tar -xf mpc-1.1.0.tar.gz
	cd mpc-1.1.0
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gcc/gcc-7.3.0/gcc-7.3.0.tar.xz
	tar -xf gcc-7.3.0.tar.xz
	cd gcc-7.3.0
	for f in 0001-ssp_nonshared.diff 0002-posix_memalign.diff 0003-cilkrts.diff 0004-libatomic-test-fix.diff 0005-libgomp-test-fix.diff 0006-libitm-test-fix.diff 0007-libvtv-test-fix.diff 0008-j2.diff 0009-s390x-muslldso.diff; do
		patch -Np1 -i $KEEP/gcc-patches/$f
	done
	case $BARCH in
		x86_64)
			sed -i '/m64=/s/lib64/lib/' gcc/config/i386/t-linux64
	esac
	mkdir build
	cd build
	../configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--target=$XTARGET \
		--with-system-zlib \
		--enable-__cxa_atexit \
		--enable-checking=release \
		--enable-clocale=generic \
		--enable-fully-dynamic-string \
		--enable-languages=c,c++ \
		--enable-libstdcxx-time \
		--enable-lto \
		--enable-threads=posix \
		--enable-tls \
		--disable-bootstrap \
		--disable-gnu-indirect-function \
		--disable-libcilkrts \
		--disable-libitm \
		--disable-libmpx \
		--disable-libmudflap \
		--disable-libsanitizer \
		--disable-libstdcxx-pch \
		--disable-multilib \
		--disable-nls \
		--disable-symvers \
		--disable-werror
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/make/make-4.2.1.tar.bz2
	tar -xf make-4.2.1.tar.bz2
	cd make-4.2.1
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--without-dmalloc \
		--without-guile \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://distfiles.dereferenced.org/pkgconf/pkgconf-1.4.1.tar.xz
	tar -xf pkgconf-1.4.1.tar.xz
	cd pkgconf-1.4.1
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la
	ln -s pkgconf $ROOTFS/usr/bin/pkg-config

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu//ncurses/ncurses-6.1.tar.gz
	tar -xf ncurses-6.1.tar.gz
	cd ncurses-6.1
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-pkg-config-libdir=/usr/lib/pkgconfig \
		--with-normal \
		--with-shared \
		--without-ada \
		--without-cxx-binding \
		--without-debug \
		--without-manpages \
		--without-tests \
		--enable-pc-files \
		--enable-widec \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://www.kernel.org/pub/linux/utils/util-linux/v2.31/util-linux-2.31.1.tar.xz
	tar -xf util-linux-2.31.1.tar.xz
	cd util-linux-2.31.1
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--enable-fsck \
		--enable-libblkid \
		--enable-libmount \
		--enable-libuuid \
		--disable-all-programs \
		--disable-nls \
		--disable-tls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://www.kernel.org/pub/linux/utils/fs/xfs/xfsprogs/xfsprogs-4.14.0.tar.xz
	tar -xf xfsprogs-4.14.0.tar.xz
	cd xfsprogs-4.14.0
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://sethwklein.net/iana-etc-2.30.tar.bz2
	tar -xf iana-etc-2.30.tar.bz2
	cd iana-etc-2.30
	make get
	make STRIP=yes
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c https://www.kernel.org/pub/linux/utils/net/iproute2/iproute2-4.15.0.tar.xz
	tar -xf iproute2-4.15.0.tar.xz
	cd iproute2-4.15.0
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://www.kernel.org/pub/linux/utils/kbd/kbd-2.0.4.tar.xz
	tar -xf kbd-2.0.4.tar.xz
	cd kbd-2.0.4
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--disable-nls \
		--disable-vlock
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://tukaani.org/xz/xz-5.2.3.tar.xz
	tar -xf xz-5.2.3.tar.xz
	cd xz-5.2.3
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://busybox.net/downloads/busybox-1.28.0.tar.bz2
	tar -xf busybox-1.28.0.tar.bz2
	cd busybox-1.28.0
	make ARCH=$XKARCH defconfig
	sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config
	sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config
	make ARCH=$XKARCH CROSS_COMPILE=$XTARGET- -j$XJOBS
	make ARCH=$XKARCH CROSS_COMPILE=$XTARGET- CONFIG_PREFIX=$ROOTFS install
	cd $ROOTFS
	ln -s bin/busybox init
	rm linuxrc

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/bc/bc-1.07.1.tar.gz
	tar -xf bc-1.07.1.tar.gz
	cd bc-1.07.1
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--without-readline
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-2.6.4.tar.gz
	tar -xf libressl-2.6.4.tar.gz
	cd libressl-2.6.4
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://github.com/thom311/libnl/releases/download/libnl3_4_0/libnl-3.4.0.tar.gz
	tar -xf libnl-3.4.0.tar.gz
	cd libnl-3.4.0
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://hostap.epitest.fi/releases/wpa_supplicant-2.6.tar.gz
	tar -xf wpa_supplicant-2.6.tar.gz
	cd wpa_supplicant-2.6/wpa_supplicant
	cp defconfig .config
	make -j$XJOBS
	make BINDIR=/sbin DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://matt.ucc.asn.au/dropbear/releases/dropbear-2017.75.tar.bz2
	tar -xf dropbear-2017.75.tar.bz2
	cd dropbear-2017.75
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://invisible-mirror.net/archives/lynx/tarballs/lynx2.8.8rel.2.tar.gz
	tar -xf lynx2.8.8rel.2.tar.gz
	cd lynx2-8-8
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-ssl \
		--enable-ipv6 \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la
}

strip_rootfs() {
	find $ROOTFS -type f | xargs file 2>/dev/null | grep "LSB executable"     | cut -f 1 -d : | xargs $STRIP --strip-all      2>/dev/null || true
	find $ROOTFS -type f | xargs file 2>/dev/null | grep "shared object"      | cut -f 1 -d : | xargs $STRIP --strip-unneeded 2>/dev/null || true
	find $ROOTFS -type f | xargs file 2>/dev/null | grep "current ar archive" | cut -f 1 -d : | xargs $STRIP --strip-debug

	rm -rf $ROOTFS/{,usr}/lib/*.la

	rm -rf $ROOTFS/usr/share/{doc,man,misc,info}
}

build_kernel() {
	cd $SOURCES
	rm -rf linux-4.15.2
	tar -xf linux-4.15.2.tar.xz
	cd linux-4.15.2
	make mrproper
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
	make ARCH=$XKARCH CROSS_COMPILE=$XTARGET-
	make ARCH=$XKARCH CROSS_COMPILE=$XTARGET- INSTALL_MOD_PATH=$ROOTFS modules_install
	cp arch/$XKARCH/boot/$KIMG $IMGDIR/$KIMG
}

case "$1" in
	toolchain)
		check_root
		configure_arch
		setup_build_env
		prepare_toolchain
		build_toolchain
		;;
	container)
		check_root
		configure_arch
		setup_build_env
		prepare_toolchain
		build_toolchain
		clean_sources
		setup_variables
		setup_rootfs
		build_rootfs
		strip_rootfs
#		build_container
		;;
	image)
		check_root
		configure_arch
		setup_build_env
		prepare_toolchain
		build_toolchain
		clean_sources
		setup_variables
		setup_rootfs
		build_rootfs
		strip_rootfs
		build_kernel
		;;
	usage|*)
		usage
esac

exit 0

