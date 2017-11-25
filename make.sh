#!/bin/bash
#

set -e

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
default_cross_configure="--build=$XTARGET --host=$XTARGET --target=$XTARGET"
default_musl_configure="--build=$XTARGET_MUSL --host=$XTARGET_MUSL --target=$XTARGET_MUSL"

kernelhost="janus"
kernelver="4.14.2"

just_prepare() {
	rm -rf ${srcdir} ${tooldir} ${pkgdir} ${isodir}
	mkdir -p ${srcdir} ${tooldir} ${pkgdir} ${isodir}

	export CFLAGS="$xflags"
	export CXXLAGS="$CFLAGS"

	export PATH="${tooldir}/bin:$PATH"
}

prepare_cross() {
	case $XARCH in
		i686)
			export XHOST=$(echo ${MACHTYPE} | sed "s/-[^-]*/-cross/")
			export XCPU=i686
			export XTARGET=$XCPU-pc-linux-musl
			export XTARGET_MUSL=i386-pc-linux-musl
			export KARCH=i386
			export libSuffix=
			;;
		x86_64)
			export XHOST=$(echo ${MACHTYPE} | sed "s/-[^-]*/-cross/")
			export XCPU=nocona
			export XTARGET=x86_64-pc-linux-musl
			export XTARGET_MUSL=x86_64-pc-linux-musl
			export KARCH=x86_64
			export libSuffix=64
			;;
		*)
			echo "XARCH isn't set!"
			echo "Please run: XARCH=[supported architecture] sh make.sh"
			echo "Supported architectures: i686, x86_64"
			exit 0
	esac
}

prepare_filesystem() {
    cd ${pkgdir}

    for _d in boot dev etc home usr var run/lock janus; do
            install -d -m755 ${_d}
    done

    for _d in bin include lib share/misc; do
        install -d -m755 usr/${_d}
    done
    
    for _d in $(seq 8); do
        install -d -m755 usr/share/man/man${_d}
    done
    
    for _d in bin lib sbin; do
        install -d -m755 janus/${_d}
    done
    
    for _d in skel rc.d; do
        install -d -m755 etc/${_d}
    done
    
    cd ${pkgdir}/usr
    ln -sf bin sbin
    
    cd ${pkgdir}
    ln -sf usr/bin bin
    ln -sf usr/bin sbin
    ln -sf usr/lib lib

    install -d -m555 proc
    install -d -m555 sys
    install -d -m0750 root
    install -d -m1777 tmp

    install -d var/{cache/man,lib,log}
    install -d -m1777 var/{tmp,spool/{,mail,uucp}}
    ln -s spool/mail var/mail
    ln -s ../run var/run

    ln -s /proc/mounts etc/mtab

	for f in fstab group hosts passwd profile resolv.conf securetty shells adduser.conf busybox.conf mdev.conf inittab hostname syslog.conf; do
		install -m644 ${stuffdir}/${f} etc/
	done

	for f in shadow ; do
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
${product_name} ${product_version} \r \l
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
		--prefix=/ \
		--target=$XTARGET
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
	export CC="$XTARGET-gcc --sysroot=${pkgdir}"
	export CXX="$XTARGET-g++ --sysroot=${pkgdir}"
	export AR="$XTARGET-ar"
	export AS="$XTARGET-as"
	export LD="$XTARGET-ld --sysroot=${pkgdir}"
	export RANLIB="$XTARGET-ranlib"
	export READELF="$XTARGET-readelf"
	export STRIP="$XTARGET-strip"
}

build_linux() {
	cd ${srcdir}
	rm -rf linux-${kernelver}*
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${kernelver}.tar.xz
	tar -xf linux-${kernelver}.tar.xz
	cd linux-${kernelver}
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- mrproper -j $NUM_JOBS
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- defconfig -j $NUM_JOBS
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
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- -j $NUM_JOBS
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- INSTALL_HDR_PATH=${pkgdir}/usr headers_install
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- INSTALL_MOD_PATH=${pkgdir} modules_install
	make ARCH=$KARCH CROSS_COMPILE=$XTARGET- INSTALL_FW_PATH=${pkgdir}/lib/firmware firmware_install
}

build_libgcc() {
	cp -a ${tooldir}/$XTARGET/lib${libSuffix}/libgcc_s.so.1 ${pkgdir}/lib/
}

