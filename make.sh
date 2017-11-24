#!/bin/bash -e
#

product_name="Janus Linux"
product_version="0.1"
product_id="janus"
product_bug_url="https://github.com/protonesso/janus/issues"
product_url="januslinux.github.io"

NUM_JOBS=$(expr $(nproc) + 1)

srcdir=$(pwd)/work/sources
pkgdir=$(pwd)/work/rootfs
isodir=$(pwd)/work/rootcd
stuffdir=$(pwd)/stuff

xflags="-Os -s -g0 -pipe -fno-asynchronous-unwind-tables -Werror-implicit-function-declaration"
xldflags="-Wl,-static"
default_configure="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --sysconfdir=/etc --sbindir=/sbin --localstatedir=/var"

kernelhost="janus"
kernelver="4.14.2"

just_prepare() {
	rm -rf ${srcdir} ${pkgdir} ${isodir}
	mkdir -p ${srcdir} ${pkgdir} ${isodir} ${stuffdir}
	
	export CFLAGS="$xflags"
	export CXXLAGS="$CFLAGS"
	export LDFLAGS="$xlflags"
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
    
    for f in fstab group host.conf hosts passwd profile resolv.conf securetty shells adduser.conf busybox.conf mdev.conf inittab hostname syslog.conf; do
            install -m644 ${stuffdir}/${f} etc/
    done
    
    for f in shadow ; do
        install -m600 ${stuffdir}/${f} etc/
    done
    
    for f in rc.init rc.shutdown rc.dhcp; do
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

build_linux() {
	cd ${srcdir}
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${kernelver}.tar.xz
	tar -xf linux-${kernelver}.tar.xz
	cd linux-${kernelver}
	make mrproper -j $NUM_JOBS
	make defconfig -j $NUM_JOBS
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
	make -j $NUM_JOBS
	make INSTALL_MOD_PATH=${pkgdir} modules_install -j $NUM_JOBS
	make INSTALL_FW_PATH=${pkgdir}/lib/firmware firmware_install -j $NUM_JOBS
	cp arch/x86/boot/bzImage ${isodir}/bzImage
}

build_musl(){
	cd ${srcdir}
	wget http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure \
		${default_configure} \
		--syslibdir=/lib \
		--enable-shared \
		--enable-static \
		--enable-optimize=size
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_busybox() {
	cd ${srcdir}
	wget http://busybox.net/downloads/busybox-1.27.2.tar.bz2
	tar -xf busybox-1.27.2.tar.bz2
	cd busybox-1.27.2
	make distclean -j $NUM_JOBS
	make defconfig -j $NUM_JOBS
	sed -i "s/.*CONFIG_STATIC.*/CONFIG_STATIC=y/" .config
	make -j $NUM_JOBS
	make CONFIG_PREFIX=${pkgdir} install -j $NUM_JOBS
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
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_nano() {
	cd ${srcdir}
	wget https://www.nano-editor.org/dist/v2.9/nano-2.9.0.tar.xz
	tar -xf nano-2.9.0.tar.xz
	cd nano-2.9.0
	./configure \
		${default_configure} \
		--disable-shared \
		--enable-static
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_ntpd() {
	cd ${srcdir}
	wget https://fastly.cdn.openbsd.org/pub/OpenBSD/OpenNTPD/openntpd-6.2p3.tar.gz
	tar -xf openntpd-6.2p3.tar.gz
	cd openntpd-6.2p3
	./configure \
		${default_configure} \
		--disable-shared \
		--enable-static \
		--with-privsep-user=ntp
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_links() {
	cd ${srcdir}
	wget http://links.twibright.com/download/links-2.14.tar.gz
	tar -xf links-2.14.tar.gz
	cd links-2.14
	./configure \
		${default_configure} \
		--disable-shared \
		--disable-graphics \
		--enable-static \
		--enable-utf8 \
		--with-ipv6 \
		--with-ssl \
		--disable-graphics \
		--without-x \
		--without-zlib
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_htop() {
	cd ${srcdir}
	wget http://hisham.hm/htop/releases/2.0.2/htop-2.0.2.tar.gz
	tar -xf htop-2.0.2.tar.gz
	cd htop-2.0.2
	./configure \
		${default_configure} \
		--disable-shared \
		--enable-static
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_curses() {
	cd ${srcdir}
	wget http://ftp.barfooze.de/pub/sabotage/tarballs/netbsd-curses-0.2.1.tar.xz
	tar -xf netbsd-curses-0.2.1.tar.xz
	cd netbsd-curses-0.2.1
	make PREFIX=${pkgdir}/usr all-static
	make PREFIX=${pkgdir}/usr install-static
}

build_e2fsprogs() {
	cd ${srcdir}
	wget http://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v1.43.7/e2fsprogs-1.43.7.tar.gz
	tar -xf e2fsprogs-1.43.7.tar.gz
	cd e2fsprogs-1.43.7
	./configure \
		${default_configure} \
		--enable-static \
		--enable-elf-shlibs \
		--enable-symlink-install \
		--disable-fsck \
		--disable-uuidd \
		--disable-libuuid \
		--disable-libblkid \
		--disable-tls \
		--disable-nls \
		--disable-shared
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install install-libs -j $NUM_JOBS
}


build_util_linux() {
	cd ${srcdir}
	wget https://www.kernel.org/pub/linux/utils/util-linux/v2.31/util-linux-2.31.tar.xz
	tar -xf util-linux-2.31.tar.xz
	cd util-linux-2.31
	./configure \
		${default_configure} \
		--enable-static \
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
		--without-python \
		--without-systemd \
		--without-systemdsystemunitdi \
		--disable-shared
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_wolfssl() {
	cd ${srcdir}
	wget https://github.com/wolfSSL/wolfssl/archive/v3.12.2-stable.tar.gz
	tar -xf v3.12.2-stable.tar.gz
	cd wolfssl-3.12.2-stable
	./autogen.sh
	./configure \
		${default_configure} \
		--enable-static \
		--enable-all \
		--enable-sslv3 \
		--disable-shared
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_curl() {
	cd ${srcdir}
	wget https://curl.haxx.se/download/curl-7.56.1.tar.xz
	tar -xf curl-7.56.1.tar.xz
	cd curl-7.56.1
	./configure \
		${default_configure} \
		--enable-static \
		--disable-shared
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_kbd() {
	cd ${srcdir}
	wget https://www.kernel.org/pub/linux/utils/kbd/kbd-2.0.4.tar.xz
	tar -xf kbd-2.0.4.tar.xz
	cd kbd-2.0.4
	./configure \
		${default_configure} \
		--enable-static \
		--disable-shared \
		--disable-vlock
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_libz() {
	cd ${srcdir}
	wget https://sortix.org/libz/release/libz-1.2.8.2015.12.26.tar.gz
	tar -xf libz-1.2.8.2015.12.26.tar.gz
	cd libz-1.2.8.2015.12.26
	./configure \
		${default_configure} \
		--enable-static \
		--disable-shared
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_file() {
	cd ${srcdir}
	wget ftp://ftp.astron.com/pub/file/file-5.32.tar.gz
	tar -xf file-5.32.tar.gz
	cd file-5.32
	./configure \
		${default_configure} \
		--enable-static \
		--disable-shared
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_extlinux() {
	cd ${srcdir}
	wget https://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
	tar -xf syslinux-6.03.tar.xz
	cd syslinux-6.03
	sed -i '/#define statfs/d;/#undef statfs/d' libinstaller/linuxioctl.h
	make -C libinstaller
	make -C extlinux OPTFLAGS="$xflags" LDFLAGS="$xldflags"
	make -C linux OPTFLAGS="$xflags" LDFLAGS="$xldflags"
	cp extlinux/extlinux $R/bin
	cp linux/syslinux $R/bin
	mkdir -p $R/lib/syslinux
	cp mbr/*mbr.bin $R/lib/syslinux
}

build_sudo() {
	cd ${srcdir}
	wget https://www.sudo.ws/dist/sudo-1.8.21p2.tar.gz
	tar -xf sudo-1.8.21p2.tar.gz
	cd sudo-1.8.21p2
	sed -i "/<config.h>/s@.*@&\n\n#include <sys/types.h>@" \
		src/preserve_fds.c
	./configure \
		${default_configure} \
		--enable-static \
		--disable-shared
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
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
		${default_configure} \
		--enable-static \
		--disable-shared
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_less() {
	cd ${srcdir}
	wget http://www.greenwoodsoftware.com/less/less-487.tar.gz
	tar -xf less-487.tar.gz
	cd less-487
	./configure \
		${default_configure} \
		--enable-static \
		--disable-shared
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
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
  		-J -r -o ../${product_name}-${product_version}.iso \
  		-b isolinux.bin \
  		-c boot.cat \
  		-input-charset UTF-8 \
  		-no-emul-boot \
  		-boot-load-size 4 \
  		-boot-info-table \
  		${isodir}/
		
	isohybrid -u ../${product_name}-${product_version}.iso
}

just_prepare
prepare_filesystem
build_linux
build_musl
build_busybox
build_iana_etc
build_libz
build_file
build_curses
build_e2fsprogs
build_util_linux
build_kbd
build_htop
build_nano
build_sudo
build_wolfssl
build_ntpd
build_curl
build_links
build_libarchive
build_extlinux
make_iso

exit 0
