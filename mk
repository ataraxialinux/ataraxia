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

	export XCONFIGURE="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --bindir=/usr/bin --sbindir=/usr/sbin --sysconfdir=/etc --localstatedir=/var"

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
			;;
		i386)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="i686-linux-musl"
			export XKARCH="i386"
			export GCCOPTS="--with-arch=i686 --with-tune=generic"
			;;
		arm64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
			;;
		arm)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-float=hard --with-fpu=neon"
			;;
		mips64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mips64-linux-musl"
			export XKARCH="mips"
			export GCCOPTS=
			;;
		mips)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mips-linux-musl"
			export XKARCH="mips"
			export GCCOPTS=
			;;
		ppc64le)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc64le-linux-musl"
			export XKARCH="powerpc64le"
			export GCCOPTS=
			;;
		ppc)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc-linux-musl"
			export XKARCH="powerpc"
			export GCCOPTS="--enable-secureplt"
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
	ln -sf . usr
}

build_toolchain() {
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
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.15.3.tar.xz
	tar -xf linux-4.15.3.tar.xz
	cd linux-4.15.3
	make mrproper
	make ARCH=$XKARCH INSTALL_HDR_PATH=$TOOLS headers_install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gcc/gcc-7.3.0/gcc-7.3.0.tar.xz
	wget -c http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpfr/mpfr-4.0.0.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz
	tar -xf gcc-7.3.0.tar.xz
	cd gcc-7.3.0
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
		--syslibdir=/lib
	make -j$XJOBS
	make DESTDIR=$TOOLS install

	cd $SOURCES
	rm -rf gcc-7.3.0
	tar -xf gcc-7.3.0.tar.xz
	cd gcc-7.3.0
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
	export PKG_CONFIG_PATH="$ROOTFS/usr/lib/pkgconfig"
}

setup_rootfs() {
	mkdir -p $ROOTFS/{boot,dev,etc/skel,home,mnt,proc,sys}
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
			ln -sf lib lib64
			;;
	esac

	ln -sf /proc/mounts $ROOTFS/etc/mtab

	touch $ROOTFS/var/log/lastlog
	chmod 664 $ROOTFS/var/log/lastlog
}

build_rootfs() {
	cd $SOURCES
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.15.3.tar.xz
	tar -xf linux-4.15.3.tar.xz
	cd linux-4.15.3
	make mrproper
	make ARCH=$XKARCH INSTALL_HDR_PATH=$ROOTFS/usr headers_install
	find $ROOTFS/usr/include \( -name .install -o -name ..install.cmd \) -delete

	cd $SOURCES
	wget -c http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	CROSS_COMPILE="$XTARGET-" \
	./configure \
		$XCONFIGURE
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
	make prefix=/usr DESTDIR=$ROOTFS install
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
	wget -c http://rsync.dragora.org/v3/sources/attr-c1a7b53073202c67becf4df36cadc32ef4759c8a-rebase.tar.lz
	tar -xf attr-c1a7b53073202c67becf4df36cadc32ef4759c8a-rebase.tar.lz
	cd attr-c1a7b53073202c67becf4df36cadc32ef4759c8a-rebase
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--enable-gettext=no
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://rsync.dragora.org/v3/sources/acl-38f32ea1865bcc44185f4118fde469cb962cff68-rebase.tar.lz
	tar -xf acl-38f32ea1865bcc44185f4118fde469cb962cff68-rebase.tar.lz
	cd acl-38f32ea1865bcc44185f4118fde469cb962cff68-rebase
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-sysroot=$ROOTFS \
		--enable-gettext=no
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.25.tar.xz
	tar -xf libcap-2.25.tar.xz
	cd libcap-2.25
	sed -i 's,BUILD_GPERF := ,BUILD_GPERF := no #,' Make.Rules
	sed -i '/^lib=/s@=.*@=/lib@' Make.Rules
	make BUILD_CC="$HOSTCC" CC="$CC" LDFLAGS="$LDFLAGS" PAM_CAP=no -j$XJOBS
	make RAISE_SETFCAP=no prefix=/usr DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la
	chmod 755 $ROOTFS/usr/lib/libcap.so

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/sed/sed-4.4.tar.xz
	tar -xf sed-4.4.tar.xz
	cd sed-4.4
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-sysroot=$ROOTFS \
		--disable-i18n \
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
	wget -c https://github.com/shadow-maint/shadow/releases/download/4.5/shadow-4.5.tar.xz
	tar -xf shadow-4.5.tar.xz
	cd shadow-4.5
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-sysroot=$ROOTFS \
		--with-group-max-length=32 \
		--without-audit \
		--without-libcrack \
		--without-libpam \
		--without-nscd \
		--without-selinux \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://www.kernel.org/pub/linux/utils/util-linux/v2.31/util-linux-2.31.1.tar.xz
	tar -xf util-linux-2.31.1.tar.xz
	cd util-linux-2.31.1
	./configure ADJTIME_PATH=/var/lib/hwclock/adjtime \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-sysroot=$ROOTFS \
		--without-systemdsystemunitdir \
		--without-systemd \
		--without-python \
		--enable-raw \
		--enable-write \
		--disable-chfn-chsh \
		--disable-login \
		--disable-nls \
		--disable-nologin \
		--disable-pylibmount \
		--disable-rpath \
		--disable-runuser \
		--disable-setpriv \
		--disable-su \
		--disable-sulogin \
		--disable-tls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://sourceforge.net/projects/procps-ng/files/Production/procps-ng-3.3.12.tar.xz
	tar -xf procps-ng-3.3.12.tar.xz
	cd procps-ng-3.3.12
	ac_cv_func_malloc_0_nonnull=yes \
	ac_cv_func_realloc_0_nonnull=yes \
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-sysroot=$ROOTFS \
		--with-ncurses \
		--without-systemd \
		--disable-kill \
		--disable-nls \
		--disable-rpath
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

	cd $SOURCES
	wget -c https://ftp.gnu.org/gnu/coreutils/coreutils-8.29.tar.xz
	tar -xf coreutils-8.29.tar.xz
	cd coreutils-8.29
	./configure FORCE_UNSAFE_CONFIGURE=1 \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--enable-no-install-program=kill,uptime,hostname \
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
		;;
	usage|*)
		usage
esac

exit 0

