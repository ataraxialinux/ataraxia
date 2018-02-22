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
		aarch64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--enable-fix-cortex-a53-835769 --enable-fix-cortex-a53-843419"
			;;
		armv7hl)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="---with-arch=armv7-a --with-float=hard --with-fpu=neon"
			;;
		i586)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="i586-linux-musl"
			export XKARCH="i386"
			export GCCOPTS="--with-arch=i586 --with-tune=i686"
			;;
		microblaze)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="microblaze-linux-musl"
			export XKARCH="microblaze"
			export GCCOPTS=
			;;
		mips)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mips-linux-musl"
			export XKARCH="mips"
			export GCCOPTS=
			;;
		or1k)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="or1k-linux-musl"
			export XKARCH="openrisc"
			export GCCOPTS=
			;;
		powerpc)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc-linux-musl"
			export XKARCH="powerpc"
			export GCCOPTS="--enable-secureplt"
			;;
		powerpc64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc64le-linux-musl"
			export XKARCH="powerpc64le"
			export GCCOPTS=
			;;
		s390x)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="s390x-linux-musl"
			export XKARCH="s390x"
			export GCCOPTS=
			;;
		x86_64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-linux-musl"
			export XKARCH="x86_64"
			export GCCOPTS="--with-arch=x86-64 --with-tune=generic"
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
	wget -c ftp://ftp.astron.com/pub/file/file-5.32.tar.gz
	tar -xf file-5.32.tar.gz
	cd file-5.32
	./configure \
		--prefix=$TOOLS
	make -j$XJOBS
	make install

	cd $SOURCES
	wget -c http://distfiles.dereferenced.org/pkgconf/pkgconf-1.4.2.tar.xz
	tar -xf pkgconf-1.4.2.tar.xz
	cd pkgconf-1.4.2
	./configure \
		--prefix=$TOOLS \
		--host=$XTARGET \
		--with-pc-path=$ROOTFS/usr/lib/pkgconfig:$ROOTFS/usr/share/pkgconfig
	make -j$XJOBS
	make install
	ln -s pkgconf $TOOLS/bin/pkg-config

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
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.20.tar.xz
	tar -xf linux-4.14.20.tar.xz
	cd linux-4.14.20
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
	cd $ROOTFS

	for d in boot dev etc/{skel,service} home mnt usr var opt srv/http run; do
		install -d -m755 $d
	done

	install -d -m555 proc
	install -d -m555 sys
	install -d -m0750 root
	install -d -m1777 tmp
	install -d -m555 -g 11 srv/ftp

	ln -s ../proc/self/mounts etc/mtab

	for d in cache local opt log/old lib/misc empty service; do
		install -d -m755 var/$d
	done

	install -d -m1777 var/{tmp,spool/mail}
	install -d -m775 -g 50 var/games
	ln -s spool/mail var/mail
	ln -s ../run var/run
	ln -s ../run/lock var/lock

	for d in bin include lib share/misc src; do
		install -d -m755 usr/$d
	done

	ln -s usr/lib lib
	[[ $BARCH = 'x86_64' ]] && {
		ln -s usr/lib lib64
		ln -s lib usr/lib64
	}

	ln -s usr/bin bin
	ln -s usr/bin sbin
	ln -s bin usr/sbin

	for d in bin etc games include lib man sbin share src; do
		install -d -m755 usr/local/$d
	done
}

