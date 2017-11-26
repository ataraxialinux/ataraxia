#!/bin/sh
#

set -ex

product_name="Janus Linux"
product_version="0.1"
product_id="janus"
product_bug_url="https://github.com/protonesso/janus/issues"
product_url="januslinux.github.io"

NUM_JOBS=$(expr $(nproc) + 1)

topdir=$(pwd)
srcdir=$(pwd)/work/sources
tooldir=$(pwd)/work/tools
pkgdir=$(pwd)/work/rootfs
isodir=$(pwd)/work/rootcd
stuffdir=$(pwd)/stuff

xflags="-Os -s -g0 -pipe -fno-asynchronous-unwind-tables -Werror-implicit-function-declaration"
default_configure="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --sysconfdir=/etc --bindir=/usr/bin --sbindir=/usr/sbin --localstatedir=/var"

kernelhost="janus"
kernelver="4.14.2"

just_prepare() {
	rm -rf ${srcdir} ${tooldir} ${pkgdir} ${isodir}
	mkdir -p ${srcdir} ${tooldir} ${pkgdir} ${isodir}

	export CFLAGS="$xflags"
	export CXXLAGS="$CFLAGS"

	export PATH="${tooldir}/bin:$PATH"
}

clean_sources() {
	rm -rf ${srcdir}/*
}

prepare_cross() {
	case $XARCH in
		i686)
			export XHOST=$(echo ${MACHTYPE} | sed "s/-[^-]*/-cross/")
			export XCPU=i686
			export XTARGET=i686-pc-linux-musl
			export KARCH=i386
			export libSuffix=
			export BUILD="-m32"
			;;
		x86_64)
			export XHOST=$(echo ${MACHTYPE} | sed "s/-[^-]*/-cross/")
			export XCPU=nocona
			export XTARGET=x86_64-pc-linux-musl
			export KARCH=x86_64
			export libSuffix=64
			export BUILD="-m64"
			;;
		powerpc64)
			export XHOST=$(echo ${MACHTYPE} | sed "s/-[^-]*/-cross/")
			export XCPU=
			export XTARGET=powerpc64-pc-linux-musl
			export KARCH=powerpc64
			export libSuffix=
			export BUILD="-m64"
			;;
		*)
			echo "XARCH isn't set!"
			echo "Please run: XARCH=[supported architecture] sh make.sh"
			echo "Supported architectures: i686(in development), x86_64, powerpc64le(in development)"
			exit 0
	esac
}

prepare_filesystem() {
	mkdir -p ${pkgdir}/{boot,dev,etc/{rc.d,skel},home}
	mkdir -p ${pkgdir}/{mnt,opt,proc,srv,sys}
	mkdir -p ${pkgdir}/var/{cache,lib,local,lock,log,opt,run,spool}
	install -d -m 0750 ${pkgdir}/root
	install -d -m 1777 ${pkgdir}/{var/,}tmp
	mkdir -p ${pkgdir}/usr/{bin,include,lib/{firmware,modules},share}
	mkdir -p ${pkgdir}/usr/local/{bin,include,lib,sbin,share}

	cd ${pkgdir}/usr
	ln -sf bin sbin

	cd ${pkgdir}
	ln -sf usr/bin bin
	ln -sf usr/bin sbin
	ln -sf usr/lib lib

	case $XARCH in
		x86_64)
			cd ${pkgdir}/usr
			ln -sf lib lib64
			cd ${pkgdir}
			ln -sf usr/lib lib64
	esac

	ln -sf /proc/mounts ${pkgdir}/etc/mtab

	touch ${pkgdir}/var/log/lastlog
	chmod -v 664 ${pkgdir}/var/log/lastlog

	for f in fstab group hosts passwd profile resolv.conf securetty shells adduser.conf busybox.conf mdev.conf inittab hostname syslog.conf sysctl.conf; do
		install -m644 ${stuffdir}/${f} etc/
	done

	for f in shadow gshadow; do
		install -m600 ${stuffdir}/${f} etc/
	done

	for f in rc.init rc.shutdown rc.dhcp rc.local; do
		install -m600 ${stuffdir}/${f} etc/rc.d/
		chmod +x etc/rc.d/${f}
	done

	cat >${pkgdir}/etc/os-release<<EOF