build_musl(){
	cd ${srcdir}
	rm -rf musl*
	wget http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure \
		${default_musl_configure} \
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
	mkdir ${pkgdir}/usr/share/udhcpc
	cp examples/udhcp/simple.script ${pkgdir}/usr/share/udhcpc/default.script
	chmod +x ${pkgdir}/usr/share/udhcpc/default.script
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
		${default_cross_configure} \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_ntpd() {
	cd ${srcdir}
	wget https://fastly.cdn.openbsd.org/pub/OpenBSD/OpenNTPD/openntpd-6.2p3.tar.gz
	tar -xf openntpd-6.2p3.tar.gz
	cd openntpd-6.2p3
	./configure \
		${default_cross_configure} \
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
		${default_cross_configure} \
		${default_configure} \
		--disable-graphics \
		--enable-utf8 \
		--with-ipv6 \
		--with-ssl \
		--without-x \
		--without-zlib
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_htop() {
	cd ${srcdir}
	wget http://hisham.hm/htop/releases/2.0.2/htop-2.0.2.tar.gz
	tar -xf htop-2.0.2.tar.gz
	cd htop-2.0.2
	./configure \
		${default_cross_configure} \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_curses() {
	cd ${srcdir}
	wget http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-0.2.1.tar.xz
	tar -xf netbsd-curses-0.2.1.tar.xz
	cd netbsd-curses-0.2.1
	make -j $NUM_JOBS
	make PREFIX=${pkgdir}/usr install
}

build_e2fsprogs() {
	cd ${srcdir}
	wget http://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v1.43.7/e2fsprogs-1.43.7.tar.gz
	tar -xf e2fsprogs-1.43.7.tar.gz
	cd e2fsprogs-1.43.7
	./configure \
		${default_cross_configure} \
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
		${default_cross_configure} \
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
	./autogen.sh
	./configure \
		${default_cross_configure} \
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
		${default_cross_configure} \
		--prefix=/usr \
		--libdir=/usr/lib \
		--sysconfdir=/etc/ssh \
		--libexecdir=/usr/lib/ssh \
		--with-pid-dir=/run \
		--with-mantype=man \
		--with-privsep-path=/var/empty \
		--with-xauth=/usr/bin/xauth \
		--with-privsep-user=sshd \
		--with-md5-passwords \
		--with-ssl-engine \
		--disable-lastlog \
		--disable-strip \
		--disable-wtmp
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_curl() {
	cd ${srcdir}
	wget https://curl.haxx.se/download/curl-7.56.1.tar.xz
	tar -xf curl-7.56.1.tar.xz
	cd curl-7.56.1
	./configure \
		${default_cross_configure} \
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
		${default_cross_configure} \
		${default_configure} \
		--disable-vlock
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_libz() {
	cd ${srcdir}
	wget https://sortix.org/libz/release/libz-1.2.8.2015.12.26.tar.gz
	tar -xf libz-1.2.8.2015.12.26.tar.gz
	cd libz-1.2.8.2015.12.26
	./configure \
		${default_cross_configure} \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_file() {
	cd ${srcdir}
	wget ftp://ftp.astron.com/pub/file/file-5.32.tar.gz
	tar -xf file-5.32.tar.gz
	cd file-5.32
	./configure \
		${default_cross_configure} \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_sudo() {
	cd ${srcdir}
	wget https://www.sudo.ws/dist/sudo-1.8.21p2.tar.gz
	tar -xf sudo-1.8.21p2.tar.gz
	cd sudo-1.8.21p2
	sed -i "/<config.h>/s@.*@&\n\n#include <sys/types.h>@" \
		src/preserve_fds.c
	./configure \
		${default_cross_configure} \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_libarchive() {
	cd ${srcdir}
	wget http://www.libarchive.org/downloads/libarchive-3.3.2.tar.gz
	tar -xf libarchive-3.3.2.tar.gz
	cd libarchive-3.3.2
	sed -i 's@HAVE_LCHMOD@&_DISABLE@' libarchive/archive_write_disk_posix.c
	sed -i 's@ -qq@@' libarchive/archive_read_support_filter_xz.c
	sed -i 's@xz -d@unxz@' libarchive/archive_read_support_filter_xz.c
	sed -i 's@lzma -d@unlzma@' libarchive/archive_read_support_filter_xz.c
	./configure \
		${default_cross_configure} \
		${default_configure}
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install
}

build_mksh() {
	cd ${srcdir}
	wget https://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R56b.tgz
	tar -xf mksh-R56b.tgz
	cd mksh
	Build.sh -r
	install -D -m 755 mksh $pkgdir/bin/mksh
}

build_less() {
	cd ${srcdir}
	wget http://www.greenwoodsoftware.com/less/less-487.tar.gz
	tar -xf less-487.tar.gz
	cd less-487
	./configure \
		${default_cross_configure} \
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
		${default_cross_configure} \
		${default_configure}
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

just_prepare
prepare_cross
build_toolchain
toolchain_variables
prepare_filesystem
build_linux
build_libgcc
build_musl
build_busybox
build_mksh
build_iana_etc
build_libz
build_file
build_curses
build_readline
build_e2fsprogs
build_util_linux
build_kbd
build_htop
build_nano
build_sudo
build_less
build_libressl
build_openssh
build_ntpd
build_curl
build_links
build_libarchive
strip_filesystem
make_iso

exit 0