build_rootfs() {
	cd $SOURCES
	wget -c https://github.com/JanusLinux/baselayout/archive/1.0-alpha2.1.tar.gz
	tar -xf 1.0-alpha2.1.tar.gz
	cd baselayout-1.0-alpha2.1
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.20.tar.xz
	tar -xf linux-4.14.20.tar.xz
	cd linux-4.14.20
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
	wget -c http://zlib.net/zlib-1.2.11.tar.xz
	tar -xf zlib-1.2.11.tar.xz
	cd zlib-1.2.11
	./configure \
		--prefix=/usr \
		--libdir=/usr/lib \
		--shared
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
	make DESTDIR=$ROOTFS install
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
	make DESTDIR=$ROOTFS install
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
	make DESTDIR=$ROOTFS install
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
	make DESTDIR=$ROOTFS install
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
	make DESTDIR=$ROOTFS install
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
	make DESTDIR=$ROOTFS install
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
	make DESTDIR=$ROOTFS install
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
		--disable-i18n \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://distfiles.dereferenced.org/pkgconf/pkgconf-1.4.2.tar.xz
	tar -xf pkgconf-1.4.2.tar.xz
	cd pkgconf-1.4.2
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-pc-path=/usr/lib/pkgconfig:/usr/share/pkgconfig
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
	LDFLAGS="$LDFLAGS -L$ROOTFS/usr/lib" \
	./configure ADJTIME_PATH=/var/lib/hwclock/adjtime \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
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
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-3.3.12.tar.xz
	tar -xf procps-ng-3.3.12.tar.xz
	cd procps-ng-3.3.12
	ac_cv_func_malloc_0_nonnull=yes \
	ac_cv_func_realloc_0_nonnull=yes \
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--without-ncurses \
		--without-systemd \
		--disable-kill \
		--disable-nls \
		--disable-rpath
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v1.43.9/e2fsprogs-1.43.9.tar.gz
	tar -xf e2fsprogs-1.43.9.tar.gz
	cd e2fsprogs-1.43.9
	LIBS="-L$ROOTFS/usr/lib" \
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--enable-elf-shlibs \
		--enable-symlink-install \
		--disable-fsck \
		--disable-libblkid \
		--disable-libuuid \
		--disable-nls \
		--disable-tls \
		--disable-uuidd
	make -j$XJOBS
	make DESTDIR=$ROOTFS install install-libs

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

	cd $SOURCES
	wget http://sethwklein.net/iana-etc-2.30.tar.bz2
	tar -xf iana-etc-2.30.tar.bz2
	cd iana-etc-2.30
	make get
	make STRIP=yes
	make DESTDIR=$ROOTFS install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/libtool/libtool-2.4.6.tar.xz
	tar -xf libtool-2.4.6.tar.xz
	cd libtool-2.4.6
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://www.kernel.org/pub/linux/utils/net/iproute2/iproute2-4.13.0.tar.xz
	tar -xf iproute2-4.13.0.tar.xz
	cd iproute2-4.13.0
	patch -Np1 -i $KEEP/0001-make-iproute2-fhs-compliant.patch
	patch -Np1 -i $KEEP/iproute2-4.12.0-musl.patch
	patch -Np1 -i $KEEP/iproute2-disable-arpd.patch
	sed -e '/^check_elf$/d' -i configure
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz
	tar -xf bzip2-1.0.6.tar.gz
	cd bzip2-1.0.6
	patch -Np1 -i $KEEP/bzip2.patch
	make -j$XJOBS
	make PREFIX=$ROOTFS/usr install
	make -f Makefile-libbz2_so -j$XJOBS
	make -f Makefile-libbz2_so PREFIX=$ROOTFS/usr install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gdbm/gdbm-1.14.1.tar.gz
	tar -xf gdbm-1.14.1.tar.gz
	cd gdbm-1.14.1
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--enable-libgdbm-compat
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/readline/readline-7.0.tar.gz
	tar -xf readline-7.0.tar.gz
	cd readline-7.0
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make SHLIB_LIBS="-L$ROOTFS/usr/lib -lncursesw" -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz
	tar -xf autoconf-2.69.tar.xz
	cd autoconf-2.69
	patch -Np1 -i $KEEP/autoconf-add-musl.patch
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/automake/automake-1.15.1.tar.xz
	tar -xf automake-1.15.1.tar.xz
	cd automake-1.15.1
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/bash/bash-4.4.18.tar.gz
	tar -xf bash-4.4.18.tar.gz
	cd bash-4.4.18
	_bashconfig=(-DDEFAULT_PATH_VALUE=\'\"/usr/local/sbin:/usr/local/bin:/usr/bin\"\'
			-DSTANDARD_UTILS_PATH=\'\"/usr/bin\"\'
			-DSYS_BASHRC=\'\"/etc/bash.bashrc\"\'
			-DSYS_BASH_LOGOUT=\'\"/etc/bash.bash_logout\"\'
			-DNON_INTERACTIVE_LOGIN_SHELLS)
	CFLAGS="${CFLAGS} ${_bashconfig[@]}"
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-installed-readline \
		--without-bash-malloc \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	ln -sf bash $ROOTFS/bin/sh
	rm -rf $ROOTFS/{,usr}/lib/*.la
	install -Dm644 $KEEP/bash/system.bashrc $ROOTFS/etc/bash.bashrc
	install -Dm644 $KEEP/bash/system.bash_logout $ROOTFS/etc/bash.bash_logout
	install -m644 $KEEP/bash/dot.bashrc $ROOTFS/etc/skel/.bashrc
	install -m644 $KEEP/bash/dot.bash_profile $ROOTFS/etc/skel/.bash_profile
	install -m644 $KEEP/bash/dot.bash_logout $ROOTFS/etc/skel/.bash_logout

	cd $SOURCES
	wget -c http://alpha.gnu.org/gnu/bc/bc-1.06.95.tar.gz
	tar -xf bc-1.06.95.tar.gz
	cd bc-1.06.95
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-readline
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/diffutils/diffutils-3.6.tar.xz
	tar -xf diffutils-3.6.tar.xz
	cd diffutils-3.6
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gawk/gawk-4.2.0.tar.xz
	tar -xf gawk-4.2.0.tar.xz
	cd gawk-4.2.0
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/findutils/findutils-4.6.0.tar.gz
	tar -xf findutils-4.6.0.tar.gz
	cd findutils-4.6.0
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/grep/grep-3.1.tar.xz
	tar -xf grep-3.1.tar.xz
	cd grep-3.1
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--disable-nls
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/groff/groff-1.22.3.tar.gz
	tar -xf groff-1.22.3.tar.gz
	cd groff-1.22.3
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--without-x
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://www.greenwoodsoftware.com/less/less-487.tar.gz
	tar -xf less-487.tar.gz
	cd less-487
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gzip/gzip-1.9.tar.xz
	tar -xf gzip-1.9.tar.xz
	cd gzip-1.9
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/inetutils/inetutils-1.9.4.tar.xz
	tar -xf inetutils-1.9.4.tar.xz
	cd inetutils-1.9.4
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-wrap \
		--enable-ncurses \
		--enable-servers \
		--disable-logger \
		--disable-nls \
		--disable-rcp \
		--disable-readline \
		--disable-rexec \
		--disable-rlogin \
		--disable-rsh \
		--disable-syslogd \
		--disable-whois
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
	wget -c http://download.savannah.gnu.org/releases/libpipeline/libpipeline-1.5.0.tar.gz
	tar -xf libpipeline-1.5.0.tar.gz
	cd libpipeline-1.5.0
	PKG_CONFIG_PATH="$ROOTFS/usr/lib/pkgconfig" \
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/make/make-4.2.1.tar.bz2
	tar -xf make-4.2.1.tar.bz2
	cd make-4.2.1
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--disable-nls
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
	wget -c https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-25.tar.xz
	tar -xf kmod-25.tar.xz
	cd kmod-25
	./configure \
		$XCONFIGURE \
		--build=$XHOST \
		--host=$XTARGET \
		--with-xz \
		--with-zlib
	make -j$XJOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/{,usr}/lib/*.la
}

strip_rootfs() {
	find $ROOTFS -type f | xargs file 2>/dev/null | grep "LSB executable"       | cut -f 1 -d : | xargs $STRIP --strip-all      2>/dev/null || true
	find $ROOTFS -type f | xargs file 2>/dev/null | grep "shared object"        | cut -f 1 -d : | xargs $STRIP --strip-unneeded 2>/dev/null || true
	find $ROOTFS -type f | xargs file 2>/dev/null | grep "current ar archive"   | cut -f 1 -d : | xargs $STRIP --strip-debug
	find $ROOTFS -type f | xargs file 2>/dev/null | grep "libtool library file" | cut -f 1 -d : | xargs rm -rf
	rm -rf $ROOTFS/usr/share/{doc,man,misc,info,locale}
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

