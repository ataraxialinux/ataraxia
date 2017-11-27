#!/bin/sh
#

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
		x86_64)
			export XHOST=$(echo ${MACHTYPE} | sed "s/-[^-]*/-cross/")
			export XCPU=nocona
			export XTARGET=x86_64-pc-linux-musl
			export KARCH=x86_64
			export libSuffix=64
			export BUILD="-m64"
			export BARCH="x86"
			export KIMAGE="bzImage"
			;;
		*)
			echo "XARCH isn't set!"
			echo "Please run: XARCH=[supported architecture] sh make.sh"
			echo "Supported architectures: x86_64"
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

	for f in fstab group hosts passwd profile securetty shells mdev.conf inittab hostname syslog.conf sysctl.conf issue; do
		install -m644 ${stuffdir}/${f} etc/
	done

	for f in shadow; do
		install -m640 ${stuffdir}/${f} etc/
	done

	for f in rc.init rc.shutdown rc.local; do
		install -m644 ${stuffdir}/${f} etc/rc.d/
		chmod +x etc/rc.d/${f}
	done

	cat >${pkgdir}/etc/os-release<<EOF
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
		--enable-languages=c,c++
	make -j $NUM_JOBS
	make install

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
		--build=$XHOST \
		--host=$XHOST \
		--target=$XTARGET \
		--with-sysroot=${tooldir} \
		--with-arch=$XCPU \
		--enable-languages=c,c++ \
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
	cp -a arch/$BARCH/boot/$KIMAGE ${pkgdir}/boot/$KIMAGE-${kernelver}
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

build_mksh() {
	cd ${srcdir}
	wget https://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R56b.tgz
	tar -xf mksh-R56b.tgz
	cd mksh
	sh Build.sh -r
	install -D -m 755 mksh $pkgdir/bin/mksh
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
build_mksh
build_linux
strip_filesystem
make_iso
make_rootfs_archive

exit 0
