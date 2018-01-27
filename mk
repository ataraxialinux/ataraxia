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
	export KEEP="$(pwd)/KEEP"

	rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $TOOLS

	export LC_ALL=POSIX

	export PATH="$TOOLS/bin:$PATH"

	export XCONFIGURE="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --bindir=/usr/bin --sbindir=/usr/bin --sysconfdir=/etc --localstatedir=/var --enable-shared --disable-static"

	export XJOBS="$(expr $(nproc) + 1)"

	export HOSTCC="gcc"
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

prepare_toolchain() {
	cd $TOOLS
	ln -sf . usr
}

build_toolchain() {
	cd $SOURCES
	wget -c ftp://ftp.astron.com/pub/file/file-5.32.tar.gz
	tar -xf file-5.32.tar.gz
	cd file-5.32
	./configure \
		--prefix=$TOOLS
	make -j$XJOBS
	make install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/m4/m4-1.4.18.tar.xz
	tar -xf m4-1.4.18.tar.xz
	cd m4-1.4.18
	./configure \
		--prefix=$TOOLS
	make -j$XJOBS
	make install

	cd $SOURCES
	wget -c http://distfiles.dereferenced.org/pkgconf/pkgconf-1.4.1.tar.xz
	tar -xf pkgconf-1.4.1.tar.xz
	cd pkgconf-1.4.1
	./configure \
		--prefix=$TOOLS \
		--host=$XTARGET \
		--with-pc-path=$ROOTFS/usr/lib/pkgconfig:$ROOTFS/usr/share/pkgconfig
	make -j$XJOBS
	make install
	cd $TOOLS/bin
	ln -sf pkgconf pkg-config

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.bz2
	tar -xf binutils-2.29.1.tar.bz2
	cd binutils-2.29.1
	mkdir build
	cd build
	../configure \
		AR="ar" AS="as" \
		--prefix=$TOOLS \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=$TOOLS \
		--enable-deterministic-archives \
		--disable-cloog-version-check \
		--disable-compressed-debug-sections \
		--disable-ppl-version-check \
		--disable-nls \
		--disable-multilib \
		--disable-werror
	make -j$XJOBS MAKEINFO="true"
	make MAKEINFO="true" install

	cd $SOURCES
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.15.tar.xz
	tar -xf linux-4.14.15.tar.xz
	cd linux-4.14.15
	make mrproper
	make ARCH=$XKARCH INSTALL_HDR_PATH=$TOOLS headers_install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gcc/gcc-6.4.0/gcc-6.4.0.tar.xz
	wget -c http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpfr/mpfr-4.0.0.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz
	tar -xf gcc-6.4.0.tar.xz
	cd gcc-6.4.0
	tar xf ../mpfr-4.0.0.tar.xz
	mv mpfr-4.0.0 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.1.0.tar.gz
	mv mpc-1.1.0 mpc
	mkdir build
	cd build
	../configure \
		AR="ar" \
		--prefix=$TOOLS \
		--libdir=$TOOLS/lib \
		--build=$XHOST \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=$TOOLS \
		--with-newlib \
		--without-headers \
		--without-ppl \
		--without-cloog \
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
	make -j$XJOBS all-gcc all-target-libgcc
	make install-gcc install-target-libgcc

	cd $SOURCES
	wget -c http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure CC="$XTARGET-gcc" CROSS_COMPILE="$XTARGET-" \
		--prefix= \
		--syslibdir=/lib \
		--enable-debug \
		--enable-optimize
	make -j$XJOBS
	make DESTDIR=$TOOLS install

	cd $SOURCES
	rm -rf gcc-6.4.0
	tar -xf gcc-6.4.0.tar.xz
	cd gcc-6.4.0
	tar xf ../mpfr-4.0.0.tar.xz
	mv mpfr-4.0.0 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.1.0.tar.gz
	mv mpc-1.1.0 mpc
	mkdir build
	cd build
	../configure \
		AR="ar" \
		--prefix=$TOOLS \
		--libdir=$TOOLS/lib \
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
	make -j$XJOBS all AS_FOR_TARGET="$XTARGET-as" LD_FOR_TARGET="$XTARGET-ld"
	make install
}

setup_variables() {
	export CFLAGS="-fdata-sections -ffunction-sections -Os -g0 -fno-unwind-tables -fno-asynchronous-unwind-tables -Wa,--noexecstack"
	export CXXFLAGS="$CFLGAS"
	export LDFLAGS="-s -Wl,--gc-sections -Wl,-z,relro,-z,now -Wl,-rpath-link,$ROOTFS/usr/lib:$ROOTFS/lib"
	export CC="$XTARGET-gcc --sysroot=$ROOTFS"
	export CXX="$XTARGET-g++ --sysroot=$ROOTFS"
	export AR="$XTARGET-ar"
	export AS="$XTARGET-as"
	export LD="$XTARGET-ld --sysroot=$ROOTFS"
	export RANLIB="$XTARGET-ranlib"
	export READELF="$XTARGET-readelf"
	export STRIP="$XTARGET-strip"
}