NAME="${product_name}"
ID=${product_id}
VERSION_ID=${product_version}
PRETTY_NAME="${product_name} ${product_version}"
HOME_URL="${product_url}"
BUG_REPORT_URL="${product_bug_url}"
EOF

	cat >${pkgdir}/etc/issue<<EOF


       _                         _      _                  
      | |                       | |    (_)                 
      | | __ _ _ __  _   _ ___  | |     _ _ __  _   ___  __
  _   | |/ _` | '_ \| | | / __| | |    | | '_ \| | | \ \/ /
 | |__| | (_| | | | | |_| \__ \ | |____| | | | | |_| |>  < 
  \____/ \__,_|_| |_|\__,_|___/ |______|_|_| |_|\__,_/_/\_\
                                                           
                                                           

			  You are running on Linux \r on \m
EOF
}

build_toolchain() {
	cd ${tooldir}
	ln -sf . usr

	cd ${srcdir}
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${kernelver}.tar.xz
	tar -xf linux-${kernelver}.tar.xz
	cd linux-${kernelver}
	make mrproper
	make ARCH=$KARCH INSTALL_HDR_PATH=${tooldir} headers_install

	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.bz2
	tar -xf binutils-2.29.1.tar.bz2
	cd binutils-2.29.1
	mkdir -v ../binutils-build
	cd ../binutils-build
	../binutils-2.29.1/configure \
		--prefix=${tooldir} \
		--target=$XTARGET \
		--with-sysroot=${tooldir} \
		--disable-nls \
		--disable-multilib
	make configure-host -j $NUM_JOBS
	make -j $NUM_JOBS
	make install

	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/gcc/gcc-7.2.0/gcc-7.2.0.tar.xz
	wget http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	wget http://ftp.gnu.org/gnu/mpfr/mpfr-3.1.6.tar.xz
	wget http://www.multiprecision.org/mpc/download/mpc-1.0.3.tar.gz
	tar -xf gcc-7.2.0.tar.xz
	cd gcc-7.2.0
	tar xf ../mpfr-3.1.6.tar.xz
	mv -v mpfr-3.1.6 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.0.3.tar.gz
	mv mpc-1.0.3 mpc
	mkdir ../gcc-build
	cd ../gcc-build
	../gcc-7.2.0/configure \
		--prefix=${tooldir} \
		--build=$XHOST \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=${tooldir} \
		--with-arch=$XCPU \
		--with-newlib \
		--without-headers \
		--disable-nls  \
		--disable-shared \
		--disable-decimal-float \
		--disable-libgomp \
		--disable-libmudflap \
		--disable-libssp \
		--disable-libatomic \
		--disable-libquadmath \
		--disable-threads \
		--disable-multilib \
		--enable-languages=c
	make all-gcc all-target-libgcc -j $NUM_JOBS
	make install-gcc install-target-libgcc

	cd ${srcdir}
	wget http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure CROSS_COMPILE=$XTARGET- \
		--target=$XTARGET \
		--prefix=/
	make -j $NUM_JOBS
	make DESTDIR=${tooldir} install

	cd ${srcdir}
	rm -rf gcc-7.2.0
	tar -xf gcc-7.2.0.tar.xz
	cd gcc-7.2.0
	tar xf ../mpfr-3.1.6.tar.xz
	mv -v mpfr-3.1.6 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.0.3.tar.gz
	mv mpc-1.0.3 mpc
	rm -rf ../gcc-build
	mkdir ../gcc-build
	cd ../gcc-build
	../gcc-7.2.0/configure \
		--prefix=${tooldir} \
		--libdir=${tooldir}/lib \
		--build=$XHOST \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=${tooldir} \
		--with-arch=$XCPU \
		--enable-languages=c \
		--enable-c99 \
		--enable-long-long \
		--disable-libmudflap \
		--disable-multilib \
		--disable-nls
	make -j $NUM_JOBS
	make install
}

toolchain_variables() {
	export CC="$XTARGET-gcc ${BUILD} --sysroot=${pkgdir}"
	export CXX="$XTARGET-g++ ${BUILD} --sysroot=${pkgdir}"
	export AR="$XTARGET-ar"
	export AS="$XTARGET-as"
	export LD="$XTARGET-ld --sysroot=${pkgdir}"
	export RANLIB="$XTARGET-ranlib"
	export READELF="$XTARGET-readelf"
	export STRIP="$XTARGET-strip"
}

build_linux_headers() {
	cd ${srcdir}
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${kernelver}.tar.xz
	tar -xf linux-${kernelver}.tar.xz
	cd linux-${kernelver}
	make mrproper
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- INSTALL_HDR_PATH=${pkgdir}/usr headers_install
}

build_linux() {
	cd ${srcdir}
	rm -rf linux-${kernelver}*
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${kernelver}.tar.xz
	tar -xf linux-${kernelver}.tar.xz
	cd linux-${kernelver}
	make mrproper -j $NUM_JOBS
	make ARCH=$KARCH defconfig -j $NUM_JOBS
	sed -i "s/.*CONFIG_DEFAULT_HOSTNAME.*/CONFIG_DEFAULT_HOSTNAME=\"${kernelhost}\"/" .config
	sed -i "s/.*CONFIG_OVERLAY_FS.*/CONFIG_OVERLAY_FS=y/" .config
	echo "CONFIG_OVERLAY_FS_REDIRECT_DIR=y" >> .config
	echo "CONFIG_OVERLAY_FS_INDEX=y" >> .config
	sed -i "s/.*\\(CONFIG_KERNEL_.*\\)=y/\\#\\ \\1 is not set/" .config
	sed -i "s/.*CONFIG_KERNEL_XZ.*/CONFIG_KERNEL_XZ=y/" .config
	sed -i "s/.*CONFIG_FB_VESA.*/CONFIG_FB_VESA=y/" .config
	sed -i "s/.*CONFIG_LOGO_LINUX_CLUT224.*/CONFIG_LOGO_LINUX_CLUT224=y/" .config
	sed -i "s/^CONFIG_DEBUG_KERNEL.*/\\# CONFIG_DEBUG_KERNEL is not set/" .config
	sed -i "s/.*CONFIG_EFI_STUB.*/CONFIG_EFI_STUB=y/" .config
	echo "CONFIG_APPLE_PROPERTIES=n" >> .config
	grep -q "CONFIG_X86_32=y" .config
	if [ $? = 1 ] ; then
		echo "CONFIG_EFI_MIXED=y" >> .config
	fi
	make ARCH=$KARCH silentoldconfig -j $NUM_JOBS
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- -j $NUM_JOBS
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- INSTALL_MOD_PATH=${pkgdir} modules_install
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- INSTALL_FW_PATH=${pkgdir}/lib/firmware firmware_install
	cp -a arch/x86/boot/bzImage ${pkgdir}/boot/bzImage-${kernelver}
}

build_musl(){
	cd ${srcdir}
	wget http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--syslibdir=/lib \
		--enable-optimize=size
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_busybox() {
	cd ${srcdir}
	wget http://busybox.net/downloads/busybox-1.27.2.tar.bz2
	tar -xf busybox-1.27.2.tar.bz2
	cd busybox-1.27.2
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- defconfig -j $NUM_JOBS
	sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config
	sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- -j $NUM_JOBS
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- CONFIG_PREFIX=${pkgdir} install
	mkdir -p ${pkgdir}/usr/share/udhcpc
	cp examples/udhcp/simple.script ${pkgdir}/usr/share/udhcpc/default.script
	chmod +x ${pkgdir}/usr/share/udhcpc/default.script
	cd ${pkgdir}
	ln -sf bin/busybox init
	rm -rf linuxrc
}

build_iana_etc() {
	cd ${srcdir}
	wget http://sethwklein.net/iana-etc-2.30.tar.bz2
	tar -xf iana-etc-2.30.tar.bz2
	cd iana-etc-2.30
	make get -j $NUM_JOBS
	make STRIP=yes -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_nano() {
	cd ${srcdir}
	wget https://www.nano-editor.org/dist/v2.9/nano-2.9.0.tar.xz
	tar -xf nano-2.9.0.tar.xz
	cd nano-2.9.0
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-nls
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_openntpd() {
	cd ${srcdir}
	wget https://fastly.cdn.openbsd.org/pub/OpenBSD/OpenNTPD/openntpd-6.2p3.tar.gz
	tar -xf openntpd-6.2p3.tar.gz
	cd openntpd-6.2p3
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--with-privsep-user=ntp
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_links() {
	cd ${srcdir}
	wget http://links.twibright.com/download/links-2.14.tar.gz
	tar -xf links-2.14.tar.gz
	cd links-2.14
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-graphics \
		--enable-utf8 \
		--with-ipv6 \
		--with-ssl \
		--with-zlib \
		--without-x
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_htop() {
	cd ${srcdir}
	wget http://hisham.hm/htop/releases/2.0.2/htop-2.0.2.tar.gz
	tar -xf htop-2.0.2.tar.gz
	cd htop-2.0.2
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_ncurses() {
	cd ${srcdir}
	wget http://invisible-mirror.net/archives/ncurses/current/ncurses-6.0-20171125.tgz
	tar -xf ncurses-6.0-20171125.tgz
	cd ncurses-6.0-20171125
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--with-pkg-config-libdir=/usr/lib/pkgconfig
		--without-cxx-binding \
		--without-debug \
		--without-ada \
		--without-tests \
		--with-normal \
		--with-shared \
		--disable-nls \
		--enable-pc-files \
		--enable-widec 
	make -j $NUM_JOBS
	make install
}

build_e2fsprogs() {
	cd ${srcdir}
	wget http://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v1.43.7/e2fsprogs-1.43.7.tar.gz
	tar -xf e2fsprogs-1.43.7.tar.gz
	cd e2fsprogs-1.43.7
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--enable-elf-shlibs \
		--enable-symlink-install \
		--disable-fsck \
		--disable-uuidd \
		--disable-libuuid \
		--disable-libblkid \
		--disable-tls \
		--disable-nls
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install install-libs
}


build_util_linux() {
	cd ${srcdir}
	wget https://www.kernel.org/pub/linux/utils/util-linux/v2.31/util-linux-2.31.tar.xz
	tar -xf util-linux-2.31.tar.xz
	cd util-linux-2.31
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--enable-raw \
		--disable-uuidd \
		--disable-nls \
		--disable-tls \
		--disable-kill \
		--disable-login \
		--disable-last \
		--disable-sulogin \
		--disable-su \
		--disable-pylibmount \
		--disable-makeinstall-chown \
		--disable-makeinstall-setuid \
		--without-python \
		--without-systemd \
		--without-systemdsystemunitdi
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_libressl() {
	cd ${srcdir}
	wget https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-2.6.3.tar.gz
	tar -xf libressl-2.6.3.tar.gz
	cd libressl-2.6.3
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_openssh() {
	cd ${srcdir}
	wget https://fastly.cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-7.6p1.tar.gz
	tar -xf openssh-7.6p1.tar.gz
	cd openssh-7.6p1
	./configure \
		--host=$XTARGET \
		--prefix=/usr \
		--libdir=/usr/lib \
		--sysconfdir=/etc/ssh \
		--libexecdir=/usr/lib/ssh \
		--with-pid-dir=/run \
		--with-mantype=man \
		--with-privsep-user=nobody \
		--with-xauth=/usr/bin/xauth \
		--without-stackprotect \
		--with-md5-passwords \
		--disable-strip \
		--disable-lastlog \
		--disable-utmp \
		--disable-utmpx \
		--disable-btmp \
		--disable-wtmp \
		--disable-wtmpx \
		--disable-pututline \
		--disable-pututxline
	sed -i '/USE_BTMP/d' config.h
	sed -i '/USE_UTMP/d' config.h
	sed -i 's@HAVE_DECL_HOWMANY 1@HAVE_DECL_HOWMANY 0@' config.h
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_curl() {
	cd ${srcdir}
	wget https://curl.haxx.se/download/curl-7.56.1.tar.xz
	tar -xf curl-7.56.1.tar.xz
	cd curl-7.56.1
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_kbd() {
	cd ${srcdir}
	wget https://www.kernel.org/pub/linux/utils/kbd/kbd-2.0.4.tar.xz
	tar -xf kbd-2.0.4.tar.xz
	cd kbd-2.0.4
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-vlock \
		--disable-nls
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_zlib() {
	cd ${srcdir}
	wget http://zlib.net/zlib-1.2.11.tar.xz
	tar -xf zlib-1.2.11.tar.xz
	cd zlib-1.2.11
	./configure \
		--prefix=/usr \
		--libdir=/usr/lib
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_file() {
	cd ${srcdir}
	wget ftp://ftp.astron.com/pub/file/file-5.32.tar.gz
	tar -xf file-5.32.tar.gz
	cd file-5.32
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_sudo() {
	cd ${srcdir}
	wget https://www.sudo.ws/dist/sudo-1.8.21p2.tar.gz
	tar -xf sudo-1.8.21p2.tar.gz
	cd sudo-1.8.21p2
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-nls
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_libarchive() {
	cd ${srcdir}
	wget http://www.libarchive.org/downloads/libarchive-3.3.2.tar.gz
	tar -xf libarchive-3.3.2.tar.gz
	cd libarchive-3.3.2
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_mksh() {
	cd ${srcdir}
	wget https://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R56b.tgz
	tar -xf mksh-R56b.tgz
	cd mksh
	sh Build.sh -r
	install -D -m 755 mksh $pkgdir/bin/mksh
}

build_less() {
	cd ${srcdir}
	wget http://www.greenwoodsoftware.com/less/less-487.tar.gz
	tar -xf less-487.tar.gz
	cd less-487
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_readline() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/readline/readline-7.0.tar.gz
	tar -xf readline-7.0.tar.gz
	cd readline-7.0
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_grub() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/grub/grub-2.02.tar.xz
	tar -xf grub-2.02.tar.xz
	cd grub-2.02
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--enable-boot-time \
		--disable-werror \
		--disable-nls \
		--disable-liblzma
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_m4() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/m4/m4-1.4.18.tar.xz
	tar -xf m4-1.4.18.tar.xz
	cd m4-1.4.18
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_sed() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/sed/sed-4.4.tar.xz
	tar -xf sed-4.4.tar.xz
	cd sed-4.4
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-i18n \
		--disable-nls
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_gawk() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/gawk/gawk-4.2.0.tar.xz
	tar -xf gawk-4.2.0.tar.xz
	cd gawk-4.2.0
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-nls
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_gmp() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	tar -xf gmp-6.1.2.tar.xz
	cd gmp-6.1.2
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_mpfr() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/mpfr/mpfr-3.1.6.tar.xz
	tar -xf mpfr-3.1.6.tar.xz
	cd mpfr-3.1.6
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_mpc() {
	cd ${srcdir}
	wget http://www.multiprecision.org/mpc/download/mpc-1.0.3.tar.gz
	tar -xf mpc-1.0.3.tar.gz
	cd mpc-1.0.3
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_gcc() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/gcc/gcc-7.2.0/gcc-7.2.0.tar.xz
	tar -xf gcc-7.2.0.tar.xz
	cd gcc-7.2.0
	mkdir build
	cd build
	../configure \
		--host=$XTARGET \
		${default_configure} \
		--with-headers=no \
		--with-arch=$XCPU \
		--with-system-zlib \
		--with-target-libiberty=no \
		--with-target-zlib=no \
		--with-multilib-list= \
		--disable-multilib \
		--disable-nls \
		--disable-mudflap \
		--disable-libmudflap \
		--disable-libgomp \
		--disable-debug \
		--disable-bootstrap \
		--disable-libsanitizer \
		--disable-vtable-verify \
		--disable-gnu-indirect-function \
		--disable-libmpx \
		--disable-libquadmath \
		--enable-libstdcxx-time \
		--enable-lto \
		--enable-libssp \
		--enable-languages=c,c++,lto \
		--enable-clocale=generic
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} \
		install-gcc \
		install-lto-plugin \
		install-target-libgcc \
		install-target-libssp \
		install-target-libstdc++-v3
}

build_binutils() {
	cd ${srcdir}
	rm -rf binutils*
	wget http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.bz2
	tar -xf binutils-2.29.1.tar.bz2
	cd binutils-2.29.1
	mkdir build
	cd build
	../configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-nls \
		--disable-werror \
		--disable-install-libbfd \
		--enable-initfini-array \
		--enable-deterministic-archives \
		--enable-lto
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} \
		install-gas \
		install-ld \
		install-binutils
}

build_make() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/make/make-4.2.1.tar.bz2
	tar -xf make-4.2.1.tar.bz2
	cd make-4.2.1
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-nls
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_patch() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/patch/patch-2.7.5.tar.xz
	tar -xf patch-2.7.5.tar.xz
	cd patch-2.7.5
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-nls
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_perl() {
	cd ${srcdir}
	wget http://www.cpan.org/src/5.0/perl-5.26.1.tar.xz
	tar -xf perl-5.26.1.tar.xz
	cd perl-5.26.1
	./Configure -des \
		-Aldflags="$CFLAGS" \
		-Dprefix=/usr -Dvendorprefix=/usr \
		-Dinstallprefix=${pkgdir} \
		-Dprivlib=/usr/lib/perl5/core_perl \
		-Darchlib=/usr/lib/perl5/core_perl \
		-Dsitelib=/usr/lib/perl5/site_perl \
		-Dsitearch=/usr/lib/perl5/site_perl \
		-Dvendorlib=/usr/lib/perl5/vendor_perl \
		-Dvendorarch=/usr/lib/perl5/vendor_perl \
		-Dscriptdir=/usr/bin \
		-Dsitescript=/usr/bin \
		-Dvendorscript=/usr/bin \
		-Dinc_version_list=none \
		-Dman1dir=/usr/share/man/man1perl -Dman1ext=1perl \
		-Dman3dir=/usr/share/man/man3perl -Dman3ext=3perl
	make -j $NUM_JOBS
	make install
}

build_pkg_config() {
	cd ${srcdir}
	wget https://pkg-config.freedesktop.org/releases/pkg-config-0.29.2.tar.gz
	tar -xf pkg-config-0.29.2.tar.gz
	cd pkg-config-0.29.2
	./configure \
		--host=$XTARGET \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_git() {
	cd ${srcdir}
	wget http://cdn.kernel.org/pub/software/scm/git/git-2.15.0.tar.xz
	tar -xf git-2.15.0.tar.xz
	cd git-2.15.0
	cat >> config.mak <<-EOF
		NO_GETTEXT=YesPlease
		NO_SVN_TESTS=YesPlease
		NO_REGEX=YesPlease
		USE_LIBPCRE2=YesPlease
		NO_NSEC=YesPlease
		NO_SYS_POLL_H=1
		CFLAGS=$CFLAGS
EOF
	make -j1 prefix=/usr gitexecdir=/usr/libexec DESTDIR=${pkgdir} perl/perl.mak
	make prefix=/usr gitexecdir=/usr/libexec DESTDIR=${pkgdir} -j $NUM_JOBS
	make -j1 prefix=/usr \
		DESTDIR=${pkgdir} \
		INSTALLDIRS=vendor \
		install
}

build_xz() {
	cd ${srcdir}
	wget http://tukaani.org/xz/xz-5.2.3.tar.xz
	tar -xf xz-5.2.3.tar.xz
	cd xz-5.2.3
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-rpath \
		--disable-werror \
		--disable-nls
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_bzip2() {
	cd ${srcdir}
	wget http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz
	tar -xf bzip2-1.0.6.tar.gz
	cd bzip2-1.0.6
	patch -Np1 -i ${stuffdir}/bzip2.patch
	make -j $NUM_JOBS
	make PREFIX=${pkgdir}/usr install
	make -f Makefile-libbz2_so -j $NUM_JOBS
	make -f Makefile-libbz2_so PREFIX=${pkgdir}/usr install
}

build_attr() {
	cd ${srcdir}
	wget http://download.savannah.gnu.org/releases/attr/attr-2.4.47.src.tar.gz
	tar -xf attr-2.4.47.src.tar.gz
	cd attr-2.4.47
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-gettext
	make -j $NUM_JOBS
	make DIST_ROOT=${pkgdir} install install-dev install-lib
}


build_acl() {
	cd ${srcdir}
	wget http://download.savannah.gnu.org/releases/acl/acl-2.2.52.src.tar.gz
	tar -xf acl-2.2.52.src.tar.gz
	cd acl-2.2.52
	./configure \
		--host=$XTARGET \
		${default_configure} \
		--disable-gettext
	make -j $NUM_JOBS
	make DIST_ROOT=${pkgdir} install install-dev install-lib
}

build_cracklib() {
	cd ${srcdir}
	wget https://github.com/cracklib/cracklib/releases/download/cracklib-2.9.6/cracklib-2.9.6.tar.gz
	tar -xf cracklib-2.9.6.tar.gz
	cd cracklib-2.9.6
	./configure \
		--build=$XTARGET --host=$HOST --target=$XTARGET \
		${default_configure} \
		--with-default-dict \
		--without-python \
		--disable-static \
		--disable-nls
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

strip_filesystem() {
	find ${pkgdir} -type f | xargs file 2>/dev/null | grep "LSB executable"     | cut -f 1 -d : | xargs strip --strip-all --strip-unneeded --strip-debug 2>/dev/null || true
	find ${pkgdir} -type f | xargs file 2>/dev/null | grep "shared object"      | cut -f 1 -d : | xargs strip --strip-all --strip-unneeded --strip-debug 2>/dev/null || true
	find ${pkgdir} -type f | xargs file 2>/dev/null | grep "current ar archive" | cut -f 1 -d : | xargs strip -g 
}

make_iso() {
	cd ${pkgdir}
	find . | cpio -H newc -o | gzip -9 > ${isodir}/rootfs.gz
	cp -a ${srcdir}/linux-${kernelver}/arch/x86/boot/bzImage ${isodir}/bzImage

	cd ${isodir}
	cp ${srcdir}/syslinux-6.03/bios/core/isolinux.bin ${isodir}/isolinux.bin
	cp ${srcdir}/syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 ${isodir}/ldlinux.c32

	mkdir -p ${isodir}/efi/boot
cat << CEOF > ${isodir}/efi/boot/startup.nsh
echo -off
echo ${product_name} is starting...
\\bzImage initrd=\\rootfs.gz
CEOF

	echo 'default bzImage initrd=rootfs.gz' > ${isodir}/isolinux.cfg

	genisoimage \
  		-J -r -o ${topdir}/${product_name}-${product_version}.iso \
  		-b isolinux.bin \
  		-c boot.cat \
  		-input-charset UTF-8 \
  		-no-emul-boot \
  		-boot-load-size 4 \
  		-boot-info-table \
  		${isodir}/

	isohybrid -u ${topdir}/${product_name}-${product_version}.iso
}

make_rootfs_archive() {
	cd ${pkgdir}
	tar jcfv ${topdir}/${product_name}-${product_version}-${XARCH}.tar.bz2 *
}

just_prepare
prepare_cross
build_toolchain
toolchain_variables
clean_sources
prepare_filesystem
build_linux_headers
build_musl
build_busybox
build_mksh
build_iana_etc
build_zlib
build_file
build_gmp
build_mpfr
build_mpc
build_m4
build_sed
build_gawk
build_gcc
build_binutils
build_make
build_patch
build_perl
build_pkg_config
build_bzip2
build_attr
build_acl
build_ncurses
build_readline
build_e2fsprogs
build_util_linux
build_kbd
build_xz
build_htop
build_nano
build_sudo
build_less
build_libressl
build_openssh
build_openntpd
build_curl
build_git
build_links
build_libarchive
case $XARCH in
	i686)
		build_grub
		;;
	x86_64)
		build_grub
		;;
	powerpc64)
		echo "In development"
		;;
	*)
		echo "No bootloader available"
		exit 0
esac
strip_filesystem
# make_iso
make_rootfs_archive

exit 0
