#!/bin/sh
#

set -e -x

product_name="JanusLinux"
product_version="0.1"
product_id="janus"
product_bug_url="https://github.com/protonesso/janus/issues"
product_url="januslinux.github.io"

NUM_JOBS=$(expr $(nproc) + 1)

topdir=$(pwd)
srcdir=${topdir}/work/sources
tooldir=${topdir}/work/tools
pkgdir=${topdir}/work/rootfs
isodir=${topdir}/work/rootcd
stuffdir=$(pwd)/stuff

xflags="-Os -g0 -pipe -fno-stack-protector -fomit-frame-pointer -fno-asynchronous-unwind-tables -U_FORTIFY_SOURCE"
default_configure="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --sysconfdir=/etc --bindir=/usr/bin --sbindir=/usr/sbin --localstatedir=/var"

kernelhost="janus"
kernelver="4.14.2"

just_prepare() {
	rm -rf ${srcdir} ${tooldir} ${pkgdir} ${isodir}
	mkdir -p ${srcdir} ${tooldir} ${pkgdir} ${isodir}

	# optimization
	export XFLAGS="-O3 -g0 -pipe -fstack-protector-strong"
	export XLDLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro"

	# toolchain optimization
	export BFLAGS="-O3 -g0 -pipe -fstack-protector-strong"
	export BLDLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro"

	export PATH="${tooldir}/bin:$PATH"
}