cleanup_old_sources() {
	rm -rf $SOURCES/*
}

setup_rootfs() {
	mkdir -p $ROOTFS/{boot,dev,etc/{init.d,skel},home,mnt,proc,sys}
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

	case $BARCH in
		x86_64|arm64)
			cd $ROOTFS/usr
			ln -sf lib lib64
			cd $ROOTFS
			ln -sf usr/lib lib64
			;;
	esac

	ln -sf /proc/mounts $ROOTFS/etc/mtab

	touch $ROOTFS/var/log/lastlog
	chmod 664 $ROOTFS/var/log/lastlog

	for f in fstab group host.conf hostname hosts inittab issue passwd profile securetty shadow shells sysctl.conf; do
		install -m644 $KEEP/etc/$f $ROOTFS/etc
	done

	install -m600 $KEEP/etc/{gshadow,shadow} $ROOTFS/etc

	for f in rc.startup rc.shutdown rc.dhcp; do
		install -m644 $KEEP/initscripts/$f $ROOTFS/etc/init.d
		chmod +x $ROOTFS/etc/init.d/$f
	done

	install -m644 $KEEP/service $ROOTFS/usr/bin/service
	chmod +x $ROOTFS/usr/bin/service
}

build_rootfs() {
        cd $SOURCES
        wget -c http://sethwklein.net/iana-etc-2.30.tar.bz2
        tar -xf iana-etc-2.30.tar.bz2
        cd iana-etc-2.30
	make get
	make STRIP=yes
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.15.tar.xz
	tar -xf linux-4.14.15.tar.xz
	cd linux-4.14.15
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
	wget -c http://zlib.net/zlib-1.2.11.tar.xz
	tar -xf zlib-1.2.11.tar.xz
	cd zlib-1.2.11
	./configure \
		--prefix=/usr \
		--libdir=/usr/lib
	make -j$XJOBS
	make DESTDIR=$ROOTFS install

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

	cd $SOURCES
	wget -c https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz
	tar -xf flex-2.6.4.tar.gz
	cd flex-2.6.4
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip

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

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.bz2
	tar -xf binutils-2.29.1.tar.bz2
	cd binutils-2.29.1
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
	wget -c http://ftp.gnu.org/gnu/gcc/gcc-6.4.0/gcc-6.4.0.tar.xz
	tar -xf gcc-6.4.0.tar.xz
	cd gcc-6.4.0
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

	cd $SOURCES
	wget -c http://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v1.43.8/e2fsprogs-1.43.8.tar.gz
	tar -xf e2fsprogs-1.43.8.tar.gz
	cd e2fsprogs-1.43.8
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--disable-nls \
		--disable-tls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install install-libs

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
	make ARCH=$XKARCH CROSS_COMPILE="$XTARGET-" -j$XJOBS
	make ARCH=$XKARCH CROSS_COMPILE="$XTARGET-" CONFIG_PREFIX=$ROOTFS install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/bc/bc-1.07.1.tar.gz
	tar -xf bc-1.07.1.tar.gz
	cd bc-1.07.1
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c https://sourceware.org/ftp/elfutils/0.170/elfutils-0.170.tar.bz2
	tar -xf elfutils-0.170.tar.bz2
	cd elfutils-0.170
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make -C libelf DESTDIR=$ROOTFS install
}

strip_rootfs() {
	find $ROOTFS -type f | xargs file 2>/dev/null | grep "LSB executable"     | cut -f 1 -d : | xargs strip --strip-unneeded 2>/dev/null || true
	find $ROOTFS -type f | xargs file 2>/dev/null | grep "shared object"      | cut -f 1 -d : | xargs strip --strip-unneeded 2>/dev/null || true
	find $ROOTFS -type f | xargs file 2>/dev/null | grep "current ar archive" | cut -f 1 -d : | xargs strip -g  
}

prepare_rootfs() {
	cd $ROOTFS
	ln -s usr/bin/busybox init
	rm linuxrc

	chmod 4555 usr/bin/busybox
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
		setup_variables
		cleanup_old_sources
		setup_rootfs
		build_rootfs
		strip_rootfs
		prepare_rootfs
		;;
	image)
		check_root
		configure_arch
		setup_build_env
		prepare_toolchain
		build_toolchain
		setup_variables
		cleanup_old_sources
		setup_rootfs
		build_rootfs
		strip_rootfs
		prepare_rootfs
		;;
	usage|*)
		usage
esac

exit 0

