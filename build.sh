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

	export CFLAGS=""
	export LDFLAGS=""
	export CXXFLAGS="$CFLAGS"

	rm -rf $BDIR
	mkdir -p $BDIR $ROOTFS $TOOLS $SRC

	export CONFIGURE="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --bindir=/usr/bin --sbindir=/usr/bin --sysconfdir=/etc --localstatedir=/var"
	export LINKING="--enable-shared --disable-static"
}

do_build_after_toolchain() {
	rm -rf $SRC/*
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
			export TARGET="x86_64-janus-linux-musl"
			export KARCH="x86_64"
			export LIBSUFFIX="64"
			export MULTILIB="--enable-multilib --with-multilib-list=m64"
			export GCCOPTS="--with-arch=nocona"
			;;
		i386)
			export HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')
			export TARGET="i686-janus-linux-musl"
			export KARCH="i386"
			export LIBSUFFIX=
			export MULTILIB="--enable-multilib --with-multilib-list=m32"
			export GCCOPTS="--with-arch=i686"
			;;
		aarch64)
			export HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')
			export TARGET="aarch64-janus-linux-musl"
			export KARCH="arm64"
			export LIBSUFFIX=
			export MULTILIB="--disable-multilib --with-multilib-list="
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
			;;
		arm)
			export HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')
			export TARGET="arm-janus-linux-musleabihf"
			export KARCH="arm"
			export LIBSUFFIX=
			export MULTILIB="--disable-multilib --with-multilib-list="
			export GCCOPTS="--with-arch=armv7-a --with-tune=generic-armv7-a --with-fpu=vfpv3-d16 --with-float=hard --with-abi=aapcs-linux --with-mode=thumb"
			;;
		*)
			echo "XARCH isn't set!"
			echo "Please run: XARCH=[supported architecture] sh make.sh"
			echo "Supported architectures: x86_64, i386(i686)"
			exit 0
	esac
}

do_build_toolchain() {
	mkdir -p $TOOLS/{bin,share,lib,include,$TARGET}
	cd $TOOLS
	ln -sf bin sbin
	cd $TOOLS/$TARGET
	ln -sf ../bin bin
	ln -sf ../lib lib
	ln -sf ../share share
	ln -sf ../include include

	case $XARCH in
		x86_64|aarch64)
			cd $TOOLS
			ln -sf lib lib64
			cd $TOOLS/$TARGET
			ln -sf lib lib64
	esac

	cd $TOOLS
	ln -sf . usr

	cd $SRC
	wget http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.bz2
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
	wget http://ftp.gnu.org/gnu/gcc/gcc-7.2.0/gcc-7.2.0.tar.xz
	wget http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	wget http://ftp.gnu.org/gnu/mpfr/mpfr-3.1.6.tar.xz
	wget http://www.multiprecision.org/mpc/download/mpc-1.0.3.tar.gz
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
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.4.tar.xz
	tar -xf linux-4.14.4.tar.xz
	cd linux-4.14.4
	make mrproper
	make ARCH=$KARCH CROSS_COMPILE=$TARGET- INSTALL_HDR_PATH=$TOOLS headers_install

	cd $SRC
	wget http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
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

do_build_basic_system() {
	cd $SRC
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.4.tar.xz
	tar -xf linux-4.14.4.tar.xz
	cd linux-4.14.4
	make mrproper
	make ARCH=$KARCH CROSS_COMPILE=$TARGET- INSTALL_HDR_PATH=$ROOTFS/usr headers_install
	find $ROOTFS/usr/include -name .install -or -name ..install.cmd | xargs rm -rf

	cd $SRC
	wget http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure \
		$CONFIGURE \
		$LINKING \
		--enable-optimize=size \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	tar -xf gmp-6.1.2.tar.xz
	cd gmp-6.1.2
	./configure \
		$CONFIGURE \
		$LINKING \
		--enable-cxx \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SRC
	wget http://www.mpfr.org/mpfr-3.1.6/mpfr-3.1.6.tar.xz
	tar -xf mpfr-3.1.6.tar.xz
	cd mpfr-3.1.6
	./configure \
		$CONFIGURE \
		$LINKING \
		--with-gmp=$ROOTFS/usr \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SRC
	wget http://www.multiprecision.org/mpc/download/mpc-1.0.3.tar.gz
	tar -xf mpc-1.0.3.tar.gz
	cd mpc-1.0.3
	./configure \
		$CONFIGURE \
		$LINKING \
		--with-gmp=$ROOTFS/usr \
		--with-mpfr=$ROOTFS/usr \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install
	rm -rf $ROOTFS/usr/lib/*.la

	cd $SRC
	wget http://sortix.org/libz/release/libz-1.2.8.2015.12.26.tar.gz
	tar -xf libz-1.2.8.2015.12.26.tar.gz
	cd libz-1.2.8.2015.12.26
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget ftp://ftp.astron.com/pub/file/file-5.32.tar.gz
	tar -xf file-5.32.tar.gz
	cd file-5.32
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-0.2.1.tar.xz
	tar -xf netbsd-curses-0.2.1.tar.xz
	cd netbsd-curses-0.2.1
    cat << EOF > config.mak
CFLAGS=-fPIC
PREFIX=/usr
DESTDIR=$ROOTFS
EOF
	make -j$JOBS
	make install

	cd $SRC
	wget http://ftp.gnu.org/gnu/readline/readline-7.0.tar.gz
	tar -xf readline-7.0.tar.gz
	cd readline-7.0
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://ftp.gnu.org/gnu/bash/bash-4.4.12.tar.gz
	tar -xf bash-4.4.12.tar.gz
	cd bash-4.4.12
	./configure \
		$CONFIGURE \
		$LINKING \
		--without-bash-malloc \
		--with-installed-readline \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://download.savannah.gnu.org/releases/attr/attr-2.4.47.src.tar.gz
	tar -xf attr-2.4.47.src.tar.gz
	cd attr-2.4.47
	./configure \
		$CONFIGURE \
		$LINKING \
		--disable-gettext \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install install-lib install-dev

	cd $SRC
	wget http://download.savannah.gnu.org/releases/acl/acl-2.2.52.src.tar.gz
	tar -xf acl-2.2.52.src.tar.gz
	cd acl-2.2.52
	./configure \
		$CONFIGURE \
		$LINKING \
		--disable-gettext \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install install-lib install-dev

	cd $SRC
	wget http://ftp.gnu.org/gnu/m4/m4-1.4.18.tar.xz
	tar -xf m4-1.4.18.tar.xz
	cd m4-1.4.18
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://ftp.gnu.org/gnu/sed/sed-4.4.tar.xz
	tar -xf sed-4.4.tar.xz
	cd sed-4.4
	./configure \
		$CONFIGURE \
		$LINKING \
		--disable-i18n \
		--disable-nls \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://ftp.gnu.org/gnu/gawk/gawk-4.2.0.tar.xz
	tar -xf gawk-4.2.0.tar.xz
	cd gawk-4.2.0
	./configure \
		$CONFIGURE \
		$LINKING \
		--disable-nls \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v1.43.7/e2fsprogs-1.43.7.tar.gz
	tar -xf e2fsprogs-1.43.7.tar.gz
	cd e2fsprogs-1.43.7
	./configure \
		$CONFIGURE \
		$LINKING \
		--enable-elf-shlibs \
		--enable-symlink-install \
		--disable-fsck \
		--disable-uuidd \
		--disable-libuuid \
		--disable-libblkid \
		--disable-tls \
		--disable-nls \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://tukaani.org/xz/xz-5.2.3.tar.xz
	tar -xf xz-5.2.3.tar.xz
	cd xz-5.2.3
	./configure \
		$CONFIGURE \
		$LINKING \
		--disable-rpath \
		--disable-werror \
		--disable-nls \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-24.tar.xz
	tar -xf kmod-24.tar.xz
	cd kmod-24
	./configure \
		$CONFIGURE \
		$LINKING \
		--with-rootlibdir=/usr/lib \
		--with-xz \
		--with-zlib \
		--disable-manpages \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://dev.gentoo.org/~blueness/eudev/eudev-3.2.5.tar.gz
	tar -xf eudev-3.2.5.tar.gz
	cd eudev-3.2.5
	./configure \
		$CONFIGURE \
		$LINKING \
		--disable-manpages \
		--disable-selinux \
		--enable-kmod \
		--enable-blkid \
		--enable-rule-generator \
		--enable-hwdb \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://ftp.gnu.org/gnu/diffutils/diffutils-3.6.tar.xz
	tar -xf diffutils-3.6.tar.xz
	cd diffutils-3.6
	./configure \
		$CONFIGURE \
		$LINKING \
		--disable-nls \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://sourceforge.net/projects/psmisc/files/psmisc/psmisc-23.1.tar.xz
	tar -xf psmisc-23.1.tar.xz
	cd psmisc-23.1
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://www.greenwoodsoftware.com/less/less-487.tar.gz
	tar -xf less-487.tar.gz
	cd less-487
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget ftp://ftp.vim.org/pub/vim/unix/vim-8.0.586.tar.bz2
	tar -xf vim-8.0.586.tar.bz2
	cd vim-8.0.586
	./configure \
		$CONFIGURE \
		$LINKING \
		--with-vim-name=vim \
		--without-x \
		--enable-multibyte \
		--enable-cscope \
		--disable-gui \
		--disable-gpm \
		--disable-nls \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://www.sudo.ws/dist/sudo-1.8.21p2.tar.gz
	tar -xf sudo-1.8.21p2.tar.gz
	cd sudo-1.8.21p2
	./configure \
		$CONFIGURE \
		$LINKING \
		--with-env-editor \
		--without-pam \
		--without-skey \
		--enable-pie \
		--disable-nls \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://ftp.gnu.org/gnu/tar/tar-1.29.tar.xz
	tar -xf tar-1.29.tar.xz
	cd tar-1.29
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-2.6.3.tar.gz
	tar -xf libressl-2.6.3.tar.gz
	cd libressl-2.6.3
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://fastly.cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-7.6p1.tar.gz
	tar -xf openssh-7.6p1.tar.gz
	cd openssh-7.6p1
	./configure \
		$LINKING \
		--prefix=/usr \
		--sysconfdir=/etc/ssh \
		--with-privsep-path=/var/lib/sshd \
		--with-md5-passwords \
		--with-ssl-engine \
		--without-pie \
		--without-pam \
		--without-selinux \
		--disable-lastlog \
		--disable-utmp \
		--disable-utmpx \
		--disable-wtmp \
		--disable-wtmpx \
		--disable-strip \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://curl.haxx.se/download/curl-7.57.0.tar.xz
	tar -xf curl-7.57.0.tar.xz
	cd curl-7.57.0
	./configure \
		$CONFIGURE \
		$LINKING \
		--without-librtmp \
		--with-ssl \
		--enable-ipv6 \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://invisible-mirror.net/archives/lynx/tarballs/lynx2.8.8rel.2.tar.Z
	tar -xf lynx2.8.8rel.2.tar.Z
	cd lynx2-8-8
	./configure \
		$CONFIGURE \
		$LINKING \
		--with-ssl \
		--enable-ipv6 \
		--disable-nls \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://prdownloads.sourceforge.net/expat/expat-2.2.5.tar.bz2
	tar -xf expat-2.2.5.tar.bz2
	cd expat-2.2.5
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://www.libarchive.org/downloads/libarchive-3.3.2.tar.gz
	tar -xf libarchive-3.3.2.tar.gz
	cd libarchive-3.3.2
	./configure \
		$CONFIGURE \
		$LINKING \
		--without-openssl \
		--without-xml2 \
		--without-expat \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install
}

do_build_post_build() {
	echo In development
}

do_build_config
do_build_cross_config
do_build_toolchain
do_build_after_toolchain
do_build_basic_system
do_build_post_build

exit 0

