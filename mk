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

	export XCONFIGURE="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --bindir=/usr/bin --sbindir=/usr/bin --sysconfdir=/etc --localstatedir=/var"

	export XJOBS="$(expr $(nproc) + 1)"

	export HOSTCC="gcc"
}

configure_arch() {
	case $BARCH in
		x86_64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-linux-musl"
			export XKARCH="x86_64"
			;;
		i686)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="i686-linux-musl"
			export XKARCH="i386"
			;;
		arm64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			;;
		arm)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			;;
		*)
			echo "BARCH variable isn't set..."
			exit 0
	esac
}

build_toolchain() {
	cd $SOURCES
	git clone https://github.com/JanusLinux/musl-cross-make.git
	cd musl-cross-make
	make TARGET=$XTARGET -j$XJOBS
	make -C build/local/$XTARGET install
	mv build/local/$XTARGET/output/* $TOOLS
}

setup_variables() {
	export CFLAGS="-g0 -Os"
	export CXXFLAGS="$CFLAGS"
	export LDFLAGS="-s -Wl,-rpath-link,$ROOTFS/usr/lib"
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
			ln -sf usr/lib lib64
			;;
	esac

	ln -sf /proc/mounts $ROOTFS/etc/mtab

	touch $ROOTFS/var/log/lastlog
	chmod 664 $ROOTFS/var/log/lastlog

	for f in fstab group host.conf hostname hosts inittab issue passwd profile securetty shells sysctl.conf; do
		install -m644 $KEEP/etc/$f $ROOTFS/etc
	done

	install -m600 $KEEP/etc/shadow $ROOTFS/etc
}

build_rootfs() {
	cd $SOURCES
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.15.tar.xz
	tar -xf linux-4.15.tar.xz
	cd linux-4.15
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
		--enable-gettext=no
	make -j$XJOBS
	make DESTDIR=$ROOTFS install-strip
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.25.tar.xz
	tar -xf libcap-2.25.tar.xz
	cd libcap-2.25
	sed -i 's,BUILD_GPERF := ,BUILD_GPERF := no #,' Make.Rules
	sed -i '/^lib=/s@=.*@=/usr/lib@' Make.Rules
	make BUILD_CC="$HOSTCC" CC="$CC" LDFLAGS="$LDFLAGS" -j$XJOBS
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
	wget -c http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-0.2.1.tar.xz
	tar -xf netbsd-curses-0.2.1.tar.xz
	cd netbsd-curses-0.2.1
	make HOSTCC="$HOSTCC" CC="$CC" CFLAGS="$CFLAGS -Os -Wall -fPIC" DFLAGS="$LDFLAGS -static" PREFIX=$ROOTFS/usr -j$XJOBS all install
	make HOSTCC="$HOSTCC" CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS -static" PREFIX=$ROOTFS/usr -j$XJOBS all-static install-static
	rm -rf $ROOTFS/{,usr}/lib/*.la

	cd $SOURCES
	wget -c http://sethwklein.net/iana-etc-2.30.tar.bz2
	tar -xf iana-etc-2.30.tar.bz2
	cd iana-etc-2.30
	make get
	make STRIP=yes
	make DESTDIR=$ROOTFS install
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
		build_toolchain
		;;
	container)
		check_root
		configure_arch
		setup_build_env
		build_toolchain
		setup_variables
		setup_rootfs
		build_rootfs
		strip_rootfs
		;;
	image)
		check_root
		configure_arch
		setup_build_env
		build_toolchain
		setup_variables
		setup_rootfs
		build_rootfs
		strip_rootfs
		;;
	usage|*)
		usage
esac

exit 0

