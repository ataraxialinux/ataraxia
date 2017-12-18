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
	mkdir -p $TOOLS/{bin,share,lib,include}
	cd $TOOLS
	ln -sf bin sbin
	ln -sf . $TARGET

	case $XARCH in
		x86_64|aarch64)
			cd $TOOLS
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
	wget http://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz
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
	wget http://busybox.net/downloads/busybox-1.27.2.tar.bz2
	tar -xf busybox-1.27.2.tar.bz2
	cd busybox-1.27.2
	make ARCH=$KARCH CROSS_COMPILE=$TARGET- KCONFIG_ALLCONFIG=$KEEP/busybox.config allnoconfig
	make ARCH=$KARCH CROSS_COMPILE=$TARGET- -j$JOBS
	make ARCH=$KARCH CROSS_COMPILE=$TARGET- CONFIG_PREFIX=$ROOTFS install
	cd $ROOTFS
	ln -sf bin/busybox init
	rm -rf linuxrc

	cd $SRC
	wget https://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R56b.tgz
	tar -xf mksh-R56b.tgz
	cd mksh
	sh Build.sh -r
	install -D -m 755 mksh $ROOTFS/usr/bin/mksh
	cd $ROOTFS/usr/bin
	rm -rf sh
	ln -sf mksh sh

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
	wget http://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz
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
	wget http://ftp.gnu.org/gnu//ncurses/ncurses-6.0.tar.gz
	tar -xf ncurses-6.0.tar.gz
	cd ncurses-6.0
	CXXFLAGS="$CXXFLAGS -P" \
	./configure \
		$CONFIGURE \
		$LINKING \
		--without-manpages \
    	--with-shared \
    	--without-debug \
    	--enable-widec \
    	--enable-pc-files \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

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
	wget http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz
	tar -xf bzip2-1.0.6.tar.gz
	cd bzip2-1.0.6
	patch -Np1 -i $KEEP/bzip2.patch
	make -j$JOBS
	make PREFIX=$ROOTFS/usr install
	make -f Makefile-libbz2_so -j$JOBS
	make -f Makefile-libbz2_so PREFIX=$ROOTFS/usr install

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
	wget https://www.kernel.org/pub/linux/utils/net/iproute2/iproute2-4.14.1.tar.xz
	tar -xf iproute2-4.14.1.tar.xz
	cd iproute2-4.14.1
	./configure \
		$CONFIGURE \
		$LINKING \
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
	wget https://www.kernel.org/pub/linux/utils/kbd/kbd-2.0.4.tar.xz
	tar -xf kbd-2.0.4.tar.xz
	cd kbd-2.0.4
	./configure \
		$CONFIGURE \
		$LINKING \
		--disable-vlock \
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
	wget http://ftp.gnu.org/gnu/gzip/gzip-1.8.tar.xz
	tar -xf gzip-1.8.tar.xz
	cd gzip-1.8
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
	wget http://download.savannah.gnu.org/releases/libpipeline/libpipeline-1.5.0.tar.gz
	tar -xf libpipeline-1.5.0.tar.gz
	cd libpipeline-1.5.0
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
	wget http://ftp.gnu.org/gnu/screen/screen-4.6.2.tar.gz
	tar -xf screen-4.6.2.tar.gz
	cd screen-4.6.2
	./configure \
		$CONFIGURE \
		$LINKING \
		--enable-colors256 \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://libestr.adiscon.com/files/download/libestr-0.1.10.tar.gz
	tar -xf libestr-0.1.10.tar.gz
	cd libestr-0.1.10
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://www.libee.org/download/files/download/libee-0.4.1.tar.gz
	tar -xf libee-0.4.1.tar.gz
	cd libee-0.4.1
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://github.com/rsyslog/rsyslog/archive/v8.31.0.tar.gz
	tar -xf v8.31.0.tar.gz
	cd rsyslog-8.31.0
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://www.kernel.org/pub/software/utils/pciutils/pciutils-3.5.6.tar.xz
	tar -xf pciutils-3.5.6.tar.xz
	cd pciutils-3.5.6
	make -j$JOBS \
		PREFIX=/usr \
		SHAREDIR=/usr/share/hwdata \
		SHARED=yes
	make \
		PREFIX=$ROOTFS/usr \
		SHAREDIR=$ROOTFS/usr/share/hwdata \
		SHARED=yes \
		install install-lib 

	cd $SRC
	wget https://github.com/libfuse/libfuse/releases/download/fuse-2.9.7/fuse-2.9.7.tar.gz
	tar -xf fuse-2.9.7.tar.gz
	cd fuse-2.9.7
	./configure \
		$CONFIGURE \
		$LINKING \
		--enable-lib \
		--enable-util \
		--disable-example \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://tuxera.com/opensource/ntfs-3g_ntfsprogs-2017.3.23.tgz
	tar -xf ntfs-3g_ntfsprogs-2017.3.23.tgz
	cd ntfs-3g_ntfsprogs-2017.3.23
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install


	cd $SRC
	wget http://rpm5.org/files/popt/popt-1.16.tar.gz
	tar -xf popt-1.16.tar.gz
	cd popt-1.16
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://github.com/logrotate/logrotate/releases/download/3.13.0/logrotate-3.13.0.tar.xz
	tar -xf logrotate-3.13.0.tar.xz
	cd logrotate-3.13.0
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://www.libssh2.org/download/libssh2-1.8.0.tar.gz
	tar -xf libssh2-1.8.0.tar.gz
	cd libssh2-1.8.0
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
	wget https://www.samba.org/ftp/rsync/src/rsync-3.1.2.tar.gz
	tar -xf rsync-3.1.2.tar.gz
	cd rsync-3.1.2
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://www.eecis.udel.edu/~ntp/ntp_spool/ntp4/ntp-4.2/ntp-4.2.8p10.tar.gz
	tar -xf ntp-4.2.8p10.tar.gz
	cd ntp-4.2.8p10
	./configure \
		$CONFIGURE \
		$LINKING \
		--with-lineeditlibs=readline \
		--enable-linuxcaps \
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
	wget https://github.com//libusb/libusb/releases/download/v1.0.21/libusb-1.0.21.tar.bz2
	tar -xf libusb-1.0.21.tar.bz2
	cd libusb-1.0.21
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://downloads.sourceforge.net/libusb/libusb-compat-0.1.5.tar.bz2
	tar -xf libusb-compat-0.1.5.tar.bz2
	cd libusb-compat-0.1.5
	./configure \
		$CONFIGURE \
		$LINKING \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget https://www.kernel.org/pub/linux/utils/usb/usbutils/usbutils-009.tar.xz
	tar -xf usbutils-009.tar.xz
	cd usbutils-009
	./configure \
		$CONFIGURE \
		$LINKING \
		--datadir=/usr/share/hwdata \
		--host=$TARGET
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://www.draisberghof.de/usb_modeswitch/usb-modeswitch-2.5.1.tar.bz2
	tar -xf usb-modeswitch-2.5.1.tar.bz2
	cd usb-modeswitch-2.5.1
	make -j$JOBS
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://www.draisberghof.de/usb_modeswitch/usb-modeswitch-data-20170806.tar.bz2
	tar -xf usb-modeswitch-data-20170806.tar.bz2
	cd usb-modeswitch-data-20170806
	make DESTDIR=$ROOTFS install

	cd $SRC
	wget http://ftp.barfooze.de/pub/sabotage/tarballs/libnl-tiny-1.0.1.tar.xz
	tar -xf libnl-tiny-1.0.1.tar.xz
	cd libnl-tiny-1.0.1
	make prefix=/usr DESTDIR=$ROOTFS all install -j$JOBS

	cd $SRC
	wget http://w1.fi/releases/wpa_supplicant-2.6.tar.gz
	tar -xf wpa_supplicant-2.6.tar.gz
	cd wpa_supplicant-2.6
	cd wpa_supplicant
	cp defconfig .config
	sed -i 's,#CONFIG_WPS=y,CONFIG_WPS=y,' .config
	make -j$JOBS
	make BINDIR=/usr/bin DESTDIR=$ROOTFS install

	cd $SRC
	wget http://www.hpl.hp.com/personal/Jean_Tourrilhes/Linux/wireless_tools.29.tar.gz
	tar -xf wireless_tools.29.tar.gz
	cd wireless_tools.29
	make -j$JOBS
	make PREFIX=$ROOTFS/usr install

	cd $SRC
	rm -rf linux*
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.4.tar.xz
	tar -xf linux-4.14.4.tar.xz
	cd linux-4.14.4
	make ARCH=$KARCH CROSS_COMPILE=$TARGET- defconfig
	make ARCH=$KARCH CROSS_COMPILE=$TARGET- -j$JOBS
	cp System.map $ROOTFS/boot
	cp arch/x86/boot/bzImage $ROOTFS/boot/vmlinuz
	make INSTALL_MOD_PATH=$ROOTFS modules_install
}

do_build_config
do_build_cross_config
do_build_toolchain
do_build_after_toolchain
do_build_setup_filesystem
do_build_basic_system
# do_build_strip_system

exit 0