clean_sources() {
	rm -rf ${srcdir}/*
}

prepare_cross() {
	case $XARCH in
		x86_64)
			export HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')
			export TARGET="x86_64-unknown-linux-musl"
			export KARCH="x86_64"
			export BUILDCFLAGS="-m64 -march=x86-64 -mtune=generic"
			export LIBSUFFIX="64"
			export GCCOPTS="--with-arch=nocona"
			;;
		i386)
			export HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')
			export TARGET="i686-unknown-linux-musl"
			export KARCH="i386"
			export BUILDCFLAGS="-m32 -march=i686 -mtune=generic"
			export LIBSUFFIX=
			export GCCOPTS="--with-arch=i686"
			;;
		*)
			echo "XARCH isn't set!"
			echo "Please run: XARCH=[supported architecture] sh make.sh"
			echo "Supported architectures: x86_64, i386"
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

	for f in fstab group hosts passwd profile securetty shells mdev.conf inittab hostname issue resolv.conf host.conf; do
		install -m644 ${stuffdir}/${f} etc/
	done

	for f in shadow gshadow; do
		install -m640 ${stuffdir}/${f} etc/
	done

	for f in rc.init rc.shutdown rc.local rc.dhcp; do
		install -m644 ${stuffdir}/${f} etc/rc.d/
		chmod +x etc/rc.d/${f}
	done

	cat >${pkgdir}/etc/os-release << EOF
NAME="${product_name}"
ID="${product_id}-$(date -Idate)"
VERSION_ID="${product_version}-$(date -Idate)"
PRETTY_NAME="${product_name} ${product_version}-$(date -Idate)"
HOME_URL="${product_url}"
BUG_REPORT_URL="${product_bug_url}"
EOF

	echo "${product_name}-${product_version}-$(date -Idate)" >> ${pkgdir}/etc/jiz.vash
}

build_toolchain() {
	export CFLAGS="$BFLAGS"
	export CXXFLAGS="$BFLAGS"
	export LDFLAGS="$BLDFLAGS"

	mkdir -p ${tooldir}/$TARGET/{lib,include}
	cd ${tooldir}/$TARGET
	
	case $XARCH in
		x86_64)
			cd ${tooldir}
			ln -sf lib lib64
			cd ${tooldir}/$TARGET
			ln -sf ../lib lib
			ln -sf lib lib64
			ln -sf ../include include
			;;
		*)
			cd ${tooldir}/$TARGET
			ln -sf ../lib lib
			ln -sf ../include include
	esac

	cd ${tooldir}
	ln -sf . usr

	cd $SRC
	wget http://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.xz
	tar -xf binutils-2.29.1.tar.xz
	cd binutils-2.29.1
	mkdir -v ../binutils-build
	cd ../binutils-build
	AR=ar AS=as \
	../binutils-2.29.1/configure \
		--host=$HOST \
		--target=$TARGET \
		--prefix=${tooldir} \
		--with-sysroot=${tooldir} \
		--enable-deterministic-archives \
		--enable-gold=yes \
		--enable-plugins \
		--enable-threads \
		--disable-compressed-debug-sections \
		--disable-werror \
		--disable-nls \
		--disable-multilib \
		--disable-ppl-version-check \
		--disable-cloog-version-check
	make configure-host -j$JOBS
	make -j$JOBS
	make install

	cd $SRC
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${kernelver}.tar.xz
	tar -xf linux-${kernelver}.tar.xz
	cd linux-${kernelver}
	make mrproper
	make ARCH=$KARCH INSTALL_HDR_PATH=${tooldir} headers_install

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
	patch -p1 $KEEP/0001-libgcc_s.patch
	mkdir ../gcc-build
	cd ../gcc-build
	AR=ar \
	../gcc-7.2.0/configure \
		--build=$HOST \
		--host=$HOST \
		--target=$TARGET \
		--prefix=${tooldir} \
		--with-sysroot=${tooldir} \
		--with-newlib \
		--without-headers \
		--without-ppl \
		--without-cloog \
		--disable-shared \
		--disable-nls  \
		--disable-decimal-float \
		--disable-libmudflap \
		--disable-libgomp \
		--disable-libssp \
		--disable-libatomic \
		--disable-libitm \
		--disable-libsanitizer \
		--disable-libquadmath \
		--disable-libvtv \
		--disable-libcilkrts \
		--disable-libstdc++-v3 \
		--disable-threads \
		--disable-multilib \
		--disable-libmpx \
		--disable-gnu-indirect-function \
		--enable-languages=c \
		--enable-clocale=generic \
		$GCCOPTS
	make all-gcc all-target-libgcc -j$JOBS
	make install-gcc install-target-libgcc

	cd $SRC
	wget http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure \
		CROSS_COMPILE=$TARGET- \
		--target=$TARGET \
		--prefix=/
	make -j$JOBS
	make DESTDIR=${tooldir} install

	cd $SRC
	rm -rf gcc-build
	rm -rf gcc-7.2.0
	tar -xf gcc-7.2.0.tar.xz
	cd gcc-7.2.0
	tar xf ../mpfr-3.1.6.tar.xz
	mv mpfr-3.1.6 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.0.3.tar.gz
	mv mpc-1.0.3 mpc
	patch -p1 $KEEP/0001-libgcc_s.patch
	mkdir ../gcc-build
	cd ../gcc-build
	AR=ar \
	../gcc-7.2.0/configure \
		--build=$HOST \
		--host=$HOST \
		--target=$TARGET \
		--prefix=${tooldir} \
		--with-sysroot=${tooldir} \
		--enable-__cxa_atexit \
		--enable-c99 \
		--enable-long-long \
		--enable-libstdcxx-time \
		--enable-threads=posix \
		--enable-languages=c,c++ \
		--enable-checking=release \
		--enable-fully-dynamic-string \
		--disable-symvers \
		--disable-gnu-indirect-function \
		--disable-libmudflap \
		--disable-multilib \
		--disable-libsanitizer \
		--disable-libmpx \
		--disable-nls \
		--disable-static \
		--disable-lto-plugin \
		$GCCOPTS
	make AS_FOR_TARGET="$TARGET-as" LD_FOR_TARGET="$TARGET-ld" -j$JOBS
	make install
}

build_variables() {
	export CC="$TARGET-gcc --sysroot=${pkgdir}"
	export CXX="$TARGET-g++ --sysroot=${pkgdir}"
	export LD="$TARGET-ld --sysroot=${pkgdir}"
	export AS="$TARGET-as --sysroot=${pkgdir}"
	export AR="$TARGET-ar"
	export NM="$TARGET-nm"
	export OBJCOPY="$TARGET-objcopy"
	export RANLIB="$TARGET-ranlib"
	export READELF="$TARGET-readelf"
	export STRIP="$TARGET-strip"
	export SIZE="$TARGET-size"
	export CFLAGS="$XFLAGS $BUILDCFLAGS"
	export CFLAGS="$XFLAGS $BUILDCFLAGS"
	export LDFLAGS="$XLDFLAGS"
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
	cp -a arch/x86/boot/bzImage ${pkgdir}/boot/bzImage-${kernelver}
}

build_musl(){
	cd ${srcdir}
	wget http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure \
		CROSS_COMPILE=$TARGET- \
		${default_configure} \
		--disable-static \
		--target=$TARGET
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

build_mksh() {
	cd ${srcdir}
	wget https://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R56b.tgz
	tar -xf mksh-R56b.tgz
	cd mksh
	sh Build.sh -r
	install -D -m 755 mksh $pkgdir/bin/mksh
}

build_dhcpcd() {
	cd ${srcdir}
	wget https://roy.marples.name/downloads/dhcpcd/dhcpcd-6.11.5.tar.xz
	tar -xf dhcpcd-6.11.5.tar.xz
	cd dhcpcd-6.11.5
	./configure \
		${default_configure} \
		--host=$TARGET
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
		--libdir=/usr/lib \
		--shared
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_ncurses() {
	cd ${srcdir}
	wget http://invisible-mirror.net/archives/ncurses/current/ncurses-6.0-20171125.tgz
	tar -xf ncurses-6.0-20171125.tgz
	cd ncurses-6.0-20171125
	./configure \
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
		--enable-widec \
		--host=$TARGET
	make -j $NUM_JOBS
	make install
}

build_libressl() {
	cd ${srcdir}
	wget https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-2.6.3.tar.gz
	tar -xf libressl-2.6.3.tar.gz
	cd libressl-2.6.3
	./configure \
		${default_configure} \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}


build_openssh() {
	cd ${srcdir}
	wget https://fastly.cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-7.6p1.tar.gz
	tar -xf openssh-7.6p1.tar.gz
	cd openssh-7.6p1
	./configure \
		--prefix=/usr \
		--sbindir=/usr/bin \
		--libexecdir=/usr/lib/ssh \
		--sysconfdir=/etc/ssh \
		--without-rpath \
		--with-ssl-engine \
		--with-privsep-user=nobody \
		--with-xauth=/usr/bin/xauth \
		--with-md5-passwords \
		--with-pid-dir=/run \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_libcap() {
	cd ${srcdir}
	wget https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.25.tar.xz
	tar -xf libcap-2.25.tar.xz
	cd libcap-2.25
	patch -Np1 -i  $KEEP/libcap-2.25-gperf.patch
	make -j $NUM_JOBS
	make install \
		DESTDIR=${pkgdir} \
		LIBDIR=/usr/lib \
		SBINDIR=/usr/bin \
		PKGCONFIGDIR=/usr/lib/pkgconfig \
		RAISE_SETFCAP=no
}

build_pciutils() {
	cd ${srcdir}
	wget https://www.kernel.org/pub/software/utils/pciutils/pciutils-3.5.4.tar.xz
	tar -xf pciutils-3.5.4.tar.xz
	cd pciutils-3.5.4
	make -j $NUM_JOBS \
		PREFIX=/usr \
		SHAREDIR=/usr/share/hwdata \
		SHARED=yes
	make \
		PREFIX=${pkgdir}/usr \
		SHAREDIR=/usr/share/hwdata \
		SHARED=yes \
		install install-lib
}

build_libnl() {
	cd ${srcdir}
	wget https://github.com/thom311/libnl/releases/download/libnl3_4_0/libnl-3.4.0.tar.gz
	tar -xf libnl-3.4.0.tar.gz
	cd libnl-3.4.0
	sed -i '/linux-private\/linux\/libc-compat/d' Makefile.in Makefile.am
	sed -i 's/linux-private\///g' lib/route/link/vrf.c
	rm -r include/linux-private/linux/libc-compat.h
	./configure \
		${default_configure} \
		--disable-static \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_wirelesstools() {
	cd ${srcdir}
	wget http://www.hpl.hp.com/personal/Jean_Tourrilhes/Linux/wireless_tools.29.tar.gz
	tar -xf wireless_tools.29.tar.gz
	cd wireless_tools.29
	sed -i s/gcc/\$\TARGET\-gcc/g Makefile
	sed -i s/\ ar/\ \$\TARGET\-ar/g Makefile
	sed -i s/ranlib/\$\TARGET\-ranlib/g Makefile
	make PREFIX=${pkgdir} -j $NUM_JOBS
	make install PREFIX=${pkgdir}
}

build_wpasupplicant() {
	cd ${srcdir}
	wget http://hostap.epitest.fi/releases/wpa_supplicant-2.6.tar.gz
	tar -xf wpa_supplicant-2.6.tar.gz
	cd wpa_supplicant-2.6
	cd wpa_supplicant
cat > .config << EOF
CONFIG_BACKEND=file
CONFIG_CTRL_IFACE=y
CONFIG_DEBUG_FILE=y
CONFIG_DEBUG_SYSLOG=y
CONFIG_DEBUG_SYSLOG_FACILITY=LOG_DAEMON
CONFIG_DRIVER_NL80211=y
CONFIG_DRIVER_WEXT=y
CONFIG_DRIVER_WIRED=y
CONFIG_EAP_GTC=y
CONFIG_EAP_LEAP=y
CONFIG_EAP_MD5=y
CONFIG_EAP_MSCHAPV2=y
CONFIG_EAP_OTP=y
CONFIG_EAP_PEAP=y
CONFIG_EAP_TLS=y
CONFIG_EAP_TTLS=y
CONFIG_IEEE8021X_EAPOL=y
CONFIG_IPV6=y
CONFIG_LIBNL32=y
CONFIG_PEERKEY=y
CONFIG_PKCS12=y
CONFIG_READLINE=y
CONFIG_SMARTCARD=y
CONFIG_WPS=y
EOF
	make BINDIR=/usr/bin LIBDIR=/usr/lib -j $NUM_JOBS
	make DESTDIR=${pkgdir} BINDIR=/usr/bin LIBDIR=/usr/lib install
}


build_shadow() {
	cd ${srcdir}
	wget https://github.com/shadow-maint/shadow/releases/download/4.5/shadow-4.5.tar.xz
	tar -xf shadow-4.5.tar.xz
	cd shadow-4.5
	./configure \
		${default_configure} \
		--disable-static \
		--without-libcrack \
		--without-nscd \
		--without-audit \
		--without-acl \
		--without-attr \
		--without-selinux \
		--with-group-name-max-length=32 \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_util_linux() {
	cd ${srcdir}
	wget https://www.kernel.org/pub/linux/utils/util-linux/v2.31/util-linux-2.31.tar.xz
	tar -xf util-linux-2.31.tar.xz
	cd util-linux-2.31
	./configure \
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
		--without-systemdsystemunitdi \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}


build_e2fsprogs() {
	cd ${srcdir}
	wget http://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v1.43.7/e2fsprogs-1.43.7.tar.gz
	tar -xf e2fsprogs-1.43.7.tar.gz
	cd e2fsprogs-1.43.7
	./configure \
		${default_configure} \
		--enable-elf-shlibs \
		--enable-symlink-install \
		--disable-fsck \
		--disable-uuidd \
		--disable-libuuid \
		--disable-libblkid \
		--disable-tls \
		--disable-nls \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install install-libs
}

build_curl() {
	cd ${srcdir}
	wget https://curl.haxx.se/download/curl-7.56.1.tar.xz
	tar -xf curl-7.56.1.tar.xz
	cd curl-7.56.1
	./configure \
		${default_configure} \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_kbd() {
	cd ${srcdir}
	wget https://www.kernel.org/pub/linux/utils/kbd/kbd-2.0.4.tar.xz
	tar -xf kbd-2.0.4.tar.xz
	cd kbd-2.0.4
	./configure \
		${default_configure} \
		--disable-vlock \
		--disable-nls \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_file() {
	cd ${srcdir}
	wget ftp://ftp.astron.com/pub/file/file-5.32.tar.gz
	tar -xf file-5.32.tar.gz
	cd file-5.32
	./configure \
		${default_configure} \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}


build_libarchive() {
	cd ${srcdir}
	wget http://www.libarchive.org/downloads/libarchive-3.3.2.tar.gz
	tar -xf libarchive-3.3.2.tar.gz
	cd libarchive-3.3.2
	./configure \
		${default_configure} \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_readline() {
	cd ${srcdir}
	wget http://ftp.gnu.org/gnu/readline/readline-7.0.tar.gz
	tar -xf readline-7.0.tar.gz
	cd readline-7.0
	./configure \
		${default_configure} \
		--host=$TARGET
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_git() {
	cd ${srcdir}
	wget http://cdn.kernel.org/pub/software/scm/git/git-2.15.0.tar.xz
	tar -xf git-2.15.0.tar.xz
	cd git-2.15.0
	cat >> config.mak << EOF
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

build_iproute2() {
	cd ${srcdir}
	wget https://www.kernel.org/pub/linux/utils/net/iproute2/iproute2-4.14.1.tar.xz
	tar -xf iproute2-4.14.1.tar.xz
	cd iproute2-4.14.1
	./configure \
		${default_configure} \
		--disable-static \
		--host=$TARGET
	make CCOPTS="$CFLAGS" LIBDIR=/usr/lib  -j $NUM_JOBS
	make -j1 DESTDIR=${pkgdir} LIBDIR=/usr/lib PREFIX=/usr install
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

	cd ${srcdir}
	wget https://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
	tar -xf syslinux-6.03.tar.xz

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
		
	xorriso \
		-as mkisofs -J -r \
		-o ${topdir}/${product_name}-${product_version}-$(date -Idate).iso \
		-b isolinux.bin \
		-c boot.cat \
		-input-charset UTF-8 \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		${isodir}/

}

make_rootfs_archive() {
	cd ${pkgdir}
	fakeroot tar jcfv ${topdir}/${product_name}-${product_version}-$(date -Idate).tar.bz2 *
}

just_prepare
prepare_cross
build_toolchain
toolchain_variables
clean_sources
prepare_filesystem
build_iana_etc
build_linux_headers
build_musl
build_busybox
build_zlib
build_file
build_readline
build_ncurses
build_libcap
build_e2fsprogs
build_util_linux
build_shadow
build_kbd
build_iproute2
build_mksh
build_pciutils
build_libressl
build_openssh
build_libarchive
build_curl
build_git
build_dhcpcd
build_libnl
build_wirelesstools
build_wpasupplicant
build_linux
strip_filesystem
make_iso
make_rootfs_archive

exit 0
